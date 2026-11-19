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

The gate includes `life_sim_test` (`tests/LifeSimTest.tscn`), which checks that
a simulated life is repeatable from a seed and never writes the save files.

## Fast-forward

To see how a new buddy's life reads over many days without waiting for them:

```powershell
python apps/runtime-godot/tools/simulate_days.py --godot "C:\path\to\Godot_v4.2.2-stable_win64_console.exe" --days 30 --seed 1 --journal firsts --out report.json
```

It runs the real mind code with a supplied clock, in a headless process, and
prints each day's decisions, the new places, people and wishes it met, and how
often the journal repeated itself. `--journal` is `all`, `firsts` or `none`;
`--out` also writes the full report as JSON. The same seed gives the same life
on any machine. Once a process starts a simulation it never saves, so the real
save files are not touched. Not simulated: ambient desktop animation, quests and
encounters, talking to the buddy, and the language model.

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
- Double click: open the Game Menu (chat, stats, inventory, wardrobe, pause)
- Chat: anything that is not a `/command` gets an in-character answer when
  Ollama is running (Settings: "Talks back"); `/help` lists the commands
- Suggestions: "why don't you go and see Mira?" It decides for itself (yes,
  later or no), says so, and the journal says why it went or did not
- Town: Menu > Town shows a map of its town, where it is now and who is
  about; click a place to see what it thinks of it
- Wants: it notices things to wear at the market lane, saves its meso and
  buys them (`/wants` lists what it is saving for), and plans its day
- Memory: it remembers what you tell it from one day to the next. Menu >
  Memory shows everything it remembers and forgets any of it (Settings:
  "Remembers you")
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
