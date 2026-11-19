# Council of 10 — Next Actions Review

**Date:** 2026-05-03  
**Scope:** What are the correct next actions to reach V1 release?  
**State at review:** Plan 11B in_progress, all prior plans done, no exported build yet, PERF_BASELINE.md all TBD.

---

## Context Brief

- Plans 1–11A all done and headless-verified.
- Plan 11B (TO Manual UX Verification Sweep) is in_progress — tasks are defined but no manual run has been executed yet.
- `export_presets.cfg` has `export_path=""` — no Windows export artifact exists.
- `PERF_BASELINE.md` release table is all TBD.
- `RC_SCENARIO_SUITE.md` (9 scenarios) has never been run against an exported build.
- `WZ_ICON_GAPS_BY_ITEM_ID.csv` exists — some icon gaps may be present.
- Godot is installed at WinGet path; launchers now exist in repo root.
- Two launchers created this session: `Launch Buddy.bat` and `Launch Buddy Dev.bat`.

---

## Solo Pass — Each Persona

### 1. Mara Voss — CTO / Delivery Absolutist

**Review:**
The project has strong process hygiene — headless gates, verification logs, decision register. But we are missing the one thing that matters: a built, runnable Windows artifact that a stranger could download and verify. Every gate we've run is editor-play truth, not exported-build truth. The `WINDOWS_RELEASE_CHECKLIST.md` exists and is clear. Nobody has followed it yet. Plan 11B manual sweep also has zero logged evidence.

**Verdict contribution:** Don't ship. Two concrete things block a tag: (1) Plan 11B has no sign-off log, (2) no exported artifact exists so RC scenarios and perf baseline can't run.

**Demands:** Owner, date, rollback pointer. The tag must reference a specific artifact SHA256.

---

### 2. Dr. Inez Kade — Head of AI / Model Realist

**Review:**
The behavior system is deterministic and well-tested by headless checks. The CHAOS_COUNCIL roundtable (2026-04-21) accepted 30+ proposals — I need to know which of those were implemented vs deferred. The risk is that the council review documents intent but the code only partially reflects it. Specifically: tone matrix by mood × bond tier (Session 3 Row 1), memory tags per user turn (Session 4 Row 2), anti-repetition n-gram suppression — are these in the code or aspirational?

**Verdict contribution:** Hold. Before tagging, audit the CHAOS_COUNCIL accepted items against actual code and create a one-page "accepted vs shipped" delta. Unshipped accepted items must be explicitly filed as post-V1 backlog, not left ambiguous.

---

### 3. Ren Ito — Principal Architect / Complexity Assassin

**Review:**
Architecture is clean with clear boundaries: runtime, content, importer. The Maple83 dependency contract is explicitly documented in PROJECT_STATUS.md and fenced. The deferred list is honest. One structural gap: `export_presets.cfg` has `export_path=""` — this means the CI export step cannot produce a deterministic artifact path. This is not a design problem, it's an incomplete config. Fix is one line.

The two new `.bat` launchers are good friction reduction. No blocker there, but the fallback detection logic should be smoke-tested.

**Verdict contribution:** Ship-with-fixes. One config fix (export_path), then go.

---

### 4. Samira Ndlovu — Head of Data Engineering / Data Skeptic

**Review:**
`item_bindings_full.csv/json` has `rows=11122`. `WZ_INGEST_LAST_RUN.json` records the last ingest. `WZ_ICON_GAPS_BY_ITEM_ID.csv` and `WZ_ICON_MISSING_REPORT.csv` both exist — I want to know if missing icons cause visible blank tiles or graceful fallback. The content schema has a fallback cascade (`load_with_fallback`) which is proven by sample_pack. The data spine looks sound. My concern is runtime visibility of icon gaps: does the companion inventory silently show empty squares, or is there a clear placeholder?

**Verdict contribution:** Ship-with-fixes. Verify the icon-missing fallback renders a placeholder (not a blank/error node) at runtime before tagging.

---

### 5. Tomo Grin — Head of MLOps / Deployability Enforcer

**Review:**
CI runs `validate-content` and headless parse/smoke checks on every commit. That's solid. But the export step in CI (`export_presets.cfg`) has a blank `export_path`. Either CI is not actually building the export, or it's writing to a temp path that's never archived as a release artifact. Either way: the release rehearsal path requires a real exported `.exe`. This must be set and tested. Also, the SHA256SUMS referenced in `WINDOWS_RELEASE_CHECKLIST.md` — there is no script to generate it. Someone will do it manually, which means it might be skipped or wrong.

**Demands:** Set export_path, add a one-command `make-release.ps1` that: exports, generates SHA256SUMS, writes the `WZ_INGEST_LAST_RUN.json` snapshot pointer.

