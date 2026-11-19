# Plan 5 Manual Verification Log (Desktop Checklist)

Date: 2026-04-21  
Plan: Plan 5: Manual Desktop Verification Gate  
Track: TO  
Checklist source: apps/runtime-godot/tests/SCENARIO_CHECKLIST.md  
Generated: 2026-04-21 22:06:51 +12:00  
Reviewer: josh

## Summary

- Result counts: PASS=15 FAIL=1 PENDING=0
- Gate status: **FAIL**

## Automated Pre-Check

Command: pwsh -NoLogo -File apps/runtime-godot/tests/run_headless_checks.ps1

Status: run manually before final sign-off

## Behavior and Encounters

- [BE1] Idle transitions over several ticks feel correct. (PASS)
- [BE2] F3 quiet strictness changes cadence suppression (verify with /cadence strict > balanced/lenient). (PASS)
- [BE3] F7 cycles event frequency; verify via Shift+F7 demo + /cadence summary. (PASS)
- [BE4] F2 cycles prompt frequency; verify via Shift+F2 demo + /cadence summary. (PASS)
- [BE5] Event budgets suppress repeat encounter spam. (PASS)

## Content Packs

- [CP1] F9 pack cycle updates chat with slot x/y and telemetry pack id (visual deltas may be subtle). (PASS)
- [CP2] Telemetry reflects active pack. (PASS)

## Multi-Monitor

- [MM1] Drag across monitor edges/displays. (PASS)
- [MM2] F8 moves companion to next monitor. (PASS)
- [MM3] Restart restores monitor + window position. (PASS)

## Overlay Basics

- [OB1] Launch transparent always-on-top window. (PASS)
- [OB2] Left-click drag feels smooth while held; release settles back to floor cleanly. (PASS)
- [OB3] Right-click sleep toggle. (PASS)

## Progression and Unlocks

- [PG1] Pet loop shows Bond Lv/XP/Growth feedback and values move in telemetry. (PASS)
- [PG2] Progress feedback shows next unlock hint (or all unlocks unlocked). (PASS)
- [PG3] Restart preserves progression state. (FAIL)

## Issues

- [PG3] seems to just sort of cycle

## Follow-Up

- If gate status is FAIL, create fix tickets and rerun this checklist.
- If gate status is IN_PROGRESS, complete pending checks and rerun.
