# Studio GUI

`cpyvn` includes a lightweight desktop GUI for two tasks:

- Create a new game project (with window size/FPS options)
- Run/export workflows for dev and player builds

## Run

```bash
python tools/studio/main.py
```

## Build Standalone Studio (No Python Required For Dev Machine)

Build on each target OS:

```bash
python -m pip install pyinstaller
python tools/freeze_studio.py --target host --clean --zip
```

Output example:

- `dist/studio/linux/cpyvn-studio/`
- `dist/studio/cpyvn-studio-linux.zip`

The frozen app can:

- create projects
- run dev game (`Run (Dev)`)
- export engine/game bundles

Current limitation:

- `Freeze runner (PyInstaller)` is disabled inside frozen Studio.
- Use source Studio (`python tools/studio/main.py`) for freeze-runner player exports.
- For cross-OS CI engine artifacts, use `.github/workflows/export-engine-matrix.yml`.

## New Game tab

1. Select parent folder.
2. Enter game name.
3. Set width/height/FPS.
4. Click **Create Project**.

Generated files include:

- `project.json`
- `script.cvn`
- `prefetch.json`
- `title_menu.json`
- `pause_menu.json`
- assets folders + `.gitkeep` files

## Export tab

- **Export Engine** wraps `tools/export_engine.py`.
- **Export Game** wraps `tools/export_game.py`.
- **One-Click Export**: auto-resolves paths from your project location, builds engine if missing, then exports game.
- **Run (Dev)** runs current project directly from source.
- **Run (Exported)** runs `play.sh` / `play.bat` from exported bundle.
- **Stop** terminates current run/export process.
- **Freeze runner (PyInstaller)** creates player-ready no-Python runtime in engine export.
- Uses the selected target (`host|linux|windows|macos` for game, plus `all` for engine).
- Logs stream in the GUI log panel.
- In frozen Studio builds, export/run tasks are executed through internal Studio task mode (`--studio-task`).

## Notes

- `Export Game` does not allow `target=all` by design.
- For frozen exports, `play.*` can run directly.
- For source runtime exports, run engine setup first:
  - Linux/macOS: `engine/setup-engine.sh`
  - Windows: `engine/setup-engine.bat`
