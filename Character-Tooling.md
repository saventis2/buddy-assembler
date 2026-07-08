# Character Tooling

Session records:

- `Session-Log-2026-04-15.md` (detailed implementation/investigation log)

## Overriding Base.wz / analysis paths (all root scripts)

All 14 root importer/analysis scripts default to the maintainer's local
`83 complete` extraction (e.g. `C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz`),
so the existing zero-flag workflow keeps working unchanged. Every script that
takes a WZ/analysis path resolves it with the same precedence:

1. **Explicit CLI flag** — e.g. `--base-wz`, `--output-dir` (most scripts
   already had this; `build_wz_index.py` gained a `--base-wz` flag and
   `character_tooling_gui.py` gained `--base-wz`/`--analysis-dir` flags to
   pre-fill the GUI fields).
2. **Environment variable** — `BUDDY_ASSEMBLER_BASE_WZ` (and, for
   `character_tooling_gui.py`'s analysis-output default,
   `BUDDY_ASSEMBLER_ANALYSIS_DIR`). Set these to point scripts at a different
   extraction tree (a second machine, a test fixture, CI) without passing
   flags on every invocation.
3. **Hardcoded fallback default** — the maintainer's local path, unchanged,
   used only when neither of the above is set.

`build_wz_index.py` and `character_tooling_gui.py` previously hardcoded their
Base.wz/analysis paths as module-level constants with no override at all;
they now follow this same precedence via a small `resolve_base_wz()` /
`resolve_default_path()` helper in each file. Scripts that already exposed
`--base-wz`/`--output-dir` (etc.) via `argparse` — e.g.
`build_item_catalogue.py`, `build_itemwz_catalogue.py`,
`import_runtime_ground_tile.py`, `analyze_npc_animation_links.py`,
`render_character_frame.py`, `export_effect_sprites.py`,
`weapon_action_compatibility_report.py`, `analyze_character_assets.py` — were
left as-is; their CLI flag already provides an override, so no env var was
added to avoid a redundant second mechanism. Scripts whose path args are
`required=True` with no default (`diff_character_assets.py`,
`alignment_audit.py`, `audit_dataset_metadata.py`) and
`export_runtime_character_sprites.py` (repo-relative defaults, no hardcoded
machine path) needed no changes.

## 0) Desktop GUI (Render + Diff)

Script: `character_tooling_gui.py`

Run:

```powershell
python character_tooling_gui.py
```

What it provides:

- `Render` tab for composing a character frame and previewing output PNG.
- `Diff` tab for old/new extracted tree comparisons with classification summary.
- `Catalogue` tab for part-separated item browsing/search and one-click ID apply into Render slots.
- `Batch Export` tab for action frame-range export (PNG sequence + optional GIF).
- `Batch Export` supports complete exports:
  - auto-detect full frame range for an action,
  - export all actions,
  - generate per-action GIFs and sprite sheets.
- Input validation for Base.wz paths, numeric IDs/frame values, and slow-mode warnings.
- Read-only command previews for both operations.
- Adjustable z-draw mode (`front-last` default, `front-first` optional) for layer ordering.
- Item ID name resolution in Render tab from `String\String.wz\Eqp.img.xml`:
  - shows `Name [ID]`,
  - warns when ID category does not match expected slot.

Council-style decisions applied:

- Default to fast-safe modes (`size` compares, `include_unchanged` off).
- Warn for risky/slow settings (`hash`, identical old/new paths, coat+longcoat overlap).
- Keep outputs inspectable via JSON/CSV and image preview instead of opaque execution.

Desktop shortcut created:

- `C:\Users\GGPC\OneDrive\Desktop\docs  fo ai (so i know where to look\MapleStory Character Tooling GUI.lnk`

## 0.1) Item Catalogue Generator

Script: `build_item_catalogue.py`

Run:

```powershell
python build_item_catalogue.py `
  --base-wz "C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz" `
  --output-dir "C:\Users\GGPC\OneDrive\Desktop\83 complete\analysis\catalogue"
```

Outputs:

- `catalogue_all.csv`
- `catalogue_summary.json`
- `catalogue_index.md`
- `catalogue_<PartCategory>.csv` files for easy part-by-part reference

The GUI `Catalogue` tab can generate/load these files, filter by category, search by name/ID, and apply selected IDs to Render fields.

## 0.2) Item.wz Catalogue (Other WZ Item Roots)

Script: `build_itemwz_catalogue.py`

Run:

```powershell
python build_itemwz_catalogue.py `
  --base-wz "C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz" `
  --output-dir ".\analysis\catalogue_itemwz"
```

Outputs:

- `itemwz_catalogue_all.csv`
- `itemwz_catalogue_summary.json`
- `itemwz_catalogue_index.md`
- `itemwz_catalogue_<root>.csv` per `Item\Item.wz` root:
  - `Cash`, `Consume`, `Etc`, `Install`, `Pet`, `Special`

This provides an index for non-Character items that live under other WZ roots.

## 0.3) NPC Animation + Link Analyzer

Script: `analyze_npc_animation_links.py`

Run:

