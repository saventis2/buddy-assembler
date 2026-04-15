# Architecture Overview

This document describes how the current repo fits together, what the main data flow is, and where the structural pressure points are.

## High-level purpose

The repo is currently a MapleStory character tooling suite built around extracted `Base.wz` assets.

Its core responsibilities are:
- inspect extracted source assets
- map item and metadata relationships
- compose character frames from selected IDs
- export animation artifacts
- validate output quality and compatibility
- compare extracted trees across versions

## High-level architecture

```text
Extracted Base.wz
   |
   +--> catalogue / metadata analysis
   |       |
   |       +--> CSV / JSON / markdown reports
   |
   +--> single-frame renderer
   |       |
   |       +--> composed PNG + metadata JSON
   |
   +--> batch export via GUI workflow
   |       |
   |       +--> frame sequence + GIF + sprite sheet + batch summary JSON
   |
   +--> validation layer
           |
           +--> alignment audit reports
           +--> tree diff reports
           +--> weapon compatibility reports
```

## Main modules and their roles

### `character_tooling_gui.py`

This is the operator-facing shell.

Responsibilities:
- guide the user through the workflow
- collect parameters and IDs
- call backend tools
- preview rendered outputs
- manage batch export controls and audit triggers

Current note:
- this file is already large and is acting as both UI layer and orchestration layer

### `render_character_frame.py`

This is the main composition backend.

Responsibilities:
- load body/head/face/hair/equipment assets
- resolve action and frame selections
- apply compatibility fallbacks
- solve world anchor placement
- normalize some equipment conflicts such as longcoat overriding coat or pants
- enforce cap/hair behavior and off-hand cleanup rules
- emit composed PNG plus metadata JSON

This is the most logic-dense script in the repo.

### `build_item_catalogue.py`

Responsibilities:
- scan character categories under extracted assets
- read name mappings from the string tables
- emit searchable catalogue CSV outputs
- summarize category coverage

This is the main lookup/indexing layer for item selection.

### `analyze_character_assets.py`

Responsibilities:
- reverse-engineering style analysis of asset structure
- summarize actions, anchors, z-layers, delays, UOL references, and preset mappings
- produce structured outputs for future understanding or tooling design

This is primarily a discovery and research script.

### `audit_dataset_metadata.py`

Responsibilities:
- check extracted tree presence
- inspect metadata availability and coverage
- summarize equipment metadata fields and weapon distributions

This is a dataset quality and coverage script.

### `diff_character_assets.py`

Responsibilities:
- compare two extracted `Character.wz` trees
- classify XML changes into structural, timing, composition, and compatibility categories
- optionally detect PNG changes as art changes

This is the version comparison and impact classification layer.

### `alignment_audit.py`

Responsibilities:
- read batch summary output
- audit frame metadata completeness
- measure jitter and fallback rates
- detect anchor mismatch, z-layer volatility, and skip-reason patterns
- emit JSON, CSV, and markdown findings

This is the output validation layer.

### `weapon_action_compatibility_report.py`

Responsibilities:
- inspect weapon source folders directly
- determine which actions a given weapon supports
- build type-level action matrices

This acts as a compatibility knowledge source for weapon behavior.

## Current workflow in practice

### 1. Catalogue stage

The user generates or loads a catalogue so item IDs can be searched and applied by category.

Primary output examples:
- `catalogue_all.csv`
- per-category catalogue CSVs
- catalogue summary JSON

### 2. Render stage

The user selects or applies a build and renders one frame.

Primary output examples:
- single composed PNG
- metadata JSON with draw order, anchors, unresolved nodes, and fallback behavior

### 3. Batch export stage

After a frame looks correct, the user exports frame sequences and optional GIF/sprite-sheet outputs.

Primary output examples:
- PNG sequence
- per-frame JSON metadata
- GIF
- sprite sheet
- batch summary JSON

### 4. Validation stage

The user runs audit or diff tools to inspect compatibility and quality.

Primary output examples:
- alignment audit JSON, CSV, and markdown
- character diff JSON and CSV
- weapon compatibility reports

## Data contracts that already exist

Even though the repo is not packaged as a formal application yet, some strong informal contracts already exist.

### Render contract

`render_character_frame.py` emits:
- a composed PNG
- optional metadata JSON

That JSON is then consumed or inspected by higher-level workflows.

### Batch summary contract

The batch export path emits summary JSON files that the alignment audit expects to read.

This is important because it means the repo already has a reusable machine-readable intermediate layer.

### Catalogue contract

The catalogue builder emits predictable CSV and JSON outputs that the GUI can load and search.

## Structural pressure points

### 1. Large GUI orchestration file

The GUI currently owns a lot of behavior:
- UI widgets
- workflow logic
- validation behavior
- preview behavior
- backend orchestration

That makes it the likely future bottleneck.

### 2. Embedded machine-specific defaults

Several scripts currently default to local Windows paths.

That is convenient for one setup, but weak for:
- portability
- onboarding
- future automation
- reproducibility

### 3. Repo identity mismatch

The implementation is strongly MapleStory-specific, while the repo name is broader.

That is not fatal, but it can confuse users and future contributors.

### 4. Flat file layout

The current flat root structure is fine for initial development, but it is already large enough that logical grouping would help.

## Recommended next refactor direction

### Near-term

- add public-facing docs
- keep scripts where they are
- reduce confusion with better repo descriptions
- add a dependency file if missing
- move working notes into a docs/devlogs area

### Medium-term

Split into folders by responsibility:
- `gui/`
- `tools/`
- `docs/`
- `outputs/` or a gitignored analysis folder

### Longer-term

Extract shared helpers into reusable modules, for example:
- asset path helpers
- XML parsing helpers
- metadata readers
- output/report writers
- shared model types for batch summary or render metadata

## Recommended cleanup priorities

1. keep the current behavior stable
2. improve docs and onboarding
3. remove hardcoded machine paths
4. modularize the GUI
5. introduce a clearer package layout

## Bottom line

The repo is already more than a prototype script dump. It has a real toolchain shape, a usable desktop operator surface, and meaningful machine-readable outputs.

The biggest remaining work is architectural housekeeping and public-facing polish, not proving the concept.
