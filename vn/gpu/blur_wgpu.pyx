from __future__ import annotations

import math
import os
import subprocess
import struct
import sys
from dataclasses import dataclass
from typing import Optional

import cython
import pygame


_WGSL_GAUSSIAN_BLUR = """
struct Params {
    width: u32,
    height: u32,
    radius: u32,
    direction: u32, // 0 = horizontal, 1 = vertical
};

@group(0) @binding(0)
var<storage, read> src_pixels: array<u32>;

@group(0) @binding(1)
var<storage, read_write> dst_pixels: array<u32>;

@group(0) @binding(2)
var<uniform> params: Params;

fn unpack_rgba8_premul(px: u32) -> vec4<f32> {
    let r = f32(px & 255u) / 255.0;
    let g = f32((px >> 8u) & 255u) / 255.0;
    let b = f32((px >> 16u) & 255u) / 255.0;
    let a = f32((px >> 24u) & 255u) / 255.0;
    return vec4<f32>(r * a, g * a, b * a, a);
}

fn pack_rgba8_unpremul(v: vec4<f32>) -> u32 {
    let a = clamp(v.a, 0.0, 1.0);
    var rgb = vec3<f32>(0.0, 0.0, 0.0);
    if (a > 0.00001) {
        rgb = clamp(v.rgb / a, vec3<f32>(0.0), vec3<f32>(1.0));
    }
    let r = u32(rgb.r * 255.0 + 0.5);
    let g = u32(rgb.g * 255.0 + 0.5);
    let b = u32(rgb.b * 255.0 + 0.5);
    let aa = u32(a * 255.0 + 0.5);
    return r | (g << 8u) | (b << 16u) | (aa << 24u);
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let idx = gid.x;
    let total = params.width * params.height;
    if (idx >= total) {
        return;
    }

    let x = i32(idx % params.width);
    let y = i32(idx / params.width);
    let radius = i32(params.radius);

    var sum = vec4<f32>(0.0);
    var weight_sum = 0.0;
    let sigma = max(0.8, f32(params.radius) * 0.55);

    for (var k = -radius; k <= radius; k = k + 1) {
        var sx = x;
        var sy = y;
        if (params.direction == 0u) {
            sx = clamp(x + k, 0, i32(params.width) - 1);
        } else {
            sy = clamp(y + k, 0, i32(params.height) - 1);
        }
        let sample_idx = u32(sy) * params.width + u32(sx);
        let dist = f32(abs(k));
        let w = exp(-(dist * dist) / (2.0 * sigma * sigma));
        sum = sum + unpack_rgba8_premul(src_pixels[sample_idx]) * w;
        weight_sum = weight_sum + w;
    }

    let out_color = sum / max(weight_sum, 0.00001);
    dst_pixels[idx] = pack_rgba8_unpremul(out_color);
}
"""


@dataclass
class _WgpuObjects:
    module: object
    pipeline: object
    buffer_usage_storage: int
    buffer_usage_uniform: int
    buffer_usage_copy_src: int
    buffer_usage_copy_dst: int


cpdef bint _is_software_adapter(object info):
    cdef str adapter_type
    cdef str device
    cdef str vendor
    cdef str combined
    cdef tuple hints
    cdef str hint
    if not isinstance(info, dict):
        return False
    adapter_type = str(info.get("adapter_type", "")).strip().lower()
    device = str(info.get("device", "")).strip().lower()
    vendor = str(info.get("vendor", "")).strip().lower()
    combined = " ".join((adapter_type, device, vendor))
    if adapter_type == "cpu":
        return True
    hints = ("llvmpipe", "swiftshader", "software rasterizer", "softpipe")
    for hint in hints:
        if hint in combined:
            return True
    return False


