from __future__ import annotations

from pathlib import Path
import shlex
from typing import List, Tuple

import cython

from ..script import Command, IfJump, Label
from .helpers import _is_signed_int, _parse_value, _strip_var_prefix
from .model import ScriptParseError


cdef int _check_counter = 0


cpdef tuple _parse_track(list args, object path, int line_no):
    cdef int amount = 1
    cdef list var_parts = args
    cdef list name_parts = []
    cdef object part
    cdef str name
    if not args:
        raise ScriptParseError(f"{path}:{line_no} track requires a stat name")

    if len(args) >= 2 and _is_signed_int(str(args[-1])):
        amount = int(str(args[-1]))
        var_parts = args[:-1]

    if not var_parts:
        raise ScriptParseError(f"{path}:{line_no} track missing stat name")

    for part in var_parts:
        name_parts.append(_strip_var_prefix(str(part)))
    name = "_".join(name_parts)
    return name, amount


cpdef tuple _parse_check_goto(list args, object path, int line_no):
    cdef int idx
    cdef str cond_text
    cdef str target
    cdef tuple cond
    if not args:
        raise ScriptParseError(f"{path}:{line_no} check missing condition")
    if "go" in args:
        idx = args.index("go")
    elif "goto" in args:
        idx = args.index("goto")
    else:
        raise ScriptParseError(f"{path}:{line_no} check missing go target")
    if idx + 1 >= len(args):
        raise ScriptParseError(f"{path}:{line_no} check missing go target")

    cond_text = " ".join(args[:idx])
    target = _strip_var_prefix(args[idx + 1])
    cond = _parse_condition(cond_text, path, line_no)
    return cond, target


cpdef tuple _parse_condition(str arg, object path, int line_no):
    cdef list tokens = shlex.split(arg)
    cdef str token
    cdef bint negate
    cdef str name
    cdef str op
    cdef str raw_value
    cdef object value
    if not tokens:
        raise ScriptParseError(f"{path}:{line_no} check missing condition")
    if len(tokens) == 1:
        token = tokens[0]
        negate = token.startswith("!")
        if negate:
            token = token[1:]
        name = _strip_var_prefix(token)
        value = False if negate else True
        return name, "==", value
    if len(tokens) >= 3:
        name = _strip_var_prefix(tokens[0])
        op = tokens[1]
        if op not in {"==", "!=", ">", ">=", "<", "<="}:
            raise ScriptParseError(f"{path}:{line_no} check invalid operator '{op}'")
        raw_value = " ".join(tokens[2:])
        value = _parse_value(raw_value)
        return name, op, value
    raise ScriptParseError(f"{path}:{line_no} check invalid condition")


cpdef void _inject_check(
    tuple cond,
    list inner,
    list commands,
    dict labels,
    push,
    int line_no,
    object path,
):
    cdef object cmd
    cdef str name
    cdef str op
    cdef object value
    cdef str inverted
    cdef str skip_label
    for cmd in inner:
        if isinstance(cmd, Label):
            if not cmd.name.startswith("__check_skip_"):
                raise ScriptParseError(f"{path}:{line_no} labels are not allowed inside check blocks")

    name, op, value = cond
    inverted = _invert_op(op)
    skip_label = f"__check_skip_{_next_check_id()}"
    push(IfJump(name=name, op=inverted, value=value, target=skip_label), line_no)
    commands.extend(inner)
    labels[skip_label] = len(commands)
    push(Label(skip_label), line_no)


@cython.cfunc
@cython.inline
cdef str _invert_op(str op):
    mapping = {
        "==": "!=",
        "!=": "==",
        ">": "<=",
        ">=": "<",
        "<": ">=",
        "<=": ">",
    }
    return mapping.get(op, "!=")


@cython.cfunc
@cython.inline
cdef int _next_check_id():
    global _check_counter
    _check_counter += 1
    return _check_counter
