# Windows Packaging & Signing

Decisions locked in PR-07. Anything not listed here is deferred to a
later release.

## Artifact layout

The `buddy-runtime-windows` CI artifact contains:

```
buddy-runtime-windows/
├── BuddyRuntime.exe     # Godot runner + embedded or paired .pck
├── BuddyRuntime.pck     # Content pack (absent if embed_pck=true)
└── SHA256SUMS           # One line per file: "<sha256>  <relative path>"
```

No extra runtime DLLs. Godot 4.2 statically links the Windows runtime
surface we depend on.

`embed_pck` is currently `false` (see `export_presets.cfg`). Shipping
the `.pck` as a sibling keeps the `.exe` debuggable with stock Godot
tooling. Switching to embedded is a later packaging decision, not a
release blocker.

## Where saves live

`%APPDATA%\Godot\app_userdata\Buddy Runtime\`

Keys:

- `settings.json`
- `profile.json`
- `world_state.json`
- `perf/idle_profile_<unix>.log` (after PR-06 burn-ins)

These are versioned and corruption-recoverable — see PR-03 /
`scripts/persistence/save_store.gd`.

## Signing decision

**V1 ships unsigned.** Rationale:

- No corporate cert yet; acquiring one pre-V1 is out of scope.
- Self-signed certs trigger a worse SmartScreen experience than an
  unsigned binary (adds a "publisher unknown — untrusted" path).
- SmartScreen "More info → Run anyway" path is documented in the
  release notes (PR-15).

When we do sign, the signing step lives in CI after the export step
with certs pulled from GitHub secrets. Placeholder — do not enable
on merge. See `codesign/enable=false` in `export_presets.cfg`.

## Version / metadata

Locked in `export_presets.cfg`:

| Field                    | Value                              |
|--------------------------|------------------------------------|
| `product_name`           | `Buddy Runtime`                    |
| `company_name`           | `Buddy Assembler`                  |
| `file_version`           | `0.1.0.0`                          |
| `product_version`        | `0.1.0.0`                          |
| `file_description`       | `Desktop companion runtime`        |
| `copyright`              | `Buddy Assembler contributors`     |

`debug/export_console_wrapper=0` — the release build does not open a
secondary console window. This matches the buddy overlay UX (a
separate console window would be jarring).

## CI gates

The export preset uses a positive selected-resources closure. The approved
source roots, exact JSON control plane, and exact generated PCK directory are
reviewed together in `packages/content-validator/shipping_inventory.json`.
Anything outside that inventory is absent by default, including sample packs,
tests, tools, vertical-slice, imported/intermediate, WZ/NX, ignored, and
workstation-local content.

1. `validate_shipping_closure.py` checks the tracked manifest dependency
   graph and exact positive export declaration. Release artifact unit tests
   prove missing, mismatched, unlisted, and unexpected PCK files fail closed.
2. `windows-export` installs SHA256-pinned `rcedit` v2.0.0 and fails on a
   non-zero export or any exporter error line.
3. The produced executable's Windows `VersionInfo` must exactly match the
   company, product, description, and versions declared in
   `export_presets.cfg`; `Godot Engine` metadata is rejected.
4. The actual `BuddyRuntime.pck` directory must exactly equal the approved
   `pck_files` inventory.
5. The exported executable runs `--verify-export-closure` and must emit the
   exact `export_closure_check: PASS` marker after proving required resources
   present and development sentinels absent.
6. The EXE and PCK are copied into a download-equivalent staging root.
   `SHA256SUMS` uses paths relative to that root and is verified successfully
   from inside it before upload.
7. Release tag cut only after RC scenario suite
   (`RC_SCENARIO_SUITE.md`) passes on the artifact.

## Release-time checklist

Short version — the full gate is `RELEASE_CHECKLIST.md`.

- [ ] Download the tagged CI artifact; verify SHA256SUMS matches.
- [ ] Unzip to a test machine without Godot editor installed.
- [ ] Run all nine `RC_SCENARIO_SUITE.md` scenarios.
- [ ] Record 10-min and multi-hour entries in `PERF_BASELINE.md`.
- [ ] Draft release notes including the SmartScreen "Run anyway"
      instruction.
- [ ] Tag, publish, record previous-good tag as rollback pointer.
