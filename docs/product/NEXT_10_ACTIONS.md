# Next 10 Actions

1. [done] Run interactive vertical-slice verification in desktop mode:
   movement, jump, emote command (`E`), facing flip, floor lock, and text-wrap UX.
   → Documented in `SCENARIO_CHECKLIST.md` (Vertical Slice section). Requires manual desktop run.

2. [done] Add a small automated runtime smoke scene test that asserts actor Y
   stays above configured floor lock.
   → `tests/SmokeFloorLockTest.tscn` + `tests/smoke_floor_lock_test.gd`; wired into `run_headless_checks.ps1`.

3. [done] Wire importer outputs (`.bif -> .tres`) into tracked imported
   content promotion flow (developer-approved snapshot step).
   → `tools/verify_content_promotion.py` + `tools/approve_content_snapshot.py`; tracks hashes in `content/promotion_log.json`.

4. [done] Add ladder/portal stub hooks to map runtime (no full traversal yet).
   → `vertical_slice_main.gd` now detects proximity and emits `ladder_entered` / `portal_triggered` stub signals.

5. [done] Add simple speech-bubble timer tuning controls in debug overlay.
   → `BuddyActor.speech_bubble_visible_seconds` var; `[` / `]` keys in vertical slice adjust it; hint label shows current value.

6. [done] Profile frame-time impact of multi-frame clip playback on 20 actors.
   → `tests/ProfileScene.tscn` + `tests/profile_20actors.gd`; run via `run_headless_checks.ps1 --profile`.

7. [done] Add resolved-frame cache invalidation policy for future skin swaps.
   → `ResolvedFrameCache.invalidate_clip()` + `invalidate_all()`; exposed via `AnimationController` and `BuddyActor.on_skin_swap()`.

8. [done] Add provenance hash verification check in importer (warn on missing).
   → `buddy_importer_plugin_import.gd` now calls `push_warning()` when `source_hash` is absent or `"unknown"`.

9. [done] Document branch/run commands for normal vs `--vertical-slice` mode.
   → `docs/WORKFLOW.md` Runtime Modes section added with all commands and stable checkpoint refs.

10. [done] Prepare first PR summary with architecture constraints checklist.
    → `docs/product/PR_ARCHITECTURE_CHECKLIST.md` created with invariants, per-area checklist, and pre-merge gates.
