# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False

from __future__ import annotations

import json
from pathlib import Path

import pygame


class PauseMenuMixin:
    def _pause_menu_init(self, ui) -> None:
        cdef object cfg_path = None
        cdef object cfg_name = getattr(ui, "pause_menu_file", "")
        cdef object root
        self.pause_menu_enabled = bool(getattr(ui, "pause_menu_enabled", True))
        self.pause_menu_active = False
        self.pause_menu_view = "menu"  # menu | save | load | prefs
        self.pause_menu_selected = 0
        self.pause_menu_buttons = []  # list[(kind, key, rect)]
        self.pause_menu_status = ""
        self.pause_menu_status_until_ms = None
        self.pause_menu_hover = None
        self.pause_menu_cfg = self._pause_menu_default_config()
        self.pause_menu_slots = []
        self.pause_menu_cols = max(1, int(getattr(ui, "pause_menu_columns", 3)))
        self.pause_menu_pref_index = 0
        self.pause_menu_pref_items = ["Text Speed", "Perf Overlay", "Save Prefs", "Back"]
        self.pause_menu_prefs_path = self.save_path.parent / "ui_prefs.json"

        root = Path(self._project_root)
        if cfg_name:
            cfg_path = (root / str(cfg_name)).resolve()
        else:
            cfg_path = (root / "pause_menu.json").resolve()
        self.pause_menu_config_path = cfg_path
        if cfg_path.exists():
            self._pause_menu_load_config(cfg_path)

        self.pause_menu_rows = max(1, int(self.pause_menu_cfg.get("slot_rows", 3)))
        self.pause_menu_cols = max(1, int(self.pause_menu_cfg.get("slot_cols", self.pause_menu_cols)))
        self.pause_menu_slots = self._pause_menu_collect_slots(int(getattr(ui, "pause_menu_slots", 9)))

        self.pause_menu_title_font = pygame.font.Font(None, int(self.pause_menu_cfg.get("title_font_size", 44)))
        self.pause_menu_item_font = pygame.font.Font(None, int(self.pause_menu_cfg.get("item_font_size", 30)))
        self.pause_menu_meta_font = pygame.font.Font(None, int(self.pause_menu_cfg.get("meta_font_size", 22)))

        self._pause_menu_load_prefs()

    def _pause_menu_default_config(self) -> dict:
        return {
            "title": "Pause Menu",
            "subtitle": "ESC to close",
            "title_font_size": 44,
            "item_font_size": 30,
            "meta_font_size": 22,
            "panel_width": 620,
            "panel_padding": 20,
            "slot_rows": 3,
            "slot_cols": 3,
            "colors": {
                "overlay": [0, 0, 0, 170],
                "panel": [20, 24, 34, 230],
                "panel_border": [105, 120, 150, 255],
                "title": [240, 242, 248, 255],
                "subtitle": [180, 190, 210, 255],
                "item": [232, 235, 242, 255],
                "item_selected": [255, 219, 120, 255],
                "slot": [34, 39, 52, 210],
                "slot_border": [98, 112, 140, 255],
                "slot_filled": [58, 78, 114, 210],
                "meta": [172, 182, 205, 255],
                "ok": [130, 220, 150, 255],
                "warn": [255, 189, 120, 255],
            },
            "buttons": [
                {"label": "Resume", "action": "resume"},
                {"label": "Save", "action": "open_save"},
                {"label": "Load", "action": "open_load"},
                {"label": "Preferences", "action": "open_prefs"},
                {"label": "Quick Save", "action": "quick_save"},
                {"label": "Quick Load", "action": "quick_load"},
                {"label": "Quit", "action": "quit"},
            ],
            "save_slots": [],
        }

    def _pause_menu_merge_dict(self, base: dict, override: dict) -> dict:
        cdef dict out = dict(base)
        cdef object key
        cdef object value
        cdef object current
        for key, value in override.items():
            if isinstance(value, dict):
                current = out.get(key)
                if isinstance(current, dict):
                    out[key] = self._pause_menu_merge_dict(current, value)
                else:
                    out[key] = self._pause_menu_merge_dict({}, value)
            else:
                out[key] = value
        return out

    def _pause_menu_load_config(self, path: Path) -> None:
        cdef object raw
        cdef dict parsed
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return
        if not isinstance(raw, dict):
            return
        parsed = self._pause_menu_merge_dict(self.pause_menu_cfg, raw)
        self.pause_menu_cfg = parsed

    def _pause_menu_collect_slots(self, default_count: int) -> list:
        cdef list slots = []
        cdef object slot_entry
        cdef int i
        cdef int count
        for slot_entry in self.pause_menu_cfg.get("save_slots", []):
            if slot_entry is None:
                continue
            slot_name = str(slot_entry).strip()
            if not slot_name:
                continue
            slots.append(slot_name)
        if slots:
            return slots

        count = max(1, default_count)
        for i in range(count):
            slots.append(f"slot_{i + 1}")
        return slots

    def _pause_menu_color(self, str key, tuple fallback) -> tuple:
        cdef object colors = self.pause_menu_cfg.get("colors", {})
        cdef object value
        cdef int r
        cdef int g
        cdef int b
        cdef int a
        if not isinstance(colors, dict):
            return fallback
        value = colors.get(key)
        if not isinstance(value, (list, tuple)):
            return fallback
        if len(value) < 3:
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

    def _pause_menu_actions(self) -> list:
        cdef list out = []
        cdef object item
        cdef str label
        cdef str action
        for item in self.pause_menu_cfg.get("buttons", []):
            if not isinstance(item, dict):
                continue
            label = str(item.get("label", "")).strip()
            action = str(item.get("action", "")).strip()
            if not label or not action:
                continue
            out.append((label, action))
        if out:
            return out
        return [
            ("Resume", "resume"),
            ("Save", "open_save"),
            ("Load", "open_load"),
            ("Preferences", "open_prefs"),
            ("Quick Save", "quick_save"),
            ("Quick Load", "quick_load"),
            ("Quit", "quit"),
        ]

    def _pause_menu_set_status(self, text: str, bint ok=True, int ms=1800) -> None:
        self.pause_menu_status = text
        self.pause_menu_status_kind = "ok" if ok else "warn"
        self.pause_menu_status_until_ms = pygame.time.get_ticks() + max(200, ms)

    def _pause_menu_open(self, str view="menu") -> None:
        if not self.pause_menu_enabled:
            return
        self.pause_menu_active = True
        self.pause_menu_view = view if view in {"menu", "save", "load", "prefs"} else "menu"
        self.pause_menu_selected = 0
        self.pause_menu_hover = None
        if self.pause_menu_view == "prefs":
            self.pause_menu_pref_index = 0

    def _pause_menu_close(self) -> None:
        self.pause_menu_active = False
        self.pause_menu_view = "menu"
        self.pause_menu_selected = 0
        self.pause_menu_buttons = []
        self.pause_menu_hover = None

    def _toggle_pause_menu(self) -> None:
        if not self.pause_menu_enabled:
            return
        if self.pause_menu_active:
            self._pause_menu_close()
        else:
            self._pause_menu_open("menu")

    def _pause_menu_execute_action(self, action: str) -> None:
        cdef str act = str(action).strip().lower()
        if not act:
            return
        if act == "resume":
            self._pause_menu_close()
            return
        if act == "open_save":
            self._pause_menu_open("save")
            return
        if act == "open_load":
            self._pause_menu_open("load")
            return
        if act == "open_prefs":
            self._pause_menu_open("prefs")
            return
        if act == "return_menu":
            self._pause_menu_open("menu")
            return
        if act == "quick_save":
            self.save_quick()
            self._pause_menu_set_status("Quick save written.", ok=True)
            return
        if act == "quick_load":
            if self.save_path.exists():
                self.load_quick()
                self._pause_menu_close()
            else:
                self._pause_menu_set_status("No quicksave found.", ok=False)
            return
        if act == "quit":
            self.running = False
            return
        if act == "prefs_save":
            self._pause_menu_save_prefs()
            self._pause_menu_set_status("Preferences saved.", ok=True)
            return

    def _pause_menu_slot_action(self, str slot_id) -> None:
        cdef object path = self._slot_path(slot_id)
        if self.pause_menu_view == "save":
            self.save_slot(slot_id)
            self._pause_menu_set_status(f"Saved: {slot_id}", ok=True)
            return
        if self.pause_menu_view == "load":
            if not path.exists():
                self._pause_menu_set_status(f"Slot empty: {slot_id}", ok=False)
                return
            self.load_slot(slot_id)
            self._pause_menu_close()

    def _pause_menu_save_prefs(self) -> None:
        cdef dict payload = {
            "text_speed": float(self.text_speed),
            "show_perf": bool(self.show_perf),
        }
        self.pause_menu_prefs_path.parent.mkdir(parents=True, exist_ok=True)
        self.pause_menu_prefs_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    def _pause_menu_load_prefs(self) -> None:
        cdef object raw
        cdef dict data
        if not self.pause_menu_prefs_path.exists():
            return
        try:
            raw = json.loads(self.pause_menu_prefs_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return
        if not isinstance(raw, dict):
            return
        data = raw
        try:
            self.text_speed = max(0.0, float(data.get("text_speed", self.text_speed)))
        except (TypeError, ValueError):
            pass
        self.show_perf = bool(data.get("show_perf", self.show_perf))

    def _pause_menu_slot_summary(self, str slot_id) -> dict:
        cdef object path = self._slot_path(slot_id)
        cdef object raw
        cdef dict data
        cdef dict bg
        cdef dict vars_data
        cdef dict inv_data
        if not path.exists():
            return {"exists": False}
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {"exists": True, "broken": True}
        if not isinstance(raw, dict):
            return {"exists": True, "broken": True}
        data = raw
        bg = data.get("background", {}) if isinstance(data.get("background"), dict) else {}
        vars_data = data.get("vars", {}) if isinstance(data.get("vars"), dict) else {}
        inv_data = data.get("inventory", {}) if isinstance(data.get("inventory"), dict) else {}
        return {
            "exists": True,
            "script_path": str(data.get("script_path", "-")),
            "index": int(data.get("index", 0)) if isinstance(data.get("index", 0), (int, float)) else 0,
            "bg_value": str(bg.get("value", "-")),
            "vars_count": len(vars_data),
            "inventory_count": len(inv_data),
        }

    def _draw_pause_menu(self) -> None:
        cdef int sw = self.screen.get_width()
        cdef int sh = self.screen.get_height()
        cdef object overlay
        cdef object panel
        cdef int panel_w = max(420, min(sw - 40, int(self.pause_menu_cfg.get("panel_width", 620))))
        cdef int panel_h
        cdef int px
        cdef int py
        cdef object title_surf
        cdef object subtitle_surf
        cdef tuple title_color
        cdef tuple subtitle_color
        cdef int now = pygame.time.get_ticks()
        overlay = pygame.Surface((sw, sh), pygame.SRCALPHA)
        overlay.fill(self._pause_menu_color("overlay", (0, 0, 0, 170)))
        self.screen.blit(overlay, (0, 0))

        if self.pause_menu_view == "menu":
            panel_h = 410
        elif self.pause_menu_view in {"save", "load"}:
            panel_h = 500
        else:
            panel_h = 360
        panel_h = min(sh - 24, panel_h)

        px = (sw - panel_w) // 2
        py = (sh - panel_h) // 2

        panel = pygame.Surface((panel_w, panel_h), pygame.SRCALPHA)
        panel.fill(self._pause_menu_color("panel", (20, 24, 34, 230)))
        self.screen.blit(panel, (px, py))
        pygame.draw.rect(
            self.screen,
            self._pause_menu_color("panel_border", (105, 120, 150, 255)),
            (px, py, panel_w, panel_h),
            2,
            border_radius=10,
        )
        self.pause_menu_buttons = []
        title_color = self._pause_menu_color("title", (240, 242, 248))
        subtitle_color = self._pause_menu_color("subtitle", (180, 190, 210))
        title_surf = self.pause_menu_title_font.render(str(self.pause_menu_cfg.get("title", "Pause Menu")), True, title_color[:3])
        self.screen.blit(title_surf, (px + (panel_w - title_surf.get_width()) // 2, py + 12))
        subtitle_surf = self.pause_menu_meta_font.render(str(self.pause_menu_cfg.get("subtitle", "ESC to close")), True, subtitle_color[:3])
        self.screen.blit(subtitle_surf, (px + (panel_w - subtitle_surf.get_width()) // 2, py + 52))

        if self.pause_menu_view == "menu":
            self._draw_pause_menu_actions(px, py, panel_w, panel_h)
        elif self.pause_menu_view in {"save", "load"}:
            self._draw_pause_menu_slots(px, py, panel_w, panel_h)
        else:
            self._draw_pause_menu_prefs(px, py, panel_w, panel_h)

        if self.pause_menu_status and self.pause_menu_status_until_ms is not None and now <= self.pause_menu_status_until_ms:
            status_color = self._pause_menu_color("ok", (130, 220, 150))
            if self.pause_menu_status_kind == "warn":
                status_color = self._pause_menu_color("warn", (255, 189, 120))
            status_surf = self.pause_menu_meta_font.render(self.pause_menu_status, True, status_color[:3])
            self.screen.blit(status_surf, (px + (panel_w - status_surf.get_width()) // 2, py + panel_h - status_surf.get_height() - 10))

    def _draw_pause_menu_actions(self, int px, int py, int panel_w, int panel_h) -> None:
        cdef list actions = self._pause_menu_actions()
        cdef int i
        cdef int row_h = 42
        cdef int total_h = len(actions) * row_h
        cdef int start_y = py + 112 + max(0, (panel_h - 170 - total_h) // 2)
        cdef object rect
        cdef tuple normal_color = self._pause_menu_color("item", (232, 235, 242))
        cdef tuple selected_color = self._pause_menu_color("item_selected", (255, 219, 120))
        cdef object text_surf
        cdef bint selected
        cdef str label
        cdef str action
        for i, (label, action) in enumerate(actions):
            rect = pygame.Rect(px + 48, start_y + (i * row_h), panel_w - 96, row_h - 4)
            selected = (self.pause_menu_selected == i) or (self.pause_menu_hover == ("action", action))
            if selected:
                pygame.draw.rect(self.screen, (55, 66, 95, 190), rect, border_radius=6)
                pygame.draw.rect(self.screen, selected_color[:3], rect, 1, border_radius=6)
            text_surf = self.pause_menu_item_font.render(label, True, (selected_color if selected else normal_color)[:3])
            self.screen.blit(text_surf, (rect.x + (rect.width - text_surf.get_width()) // 2, rect.y + (rect.height - text_surf.get_height()) // 2))
            self.pause_menu_buttons.append(("action", action, rect))

    def _draw_pause_menu_slots(self, int px, int py, int panel_w, int panel_h) -> None:
        cdef int cols = max(1, self.pause_menu_cols)
        cdef int rows = max(1, self.pause_menu_rows)
        cdef int total_slots = min(len(self.pause_menu_slots), cols * rows)
        cdef int grid_w = panel_w - 56
        cdef int grid_h = panel_h - 176
        cdef int gap = 10
        cdef int slot_w = max(120, (grid_w - ((cols - 1) * gap)) // cols)
        cdef int slot_h = max(84, (grid_h - ((rows - 1) * gap)) // rows)
        cdef int grid_x = px + (panel_w - (cols * slot_w + (cols - 1) * gap)) // 2
        cdef int grid_y = py + 100
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
        cdef tuple slot_color
        cdef bint selected
        cdef int selected_index
        cdef object back_rect

        selected_index = self.pause_menu_selected
        for i in range(total_slots):
            c = i % cols
            r = i // cols
            sx = grid_x + c * (slot_w + gap)
            sy = grid_y + r * (slot_h + gap)
            rect = pygame.Rect(sx, sy, slot_w, slot_h)
            slot_id = self.pause_menu_slots[i]
            summary = self._pause_menu_slot_summary(slot_id)
            selected = (selected_index == i) or (self.pause_menu_hover == ("slot", slot_id))
            if summary.get("exists"):
                slot_color = self._pause_menu_color("slot_filled", (58, 78, 114, 210))
            else:
                slot_color = self._pause_menu_color("slot", (34, 39, 52, 210))
            pygame.draw.rect(self.screen, slot_color, rect, border_radius=8)
            pygame.draw.rect(
                self.screen,
                (self._pause_menu_color("item_selected", (255, 219, 120)) if selected else self._pause_menu_color("slot_border", (98, 112, 140, 255)))[:3],
                rect,
                2 if selected else 1,
                border_radius=8,
            )
            title_surf = self.pause_menu_item_font.render(slot_id, True, self._pause_menu_color("item", (232, 235, 242))[:3])
            self.screen.blit(title_surf, (sx + 10, sy + 8))
            if summary.get("exists"):
                meta_surf = self.pause_menu_meta_font.render(str(summary.get("script_path", "-")), True, self._pause_menu_color("meta", (172, 182, 205))[:3])
                extra_surf = self.pause_menu_meta_font.render(
                    f"bg:{summary.get('bg_value', '-')} inv:{summary.get('inventory_count', 0)} vars:{summary.get('vars_count', 0)}",
                    True,
                    self._pause_menu_color("meta", (172, 182, 205))[:3],
                )
                self.screen.blit(meta_surf, (sx + 10, sy + 38))
                self.screen.blit(extra_surf, (sx + 10, sy + 60))
            else:
                meta_surf = self.pause_menu_meta_font.render("Empty", True, self._pause_menu_color("meta", (172, 182, 205))[:3])
                self.screen.blit(meta_surf, (sx + 10, sy + 44))
            self.pause_menu_buttons.append(("slot", slot_id, rect))

        back_rect = pygame.Rect(px + (panel_w - 220) // 2, py + panel_h - 56, 220, 34)
        selected = (selected_index == total_slots) or (self.pause_menu_hover == ("action", "return_menu"))
        if selected:
            pygame.draw.rect(self.screen, (55, 66, 95, 190), back_rect, border_radius=6)
        pygame.draw.rect(self.screen, self._pause_menu_color("slot_border", (98, 112, 140, 255))[:3], back_rect, 1, border_radius=6)
        title_surf = self.pause_menu_item_font.render("Return", True, (self._pause_menu_color("item_selected", (255, 219, 120)) if selected else self._pause_menu_color("item", (232, 235, 242)))[:3])
        self.screen.blit(title_surf, (back_rect.x + (back_rect.width - title_surf.get_width()) // 2, back_rect.y + (back_rect.height - title_surf.get_height()) // 2))
        self.pause_menu_buttons.append(("action", "return_menu", back_rect))

    def _draw_pause_menu_prefs(self, int px, int py, int panel_w, int panel_h) -> None:
        cdef list rows = [
            f"Text Speed: {self.text_speed:.1f} (Left/Right)",
            f"Perf Overlay: {'On' if self.show_perf else 'Off'} (Left/Right)",
            "Save Prefs",
            "Back",
        ]
        cdef int i
        cdef object rect
        cdef bint selected
        cdef object text_surf
        cdef tuple normal_color = self._pause_menu_color("item", (232, 235, 242))
        cdef tuple selected_color = self._pause_menu_color("item_selected", (255, 219, 120))
        cdef int start_y = py + 130
        for i in range(len(rows)):
            rect = pygame.Rect(px + 42, start_y + (i * 48), panel_w - 84, 40)
            selected = self.pause_menu_pref_index == i
            if selected:
                pygame.draw.rect(self.screen, (55, 66, 95, 190), rect, border_radius=6)
            pygame.draw.rect(self.screen, self._pause_menu_color("slot_border", (98, 112, 140, 255))[:3], rect, 1, border_radius=6)
            text_surf = self.pause_menu_item_font.render(rows[i], True, (selected_color if selected else normal_color)[:3])
            self.screen.blit(text_surf, (rect.x + 10, rect.y + (rect.height - text_surf.get_height()) // 2))
            if i == 2:
                self.pause_menu_buttons.append(("action", "prefs_save", rect))
            elif i == 3:
                self.pause_menu_buttons.append(("action", "return_menu", rect))
            else:
                self.pause_menu_buttons.append(("prefs", str(i), rect))

    def _pause_menu_keydown(self, event) -> None:
        cdef int total
        cdef int cols
        cdef int rows
        cdef int max_index
        cdef int slot_count
        cdef str slot_id
        if event.key == pygame.K_ESCAPE:
            self._pause_menu_close()
            return

        if self.pause_menu_view == "menu":
            total = len(self._pause_menu_actions())
            if total <= 0:
                return
            if event.key in (pygame.K_UP, pygame.K_w):
                self.pause_menu_selected = (self.pause_menu_selected - 1) % total
                return
            if event.key in (pygame.K_DOWN, pygame.K_s):
                self.pause_menu_selected = (self.pause_menu_selected + 1) % total
                return
            if event.key in (pygame.K_RETURN, pygame.K_SPACE):
                self._pause_menu_execute_action(self._pause_menu_actions()[self.pause_menu_selected][1])
                return
            return

        if self.pause_menu_view in {"save", "load"}:
            slot_count = min(len(self.pause_menu_slots), self.pause_menu_cols * self.pause_menu_rows)
            max_index = slot_count
            cols = max(1, self.pause_menu_cols)
            if event.key == pygame.K_UP:
                if self.pause_menu_selected == slot_count:
                    self.pause_menu_selected = max(0, slot_count - cols)
                else:
                    self.pause_menu_selected = max(0, self.pause_menu_selected - cols)
                return
            if event.key == pygame.K_DOWN:
                if self.pause_menu_selected < slot_count - cols:
                    self.pause_menu_selected += cols
                else:
                    self.pause_menu_selected = slot_count
                return
            if event.key in (pygame.K_LEFT, pygame.K_a):
                if self.pause_menu_selected == slot_count:
                    self.pause_menu_selected = max(0, slot_count - 1)
                else:
                    self.pause_menu_selected = max(0, self.pause_menu_selected - 1)
                return
            if event.key in (pygame.K_RIGHT, pygame.K_d):
                if self.pause_menu_selected == slot_count:
                    self.pause_menu_selected = 0
                else:
                    self.pause_menu_selected = min(max_index, self.pause_menu_selected + 1)
                return
            if event.key in (pygame.K_RETURN, pygame.K_SPACE):
                if self.pause_menu_selected >= slot_count:
                    self._pause_menu_execute_action("return_menu")
                    return
                slot_id = self.pause_menu_slots[self.pause_menu_selected]
                self._pause_menu_slot_action(slot_id)
                return
            return

        # prefs
        rows = len(self.pause_menu_pref_items)
        if event.key in (pygame.K_UP, pygame.K_w):
            self.pause_menu_pref_index = (self.pause_menu_pref_index - 1) % rows
            return
        if event.key in (pygame.K_DOWN, pygame.K_s):
            self.pause_menu_pref_index = (self.pause_menu_pref_index + 1) % rows
            return
        if self.pause_menu_pref_index == 0 and event.key in (pygame.K_LEFT, pygame.K_RIGHT):
            if event.key == pygame.K_LEFT:
                self.text_speed = max(0.0, self.text_speed - 2.0)
            else:
                self.text_speed = min(300.0, self.text_speed + 2.0)
            return
        if self.pause_menu_pref_index == 1 and event.key in (pygame.K_LEFT, pygame.K_RIGHT):
            self.show_perf = not self.show_perf
            return
        if event.key in (pygame.K_RETURN, pygame.K_SPACE):
            if self.pause_menu_pref_index == 2:
                self._pause_menu_execute_action("prefs_save")
            elif self.pause_menu_pref_index == 3:
                self._pause_menu_execute_action("return_menu")

    def _pause_menu_mousemotion(self, event) -> None:
        cdef object entry
        cdef tuple pos = event.pos
        self.pause_menu_hover = None
        for entry in self.pause_menu_buttons:
            if entry[2].collidepoint(pos):
                self.pause_menu_hover = (entry[0], entry[1])
                break

    def _pause_menu_mousedown(self, event) -> None:
        cdef object entry
        cdef str slot_id
        cdef str action
        cdef tuple pos
        if event.button != 1:
            return
        pos = event.pos
        for entry in self.pause_menu_buttons:
            if not entry[2].collidepoint(pos):
                continue
            if entry[0] == "action":
                action = str(entry[1])
                self._pause_menu_execute_action(action)
                return
            if entry[0] == "slot":
                slot_id = str(entry[1])
                self._pause_menu_slot_action(slot_id)
                return
            if entry[0] == "prefs":
                self.pause_menu_pref_index = int(entry[1])
                return
