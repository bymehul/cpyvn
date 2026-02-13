# blend

**Syntax**
```vn
blend <style> <seconds>;
```

**Description**
Plays a full-screen transition effect.

Supported styles:
- `fade`
- `wipe`
- `slide`
- `dissolve`
- `zoom`
- `blur`
- `flash`
- `shake`
- `none`

Notes:
- `none` disables the transition.
- `blur` uses CPU blur by default.
- Set `"wgpu_blur": true` in `project.json` to force the dedicated `wgpu` backend (see `docs/wgpu_blur.md`).

**Example**
```vn
blend fade 0.8;
blend wipe 0.6;
blend blur 0.5;
```