```powershell
python analyze_npc_animation_links.py `
  --base-wz "C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz" `
  --npc-id 2004 `
  --action stand
```

What it validates:

- `info/link` chain resolution (for linked NPCs)
- per-frame `delay` parsing from both `int` and `string` nodes
- `uol` frame delay inheritance
- aggregate dataset scan stats (link usage ratio, delay field type mix, top action names)

## 1) Prototype Frame Renderer

Script: `render_character_frame.py`

Example (starter male, stand frame):

```powershell
python render_character_frame.py `
  --starter-male `
  --action stand1 `
  --frame 0 `
  --output-png .\renders\starter_male_stand1_0.png `
  --output-json .\renders\starter_male_stand1_0.json
```

Key options:

- `--base-wz` extracted `Base.wz` root.
- `--action`, `--frame` select state/frame.
- `--z-draw-order front-last|front-first` controls final compositing order (`front-last` recommended).
- `--base-id`, `--head-id`, `--face-id`, `--hair-id` for base appearance.
- Optional equip IDs: `--cap-id`, `--coat-id`, `--longcoat-id`, `--pants-id`, `--shoes-id`, `--glove-id`, `--cape-id`, `--shield-id`, `--weapon-id`, `--accessory-id`.

Output:

- Composited PNG.
- Metadata JSON with draw order, z-layers, anchor used, and unresolved nodes.

## 2) Character Asset Diff Tool

Script: `diff_character_assets.py`

Example (compare two extracts):

```powershell
python diff_character_assets.py `
  --old-base-wz "D:\extract_old\Base.wz" `
  --new-base-wz "D:\extract_new\Base.wz" `
  --output-dir ".\diff_out" `
  --xml-compare size `
  --png-compare size
```

Key options:

- `--xml-compare size|hash`
  - `size`: fast pre-check.
  - `hash`: accurate, slower.
- `--png-compare size|hash`
  - `size`: fast.
  - `hash`: accurate, slower.
- `--skip-png` for XML-only diff.
- `--include-unchanged` to emit full CSVs (can be large).

Output:

- `character_diff_summary.json`
- `character_xml_diff.csv`
- `character_png_diff.csv`

Classification buckets:

- `structural`
- `timing`
- `composition`
- `compatibility`
- plus art changes via PNG diff.

## 3) Batch Animation Export (GUI tab)

Use the GUI `Batch Export` tab to export a frame range or complete action/action-set.

Inputs:

- Base.wz path, action, start/end frame.
- Optional automatic full-frame detection for the chosen action.
- Optional all-actions mode (exports every action detected in base template).
- Output directory + filename prefix.
- Optional GIF path/duration.
- Optional sprite sheet path/columns.
- Character IDs come from Render tab values (or starter preset).

Outputs:

- `prefix_action_###.png` frame sequence.
- Optional `prefix_action_###.json` metadata per frame.
- Optional GIF (`prefix_action.gif` in all-actions mode).
- Optional sprite sheet (`prefix_action_sheet.png` in all-actions mode).
- Batch summary JSON (`prefix_action_batch_summary.json` or `prefix_all_actions_batch_summary.json`).

GIF/sprite-sheet location behavior:

- Single-action mode:
  - uses the exact `GIF Path` and `Sprite Sheet Path` fields.
- All-actions mode:
  - writes per-action outputs inside `Output Dir\<action>\`:
    - `prefix_<action>.gif`
    - `prefix_<action>_sheet.png`
  - Batch log prints each created path.

Quality controls (recommended):

- `Skip frames with unresolved assets`: drops frames that reference missing PNG/XML pieces.
- `Minimum drawn layers per frame`: drops frames that render too few layers (likely broken output).
- Dropped frames are logged with reasons and excluded from final GIF/sprite sheet.

## 4) Alignment Audit

Script: `alignment_audit.py`

Purpose:

- Analyze existing batch-render metadata to detect alignment risk and animation compatibility issues.
- Quantify fallback usage, unresolved taxonomy, anchor behavior, and frame-to-frame positional drift.

Run:

```powershell
python alignment_audit.py `
  --batch-summary ".\batch_exports\anim_all_actions_batch_summary.json" `
  --base-wz "C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz" `
  --out-dir ".\alignment_audit"
```

Outputs:

- `alignment_audit_report.json` (full diagnostics + metrics)
- `alignment_findings.csv` (flat findings table)
- `alignment_summary.md` (human-readable summary)

Key options:

- `--max-jitter-px` (default `6.0`)
- `--max-fallback-rate` (default `0.35`)
- `--allow-origin-fallback-kinds` (default `body`)

GUI integration:

- Batch tab now includes `Run Alignment Audit` to run the same pipeline against the expected batch summary file.

## 5) Recent Fixes (2026-04-15)

- Weapon action compatibility fallback:
  - Missing weapon nodes on actions like `swingO*`, `swingT3/TF`, `stabO*`, `stand1` now map to compatible weapon families (for example `swingP*`, `stabT*`, `stand2`) instead of dropping weapon rendering.
