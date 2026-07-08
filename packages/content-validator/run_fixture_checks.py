#!/usr/bin/env python3
"""Run manifest and schema validation checks over known fixtures and runtime packs."""

from __future__ import annotations

import json
from pathlib import Path

from validate_pack import ValidationError, validate_manifest, validate_schema_document


def load_dict(path: Path) -> dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"Root must be object: {path}")
    return raw


def report(kind: str, path: Path, errors: list[ValidationError], should_be_valid: bool) -> int:
    is_valid = len(errors) == 0
    if is_valid == should_be_valid:
        print(f"PASS ({kind}): {path}")
        return 0

    expected = "valid" if should_be_valid else "invalid"
    actual = "valid" if is_valid else "invalid"
    print(f"FAIL ({kind}): {path} expected {expected} but got {actual}")
    for err in errors:
        print(f"  - {err.format()}")
    return 1


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    fixtures_dir = Path(__file__).resolve().parent / "fixtures"
    content_dir = repo_root / "apps" / "runtime-godot" / "content"

    # (path, should_be_valid)
    manifest_checks = [
        (content_dir / "core_pack" / "manifest.json", True),
        (content_dir / "night_pack" / "manifest.json", True),
        (content_dir / "sample_pack" / "manifest.json", True),
        (fixtures_dir / "invalid_missing_action.json", False),
    ]

    # Schema fixtures live under fixtures/schema/, kept separate from the
    # manifest fixtures above so a future glob over fixtures/ can't
    # accidentally feed a schema-shaped file into validate_manifest (or
    # vice versa) and misreport it as "should pass".
    schema_checks = [
        (repo_root / "packages" / "content-schema" / "buddy-pack.schema.json", True),
        (fixtures_dir / "schema" / "malformed_schema.json", False),
    ]

    failures = 0
    for path, should_be_valid in manifest_checks:
        manifest = load_dict(path)
        errors = validate_manifest(manifest)
        failures += report("manifest", path, errors, should_be_valid)

    for path, should_be_valid in schema_checks:
        schema = load_dict(path)
        errors = validate_schema_document(schema)
        failures += report("schema", path, errors, should_be_valid)

    if failures:
        print(f"Fixture checks failed: {failures}")
        return 1
    print("All fixture checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
