# Godot Upgrade Migration Plan (4.2.2 → current stable)

Status: **PLAN ONLY — no code changes.** Backlog item **87**
(`docs/product/IMPROVEMENT_BACKLOG_TOP_100.md`), gated as "explicit
migration planning, not incidental work" per
`docs/product/IMPROVEMENT_BACKLOG_BUILD_SEQUENCE.md` (Wave 4).
Researched: 2026-07-13. Maintainer review and sign-off required before
any upgrade PR is opened.

---

## 1. Executive summary

- **Current stable Godot is 4.7** (tag `4.7-stable`, published
  **2026-06-18**). The previous minor's latest patch is **4.6.3**
  (published 2026-05-20). We ship on **4.2.2** (pinned in
  `apps/runtime-godot/project.godot` and
  `.github/workflows/runtime-smoke.yml`) — five minor releases behind.
- **Recommended target: `4.6.3-stable`**, upgraded in a **single
  direct jump** (no intermediate 4.3/4.4/4.5 hops as separate PRs).
  Reasoning in §3. 4.7.0 is a 3.5-week-old `.0` release with zero
  patch releases; re-evaluate 4.7.x if a 4.7.1+ exists when the
  upgrade PR is actually started.
- **Tray icon fact check (load-bearing for backlog #1):**
  `DisplayServer.create_status_indicator` was added in **Godot 4.3**
  (released 2024-08-15) via
  [godot#80211](https://github.com/godotengine/godot/pull/80211)
  ("Implement support for application status indicators (tray
  icons)"), listed in the `4.3-stable` `CHANGELOG.md` under the 4.3
  section. It is absent from the `4.2-stable` `DisplayServer.xml`
  class docs and present from `4.3-stable` onward, including current
  master. The repo's prior "needs 4.3+" claim is **confirmed
  correct**. A `StatusIndicator` node and
  `DisplayServer.FEATURE_STATUS_INDICATOR` capability flag also exist,
  so the tray-icon code can feature-detect at runtime.
- **No hard API breaks found** for the specific engine APIs this
  project uses (full inventory in §4). The dominant risk is
  **behavioral**, not compile-time: the overlay's core trick —
  borderless + per-pixel-transparent + always-on-top window moved via
  `DisplayServer.window_set_position()` every frame — sits exactly on
  the surface where Godot has a history of Windows-specific
  compositing edge cases, and CI (headless Linux + export-only
  Windows) cannot observe any of it. The manual gates in §6 are the
  real acceptance test, not CI.

## 2. Version landscape (verified 2026-07-13)

| Version | Released | Notes relevant to us |
|---|---|---|
| 4.2.2 | 2024-02 | Current pin (`GODOT_RELEASE: "4.2.2-stable"`) |
| 4.3 | 2024-08-15 | Adds `create_status_indicator` (tray icon, unblocks #1) |
| 4.4 | 2025-03 | `.uid` sidecar files for scripts (repo churn, §5) |
| 4.5 | 2025-09 | Font oversampling rework; `Resource.duplicate` change |
| 4.6 / 4.6.3 | 2026-01 / 2026-05-20 | `.tscn` format tweaks; D3D12 default for *new* projects only |
| 4.7 | 2026-06-18 | HDR output, GDScript typed-return rule; no patch release yet |

Sources: GitHub releases API (`4.7-stable` latest, `4.6.3-stable`
prior), official per-version upgrade guides in `godotengine/godot-docs`
(`tutorials/migrating/upgrading_to_godot_4.{3,4,5,6,7}.rst`),
`godotengine/godot` `4.3-stable` `CHANGELOG.md`, and the
[Godot 4.6](https://godotengine.org/releases/4.6/) /
[4.7](https://godotengine.org/releases/4.7/) release pages.

## 3. Target version and jump strategy

### Recommendation: 4.6.3, one direct jump, one upgrade PR

**Why 4.6.3 and not 4.7.0 (today):**

- 4.6.3 has had **three patch rounds over ~5 months**; 4.7.0 has had
  **zero** and is under a month old. This repo's own release culture
  ("editor-play is not sufficient", exported-build truth,
  `RC_SCENARIO_SUITE.md`) argues against absorbing a `.0` engine.
- 4.7's headline feature is a rework of the **display output pipeline
  (HDR output on Windows)** — precisely the compositing surface a
  transparent desktop overlay is most sensitive to. Off by default,
  but `.0`-release regressions in output/present paths are the risk.
- Everything we *need* (tray icon API) has been available since 4.3.
  4.6.3 delivers it with maximal soak time.
- If, at implementation time, **4.7.1+ exists**, jumping straight to
  4.7.x instead is reasonable — the 4.6→4.7 delta relevant to this
  repo is small and is already included in the checklist below (§4)
  so the plan doesn't need rewriting for that decision.

**Why one direct jump, not incremental 4.3 → 4.4 → … PRs:**

- Godot does **not** require stepping a project through intermediate
  editors; the official migration guides are per-minor but cumulative,
  and a 4.2 project opens directly in 4.6.
- Each intermediate stop would trigger its own full manual retest
  cycle (§6) — the expensive part — for zero extra safety, since the
  per-minor breaking-change lists were reviewed against this codebase
  (§4) and none of the intermediate versions is a state we want to
  ship.
- Incremental value is only diagnostic, and we can get it **without
  extra PRs**: the headless test scripts
  (`apps/runtime-godot/tests/run_headless_checks.ps1`) take whatever
  `godot` is on PATH and the CI suite is driven by two env vars, so if
  the 4.6.3 run breaks something non-obvious, bisecting locally across
  4.3/4.4/4.5 binaries is cheap. Use that for diagnosis, not for
  sequencing.

## 4. Breaking-changes checklist, scoped to what this project uses

Method: inventoried the engine API surface actually used under
`apps/runtime-godot/` (55 `.gd` files, 17 `.tscn` scenes; the shipping
overlay controller `scripts/buddy_overlay.gd` is the heaviest engine
consumer), then checked every item against the official 4.3, 4.4,
4.5, 4.6 and 4.7 upgrade guides.

### 4.1 DisplayServer window/screen APIs — no signature breaks; retest behavior

`scripts/buddy_overlay.gd` is the **only** file calling
`DisplayServer` (~38 call sites): `window_set_flag`
(`WINDOW_FLAG_BORDERLESS` / `ALWAYS_ON_TOP` / `TRANSPARENT`),
`window_set_mouse_passthrough(PackedVector2Array())`,
`window_get/set_position`, `window_get/set_current_screen`,
`window_get_size`, `screen_get_usable_rect`, `get_screen_count`,
`mouse_get_position`, `window_set_title`.

- **None of these appear in any 4.3–4.7 breaking-change table**, and
  all are present unchanged in current master class docs. Expect this
  file to parse and run unmodified.
- **Behavior retest is still mandatory** (Windows, real hardware):
  - Per-pixel transparency + borderless + always-on-top: known
    Windows edge cases exist in the 4.4/4.5 era, e.g.
    [godot#107582](https://github.com/godotengine/godot/issues/107582)
    (screen-sized transparent window renders black when focused,
    4.4.1) and
    [godot#109693](https://github.com/godotengine/godot/issues/109693)
    (transparency glitches — notably only when *not* borderless, which
    we are). Our 340×340 window shouldn't hit #107582, but this class
    of bug is why the exported-build gates exist. Retest:
    `_configure_window()` (`buddy_overlay.gd:229-238`), transparent
    clear color from `project.godot` (`[display]` per-pixel
    transparency + `[rendering]` clear color).
  - Per-frame `window_set_position` roaming and floor-lock
    (`_update_window_roam()`, `buddy_overlay.gd:763-814`), multi-
    monitor clamp/cycle (`_move_to_next_monitor()`, `_screen_rect()`,
    `_clamp_window_to_screen()`), and taskbar-aware
    `screen_get_usable_rect` behavior — retest on a 2-monitor setup
    with different DPI if available (RC scenarios 3 and 4 cover most
    of this; F8 covers monitor cycling).
  - Window state persistence across restart
    (`_restore_window_state()`, `buddy_overlay.gd:634-644` +
    `AppState.set_window_state`) — RC scenario 2.

### 4.2 Native subwindows — retest, active development area

`get_viewport().gui_embed_subwindows = false`
(`buddy_overlay.gd:232`) forces the F10 settings popout and chat
popout (`Window` nodes `$SettingsWindow`, `$ChatWindow` in
`scenes/BuddyOverlay.tscn`) to be real OS windows with their own
`always_on_top`. Multi-window/embedding code has been actively
reworked across 4.4–4.6 (editor embedded game window, etc.). No API
break affects us, but retest: popout opens as native window, stays on
top, closes via close button, `grab_focus()` works, layout clamping
via `screen_get_usable_rect` (`_layout_settings_window()` /
`_layout_chat_window()`).

### 4.3 GDScript — two items to audit, CI parse gate catches both

- **4.7 only** ([GH-115763](https://github.com/godotengine/godot/pull/115763)):
  overriding a method whose base declares a typed return now requires
  an explicit `return` in the override. Audit the class-extension
  chains (e.g. `runtime/actor/buddy_actor.gd`, behavior/test scripts
  extending shared bases). The CI parse check
  (`runtime-smoke.yml` "Parse check" step) fails loudly on this, so it
  cannot slip through. Not applicable if targeting 4.6.3.
- New GDScript **warnings** added across 4.3–4.6 (e.g. untyped
  declarations, shadowing — `_format_floor_adjust_text()` shadows the
  `sign()` built-in at `buddy_overlay.gd:1135`) may add console noise.
  The parse gate greps for `SCRIPT ERROR|Parse Error|error(s)`, so
  warnings don't fail CI, but check the noise doesn't obscure real
  errors in logs.
- **Confirmed non-issues:** all 79 `duplicate(true)` calls operate on
  `Dictionary`/`Array` values, not `Resource`s, so 4.5's
  `Resource.duplicate` semantic change doesn't apply (re-grep during
  the upgrade to be sure). `FileAccess.store_*` returning `bool`
  instead of `void` (4.4) is GDScript-compatible;
  `save_store.gd` unaffected. `FileAccess.get_as_text()` is always
  called without the removed `skip_cr` arg. No `TileMap`,
  `AnimationPlayer`, particles, shaders (`*.gdshader`: none), physics
  or navigation usage — the largest breaking-change categories in
  4.3–4.7 simply don't apply to this codebase.

### 4.4 Save data — unaffected, and rollback-safe

`scripts/persistence/save_store.gd` is pure **JSON via
`FileAccess`/`JSON.parse_string`/`JSON.stringify`** (no `store_var`,
no `ConfigFile`, no binary resources in `user://`). 4.3's binary
serialization change and `PackedByteArray` storage-format change
therefore do not touch user saves — saves written under 4.6.x remain
readable by a rolled-back 4.2.2 build and vice versa. This makes the
rollback story (§7) unusually clean.

### 4.5 Rendering — keep `gl_compatibility`, verify one setting

- `project.godot` pins `renderer/rendering_method="gl_compatibility"`.
  The Compatibility renderer remains fully supported through 4.7.
- 4.6 made **D3D12 the default rendering driver for *newly created*
  projects only**
  ([GH-113213](https://github.com/godotengine/godot/pull/113213));
  existing projects keep their settings. After first editor open,
  diff `project.godot` and confirm no rendering-driver key was
  injected/changed.
- 4.6's glow/environment default changes and 4.7's HDR output are 3D/
  Environment features we don't use (2D overlay, no `Environment`
  resource). 4.7's `CanvasItem` line-feather removal
  ([GH-105122](https://github.com/godotengine/godot/pull/105122))
  would slightly thin the `_draw()` fallback cross-lines and any
  balloon strokes — cosmetic only, 4.7-only.
- 4.5's **font oversampling rework** can subtly change text rendering
  in the telemetry overlay, settings popout and chat window
  (`Label`/`RichTextLabel`) — cosmetic retest under F6/F10.

### 4.6 Editor import plugin

`addons/buddy_importer/` (`EditorPlugin` + `EditorImportPlugin` with
`_import`, `_get_import_options(path, preset_index)`,
`_can_import_threaded`, etc.): no 4.3–4.7 breaking change hits these
virtuals. The CI "Headless import" steps exercise it on both OSes;
also re-import locally once and confirm `content/` resources load
(PackValidationTest covers fallback behavior).

### 4.7 Input (4.7 only)

4.7 changed mouse/keyboard device IDs to
`InputEvent.DEVICE_ID_MOUSE/KEYBOARD`
([GH-116274](https://github.com/godotengine/godot/pull/116274)).
`buddy_overlay.gd:_input()` dispatches on event *type*
(`InputEventKey`/`InputEventMouseButton`), never on `device`, so we're
unaffected — noted for completeness.

## 5. Mechanical churn to expect in the upgrade PR (not bugs)

1. **`.uid` sidecar files (4.4+):** first import generates a
   `<script>.uid` next to every `.gd` (~55 files). Per official
   guidance ([UID changes coming to Godot
   4.4](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/)),
   these must be **committed**, never gitignored (gitignoring breaks
   script references for every fresh clone). Expect ~55 new one-line
   files under `apps/runtime-godot/`.
2. **Scene re-saves (4.6 format):** `load_steps` dropped and unique
   node IDs added on re-save — large-looking but expected diffs across
   the 17 `.tscn` files. Run *Project → Tools → Upgrade Project
   Files…* once in the upgrade PR so the churn lands there instead of
   dribbling into later PRs. (4.5↔4.6 scene format is explicitly
   forward/backward compatible per the 4.6 upgrade guide.)
3. **`project.godot`:** `config/features=PackedStringArray("4.2")` →
   `("4.6")` (editor rewrites on save). Verify no other keys are
   injected beyond the features bump.
4. **`export_presets.cfg`:** opening the export dialog once will add
   new option keys introduced since 4.2 (D3D12/Agility SDK, ANGLE,
   codesign additions). Diff-review the regenerated file; the preset
   name **"Windows Desktop" must not change** — CI's export step
   hard-codes it (`runtime-smoke.yml:267`).
5. **CI env bump:** `GODOT_VERSION: "4.6.3"`,
   `GODOT_RELEASE: "4.6.3-stable"` in
   `.github/workflows/runtime-smoke.yml` (the only workflow that pins
   Godot; `content-validator.yml` and `python-lint.yml` don't).
   Verified the release-asset naming CI depends on is unchanged at
   4.6.3: `Godot_v4.6.3-stable_linux.x86_64.zip`,
   `Godot_v4.6.3-stable_win64.exe.zip`,
   `Godot_v4.6.3-stable_export_templates.tpz`. The
   `actions/cache` keys include `GODOT_RELEASE`, so caches roll over
   automatically; the templates path convention
   (`%APPDATA%\Godot\export_templates\<version>.stable`) is unchanged.
6. **Local tooling:** `tests/run_headless_checks.ps1`,
   `run_burn_in.ps1`, `run_plan5_gate.ps1`, `run_rc_scenario_suite.ps1`
   are all version-agnostic (whatever `godot` is on PATH / `-Godot`
   param) — **no script changes needed**, contributors just switch
   binaries.

## 6. Retest scope after the upgrade

| Surface | Where | Re-run? | Needs modification first? |
|---|---|---|---|
| Headless test suite (10 scenes) | CI `parse-and-smoke` job; locally `run_headless_checks.ps1` | Yes — free, runs on every PR commit | No |
| Windows export | CI `windows-export` job | Yes — verify `BuddyRuntime.exe` produced and launches | No (watch preset name) |
| RC scenario suite (9 scenarios) | `docs/product/RC_SCENARIO_SUITE.md`, exported build | **Yes, full pass** — engine swap invalidates all prior results. Most sensitive: 1 (first run), 2 (restart/window restore), 3 (drag), 9 (exported launch) | No; record engine version in the results log note line |
| Plan 5 manual checklist | `run_plan5_gate.ps1` / `SCENARIO_CHECKLIST.md` | **Yes** — it's the only gate that observes transparency/always-on-top/popouts on a live desktop | No |
| Perf burn-in | `PERF_BASELINE.md` recipe, `run_burn_in.ps1` (600 s short; 10 800 s release gate) | **Yes** — engine internals changed; treat the result as a **new baseline row**, not a pass/fail against 4.2.2 numbers. The mem-drift red flag (>~5 MB / 10 min) still applies as-is | Add a new baseline table row labeled with the engine version |

CI limitations to keep honest about: the Linux headless job proves
parsing/logic, the Windows job proves the export pipeline — **neither
observes a rendered transparent window**. The manual gates are the
acceptance test for this upgrade.

## 7. Rollback plan

Godot version is referenced in exactly three tracked files, all
changed by the same upgrade PR:

- `apps/runtime-godot/project.godot` (`config/features` — advisory tag)
- `.github/workflows/runtime-smoke.yml` (`GODOT_VERSION` +
  `GODOT_RELEASE` — the operative CI pin)
- `apps/runtime-godot/export_presets.cfg` (no literal version, but
  format/options are version-coupled)

**Rollback = `git revert` of the upgrade PR's commit(s).** That
restores all three files plus the `.tscn` re-saves and deletes the
`.uid` sidecars (4.2.2 neither needs nor understands them). CI caches
are keyed on `GODOT_RELEASE`, so the old 4.2.2 cache entries are still
valid after revert — no cache surgery.

Caveats and mitigations:

- **Post-upgrade edits shrink the revert window.** Any scene/script
  edited *after* the upgrade merges is saved in new-format and may not
  revert cleanly. Mitigation: cut the planned release tag first (the
  backlog already frames #87 as a *post-tag* migration — that tag is
  the rollback anchor), and hold follow-up runtime PRs until the
  upgrade has survived the §6 gates.
- **User saves are safe in both directions** — pure JSON (§4.4), no
  engine serialization formats in `user://`. A user who ran a 4.6.x
  build and rolls back to a 4.2.2 build keeps their profile;
  `save_store.gd`'s quarantine path handles any surprise corruption.
- **Contributors** must switch editor binaries back; local `.godot/`
  caches regenerate automatically either way.

## 8. What this unlocks — and what it doesn't

- **Unlocks item #1** (system tray icon with pause/quiet/settings/
  quit): `DisplayServer.create_status_indicator` (4.3+, confirmed §1),
  plus the `StatusIndicator` node and `FEATURE_STATUS_INDICATOR`
  feature flag for graceful degradation. Item **#28** (one-click DND
  *from the tray*) is transitively unblocked, since it builds on #1.
- **Nothing else in the backlog is gated on this.**
  `IMPROVEMENT_BACKLOG_BUILD_SEQUENCE.md` Wave 4 lists #87 as gating
  only #1. Other items (e.g. #5 DPI awareness, #7 fullscreen
  detection) may get *easier* on a newer engine but are not blocked
  today.

## 9. Recommended sequencing

**Two PRs, strictly ordered. Do not fold the tray icon into the
upgrade.**

1. **PR A — the upgrade** (after this plan is approved and the release
   tag is cut): bump `GODOT_VERSION`/`GODOT_RELEASE`, open the project
   once in 4.6.3, commit the mechanical churn (§5), fix anything the
   parse/headless gates surface, regenerate/diff-review
   `export_presets.cfg`. Evidence required in the PR: green CI on both
   jobs, full RC scenario table on the exported artifact, Plan 5 gate
   log, and a new perf-baseline row. Nothing behavioral changes on
   purpose in this PR — it should be boring.
2. **PR B — tray icon (item #1)** as a separate follow-up, on top of
   the proven engine. Keeping it separate means a tray-icon bug can't
   force an engine rollback, and an engine problem can't be confused
   with tray-icon code.

Optional stage 0 if the maintainer wants extra signal before PR A: a
throwaway branch that only bumps the CI env vars, to see the headless
suite + Windows export run on 4.6.3 without committing any project
churn. Cheap (one CI run) and answers "does anything explode"
before the real PR is drafted.

## 10. Honest risk assessment

- **Biggest risk:** Windows compositing behavior of the transparent
  always-on-top overlay across a 5-minor engine jump, with zero CI
  coverage of it. Known 4.4/4.5-era transparency issues (§4.1) were
  configuration-specific and our configuration (small borderless
  window) avoided the reported repro conditions — but that's exactly
  the kind of claim only RC scenarios 1–4 on real hardware can verify.
- **Second:** export-preset regeneration silently changing an option
  the Windows artifact depends on — mitigated by diff-review and the
  export job's hard check for the produced `.exe`.
- **Not risks for this codebase:** GDScript source breaks (audited:
  none for ≤4.6; one auditable rule for 4.7), save-data migration
  (JSON), renderer swap (we pin Compatibility), and the tray API
  version claim (verified 4.3, primary sources).
- If PR A's gates surface a transparency/always-on-top regression on
  4.6.3, the fallback is not "give up": test 4.5.x/4.4.x with the same
  branch (two-env-var change) to find the newest good version ≥4.3 —
  any of them still unblocks item #1.

## Sources

- Latest release: GitHub API `godotengine/godot` releases — latest =
  `4.7-stable` (2026-06-18); `4.6.3-stable` (2026-05-20).
- Godot release pages: [4.6](https://godotengine.org/releases/4.6/),
  [4.7](https://godotengine.org/releases/4.7/).
- Official upgrade guides (godotengine/godot-docs,
  `tutorials/migrating/`): `upgrading_to_godot_4.3.rst` … `4.7.rst`.
- Tray API introduction: `godotengine/godot` `4.3-stable`
  `CHANGELOG.md` ("Implement support for application status
  indicators (tray icons)",
  [GH-80211](https://github.com/godotengine/godot/pull/80211));
  `doc/classes/DisplayServer.xml` at `4.2-stable` (absent) vs
  `4.3-stable`/master (present).
- `.uid` files: [UID changes coming to Godot 4.4](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/).
- Transparency issue history:
  [godot#107582](https://github.com/godotengine/godot/issues/107582),
  [godot#109693](https://github.com/godotengine/godot/issues/109693).
- Release asset naming at 4.6.3 verified against the official
  SourceForge mirror listing for `4.6.3-stable`.
