#!/usr/bin/env python3
"""Minimal dependency-free validator for Buddy content packs."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def expect_type(value: Any, expected: type, field: str, errors: list[str]) -> None:
    if not isinstance(value, expected):
        errors.append(f"{field} must be {expected.__name__}")


def expect_non_empty_string(value: Any, field: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{field} must be a non-empty string")


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    required_root = [
        "schemaVersion",
        "id",
        "name",
        "version",
        "companion",
        "idleActions",
        "reactionActions",
        "encounterActions",
        "eventRules",
    ]
    for key in required_root:
        if key not in manifest:
            errors.append(f"Missing required field: {key}")

    if errors:
        return errors

    if not isinstance(manifest["schemaVersion"], int) or manifest["schemaVersion"] < 1:
        errors.append("schemaVersion must be integer >= 1")
    expect_non_empty_string(manifest["id"], "id", errors)
    expect_non_empty_string(manifest["name"], "name", errors)
    expect_non_empty_string(manifest["version"], "version", errors)

    companion = manifest["companion"]
    expect_type(companion, dict, "companion", errors)
    if isinstance(companion, dict):
        expect_non_empty_string(companion.get("id"), "companion.id", errors)
        expect_non_empty_string(companion.get("displayName"), "companion.displayName", errors)
        traits = companion.get("traits")
        expect_type(traits, list, "companion.traits", errors)
        if isinstance(traits, list):
            for i, trait in enumerate(traits):
                expect_non_empty_string(trait, f"companion.traits[{i}]", errors)

    visual = manifest.get("visual")
    if visual is not None:
        expect_type(visual, dict, "visual", errors)
        if isinstance(visual, dict):
            scale = visual.get("scale")
            if scale is not None and (not isinstance(scale, (float, int)) or float(scale) <= 0):
                errors.append("visual.scale must be > 0 when set")

            anchor = visual.get("anchor")
            if anchor is not None:
                expect_type(anchor, list, "visual.anchor", errors)
                if isinstance(anchor, list):
                    if len(anchor) != 2:
                        errors.append("visual.anchor must have exactly 2 numbers")
                    else:
                        for i, value in enumerate(anchor):
                            if not isinstance(value, (float, int)):
                                errors.append(f"visual.anchor[{i}] must be numeric")

            animations = visual.get("animations")
            if animations is not None:
                expect_type(animations, dict, "visual.animations", errors)
                if isinstance(animations, dict):
                    for key, value in animations.items():
                        expect_non_empty_string(key, "visual.animations key", errors)
                        expect_non_empty_string(value, f"visual.animations[{key}]", errors)

            sprites = visual.get("sprites")
            if sprites is not None:
                expect_type(sprites, dict, "visual.sprites", errors)
                if isinstance(sprites, dict):
                    for key, value in sprites.items():
                        expect_non_empty_string(key, "visual.sprites key", errors)
                        expect_non_empty_string(value, f"visual.sprites[{key}]", errors)

    for field in ("idleActions", "reactionActions", "encounterActions"):
        value = manifest[field]
        expect_type(value, list, field, errors)
        if isinstance(value, list):
            if field != "encounterActions" and not value:
                errors.append(f"{field} must not be empty")
            for i, item in enumerate(value):
                expect_non_empty_string(item, f"{field}[{i}]", errors)

    event_rules = manifest["eventRules"]
    expect_type(event_rules, list, "eventRules", errors)
    if isinstance(event_rules, list):
        for i, event in enumerate(event_rules):
            if not isinstance(event, dict):
                errors.append(f"eventRules[{i}] must be object")
                continue
            expect_non_empty_string(event.get("id"), f"eventRules[{i}].id", errors)
            expect_non_empty_string(event.get("action"), f"eventRules[{i}].action", errors)
            weight = event.get("weight")
            if not isinstance(weight, (float, int)) or float(weight) <= 0:
                errors.append(f"eventRules[{i}].weight must be > 0")
            cooldown = event.get("cooldownSeconds")
            if not isinstance(cooldown, int) or cooldown < 1:
                errors.append(f"eventRules[{i}].cooldownSeconds must be integer >= 1")
            per_hour = event.get("perHour")
            if per_hour is not None and (not isinstance(per_hour, int) or per_hour < 1):
                errors.append(f"eventRules[{i}].perHour must be integer >= 1 when set")
            per_day = event.get("perDay")
            if per_day is not None and (not isinstance(per_day, int) or per_day < 1):
                errors.append(f"eventRules[{i}].perDay must be integer >= 1 when set")

    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python validate_pack.py <manifest.json>")
        return 2

    path = Path(sys.argv[1]).resolve()
    if not path.exists():
        print(f"ERROR: file not found: {path}")
        return 2

    try:
        raw = load_json(path)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: invalid JSON: {exc}")
        return 2

    if not isinstance(raw, dict):
        print("ERROR: manifest root must be JSON object")
        return 2

    errors = validate_manifest(raw)
    if errors:
        print("INVALID manifest:")
        for err in errors:
            print(f"- {err}")
        return 1

    print(f"OK: manifest valid -> {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
