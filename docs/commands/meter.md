# meter

**Syntax**
```vn
meter show <variable_name> "<label>" <min> <max> [color <hex_color>];
meter update <variable_name>;
meter hide <variable_name>;
meter clear;
```

**Description**
Displays and manages relationship or progress meters in the top-right corner of the screen.

- **show**: Creates and displays a new meter.
    - **variable_name**: The variable whose value the meter monitors.
    - **label**: The display name for the meter. Supports `${var}` placeholders.
    - **min**: The minimum value for the meter.
    - **max**: The maximum value for the meter.
    - **color**: (Optional) Hex color code for the filled part of the bar (e.g., `#FF0000`). Default is white.
- **update**: Refreshes the meter's visual value (useful after changing the variable).
- **hide**: Removes a specific meter.
- **clear**: Removes all active meters.

**Example**
```vn
set trust 50;
meter show trust "Trust" 0 100 color #4ECDC4;
narrator "Alice seems to like that.";
track trust 10;
meter update trust;
# ... later ...
meter clear;
```
