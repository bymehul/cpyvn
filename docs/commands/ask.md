# ask

**Syntax**
```vn
ask "Prompt" [timeout <seconds> default <index>]
    "Option A" -> label_a
    "Option B" -> label_b;
```

**Description**
Shows a prompt and a list of choices. Selecting a choice jumps to its label.
Choice text supports the same inline tags as dialogue (bold, italic, color, shake).
Prompt and option text support `${var}` placeholders.

**Example**
```vn
ask "What to do?"
    "Go Outside" -> go_outside
    "Go Back" -> hallway;

ask "Coins: ${coins}"
    "Buy (${price})" -> buy
    "Leave" -> leave;
```
