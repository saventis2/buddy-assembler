# Improvement Backlog — Top 100

Created: 2026-07-07. Grounded in the repo state on `main` (post PR-15,
pre release-tag). This is a prioritization *menu*, not a commitment.
Items that touch `DEFERRED.md` scope fences are marked **[post-V1]**
and must follow the re-entry rule (scope-reopen PR updating
`DEFERRED.md` + `docs/product/V1_PRD.md` together).

Sections are roughly ordered user-visible → internal. Within a section,
higher items are higher leverage.

## A. Desktop presence & window UX (1–12)

1. System tray icon with pause / quiet / settings / quit menu — end
   users should never need F-keys to control the buddy.
2. Launch-at-Windows-startup opt-in toggle in the settings popout.
3. Single-instance guard so a double-launch doesn't spawn two buddies.
4. ~~Persist buddy position and monitor across restarts~~ — **already
   implemented**, not a gap: `AppState.set_window_state()`/
   `get_window_state()` persist `preferredScreen`/`lastWindowPosition`,
   `_restore_window_state()` runs in `_ready()`, and `_move_to_next_monitor()`
   (`F8`) persists after cycling
   (`apps/runtime-godot/scripts/autoload/app_state.gd:178-193`,
   `apps/runtime-godot/scripts/buddy_overlay.gd:203,610-620,725-736`).
5. Per-monitor DPI awareness plus a user-facing buddy size slider.
6. Optional click-through mode (buddy visible but never steals clicks).
7. Fullscreen / game / presentation detection → auto-hide or
   auto-quiet while the foreground app is fullscreen.
8. Quiet-hours schedule (time ranges where prompts are suppressed),
   layered on the existing quiet-strictness knob.
9. ~~Respect the Windows work area (taskbar) rather than raw screen
   bounds~~ — **already implemented**, not a gap: `_screen_rect()`
   returns `DisplayServer.screen_get_usable_rect()`, and
   `_update_window_roam()` uses it for `floor_y`/`min_x`/`max_x`
   (`apps/runtime-godot/scripts/buddy_overlay.gd:634-636,745-778`).
10. Fade in/out transitions for hide/show instead of popping.
11. Drag continuity across monitor boundaries during a single drag.
12. Split debug hotkeys (`F1`–`F12`) behind a `--debug` flag and move
    every user-relevant control into the `F10` settings popout UI.

## B. Buddy behavior & personality (13–24)

13. Cursor gaze — eyes/head subtly track the mouse pointer when idle.
14. Gentle reactions to user activity transitions (typing burst → calm
    watch pose), building on the existing productivity tracker states.
15. Time-of-day awareness: auto-select `night_pack` by clock, plus
    morning/evening greeting flavor.
16. More idle micro-animations (stretch, look-around, yawn) fed into
    the existing anti-repeat weighting in `BehaviorEngine`.
17. Rare capped-frequency "delight" events (a once-a-day surprise).
18. Curated personality presets (2–3) exposed from
    `behavior_profile.gd` instead of a single default.
19. Petting interaction variety: double-click, press-and-hold, and
    per-zone responses with distinct bond feedback.
20. Buddy sleep schedule that mirrors observed user session hours.
21. Expand the continuity digest (resume hint) with more variety and
    references to the previous session's notable events.
22. Visitor system depth: more visitor types and arrival scheduling
    tied to bond level.
23. Deeper bond-driven cadence/flavor shifts per the PR-09 intent —
    all data-driven from tuning tables in content, not code.
24. Seasonal/idle variation in face-emote rotation weights by mood.

## C. Interaction, prompts & support features (25–34)

25. Actionable break suggestions: snooze / dismiss / "done" buttons on
    the hint, with per-day caps tunable in settings (hourly cap exists).
26. Opt-in focus-session (pomodoro-style) mode with buddy celebration
    at completion, built on the focus-celebration hook.
27. Chat balloon polish: paced text reveal and inline emote glyphs.
28. One-click do-not-disturb from the tray icon (see item 1).
29. Digest mode: batch queued world prompts into one summary balloon.
30. Configurable prompt tone (encouraging / neutral / minimal).
31. Verify implementation parity with `FIRST_RUN_ONBOARDING.md` and add
    an interactive first-run tour of controls.
