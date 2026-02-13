from __future__ import annotations

from pathlib import Path
from typing import Dict, Optional, Protocol, Tuple

import cython
import pygame


class _BlurBackend(Protocol):
    def blur(self, surface: pygame.Surface, strength: int) -> pygame.Surface:
        ...


class AssetManager:
    def __init__(self, project_root: Path, asset_dirs: Dict[str, Path], screen_size: Tuple[int, int]):
        self.project_root = project_root
        self.asset_dirs = asset_dirs
        self.screen_size = screen_size
        self._image_cache: Dict[Path, pygame.Surface] = {}
        self._sound_cache: Dict[Path, pygame.mixer.Sound] = {}
        self._music_path: Optional[Path] = None
        self._echo_channel = pygame.mixer.Channel(0)
        self._voice_channel = pygame.mixer.Channel(1)
        self._echo_path: Optional[Path] = None
        self._voice_path: Optional[Path] = None
        self._pinned_images: set[Path] = set()
        self._pinned_sounds: set[Path] = set()
        self._blur_backend: _BlurBackend | None = None
        self.require_wgpu_blur: bool = False
        self._gpu_specs_lines: list[str] = []
        self._blur_backend_name: str = "cpu"
        self._gpu_blur_calls: int = 0

    def resolve_path(self, path: str, kind: str) -> Path:
        cdef object p
        cdef object base
        p = Path(path)
        if p.is_absolute():
            return p
        if path.startswith("./") or path.startswith("../"):
            return (self.project_root / p).resolve()
        base = self.asset_dirs.get(kind, self.project_root)
        return (base / p).resolve()

    def load_image(self, path: str, kind: str) -> pygame.Surface:
        cdef object resolved
        cdef object surface
        resolved = self.resolve_path(path, kind)
        if resolved in self._image_cache:
            return self._image_cache[resolved]
        if not resolved.exists():
            surface = self._placeholder_surface(f"Missing: {path}")
            self._image_cache[resolved] = surface
            return surface
        surface = pygame.image.load(resolved).convert_alpha()
        self._image_cache[resolved] = surface
        return surface

    def make_color_surface(self, color: str, size: Optional[Tuple[int, int]] = None) -> pygame.Surface:
        rgb = parse_color(color)
        if size is None:
            size = self.screen_size
        surface = pygame.Surface(size)
        surface.fill(rgb)
        return surface

    def make_rect_surface(self, color: str, size: Tuple[int, int]) -> pygame.Surface:
        rgb = parse_color(color)
        surface = pygame.Surface(size, pygame.SRCALPHA)
        surface.fill(rgb)
        return surface

    def play_music(self, path: str, loop: bool = True) -> None:
        resolved = self.resolve_path(path, "audio")
        if not resolved.exists():
            return
        if self._music_path == resolved:
            return
        try:
            pygame.mixer.music.load(resolved)
            pygame.mixer.music.play(-1 if loop else 0)
            self._music_path = resolved
        except pygame.error:
            return

    def play_sound(self, path: str) -> None:
        cdef object resolved
        cdef object sound
        resolved = self.resolve_path(path, "audio")
        if not resolved.exists():
            return
        if resolved in self._sound_cache:
            self._sound_cache[resolved].play()
            return
        try:
            sound = pygame.mixer.Sound(resolved)
            self._sound_cache[resolved] = sound
            sound.play()
        except pygame.error:
            return

    def preload_image(self, path: str, kind: str) -> None:
        self.load_image(path, kind)

    def preload_sound(self, path: str) -> None:
        cdef object resolved
        resolved = self.resolve_path(path, "audio")
        if not resolved.exists():
            return
        if resolved in self._sound_cache:
            return
        try:
            self._sound_cache[resolved] = pygame.mixer.Sound(resolved)
        except pygame.error:
            return

    def pin_image(self, path: str, kind: str) -> None:
        resolved = self.resolve_path(path, kind)
        self._pinned_images.add(resolved)
        self.load_image(path, kind)

    def unpin_image(self, path: str, kind: str) -> None:
        resolved = self.resolve_path(path, kind)
        self._pinned_images.discard(resolved)

    def pin_sound(self, path: str) -> None:
        resolved = self.resolve_path(path, "audio")
        self._pinned_sounds.add(resolved)
        self.preload_sound(path)

    def unpin_sound(self, path: str) -> None:
        resolved = self.resolve_path(path, "audio")
        self._pinned_sounds.discard(resolved)

    def clear_images(self) -> None:
        cdef object key
        for key in list(self._image_cache.keys()):
            if key not in self._pinned_images:
                del self._image_cache[key]

    def prune_images(self, keep: set[Path]) -> None:
        cdef object key
        if not keep:
            keep = set()
        keep = set(keep)
        keep.update(self._pinned_images)
        for key in list(self._image_cache.keys()):
            if key not in keep:
                del self._image_cache[key]

    def clear_sounds(self) -> None:
        cdef object key
        for key in list(self._sound_cache.keys()):
            if key not in self._pinned_sounds:
                del self._sound_cache[key]

    def clear_all(self) -> None:
        self.clear_images()
        self.clear_sounds()

    def play_echo(self, path: str) -> None:
        resolved = self.resolve_path(path, "audio")
        if not resolved.exists():
            return
        if resolved not in self._sound_cache:
            try:
                self._sound_cache[resolved] = pygame.mixer.Sound(resolved)
            except pygame.error:
                return
        sound = self._sound_cache[resolved]
        self._echo_channel.play(sound, loops=-1)
        self._echo_path = resolved

    def stop_echo(self) -> None:
        self._echo_channel.stop()
        self._echo_path = None

    def play_voice(self, path: str) -> None:
        resolved = self.resolve_path(path, "audio")
        if not resolved.exists():
            return
        if resolved not in self._sound_cache:
            try:
                self._sound_cache[resolved] = pygame.mixer.Sound(resolved)
            except pygame.error:
                return
        sound = self._sound_cache[resolved]
        self._voice_channel.stop()
        self._voice_channel.play(sound)
        self._voice_path = resolved

    def is_voice_playing(self) -> bool:
        return self._voice_channel.get_busy()

    def set_blur_backend(self, backend: _BlurBackend | None) -> None:
        cdef object getter
        cdef object lines
        cdef object line
        self._blur_backend = backend
        if backend is None:
            self._gpu_specs_lines = []
            self._blur_backend_name = "cpu"
            self._gpu_blur_calls = 0
            return
        self._blur_backend_name = backend.__class__.__name__
        self._gpu_blur_calls = 0
        getter = getattr(backend, "get_specs_lines", None)
        if callable(getter):
            try:
                lines = getter()
            except Exception:
                lines = []
            self._gpu_specs_lines = []
            for line in lines:
                if str(line).strip():
                    self._gpu_specs_lines.append(str(line))
        else:
            self._gpu_specs_lines = []

    def disable_blur_backend(self, reason: str) -> None:
        self._blur_backend = None
        self.require_wgpu_blur = False
        self._blur_backend_name = "cpu-fallback"
        self._gpu_blur_calls = 0
        details = reason.strip() if reason.strip() else "unknown error"
        self._gpu_specs_lines = [f"WGPU blur disabled: {details}"]

    def blur_wgpu(self, surface: pygame.Surface, strength: int) -> pygame.Surface | None:
        cdef object out
        if self._blur_backend is None:
            return None
        try:
            out = self._blur_backend.blur(surface, strength)
        except Exception as exc:
            self.disable_blur_backend(type(exc).__name__)
            return None
        self._gpu_blur_calls += 1
        return out

    def get_gpu_specs_lines(self) -> list[str]:
        cdef list lines = []
        if self._gpu_specs_lines:
            lines.extend(self._gpu_specs_lines)
        else:
            lines.append("GPU: CPU/none")
        lines.append(f"Blur: {self._blur_backend_name}")
        if self._gpu_blur_calls > 0:
            lines.append(f"Blur Calls: {self._gpu_blur_calls}")
        return lines

    def mute(self, target: str = "all") -> None:
        cdef int idx
        if target == "music":
            pygame.mixer.music.stop()
            self._music_path = None
            return
        if target == "echo":
            self.stop_echo()
            return
        if target == "voice":
            self._voice_channel.stop()
            self._voice_path = None
            return
        if target == "sfx":
            for idx in range(pygame.mixer.get_num_channels()):
                if idx < 2:
                    continue
                pygame.mixer.Channel(idx).stop()
            return
        pygame.mixer.music.stop()
        pygame.mixer.stop()
        self._music_path = None
        self._echo_path = None
        self._voice_path = None

    def cached_image_paths(self) -> set[Path]:
        return set(self._image_cache.keys())

    def cached_sound_paths(self) -> set[Path]:
        return set(self._sound_cache.keys())

    def active_sound_paths(self) -> set[Path]:
        cdef set active = set()
        if self._echo_path is not None:
            try:
                if self._echo_channel.get_busy():
                    active.add(self._echo_path)
                else:
                    self._echo_path = None
            except pygame.error:
                self._echo_path = None
        if self._voice_path is not None:
            try:
                if self._voice_channel.get_busy():
                    active.add(self._voice_path)
                else:
                    self._voice_path = None
            except pygame.error:
                self._voice_path = None
        return active

    def prune_sounds(self, keep: set[Path]) -> None:
        cdef object key
        if not keep:
            keep = set()
        keep = set(keep)
        keep.update(self._pinned_sounds)
        keep.update(self.active_sound_paths())
        for key in list(self._sound_cache.keys()):
            if key not in keep:
                del self._sound_cache[key]

    def _placeholder_surface(self, label: str) -> pygame.Surface:
        surface = pygame.Surface(self.screen_size)
        surface.fill((40, 40, 40))
        pygame.draw.line(surface, (220, 80, 80), (0, 0), self.screen_size, 4)
        pygame.draw.line(surface, (220, 80, 80), (0, self.screen_size[1]), (self.screen_size[0], 0), 4)
        try:
            font = pygame.font.Font(None, 28)
            text = font.render(label, True, (240, 240, 240))
            rect = text.get_rect(center=(self.screen_size[0] // 2, self.screen_size[1] // 2))
            surface.blit(text, rect)
        except pygame.error:
            pass
        return surface


cpdef tuple parse_color(str value):
    cdef str hex_value
    cdef list parts
    cdef int r
    cdef int g
    cdef int b
    value = value.strip()
    if value.startswith("#"):
        hex_value = value[1:]
        if len(hex_value) == 3:
            try:
                r = int(hex_value[0] * 2, 16)
                g = int(hex_value[1] * 2, 16)
                b = int(hex_value[2] * 2, 16)
            except ValueError:
                return 120, 120, 120
            return r, g, b
        if len(hex_value) == 6:
            try:
                r = int(hex_value[0:2], 16)
                g = int(hex_value[2:4], 16)
                b = int(hex_value[4:6], 16)
            except ValueError:
                return 120, 120, 120
            return r, g, b

    if "," in value:
        parts = [p.strip() for p in value.split(",")]
        if len(parts) >= 3:
            try:
                return int(parts[0]), int(parts[1]), int(parts[2])
            except ValueError:
                pass

    return 120, 120, 120
