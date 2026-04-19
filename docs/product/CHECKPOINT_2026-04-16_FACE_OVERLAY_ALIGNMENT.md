# Checkpoint: 2026-04-16 Face Overlay Alignment

## Version Label

- `checkpoint-2026-04-16-face-overlay-alignment`
- Branch context: `version/sit-chair-height-tuning`

## Recorded Scope

- Migrated to face-overlay architecture for runtime buddy rendering:
  - body/sprite frames exported without baked face layer
  - neutral/default face rendered as overlay at runtime
  - emote faces swapped via semantic emote mapping
- Added semantic emote manifest:
  - `apps/runtime-godot/content/core_pack/character/emotes/manifest.json`
- Added runtime emote controls and diagnostics:
  - `F10` debug panel
  - hotkeys `1..0` for emote testing
  - face source telemetry line for path verification
- Fixed alignment drift using metadata normalization sync:
  - frame JSON `frame_bounds_world` now updated when PNG frames are normalized
  - normalized offset/size persisted per frame JSON
- Regenerated core runtime sprite assets and animation sheets with updated exporter.

## Primary Files Updated

- `render_character_frame.py`
- `export_runtime_character_sprites.py`
- `apps/runtime-godot/scripts/buddy_overlay.gd`
- `apps/runtime-godot/content/core_pack/manifest.json`
- `apps/runtime-godot/content/core_pack/character/emotes/manifest.json`
- `apps/runtime-godot/content/core_pack/character/*.png`
- `apps/runtime-godot/content/core_pack/character/animations/**/*`
- `docs/product/IMPLEMENTATION_LOG_2026-04-15.md`

## Validation

- Runtime export completed successfully via:
  - `python export_runtime_character_sprites.py`
- Godot runtime headless startup check passed via:
  - `godot_console.exe --headless --path . --quit`
  - Note: Windows certificate-store warning appears, but startup succeeds.
