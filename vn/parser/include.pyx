from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Tuple

import cython

from ..script import Call, Choice, Command, CharacterDef, IfJump, Jump, Label, Map, Say, ShowChar, Voice
from .helpers import _as_string, _strip_var_prefix
from .model import Script, ScriptParseError


cpdef tuple _parse_include(list args, object path, int line_no):
    cdef str raw
    cdef str alias
    cdef object include_path
    if len(args) != 3:
        raise ScriptParseError(f'{path}:{line_no} include requires alias: include "file.vn" as name')
    raw = _as_string(args[0], path, line_no)
    if args[1] != "as":
        raise ScriptParseError(f'{path}:{line_no} include requires alias: include "file.vn" as name')
    alias = _as_string(args[2], path, line_no)
    if not alias or not _is_valid_alias(alias):
        raise ScriptParseError(f"{path}:{line_no} include alias must be an identifier")
    include_path = Path(raw)
    if not include_path.is_absolute():
        include_path = (path.parent / include_path).resolve()
    return include_path, alias


cpdef bint _is_valid_alias(str value):
    cdef str ch
    if not value:
        return False
    if not (value[0].isalpha() or value[0] == "_"):
        return False
    for ch in value:
        if not (ch.isalnum() or ch == "_"):
            return False
    return True


cpdef tuple _parse_call(list args, object path, int line_no):
    cdef str call_path
    cdef str label
    if len(args) < 2:
        raise ScriptParseError(f"{path}:{line_no} call expects '<file> <label>'")
    call_path = _as_string(args[0], path, line_no)
    label = _strip_var_prefix(args[1])
    if not label:
        raise ScriptParseError(f"{path}:{line_no} call missing label")
    return call_path, label


@cython.cfunc
@cython.inline
cdef str _namespace_label(str name, dict mapping, object include_path):
    if name.startswith("::"):
        return name[2:]
    if "." in name:
        return name
    if name in mapping:
        return mapping[name]
    raise ScriptParseError(
        f"{include_path} unknown label '{name}' in namespaced include "
        f"(use ::{name} for global or alias.label)"
    )


@cython.cfunc
@cython.inline
cdef object _namespace_char(object name, dict mapping):
    if name is None:
        return None
    if name.startswith("::"):
        return name[2:]
    if "." in name:
        return name
    return mapping.get(name, name)


cpdef object _namespace_command(
    object cmd,
    dict mapping,
    object include_path,
    dict char_mapping,
):
    cdef list options
    cdef object text
    cdef object target
    if isinstance(cmd, Label):
        if cmd.name not in mapping:
            raise ScriptParseError(f"{include_path} unknown label '{cmd.name}' in include")
        return Label(mapping[cmd.name])
    if isinstance(cmd, Jump):
        return Jump(_namespace_label(cmd.target, mapping, include_path))
    if isinstance(cmd, IfJump):
        return IfJump(
            name=cmd.name,
            op=cmd.op,
            value=cmd.value,
            target=_namespace_label(cmd.target, mapping, include_path),
        )
    if isinstance(cmd, Choice):
        options = []
        for text, target in cmd.options:
            options.append((text, _namespace_label(target, mapping, include_path)))
        return Choice(options=options, prompt=cmd.prompt)
    if isinstance(cmd, CharacterDef):
        return CharacterDef(
            ident=_namespace_char(cmd.ident, char_mapping) or cmd.ident,
            display_name=cmd.display_name,
            color=cmd.color,
            sprites=cmd.sprites,
            voice_tag=_namespace_char(cmd.voice_tag, char_mapping),
            pos=cmd.pos,
            anchor=cmd.anchor,
            z=cmd.z,
            float_amp=cmd.float_amp,
            float_speed=cmd.float_speed,
        )
    if isinstance(cmd, ShowChar):
        return ShowChar(
            ident=_namespace_char(cmd.ident, char_mapping) or cmd.ident,
            expression=cmd.expression,
            pos=cmd.pos,
            anchor=cmd.anchor,
            z=cmd.z,
            fade=cmd.fade,
            float_amp=cmd.float_amp,
            float_speed=cmd.float_speed,
        )
    if isinstance(cmd, Say):
        return Say(
            speaker=_namespace_char(cmd.speaker, char_mapping),
            text=cmd.text,
        )
    if isinstance(cmd, Voice):
        return Voice(
            character=_namespace_char(cmd.character, char_mapping),
            path=cmd.path,
        )
    if isinstance(cmd, Map):
        if cmd.action == "poi":
            return Map(
                action=cmd.action,
                value=cmd.value,
                label=cmd.label,
                pos=cmd.pos,
                points=cmd.points,
                target=_namespace_label(cmd.target, mapping, include_path),
            )
        return cmd
    return cmd


cpdef void _merge_script(
    object included,
    list commands,
    dict labels,
    object path,
    int line_no,
    str alias,
    object include_path,
):
    cdef dict mapping = {}
    cdef list char_ids = []
    cdef dict char_mapping = {}
    cdef list namespaced_commands = []
    cdef dict namespaced_labels = {}
    cdef object name
    cdef object idx
    cdef object cmd
    cdef int offset
    for name in included.labels:
        mapping[name] = f"{alias}.{name}"
    for cmd in included.commands:
        if isinstance(cmd, CharacterDef):
            char_ids.append(cmd.ident)
    for name in char_ids:
        char_mapping[name] = f"{alias}.{name}"
    for cmd in included.commands:
        namespaced_commands.append(_namespace_command(cmd, mapping, include_path, char_mapping))
    for name, idx in included.labels.items():
        namespaced_labels[mapping[name]] = idx
    offset = len(commands)
    for name, idx in namespaced_labels.items():
        if name in labels:
            raise ScriptParseError(f"{path}:{line_no} duplicate label '{name}' from include")
        labels[name] = idx + offset
    commands.extend(namespaced_commands)
