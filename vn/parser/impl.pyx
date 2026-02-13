from __future__ import annotations

import logging
import importlib
from pathlib import Path
import shlex
from typing import Dict, List, Optional

import cython

from ..script import (
    AddVar,
    Animate,
    Blend,
    Call,
    Choice,
    Command,
    GarbageCollect,
    Hide,
    HudAdd,
    HudRemove,
    IfJump,
    Input,
    Item,
    Jump,
    Label,
    Load,
    Loading,
    Map,
    Meter,
    Notify,
    Phone,
    Save,
    Say,
    Scene,
    SetVar,
    Show,
    ShowChar,
    Video,
    Wait,
    WaitVideo,
    WaitVoice,
)
from .blocks import _collect_statement, _parse_character_block, _parse_choice_block, _strip_inline_comment
from .commands import (
    _parse_ask_prompt,
    _parse_blend,
    _parse_camera,
    _parse_cache,
    _parse_echo,
    _parse_float,
    _parse_hotspot,
    _parse_hud,
    _parse_input,
    _parse_loading_header,
    _parse_meter,
    _parse_mute,
    _parse_notify,
    _parse_phone,
    _parse_item,
    _parse_map,
    _parse_play,
    _parse_animate,
    _parse_preload,
    _parse_show_char,
    _parse_show_tokens,
    _parse_slot,
    _parse_sound_effect,
    _parse_video,
    _parse_voice,
)
from .helpers import (
    _as_string,
    _is_dialogue_line,
    _parse_scene,
    _parse_set,
    _pop_transition,
    _strip_trailing_semicolon,
    _strip_var_prefix,
)
from .logic import _inject_check, _parse_check_goto, _parse_condition, _parse_track
from .model import Script, ScriptParseError

logger = logging.getLogger("cpyvn.parser")

_include_mod = importlib.import_module("vn.parser.include")
_merge_script = _include_mod._merge_script
_parse_call = _include_mod._parse_call
_parse_include = _include_mod._parse_include


@cython.cfunc
@cython.inline
cdef void _mark_include_closed(dict include_state):
    if include_state.get("open"):
        include_state["open"] = False


@cython.cfunc
@cython.inline
cdef void _push_command(list commands, object cmd, object path, int line_no):
    commands.append(cmd)
    logger.debug("Parsed %s at %s:%d", cmd, path, line_no)


def parse_script(path: str | Path, _seen: Optional[set[Path]] = None) -> Script:
    cdef list lines
    cdef list commands
    cdef dict labels
    cdef dict include_state
    path = Path(path).resolve()
    if not path.exists():
        raise ScriptParseError(f"Script not found: {path}")
    if _seen is None:
        _seen = set()
    if path in _seen:
        raise ScriptParseError(f"Circular include detected: {path}")
    _seen.add(path)
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
        commands = []
        labels = {}
        include_state = {"open": True}

        _parse_block(
            lines,
            0,
            path,
            commands,
            labels,
            allow_labels=True,
            seen=_seen,
            top_level=True,
            include_state=include_state,
            in_loading=False,
        )

        return Script(commands=commands, labels=labels)
    finally:
        _seen.discard(path)


