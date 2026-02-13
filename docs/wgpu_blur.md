# WGPU Blur Backend

cpyvn supports a dedicated `wgpu` blur backend for blur transitions.

## Current status

- Blur is currently buggy.
- WGPU blur is more buggy and less stable than CPU blur.

## Install

```bash
pip install -r requirements-wgpu.txt
```

## Enable in `project.json`

Set `wgpu_blur` to `true`:

```json
{
  "name": "demo",
  "entry": "script.vn",
  "wgpu_blur": true,
  "wgpu_backend": "Vulkan"
}
```

`wgpu_backend` is optional. Useful values:
- `Vulkan`
- `OpenGL`
- `Metal`
- `Dx12`

When enabled:
- cpyvn initializes `WgpuBlurBackend` from `vn/gpu/blur_wgpu.pyx`.
- if `wgpu_backend` is `OpenGL`, cpyvn probes it in a subprocess first to avoid hard crashes on unstable drivers.
- `scene ... blur`, `show ... blur`, and `off ... blur` use the GPU backend when available.
- `blend blur` currently uses the CPU path for stability/consistency across drivers.
- if `wgpu` init fails, runtime falls back to CPU blur (no hard stop).
- if a software adapter (like llvmpipe/swiftshader) is detected, cpyvn disables wgpu blur and uses CPU fallback.
- if `ui.show_perf` is enabled, perf overlay shows:
  - GPU adapter specs
  - blur backend (`WgpuBlurBackend` or CPU)
  - GPU/CPU blur call counters

## Disable

Set `wgpu_blur` to `false` (or remove the key).  
Blur transitions will use the CPU fallback path.

## Note

Blur on flat-color backgrounds can look subtle. For visual verification, test blur between image backgrounds or on character sprites.

If perf overlay shows `GPU Type: CPU` (llvmpipe), keep `wgpu_blur` off on that machine.
You can still force-enable software backend for debugging:

```bash
CPYVN_WGPU_ALLOW_SOFTWARE=1 python main.py --project games/demo
```

If Vulkan is unstable on your host, try:

```json
"wgpu_backend": "OpenGL"
```
