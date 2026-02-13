# loading

**Syntax**
```vn
loading "Loading" {
    ...
};
```

**Description**
Shows a full-screen loading overlay while the block runs. Use it to wrap preloads and heavy setup.

`loading` is optional for `call`.
You can still use it when you want explicit, script-controlled loading UX.

**Example**
```vn
loading "Loading map" {
    preload bg "map.png";
    preload sprites "npc.png";
};
```
