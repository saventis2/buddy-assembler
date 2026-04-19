# First-run onboarding & presence controls

## What happens on first launch

On the very first launch (no `settings.json` under
`%APPDATA%\Godot\app_userdata\Buddy Runtime\`), the runtime:

1. Creates default settings with quiet, conservative values (see below).
2. Shows a one-time welcome tooltip for 6 seconds:
   > "Hi! I'm your new desktop buddy.
   > Right-click me to sleep. Drag to move."
3. Sets `firstRunSeen: true` in `settings.json` so the tooltip never
   appears again.

The tooltip is a screen-centred Label on its own CanvasLayer — it
doesn't require the content pack to be loaded and appears even in
safe-mode fallback.

## Default settings (quiet by design)

| Setting               | Default  | Rationale                              |
|-----------------------|----------|----------------------------------------|
| `quietHoursEnabled`   | `true`   | Suppresses events 22:00–07:00 by default. New users should not be surprised by late-night activity. |
| `quietHoursStart`     | `22`     | 10 pm                                  |
| `quietHoursEnd`       | `7`      | 7 am                                   |
| `eventFrequency`      | `normal` | Middle of the road; tunable via F7.    |
| `productivityOptIn`   | `false`  | Productivity features are opt-in only. |
| `opacity`             | `1.0`    | Fully opaque; adjustable via settings. |
| `firstRunSeen`        | `false`  | Cleared on first launch, never again.  |

## Presence controls reference

| Control             | How to use                                         |
|---------------------|----------------------------------------------------|
| Move buddy          | Left-click and drag                                |
| Sleep / wake        | Right-click the buddy                              |
| Quiet hours         | Edit `settings.json` → `quietHoursStart` / `End`; or toggle `quietHoursEnabled` |
| Event frequency     | Press **F7** in-app to cycle low → normal → high   |
| Switch content pack | Press **F9** to cycle available packs              |
| Move to next screen | Press **F8**                                       |
| Telemetry overlay   | Press **F6** to toggle the on-screen debug panel   |
| Hide buddy          | Right-click → sleep; planned: system-tray toggle (deferred, not V1) |

## Implementation notes

- `AppState.is_first_run()` returns `true` when `settings["firstRunSeen"]`
  is `false` (or absent in older saves — backwards-compatible).
- `AppState.mark_first_run_seen()` sets the flag and flushes
  `settings.json` immediately (atomic write via `SaveStore`).
- The welcome label lives at `scenes/BuddyOverlay.tscn →
  WelcomeLayer/WelcomeLabel`. It is hidden by default; shown for 6 s
  via `buddy_overlay._show_welcome_once()`.
- Subsequent launches: `is_first_run()` returns `false` immediately,
  `_show_welcome_once` is never called.
