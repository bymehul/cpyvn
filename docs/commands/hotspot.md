# hotspot

Defines clickable screen regions that jump to labels.

## Syntax

```vn
hotspot add <name> <x> <y> <w> <h> -> <label>;
hotspot poly <name> <x1> <y1> <x2> <y2> <x3> <y3> ... -> <label>;
hotspot remove <name>;
hotspot clear;
hotspot debug on;
hotspot debug off;
```

## Notes

- Coordinates are absolute screen pixels.
- Polygon coordinates use the same world-space coordinate system as `hotspot add`.
- Last defined hotspot wins when regions overlap.
- Hotspots are active when no dialogue/choice is blocking input.
- `hotspot debug on` draws hotspot rectangles and labels so placement is easy.
- Hotspots are camera-aware: when you pan/zoom via `camera`, click detection still matches visuals.

## In-Engine Editor

- Press `F4` to open hotspot editor.
- `1/2/3` switch mode: `select`, `rect`, `poly`.
- `Rect` mode: click-drag to create a hotspot quickly.
- `Poly` mode: click points, press `Enter` to finalize.
- `Del` removes selected hotspot.
- `C` prints selected hotspot command snippet in terminal.
- `T` cycles selected hotspot target through available labels.
- Arrow keys move selected hotspot (`Shift` = bigger step).
- `+/-` or mouse wheel zoom camera while placing.

## Example

```vn
label map:
  scene image "map_day.png";
  camera 120 -40 1.30;
  hotspot debug on;
  hotspot add school 90 130 220 180 -> school_gate;
  hotspot poly river 420 220 610 190 710 300 650 420 460 430 370 320 -> river_bank;
  hotspot add home 760 360 240 200 -> home_entrance;
  narrator "Click a location.";
```
