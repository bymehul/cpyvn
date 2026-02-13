# voice

**Syntax**
```vn
voice <character> "path";
voice "path";
```

**Description**
Plays a voice line on the dedicated voice channel. If a character is provided and that
character has a `voice` tag in its definition, relative paths are prefixed with that tag.

Use `wait voice;` if you want script execution to block until the current voice line finishes.

**Example**
```vn
voice mc "line_01.wav";
voice mc "intro_01.wav"; // resolves to "mc/intro_01.wav" if character voice tag is "mc"
wait voice;
```
