# animate

**Syntax**
```vn
animate <sprite_name> move <x> <y> <seconds> [linear|in|out|inout];
animate <sprite_name> size <w> <h> <seconds> [linear|in|out|inout];
animate <sprite_name> alpha <0..255> <seconds> [linear|in|out|inout];
animate stop <sprite_name>;
```

**Description**
Animates an existing sprite over time.

- `move`: animates top-left position.
- `size`: animates width/height.
- `alpha`: animates transparency (`0` = invisible, `255` = fully visible).
- `ease` is optional. Default is `linear`.

`animate stop <sprite_name>;` clears all active animation tracks on that sprite.

**Important**
- Target must already exist (`add ...` / `show ...` first).
- Name is the sprite key, for example:
  - `add image card ...` -> `animate card ...`
  - `show chars.alice ...` -> `animate chars.alice ...`
- Multiple tracks can run together on one sprite (e.g. move + alpha).
- New animation on same track replaces old one for that track.

**Example**
```vn
add image card "card.png" 200 220 z 3;
animate card move 560 220 0.8 inout;
animate card size 420 620 0.6 out;
animate card alpha 180 0.4 in;
animate stop card;
```

**Character example**
```vn
show chars.alice happy right;
animate chars.alice move 780 180 0.5 out;
animate chars.alice alpha 210 0.35 in;
```
