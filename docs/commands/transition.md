# transitions

Transition behavior is handled by command parameters and `blend`.

## Current status

- `blur` transition is currently buggy and may look inconsistent.

## Commands that support transitions

- `scene ... fade <seconds>;`
- `show ... fade <seconds>;`
- `off ... fade <seconds>;`
- `blend <style> <seconds>;`

There is **no standalone `transition` command**.

`scene`, `show`, and `off` support the same style list as `blend`:

- `fade`
- `wipe`
- `slide`
- `dissolve`
- `zoom`
- `blur`
- `flash`
- `shake`
- `none`

## Blend styles

- `fade` - black in/out blend.
- `wipe` - left-to-right reveal.
- `slide` - previous frame slides out while current slides in.
- `dissolve` - tile-random reveal from previous to current frame.
- `zoom` - previous frame zooms and fades over current frame.
- `blur` - blurred transition (CPU by default, optional `wgpu` backend).
- `flash` - fast white flash.
- `shake` - screen shake burst.
- `none` - disables blend effect.

**Examples**
```vn
scene image "bg/park.png" fade 0.6;
scene image "bg/night.png" wipe 0.7;
show alice happy right fade 0.3;
show alice happy right dissolve 0.4;
off alice slide 0.4;

blend fade 0.8;
blend wipe 0.7;
blend dissolve 0.8;
blend zoom 0.7;
blend blur 0.7;
blend flash 0.2;
blend shake 0.35;
blend none 0.1;
```