- `alert` weapon outlier guard:
  - Some weapon `alert` nodes include extreme hand-anchor offsets that render detached/off-body.
  - Renderer now detects this case and falls back to a compatible idle weapon node (`stand2`/`stand1`/`walk2`/`walk1`/`prone`) with selection mode `fallback_weapon_alert_outlier_alias_closest_frame`.
- Batch quality filtering update:
  - When a weapon has no render node for an action (`selection_mode=no_render_node`, `entry_count=0`), effective minimum-layer threshold is reduced by 1 for that frame.
  - This preserves valid low-layer actions like `rope`/`ladder` that were previously dropped by strict global min-layer filtering.
- Ranged weapon alias tightening:
  - For ranged weapon classes (`145/146/147/149`), alias fallback is now intentionally minimal (`stand2->stand1`, `walk2->walk1`, plus conservative `alert` fallback).
  - This avoids cross-family remaps (for example forcing `swingTF`/`stabOF` onto unrelated weapon nodes) that can produce detached or static-looking gun placement.
- Ranged `alert/heal` hand-face layering:
  - For ranged loadouts, `lHand` on `alert`/`heal` is forced behind face (`z_index > face`) when it uses `handBelowWeapon`, preventing visible hand-over-face overlap artifacts.
- Off-hand visibility policy (`alert/heal`):
  - `lHand` is now suppressed when it is effectively orphaned (`used_anchor=asset_origin_inherit`) in `alert/heal`.
  - For ranged weapon classes (`145/146/147/149`), `lHand` is also suppressed in `alert/heal` to avoid stray face-adjacent off-hand artifacts.
  - Policy output is recorded in frame metadata under `offhand_policy.removed_node_paths`.
- Strict metadata alignment (positioning rewrite):
  - Placement now uses canonical anchor publication from `body` and `head` only.
  - Non-canonical equipment layers (including weapon) no longer publish new global anchors during solve.
  - Weapon hand-proxy alignment override is disabled in strict mode so weapon position is determined by the frame's own map/origin metadata.

## 6) Weapon Action Compatibility (Source-Driven)

New script: `weapon_action_compatibility_report.py`

Purpose:

- Read weapon source metadata directly from `Character/Character.wz/Weapon`.
- Report which actions each weapon actually supports (based on source action folders/frames).
- Build type-level action matrices (common actions vs union actions).

Run:

```powershell
python weapon_action_compatibility_report.py `
  --base-wz "C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz" `
  --output-dir ".\dataset_audit" `
  --weapon-id 1452011 `
  --weapon-id 1492037 `
  --weapon-id 1432008
```

Outputs:

- `dataset_audit/weapon_action_profiles.json`
- `dataset_audit/weapon_action_profiles_selected.json` (when `--weapon-id` is provided)
- `dataset_audit/weapon_type_action_matrix.json`
- `dataset_audit/weapon_type_action_matrix.csv`

Batch export mode update:

- `All-actions source` now includes `loadout-intersection-with-weapon` (strict compatibility mode).
- In strict mode, all-actions export uses the intersection of body/core gear actions and weapon-supported actions.
- Batch summary now includes `weapon_profile` metadata for traceability.

Weapon intent metadata notes:

- Action support is inferred from weapon action folders in `Character/Character.wz/Weapon/<weapon>.img/<action>/...`.
- Weapon archetype hints come from weapon `info` strings:
  - `afterImage` (for example `bow`, `gun`, `spear`)
  - `islot` / `vslot`
- Use these together to avoid invalid action/weapon pairings.

## 7) Skill Overlay Animation (Optional)

Renderer support:

- `render_character_frame.py` now supports optional skill overlays from `Skill/Skill.wz`.
- New args:
  - `--skill-id <int>`
  - `--skill-anim auto|effect|effect0|effect1|hit|ball|prepare|summon|affected`

Example:

```powershell
python render_character_frame.py `
  --base-wz "C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz" `
  --action swingT1 `
  --frame 0 `
  --base-id 2000 --head-id 12000 --face-id 20425 --hair-id 31545 `
  --coat-id 1041127 --pants-id 1060133 --shoes-id 1072318 --weapon-id 1452011 `
  --skill-id 1001004 --skill-anim effect `
  --output-png ".\tmp_diag_skill_overlay\skill_effect.png" `
  --output-json ".\tmp_diag_skill_overlay\skill_effect.json"
```

Batch tab support:

- New fields:
  - `Skill ID (optional overlay)`
  - `Skill Anim`
- When set, skill overlay is rendered for every exported frame/action.
- Batch summary includes `skill_overlay` settings; per-frame JSON includes `skill_selection`.

## 8) Versioning & Rollback

Repository status:

- This project is git-versioned on branch `main`.

Checkpoint workflow (recommended after each stable milestone):

1. Commit current stable changes:

```powershell
git add -A
git commit -m "chore: stable checkpoint <short note>"
```

2. Create an annotated rollback tag:

```powershell
git tag -a stable-YYYY-MM-DD-HHMM -m "Stable checkpoint"
```

3. List available rollback points:

```powershell
git tag --list "stable-*"
```

4. Restore a previous stable state:

```powershell
git switch --detach <tag-name>
# or to move main back explicitly:
# git switch main
# git reset --hard <tag-name>
```
