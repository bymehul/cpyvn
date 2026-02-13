from __future__ import annotations

import gc
import logging
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cython
import pygame

from ..assets import AssetManager, parse_color
from ..config import UiConfig
from ..parser import ScriptParseError, parse_script
from ..script import (
    AddVar,
    Animate,
    Blend,
    CacheClear,
    CachePin,
    CacheUnpin,
    CameraSet,
    CharacterDef,
    Choice,
    Command,
    Echo,
    GarbageCollect,
    Hide,
    HotspotAdd,
    HotspotDebug,
    HotspotPoly,
    HotspotRemove,
    HudAdd,
    HudRemove,
    IfJump,
    Input,
    Jump,
    Label,
    Loading,
    Load,
    Music,
    Mute,
    Notify,
    Call,
    Item,
    Map,
    Meter,
    Phone,
    Preload,
    Say,
    Save,
    Scene,
    SetVar,
    Show,
    ShowChar,
    Sound,
    Video,
    Voice,
    Wait,
    WaitVideo,
    WaitVoice,
)
from ..ui import TextBox
from ..text import count_visible_chars, slice_visible_text
from .inspector import InspectorMixin
from .pause_menu import PauseMenuMixin
from .render import RenderMixin
from .save import SaveMixin
from .scene_manifest import SceneManifest, build_scene_manifest
from .state import BackgroundState, HotspotArea, HudButton, SpriteAnimation, SpriteInstance, SpriteState
from .title_menu import TitleMenuMixin
from .video import VideoBackendUnavailable
from .video_factory import create_video_playback, normalize_video_backend

logger = logging.getLogger("cpyvn.runtime")

SUPPORTED_BLEND_STYLES = {
    "fade",
    "wipe",
    "slide",
    "dissolve",
    "zoom",
    "blur",
    "flash",
    "shake",
    "none",
}

_VAR_INTERPOLATION_RE = re.compile(r"\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}")


@cython.cfunc
@cython.inline
cdef double _clamp_zoom_value(double zoom):
    if zoom < 0.1:
        return 0.1
    if zoom > 8.0:
        return 8.0
    return zoom


@cython.cfunc
@cython.inline
cdef bint _point_in_polygon_xy(double x, double y, list polygon):
    cdef Py_ssize_t n = len(polygon)
    cdef Py_ssize_t i
    cdef bint inside = False
    cdef tuple p1
    cdef tuple p2
    cdef double p1x
    cdef double p1y
    cdef double p2x
    cdef double p2y
    cdef double xinters
    if n < 3:
        return False
    p1 = polygon[0]
    p1x = float(p1[0])
    p1y = float(p1[1])
    for i in range(1, n + 1):
        p2 = polygon[i % n]
        p2x = float(p2[0])
        p2y = float(p2[1])
        if min(p1y, p2y) < y <= max(p1y, p2y):
            if x <= max(p1x, p2x):
                if p1y != p2y:
                    xinters = (y - p1y) * (p2x - p1x) / ((p2y - p1y) + 1e-12) + p1x
                else:
                    xinters = p1x
                if p1x == p2x or x <= xinters:
                    inside = not inside
        p1x = p2x
        p1y = p2y
    return inside


@cython.cfunc
@cython.inline
cdef bint _point_in_circle_xy(double x, double y, double cx, double cy, double radius):
    cdef double dx = x - cx
    cdef double dy = y - cy
    return (dx * dx + dy * dy) <= (radius * radius)


@cython.cfunc
@cython.inline
cdef double _ease_progress(double t, str ease):
    cdef double inv
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    if ease == "in":
        return t * t
    if ease == "out":
        inv = 1.0 - t
        return 1.0 - (inv * inv)
    if ease == "inout":
        if t < 0.5:
            return 2.0 * t * t
        inv = -2.0 * t + 2.0
        return 1.0 - ((inv * inv) / 2.0)
    return t