**Verdict contribution:** Don't ship until export path is set and a rehearsal artifact has been produced and tested.

---

### 6. Elena Park — Head of Platform / Cost and Capacity Hawk

**Review:**
PERF_BASELINE.md is completely empty. The burn-in recipe is documented and the script exists. This is purely an execution gap, not a design gap. The 600-second run takes 10 minutes; the 10800-second run takes 3 hours. One of those must be run before the tag. The 600s run is the fast gate — run it first. If mem drift is clean there, schedule the 3h run overnight.

**Verdict contribution:** Don't ship. The perf table must have at least the 600s row filled before tagging. This is a 10-minute task.

---

### 7. Asha Qadir — Head of Security / Paranoid Professional

**Review:**
`NON_MAPLE_CONTENT_PROOF.md` is clear and the provenance model is documented. No binary WZ/NX assets in the repo. The content pack fallback cascade is good defensive design. My concerns are narrow: (1) The companion accepts typed chat input — are there any command injection paths through slash commands into system operations? The command router should only trigger internal GDScript state, never shell. (2) `user://` save paths — Godot handles these safely by design. (3) The `.bat` launchers don't sanitize REPO path — if someone puts the repo in a path with spaces, `%REPO%` expansion in batch could break. The current batch uses `set "REPO=%~dp0"` and wraps in quotes later, so this is actually safe.

**Verdict contribution:** Ship-with-fixes. Verify slash command router cannot trigger OS-level side effects (should already be true for a deterministic GDScript router, but confirm).

---

### 8. Jonah Reed — Head of Reliability / Failure Cartographer

**Review:**
The save system has atomic writes, corruption recovery (PR-03), and schema versioning. The content fallback cascade protects against bad pack loads. The Plan 5 log shows PG3 (restart preserves progression) initially failed, then was fixed and reached PASS=16. That's good process. My concern: the `RC_SCENARIO_SUITE.md` has Scenario 8 (corrupted settings recovery) — this specifically tests the corruption path on an exported build. Until that scenario is run on the actual `.exe`, we have editor-play evidence only for the recovery path.

**SLO framing:** V1 should degrade gracefully when: (1) save file corrupted, (2) pack missing, (3) monitor layout changed, (4) Godot update changes user:// path. Scenarios 7 and 8 cover (1) and (2). (3) is covered by multi-monitor drag test (MM1-3 in Plan 5). (4) is not tested — acceptable for V1 if documented.

**Verdict contribution:** Ship-with-fixes. RC Suite Scenarios 7 and 8 must pass on exported build.

---

### 9. Priya Deshmukh — Head of Evaluation / QA Prosecutor

**Review:**
Headless checks pass: parse, smoke, save-store, pack validation, world/economy flow, companion depth, economy tuning, prompt cadence, progression consistency, manual verification report. That's a good automated base. But the RC_SCENARIO_SUITE.md 9-scenario suite has zero evidence rows — the results table is blank. This is the primary QA gate for the exported build and it has not been executed. Plan 11B manual sweep also has no log yet. These are not optional: they are the stated release gates in MILESTONE_STATUS and WINDOWS_RELEASE_CHECKLIST.

**Golden set gap:** The CHAOS_COUNCIL proposed a "response rationale debug panel" (Session 3 Row 10) — was this implemented? If so, it should be used during the Plan 11B sweep to capture evidence of response quality, not just functional behavior.

**Verdict contribution:** Don't ship. RC Suite evidence and Plan 11B log are required before tag.

---

### 10. Lucas Meyer — Head of Developer Experience / Friction Killer

**Review:**
Previously: starting the buddy required opening PowerShell, navigating to the repo, and typing a multi-part command. This session added `Launch Buddy.bat` and `Launch Buddy Dev.bat` in the repo root — that's correct. A new contributor (or the user returning after a gap) can now double-click to start. The Godot fallback path detection using `where godot` + WinGet fallback is robust.

One remaining friction point: the `run_plan5_gate.ps1` requires opening PowerShell and navigating to the tests directory. Add a `Run Tests.bat` at the repo root that calls it. Also: the SCENARIO_CHECKLIST in tests/ is not linked from the root README — add a one-liner pointer.

**Verdict contribution:** Ship-with-fixes. Add `Run Tests.bat` at repo root. Update root README with launch instructions.

---

## Challenge Round

**Tomo challenges Ren:** "You said export_path is one line fix — but if CI is already exporting to a temp path and nobody noticed it was blank, that means CI export may be broken or skipped entirely. It's not just a config line. It's a test of whether the export pipeline actually works."

