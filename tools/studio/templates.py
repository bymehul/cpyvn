from __future__ import annotations

import json
import re
from pathlib import Path


def slugify(name: str) -> str:
    text = re.sub(r"[^a-zA-Z0-9_-]+", "_", name.strip().lower())
    text = re.sub(r"_+", "_", text).strip("_")
    return text or "new_game"


def project_json(
    name: str,
    width: int,
    height: int,
    fps: int,
    resizable: bool,
    title_menu_enabled: bool,
    pause_menu_enabled: bool,
) -> str:
    payload = {
        "name": name,
        "debug": True,
        "entry": "script.cvn",
        "window": {
            "width": width,
            "height": height,
            "fps": fps,
            "resizable": bool(resizable),
        },
        "assets": {
            "bg": "assets/bg",
            "sprites": "assets/sprites",
            "audio": "assets/audio",
            "video": "assets/video",
        },
        "prefetch": "prefetch.json",
        "saves": "saves",
        "video_backend": "auto",
        "video_audio": True,
        "video_framedrop": "auto",
        "features": {
            "hud": {"use": False, "path": "hud.cvn"},
            "items": {"use": False, "path": "items.cvn"},
            "maps": {"use": False, "path": "maps.cvn"},
        },
        "ui": {
            "text_speed": 40,
            "box_opacity": 0.72,
            "font_size": 30,
            "name_font_size": 26,
            "choice_font_size": 28,
            "notify_font_size": 26,
            "show_perf": False,
            "title_menu_enabled": bool(title_menu_enabled),
            "title_menu_file": "title_menu.json",
            "pause_menu_enabled": bool(pause_menu_enabled),
            "pause_menu_file": "pause_menu.json",
            "pause_menu_slots": 9,
            "pause_menu_columns": 3,
            "call_auto_loading": True,
            "call_loading_text": "Loading next scene...",
            "call_loading_threshold_ms": 120,
            "call_loading_min_show_ms": 140,
        },
    }
    return json.dumps(payload, indent=2) + "\n"


def prefetch_json() -> str:
    payload = {"pin": [], "warm_scripts": []}
    return json.dumps(payload, indent=2) + "\n"


def script_cvn(game_name: str) -> str:
    return (
        "label start:\n"
        "    scene color #1f2430 fade 0.3;\n"
        f'    narrator "Welcome to {game_name}.";\n'
        '    narrator "Edit script.cvn and start building your VN.";\n'
    )


def title_menu_json(game_name: str) -> str:
    payload = {
        "title": game_name,
        "subtitle": "A cpyvn game",
        "background": {
            "kind": "color",
            "value": "#101827",
            "overlay_alpha": 120,
        },
        "layout": {
            "menu_x": 90,
            "menu_y": 220,
            "menu_width": 390,
            "button_height": 48,
            "button_gap": 10,
        },
        "buttons": [
            {"label": "New Game", "action": "new_game"},
            {"label": "Continue", "action": "continue"},
            {"label": "Load", "action": "open_load"},
            {"label": "Preferences", "action": "open_prefs"},
            {"label": "Quit", "action": "quit"},
        ],
    }
    return json.dumps(payload, indent=2) + "\n"


def pause_menu_json() -> str:
    payload = {
        "title": "Paused",
        "subtitle": "Session Menu",
        "panel_width": 620,
        "buttons": [
            {"label": "Resume", "action": "resume"},
            {"label": "Save", "action": "open_save"},
            {"label": "Load", "action": "open_load"},
            {"label": "Preferences", "action": "open_prefs"},
            {"label": "Quit", "action": "quit"},
        ],
    }
    return json.dumps(payload, indent=2) + "\n"


def create_project_tree(
    destination: Path,
    game_name: str,
    width: int,
    height: int,
    fps: int,
    resizable: bool,
    title_menu_enabled: bool,
    pause_menu_enabled: bool,
) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "assets" / "bg").mkdir(parents=True, exist_ok=True)
    (destination / "assets" / "sprites").mkdir(parents=True, exist_ok=True)
    (destination / "assets" / "audio").mkdir(parents=True, exist_ok=True)
    (destination / "assets" / "video").mkdir(parents=True, exist_ok=True)
    (destination / "saves").mkdir(parents=True, exist_ok=True)

    (destination / "project.json").write_text(
        project_json(
            name=game_name,
            width=width,
            height=height,
            fps=fps,
            resizable=resizable,
            title_menu_enabled=title_menu_enabled,
            pause_menu_enabled=pause_menu_enabled,
        ),
        encoding="utf-8",
    )
    (destination / "prefetch.json").write_text(prefetch_json(), encoding="utf-8")
    (destination / "script.cvn").write_text(script_cvn(game_name), encoding="utf-8")
    (destination / "title_menu.json").write_text(title_menu_json(game_name), encoding="utf-8")
    (destination / "pause_menu.json").write_text(pause_menu_json(), encoding="utf-8")
    for rel in [
        Path("assets") / "bg" / ".gitkeep",
        Path("assets") / "sprites" / ".gitkeep",
        Path("assets") / "audio" / ".gitkeep",
        Path("assets") / "video" / ".gitkeep",
    ]:
        (destination / rel).write_text("", encoding="utf-8")
