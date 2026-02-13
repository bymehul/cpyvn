#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

from export_common import (
    REPO_ROOT,
    copy_any,
    ensure_clean_dir,
    find_vnef_artifact,
    resolve_targets,
    vnef_lib_name,
    write_json,
    zip_dir,
)


def _write_launchers(engine_dir: Path, target: str, lib_name: str) -> None:
    if target == "windows":
        setup_bat = engine_dir / "setup-engine.bat"
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


def _build_one_target(target: str, output_root: Path, artifacts_root: Path, zip_output: bool, strict: bool) -> Path:
    bundle_name = f"cpyvn-engine-{target}"
    engine_dir = output_root / bundle_name
    ensure_clean_dir(engine_dir)
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

    _write_launchers(engine_dir, target, lib_name)
    write_json(
        engine_dir / "engine_manifest.json",
        {
            "name": "cpyvn-engine",
            "target": target,
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "vnef_video": {
                "lib_name": lib_name,
                "bundled": vnef_dst.exists(),
                "path": str(vnef_dst.relative_to(engine_dir)),
            },
        },
    )

    if zip_output:
        zip_path = output_root / f"{bundle_name}.zip"
        zip_dir(engine_dir, zip_path)
        print(f"[ok] zip: {zip_path}")
    return engine_dir


def main() -> None:
    parser = argparse.ArgumentParser(description="Export cpyvn engine bundle(s) with platform vnef-video artifact.")
    parser.add_argument("--target", default="host", help="linux|windows|macos|all|host")
    parser.add_argument("--output", default="dist/exports/engine", help="Output directory")
    parser.add_argument("--artifacts", default="vnef-video/artifacts", help="vnef-video artifacts root")
    parser.add_argument("--zip", action="store_true", help="Also create zip archives")
    parser.add_argument("--strict", action="store_true", help="Fail if vnef artifact is missing")
    args = parser.parse_args()

    target_arg = args.target.strip().lower()
    if target_arg == "host":
        from export_common import detect_target

        target_arg = detect_target()

    output_root = (REPO_ROOT / args.output).resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    artifacts_root = (REPO_ROOT / args.artifacts).resolve()

    targets = resolve_targets(target_arg)
    built = []
    for target in targets:
        built_dir = _build_one_target(
            target=target,
            output_root=output_root,
            artifacts_root=artifacts_root,
            zip_output=bool(args.zip),
            strict=bool(args.strict),
        )
        built.append(built_dir)
        print(f"[ok] engine export: {built_dir}")

    print(f"[done] exported {len(built)} target(s) to {output_root}")


if __name__ == "__main__":
    main()
