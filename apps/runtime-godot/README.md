# Runtime Godot Scaffold

This folder is the Windows-first desktop buddy runtime track.

## Current Scope

- transparent always-on-top buddy window
- click interaction and drag behavior
- bottom-anchored sprite placement (feet lock to window bottom edge)
- no rendered ground layer in runtime overlay
- deterministic weighted behavior loop
- local persistence for settings/profile/world-state
- encounter scheduler with hourly/day budget controls
- level-based unlock wiring for companion actions
- content pack loading with manifest validation contract
- opt-in productivity signal hooks (focus celebration + break suggestion)

## Start From Terminal (Windows)

The v0.1 runtime and gate scripts require exact Godot 4.2.2-stable; the
machine-readable pin is `toolchain.json`.

1. Open PowerShell.
2. Run:
   `cd C:\Users\GGPC\buddy-assembler`
3. Start normal buddy:
   `godot --path apps/runtime-godot`
4. Start vertical-slice mode:
   `godot --path apps/runtime-godot -- --vertical-slice`

If `godot` is not on PATH, pass the exact 4.2.2 console executable to the
gate script with `-Godot "C:\path\to\Godot_v4.2.2-stable_win64_console.exe"`.

Run the complete local/CI-parity gate with:

```powershell
pwsh ./apps/runtime-godot/tests/run_headless_checks.ps1
```

The current implementation is intentionally minimal and is a vertical-slice
scaffold, not final production content.

## Maple-Agnostic Slice

A separate architecture-first slice is available at:

- `res://scenes/vertical_slice/VerticalSliceMain.tscn`
- docs: `README_VERTICAL_SLICE.md`

## Runtime Controls

Everything below is reachable by keyboard for developers, but a real user
should never need to memorize F-keys. The `F10` settings popout is the
click-only path: open it once and Pause/Resume, Quiet strictness, content
pack, Restart, and Quit are all buttons, no hotkeys required.

- Left click + drag: move companion
- Right click: sleep/pause toggle (also a "Pause Buddy" / "Resume Buddy"
  button in the `F10` settings popout)
- `F6`: toggle telemetry overlay
- `F1`: export manual verification snapshot to `user://manual_verification/`
- `F2`: cycle prompt frequency (`low`, `normal`, `high`)
- `Shift+F2`: emit demo support prompt for cadence checks
- `F3`: cycle quiet strictness (`lenient`, `balanced`, `strict`) (also a
  button in the `F10` popout)
- `F4`: cycle interaction intensity (`cozy`, `balanced`, `deep`)
- `F7`: cycle event frequency (`low`, `normal`, `high`)
- `Shift+F7`: emit demo world prompt for cadence checks
- `F8`: move companion to next monitor
- `F9`: cycle available content packs (also a "Cycle Content Pack" button
  in the `F10` popout)
- `F10`: toggle separate movable settings popout window (categorized runtime
  settings + debug shortcuts). The popout also has a "Quit Runtime" button,
  so closing the buddy never requires a hotkey either.

The remaining F-key shortcuts are developer/debug tools (telemetry,
manual-verification export, demo prompts, reward-box, world-prompt
resolution, emote debug keys). A full audit of which of those deserve a
click target too is intentionally out of scope here and left for a
follow-up pass.

## Character Sprite + Animation Export

To export runtime visuals from your saved Buddy Assembler combo:

```powershell
python .\tools\importers\export_runtime_character_sprites.py
```

This reads `combinations/last_combo.json` and writes:

- static state PNGs to `apps/runtime-godot/content/core_pack/character/`
- animation JSON + sprite sheets to `apps/runtime-godot/content/core_pack/character/animations/`

Optional flags:

- `--max-frames 8` limits frames per action animation.
- `--default-delay-ms 120` sets fallback frame timing when action delay metadata is missing.
- `--no-export-animations` exports only static state PNGs.
