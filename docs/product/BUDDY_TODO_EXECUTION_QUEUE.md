# Buddy TODO Execution Queue

Updated: 2026-04-23 (Plan 10 saturation complete; Plan 11 started)
Source of truth: `BUDDY_V1_BUILD_PLAN_MILESTONE_EXECUTION_2026-04-20.md`

## How We Use This

- Work top-to-bottom.
- Do not start the next plan until the current plan's done gate is met.
- Keep commits small and scoped to one plan.
- After each completed plan:
  - update this file
  - update `MILESTONE_STATUS.md`
  - run the verification gate

## Completed Plans

- [x] Plan 1: Identity/Mood/Bond/Growth modular core + schema v2 migration
- [x] Plan 2: Economy foundation (curated items/currency/reward boxes)
- [x] Plan 3: World layer stub (home mode, NPCs, quests, encounters)
- [x] Plan 4A: Anti-repetition tuning (behavior/world cadence)
- [x] Plan 4B: Regression coverage for world/economy flow

## Active Queue

### Plan 5: Manual Desktop Verification Gate (Required Before Deeper Features)

Status: `done`

Tasks:
- [x] Run automated pre-check and create manual verification log
- [x] Add guided manual checklist logger (`run_manual_checklist.ps1`)
- [x] Add one-command gate runner (`run_plan5_gate.ps1`)
- [x] Add runtime snapshot export (`F1`) with prompt-cadence evidence metrics
- [x] Run interactive desktop checklist from `tests/SCENARIO_CHECKLIST.md` (TO track)
- [x] Verify monitor drag/clamp behavior in multi-monitor setup
- [x] Verify prompt/event cadence controls are verifiable (`F2/F7` + `/cadence`)
- [x] Verify progression feedback visibility (Bond Lv/XP/Growth + unlock hint)
- [x] Verify pack cycle evidence (`F9` slot x/y + telemetry pack id)
- [x] Close remaining pending checklist item: `BE2` quiet-hours behavior confirmation

Done gate:
- [x] Checklist completed and logged with pass/fail notes (PASS=16, FAIL=0, PENDING=0, Gate=PASS)
- [x] Any blocking UX bugs are either fixed or explicitly deferred

Current log:
- `PLAN5_MANUAL_VERIFICATION_LOG_2026-04-21.md`

### Plan 6: Companion Depth Foundation (Milestone 5 from V1 plan)

Status: `done`

Tasks:
- [x] Add stronger real-activity reaction weighting (focus/idle/late sessions)
- [x] Add continuity memory summary between sessions (short rolling digest)
- [x] Add settings knobs for reaction intensity and quiet-mode strictness
- [x] Add user-facing state hints without notification spam
- [x] Add tests for activity-reaction cadence and quiet-hour suppression
- [x] Add deterministic scheduler cadence regression (`low < normal < high`)
- [x] Add configurable prompt-frequency cadence guard with deferred world prompt surfacing
- [x] Add hourly productivity-hint caps by interaction intensity (`cozy/balanced/deep`)

Done gate:
- [x] User activity reactions are visible but non-intrusive (manual desktop confirm)
- [x] Quiet settings consistently suppress high-frequency prompts
- [x] Headless checks pass with new tests

### Plan 7: Economy Tuning Pass 2 (Drop Feel and Pacing)

Status: `done`

Tasks:
- [x] Tune rarity tables to preserve high-rarity excitement (kept high-rarity pulls rare; no inflation)
- [x] Add per-theme pull telemetry for balancing
- [x] Tune duplicate recycle values against box costs
- [x] Add minimum-value guarantee for low-value streak protection

Done gate:
- [x] Common pulls still feel useful
- [x] High rarity remains infrequent and meaningful
- [x] No economy exploit from duplicate recycle loop

### Plan 8: World Variety Expansion (Low-Risk Content Growth)

Status: `done`

Tasks:
- [x] Add 2-3 more NPCs with distinct quest flavor
- [x] Add additional quest categories (home upkeep, training, social)
- [x] Add optional encounter variants with different reward profiles
- [x] Add anti-repeat weighting across category groups, not only IDs

Done gate:
- [x] Short repeated sessions show visible content variety
- [x] Encounter skip path remains valid and non-punitive

Verification:
- [x] Added `WorldVarietyTest` and wired it into `run_headless_checks.ps1`

### Plan 9A: WZ Equipment Data Spine

Status: `done`

Tasks:
- [x] Extend canonical WZ bindings build to ingest Character equipment rows
- [x] Add gear slot mapping in canonical ingest output
- [x] Regenerate `item_bindings_full.csv/json` with gear rows included
- [x] Sync manifest from full bindings with add-missing path
- [x] Import item icons for full catalog rows (including gear)

Done gate:
- [x] `gear` category exists in canonical bindings with non-empty slot coverage
- [x] Manifest rows include the newly ingested gear catalog
- [x] Icon import reports `missing=0` for catalog-backed rows

### Plan 9C: Level/XP Consistency and Stat Allocation Integrity

Status: `done`