class VNRuntime(InspectorMixin, PauseMenuMixin, TitleMenuMixin, RenderMixin, SaveMixin):
    def __init__(
        self,
        commands: List[Command],
        labels: Dict[str, int],
        screen: pygame.Surface,
        assets: AssetManager,
        save_path: Path,
        script_path: Path,
        fps: int = 60,
        ui: UiConfig | None = None,
        video_backend: str = "auto",
        video_audio: bool = True,
        video_framedrop: str = "auto",
        feature_script_paths: Dict[str, Path] | None = None,
        feature_flags: Dict[str, bool] | None = None,
    ) -> None:
        self.commands = commands
        self.labels = labels
        self.screen = screen
        self.assets = assets
        self.save_path = save_path
        self.fps = fps
        self.entry_script_path = script_path.resolve()
        self.current_script_path = self.entry_script_path
        self.feature_script_paths: Dict[str, Path] = {}
        if feature_script_paths:
            for _k, _v in feature_script_paths.items():
                self.feature_script_paths[str(_k)] = Path(_v).resolve()
        self.feature_flags: Dict[str, bool] = {"hud": True, "items": True, "maps": True}
        if feature_flags:
            for _k, _v in feature_flags.items():
                self.feature_flags[str(_k)] = bool(_v)

        ui = ui or UiConfig()
        self.text_speed = ui.text_speed
        self.show_perf = ui.show_perf
        self.call_auto_loading = bool(ui.call_auto_loading)
        self.call_loading_text = str(ui.call_loading_text or "Loading scene...")
        self.call_loading_threshold_ms = max(0, int(ui.call_loading_threshold_ms))
        self.call_loading_min_show_ms = max(0, int(ui.call_loading_min_show_ms))
        self._call_elapsed_ms: Dict[Path, int] = {}
        self.textbox = TextBox(
            screen.get_width(),
            screen.get_height(),
            font_size=ui.font_size,
            name_font_size=ui.name_font_size,
            choice_font_size=ui.choice_font_size,
            notify_font_size=ui.notify_font_size,
            box_opacity=ui.box_opacity,
        )
        self.perf_font = pygame.font.Font(None, 20)
        self._perf_surface: Optional[pygame.Surface] = None
        self._perf_next_update_ms: int = 0
        self._fps: float = 0.0
        self._frame_ms: int = 0

        self.index = 0
        self.running = True

        self.background_state = BackgroundState("color", "#000000")
        self.background_surface = self.assets.make_color_surface("#000000")

        self.sprites: Dict[str, SpriteInstance] = {}
        self.sprite_animations: Dict[str, Dict[str, SpriteAnimation]] = {}
        self.video_player: object | None = None
        self.video_surface: pygame.Surface | None = None
        self.video_path: str | None = None
        self.video_fit: str = "contain"
        self.video_loop: bool = False
        self.video_stats: Dict[str, object] = {}
        self.video_backend: str = normalize_video_backend(video_backend, default="auto")
        self.video_backend_active: str = "none"
        self.video_audio_enabled: bool = bool(video_audio)
        framdrop_value = str(video_framedrop).strip().lower()
        if framdrop_value not in {"auto", "on", "off"}:
            framdrop_value = "auto"
        self.video_framedrop: str = framdrop_value
        self.video_framedrop_effective: str = "on" if framdrop_value in {"auto", "on"} else "off"
        self.video_framedrop_auto_enabled: bool = framdrop_value == "auto"
        self.video_framedrop_auto_hold: int = 0
        self.video_audio_channel: pygame.mixer.Channel | None = None
        self.video_audio_pending: List[pygame.mixer.Sound] = []
        self.video_audio_pcm_buffer = bytearray()
        self.video_audio_format: Tuple[int, int, int] | None = None
        self.video_audio_chunk_ms: int = 80
        self.video_audio_warned_format: bool = False
        self.video_audio_backend_active: bool = False
        try:
            if pygame.mixer.get_init():
                self.video_audio_channel = pygame.mixer.Channel(2)
        except pygame.error:
            self.video_audio_channel = None
        self.music_state: Optional[Tuple[str, bool]] = None

        self.current_say: Optional[Tuple[Optional[str], str]] = None
        self.say_start_ms: Optional[int] = None
        self.say_reveal_all = False
        self.current_choice: Optional[Choice] = None
        self.choice_selected = 0
        self.choice_hitboxes: List[pygame.Rect] = []
        self.choice_timer_start_ms: Optional[int] = None
        self.choice_timeout_ms: Optional[int] = None
        self.choice_timeout_default: Optional[int] = None

        self.input_active: bool = False
        self.input_variable: Optional[str] = None
        self.input_prompt: Optional[str] = None
        self.input_buffer: str = ""
        self.input_cursor: int = 0

        self.phone_active: bool = False
        self.phone_contact: Optional[str] = None
        self.phone_messages: List[Tuple[str, str]] = []  # (side, text)

        self.meters: Dict[str, dict] = {}  # name -> {label, min, max, value, color}

        self.hotspots: Dict[str, HotspotArea] = {}
        self.hotspot_debug: bool = False
        self.hotspot_hovered: Optional[str] = None
        self.camera_pan_x: float = 0.0
        self.camera_pan_y: float = 0.0
        self.camera_zoom: float = 1.0
        self.variables: Dict[str, object] = {}
        self.characters: Dict[str, CharacterDef] = {}
        self.show_inspector: bool = False
        self.inspector_selected: Optional[str] = None
        self.inspector_dragging: bool = False
        self.inspector_drag_offset: Tuple[int, int] = (0, 0)
        self.inspector_resizing: bool = False
        self.inspector_resize_handle: Optional[str] = None
        self.inspector_resize_start_rect: Optional[pygame.Rect] = None
        self.inspector_resize_start_mouse: Tuple[int, int] = (0, 0)
        self.inspector_asset_mode: bool = False
        self.inspector_asset_entries: List[str] = []
        self.inspector_asset_selected: int = 0
        self.inspector_asset_scroll: int = 0
        self.inspector_asset_buttons: Dict[str, pygame.Rect] = {}
        self.inspector_font = pygame.font.Font(None, 18)
        self.inspector_path = self.save_path.parent / "inspector.json"
        self.show_hotspot_editor: bool = False
        self.hotspot_editor_mode: str = "select"  # select | rect | poly
        self.hotspot_editor_selected: Optional[str] = None
        self.hotspot_editor_drag_start: Optional[Tuple[int, int]] = None
        self.hotspot_editor_preview_points: List[Tuple[int, int]] = []
        self.hotspot_editor_poly_points: List[Tuple[int, int]] = []
        self.hotspot_editor_buttons: Dict[str, pygame.Rect] = {}
        self.hotspot_editor_default_target: str = "TODO_LABEL"
        self.hud_buttons: Dict[str, HudButton] = {}
        self.hud_hovered: Optional[str] = None
        self.show_hud_editor: bool = False
        self.hud_editor_mode: str = "select"
        self.hud_editor_selected: Optional[str] = None
        self.hud_editor_drag_start: Optional[Tuple[int, int]] = None
        self.hud_editor_preview_rect: Optional[Tuple[int, int, int, int]] = None
        self.hud_editor_buttons: Dict[str, pygame.Rect] = {}
        
        self.show_debug_menu: bool = False
        
        self.inventory: Dict[str, dict] = {} # id -> {name, desc, icon, count}
        self.inventory_active: bool = False
        self.inventory_hovered: Optional[str] = None
        self.inventory_slots: List[pygame.Rect] = []
        self.inventory_page: int = 0
        self.inventory_items_per_page: int = 15
        self.inventory_panel_rect: Optional[pygame.Rect] = None
        
        self.map_active: bool = False
        self.map_image: Optional[str] = None
        self.map_points: List[dict] = [] # {label, x, y, target, points}
        self.map_hovered: Optional[int] = None # index in self.map_points
        self.map_poi_editor_poly_active: bool = False
        self.map_poi_editor_poly_points: List[Tuple[int, int]] = []
        self.hud_editor_dragging: bool = False
        self.hud_editor_drag_offset: Tuple[int, int] = (0, 0)
        self.hud_editor_default_target: str = "TODO_LABEL"
        self.hud_editor_default_text: str = "Button"
        self.bg_transition_start: Optional[pygame.Surface] = None
        self.bg_transition_end: Optional[pygame.Surface] = None
        self.bg_transition_start_ms: Optional[int] = None
        self.bg_transition_duration_ms: int = 0
        self.bg_transition_style: Optional[str] = None
        self.bg_transition_dissolve_tiles: List[Tuple[int, int, int, int, float]] = []
        self.wait_until_ms: Optional[int] = None
        self.wait_for_voice: bool = False
        self.wait_for_video: bool = False
        self.notify_message: Optional[str] = None
        self.notify_until_ms: Optional[int] = None
        self.blend_style: Optional[str] = None
        self.blend_start_ms: Optional[int] = None
        self.blend_duration_ms: int = 0
        self.blend_snapshot: Optional[pygame.Surface] = None
        self.blend_dissolve_tiles: List[Tuple[int, int, int, int, float]] = []
        self._warned_wgpu_blur: bool = False
        self._blur_cpu_calls: int = 0
        self._blur_last_path: str = "none"
        self.loading_active: bool = False
        self.loading_text: str = "Loading..."
        self.loading_auto_continue: bool = False
        self._script_cache: Dict[Path, Tuple[List[Command], Dict[str, int], SceneManifest]] = {}
        self.current_scene_manifest: SceneManifest = build_scene_manifest(commands)
        self._script_cache[self.current_script_path] = (commands, labels, self.current_scene_manifest)
        self._project_root: Path = self.assets.project_root
        self.show_script_editor: bool = False
        self.script_editor_font = pygame.font.SysFont("DejaVu Sans Mono", 18)
        self.script_editor_path: Path = self.current_script_path
        self.script_editor_loaded_path: Path | None = None
        self.script_editor_lines: List[str] = []
        self.script_editor_cursor_line: int = 0
        self.script_editor_cursor_col: int = 0
        self.script_editor_scroll: int = 0
        self.script_editor_dirty: bool = False
        self.script_editor_status: str = "Ready"
        self.script_editor_follow_runtime: bool = True
        self.script_editor_files: List[Path] = []
        self.script_editor_file_index: int = 0
        self.script_editor_file_scroll: int = 0
        self._pause_menu_init(ui)
        self._title_menu_init(ui)

    def run(self) -> None:
        clock = pygame.time.Clock()
        if not self.title_menu_active:
            self._step()
            self.title_menu_started_game = True

        while self.running:
            self._update_timers()
            self._handle_events()
            self._render()
            pygame.display.flip()
            clock.tick(self.fps)
            self._fps = clock.get_fps()
            self._frame_ms = clock.get_time()
            if self.loading_auto_continue:
                self.loading_auto_continue = False
                self._step()

    def _handle_events(self) -> None:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.running = False
                return

            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_F6:
                    self._toggle_script_editor()
                    return
                if event.key == pygame.K_m and (
                    (getattr(event, "mod", 0) & pygame.KMOD_CTRL)
                    or (pygame.key.get_mods() & pygame.KMOD_CTRL)
                ):
                    self._toggle_debug_menu()
                    return
                if self.map_active and self.map_poi_editor_poly_active:
                    if event.key in {pygame.K_RETURN, pygame.K_KP_ENTER}:
                        self._handle_debug_menu_rightclick(event)
                        return
                if self.show_script_editor:
                    self._handle_script_editor_keydown(event)
                    return
                if self.title_menu_active:
                    self._title_menu_keydown(event)
                    return
                if self.pause_menu_active:
                    self._pause_menu_keydown(event)
                    return
                if event.key == pygame.K_F4:
                    self._toggle_hotspot_editor()
                    return
                if event.key == pygame.K_F7:
                    self._toggle_hud_editor()
                    return
                if event.key == pygame.K_ESCAPE:
                    if self.show_hud_editor and self._cancel_hud_editor_action():
                        return
                    if self.show_hotspot_editor and self._cancel_hotspot_editor_action():
                        return
                    self._toggle_pause_menu()
                    return
                if event.key == pygame.K_F3:
                    self.show_inspector = not self.show_inspector
                    if self.show_inspector and self.show_hotspot_editor:
                        self._toggle_hotspot_editor()
                    if not self.show_inspector:
                        self.inspector_selected = None
                        self.inspector_dragging = False
                        self.inspector_resizing = False
                        self.inspector_resize_handle = None
                        self.inspector_resize_start_rect = None
                        self.inspector_asset_mode = False
                    return
                if event.key == pygame.K_F5:
                    self.save_quick()
                    return
                if event.key == pygame.K_F9:
                    self.load_quick()
                    return
                if self.show_hud_editor:
                    self._handle_hud_editor_keydown(event)
                    return
                if self.show_hotspot_editor:
                    self._handle_hotspot_editor_keydown(event)
                    return
                if self.show_inspector and self._handle_inspector_keydown(event):
                    return
                if event.key == pygame.K_i:
                    if self._is_feature_enabled("items"):
                        self.inventory_active = not self.inventory_active
                        if not self.inventory_active:
                            self.inventory_hovered = None
                    else:
                        self.inventory_active = False
                        self.inventory_hovered = None
                    return

                if self.inventory_active:
                    if event.key == pygame.K_ESCAPE:
                        self.inventory_active = False
                        self.inventory_hovered = None
                        return
                    if event.key in (pygame.K_PAGEUP, pygame.K_UP, pygame.K_LEFT):
                        self._scroll_inventory_page(-1)
                        return
                    if event.key in (pygame.K_PAGEDOWN, pygame.K_DOWN, pygame.K_RIGHT):
                        self._scroll_inventory_page(1)
                        return
                    return

                if self.map_active:
                    return

                if self.loading_active:
                    return
                if self._is_waiting():
                    return
                if self.input_active:
                    self._handle_input_keydown(event)
                    return

                if self.current_choice is not None:
                    if event.key in (pygame.K_UP, pygame.K_w):
                        self.choice_selected = (self.choice_selected - 1) % len(self.current_choice.options)
                    elif event.key in (pygame.K_DOWN, pygame.K_s):
                        self.choice_selected = (self.choice_selected + 1) % len(self.current_choice.options)
                    elif event.key in (pygame.K_RETURN, pygame.K_SPACE):
                        self._select_choice()
                    return

                if event.key in (pygame.K_RETURN, pygame.K_SPACE):
                    self._advance()
                    return

            if event.type == pygame.MOUSEBUTTONDOWN:
                if self.title_menu_active:
                    self._title_menu_mousedown(event)
                    return
                if self.pause_menu_active:
                    self._pause_menu_mousedown(event)
                    return
                if self.show_script_editor:
                    self._handle_script_editor_mousedown(event)
                    return
                if self.show_hud_editor:
                    self._handle_hud_editor_mousedown(event)
                    return
                if self.show_debug_menu:
                    self._handle_debug_menu_mousedown(event)
                    return
                if self.inventory_active:
                    self._handle_inventory_mousedown(event)
                    return
                if self.map_active:
                    self._handle_map_mousedown(event)
                    return
                if self.show_hotspot_editor:
                    self._handle_hotspot_editor_mousedown(event)
                    return
                if self.show_inspector and self._handle_inspector_mousedown(event):
                    return
            if event.type == pygame.MOUSEBUTTONDOWN and event.button == 3:
                if self.title_menu_active:
                    return
                if self.pause_menu_active:
                    return
                if self.show_debug_menu:
                    self._handle_debug_menu_rightclick(event)
                    return
                if self.show_hotspot_editor:
                    self._handle_hotspot_editor_rightclick(event)
                    return
            if event.type == pygame.MOUSEWHEEL:
                if self.title_menu_active:
                    return
                if self.pause_menu_active:
                    return
                if self.inventory_active:
                    self._scroll_inventory_page(-event.y)
                    return
                if self.show_script_editor:
                    self._handle_script_editor_mousewheel(event.y, pygame.mouse.get_pos())
                    return
                if self.show_inspector and self._handle_inspector_mousewheel(event.y):
                    return
            if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                if self.title_menu_active:
                    return
                if self.pause_menu_active:
                    return
                if self.loading_active:
                    return
                if self._is_waiting():
                    return
                if self.current_choice is not None:
                    if self._handle_choice_click(event.pos):
                        return
                else:
                    if self._handle_hud_click(event.pos):
                        return
                    if self.current_say is None and self._handle_hotspot_click(event.pos):
                        return
                    self._advance()
            if event.type == pygame.MOUSEMOTION:
                if self.title_menu_active:
                    self._title_menu_mousemotion(event)
                    return
                if self.pause_menu_active:
                    self._pause_menu_mousemotion(event)
                    return
                if self.show_script_editor:
                    self._handle_script_editor_mousemotion(event)
                    return
                if self.show_hud_editor:
                    self._handle_hud_editor_mousemotion(event)
                    return
                if self.inventory_active:
                    self._handle_inventory_mousemotion(event)
                    return
                if self.map_active:
                    self._handle_map_mousemotion(event)
                    return
                if self.show_hotspot_editor:
                    self._handle_hotspot_editor_mousemotion(event)
                    return
                if self.show_inspector and self._handle_inspector_mousemotion(event):
                    return
                if self.current_choice is not None:
                    self._handle_choice_hover(event.pos)
                elif self.current_say is None and not self.loading_active and not self._is_waiting():
                    self._handle_hud_hover(event.pos)
                    self._handle_hotspot_hover(event.pos)
                else:
                    self.hotspot_hovered = None
                    self.hud_hovered = None
            if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
                if self.show_hud_editor:
                    self._handle_hud_editor_mouseup(event)
                    return
                if self.show_hotspot_editor:
                    self._handle_hotspot_editor_mouseup(event)
                    return
                if self.show_inspector and self._handle_inspector_mouseup(event):
                    return

    def _advance(self) -> None:
        if self.current_choice is not None:
            return
        if self.input_active:
            return
        if self._is_waiting():
            self._check_wait()
        if self.current_say is not None and not self._is_current_say_revealed():
            self.say_reveal_all = True
            return
        self.current_say = None
        self.say_start_ms = None
        self.say_reveal_all = False
        self._step()

    def _select_choice(self) -> None:
        if not self.current_choice:
            return
        _, target = self.current_choice.options[self.choice_selected]
        self.current_choice = None
        self.choice_selected = 0
        self.choice_timer_start_ms = None
        self.choice_timeout_ms = None
        self.choice_timeout_default = None
        self._jump(target)
        self._step()

    def _handle_input_keydown(self, event) -> None:
        if event.key == pygame.K_RETURN:
            if self.input_variable:
                self.variables[self.input_variable] = self.input_buffer
            self.input_active = False
            self.input_variable = None
            self.input_prompt = None
            self.input_buffer = ""
            self.input_cursor = 0
            self._step()
        elif event.key == pygame.K_BACKSPACE:
            if self.input_buffer:
                self.input_buffer = self.input_buffer[:-1]
                self.input_cursor = len(self.input_buffer)
        elif event.unicode and ord(event.unicode) >= 32:
            self.input_buffer += event.unicode
            self.input_cursor = len(self.input_buffer)

    def _handle_choice_click(self, pos: Tuple[int, int]) -> bool:
        if not self.current_choice:
            return False
        for idx, rect in enumerate(self.choice_hitboxes):
            if rect.collidepoint(pos):
                self.choice_selected = idx
                self._select_choice()
                return True
        return False

    def _handle_choice_hover(self, pos: Tuple[int, int]) -> None:
        for idx, rect in enumerate(self.choice_hitboxes):
            if rect.collidepoint(pos):
                if self.choice_selected != idx:
                    self.choice_selected = idx
                return

    def _camera_zoom_clamped(self) -> float:
        cdef double zoom
        try:
            zoom = float(self.camera_zoom)
        except (TypeError, ValueError):
            zoom = 1.0
        return _clamp_zoom_value(zoom)

    def _bg_transform(
        self,
        surface: pygame.Surface | None = None,
        float_amp: float | None = None,
        float_speed: float | None = None,
    ) -> tuple[float, float, float, float, float]:
        cdef object bg
        cdef double base_x
        cdef double base_y
        cdef int surf_w
        cdef int surf_h
        cdef double zoom
        cdef double base_center_x
        cdef double base_center_y
        cdef double draw_center_x
        cdef double draw_center_y
        bg = surface if surface is not None else self.background_surface
        if float_amp is None and float_speed is None:
            float_amp = self.background_state.float_amp
            float_speed = self.background_state.float_speed
        base_x, base_y = self._bg_draw_pos(bg, float_amp, float_speed)
        surf_w, surf_h = bg.get_size()
        zoom = self._camera_zoom_clamped()
        base_center_x = base_x + (surf_w * 0.5)
        base_center_y = base_y + (surf_h * 0.5)
        draw_center_x = base_center_x - (self.camera_pan_x * zoom)
        draw_center_y = base_center_y - (self.camera_pan_y * zoom)
        return draw_center_x, draw_center_y, zoom, float(surf_w), float(surf_h)

    def _bg_world_to_screen(self, point: tuple[int, int]) -> tuple[float, float]:
        cdef double cx
        cdef double cy
        cdef double zoom
        cdef double sw
        cdef double sh
        cdef int wx
        cdef int wy
        cdef double sx
        cdef double sy
        cx, cy, zoom, sw, sh = self._bg_transform()
        wx, wy = point
        sx = cx + ((float(wx) - (sw * 0.5)) * zoom)
        sy = cy + ((float(wy) - (sh * 0.5)) * zoom)
        return sx, sy

    def _screen_to_bg_world(self, point: tuple[int, int]) -> tuple[int, int]:
        cdef double cx
        cdef double cy
        cdef double zoom
        cdef double sw
        cdef double sh
        cdef double sx
        cdef double sy
        cdef double wx
        cdef double wy
        cx, cy, zoom, sw, sh = self._bg_transform()
        if zoom <= 0:
            zoom = 1.0
        sx, sy = float(point[0]), float(point[1])
        wx = ((sx - cx) / zoom) + (sw * 0.5)
        wy = ((sy - cy) / zoom) + (sh * 0.5)
        return int(round(wx)), int(round(wy))

    def _hotspot_screen_points(self, hotspot: HotspotArea) -> list[tuple[float, float]]:
        return [self._bg_world_to_screen(point) for point in hotspot.points]

    def _point_in_polygon(self, pos: Tuple[int, int], polygon: list[tuple[float, float]]) -> bool:
        cdef double x = float(pos[0])
        cdef double y = float(pos[1])
        return _point_in_polygon_xy(x, y, polygon)

    def _iter_hotspots_topmost(self) -> List[HotspotArea]:
        # Last defined hotspot wins on overlap.
        cdef list ordered = list(self.hotspots.values())
        ordered.reverse()
        return ordered

    def _find_hotspot(self, pos: Tuple[int, int]) -> Optional[HotspotArea]:
        for hotspot in self._iter_hotspots_topmost():
            if self._point_in_polygon(pos, self._hotspot_screen_points(hotspot)):
                return hotspot
        return None

    def _handle_hotspot_hover(self, pos: Tuple[int, int]) -> None:
        hotspot = self._find_hotspot(pos)
        self.hotspot_hovered = hotspot.name if hotspot else None

    def _handle_hotspot_click(self, pos: Tuple[int, int]) -> bool:
        hotspot = self._find_hotspot(pos)
        if hotspot is None:
            return False
        self.hotspot_hovered = hotspot.name
        self._jump(hotspot.target)
        self._step()
        return True

    def _step(self) -> None:
        while self.index < len(self.commands):
            cmd = self.commands[self.index]
            logger.debug("Exec %d: %s", self.index, cmd)
            self.index += 1

            if isinstance(cmd, Label):
                continue
            if isinstance(cmd, Scene):
                self._apply_scene(cmd)
                continue
            if isinstance(cmd, Show):
                self._apply_show(cmd)
                continue
            if isinstance(cmd, Hide):
                self._apply_hide(cmd)
                continue
            if isinstance(cmd, Music):
                self._apply_music(cmd)
                continue
            if isinstance(cmd, Video):
                self._apply_video(cmd)
                continue
            if isinstance(cmd, Sound):
                self.assets.play_sound(cmd.path)
                continue
            if isinstance(cmd, Echo):
                if cmd.action == "stop":
                    self.assets.stop_echo()
                else:
                    if cmd.path:
                        self.assets.play_echo(cmd.path)
                continue
            if isinstance(cmd, Voice):
                voice_path = self._resolve_voice_path(cmd)
                self.assets.play_voice(voice_path)
                continue
            if isinstance(cmd, CharacterDef):
                self._apply_character_def(cmd)
                continue
            if isinstance(cmd, ShowChar):
                self._apply_show_char(cmd)
                continue
            if isinstance(cmd, HotspotAdd):
                self._apply_hotspot_add(cmd)
                continue
            if isinstance(cmd, HotspotPoly):
                self._apply_hotspot_poly(cmd)
                continue
            if isinstance(cmd, HotspotRemove):
                self._apply_hotspot_remove(cmd)
                continue
            if isinstance(cmd, HotspotDebug):
                self.hotspot_debug = cmd.enabled
                if not cmd.enabled:
                    self.hotspot_hovered = None
                continue
            if isinstance(cmd, HudAdd):
                self._apply_hud_add(cmd)
                continue
            if isinstance(cmd, HudRemove):
                self._apply_hud_remove(cmd)
                continue
            if isinstance(cmd, CameraSet):
                self._apply_camera(cmd)
                continue
            if isinstance(cmd, Mute):
                self.assets.mute(cmd.target)
                continue
            if isinstance(cmd, Preload):
                self._apply_preload(cmd)
                continue
            if isinstance(cmd, CacheClear):
                self._apply_cache_clear(cmd)
                continue
            if isinstance(cmd, CachePin):
                self._apply_cache_pin(cmd)
                continue
            if isinstance(cmd, CacheUnpin):
                self._apply_cache_unpin(cmd)
                continue
            if isinstance(cmd, Loading):
                self._apply_loading(cmd)
                return
            if isinstance(cmd, GarbageCollect):
                gc.collect()
                continue
            if isinstance(cmd, Wait):
                self._apply_wait(cmd)
                return
            if isinstance(cmd, WaitVoice):
                if self._apply_wait_voice():
                    return
                continue
            if isinstance(cmd, WaitVideo):
                if self._apply_wait_video():
                    return
                continue
            if isinstance(cmd, Notify):
                self._apply_notify(cmd)
                continue
            if isinstance(cmd, Blend):
                self._apply_blend(cmd)
                continue
            if isinstance(cmd, Save):
                self.save_slot(cmd.slot)
                continue
            if isinstance(cmd, Load):
                self.load_slot(cmd.slot)
                return
            if isinstance(cmd, Call):
                self._apply_call(cmd)
                return
            if isinstance(cmd, Jump):
                self._jump(cmd.target)
                continue
            if isinstance(cmd, SetVar):
                self.variables[cmd.name] = self._resolve_set_value(cmd.value)
                continue
            if isinstance(cmd, AddVar):
                self._apply_add(cmd)
                continue
            if isinstance(cmd, Animate):
                self._apply_animate(cmd)
                continue
            if isinstance(cmd, IfJump):
                if self._eval_condition(cmd):
                    self._jump(cmd.target)
                continue
            if isinstance(cmd, Say):
                self._auto_show_character(cmd.speaker)
                self.current_say = (cmd.speaker, self._interpolate_variables(cmd.text))
                self.say_start_ms = pygame.time.get_ticks()
                self.say_reveal_all = False
                return
            if isinstance(cmd, Choice):
                self.current_choice = Choice(
                    [
                        (self._interpolate_variables(option_text), target)
                        for option_text, target in cmd.options
                    ],
                    self._interpolate_variables(cmd.prompt) if cmd.prompt else None,
                )
                self.choice_selected = 0
                if cmd.timeout:
                    self.choice_timer_start_ms = pygame.time.get_ticks()
                    self.choice_timeout_ms = int(cmd.timeout * 1000)
                    self.choice_timeout_default = cmd.timeout_default
                else:
                    self.choice_timer_start_ms = None
                    self.choice_timeout_ms = None
                    self.choice_timeout_default = None
                return
            if isinstance(cmd, Input):
                self._apply_input(cmd)
                return
            if isinstance(cmd, Phone):
                self._apply_phone(cmd)
                continue
            if isinstance(cmd, Meter):
                self._apply_meter(cmd)
                continue
            if isinstance(cmd, Item):
                self._apply_item(cmd)
                continue
            if isinstance(cmd, Map):
                if cmd.action == "show":
                    self._apply_map(cmd)
                    # Consume immediately-following POIs before entering map mode.
                    while self.index < len(self.commands):
                        next_cmd = self.commands[self.index]
                        if not isinstance(next_cmd, Map) or next_cmd.action != "poi":
                            break
                        self.index += 1
                        self._apply_map(next_cmd)
                    return  # Blocks while map is active
                if self._apply_map(cmd):
                    return
                continue

        if self.hotspots:
            return
        self.running = False

    def _jump(self, target: str) -> None:
        if target in {"::inventory_toggle", "inventory_toggle"}:
            if self._is_feature_enabled("items"):
                self.inventory_active = not self.inventory_active
                if not self.inventory_active:
                    self.inventory_hovered = None
            else:
                self.inventory_active = False
                self.inventory_hovered = None
            return
        if target.startswith("::"):
            target = target[2:]
        if target not in self.labels:
            raise ValueError(f"Unknown label: {target}")
        self.index = self.labels[target]

    def _apply_input(self, cmd: Input) -> None:
        self.input_active = True
        self.input_variable = cmd.variable
        self.input_prompt = self._interpolate_variables(cmd.prompt)
        text = str(cmd.default_value) if cmd.default_value is not None else ""
        self.input_buffer = text
        self.input_cursor = len(text)

    def _apply_phone(self, cmd: Phone) -> None:
        if cmd.action == "open":
            self.phone_active = True
            self.phone_contact = self._interpolate_variables(cmd.contact)
            # self.phone_messages = [] # Keep history? Or clear? Implementation plan says "accumulate", close clears.
            # actually if we open, we usually want to start fresh or keep previous context?
            # Start fresh seems safer for a simple system unless we have a specific "phone clear" command.
            # But wait, if I want to build a conversation, I might do open -> msg -> msg.
            # If I close and reopen, do I want history? Probably not for a linear VN, usually it's a specific scene.
            self.phone_messages = []
        elif cmd.action == "msg":
            if not self.phone_active:
                return # warn?
            text = self._interpolate_variables(cmd.text)
            self.phone_messages.append((cmd.side, text))
        elif cmd.action == "close":
            self.phone_active = False
            self.phone_contact = None
            self.phone_messages = []

    def _apply_meter(self, cmd: Meter) -> None:
        if cmd.action == "show":
            self.meters[cmd.variable] = {
                "label": self._interpolate_variables(cmd.label),
                "min": cmd.min_val,
                "max": cmd.max_val,
                "value": self.variables.get(cmd.variable, 0),
                "color": cmd.color or "#ffffff"
            }
        elif cmd.action == "hide":
            self.meters.pop(cmd.variable, None)
        elif cmd.action == "update":
            # Just refresh value from variables
            if cmd.variable in self.meters:
                self.meters[cmd.variable]["value"] = self.variables.get(cmd.variable, 0)
        elif cmd.action == "clear":
            self.meters.clear()

    def _apply_item(self, cmd: Item) -> None:
        if not self._is_feature_enabled("items"):
            return
        item_id = cmd.item_id
        if cmd.action == "add":
            if item_id in self.inventory:
                self.inventory[item_id]["count"] += cmd.amount
            else:
                self.inventory[item_id] = {
                    "name": cmd.name,
                    "desc": cmd.description,
                    "icon": cmd.icon,
                    "count": cmd.amount
                }
        elif cmd.action == "remove":
            if item_id in self.inventory:
                self.inventory[item_id]["count"] -= cmd.amount
                if self.inventory[item_id]["count"] <= 0:
                    self.inventory.pop(item_id)
        elif cmd.action == "clear":
            self.inventory.clear()
        self._clamp_inventory_page()

    def _apply_map(self, cmd: Map) -> bool:
        if cmd.action == "show":
            self.map_active = True
            self.map_image = cmd.value
            self.map_points = []
            self.map_hovered = None
            return True
        elif cmd.action == "poi":
            # map poi "<label>" <x1> <y1> ... -> <target>
            self.map_points.append({
                "label": cmd.label,
                "pos": cmd.pos if cmd.pos else (cmd.points[0] if cmd.points else (0,0)),
                "points": cmd.points,
                "target": cmd.target,
            })
            return False
        elif cmd.action == "hide":
            self.map_active = False
            self.map_image = None
            self.map_points = []
            return False
        return False

    def _apply_scene(self, cmd: Scene) -> None:
        self.background_state = BackgroundState(cmd.kind, cmd.value, cmd.float_amp, cmd.float_speed)
        screen_w, screen_h = self.screen.get_size()
        float_pad = int(abs(cmd.float_amp)) if cmd.float_amp else 0
        target_size = (screen_w + float_pad * 2, screen_h + float_pad * 2)
        if cmd.kind == "color":
            next_surface = self.assets.make_color_surface(cmd.value, target_size)
        else:
            surface = self.assets.load_image(cmd.value, "bg")
            next_surface = pygame.transform.smoothscale(surface, target_size)

        transition_style, transition_seconds = self._resolve_transition(cmd.transition_style, cmd.transition_seconds, cmd.fade)
        if transition_style and transition_seconds > 0:
            self.bg_transition_start = self.background_surface
            self.bg_transition_end = next_surface
            self.bg_transition_style = transition_style
            self.bg_transition_start_ms = pygame.time.get_ticks()
            self.bg_transition_duration_ms = max(1, int(transition_seconds * 1000))
            if transition_style == "dissolve":
                self.bg_transition_dissolve_tiles = []
            else:
                self.bg_transition_dissolve_tiles = []
            self.background_surface = next_surface
            return

        self.bg_transition_start = None
        self.bg_transition_end = None
        self.bg_transition_style = None
        self.bg_transition_start_ms = None
        self.bg_transition_duration_ms = 0
        self.bg_transition_dissolve_tiles = []
        self.background_surface = next_surface

    def _apply_show(self, cmd: Show) -> None:
        self.sprite_animations.pop(cmd.name, None)
        source_surface: pygame.Surface | None = None
        if cmd.kind == "rect":
            if not cmd.size:
                return
            surface = self.assets.make_rect_surface(cmd.value, cmd.size)
        else:
            source = self.assets.load_image(cmd.value, "sprites").copy()
            source_surface = source
            if cmd.size:
                width = max(1, int(cmd.size[0]))
                height = max(1, int(cmd.size[1]))
                surface = pygame.transform.smoothscale(source, (width, height))
            else:
                surface = source

        rect = surface.get_rect()
        if cmd.pos:
            rect.topleft = cmd.pos
        elif cmd.anchor:
            self._apply_anchor(rect, cmd.anchor)
        else:
            rect.centerx = self.screen.get_width() // 2
            rect.bottom = self.screen.get_height() - self.textbox.box_height - 20

        state = SpriteState(
            cmd.kind,
            cmd.value,
            cmd.size,
            cmd.pos,
            cmd.anchor,
            cmd.z,
            float_amp=cmd.float_amp,
            float_speed=cmd.float_speed,
            float_phase=self._float_phase_for(cmd.name),
        )
        transition_style, transition_seconds = self._resolve_transition(cmd.transition_style, cmd.transition_seconds, cmd.fade)
        if transition_style and transition_seconds > 0:
            now = pygame.time.get_ticks()
            if transition_style == "fade":
                state.alpha = 0
                state.fade_start_ms = now
                state.fade_duration_ms = max(1, int(transition_seconds * 1000))
                state.fade_from = 0
                state.fade_to = 255
            else:
                state.transition_style = transition_style
                state.transition_start_ms = now
                state.transition_duration_ms = max(1, int(transition_seconds * 1000))
                state.transition_mode = "in"
                state.transition_remove = False
                state.transition_seed = int(now + len(cmd.name) * 73) & 0xFFFF
        self.sprites[cmd.name] = SpriteInstance(state=state, surface=surface, rect=rect, source_surface=source_surface)

    def _apply_hotspot_add(self, cmd: HotspotAdd) -> None:
        points = [
            (cmd.x, cmd.y),
            (cmd.x + cmd.w, cmd.y),
            (cmd.x + cmd.w, cmd.y + cmd.h),
            (cmd.x, cmd.y + cmd.h),
        ]
        self.hotspots[cmd.name] = HotspotArea(name=cmd.name, points=points, target=cmd.target)

    def _apply_hotspot_poly(self, cmd: HotspotPoly) -> None:
        if len(cmd.points) < 3:
            return
        self.hotspots[cmd.name] = HotspotArea(name=cmd.name, points=list(cmd.points), target=cmd.target)

    def _apply_hotspot_remove(self, cmd: HotspotRemove) -> None:
        if cmd.name is None:
            self.hotspots.clear()
            self.hotspot_hovered = None
            return
        self.hotspots.pop(cmd.name, None)
        if self.hotspot_hovered == cmd.name:
            self.hotspot_hovered = None

    def _apply_hud_add(self, cmd: HudAdd) -> None:
        icon_surface = None
        if cmd.icon is not None:
            try:
                icon_surface = self.assets.load_image(cmd.icon, "sprites")
                if cmd.w > 0 and cmd.h > 0:
                    icon_surface = pygame.transform.smoothscale(icon_surface, (cmd.w, cmd.h))
            except Exception:
                icon_surface = None
        self.hud_buttons[cmd.name] = HudButton(
            name=cmd.name,
            style=cmd.style,
            text=cmd.text,
            icon_path=cmd.icon,
            icon_surface=icon_surface,
            rect=pygame.Rect(cmd.x, cmd.y, cmd.w, cmd.h),
            target=cmd.target,
        )

    def _apply_hud_remove(self, cmd: HudRemove) -> None:
        if cmd.name is None:
            self.hud_buttons.clear()
            self.hud_hovered = None
            return
        self.hud_buttons.pop(cmd.name, None)
        if self.hud_hovered == cmd.name:
            self.hud_hovered = None

    def _handle_hud_click(self, pos: Tuple[int, int]) -> bool:
        for btn in self.hud_buttons.values():
            if btn.rect.collidepoint(pos):
                self.hud_hovered = btn.name
                self._jump(btn.target)
                self._step()
                return True
        return False

    def _handle_hud_hover(self, pos: Tuple[int, int]) -> None:
        for btn in self.hud_buttons.values():
            if btn.rect.collidepoint(pos):
                self.hud_hovered = btn.name
                return
        self.hud_hovered = None

    def _apply_camera(self, cmd: CameraSet) -> None:
        self.camera_pan_x = float(cmd.pan_x)
        self.camera_pan_y = float(cmd.pan_y)
        self.camera_zoom = max(0.1, min(8.0, float(cmd.zoom)))

    def _apply_character_def(self, cmd: CharacterDef) -> None:
        sprites = cmd.sprites or {}
        if "default" not in sprites and sprites:
            first_key = next(iter(sprites.keys()))
            sprites = {"default": sprites[first_key], **sprites}
        self.characters[cmd.ident] = CharacterDef(
            ident=cmd.ident,
            display_name=cmd.display_name,
            color=cmd.color,
            sprites=sprites or None,
            voice_tag=cmd.voice_tag,
            pos=cmd.pos,
            anchor=cmd.anchor,
            z=cmd.z,
            float_amp=cmd.float_amp,
            float_speed=cmd.float_speed,
        )

    def _apply_show_char(self, cmd: ShowChar) -> None:
        character = self.characters.get(cmd.ident)
        if not character:
            if cmd.expression:
                self._apply_show(
                    Show(
                        kind="image",
                        name=cmd.ident,
                        value=cmd.expression,
                        pos=cmd.pos,
                        anchor=cmd.anchor,
                        z=cmd.z or 0,
                        fade=cmd.fade,
                        transition_style=cmd.transition_style,
                        transition_seconds=cmd.transition_seconds,
                        float_amp=cmd.float_amp,
                        float_speed=cmd.float_speed,
                    )
                )
            return

        expr = cmd.expression or "default"
        sprite_map = character.sprites or {}
        path = sprite_map.get(expr) or sprite_map.get("default")
        if not path:
            return
        pos = cmd.pos if cmd.pos is not None else character.pos
        anchor = cmd.anchor if cmd.anchor is not None else character.anchor
        z = cmd.z if cmd.z is not None else character.z
        float_amp = cmd.float_amp if cmd.float_amp is not None else character.float_amp
        float_speed = cmd.float_speed if cmd.float_speed is not None else character.float_speed
        self._apply_show(
            Show(
                kind="image",
                name=cmd.ident,
                value=path,
                pos=pos,
                anchor=anchor,
                z=z,
                fade=cmd.fade,
                transition_style=cmd.transition_style,
                transition_seconds=cmd.transition_seconds,
                float_amp=float_amp,
                float_speed=float_speed,
            )
        )

    def _auto_show_character(self, speaker: Optional[str]) -> None:
        if not speaker:
            return
        if speaker in self.sprites:
            return
        character = self.characters.get(speaker)
        if not character:
            return
        sprite_map = character.sprites or {}
        path = sprite_map.get("default")
        if not path:
            return
        pos = character.pos
        anchor = character.anchor or "right"
        z = character.z
        self._apply_show(
            Show(
                kind="image",
                name=speaker,
                value=path,
                pos=pos,
                anchor=anchor,
                z=z,
                float_amp=character.float_amp,
                float_speed=character.float_speed,
            )
        )

    def _resolve_voice_path(self, cmd: Voice) -> str:
        if not cmd.character:
            return cmd.path
        character = self.characters.get(cmd.character)
        if not character or not character.voice_tag:
            return cmd.path
        if "/" in cmd.path or cmd.path.startswith("./") or cmd.path.startswith("../"):
            return cmd.path
        return f"{character.voice_tag}/{cmd.path}"

    def _sorted_sprites(self) -> List[SpriteInstance]:
        sprites = list(self.sprites.values())
        sprites.sort(key=lambda item: item.state.z)
        return sprites

    def _apply_hide(self, cmd: Hide) -> None:
        sprite = self.sprites.get(cmd.name)
        if not sprite:
            return
        self.sprite_animations.pop(cmd.name, None)
        transition_style, transition_seconds = self._resolve_transition(cmd.transition_style, cmd.transition_seconds, cmd.fade)
        if transition_style and transition_seconds > 0:
            now = pygame.time.get_ticks()
            if transition_style == "fade":
                sprite.state.fade_start_ms = now
                sprite.state.fade_duration_ms = max(1, int(transition_seconds * 1000))
                sprite.state.fade_from = sprite.state.alpha
                sprite.state.fade_to = 0
                sprite.state.fade_remove = True
            else:
                sprite.state.transition_style = transition_style
                sprite.state.transition_start_ms = now
                sprite.state.transition_duration_ms = max(1, int(transition_seconds * 1000))
                sprite.state.transition_mode = "out"
                sprite.state.transition_remove = True
                sprite.state.transition_seed = int(now + len(cmd.name) * 89) & 0xFFFF
            return
        del self.sprites[cmd.name]

    def _apply_music(self, cmd: Music) -> None:
        self.music_state = (cmd.path, cmd.loop)
        self.assets.play_music(cmd.path, cmd.loop)

    def _apply_video(self, cmd: Video) -> None:
        if cmd.action == "stop":
            self._stop_video()
            return

        if not cmd.path:
            return
        try:
            resolved = self.assets.resolve_path(cmd.path, "video")
        except Exception:
            logger.warning("Video path resolution failed: %s", cmd.path)
            self._stop_video()
            return
        if not resolved.exists():
            logger.warning("Video not found: %s", resolved)
            self._stop_video()
            return

        try:
            playback = create_video_playback(
                resolved,
                loop=cmd.loop,
                backend=self.video_backend,
                audio_enabled=self.video_audio_enabled,
                framedrop=self.video_framedrop != "off",
            )
        except VideoBackendUnavailable as exc:
            logger.warning("Video backend unavailable: %s", exc)
            self._stop_video()
            return
        except Exception as exc:
            logger.warning("Video load failed (%s): %s", type(exc).__name__, exc)
            self._stop_video()
            return

        self.video_player = playback
        self.video_surface = None
        self.video_path = cmd.path
        self.video_fit = cmd.fit
        self.video_loop = cmd.loop
        self.video_backend_active = str(getattr(playback, "backend_name", self.video_backend))
        self.video_audio_pending.clear()
        self.video_audio_pcm_buffer.clear()
        self.video_audio_format = None
        self.video_audio_warned_format = False
        self.video_audio_backend_active = False
        self.video_framedrop_auto_hold = 0
        self.video_framedrop_effective = "on" if self.video_framedrop in {"auto", "on"} else "off"
        self._apply_video_framedrop_mode(playback)
        self._update_video_frame()
        self._update_video_stats(playback)

    def _stop_video(self) -> None:
        self._stop_video_audio()
        player = self.video_player
        if player is not None:
            try:
                player.close()
            except Exception:
                pass
        self.video_player = None
        self.video_surface = None
        self.video_path = None
        self.video_fit = "contain"
        self.video_loop = False
        self.video_stats = {}
        self.video_backend_active = "none"
        self.video_audio_backend_active = False
        self.video_framedrop_auto_hold = 0
        self.video_framedrop_effective = "off" if self.video_framedrop == "off" else "on"

    def _stop_video_audio(self) -> None:
        self.video_audio_pending.clear()
        self.video_audio_pcm_buffer.clear()
        self.video_audio_format = None
        channel = self.video_audio_channel
        if channel is None:
            self.video_audio_backend_active = False
            return
        try:
            channel.stop()
        except pygame.error:
            pass
        self.video_audio_backend_active = False

    def _video_audio_matches_mixer(self, sample_rate: int, channels: int, bytes_per_sample: int) -> bool:
        if sample_rate <= 0 or channels <= 0 or bytes_per_sample <= 0:
            return False
        if bytes_per_sample != 2:
            return False
        init = pygame.mixer.get_init()
        if not init:
            return False
        mix_rate, mix_format, mix_channels = init
        mix_bits = abs(int(mix_format))
        if mix_bits != bytes_per_sample * 8:
            return False
        if mix_rate != sample_rate:
            return False
        if mix_channels != channels:
            return False
        return True

    def _flush_video_audio_pcm(self, force: bool = False) -> None:
        fmt = self.video_audio_format
        if fmt is None:
            return
        sample_rate, channels, bytes_per_sample = fmt
        frame_bytes = max(1, channels * bytes_per_sample)
        if sample_rate <= 0:
            return
        target = int(sample_rate * channels * bytes_per_sample * (self.video_audio_chunk_ms / 1000.0))
        target = max(frame_bytes * 4, (target // frame_bytes) * frame_bytes)

        while len(self.video_audio_pcm_buffer) >= target or (force and len(self.video_audio_pcm_buffer) >= frame_bytes):
            if len(self.video_audio_pcm_buffer) >= target:
                size = target
            else:
                size = len(self.video_audio_pcm_buffer) - (len(self.video_audio_pcm_buffer) % frame_bytes)
                if size <= 0:
                    break
            chunk = bytes(self.video_audio_pcm_buffer[:size])
            del self.video_audio_pcm_buffer[:size]
            try:
                snd = pygame.mixer.Sound(buffer=chunk)
            except pygame.error as exc:
                if not self.video_audio_warned_format:
                    self.video_audio_warned_format = True
                    logger.warning("Video audio chunk rejected: %s", exc)
                continue
            self.video_audio_pending.append(snd)
            if len(self.video_audio_pending) > 64:
                # Keep queue bounded to avoid memory spikes on slow machines.
                self.video_audio_pending = self.video_audio_pending[-64:]

    def _enqueue_video_audio_packet(
        self,
        pts_ms: int,
        sample_rate: int,
        channels: int,
        bytes_per_sample: int,
        pcm: bytes,
    ) -> None:
        if not self.video_audio_enabled:
            return
        if self.video_audio_channel is None:
            return
        if not pcm:
            return
        if not self._video_audio_matches_mixer(sample_rate, channels, bytes_per_sample):
            if not self.video_audio_warned_format:
                self.video_audio_warned_format = True
                logger.warning(
                    "Video audio format mismatch; disabling embedded audio for this clip "
                    "(got %d Hz, %d ch, %d bytes; mixer=%s)",
                    sample_rate,
                    channels,
                    bytes_per_sample,
                    pygame.mixer.get_init(),
                )
            return
        fmt = (sample_rate, channels, bytes_per_sample)
        if self.video_audio_format is None:
            self.video_audio_format = fmt
        elif self.video_audio_format != fmt:
            self._flush_video_audio_pcm(force=True)
            self.video_audio_format = fmt
        self.video_audio_pcm_buffer.extend(pcm)
        self.video_audio_backend_active = True
        self._flush_video_audio_pcm(force=False)

    def _drain_video_audio_packets(self, player: object) -> None:
        drain = getattr(player, "drain_audio_packets", None)
        if not callable(drain):
            return
        packets = drain()
        if not packets:
            return
        for packet in packets:
            if not isinstance(packet, tuple) or len(packet) != 5:
                continue
            pts_ms, sample_rate, channels, bytes_per_sample, pcm = packet
            self._enqueue_video_audio_packet(
                int(pts_ms),
                int(sample_rate),
                int(channels),
                int(bytes_per_sample),
                bytes(pcm),
            )

    def _pump_video_audio(self) -> None:
        channel = self.video_audio_channel
        if channel is None:
            return
        if not self.video_audio_pending:
            return
        try:
            busy = channel.get_busy()
            queued = channel.get_queue()
            if not busy:
                current = self.video_audio_pending.pop(0)
                channel.play(current)
                if self.video_audio_pending and channel.get_queue() is None:
                    channel.queue(self.video_audio_pending.pop(0))
                return
            if queued is None:
                channel.queue(self.video_audio_pending.pop(0))
        except pygame.error:
            return

    def _update_video_frame(self) -> None:
        player = self.video_player
        if player is None:
            self._flush_video_audio_pcm(force=False)
            self._pump_video_audio()
            return
        self._apply_video_framedrop_mode(player)
        now_ms = pygame.time.get_ticks()
        try:
            frame, finished = player.update(now_ms)
            self._drain_video_audio_packets(player)
            self._flush_video_audio_pcm(force=False)
            self._pump_video_audio()
            self._update_video_stats(player)
        except Exception as exc:
            logger.warning("Video playback failed (%s): %s", type(exc).__name__, exc)
            self._stop_video()
            return
        if frame is not None:
            self.video_surface = frame
        if finished:
            self._flush_video_audio_pcm(force=True)
            self._pump_video_audio()
            if not self.video_loop:
                try:
                    player.close()
                except Exception:
                    pass
                self.video_player = None

    def _set_player_framedrop(self, player: object, enabled: bool) -> None:
        applied = False
        set_fn = getattr(player, "set_framedrop", None)
        if callable(set_fn):
            try:
                set_fn(bool(enabled))
                applied = True
            except Exception:
                applied = False
        if not applied:
            try:
                setattr(player, "framedrop", bool(enabled))
                applied = True
            except Exception:
                applied = False
        if applied:
            self.video_framedrop_effective = "on" if enabled else "off"

    def _compute_auto_framedrop(self) -> bool:
        stats = self.video_stats if isinstance(self.video_stats, dict) else {}
        lag_ms = int(stats.get("lag_ms", 0))
        q_depth = int(stats.get("video_queue_depth", 0))
        decode_stalled = bool(stats.get("decode_stalled", False))

        current_on = self.video_framedrop_effective == "on"
        if lag_ms >= 120 or q_depth >= 7:
            self.video_framedrop_auto_hold = 90
            return True
        if decode_stalled and lag_ms >= 48:
            self.video_framedrop_auto_hold = max(self.video_framedrop_auto_hold, 45)
            return True

        if self.video_framedrop_auto_hold > 0:
            self.video_framedrop_auto_hold -= 1
            return True

        if lag_ms <= 24 and q_depth <= 2:
            return False
        return current_on

    def _apply_video_framedrop_mode(self, player: object) -> None:
        if self.video_framedrop == "on":
            self._set_player_framedrop(player, True)
            return
        if self.video_framedrop == "off":
            self._set_player_framedrop(player, False)
            return
        desired = self._compute_auto_framedrop()
        self._set_player_framedrop(player, desired)

    def _update_video_stats(self, player: object) -> None:
        stats_fn = getattr(player, "stats", None)
        if not callable(stats_fn):
            return
        try:
            stats = stats_fn()
        except Exception:
            return
        if isinstance(stats, dict):
            self.video_stats = dict(stats)

    def _draw_video_layer(self) -> None:
        frame = self.video_surface
        if frame is None:
            return
        screen_w, screen_h = self.screen.get_size()
        frame_w, frame_h = frame.get_size()
        if frame_w <= 0 or frame_h <= 0:
            return
        fit = self.video_fit
        if fit == "stretch":
            scaled = pygame.transform.smoothscale(frame, (screen_w, screen_h))
            self.screen.blit(scaled, (0, 0))
            return

        if fit == "cover":
            scale = max(screen_w / frame_w, screen_h / frame_h)
        else:
            scale = min(screen_w / frame_w, screen_h / frame_h)
        target_w = max(1, int(round(frame_w * scale)))
        target_h = max(1, int(round(frame_h * scale)))
        scaled = pygame.transform.smoothscale(frame, (target_w, target_h))
        rect = scaled.get_rect(center=(screen_w // 2, screen_h // 2))
        self.screen.blit(scaled, rect)

    def _ease_value(self, t: float, ease: str) -> float:
        return _ease_progress(float(t), ease)

    def _apply_animate(self, cmd: Animate) -> None:
        if cmd.action == "stop":
            self.sprite_animations.pop(cmd.name, None)
            return

        sprite = self.sprites.get(cmd.name)
        if sprite is None:
            logger.debug("Animate ignored, sprite not found: %s", cmd.name)
            return
        duration_ms = max(1, int(max(0.0, cmd.seconds) * 1000))
        now = pygame.time.get_ticks()
        tracks = self.sprite_animations.setdefault(cmd.name, {})
        if cmd.action == "move":
            if cmd.v1 is None or cmd.v2 is None:
                return
            tracks["move"] = SpriteAnimation(
                action="move",
                start_v1=float(sprite.rect.x),
                start_v2=float(sprite.rect.y),
                end_v1=float(cmd.v1),
                end_v2=float(cmd.v2),
                start_ms=now,
                duration_ms=duration_ms,
                ease=cmd.ease,
            )
            return

        if cmd.action == "size":
            if cmd.v1 is None or cmd.v2 is None:
                return
            tracks["size"] = SpriteAnimation(
                action="size",
                start_v1=float(sprite.rect.width),
                start_v2=float(sprite.rect.height),
                end_v1=max(1.0, float(cmd.v1)),
                end_v2=max(1.0, float(cmd.v2)),
                start_ms=now,
                duration_ms=duration_ms,
                ease=cmd.ease,
            )
            return

        if cmd.action == "alpha":
            if cmd.v1 is None:
                return
            tracks["alpha"] = SpriteAnimation(
                action="alpha",
                start_v1=float(sprite.state.alpha),
                start_v2=0.0,
                end_v1=max(0.0, min(255.0, float(cmd.v1))),
                end_v2=0.0,
                start_ms=now,
                duration_ms=duration_ms,
                ease=cmd.ease,
            )
            return

    def _update_sprite_animations(self) -> None:
        cdef int now
        cdef object sprite
        cdef bint changed
        cdef list remove_actions
        cdef str action
        cdef object track
        cdef int elapsed
        cdef double progress
        cdef double eased
        cdef int target_w
        cdef int target_h
        cdef tuple top_left
        cdef int alpha
        if not self.sprite_animations:
            return
        now = pygame.time.get_ticks()
        for name, tracks in list(self.sprite_animations.items()):
            sprite = self.sprites.get(name)
            if sprite is None:
                self.sprite_animations.pop(name, None)
                continue

            changed = False
            remove_actions = []
            for action, track in tracks.items():
                elapsed = max(0, now - track.start_ms)
                progress = min(1.0, elapsed / max(1, track.duration_ms))
                eased = self._ease_value(progress, track.ease)
                if action == "move":
                    sprite.rect.x = int(round(track.start_v1 + ((track.end_v1 - track.start_v1) * eased)))
                    sprite.rect.y = int(round(track.start_v2 + ((track.end_v2 - track.start_v2) * eased)))
                    changed = True
                elif action == "size":
                    target_w = max(1, int(round(track.start_v1 + ((track.end_v1 - track.start_v1) * eased))))
                    target_h = max(1, int(round(track.start_v2 + ((track.end_v2 - track.start_v2) * eased))))
                    top_left = sprite.rect.topleft
                    if target_w != sprite.rect.width or target_h != sprite.rect.height:
                        self._rescale_sprite_surface(sprite, (target_w, target_h))
                        sprite.rect.topleft = top_left
                        changed = True
                elif action == "alpha":
                    alpha = int(round(track.start_v1 + ((track.end_v1 - track.start_v1) * eased)))
                    alpha = max(0, min(255, alpha))
                    if alpha != sprite.state.alpha:
                        sprite.state.alpha = alpha
                        changed = True

                if progress >= 1.0:
                    remove_actions.append(action)

            if changed:
                self._sync_sprite_state_from_rect(sprite)
            for action in remove_actions:
                tracks.pop(action, None)
            if not tracks:
                self.sprite_animations.pop(name, None)

    def _apply_wait(self, cmd: Wait) -> None:
        duration_ms = max(0, int(cmd.seconds * 1000))
        self.wait_until_ms = pygame.time.get_ticks() + duration_ms

    def _apply_wait_voice(self) -> bool:
        if not self.assets.is_voice_playing():
            self.wait_for_voice = False
            return False
        self.wait_for_voice = True
        return True

    def _is_video_active(self) -> bool:
        if self.video_player is not None:
            return True
        if self.video_audio_pending:
            return True
        if self.video_audio_pcm_buffer:
            return True
        channel = self.video_audio_channel
        if channel is not None:
            try:
                if channel.get_busy() or channel.get_queue() is not None:
                    return True
            except pygame.error:
                return False
        return False

    def _apply_wait_video(self) -> bool:
        if not self._is_video_active():
            self.wait_for_video = False
            return False
        self.wait_for_video = True
        return True

    def _apply_notify(self, cmd: Notify) -> None:
        self.notify_message = self._interpolate_variables(cmd.text)
        duration = cmd.seconds if cmd.seconds is not None else 3.0
        duration_ms = max(0, int(duration * 1000))
        self.notify_until_ms = pygame.time.get_ticks() + duration_ms

    def _apply_blend(self, cmd: Blend) -> None:
        style = (cmd.style or "fade").strip().lower()
        if style not in SUPPORTED_BLEND_STYLES:
            logger.warning("Unknown blend style '%s'; falling back to fade", cmd.style)
            style = "fade"
        if style == "none":
            self.blend_style = None
            self.blend_start_ms = None
            self.blend_duration_ms = 0
            self.blend_snapshot = None
            self.blend_dissolve_tiles = []
            return

        self.blend_style = style
        self.blend_start_ms = pygame.time.get_ticks()
        self.blend_duration_ms = max(1, int(cmd.seconds * 1000))
        # Snapshot is used by directional, dissolve, zoom and blur styles.
        self.blend_snapshot = self.screen.copy()
        if style == "dissolve":
            self._prepare_dissolve_tiles()
        else:
            self.blend_dissolve_tiles = []

    def _resolve_transition(
        self,
        style: str | None,
        seconds: float | None,
        fade: float | None,
    ) -> tuple[str | None, float]:
        cdef double resolved
        if style is not None and seconds is not None:
            if style == "none":
                return None, 0.0
            resolved = max(0.0, float(seconds))
            return style, resolved
        if fade is not None and fade > 0:
            return "fade", float(fade)
        return None, 0.0

    def _apply_add(self, cmd: AddVar) -> None:
        cdef object current
        current = self.variables.get(cmd.name, 0)
        if not isinstance(current, (int, float)):
            current = 0
        self.variables[cmd.name] = int(current) + cmd.amount

    def _eval_condition(self, cmd: IfJump) -> bool:
        cdef object left
        cdef object right
        left = self.variables.get(cmd.name, 0)
        right = self._resolve_variable_reference(cmd.value)

        if (
            isinstance(left, (int, float))
            and isinstance(right, (int, float))
            and not isinstance(left, bool)
            and not isinstance(right, bool)
        ):
            return _compare_numbers(float(left), float(right), cmd.op)

        if cmd.op == "==":
            return str(left) == str(right)
        if cmd.op == "!=":
            return str(left) != str(right)
        return False

    def _format_variable_value(self, value: object) -> str:
        if value is None:
            return ""
        if isinstance(value, bool):
            return "true" if value else "false"
        return str(value)

    def _resolve_variable_reference(self, value: object) -> object:
        cdef str raw
        cdef str name
        if not isinstance(value, str):
            return value
        raw = value.strip()
        if raw.startswith("$") and len(raw) > 1 and " " not in raw:
            name = raw[1:]
            return self.variables.get(name, "")
        return value

    def _resolve_set_value(self, value: object) -> object:
        value = self._resolve_variable_reference(value)
        if isinstance(value, str):
            return self._interpolate_variables(value)
        return value

    def _interpolate_variables(self, text: object) -> str:
        cdef str value
        if text is None:
            return ""
        value = str(text)
        if "${" not in value:
            return value

        def _replace(match):
            key = match.group(1)
            return self._format_variable_value(self.variables.get(key, ""))

        try:
            return _VAR_INTERPOLATION_RE.sub(_replace, value)
        except Exception:
            return value

    def _is_waiting(self) -> bool:
        if self.wait_for_video and self._is_video_active():
            return True
        if self.wait_for_voice and self.assets.is_voice_playing():
            return True
        return self.wait_until_ms is not None and pygame.time.get_ticks() < self.wait_until_ms

    def _update_timers(self) -> None:
        self._update_sprite_animations()
        self._update_video_frame()

        if self.wait_for_video and not self._is_video_active():
            self.wait_for_video = False
            if self.current_say is None and self.current_choice is None:
                self._step()

        if self.wait_for_voice and not self.assets.is_voice_playing():
            self.wait_for_voice = False
            if self.current_say is None and self.current_choice is None:
                self._step()

        if self.wait_until_ms is not None and pygame.time.get_ticks() >= self.wait_until_ms:
            self.wait_until_ms = None
            if self.current_say is None and self.current_choice is None:
                self._step()

        if self.current_choice is not None and self.choice_timeout_ms is not None:
            elapsed = pygame.time.get_ticks() - (self.choice_timer_start_ms or 0)
            if elapsed >= self.choice_timeout_ms:
                default_idx = (self.choice_timeout_default or 1) - 1
                if 0 <= default_idx < len(self.current_choice.options):
                    self.choice_selected = default_idx
                else:
                    self.choice_selected = 0
                self._select_choice()

        if self.notify_until_ms is not None and pygame.time.get_ticks() >= self.notify_until_ms:
            self.notify_until_ms = None
            self.notify_message = None

    def _is_notify_active(self) -> bool:
        return self.notify_until_ms is not None and pygame.time.get_ticks() < self.notify_until_ms

    def _apply_cache_clear(self, cmd: CacheClear) -> None:
        if cmd.kind == "images":
            self.assets.clear_images()
        elif cmd.kind == "sounds":
            self.assets.clear_sounds()
        elif cmd.kind == "script":
            if cmd.path:
                resolved = self._resolve_script_path(cmd.path)
                self._script_cache.pop(resolved, None)
                if resolved == self.current_script_path.resolve():
                    self._clear_runtime_memory()
                    self._prune_to_current_scene()
                else:
                    self._prune_to_current_scene()
            else:
                self._clear_script_cache()
                self._prune_to_current_scene()
        elif cmd.kind == "scripts":
            self._clear_script_cache()
            self._prune_to_current_scene()
        elif cmd.kind == "runtime":
            self._clear_script_cache()
            self._clear_runtime_memory()
            self.assets.clear_all()
            gc.collect()
        else:
            self.assets.clear_all()

    def _apply_loading(self, cmd: Loading) -> None:
        if cmd.action == "start":
            if cmd.text:
                self.loading_text = cmd.text
            self.loading_active = True
            self.loading_auto_continue = True
        else:
            self.loading_active = False
            self.loading_auto_continue = True

    def _apply_call(self, cmd: Call) -> None:
        cdef object script_path
        cdef bint cold
        cdef object prev_elapsed
        cdef bint show_auto_loading
        cdef int overlay_start_ms = 0
        cdef int call_start_ms = 0
        cdef int elapsed_ms = 0
        cdef int shown_ms = 0
        cdef int remain_ms = 0
        cdef str prev_loading_text = self.loading_text
        cdef object commands, labels, next_manifest
        script_path = self._resolve_script_path(cmd.path)
        cold = script_path not in self._script_cache
        prev_elapsed = self._call_elapsed_ms.get(script_path)
        show_auto_loading = (
            self.call_auto_loading
            and not self.loading_active
            and (
                cold
                or (
                    prev_elapsed is not None
                    and int(prev_elapsed) >= self.call_loading_threshold_ms
                )
            )
        )

        if show_auto_loading:
            self.loading_text = self.call_loading_text
            self.loading_active = True
            overlay_start_ms = pygame.time.get_ticks()
            self._render()
            pygame.display.flip()
            pygame.event.pump()

        call_start_ms = pygame.time.get_ticks()
        try:
            try:
                commands, labels, next_manifest = self._load_script(script_path)
            except ScriptParseError as exc:
                raise RuntimeError(str(exc)) from exc
            if cmd.label not in labels:
                raise RuntimeError(f"Unknown label in call: {cmd.label}")
            self._prefetch_manifest_assets(next_manifest)
            self._prune_for_scene_switch(next_manifest)
            self._prefetch_manifest_scripts(next_manifest)
            self.commands = commands
            self.labels = labels
            self.current_script_path = script_path
            self.current_scene_manifest = next_manifest
            self.index = labels[cmd.label]
            self.current_choice = None
            self.current_say = None
            self.say_start_ms = None
            self.say_reveal_all = False
            self.sprites.clear()
            self.hotspots.clear()
            self.hotspot_hovered = None
            self.sprite_animations.clear()
            self._stop_video()
            if self.show_script_editor and self.script_editor_follow_runtime:
                self.script_editor_path = script_path
                self.script_editor_loaded_path = None
        finally:
            elapsed_ms = max(0, pygame.time.get_ticks() - call_start_ms)
            self._call_elapsed_ms[script_path] = elapsed_ms
            if show_auto_loading:
                shown_ms = max(0, pygame.time.get_ticks() - overlay_start_ms)
                remain_ms = self.call_loading_min_show_ms - shown_ms
                if remain_ms > 0:
                    pygame.time.wait(remain_ms)
                self.loading_active = False
                self.loading_text = prev_loading_text

    def _reload_script_from_path(self, path: Path) -> tuple[bool, str]:
        script_path = path.resolve()
        try:
            script = parse_script(script_path)
        except ScriptParseError as exc:
            return False, str(exc)
        commands = script.commands
        labels = script.labels
        manifest = build_scene_manifest(commands)
        self._script_cache[script_path] = (commands, labels, manifest)
        self._prefetch_manifest_assets(manifest)
        self._prune_for_scene_switch(manifest)
        self.commands = commands
        self.labels = labels
        self.current_script_path = script_path
        self.current_scene_manifest = manifest
        if "start" in labels:
            self.index = labels["start"]
        elif labels:
            self.index = min(labels.values())
        else:
            self.index = 0

        self.current_say = None
        self.say_start_ms = None
        self.say_reveal_all = False
        self.current_choice = None
        self.choice_selected = 0
        self.choice_hitboxes = []
        self.wait_until_ms = None
        self.wait_for_voice = False
        self.wait_for_video = False
        self.notify_message = None
        self.notify_until_ms = None
        self.loading_active = False
        self.loading_auto_continue = False
        self.hotspots.clear()
        self.hotspot_hovered = None
        self.blend_style = None
        self.blend_start_ms = None
        self.blend_duration_ms = 0
        self.blend_snapshot = None
        self.bg_transition_start = None
        self.bg_transition_end = None
        self.bg_transition_start_ms = None
        self.bg_transition_duration_ms = 0
        self.bg_transition_style = None
        self.bg_transition_dissolve_tiles = []
        self.running = True
        self._step()
        return True, f"Reloaded {script_path}"

    def _load_script(self, path: Path) -> Tuple[List[Command], Dict[str, int], SceneManifest]:
        if path in self._script_cache:
            return self._script_cache[path]
        script = parse_script(path)
        manifest = build_scene_manifest(script.commands)
        data = (script.commands, script.labels, manifest)
        self._script_cache[path] = data
        return data

    def _handle_map_mousedown(self, event) -> None:
        if not self.map_active:
            return
        cdef int i
        cdef dict point
        for i in range(len(self.map_points)):
            point = self.map_points[i]
            if self._map_poi_contains(point, event.pos):
                self._jump(point["target"])
                self.map_active = False
                self.map_hovered = None
                self._step()
                return

    def _handle_map_mousemotion(self, event) -> None:
        if not self.map_active:
            return
        cdef int i
        cdef dict point
        self.map_hovered = None
        for i in range(len(self.map_points)):
            point = self.map_points[i]
            if self._map_poi_contains(point, event.pos):
                self.map_hovered = i
                return

    def _map_poi_contains(self, point: dict, pos: Tuple[int, int]) -> bool:
        cdef list points = point.get("points", [])
        cdef tuple anchor
        cdef double px
        cdef double py
        cdef double x = float(pos[0])
        cdef double y = float(pos[1])
        if len(points) >= 3:
            return _point_in_polygon_xy(x, y, points)
        anchor = point.get("pos", (0, 0))
        px = float(anchor[0])
        py = float(anchor[1])
        return _point_in_circle_xy(x, y, px, py, 22.0)

    def _handle_inventory_mousedown(self, event) -> None:
        if event.button == 4:
            self._scroll_inventory_page(-1)
            return
        if event.button == 5:
            self._scroll_inventory_page(1)
            return
        if self.inventory_panel_rect is not None and self.inventory_panel_rect.collidepoint(event.pos):
            return
        self.inventory_active = False
        self.inventory_hovered = None

    def _handle_inventory_mousemotion(self, event) -> None:
        if not self.inventory_active:
            return
        return

    def _is_feature_enabled(self, name: str) -> bool:
        return bool(self.feature_flags.get(name, True))

    def _clamp_inventory_page(self) -> None:
        cdef int total = len(self.inventory)
        cdef int per_page = max(1, int(self.inventory_items_per_page))
        cdef int max_page = 0
        if total > 0:
            max_page = (total - 1) // per_page
        if self.inventory_page < 0:
            self.inventory_page = 0
        if self.inventory_page > max_page:
            self.inventory_page = max_page

    def _scroll_inventory_page(self, delta: int) -> None:
        cdef int total
        cdef int per_page
        cdef int max_page
        if delta == 0:
            return
        total = len(self.inventory)
        per_page = max(1, int(self.inventory_items_per_page))
        if total <= per_page:
            self.inventory_page = 0
            return
        max_page = (total - 1) // per_page
        self.inventory_page += delta
        if self.inventory_page < 0:
            self.inventory_page = 0
        if self.inventory_page > max_page:
            self.inventory_page = max_page

    def _clear_script_cache(self) -> None:
        self._script_cache.clear()

    def _clear_runtime_memory(self) -> None:
        # Stop all active media channels and clear transient scene state.
        self.assets.mute("all")
        self._stop_video()
        self.music_state = None
        self.current_say = None
        self.say_start_ms = None
        self.say_reveal_all = False
        self.current_choice = None
        self.choice_selected = 0
        self.choice_hitboxes = []
        self.wait_until_ms = None
        self.wait_for_voice = False
        self.wait_for_video = False
        self.notify_message = None
        self.notify_until_ms = None
        self.loading_active = False
        self.loading_auto_continue = False
        self.choice_timer_start_ms = None
        self.choice_timeout_ms = None
        self.choice_timeout_default = None
        self.input_active = False
        self.input_variable = None
        self.input_prompt = None
        self.input_buffer = ""
        self.input_cursor = 0
        self.phone_active = False
        self.phone_contact = None
        self.phone_messages = []
        self.sprites.clear()
        self.sprite_animations.clear()
        self.hotspots.clear()
        self.hotspot_hovered = None
        self.background_state = BackgroundState("color", "#000000")
        self.background_surface = self.assets.make_color_surface("#000000")
        self.camera_pan_x = 0.0
        self.camera_pan_y = 0.0
        self.camera_zoom = 1.0
        self.blend_style = None
        self.blend_start_ms = None
        self.blend_duration_ms = 0
        self.blend_snapshot = None
        self.blend_dissolve_tiles = []
        self.bg_transition_start = None
        self.bg_transition_end = None
        self.bg_transition_start_ms = None
        self.bg_transition_duration_ms = 0
        self.bg_transition_style = None
        self.bg_transition_dissolve_tiles = []
        self.current_scene_manifest = SceneManifest()

    def _resolve_script_path(self, raw: str) -> Path:
        p = Path(raw)
        if p.is_absolute():
            return p
        return (self._project_root / p).resolve()

    def _resolve_manifest_images(self, manifest: SceneManifest) -> set[Path]:
        out: set[Path] = set()
        for rel in manifest.bg_images:
            out.add(self.assets.resolve_path(rel, "bg"))
        for rel in manifest.sprite_images:
            out.add(self.assets.resolve_path(rel, "sprites"))
        return out

    def _resolve_manifest_sounds(self, manifest: SceneManifest) -> set[Path]:
        out: set[Path] = set()
        for rel in manifest.audio_paths:
            out.add(self.assets.resolve_path(rel, "audio"))
        return out

    def _prefetch_manifest_assets(self, manifest: SceneManifest) -> None:
        for rel in manifest.bg_images:
            self.assets.preload_image(rel, "bg")
        for rel in manifest.sprite_images:
            self.assets.preload_image(rel, "sprites")
        for rel in manifest.audio_paths:
            self.assets.preload_sound(rel)

    def _prefetch_manifest_scripts(self, manifest: SceneManifest) -> None:
        for rel in manifest.script_calls:
            path = self._resolve_script_path(rel)
            try:
                self._load_script(path)
            except ScriptParseError as exc:
                logger.warning("Scene prefetch script parse failed (%s): %s", path, exc)

    def _prune_for_scene_switch(self, next_manifest: SceneManifest) -> None:
        keep_images = self._resolve_manifest_images(next_manifest)
        keep_sounds = self._resolve_manifest_sounds(next_manifest)
        # Keep current music asset path if active, even though music is not in Sound cache.
        if self.music_state is not None:
            keep_sounds.add(self.assets.resolve_path(self.music_state[0], "audio"))
        self.assets.prune_images(keep_images)
        self.assets.prune_sounds(keep_sounds)

    def _prune_to_current_scene(self) -> None:
        keep_images = self._resolve_manifest_images(self.current_scene_manifest)
        keep_sounds = self._resolve_manifest_sounds(self.current_scene_manifest)
        if self.music_state is not None:
            keep_sounds.add(self.assets.resolve_path(self.music_state[0], "audio"))
        self.assets.prune_images(keep_images)
        self.assets.prune_sounds(keep_sounds)

    def prefetch_scripts(self, paths: List[Path]) -> None:
        for path in paths:
            try:
                self._load_script(path)
            except ScriptParseError as exc:
                raise RuntimeError(str(exc)) from exc

    def _apply_cache_pin(self, cmd: CachePin) -> None:
        if cmd.kind == "audio":
            self.assets.pin_sound(cmd.path)
        else:
            self.assets.pin_image(cmd.path, cmd.kind)

    def _apply_cache_unpin(self, cmd: CacheUnpin) -> None:
        if cmd.kind == "audio":
            self.assets.unpin_sound(cmd.path)
        else:
            self.assets.unpin_image(cmd.path, cmd.kind)

    def _apply_preload(self, cmd: Preload) -> None:
        if cmd.kind == "audio":
            self.assets.preload_sound(cmd.path)
        else:
            self.assets.preload_image(cmd.path, cmd.kind)

    def _apply_anchor(self, rect: pygame.Rect, anchor: str) -> None:
        tokens = anchor.split()
        x_anchor: Optional[str] = None
        y_anchor: Optional[str] = None
        for token in tokens:
            if token in {"left", "center", "right"}:
                x_anchor = token
            elif token in {"top", "middle", "bottom"}:
                y_anchor = token

        if x_anchor is None:
            x_anchor = "center"
        if y_anchor is None:
            y_anchor = "bottom"

        screen_w = self.screen.get_width()
        screen_h = self.screen.get_height()
        edge_margin = int(screen_w * 0.08)
        top_margin = int(screen_h * 0.08)
        bottom_y = screen_h - self.textbox.box_height - 20

        if x_anchor == "left":
            rect.left = edge_margin
        elif x_anchor == "right":
            rect.right = screen_w - edge_margin
        else:
            rect.centerx = screen_w // 2

        if y_anchor == "top":
            rect.top = top_margin
        elif y_anchor == "middle":
            rect.centery = screen_h // 2
        else:
            rect.bottom = bottom_y

    def _visible_text(self, text: str) -> Tuple[str, bool]:
        cdef int elapsed
        cdef int max_chars
        cdef int total_visible
        if self.say_reveal_all or self.text_speed <= 0 or self.say_start_ms is None:
            return text, True
        elapsed = pygame.time.get_ticks() - self.say_start_ms
        max_chars = int((elapsed / 1000.0) * self.text_speed)
        total_visible = count_visible_chars(text)
        if max_chars >= total_visible:
            return text, True
        return slice_visible_text(text, max_chars), False

    def _is_current_say_revealed(self) -> bool:
        if self.current_say is None:
            return True
        _, text = self.current_say
        _, done = self._visible_text(text)
        return done

    def _resolve_speaker(
        self, speaker: Optional[str]
    ) -> Tuple[Optional[str], Optional[Tuple[int, int, int]]]:
        if not speaker:
            return None, None
        character = self.characters.get(speaker)
        if not character:
            return speaker, None
        name = character.display_name or speaker
        color = None
        if character.color:
            try:
                color = parse_color(character.color)
            except Exception:
                color = None
        return name, color


cpdef bint _compare_numbers(double left, double right, str op):
    if op == "==":
        return left == right
    if op == "!=":
        return left != right
    if op == ">":
        return left > right
    if op == ">=":
        return left >= right
    if op == "<":
        return left < right
    if op == "<=":
        return left <= right
    return False
