from __future__ import annotations

from pathlib import Path
import shlex
from typing import List, Optional, Tuple

import cython

from ..script import (
    Animate,
    Blend,
    CacheClear,
    CachePin,
    CacheUnpin,
    CameraSet,
    Command,
    Echo,
    HotspotAdd,
    HotspotDebug,
    HotspotPoly,
    HotspotRemove,
    HudAdd,
    HudRemove,
    Input,
    Item,
    Map,
    Meter,
    Music,
    Mute,
    Notify,
    Phone,
    Preload,
    Show,
    ShowChar,
    Sound,
    Video,
    Voice,
)
from .helpers import (
    _as_bool,
    _as_string,
    _is_int,
    _looks_number,
    _parse_int,
    _parse_position,
    _pop_transition,
    _pop_float,
    _pop_z,
    _strip_var_prefix,
)
from .model import ScriptParseError

_VIDEO_FITS = {"contain", "cover", "stretch"}
_ANIMATE_EASES = {"linear", "in", "out", "inout"}
_ANCHOR_KEYWORDS = {"left", "center", "right", "top", "middle", "bottom"}


cpdef tuple _pop_size(list parts, object path, int line_no):
    cdef int idx
    cdef str token
    cdef str width_token
    cdef str height_token
    cdef int width
    cdef int height
    if not parts:
        return parts, None
    for idx, token in enumerate(parts):
        if token != "size":
            continue
        if idx + 2 >= len(parts):
            raise ScriptParseError(f"{path}:{line_no} size expects width and height")
        width_token = parts[idx + 1]
        height_token = parts[idx + 2]
        if not _is_int(width_token) or not _is_int(height_token):
            raise ScriptParseError(f"{path}:{line_no} size expects integer width and height")
        width = _parse_int(width_token, path, line_no)
        height = _parse_int(height_token, path, line_no)
        if width <= 0 or height <= 0:
            raise ScriptParseError(f"{path}:{line_no} size values must be > 0")
        return parts[:idx] + parts[idx + 3 :], (width, height)
    return parts, None


cpdef object _parse_ask_prompt(str line, object path, int line_no):
    """Return (prompt, timeout, timeout_default) from an 'ask' line."""
    cdef list tokens = shlex.split(line)
    if not tokens or tokens[0] != "ask":
        return None, None, None
    if len(tokens) < 2:
        return None, None, None
    cdef str prompt = None
    cdef object timeout = None
    cdef object timeout_default = None
    cdef list rest = tokens[1:]
    cdef list prompt_parts = []
    cdef int idx = 0
    while idx < len(rest):
        w = rest[idx].lower()
        if w == "timeout" and idx + 1 < len(rest):
            try:
                timeout = float(rest[idx + 1])
            except ValueError:
                raise ScriptParseError(f"{path}:{line_no} timeout must be a number")
            idx += 2
            continue
        if w == "default" and idx + 1 < len(rest):
            try:
                timeout_default = int(rest[idx + 1])
            except ValueError:
                raise ScriptParseError(f"{path}:{line_no} default must be an integer")
            idx += 2
            continue
        prompt_parts.append(rest[idx])
        idx += 1
    prompt = " ".join(prompt_parts).strip() or None
    return prompt, timeout, timeout_default


cpdef object _parse_show_tokens(list args, object path, int line_no):
    cdef list parts
    cdef int z
    cdef object transition_style
    cdef object transition_seconds
    cdef object fade
    cdef object float_amp
    cdef object float_speed
    cdef object size
    cdef str mode = "image"
    cdef str name
    cdef str color
    cdef int width
    cdef int height
    cdef str image_path
    cdef object pos
    cdef object anchor
    if not args:
        raise ScriptParseError(f"{path}:{line_no} add missing args")

    parts = [str(arg) for arg in args]
    parts, z = _pop_z(parts, path, line_no)
    parts, transition_style, transition_seconds = _pop_transition(parts, path, line_no)
    fade = transition_seconds if transition_style == "fade" else None
    parts, float_amp, float_speed = _pop_float(parts, path, line_no)
    parts, size = _pop_size(parts, path, line_no)
    mode = "image"
    if parts[0] in {"rect", "image"}:
        mode = parts[0]
        parts = parts[1:]

    if mode == "rect":
        if size is not None:
            raise ScriptParseError(f"{path}:{line_no} add rect does not support 'size'")
        if len(parts) < 4:
            raise ScriptParseError(f"{path}:{line_no} add rect requires name color w h")
        name = parts[0]
        color = parts[1]
        width = _parse_int(parts[2], path, line_no)
        height = _parse_int(parts[3], path, line_no)
        pos, anchor = _parse_position(parts[4:], path, line_no)
        return Show(
            kind="rect",
            name=name,
            value=color,
            size=(width, height),
            pos=pos,
            anchor=anchor,
            z=z,
            fade=fade,
            transition_style=transition_style,
            transition_seconds=transition_seconds,
            float_amp=float_amp,
            float_speed=float_speed,
        )

    if len(parts) < 2:
        raise ScriptParseError(f"{path}:{line_no} add image requires name path")

    name = parts[0]
    image_path = parts[1]
    pos, anchor = _parse_position(parts[2:], path, line_no)
    return Show(
        kind="image",
        name=name,
        value=image_path,
        size=size,
        pos=pos,
        anchor=anchor,
        z=z,
        fade=fade,
        transition_style=transition_style,
        transition_seconds=transition_seconds,
        float_amp=float_amp,
        float_speed=float_speed,
    )


