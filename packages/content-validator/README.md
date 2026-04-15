# Content Validator

Local validator for buddy content manifests.

This validator is intentionally dependency-free and performs structural checks
against the V1 contract in `packages/content-schema/buddy-pack.schema.json`.

## Usage

```powershell
python validate_pack.py ..\..\apps\runtime-godot\content\core_pack\manifest.json
```

Returns non-zero exit code when validation fails.

## Fixture Checks

```powershell
python run_fixture_checks.py
```

Runs known-good and known-bad manifests to guard validator behavior.
