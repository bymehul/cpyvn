# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
from __future__ import annotations

from typing import List, Optional, Tuple
import random

import pygame

from ..text.richtext import parse_rich_text, Run, Style

_RichLine = Tuple[List[Tuple[pygame.Surface, bool]], int]


cdef class _ChoiceVariant:
    cdef public list normal
    cdef public list selected

    def __init__(self, list normal, list selected):
        self.normal = normal
        self.selected = selected


cdef class _ChoiceCache:
    cdef public tuple key
    cdef public list prompt_lines
    cdef public list option_lines

    def __init__(self, tuple key, list prompt_lines, list option_lines):
        self.key = key
        self.prompt_lines = prompt_lines
        self.option_lines = option_lines


cdef class _Nameplate:
    cdef public str speaker
    cdef public object text    # pygame.Surface
    cdef public object plate   # pygame.Surface
    cdef public int pad_x
    cdef public int pad_y
    cdef public object color   # Optional[Tuple[int,int,int]]

    def __init__(
        self,
        str speaker,
        object text,
        object plate,
        int pad_x,
        int pad_y,
        object color,
    ):
        self.speaker = speaker
        self.text    = text
        self.plate   = plate
        self.pad_x   = pad_x
        self.pad_y   = pad_y
        self.color   = color


cdef inline int _normalize_alpha(double value):
    cdef int alpha
    if value <= 1.0:
        alpha = <int>(value * 255)
    else:
        alpha = <int>value
    if alpha < 0:
        return 0
    if alpha > 255:
        return 255
    return alpha


cdef inline tuple _shake_offset(int amount):
    return (random.randint(-amount, amount), random.randint(-amount, amount))


cdef void _append_run(list line, str text, tuple style):
    """Append *text* with *style* to *line*, merging with the last run when possible."""
    cdef Py_ssize_t last
    if not text:
        return
    if line:
        last = len(line) - 1
        if line[last][1] == style:
            line[last] = (line[last][0] + text, style)
            return
    line.append((text, style))


cpdef dict _make_font_variants(int size):
    cdef object normal, bold, italic, bold_italic
    normal = pygame.font.Font(None, size)
    bold   = pygame.font.Font(None, size)
    bold.set_bold(True)
    italic = pygame.font.Font(None, size)
    italic.set_italic(True)
    bold_italic = pygame.font.Font(None, size)
    bold_italic.set_bold(True)
    bold_italic.set_italic(True)
    return {
        (False, False): normal,
        (True,  False): bold,
        (False, True):  italic,
        (True,  True):  bold_italic,
    }


cdef object _font_for_style(tuple style, dict font_map):
    return font_map.get((style[0], style[1]), font_map[(False, False)])



cpdef list _iter_tokens(str text):
    cdef list tokens = []
    cdef list buf    = []
    cdef object mode = None
    cdef str ch

    for ch in text:
        if ch == "\n":
            if buf:
                tokens.append("".join(buf))
                buf = []
            tokens.append("\n")
            mode = None
            continue
        if ch == " " or ch == "\t":
            if mode != "space":
                if buf:
                    tokens.append("".join(buf))
                    buf = []
                mode = "space"
            buf.append(ch)
        else:
            if mode != "word":
                if buf:
                    tokens.append("".join(buf))
                    buf = []
                mode = "word"
            buf.append(ch)
    if buf:
        tokens.append("".join(buf))
    return tokens


cpdef list _wrap_rich_runs(list runs, dict font_map, int max_width):
    cdef list lines     = []
    cdef list line      = []
    cdef int  line_width = 0
    cdef int  token_width, ch_width
    cdef object font
    cdef str text, token, ch
    cdef tuple style

    for text, style in runs:
        font = _font_for_style(style, font_map)
        for token in _iter_tokens(text):
            if token == "\n":
                lines.append(line)
                line = []
                line_width = 0
                continue
            if token == " " or (len(token) > 0 and token[0] == " "):
                if not line:
                    continue
                token_width = font.size(" ")[0]
                if line_width + token_width <= max_width:
                    _append_run(line, " ", style)
                    line_width += token_width
                continue

            token_width = font.size(token)[0]
            if line and line_width + token_width > max_width:
                lines.append(line)
                line = []
                line_width = 0

            if token_width <= max_width:
                _append_run(line, token, style)
                line_width += token_width
            else:
                for ch in token:
                    ch_width = font.size(ch)[0]
                    if line and line_width + ch_width > max_width:
                        lines.append(line)
                        line = []
                        line_width = 0
                    _append_run(line, ch, style)
                    line_width += ch_width

    if line or not lines:
        lines.append(line)
    return lines


