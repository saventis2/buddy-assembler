# Runtime Scenario Checklist

Run these checks in Godot editor or exported build.

Optional pre-check:

```powershell
pwsh ./run_headless_checks.ps1
```

## Overlay Basics

1. Launch scene and confirm transparent always-on-top window.
2. Left-click and drag buddy; ensure smooth repositioning.
3. Right-click buddy; verify sleep toggle.

## Multi-Monitor

1. Drag buddy near monitor edge and across displays.
2. Press `F8` to move to next monitor.
3. Restart app and verify window restores on preferred monitor and position.

## Behavior and Encounters

1. Observe idle transitions over several ticks.
2. Confirm quiet-hours behavior lowers active events.
3. Press `F7` to cycle event frequency (`low` -> `normal` -> `high`) and verify effect.
4. Confirm event budgets prevent repeated encounter spam in same hour/day.

## Progression and Unlocks

1. Repeated pet interactions increase bond XP and level.
2. Unlock list grows at expected levels (wander/happy/gift/visitor).
3. Restart app and verify progression persists.

## Content Packs

1. Validate both manifests using validator CLI.
2. Press `F9` to cycle available packs.
3. Verify runtime reports active pack in telemetry.
