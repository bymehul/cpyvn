# show

**Syntax**
```vn
show <character> [expression] [position];
show <character> [expression] [position] z <int>;
show <character> [expression] [position] <transition> <seconds>;
show <character> [expression] [position] float <amp> [speed];
```

**Description**
Shows a character sprite using its `character` definition. If `expression` is
omitted, it uses `default`. If the expression is unknown, it falls back to
`default`. Position can be `left`, `center`, `right`, `top`, `middle`, `bottom`,
or `x y`. Use `z` to control render order, `<transition>` to animate in, and `float`
for a gentle vertical bob.

For full effect details, see `docs/commands/effect.md`.

Supported transitions:
`fade | wipe | slide | dissolve | zoom | blur | flash | shake | none`

**Example**
```vn
show alice happy right;
show bob left;
show alice default 320 540;
show alice happy right z 5;
show alice happy right fade 0.3;
show alice happy right wipe 0.3;
show alice happy right dissolve 0.45;
show alice happy right shake 0.3;
show alice happy right float 4 1.0;
```
