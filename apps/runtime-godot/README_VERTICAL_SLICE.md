# Maple-Agnostic Vertical Slice

This slice proves the architecture rule:

- import Maple-derived data into internal resources
- keep runtime independent from source-specific paths and schemas

## Scope

- one actor from internal `ActorDefinition`
- semantic clips: `idle`, `walk`, `jump`, `happy_emote`
- one test map using `CollisionMapResource`
- one command bridge: `play_emote("happy")`

## Paths

- Scene: `res://scenes/vertical_slice/VerticalSliceMain.tscn`
- Runtime scripts: `res://runtime/actor`, `res://runtime/world`, `res://runtime/buddy`
- Internal types: `res://content/types`
- Sample imported resources: `res://content/imported/demo`
- Intermediate schemas/examples (`.bif`): `res://content/intermediate`
- Converter stub: `res://tools/converter/convert_to_bif.py`
- Importer skeleton: `res://addons/buddy_importer`

## Run

1. Open PowerShell.
2. Run:
   `cd C:\Users\GGPC\buddy-assembler`
3. Start vertical-slice mode:
   `godot --path apps/runtime-godot -- --vertical-slice`
4. Controls:
   - Arrow keys: walk
   - Space: jump
   - `E`: `play_emote("happy")`
   - `R`: `play_emote("sad")`
   - `T`: `play_emote("angry")`
   - `Y`: `play_emote("love")`
   - `[` / `]`: decrease/increase speech-bubble duration
   - `M`: immediate speech-bubble test line with current duration

If `godot` is not found, use:
`& "C:\Users\GGPC\AppData\Local\Microsoft\WinGet\Links\godot.exe" --path apps/runtime-godot -- --vertical-slice`

## Notes

- Runtime modules do not parse WZ and do not reference Maple node/file paths.
- Maple/source provenance is stored under `metadata` on imported resources.
- Importer plugin is scaffolded for `.bif -> .tres` ingestion and format versioning.