def _parse_block(
    lines: list,
    int index,
    object path,
    list commands,
    dict labels,
    bint allow_labels,
    set seen,
    bint top_level,
    dict include_state,
    bint in_loading,
):
    cdef int i = index
    cdef str raw
    cdef int line_no
    cdef str statement
    cdef str stripped
    cdef int indent
    cdef list tokens
    cdef str cmd
    cdef list args
    cdef object scene
    cdef object cond
    cdef list inner
    cdef object preload
    cdef object cache_action
    cdef object music
    cdef object video_cmd
    cdef object sound
    cdef object echo
    cdef object voice
    cdef object mute
    cdef object hotspot_cmd
    cdef object camera_cmd
    cdef object include_path
    cdef object alias
    cdef object included
    cdef object name
    cdef object value
    cdef object amount
    cdef object animate_cmd
    cdef object target
    cdef object text
    cdef object style
    cdef object seconds
    cdef object slot
    cdef object call_path
    cdef object label
    cdef list parts
    cdef object transition_style
    cdef object transition_seconds
    cdef object fade
    cdef list options
    cdef object prompt

    def _push_for_check(cmd, ln):
        _push_command(commands, cmd, path, ln)

    while i < len(lines):
        raw = lines[i]
        line_no = i + 1
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
            return i

        if stripped.endswith("{"):
            header = _strip_trailing_semicolon(stripped[:-1].strip())
            if header.startswith("character "):
                if not top_level:
                    raise ScriptParseError(f"{path}:{line_no} character blocks only allowed at top-level")
                if include_state.get("open"):
                    include_state["open"] = False
                ident = header[len("character ") :].strip()
                if not ident:
                    raise ScriptParseError(f"{path}:{line_no} character missing id")
                character, i = _parse_character_block(lines, i, path, line_no, ident)
                _push_command(commands, character, path, line_no)
                continue
            if header.startswith("scene "):
                if top_level and include_state.get("open"):
                    include_state["open"] = False
                scene = _parse_scene(header[len("scene ") :], path, line_no)
                _push_command(commands, scene, path, line_no)
                i = _parse_block(
                    lines,
                    i,
                    path,
                    commands,
                    labels,
                    allow_labels,
                    seen=seen,
                    top_level=False,
                    include_state=include_state,
                    in_loading=in_loading,
                )
                continue
            if header.startswith("check "):
                if top_level and include_state.get("open"):
                    include_state["open"] = False
                cond = _parse_condition(header[len("check ") :], path, line_no)
                inner = []
                i = _parse_block(
                    lines,
                    i,
                    path,
                    inner,
                    labels,
                    allow_labels=False,
                    seen=seen,
                    top_level=False,
                    include_state=include_state,
                    in_loading=in_loading,
                )
                _inject_check(cond, inner, commands, labels, _push_for_check, line_no, path)
                continue
            if header.startswith("loading"):
                if top_level and include_state.get("open"):
                    include_state["open"] = False
                text = _parse_loading_header(header, path, line_no)
                _push_command(commands, Loading(action="start", text=text), path, line_no)
                i = _parse_block(
                    lines,
                    i,
                    path,
                    commands,
                    labels,
                    allow_labels=False,
                    seen=seen,
                    top_level=False,
                    include_state=include_state,
                    in_loading=True,
                )
                _push_command(commands, Loading(action="end"), path, line_no)
                continue
            if top_level:
                _mark_include_closed(include_state)
            i = _parse_block(
                lines,
                i,
                path,
                commands,
                labels,
                allow_labels,
                seen=seen,
                top_level=False,
                include_state=include_state,
                in_loading=in_loading,
            )
            continue

        indent = len(raw) - len(raw.lstrip(" "))

        if stripped.startswith("ask "):
            if top_level:
                _mark_include_closed(include_state)
            prompt, timeout, timeout_default = _parse_ask_prompt(stripped, path, line_no)
            options, i = _parse_choice_block(lines, i, indent, path)
            if not options:
                raise ScriptParseError(f"{path}:{line_no} ask has no options")
            _push_command(commands, Choice(options, prompt=prompt, timeout=timeout, timeout_default=timeout_default), path, line_no)
            continue

        if stripped.startswith("label "):
            if not allow_labels:
                raise ScriptParseError(f"{path}:{line_no} labels are not allowed inside blocks")
            if top_level:
                _mark_include_closed(include_state)
            name = stripped[len("label ") :].strip()
            if name.endswith(":"):
                name = name[:-1].strip()
            if not name:
                raise ScriptParseError(f"{path}:{line_no} label missing name")
            labels[name] = len(commands)
            _push_command(commands, Label(name), path, line_no)
            continue

        tokens = shlex.split(stripped)
        if not tokens:
            continue
        cmd = tokens[0]
        args = tokens[1:]

        if cmd in {"go", "goto", "jump"}:
            if top_level:
                _mark_include_closed(include_state)
            if not args:
                raise ScriptParseError(f"{path}:{line_no} go missing target")
            _push_command(commands, Jump(_strip_var_prefix(args[0])), path, line_no)
            continue

        if cmd == "scene":
            if top_level:
                _mark_include_closed(include_state)
            arg = " ".join(args)
            scene = _parse_scene(arg, path, line_no)
            _push_command(commands, scene, path, line_no)
            continue

        if cmd == "add":
            if top_level:
                _mark_include_closed(include_state)
            show = _parse_show_tokens(args, path, line_no)
            _push_command(commands, show, path, line_no)
            continue

        if cmd == "item":
            if top_level:
                _mark_include_closed(include_state)
            item_cmd = _parse_item(tokens, path, line_no)
            _push_command(commands, item_cmd, path, line_no)
            continue

        if cmd == "map":
            if top_level:
                _mark_include_closed(include_state)
            map_cmd = _parse_map(tokens, path, line_no)
            _push_command(commands, map_cmd, path, line_no)
            continue

        if cmd == "show":
            if top_level:
                _mark_include_closed(include_state)
            # Support `show rect ...` / `show image ...` as aliases of `add ...`.
            if args and args[0] in {"rect", "image"}:
                show = _parse_show_tokens(args, path, line_no)
            else:
                show = _parse_show_char(args, path, line_no)
            _push_command(commands, show, path, line_no)
            continue

        if cmd == "off":
            if top_level:
                _mark_include_closed(include_state)
            if not args:
                raise ScriptParseError(f"{path}:{line_no} off missing name")
            parts = [str(arg) for arg in args]
            parts, transition_style, transition_seconds = _pop_transition(parts, path, line_no)
            fade = transition_seconds if transition_style == "fade" else None
            if not parts:
                raise ScriptParseError(f"{path}:{line_no} off missing name")
            _push_command(
                commands,
                Hide(
                    _strip_var_prefix(parts[0]),
                    fade=fade,
                    transition_style=transition_style,
                    transition_seconds=transition_seconds,
                ),
                path,
                line_no,
            )
            continue

        if cmd == "play":
            if top_level:
                _mark_include_closed(include_state)
            music = _parse_play(tokens, path, line_no)
            _push_command(commands, music, path, line_no)
            continue

        if cmd == "video":
            if top_level:
                _mark_include_closed(include_state)
            video_cmd = _parse_video(tokens, path, line_no)
            _push_command(commands, video_cmd, path, line_no)
            continue

        if cmd == "sound":
            if top_level:
                _mark_include_closed(include_state)
            sound = _parse_sound_effect(tokens, path, line_no)
            _push_command(commands, sound, path, line_no)
            continue

        if cmd == "echo":
            if top_level:
                _mark_include_closed(include_state)
            echo = _parse_echo(tokens, path, line_no)
            _push_command(commands, echo, path, line_no)
            continue

        if cmd == "voice":
            if top_level:
                _mark_include_closed(include_state)
            voice = _parse_voice(tokens, path, line_no)
            _push_command(commands, voice, path, line_no)
            continue

        if cmd == "mute":
            if top_level:
                _mark_include_closed(include_state)
            mute = _parse_mute(tokens, path, line_no)
            _push_command(commands, mute, path, line_no)
            continue

        if cmd == "preload":
            if top_level:
                _mark_include_closed(include_state)
            preload = _parse_preload(tokens, path, line_no)
            _push_command(commands, preload, path, line_no)
            continue

        if cmd == "cache":
            if top_level:
                _mark_include_closed(include_state)
            cache_action = _parse_cache(tokens, path, line_no)
            _push_command(commands, cache_action, path, line_no)
            continue

        if cmd == "gc":
            if top_level:
                _mark_include_closed(include_state)
            _push_command(commands, GarbageCollect(), path, line_no)
            continue

        if cmd == "wait":
            if top_level:
                _mark_include_closed(include_state)
            if len(args) == 1 and str(args[0]).lower() == "voice":
                _push_command(commands, WaitVoice(), path, line_no)
                continue
            if len(args) == 1 and str(args[0]).lower() == "video":
                _push_command(commands, WaitVideo(), path, line_no)
                continue
            seconds = _parse_float(args, path, line_no)
            _push_command(commands, Wait(seconds=seconds), path, line_no)
            continue

        if cmd == "notify":
            if top_level:
                _mark_include_closed(include_state)
            text, seconds = _parse_notify(args, path, line_no)
            _push_command(commands, Notify(text=text, seconds=seconds), path, line_no)
            continue

        if cmd == "blend":
            if top_level:
                _mark_include_closed(include_state)
            style, seconds = _parse_blend(args, path, line_no)
            _push_command(commands, Blend(style=style, seconds=seconds), path, line_no)
            continue

        if cmd == "save":
            if top_level:
                _mark_include_closed(include_state)
            slot = _parse_slot(args, path, line_no, "save")
            _push_command(commands, Save(slot=slot), path, line_no)
            continue

        if cmd == "load":
            if top_level:
                _mark_include_closed(include_state)
            slot = _parse_slot(args, path, line_no, "load")
            _push_command(commands, Load(slot=slot), path, line_no)
            continue

        if cmd == "call":
            if top_level:
                _mark_include_closed(include_state)
            call_path, label = _parse_call(args, path, line_no)
            _push_command(commands, Call(path=call_path, label=label), path, line_no)
            continue

        if cmd == "hotspot":
            if top_level:
                _mark_include_closed(include_state)
            hotspot_cmd = _parse_hotspot(tokens, path, line_no)
            _push_command(commands, hotspot_cmd, path, line_no)
            continue

        if cmd == "hud":
            if top_level:
                _mark_include_closed(include_state)
            hud_cmd = _parse_hud(tokens, path, line_no)
            _push_command(commands, hud_cmd, path, line_no)
            continue

        if cmd == "camera":
            if top_level:
                _mark_include_closed(include_state)
            camera_cmd = _parse_camera(tokens, path, line_no)
            _push_command(commands, camera_cmd, path, line_no)
            continue

        if cmd == "include":
            if not allow_labels:
                raise ScriptParseError(f"{path}:{line_no} include not allowed inside blocks")
            if not top_level:
                raise ScriptParseError(f"{path}:{line_no} include only allowed at top-level")
            if not include_state.get("open"):
                raise ScriptParseError(f"{path}:{line_no} include must appear before any other commands")
            include_path, alias = _parse_include(args, path, line_no)
            included = parse_script(include_path, _seen=seen)
            _merge_script(included, commands, labels, path, line_no, alias=alias, include_path=include_path)
            continue

        if cmd == "set":
            if top_level:
                _mark_include_closed(include_state)
            name, value = _parse_set(" ".join(args), path, line_no)
            _push_command(commands, SetVar(name=name, value=value), path, line_no)
            continue

        if cmd == "track":
            if top_level:
                _mark_include_closed(include_state)
            name, amount = _parse_track(args, path, line_no)
            _push_command(commands, AddVar(name=name, amount=amount), path, line_no)
            continue

        if cmd == "animate":
            if top_level:
                _mark_include_closed(include_state)
            animate_cmd = _parse_animate(args, path, line_no)
            _push_command(commands, animate_cmd, path, line_no)
            continue

        if cmd == "check":
            if top_level:
                _mark_include_closed(include_state)
            cond, target = _parse_check_goto(args, path, line_no)
            _push_command(commands, IfJump(name=cond[0], op=cond[1], value=cond[2], target=target), path, line_no)
            continue

        if cmd == "input":
            if top_level:
                _mark_include_closed(include_state)
            input_cmd = _parse_input(tokens, path, line_no)
            _push_command(commands, input_cmd, path, line_no)
            continue

        if cmd == "phone":
            if top_level:
                _mark_include_closed(include_state)
            phone_cmd = _parse_phone(tokens, path, line_no)
            _push_command(commands, phone_cmd, path, line_no)
            continue

        if cmd == "meter":
            if top_level:
                _mark_include_closed(include_state)
            meter_cmd = _parse_meter(tokens, path, line_no)
            _push_command(commands, meter_cmd, path, line_no)
            continue

        if _is_dialogue_line(stripped, cmd):
            if top_level:
                _mark_include_closed(include_state)
            speaker = cmd
            if len(args) < 1:
                raise ScriptParseError(f"{path}:{line_no} dialogue missing text")
            text = _as_string(args[0], path, line_no)
            _push_command(commands, Say(speaker, text), path, line_no)
            continue

        raise ScriptParseError(f"{path}:{line_no} unknown command: {cmd}")

    return i