cpdef object _parse_show_char(list args, object path, int line_no):
    cdef list raw_parts
    cdef int z
    cdef object transition_style
    cdef object transition_seconds
    cdef object fade
    cdef object float_amp
    cdef object float_speed
    cdef str ident
    cdef list tail
    cdef object expr
    cdef object pos
    cdef object anchor
    cdef list maybe_pos
    cdef object part
    cdef bint anchors_only
    if not args:
        raise ScriptParseError(f"{path}:{line_no} show missing character id")
    raw_parts = [str(part) for part in args]
    raw_parts, z = _pop_z(raw_parts, path, line_no)
    raw_parts, transition_style, transition_seconds = _pop_transition(raw_parts, path, line_no)
    fade = transition_seconds if transition_style == "fade" else None
    raw_parts, float_amp, float_speed = _pop_float(raw_parts, path, line_no)
    ident = _strip_var_prefix(raw_parts[0]) if raw_parts else ""
    if not ident:
        raise ScriptParseError(f"{path}:{line_no} show missing character id")

    if len(raw_parts) == 1:
        return ShowChar(
            ident=ident,
            z=z,
            fade=fade,
            transition_style=transition_style,
            transition_seconds=transition_seconds,
            float_amp=float_amp,
            float_speed=float_speed,
        )

    if len(raw_parts) >= 2:
        tail = raw_parts[1:]
        expr = None
        pos = None
        anchor = None

        if len(tail) >= 2 and _is_int(str(tail[-2])) and _is_int(str(tail[-1])):
            expr = tail[0] if len(tail) > 2 else None
            pos, anchor = _parse_position(tail[-2:], path, line_no)
            return ShowChar(
                ident=ident,
                expression=expr,
                pos=pos,
                anchor=anchor,
                z=z,
                fade=fade,
                transition_style=transition_style,
                transition_seconds=transition_seconds,
                float_amp=float_amp,
                float_speed=float_speed,
            )

        anchors_only = True
        for part in tail:
            if part not in _ANCHOR_KEYWORDS:
                anchors_only = False
                break
        if anchors_only:
            expr = None
            pos, anchor = _parse_position(tail, path, line_no)
            return ShowChar(
                ident=ident,
                expression=expr,
                pos=pos,
                anchor=anchor,
                z=z,
                fade=fade,
                transition_style=transition_style,
                transition_seconds=transition_seconds,
                float_amp=float_amp,
                float_speed=float_speed,
            )

        if len(tail) >= 2:
            maybe_pos = tail[1:]
            try:
                pos, anchor = _parse_position(maybe_pos, path, line_no)
                expr = tail[0]
                return ShowChar(
                    ident=ident,
                    expression=expr,
                    pos=pos,
                    anchor=anchor,
                    z=z,
                    fade=fade,
                    transition_style=transition_style,
                    transition_seconds=transition_seconds,
                    float_amp=float_amp,
                    float_speed=float_speed,
                )
            except ScriptParseError:
                pass

        expr = tail[0]
        return ShowChar(
            ident=ident,
            expression=expr,
            z=z,
            fade=fade,
            transition_style=transition_style,
            transition_seconds=transition_seconds,
            float_amp=float_amp,
            float_speed=float_speed,
        )

    return ShowChar(
        ident=ident,
        z=z,
        fade=fade,
        transition_style=transition_style,
        transition_seconds=transition_seconds,
        float_amp=float_amp,
        float_speed=float_speed,
    )


cpdef object _parse_play(list tokens, object path, int line_no):
    cdef str music_path
    cdef bint loop = True
    if len(tokens) < 3 or tokens[1] != "tune":
        raise ScriptParseError(f"{path}:{line_no} play expects 'tune <name>'")
    music_path = _as_string(tokens[2], path, line_no)
    if len(tokens) > 3:
        loop = _as_bool(tokens[3], path, line_no)
    return Music(path=music_path, loop=loop)


