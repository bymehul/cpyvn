# cache

**Syntax**
```vn
cache clear images;
cache clear sounds;
cache clear all;
cache clear scripts;
cache clear script "chapters/intro.vn";
cache clear runtime;
cache pin bg "room.png";
cache pin sprites "alice.png";
cache pin audio "click.wav";
cache unpin bg "room.png";
cache unpin sprites "alice.png";
cache unpin audio "click.wav";
```

**Description**
Manual cache control for images and sounds. Pin keeps assets from being cleared.
For full behavior, see `docs/memory.md`.

- `cache clear scripts;`
  - Clears parsed script cache (`call`/include-loaded script data).
  - Prunes image/sound cache back to what the current scene still needs.
- `cache clear script "<path>";`
  - Clears parsed cache for one script file path.
  - If that script is currently running, also clears current runtime scene state.
  - For non-current scripts, prunes image/sound cache back to current-scene assets.
- `cache clear runtime;`
  - Clears script cache + current runtime scene memory:
  - stops media, clears sprites/hotspots/transitions, resets background to black,
    clears image/sound cache, and runs `gc`.

**Notes**
- Script switches via `call` already do automatic cache pruning for the next script manifest.
- `cache clear scene;` is supported as an alias of `cache clear runtime;`.
- Pinned assets (`cache pin ...`) are not removed by scene/script pruning.

**Example**
```vn
cache clear images;
cache pin bg "room.png";
cache unpin bg "room.png";
cache clear scripts;
cache clear script "chapters/intro.vn";
cache clear runtime;
```
