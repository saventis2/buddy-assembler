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

10. Skill animation overlay support
- Added optional skill overlay rendering from `Skill/Skill.wz` in
  `render_character_frame.py`.
- New renderer parameters:
  - `skill_id` / `--skill-id`
  - `skill_anim` / `--skill-anim` with branch selection
    (`auto|effect|effect0|effect1|hit|ball|prepare|summon|affected`)
- Added batch UI fields for skill overlay (`Skill ID`, `Skill Anim`) and pass
  through to frame rendering.
- Batch summary now records `skill_overlay`; per-frame metadata records
  `skill_selection`.

11. Versioning workflow hardening
- Added a rollback section to `Character-Tooling.md` documenting commit/tag
  checkpoint workflow and restore commands.
- Created baseline rollback points:
  - commit: `b67d821`
  - tag: `stable-2026-04-15-weapon-skill-baseline`
  - branch: `stable/2026-04-15-weapon-skill-baseline`

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

## Addendum (Desktop Buddy Runtime + Tooling)

12. Runtime animation source parity
- Updated exporter timeline/link handling to mirror NPC behavior semantics:
  - resolves action chains through `info/link`
  - supports delay parsing from both int/string nodes
  - supports `uol` frame references with inherited delays
- Regenerated runtime character animation artifacts under
  `apps/runtime-godot/content/core_pack/character/animations/`.

13. Other-WZ item catalogue support
- Added `build_itemwz_catalogue.py` to index `Item/Item.wz` roots:
  `Cash`, `Consume`, `Etc`, `Install`, `Pet`, `Special`.
- Outputs include:
  - `itemwz_catalogue_all.csv`
  - `itemwz_catalogue_<root>.csv`
  - `itemwz_catalogue_summary.json`
  - `itemwz_catalogue_index.md`
- Added `analyze_npc_animation_links.py` for NPC link-chain/timeline inspection.

14. Buddy overlay cropping/alignment fix
- Updated `apps/runtime-godot/scripts/buddy_overlay.gd`:
  - switched draw pivot from viewport-center to floor anchor
  - unified draw/hit test via a shared computed sprite rect
  - clamped sprite rect to viewport bounds to prevent hover clipping
  - added fit-to-viewport scaling guard for oversized frames

15. GUI catalogue mode extension
- Updated `character_tooling_gui.py` catalogue tab with dual modes:
  - `Character (Equip)` (existing behavior)
  - `Item.wz (Other Items)` (browse mode)
- Item.wz mode can generate/load `itemwz_catalogue_all.csv`, search/filter rows,
  and preview icons; apply-to-render is intentionally blocked with explicit UX.

16. Metadata-driven floor anchoring for buddy runtime
- Extended animation export (`export_runtime_character_sprites.py`) to emit:
  - `floor_world_ref` (derived from idle frame world bounds)
  - per-frame `pivot_px` and `pivot_world`
- Updated runtime animation loader (`apps/runtime-godot/scripts/buddy_overlay.gd`)
  to consume per-frame `pivot_px` and apply dynamic frame anchors, including
  anchors outside image bounds when needed (for consistent floor lock across
  states with different crop heights).
- Updated core manifest visual anchor fallback to `[0.5, 1.0]`.

17. Terrain ground layer for desktop runtime
- Added runtime ground rendering support in
  `apps/runtime-godot/scripts/buddy_overlay.gd`:
  - manifest-driven `visual.ground` config
  - tiled or centered draw modes
  - alignment options (`top|center|bottom`)
  - configurable floor padding (`visual.ground.floor_padding`)
- Added `import_runtime_ground_tile.py` to import terrain tiles directly from
  `Map/Map.wz/Tile/*` into runtime content packs.
- Imported default tile:
  `Map/Map.wz/Tile/citySG.img/bsc/0.png` ->
  `apps/runtime-godot/content/core_pack/terrain/ground_citySG_bsc_0.png`
- Enabled ground in `core_pack` manifest under `visual.ground`.

## Verification (Addendum)

- `python -m py_compile character_tooling_gui.py build_itemwz_catalogue.py analyze_npc_animation_links.py export_runtime_character_sprites.py`
- `pwsh ./apps/runtime-godot/tests/run_headless_checks.ps1`
- Note: Godot still reports the existing Windows certificate store warning in
  headless mode; parse checks completed successfully.

## Addendum (2026-04-16)

18. Ground/tuner rollback and bottom-anchor simplification
- Removed runtime ground tuner UI path from `buddy_overlay.gd`:
  - removed startup creation of slider/tickbox controls
  - removed `F10` ground-tuner toggle input
- Removed visible ground render pass from draw flow.
- Forced companion floor anchor to the window bottom edge:
  - `_floor_point()` now returns `viewport_bottom - SPRITE_VIEW_MARGIN`
  - pivot metadata still drives frame alignment, but floor no longer depends
    on terrain or tuner offsets.

19. Runtime settings cleanup and manifest bump
- Removed temporary ground-tuner settings defaults from
  `apps/runtime-godot/scripts/autoload/app_state.gd`:
  - `groundSurfaceAdjustPx`
  - `lockGroundPivotY`
- Updated `apps/runtime-godot/content/core_pack/manifest.json`:
  - pack version bumped `0.1.0` -> `0.1.1`
  - `visual.ground.enabled` set to `false`
- Updated runtime docs to reflect current behavior:
  - bottom-anchored sprite placement
  - no rendered ground layer