cpdef object _parse_video(list tokens, object path, int line_no):
    cdef str action
    cdef str video_path
    cdef bint loop = False
    cdef str fit = "contain"
    cdef int idx = 3
    cdef str token
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} video expects 'play <path>' or 'stop'")
    action = tokens[1]
    if action == "stop":
        if len(tokens) != 2:
            raise ScriptParseError(f"{path}:{line_no} video stop takes no extra arguments")
        return Video(action="stop")
    if action != "play":
        raise ScriptParseError(f"{path}:{line_no} video action must be play or stop")
    if len(tokens) < 3:
        raise ScriptParseError(f"{path}:{line_no} video play missing path")

    video_path = _as_string(tokens[2], path, line_no)
    while idx < len(tokens):
        token = tokens[idx]
        if token == "loop":
            if idx + 1 >= len(tokens):
                raise ScriptParseError(f"{path}:{line_no} video loop missing bool value")
            loop = _as_bool(tokens[idx + 1], path, line_no)
            idx += 2
            continue
        if token == "fit":
            if idx + 1 >= len(tokens):
                raise ScriptParseError(f"{path}:{line_no} video fit missing value")
            fit = tokens[idx + 1]
            if fit not in _VIDEO_FITS:
                raise ScriptParseError(
                    f"{path}:{line_no} video fit must be one of: {', '.join(sorted(_VIDEO_FITS))}"
                )
            idx += 2
            continue
        raise ScriptParseError(f"{path}:{line_no} unknown video option: {token}")

    return Video(action="play", path=video_path, loop=loop, fit=fit)


@cython.cfunc
@cython.inline
cdef double _parse_seconds_value(str value, object path, int line_no):
    cdef double seconds
    if not _looks_number(value):
        raise ScriptParseError(f"{path}:{line_no} animate duration must be a number")
    seconds = float(value)
    if seconds < 0:
        raise ScriptParseError(f"{path}:{line_no} animate duration must be >= 0")
    return seconds


@cython.cfunc
@cython.inline
cdef str _parse_ease_value(list rest, object path, int line_no):
    cdef str ease
    if not rest:
        return "linear"
    if len(rest) > 1:
        raise ScriptParseError(f"{path}:{line_no} animate has too many arguments")
    ease = str(rest[0])
    if ease not in _ANIMATE_EASES:
        raise ScriptParseError(
            f"{path}:{line_no} animate ease must be one of: {', '.join(sorted(_ANIMATE_EASES))}"
        )
    return ease


cpdef object _parse_animate(list args, object path, int line_no):
    cdef str name
    cdef str action
    cdef int x
    cdef int y
    cdef int width
    cdef int height
    cdef int alpha
    cdef double seconds
    cdef str ease
    if not args:
        raise ScriptParseError(f"{path}:{line_no} animate expects target and action")
    if args[0] == "stop":
        if len(args) != 2:
            raise ScriptParseError(f"{path}:{line_no} animate stop expects target name")
        return Animate(name=_strip_var_prefix(args[1]), action="stop")

    if len(args) < 2:
        raise ScriptParseError(f"{path}:{line_no} animate expects target and action")
    name = _strip_var_prefix(args[0])
    action = args[1]

    if action == "move":
        if len(args) < 5:
            raise ScriptParseError(f"{path}:{line_no} animate move expects: animate <name> move <x> <y> <seconds> [ease]")
        x = _parse_int(args[2], path, line_no)
        y = _parse_int(args[3], path, line_no)
        seconds = _parse_seconds_value(args[4], path, line_no)
        ease = _parse_ease_value(args[5:], path, line_no)
        return Animate(name=name, action="move", v1=float(x), v2=float(y), seconds=seconds, ease=ease)

    if action == "size":
        if len(args) < 5:
            raise ScriptParseError(f"{path}:{line_no} animate size expects: animate <name> size <w> <h> <seconds> [ease]")
        width = _parse_int(args[2], path, line_no)
        height = _parse_int(args[3], path, line_no)
        if width <= 0 or height <= 0:
            raise ScriptParseError(f"{path}:{line_no} animate size values must be > 0")
        seconds = _parse_seconds_value(args[4], path, line_no)
        ease = _parse_ease_value(args[5:], path, line_no)
        return Animate(name=name, action="size", v1=float(width), v2=float(height), seconds=seconds, ease=ease)

    if action == "alpha":
        if len(args) < 4:
            raise ScriptParseError(f"{path}:{line_no} animate alpha expects: animate <name> alpha <0..255> <seconds> [ease]")
        alpha = _parse_int(args[2], path, line_no)
        if alpha < 0 or alpha > 255:
            raise ScriptParseError(f"{path}:{line_no} animate alpha must be between 0 and 255")
        seconds = _parse_seconds_value(args[3], path, line_no)
        ease = _parse_ease_value(args[4:], path, line_no)
        return Animate(name=name, action="alpha", v1=float(alpha), seconds=seconds, ease=ease)

    raise ScriptParseError(f"{path}:{line_no} unknown animate action: {action}")


