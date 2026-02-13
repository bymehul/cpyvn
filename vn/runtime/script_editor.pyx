# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
from __future__ import annotations

from pathlib import Path
from typing import List, Tuple

import pygame


class ScriptEditorMixin:

    def _toggle_script_editor(self):
        if not self.show_script_editor:
            self.show_script_editor   = True
            self.show_inspector       = False
            self.inspector_selected   = None
            self.inspector_dragging   = False
            if self.show_hotspot_editor:
                self._toggle_hotspot_editor()
            self.script_editor_follow_runtime = True
            self._script_editor_collect_files()
            self._script_editor_sync_path()
            self.script_editor_status = f"Editing: {self.script_editor_path}"
        else:
            self.show_script_editor = False

    def _script_editor_sync_path(self):
        cdef object path
        if not self.script_editor_follow_runtime:
            return
        path = self.current_script_path
        if self.script_editor_loaded_path == path and self.script_editor_lines:
            return
        self.script_editor_path = path
        self._script_editor_load(path)
        self._script_editor_collect_files()

    def _script_editor_collect_files(self):
        cdef list files = []
        cdef object root = self._project_root
        cdef object current

        if root.exists():
            files = sorted(path.resolve() for path in root.rglob("*.vn"))
        current = self.script_editor_path.resolve()
        if current not in files:
            files.append(current)
            files.sort()
        self.script_editor_files = files
        if files:
            try:
                self.script_editor_file_index = files.index(current)
            except ValueError:
                self.script_editor_file_index = 0
            self._script_editor_keep_selected_file_visible()

    def _script_editor_rel_path(self, object path):
        try:
            return str(path.relative_to(self._project_root))
        except ValueError:
            return str(path)

    def _script_editor_open_file(self, object path, bint follow_runtime=False):
        cdef object target = path.resolve()
        if self.script_editor_dirty and target != self.script_editor_path.resolve():
            if not self._script_editor_save():
                return False
        self.script_editor_path             = target
        self.script_editor_follow_runtime   = follow_runtime
        self._script_editor_load(target)
        self._script_editor_collect_files()
        return True

    def _script_editor_open_relative_file(self, int step):
        if not self.script_editor_files:
            self._script_editor_collect_files()
        if not self.script_editor_files:
            return
        self.script_editor_file_index = (
            (self.script_editor_file_index + step) % len(self.script_editor_files)
        )
        self._script_editor_keep_selected_file_visible()
        self._script_editor_open_file(
            self.script_editor_files[self.script_editor_file_index],
            follow_runtime=False,
        )

    def _script_editor_load(self, object path):
        cdef str text
        cdef list lines

        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            self.script_editor_lines       = [""]
            self.script_editor_cursor_line = 0
            self.script_editor_cursor_col  = 0
            self.script_editor_scroll      = 0
            self.script_editor_dirty       = False
            self.script_editor_loaded_path = None
            self.script_editor_status      = f"Open failed: {exc}"
            return
        lines = text.splitlines()
        if not lines:
            lines = [""]
        self.script_editor_lines       = lines
        self.script_editor_cursor_line = 0
        self.script_editor_cursor_col  = 0
        self.script_editor_scroll      = 0
        self.script_editor_dirty       = False
        self.script_editor_loaded_path = path
        self.script_editor_status      = f"Opened: {path}"

    def _script_editor_text(self):
        return "\n".join(self.script_editor_lines)

    def _script_editor_mark_dirty(self):
        self.script_editor_dirty = True

    def _script_editor_clamp_cursor(self):
        cdef str line
        if not self.script_editor_lines:
            self.script_editor_lines = [""]
        if self.script_editor_cursor_line < 0:
            self.script_editor_cursor_line = 0
        if self.script_editor_cursor_line >= len(self.script_editor_lines):
            self.script_editor_cursor_line = len(self.script_editor_lines) - 1
        line = self.script_editor_lines[self.script_editor_cursor_line]
        if self.script_editor_cursor_col < 0:
            self.script_editor_cursor_col = 0
        if self.script_editor_cursor_col > len(line):
            self.script_editor_cursor_col = len(line)

    def _script_editor_insert_text(self, str text):
        cdef str line
        cdef int col
        line = self.script_editor_lines[self.script_editor_cursor_line]
        col  = self.script_editor_cursor_col
        self.script_editor_lines[self.script_editor_cursor_line] = line[:col] + text + line[col:]
        self.script_editor_cursor_col += len(text)
        self._script_editor_mark_dirty()

    def _script_editor_newline(self):
        cdef str line, left, right
        cdef int col
        line  = self.script_editor_lines[self.script_editor_cursor_line]
        col   = self.script_editor_cursor_col
        left  = line[:col]
        right = line[col:]
        self.script_editor_lines[self.script_editor_cursor_line] = left
        self.script_editor_lines.insert(self.script_editor_cursor_line + 1, right)
        self.script_editor_cursor_line += 1
        self.script_editor_cursor_col   = 0
        self._script_editor_mark_dirty()

    def _script_editor_backspace(self):
        cdef str line, prev, current
        cdef int col, prev_idx
        if self.script_editor_cursor_col > 0:
            line = self.script_editor_lines[self.script_editor_cursor_line]
            col  = self.script_editor_cursor_col
            self.script_editor_lines[self.script_editor_cursor_line] = line[:col - 1] + line[col:]
            self.script_editor_cursor_col -= 1
            self._script_editor_mark_dirty()
            return
        if self.script_editor_cursor_line <= 0:
            return
        prev_idx = self.script_editor_cursor_line - 1
        prev     = self.script_editor_lines[prev_idx]
        current  = self.script_editor_lines[self.script_editor_cursor_line]
        self.script_editor_lines[prev_idx] = prev + current
        del self.script_editor_lines[self.script_editor_cursor_line]
        self.script_editor_cursor_line = prev_idx
        self.script_editor_cursor_col  = len(prev)
        self._script_editor_mark_dirty()

    def _script_editor_delete(self):
        cdef str line
        cdef int col
        line = self.script_editor_lines[self.script_editor_cursor_line]
        col  = self.script_editor_cursor_col
        if col < len(line):
            self.script_editor_lines[self.script_editor_cursor_line] = line[:col] + line[col + 1:]
            self._script_editor_mark_dirty()
            return
        if self.script_editor_cursor_line + 1 >= len(self.script_editor_lines):
            return
        self.script_editor_lines[self.script_editor_cursor_line] = (
            line + self.script_editor_lines[self.script_editor_cursor_line + 1]
        )
        del self.script_editor_lines[self.script_editor_cursor_line + 1]
        self._script_editor_mark_dirty()

    def _script_editor_save(self):
        cdef object cache
        try:
            self.script_editor_path.write_text(self._script_editor_text(), encoding="utf-8")
        except OSError as exc:
            self.script_editor_status = f"Save failed: {exc}"
            return False
        cache = getattr(self, "_script_cache", None)
        if isinstance(cache, dict):
            cache.pop(self.script_editor_path.resolve(), None)
        self.script_editor_dirty  = False
        self.script_editor_status = f"Saved: {self.script_editor_path}"
        return True

    def _script_editor_reload_runtime(self):
        cdef object ok, message
        ok, message = self._reload_script_from_path(self.script_editor_path)
        self.script_editor_status = message
        if ok:
            self.script_editor_loaded_path    = self.script_editor_path
            self.script_editor_follow_runtime = True
            self._script_editor_collect_files()

    def _script_editor_visible_rows(self):
        cdef int line_h      = self.script_editor_font.get_height() + 2
        cdef int available_h = self.screen.get_height() - 72
        return max(1, available_h // line_h)

    def _script_editor_keep_cursor_visible(self):
        cdef int rows       = self._script_editor_visible_rows()
        cdef int max_scroll
        if self.script_editor_cursor_line < self.script_editor_scroll:
            self.script_editor_scroll = self.script_editor_cursor_line
        elif self.script_editor_cursor_line >= self.script_editor_scroll + rows:
            self.script_editor_scroll = self.script_editor_cursor_line - rows + 1
        max_scroll = max(0, len(self.script_editor_lines) - rows)
        if self.script_editor_scroll < 0:
            self.script_editor_scroll = 0
        elif self.script_editor_scroll > max_scroll:
            self.script_editor_scroll = max_scroll

    def _script_editor_scroll_by(self, int amount):
        cdef int rows       = self._script_editor_visible_rows()
        cdef int max_scroll = max(0, len(self.script_editor_lines) - rows)
        self.script_editor_scroll = max(0, min(max_scroll, self.script_editor_scroll + amount))

    def _script_editor_visible_file_rows(self):
        cdef dict layout = self._script_editor_layout()
        cdef int row_h      = layout["file_row_h"]
        cdef int list_top   = layout["top"] + 22
        cdef int available_h = layout["height"] - list_top - 10
        return max(1, available_h // row_h)

    def _script_editor_clamp_file_scroll(self):
        cdef int rows       = self._script_editor_visible_file_rows()
        cdef int max_scroll = max(0, len(self.script_editor_files) - rows)
        self.script_editor_file_scroll = max(0, min(max_scroll, self.script_editor_file_scroll))

    def _script_editor_keep_selected_file_visible(self):
        cdef int rows = self._script_editor_visible_file_rows()
        if self.script_editor_file_index < self.script_editor_file_scroll:
            self.script_editor_file_scroll = self.script_editor_file_index
        elif self.script_editor_file_index >= self.script_editor_file_scroll + rows:
            self.script_editor_file_scroll = self.script_editor_file_index - rows + 1
        self._script_editor_clamp_file_scroll()

    def _script_editor_layout(self):
        cdef int width, height, top, left, panel_w, gutter_w
        cdef int editor_left, text_x, line_h, file_row_h
        width, height = self.screen.get_size()
        top         = 66
        left        = 10
        panel_w     = min(380, max(220, <int>(width * 0.28)))
        gutter_w    = 58
        editor_left = left + panel_w + 8
        text_x      = editor_left + gutter_w + 8
        line_h      = self.script_editor_font.get_height() + 2
        file_row_h  = self.inspector_font.get_height() + 4
        return {
            "width":       width,
            "height":      height,
            "top":         top,
            "left":        left,
            "panel_w":     panel_w,
            "editor_left": editor_left,
            "gutter_w":    gutter_w,
            "text_x":      text_x,
            "line_h":      line_h,
            "file_row_h":  file_row_h,
        }

    def _script_editor_col_from_x(self, str line, int x_px):
        cdef int char_w, approx, best, best_dist, low, high, idx, dist
        if x_px <= 0:
            return 0
        char_w  = max(1, self.script_editor_font.size("M")[0])
        approx  = min(len(line), max(0, x_px // char_w))
        best    = approx
        best_dist = abs(self.script_editor_font.size(line[:approx])[0] - x_px)
        low     = max(0, approx - 4)
        high    = min(len(line), approx + 4)
        for idx in range(low, high + 1):
            dist = abs(self.script_editor_font.size(line[:idx])[0] - x_px)
            if dist < best_dist:
                best      = idx
                best_dist = dist
        return best

    def _script_editor_set_cursor_from_mouse(self, tuple pos):
        cdef dict layout = self._script_editor_layout()
        cdef int x = pos[0], y = pos[1]
        cdef int row, line_idx, col_x
        cdef str line

        if y < layout["top"] or y >= layout["height"] - 8:
            return
        if x < layout["editor_left"]:
            return
        row      = (y - layout["top"]) // layout["line_h"]
        line_idx = self.script_editor_scroll + row
        line_idx = max(0, min(len(self.script_editor_lines) - 1, line_idx))
        self.script_editor_cursor_line = line_idx
        line  = self.script_editor_lines[line_idx]
        col_x = x - layout["text_x"]
        self.script_editor_cursor_col = self._script_editor_col_from_x(line, col_x)
        self._script_editor_keep_cursor_visible()

    def _script_editor_pick_file_at(self, tuple pos):
        cdef dict layout  = self._script_editor_layout()
        cdef int x = pos[0], y = pos[1]
        cdef int panel_x0, panel_x1, list_top, row, idx

        panel_x0 = layout["left"]
        panel_x1 = panel_x0 + layout["panel_w"]
        list_top = layout["top"] + 22
        if x < panel_x0 or x > panel_x1:
            return None
        if y < list_top or y > layout["height"] - 8:
            return None
        row = (y - list_top) // layout["file_row_h"]
        idx = self.script_editor_file_scroll + row
        if 0 <= idx < len(self.script_editor_files):
            return self.script_editor_files[idx]
        return None

    def _script_editor_mouse_target(self, tuple pos):
        cdef dict layout = self._script_editor_layout()
        cdef int x = pos[0], y = pos[1]
        if y < 0 or y > layout["height"]:
            return "none"
        if x < layout["editor_left"]:
            return "files"
        return "text"

    def _handle_script_editor_mousewheel(self, int wheel_y, tuple pos):
        cdef str target
        if wheel_y == 0:
            return
        target = self._script_editor_mouse_target(pos)
        if target == "none":
            target = "text"
        if target == "files":
            self.script_editor_file_scroll -= wheel_y * 2
            self._script_editor_clamp_file_scroll()
            return
        if target == "text":
            self._script_editor_scroll_by(-wheel_y * 3)

    def _handle_script_editor_mousedown(self, object event):
        cdef tuple pos = event.pos
        cdef object file_path

        if event.button == 1:
            file_path = self._script_editor_pick_file_at(pos)
            if file_path is not None:
                self._script_editor_open_file(file_path, follow_runtime=False)
                return
            self._script_editor_set_cursor_from_mouse(pos)
            return
        if event.button == 4:
            self._handle_script_editor_mousewheel(1, pos)
            return
        if event.button == 5:
            self._handle_script_editor_mousewheel(-1, pos)

    def _handle_script_editor_keydown(self, object event):
        cdef int key  = event.key
        cdef int mods = pygame.key.get_mods()
        cdef bint ctrl = bool(mods & pygame.KMOD_CTRL)
        cdef str line, text

        if key == pygame.K_ESCAPE:
            self.show_script_editor = False
            return
        if ctrl and key == pygame.K_e:
            self._script_editor_open_file(self.current_script_path, follow_runtime=True)
            return
        if ctrl and key == pygame.K_s:
            self._script_editor_save()
            return
        if ctrl and key == pygame.K_r:
            if self.script_editor_dirty and not self._script_editor_save():
                return
            self._script_editor_reload_runtime()
            return
        if ctrl and key == pygame.K_UP:
            self._script_editor_open_relative_file(-1)
            return
        if ctrl and key == pygame.K_DOWN:
            self._script_editor_open_relative_file(1)
            return
        if ctrl and key == pygame.K_d:
            line = self.script_editor_lines[self.script_editor_cursor_line]
            self.script_editor_lines.insert(self.script_editor_cursor_line + 1, line)
            self.script_editor_cursor_line += 1
            self.script_editor_cursor_col   = 0
            self._script_editor_mark_dirty()
            self._script_editor_keep_cursor_visible()
            return

        if key == pygame.K_UP:
            self.script_editor_cursor_line -= 1
            self._script_editor_clamp_cursor()
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_DOWN:
            self.script_editor_cursor_line += 1
            self._script_editor_clamp_cursor()
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_LEFT:
            if self.script_editor_cursor_col > 0:
                self.script_editor_cursor_col -= 1
            elif self.script_editor_cursor_line > 0:
                self.script_editor_cursor_line -= 1
                self.script_editor_cursor_col = len(
                    self.script_editor_lines[self.script_editor_cursor_line]
                )
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_RIGHT:
            line = self.script_editor_lines[self.script_editor_cursor_line]
            if self.script_editor_cursor_col < len(line):
                self.script_editor_cursor_col += 1
            elif self.script_editor_cursor_line + 1 < len(self.script_editor_lines):
                self.script_editor_cursor_line += 1
                self.script_editor_cursor_col   = 0
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_HOME:
            self.script_editor_cursor_col = 0
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_END:
            self.script_editor_cursor_col = len(
                self.script_editor_lines[self.script_editor_cursor_line]
            )
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_PAGEUP:
            self.script_editor_cursor_line -= self._script_editor_visible_rows()
            self._script_editor_clamp_cursor()
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_PAGEDOWN:
            self.script_editor_cursor_line += self._script_editor_visible_rows()
            self._script_editor_clamp_cursor()
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_BACKSPACE:
            self._script_editor_backspace()
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_DELETE:
            self._script_editor_delete()
            self._script_editor_keep_cursor_visible()
            return
        if key in (pygame.K_RETURN, pygame.K_KP_ENTER):
            self._script_editor_newline()
            self._script_editor_keep_cursor_visible()
            return
        if key == pygame.K_TAB:
            self._script_editor_insert_text("  ")
            self._script_editor_keep_cursor_visible()
            return

        if ctrl:
            return
        text = event.unicode
        if text and text >= " ":
            self._script_editor_insert_text(text)
            self._script_editor_keep_cursor_visible()

    def _draw_script_editor(self):
        cdef object overlay = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
        overlay.fill((8, 10, 14, 236))
        self.screen.blit(overlay, (0, 0))

        cdef dict layout = self._script_editor_layout()
        cdef int width       = layout["width"]
        cdef int height      = layout["height"]
        cdef int top         = layout["top"]
        cdef int left        = layout["left"]
        cdef int panel_w     = layout["panel_w"]
        cdef int editor_left = layout["editor_left"]
        cdef int gutter_w    = layout["gutter_w"]
        cdef int text_x      = layout["text_x"]
        cdef int line_h      = layout["line_h"]
        cdef int file_row_h  = layout["file_row_h"]
        cdef object font     = self.script_editor_font

        cdef object header = self.inspector_font.render(
            f"Script Editor (F6): {self.script_editor_path}", True, (240, 240, 245)
        )
        self.screen.blit(header, (10, 8))
        cdef object hotkeys_surf = self.inspector_font.render(
            "Ctrl+S save  Ctrl+R save+reload  Ctrl+Up/Down file  "
            "Ctrl+E current script  Ctrl+D dup line  Esc close",
            True, (180, 190, 210),
        )
        self.screen.blit(hotkeys_surf, (10, 26))

        cdef tuple status_color = (255, 200, 120) if self.script_editor_dirty else (130, 220, 150)
        cdef str status = "*" if self.script_editor_dirty else "ok"
        cdef object status_surf = self.inspector_font.render(
            f"[{status}] {self.script_editor_status}", True, status_color
        )
        self.screen.blit(status_surf, (10, 44))

        cdef int rows  = max(1, (height - top - 12) // line_h)
        self._script_editor_keep_cursor_visible()
        cdef int first = self.script_editor_scroll
        cdef int last  = min(len(self.script_editor_lines), first + rows)

        cdef object panel_rect = pygame.Rect(left, top - 2, panel_w, height - top - 6)
        pygame.draw.rect(self.screen, (16, 20, 30), panel_rect)
        pygame.draw.rect(self.screen, (48, 58, 80), panel_rect, 1)
        cdef object panel_title = self.inspector_font.render("Scripts", True, (205, 212, 226))
        self.screen.blit(panel_title, (left + 8, top + 4))

        cdef int list_top   = top + 22
        cdef int file_rows  = max(1, (height - list_top - 10) // file_row_h)
        self._script_editor_clamp_file_scroll()
        cdef int file_start = self.script_editor_file_scroll
        cdef int file_end   = min(len(self.script_editor_files), file_start + file_rows)
        cdef int row, idx, y
        cdef object file_path, txt, bg
        cdef bint active
        cdef str label
        cdef tuple color

        for row in range(file_end - file_start):
            idx       = file_start + row
            y         = list_top + row * file_row_h
            file_path = self.script_editor_files[idx]
            active    = file_path.resolve() == self.script_editor_path.resolve()
            if active:
                bg = pygame.Rect(left + 4, y - 1, panel_w - 8, file_row_h)
                pygame.draw.rect(self.screen, (45, 82, 136), bg, border_radius=3)
            label = self._script_editor_rel_path(file_path)
            color = (248, 250, 255) if active else (178, 186, 204)
            txt   = self.inspector_font.render(label, True, color)
            self.screen.blit(txt, (left + 8, y))

        cdef str line
        cdef object ln
        for row in range(last - first):
            idx  = first + row
            y    = top + row * line_h
            line = self.script_editor_lines[idx]
            ln   = self.inspector_font.render(f"{idx + 1:4d}", True, (120, 130, 150))
            self.screen.blit(ln, (editor_left, y + 1))
            txt  = font.render(line if line else " ", True, (235, 238, 245))
            self.screen.blit(txt, (text_x, y))

        pygame.draw.line(
            self.screen, (45, 55, 72),
            (editor_left + gutter_w, top),
            (editor_left + gutter_w, height - 8),
            1,
        )
        pygame.draw.rect(
            self.screen,
            (55, 65, 84),
            pygame.Rect(editor_left - 2, top - 2, width - editor_left - 8, height - top - 6),
            1,
        )

        cdef bint blink_on = (pygame.time.get_ticks() // 500) % 2 == 0
        cdef int cl, cc, cursor_y, cursor_x
        cdef str prefix
        if blink_on:
            cl = self.script_editor_cursor_line
            cc = self.script_editor_cursor_col
            if first <= cl < last:
                cursor_y = top + (cl - first) * line_h
                prefix   = self.script_editor_lines[cl][:cc]
                cursor_x = text_x + font.size(prefix)[0]
                pygame.draw.line(
                    self.screen, (255, 255, 255),
                    (cursor_x, cursor_y),
                    (cursor_x, cursor_y + line_h - 1),
                    2,
                )
