# cython: language_level=3

from typing import List, Tuple

cimport cython

Style = Tuple[bool, bool, Tuple[int, int, int], bool]
Run = Tuple[str, Style]


cpdef list parse_rich_text(str text, tuple default_color):
    cdef int bold_depth = 0
    cdef int italic_depth = 0
    cdef int shake_depth = 0
    cdef list color_stack = [default_color]
    cdef list runs = []
    cdef list buf = []
    cdef Py_ssize_t i = 0
    cdef Py_ssize_t length = len(text)
    cdef int tag_len
    cdef object tag

    while i < length:
        if text[i] == "[":
            tag_len, tag = _match_tag(text, i)
            if tag_len:
                _flush_run(buf, runs, bold_depth, italic_depth, color_stack[-1], shake_depth)
                bold_depth, italic_depth, shake_depth, color_stack = _apply_tag(
                    <str>tag,
                    bold_depth,
                    italic_depth,
                    shake_depth,
                    color_stack,
                )
                i += tag_len
                continue
        buf.append(text[i])
        i += 1

    _flush_run(buf, runs, bold_depth, italic_depth, color_stack[-1], shake_depth)
    return runs


cpdef int count_visible_chars(str text):
    cdef int count = 0
    cdef Py_ssize_t i = 0
    cdef Py_ssize_t length = len(text)
    cdef int tag_len
    cdef object tag

    while i < length:
        if text[i] == "[":
            tag_len, tag = _match_tag(text, i)
            if tag_len:
                i += tag_len
                continue
        count += 1
        i += 1
    return count


cpdef str slice_visible_text(str text, int max_chars):
    if max_chars <= 0:
        return ""

    cdef list out = []
    cdef int visible = 0
    cdef Py_ssize_t i = 0
    cdef Py_ssize_t length = len(text)
    cdef int tag_len
    cdef object tag

    while i < length and visible < max_chars:
        if text[i] == "[":
            tag_len, tag = _match_tag(text, i)
            if tag_len:
                out.append(text[i : i + tag_len])
                i += tag_len
                continue
        out.append(text[i])
        visible += 1
        i += 1
    return "".join(out)


cdef inline void _flush_run(
    list buf,
    list runs,
    int bold_depth,
    int italic_depth,
    tuple color,
    int shake_depth,
):
    cdef str text
    cdef tuple style
    if not buf:
        return
    text = "".join(buf)
    buf.clear()
    style = (bold_depth > 0, italic_depth > 0, color, shake_depth > 0)
    if runs and runs[-1][1] == style:
        runs[-1] = (runs[-1][0] + text, style)
    else:
        runs.append((text, style))


cdef tuple _match_tag(str text, Py_ssize_t start):
    cdef Py_ssize_t end
    cdef str raw

    end = text.find("]", start + 1)
    if end == -1:
        return 0, None
    raw = text[start + 1 : end].strip()
    if not raw:
        return 0, None
    if _parse_tag(raw) is None:
        return 0, None
    return <int>(end - start + 1), raw


cdef tuple _parse_tag(str tag):
    cdef str lower = tag.lower()
    if lower == "b":
        return "bold", None, False
    if lower == "/b":
        return "bold", None, True
    if lower == "i":
        return "italic", None, False
    if lower == "/i":
        return "italic", None, True
    if lower == "shake":
        return "shake", None, False
    if lower == "/shake":
        return "shake", None, True
    if lower.startswith("color="):
        return "color", tag[6:].strip(), False
    if lower == "/color":
        return "color", None, True
    return None


cdef tuple _apply_tag(
    str tag,
    int bold_depth,
    int italic_depth,
    int shake_depth,
    list color_stack,
):
    cdef tuple parsed = _parse_tag(tag)
    cdef str kind
    cdef object value
    cdef bint closing

    if parsed is None:
        return bold_depth, italic_depth, shake_depth, color_stack

    kind, value, closing = parsed
    if kind == "bold":
        if closing:
            if bold_depth > 0:
                bold_depth -= 1
        else:
            bold_depth += 1
    elif kind == "italic":
        if closing:
            if italic_depth > 0:
                italic_depth -= 1
        else:
            italic_depth += 1
    elif kind == "color":
        if closing:
            if len(color_stack) > 1:
                color_stack.pop()
        else:
            color_stack.append(_parse_color(value, color_stack[-1]))
    elif kind == "shake":
        if closing:
            if shake_depth > 0:
                shake_depth -= 1
        else:
            shake_depth += 1
    return bold_depth, italic_depth, shake_depth, color_stack


cdef tuple _parse_color(object value, tuple fallback):
    cdef str raw
    cdef int r
    cdef int g
    cdef int b

    if not value:
        return fallback

    raw = (<str>value).strip()
    if raw.startswith("#"):
        raw = raw[1:]

    if len(raw) == 3:
        try:
            r = int(raw[0] * 2, 16)
            g = int(raw[1] * 2, 16)
            b = int(raw[2] * 2, 16)
            return r, g, b
        except ValueError:
            return fallback
    if len(raw) == 6:
        try:
            r = int(raw[0:2], 16)
            g = int(raw[2:4], 16)
            b = int(raw[4:6], 16)
            return r, g, b
        except ValueError:
            return fallback
    return fallback
