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
on any machine. The launcher starts the app with `-- --no-save`, so it starts
from defaults and never opens the save files, not even while starting up; the
simulation scene refuses to run without it. Not simulated: ambient desktop
animation, quests and encounters, talking to the buddy, and the language model.

`--world` picks the world. `land`, the default, is the house and land a buddy
starts with since Plan 14; `town` is the older town with its six characters.

```powershell
python apps/runtime-godot/tools/simulate_days.py --godot "C:\path\to\Godot_v4.2.2-stable_win64_console.exe" --days 30 --seed 1 --world town --journal firsts
```

## Small beginnings

Since Plan 14 a buddy starts with a house and the land around it, alone, and
finds the rest a piece at a time (`docs/product/PLAN14_SMALL_BEGINNINGS.md`).
The setting is `smallBeginnings` in `settings.json`, on by default.

The first time the app starts in this world with a buddy from before, it puts
that buddy away and a new one wakes up:

- `settings.json`, `profile.json` and `world_state.json` are copied to
  `backups/before-small-beginnings-<date>/` in the save folder
  (`%APPDATA%\Godot\app_userdata\Buddy Runtime`). The folder is never
  overwritten, and each copy is checked against its original. If the copy
  fails, nothing is changed and the old buddy carries on for that run.
- Only the buddy starts over: its name, memories, journal, feelings, bond and
  growth. Settings, items, wardrobe and meso are kept.
- `freshStartBackup` in `settings.json` records where the copy went.

Only a real launch does this. The tests, the CI start-up modes and the
fast-forward tool never touch the save.

To go back to the buddy from before: close the app, set
`"smallBeginnings": false` in `settings.json`, and copy `profile.json` from the
backup folder over the one in the save folder. The old town, its six
characters, quests and encounters are still in the pack and the code; with the
setting off they work as before.

On the land, chat tells the model nothing about the buddy's world: it speaks
from its own memories (`your_memories`), and what it says is checked against
them before it goes out. A reply that names someone or something it has not
met is asked for once more, told so, and if that fails too it says a plain
line instead, such as "I haven't met anyone here." The default chat model,
`gemma3:4b`, often goes along with questions that take people for granted
("what's your neighbour's name?"), so it falls back to that line more: 23 of 47
such answers in the 2b-2 evaluation, against 8 of 48 for `gemma3:12b`. If 12b
is installed and you can spare the graphics memory, set
`"chatModelName": "gemma3:12b"` in `settings.json`. The buddy also picks its
name with the chat model, so it stays nameless while the model is off.
`tests/ChatEval.tscn` measures this against a real model (see
`docs/product/PLAN14_SMALL_BEGINNINGS.md`, step 2b-2).

The current implementation is intentionally minimal and is a vertical-slice
scaffold, not final production content.

## World host

On by default (D-010). Turn it off with Menu > Settings > Its own mind > World
host, or `"worldHost": false` in `settings.json`; it takes effect the next time
the app starts, and a running host notices within ten seconds and quits. The
same goes for `"smallBeginnings": false`: the host runs only the land life.
Your buddy lives on its own land in a background program that keeps running
when the app is closed, and the app is the buddy visiting you. Only a real
launch of the app counts: a headless run (the CI parse check, the tests, the
fast-forward tool) never takes the app's role and never starts a host.

- Opening the app starts the host if it is not running and asks the buddy to
  come over. It comes at once unless it is asleep or busy; then the app says
  when it will come. While it is at home the app shows a small panel with its
  latest journal line and a "Call over" button.
- A visit ends when the app closes, at bedtime, after two quiet hours, or when
  you choose "Send home" in the menu. Closing the app sends it home first.
  Called at its bedtime, it says it will come in the morning (07:00).
- Start the app with the windowed program (or an exported build). Through
  Godot's console wrapper (`..._console.exe`), the host the app starts stops
  when the app does.
- After a restart of the PC its world waits until the app is opened again:
  there is no watchdog until the move to Nexus.
- Its files are in the save folder under `host/`: `buddy.lock/`, `host.json`,
  `desktop.json` and `inbox/`. Only the program that holds the buddy writes
  `profile.json` and `world_state.json`; `settings.json` belongs to the app.
- The host is the same program run as `--headless -- --world-host`. To stop
  it, turn the setting off: it notices within ten seconds and quits.

## Letters

On the land, the main menu has a Letters window: write to your buddy and it
reads the letter at the glowing box in its house, the next time it goes there
(a waiting letter draws it). It has to work out the glowing box first, which
takes a few visits; until then letters wait there and the box blinks. While it is
at home the letter goes through the world host's inbox, and the window shows it
as on its way, waiting or read. Letters are kept in the buddy's save, so
anything that looks like a password or a key is refused. The buddy writes back
(step 2c-2) with `letterModelName` in `settings.json` (default `gemma3:12b`,
falling back to the chat model when that is not installed), from what it
remembers, checked like chat, with a plain fallback letter when the check fails
twice; only the process that has the buddy at home writes, and it needs the
thinking model on. To see how soon a letter is read, add `--letter DAY:HH:MM:TEXT` (repeatable)
to the fast-forward tool, for example `--letter 1:10:00:Hello`.

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
