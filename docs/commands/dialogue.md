# dialogue

**Syntax**
```vn
<speaker> "text";
```

**Description**
Displays a line of dialogue. The first word is the speaker name.
If the speaker matches a `character` id, its display name and color are used.
If the character has a `sprite default`, it auto-shows when the character speaks.
`${var}` placeholders are expanded using runtime variables.

**Text Styles**
Inline tags let you style parts of a line:
- `[b]bold[/b]`
- `[i]italic[/i]`
- `[color=#ff6b6b]color[/color]` (hex `#RGB` or `#RRGGBB`)
- `[shake]shake[/shake]`

Tags do not count toward text speed reveal.

**Example**
```vn
narrator "Welcome to cpyvn.";
mc "Hey there.";
narrator "This is [b]bold[/b], [i]italic[/i], and [color=#ff6b6b]red[/color].";
narrator "Coins: ${coins}";
```
