# Content Validator

Local validator for buddy content manifests.

This validator is intentionally dependency-free and performs structural checks
against the V1 contract in `packages/content-schema/buddy-pack.schema.json`.

**Design note:** `validate_pack.py` does not load `buddy-pack.schema.json` and
evaluate it with a real JSON Schema engine (e.g. the `jsonschema` PyPI
package) — there is no such engine here. The checks in `validate_manifest()`
are written by hand to mirror that schema's intent, and the two files have to
be kept in sync manually when either one changes. `buddy-pack.schema.json`
pins its JSON Schema draft explicitly via
`"$schema": "https://json-schema.org/draft/2020-12/schema"`; `--check-schema`
(below) is what actually enforces that pin and checks the document's
structure, since nothing else in this repo interprets `$schema` at all.

## Usage

```powershell
python validate_pack.py ..\..\apps\runtime-godot\content\core_pack\manifest.json
```

Returns non-zero exit code when validation fails. Failures report the JSON
path of the offending field (e.g. `manifest.eventRules[2].action`) plus a
one-line hint on how to fix it. For on-disk packs, validation also resolves
animation sheets and other declared visual dependencies, and rejects missing,
ignored, untracked, drive-letter, absolute, traversal, and workstation-local
paths.

Manifests must declare the schema semver contract: `schemaSemver`
(`MAJOR.MINOR.PATCH`) whose major equals the integer `schemaVersion`. An
unsupported major is rejected. A newer minor within the supported major is
accepted with a `WARNING:` line (exit 0). A newer patch is accepted
silently. Policy and bump procedure: `docs/product/CONTENT_SCHEMA.md`
("Schema versioning"). Per-version notes:
`docs/product/CONTENT_SCHEMA_MIGRATIONS.md`. Run
`python -m pytest test_validate_pack.py` for the contract tests.

Run `python validate_shipping_closure.py` from any directory to verify the
two user packs, the development-pack boundary, and the reviewed Windows
positive export declaration in `shipping_inventory.json`.

`release_artifact_checks.py` reads the actual unencrypted Godot 4.2 PCK
directory and compares it to that same contract. It also writes and verifies
artifact-root-relative `SHA256SUMS` manifests. Run
`python test_release_artifact_checks.py` for missing, mismatched, unlisted,
unexpected-PCK-file, and PCK-parser negative coverage.

```
INVALID manifest -> ...\fixtures\invalid_missing_action.json
- manifest.eventRules[0].action: must be a non-empty string, found missing (hint: Add an "action" field naming the action id this rule triggers; it should match an entry in idleActions/reactionActions/encounterActions.)
```

## Schema self-check

```powershell
python validate_pack.py --check-schema
```

Checks that `packages/content-schema/buddy-pack.schema.json` (or an explicit
path passed as a second argument) is itself well-formed: valid JSON *and* a
structurally sound JSON Schema document for the keyword subset this project
uses (`type`, `properties`, `required`, `items`, `additionalProperties`,
length/numeric bounds, `enum`, and that `$schema` is pinned to draft
2020-12). This is a hand-rolled structural check, not a full meta-schema
validator — see the module docstring in `validate_pack.py` for the exact
keyword list covered.

## Fixture Checks

```powershell
python run_fixture_checks.py
```

Runs known-good and known-bad manifests (including all three on-disk content
packs: `core_pack`, `night_pack`, `sample_pack`) plus known-good and
known-bad schema documents (`fixtures/schema/`) to guard validator behavior.
Schema fixtures live in their own `fixtures/schema/` subdirectory, separate
from manifest fixtures in `fixtures/`, so the two kinds are never accidentally
cross-checked.

## Headless suite: limits, timings and the machine lock

`headless_suite.py` runs the required Godot suite (`required_headless_scenes.json`)
for both the local gate and CI.

- **Timings.** Every case prints `headless_suite[<id>]: took <seconds> s (limit <n> s)`,
  so limits come from measurements.
- **Per-case limits.** A case may carry `"timeout_seconds"`, an integer from 1 to 600.
  Set it to about 1.5x the case's p95 time over at least five local runs. Every other
  case uses the runner's `--timeout` (90 in CI and locally). There is no global raise
  and no local-only override.
- **Limits are gate authority.** The contract file is not protected, so
  `validate_ci_contract.py` accepts a case's limit only if it is on its protected
  allow-list (`_CASE_TIMEOUT_SECONDS_ALLOWED`), and no larger. Raising one needs the
  same owner-merged change as the workflows, with the measurements in it.
- **The machine lock.** One required suite or capture runs at a time on a machine. A
  second Godot run shares the CPU, pushes slow cases past their limits and spoils
  timings, so it is refused, not warned. It exits 2, naming the lock file:
  `buddy-runtime-godot.lock` in the user's temp folder on Windows, or
  `buddy-runtime-godot-<uid>.lock` in the shared temp folder elsewhere.
  - The lock is an OS file lock, so it is released when its holder exits, even on a
    crash.
  - The file is opened without following symlinks where the system allows it.
  - Capture tools take the same lock.
  - A Godot child left running after its runner was killed outlives the lock, so stop
    it before starting another run.

## CI tripwires (council Q2)

CI runs every check on every PR. A newer push to a pull request cancels that pull
request's older run. Runs on main are never cancelled.

That policy holds only while the repository is public, which keeps standard-runner
minutes unbilled, and while runs stay quick. Two tripwires watch it:

- **Visibility.** The Runtime smoke workflow fails on every run if the repository is
  not public.
- **Speed.** Before pushing a row, run the local check:

  ```powershell
  python packages/content-validator/ci_tripwires.py
  ```

  It reads the repository's visibility and the last three completed Runtime smoke runs
  on main through `gh`, read-only. It fails when the median queue wait is over 5
  minutes or the median run is over 6.

Either trip means CI moves to the gated policy: the Linux pack and `verify-pck` on every
PR, with the Windows export gated. The workflows are protected by gate authority, so
only the owner can land that change.
