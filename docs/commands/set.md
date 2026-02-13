# set

**Syntax**
```vn
set <var> <value>;
```

**Description**
Sets a variable.

Supported value types:
- integer (`42`)
- boolean (`true` / `false`)
- string (`"hello"`)
- variable reference (`$other_var`)

If the value is a string, `${var}` placeholders are expanded at runtime.

**Example**
```vn
set visits 0;
set has_key true;
set title "Chapter 1";
set coins_copy $coins;
set line "Coins: ${coins}";
```