cpdef object _parse_sound_effect(list tokens, object path, int line_no):
    cdef str sound_path
    if len(tokens) < 3 or tokens[1] != "effect":
        raise ScriptParseError(f"{path}:{line_no} sound expects 'effect <name>'")
    sound_path = _as_string(tokens[2], path, line_no)
    return Sound(path=sound_path)


cpdef object _parse_echo(list tokens, object path, int line_no):
    cdef str action = "start"
    cdef object echo_path = None
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} echo expects '<path> [start|stop]'")

    if tokens[1] in {"start", "stop"}:
        action = tokens[1]
    else:
        echo_path = _as_string(tokens[1], path, line_no)
        if len(tokens) > 2:
            action = tokens[2].lower()

    if action not in {"start", "stop"}:
        raise ScriptParseError(f"{path}:{line_no} echo action must be 'start' or 'stop'")

    if action == "start" and not echo_path:
        raise ScriptParseError(f"{path}:{line_no} echo start missing path")

    return Echo(path=echo_path, action=action)


cpdef object _parse_voice(list tokens, object path, int line_no):
    cdef str voice_path
    cdef str character
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} voice expects '<char> <path>' or '<path>'")
    if len(tokens) == 2:
        voice_path = _as_string(tokens[1], path, line_no)
        return Voice(character=None, path=voice_path)
    character = tokens[1]
    voice_path = _as_string(tokens[2], path, line_no)
    return Voice(character=character, path=voice_path)


cpdef object _parse_mute(list tokens, object path, int line_no):
    cdef str target
    if len(tokens) == 1:
        target = "all"
    else:
        target = tokens[1].lower()
    if target not in {"all", "music", "sfx", "echo", "voice"}:
        raise ScriptParseError(f"{path}:{line_no} mute target must be all/music/sfx/echo/voice")
    return Mute(target=target)


cpdef object _parse_preload(list tokens, object path, int line_no):
    cdef str kind
    cdef str asset_path
    if len(tokens) < 3:
        raise ScriptParseError(f"{path}:{line_no} preload expects '<bg|sprites|audio> <path>'")
    kind = _normalize_asset_kind(tokens[1], path, line_no)
    asset_path = _as_string(tokens[2], path, line_no)
    return Preload(kind=kind, path=asset_path)


cpdef object _parse_loading_header(str header, object path, int line_no):
    cdef list tokens = shlex.split(header)
    if not tokens or tokens[0] != "loading":
        raise ScriptParseError(f"{path}:{line_no} loading block expects 'loading {{ ... }}'")
    if len(tokens) > 1:
        return " ".join(tokens[1:]).strip() or None
    return None


cpdef object _parse_cache(list tokens, object path, int line_no):
    cdef str action
    cdef str kind
    cdef str script_path
    cdef str asset_path
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} cache expects 'clear|pin|unpin ...'")
    action = tokens[1].lower()
    if action == "clear":
        if len(tokens) < 3:
            raise ScriptParseError(f"{path}:{line_no} cache clear expects images|sounds|all|scripts|runtime|script")
        kind = tokens[2].lower()
        if kind == "scene":
            kind = "runtime"
        if kind in {"script", "file"}:
            if len(tokens) < 4:
                raise ScriptParseError(f"{path}:{line_no} cache clear script expects a script path")
            script_path = _as_string(tokens[3], path, line_no)
            return CacheClear(kind="script", path=script_path)
        if kind not in {"images", "sounds", "all", "scripts", "runtime"}:
            raise ScriptParseError(f"{path}:{line_no} cache clear expects images|sounds|all|scripts|runtime|script")
        return CacheClear(kind=kind, path=None)

    if action in {"pin", "unpin"}:
        if len(tokens) < 4:
            raise ScriptParseError(f"{path}:{line_no} cache {action} expects '<bg|sprites|audio> <path>'")
        kind = _normalize_asset_kind(tokens[2], path, line_no)
        asset_path = _as_string(tokens[3], path, line_no)
        if action == "pin":
            return CachePin(kind=kind, path=asset_path)
        return CacheUnpin(kind=kind, path=asset_path)

    raise ScriptParseError(f"{path}:{line_no} cache expects 'clear|pin|unpin ...'")


