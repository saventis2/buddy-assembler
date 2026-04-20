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

1. Open PowerShell.
2. Run:
   `cd C:\Users\GGPC\buddy-assembler`
3. Start normal buddy:
   `godot --path apps/runtime-godot`
4. Start vertical-slice mode:
   `godot --path apps/runtime-godot -- --vertical-slice`

If `godot` is not found, use:
`& "C:\Users\GGPC\AppData\Local\Microsoft\WinGet\Links\godot.exe" --path apps/runtime-godot`

The current implementation is intentionally minimal and is a vertical-slice
scaffold, not final production content.

## Maple-Agnostic Slice

A separate architecture-first slice is available at:

- `res://scenes/vertical_slice/VerticalSliceMain.tscn`
- docs: `README_VERTICAL_SLICE.md`

## Runtime Controls

- Left click + drag: move companion
- Right click: sleep toggle
- `F6`: toggle telemetry overlay
- `F1`: export manual verification snapshot to `user://manual_verification/`
- `F2`: cycle prompt frequency (`low`, `normal`, `high`)
- `F3`: cycle quiet strictness (`lenient`, `balanced`, `strict`)
- `F4`: cycle interaction intensity (`cozy`, `balanced`, `deep`)
- `F7`: cycle event frequency (`low`, `normal`, `high`)
- `F8`: move companion to next monitor
- `F9`: cycle available content packs

## Character Sprite + Animation Export

To export runtime visuals from your saved Buddy Assembler combo:

```powershell
python .\export_runtime_character_sprites.py
```

This reads `combinations/last_combo.json` and writes:

- static state PNGs to `apps/runtime-godot/content/core_pack/character/`
- animation JSON + sprite sheets to `apps/runtime-godot/content/core_pack/character/animations/`

Optional flags:

- `--max-frames 8` limits frames per action animation.
- `--default-delay-ms 120` sets fallback frame timing when action delay metadata is missing.
- `--no-export-animations` exports only static state PNGs.
