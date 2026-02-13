# video

**Syntax**
```vn
video play "cutscene.mp4";
video play "cutscene.mp4" loop true;
video play "cutscene.mp4" fit contain;
video play "cutscene.mp4" loop false fit cover;
video stop;
wait video;
```

**Description**
Plays a video layer behind sprites and UI.

- `loop`: `true` or `false` (default `false`)
- `fit`:
  - `contain`: keep full frame visible (letterbox if needed)
  - `cover`: fill screen (crop if needed)
  - `stretch`: stretch to screen

`video stop;` stops playback and removes the video layer.
`wait video;` blocks script advance until video playback (and queued video-audio) ends.

**Notes**
- Video files resolve from `assets.video` in `project.json` (default `assets/video`).
- Backend selection comes from `project.json` key `video_backend`:
  - `auto` (default): use `vnef`
  - `vnef`: force native `vnef-video`
  - `imageio`: legacy alias (maps to `vnef`)
- Embedded video audio can be toggled with `project.json` key `video_audio` (default `true`).
- Frame drop policy uses `project.json` key `video_framedrop`:
  - `auto`: adaptive mode (toggles on/off based on real-time lag/queue)
  - `on`: always drop late frames
  - `off`: never drop (can visually lag on weak hardware)
- `vnef` backend requires `vnef-video` native library.

**Build Requirement**
- Engine dev / CI building the native video library: needs CMake toolchain.
- Game creators and players: do not need CMake if shipped with prebuilt `libvnef_video` for their platform.
- Optional override for custom library path:
  - `CPYVN_VNEF_VIDEO_LIB=/absolute/path/to/libvnef_video.so` (Linux example)
  - `CPYVN_VNEF_VIDEO_DIR=/path/to/folder/containing/lib` (engine searches this dir too)
- Export flow (engine + game) is documented in `docs/export.md`.

**Example**
```vn
label intro_cutscene:
    video play "opening.mp4" loop false fit contain;
    wait video;
    go start;
```