Tasks:
- [x] Add load-time progression reconciliation from XP -> level
- [x] Add stat-point reconciliation floor from earned-vs-spent points
- [x] Add XP progress fields (`into/need/max`) to telemetry + stats snapshot
- [x] Improve `/status` and Stats popout with next unlock + XP progress
- [x] Add/expand regression checks for progression reconciliation edge cases

Done gate:
- [x] Restart preserves coherent level/XP display without stale level lock
- [x] Manual + idle auto-assign modes remain deterministic
- [x] Headless checks pass with progression regression coverage

### Plan 9B: Inventory/Paper-Doll Expansion

Status: `done`

Tasks:
- [x] Expand paper-doll readout to grouped Maple-style slot families
- [x] Add group-level unequip actions for combat/style/accessory slots
- [x] Preserve item actions (use/equip/unequip) while improving slot visibility

Done gate:
- [x] Inventory window exposes broad equipped-slot state without switching scenes
- [x] Group controls can unequip currently equipped items safely
- [x] Headless checks pass after UI/equipment changes

### Plan 9D: Job/Drop Coupling Upgrade

Status: `done`

Tasks:
- [x] Carry `job_drop_bias` from progression manifest into profile state
- [x] Pass job context (`job_id`, `job_primary_stat`, `job_drop_bias`) into encounter drop rolls
- [x] Upgrade drop-pool weighting for job affinity, stat affinity, slot affinity, and category bias
- [x] Add regression coverage proving context-sensitive drop bias

Done gate:
- [x] Drop outcomes respond to job context beyond simple one-field affinity
- [x] Job/stat/category hints are integrated without breaking legacy drop tables
- [x] Headless checks pass with new economy regression case

### Plan 10A: Controlled WZ Ingest Pipeline

Status: `done`

Tasks:
- [x] Add category-scoped manifest sync (`--categories`) for incremental ingest
- [x] Upgrade batch runner with machine-readable run report output
- [x] Document one-command batch flow and review protocol

Done gate:
- [x] Ingest can be run in narrow category slices (e.g. `gear` only)
- [x] Batch run emits structured summary in `WZ_INGEST_LAST_RUN.json`
- [x] Workflow is documented for repeatable future batches

### Plan 10B: Content Expansion Batches (Execution)

Status: `done`

Tasks:
- [x] Run first controlled category ingest batch and review output (`gear`, dry-run, delta=0)
- [x] Run first non-dry-run bounded ingest with checks (`food,materials`, delta=0, checks pass)
- [x] Validate no regressions in inventory/equip/drop loops (headless gate pass)
- [x] Record structured run output in `WZ_INGEST_LAST_RUN.json`

Done gate:
- [x] First post-Plan-9 ingest batch lands clean with passing checks
- [x] No regressions in inventory/equip/drop loops

### Plan 10C: Next Expansion Source Pass

Status: `done`

Tasks:
- [x] Re-run canonical binding generation from current local WZ source set (`rows=11122`)
- [x] Confirm current source set saturation (`added_items=0` on dry-run sync)
- [x] Add multi-root canonical ingest support (ready for additional source bundles)
- [x] Validate source layout assumption (`Base.wz` acts as extracted super-root)
- [x] De-scope duplicate extraction path from active execution

Done gate:
- [x] Canonical ingest path is stable and repeatable for current local source scope
- [x] Active plan no longer depends on duplicate extraction assumptions

### Plan 11A: Runtime Depth from Existing Dataset

Status: `done`

Tasks:
- [x] Expand interactive event visibility so cadence/settings effects are obvious in TO
- [x] Add clearer progression surface (stat growth and unlock deltas) in runtime UI
- [x] Add inventory/equipment affordances for faster build iteration (filter/sort/quick actions)

Done gate:
- [x] Manual TO verification can clearly observe event/prompt cadence changes
- [x] Progression changes are readable without telemetry-only dependency
- [x] Headless checks pass after UI/runtime updates

### Plan 11B: TO Manual UX Verification Sweep

Status: `in_progress`

Tasks:
- [ ] Re-run Plan 5 gate with focus on new TO cadence/progression/inventory UX
- [ ] Capture operator notes on quick-action usability and sort cycling
- [ ] Log any polish defects as follow-up backlog items

Done gate:
- [ ] Manual gate passes with no blocker regressions
- [ ] Follow-up list is recorded and prioritized

### Plan 12A: Autonomous Mind (offline)

Status: `done`

Tasks:
- [x] Self-directed decision loop driven by mood modifiers
- [x] Learned per-subject feelings and preference-weighted choices
- [x] Journal, `/journal`, spoken thought, catch-up while closed
- [x] `MindServiceTest` wired into the required headless suite

Done gate:
- [x] Headless suite passes (14 tests)
- [ ] Manual desktop confirmation that thoughts and animations feel right

### Plan 12B: Thinking model via local Ollama

Status: `done` (pending a run against a real Ollama server)

Tasks:
- [x] Request builder, reply parser and sanitiser (`mind_thinker.gd`)
- [x] Async call from the overlay with silent fallback
- [x] Model `want` nudges the next decision
- [x] `MindThinkerTest` wired into the required headless suite
- [ ] Confirm wording and latency with `gemma3:4b` on a real Ollama server

