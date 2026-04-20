# Runtime Scenario Checklist

Run these checks in Godot editor or exported build.

Optional pre-check:

```powershell
pwsh ./run_headless_checks.ps1
```

Optional guided log generator:

```powershell
pwsh ./run_manual_checklist.ps1
```

For non-interactive template generation:

```powershell
pwsh ./run_manual_checklist.ps1 -UseDefaults -DefaultResult pending
```

One-command Plan 5 gate flow:

```powershell
pwsh ./run_plan5_gate.ps1
```

Non-interactive tooling smoke mode (skip GUI launches):

```powershell
pwsh ./run_plan5_gate.ps1 -SkipRuntimeLaunch -UseDefaults -DefaultResult pending
```

## Overlay Basics

1. Launch scene and confirm transparent always-on-top window.
2. Left-click and drag buddy; ensure smooth repositioning.
3. Right-click buddy; verify sleep toggle.
4. Press `F1` and verify a manual snapshot JSON is written under `user://manual_verification/`.

## Multi-Monitor

1. Drag buddy near monitor edge and across displays.
2. Press `F8` to move to next monitor.
3. Restart app and verify window restores on preferred monitor and position.

## Behavior and Encounters

1. Observe idle transitions over several ticks.
2. Confirm quiet-hours behavior lowers active events.
3. Press `F7` to cycle event frequency (`low` -> `normal` -> `high`) and verify effect.
4. Press `F2` to cycle prompt frequency (`low` -> `normal` -> `high`) and verify chat prompt cadence changes.
5. Confirm event budgets prevent repeated encounter spam in same hour/day.

## Progression and Unlocks

1. Repeated pet interactions increase bond XP and level.
2. Unlock list grows at expected levels (wander/happy/gift/visitor).
3. Restart app and verify progression persists.

## Content Packs

1. Validate both manifests using validator CLI.
2. Press `F9` to cycle available packs.
3. Verify runtime reports active pack in telemetry.

## Vertical Slice (requires desktop run with `--vertical-slice` flag)

Run command:
```powershell
godot_console.exe --path apps/runtime-godot -- --vertical-slice
```

1. **Movement** — Press left/right arrow keys; character walks left and right smoothly.
2. **Jump** — Press Space; character leaves the ground, plays jump animation, lands back at floor.
3. **Emote** — Press `E`; happy emote plays and holds briefly before returning to idle/walk.
   - Also test `R` (sad), `T` (angry), `Y` (love).
4. **Facing flip** — Walk right; sprite faces right. Walk left; sprite faces left.
5. **Floor lock** — Jump and land repeatedly; actor must not sink below floor level.
6. **Text-wrap hint** — Top-of-window hint label is fully readable and wraps within window width.

## Speech Bubble Timer (vertical slice)

1. Wait for idle speech bubble to appear (default ~8 seconds).
2. Verify bubble disappears after configured duration (default 1.6 seconds).
3. Press `]` to increase bubble duration; press `[` to decrease it.
4. Trigger a say event and confirm the new duration is applied.
