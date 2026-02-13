# Prefetch

`prefetch.json` lets you declare assets and scripts that must be loaded and pinned for the whole game session.

**Rules**
- Prefetched assets are pinned until exit.
- `cache clear` will not evict pinned items.
- Missing files log a warning (no hard crash).
- Duplicates are ignored.
- Prefetched scripts are parsed and stored in script cache.
- Runtime scene switches still prune non-pinned assets by scene manifest.

See also: `docs/memory.md`.

**Example**
```json
{
  "scripts": ["chapters/intro.vn", "chapters/outro.vn"],
  "images": {
    "bg": ["witches_library.png"],
    "sprites": ["body1 1.png"]
  },
  "audio": {
    "music": ["I'll be Here.wav"],
    "sfx": ["ui_bell.wav"],
    "voice": []
  }
}
```
