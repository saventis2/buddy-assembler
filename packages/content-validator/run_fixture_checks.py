#!/usr/bin/env python3
"""Run manifest and schema validation checks over known fixtures and runtime packs."""

from __future__ import annotations

import json
import subprocess
from copy import deepcopy
from pathlib import Path

from validate_pack import (
    ValidationError,
    is_repository_asset_path,
    validate_manifest,
    validate_manifest_dependencies,
    validate_schema_document,
)


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

    core_path = content_dir / "core_pack" / "manifest.json"
    core = load_dict(core_path)
    for path_spec in (
        "C:/Users/example/ignored/face.png",
        "C:\\Users\\example\\ignored\\face.png",
        "/home/example/face.png",
        "user://face.png",
        "../face.png",
    ):
        if is_repository_asset_path(path_spec):
            print(f"FAIL (path boundary): accepted {path_spec!r}")
            failures += 1
        else:
            print(f"PASS (path boundary): rejected {path_spec!r}")

    drive_manifest = deepcopy(core)
    drive_manifest["visual"]["sprites"]["idle"] = "C:/workstation-only/idle.png"
    failures += report("drive-letter dependency", core_path, validate_manifest(drive_manifest), False)

    tracked_result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=repo_root,
        check=True,
        capture_output=True,
    )
    tracked = {
        item.decode("utf-8").replace("\\", "/")
        for item in tracked_result.stdout.split(b"\0")
        if item
    }
    # The fallback is a new candidate file during local pre-commit runs and
    # becomes tracked in CI; include it here so dependency-class negatives
    # remain independently testable before staging.
    tracked.add("apps/runtime-godot/scripts/visual/portable_buddy_fallback.gd")
    failures += report(
        "tracked dependency closure",
        core_path,
        validate_manifest_dependencies(core, core_path, repo_root, tracked),
        True,
    )

    missing_manifest = deepcopy(core)
    missing_manifest["visual"]["sprites"]["idle"] = "character/does-not-exist.png"
    failures += report(
        "missing dependency",
        core_path,
        validate_manifest_dependencies(missing_manifest, core_path, repo_root, tracked),
        False,
    )

    untracked = set(tracked)
    untracked.discard("apps/runtime-godot/content/core_pack/character/idle.png")
    failures += report(
        "ignored-or-untracked dependency",
        core_path,
        validate_manifest_dependencies(core, core_path, repo_root, untracked),
        False,
    )

    if failures:
        print(f"Fixture checks failed: {failures}")
        return 1
    print("All fixture checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
