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
one-line hint on how to fix it:

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
