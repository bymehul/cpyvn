# call

**Syntax**
```vn
call "chapter2.vn" start;
```

**Description**
Loads another script file at runtime and jumps to the given label.
This does not return to the original script.

`call` works with or without a `loading { ... }` block.

- Manual loading: wrap with `loading` when you want explicit control.
- Auto loading: runtime can show loading overlay for cold/slow calls (project config).

**Example**
```vn
call "chapters/ch2.vn" start;
```

Manual overlay:
```vn
loading "Loading chapter 2" {
    call "chapters/ch2.vn" start;
};
```
