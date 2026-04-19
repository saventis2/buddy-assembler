#!/usr/bin/env python3
"""Run manifest validation checks over known fixtures and runtime packs."""

from __future__ import annotations

import json
from pathlib import Path

from validate_pack import validate_manifest


def load_dict(path: Path) -> dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"Root must be object: {path}")
    return raw


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    checks = [
        (repo_root / "apps" / "runtime-godot" / "content" / "core_pack" / "manifest.json", True),
        (repo_root / "apps" / "runtime-godot" / "content" / "night_pack" / "manifest.json", True),
        (Path(__file__).resolve().parent / "fixtures" / "invalid_missing_action.json", False),
    ]

    failures = 0
    for path, should_be_valid in checks:
        manifest = load_dict(path)
        errors = validate_manifest(manifest)
        is_valid = len(errors) == 0
        if is_valid != should_be_valid:
            failures += 1
            expected = "valid" if should_be_valid else "invalid"
            print(f"FAIL: {path} expected {expected} but got {'valid' if is_valid else 'invalid'}")
            if errors:
                for err in errors:
                    print(f"  - {err}")
        else:
            print(f"PASS: {path}")

    if failures:
        print(f"Fixture checks failed: {failures}")
        return 1
    print("All fixture checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

