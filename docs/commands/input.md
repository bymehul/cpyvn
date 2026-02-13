# input

**Syntax**
```vn
input <variable_name> "<prompt>" [default "<default_value>"];
```

**Description**
Shows an input prompt centered on the screen. The user can type text and press Enter to confirm. The entered text is stored in the specified variable.

- **variable_name**: The name of the variable to store the result in.
- **prompt**: The text to display above the input box. Supports `${var}` placeholders.
- **default**: (Optional) The initial text in the input box.

**Example**
```vn
input player_name "What is your name?" default "Hero";
narrator "Welcome, ${player_name}!";
```
