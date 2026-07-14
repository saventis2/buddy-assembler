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
- backlog #44 split the former monolith: `character_tooling_gui.py` keeps the
  tkinter shell (widgets, tab layout, event handlers), while the WZ-domain
  logic lives in `character_tooling_core.py` and the batch-export operation in
  `character_tooling_ops.py` — both importable and testable without tkinter,
  and the intended call surface for backlog #47's headless CLI

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

---

# Godot Runtime: Autoload & Service Dependency Graph

This section documents `apps/runtime-godot/` — the shipping Windows desktop-buddy app (Godot 4.2). It covers the singleton (autoload) layer, the plain-object "service" layer, and how both relate to the scene-tree nodes under `runtime/`. It is derived by reading every script in `apps/runtime-godot/scripts/autoload/`, `apps/runtime-godot/scripts/services/`, and `apps/runtime-godot/project.godot` in full, plus enough of the calling code (`scripts/buddy_overlay.gd`, `scenes/vertical_slice/vertical_slice_main.gd`, `runtime/**`) to establish who calls whom.

## Autoload list (registration order)

`apps/runtime-godot/project.godot` has exactly one entry under `[autoload]`:

```ini
[autoload]

AppState="*res://scripts/autoload/app_state.gd"
```

| Order | Name | Script | Owns |
|---|---|---|---|
| 1 | `AppState` | `scripts/autoload/app_state.gd` | The only registered autoload in the project. Owns the three durable state dictionaries (`settings`, `profile`, `world_state`), loads/migrates/flushes them via `SaveStore`/`SchemaMigrations`, instantiates and holds the seven `services/*` objects, and exposes the single public API surface the rest of the app calls into (`record_interaction`, `apply_behavior`, `apply_loaded_pack`, `get_behavior_context`, `tick_world_events`, `open_reward_box`, window-state persistence, telemetry snapshotting, etc.). |

There is no load-order question to document beyond this — with a single autoload, "order" is trivially `[AppState]`. The one internal order that *does* matter is the `SERVICE_PATHS` dictionary inside `app_state.gd` (`_load_services()`), which is iterated to instantiate `identity → mood → bond → growth → economy → world → report` on `_ready()`. Since the services are stateless (see below) this iteration order has no observable effect today, but it is the closest thing to a "boot sequence" in the runtime.

## The "services" are not autoloads

Despite living in a directory that mirrors the autoload naming convention, none of the seven files under `scripts/services/` are registered anywhere in `project.godot`. Each one is:

- `extends RefCounted` (not `Node`), so it cannot be an autoload and has no `_ready()`/scene-tree lifecycle, no signals, and no persistent internal state between calls.
- Instantiated directly by `AppState._load_services()` via `load(path).new()` and stashed in a private `Dictionary` (`_services`), keyed by short name (`identity`, `mood`, `bond`, `growth`, `economy`, `world`, `report`).
- Called only through `AppState`'s private dispatch helpers (`_call_profile_service`, `_call_world_service`, `_call_service_with_fallback`) — nothing outside `app_state.gd` holds a reference to a service instance or imports a service script directly (confirmed by grep; the only other reference to `scripts/services/*.gd` in the whole app is from `apps/runtime-godot/tests/*.gd`).

