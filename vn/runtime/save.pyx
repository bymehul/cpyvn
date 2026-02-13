# cython: language_level=3
# cython: wraparound=False
# cython: boundscheck=False

import json
import os
import re
from pathlib import Path
from typing import Dict, Optional, List, Tuple, Any

import pygame

from ..script import CharacterDef, Choice
from .state import BackgroundState, HotspotArea, HudButton, SpriteInstance, SpriteState

SAVE_SCHEMA_VERSION = 2


class SaveMixin:
    def save_quick(self) -> None:
        cdef dict data = self._make_save_data()
        self.save_path.parent.mkdir(parents=True, exist_ok=True)
        self._write_json_atomic(self.save_path, data)

    def load_quick(self) -> None:
        if not self.save_path.exists():
            return
        cdef object raw
        cdef dict data
        try:
            raw = json.loads(self.save_path.read_text(encoding="utf-8"))
            data = raw if isinstance(raw, dict) else {}
        except (OSError, json.JSONDecodeError):
            return
        self._apply_save_data(data)

    def save_slot(self, str slot) -> None:
        cdef dict data = self._make_save_data()
        cdef object path = self._slot_path(slot)
        path.parent.mkdir(parents=True, exist_ok=True)
        self._write_json_atomic(path, data)

    def load_slot(self, str slot) -> None:
        cdef object path = self._slot_path(slot)
        if not path.exists():
            return
        cdef object raw
        cdef dict data
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            data = raw if isinstance(raw, dict) else {}
        except (OSError, json.JSONDecodeError):
            return
        self._apply_save_data(data)

    def _write_json_atomic(self, path: Path, data: dict) -> None:
        cdef object tmp_path = path.with_suffix(path.suffix + ".tmp")
        cdef str payload = json.dumps(data, indent=2)
        tmp_path.write_text(payload, encoding="utf-8")
        os.replace(tmp_path, path)

    def _serialize_script_path(self, path: Path) -> str:
        cdef object project_root = Path(self.assets.project_root).resolve()
        cdef object resolved = Path(path).resolve()
        try:
            return str(resolved.relative_to(project_root))
        except ValueError:
            return str(resolved)

    def _resolve_saved_script_path(self, raw: object) -> object:
        cdef object p
        if raw is None:
            return None
        p = Path(str(raw))
        if p.is_absolute():
            return p.resolve()
        return (Path(self.assets.project_root) / p).resolve()

    def _slot_path(self, str slot) -> Path:
        cdef str safe = re.sub(r"[^a-zA-Z0-9_-]+", "_", slot.strip())
        if not safe:
            safe = "slot"
        return self.save_path.parent / f"{safe}.json"

    def _make_save_data(self) -> dict:
        cdef dict sprites = {}
        cdef dict inventory_data = {}
        cdef dict meters_data = {}
        cdef list hud_buttons_data = []
        cdef list map_points_data = []
        cdef str name
        cdef object sprite
        cdef object st
        cdef object item
        cdef str item_id
        cdef str meter_id
        cdef object meter
        cdef object btn
        cdef object point
        cdef object btn_rect

        for name, sprite in self.sprites.items():
            st = sprite.state
            sprites[name] = {
                "kind": st.kind,
                "value": st.value,
                "size": st.size,
                "pos": st.pos,
                "anchor": st.anchor,
                "z": st.z,
                "float_amp": st.float_amp,
                "float_speed": st.float_speed,
                "rect": [sprite.rect.x, sprite.rect.y],
            }

        cdef object waiting = None
        cdef object timeout_elapsed_ms = None
        if self.current_choice is not None:
            if self.choice_timeout_ms is not None and self.choice_timer_start_ms is not None:
                timeout_elapsed_ms = max(0, pygame.time.get_ticks() - int(self.choice_timer_start_ms))
            waiting = {
                "type": "choice",
                "options": self.current_choice.options,
                "selected": self.choice_selected,
                "prompt": self.current_choice.prompt,
                "timeout_ms": self.choice_timeout_ms,
                "timeout_default": self.choice_timeout_default,
                "timeout_elapsed_ms": timeout_elapsed_ms,
            }
        elif self.current_say is not None:
            waiting = {
                "type": "say",
                "speaker": self.current_say[0],
                "text": self.current_say[1],
            }

        cdef object music = None
        if self.music_state:
            music = {"path": self.music_state[0], "loop": self.music_state[1]}

        cdef dict characters = {}
        cdef str ident
        cdef object character
        for ident, character in self.characters.items():
            characters[ident] = {
                "display_name": character.display_name,
                "color": character.color,
                "sprites": character.sprites or {},
                "voice_tag": character.voice_tag,
                "pos": list(character.pos) if character.pos else None,
                "anchor": character.anchor,
                "z": character.z,
                "float_amp": character.float_amp,
                "float_speed": character.float_speed,
            }

        cdef list hotspots_list = []
        cdef object hotspot
        cdef int x, y
        for hotspot in self.hotspots.values():
            hotspots_list.append({
                "name": hotspot.name,
                "points": [[int(x), int(y)] for x, y in hotspot.points],
                "target": hotspot.target,
            })

        for item_id, item in self.inventory.items():
            inventory_data[item_id] = {
                "name": str(item.get("name", "")),
                "desc": str(item.get("desc", "")),
                "icon": item.get("icon"),
                "count": int(item.get("count", 0)),
            }

        for meter_id, meter in self.meters.items():
            meters_data[meter_id] = {
                "label": meter.get("label"),
                "min": int(meter.get("min", 0)),
                "max": int(meter.get("max", 0)),
                "value": meter.get("value", 0),
                "color": str(meter.get("color", "#ffffff")),
            }

        for btn in self.hud_buttons.values():
            btn_rect = btn.rect
            hud_buttons_data.append(
                {
                    "name": btn.name,
                    "style": btn.style,
                    "text": btn.text,
                    "icon": btn.icon_path,
                    "target": btn.target,
                    "rect": [
                        int(btn_rect.x),
                        int(btn_rect.y),
                        int(btn_rect.width),
                        int(btn_rect.height),
                    ],
                }
            )

        for point in self.map_points:
            pos = point.get("pos", (0, 0))
            if not isinstance(pos, (list, tuple)) or len(pos) != 2:
                pos = (0, 0)
            map_points_data.append(
                {
                    "label": str(point.get("label", "")),
                    "target": str(point.get("target", "")),
                    "pos": [int(pos[0]), int(pos[1])],
                    "points": [
                        [int(coord[0]), int(coord[1])]
                        for coord in point.get("points", [])
                        if isinstance(coord, (tuple, list)) and len(coord) == 2
                    ],
                }
            )

        return {
            "save_version": SAVE_SCHEMA_VERSION,
            "script_path": self._serialize_script_path(self.current_script_path),
            "index": self.index,
            "background": {
                "kind": self.background_state.kind,
                "value": self.background_state.value,
                "float_amp": self.background_state.float_amp,
                "float_speed": self.background_state.float_speed,
            },
            "vars": self.variables,
            "sprites": sprites,
            "inventory": inventory_data,
            "inventory_page": int(self.inventory_page),
            "inventory_open": bool(self.inventory_active),
            "meters": meters_data,
            "hud_buttons": hud_buttons_data,
            "music": music,
            "waiting": waiting,
            "characters": characters,
            "hotspots": hotspots_list,
            "hotspot_debug": self.hotspot_debug,
            "map": {
                "active": bool(self.map_active),
                "image": self.map_image,
                "points": map_points_data,
            },
            "camera": {
                "pan_x": self.camera_pan_x,
                "pan_y": self.camera_pan_y,
                "zoom": self.camera_zoom,
            },
        }

    def _apply_save_data(self, dict data) -> None:
        cdef dict payload = data if isinstance(data, dict) else {}
        cdef int save_version = 1
        cdef object raw_version = payload.get("save_version", 1)
        cdef object saved_script_raw
        cdef object saved_script_path
        cdef object commands
        cdef object labels
        cdef object manifest
        cdef int saved_index = 0
        cdef dict bg
        cdef float float_amp_val
        cdef float float_speed_val
        cdef int float_pad
        cdef int screen_w
        cdef int screen_h
        cdef tuple target_size
        cdef dict vars_data
        cdef dict char_map
        cdef object char_data
        cdef str ident
        cdef object pos_data
        cdef tuple char_pos
        cdef int char_z
        cdef dict sprite_map
        cdef str name
        cdef object sprite_data
        cdef str kind
        cdef str value
        cdef object size
        cdef object pos
        cdef object sprite_anchor
        cdef int z
        cdef object surface
        cdef object rect_obj
        cdef object rect_data
        cdef list hotspots_data
        cdef object entry
        cdef str hs_name
        cdef str hs_target
        cdef object points_data_raw
        cdef list points
        cdef object point
        cdef int px
        cdef int py
        cdef int w
        cdef int h
        cdef bint malformed
        cdef dict inv_data
        cdef str item_id
        cdef object item_data
        cdef int item_count
        cdef dict meters_data
        cdef str meter_key
        cdef object meter_data
        cdef int meter_min
        cdef int meter_max
        cdef object meter_value
        cdef list hud_data
        cdef object btn
        cdef str btn_name
        cdef str btn_style
        cdef object btn_text
        cdef object btn_icon
        cdef str btn_target
        cdef object btn_rect
        cdef object icon_surface
        cdef dict map_data
        cdef object map_image
        cdef list map_points_data
        cdef object map_point
        cdef list map_points
        cdef tuple map_pos
        cdef dict camera_data
        cdef float c_pan_x = 0.0
        cdef float c_pan_y = 0.0
        cdef float c_zoom = 1.0
        cdef dict music_dict
        cdef dict waiting_dict
        cdef int timeout_saved
        cdef int timeout_elapsed
        cdef int selected_idx
        cdef object options
        cdef list normalized_options
        cdef object opt
        cdef object prompt

        try:
            save_version = int(raw_version)
        except (TypeError, ValueError):
            save_version = 1
        if save_version < 1:
            save_version = 1

        saved_script_raw = payload.get("script_path")
        saved_script_path = self._resolve_saved_script_path(saved_script_raw)
        if saved_script_path is not None and Path(saved_script_path).exists():
            try:
                commands, labels, manifest = self._load_script(Path(saved_script_path))
                self._prefetch_manifest_assets(manifest)
                self._prefetch_manifest_scripts(manifest)
                self.commands = commands
                self.labels = labels
                self.current_script_path = Path(saved_script_path).resolve()
                self.current_scene_manifest = manifest
            except Exception:
                pass

        try:
            saved_index = int(payload.get("index", 0))
        except (TypeError, ValueError):
            saved_index = 0
        if saved_index < 0:
            saved_index = 0
        if saved_index > len(self.commands):
            saved_index = len(self.commands)
        self.index = saved_index

        self.current_choice = None
        self.current_say = None
        self.say_start_ms = None
        self.say_reveal_all = False
        self.choice_hitboxes = []
        self.choice_selected = 0
        self.choice_timer_start_ms = None
        self.choice_timeout_ms = None
        self.choice_timeout_default = None
        self.wait_until_ms = None
        self.wait_for_voice = False
        self.wait_for_video = False
        self.notify_message = None
        self.notify_until_ms = None
        self.input_active = False
        self.input_variable = None
        self.input_prompt = None
        self.input_buffer = ""
        self.input_cursor = 0
        self._stop_video()

        bg = payload.get("background") if isinstance(payload.get("background"), dict) else {}
        float_amp_val = 0.0
        float_speed_val = 0.0
        if bg:
            try:
                float_amp_val = float(bg.get("float_amp") or 0.0)
            except (TypeError, ValueError):
                float_amp_val = 0.0
            try:
                float_speed_val = float(bg.get("float_speed") or 0.0)
            except (TypeError, ValueError):
                float_speed_val = 0.0

            self.background_state = BackgroundState(
                str(bg.get("kind", "color")),
                str(bg.get("value", "#000000")),
                float_amp=float_amp_val if bg.get("float_amp") is not None else None,
                float_speed=float_speed_val if bg.get("float_speed") is not None else None,
            )

            screen_w, screen_h = self.screen.get_size()
            float_pad = int(abs(float_amp_val)) if float_amp_val else 0
            target_size = (screen_w + float_pad * 2, screen_h + float_pad * 2)
            try:
                if self.background_state.kind == "color":
                    self.background_surface = self.assets.make_color_surface(self.background_state.value, target_size)
                else:
                    surface = self.assets.load_image(self.background_state.value, "bg")
                    self.background_surface = pygame.transform.smoothscale(surface, target_size)
            except Exception:
                self.background_state = BackgroundState("color", "#000000")
                self.background_surface = self.assets.make_color_surface("#000000")

        vars_data = payload.get("vars") if isinstance(payload.get("vars"), dict) else {}
        self.variables = dict(vars_data)

        char_map = payload.get("characters") if isinstance(payload.get("characters"), dict) else {}
        self.characters.clear()
        for ident, char_data in char_map.items():
            if not isinstance(char_data, dict):
                continue
            pos_data = char_data.get("pos")
            char_pos = None
            if isinstance(pos_data, (list, tuple)) and len(pos_data) == 2:
                try:
                    char_pos = (int(pos_data[0]), int(pos_data[1]))
                except (TypeError, ValueError):
                    char_pos = None
            try:
                char_z = int(char_data.get("z", 0))
            except (TypeError, ValueError):
                char_z = 0
            self.characters[str(ident)] = CharacterDef(
                ident=str(ident),
                display_name=char_data.get("display_name"),
                color=char_data.get("color"),
                sprites=char_data.get("sprites") or {},
                voice_tag=char_data.get("voice_tag"),
                pos=char_pos,
                anchor=char_data.get("anchor"),
                z=char_z,
                float_amp=char_data.get("float_amp"),
                float_speed=char_data.get("float_speed"),
            )

        self.sprites.clear()
        self.sprite_animations.clear()
        sprite_map = payload.get("sprites") if isinstance(payload.get("sprites"), dict) else {}
        for name, sprite_data in sprite_map.items():
            if not isinstance(sprite_data, dict):
                continue
            kind = str(sprite_data.get("kind", "image"))
            value = str(sprite_data.get("value", ""))
            size = None
            if isinstance(sprite_data.get("size"), (list, tuple)) and len(sprite_data.get("size")) == 2:
                try:
                    size = (int(sprite_data.get("size")[0]), int(sprite_data.get("size")[1]))
                except (TypeError, ValueError):
                    size = None
            pos = None
            if isinstance(sprite_data.get("pos"), (list, tuple)) and len(sprite_data.get("pos")) == 2:
                try:
                    pos = (int(sprite_data.get("pos")[0]), int(sprite_data.get("pos")[1]))
                except (TypeError, ValueError):
                    pos = None
            sprite_anchor = sprite_data.get("anchor")
            try:
                z = int(sprite_data.get("z", 0))
            except (TypeError, ValueError):
                z = 0

            try:
                if kind == "rect" and size:
                    surface = self.assets.make_rect_surface(value, size)
                else:
                    surface = self.assets.load_image(value, "sprites")
                    if size:
                        surface = pygame.transform.smoothscale(surface, size)
            except Exception:
                continue

            rect_obj = surface.get_rect()
            rect_data = sprite_data.get("rect")
            if isinstance(rect_data, (list, tuple)) and len(rect_data) == 2:
                try:
                    rect_obj.x = int(rect_data[0])
                    rect_obj.y = int(rect_data[1])
                except (TypeError, ValueError):
                    pass
            elif pos:
                rect_obj.topleft = pos
            else:
                rect_obj.centerx = self.screen.get_width() // 2
                rect_obj.bottom = self.screen.get_height() - self.textbox.box_height - 20

            self.sprites[str(name)] = SpriteInstance(
                state=SpriteState(
                    kind,
                    value,
                    size,
                    pos,
                    sprite_anchor,
                    z,
                    float_amp=sprite_data.get("float_amp"),
                    float_speed=sprite_data.get("float_speed"),
                    float_phase=self._float_phase_for(str(name)),
                ),
                surface=surface,
                rect=rect_obj,
            )

        self.hotspots.clear()
        self.hotspot_hovered = None
        hotspots_data = payload.get("hotspots") if isinstance(payload.get("hotspots"), list) else []
        for entry in hotspots_data:
            if not isinstance(entry, dict):
                continue
            hs_name = str(entry.get("name", "")).strip()
            hs_target = str(entry.get("target", "")).strip()
            points_data_raw = entry.get("points")
            if points_data_raw is None and isinstance(entry.get("rect"), list) and len(entry.get("rect")) == 4:
                try:
                    px, py, w, h = [int(v) for v in entry.get("rect")]
                    if w > 0 and h > 0:
                        points_data_raw = [[px, py], [px + w, py], [px + w, py + h], [px, py + h]]
                except (TypeError, ValueError):
                    points_data_raw = None
            if not hs_name or not hs_target or not isinstance(points_data_raw, list):
                continue
            points = []
            malformed = False
            for point in points_data_raw:
                if not isinstance(point, (list, tuple)) or len(point) != 2:
                    malformed = True
                    break
                try:
                    px = int(point[0])
                    py = int(point[1])
                    points.append((px, py))
                except (TypeError, ValueError):
                    malformed = True
                    break
            if not malformed and len(points) >= 3:
                self.hotspots[hs_name] = HotspotArea(name=hs_name, points=points, target=hs_target)
        self.hotspot_debug = bool(payload.get("hotspot_debug", False))

        inv_data = payload.get("inventory") if isinstance(payload.get("inventory"), dict) else {}
        self.inventory.clear()
        for item_id, item_data in inv_data.items():
            if not isinstance(item_data, dict):
                continue
            try:
                item_count = int(item_data.get("count", 0))
            except (TypeError, ValueError):
                item_count = 0
            if item_count <= 0:
                continue
            self.inventory[str(item_id)] = {
                "name": str(item_data.get("name", "")),
                "desc": str(item_data.get("desc", "")),
                "icon": item_data.get("icon"),
                "count": item_count,
            }
        try:
            self.inventory_page = int(payload.get("inventory_page", 0))
        except (TypeError, ValueError):
            self.inventory_page = 0
        self.inventory_active = bool(payload.get("inventory_open", False))
        self.inventory_hovered = None
        self.inventory_slots = []
        self.inventory_panel_rect = None
        self._clamp_inventory_page()

        meters_data = payload.get("meters") if isinstance(payload.get("meters"), dict) else {}
        self.meters.clear()
        for meter_key, meter_data in meters_data.items():
            if not isinstance(meter_data, dict):
                continue
            try:
                meter_min = int(meter_data.get("min", 0))
            except (TypeError, ValueError):
                meter_min = 0
            try:
                meter_max = int(meter_data.get("max", 0))
            except (TypeError, ValueError):
                meter_max = 0
            meter_value = meter_data.get("value", 0)
            if not isinstance(meter_value, (int, float)):
                meter_value = 0
            self.meters[str(meter_key)] = {
                "label": meter_data.get("label"),
                "min": meter_min,
                "max": meter_max,
                "value": meter_value,
                "color": str(meter_data.get("color", "#ffffff")),
            }

        hud_data = payload.get("hud_buttons") if isinstance(payload.get("hud_buttons"), list) else []
        self.hud_buttons.clear()
        self.hud_hovered = None
        for btn in hud_data:
            if not isinstance(btn, dict):
                continue
            btn_name = str(btn.get("name", "")).strip()
            if not btn_name:
                continue
            btn_style = str(btn.get("style", "text")).strip().lower()
            if btn_style not in {"text", "icon", "both"}:
                btn_style = "text"
            btn_text = btn.get("text")
            btn_icon = btn.get("icon")
            btn_target = str(btn.get("target", "")).strip() or "::start"
            btn_rect = btn.get("rect")
            if not isinstance(btn_rect, (list, tuple)) or len(btn_rect) != 4:
                continue
            try:
                px = int(btn_rect[0])
                py = int(btn_rect[1])
                w = max(1, int(btn_rect[2]))
                h = max(1, int(btn_rect[3]))
            except (TypeError, ValueError):
                continue
            icon_surface = None
            if btn_icon is not None:
                try:
                    icon_surface = self.assets.load_image(str(btn_icon), "sprites")
                    icon_surface = pygame.transform.smoothscale(icon_surface, (w, h))
                except Exception:
                    icon_surface = None
            self.hud_buttons[btn_name] = HudButton(
                name=btn_name,
                style=btn_style,
                text=btn_text,
                icon_path=btn_icon,
                icon_surface=icon_surface,
                rect=pygame.Rect(px, py, w, h),
                target=btn_target,
            )

        self.map_active = False
        self.map_image = None
        self.map_points = []
        self.map_hovered = None
        map_data = payload.get("map") if isinstance(payload.get("map"), dict) else {}
        if map_data:
            map_image = map_data.get("image")
            if isinstance(map_image, str) and map_image.strip():
                self.map_image = map_image.strip()
            map_points_data = map_data.get("points") if isinstance(map_data.get("points"), list) else []
            for map_point in map_points_data:
                if not isinstance(map_point, dict):
                    continue
                hs_name = str(map_point.get("label", "POI"))
                hs_target = str(map_point.get("target", "::start"))
                map_points = []
                points_data_raw = map_point.get("points")
                if isinstance(points_data_raw, list):
                    for point in points_data_raw:
                        if not isinstance(point, (list, tuple)) or len(point) != 2:
                            continue
                        try:
                            map_points.append((int(point[0]), int(point[1])))
                        except (TypeError, ValueError):
                            continue
                pos_data = map_point.get("pos")
                if isinstance(pos_data, (list, tuple)) and len(pos_data) == 2:
                    try:
                        map_pos = (int(pos_data[0]), int(pos_data[1]))
                    except (TypeError, ValueError):
                        map_pos = map_points[0] if map_points else (0, 0)
                else:
                    map_pos = map_points[0] if map_points else (0, 0)
                self.map_points.append(
                    {
                        "label": hs_name,
                        "target": hs_target,
                        "pos": map_pos,
                        "points": map_points,
                    }
                )
            self.map_active = bool(map_data.get("active", False) and self.map_image)

        camera_data = payload.get("camera", {}) if isinstance(payload.get("camera"), dict) else {}
        try:
            c_pan_x = float(camera_data.get("pan_x", 0.0))
            c_pan_y = float(camera_data.get("pan_y", 0.0))
            c_zoom = float(camera_data.get("zoom", 1.0))
        except (TypeError, ValueError):
            c_pan_x = 0.0
            c_pan_y = 0.0
            c_zoom = 1.0
        self.camera_pan_x = c_pan_x
        self.camera_pan_y = c_pan_y
        self.camera_zoom = max(0.1, min(8.0, c_zoom))

        music_dict = payload.get("music") if isinstance(payload.get("music"), dict) else {}
        if music_dict and music_dict.get("path"):
            self.music_state = (str(music_dict["path"]), bool(music_dict.get("loop", True)))
            self.assets.play_music(self.music_state[0], self.music_state[1])
        else:
            self.music_state = None
            try:
                pygame.mixer.music.stop()
            except pygame.error:
                pass

        waiting_dict = payload.get("waiting") if isinstance(payload.get("waiting"), dict) else {}
        if waiting_dict:
            if waiting_dict.get("type") == "choice":
                options = waiting_dict.get("options", [])
                normalized_options = []
                if isinstance(options, list):
                    for opt in options:
                        if not isinstance(opt, (list, tuple)) or len(opt) != 2:
                            continue
                        normalized_options.append((str(opt[0]), str(opt[1])))
                prompt = waiting_dict.get("prompt")
                self.current_choice = Choice(options=normalized_options, prompt=prompt)
                try:
                    selected_idx = int(waiting_dict.get("selected", 0))
                except (TypeError, ValueError):
                    selected_idx = 0
                if self.current_choice.options:
                    self.choice_selected = max(0, min(len(self.current_choice.options) - 1, selected_idx))
                else:
                    self.choice_selected = 0
                self.choice_timer_start_ms = None
                self.choice_timeout_ms = None
                self.choice_timeout_default = None
                try:
                    timeout_saved = int(waiting_dict.get("timeout_ms"))
                except (TypeError, ValueError):
                    timeout_saved = 0
                if timeout_saved > 0:
                    self.choice_timeout_ms = timeout_saved
                    try:
                        self.choice_timeout_default = int(waiting_dict.get("timeout_default"))
                    except (TypeError, ValueError):
                        self.choice_timeout_default = None
                    try:
                        timeout_elapsed = int(waiting_dict.get("timeout_elapsed_ms", 0))
                    except (TypeError, ValueError):
                        timeout_elapsed = 0
                    self.choice_timer_start_ms = pygame.time.get_ticks() - max(0, timeout_elapsed)
            elif waiting_dict.get("type") == "say":
                self.current_say = (
                    waiting_dict.get("speaker"),
                    str(waiting_dict.get("text", "")),
                )
                self.say_start_ms = pygame.time.get_ticks()
                self.say_reveal_all = True

        # Old saves (v1) did not store script_path and extended UI/runtime state.
        if save_version <= 1 and "script_path" not in payload:
            pass

        if self.current_choice is None and self.current_say is None and not self.map_active:
            self._step()
