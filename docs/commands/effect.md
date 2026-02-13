# effect

There is no standalone `effect` command yet. Effects are applied through existing
commands and text tags.

For timed sprite transforms, use `animate` (see `docs/commands/animate.md`).

**Float Effect**
- Syntax: `float <amp> [speed]`
- `amp`: movement amount in pixels.
- `speed`: cycles per second (optional, default `1.0`).

**Supported Targets**
- `scene image ... float <amp> [speed]`
- `add image ... float <amp> [speed]`
- `show <character> ... float <amp> [speed]`
- `character ... float <amp> [speed]` (default for that character)

**Text Effect**
- Tag syntax: `[shake]text[/shake]`
- Works inside dialogue text.

**Examples**
```vn
scene image "bg/river.png" float 6 0.4;
add image fog "fx/fog.png" center float 3 0.6;
show chars.alice happy right float 4 1.2;

chars.narrator "This is [shake]shaky[/shake].";
```