**Ren responds:** "Fair. The fix is still one config line but the acceptance test must be: run the export locally, confirm the .exe launches, then check CI produces an artifact. Two steps, not one."

**Elena challenges Priya:** "You say don't ship without RC Suite. But the RC Suite takes 20 minutes on an exported build and the exported build doesn't exist yet. These are sequenced, not parallel. The critical path is: export → RC suite → perf 600s. Don't let perfect sequencing block the start."

**Priya responds:** "Agreed on sequencing. The blocker is that nobody has started the export step. Once export works, the 20-minute RC suite can follow immediately."

**Lucas challenges Mara:** "You want owner and date. Who is the owner? This is a solo project. The date is 'when the user decides to run the checklist.' Don't add process overhead that doesn't apply."

**Mara responds:** "Fair. Owner = the user (J). Date = self-imposed. The point is: write it down or it stays perpetually in_progress. Pick a date, even if it's 'this week.'"

---

## Synthesis

The headless test suite is solid and all development plans are done. The only gap is **execution of the release rehearsal sequence**. Nothing requires new code. The blockers are:

1. Plan 11B manual log (run the buddy, fill in the checklist)
2. Windows export artifact (set export_path, export from Godot, or use CI artifact)
3. RC Scenario Suite run against that artifact (20 min)
4. Perf baseline 600s run (10 min, using `run_burn_in.ps1 -Duration 600`)
5. CHAOS_COUNCIL accepted-vs-shipped delta (30-min audit to close ambiguity)

---

## Verdict: **Ship-with-fixes**

All blocking items are execution tasks, not code changes.

---

## Top 3 Risks

1. **No exported artifact exists** — export_path is blank; RC Suite and perf baseline cannot run until an `.exe` is in hand. This is the critical path item.
2. **PERF_BASELINE.md is all TBD** — release gate explicitly requires 600s row filled before tag; 10-minute task that hasn't been done.
3. **CHAOS_COUNCIL accepted items vs code delta is unknown** — 30+ proposals were accepted; unclear which are in code vs aspirational. Risk of shipping with a gap between documented intent and actual behavior.

---

## Missing Info

- Is `export_path` in `export_presets.cfg` intentionally blank (CI sets it) or an oversight?
- Which CHAOS_COUNCIL Session 3/4 proposals made it into code?
- Has the icon-missing fallback been visually verified (shows placeholder, not blank)?

---

## Fix Plan

| # | Task | Effort | Blocks |
|---|------|--------|--------|
| 1 | Run Plan 11B manual sweep (open buddy, fill checklist) | 20 min | Plan 11B done gate |
| 2 | Set `export_path` in `export_presets.cfg`, export Windows build | 15 min | RC Suite, Perf |
| 3 | Add `Run Tests.bat` at repo root | 5 min | Friction |
| 4 | Run `run_burn_in.ps1 -Duration 600`, fill PERF_BASELINE.md 600s row | 15 min | Release gate |
| 5 | Run RC_SCENARIO_SUITE.md (9 scenarios) against exported `.exe` | 20 min | Release gate |
| 6 | Audit CHAOS_COUNCIL accepted list vs code; file any gaps as post-V1 | 30 min | Release confidence |
| 7 | Generate SHA256SUMS for exported artifact | 5 min | Release packaging |
| 8 | Cut v0.1 tag with SHA256SUMS and release notes | 10 min | Ship |

**Total estimated effort: ~2 hours.**

---

## Acceptance Tests

- [ ] Plan 11B log exists in `docs/product/` with PASS≥15, FAIL=0
- [ ] `BuddyRuntime.exe` export artifact exists locally (or CI artifact downloaded)
- [ ] RC Scenario Suite results table filled: 9/9 P (or FAIL rows have fix notes)
- [ ] `PERF_BASELINE.md` 600s row filled with real numbers (avg fps, max dt, mem drift)
- [ ] CHAOS_COUNCIL delta doc created: accepted proposals marked shipped/deferred
- [ ] `SHA256SUMS` generated for the release artifact
- [ ] `v0.1` tag created and pushed with SHA256SUMS attached

---

## Scoring Rubric

| Dimension | Score (0–5) | Notes |
|-----------|-------------|-------|
| Correctness / Safety | 4 | Headless suite solid; exported-build correctness untested |
| Reliability / Operability | 4 | Corruption recovery designed; RC Scenario 8 not yet run on export |
| Cost / Performance | 2 | PERF_BASELINE all TBD; burn-in not run |
| Maintainability | 5 | Decision register, deferred list, content schema, PR architecture checklist all present |
| User value | 4 | Vertical slice is expressive; Plan 11B UX pass pending |
