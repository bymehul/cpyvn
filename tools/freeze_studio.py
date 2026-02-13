#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from export_common import REPO_ROOT, detect_target, normalize_target, zip_dir
from freeze_runner import HIDDEN_IMPORTS as RUNNER_HIDDEN_IMPORTS
from freeze_runner import STDLIB_IMPORTS as RUNNER_STDLIB_IMPORTS


STUDIO_HIDDEN_IMPORTS = [
    "tools.export_common",
    "tools.export_engine",
    "tools.export_game",
    "tools.studio",
    "tools.studio.templates",
]

DATA_PATHS = [
    ("main.py", "."),
    ("vn", "vn"),
    ("tools", "tools"),
    ("setup_cython.py", "."),
    ("requirements.txt", "."),
    ("requirements-video.txt", "."),
    ("requirements-wgpu.txt", "."),
    ("vnef-video", "vnef-video"),
]

def _run(cmd: list[str], cwd: Path) -> None:
    print("$ " + " ".join(cmd))
    result = subprocess.run(cmd, cwd=str(cwd), check=False)
    if result.returncode != 0:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(cmd)}")


def _ensure_pyinstaller() -> None:
    _run([sys.executable, "-m", "PyInstaller", "--version"], REPO_ROOT)


def _add_data_arg(src: Path, dst_rel: str) -> str:
    sep = ";" if sys.platform.startswith("win") else ":"
    return f"{src}{sep}{dst_rel}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Freeze cpyvn Studio into a standalone app (PyInstaller onedir).")
    parser.add_argument("--target", default="host", help="host|linux|windows|macos (must match current OS)")
    parser.add_argument("--output", default="dist/studio", help="Output root")
    parser.add_argument("--name", default="cpyvn-studio", help="Executable/app name")
    parser.add_argument("--clean", action="store_true", help="Pass --clean to PyInstaller")
    parser.add_argument("--zip", action="store_true", help="Create zip archive")
    args = parser.parse_args()

    host = detect_target()
    target_text = str(args.target).strip().lower()
    target = host if target_text == "host" else normalize_target(target_text)
    if target == "all":
        raise ValueError("freeze_studio does not support target=all.")
    if target != host:
        raise RuntimeError(f"Cannot freeze target '{target}' on host '{host}'. Build on matching OS.")

    _ensure_pyinstaller()

    output_root = (REPO_ROOT / str(args.output)).resolve()
    dist_root = output_root / target
    work_root = output_root / f".build-{target}"
    spec_root = output_root / f".spec-{target}"
    dist_root.mkdir(parents=True, exist_ok=True)
    work_root.mkdir(parents=True, exist_ok=True)
    spec_root.mkdir(parents=True, exist_ok=True)

    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--onedir",
        "--name",
        str(args.name),
        "--distpath",
        str(dist_root),
        "--workpath",
        str(work_root),
        "--specpath",
        str(spec_root),
        "--paths",
        str(REPO_ROOT),
    ]
    if args.clean:
        cmd.append("--clean")

    for rel_src, rel_dst in DATA_PATHS:
        src = REPO_ROOT / rel_src
        if src.exists():
            cmd.extend(["--add-data", _add_data_arg(src, rel_dst)])

    seen: set[str] = set()
    for mod in RUNNER_HIDDEN_IMPORTS + RUNNER_STDLIB_IMPORTS + STUDIO_HIDDEN_IMPORTS:
        if mod in seen:
            continue
        seen.add(mod)
        cmd.extend(["--hidden-import", mod])

    cmd.append(str(REPO_ROOT / "tools" / "studio" / "main.py"))
    _run(cmd, REPO_ROOT)

    app_dir = dist_root / str(args.name)
    if not app_dir.exists():
        raise RuntimeError(f"Frozen Studio directory missing: {app_dir}")

    print(f"[ok] frozen studio: {app_dir}")
    if args.zip:
        zip_path = output_root / f"{args.name}-{target}.zip"
        zip_dir(app_dir, zip_path)
        print(f"[ok] zip: {zip_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(2)
