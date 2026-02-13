# Title Menu

`cpyvn` now supports a startup title menu before script execution.

## Enable

In `project.json`:

```json
"ui": {
  "title_menu_enabled": true,
  "title_menu_file": "title_menu.json"
}
```

## Theme File

`title_menu_file` points to a JSON file in project root.

Main keys:

- `title`, `subtitle`
- `title_font_size`, `subtitle_font_size`, `item_font_size`, `meta_font_size`
- `background`: `kind` (`image`/`color`), `value`, `asset_kind`, `overlay_alpha`
- `layout`: `menu_x`, `menu_y`, `menu_width`, `button_height`, `button_gap`
- `colors`
- `buttons` (`label` + `action`)
- `logos`: list of image blocks
  - each logo: `path`, `asset_kind`, `x`, `y`, optional `w`, `h`, `alpha`, `anchor`
- `load_rows`, `load_cols`

Actions:

- `new_game`
- `continue`
- `open_load`
- `open_prefs`
- `quit`

## Notes

- `Continue` auto-disables if no quicksave/slot exists.
- Load view reads slot metadata from save files.
- Preferences share `saves/ui_prefs.json` with pause menu.