cpdef str _normalize_asset_kind(str raw, object path, int line_no):
    cdef str value = raw.lower()
    if value in {"bg", "background"}:
        return "bg"
    if value in {"sprite", "sprites", "image", "images"}:
        return "sprites"
    if value in {"audio", "sound", "sounds", "music"}:
        return "audio"
    raise ScriptParseError(f"{path}:{line_no} invalid asset kind '{raw}' (use bg/sprites/audio)")


cpdef double _parse_float(list args, object path, int line_no):
    if len(args) != 1:
        raise ScriptParseError(f"{path}:{line_no} expected a single number")
    try:
        return float(args[0])
    except ValueError as exc:
        raise ScriptParseError(f"{path}:{line_no} expected number, got '{args[0]}'") from exc


cpdef str _parse_text(list args, object path, int line_no, str name):
    if not args:
        raise ScriptParseError(f"{path}:{line_no} {name} missing text")
    return " ".join(args).strip()


cpdef tuple _parse_notify(list args, object path, int line_no):
    cdef list parts
    cdef double seconds
    cdef str text
    if not args:
        raise ScriptParseError(f"{path}:{line_no} notify missing text")
    parts = [str(arg) for arg in args]
    if len(parts) >= 2 and _looks_number(str(parts[-1])):
        seconds = _parse_float([str(parts[-1])], path, line_no)
        text = " ".join(parts[:-1]).strip()
        if not text:
            raise ScriptParseError(f"{path}:{line_no} notify missing text")
        return text, seconds
    return " ".join(parts).strip(), None


cpdef tuple _parse_blend(list args, object path, int line_no):
    cdef str style
    cdef set allowed
    cdef double seconds
    if len(args) != 2:
        raise ScriptParseError(f"{path}:{line_no} blend expects '<style> <seconds>'")
    style = args[0].lower()
    allowed = {"fade", "wipe", "slide", "dissolve", "zoom", "blur", "flash", "shake", "none"}
    if style not in allowed:
        styles = " | ".join(sorted(allowed))
        raise ScriptParseError(f"{path}:{line_no} blend style must be one of: {styles}")
    seconds = _parse_float([args[1]], path, line_no)
    return style, seconds


cpdef str _parse_slot(list args, object path, int line_no, str name):
    cdef str slot
    if not args:
        raise ScriptParseError(f"{path}:{line_no} {name} missing slot")
    slot = " ".join(args).strip()
    if not slot:
        raise ScriptParseError(f"{path}:{line_no} {name} missing slot")
    return slot


cpdef object _parse_hotspot(list tokens, object path, int line_no):
    cdef str action
    cdef str name
    cdef int x
    cdef int y
    cdef int w
    cdef int h
    cdef str target
    cdef int arrow_idx
    cdef list coords
    cdef list points
    cdef int idx
    cdef str raw
    cdef bint enabled
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} hotspot expects add/remove/clear/debug")
    action = tokens[1].lower()

    if action == "add":
        # hotspot add <name> <x> <y> <w> <h> -> <label>
        if len(tokens) != 9 or tokens[7] != "->":
            raise ScriptParseError(
                f"{path}:{line_no} hotspot add expects '<name> <x> <y> <w> <h> -> <label>'"
            )
        name = tokens[2].strip()
        if not name:
            raise ScriptParseError(f"{path}:{line_no} hotspot add missing name")
        x = _parse_int(tokens[3], path, line_no)
        y = _parse_int(tokens[4], path, line_no)
        w = _parse_int(tokens[5], path, line_no)
        h = _parse_int(tokens[6], path, line_no)
        if w <= 0 or h <= 0:
            raise ScriptParseError(f"{path}:{line_no} hotspot width/height must be > 0")
        target = _strip_var_prefix(tokens[8])
        if not target:
            raise ScriptParseError(f"{path}:{line_no} hotspot add missing target label")
        return HotspotAdd(name=name, x=x, y=y, w=w, h=h, target=target)

    if action == "poly":
        # hotspot poly <name> <x1> <y1> ... -> <label>
        if len(tokens) < 11:
            raise ScriptParseError(
                f"{path}:{line_no} hotspot poly expects '<name> <x1> <y1> <x2> <y2> <x3> <y3> ... -> <label>'"
            )
        if "->" not in tokens:
            raise ScriptParseError(f"{path}:{line_no} hotspot poly missing '-> <label>'")
        arrow_idx = tokens.index("->")
        if arrow_idx < 9 or arrow_idx + 1 >= len(tokens) or arrow_idx + 2 != len(tokens):
            raise ScriptParseError(
                f"{path}:{line_no} hotspot poly expects '<name> <x1> <y1> ... -> <label>'"
            )
        name = tokens[2].strip()
        if not name:
            raise ScriptParseError(f"{path}:{line_no} hotspot poly missing name")
        coords = tokens[3:arrow_idx]
        if len(coords) < 6 or len(coords) % 2 != 0:
            raise ScriptParseError(
                f"{path}:{line_no} hotspot poly requires at least 3 points (x y pairs)"
            )
        points = []
        for idx in range(0, len(coords), 2):
            x = _parse_int(coords[idx], path, line_no)
            y = _parse_int(coords[idx + 1], path, line_no)
            points.append((x, y))
        target = _strip_var_prefix(tokens[arrow_idx + 1])
        if not target:
            raise ScriptParseError(f"{path}:{line_no} hotspot poly missing target label")
        return HotspotPoly(name=name, points=points, target=target)

    if action == "remove":
        if len(tokens) != 3:
            raise ScriptParseError(f"{path}:{line_no} hotspot remove expects '<name>'")
        name = tokens[2].strip()
        if not name:
            raise ScriptParseError(f"{path}:{line_no} hotspot remove missing name")
        return HotspotRemove(name=name)

    if action == "clear":
        if len(tokens) != 2:
            raise ScriptParseError(f"{path}:{line_no} hotspot clear does not take arguments")
        return HotspotRemove(name=None)

    if action == "debug":
        if len(tokens) != 3:
            raise ScriptParseError(f"{path}:{line_no} hotspot debug expects on/off")
        raw = str(tokens[2]).strip().lower()
        if raw in {"on", "true", "1"}:
            enabled = True
        elif raw in {"off", "false", "0"}:
            enabled = False
        else:
            raise ScriptParseError(f"{path}:{line_no} hotspot debug expects on/off")
        return HotspotDebug(enabled=enabled)

    raise ScriptParseError(f"{path}:{line_no} hotspot expects add/poly/remove/clear/debug")