cpdef list _render_rich_lines(list lines, dict font_map):
    cdef list rendered  = []
    cdef object fallback = font_map[(False, False)]
    cdef list line, surfaces
    cdef int max_height
    cdef object font, surf
    cdef tuple style
    cdef str text
    cdef object color
    cdef bint shake

    for line in lines:
        if not line:
            rendered.append(([], fallback.get_height()))
            continue
        surfaces   = []
        max_height = 0
        for text, style in line:
            font  = _font_for_style(style, font_map)
            color = style[2]
            shake = <bint>style[3]
            surf  = font.render(text, True, color)
            surfaces.append((surf, shake))
            h = surf.get_height()
            if h > max_height:
                max_height = h
        rendered.append((surfaces, max_height))
    return rendered


cpdef list _build_rich_lines(str text, dict font_map, int max_width, tuple base_color):
    cdef list runs, wrapped
    runs = parse_rich_text(text, base_color)
    if not runs:
        return _render_rich_lines([[]], font_map)
    wrapped = _wrap_rich_runs(runs, font_map, max_width)
    return _render_rich_lines(wrapped, font_map)


cpdef list wrap_text(str text, object font, int max_width):
    cdef list words, lines
    cdef str current, word, test_line

    words = text.split()
    if not words:
        return [""]

    lines   = []
    current = words[0]
    for word in words[1:]:
        test_line = current + " " + word
        if font.size(test_line)[0] <= max_width:
            current = test_line
        else:
            lines.append(current)
            current = word
    lines.append(current)
    return lines



cpdef _ChoiceCache _build_choice_cache(
    list options,
    object prompt,          # str | None
    int max_text_width,
    dict prompt_fonts,
    dict choice_fonts,
):
    cdef list prompt_lines = []
    cdef list option_lines = []
    cdef list normal_lines, selected_lines
    cdef str option

    if prompt:
        prompt_lines = _build_rich_lines(prompt, prompt_fonts, max_text_width, (235, 235, 235))

    for option in options:
        normal_lines   = _build_rich_lines("  " + option, choice_fonts, max_text_width, (230, 230, 230))
        selected_lines = _build_rich_lines("> " + option, choice_fonts, max_text_width, (255, 80, 80))
        option_lines.append(_ChoiceVariant(normal_lines, selected_lines))

    return _ChoiceCache((tuple(options), prompt, max_text_width), prompt_lines, option_lines)


