# Export

cpyvn supports two packaging steps:

1. **Engine export**: package the runtime once per target OS.
2. **Game export**: package a specific game using one engine export.

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

Useful flags:

- `--target linux|windows|macos|all|host`
- `--artifacts vnef-video/artifacts`
- `--output dist/exports/engine`
- `--strict` (fail if a target lib is missing)
- `--zip`

Output example:

```text
dist/exports/engine/
  cpyvn-engine-linux/
  cpyvn-engine-macos/
  cpyvn-engine-windows/
```

Each engine bundle contains:

- `main.py`
- `vn/`
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
  setup-game.sh
  play.sh
  game_manifest.json
```

## Linux quick test

```bash
# 1) export
python tools/export_engine.py --target linux --zip
python tools/export_game.py --project games/demo --target linux --zip

# 2) setup runtime once
cd dist/exports/game/demo-linux
./setup-game.sh

# 3) run game
./play.sh
```

If you manage Python yourself, set:

```bash
export CPYVN_PYTHON=/path/to/python3
./play.sh
```

## Notes

- Export scripts currently generate portable bundles with launchers.
- Launchers set `CPYVN_VNEF_VIDEO_LIB` to bundled native lib automatically.
- To ship **no-Python-visible** builds, add a final executable packaging step
  (PyInstaller/Nuitka) per platform in CI, then drop that runner into engine export.
