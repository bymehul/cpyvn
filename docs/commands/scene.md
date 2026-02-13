# scene

**Syntax**
```vn
scene color <hex>;
scene image <path>;
scene image <path> <transition> <seconds>;
scene image <path> float <amp> [speed];
scene image <path> <transition> <seconds> float <amp> [speed];

scene color <hex> {
    ...
};
```

**Description**
Sets the background. A scene block runs the contained commands in order.
Optional `<transition> <seconds>` animates from the previous background. Optional
`float <amp> [speed]` adds a gentle vertical bob (pixels, cycles/sec).
For full effect details, see `docs/commands/effect.md`.

Supported transitions:
`fade | wipe | slide | dissolve | zoom | blur | flash | shake | none`

**Example**
```vn
scene color #2b2d42;
scene image "bg/park.png";
scene image "bg/river.png" float 6 0.6;
scene image "bg/night.png" wipe 0.6;
scene image "bg/forest.png" dissolve 0.5;

scene color #222 {
    narrator "Inside the scene block.";
};
```
