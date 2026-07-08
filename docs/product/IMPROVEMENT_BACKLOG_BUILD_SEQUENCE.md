# Improvement Backlog — Build Sequence

Companion to `IMPROVEMENT_BACKLOG_TOP_100.md`. That doc is a flat menu;
this one orders it so later work builds on earlier work instead of
duplicating it or landing on infrastructure that doesn't exist yet.

This is **waves, not a strict 1–98 order** — items within a wave are
mostly independent of each other and can build in any order or in
parallel; items are only pulled into a later wave when something in
an earlier wave is a real prerequisite (named explicitly below), not
just "thematically related."

## Wave 0 — Done

- **56** (pack validator CI glob) — shipped, PR #23.
- **89** (full headless suite in CI) — shipped, PR #24.
- **85** (RC scenario suite) — *scaffolding* shipped (guided runner,
  PR #25). Actual execution against the exported build is still a
  human-on-Windows task; no further agent work is possible here until
  that happens.
- **77** (perf baseline) — *scaffolding* shipped (log→table recorder,
  PR #27). Same caveat: real burn-in numbers still need a human run.
- **12** (de-F-key hotkeys) — *partially* shipped: Pause/Resume button
  landed and Quit/Quiet/Pack buttons were discovered already wired
  and documented (PR #26). Full F1–F12 audit/reclassification is
  explicitly deferred to a follow-up (see Wave 3).
- **4, 9** — turned out to already be implemented; corrected in the
  top-100 doc, not real work items.

## Wave 1 — Foundational, low-risk, unblocks everything else

Nothing here depends on anything not already in the repo. This is
the "next 10" batch.

- **94** — Reconcile release-truth contradiction (PROJECT_STATUS.md
  vs README/PR_PLAN.md re: PR-12). Pure docs, but it's a *prerequisite*
  for deciding whether **43** (relocate root scripts) is still needed
  at all — don't act on 43 until this lands.
- **76** — Document the autoload/service dependency graph. Pure docs,
  but de-risks every later runtime GDScript change (69, 67, 71, 72,
  73) by making the architecture legible before touching it.
- **96** — LICENSE + CONTRIBUTING.md. Cheap, independent, foundational
  governance.
- **53** — Pin `requirements.txt` + add `requirements-dev.txt`
  (ruff/pytest/mypy). Prerequisite for **54**.
- **54** — ruff + mypy CI job. Builds on 53 (self-contained: installs
  its own pinned lint deps in CI rather than hard-depending on 53's
  branch landing first, so the two can still ship in parallel).
- **98** — `.editorconfig` + pre-commit hooks (ruff for Python,
  gdformat/gdlint for GDScript). Pairs with 53/54; also a lower-risk
  substitute for jumping straight to a full typed-GDScript pass (69) —
  get the tooling in place before the big mechanical change.
- **86 + 88 — combined into one PR.** Cache Godot binaries/export
  templates in CI, and pin GitHub Actions by SHA + add Dependabot.
  Both edit the same two workflow files
  (`runtime-smoke.yml`, `content-validator.yml`); shipping them as two
  parallel PRs would just create a guaranteed merge conflict between
  our own work, which is exactly the failure mode this exercise is
  supposed to avoid.
- **57** — Validator UX improvements (pinned schema draft,
  self-validation, JSON-path error messages). Direct next step on top
  of 56, which just shipped.
- **45** — Replace hardcoded `C:\Users\GGPC\...` paths in importer
  scripts with a config/CLI-override mechanism. Prerequisite for **46**
  (shared importer library) and makes **52** (golden-image tests)
  meaningfully portable instead of tied to one machine's paths.

## Wave 2 — Builds directly on Wave 1

- **43** — Relocate root scripts under `tools/importers/`. Gated on
  **94** actually landing first (need the real ground truth on whether
  this already happened before moving anything).
- **46** — Shared importer library (path resolution, extracted-tree
  reading, logging). Gated on **45** (needs the config mechanism to
  exist first, or it's extracting duplication around a pattern that's
  about to change).
- **44** — Break up `character_tooling_gui.py`. Better after **46**
  exists so the split doesn't duplicate logic **46** is about to
  centralize.
- **47** — Headless CLI mode for every GUI operation. Benefits from
  both **45** (config) and **46** (shared lib) existing first.
- **52** — Golden-image regression tests for `render_character_frame.py`.
  Wants **45** landed so the test fixture isn't tied to a hardcoded
  machine path.
- **58** — Provenance verification as a required CI gate. Pairs with
  **57**'s validator-UX pass in the same area.
- **97** — Move root analysis CSVs into `analysis/` or gitignore them.
  Natural pair with **43**'s repo-hygiene move; sequence together.
- **69** — Typed-GDScript pass + warnings-as-errors in CI. Deliberately
  *not* in Wave 1 despite being "foundational" — it's a large,
  invasive, hard-to-visually-verify change across dozens of files (no
  Godot binary/display available to this agent workflow). Do it
  incrementally, after **98**'s lint tooling exists, and only once
  **76**'s architecture doc makes the blast radius legible. Candidate
  for a follow-up batch, scoped file-by-file rather than repo-wide.

## Wave 3 — Product / behavior / content feature work

Mostly independent of each other and of Wave 1–2 infra (beyond
"the repo builds and CI is healthy"), but with some internal ordering:

- **18** (personality presets) and **23** (data-driven tuning tables
  for bond/cadence) are the two "infrastructure" items *within* this
  wave — several other items read more naturally as building on them
  rather than needing later retrofitting: **13, 14, 16, 20, 24** (all
  flavor/animation variety) fit naturally on top of **18**'s presets;
  **19, 22, 40** (petting variety, visitor depth, encounter flavor)
  fit naturally on top of **23**'s tuning-table pattern.
  Not hard blockers — just sequence 18 and 23 first within this wave
  if picking work here.
- **25** (break-suggestion actions) before **26** (focus-session mode),
  which extends the same hook.
- **35** (quest/NPC variety) may want schema fields from **59**
  (schema semver) landed first if new manifest fields are needed —
  check before starting.
- Everything else in B/C/D (27–34, 36–42 minus the above) has no
  hard ordering constraint.

## Wave 4 — Bigger, riskier, or explicitly migration-gated

- **87** — Godot 4.2 → current-stable upgrade. Already called out in
  the top-100 doc as needing "explicit migration planning," not
  incidental work. This *gates* item **1** (tray icon — needs Godot
  4.3+'s `DisplayServer.create_status_indicator`, confirmed absent in
  4.2). Do not attempt 1 before 87.
- **68** — GDScript test framework migration (gdUnit4/GUT). Gated
  behind itself being worth the churn of migrating the tests just
  added in Wave 0 (56/89's batch) — reconsider once there are enough
  new ad hoc `grep PASS` tests that the migration pain is clearly
  worse than doing nothing.
- **82** (texture-atlas packing), **63** (zip pack format) — bigger,
  more invasive, harder to verify without visual/runtime access.
- **59, 60, 62, 65, 66** — schema changes. Sequence **59** (semver)
  first; the rest are additions that ideally land under a semver
  contract rather than before one exists.

## Wave 5 — Explicitly out of active sequencing

**64, 91, 92, 93** are marked `[post-V1]` in the top-100 doc and stay
fenced per `DEFERRED.md`'s re-entry rule — not sequenced here at all
unless that fence is reopened.

## What's next

Wave 1 is the next batch: 9 PRs covering the 10 items above (86+88
ship together). See the top-100 doc's "Suggested first five" section
for how the first batch was picked; this wave follows the same
leverage-per-effort logic, now filtered through "does it depend on
something we don't have yet."