32. Undo affordance for accidental actions (e.g. skipped encounter).
33. Keyboard navigation + focus order in the settings popout.
34. Optional, off-by-default subtle SFX with a volume slider.

## D. World & economy systems (35–42)

35. Grow quest/NPC variety beyond the Plan-8 cast, driven entirely
    from pack manifests (no code changes per content add).
36. Economy balance report: export `box_open_stats` and recycle
    telemetry to CSV plus a summary view for tuning passes.
37. Subtly surface the low-value-streak protection ("pity") so reward
    pacing feels fair rather than random.
38. Home decor persistence with additional decor slots.
39. NPC dialogue pools with anti-repeat memory across sessions.
40. Encounter outcome flavor-text variety per reward profile.
41. Seasonal event packs (content-only, schema-driven, no engine work).
42. Local-only achievements / milestones journal.

## E. Content pipeline & assembler tooling (43–58)

43. Finish the PR-12 promise: relocate the 14 root Python scripts under
    `tools/importers/` (README still says "will move"; PROJECT_STATUS
    says PR-12 merged — reconcile and complete).
44. Break up `character_tooling_gui.py` (3,531 lines) into modules:
    UI shell, render orchestration, catalogue IO, export.
45. Replace hardcoded machine paths (`C:\Users\GGPC\...` appears in 10
    scripts and the runtime README) with a config file + first-run
    setup prompt.
46. Extract a shared importer library (path resolution, extracted-tree
    reading, logging) to kill duplication across the root scripts.
47. Headless CLI mode for every GUI operation so batch assembly is
    scriptable and CI-runnable.
48. Content-addressable export cache keyed on source hash so unchanged
    sprites are skipped on re-export.
49. Parallelize batch sprite/animation export with multiprocessing.
50. Structured `logging` with `--verbose/--quiet` instead of prints.
51. Progress reporting + resumable batch operations for long exports.
52. Golden-image regression tests for `render_character_frame.py`
    (assemble known combo → compare against checked-in reference PNG).
53. Pin `requirements.txt` (currently a single unpinned `Pillow` line)
    and add a dev-requirements file (ruff, pytest, mypy).
54. Add ruff + mypy CI job for all Python tooling.
55. Port `run_fixture_checks.py` to pytest with coverage reporting.
56. CI validates **all** pack manifests by glob — the workflow
    hardcodes `core_pack` and `night_pack`, so a new pack ships with
    zero CI validation today.
57. Validator UX: pin JSON Schema draft, self-validate the schema, and
    report errors with JSON paths + human-readable fix hints.
58. Promote provenance verification (`verify_content_promotion.py`)
    into a required CI gate for `content/` changes.

## F. Content schema & pack format (59–66)

59. Schema semver with a migration-notes doc required per version bump.
60. Per-asset integrity hashes in the manifest, verified at pack load.
61. Hot-reload content packs in a running debug session (dev QoL).
62. Require author / license / provenance fields in the manifest
    schema, aligning with the IP posture and PR-13 manifest.
63. Single-file compressed pack format (`.zip`) for distribution.
64. **[post-V1]** Grow the PR-14 non-Maple sample pack into a fully
    independent default content lane (explicit migration per
    `DEFERRED.md`, not incidental cleanup).
65. i18n-ready string tables in packs (ship `en` only; hooks first).
66. `minimum_runtime_version` field in manifests, enforced at load
    with a graceful "pack too new" fallback.

## G. Runtime code quality (67–76)

67. Split `character_renderer_2d.gd` (579 lines) into composition,
    z-ordering, and overlay concerns.
68. Adopt a GDScript test framework (gdUnit4 or GUT) to replace the
    bespoke per-scene `grep PASS` pattern; one runner, JUnit output.
69. Typed-GDScript pass across `runtime/` and `scripts/`; treat parse
    warnings as errors in the CI parse gate.
70. Move remaining magic numbers in behavior/economy weighting into
    the data-driven tuning tables PR-09 established.
71. Consistent error taxonomy: `push_warning` vs `push_error` policy,
    plus a small user-visible "content problem" indicator instead of
    fully silent fallback.
72. Rotating logs under `user://logs/` and a "copy debug info" button
    in the settings popout for support workflows.
