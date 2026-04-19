# Perf baseline and burn-in recipe

Release gate (see `RELEASE_CHECKLIST.md` → PR-06): idle behavior must
hold steady over 10 minutes and over a multi-hour window. This doc
defines how to run the burn-in and where to record the numbers.

## Recipe

Short run (fast signal — CI, local smoke):

```powershell
apps\runtime-godot\tests\run_burn_in.ps1 -Duration 600
```

Multi-hour run (release gate):

```powershell
apps\runtime-godot\tests\run_burn_in.ps1 -Duration 10800
```

The wrapper invokes `godot --headless` against `IdleProfile.tscn`
with a single BuddyActor idling for the requested duration. It
samples static memory every 5 s and captures every frame delta.

Output log:
`%APPDATA%\Godot\app_userdata\Buddy Runtime\perf\idle_profile_<unix>.log`

## What we measure

- **Avg dt / fps** — steady-state frame time.
- **Max dt** — worst observed stall.
- **Mem drift** — max minus min static memory across samples.
  Drift > ~5 MB over 10 minutes is a red flag; investigate before
  release.

## Baseline (to be filled on release rehearsal)

Populate this table on release-rehearsal runs against the exported
`BuddyRuntime.exe`. Editor-play numbers are informational only and
must be clearly labeled as such.

| Date (UTC) | Build            | Duration | Avg fps | Max dt ms | Mem drift KB | Notes |
|------------|------------------|----------|---------|-----------|--------------|-------|
| _TBD_      | exported v0.1-rc | 600 s    |         |           |              |       |
| _TBD_      | exported v0.1-rc | 10800 s  |         |           |              |       |

Record every release. Regression vs. the prior release of > 20% on
avg fps or > 2x on mem drift blocks the tag until triaged.

## Notes

- Headless runs do not exercise the overlay window composition, so
  CPU/GPU numbers will differ from a real desktop session. Numbers
  here are a lower-bound regression tripwire, not a ship-truth claim.
- The RC scenario suite (`RC_SCENARIO_SUITE.md` → Scenario 4) covers
  the real-desktop idle sanity check.
