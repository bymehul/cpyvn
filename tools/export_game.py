#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from export_common import (
    REPO_ROOT,
    copy_any,
    detect_target,
    ensure_clean_dir,
    normalize_target,
    runner_exec_name,
    vnef_lib_name,
    write_json,
    zip_dir,
)


def _project_name(project_dir: Path) -> str:
    project_json = project_dir / "project.json"
    if not project_json.exists():
        return project_dir.name
    try:
        raw = json.loads(project_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return project_dir.name
    if isinstance(raw, dict):
        name = str(raw.get("name", "")).strip()
        if name:
            return name
    return project_dir.name


def _engine_runner_relpath(engine_dir: Path, target: str) -> Path:
    manifest = engine_dir / "engine_manifest.json"
    default_rel = Path("runner") / runner_exec_name(target)
    if not manifest.exists():
        return default_rel
    try:
        raw = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default_rel
    if not isinstance(raw, dict):
        return default_rel
    runner = raw.get("runner")
    if not isinstance(runner, dict):
        return default_rel
    rel = str(runner.get("executable", "")).strip()
    if not rel:
        return default_rel
    return Path(rel)


def _write_game_launchers(bundle_dir: Path, target: str, lib_name: str, engine_has_frozen: bool, runner_relpath: Path) -> None:
    exec_name = str(runner_relpath).replace("/", "\\") if target == "windows" else str(runner_relpath)
    if target == "windows":
        play_bat = bundle_dir / "play.bat"
        play_bat.write_text(
            "\n".join(
                [
                    "@echo off",
                    "setlocal",
                    "set ROOT=%~dp0",
                    f"set RUNNER=%ROOT%engine\\{exec_name}",
                    "if exist \"%RUNNER%\" (",
                    f"  set CPYVN_VNEF_VIDEO_LIB=%ROOT%engine\\runtime\\vnef\\{lib_name}",
                    "  \"%RUNNER%\" --project \"%ROOT%game\" %*",
                    "  goto :eof",
                    ")",
                    "set PYBIN=%CPYVN_PYTHON%",
                    "if \"%PYBIN%\"==\"\" if exist \"%ROOT%engine\\.venv\\Scripts\\python.exe\" set PYBIN=%ROOT%engine\\.venv\\Scripts\\python.exe",
                    "if \"%PYBIN%\"==\"\" set PYBIN=python",
                    "%PYBIN% --version >nul 2>&1",
                    "if errorlevel 1 set PYBIN=py -3",
                    f"set CPYVN_VNEF_VIDEO_LIB=%ROOT%engine\\runtime\\vnef\\{lib_name}",
                    "%PYBIN% -c \"import pygame\" >nul 2>&1",
                    "if errorlevel 1 (",
                    "  echo Missing runtime deps. Run engine\\setup-engine.bat first.",
                    "  exit /b 2",
                    ")",
                    '%PYBIN% "%ROOT%engine\\main.py" --project "%ROOT%game" %*',
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        return

    play_sh = bundle_dir / "play.sh"
    play_sh.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
                f'RUNNER="$ROOT_DIR/engine/{exec_name}"',
                'if [[ -x "$RUNNER" ]]; then',
                f'  export CPYVN_VNEF_VIDEO_LIB="$ROOT_DIR/engine/runtime/vnef/{lib_name}"',
                '  "$RUNNER" --project "$ROOT_DIR/game" "$@"',
                "  exit $?",
                "fi",
                'if [[ -n "${CPYVN_PYTHON:-}" ]]; then',
                '  PYBIN="$CPYVN_PYTHON"',
                'elif [[ -x "$ROOT_DIR/engine/.venv/bin/python" ]]; then',
                '  PYBIN="$ROOT_DIR/engine/.venv/bin/python"',
                "elif command -v python >/dev/null 2>&1; then",
                '  PYBIN="python"',
                "elif command -v python3 >/dev/null 2>&1; then",
                '  PYBIN="python3"',
                "else",
                '  echo "python interpreter not found (set CPYVN_PYTHON)." >&2',
                "  exit 127",
                "fi",
                f'export CPYVN_VNEF_VIDEO_LIB="$ROOT_DIR/engine/runtime/vnef/{lib_name}"',
                'if ! "$PYBIN" -c "import pygame" >/dev/null 2>&1; then',
                '  echo "Missing runtime deps. Run: $ROOT_DIR/engine/setup-engine.sh" >&2',
                "  exit 2",
                "fi",
                '"$PYBIN" "$ROOT_DIR/engine/main.py" --project "$ROOT_DIR/game" "$@"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    play_sh.chmod(0o755)


def export_game(
    *,
    project: str,
    target: str = "host",
    engine: str = "",
    output: str = "dist/exports/game",
    zip_output: bool = False,
) -> Path:
    target_arg = target.strip().lower()
    if target_arg == "host":
        target_arg = detect_target()
    resolved_target = normalize_target(target_arg)

    project_dir = (REPO_ROOT / project).resolve()
    if not project_dir.exists():
        raise FileNotFoundError(f"Project directory not found: {project_dir}")

    if engine:
        engine_dir = (REPO_ROOT / engine).resolve()
    else:
        engine_dir = (REPO_ROOT / "dist" / "exports" / "engine" / f"cpyvn-engine-{resolved_target}").resolve()
    if not engine_dir.exists():
        raise FileNotFoundError(f"Engine export directory not found: {engine_dir}")

    output_root = (REPO_ROOT / output).resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    game_name = _project_name(project_dir)
    bundle_name = f"{game_name}-{resolved_target}"
    bundle_dir = output_root / bundle_name
    ensure_clean_dir(bundle_dir)

    copy_any(engine_dir, bundle_dir / "engine")
    copy_any(project_dir, bundle_dir / "game")

    lib_name = vnef_lib_name(resolved_target)
    runner_relpath = _engine_runner_relpath(bundle_dir / "engine", resolved_target)
    engine_has_frozen = (bundle_dir / "engine" / runner_relpath).exists()
    _write_game_launchers(
        bundle_dir,
        resolved_target,
        lib_name,
        engine_has_frozen=engine_has_frozen,
        runner_relpath=runner_relpath,
    )
    write_json(
        bundle_dir / "game_manifest.json",
        {
            "name": game_name,
            "target": resolved_target,
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "project_dir": "game",
            "engine_dir": "engine",
            "runtime_mode": "frozen" if engine_has_frozen else "source",
            "launchers": ["play.bat"] if resolved_target == "windows" else ["play.sh"],
        },
    )

    if zip_output:
        zip_path = output_root / f"{bundle_name}.zip"
        zip_dir(bundle_dir, zip_path)
        print(f"[ok] zip: {zip_path}")

    print(f"[ok] game export: {bundle_dir}")
    return bundle_dir


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Export a game bundle using a pre-exported cpyvn engine bundle.")
    parser.add_argument("--project", required=True, help="Game project directory")
    parser.add_argument("--target", default="host", help="linux|windows|macos|host")
    parser.add_argument("--engine", default="", help="Path to engine export directory (cpyvn-engine-<target>)")
    parser.add_argument("--output", default="dist/exports/game", help="Output directory")
    parser.add_argument("--zip", action="store_true", help="Also create a zip archive")
    args = parser.parse_args(argv)
    export_game(
        project=str(args.project),
        target=str(args.target),
        engine=str(args.engine),
        output=str(args.output),
        zip_output=bool(args.zip),
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(2)
