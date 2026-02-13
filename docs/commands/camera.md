# camera

Controls background camera pan/zoom for map-style scenes.

## Syntax

```vn
camera <pan_x> <pan_y> <zoom>;
camera reset;
```

## Notes

- `pan_x` / `pan_y` are world-space pixel offsets.
- `zoom` must be greater than `0`.
- Hotspots are transformed with camera automatically, so clicks stay accurate.

## Example

```vn
label map:
  scene image "city_map.png";
  camera 180 -60 1.4;
  hotspot debug on;
  hotspot add park 150 200 220 180 -> park_scene;
```