cpdef object _parse_camera(list tokens, object path, int line_no):
    cdef double pan_x
    cdef double pan_y
    cdef double zoom
    # camera <pan_x> <pan_y> <zoom>
    # camera reset
    if len(tokens) == 2 and tokens[1].lower() == "reset":
        return CameraSet(pan_x=0.0, pan_y=0.0, zoom=1.0)
    if len(tokens) != 4:
        raise ScriptParseError(f"{path}:{line_no} camera expects '<pan_x> <pan_y> <zoom>' or 'reset'")
    try:
        pan_x = float(tokens[1])
        pan_y = float(tokens[2])
        zoom = float(tokens[3])
    except ValueError as exc:
        raise ScriptParseError(f"{path}:{line_no} camera values must be numbers") from exc
    if zoom <= 0:
        raise ScriptParseError(f"{path}:{line_no} camera zoom must be > 0")
    return CameraSet(pan_x=pan_x, pan_y=pan_y, zoom=zoom)


cpdef object _parse_hud(list tokens, object path, int line_no):
    cdef str action
    cdef str name
    cdef str style
    cdef str text
    cdef str icon
    cdef int x, y, w, h
    cdef str target
    cdef int arrow_idx

    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} hud expects add/remove/clear")
    action = tokens[1].strip().lower()

    if action == "add":
        # hud add <name> text "<label>" <x> <y> <w> <h> -> <target>
        # hud add <name> icon "<path>" <x> <y> <w> <h> -> <target>
        # hud add <name> both "<path>" "<label>" <x> <y> <w> <h> -> <target>
        if len(tokens) < 4:
            raise ScriptParseError(
                f"{path}:{line_no} hud add expects '<name> text|icon|both ...'"
            )
        name = tokens[2].strip()
        if not name:
            raise ScriptParseError(f"{path}:{line_no} hud add missing name")
        style = tokens[3].strip().lower()
        if style not in {"text", "icon", "both"}:
            raise ScriptParseError(
                f"{path}:{line_no} hud add style must be text/icon/both, got '{style}'"
            )

        if style == "text":
            # hud add <name> text "<label>" <x> <y> <w> <h> -> <target>
            if len(tokens) != 11:
                raise ScriptParseError(
                    f"{path}:{line_no} hud add text expects "
                    f"'<name> text \"<label>\" <x> <y> <w> <h> -> <target>'"
                )
            if tokens[9] != "->":
                raise ScriptParseError(f"{path}:{line_no} hud add text missing '-> <label>'")
            text = str(tokens[4])
            x = _parse_int(tokens[5], path, line_no)
            y = _parse_int(tokens[6], path, line_no)
            w = _parse_int(tokens[7], path, line_no)
            h = _parse_int(tokens[8], path, line_no)
            target = _strip_var_prefix(tokens[10])
            return HudAdd(name=name, style="text", text=text, icon=None,
                          x=x, y=y, w=w, h=h, target=target)

        if style == "icon":
            # hud add <name> icon "<path>" <x> <y> <w> <h> -> <target>
            if len(tokens) != 11:
                raise ScriptParseError(
                    f"{path}:{line_no} hud add icon expects "
                    f"'<name> icon \"<path>\" <x> <y> <w> <h> -> <target>'"
                )
            if tokens[9] != "->":
                raise ScriptParseError(f"{path}:{line_no} hud add icon missing '-> <label>'")
            icon = str(tokens[4])
            x = _parse_int(tokens[5], path, line_no)
            y = _parse_int(tokens[6], path, line_no)
            w = _parse_int(tokens[7], path, line_no)
            h = _parse_int(tokens[8], path, line_no)
            target = _strip_var_prefix(tokens[10])
            return HudAdd(name=name, style="icon", text=None, icon=icon,
                          x=x, y=y, w=w, h=h, target=target)

        if style == "both":
            # hud add <name> both "<path>" "<label>" <x> <y> <w> <h> -> <target>
            if len(tokens) != 12:
                raise ScriptParseError(
                    f"{path}:{line_no} hud add both expects "
                    f"'<name> both \"<icon>\" \"<label>\" <x> <y> <w> <h> -> <target>'"
                )
            if tokens[10] != "->":
                raise ScriptParseError(f"{path}:{line_no} hud add both missing '-> <label>'")
            icon = str(tokens[4])
            text = str(tokens[5])
            x = _parse_int(tokens[6], path, line_no)
            y = _parse_int(tokens[7], path, line_no)
            w = _parse_int(tokens[8], path, line_no)
            h = _parse_int(tokens[9], path, line_no)
            target = _strip_var_prefix(tokens[11])
            return HudAdd(name=name, style="both", text=text, icon=icon,
                          x=x, y=y, w=w, h=h, target=target)

    if action == "remove":
        if len(tokens) != 3:
            raise ScriptParseError(f"{path}:{line_no} hud remove expects '<name>'")
        name = tokens[2].strip()
        if not name:
            raise ScriptParseError(f"{path}:{line_no} hud remove missing name")
        return HudRemove(name=name)

    if action == "clear":
        if len(tokens) != 2:
            raise ScriptParseError(f"{path}:{line_no} hud clear does not take arguments")
        return HudRemove(name=None)

    raise ScriptParseError(f"{path}:{line_no} hud expects add/remove/clear")


