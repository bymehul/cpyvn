# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False

from __future__ import annotations

import json
from pathlib import Path

import pygame

from .state import BackgroundState


class TitleMenuMixin:
    def _title_menu_init(self, ui) -> None:
        cdef object cfg_name = getattr(ui, "title_menu_file", "")
        cdef object root = Path(self._project_root)
        cdef object cfg_path
        self.title_menu_enabled = bool(getattr(ui, "title_menu_enabled", False))
        self.title_menu_active = self.title_menu_enabled
        self.title_menu_view = "main"  # main | load | prefs
        self.title_menu_selected = 0
        self.title_menu_hover = None
        self.title_menu_buttons = []
        self.title_menu_status = ""
        self.title_menu_status_kind = "ok"
        self.title_menu_status_until_ms = None
        self.title_menu_pref_index = 0
        self.title_menu_started_game = False
        self.title_menu_logo_cache = {}
        self.title_menu_cfg = self._title_menu_default_config()

        if cfg_name:
            cfg_path = (root / str(cfg_name)).resolve()
        else:
            cfg_path = (root / "title_menu.json").resolve()
        self.title_menu_config_path = cfg_path
        if cfg_path.exists():
            self._title_menu_load_config(cfg_path)

        self.title_menu_title_font = pygame.font.Font(None, int(self.title_menu_cfg.get("title_font_size", 68)))
        self.title_menu_subtitle_font = pygame.font.Font(None, int(self.title_menu_cfg.get("subtitle_font_size", 26)))
        self.title_menu_item_font = pygame.font.Font(None, int(self.title_menu_cfg.get("item_font_size", 36)))
        self.title_menu_meta_font = pygame.font.Font(None, int(self.title_menu_cfg.get("meta_font_size", 22)))

    def _title_menu_default_config(self) -> dict:
        return {
            "title": "cpyvn",
            "subtitle": "Script-first visual novel engine",
            "title_font_size": 68,
            "subtitle_font_size": 26,
            "item_font_size": 36,
            "meta_font_size": 22,
            "background": {
                "kind": "image",  # image | color
                "value": "witches_library.png",
                "asset_kind": "bg",
                "overlay_alpha": 120,
            },
            "layout": {
                "menu_x": 90,
                "menu_y": 220,
                "menu_width": 360,
                "button_height": 46,
                "button_gap": 10,
            },
            "colors": {
                "title": [245, 247, 255, 255],
                "subtitle": [195, 205, 228, 255],
                "item": [236, 239, 248, 255],
                "item_selected": [255, 216, 112, 255],
                "item_disabled": [132, 142, 164, 255],
                "panel": [20, 24, 34, 232],
                "panel_border": [100, 120, 156, 255],
                "overlay": [4, 8, 15, 120],
                "slot": [34, 39, 52, 210],
                "slot_border": [98, 112, 140, 255],
                "slot_filled": [58, 78, 114, 210],
                "meta": [172, 182, 205, 255],
                "ok": [130, 220, 150, 255],
                "warn": [255, 189, 120, 255],
            },
            "buttons": [
                {"label": "New Game", "action": "new_game"},
                {"label": "Continue", "action": "continue"},
                {"label": "Load", "action": "open_load"},
                {"label": "Preferences", "action": "open_prefs"},
                {"label": "Quit", "action": "quit"},
            ],
            "logos": [],
            "load_rows": 3,
            "load_cols": 3,
        }

    def _title_menu_merge_dict(self, base: dict, override: dict) -> dict:
        cdef dict out = dict(base)
        cdef object key
        cdef object value
        cdef object current
        for key, value in override.items():
            if isinstance(value, dict):
                current = out.get(key)
                if isinstance(current, dict):
                    out[key] = self._title_menu_merge_dict(current, value)
                else:
                    out[key] = self._title_menu_merge_dict({}, value)
            else:
                out[key] = value
        return out

    def _title_menu_load_config(self, path: Path) -> None:
        cdef object raw
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return
        if not isinstance(raw, dict):
            return
        self.title_menu_cfg = self._title_menu_merge_dict(self.title_menu_cfg, raw)

    def _title_menu_color(self, str key, tuple fallback) -> tuple:
        cdef object colors = self.title_menu_cfg.get("colors", {})
        cdef object value
        cdef int r
        cdef int g
        cdef int b
        cdef int a
        if not isinstance(colors, dict):
            return fallback
        value = colors.get(key)
        if not isinstance(value, (list, tuple)) or len(value) < 3:
            return fallback
        try:
            r = max(0, min(255, int(value[0])))
            g = max(0, min(255, int(value[1])))
            b = max(0, min(255, int(value[2])))
            if len(value) >= 4:
                a = max(0, min(255, int(value[3])))
                return (r, g, b, a)
            return (r, g, b)
        except (TypeError, ValueError):
            return fallback

    def _title_menu_actions(self) -> list:
        cdef list out = []
        cdef object item
        cdef str label
        cdef str action
        for item in self.title_menu_cfg.get("buttons", []):
            if not isinstance(item, dict):
                continue
            label = str(item.get("label", "")).strip()
            action = str(item.get("action", "")).strip().lower()
            if not label or not action:
                continue
            out.append((label, action))
        if out:
            return out
        return [
            ("New Game", "new_game"),
            ("Continue", "continue"),
            ("Load", "open_load"),
            ("Preferences", "open_prefs"),
            ("Quit", "quit"),
        ]

    def _title_menu_set_status(self, text: str, bint ok=True, int ms=1800) -> None:
        self.title_menu_status = text
        self.title_menu_status_kind = "ok" if ok else "warn"
        self.title_menu_status_until_ms = pygame.time.get_ticks() + max(200, ms)

    def _title_menu_has_continue(self) -> bool:
        cdef object p
        cdef object path
        if self.save_path.exists():
            return True
        for p in self.pause_menu_slots:
            path = self._slot_path(str(p))
            if path.exists():
                return True
        return False

    def _title_menu_open(self, str view="main") -> None:
        if not self.title_menu_enabled:
            return
        self.title_menu_active = True
        self.title_menu_view = view if view in {"main", "load", "prefs"} else "main"
        self.title_menu_selected = 0
        self.title_menu_pref_index = 0
        self.title_menu_hover = None
        self.pause_menu_active = False

    def _title_menu_close(self) -> None:
        self.title_menu_active = False
        self.title_menu_view = "main"
        self.title_menu_buttons = []
        self.title_menu_hover = None

    def _title_menu_reset_runtime_for_new_game(self) -> None:
        self.assets.mute("all")
        self._stop_video()
        self.music_state = None
        self.current_choice = None
        self.current_say = None
        self.choice_selected = 0
        self.choice_hitboxes = []
        self.choice_timer_start_ms = None
        self.choice_timeout_ms = None
        self.choice_timeout_default = None
        self.say_start_ms = None
        self.say_reveal_all = False
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
        self.phone_active = False
        self.phone_contact = None
        self.phone_messages = []
        self.loading_active = False
        self.loading_auto_continue = False
        self.sprites.clear()
        self.sprite_animations.clear()
        self.hotspots.clear()
        self.hotspot_hovered = None
        self.hud_buttons.clear()
        self.hud_hovered = None
        self.inventory.clear()
        self.inventory_active = False
        self.inventory_page = 0
        self.inventory_hovered = None
        self.meters.clear()
        self.map_active = False
        self.map_image = None
        self.map_points = []
        self.map_hovered = None
        self.camera_pan_x = 0.0
        self.camera_pan_y = 0.0
        self.camera_zoom = 1.0
        self.variables.clear()
        self.characters.clear()
        self.background_state = BackgroundState("color", "#000000")
        self.background_surface = self.assets.make_color_surface("#000000")
        self.index = 0

    def _title_menu_start_new_game(self) -> None:
        self._title_menu_reset_runtime_for_new_game()
        self._title_menu_close()
        self.title_menu_started_game = True
        self._step()

    def _title_menu_continue_game(self) -> None:
        cdef object newest_path = None
        cdef float newest_mtime = -1.0
        cdef object slot_id
        cdef object p
        cdef float mt
        if self.save_path.exists():
            self.load_quick()
            self._title_menu_close()
            self.title_menu_started_game = True
            return
        for slot_id in self.pause_menu_slots:
            p = self._slot_path(str(slot_id))
            if not p.exists():
                continue
            mt = float(p.stat().st_mtime)
            if mt > newest_mtime:
                newest_mtime = mt
                newest_path = p
        if newest_path is None:
            self._title_menu_set_status("No save data found.", ok=False)
            return
        try:
            self.load_slot(Path(newest_path).stem)
            self._title_menu_close()
            self.title_menu_started_game = True
        except Exception:
            self._title_menu_set_status("Failed to load save.", ok=False)

    def _title_menu_execute_action(self, action: str) -> None:
        cdef str act = str(action).strip().lower()
        if act == "new_game":
            self._title_menu_start_new_game()
            return
        if act == "continue":
            self._title_menu_continue_game()
            return
        if act in {"open_load", "load"}:
            self.title_menu_view = "load"
            self.title_menu_selected = 0
            return
        if act in {"open_prefs", "preferences"}:
            self.title_menu_view = "prefs"
            self.title_menu_pref_index = 0
            return
        if act == "save_prefs":
            self._pause_menu_save_prefs()
            self._title_menu_set_status("Preferences saved.", ok=True)
            return
        if act in {"back", "main"}:
            self.title_menu_view = "main"
            self.title_menu_selected = 0
            return
        if act == "quick_load":
            if self.save_path.exists():
                self.load_quick()
                self._title_menu_close()
                self.title_menu_started_game = True
            else:
                self._title_menu_set_status("No quicksave found.", ok=False)
            return
        if act == "quit":
            self.running = False

    def _title_menu_load_slot(self, str slot_id) -> None:
        cdef object path = self._slot_path(slot_id)
        if not path.exists():
            self._title_menu_set_status(f"Slot empty: {slot_id}", ok=False)
            return
        self.load_slot(slot_id)
        self._title_menu_close()
        self.title_menu_started_game = True

    def _title_menu_logo_surface(self, str path, str asset_kind, int w, int h):
        cdef tuple key = (path, asset_kind, w, h)
        cdef object surf
        surf = self.title_menu_logo_cache.get(key)
        if surf is not None:
            return surf
        try:
            surf = self.assets.load_image(path, asset_kind)
        except Exception:
            return None
        if surf is None:
            return None
        if w > 0 and h > 0 and (surf.get_width() != w or surf.get_height() != h):
            surf = pygame.transform.smoothscale(surf, (w, h))
        self.title_menu_logo_cache[key] = surf
        return surf

    def _draw_title_menu_logos(self) -> None:
        cdef object logos = self.title_menu_cfg.get("logos", [])
        cdef object item
        cdef str path
        cdef str asset_kind
        cdef int x
        cdef int y
        cdef int w
        cdef int h
        cdef int alpha
        cdef str anchor
        cdef object surf
        cdef object draw
        cdef object rect
        if not isinstance(logos, list):
            return
        for item in logos:
            if not isinstance(item, dict):
                continue
            path = str(item.get("path", "")).strip()
            if not path:
                continue
            asset_kind = str(item.get("asset_kind", "sprites")).strip() or "sprites"
            try:
                x = int(item.get("x", 0))
                y = int(item.get("y", 0))
                w = int(item.get("w", 0))
                h = int(item.get("h", 0))
                alpha = max(0, min(255, int(item.get("alpha", 255))))
            except (TypeError, ValueError):
                continue
            anchor = str(item.get("anchor", "topleft")).strip().lower()
            surf = self._title_menu_logo_surface(path, asset_kind, w, h)
            if surf is None:
                continue
            draw = surf
            if alpha < 255:
                draw = surf.copy()
                draw.set_alpha(alpha)
            rect = draw.get_rect()
            if anchor == "center":
                rect.center = (x, y)
            elif anchor == "topright":
                rect.topright = (x, y)
            elif anchor == "bottomleft":
                rect.bottomleft = (x, y)
            elif anchor == "bottomright":
                rect.bottomright = (x, y)
            else:
                rect.topleft = (x, y)
            self.screen.blit(draw, rect.topleft)

    def _draw_title_menu(self) -> None:
        cdef int sw = self.screen.get_width()
        cdef int sh = self.screen.get_height()
        cdef object bg_cfg = self.title_menu_cfg.get("background", {})
        cdef str bg_kind = "image"
        cdef str bg_value = ""
        cdef str asset_kind = "bg"
        cdef int overlay_alpha = 120
        cdef object surface
        cdef object overlay
        cdef tuple title_color
        cdef tuple subtitle_color
        cdef tuple status_color
        cdef object title_surf
        cdef object subtitle_surf
        cdef object status_surf
        cdef int now = pygame.time.get_ticks()
        if isinstance(bg_cfg, dict):
            bg_kind = str(bg_cfg.get("kind", "image")).strip().lower()
            bg_value = str(bg_cfg.get("value", "")).strip()
            asset_kind = str(bg_cfg.get("asset_kind", "bg")).strip().lower() or "bg"
            try:
                overlay_alpha = max(0, min(255, int(bg_cfg.get("overlay_alpha", 120))))
            except (TypeError, ValueError):
                overlay_alpha = 120

        if bg_kind == "color":
            self.screen.fill(pygame.Color(bg_value or "#10141f"))
        else:
            try:
                surface = self.assets.load_image(bg_value, asset_kind)
                if surface.get_size() != (sw, sh):
                    surface = pygame.transform.smoothscale(surface, (sw, sh))
                self.screen.blit(surface, (0, 0))
            except Exception:
                self.screen.fill((16, 20, 31))

        overlay = pygame.Surface((sw, sh), pygame.SRCALPHA)
        overlay.fill((self._title_menu_color("overlay", (4, 8, 15, 120))[0], self._title_menu_color("overlay", (4, 8, 15, 120))[1], self._title_menu_color("overlay", (4, 8, 15, 120))[2], overlay_alpha))
        self.screen.blit(overlay, (0, 0))
        self._draw_title_menu_logos()

        title_color = self._title_menu_color("title", (245, 247, 255))
        subtitle_color = self._title_menu_color("subtitle", (195, 205, 228))
        title_surf = self.title_menu_title_font.render(str(self.title_menu_cfg.get("title", "cpyvn")), True, title_color[:3])
        subtitle_surf = self.title_menu_subtitle_font.render(str(self.title_menu_cfg.get("subtitle", "")), True, subtitle_color[:3])
        self.screen.blit(title_surf, (80, 76))
        self.screen.blit(subtitle_surf, (84, 76 + title_surf.get_height() + 8))

        self.title_menu_buttons = []
        if self.title_menu_view == "main":
            self._draw_title_menu_main(sw, sh)
        elif self.title_menu_view == "load":
            self._draw_title_menu_load(sw, sh)
        else:
            self._draw_title_menu_prefs(sw, sh)

        if self.title_menu_status and self.title_menu_status_until_ms is not None and now <= self.title_menu_status_until_ms:
            status_color = self._title_menu_color("ok", (130, 220, 150))
            if self.title_menu_status_kind == "warn":
                status_color = self._title_menu_color("warn", (255, 189, 120))
            status_surf = self.title_menu_meta_font.render(self.title_menu_status, True, status_color[:3])
            self.screen.blit(status_surf, (84, sh - status_surf.get_height() - 24))

    def _draw_title_menu_main(self, int sw, int sh) -> None:
        cdef object layout = self.title_menu_cfg.get("layout", {})
        cdef int x = 90
        cdef int y = 220
        cdef int w = 360
        cdef int h = 46
        cdef int gap = 10
        cdef list actions = self._title_menu_actions()
        cdef int i
        cdef str label
        cdef str action
        cdef object rect
        cdef bint selected
        cdef bint disabled
        cdef object text_surf
        cdef tuple selected_color = self._title_menu_color("item_selected", (255, 216, 112))
        cdef tuple normal_color = self._title_menu_color("item", (236, 239, 248))
        cdef tuple disabled_color = self._title_menu_color("item_disabled", (132, 142, 164))
        cdef tuple panel_color = self._title_menu_color("panel", (20, 24, 34, 232))
        cdef tuple panel_border = self._title_menu_color("panel_border", (100, 120, 156, 255))
        if isinstance(layout, dict):
            try:
                x = int(layout.get("menu_x", x))
                y = int(layout.get("menu_y", y))
                w = int(layout.get("menu_width", w))
                h = int(layout.get("button_height", h))
                gap = int(layout.get("button_gap", gap))
            except (TypeError, ValueError):
                pass

        for i, (label, action) in enumerate(actions):
            rect = pygame.Rect(x, y + i * (h + gap), w, h)
            selected = (self.title_menu_selected == i) or (self.title_menu_hover == ("action", action))
            disabled = (action == "continue" and not self._title_menu_has_continue())
            if selected:
                pygame.draw.rect(self.screen, panel_color, rect, border_radius=7)
                pygame.draw.rect(self.screen, panel_border[:3], rect, 1, border_radius=7)
            text_surf = self.title_menu_item_font.render(
                label,
                True,
                (disabled_color if disabled else (selected_color if selected else normal_color))[:3],
            )
            self.screen.blit(text_surf, (rect.x + 12, rect.y + (rect.height - text_surf.get_height()) // 2))
            self.title_menu_buttons.append(("action", action, rect, disabled))

    def _draw_title_menu_load(self, int sw, int sh) -> None:
        cdef int panel_w = min(sw - 120, 860)
        cdef int panel_h = min(sh - 140, 560)
        cdef int px = (sw - panel_w) // 2
        cdef int py = (sh - panel_h) // 2
        cdef int cols = max(1, int(self.title_menu_cfg.get("load_cols", 3)))
        cdef int rows = max(1, int(self.title_menu_cfg.get("load_rows", 3)))
        cdef int total_slots = min(len(self.pause_menu_slots), cols * rows)
        cdef int grid_w = panel_w - 56
        cdef int grid_h = panel_h - 126
        cdef int gap = 10
        cdef int slot_w = max(120, (grid_w - ((cols - 1) * gap)) // cols)
        cdef int slot_h = max(84, (grid_h - ((rows - 1) * gap)) // rows)
        cdef int grid_x = px + (panel_w - (cols * slot_w + (cols - 1) * gap)) // 2
        cdef int grid_y = py + 66
        cdef int i
        cdef int c
        cdef int r
        cdef int sx
        cdef int sy
        cdef object rect
        cdef str slot_id
        cdef dict summary
        cdef object title_surf
        cdef object meta_surf
        cdef object extra_surf
        cdef bint selected
        cdef int selected_index = self.title_menu_selected
        cdef object back_rect

        pygame.draw.rect(self.screen, self._title_menu_color("panel", (20, 24, 34, 232)), (px, py, panel_w, panel_h), border_radius=10)
        pygame.draw.rect(self.screen, self._title_menu_color("panel_border", (100, 120, 156, 255))[:3], (px, py, panel_w, panel_h), 2, border_radius=10)
        title_surf = self.title_menu_item_font.render("Load Game", True, self._title_menu_color("item", (236, 239, 248))[:3])
        self.screen.blit(title_surf, (px + (panel_w - title_surf.get_width()) // 2, py + 18))

        for i in range(total_slots):
            c = i % cols
            r = i // cols
            sx = grid_x + c * (slot_w + gap)
            sy = grid_y + r * (slot_h + gap)
            rect = pygame.Rect(sx, sy, slot_w, slot_h)
            slot_id = str(self.pause_menu_slots[i])
            summary = self._pause_menu_slot_summary(slot_id)
            selected = (selected_index == i) or (self.title_menu_hover == ("slot", slot_id))
            if summary.get("exists"):
                pygame.draw.rect(self.screen, self._title_menu_color("slot_filled", (58, 78, 114, 210)), rect, border_radius=8)
            else:
                pygame.draw.rect(self.screen, self._title_menu_color("slot", (34, 39, 52, 210)), rect, border_radius=8)
            pygame.draw.rect(
                self.screen,
                (self._title_menu_color("item_selected", (255, 216, 112)) if selected else self._title_menu_color("slot_border", (98, 112, 140, 255)))[:3],
                rect,
                2 if selected else 1,
                border_radius=8,
            )
            title_surf = self.title_menu_item_font.render(slot_id, True, self._title_menu_color("item", (236, 239, 248))[:3])
            self.screen.blit(title_surf, (sx + 10, sy + 8))
            if summary.get("exists"):
                meta_surf = self.title_menu_meta_font.render(str(summary.get("script_path", "-")), True, self._title_menu_color("meta", (172, 182, 205))[:3])
                extra_surf = self.title_menu_meta_font.render(
                    f"bg:{summary.get('bg_value', '-')} inv:{summary.get('inventory_count', 0)} vars:{summary.get('vars_count', 0)}",
                    True,
                    self._title_menu_color("meta", (172, 182, 205))[:3],
                )
                self.screen.blit(meta_surf, (sx + 10, sy + 38))
                self.screen.blit(extra_surf, (sx + 10, sy + 60))
            else:
                meta_surf = self.title_menu_meta_font.render("Empty", True, self._title_menu_color("meta", (172, 182, 205))[:3])
                self.screen.blit(meta_surf, (sx + 10, sy + 44))
            self.title_menu_buttons.append(("slot", slot_id, rect, not bool(summary.get("exists"))))

        back_rect = pygame.Rect(px + (panel_w - 220) // 2, py + panel_h - 46, 220, 30)
        selected = (selected_index == total_slots) or (self.title_menu_hover == ("action", "main"))
        if selected:
            pygame.draw.rect(self.screen, (55, 66, 95, 190), back_rect, border_radius=6)
        pygame.draw.rect(self.screen, self._title_menu_color("slot_border", (98, 112, 140, 255))[:3], back_rect, 1, border_radius=6)
        title_surf = self.title_menu_item_font.render("Back", True, (self._title_menu_color("item_selected", (255, 216, 112)) if selected else self._title_menu_color("item", (236, 239, 248)))[:3])
        self.screen.blit(title_surf, (back_rect.x + (back_rect.width - title_surf.get_width()) // 2, back_rect.y + (back_rect.height - title_surf.get_height()) // 2))
        self.title_menu_buttons.append(("action", "main", back_rect, False))

    def _draw_title_menu_prefs(self, int sw, int sh) -> None:
        cdef int panel_w = 680
        cdef int panel_h = 320
        cdef int px = (sw - panel_w) // 2
        cdef int py = (sh - panel_h) // 2
        cdef list rows = [
            f"Text Speed: {self.text_speed:.1f} (Left/Right)",
            f"Perf Overlay: {'On' if self.show_perf else 'Off'} (Left/Right)",
            "Save Preferences",
            "Back",
        ]
        cdef int i
        cdef object rect
        cdef bint selected
        cdef object text_surf
        pygame.draw.rect(self.screen, self._title_menu_color("panel", (20, 24, 34, 232)), (px, py, panel_w, panel_h), border_radius=10)
        pygame.draw.rect(self.screen, self._title_menu_color("panel_border", (100, 120, 156, 255))[:3], (px, py, panel_w, panel_h), 2, border_radius=10)
        text_surf = self.title_menu_item_font.render("Preferences", True, self._title_menu_color("item", (236, 239, 248))[:3])
        self.screen.blit(text_surf, (px + (panel_w - text_surf.get_width()) // 2, py + 18))
        for i in range(len(rows)):
            rect = pygame.Rect(px + 42, py + 80 + i * 52, panel_w - 84, 42)
            selected = self.title_menu_pref_index == i
            if selected:
                pygame.draw.rect(self.screen, (55, 66, 95, 190), rect, border_radius=6)
            pygame.draw.rect(self.screen, self._title_menu_color("slot_border", (98, 112, 140, 255))[:3], rect, 1, border_radius=6)
            text_surf = self.title_menu_item_font.render(
                rows[i],
                True,
                (self._title_menu_color("item_selected", (255, 216, 112)) if selected else self._title_menu_color("item", (236, 239, 248)))[:3],
            )
            self.screen.blit(text_surf, (rect.x + 10, rect.y + (rect.height - text_surf.get_height()) // 2))
            if i == 2:
                self.title_menu_buttons.append(("action", "save_prefs", rect, False))
            elif i == 3:
                self.title_menu_buttons.append(("action", "main", rect, False))
            else:
                self.title_menu_buttons.append(("prefs", str(i), rect, False))

    def _title_menu_keydown(self, event) -> None:
        cdef list actions
        cdef int total
        cdef int cols
        cdef int rows
        cdef int slot_count
        cdef int max_index
        cdef str action
        cdef str slot_id
        if event.key == pygame.K_ESCAPE:
            self.running = False
            return
        if self.title_menu_view == "main":
            actions = self._title_menu_actions()
            total = len(actions)
            if total <= 0:
                return
            if event.key in (pygame.K_UP, pygame.K_w):
                self.title_menu_selected = (self.title_menu_selected - 1) % total
                return
            if event.key in (pygame.K_DOWN, pygame.K_s):
                self.title_menu_selected = (self.title_menu_selected + 1) % total
                return
            if event.key in (pygame.K_RETURN, pygame.K_SPACE):
                action = actions[self.title_menu_selected][1]
                if action == "continue" and not self._title_menu_has_continue():
                    self._title_menu_set_status("No save data found.", ok=False)
                    return
                self._title_menu_execute_action(action)
                return
            return
        if self.title_menu_view == "load":
            cols = max(1, int(self.title_menu_cfg.get("load_cols", 3)))
            rows = max(1, int(self.title_menu_cfg.get("load_rows", 3)))
            slot_count = min(len(self.pause_menu_slots), cols * rows)
            max_index = slot_count
            if event.key == pygame.K_UP:
                if self.title_menu_selected == slot_count:
                    self.title_menu_selected = max(0, slot_count - cols)
                else:
                    self.title_menu_selected = max(0, self.title_menu_selected - cols)
                return
            if event.key == pygame.K_DOWN:
                if self.title_menu_selected < slot_count - cols:
                    self.title_menu_selected += cols
                else:
                    self.title_menu_selected = slot_count
                return
            if event.key in (pygame.K_LEFT, pygame.K_a):
                if self.title_menu_selected == slot_count:
                    self.title_menu_selected = max(0, slot_count - 1)
                else:
                    self.title_menu_selected = max(0, self.title_menu_selected - 1)
                return
            if event.key in (pygame.K_RIGHT, pygame.K_d):
                if self.title_menu_selected == slot_count:
                    self.title_menu_selected = 0
                else:
                    self.title_menu_selected = min(max_index, self.title_menu_selected + 1)
                return
            if event.key in (pygame.K_RETURN, pygame.K_SPACE):
                if self.title_menu_selected >= slot_count:
                    self._title_menu_execute_action("main")
                else:
                    slot_id = str(self.pause_menu_slots[self.title_menu_selected])
                    self._title_menu_load_slot(slot_id)
                return
            return
        # prefs
        if event.key in (pygame.K_UP, pygame.K_w):
            self.title_menu_pref_index = (self.title_menu_pref_index - 1) % 4
            return
        if event.key in (pygame.K_DOWN, pygame.K_s):
            self.title_menu_pref_index = (self.title_menu_pref_index + 1) % 4
            return
        if self.title_menu_pref_index == 0 and event.key in (pygame.K_LEFT, pygame.K_RIGHT):
            if event.key == pygame.K_LEFT:
                self.text_speed = max(0.0, self.text_speed - 2.0)
            else:
                self.text_speed = min(300.0, self.text_speed + 2.0)
            return
        if self.title_menu_pref_index == 1 and event.key in (pygame.K_LEFT, pygame.K_RIGHT):
            self.show_perf = not self.show_perf
            return
        if event.key in (pygame.K_RETURN, pygame.K_SPACE):
            if self.title_menu_pref_index == 2:
                self._title_menu_execute_action("save_prefs")
            elif self.title_menu_pref_index == 3:
                self._title_menu_execute_action("main")

    def _title_menu_mousemotion(self, event) -> None:
        cdef object entry
        cdef tuple pos = event.pos
        self.title_menu_hover = None
        for entry in self.title_menu_buttons:
            if entry[2].collidepoint(pos):
                self.title_menu_hover = (entry[0], entry[1])
                break

    def _title_menu_mousedown(self, event) -> None:
        cdef object entry
        cdef str action
        cdef str slot_id
        if event.button != 1:
            return
        for entry in self.title_menu_buttons:
            if not entry[2].collidepoint(event.pos):
                continue
            if bool(entry[3]):
                if entry[0] == "action" and str(entry[1]) == "continue":
                    self._title_menu_set_status("No save data found.", ok=False)
                return
            if entry[0] == "action":
                action = str(entry[1])
                self._title_menu_execute_action(action)
                return
            if entry[0] == "slot":
                slot_id = str(entry[1])
                self._title_menu_load_slot(slot_id)
                return
            if entry[0] == "prefs":
                self.title_menu_pref_index = int(entry[1])
                return