class WgpuBlurBackend:
    def __init__(self, power_preference: str = "high-performance", backend_type: str | None = None) -> None:
        if backend_type and not os.getenv("WGPU_BACKEND_TYPE"):
            os.environ["WGPU_BACKEND_TYPE"] = str(backend_type)

        try:
            import wgpu
        except Exception as exc:  # pragma: no cover - import path depends on host env
            raise RuntimeError("wgpu-py is required for WgpuBlurBackend") from exc

        self._wgpu = wgpu
        adapter = self._pick_best_adapter(power_preference, backend_type)
        if adapter is None:
            raise RuntimeError("Failed to initialize wgpu adapter")

        self._device = adapter.request_device_sync(required_features=[])
        self._adapter_info = getattr(adapter, "info", None)
        allow_software = os.getenv("CPYVN_WGPU_ALLOW_SOFTWARE", "0").strip() == "1"
        if _is_software_adapter(self._adapter_info) and not allow_software:
            raise RuntimeError(
                "WGPU blur disabled: software adapter detected "
                "(set CPYVN_WGPU_ALLOW_SOFTWARE=1 to force-enable)."
            )
        module = self._device.create_shader_module(code=_WGSL_GAUSSIAN_BLUR)
        pipeline = self._device.create_compute_pipeline(
            layout="auto",
            compute={"module": module, "entry_point": "main"},
        )
        self._objects = _WgpuObjects(
            module=module,
            pipeline=pipeline,
            buffer_usage_storage=wgpu.BufferUsage.STORAGE,
            buffer_usage_uniform=wgpu.BufferUsage.UNIFORM,
            buffer_usage_copy_src=wgpu.BufferUsage.COPY_SRC,
            buffer_usage_copy_dst=wgpu.BufferUsage.COPY_DST,
        )

    def _pick_best_adapter(self, power_preference: str, backend_type: str | None):
        wgpu = self._wgpu
        adapter = wgpu.gpu.request_adapter_sync(
            power_preference=power_preference,
            force_fallback_adapter=False,
        )
        if adapter is not None:
            return adapter

        # Last-resort fallback adapter for hosts without a hardware adapter.
        return wgpu.gpu.request_adapter_sync(
            power_preference=power_preference,
            force_fallback_adapter=True,
        )

    def blur(self, surface: pygame.Surface, strength: int) -> pygame.Surface:
        cdef int width
        cdef int height
        cdef int radius
        cdef bytes rgba
        cdef int byte_size
        cdef int passes
        width, height = surface.get_size()
        if width <= 1 or height <= 1:
            return surface.copy()

        # GPU blur looked too mild compared to the CPU fallback in transitions.
        # Scale strength so visual intensity is closer between paths.
        radius = max(1, min(32, int(math.ceil(strength * 1.8))))
        rgba = pygame.image.tostring(surface, "RGBA")
        byte_size = len(rgba)
        if byte_size == 0:
            return surface.copy()

        usage_rw = (
            self._objects.buffer_usage_storage
            | self._objects.buffer_usage_copy_src
            | self._objects.buffer_usage_copy_dst
        )
        src = self._device.create_buffer_with_data(data=rgba, usage=usage_rw)
        tmp = self._device.create_buffer(size=byte_size, usage=usage_rw)

        passes = 2 if radius >= 14 else 1
        for _ in range(passes):
            self._dispatch_blur_pass(src, tmp, width, height, radius, direction=0)
            self._dispatch_blur_pass(tmp, src, width, height, radius, direction=1)

        out = bytes(self._device.queue.read_buffer(src))
        # fromstring keeps alpha and works with the runtime's existing pygame surfaces.
        return pygame.image.fromstring(out, (width, height), "RGBA").convert_alpha()

    def get_specs_lines(self) -> list[str]:
        cdef object info
        cdef str backend
        cdef str adapter_type
        cdef str device
        cdef str vendor
        info = self._adapter_info
        if info is None:
            return ["GPU: wgpu (adapter info unavailable)"]
        backend = str(info.get("backend_type", "?"))
        adapter_type = str(info.get("adapter_type", "?"))
        device = str(info.get("device", "?"))
        vendor = str(info.get("vendor", "?"))
        return [
            f"GPU API: wgpu/{backend}",
            f"GPU Type: {adapter_type}",
            f"GPU Dev: {device}",
            f"GPU Vendor: {vendor}",
        ]

    def _dispatch_blur_pass(
        self,
        src_buffer,
        dst_buffer,
        width: int,
        height: int,
        radius: int,
        direction: int,
    ) -> None:
        cdef bytes params
        cdef int total_pixels
        cdef int workgroups
        params = struct.pack("<4I", width, height, radius, direction)
        params_buffer = self._device.create_buffer_with_data(
            data=params,
            usage=self._objects.buffer_usage_uniform,
        )

        bind_group = self._device.create_bind_group(
            layout=self._objects.pipeline.get_bind_group_layout(0),
            entries=[
                {"binding": 0, "resource": {"buffer": src_buffer}},
                {"binding": 1, "resource": {"buffer": dst_buffer}},
                {"binding": 2, "resource": {"buffer": params_buffer}},
            ],
        )

        total_pixels = width * height
        workgroups = max(1, math.ceil(total_pixels / 64))

        encoder = self._device.create_command_encoder()
        cpass = encoder.begin_compute_pass()
        cpass.set_pipeline(self._objects.pipeline)
        cpass.set_bind_group(0, bind_group, [], 0, 99)
        cpass.dispatch_workgroups(workgroups, 1, 1)
        cpass.end()
        self._device.queue.submit([encoder.finish()])


cpdef object create_wgpu_blur_backend(
    power_preference: str = "high-performance",
    backend_type: str | None = None,
):
    try:
        return WgpuBlurBackend(power_preference=power_preference, backend_type=backend_type)
    except Exception:
        return None


cpdef bint probe_wgpu_backend(str backend_type, double timeout_seconds = 6.0):
    cdef str backend = str(backend_type or "").strip()
    cdef dict env
    cdef str code
    if not backend:
        return True
    env = os.environ.copy()
    env["WGPU_BACKEND_TYPE"] = backend
    code = (
        "import os\n"
        "import pygame\n"
        "pygame.init()\n"
        "pygame.display.set_mode((1, 1))\n"
        "from vn.gpu.blur_wgpu import create_wgpu_blur_backend\n"
        "b = create_wgpu_blur_backend(backend_type=os.environ.get('WGPU_BACKEND_TYPE'))\n"
        "if b is None:\n"
        "    raise SystemExit(2)\n"
        "s = pygame.Surface((48, 48), pygame.SRCALPHA)\n"
        "for y in range(48):\n"
        "    for x in range(48):\n"
        "        c = (x * 13 + y * 7) % 255\n"
        "        s.set_at((x, y), (c, 255 - c, (x * y) % 255, 255))\n"
        "b.blur(s, 6)\n"
    )
    try:
        result = subprocess.run(
            [sys.executable, "-c", code],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout_seconds,
            check=False,
        )
    except Exception:
        return False
    return result.returncode == 0