### Plan 13: Town and conversation

Status: `in_progress` (see `PLAN13_TOWN_AND_CONVERSATION.md`)

- [x] A1 town as data
- [x] B1 conversation and self-chosen name
- [x] B2 graph memory
- [x] A2 town map window
- [ ] A3 changing town, things you leave
- [x] B3 talk changes the buddy
- [x] Part C, C1+C2 part 1: wants it saves for and buys, a day plan
- [ ] Part C, C1+C2 part 2: asking you for things, a Wants window, projects
- [ ] Part C: nightly reflection, making things, tastes and relationships

The unchecked items above are reshaped by Plan 14: the buddy now starts with
only a house and land and builds its own town, with no townspeople for now.

### Plan 14: Small beginnings

Status: `in_progress` (see `PLAN14_SMALL_BEGINNINGS.md`)

- [x] 1a Fast-forward tool (`tools/simulate_days.py`, `LifeSimTest`)
- [x] 1b House and land with discovery, behind a setting; known filter (`land_data.gd`, `LandLifeTest`)
- [x] 1c Fresh start with backup; the new world on by default (`fresh_start_if_due`, `FreshStartTest`, D-007)
- [x] Chat on the land: its own wording, measured on gemma3:4b and gemma3:12b (`LAND_CHAT_SYSTEM_PROMPT`, `mind_chat_test`)
- [x] 2a-1 World host and the visit, behind a setting that is off by default (`world_host.gd`, `visit_controller.gd`, `buddy_whereabouts.gd`, `WorldHostTest`)
- [x] 2a-2 The world host on by default (D-010), a journal line after the host was down, the host choosing the name (`_is_real_launch_args`, `note_still_world`, `note_name`, `WorldHostTest`)
- [x] 2b-1 Memory: short-term (`memory.today`) and long-term memory, the nightly pass, fading, the alone belief (`memory_service.gd`, `MemoryNightTest`, D-012)
- [x] 2b-2 Memory: recall into chat, the check on what it says, the land wording goes (`recall_land`, `check_reply`, `ChatCheckTest`, `ChatEval.tscn`, D-012)
- [x] 2c-1 Letters arrive: the mailbox, working out the console, the pull and reading, delivery through the host's inbox, the Letters window (`letter_service.gd`, `LetterTest`, 2026-11-19)
- [x] 2c-2 Writing back with the model: its first letter when it works out the console, answers from recalled memories checked before they go, letters into its memory
- [x] 3a The world's rules: materials, ways of working, tools, building needs, outcomes with reasons, the basics check (`world_rules.gd`, `WorldRulesTest`, 2026-11-19)
- [x] 3b-1 Things it meets and its own names: 15 things, named on the third meeting from the land data by its own seed (`land_data.gd` things, `mind.things`, 2026-11-19)
- [x] 3b-2 Real names held back: the check catches the real names of land things it has not learned (2026-11-19)
- [ ] 4 2.5D view on the desktop
- [ ] 5 Public world on Hardlight, nothing about you published
- [ ] 6 Learning by trying, study time by difficulty
- [ ] 7 Tools and making things
- [ ] 8 Designing and building, assembled in 3D from a modular kit
- [ ] 9 The console, part two: asking for and sending materials
- [ ] 10 Self-sheet nightly rules, things on its mind, interests
- [ ] 11 Library and encyclopedia research
- [ ] 12 Labelled model library for objects
- [ ] 13 Commerce and the market it runs
- [ ] 14 Mind view and library shelves
- [ ] 15 Things you leave appear on the land
- [ ] Later: watchdog that keeps the host running, with the move to Nexus (expected after a delivery due around 2026-12-05, no guarantee)

### Plan 12C: Things left for the buddy, visible places

Status: `not started`

See `PLAN12_AUTONOMOUS_MIND.md` ("Not yet built").

## Follow-Up Backlog (Populate During Testing)

- [x] Fix Plan 5 gate runner to auto-launch runtime + vertical-slice sessions
- [x] Fix default manual log path to repo `docs/product/` root
- [x] Add visible progression feedback on pet interactions (XP/level/unlock delta)
- [x] Add explicit `F9` pack-cycle chat feedback to confirm pack switching
- [x] Improve vertical-slice manual checks: `M` speech trigger + bracket-duration immediate validation
- [x] Improve vertical-slice key capture reliability for emote hotkeys
- [x] Re-run Plan 5 after gate-runner fix and capture updated log
- [x] Re-run Plan 5 once more and resolve `BE2` pending to close gate

## Verification Gate (Run After Each Plan)

Commands:

```powershell
pwsh -NoLogo -File apps/runtime-godot/tests/run_headless_checks.ps1
```

Must pass:
- parse check
- smoke floor-lock
- SaveStoreTest
- PackValidationTest
- WorldEconomyFlowTest
- CompanionDepthTest
- EconomyTuningTest
- PromptCadenceTest
- ProgressionConsistencyTest
- ManualVerificationReportTest
