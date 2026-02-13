# hud

Persistent HUD (Heads-Up Display) buttons that remain visible across scene changes.
Buttons can display text, an icon (image), or both.

## Syntax

```vn
hud add <name> text "<label>" <x> <y> <w> <h> -> <target>;
hud add <name> icon "<image_path>" <x> <y> <w> <h> -> <target>;
hud add <name> both "<image_path>" "<label>" <x> <y> <w> <h> -> <target>;
hud remove <name>;
hud clear;
```

## Notes

- Coordinates are absolute screen pixels.
- HUD buttons **persist across scene changes** — they are not cleared by `scene`, `call`, or `cache clear`.
- They are only removed by `hud remove <name>` or `hud clear`.
- When clicked, the button jumps to the target label (same as hotspot).
- HUD buttons are checked for clicks **before** hotspots, so they take priority on overlap.
- Hover state highlights the button with a lighter background.

## Difference from Hotspots

| Feature | `hotspot` | `hud` |
|---|---|---|
| Persists across scenes | No | **Yes** |
| Cleared by `cache clear runtime` | Yes | **No** |
| Visual | Invisible (debug outline) | Rendered button |
| Camera-aware | Yes | No (screen-fixed) |
| Styles | rect / poly | text / icon / both |

## In-Engine Editor

- Press `F7` to open HUD editor.
- `1` / `2`: switch mode — `select`, `rect`.
- `Rect` mode: click-drag to create a new button.
- `Select` mode: click to select, drag to move.
- `Del` removes selected button.
- `T` cycles selected button target through available labels.
- Arrow keys move selected button (`Shift` = 10px step).
- Edits auto-save into the `# cpyvn-editor begin/end` block in the script.

## Example

```vn
label start:
    scene image "background.png" fade 0.5;
    hud add menu_btn text "Menu" 10 10 100 32 -> main_menu;
    hud add inv_btn icon "icons/bag.png" 50 80 48 48 -> inventory;
    hud add help_btn both "icons/help.png" "Help" 10 130 120 32 -> help_screen;
    narrator "The HUD buttons are now visible.";

label main_menu:
    hud clear;
    narrator "HUD cleared.";
```
