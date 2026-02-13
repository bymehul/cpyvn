# item

The `item` command manages the runtime inventory.

## Syntax

```vn
item add <id> "<name>" "<description>" icon "<image_path>" [amount <int>];
item remove <id> [amount <int>];
item clear;
```

## Quick Start

```vn
label start:
    item add key_101 "Room Key" "Opens room 101." icon "items/key.png";
    item add coin "Coin" "A small coin." icon "items/coin.png" amount 3;
    item remove coin amount 1;
```

## Behavior

- `item add`: inserts item if missing, otherwise increments existing count.
- `item remove`: decrements count; item is removed when count becomes `<= 0`.
- `item clear`: removes all inventory entries.
- `id` is the unique key. Keep it stable and lowercase-friendly (`room_key`, `coin`, `quest_letter`).
- If `item remove` references an item that is not present, runtime safely ignores it.

## Data Model

Each inventory entry stores:

- `id`: unique script id
- `name`: UI display name
- `description`: tooltip/body text
- `icon`: sprite-path string
- `count`: stack amount

## Inventory UI

Press `I` during gameplay to toggle inventory.

- Hover slot: shows name + description tooltip.
- `Esc`: close inventory.
- Click outside panel: close inventory.
- If item count exceeds one page:
  - Mouse wheel scrolls pages.
  - `PgUp`/`PgDn` changes pages.
  - Arrow keys also change pages while inventory is open.

## Feature Toggle

Inventory hotkey/toggle can be disabled in `project.json`:

```json
"features": {
  "items": { "use": false, "path": "items.cvn" }
}
```

When disabled:

- `I` will not open inventory.
- `inventory_toggle` jump target is ignored.
- `item` commands become no-ops.

## Notes

- Inventory is runtime state; it is saved/loaded with save slots.
- Use `item clear;` only when you intentionally reset progression.
