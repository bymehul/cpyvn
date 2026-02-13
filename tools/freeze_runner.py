#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib
import subprocess
import sys
from pathlib import Path

from export_common import REPO_ROOT, detect_target, normalize_target, runner_exec_name


HIDDEN_IMPORTS = [
    "vn",
    "vn.app",
    "vn.assets",
    "vn.cli",
    "vn.config",
    "vn.gpu",
    "vn.parser",
    "vn.runtime",
    "vn.script",
    "vn.text",
    "vn.ui",
    "vn.utils",
    "vn.app.main",
    "vn.cli.main",
    "vn.config.project",
    "vn.ui.impl",
    "vn.runtime.impl",
    "vn.runtime.inspector",
    "vn.runtime.pause_menu",
    "vn.runtime.render",
    "vn.runtime.save",
    "vn.runtime.scene_manifest",
    "vn.runtime.script_editor",
    "vn.runtime.state",
    "vn.runtime.title_menu",
    "vn.runtime.video",
    "vn.runtime.video_factory",
    "vn.runtime.video_vnef",
    "vn.assets.manager",
    "vn.gpu.blur_wgpu",
    "vn.script.ast",
    "vn.text.richtext",
    "vn.parser.impl",
    "vn.parser.blocks",
    "vn.parser.commands",
    "vn.parser.helpers",
    "vn.parser.include",
    "vn.parser.logic",
    "vn.parser.model",
]

STDLIB_IMPORTS = [
    "argparse",
    "ctypes",
    "ctypes.util",
    "dataclasses",
    "gc",
    "importlib",
    "json",
    "logging",
    "math",
    "os",
    "pathlib",
    "random",
    "re",
    "shlex",
    "struct",
    "subprocess",
    "sys",
    "typing",
    "pygame",
]


def _run(cmd: list[str], cwd: Path) -> None:
    print("$ " + " ".join(cmd))
    result = subprocess.run(cmd, cwd=str(cwd), check=False)
    if result.returncode != 0:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(cmd)}")


def _is_frozen_runtime() -> bool:
    return bool(getattr(sys, "frozen", False))


def _ensure_pyinstaller() -> None:
    if _is_frozen_runtime():
        try:
            importlib.import_module("PyInstaller.__main__")
            return
        except Exception as exc:  # pragma: no cover
            raise RuntimeError("PyInstaller is not bundled in this runtime.") from exc
    try:
        _run([sys.executable, "-m", "PyInstaller", "--version"], REPO_ROOT)
    except Exception as exc:  # pragma: no cover
        raise RuntimeError(
            "PyInstaller is not available. Install with:\n"
            "  python -m pip install pyinstaller"
        ) from exc


def _run_pyinstaller(args: list[str]) -> None:
    if _is_frozen_runtime():
        pyi_main = importlib.import_module("PyInstaller.__main__")
        print("$ PyInstaller " + " ".join(args))
        pyi_main.run(args)
        return
    cmd = [sys.executable, "-m", "PyInstaller", *args]
    _run(cmd, REPO_ROOT)


def freeze_runner(
    *,
    target: str = "host",
    output: str = "dist/frozen",
    name: str = "cpyvn-runner",
    no_build_cython: bool = False,
    clean: bool = False,
) -> Path:
    host = detect_target()
    target_text = target.strip().lower()
    resolved_target = host if target_text == "host" else normalize_target(target_text)
    if resolved_target == "all":
        raise ValueError("freeze_runner does not support target=all.")
    if resolved_target != host:
        raise RuntimeError(f"Cannot freeze target '{resolved_target}' on host '{host}'. Build on matching OS.")

    _ensure_pyinstaller()
    if not no_build_cython:
        if _is_frozen_runtime():
            raise RuntimeError(
                "Cython build is not supported inside frozen runtime. "
                "Use --no-build-cython or freeze from source environment."
            )
        _run([sys.executable, "setup_cython.py", "build_ext", "--inplace"], REPO_ROOT)

    output_root = (REPO_ROOT / output).resolve()
    dist_root = output_root / resolved_target
    work_root = output_root / f".build-{resolved_target}"
    spec_root = output_root / f".spec-{resolved_target}"
    dist_root.mkdir(parents=True, exist_ok=True)
    work_root.mkdir(parents=True, exist_ok=True)
    spec_root.mkdir(parents=True, exist_ok=True)

    cmd = [
        "--noconfirm",
        "--onedir",
        "--name",
        name,
        "--distpath",
        str(dist_root),
        "--workpath",
        str(work_root),
        "--specpath",
        str(spec_root),
        "--paths",
        str(REPO_ROOT),
    ]
    if clean:
        cmd.append("--clean")
    for mod in HIDDEN_IMPORTS + STDLIB_IMPORTS:
        cmd.extend(["--hidden-import", mod])
    cmd.append(str(REPO_ROOT / "main.py"))
    _run_pyinstaller(cmd)

    runner_dir = dist_root / name
    exe_path = runner_dir / runner_exec_name(resolved_target)
    if not exe_path.exists():
        raise RuntimeError(f"Frozen runner missing executable: {exe_path}")

    print(f"[ok] frozen runner: {runner_dir}")
    print(f"[ok] executable: {exe_path}")
    return runner_dir


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Freeze cpyvn runner with PyInstaller (onedir).")
    parser.add_argument("--target", default="host", help="host|linux|windows|macos (must match current OS)")
    parser.add_argument("--output", default="dist/frozen", help="Frozen runner output root")
    parser.add_argument("--name", default="cpyvn-runner", help="Executable/app name")
    parser.add_argument("--no-build-cython", action="store_true", help="Skip setup_cython build before freezing")
    parser.add_argument("--clean", action="store_true", help="Pass --clean to PyInstaller")
    args = parser.parse_args(argv)
    freeze_runner(
        target=str(args.target),
        output=str(args.output),
        name=str(args.name),
        no_build_cython=bool(args.no_build_cython),
        clean=bool(args.clean),
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(2)
