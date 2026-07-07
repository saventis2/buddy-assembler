# RC Scenario Suite

Release-candidate smoke. Nine scenarios that must pass on the
**exported Windows build** before a release tag is cut. Editor-play
does not count — see `RELEASE_CHECKLIST.md`.

Another contributor should be able to run this top-to-bottom from
a clean machine in under 20 minutes.

## Prerequisites

- Windows 10 or 11.
- A freshly downloaded release artifact `BuddyRuntime.exe` from the
  `buddy-runtime-windows` CI artifact or a local export.
- `%APPDATA%\Godot\app_userdata\Buddy Runtime\` does **not** exist
  (delete it if it does — we test first-run state below).
- Two terminals: one PowerShell for running the exe, one File
  Explorer open on `%APPDATA%\Godot\app_userdata\Buddy Runtime\`
  to inspect save files between scenarios.

## Results template

Copy to your PR description or release notes. Every row should be
P / F / S (pass / fail / skipped) with a one-line note on fail.

| # | Scenario | Result | Notes |
|---|----------|--------|-------|
| 1 | First run                        |   |   |
| 2 | Restart                          |   |   |
| 3 | Drag / click interaction         |   |   |
| 4 | Idle behavior                    |   |   |
| 5 | Sleep                            |   |   |
| 6 | Visits                           |   |   |
| 7 | Invalid content fallback         |   |   |
| 8 | Corrupted settings recovery      |   |   |
| 9 | Exported build launches cleanly  |   |   |

## Guided runner

Optional interactive log generator — asks p/f/s per scenario, captures
a short note when a scenario fails, and writes a dated results log
matching the table above:

```powershell
pwsh -NoLogo -File apps/runtime-godot/tests/run_rc_scenario_suite.ps1
```

Non-interactive template generation (no prompts; every scenario is
stamped `PENDING`):

```powershell
pwsh -NoLogo -File apps/runtime-godot/tests/run_rc_scenario_suite.ps1 -UseDefaults -DefaultResult pending
```

Writes `docs/product/RC_SCENARIO_SUITE_LOG_<date>.md` by default (pass
`-OutputPath` to override). The script only carries a short one-line
prompt per scenario — the numbered steps below remain the source of
truth for what to actually click through.

---

## 1. First run

**Preconditions:** `app_userdata\Buddy Runtime\` directory does not
exist.

**Steps:**
1. Launch `BuddyRuntime.exe`.
2. Wait 5 seconds.

**Expected:**
- Companion appears on-screen.
- `app_userdata\Buddy Runtime\` is created and contains
  `settings.json`, `profile.json`, `world_state.json`.
- Each file has a top-level `"schemaVersion"` key with an integer
  value matching the current runtime.
- No unhandled exception dialog.

**Reset for next scenario:** none needed; leave files in place.

---

## 2. Restart

**Preconditions:** Completed Scenario 1. Save files present.

**Steps:**
1. Quit the running instance (tray / close).
2. Re-launch `BuddyRuntime.exe`.

**Expected:**
- Companion re-appears in approximately the same last-known
  on-screen position.
- `settings.json` last-modified time updates on quit (or is stable
  across restarts — either is acceptable as long as no file is
  deleted or blanked).
- No first-run state leakage (no duplicate defaults written).

**Reset:** none.

---

## 3. Drag / click interaction

**Preconditions:** Runtime idle.

**Steps:**
1. Left-click the companion and drag to a new screen position.
2. Release.
3. Right-click the companion (if a context menu is part of the V1
   surface; otherwise note "N/A").

**Expected:**
- Companion follows cursor smoothly while dragged (no teleport
  jumps, no visible clipping through the desktop edge).
- Position persists across the next restart (covered in Scenario 2
  re-run if you choose to re-verify).
- Right-click behavior matches the V1 UX spec (or is absent if
  right-click is deferred).

**Reset:** none.

---

## 4. Idle behavior

**Preconditions:** Runtime idle; no user input for ≥ 60 seconds.

**Steps:**
1. Leave the companion alone for 60 seconds.
2. Observe.

**Expected:**
- Companion plays idle animation(s) or breathing frames.
- No busy-loop CPU (check Task Manager — CPU should be < 5% on a
  modern machine with no other load).
- No memory growth of more than ~5 MB across the 60-second window.

**Reset:** none.

---

## 5. Sleep

**Preconditions:** Runtime idle.

**Steps:**
1. Trigger sleep per the V1 UX (e.g. right-click → sleep, or wait
   for idle-to-sleep timeout — record which path you took).
2. Observe for 30 seconds.
3. Wake the companion (left-click, or the documented wake input).

**Expected:**
- Sleep animation / reduced-activity state visible.
- CPU drops further (should be below idle baseline).
- Wake returns to idle/active cleanly with no frame glitches.

**Reset:** none.

---

## 6. Visits

**Preconditions:** Runtime idle.

**Steps:**
1. Trigger or wait for a visit event (document the method used — a
   debug hotkey is acceptable for RC testing).
2. Watch the visit play out.

**Expected:**
- Visit sequence starts, plays, and returns to idle without
  blocking user input.
- No orphaned actor or pinned overlay left on screen after the
  visit ends.

**Reset:** none.

---

## 7. Invalid content fallback

**Preconditions:** Runtime quit. Backup `settings.json` first.

**Steps:**
1. In `settings.json`, set `"selected_pack"` (or the equivalent
   pack-id key) to `"does_not_exist"`.
2. Launch `BuddyRuntime.exe`.
3. Observe.

**Expected:**
- Runtime does not crash.
- Companion still appears — driven by core pack or built-in safe
  mode.
- A log line or telemetry indicates pack fallback fired. Example
  from `load_with_fallback`:
  `content: pack fallback — tier=core reason=selected failed validation ...`.
  or `tier=builtin` if core also failed.

**Reset:** restore the backed-up `settings.json`.

---

## 8. Corrupted settings recovery

**Preconditions:** Runtime quit. Backup `settings.json` first.

**Steps:**
1. Overwrite `settings.json` with the literal text `{not valid
   json`.
2. Launch `BuddyRuntime.exe`.
3. Quit.
4. List files in the save directory.

**Expected:**
- Runtime launches on defaults (no crash).
- A new `settings.json` exists and parses.
- A quarantined sibling file exists with a name like
  `settings.json.corrupt-<unixtime>.bad_json`. This is the contract
  from `SaveStore._quarantine`.

**Reset:** delete the quarantine file; restore backup if desired.

---

## 9. Exported build launches cleanly

**Preconditions:** `BuddyRuntime.exe` on a machine with **no Godot
editor installed**.

**Steps:**
1. Copy the build to a fresh user profile or a second test machine.
2. Double-click `BuddyRuntime.exe`.

**Expected:**
- Launches without missing-DLL errors.
- Save directory is created under that user's `%APPDATA%` (not the
  developer's).
- Companion appears and responds to input.

This scenario is the release-truth gate referenced in
`RELEASE_CHECKLIST.md` — editor-play success does not satisfy it.