Functionally they behave as **pure(-ish) transform functions**: every public method takes the relevant state `Dictionary` (and sometimes another dictionary, like `manifest` or another service's output) as an argument and returns a new `Dictionary` — they never reach into `AppState` themselves and never call each other. `AppState` is the only place mutation gets committed back into `profile` / `world_state`, and the only place `SaveStore.write_json` (via `flush()`) gets called.

| Service | File | Owns / responsibility | Public API (methods) | Reads |
|---|---|---|---|---|
| Identity | `identity_service.gd` | Personality trait profile, interests, trait history | `ensure_profile`, `record_interaction`, `record_behavior`, `get_context` | `profile` dict only |
| Mood | `mood_service.gd` | `dominant_mood` + mood modifiers (energy strain, social fulfillment, comfort, confidence) | `ensure_profile`, `apply_interaction`, `apply_behavior`, `get_context` | `profile` dict, plus a `quiet_mode` bool passed in by `AppState.is_quiet_hours_now()` |
| Bond | `bond_service.gd` | XP/level/trust progression, affection memory | `ensure_profile`, `apply_interaction`, `apply_behavior`, `get_status` | `profile` dict + `xp_per_level`/`max_level` sourced from `UnlockTable` (a `scripts/progression/` helper, not a service) |
| Growth | `growth_service.gd` | Growth stage + base stats (strength/dexterity/etc.), milestone flags | `ensure_profile`, `apply_interaction`, `apply_behavior`, `get_context` | `profile` dict, including fields (`total_interactions`, `bond_level`) that are *written by other services* — see "surprising" below |
| Economy | `economy_service.gd` | Wallet (crystals), inventory, reward-box tables, duplicate-recycle/streak protection, transaction log | `ensure_world_state`, `configure_from_manifest`, `grant_crystals`, `grant_item`, `open_reward_box`, `get_snapshot`, `list_reward_box_ids` | `world_state` dict + content-pack `manifest` dict |
| World | `world_service.gd` | Home/scene mode, NPC roster, quest/encounter rotation and scheduling, npc affinity | `ensure_world_state`, `configure_from_manifest`, `tick_world`, `complete_pending_quest`, `resolve_pending_encounter`, `get_snapshot`, `set_home_mode` | `world_state` dict + `manifest` dict + `profile.dominant_mood` (passed in by `AppState`) |
| Report | `report_service.gd` | "While you were away" summary text + continuity digest line generation | `generate_while_away_report` | `profile` dict + `world_state` dict + `now_unix` |

## Dependency map

```
project.godot [autoload]
  └─ AppState (Node, singleton)
       ├─ owns: settings, profile, world_state (Dictionaries), _services (Dictionary of RefCounted instances)
       ├─ preloads (static helper classes, not services):
       │    ├─ SaveStore              (scripts/persistence/save_store.gd)      — atomic JSON read/write, quarantine-on-corruption
       │    ├─ SchemaMigrations       (scripts/persistence/schema_migrations.gd) — version constants + migrator callables
       │    └─ UnlockTable            (scripts/progression/unlock_table.gd)    — bond-tier/unlock JSON cache, static funcs
       └─ instantiates + calls (never the reverse; services never call AppState or each other):
            ├─ IdentityService  (services/identity_service.gd)
            ├─ MoodService      (services/mood_service.gd)
            ├─ BondService      (services/bond_service.gd)
            ├─ GrowthService    (services/growth_service.gd)
            ├─ EconomyService   (services/economy_service.gd)
            ├─ WorldService     (services/world_service.gd)
            └─ ReportService    (services/report_service.gd)

scripts/buddy_overlay.gd  (BuddyOverlay.tscn root node — NOT an autoload, the shipping scene's controller)
  ├─ calls AppState.* directly (~90 call sites: record_interaction, apply_behavior, get_behavior_context,
  │    tick_world_events, get_world_snapshot, open_reward_box, set_home_mode, flush, settings r/w, etc.)
  ├─ preloads its own set of RefCounted helper classes that AppState never touches:
  │    BehaviorEngine, ContentLoader, EncounterScheduler, ChatCommandRouter, ProductivityTracker,
  │    PromptCadence, ManualVerificationReport, UnlockTable
  └─ owns/drives one runtime/ node directly: ChatBalloon (runtime/ui/chat_balloon.gd)

scenes/vertical_slice/vertical_slice_main.gd  (dev/test scene — never registered as run/main_scene by default)
  ├─ does NOT reference AppState, or any autoload/service, at all
  └─ drives the runtime/actor + runtime/buddy node tree directly:
       BuddyActor → StateMachine, MovementController, AnimationController,
                    CharacterRenderer2D, BuddyBrain, SpeechBubble
       + VisitorController (spawned at runtime), TestMap (runtime/world)
```

Everything under `runtime/actor/`, `runtime/buddy/`, and `runtime/world/` (`BuddyActor`, `ActorStateMachine`, `MovementController`, `AnimationController`, `CharacterRenderer2D`, `ResolvedFrameCache`, `CharacterAssembler`, `BuddyBrain`, `BuddyCommandBridge`, `VisitorController`, `CollisionMapRuntime`, `TestMap`) has **zero references to `AppState` or to any `scripts/services/*` class** — confirmed by grep across the whole `apps/runtime-godot/` tree. `runtime/ui/chat_balloon.gd` is the one `runtime/` script used by the shipping scene (`buddy_overlay.gd` owns a `ChatBalloon` child directly); the rest of `runtime/` is currently only exercised by the vertical-slice dev scene.

## Circular / surprising dependencies

- **Only one true autoload.** The "services" directory strongly suggests parallel singletons, but none of the seven are registered in `project.godot`. They are stateless `RefCounted` value-transform objects, private to `AppState`. Anyone assuming `EconomyService.grant_crystals(...)` etc. is reachable as a global singleton (the way `AppState` is) will be wrong — it's only reachable through `AppState`'s dispatch helpers.
- **No cycles among services** — by construction, since none of them call `AppState` or each other, a cycle isn't currently possible. All cross-service coordination (e.g. an interaction awarding bond XP *and* mood shift *and* crystals) happens by `AppState.record_interaction()` calling multiple services in sequence and threading `profile`/`world_state` through each call.
- **Implicit ordering coupling in `AppState`.** `growth_service.gd._recompute_stage()` reads `profile.total_interactions` and `profile.bond_level`, both of which are written earlier in the *same* `AppState` method (`record_interaction()` increments `total_interactions` before calling identity/bond/mood/growth in that literal order; `apply_behavior()` calls bond before growth). This isn't a cycle, but it is a hidden ordering dependency: reordering the `_call_profile_service(...)` chain in `app_state.gd` would silently change `growth_stage` derivation. This lives entirely in prose/comments today, not in any type system — worth flagging for anyone touching `record_interaction`/`apply_behavior`.
- **Two parallel character-presentation pipelines that never meet.** The shipping overlay (`scripts/buddy_overlay.gd`, driven from `BuddyOverlay.tscn`, the actual `run/main_scene` target via `LaunchRouter.tscn`) does its own inline sprite/frame composition and never touches `runtime/actor/character_assembler.gd`, `CharacterRenderer2D`, `ActorStateMachine`, etc. Those `runtime/actor` + `runtime/buddy` classes are instead exercised by `scenes/vertical_slice/VerticalSliceMain.tscn`, a separate dev/test scene reachable only via the `--vertical-slice` launch arg (`scripts/launch_router.gd`). The two pipelines duplicate a fair amount of intent (state machine, animation, movement) without sharing code, and the vertical-slice path has no connection to `AppState`/persistence at all — a buddy driven through the vertical slice does not read or write `settings`/`profile`/`world_state`. This is a plausible follow-up-refactor candidate but is out of scope here (see PR queue reference below).
- **Two separate "pure helper" namespaces that look similar but are wired differently.** `scripts/services/*` are reached exclusively through `AppState._services`. A second family of RefCounted helpers — `scripts/behavior/`, `scripts/content/`, `scripts/encounters/`, `scripts/interaction/`, `scripts/progression/unlock_table.gd`, `scripts/utility/*` — are reached exclusively through direct `preload()` consts in `scripts/buddy_overlay.gd`, bypassing `AppState` entirely (except `UnlockTable`, which both `AppState` and `buddy_overlay.gd` preload independently). Nothing enforces the distinction between "goes through AppState" and "goes through buddy_overlay directly"; it's purely a product of who happened to write the call site.

## State vs. behavior/presentation boundary

- **`scripts/autoload/` (`AppState`) owns durable state and cross-cutting orchestration.** It is the single source of truth for `settings`, `profile`, and `world_state`, the only place that persists to disk (`SaveStore.write_json` via `flush()`), and the only place that sequences multi-service updates for a given player action. It has no scene presence of its own beyond being a `Node` autoload — it draws nothing and has no `_process`/`_physics_process` visual behavior.
- **`scripts/services/`** own **domain-specific state *shape* and transform rules** (how bond XP maps to level, how a reward box roll works, how quests rotate) but own no storage and no scene presence — they are pure functions over dictionaries owned by `AppState`.
- **`scripts/buddy_overlay.gd`** is the presentation/behavior *and* orchestration root for the shipping app: it owns the actual `Node2D`/`Window`/`Timer` scene tree for the overlay, translates player input and timers into calls on `AppState`, and renders the result (sprite state, chat window, settings window, telemetry HUD) — it is the boundary object between "world state" (AppState) and "what's on screen."
- **`runtime/actor/`, `runtime/buddy/`, `runtime/ui/`, `runtime/world/`** own scene-tree-level presentation and physics/animation behavior only (movement, state machine transitions, sprite assembly/rendering, speech-bubble display, collision/map data) and are state-agnostic with respect to `AppState` — none of them read or write `settings`/`profile`/`world_state`. `runtime/ui/chat_balloon.gd` is invoked by the shipping scene; the rest of `runtime/` is currently exercised only by the vertical-slice scene, which has no persistence or `AppState` wiring at all.

In short: **`autoload/` + `services/` = state + rules, headless**; **`runtime/*` = scene-tree presentation/physics, stateless with respect to save data**; **`scripts/buddy_overlay.gd` = the one script currently bridging the two**, for the shipping overlay only.
