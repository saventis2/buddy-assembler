# Plan 5 Manual Verification Log (Desktop Checklist)

Date: 2026-04-20  
Plan: `Plan 5: Manual Desktop Verification Gate`  
Checklist source: `apps/runtime-godot/tests/SCENARIO_CHECKLIST.md`

Guided log helper:

```powershell
pwsh -NoLogo -File apps/runtime-godot/tests/run_manual_checklist.ps1
```

One-command gate runner:

```powershell
pwsh -NoLogo -File apps/runtime-godot/tests/run_plan5_gate.ps1
```

Note:
- Gate runner now launches both runtime sessions automatically:
  1) normal runtime window
  2) vertical-slice window
- Close each window after completing the corresponding checklist section.

## Summary

- Automated pre-checks: **PASS**
- Interactive desktop checks: **PENDING MANUAL CONFIRMATION**
- Gate status: **IN PROGRESS** (blocked on GUI-observable validation)

## Automated Pre-Check Results

Command run:

```powershell
pwsh -NoLogo -File apps/runtime-godot/tests/run_headless_checks.ps1
```

Result:

- Parse check: PASS
- Smoke floor-lock: PASS
- SaveStoreTest: PASS
- PackValidationTest: PASS
- WorldEconomyFlowTest: PASS

## Interactive Checklist Status

### Overlay Basics

- [ ] Launch transparent always-on-top window (manual)
- [ ] Left-click drag smooth reposition (manual)
- [ ] Right-click sleep toggle (manual)

### Multi-Monitor

- [ ] Drag across monitor edges/displays (manual)
- [ ] `F8` next-monitor move works (manual)
- [ ] Restart restore monitor+position (manual)

### Behavior and Encounters

- [ ] Idle transitions over several ticks feel correct (manual)
- [ ] Quiet-hours lowers active events (manual)
- [ ] `F7` frequency cycle affects cadence (manual)
- [ ] Event budgets suppress same-hour/day spam (manual)

### Progression and Unlocks

- [ ] Pet loop increases bond XP/level (manual)
- [ ] Unlock growth by level appears as expected (manual)
- [ ] Restart persists progression (manual)

### Content Packs

- [x] Manifest validation pass (automated via headless checks)
- [ ] `F9` pack cycle observable in runtime (manual)
- [ ] Telemetry reflects active pack (manual)

### Vertical Slice

Run:

```powershell
godot --path apps/runtime-godot -- --vertical-slice
```

- [ ] Movement left/right works and is smooth (manual)
- [ ] Jump leaves/lands correctly (manual)
- [ ] Emote keys `E/R/T/Y` work and recover (manual)
- [ ] Facing flip matches direction (manual)
- [ ] Floor lock remains stable under repeated jump (manual)
- [ ] Top hint text wraps/readable (manual)

### Speech Bubble Timer (Vertical Slice)

- [ ] Idle bubble appears at expected cadence (manual)
- [ ] Bubble duration timeout works (manual)
- [ ] `[` / `]` duration tuning works (manual)
- [ ] New duration applied on subsequent say event (manual)

## Blocking Notes

- Terminal-only execution cannot verify visual/interactive behavior.
- No blocking automated regressions were detected.

## Close-Out Instructions

After manual run, append one of:

- `PASS` with short notes and any UX polish follow-ups, or
- `FAIL` with issue list (repro steps + expected vs actual).
