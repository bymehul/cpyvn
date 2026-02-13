# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict

@dataclass(frozen=True)
class FeatureConfig:
    use: bool
    path: Path


@dataclass(frozen=True)
class WindowConfig:
    width: int
    height: int
    fps: int
    resizable: bool


@dataclass(frozen=True)
class UiConfig:
    text_speed: float = 0.0
    box_opacity: float = 0.67
    font_size: int = 30
    name_font_size: int = 26
    choice_font_size: int = 28
    notify_font_size: int = 26
    show_perf: bool = False
    call_auto_loading: bool = True
    call_loading_text: str = "Loading scene..."
    call_loading_threshold_ms: int = 120
    call_loading_min_show_ms: int = 120
    pause_menu_enabled: bool = True
    pause_menu_file: str = "pause_menu.json"
    pause_menu_slots: int = 9
    pause_menu_columns: int = 3
    title_menu_enabled: bool = False
    title_menu_file: str = "title_menu.json"


@dataclass(frozen=True)
class ProjectConfig:
    name: str
    root: Path
    entry: Path
    window: WindowConfig
    assets: Dict[str, Path]
    saves_dir: Path
    prefetch: object
    debug: bool
    ui: UiConfig
    features: Dict[str, FeatureConfig]
    wgpu_blur: bool
    wgpu_backend: object
    video_backend: str
    video_audio: bool
    video_framedrop: str

cpdef bint _parse_bool(object value, bint default=False):
    if value is None:
        return default
    if isinstance(value, bool):
        return <bint>value
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


cpdef double _parse_float(object value, double default=0.0):
    if value is None:
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


cpdef double _clamp01(double value):
    if value < 0.0:
        return 0.0
    if value > 1.0:
        return 1.0
    return value


cpdef object _parse_str(object value):
    """Return stripped string or None."""
    cdef str text
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None


cpdef str _parse_video_backend(object value, str default="auto"):
    cdef str text
    if value is None:
        return default
    text = str(value).strip().lower()
    if not text:
        return default
    if text in {"auto", "default"}:
        return "auto"
    if text in {"vnef", "native", "vnef-video", "vnef_video"}:
        return "vnef"
    if text in {"imageio", "imageio-ffmpeg"}:
        return "vnef"
    return default


cpdef str _parse_video_framedrop(object value, str default="auto"):
    cdef str text
    if value is None:
        return default
    text = str(value).strip().lower()
    if not text:
        return default
    if text in {"auto", "default"}:
        return "auto"
    if text in {"on", "true", "1", "yes"}:
        return "on"
    if text in {"off", "false", "0", "no"}:
        return "off"
    return default