73. `--safe` launch flag: skip external packs and load built-ins after
    repeated startup failures (extends the PR-03/04 durability story).
74. Save backup rotation — keep last N good save generations alongside
    the existing corruption recovery.
75. Settings export/import as a single JSON for support and migration.
76. Document the autoload/service dependency graph
    (`scripts/autoload`, `services`) in `docs/ARCHITECTURE.md`.

## H. Performance & efficiency (77–84)

77. Populate `PERF_BASELINE.md` from the exported build (10-min and
    multi-hour runs) — an open release-gate task, and the baseline all
    later perf work needs.
78. Idle tick throttling: drop process/render rate when no state or
    animation change is pending.
79. Suspend rendering when the buddy is hidden, fully occluded, or the
    session is locked.
80. Battery awareness: reduce update rate on battery power.
81. Add memory-ceiling assertions to `run_burn_in.ps1` multi-hour runs
    to catch slow leaks.
82. Texture-atlas packing for pack frames to cut draw calls and load
    time.
83. Startup-time budget measured in CI against the exported artifact.
84. Expose resolved-frame cache hit rate in the `F6` telemetry overlay
    to validate the invalidation policy.

## I. CI, release & distribution (85–93)

85. Execute `RC_SCENARIO_SUITE.md` against the exported Windows
    artifact and record results — the largest open pre-tag item.
86. Cache Godot binaries and export templates in CI (both workflows
    re-download 4.2.2 every run).
87. Plan a Godot 4.2.2 → current-stable upgrade as an explicit
    post-tag migration PR (renderer + window-flag behavior retest).
88. Pin GitHub Actions by SHA and add Dependabot for actions + Python.
89. Run the **full** headless test suite in CI — `runtime-smoke.yml`
    runs 3 scenes while 10+ test scenes exist (`CompanionDepthTest`,
    `EconomyTuningTest`, `PromptCadenceTest`, `WorldVarietyTest`, …)
    and only run via the local PowerShell script.
90. Nightly scheduled burn-in workflow (IdleProfile / burn-in recipe)
    with perf-trend artifacts.
91. **[post-V1]** Code signing implementation (decision is documented;
    for unsigned V1, ship SmartScreen guidance in user docs).
92. **[post-V1]** Distribution packaging: portable zip vs installer
    decision, plus a winget manifest.
93. **[post-V1]** Auto-update design doc — consider a check-only
    "update available" notice as the minimal middle ground.

## J. Docs, governance & repo hygiene (94–100)

94. Reconcile release-truth contradictions: `PROJECT_STATUS.md` says
    PR-00–15 merged while README/PR_PLAN still describe PR-12 moves as
    future — pick one truth source per the 2026-04-20 lesson.
95. Consolidate the timestamped 2026-04-20 spec docs into living specs
    with changelogs; move `Session-Log-2026-04-15.md` from repo root
    into `docs/DEVLOGS/`.
96. Add `LICENSE` and `CONTRIBUTING.md` (neither exists).
97. Move root analysis outputs (`action_frequency.csv`,
    `z_layer_frequency.csv`, `anchor_frequency.csv`, …) into
    `analysis/` or gitignore regenerable artifacts.
98. Add `.editorconfig` + pre-commit hooks (gdformat/gdlint for
    GDScript, ruff for Python).
99. Generate `docs/REPO_INDEX.md` from a script so it cannot go stale.
100. Publish a user-facing guide/FAQ (controls, privacy posture, save
     location, uninstall) separate from developer docs.

## Suggested first five — done

**85** (RC suite scaffolding), **77** (perf baseline scaffolding),
**56** (pack CI gap), **89** (run all tests in CI), and **1+12** (tray
icon + de-F-keying) were the first batch. Shipped: 56 (PR #23), 89
(PR #24), 85-scaffolding (PR #25), 77-scaffolding (PR #27), and
12-partial (PR #26 — Pause/Resume button; full F-key audit deferred,
tray icon itself descoped, needs Godot 4.3+). See
`IMPROVEMENT_BACKLOG_BUILD_SEQUENCE.md` for the dependency-ordered
sequence for everything after this — it explains why the next batch
is what it is instead of just re-sorting by leverage again.
