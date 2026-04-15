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

## Open in Godot

1. Open Godot 4.
2. Import this folder as a project.
3. Run the default scene.

Launch routing:

- default run target: `BuddyOverlay`
- vertical slice target: run with `-- --vertical-slice`

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
