# Editor Tools

cpyvn has four built-in dev tools:
- `F3` Inspector (sprite placement)
- `F4` Hotspot Editor (map/hotspot authoring)
- `F6` Script Editor (in-engine text editing)
- `F7` HUD Editor (persistent button placement)
- `Ctrl+M` Map Overlay Editor (map POI authoring while map is active)

These are runtime debug tools for rapid iteration.
When any editor mode is open (`F3`/`F4`/`F6`/`F7`), the perf HUD is hidden to reduce visual clutter.

## Global Shortcuts

- `F3`: Toggle inspector
- `F4`: Toggle hotspot editor
- `F5`: Quicksave
- `F6`: Toggle script editor
- `F7`: Toggle HUD editor
- `F9`: Quickload
- `Ctrl+M`: Toggle map overlay editor (only when a map is currently shown)
- `Esc`: Close active editor mode (or quit if no editor mode is active)

## Inspector (`F3`)

Use it to position sprites and inspect z-order quickly.

- Click/touch a sprite: select it
- Click/touch + drag: move selected sprite
- Drag corner handles: resize selected sprite
- Hold `Shift` while resizing: lock aspect ratio
- Mouse wheel on selected sprite: quick scale
- Arrow keys: nudge selected sprite by 1px
- `Shift + Arrow`: nudge by 10px
- `[` / `]`: decrease/increase selected sprite `z`
- `C`: print selected sprite script snippet
- `A`: toggle Placement Mode panel

### Placement Mode (`F3` + `A`)

- Shows a sprite list from `assets/sprites` (recursive)
- Select an entry with mouse or `Up/Down`
- `Enter` or `Add`: place image sprite into scene
- `Refresh`: rescan sprite files
- `Close`: hide panel

Notes:
- Added sprites are inserted as `add image` snippets in the managed auto block.
- Resized image sprites emit `size <w> <h>` in snippets.

## Hotspot Editor (`F4`)

Use it to create and edit map hotspots with camera pan/zoom support.

### Modes

- `1`: Select mode
- `2`: Rect mode
- `3`: Poly mode
- `Tab`: Cycle mode

### Actions

- Left click (Select): select hotspot
- Left drag (Rect): draw rectangle hotspot
- Left click (Poly): add polygon point
- Right click (Poly): remove last polygon point
- `Enter` (Poly): finalize polygon
- `Del`/`Backspace`: delete selected hotspot
- `T`: cycle selected hotspot target label
- `C`: print selected hotspot snippet
- `P`: print all hotspot snippets

### Camera Controls

- Mouse wheel: zoom in/out
- `+` / `-`: zoom in/out
- Arrow keys: pan camera (when no hotspot selected)
- Arrow keys: move selected hotspot (when selected)
- `Shift + Arrow`: move hotspot by larger step
- `R`: camera reset

## Map Overlay Editor (`Ctrl+M`)

Use it to author map POIs directly on the active map view.

- Works only while `map show ...` is active.
- Draw point or polygon POIs visually.
- `Enter`: save/finalize current POI.
- Saved POIs sync into the active script auto block:
  - `# cpyvn-editor begin`
  - `# cpyvn-editor end`
- The runtime keeps POI overlays clickable/highlighted for immediate test.

For DSL syntax details, see `docs/commands/map.md`.

## Script Editor (`F6`)

Use it to edit `.vn` files live in-engine.

### Core

- `Ctrl+S`: save current file
- `Ctrl+R`: save + reload runtime from current file
- `Esc`: close script editor

### Navigation/Edit

- Arrow keys: cursor move
- `Home` / `End`: line start/end
- `PageUp` / `PageDown`: jump by viewport
- `Backspace` / `Delete`: delete
- `Enter`: newline
- `Tab`: inserts 2 spaces
- Mouse click: place cursor
- Mouse wheel: scroll text pane

### Multi-file

- Left panel lists all `.vn` files in project
- Click file in panel: open file
- `Ctrl+Up` / `Ctrl+Down`: previous/next file
- `Ctrl+E`: jump to currently running script file
- `Ctrl+D`: duplicate current line
- Wheel on file panel: scroll file list

## Auto Sync Block

Inspector + hotspot/camera edits can auto-write a managed block into the running script:

- `# cpyvn-editor begin`
- `# cpyvn-editor end`

Lines are written as comments for safe review and manual copy into real script flow.

## HUD Editor (`F7`)

Use it to create and position persistent HUD buttons (text/icon/both).

### Modes

- `1`: Select mode (click to select, drag to move)
- `2`: Rect mode (drag to create new button)
- `Tab`: Cycle mode

### Actions

- Left click (Select): select button
- Left drag (Select): move selected button
- Left drag (Rect): draw new button area
- `Del`/`Backspace`: delete selected button
- `T`: cycle selected button target label
- Arrow keys: nudge selected button by 1px
- `Shift + Arrow`: nudge by 10px

### Notes

- New buttons default to `text` style with placeholder text.
- Edits auto-write into the `# cpyvn-editor begin/end` block.
- HUD buttons persist across scene changes (unlike hotspots).
