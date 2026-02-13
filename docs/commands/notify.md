# notify

**Syntax**
```vn
notify "Message";
notify "Message" 3.0;
```

**Description**
Shows a brief notification at the top of the screen. It does not block script flow.
If a duration (in seconds) is provided, it controls how long the message stays up.
Default is about 3 seconds.
`${var}` placeholders are expanded from runtime variables.

**Example**
```vn
notify "Quest updated";
notify "Auto-saved" 2.5;
notify "Coins: ${coins}" 2.0;
```
