# Buddy TODO Execution Queue

Updated: 2026-04-21 (Plan 5 gate passed)
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
- ManualVerificationReportTest