cpdef object load_project(object project_dir):
    cdef object root, config_path, data
    cdef str name
    cdef object entry
    cdef dict window_data, assets_data, ui_data
    cdef object window, assets, saves_dir
    cdef object prefetch, prefetch_value
    cdef bint debug, wgpu_blur, video_audio, call_auto_loading, pause_menu_enabled, title_menu_enabled
    cdef object wgpu_backend
    cdef str video_backend, video_framedrop
    cdef str call_loading_text, pause_menu_file, title_menu_file
    cdef int call_loading_threshold_ms, call_loading_min_show_ms, pause_menu_slots, pause_menu_columns
    cdef object ui
    cdef dict features_data
    cdef dict features = {}
    cdef str f_key
    cdef dict f_val

    root = Path(project_dir).resolve()
    config_path = root / "project.json"
    if not config_path.exists():
        raise FileNotFoundError(f"Missing project.json in {root}")

    data = json.loads(config_path.read_text(encoding="utf-8"))

    name  = str(data.get("name", root.name))
    entry = root / str(data.get("entry", "script.vn"))

    window_data = data.get("window", {})
    window = WindowConfig(
        width=int(window_data.get("width",  1280)),
        height=int(window_data.get("height", 720)),
        fps=int(window_data.get("fps",       60)),
        resizable=_parse_bool(window_data.get("resizable"), default=True),
    )

    assets_data = data.get("assets", {})
    assets = {
        "bg":      root / assets_data.get("bg",      "assets/bg"),
        "sprites": root / assets_data.get("sprites", "assets/sprites"),
        "audio":   root / assets_data.get("audio",   "assets/audio"),
        "video":   root / assets_data.get("video",   "assets/video"),
    }

    saves_dir      = root / data.get("saves", "saves")
    prefetch_value = data.get("prefetch")
    prefetch       = None
    if isinstance(prefetch_value, str) and prefetch_value.strip():
        prefetch = (root / prefetch_value.strip()).resolve()
    elif _parse_bool(prefetch_value, default=False):
        prefetch = (root / "prefetch.json").resolve()

    debug            = _parse_bool(data.get("debug", False), default=False)
    ui_data          = data.get("ui", {})
    wgpu_blur        = _parse_bool(data.get("wgpu_blur",   False), default=False)
    wgpu_backend     = _parse_str(data.get("wgpu_backend"))
    video_backend    = _parse_video_backend(data.get("video_backend"),   default="auto")
    video_audio      = _parse_bool(data.get("video_audio", True),        default=True)
    video_framedrop  = _parse_video_framedrop(data.get("video_framedrop"), default="auto")

    if "wgpu_blur" in ui_data:
        wgpu_blur = _parse_bool(ui_data.get("wgpu_blur"), default=wgpu_blur)
    if "wgpu_backend" in ui_data:
        wgpu_backend = _parse_str(ui_data.get("wgpu_backend")) or wgpu_backend
    if "video_backend" in ui_data:
        video_backend = _parse_video_backend(ui_data.get("video_backend"), default=video_backend)
    if "video_audio" in ui_data:
        video_audio = _parse_bool(ui_data.get("video_audio"), default=video_audio)
    if "video_framedrop" in ui_data:
        video_framedrop = _parse_video_framedrop(ui_data.get("video_framedrop"), default=video_framedrop)

    call_auto_loading = _parse_bool(
        data.get("call_auto_loading", UiConfig.call_auto_loading),
        default=UiConfig.call_auto_loading,
    )
    call_loading_text = str(
        data.get("call_loading_text", UiConfig.call_loading_text)
    ).strip() or UiConfig.call_loading_text
    call_loading_threshold_ms = max(
        0,
        int(
            _parse_float(
                data.get("call_loading_threshold_ms", UiConfig.call_loading_threshold_ms),
                default=UiConfig.call_loading_threshold_ms,
            )
        ),
    )
    call_loading_min_show_ms = max(
        0,
        int(
            _parse_float(
                data.get("call_loading_min_show_ms", UiConfig.call_loading_min_show_ms),
                default=UiConfig.call_loading_min_show_ms,
            )
        ),
    )
    pause_menu_enabled = _parse_bool(
        data.get("pause_menu_enabled", UiConfig.pause_menu_enabled),
        default=UiConfig.pause_menu_enabled,
    )
    pause_menu_file = str(
        data.get("pause_menu_file", UiConfig.pause_menu_file)
    ).strip() or UiConfig.pause_menu_file
    pause_menu_slots = max(
        1,
        int(
            _parse_float(
                data.get("pause_menu_slots", UiConfig.pause_menu_slots),
                default=UiConfig.pause_menu_slots,
            )
        ),
    )
    pause_menu_columns = max(
        1,
        int(
            _parse_float(
                data.get("pause_menu_columns", UiConfig.pause_menu_columns),
                default=UiConfig.pause_menu_columns,
            )
        ),
    )
    title_menu_enabled = _parse_bool(
        data.get("title_menu_enabled", UiConfig.title_menu_enabled),
        default=UiConfig.title_menu_enabled,
    )
    title_menu_file = str(
        data.get("title_menu_file", UiConfig.title_menu_file)
    ).strip() or UiConfig.title_menu_file

    if "call_auto_loading" in ui_data:
        call_auto_loading = _parse_bool(
            ui_data.get("call_auto_loading"),
            default=call_auto_loading,
        )
    if "call_loading_text" in ui_data:
        call_loading_text = str(ui_data.get("call_loading_text")).strip() or call_loading_text
    if "call_loading_threshold_ms" in ui_data:
        call_loading_threshold_ms = max(
            0,
            int(
                _parse_float(
                    ui_data.get("call_loading_threshold_ms"),
                    default=call_loading_threshold_ms,
                )
            ),
        )
    if "call_loading_min_show_ms" in ui_data:
        call_loading_min_show_ms = max(
            0,
            int(
                _parse_float(
                    ui_data.get("call_loading_min_show_ms"),
                    default=call_loading_min_show_ms,
                )
            ),
        )
    if "pause_menu_enabled" in ui_data:
        pause_menu_enabled = _parse_bool(
            ui_data.get("pause_menu_enabled"),
            default=pause_menu_enabled,
        )
    if "pause_menu_file" in ui_data:
        pause_menu_file = str(ui_data.get("pause_menu_file")).strip() or pause_menu_file
    if "pause_menu_slots" in ui_data:
        pause_menu_slots = max(
            1,
            int(
                _parse_float(
                    ui_data.get("pause_menu_slots"),
                    default=pause_menu_slots,
                )
            ),
        )
    if "pause_menu_columns" in ui_data:
        pause_menu_columns = max(
            1,
            int(
                _parse_float(
                    ui_data.get("pause_menu_columns"),
                    default=pause_menu_columns,
                )
            ),
        )
    if "title_menu_enabled" in ui_data:
        title_menu_enabled = _parse_bool(
            ui_data.get("title_menu_enabled"),
            default=title_menu_enabled,
        )
    if "title_menu_file" in ui_data:
        title_menu_file = str(ui_data.get("title_menu_file")).strip() or title_menu_file

    features_data = data.get("features", {})
    for f_key in ("hud", "items", "maps"):
        f_val = features_data.get(f_key, {})
        features[f_key] = FeatureConfig(
            use=_parse_bool(f_val.get("use", False), default=False),
            path=root / str(f_val.get("path", f"{f_key}.cvn")),
        )

    ui = UiConfig(
        text_speed=_parse_float(
            ui_data.get("text_speed", UiConfig.text_speed),
            default=UiConfig.text_speed,
        ),
        box_opacity=_clamp01(
            _parse_float(
                ui_data.get("box_opacity", UiConfig.box_opacity),
                default=UiConfig.box_opacity,
            )
        ),
        font_size=int(ui_data.get("font_size",           UiConfig.font_size)),
        name_font_size=int(ui_data.get("name_font_size", UiConfig.name_font_size)),
        choice_font_size=int(ui_data.get("choice_font_size", UiConfig.choice_font_size)),
        notify_font_size=int(ui_data.get("notify_font_size", UiConfig.notify_font_size)),
        show_perf=_parse_bool(
            ui_data.get("show_perf", UiConfig.show_perf),
            default=UiConfig.show_perf,
        ),
        call_auto_loading=call_auto_loading,
        call_loading_text=call_loading_text,
        call_loading_threshold_ms=call_loading_threshold_ms,
        call_loading_min_show_ms=call_loading_min_show_ms,
        pause_menu_enabled=pause_menu_enabled,
        pause_menu_file=pause_menu_file,
        pause_menu_slots=pause_menu_slots,
        pause_menu_columns=pause_menu_columns,
        title_menu_enabled=title_menu_enabled,
        title_menu_file=title_menu_file,
    )

    return ProjectConfig(
        name=name,
        root=root,
        entry=entry,
        window=window,
        assets=assets,
        saves_dir=saves_dir,
        prefetch=prefetch,
        debug=debug,
        ui=ui,
        features=features,
        wgpu_blur=wgpu_blur,
        wgpu_backend=wgpu_backend,
        video_backend=video_backend,
        video_audio=video_audio,
        video_framedrop=video_framedrop,
    )
