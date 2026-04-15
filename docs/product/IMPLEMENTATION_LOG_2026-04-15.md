# Implementation Log - 2026-04-15

## Recorded

- Execution plan captured in `EXECUTION_PLAN.md`.
- Product decisions locked in `DECISION_REGISTER.md`.
- V1 product spec captured in `V1_PRD.md`.

## Implemented (initial scaffold)

- Runtime scaffold directory: `apps/runtime-godot/`
- Content schema contract: `packages/content-schema/`
- Local content validator: `packages/content-validator/`
- Overlay scene with drag/click interaction loop
- Deterministic weighted behavior engine with cooldowns
- Save/settings/profile/world-state persistence bootstrap
- Quiet-hours and event-frequency hooks in behavior context
- Multi-monitor window restore/clamp and monitor cycling
- Encounter scheduler with cooldowns and event budgets
- Unlock-table wiring tied to bond level progression
- Content pack loader + second test pack (`night_pack`)
- CI workflow for manifest validation + fixture checks
- Headless runtime check script (`apps/runtime-godot/tests/run_headless_checks.ps1`)
- Godot 4.6.2 installed via winget and headless runtime check executed
- Productivity utility tracker added (focus celebration + break suggestions)
- Runtime visuals now support pack-driven character sprite maps (`visual.sprites`)
- Added sprite exporter pipeline from `combinations/last_combo.json`
- Added Maple-agnostic vertical slice module under `apps/runtime-godot/`:
  - internal content resource types (`ActorDefinition`, `AnimationClip`, etc.)
  - BIF converter stub and Godot importer plugin scaffold
  - imported demo actor resources and test map scene
  - launch router with `--vertical-slice` runtime flag
- Added resolved-frame cache in runtime animation controller for clip playback.
- Fixed runtime character orientation:
  - actor now flips horizontally with corrected direction mapping
    (move right -> face right, move left -> face left).
- Fixed critical vertical-slice floor regression:
  - explicit actor/floor collision layer setup
  - foothold-derived floor lock fallback to prevent sink-through failures.
- Restored jump + animation behavior in vertical slice:
  - grounded fallback now feeds movement and state machine.
  - prevents false permanent jump state that caused non-loop still-frame lock.
- Fixed jump-vs-walk priority:
  - jump state now overrides walk immediately on jump start and upward motion.
- Fixed emote command visibility:
  - `E`-triggered `play_emote(\"happy\")` now holds emote state briefly instead of
    being immediately replaced by idle/walk.
- Fixed top instruction readability:
  - hint label now wraps within the window and uses multiline wording.

## Next

- Run Godot vertical slice in-editor and verify interaction loop.
- Tune behavior weights using dogfood feedback.
- Add richer art/animation assets for unlocked actions.
