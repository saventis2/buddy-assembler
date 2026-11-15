# Repo Index

This document is a practical index of the current repo structure and responsibilities.

## Repo identity

`buddy-assembler` currently functions as a MapleStory character tooling repo.

The present implementation centers on:
- extracted `Base.wz` inspection
- character composition and rendering
- catalogue generation
- batch export and output validation
- source diffing and compatibility reporting

## Indexed file map

### Root docs

- `README.md`
  - Public-facing repo overview and entrypoints.
- `Character-Tooling.md`
  - Main operator guide, usage notes, and implementation status.
- `Session-Log-2026-04-15.md`
  - Development session log still present at repo root.

All importer/analysis scripts live under `tools/importers/`.

### GUI and orchestration

- `tools/importers/character_tooling_gui.py`
  - Desktop GUI entrypoint.
  - Hosts tabs for Start Here, Catalogue, Render, Batch Export, and Diff.
  - Imports and orchestrates the main backend tools.
- `tools/importers/character_tooling_core.py`
  - WZ-domain logic behind the GUI (action/frame/timeline detection, name and
    weapon-metadata lookups, GIF building, catalogue slot inference).
  - Importable without tkinter; unit-tested headlessly.
- `tools/importers/character_tooling_ops.py`
  - The batch-export operation (`run_batch_export`) extracted from the GUI's
    worker thread; headless entry point for backlog #47's CLI mode.

### Rendering and composition

- `tools/importers/render_character_frame.py`
  - Builds a single composed frame from selected body and equipment IDs.
  - Handles anchor solving, layer ordering, fallback selection, cap/hair policy, and metadata output.

### Catalogue and analysis

- `tools/importers/build_item_catalogue.py`
  - Scans extracted character asset trees.
  - Reads mapped names from `String\\String.wz\\Eqp.img.xml`.
  - Emits master and per-category catalogue CSVs plus summary/index files.

- `tools/importers/analyze_character_assets.py`
  - Extracts reverse-engineering facts from extracted character trees.
  - Summarizes actions, anchors, z-layers, delays, UOL references, category stats, and customization presets.

- `tools/importers/audit_dataset_metadata.py`
  - Audits metadata coverage across major extracted trees.
  - Produces category-level coverage and weapon metadata statistics.

### Validation and comparison

- `tools/importers/diff_character_assets.py`
  - Compares two extracted `Character.wz` trees.
  - Classifies XML changes as structural, timing, composition, or compatibility changes.
  - Optionally scans PNG differences as art changes.

- `tools/importers/alignment_audit.py`
  - Audits batch output metadata.
  - Checks jitter, fallback rates, anchor mismatch, z-volatility, unresolved assets, and skipped-frame reasons.

- `tools/importers/weapon_action_compatibility_report.py`
  - Builds weapon action support profiles directly from extracted weapon source folders.
  - Produces type-level action matrices and selected-weapon reports.

## Functional grouping

The repo currently groups naturally into four layers.

### 1. Source inspection layer

These scripts read extracted MapleStory data and turn it into structured information:
- `build_item_catalogue.py`
- `analyze_character_assets.py`
- `audit_dataset_metadata.py`
- `weapon_action_compatibility_report.py`

### 2. Composition layer

This script is responsible for actual frame generation:
- `render_character_frame.py`

### 3. Validation layer

These scripts help verify quality, consistency, and change impact:
- `alignment_audit.py`
- `diff_character_assets.py`

### 4. Operator interface layer

This is the user-facing orchestration surface:
- `character_tooling_gui.py` (tkinter shell)
- `character_tooling_core.py` (headless WZ-domain logic behind the GUI)
- `character_tooling_ops.py` (headless batch-export operation)

## Current workflow

1. Generate or load a catalogue
2. Apply item IDs into a build
3. Render a single frame to validate composition
4. Batch export an action or set of actions
5. Run audit and diff tooling as needed

## Structural observations

### Strong points

- Clear workflow from catalogue to render to validation
- Useful script separation by responsibility
- Inspectable outputs such as JSON, CSV, PNG, GIF, and summary markdown
- GUI already acts as a practical operator surface

### Weak points

- No strong package/module layout yet
- GUI is large and likely to become the main maintenance bottleneck
- Machine-specific default paths are still embedded in scripts
- Session-log style material currently lives at repo root
- Repo name is broader than the current implementation scope

## Suggested future structure

The importer/analysis scripts have already been relocated under
`tools/importers/` (PR-12 boundary cleanup). A later cleanup pass could
move further toward something like:

```text
buddy-assembler/
├─ README.md
├─ docs/
│  ├─ REPO_INDEX.md
│  ├─ ARCHITECTURE.md
│  ├─ WORKFLOW.md
│  └─ DEVLOGS/
├─ gui/
│  ├─ app.py
│  ├─ render_tab.py
│  ├─ catalogue_tab.py
│  ├─ batch_tab.py
│  └─ diff_tab.py
├─ tools/
│  ├─ render_character_frame.py
│  ├─ build_item_catalogue.py
│  ├─ analyze_character_assets.py
│  ├─ audit_dataset_metadata.py
│  ├─ alignment_audit.py
│  ├─ diff_character_assets.py
│  └─ weapon_action_compatibility_report.py
└─ outputs/
```

## Bottom line

This repo is already a functioning MapleStory tooling suite. The biggest remaining work is not basic capability; it is improving structure, naming clarity, onboarding, and public-facing polish.

## 2026-04-15 Companion Runtime Track

In addition to the MapleStory tooling suite, the repo now contains an initial
desktop companion product track:

- `apps/runtime-godot/`
- `packages/content-schema/`
- `packages/content-validator/`
- `docs/product/`

These directories are isolated so companion product work can proceed without
breaking existing tooling flows.