cpdef object _parse_input(list tokens, object path, int line_no):
    """Parse: input <var> "<prompt>" [default "<val>"];"""
    cdef str variable, prompt
    cdef object default_value = None
    if len(tokens) < 3:
        raise ScriptParseError(f"{path}:{line_no} input expects '<var> \"<prompt>\"'")
    variable = tokens[1].strip()
    prompt = str(tokens[2])
    if len(tokens) >= 5 and tokens[3].lower() == "default":
        default_value = str(tokens[4])
    elif len(tokens) > 3 and tokens[3].lower() != "default":
        raise ScriptParseError(f"{path}:{line_no} input unexpected token '{tokens[3]}'")
    return Input(variable=variable, prompt=prompt, default_value=default_value)


cpdef object _parse_phone(list tokens, object path, int line_no):
    """Parse: phone open/msg/close ..."""
    cdef str action, contact, side, text
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} phone expects open/msg/close")
    action = tokens[1].strip().lower()
    if action == "open":
        if len(tokens) < 3:
            raise ScriptParseError(f"{path}:{line_no} phone open expects '\"<contact>\"'")
        contact = str(tokens[2])
        return Phone(action="open", contact=contact)
    if action == "msg":
        if len(tokens) < 4:
            raise ScriptParseError(f"{path}:{line_no} phone msg expects '<side> \"<text>\"'")
        side = tokens[2].strip().lower()
        if side not in {"left", "right"}:
            raise ScriptParseError(f"{path}:{line_no} phone msg side must be left/right")
        text = str(tokens[3])
        return Phone(action="msg", side=side, text=text)
    if action == "close":
        return Phone(action="close")
    raise ScriptParseError(f"{path}:{line_no} phone expects open/msg/close")


