# WZ Item Data Map (Source-of-Truth)

There is no single master file in WZ that contains all item data.
The mapping is split across domains and must be joined by item id.

## Core Join Key
- Item ID (for example `2022043`, `4032444`, `1302000`)

## Where each field comes from
- Name/description:
  - `Base.wz/String/String.wz/Consume.img.xml`
  - `Base.wz/String/String.wz/Eqp.img.xml`
  - `Base.wz/String/String.wz/Etc.img.xml`
  - `Base.wz/String/String.wz/Cash.img.xml`
- Price/slot/stat/effect metadata:
  - `Base.wz/Item/Item.wz/**/<group>.img.xml`
  - Example: `Base.wz/Item/Item.wz/Consume/0202.img.xml`
- Icon/canvas paths:
  - inside each item node under `info/icon` (and sometimes variants)
- Equip visual layers/offsets/attachment behavior:
  - `Base.wz/Character/Character.wz/**/*.img.xml`
  - Example weapon file includes `map/*`, `origin`, `z`
- Ground/drop behavior and world-side visuals (bobbing, pickup presentation):
  - `Base.wz/Map/**`
  - `Base.wz/Effect/**`
  - `Base.wz/Reactor/**` (for some interactables)

## Runtime Mapping in Buddy Assembler
- Normalized mapping table:
  - `apps/runtime-godot/content/core_pack/item_bindings.csv`
- Runtime item catalog:
  - `apps/runtime-godot/content/core_pack/manifest.json` (`items[]`)
- Imported icon output:
  - `apps/runtime-godot/content/core_pack/icons/items/`

## Broad Ingest Script (Canonical Map)

- Script:
  - `apps/runtime-godot/tools/build_wz_canonical_item_map.py`
- Example run:
  - `python apps/runtime-godot/tools/build_wz_canonical_item_map.py --wz-root "C:/Users/GGPC/OneDrive/Desktop/83 complete/Base.wz"`
- Output:
  - `apps/runtime-godot/content/core_pack/item_bindings_full.csv`
  - `apps/runtime-godot/content/core_pack/item_bindings_full.json`

### Sync manifest from canonical map

- Dry-run sync existing manifest items:
  - `python apps/runtime-godot/tools/sync_manifest_items_from_bindings.py --bindings "apps/runtime-godot/content/core_pack/item_bindings_full.csv" --dry-run`
- Dry-run add missing items preview:
  - `python apps/runtime-godot/tools/sync_manifest_items_from_bindings.py --bindings "apps/runtime-godot/content/core_pack/item_bindings_full.csv" --add-missing --max-add 25 --dry-run`

### One-command batch ingest

- Add N items + import icons + run checks:
  - `python apps/runtime-godot/tools/run_wz_ingest_batch.py --batch-size 100`
- Faster loop (skip checks):
  - `python apps/runtime-godot/tools/run_wz_ingest_batch.py --batch-size 100 --skip-checks`
- Multi-batch autonomous run (example: 10 batches of 100):
  - `python apps/runtime-godot/tools/run_wz_ingest_batch.py --batch-size 100 --batches 10`

## Current constraint
- Legacy runtime ids like `cozy-lamp`, `warm-tea`, `plush-heart` are not WZ ids.
- They must be remapped to WZ-backed ids before item-specific icon and metadata can render correctly.

## Icon ingest status (2026-04-23)
- Importer now resolves both:
  - `.../info/icon.png`
  - alternate extracted layouts such as `.../icon.png` and `.../iconRaw/0.png`
- Current full ingest result:
  - `copied=6008`
  - `missing=0` (for all catalog-backed rows in `item_bindings_full.csv`)
- Remaining gap report: `0` rows (no current manifest icon gaps).
