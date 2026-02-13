# character

**Syntax**
```vn
character <id> {
  name "Display Name";
  color #ff6b6b;
  sprite default "alice/neutral.png";
  sprite happy "alice/happy.png";
  voice "alice";
  float 4 1.0;
};
```

**Description**
Defines a character profile used by dialogue and `show`. The `id` is the name used
in script (speaker id and show command).

**Fields**
- `name` (optional) - display name shown in the nameplate.
- `color` (optional) - nameplate text/border color.
- `sprite` (optional, repeatable) - maps expression to a sprite path.
- `voice` (optional) - used to prefix relative `voice` paths (e.g., `voice alice "line.wav"` -> `alice/line.wav`).
- `pos` (optional) - default pixel position (`x y`) for `show` or auto-show.
- `anchor` (optional) - default anchor (left/center/right + top/middle/bottom).
- `z` (optional) - default render order for the character sprite.
- `float` (optional) - adds a gentle vertical bob (`float <amp> [speed]`).

For full effect details, see `docs/commands/effect.md`.

**Use In Script**
```vn
# characters.vn
character alice {
  name "Alice";
  color #ff6b6b;
  sprite default "alice/neutral.png";
  sprite happy "alice/happy.png";
  anchor right bottom;
  float 3 1.0;
};
```

```vn
# script.vn
include "characters.vn" as chars;

label start:
  chars.narrator "Characters are used via include alias.";
  chars.alice "I auto-show because I have a default sprite.";
  show chars.alice happy right;
  show chars.alice happy right float 5 1.4;
  off chars.alice fade 0.25;
```

When a character file is included with an alias, refer to characters as
`alias.id` (example: `chars.alice`).

**Example**
```vn
character alice {
  name "Alice";
  color #ff6b6b;
  sprite default "alice/neutral.png";
  sprite happy "alice/happy.png";
  pos 320 520;
  anchor right bottom;
  z 5;
  float 4 1.0;
};
```