class TextBox:
    def __init__(
        self,
        int width,
        int height,
        *,
        int font_size        = 30,
        int name_font_size   = 26,
        int choice_font_size = 28,
        int notify_font_size = 26,
        double box_opacity   = 0.67,
    ):
        self.width  = width
        self.height = height

        self.box_height         = 200
        self.margin             = 24
        self.line_gap           = 6
        self.name_gap           = 10
        self.choice_panel_width = int(width * 0.7)
        self.choice_padding     = 20
        self.choice_option_gap  = 8
        self.shake_px           = 2

        self._dialogue_fonts = _make_font_variants(font_size)
        self.font            = self._dialogue_fonts[(False, False)]
        self.name_font       = pygame.font.Font(None, name_font_size)
        self.name_font.set_bold(True)
        self._choice_fonts   = _make_font_variants(choice_font_size)
        self.choice_font     = self._choice_fonts[(False, False)]
        self.notify_font     = pygame.font.Font(None, notify_font_size)
        self.notify_padding  = 14
        self.loading_font    = pygame.font.Font(None, 34)
        self.choice_anim_ms  = 180

        self._choice_signature    = None
        self._choice_anim_start_ms = None
        self._choice_cache        = None
        self._dialogue_cache_key  = None
        self._dialogue_cache_lines: list = []
        self._dialogue_cache_name = None

        self._box_surface = pygame.Surface(
            (width - self.margin * 2, self.box_height), pygame.SRCALPHA
        )
        cdef int alpha = _normalize_alpha(box_opacity)
        self._box_surface.fill((0, 0, 0, alpha))

    # ------------------------------------------------------------------
    def draw_dialogue(
        self,
        object screen,
        object speaker,
        str text,
        *,
        object name_color = None,
    ) -> None:
        cdef object box_rect, cached
        cdef int x, y, max_width, line_x
        cdef tuple jitter
        cdef object surf
        cdef bint shake
        cdef int line_height

        box_rect = self._box_rect()
        screen.blit(self._box_surface, box_rect)

        x = box_rect.x + self.margin
        y = box_rect.y + self.margin

        if speaker:
            cached = self._get_nameplate(speaker, name_color)
            screen.blit(cached.plate, (x - cached.pad_x, y - cached.pad_y))
            screen.blit(cached.text,  (x, y))
            y += cached.text.get_height() + self.name_gap

        max_width = box_rect.width - self.margin * 2
        cache_key = (speaker, text, max_width)
        if cache_key != self._dialogue_cache_key:
            self._dialogue_cache_key   = cache_key
            self._dialogue_cache_lines = _build_rich_lines(
                text,
                self._dialogue_fonts,
                max_width,
                (235, 235, 235),
            )
        for line_surfs, line_height in self._dialogue_cache_lines:
            line_x = x
            for surf, shake in line_surfs:
                if shake:
                    jitter = _shake_offset(self.shake_px)
                    screen.blit(surf, (line_x + jitter[0], y + jitter[1]))
                else:
                    screen.blit(surf, (line_x, y))
                line_x += surf.get_width()
            y += line_height + self.line_gap

    # ------------------------------------------------------------------
    def draw_choices(
        self,
        object screen,
        list options,
        int selected,
        object prompt = None,
    ) -> list:
        cdef int panel_width, max_text_width
        cdef int prompt_height, options_height, panel_height
        cdef int panel_alpha, offset_y, elapsed
        cdef double t, ease
        cdef object panel_rect, panel_surface, shadow, highlight
        cdef list hitboxes, lines
        cdef int x, y, line_x, option_y_start, option_y_end, option_height, idx
        cdef object surf
        cdef bint shake
        cdef int line_height
        cdef tuple jitter, signature, cache_key

        panel_width    = self.choice_panel_width
        max_text_width = panel_width - self.choice_padding * 2

        cache_key = (tuple(options), prompt, max_text_width)
        if self._choice_cache is None or self._choice_cache.key != cache_key:
            self._choice_cache = _build_choice_cache(
                options, prompt, max_text_width,
                self._dialogue_fonts, self._choice_fonts,
            )

        prompt_surfaces = self._choice_cache.prompt_lines
        option_lines    = self._choice_cache.option_lines

        prompt_height = sum(lh + self.line_gap for _, lh in prompt_surfaces)
        if prompt_surfaces:
            prompt_height += self.choice_option_gap

        options_height = 0
        for idx, variant in enumerate(option_lines):
            lines = variant.selected if idx == selected else variant.normal
            options_height += sum(lh + self.line_gap for _, lh in lines)
            options_height += self.choice_option_gap

        panel_height = self.choice_padding * 2 + prompt_height + options_height
        panel_height = min(panel_height, int(self.height * 0.75))

        panel_rect = pygame.Rect(
            (self.width - panel_width) // 2,
            (self.height - panel_height) // 2,
            panel_width,
            panel_height,
        )

        signature = (tuple(options), prompt)
        if signature != self._choice_signature:
            self._choice_signature      = signature
            self._choice_anim_start_ms  = pygame.time.get_ticks()

        panel_alpha = 255
        offset_y    = 0
        if self._choice_anim_start_ms is not None:
            elapsed     = pygame.time.get_ticks() - self._choice_anim_start_ms
            t           = min(1.0, elapsed / <double>self.choice_anim_ms)
            ease        = t * t * (3.0 - 2.0 * t)
            panel_alpha = max(0, min(255, <int>(255.0 * ease)))
            offset_y    = <int>((1.0 - ease) * 12.0)
            if t >= 1.0:
                self._choice_anim_start_ms = None

        panel_rect.y += offset_y

        panel_surface = pygame.Surface((panel_width, panel_height), pygame.SRCALPHA)
        panel_surface.fill((0, 0, 0, 200))
        pygame.draw.rect(
            panel_surface, (220, 220, 220, 80),
            panel_surface.get_rect(), 2, border_radius=8,
        )

        y        = self.choice_padding
        x        = self.choice_padding
        hitboxes = []

        for _, line_height in prompt_surfaces:
            pass  # measured above; re-blit below
        # blit prompt
        for line_surfs, line_height in prompt_surfaces:
            line_x = x
            for surf, shake in line_surfs:
                if shake:
                    jitter = _shake_offset(self.shake_px)
                    panel_surface.blit(surf, (line_x + jitter[0], y + jitter[1]))
                else:
                    panel_surface.blit(surf, (line_x, y))
                line_x += surf.get_width()
            y += line_height + self.line_gap
        if prompt_surfaces:
            y += self.choice_option_gap

        for idx, variant in enumerate(option_lines):
            lines         = variant.selected if idx == selected else variant.normal
            option_y_start = y
            for line_surfs, line_height in lines:
                line_x = x
                for surf, shake in line_surfs:
                    if shake:
                        jitter = _shake_offset(self.shake_px)
                        panel_surface.blit(surf, (line_x + jitter[0], y + jitter[1]))
                    else:
                        panel_surface.blit(surf, (line_x, y))
                    line_x += surf.get_width()
                y += line_height + self.line_gap
            option_y_end = y

            option_height = max(option_y_end - option_y_start, self.choice_font.get_height())
            hitboxes.append(pygame.Rect(
                panel_rect.x + x,
                panel_rect.y + option_y_start,
                max_text_width,
                option_height,
            ))

            if idx == selected:
                highlight = pygame.Surface((max_text_width, option_height), pygame.SRCALPHA)
                highlight.fill((255, 80, 80, 40))
                panel_surface.blit(highlight, (x, option_y_start))

            y += self.choice_option_gap

        shadow = pygame.Surface((panel_width, panel_height), pygame.SRCALPHA)
        shadow.fill((0, 0, 0, 90))
        shadow.set_alpha(panel_alpha)
        panel_surface.set_alpha(panel_alpha)
        screen.blit(shadow,        (panel_rect.x + 4, panel_rect.y + 6))
        screen.blit(panel_surface, panel_rect.topleft)
        return hitboxes

    # ------------------------------------------------------------------
    def _get_nameplate(self, str speaker, object color) -> _Nameplate:
        cdef object cached = self._dialogue_cache_name
        cdef object text_color, border_color, name_surf, plate
        cdef int name_pad_x, name_pad_y
        cdef object name_rect

        if (
            cached is not None
            and cached.speaker == speaker
            and cached.color   == color
        ):
            return cached

        text_color   = color if color else (240, 240, 240)
        border_color = (color[0], color[1], color[2], 120) if color else (240, 240, 240, 80)
        name_surf    = self.name_font.render(speaker, True, text_color)
        name_pad_x   = 10
        name_pad_y   = 6
        name_rect    = name_surf.get_rect()
        plate        = pygame.Surface(
            (name_rect.width + name_pad_x * 2, name_rect.height + name_pad_y * 2),
            pygame.SRCALPHA,
        )
        plate.fill((20, 20, 20, 210))
        pygame.draw.rect(plate, border_color, plate.get_rect(), 1, border_radius=6)
        self._dialogue_cache_name = _Nameplate(
            speaker=speaker,
            text=name_surf,
            plate=plate,
            pad_x=name_pad_x,
            pad_y=name_pad_y,
            color=color,
        )
        return self._dialogue_cache_name

    # ------------------------------------------------------------------
    def draw_notify(self, object screen, str text) -> None:
        cdef int max_width, content_width, line_height, content_height
        cdef int box_height, max_line_width, box_width
        cdef list lines
        cdef object box_rect, surface, line_surf
        cdef int x, y
        cdef str line

        if not text:
            return

        max_width     = int(self.width * 0.6)
        content_width = max_width - self.notify_padding * 2
        lines         = wrap_text(text, self.notify_font, content_width)

        line_height    = self.notify_font.get_height()
        content_height = (
            len(lines) * line_height
            + max(0, len(lines) - 1) * self.line_gap
        )
        box_height = self.notify_padding * 2 + content_height

        max_line_width = max(
            (self.notify_font.size(line)[0] for line in lines), default=0
        )
        box_width = min(max_width, max_line_width + self.notify_padding * 2)

        box_rect = pygame.Rect(
            (self.width - box_width) // 2,
            self.margin,
            box_width,
            box_height,
        )

        surface = pygame.Surface((box_width, box_height), pygame.SRCALPHA)
        surface.fill((15, 15, 15, 210))
        pygame.draw.rect(
            surface, (240, 240, 240, 70),
            surface.get_rect(), 1, border_radius=6,
        )

        y = self.notify_padding
        x = self.notify_padding
        for line in lines:
            line_surf = self.notify_font.render(line, True, (245, 245, 245))
            surface.blit(line_surf, (x, y))
            y += line_height + self.line_gap

        screen.blit(surface, box_rect.topleft)

    # ------------------------------------------------------------------
    def draw_loading(self, object screen, str text) -> None:
        cdef object overlay, text_surf, text_rect
        cdef int dots
        cdef str label

        overlay = pygame.Surface((self.width, self.height), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 170))
        screen.blit(overlay, (0, 0))

        dots      = (pygame.time.get_ticks() // 400) % 4
        label     = text + "." * dots
        text_surf = self.loading_font.render(label, True, (240, 240, 240))
        text_rect = text_surf.get_rect(center=(self.width // 2, self.height // 2))
        screen.blit(text_surf, text_rect)

    # ------------------------------------------------------------------
    def _box_rect(self) -> pygame.Rect:
        return pygame.Rect(
            self.margin,
            self.height - self.box_height - self.margin,
            self.width - self.margin * 2,
            self.box_height,
        )
