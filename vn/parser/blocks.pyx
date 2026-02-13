from __future__ import annotations

from pathlib import Path
import shlex
from typing import List, Optional, Tuple

import cython

from ..script import CharacterDef
from .helpers import (
    _as_string,
    _is_int,
    _needs_more,
    _parse_choice_option,
    _parse_float_pair,
    _parse_int,
    _parse_position,
    _strip_trailing_semicolon,
)
from .model import ScriptParseError


cpdef tuple _collect_statement(list lines, int start_index):
    cdef str statement = lines[start_index]
    cdef int i = start_index + 1
    if _needs_more(statement):
        while i < len(lines):
            statement += "\n" + lines[i]
            i += 1
            if not _needs_more(statement):
                break
    return statement, i


cpdef str _strip_inline_comment(str text):
    in_str: str | None = None
    cdef bint escape = False
    cdef int i = 0
    cdef str ch
    while i < len(text):
        ch = text[i]
        if escape:
            escape = False
            i += 1
            continue
        if ch == "\\":
            escape = True
            i += 1
            continue
        if ch in {"'", "\""}:
            if in_str == ch:
                in_str = None
            elif in_str is None:
                in_str = ch
            i += 1
            continue
        if in_str is None and ch == "/" and i + 1 < len(text) and text[i + 1] == "/":
            return text[:i]
        i += 1
    return text


cpdef tuple _parse_choice_block(list lines, int index, int indent, object path):
    cdef list options = []
    cdef int i = index
    cdef str next_raw
    cdef str next_stripped
    cdef int next_indent
    cdef str option_text
    cdef str target
    while i < len(lines):
        next_raw = lines[i]
        next_stripped = next_raw.strip()
        if not next_stripped:
            i += 1
            continue
        if next_stripped.startswith("#") or next_stripped.startswith("//"):
            i += 1
            continue
        if next_stripped in {"}", "};"}:
            break
        next_indent = len(next_raw) - len(next_raw.lstrip(" "))
        if next_indent <= indent:
            break

        next_stripped = _strip_trailing_semicolon(next_stripped)
        option_text, target = _parse_choice_option(next_stripped, path, i + 1)
        options.append((option_text, target))
        i += 1

    return options, i


cpdef tuple _parse_character_block(
    list lines,
    int index,
    object path,
    int line_no,
    str ident,
):
    display_name: Optional[str] = None
    color: Optional[str] = None
    voice_tag: Optional[str] = None
    pos: Tuple[int, int] | None = None
    anchor: str | None = None
    z: int = 0
    float_amp: float | None = None
    float_speed: float | None = None
    sprites: dict[str, str] = {}

    cdef int i = index
    cdef str statement
    cdef str stripped
    cdef list tokens
    cdef str key
    cdef list args
    cdef str expr
    cdef str sprite_path
    while i < len(lines):
        statement, i = _collect_statement(lines, i)
        stripped = statement.strip()
        if not stripped:
            continue
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        stripped = _strip_inline_comment(stripped).strip()
        if not stripped:
            continue
        stripped = _strip_trailing_semicolon(stripped)
        if stripped in {"}", "};"}:
            break

        tokens = shlex.split(stripped)
        if not tokens:
            continue
        key = tokens[0]
        args = tokens[1:]

        if key == "name":
            if not args:
                raise ScriptParseError(f"{path}:{line_no} character name missing value")
            display_name = _as_string(args[0], path, line_no)
            continue
        if key == "color":
            if not args:
                raise ScriptParseError(f"{path}:{line_no} character color missing value")
            color = args[0]
            continue
        if key == "voice":
            if not args:
                raise ScriptParseError(f"{path}:{line_no} character voice missing value")
            voice_tag = _as_string(args[0], path, line_no)
            continue
        if key == "pos":
            pos, anchor = _parse_position(args, path, line_no)
            if not pos:
                raise ScriptParseError(f"{path}:{line_no} character pos expects 'x y'")
            continue
        if key == "anchor":
            _, anchor = _parse_position(args, path, line_no)
            if not anchor:
                raise ScriptParseError(
                    f"{path}:{line_no} character anchor expects keywords like left/center/right top/middle/bottom"
                )
            continue
        if key == "sprite":
            if not args:
                raise ScriptParseError(f"{path}:{line_no} character sprite missing value")
            if len(args) == 1:
                expr = "default"
                sprite_path = _as_string(args[0], path, line_no)
            else:
                expr = args[0]
                sprite_path = _as_string(args[1], path, line_no)
            sprites[expr] = sprite_path
            continue
        if key == "z":
            if not args:
                raise ScriptParseError(f"{path}:{line_no} character z missing value")
            z = _parse_int(args[0], path, line_no)
            continue
        if key == "float":
            float_amp, float_speed = _parse_float_pair(args, path, line_no)
            continue

        raise ScriptParseError(f"{path}:{line_no} unknown character field '{key}'")

    if not display_name:
        display_name = ident

    return (
        CharacterDef(
            ident=ident,
            display_name=display_name,
            color=color,
            sprites=sprites or None,
            voice_tag=voice_tag,
            pos=pos,
            anchor=anchor,
            z=z,
            float_amp=float_amp,
            float_speed=float_speed,
        ),
        i,
    )
