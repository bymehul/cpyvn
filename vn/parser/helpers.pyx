from __future__ import annotations

from pathlib import Path
import shlex
from typing import List, Tuple

import cython

from ..script import Music, Scene, Show, Sound
from .model import ScriptParseError

TRANSITION_STYLES: tuple[str, ...] = (
    "fade",
    "wipe",
    "slide",
    "dissolve",
    "zoom",
    "blur",
    "flash",
    "shake",
    "none",
)

DIALOGUE_KEYWORDS: tuple[str, ...] = (
    "mark",
    "label",
    "go",
    "goto",
    "back",
    "scene",
    "put",
    "add",
    "drop",
    "off",
    "ask",
    "pick",
    "bgm",
    "play",
    "sfx",
    "sound",
    "echo",
    "voice",
    "mute",
    "preload",
    "loading",
    "cache",
    "gc",
    "include",
    "call",
    "wait",
    "notify",
    "blend",
    "save",
    "load",
    "set",
    "track",
    "check",
    "say",
    "line",
)


@cython.cfunc
@cython.inline
cdef bint _is_transition_style(str token):
    return token in TRANSITION_STYLES


cpdef bint _is_signed_int(str value):
    cdef str head
    if not value:
        return False
    head = value[0]
    if head in {"+", "-"}:
        return value[1:].isdigit()
    return value.isdigit()


cpdef bint _looks_number(str value):
    try:
        float(value)
        return True
    except ValueError:
        return False


def _parse_pos_args(parts: List[object], path: Path, line_no: int) -> Tuple[int, int] | None:
    if len(parts) < 2:
        return None
    return _as_int(parts[-2], path, line_no), _as_int(parts[-1], path, line_no)


def _require_args(name: str, args: List[object], count: int, path: Path, line_no: int) -> None:
    if len(args) < count:
        raise ScriptParseError(f"{path}:{line_no} {name} expects {count} arguments")


cpdef str _as_string(object value, object path, int line_no):
    if isinstance(value, str):
        return value
    if isinstance(value, (int, float, bool)):
        return str(value)
    raise ScriptParseError(f"{path}:{line_no} expected string")


cpdef int _as_int(object value, object path, int line_no):
    if isinstance(value, bool):
        raise ScriptParseError(f"{path}:{line_no} expected int")
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    try:
        return int(value)
    except (ValueError, TypeError) as exc:
        raise ScriptParseError(f"{path}:{line_no} expected int") from exc


cpdef bint _as_bool(object value, object path, int line_no):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    raise ScriptParseError(f"{path}:{line_no} expected bool")


cpdef str _strip_trailing_semicolon(str text):
    return text[:-1].rstrip() if text.endswith(";") else text


cpdef bint _needs_more(str text):
    cdef int paren = 0
    cdef int bracket = 0
    in_str: str | None = None
    cdef bint escape = False
    cdef str ch
    for ch in text:
        if escape:
            escape = False
            continue
        if ch == "\\":
            escape = True
            continue
        if ch in {"'", "\""}:
            if in_str == ch:
                in_str = None
            elif in_str is None:
                in_str = ch
            continue
        if in_str is not None:
            continue
        if ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
    return paren > 0 or bracket > 0


cpdef tuple _parse_choice_option(str line, object path, int line_no):
    cdef str trimmed = line
    cdef str arrow
    cdef str left
    cdef str right
    cdef str option_text
    cdef str target
    if trimmed and trimmed[0] in {"-", "*"}:
        trimmed = trimmed[1:].strip()

    arrow = "=>"
    if "->" in trimmed:
        arrow = "->"
    elif "=>" not in trimmed:
        raise ScriptParseError(f"{path}:{line_no} ask option missing '->' or '=>'")

    left, right = trimmed.split(arrow, 1)
    option_text = _strip_quotes(left.strip())
    target = right.strip()
    if not option_text or not target:
        raise ScriptParseError(f"{path}:{line_no} invalid ask option")

    return option_text, target


cpdef tuple _parse_say(str arg, object path, int line_no):
    cdef list parts
    cdef str speaker
    cdef str text_part
    cdef str text
    arg = arg.strip()
    if not arg:
        raise ScriptParseError(f"{path}:{line_no} dialogue missing text")

    if arg.startswith("\""):
        text = _strip_quotes(arg)
        if not text:
            raise ScriptParseError(f"{path}:{line_no} dialogue missing text")
        return None, text

    parts = arg.split(maxsplit=1)
    speaker = parts[0].strip()
    text_part = parts[1].strip() if len(parts) > 1 else ""
    text = _strip_quotes(text_part) or text_part
    if not text:
        raise ScriptParseError(f"{path}:{line_no} dialogue missing text")
    return speaker, text


