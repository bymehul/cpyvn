#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


def main() -> int:
    path = Path("vnef-video/src/vnef_video.c")
    if not path.exists():
        raise SystemExit(f"missing source file: {path}")

    original = path.read_text(encoding="utf-8")
    source = original
    replacements = {
        "int ch = v->adec->ch_layout.nb_channels > 0 ? v->adec->ch_layout.nb_channels : (v->adec->channels > 0 ? v->adec->channels : 2);":
        "int ch = v->adec->ch_layout.nb_channels > 0 ? v->adec->ch_layout.nb_channels : 2;",
        "out_info->channels = v->adec->ch_layout.nb_channels > 0 ? v->adec->ch_layout.nb_channels : v->adec->channels;":
        "out_info->channels = v->adec->ch_layout.nb_channels > 0 ? v->adec->ch_layout.nb_channels : 2;",
        "int channels = v->adec->ch_layout.nb_channels > 0 ? v->adec->ch_layout.nb_channels : v->adec->channels;":
        "int channels = v->adec->ch_layout.nb_channels > 0 ? v->adec->ch_layout.nb_channels : 2;",
    }

    unresolved: list[str] = []
    patched = 0
    already_ok = 0

    for old, new in replacements.items():
        if old in source:
            source = source.replace(old, new)
            patched += 1
            continue
        if new in source:
            already_ok += 1
            continue
        unresolved.append(old)

    if unresolved:
        joined = "\n".join(f"  - {line}" for line in unresolved)
        raise SystemExit(f"expected patterns not found in {path}:\n{joined}")

    if source != original:
        path.write_text(source, encoding="utf-8")
        print(f"patched {path} ({patched} replacements)")
    else:
        print(f"no patch needed for {path} ({already_ok} already compatible)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