cpdef object _parse_meter(list tokens, object path, int line_no):
    """Parse: meter show/hide/update/clear ..."""
    cdef str action, variable, label, color
    cdef int min_val, max_val
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} meter expects show/hide/update/clear")
    action = tokens[1].strip().lower()
    if action == "show":
        # meter show <var> "<label>" <min> <max> [color <hex>]
        if len(tokens) < 6:
            raise ScriptParseError(
                f"{path}:{line_no} meter show expects '<var> \"<label>\" <min> <max> [color <hex>]'"
            )
        variable = tokens[2].strip()
        label = str(tokens[3])
        min_val = _parse_int(tokens[4], path, line_no)
        max_val = _parse_int(tokens[5], path, line_no)
        color = None
        if len(tokens) >= 8 and tokens[6].lower() == "color":
            color = str(tokens[7])
        return Meter(action="show", variable=variable, label=label,
                     min_val=min_val, max_val=max_val, color=color)
    if action == "hide":
        if len(tokens) < 3:
            raise ScriptParseError(f"{path}:{line_no} meter hide expects '<var>'")
        variable = tokens[2].strip()
        return Meter(action="hide", variable=variable)
    if action == "update":
        if len(tokens) < 3:
            raise ScriptParseError(f"{path}:{line_no} meter update expects '<var>'")
        variable = tokens[2].strip()
        return Meter(action="update", variable=variable)
    if action == "clear":
        return Meter(action="clear")
    raise ScriptParseError(f"{path}:{line_no} meter expects show/hide/update/clear")


cpdef object _parse_item(list tokens, object path, int line_no):
    """Parse: item add/remove/clear ..."""
    cdef str action, item_id, name, description, icon
    cdef int amount = 1
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} item expects add/remove/clear")
    action = tokens[1].strip().lower()
    if action == "add":
        # item add <id> "<name>" "<desc>" icon "<icon>" [amount <int>]
        if len(tokens) < 6:
            raise ScriptParseError(
                f"{path}:{line_no} item add expects '<id> \"<name>\" \"<desc>\" icon \"<icon>\" [amount <int>]'"
            )
        item_id = tokens[2].strip()
        name = str(tokens[3])
        description = str(tokens[4])
        if tokens[5].lower() != "icon":
            raise ScriptParseError(f"{path}:{line_no} item add missing 'icon' keyword")
        if len(tokens) < 7:
             raise ScriptParseError(f"{path}:{line_no} item add missing icon path")
        icon = str(tokens[6])
        if len(tokens) >= 9 and tokens[7].lower() == "amount":
            amount = _parse_int(tokens[8], path, line_no)
        return Item(action="add", item_id=item_id, name=name,
                    description=description, icon=icon, amount=amount)
    if action == "remove":
        # item remove <id> [amount <int>]
        if len(tokens) < 3:
            raise ScriptParseError(f"{path}:{line_no} item remove expects '<id>'")
        item_id = tokens[2].strip()
        if len(tokens) >= 5 and tokens[3].lower() == "amount":
            amount = _parse_int(tokens[4], path, line_no)
        return Item(action="remove", item_id=item_id, amount=amount)
    if action == "clear":
        return Item(action="clear")
    raise ScriptParseError(f"{path}:{line_no} item expects add/remove/clear")


cpdef object _parse_map(list tokens, object path, int line_no):
    """Parse: map show/poi/hide ..."""
    cdef str action, value, label, target
    cdef int x, y
    if len(tokens) < 2:
        raise ScriptParseError(f"{path}:{line_no} map expects show/poi/hide")
    action = tokens[1].strip().lower()
    if action == "show":
        # map show "<image>"
        if len(tokens) < 3:
            raise ScriptParseError(f"{path}:{line_no} map show expects '\"<image>\"'")
        value = str(tokens[2])
        return Map(action="show", value=value)
    if action == "poi":
        # map poi "<label>" <x1> <y1> <x2> <y2> ... -> <target>
        if len(tokens) < 7:
            raise ScriptParseError(
                f"{path}:{line_no} map poi expects '\"<label>\" <x1> <y1> ... -> <target>'"
            )
        if "->" not in tokens:
            raise ScriptParseError(f"{path}:{line_no} map poi missing '->'")
        arrow_idx = tokens.index("->")
        if arrow_idx < 5 or arrow_idx + 1 >= len(tokens) or arrow_idx + 2 != len(tokens):
             raise ScriptParseError(
                f"{path}:{line_no} map poi expects '\"<label>\" <x1> <y1> ... -> <target>'"
            )
        label = str(tokens[2])
        coords = tokens[3:arrow_idx]
        if len(coords) < 2 or len(coords) % 2 != 0:
            raise ScriptParseError(
                f"{path}:{line_no} map poi requires at least 1 point (or 3+ for polygon)"
            )
        points = []
        for idx in range(0, len(coords), 2):
            x = _parse_int(coords[idx], path, line_no)
            y = _parse_int(coords[idx + 1], path, line_no)
            points.append((x, y))
        target = _strip_var_prefix(tokens[arrow_idx + 1])
        # If only one point is provided, we set 'pos' for compatibility, but 'points' is preferred.
        pos = points[0] if len(points) == 1 else None
        return Map(action="poi", label=label, pos=pos, points=points, target=target)
    if action == "hide":
        return Map(action="hide")
    raise ScriptParseError(f"{path}:{line_no} map expects show/poi/hide")
