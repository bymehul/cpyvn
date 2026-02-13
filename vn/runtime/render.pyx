from __future__ import annotations

import math
import random
from typing import Tuple

import cython
import pygame

from .state import SpriteInstance


@cython.cfunc
@cython.inline
cdef int _clamp_u8(int value):
    if value < 0:
        return 0
    if value > 255:
        return 255
    return value


@cython.cfunc
@cython.inline
cdef double _clamp01(double value):
    if value < 0.0:
        return 0.0
    if value > 1.0:
        return 1.0
    return value


class RenderMixin:
    def _render(self) -> None:
        if self.title_menu_active:
            self._draw_title_menu()
            return
        self._draw_background()
        draw_video = getattr(self, "_draw_video_layer", None)
        if callable(draw_video):
            draw_video()
        for sprite in self._sorted_sprites():
            self._draw_sprite(sprite)
        if (self.hotspot_debug or self.show_hotspot_editor) and self.hotspots:
            self._draw_hotspots()
        if self.hud_buttons:
            self._draw_hud_buttons()

        if self.current_choice is not None:
            options = [opt[0] for opt in self.current_choice.options]
            self.choice_hitboxes = self.textbox.draw_choices(
                self.screen, options, self.choice_selected, prompt=self.current_choice.prompt
            )
            if self.choice_timeout_ms is not None:
                self._draw_choice_timer()
        elif self.input_active:
            self._draw_input()
            self.choice_hitboxes = []
        else:
            if self.current_say is not None:
                speaker, text = self.current_say
                display_name, name_color = self._resolve_speaker(speaker)
                visible_text, _ = self._visible_text(text)
                self.textbox.draw_dialogue(self.screen, display_name, visible_text, name_color=name_color)
            self.choice_hitboxes = []

        if self.phone_active:
            self._draw_phone()

        if self.meters:
            self._draw_meters()
            
        if self.map_active:
            self._draw_map()
            
        if self.inventory_active:
            self._draw_inventory()

        self._draw_blend()

        if self._is_notify_active():
            self.textbox.draw_notify(self.screen, self.notify_message or "")

        if self.show_perf and self.dev_mode:
            self._draw_perf()

        if self.loading_active:
            self.textbox.draw_loading(self.screen, self.loading_text)

        if self.show_inspector:
            self._draw_inspector()
        if self.show_hotspot_editor:
            self._draw_hotspot_editor()
        if self.show_hud_editor:
            self._draw_hud_editor()
        if self.show_script_editor:
            self._draw_script_editor()
        if self.show_debug_menu:
            self._draw_debug_menu()
        if self.pause_menu_active:
            self._draw_pause_menu()

    def _draw_hotspots(self) -> None:
        cdef object overlay
        cdef object font
        cdef object hotspot
        cdef list points
        cdef bint hovered
        cdef object fill
        cdef object border
        cdef str label
        cdef object text
        cdef object text_bg
        cdef double min_x
        cdef double min_y
        cdef tuple point
        cdef int tx
        cdef int ty
        overlay = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
        font = self.perf_font
        for hotspot in self.hotspots.values():
            points = self._hotspot_screen_points(hotspot)
            if len(points) < 3:
                continue
            hovered = hotspot.name == self.hotspot_hovered
            fill = (255, 90, 90, 64) if hovered else (60, 210, 255, 46)
            border = (255, 120, 120) if hovered else (120, 230, 255)
            pygame.draw.polygon(overlay, fill, points)
            pygame.draw.polygon(overlay, border, points, 2)
            label = f"{hotspot.name} -> {hotspot.target}"
            text = font.render(label, True, border)
            text_bg = pygame.Surface((text.get_width() + 6, text.get_height() + 4), pygame.SRCALPHA)
            text_bg.fill((0, 0, 0, 155))
            min_x = float(points[0][0])
            min_y = float(points[0][1])
            for point in points[1:]:
                if float(point[0]) < min_x:
                    min_x = float(point[0])
                if float(point[1]) < min_y:
                    min_y = float(point[1])
            tx = int(min_x)
            ty = max(0, int(min_y) - text_bg.get_height())
            overlay.blit(text_bg, (tx, ty))
            overlay.blit(text, (tx + 3, ty + 2))
        self.screen.blit(overlay, (0, 0))

    def _draw_hud_buttons(self) -> None:
        cdef object btn
        cdef bint hovered
        cdef object fill
        cdef object border
        cdef object text_surf
        cdef int tx, ty
        cdef object icon
        cdef int icon_x, text_x
        for btn in self.hud_buttons.values():
            hovered = btn.name == self.hud_hovered
            if hovered:
                fill = (60, 80, 120, 210)
                border = (255, 220, 120)
            else:
                fill = (30, 30, 40, 180)
                border = (160, 170, 190)
            bg = pygame.Surface((btn.rect.width, btn.rect.height), pygame.SRCALPHA)
            bg.fill(fill)
            self.screen.blit(bg, btn.rect.topleft)
            pygame.draw.rect(self.screen, border, btn.rect, 2, border_radius=6)

            if btn.style == "icon" and btn.icon_surface is not None:
                icon = btn.icon_surface
                icon_x = btn.rect.x + (btn.rect.width - icon.get_width()) // 2
                ty = btn.rect.y + (btn.rect.height - icon.get_height()) // 2
                self.screen.blit(icon, (icon_x, ty))
            elif btn.style == "both" and btn.icon_surface is not None and btn.text:
                icon = btn.icon_surface
                icon_h = min(btn.rect.height - 4, icon.get_height())
                icon_w = int(icon.get_width() * (icon_h / max(1, icon.get_height())))
                scaled_icon = pygame.transform.smoothscale(icon, (icon_w, icon_h))
                icon_x = btn.rect.x + 6
                ty = btn.rect.y + (btn.rect.height - icon_h) // 2
                self.screen.blit(scaled_icon, (icon_x, ty))
                text_surf = self.perf_font.render(btn.text, True, (245, 245, 245))
                text_x = icon_x + icon_w + 6
                ty = btn.rect.y + (btn.rect.height - text_surf.get_height()) // 2
                self.screen.blit(text_surf, (text_x, ty))
            elif btn.text:
                text_surf = self.perf_font.render(btn.text, True, (245, 245, 245))
                tx = btn.rect.x + (btn.rect.width - text_surf.get_width()) // 2
                ty = btn.rect.y + (btn.rect.height - text_surf.get_height()) // 2
                self.screen.blit(text_surf, (tx, ty))

    def _draw_hud_editor(self) -> None:
        cdef str mode = self.hud_editor_mode
        cdef object panel = pygame.Surface((self.screen.get_width(), 56), pygame.SRCALPHA)
        panel.fill((8, 8, 10, 185))
        self.screen.blit(panel, (0, 0))

        cdef object title_surf = self.inspector_font.render(
            "HUD Editor (F7): 1 Select  2 Rect  Arrow=move  Del remove  C copy  T target  Esc close",
            True, (240, 240, 240),
        )
        self.screen.blit(title_surf, (10, 8))

        cdef list buttons = [
            ("mode_select", "Select", mode == "select"),
            ("mode_rect",   "Rect",   mode == "rect"),
            ("copy",        "Copy",   False),
            ("delete",      "Delete", False),
            ("clear",       "Clear",  False),
        ]
        self.hud_editor_buttons = {}
        cdef int x = 10, y = 28, bw
        cdef str key, label
        cdef bint active
        cdef object rect, color, txt
        for key, label, active in buttons:
            bw = 74
            rect = pygame.Rect(x, y, bw, 22)
            self.hud_editor_buttons[key] = rect
            color = (80, 170, 255) if active else (70, 70, 80)
            pygame.draw.rect(self.screen, color, rect, border_radius=4)
            pygame.draw.rect(self.screen, (220, 220, 220), rect, 1, border_radius=4)
            txt = self.inspector_font.render(label, True, (245, 245, 245))
            self.screen.blit(txt, (rect.x + 6, rect.y + 3))
            x += bw + 6

        cdef str selected = self.hud_editor_selected or "-"
        cdef str hovered_name = self.hud_hovered or "-"
        cdef str status = f"selected: {selected} | hovered: {hovered_name} | buttons: {len(self.hud_buttons)}"
        cdef object status_surf = self.inspector_font.render(status, True, (230, 230, 150))
        self.screen.blit(status_surf, (x + 8, y + 3))

        if mode == "rect" and self.hud_editor_preview_rect is not None:
            pr = self.hud_editor_preview_rect
            preview_rect = pygame.Rect(pr[0], pr[1], pr[2], pr[3])
            preview_surf = pygame.Surface((preview_rect.width, preview_rect.height), pygame.SRCALPHA)
            preview_surf.fill((255, 255, 120, 40))
            self.screen.blit(preview_surf, preview_rect.topleft)
            pygame.draw.rect(self.screen, (255, 255, 120), preview_rect, 2)

        cdef object btn
        for btn in self.hud_buttons.values():
            btn_color = (255, 120, 80) if btn.name == self.hud_editor_selected else (120, 230, 255)
            pygame.draw.rect(self.screen, btn_color, btn.rect, 2)
            info = f"{btn.name} ({btn.rect.x},{btn.rect.y}) {btn.rect.width}x{btn.rect.height} -> {btn.target}"
            info_surf = self.inspector_font.render(info, True, btn_color)
            self.screen.blit(info_surf, (btn.rect.x, max(0, btn.rect.y - info_surf.get_height() - 2)))

    def _draw_background(self) -> None:
        cdef int now
        cdef int elapsed
        cdef double t
        cdef str style
        cdef object start
        cdef object end
        cdef tuple start_pos
        cdef tuple end_pos
        cdef int alpha
        cdef object overlay
        cdef int width
        cdef int height
        cdef int reveal_width
        cdef object src
        cdef int offset
        cdef int x
        cdef int y
        cdef int w
        cdef int h
        cdef double threshold
        cdef double scale
        cdef int zoom_w
        cdef int zoom_h
        cdef object zoomed
        cdef object rect
        cdef int flash
        cdef object white
        cdef int amp
        cdef int dx
        cdef int dy
        cdef object start_blur
        cdef object end_blur
        if (
            self.bg_transition_start is None
            or self.bg_transition_end is None
            or self.bg_transition_start_ms is None
            or self.bg_transition_duration_ms <= 0
            or self.bg_transition_style is None
        ):
            self._blit_bg_with_camera(
                self.background_surface,
                self.background_state.float_amp,
                self.background_state.float_speed,
            )
            return

        now = pygame.time.get_ticks()
        elapsed = now - self.bg_transition_start_ms
        if elapsed >= self.bg_transition_duration_ms:
            self.bg_transition_start = None
            self.bg_transition_end = None
            self.bg_transition_style = None
            self.bg_transition_start_ms = None
            self.bg_transition_duration_ms = 0
            self.bg_transition_dissolve_tiles = []
            self._blit_bg_with_camera(
                self.background_surface,
                self.background_state.float_amp,
                self.background_state.float_speed,
            )
            return

        t = elapsed / self.bg_transition_duration_ms
        style = self.bg_transition_style
        start = self.bg_transition_start
        end = self.bg_transition_end
        start_pos = self._bg_draw_pos(start, None, None)
        end_pos = self._bg_draw_pos(end, self.background_state.float_amp, self.background_state.float_speed)

        if style == "fade":
            alpha = _clamp_u8(int(255 * t))
            self.screen.blit(start, start_pos)
            overlay = end.copy()
            overlay.set_alpha(alpha)
            self.screen.blit(overlay, end_pos)
            return

        if style == "wipe":
            width, height = self.screen.get_size()
            reveal_width = int(width * t)
            self.screen.blit(start, start_pos)
            if reveal_width > 0:
                src = pygame.Rect(0, 0, reveal_width, height)
                self.screen.blit(end, (0, 0), src)
            return

        if style == "slide":
            width, _ = self.screen.get_size()
            offset = int(width * t)
            self.screen.fill((0, 0, 0))
            self.screen.blit(start, (-offset, start_pos[1]))
            self.screen.blit(end, (width - offset, end_pos[1]))
            return

        if style == "dissolve":
            if not self.bg_transition_dissolve_tiles:
                self.bg_transition_dissolve_tiles = self._make_dissolve_tiles()
            self.screen.blit(start, start_pos)
            for x, y, w, h, threshold in self.bg_transition_dissolve_tiles:
                if threshold <= t:
                    area = pygame.Rect(x, y, w, h)
                    self.screen.blit(end, (x, y), area)
            return

        if style == "zoom":
            width, height = self.screen.get_size()
            self.screen.blit(end, end_pos)
            scale = 1.0 + (0.22 * t)
            zoom_w = max(1, int(width * scale))
            zoom_h = max(1, int(height * scale))
            zoomed = pygame.transform.smoothscale(start, (zoom_w, zoom_h))
            rect = zoomed.get_rect(center=(width // 2, height // 2))
            zoomed.set_alpha(_clamp_u8(int((1.0 - t) * 220)))
            self.screen.blit(zoomed, rect)
            return

        if style == "blur":
            start_blur = self._blur_surface(start, 2 + int(t * 14))
            end_blur = self._blur_surface(end, 2 + int((1.0 - t) * 14))
            self.screen.blit(start_blur, start_pos)
            end_blur.set_alpha(_clamp_u8(int(255 * t)))
            self.screen.blit(end_blur, end_pos)
            return

        if style == "flash":
            alpha = _clamp_u8(int(255 * t))
            self.screen.blit(start, start_pos)
            overlay = end.copy()
            overlay.set_alpha(alpha)
            self.screen.blit(overlay, end_pos)
            flash = max(0, int((1.0 - t * 2.2) * 230))
            if flash > 0:
                white = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
                white.fill((255, 255, 255, flash))
                self.screen.blit(white, (0, 0))
            return

        if style == "shake":
            amp = max(0, int((1.0 - t) * 22))
            dx = int(math.sin(now * 0.037) * amp)
            dy = int(math.cos(now * 0.049) * amp)
            self.screen.fill((0, 0, 0))
            self.screen.blit(end, (dx, dy))
            return

        # Unknown style fallback
        alpha = max(0, min(255, int(255 * t)))
        self.screen.blit(start, start_pos)
        overlay = end.copy()
        overlay.set_alpha(alpha)
        self.screen.blit(overlay, end_pos)

    def _draw_sprite(self, sprite: SpriteInstance) -> None:
        st = sprite.state
        if st.transition_style and st.transition_start_ms is not None and st.transition_duration_ms > 0:
            if self._draw_sprite_transition(sprite):
                return
        alpha = st.alpha
        if st.fade_start_ms is not None and st.fade_duration_ms > 0:
            now = pygame.time.get_ticks()
            elapsed = now - st.fade_start_ms
            if elapsed >= st.fade_duration_ms:
                alpha = st.fade_to
                st.alpha = alpha
                st.fade_start_ms = None
                st.fade_duration_ms = 0
                st.fade_from = alpha
                st.fade_to = alpha
                if st.fade_remove and alpha <= 0:
                    name = self._find_sprite_name(sprite)
                    if name:
                        del self.sprites[name]
                        animations = getattr(self, "sprite_animations", None)
                        if isinstance(animations, dict):
                            animations.pop(name, None)
                    return
            else:
                t = elapsed / st.fade_duration_ms
                alpha = int(st.fade_from + (st.fade_to - st.fade_from) * t)
                alpha = max(0, min(255, alpha))
                st.alpha = alpha
        offset_x, offset_y = self._float_offset(st.float_amp, st.float_speed, st.float_phase)
        if alpha < 255:
            sprite.surface.set_alpha(alpha)
        else:
            sprite.surface.set_alpha(None)
        if offset_x or offset_y:
            self.screen.blit(sprite.surface, sprite.rect.move(offset_x, offset_y))
        else:
            self.screen.blit(sprite.surface, sprite.rect)

    def _draw_sprite_transition(self, sprite: SpriteInstance) -> bool:
        cdef object st
        cdef int now
        cdef int elapsed
        cdef double progress
        cdef double t
        cdef str style
        cdef object base
        cdef object rect
        cdef int width
        cdef int offset
        cdef int tile
        cdef int y
        cdef int h
        cdef int x
        cdef int w
        cdef int seed
        cdef double threshold
        cdef double scale
        cdef int zw
        cdef int zh
        cdef object zoomed
        cdef object zrect
        cdef int strength
        cdef object blurred
        cdef int flash
        cdef object overlay
        cdef int amp
        cdef int dx
        cdef int dy
        cdef object temp
        cdef str name
        cdef object animations
        st = sprite.state
        if st.transition_start_ms is None or st.transition_duration_ms <= 0 or st.transition_style is None:
            return False

        now = pygame.time.get_ticks()
        elapsed = now - st.transition_start_ms
        progress = min(1.0, max(0.0, elapsed / st.transition_duration_ms))
        if st.transition_mode == "out":
            t = 1.0 - progress
        else:
            t = progress

        style = st.transition_style
        base = sprite.surface
        rect = sprite.rect

        if style == "wipe":
            width = max(0, min(rect.width, int(rect.width * t)))
            if width > 0:
                area = pygame.Rect(0, 0, width, rect.height)
                self.screen.blit(base, rect.topleft, area)
        elif style == "slide":
            offset = int((1.0 - t) * rect.width)
            if st.transition_mode == "out":
                offset = int(progress * rect.width)
            self.screen.blit(base, (rect.x + offset, rect.y))
        elif style == "dissolve":
            tile = 8
            for y in range(0, rect.height, tile):
                h = min(tile, rect.height - y)
                for x in range(0, rect.width, tile):
                    w = min(tile, rect.width - x)
                    seed = (x * 73856093) ^ (y * 19349663) ^ st.transition_seed
                    threshold = (seed & 0xFFFF) / 65535.0
                    if threshold <= t:
                        area = pygame.Rect(x, y, w, h)
                        self.screen.blit(base, (rect.x + x, rect.y + y), area)
        elif style == "zoom":
            scale = 1.2 - (0.2 * t) if st.transition_mode == "in" else 1.0 + (0.2 * progress)
            zw = max(1, int(rect.width * scale))
            zh = max(1, int(rect.height * scale))
            zoomed = pygame.transform.smoothscale(base, (zw, zh))
            zrect = zoomed.get_rect(center=rect.center)
            zoomed.set_alpha(_clamp_u8(int(255 * t)))
            self.screen.blit(zoomed, zrect)
        elif style == "blur":
            if st.transition_mode == "in":
                strength = max(1, int((1.0 - t) * 14))
            else:
                strength = max(1, int(progress * 14))
            blurred = self._blur_surface(base, strength)
            if st.transition_mode == "in":
                blurred.set_alpha(None)
            else:
                blurred.set_alpha(_clamp_u8(int(255 * t)))
            self.screen.blit(blurred, rect)
        elif style == "flash":
            self.screen.blit(base, rect)
            flash = max(0, int((1.0 - progress * 2.0) * 220))
            if flash > 0:
                overlay = pygame.Surface((rect.width, rect.height), pygame.SRCALPHA)
                overlay.fill((255, 255, 255, flash))
                self.screen.blit(overlay, rect.topleft)
        elif style == "shake":
            amp = max(0, int((1.0 - progress) * 10))
            dx = int(math.sin(now * 0.041 + st.transition_seed) * amp)
            dy = int(math.cos(now * 0.053 + st.transition_seed) * amp)
            self.screen.blit(base, rect.move(dx, dy))
        else:
            # Fallback behaves like fade for unknown style.
            temp = base.copy()
            temp.set_alpha(_clamp_u8(int(255 * t)))
            self.screen.blit(temp, rect)

        if progress >= 1.0:
            st.transition_style = None
            st.transition_start_ms = None
            st.transition_duration_ms = 0
            if st.transition_remove:
                name = self._find_sprite_name(sprite)
                if name:
                    del self.sprites[name]
                    animations = getattr(self, "sprite_animations", None)
                    if isinstance(animations, dict):
                        animations.pop(name, None)
                    return True
            st.transition_remove = False
        return False

    def _make_dissolve_tiles(self) -> list[tuple[int, int, int, int, float]]:
        cdef int width, height
        cdef int tile_size = 16
        cdef int y
        cdef int x
        cdef int tile_h
        cdef int tile_w
        cdef object rng
        cdef list tiles = []
        width, height = self.screen.get_size()
        rng = random.Random(pygame.time.get_ticks())
        for y in range(0, height, tile_size):
            tile_h = min(tile_size, height - y)
            for x in range(0, width, tile_size):
                tile_w = min(tile_size, width - x)
                tiles.append((x, y, tile_w, tile_h, rng.random()))
        return tiles

    def _find_sprite_name(self, sprite: SpriteInstance) -> str:
        for name, item in self.sprites.items():
            if item is sprite:
                return name
        return ""

    def _float_phase_for(self, name: str) -> float:
        cdef int total = 0
        cdef str ch
        for ch in name:
            total += ord(ch)
        return (total % 360) * (math.pi / 180.0)

    def _float_offset(self, amp: float | None, speed: float | None, phase: float = 0.0) -> Tuple[int, int]:
        if amp is None:
            return 0, 0
        cdef double amp_val = max(0.0, float(amp))
        cdef double speed_val
        cdef double t
        cdef double angle
        cdef double dx
        cdef double dy
        if amp_val <= 0:
            return 0, 0
        speed_val = float(speed) if speed is not None else 0.2
        if speed_val <= 0:
            speed_val = 0.2
        t = pygame.time.get_ticks() / 1000.0
        angle = t * speed_val * math.tau + phase
        dx = math.sin(angle) * amp_val
        dy = math.cos(angle * 0.9) * amp_val
        return int(dx), int(dy)

    def _bg_draw_pos(self, surface: pygame.Surface, float_amp: float | None, float_speed: float | None) -> Tuple[int, int]:
        cdef int screen_w
        cdef int screen_h
        cdef int surf_w
        cdef int surf_h
        cdef int base_x
        cdef int base_y
        cdef int offset_x
        cdef int offset_y
        cdef int max_x
        cdef int max_y
        screen_w, screen_h = self.screen.get_size()
        surf_w, surf_h = surface.get_size()
        base_x = (screen_w - surf_w) // 2
        base_y = (screen_h - surf_h) // 2
        offset_x, offset_y = self._float_offset(float_amp, float_speed)
        max_x = max(0, (surf_w - screen_w) // 2)
        max_y = max(0, (surf_h - screen_h) // 2)
        if offset_x > max_x:
            offset_x = max_x
        elif offset_x < -max_x:
            offset_x = -max_x
        if offset_y > max_y:
            offset_y = max_y
        elif offset_y < -max_y:
            offset_y = -max_y
        return base_x + offset_x, base_y + offset_y

    def _blit_bg_with_camera(
        self,
        surface: pygame.Surface,
        float_amp: float | None,
        float_speed: float | None,
    ) -> None:
        cdef object transform_fn
        cdef tuple pos
        cdef double center_x
        cdef double center_y
        cdef double zoom
        cdef double surf_w
        cdef double surf_h
        cdef object draw_surface
        cdef int scaled_w
        cdef int scaled_h
        cdef object rect
        transform_fn = getattr(self, "_bg_transform", None)
        if not callable(transform_fn):
            pos = self._bg_draw_pos(surface, float_amp, float_speed)
            self.screen.blit(surface, pos)
            return

        center_x, center_y, zoom, surf_w, surf_h = transform_fn(surface, float_amp, float_speed)
        draw_surface = surface
        if abs(zoom - 1.0) > 0.0001:
            scaled_w = max(1, int(round(surf_w * zoom)))
            scaled_h = max(1, int(round(surf_h * zoom)))
            draw_surface = pygame.transform.smoothscale(surface, (scaled_w, scaled_h))
        rect = draw_surface.get_rect(center=(int(round(center_x)), int(round(center_y))))
        self.screen.blit(draw_surface, rect)

    def _draw_blend(self) -> None:
        cdef int now
        cdef int elapsed
        cdef double progress
        cdef str style
        cdef object current
        cdef object snapshot
        if self.blend_start_ms is None or self.blend_style is None:
            return
        now = pygame.time.get_ticks()
        elapsed = now - self.blend_start_ms
        if elapsed >= self.blend_duration_ms:
            self._end_blend()
            return
        progress = _clamp01(elapsed / self.blend_duration_ms)
        style = self.blend_style
        current = self.screen.copy()
        snapshot = self.blend_snapshot if self.blend_snapshot is not None else current

        if style == "fade":
            self._draw_blend_fade(progress)
            return
        if style == "flash":
            self._draw_blend_flash(progress)
            return
        if style == "wipe":
            self._draw_blend_wipe(snapshot, current, progress)
            return
        if style == "slide":
            self._draw_blend_slide(snapshot, current, progress)
            return
        if style == "dissolve":
            self._draw_blend_dissolve(snapshot, current, progress)
            return
        if style == "zoom":
            self._draw_blend_zoom(snapshot, current, progress)
            return
        if style == "blur":
            self._draw_blend_blur(snapshot, current, progress)
            return
        if style == "shake":
            self._draw_blend_shake(current, progress)
            return
        if style == "none":
            self._end_blend()
            return
        # Fallback for unknown style.
        self._draw_blend_fade(progress)

    def _end_blend(self) -> None:
        self.blend_start_ms = None
        self.blend_style = None
        self.blend_duration_ms = 0
        self.blend_snapshot = None
        self.blend_dissolve_tiles = []

    def _draw_blend_fade(self, progress: float) -> None:
        cdef int alpha
        cdef object overlay
        if progress < 0.5:
            alpha = int(progress * 2 * 255)
        else:
            alpha = int((1 - (progress - 0.5) * 2) * 255)
        overlay = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, _clamp_u8(alpha)))
        self.screen.blit(overlay, (0, 0))

    def _draw_blend_flash(self, progress: float) -> None:
        cdef double fade = max(0.0, 1.0 - progress * 2.4)
        cdef int alpha = int(255 * fade)
        cdef object overlay
        if alpha <= 0:
            return
        overlay = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
        overlay.fill((255, 255, 255, _clamp_u8(alpha)))
        self.screen.blit(overlay, (0, 0))

    def _draw_blend_wipe(self, snapshot: pygame.Surface, current: pygame.Surface, progress: float) -> None:
        cdef int width
        cdef int height
        cdef int reveal_width
        cdef object src
        width, height = self.screen.get_size()
        reveal_width = int(width * progress)
        self.screen.blit(snapshot, (0, 0))
        if reveal_width <= 0:
            return
        src = pygame.Rect(0, 0, reveal_width, height)
        self.screen.blit(current, (0, 0), src)

    def _draw_blend_slide(self, snapshot: pygame.Surface, current: pygame.Surface, progress: float) -> None:
        cdef int width
        cdef int offset
        width, _ = self.screen.get_size()
        offset = int(width * progress)
        self.screen.fill((0, 0, 0))
        self.screen.blit(snapshot, (-offset, 0))
        self.screen.blit(current, (width - offset, 0))

    def _draw_blend_dissolve(self, snapshot: pygame.Surface, current: pygame.Surface, progress: float) -> None:
        cdef int x
        cdef int y
        cdef int w
        cdef int h
        cdef double threshold
        cdef object area
        if not self.blend_dissolve_tiles:
            self._prepare_dissolve_tiles()
        self.screen.blit(snapshot, (0, 0))
        for x, y, w, h, threshold in self.blend_dissolve_tiles:
            if threshold <= progress:
                area = pygame.Rect(x, y, w, h)
                self.screen.blit(current, (x, y), area)

    def _draw_blend_zoom(self, snapshot: pygame.Surface, current: pygame.Surface, progress: float) -> None:
        cdef int width
        cdef int height
        cdef double scale
        cdef int zoom_w
        cdef int zoom_h
        cdef object zoomed
        cdef object rect
        width, height = self.screen.get_size()
        self.screen.blit(current, (0, 0))
        scale = 1.0 + (0.22 * progress)
        zoom_w = max(1, int(width * scale))
        zoom_h = max(1, int(height * scale))
        zoomed = pygame.transform.smoothscale(snapshot, (zoom_w, zoom_h))
        rect = zoomed.get_rect(center=(width // 2, height // 2))
        zoomed.set_alpha(_clamp_u8(int((1.0 - progress) * 220)))
        self.screen.blit(zoomed, rect)

    def _draw_blend_blur(self, snapshot: pygame.Surface, current: pygame.Surface, progress: float) -> None:
        cdef double pulse
        cdef int pulse_strength
        cdef object base
        cdef object overlay
        cdef object blurred
        # Make blur visually obvious even when there is no scene change.
        pulse = 1.0 - abs(progress * 2.0 - 1.0)  # 0 -> 1 -> 0
        pulse_strength = 6 + int(pulse * 26)  # up to ~32 (max gaussian radius)

        base = snapshot.copy()
        overlay = current.copy()
        overlay.set_alpha(max(0, min(255, int(progress * 255))))
        base.blit(overlay, (0, 0))

        # Full-screen blend blur on some wgpu drivers is unstable/weak.
        # Use the CPU path here for consistent visuals; sprite/scene blur can still use GPU.
        self._blur_last_path = "cpu-blend"
        blurred = self._blur_surface_cpu(base, pulse_strength)
        self.screen.blit(base, (0, 0))
        blurred.set_alpha(_clamp_u8(int(40 + pulse * 215)))
        self.screen.blit(blurred, (0, 0))

    def _draw_blend_shake(self, current: pygame.Surface, progress: float) -> None:
        cdef int amp = max(0, int((1.0 - progress) * 18))
        cdef int now
        cdef int dx
        cdef int dy
        if amp <= 0:
            return
        now = pygame.time.get_ticks()
        dx = int(math.sin(now * 0.037) * amp)
        dy = int(math.cos(now * 0.049) * amp)
        self.screen.fill((0, 0, 0))
        self.screen.blit(current, (dx, dy))

    def _prepare_dissolve_tiles(self) -> None:
        self.blend_dissolve_tiles = self._make_dissolve_tiles()

    def _blur_surface(self, surface: pygame.Surface, strength: int) -> pygame.Surface:
        cdef object gpu_surface
        if strength <= 1:
            self._blur_last_path = "none"
            return surface.copy()
        # Placeholder for optional GPU path.
        gpu_surface = self._try_wgpu_blur(surface, strength)
        if gpu_surface is not None:
            self._blur_last_path = "gpu"
            return gpu_surface
        self._blur_last_path = "cpu"
        self._blur_cpu_calls += 1
        return self._blur_surface_cpu(surface, strength)

    def _try_wgpu_blur(self, surface: pygame.Surface, strength: int) -> pygame.Surface | None:
        blur_fn = getattr(self.assets, "blur_wgpu", None)
        if not callable(blur_fn):
            return None
        try:
            return blur_fn(surface, strength)
        except Exception:
            return None

    def _blur_surface_cpu(self, surface: pygame.Surface, strength: int) -> pygame.Surface:
        cdef int width, height
        cdef int factor
        cdef int small_w
        cdef int small_h
        cdef object tmp
        width, height = surface.get_size()
        if width <= 1 or height <= 1:
            return surface.copy()
        factor = max(2, min(24, strength + 1))
        small_w = max(1, width // factor)
        small_h = max(1, height // factor)
        tmp = pygame.transform.smoothscale(surface, (small_w, small_h))
        return pygame.transform.smoothscale(tmp, (width, height))

    def _draw_perf(self) -> None:
        cdef int now
        cdef list lines
        cdef object stats
        cdef int v_dec
        cdef int v_drop
        cdef int a_dec
        cdef int a_drop
        cdef int q_depth
        cdef int q_peak
        cdef int lag_ms
        cdef object getter
        cdef object item
        cdef object active_sprite
        cdef str name
        cdef object sprite
        cdef object st
        cdef int elapsed
        cdef int pct
        cdef list surfaces
        cdef object line
        cdef object line_surface
        cdef int width
        cdef int height
        cdef object surface
        cdef int y
        now = pygame.time.get_ticks()
        if now >= self._perf_next_update_ms:
            lines = [
                f"FPS: {self._fps:0.1f}",
                f"Frame: {self._frame_ms} ms",
                f"Res: {self.screen.get_width()}x{self.screen.get_height()}",
                f"Sprites: {len(self.sprites)}",
                "F3 Inspector  F4 Hotspot  F5 Save  F6 Script  F7 HUD  F9 Load",
                "Ctrl+M Debug Menu  Esc Pause  I Inventory",
            ]
            if getattr(self, "video_path", None):
                lines.append(f"Video: {self.video_path} ({self.video_fit})")
                lines.append(f"Video Backend: {self.video_backend_active}")
                lines.append(f"Video Audio: {'on' if self.video_audio_backend_active else 'off'}")
                if self.video_framedrop == "auto":
                    lines.append(f"Framedrop: auto ({self.video_framedrop_effective})")
                else:
                    lines.append(f"Framedrop: {self.video_framedrop}")
                audio_q = len(getattr(self, "video_audio_pending", []))
                audio_buf = len(getattr(self, "video_audio_pcm_buffer", b""))
                lines.append(f"Video Audio Queue: {audio_q}")
                if audio_buf > 0:
                    lines.append(f"Video Audio Buffer: {audio_buf} bytes")
                stats = getattr(self, "video_stats", None)
                if isinstance(stats, dict) and stats:
                    v_dec = int(stats.get("decoded_video_frames", 0))
                    v_drop = int(stats.get("dropped_video_frames", 0))
                    a_dec = int(stats.get("decoded_audio_packets", 0))
                    a_drop = int(stats.get("dropped_audio_packets", 0))
                    q_depth = int(stats.get("video_queue_depth", 0))
                    q_peak = int(stats.get("max_video_queue_depth", 0))
                    lag_ms = int(stats.get("lag_ms", 0))
                    lines.append(f"Video Frames: dec {v_dec} drop {v_drop} q {q_depth}/{q_peak}")
                    lines.append(f"Video Audio Pkts: dec {a_dec} drop {a_drop}")
                    lines.append(f"Video Lag: {lag_ms} ms")
            lines.append(
                f"Camera: pan({self.camera_pan_x:0.1f},{self.camera_pan_y:0.1f}) zoom {self.camera_zoom:0.2f}"
            )
            if self.hotspots:
                lines.append(f"Hotspots: {len(self.hotspots)}")
                if self.hotspot_debug:
                    lines.append(f"HS Hover: {self.hotspot_hovered or '-'}")
            if self.show_hotspot_editor:
                lines.append(f"HS Edit: {self.hotspot_editor_mode}")
            getter = getattr(self.assets, "get_gpu_specs_lines", None)
            if callable(getter):
                try:
                    for item in getter():
                        lines.append(str(item))
                except Exception:
                    lines.append("GPU: unavailable")
            if self._blur_cpu_calls > 0:
                lines.append(f"Blur CPU Calls: {self._blur_cpu_calls}")
            lines.append(f"Blur Path: {self._blur_last_path}")

            if self.blend_style and self.blend_start_ms is not None and self.blend_duration_ms > 0:
                elapsed = max(0, now - self.blend_start_ms)
                pct = int(min(100, (elapsed / self.blend_duration_ms) * 100))
                lines.append(f"Blend FX: {self.blend_style} {pct}%")

            if self.bg_transition_style and self.bg_transition_start_ms is not None and self.bg_transition_duration_ms > 0:
                elapsed = max(0, now - self.bg_transition_start_ms)
                pct = int(min(100, (elapsed / self.bg_transition_duration_ms) * 100))
                lines.append(f"BG FX: {self.bg_transition_style} {pct}%")

            active_sprite = None
            for name, sprite in self.sprites.items():
                st = sprite.state
                if st.transition_style and st.transition_start_ms is not None and st.transition_duration_ms > 0:
                    elapsed = max(0, now - st.transition_start_ms)
                    pct = int(min(100, (elapsed / st.transition_duration_ms) * 100))
                    active_sprite = (name, st.transition_style, pct)
                    break
            if active_sprite is not None:
                lines.append(f"SP FX: {active_sprite[0]} {active_sprite[1]} {active_sprite[2]}%")
            surfaces = []
            for line in lines:
                surfaces.append(self.perf_font.render(line, True, (255, 255, 255)))
            width = 0
            height = 0
            for line_surface in surfaces:
                if line_surface.get_width() > width:
                    width = line_surface.get_width()
                height += line_surface.get_height()
            surface = pygame.Surface((width + 12, height + 12), pygame.SRCALPHA)
            surface.fill((0, 0, 0, 140))
            y = 6
            for line_surface in surfaces:
                surface.blit(line_surface, (6, y))
                y += line_surface.get_height()
            self._perf_surface = surface
            self._perf_next_update_ms = now + 200

        if self._perf_surface:
            self.screen.blit(self._perf_surface, (10, 10))

    def _draw_input(self) -> None:
        cdef int sw = self.screen.get_width()
        cdef int sh = self.screen.get_height()
        cdef int box_w = int(sw * 0.6)
        cdef int box_h = 120
        cdef int box_x = (sw - box_w) // 2
        cdef int box_y = (sh - box_h) // 2

        panel = pygame.Surface((box_w, box_h), pygame.SRCALPHA)
        panel.fill((0, 0, 0, 210))
        pygame.draw.rect(panel, (200, 200, 200, 100), panel.get_rect(), 2, border_radius=8)

        font = pygame.font.Font(None, 28)
        prompt_text = self.input_prompt or "Enter text:"
        prompt_surf = font.render(prompt_text, True, (220, 220, 220))
        panel.blit(prompt_surf, (16, 14))

        input_y = 50
        input_h = 36
        input_rect = pygame.Rect(16, input_y, box_w - 32, input_h)
        pygame.draw.rect(panel, (40, 40, 40, 255), input_rect, border_radius=4)
        pygame.draw.rect(panel, (120, 120, 120, 200), input_rect, 1, border_radius=4)

        buf = self.input_buffer
        blink = (pygame.time.get_ticks() // 500) % 2 == 0
        display_text = buf + ("|" if blink else "")
        text_surf = font.render(display_text, True, (240, 240, 240))
        panel.blit(text_surf, (input_rect.x + 8, input_rect.y + 6))

        hint_font = pygame.font.Font(None, 22)
        hint = hint_font.render("Press Enter to confirm", True, (150, 150, 150))
        panel.blit(hint, (16, input_y + input_h + 6))

        self.screen.blit(panel, (box_x, box_y))

    def _draw_phone(self) -> None:
        cdef int sw = self.screen.get_width()
        cdef int sh = self.screen.get_height()
        cdef int phone_w = min(320, int(sw * 0.35))
        cdef int phone_h = min(500, int(sh * 0.75))
        cdef int phone_x = (sw - phone_w) // 2
        cdef int phone_y = (sh - phone_h) // 2

        # Phone frame
        frame = pygame.Surface((phone_w, phone_h), pygame.SRCALPHA)
        frame.fill((25, 25, 35, 240))
        pygame.draw.rect(frame, (80, 80, 100, 180), frame.get_rect(), 3, border_radius=16)

        # Header bar
        header_h = 44
        header = pygame.Surface((phone_w, header_h), pygame.SRCALPHA)
        header.fill((40, 40, 55, 255))
        header_font = pygame.font.Font(None, 26)
        header_font.set_bold(True)
        contact = self.phone_contact or "Unknown"
        name_surf = header_font.render(contact, True, (230, 230, 240))
        header.blit(name_surf, ((phone_w - name_surf.get_width()) // 2, (header_h - name_surf.get_height()) // 2))
        frame.blit(header, (0, 0))

        # Messages area
        msg_font = pygame.font.Font(None, 22)
        msg_y = header_h + 10
        max_msg_w = phone_w - 40
        for side, text in self.phone_messages:
            # Wrap text
            words = text.split()
            lines = []
            current = ""
            for word in words:
                test = current + " " + word if current else word
                if msg_font.size(test)[0] > max_msg_w - 16:
                    if current:
                        lines.append(current)
                    current = word
                else:
                    current = test
            if current:
                lines.append(current)
            if not lines:
                lines = [""]

            line_h = msg_font.get_height()
            bubble_h = len(lines) * (line_h + 2) + 12
            bubble_w = max(msg_font.size(line)[0] for line in lines) + 16
            bubble_w = min(bubble_w, max_msg_w)

            if side == "right":
                bg_color = (50, 100, 200, 220)
                bubble_x = phone_w - bubble_w - 14
            else:
                bg_color = (60, 60, 70, 220)
                bubble_x = 14

            bubble = pygame.Surface((bubble_w, bubble_h), pygame.SRCALPHA)
            bubble.fill(bg_color)
            pygame.draw.rect(bubble, (255, 255, 255, 40), bubble.get_rect(), 1, border_radius=8)

            text_y = 6
            for line in lines:
                line_surf = msg_font.render(line, True, (230, 230, 240))
                bubble.blit(line_surf, (8, text_y))
                text_y += line_h + 2

            frame.blit(bubble, (bubble_x, msg_y))
            msg_y += bubble_h + 6

        self.screen.blit(frame, (phone_x, phone_y))

    def _draw_meters(self) -> None:
        cdef int sw = self.screen.get_width()
        cdef int bar_w = 180
        cdef int bar_h = 20
        cdef int gap = 8
        cdef int pad = 12
        cdef int x = sw - bar_w - pad - 10
        cdef int y = pad

        font = pygame.font.Font(None, 22)

        for name, meter in self.meters.items():
            label = meter.get("label", name)
            min_val = meter.get("min", 0)
            max_val = meter.get("max", 100)
            value = meter.get("value", 0)
            color_hex = meter.get("color", "#ffffff")

            # Parse color
            try:
                c = color_hex.lstrip("#")
                r = int(c[0:2], 16)
                g = int(c[2:4], 16)
                b = int(c[4:6], 16)
                bar_color = (r, g, b)
            except (ValueError, IndexError):
                bar_color = (255, 255, 255)

            # Clamp
            try:
                val = int(value)
            except (TypeError, ValueError):
                val = 0
            range_size = max(max_val - min_val, 1)
            fill = max(0.0, min(1.0, (val - min_val) / range_size))

            # Background panel
            panel_h = bar_h + 24
            panel = pygame.Surface((bar_w + 20, panel_h), pygame.SRCALPHA)
            panel.fill((0, 0, 0, 160))
            pygame.draw.rect(panel, (200, 200, 200, 60), panel.get_rect(), 1, border_radius=6)

            # Label
            label_surf = font.render(f"{label}: {val}", True, (230, 230, 230))
            panel.blit(label_surf, (10, 4))

            # Bar background
            bar_rect = pygame.Rect(10, 22, bar_w, bar_h)
            pygame.draw.rect(panel, (50, 50, 50, 200), bar_rect, border_radius=4)

            # Filled bar
            fill_w = int(bar_w * fill)
            if fill_w > 0:
                fill_rect = pygame.Rect(10, 22, fill_w, bar_h)
                pygame.draw.rect(panel, bar_color, fill_rect, border_radius=4)

            # Bar border
            pygame.draw.rect(panel, (150, 150, 150, 100), bar_rect, 1, border_radius=4)

            self.screen.blit(panel, (x, y))
            y += panel_h + gap

    def _draw_choice_timer(self) -> None:
        if self.choice_timer_start_ms is None or self.choice_timeout_ms is None:
            return
        elapsed = pygame.time.get_ticks() - self.choice_timer_start_ms
        remaining = max(0.0, 1.0 - elapsed / self.choice_timeout_ms)

        cdef int sw = self.screen.get_width()
        cdef int bar_w = int(sw * 0.5)
        cdef int bar_h = 8
        cdef int bar_x = (sw - bar_w) // 2
        cdef int bar_y
        if self.choice_hitboxes:
            bar_y = self.choice_hitboxes[0].top - bar_h - 16
        else:
            bar_y = self.screen.get_height() // 2 - 60

        # Background
        bg = pygame.Surface((bar_w, bar_h), pygame.SRCALPHA)
        bg.fill((40, 40, 40, 180))
        self.screen.blit(bg, (bar_x, bar_y))

        # Filled portion (green->red gradient)
        fill_w = int(bar_w * remaining)
        if fill_w > 0:
            r = int(255 * (1.0 - remaining))
            g = int(255 * remaining)
            fill = pygame.Surface((fill_w, bar_h), pygame.SRCALPHA)
            fill.fill((r, g, 40, 220))
            self.screen.blit(fill, (bar_x, bar_y))

        # Border
        pygame.draw.rect(self.screen, (180, 180, 180, 100), (bar_x, bar_y, bar_w, bar_h), 1, border_radius=3)
    def _draw_map(self) -> None:
        cdef int sw = self.screen.get_width()
        cdef int sh = self.screen.get_height()
        cdef object surface
        cdef object poi_overlay = pygame.Surface((sw, sh), pygame.SRCALPHA)
        cdef tuple mouse_pos = pygame.mouse.get_pos()
        cdef int hovered_idx = -1
        
        # 1. Background image
        if self.map_image:
            surface = self.assets.load_image(self.map_image, "bg")
            if surface:
                surface = pygame.transform.smoothscale(surface, (sw, sh))
                self.screen.blit(surface, (0, 0))
        
        # 2. POIs
        cdef int i
        cdef dict point
        cdef list points
        cdef object color, border
        cdef object txt, bg
        cdef int px, py
        cdef str label
        cdef object label_text
        cdef object label_bg

        for i in range(len(self.map_points)):
            point = self.map_points[i]
            if self._map_poi_contains(point, mouse_pos):
                hovered_idx = i
                break
        if hovered_idx >= 0:
            self.map_hovered = hovered_idx
        else:
            self.map_hovered = None

        # Pass 1: filled clickable areas.
        for i in range(len(self.map_points)):
            point = self.map_points[i]
            points = point.get("points", [])
            if len(points) >= 3:
                if self.map_hovered == i:
                    pygame.draw.polygon(poi_overlay, (255, 214, 102, 138), points, 0)
                else:
                    pygame.draw.polygon(poi_overlay, (70, 190, 240, 74), points, 0)
            else:
                px, py = point["pos"]
                if self.map_hovered == i:
                    pygame.draw.circle(poi_overlay, (255, 214, 102, 110), (px, py), 24)
                else:
                    pygame.draw.circle(poi_overlay, (70, 190, 240, 86), (px, py), 22)
        self.screen.blit(poi_overlay, (0, 0))

        # Pass 2: outlines, markers, labels.
        for i in range(len(self.map_points)):
            point = self.map_points[i]
            points = point.get("points", [])

            if self.map_hovered == i:
                color = (255, 220, 120)
                border = (255, 255, 255)
                px, py = point["pos"]
                txt = self.inspector_font.render(point["label"], True, (255, 255, 255))
                bg = pygame.Surface((txt.get_width() + 10, txt.get_height() + 6), pygame.SRCALPHA)
                bg.fill((0, 0, 0, 180))
                self.screen.blit(bg, (px + 15, py - 10))
                self.screen.blit(txt, (px + 20, py - 7))
            else:
                color = (80, 205, 255)
                border = (10, 35, 60)

            if len(points) >= 3:
                if self.map_hovered == i:
                    pygame.draw.polygon(self.screen, (255, 255, 200), points, 2)
                else:
                    pygame.draw.polygon(self.screen, (105, 220, 255), points, 1)
            else:
                px, py = point["pos"]
                if self.map_hovered == i:
                    pygame.draw.circle(self.screen, (255, 255, 210), (px, py), 24, 2)
                else:
                    pygame.draw.circle(self.screen, (105, 220, 255), (px, py), 22, 1)

            px, py = point["pos"]
            pygame.draw.circle(self.screen, color, (px, py), 9)
            pygame.draw.circle(self.screen, border, (px, py), 9, 2)

            label = str(point.get("label", "POI"))
            label_text = self.perf_font.render(label, True, (245, 250, 255))
            label_bg = pygame.Surface((label_text.get_width() + 8, label_text.get_height() + 4), pygame.SRCALPHA)
            if self.map_hovered == i:
                label_bg.fill((0, 0, 0, 185))
            else:
                label_bg.fill((0, 0, 0, 140))
            self.screen.blit(label_bg, (px + 12, py - 10))
            self.screen.blit(label_text, (px + 16, py - 8))

    def _draw_inventory(self) -> None:
        cdef int sw = self.screen.get_width()
        cdef int sh = self.screen.get_height()
        cdef int panel_w = max(440, min(760, sw - 32))
        cdef int panel_h = max(360, min(620, sh - 32))
        cdef int px = (sw - panel_w) // 2
        cdef int py = (sh - panel_h) // 2
        cdef int content_top = py + 78
        cdef int footer_h = 50
        cdef int cols = 5
        cdef int gap = 12
        cdef int slot_size
        cdef int rows
        cdef int start_x
        cdef int start_y
        cdef int start_idx
        cdef int end_idx
        cdef int total_items
        cdef int max_page
        cdef int items_per_page
        cdef int visible_index
        cdef object page_text
        cdef str page_hint
        cdef tuple mouse_pos = pygame.mouse.get_pos()
        
        # Overlay
        cdef object overlay = pygame.Surface((sw, sh), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 160))
        self.screen.blit(overlay, (0, 0))
        self.inventory_panel_rect = pygame.Rect(px, py, panel_w, panel_h)
        
        # Panel
        pygame.draw.rect(self.screen, (30, 32, 36, 230), (px, py, panel_w, panel_h), border_radius=12)
        pygame.draw.rect(self.screen, (100, 105, 115), (px, py, panel_w, panel_h), 2, border_radius=12)
        
        # Title
        title_surf = self.textbox.font.render("Inventory", True, (255, 255, 255))
        self.screen.blit(title_surf, (px + (panel_w - title_surf.get_width()) // 2, py + 20))
        
        # Grid
        slot_size = (panel_w - 56 - ((cols - 1) * gap)) // cols
        slot_size = max(72, min(104, slot_size))
        rows = max(1, (panel_h - (content_top - py) - footer_h + gap) // (slot_size + gap))
        items_per_page = max(1, cols * rows)
        self.inventory_items_per_page = items_per_page
        self._clamp_inventory_page()
        start_x = px + (panel_w - (cols * slot_size + (cols - 1) * gap)) // 2
        start_y = content_top
        
        self.inventory_slots = []
        cdef list item_ids = list(self.inventory.keys())
        total_items = len(item_ids)
        max_page = 0 if total_items == 0 else (total_items - 1) // items_per_page
        if self.inventory_page > max_page:
            self.inventory_page = max_page
        start_idx = self.inventory_page * items_per_page
        end_idx = min(total_items, start_idx + items_per_page)
        cdef int r, c, idx
        cdef object slot_rect, icon_surf, count_surf, empty_text
        cdef dict item
        cdef str item_id
        self.inventory_hovered = None
        
        for r in range(rows):
            for c in range(cols):
                idx = r * cols + c
                sx = start_x + c * (slot_size + gap)
                sy = start_y + r * (slot_size + gap)
                slot_rect = pygame.Rect(sx, sy, slot_size, slot_size)
                self.inventory_slots.append(slot_rect)
                
                # Draw slot bg
                pygame.draw.rect(self.screen, (20, 22, 26), slot_rect, border_radius=8)
                
                visible_index = start_idx + idx
                if visible_index < end_idx:
                    item_id = item_ids[visible_index]
                    item = self.inventory[item_id]
                    
                    # Hover highlight
                    if slot_rect.collidepoint(mouse_pos):
                        pygame.draw.rect(self.screen, (60, 80, 120), slot_rect, border_radius=8)
                        # Tooltip (implement later or simple for now)
                        self.inventory_hovered = item_id
                    
                    pygame.draw.rect(self.screen, (80, 85, 95), slot_rect, 1, border_radius=8)
                    
                    # Icon
                    if item["icon"]:
                        icon_surf = self.assets.load_image(item["icon"], "sprites")
                        if icon_surf:
                            # Resize to fit slot
                            is_w = icon_surf.get_width()
                            is_h = icon_surf.get_height()
                            scale = min((slot_size-10)/is_w, (slot_size-10)/is_h)
                            icon_surf = pygame.transform.smoothscale(icon_surf, (int(is_w*scale), int(is_h*scale)))
                            self.screen.blit(icon_surf, (sx + (slot_size-icon_surf.get_width())//2, sy + (slot_size-icon_surf.get_height())//2))
                    
                    # Count
                    if item["count"] > 1:
                        count_surf = self.inspector_font.render(str(item["count"]), True, (255, 255, 255))
                        self.screen.blit(count_surf, (sx + slot_size - count_surf.get_width() - 5, sy + slot_size - count_surf.get_height() - 5))
                else:
                    pygame.draw.rect(self.screen, (65, 70, 78), slot_rect, 1, border_radius=8)

        if total_items == 0:
            empty_text = self.inspector_font.render("No items", True, (180, 185, 195))
            self.screen.blit(empty_text, (px + (panel_w - empty_text.get_width()) // 2, py + panel_h - footer_h - 8))

        page_hint = f"Page {self.inventory_page + 1}/{max_page + 1}  ({total_items} items)"
        if max_page > 0:
            page_hint += "  Wheel/PgUp/PgDn"
        page_text = self.inspector_font.render(page_hint, True, (190, 195, 210))
        self.screen.blit(page_text, (px + (panel_w - page_text.get_width()) // 2, py + panel_h - 34))
        
        # Draw tooltip for hovered item
        if self.inventory_hovered:
            item = self.inventory[self.inventory_hovered]
            mx, my = pygame.mouse.get_pos()
            t_name = self.inspector_font.render(item["name"], True, (255, 220, 100))
            t_desc = self.inspector_font.render(item["desc"], True, (200, 200, 200))
            tw = max(t_name.get_width(), t_desc.get_width()) + 20
            th = t_name.get_height() + t_desc.get_height() + 15
            t_rect = pygame.Rect(mx + 15, my + 15, tw, th)
            # Flip if off screen
            if t_rect.right > sw: t_rect.x = mx - tw - 15
            if t_rect.bottom > sh: t_rect.y = my - th - 15
            
            pygame.draw.rect(self.screen, (10, 12, 16, 240), t_rect, border_radius=6)
            pygame.draw.rect(self.screen, (100, 110, 130), t_rect, 1, border_radius=6)
            self.screen.blit(t_name, (t_rect.x + 10, t_rect.y + 8))
            self.screen.blit(t_desc, (t_rect.x + 10, t_rect.y + 10 + t_name.get_height()))
