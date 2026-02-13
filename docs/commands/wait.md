# wait

**Syntax**
```vn
wait <seconds>;
wait voice;
wait video;
```

**Description**
Pauses script execution while the scene keeps rendering.

- `wait <seconds>;` waits for a fixed duration.
- `wait voice;` waits until the active voice channel finishes playback.
- `wait video;` waits until the current video playback (and queued embedded video audio) completes.

**Example**
```vn
wait 1.5;

voice narrator "line_01.wav";
wait voice;
chars.narrator "This line starts after voice ends.";

video play "intro.mp4";
wait video;
chars.narrator "This line starts after video finishes.";
```
