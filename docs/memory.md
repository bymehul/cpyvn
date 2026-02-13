# Memory Model

cpyvn uses a deterministic, scene-scoped memory model.

## Layers

1. Parse cache  
   Parsed script AST + labels, keyed by absolute script path.

2. Asset caches  
   - image cache (`bg`, `sprites`)
   - sound cache (`audio`)

3. Runtime scene state  
   Current background, visible sprites, hotspots, transitions, active waits, video state.

4. HUD state  
   Persistent HUD buttons (`self.hud_buttons`). Unlike hotspots, these survive scene changes
   and `cache clear`. Only cleared by explicit `hud remove` / `hud clear`.

5. Variable state  
   Runtime variables from `set`/`track` (`self.variables`), persisted in save files.

6. Pins  
   Pinned assets are never evicted by scene/script pruning.

## Scene Manifest

Every loaded script builds a scene manifest (`vn/runtime/scene_manifest.pyx`) that records:

- background images
- sprite images (including `character` sprite mappings)
- audio paths (`music`, `sound`, `echo`, `voice`)
- called scripts (`call ...`)
- referenced videos

This manifest is used to prefetch and prune safely.

## What Happens On `call`

When switching scripts with `call`:

1. Next script is parsed/loaded (from cache if available).
2. Next manifest assets are prefetched.
3. Cache is pruned to next-scene needs:
   - keep next-scene assets
   - keep pinned assets
   - keep currently active echo/voice
   - keep current music path
4. Runtime moves to target label in next script.

Result: old script assets are dropped when no longer needed.

### Call Loading Overlay

`call` does not require `loading { ... }`.

Runtime can auto-show loading overlay for:
- cold calls (script not in parse cache)
- scripts previously measured as slow

Project knobs:
- `ui.call_auto_loading` (default `true`)
- `ui.call_loading_text` (default `"Loading scene..."`)
- `ui.call_loading_threshold_ms` (default `120`)
- `ui.call_loading_min_show_ms` (default `120`)

## `loading` And `preload`

`loading "text" { ... };` is a script-level loading phase.

- `loading start` shows loading overlay.
- `preload` commands inside it load assets into cache immediately.
- `loading end` hides overlay.

`preload` loads cache entries, but does not make them immutable.  
Use `cache pin ...` or `prefetch.json` if you need guaranteed retention.

## Cache Commands

- `cache clear images;`  
  Drop non-pinned image cache entries.

- `cache clear sounds;`  
  Drop non-pinned sound cache entries.

- `cache clear scripts;`  
  Clear parse cache and prune assets back to current-scene needs.

- `cache clear script "path.vn";`  
  Clear one parsed script entry.  
  If it is the current script, runtime scene state is reset.

- `cache clear runtime;` (`cache clear scene;` alias)  
  Full runtime reset + non-pinned cache clear + GC.
  Variables are kept (not cleared).

## Prefetch

`prefetch.json` is startup-level pinning/warming:

- scripts are parsed and kept in script cache
- images/audio are preloaded and pinned
- duplicates are ignored
- missing files only warn

Use prefetch for always-hot assets (map, UI sounds, common characters).

## Practical Rules

- Pin only assets that are truly global.
- Use scene-local assets for chapter-specific content.
- Use `call` boundaries as cleanup boundaries.
- Use `cache clear runtime` only for hard reset/debug, not normal flow.
