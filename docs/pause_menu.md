# Pause Menu

Press `Esc` in runtime to open the pause menu.

## Features

- Resume
- Save slots
- Load slots
- Preferences (`text_speed`, `show_perf`)
- Quit

Preferences are stored in:

- `saves/ui_prefs.json`

## Project Config

`project.json`:

```json
"ui": {
  "pause_menu_enabled": true,
  "pause_menu_file": "pause_menu.json",
  "pause_menu_slots": 9,
  "pause_menu_columns": 3
}
```

## Theme/Layout File

`pause_menu_file` points to a JSON file in the project root.

Example keys:

- `title`, `subtitle`
- `title_font_size`, `item_font_size`, `meta_font_size`
- `panel_width`
- `slot_rows`, `slot_cols`
- `colors` (RGBA arrays)
- `buttons` (`label` + `action`)
- `save_slots` (custom slot ids)

Actions:

- `resume`
- `open_save`
- `open_load`
- `open_prefs`
- `quick_save`
- `quick_load`
- `quit`
