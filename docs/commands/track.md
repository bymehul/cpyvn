# track

**Syntax**
```vn
track <var> +N;
track <var> -N;
```

**Description**
Adjusts a numeric variable by a delta.
If the variable is missing (or non-numeric), runtime treats it as `0`.

**How It Works**
- `track score +5;` means: current value + 5
- `track score -2;` means: current value - 2
- First use without `set` is valid:
  `track score +1;` -> `score` becomes `1`
- If a variable is text/bool, `track` safely resets from `0` before applying delta.

Use `set` when you want an exact value, and `track` when you want incremental changes.

**Example**
```vn
set visits 0;
track visits +1;
track rel_gf -5;
```
