# map

The `map` command creates interactive exploration screens.

## Syntax

```vn
map show "<background_image>";
map poi "<label>" <x> <y> -> <target_label>;
map poi "<label>" <x1> <y1> <x2> <y2> <x3> <y3> ... -> <target_label>;
map hide;
```

## Quick Start

```vn
label explore:
    map show "world_map.png";
    map poi "Town" 400 300 -> town_gate;
    map poi "Park" 900 260 1120 260 1160 430 980 470 -> park_entry;
    map poi "Forest" 1200 800 -> woods;
    map poi "Back" 80 80 -> ::start;
```

## Behavior

- `map show` enters blocking map mode.
- `map poi` defines clickable destinations.
  - Point POI: single coordinate pair.
  - Polygon POI: 3+ coordinate pairs forming area.
- Clicking a POI:
  - jumps to target label
  - automatically hides map
  - continues script execution from target label
- `map hide` exits map mode manually.

## Important Ordering Rule

After `map show`, place POIs immediately:

```vn
map show "world_map.png";
map poi "A" 100 100 -> a_label;
map poi "B" 300 200 -> b_label;
```

POIs are collected right after `map show` before runtime blocks in map mode.
If POIs are missing, there is nothing clickable.

## Label Target Rules

- `end` -> local/current namespace label
- `alias.end` -> explicit include namespace
- `::end` -> global/root label

## In-Engine Map Editor (Ctrl+M)

- Open map in script (`map show ...`), then press `Ctrl+M`.
- `Add Map POI`: click once to add a point POI.
- `Add Map Poly`: left-click multiple vertices.
- Save polygon: press `Enter` or right-click.
- Auto-sync writes generated snippets into `# cpyvn-editor begin/end` block.

Note: lines in that auto block are comments (`# ...`), useful as reference.  
Executable POI lines must be normal `map poi ...;` statements.

## Troubleshooting

- Map visible but no clickable area:
  - POI lines are commented out.
  - POIs are not directly after `map show`.
  - Coordinates are outside the visible map area.
- Wrong jump target:
  - Use `alias.label` for included scripts.
  - Use `::label` only for global/root labels.