cpdef tuple _parse_set(str arg, object path, int line_no):
    cdef list tokens = shlex.split(arg)
    cdef str name
    cdef str raw_value
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} set requires name and value")
    name = _strip_var_prefix(tokens[0])
    raw_value = " ".join(tokens[1:])
    return name, _parse_value(raw_value)


cpdef tuple _parse_add(str arg, object path, int line_no):
    cdef list tokens = shlex.split(arg)
    cdef str name
    if not tokens:
        raise ScriptParseError(f"{path}:{line_no} add requires name")
    name = _strip_var_prefix(tokens[0])
    amount = 1
    if len(tokens) > 1:
        amount = _parse_int(tokens[1], path, line_no)
    return name, amount


cpdef object _parse_scene(str arg, object path, int line_no):
    cdef list parts
    cdef str head
    cdef list rest
    arg = arg.strip()
    if not arg:
        raise ScriptParseError(f"{path}:{line_no} scene missing value")

    parts = arg.split()
    parts, transition_style, transition_seconds = _pop_transition(parts, path, line_no)
    parts, float_amp, float_speed = _pop_float(parts, path, line_no)
    fade = transition_seconds if transition_style == "fade" else None
    if not parts:
        raise ScriptParseError(f"{path}:{line_no} scene missing value")
    head = parts[0]
    rest = parts[1:]
    if head == "color":
        if len(rest) < 1:
            raise ScriptParseError(f"{path}:{line_no} scene color missing value")
        return Scene(
            kind="color",
            value=" ".join(rest).strip(),
            fade=fade,
            transition_style=transition_style,
            transition_seconds=transition_seconds,
            float_amp=float_amp,
            float_speed=float_speed,
        )

    if head == "image":
        if len(rest) < 1:
            raise ScriptParseError(f"{path}:{line_no} scene image missing path")
        return Scene(
            kind="image",
            value=" ".join(rest).strip(),
            fade=fade,
            transition_style=transition_style,
            transition_seconds=transition_seconds,
            float_amp=float_amp,
            float_speed=float_speed,
        )

    return Scene(
        kind="image",
        value=" ".join(parts).strip(),
        fade=fade,
        transition_style=transition_style,
        transition_seconds=transition_seconds,
        float_amp=float_amp,
        float_speed=float_speed,
    )


cpdef object _parse_show(str arg, object path, int line_no):
    cdef list parts = arg.split()
    cdef str mode = "image"
    cdef str name
    cdef str color
    cdef int width
    cdef int height
    cdef str image_path
    parts, z = _pop_z(parts, path, line_no)
    parts, fade = _pop_fade(parts, path, line_no)
    if not parts:
        raise ScriptParseError(f"{path}:{line_no} add missing args")

    if parts[0] in {"rect", "image"}:
        mode = parts[0]
        parts = parts[1:]

    if mode == "rect":
        if len(parts) < 4:
            raise ScriptParseError(f"{path}:{line_no} add rect requires name color w h")
        name = parts[0]
        color = parts[1]
        width = _parse_int(parts[2], path, line_no)
        height = _parse_int(parts[3], path, line_no)
        pos, anchor = _parse_position(parts[4:], path, line_no)
        return Show(kind="rect", name=name, value=color, size=(width, height), pos=pos, anchor=anchor, z=z, fade=fade)

    if len(parts) < 2:
        raise ScriptParseError(f"{path}:{line_no} add image requires name path")

    name = parts[0]
    image_path = parts[1]
    pos, anchor = _parse_position(parts[2:], path, line_no)
    return Show(kind="image", name=name, value=image_path, pos=pos, anchor=anchor, z=z, fade=fade)


cpdef object _parse_music(str arg, object path, int line_no):
    cdef list parts = arg.split()
    cdef str music_path
    cdef str flag
    cdef bint loop = True
    if not parts:
        raise ScriptParseError(f"{path}:{line_no} play missing path")
    music_path = parts[0]
    if len(parts) > 1:
        flag = parts[1].lower()
        loop = flag in {"loop", "true", "1", "yes"}
    return Music(path=music_path, loop=loop)


cpdef object _parse_sound(str arg, object path, int line_no):
    cdef list parts = arg.split()
    if not parts:
        raise ScriptParseError(f"{path}:{line_no} sound missing path")
    return Sound(path=parts[0])


cpdef object _parse_optional_pos(list parts):
    cdef int x
    cdef int y
    if len(parts) < 2:
        return None
    try:
        x = int(parts[-2])
        y = int(parts[-1])
    except ValueError:
        return None
    return x, y


