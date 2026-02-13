#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from export_common import (
    REPO_ROOT,
    copy_any,
    detect_target,
    ensure_clean_dir,
    normalize_target,
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


def _write_game_launchers(bundle_dir: Path, target: str, lib_name: str) -> None:
    if target == "windows":
        setup_bat = bundle_dir / "setup-game.bat"
        setup_bat.write_text(
            "\n".join(
                [
                    "@echo off",
                    "setlocal",
                    "set ROOT=%~dp0",
                    "call \"%ROOT%engine\\setup-engine.bat\"",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        play_bat = bundle_dir / "play.bat"
        play_bat.write_text(
            "\n".join(
                [
                    "@echo off",
                    "setlocal",
                    "set ROOT=%~dp0",
                    "set PYBIN=%CPYVN_PYTHON%",
                    "if \"%PYBIN%\"==\"\" if exist \"%ROOT%engine\\.venv\\Scripts\\python.exe\" set PYBIN=%ROOT%engine\\.venv\\Scripts\\python.exe",
                    "if \"%PYBIN%\"==\"\" set PYBIN=python",
                    "%PYBIN% --version >nul 2>&1",
                    "if errorlevel 1 set PYBIN=py -3",
                    f"set CPYVN_VNEF_VIDEO_LIB=%ROOT%engine\\runtime\\vnef\\{lib_name}",
                    "%PYBIN% -c \"import pygame\" >nul 2>&1",
                    "if errorlevel 1 (",
                    "  echo Missing runtime deps. Run setup-game.bat first.",
                    "  exit /b 2",
                    ")",
                    '%PYBIN% "%ROOT%engine\\main.py" --project "%ROOT%game" %*',
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        return

    setup_sh = bundle_dir / "setup-game.sh"
    setup_sh.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
                '"$ROOT_DIR/engine/setup-engine.sh"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    setup_sh.chmod(0o755)

    play_sh = bundle_dir / "play.sh"
    play_sh.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
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
                '  echo "Missing runtime deps. Run: $ROOT_DIR/setup-game.sh" >&2',
                "  exit 2",
                "fi",
                '"$PYBIN" "$ROOT_DIR/engine/main.py" --project "$ROOT_DIR/game" "$@"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    play_sh.chmod(0o755)


def main() -> None:
    parser = argparse.ArgumentParser(description="Export a game bundle using a pre-exported cpyvn engine bundle.")
    parser.add_argument("--project", required=True, help="Game project directory")
    parser.add_argument("--target", default="host", help="linux|windows|macos|host")
    parser.add_argument("--engine", default="", help="Path to engine export directory (cpyvn-engine-<target>)")
    parser.add_argument("--output", default="dist/exports/game", help="Output directory")
    parser.add_argument("--zip", action="store_true", help="Also create a zip archive")
    args = parser.parse_args()

    target_arg = args.target.strip().lower()
    if target_arg == "host":
        target_arg = detect_target()
    target = normalize_target(target_arg)

    project_dir = (REPO_ROOT / args.project).resolve()
    if not project_dir.exists():
        raise FileNotFoundError(f"Project directory not found: {project_dir}")

    if args.engine:
        engine_dir = (REPO_ROOT / args.engine).resolve()
    else:
        engine_dir = (REPO_ROOT / "dist" / "exports" / "engine" / f"cpyvn-engine-{target}").resolve()
    if not engine_dir.exists():
        raise FileNotFoundError(f"Engine export directory not found: {engine_dir}")

    output_root = (REPO_ROOT / args.output).resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    game_name = _project_name(project_dir)
    bundle_name = f"{game_name}-{target}"
    bundle_dir = output_root / bundle_name
    ensure_clean_dir(bundle_dir)

    copy_any(engine_dir, bundle_dir / "engine")
    copy_any(project_dir, bundle_dir / "game")

    lib_name = vnef_lib_name(target)
    _write_game_launchers(bundle_dir, target, lib_name)
    write_json(
        bundle_dir / "game_manifest.json",
        {
            "name": game_name,
            "target": target,
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "project_dir": "game",
            "engine_dir": "engine",
            "launchers": ["play.bat"] if target == "windows" else ["play.sh"],
        },
    )

    if args.zip:
        zip_path = output_root / f"{bundle_name}.zip"
        zip_dir(bundle_dir, zip_path)
        print(f"[ok] zip: {zip_path}")

    print(f"[ok] game export: {bundle_dir}")


if __name__ == "__main__":
    main()
