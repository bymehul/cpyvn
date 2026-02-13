# add

**Syntax**
```vn
add rect <name> <color> <w> <h>;
add image <name> <path>;
add image <name> <path> size <w> <h>;
add image <name> <path> <x> <y>;
add image <name> <path> left|center|right [top|middle|bottom];
add image <name> <path> ... z <int>;
add image <name> <path> ... fade <seconds>;
add image <name> <path> ... float <amp> [speed];
```

**Description**
Adds a sprite to the scene. Use `rect` for placeholder art or `image` for files.
Positioning is optional. You can pass pixel coordinates or anchor keywords.
Anchors also work for `rect`.
For character sprites with expressions, use `show` instead.
For full effect details, see `docs/commands/effect.md`.

**Example**
```vn
add rect alice #ef233c 240 360;
add image alice "sprites/alice.png";
add image alice "sprites/alice.png" size 360 640;
add image alice "sprites/alice.png" right;
add image alice "sprites/alice.png" left top;
add image alice "sprites/alice.png" 120 420;
add image alice "sprites/alice.png" right z 5;
add image alice "sprites/alice.png" right fade 0.3;
add image alice "sprites/alice.png" right float 4 1.0;
```