cpdef tuple _parse_position(list parts, object path, int line_no):
    cdef str part
    cdef object x_anchor = None
    cdef object y_anchor = None
    cdef list anchor_parts
    cdef bint all_keywords = True
    if not parts:
        return None, None
    if len(parts) >= 2 and _is_int(parts[-2]) and _is_int(parts[-1]):
        return (int(parts[-2]), int(parts[-1])), None

    keywords = {"left", "center", "right", "top", "middle", "bottom"}
    for part in parts:
        if part not in keywords:
            all_keywords = False
            break
    if all_keywords:
        for part in parts:
            if part in {"left", "center", "right"}:
                x_anchor = part
            elif part in {"top", "middle", "bottom"}:
                y_anchor = part
        anchor_parts = []
        if x_anchor:
            anchor_parts.append(x_anchor)
        if y_anchor:
            anchor_parts.append(y_anchor)
        if anchor_parts:
            return None, " ".join(anchor_parts)

    raise ScriptParseError(
        f"{path}:{line_no} invalid position (use 'x y' or keywords like left/center/right top/middle/bottom)"
    )


cpdef tuple _pop_z(list parts, object path, int line_no):
    cdef int idx
    cdef str token
    cdef int z
    if not parts:
        return parts, 0
    for idx, token in enumerate(parts):
        if token == "z":
            if idx + 1 >= len(parts):
                raise ScriptParseError(f"{path}:{line_no} z missing value")
            if not _is_int(parts[idx + 1]):
                raise ScriptParseError(f"{path}:{line_no} z expects int, got '{parts[idx + 1]}'")
            z = _parse_int(parts[idx + 1], path, line_no)
            return parts[:idx] + parts[idx + 2 :], z
    return parts, 0


cpdef tuple _pop_transition(list parts, object path, int line_no):
    cdef int idx
    cdef str token
    cdef double seconds
    if not parts:
        return parts, None, None
    for idx, token in enumerate(parts):
        if not _is_transition_style(token):
            continue
        if idx + 1 >= len(parts):
            raise ScriptParseError(f"{path}:{line_no} transition '{token}' missing value")
        if not _looks_number(parts[idx + 1]):
            continue
        seconds = _parse_float([parts[idx + 1]], path, line_no)
        return parts[:idx] + parts[idx + 2 :], token, seconds
    return parts, None, None


cpdef tuple _pop_fade(list parts, object path, int line_no):
    parts, style, seconds = _pop_transition(parts, path, line_no)
    if style == "fade":
        return parts, seconds
    return parts, None


cpdef tuple _parse_float_pair(list args, object path, int line_no):
    cdef double amp
    cdef double speed
    if len(args) == 1:
        amp = _parse_float([args[0]], path, line_no)
        return amp, 1.0
    if len(args) >= 2:
        amp = _parse_float([args[0]], path, line_no)
        speed = _parse_float([args[1]], path, line_no)
        return amp, speed
    raise ScriptParseError(f"{path}:{line_no} float expects '<amp> [speed]'")


cpdef tuple _pop_float(list parts, object path, int line_no):
    cdef int idx
    cdef str token
    cdef list tail
    cdef double amp
    cdef double speed
    if not parts:
        return parts, None, None
    for idx, token in enumerate(parts):
        if token == "float":
            if idx + 1 >= len(parts):
                raise ScriptParseError(f"{path}:{line_no} float missing value")
            tail = parts[idx + 1 :]
            if not tail:
                raise ScriptParseError(f"{path}:{line_no} float missing value")
            if len(tail) >= 2 and _looks_number(tail[0]) and _looks_number(tail[1]):
                amp, speed = _parse_float_pair(tail[:2], path, line_no)
                return parts[:idx] + parts[idx + 3 :], amp, speed
            amp, speed = _parse_float_pair(tail[:1], path, line_no)
            return parts[:idx] + parts[idx + 2 :], amp, speed
    return parts, None, None


cpdef int _parse_int(str value, object path, int line_no):
    try:
        return int(value)
    except ValueError as exc:
        raise ScriptParseError(f"{path}:{line_no} expected int, got '{value}'") from exc


cpdef bint _is_int(str value):
    try:
        int(value)
        return True
    except ValueError:
        return False


cpdef double _parse_float(list args, object path, int line_no):
    if not args:
        raise ScriptParseError(f"{path}:{line_no} expected float")
    try:
        return float(args[0])
    except ValueError as exc:
        raise ScriptParseError(f"{path}:{line_no} expected float, got '{args[0]}'") from exc


cpdef object _parse_value(str value):
    cdef str lowered = value.strip().lower()
    if lowered in {"true", "yes", "on"}:
        return True
    if lowered in {"false", "no", "off"}:
        return False
    try:
        return int(value)
    except ValueError:
        return value


cpdef str _strip_quotes(str value):
    cdef int last
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    if value.startswith('"') and '"' in value[1:]:
        last = value.rfind('"')
        return value[1:last]
    return value


cpdef str _strip_var_prefix(str value):
    if value.startswith("$"):
        return value[1:]
    return value


cpdef bint _is_dialogue_line(str stripped, str cmd):
    if cmd in DIALOGUE_KEYWORDS:
        return False
    return "\"" in stripped or "'" in stripped
