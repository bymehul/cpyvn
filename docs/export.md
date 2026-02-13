# Export

cpyvn supports two packaging steps:

1. **Engine export**: package the runtime once per target OS.
2. **Game export**: package a specific game using one engine export.

For a standalone developer app (no system Python), see `docs/studio.md` and `tools/freeze_studio.py`.

`vnef-video` native library is bundled per platform in engine export.

## 1) Build/collect `vnef-video` artifacts

Expected artifact names:

- Linux: `libvnef_video.so`
- macOS: `libvnef_video.dylib`
- Windows: `vnef_video.dll`

Recommended layout:

```text
vnef-video/artifacts/
  linux/libvnef_video.so
  macos/libvnef_video.dylib
  windows/vnef_video.dll
```

Engine exporter also checks local dev build fallback:

- `vnef-video/build/...`

## 2) Export engine bundle(s)

```bash
python tools/export_engine.py --target all --zip
```

For a **Python-free player runtime**, freeze runner on host target:

```bash
python tools/export_engine.py --target host --freeze --zip
```

Requires `pyinstaller` on the build machine:

```bash
python -m pip install pyinstaller
```

Useful flags:

- `--target linux|windows|macos|all|host`
- `--artifacts vnef-video/artifacts`
- `--output dist/exports/engine`
- `--strict` (fail if a target lib is missing)
- `--zip`
- `--freeze` (embed PyInstaller onedir runner; single target only)
- `--freeze-skip-cython` (skip `setup_cython.py build_ext` before freeze)
- `--freeze-output dist/frozen`
- `--freeze-name cpyvn-runner`

Output example:

```text
dist/exports/engine/
  cpyvn-engine-linux/
  cpyvn-engine-macos/
  cpyvn-engine-windows/
```

Each engine bundle contains:

- source runtime (`main.py`, `vn/`) **or** frozen runner (`runner/`)
- `runtime/vnef/<platform-lib>`
- setup script (`setup-engine.sh` / `setup-engine.bat`)
- launcher (`run-engine.sh` / `run-engine.bat`)
- `engine_manifest.json`

## 3) Export a game bundle

```bash
python tools/export_game.py --project games/demo --target host --zip
```

Useful flags:

- `--project <game-dir>` (required)
- `--target linux|windows|macos|host`
- `--engine <engine-export-dir>` (optional override)
- `--output dist/exports/game`
- `--zip`

Output example:

```text
dist/exports/game/demo-linux/
  engine/
  game/
  play.sh
  game_manifest.json
```

## Linux quick test

```bash
# 1) export
python tools/export_engine.py --target linux --freeze --zip
python tools/export_game.py --project games/demo --target linux --zip

# 2) run game
cd dist/exports/game/demo-linux
./play.sh
```

If you exported **without** `--freeze`, setup engine first:

```bash
cd dist/exports/game/demo-linux
./engine/setup-engine.sh

# 3) run game
./play.sh
```

If you manage Python yourself, set:

```bash
export CPYVN_PYTHON=/path/to/python3
./play.sh
```

## Notes

- With `--freeze`, player package does not need Python installation.
- Launchers set `CPYVN_VNEF_VIDEO_LIB` to bundled native lib automatically.
- Freeze target must match host OS (build each OS on that OS/CI runner).

## GitHub Actions (Cross-OS Artifacts)

If you only develop on Linux but need Windows/macOS engine exports too, run the
matrix workflow:

- `.github/workflows/export-engine-matrix.yml`

It runs on Linux, Windows, and macOS GitHub runners and uploads
`cpyvn-engine-*` artifacts for each OS.
The workflow also builds `vnef-video` native libs on each OS before export.
It also uploads one combined archive: `cpyvn-engines-all`.

Trigger it from GitHub:

1. Open **Actions**.
2. Select **Export Engine Matrix**.
3. Click **Run workflow**.

It also runs automatically on pushes to `main` when engine/runtime-related files
change.

Note:

- Workflow artifacts are temporary; publish zips to a GitHub Release for long-term distribution.
