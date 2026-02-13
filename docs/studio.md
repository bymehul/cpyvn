# Studio GUI

`cpyvn` includes a lightweight desktop GUI for two tasks:

- Create a new game project (with window size/FPS options)
- Run engine/game export workflows

## Run

```bash
python tools/studio/main.py
```

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
- Uses the selected target (`host|linux|windows|macos` for game, plus `all` for engine).
- Logs stream in the GUI log panel.

## Notes

- `Export Game` does not allow `target=all` by design.
- After export, use generated setup scripts:
  - Linux/macOS: `setup-engine.sh` / `setup-game.sh`
  - Windows: `setup-engine.bat` / `setup-game.bat`
