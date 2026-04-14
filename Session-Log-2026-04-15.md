# Session Log - 2026-04-15

This log records the implementation and investigation work completed in this
session for MapleStory character rendering/export.

## Scope

- Renderer positioning/alignment behavior
- Weapon-action compatibility behavior
- Batch export action/frame filtering and folder structure
- Hand/face overlap issues in `alert`/`heal`
- Documentation updates

## Implemented Changes

1. Weapon action fallback support (melee families)
- Added compatibility alias mapping so weapons without exact body action names
  can still render where family-compatible (for example `swingO*` -> `swingP*`,
  `stabO*` -> `stabT*`, `stand1` -> `stand2`).
- Added explicit selection mode metadata for alias-based picks.

2. Weapon `alert` outlier guard
- Added detection for outlier `alert` weapon anchor geometry that can detach
  weapon placement.
- Added guarded fallback to compatible idle actions when this outlier is hit.

3. Batch quality filter update
- Added dynamic effective min-layer rule when weapon has no render node:
  `effective_min_layers = max(1, min_layers - 1)`.
- Preserves valid low-layer actions like `rope`/`ladder` while still filtering
  broken frames.

4. Ranged alias tightening
- Restricted ranged weapon classes (`145/146/147/149`) to conservative alias
  remaps only, preventing cross-family weapon mismatches.

5. Strict metadata alignment rewrite
- Enabled strict anchor publication from canonical providers only:
  `body` and `head`.
- Non-canonical layers (including weapon) no longer publish global anchors.
- Disabled weapon hand-proxy override in strict mode.
- Positioning now follows frame `origin/map` metadata directly.

6. Off-hand handling in `alert`/`heal`
- Added off-hand visibility policy:
  - remove `lHand` for ranged weapons in `alert`/`heal`;
  - remove `lHand` when orphaned (`used_anchor=asset_origin_inherit`) in
    `alert`/`heal`.
- Added metadata output: `offhand_policy.removed_node_paths`.

7. Hand/face overlap mitigation
- Added ranged `alert/heal` layer correction for `lHand` when necessary to
  prevent face overlap artifacts.

8. Output organization and export behavior (already in active code/docs)
- Per-character output folders with character IDs.
- Per-action output subfolders in all-actions mode.
- Action-timeline delay usage from source body metadata.
- Optional per-action canvas normalization for stable GIF/sheet layout.

9. Weapon compatibility reporting and strict action-source mode
- Added `weapon_action_compatibility_report.py` to extract source-truth weapon
  action support from `Weapon/*.img`.
- Added strict batch action source mode:
  `loadout-intersection-with-weapon`.
- Batch export now logs and writes `weapon_profile` metadata in summary JSON.

## Files Updated During Session

- `render_character_frame.py`
- `character_tooling_gui.py`
- `Character-Tooling.md`
- `alignment_audit.py` (earlier in session)

## Verification Performed

- `python -m py_compile render_character_frame.py character_tooling_gui.py`
- Focused re-renders for affected loadouts/actions:
  - spear/polearm-style case (`1432008`) for alias/outlier checks
  - gun case (`1492037`) for ranged alias/placement checks
  - bow case (`1452011`) for `alert`/`heal` off-hand artifact checks
- Batch summary inspections under `analysis/batch_exports/char_*`
- Frame-level metadata checks (`action_resolution`, `draw_order`,
  `offhand_policy`, per-frame selection modes)

## Known Active Direction

- Weapon-to-action compatibility should be treated as source-data driven.
- Action support is discoverable directly from weapon asset action folders and
  weapon `info` metadata (`islot`, `vslot`, `afterImage`, `sfx`).
- Next step in progress: expose weapon compatibility reporting/strict action
  gating more explicitly in the GUI workflow.
