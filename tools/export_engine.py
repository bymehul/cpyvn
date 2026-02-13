#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import List

from export_common import (
    REPO_ROOT,
    copy_any,
    detect_target,
    ensure_clean_dir,
    find_vnef_artifact,
    resolve_targets,
    runner_exec_name,
    vnef_lib_name,
    write_json,
    zip_dir,
)
from freeze_runner import freeze_runner as run_freeze_runner


def _run(cmd: list[str], cwd: Path) -> None:
    print("$ " + " ".join(cmd))
    result = subprocess.run(cmd, cwd=str(cwd), check=False)
    if result.returncode != 0:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(cmd)}")


def _write_launchers(engine_dir: Path, target: str, lib_name: str, freeze: bool) -> None:
    exec_name = runner_exec_name(target)
    if target == "windows":
        setup_bat = engine_dir / "setup-engine.bat"
        if freeze:
            setup_bat.write_text("@echo off\necho Prebuilt runner bundle: setup not required.\n", encoding="utf-8")
        else:
            setup_bat.write_text(
                "\n".join(
                    [
                        "@echo off",
                        "setlocal",
                        "set ROOT=%~dp0",
                        "set PYBIN=%CPYVN_PYTHON%",
                        "if \"%PYBIN%\"==\"\" set PYBIN=python",
                        "%PYBIN% --version >nul 2>&1",
                        "if errorlevel 1 set PYBIN=py -3",
                        "cd /d \"%ROOT%\"",
                        "%PYBIN% -m venv .venv",
                        "call .venv\\Scripts\\activate.bat",
                        "python -m pip install --upgrade pip",
                        "python -m pip install -r requirements.txt",
                        "python setup_cython.py build_ext --inplace",
                        "echo Engine setup complete.",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
        run_bat = engine_dir / "run-engine.bat"
        if freeze:
            run_bat.write_text(
                "\n".join(
                    [
                        "@echo off",
                        "setlocal",
                        "set ROOT=%~dp0",
                        f"set CPYVN_VNEF_VIDEO_LIB=%ROOT%runtime\\vnef\\{lib_name}",
                        f'set RUNNER=%ROOT%runner\\{exec_name}',
                        "if not exist \"%RUNNER%\" (",
                        "  echo Frozen runner missing: %RUNNER%",
                        "  exit /b 2",
                        ")",
                        "\"%RUNNER%\" %*",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
        else:
            run_bat.write_text(
                "\n".join(
                    [
                        "@echo off",
                        "setlocal",
                        "set ROOT=%~dp0",
                        "set PYBIN=%CPYVN_PYTHON%",
                        "if \"%PYBIN%\"==\"\" if exist \"%ROOT%.venv\\Scripts\\python.exe\" set PYBIN=%ROOT%.venv\\Scripts\\python.exe",
                        "if \"%PYBIN%\"==\"\" set PYBIN=python",
                        "%PYBIN% --version >nul 2>&1",
                        "if errorlevel 1 set PYBIN=py -3",
                        f"set CPYVN_VNEF_VIDEO_LIB=%ROOT%runtime\\vnef\\{lib_name}",
                        '%PYBIN% "%ROOT%main.py" %*',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
        return

    setup_sh = engine_dir / "setup-engine.sh"
    if freeze:
        setup_sh.write_text(
            "#!/usr/bin/env bash\nset -euo pipefail\necho \"Prebuilt runner bundle: setup not required.\"\n",
            encoding="utf-8",
        )
    else:
        setup_sh.write_text(
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    "set -euo pipefail",
                    'ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
                    'if [[ -n "${CPYVN_PYTHON:-}" ]]; then',
                    '  BOOT_PY="$CPYVN_PYTHON"',
                    "elif command -v python >/dev/null 2>&1; then",
                    '  BOOT_PY="python"',
                    "elif command -v python3 >/dev/null 2>&1; then",
                    '  BOOT_PY="python3"',
                    "else",
                    '  echo "python interpreter not found (set CPYVN_PYTHON)." >&2',
                    "  exit 127",
                    "fi",
                    'cd "$ROOT_DIR"',
                    '"$BOOT_PY" -m venv .venv',
                    'source "$ROOT_DIR/.venv/bin/activate"',
                    'python -m pip install --upgrade pip',
                    'python -m pip install -r "$ROOT_DIR/requirements.txt"',
                    'python "$ROOT_DIR/setup_cython.py" build_ext --inplace',
                    'echo "Engine setup complete."',
                ]
            )
            + "\n",
            encoding="utf-8",
        )
    setup_sh.chmod(0o755)

    run_sh = engine_dir / "run-engine.sh"
    if freeze:
        run_sh.write_text(
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    "set -euo pipefail",
                    'ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
                    f'export CPYVN_VNEF_VIDEO_LIB="$ROOT_DIR/runtime/vnef/{lib_name}"',
                    f'RUNNER="$ROOT_DIR/runner/{exec_name}"',
                    'if [[ ! -x "$RUNNER" ]]; then',
                    '  echo "Frozen runner missing: $RUNNER" >&2',
                    "  exit 2",
                    "fi",
                    '"$RUNNER" "$@"',
                ]
            )
            + "\n",
            encoding="utf-8",
        )
    else:
        run_sh.write_text(
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    "set -euo pipefail",
                    'ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
                    'if [[ -n "${CPYVN_PYTHON:-}" ]]; then',
                    '  PYBIN="$CPYVN_PYTHON"',
                    'elif [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then',
                    '  PYBIN="$ROOT_DIR/.venv/bin/python"',
                    "elif command -v python >/dev/null 2>&1; then",
                    '  PYBIN="python"',
                    "elif command -v python3 >/dev/null 2>&1; then",
                    '  PYBIN="python3"',
                    "else",
                    '  echo "python interpreter not found (set CPYVN_PYTHON)." >&2',
                    "  exit 127",
                    "fi",
                    f'export CPYVN_VNEF_VIDEO_LIB="$ROOT_DIR/runtime/vnef/{lib_name}"',
                    'if ! "$PYBIN" -c "import pygame" >/dev/null 2>&1; then',
                    '  echo "Missing runtime deps. Run: $ROOT_DIR/setup-engine.sh" >&2',
                    "  exit 2",
                    "fi",
                    '"$PYBIN" "$ROOT_DIR/main.py" "$@"',
                ]
            )
            + "\n",
            encoding="utf-8",
        )
    run_sh.chmod(0o755)


def _copy_engine_payload(engine_dir: Path) -> None:
    for rel in [
        "main.py",
        "vn",
        "requirements.txt",
        "requirements-video.txt",
        "requirements-wgpu.txt",
        "setup_cython.py",
        "LICENSE",
        "README.md",
    ]:
        src = REPO_ROOT / rel
        if src.exists():
            copy_any(src, engine_dir / rel)


def _run_freeze_runner(
    target: str,
    freeze_output_root: Path,
    freeze_name: str,
    freeze_clean: bool,
    freeze_skip_cython: bool,
) -> Path:
    if getattr(sys, "frozen", False):
        run_freeze_runner(
            target=target,
            output=str(freeze_output_root),
            name=freeze_name,
            clean=freeze_clean,
            no_build_cython=freeze_skip_cython,
        )
    else:
        cmd = [
            sys.executable,
            str(REPO_ROOT / "tools" / "freeze_runner.py"),
            "--target",
            target,
            "--output",
            str(freeze_output_root),
            "--name",
            freeze_name,
        ]
        if freeze_clean:
            cmd.append("--clean")
        if freeze_skip_cython:
            cmd.append("--no-build-cython")
        _run(cmd, REPO_ROOT)
    frozen_runner_dir = (freeze_output_root / target / freeze_name).resolve()
    if not frozen_runner_dir.exists():
        raise FileNotFoundError(f"Frozen runner directory not found: {frozen_runner_dir}")
    return frozen_runner_dir


def _build_one_target(
    target: str,
    output_root: Path,
    artifacts_root: Path,
    zip_output: bool,
    strict: bool,
    freeze: bool,
    freeze_name: str,
    frozen_runner_dir: Path | None,
) -> Path:
    bundle_name = f"cpyvn-engine-{target}"
    engine_dir = output_root / bundle_name
    ensure_clean_dir(engine_dir)
    if freeze:
        if frozen_runner_dir is None:
            raise RuntimeError("Frozen runner dir missing.")
        copy_any(frozen_runner_dir, engine_dir / "runner")
        for rel in ["LICENSE", "README.md"]:
            src = REPO_ROOT / rel
            if src.exists():
                copy_any(src, engine_dir / rel)
    else:
        _copy_engine_payload(engine_dir)

    lib_name = vnef_lib_name(target)
    vnef_artifact = find_vnef_artifact(target, artifacts_root)
    vnef_dst = engine_dir / "runtime" / "vnef" / lib_name
    if vnef_artifact is None:
        msg = f"[warn] missing vnef-video artifact for {target}: expected {lib_name}"
        if strict:
            raise FileNotFoundError(msg)
        print(msg)
    else:
        vnef_dst.parent.mkdir(parents=True, exist_ok=True)
        copy_any(vnef_artifact, vnef_dst)
        print(f"[ok] bundled vnef-video: {vnef_artifact}")

    _write_launchers(engine_dir, target, lib_name, freeze=freeze)
    write_json(
        engine_dir / "engine_manifest.json",
        {
            "name": "cpyvn-engine",
            "target": target,
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "runtime_mode": "frozen" if freeze else "source",
            "vnef_video": {
                "lib_name": lib_name,
                "bundled": vnef_dst.exists(),
                "path": str(vnef_dst.relative_to(engine_dir)),
            },
            "runner": {
                "name": freeze_name if freeze else "",
                "executable": str(Path("runner") / runner_exec_name(target)) if freeze else "",
            },
        },
    )

    if zip_output:
        zip_path = output_root / f"{bundle_name}.zip"
        zip_dir(engine_dir, zip_path)
        print(f"[ok] zip: {zip_path}")
    return engine_dir


def export_engine(
    *,
    target: str = "host",
    output: str = "dist/exports/engine",
    artifacts: str = "vnef-video/artifacts",
    zip_output: bool = False,
    strict: bool = False,
    freeze: bool = False,
    freeze_output: str = "dist/frozen",
    freeze_name: str = "cpyvn-runner",
    freeze_clean: bool = False,
    freeze_skip_cython: bool = False,
) -> List[Path]:
    target_arg = target.strip().lower()
    if target_arg == "host":
        target_arg = detect_target()

    output_root = (REPO_ROOT / output).resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    artifacts_root = (REPO_ROOT / artifacts).resolve()

    targets = resolve_targets(target_arg)
    if freeze:
        if len(targets) != 1:
            raise ValueError("--freeze supports a single target only. Use --target host or one OS target.")
        host = detect_target()
        if targets[0] != host:
            raise RuntimeError(f"Cannot --freeze target '{targets[0]}' on host '{host}'.")

    frozen_runner_dir = None
    if freeze:
        freeze_output_root = (REPO_ROOT / freeze_output).resolve()
        frozen_runner_dir = _run_freeze_runner(
            target=targets[0],
            freeze_output_root=freeze_output_root,
            freeze_name=str(freeze_name),
            freeze_clean=bool(freeze_clean),
            freeze_skip_cython=bool(freeze_skip_cython),
        )

    built = []
    for one_target in targets:
        built_dir = _build_one_target(
            target=one_target,
            output_root=output_root,
            artifacts_root=artifacts_root,
            zip_output=bool(zip_output),
            strict=bool(strict),
            freeze=bool(freeze),
            freeze_name=str(freeze_name),
            frozen_runner_dir=frozen_runner_dir,
        )
        built.append(built_dir)
        print(f"[ok] engine export: {built_dir}")

    print(f"[done] exported {len(built)} target(s) to {output_root}")
    return built


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Export cpyvn engine bundle(s) with platform vnef-video artifact.")
    parser.add_argument("--target", default="host", help="linux|windows|macos|all|host")
    parser.add_argument("--output", default="dist/exports/engine", help="Output directory")
    parser.add_argument("--artifacts", default="vnef-video/artifacts", help="vnef-video artifacts root")
    parser.add_argument("--zip", action="store_true", help="Also create zip archives")
    parser.add_argument("--strict", action="store_true", help="Fail if vnef artifact is missing")
    parser.add_argument("--freeze", action="store_true", help="Bundle pre-frozen runner (PyInstaller onedir)")
    parser.add_argument("--freeze-output", default="dist/frozen", help="Frozen runner output root")
    parser.add_argument("--freeze-name", default="cpyvn-runner", help="Frozen runner name")
    parser.add_argument("--freeze-clean", action="store_true", help="Pass --clean to freeze_runner")
    parser.add_argument("--freeze-skip-cython", action="store_true", help="Skip build_ext in freeze_runner")
    args = parser.parse_args(argv)
    export_engine(
        target=str(args.target),
        output=str(args.output),
        artifacts=str(args.artifacts),
        zip_output=bool(args.zip),
        strict=bool(args.strict),
        freeze=bool(args.freeze),
        freeze_output=str(args.freeze_output),
        freeze_name=str(args.freeze_name),
        freeze_clean=bool(args.freeze_clean),
        freeze_skip_cython=bool(args.freeze_skip_cython),
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(2)
