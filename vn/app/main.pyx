# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
from __future__ import annotations

from pathlib import Path
import json
import logging

import pygame

from ..assets import AssetManager
from ..utils import require_cython
from ..parser import ScriptParseError, parse_script

from ..config import UiConfig
from ..gpu import create_wgpu_blur_backend, probe_wgpu_backend
from ..runtime import VNRuntime

logger = logging.getLogger("cpyvn.app")

cpdef list _coerce_list(object value):
    """Coerce *value* to a list of non-empty stripped strings."""
    cdef str text
    cdef list items

    if value is None:
        return []
    if isinstance(value, list):
        items = []
        for item in value:
            text = str(item).strip()
            if text:
                items.append(text)
        return items
    text = str(value).strip()
    return [text] if text else []


cpdef object _load_prefetch_data(object path):
    """Load and validate a JSON prefetch file.

    Returns the parsed dict, or *None* on any failure.
    """
    cdef object data

    if not path.exists():
        logger.warning("Prefetch file not found: %s", path)
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        logger.warning("Failed to read prefetch file %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        logger.warning("Prefetch file must be a JSON object: %s", path)
        return None
    return data


def _iter_prefetch_scripts(dict data):
    cdef str item
    for item in _coerce_list(data.get("scripts")):
        yield item


def _iter_prefetch_images(dict data, str kind):
    cdef object images
    cdef str item

    images = data.get("images", {})
    if isinstance(images, dict):
        for item in _coerce_list(images.get(kind)):
            yield item
    for item in _coerce_list(data.get(kind)):
        yield item


def _iter_prefetch_audio(dict data):
    cdef object audio
    cdef str key, item

    audio = data.get("audio", [])
    if isinstance(audio, dict):
        for key in ("music", "sfx", "voice", "sounds"):
            for item in _coerce_list(audio.get(key)):
                yield item
    else:
        for item in _coerce_list(audio):
            yield item

cpdef void _prefetch_assets(object assets, dict data):
    cdef set pinned_images = set()
    cdef set pinned_sounds = set()
    cdef str kind, path
    cdef object resolved

    for kind in ("bg", "sprites"):
        for path in _iter_prefetch_images(data, kind):
            resolved = assets.resolve_path(path, kind)
            if resolved in pinned_images:
                continue
            if not resolved.exists():
                logger.warning("Prefetch missing %s image: %s", kind, resolved)
                continue
            assets.pin_image(path, kind)
            pinned_images.add(resolved)

    for path in _iter_prefetch_audio(data):
        resolved = assets.resolve_path(path, "audio")
        if resolved in pinned_sounds:
            continue
        if not resolved.exists():
            logger.warning("Prefetch missing audio: %s", resolved)
            continue
        assets.pin_sound(path)
        pinned_sounds.add(resolved)


cpdef list _resolve_prefetch_scripts(dict data, object project_root):
    cdef set seen = set()
    cdef list scripts = []
    cdef str raw
    cdef object p

    for raw in _iter_prefetch_scripts(data):
        p = Path(raw)
        if not p.is_absolute():
            p = (project_root / p).resolve()
        if p in seen:
            continue
        if not p.exists():
            logger.warning("Prefetch missing script: %s", p)
            continue
        seen.add(p)
        scripts.append(p)
    return scripts


cpdef void run(
    object script_path,
    object project_root,
    str title,
    int width,
    int height,
    int fps,
    bint resizable,
    dict asset_dirs,
    object save_dir,
    object ui = None,
    object prefetch_path = None,
    bint wgpu_blur = False,
    object wgpu_backend = None,
    str video_backend = "auto",
    bint video_audio = True,
    str video_framedrop = "auto",
    dict features = None,
):
    cdef object assets, screen, blur_backend
    cdef object selected_backend
    cdef bint should_probe
    cdef dict prefetch_data
    cdef list prefetch_scripts
    cdef object script, runtime
    cdef str f_alias
    cdef object f_conf
    cdef dict feature_script_paths = {}
    cdef dict feature_flags = {"hud": True, "items": True, "maps": True}

    require_cython()

    pygame.init()
    pygame.mixer.init()
    pygame.mixer.set_num_channels(16)
    pygame.mixer.set_reserved(2)

    assets = AssetManager(
        project_root=project_root,
        asset_dirs=asset_dirs,
        screen_size=(width, height),
    )

    # On some Linux/mesa stacks, creating a wgpu adapter after SDL creates the
    # window can trigger an unrecoverable EGL BadAccess panic inside wgpu-native.
    # Initialize the optional wgpu blur backend before `pygame.display.set_mode`.
    if wgpu_blur:
        selected_backend = wgpu_backend
        should_probe = (
            selected_backend is not None
            and selected_backend.strip().lower() in {"opengl", "gl", "gles"}
        )
        if should_probe and not probe_wgpu_backend(selected_backend):
            logger.warning(
                "Requested wgpu backend '%s' failed probe on this host; "
                "falling back to auto selection",
                selected_backend,
            )
            selected_backend = None

        blur_backend = create_wgpu_blur_backend(backend_type=selected_backend)

        if blur_backend is None and selected_backend is not None:
            logger.warning(
                "Failed to initialize requested wgpu backend '%s'; "
                "retrying with auto selection",
                selected_backend,
            )
            selected_backend = None
            blur_backend = create_wgpu_blur_backend()

        if blur_backend is None:
            logger.warning("WGPU blur requested but unavailable; using CPU blur fallback")
        else:
            assets.set_blur_backend(blur_backend)
            assets.require_wgpu_blur = False
            if selected_backend:
                logger.info("WGPU blur enabled (backend override: %s)", selected_backend)
            else:
                logger.info("WGPU blur enabled")

    cdef int window_flags = pygame.RESIZABLE if resizable else 0
    screen = pygame.display.set_mode((width, height), window_flags)
    pygame.display.set_caption(title)

    prefetch_data = None
    prefetch_scripts = []
    if prefetch_path is not None:
        prefetch_data = _load_prefetch_data(prefetch_path)
        if prefetch_data is not None:
            _prefetch_assets(assets, prefetch_data)
            prefetch_scripts = _resolve_prefetch_scripts(prefetch_data, project_root)

    try:
        script = parse_script(script_path)
    except ScriptParseError as exc:
        print(str(exc))
        pygame.quit()
        return

    # Auto-merge special features
    if features:
        for f_alias, f_conf in features.items():
            feature_flags[f_alias] = bool(f_conf.use)
            if f_conf.use:
                if f_conf.path.exists():
                    feature_script_paths[f_alias] = f_conf.path.resolve()
                    try:
                        included = parse_script(f_conf.path)
                        # We use dynamic import to avoid 'include' keyword conflict in Cython
                        __import__("vn.parser.include", fromlist=["_merge_script"])._merge_script(
                            included=included,
                            commands=script.commands,
                            labels=script.labels,
                            path=script_path,
                            line_no=0,
                            alias=f_alias,
                            include_path=f_conf.path,
                        )
                        logger.info("Auto-included feature '%s' from %s", f_alias, f_conf.path)
                    except ScriptParseError as exc:
                        logger.error("Failed to parse auto-included feature '%s': %s", f_alias, exc)
                else:
                    logger.warning("Feature '%s' enabled but path not found: %s", f_alias, f_conf.path)

    runtime = VNRuntime(
        commands=script.commands,
        labels=script.labels,
        screen=screen,
        assets=assets,
        save_path=save_dir / "quicksave.json",
        script_path=script_path,
        fps=fps,
        ui=ui,
        video_backend=video_backend,
        video_audio=video_audio,
        video_framedrop=video_framedrop,
        feature_script_paths=feature_script_paths,
        feature_flags=feature_flags,
    )

    if prefetch_scripts:
        runtime.prefetch_scripts(prefetch_scripts)

    try:
        runtime.run()
    except Exception as exc:
        print(f"Runtime error: {exc}")
    finally:
        pygame.quit()
