# check

**Syntax**
```vn
check <var> <op> <value> {
    ...
};
```

**Description**
Runs the block only if the condition is true.

Supported operators: `== != > >= < <=`

A `$` prefix is allowed in the variable name.
Right-side value can also be a variable reference (`$other_var`).

**Example**
```vn
check visits > 1 {
    narrator "Welcome back.";
};

check $has_key == true {
    narrator "Door unlocked.";
};

check coins >= $required_coins {
    narrator "Enough coins.";
};
```
