#!/usr/bin/env python3
"""Minimal dependency-free validator for Buddy content packs.

Design note (see README.md for the full write-up): this module is a
hand-rolled, dependency-free structural checker. It does NOT load
``buddy-pack.schema.json`` and evaluate it with a real JSON Schema engine
(e.g. the ``jsonschema`` PyPI package) -- there is no such engine in this
codebase. The checks below are written by hand to mirror that schema's
intent, and the two files must be kept in sync manually.

``buddy-pack.schema.json`` pins its JSON Schema draft explicitly via
``"$schema": "https://json-schema.org/draft/2020-12/schema"``. That pin is
enforced and structurally checked by ``validate_schema_document`` below
(exposed as ``--check-schema`` on the CLI) -- it does not mean manifest
validation in this file follows draft 2020-12 keyword-for-keyword; it means
the *reference schema document* is unambiguous about which draft its
authors intended, and that intent is checked automatically instead of
silently rotting.
"""

from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TypeGuard

MANIFEST_ROOT = "manifest"
SCHEMA_ROOT = "schema"

# The JSON Schema draft that packages/content-schema/buddy-pack.schema.json
# is expected to declare via its own top-level "$schema" key. Kept as a
# constant so `--check-schema` fails loudly (with a clear hint) if the two
# ever drift apart.
EXPECTED_SCHEMA_DRAFT = "https://json-schema.org/draft/2020-12/schema"

JSON_SCHEMA_PRIMITIVE_TYPES = {
    "null",
    "boolean",
    "object",
    "array",
    "number",
    "string",
    "integer",
}

DEFAULT_SCHEMA_PATH = (
    Path(__file__).resolve().parents[1] / "content-schema" / "buddy-pack.schema.json"
)


@dataclass
class ValidationError:
    """One validation failure, with enough context to fix it without cross-referencing the schema."""

    path: str
    problem: str
    hint: str

    def format(self) -> str:
        return f"{self.path}: {self.problem} (hint: {self.hint})"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def is_bool(value: Any) -> bool:
    return isinstance(value, bool)


def is_int(value: Any) -> TypeGuard[int]:
    return isinstance(value, int) and not is_bool(value)


def is_number(value: Any) -> TypeGuard[int | float]:
    return isinstance(value, (int, float)) and not is_bool(value)


def describe(value: Any) -> str:
    """Short human-readable description of a JSON value's shape, for error text."""
    if value is None:
        return "missing"
    if isinstance(value, str):
        return "an empty/blank string" if not value.strip() else f"string {value!r}"
    if isinstance(value, bool):
        return f"boolean {value!r}"
    return f"{type(value).__name__} {value!r}" if not isinstance(value, (dict, list)) else type(value).__name__


def add_error(errors: list[ValidationError], path: str, problem: str, hint: str) -> None:
    errors.append(ValidationError(path=path, problem=problem, hint=hint))


def expect_type(
    value: Any,
    expected: type,
    path: str,
    errors: list[ValidationError],
    hint: str | None = None,
) -> bool:
    if not isinstance(value, expected):
        add_error(
            errors,
            path,
            f"must be {expected.__name__}, found {describe(value)}",
            hint or f'Set "{path}" to a {expected.__name__}.',
        )
        return False
    return True


def expect_non_empty_string(
    value: Any,
    path: str,
    errors: list[ValidationError],
    hint: str | None = None,
) -> bool:
    if not isinstance(value, str) or not value.strip():
        add_error(
            errors,
            path,
            f"must be a non-empty string, found {describe(value)}",
            hint or f'Set "{path}" to a non-empty string.',
        )
        return False
    return True


def is_repository_asset_path(path_spec: Any) -> bool:
    """Match the runtime's portable-path boundary for shipping dependencies."""
    if not isinstance(path_spec, str):
        return False
    path = path_spec.strip()
    if not path or "\\" in path:
        return False
    if path.startswith(("/", "user://", "file://")):
        return False
    if len(path) >= 2 and path[1] == ":":
        return False
    if "://" in path and not path.startswith("res://"):
        return False
    relative = path.removeprefix("res://")
    return bool(relative) and ":" not in relative and ".." not in relative.split("/")


# ---------------------------------------------------------------------------
# Manifest validation (packages/content-schema/buddy-pack.schema.json V1)
# ---------------------------------------------------------------------------


def validate_manifest(manifest: dict[str, Any]) -> list[ValidationError]:
    errors: list[ValidationError] = []
    root = MANIFEST_ROOT

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
            add_error(
                errors,
                f"{root}.{key}",
                "is missing",
                f'Add a top-level "{key}" field to the manifest '
                "(see docs/product/CONTENT_SCHEMA.md for the expected shape).",
            )

    if errors:
        return errors

    schema_version = manifest["schemaVersion"]
    if not is_int(schema_version) or schema_version < 1:
        add_error(
            errors,
            f"{root}.schemaVersion",
            f"must be an integer >= 1, found {describe(schema_version)}",
            'Set "schemaVersion" to 1 (the current CONTENT_SCHEMA_VERSION) '
            "unless this pack intentionally targets a newer runtime.",
        )

    expect_non_empty_string(
        manifest["id"],
        f"{root}.id",
        errors,
        'Set "id" to a non-empty string matching the pack\'s directory name, e.g. "night_pack".',
    )
    expect_non_empty_string(
        manifest["name"],
        f"{root}.name",
        errors,
        'Set "name" to the human-readable display name for this pack, e.g. "Night Pack".',
    )
    expect_non_empty_string(
        manifest["version"],
        f"{root}.version",
        errors,
        'Set "version" to a semver string, e.g. "1.0.0".',
    )

    runtime_audience = manifest.get("runtimeAudience", "user")
    if runtime_audience not in ("user", "development"):
        add_error(
            errors,
            f"{root}.runtimeAudience",
            f"must be 'user' or 'development', found {describe(runtime_audience)}",
            'Use "user" for production-cycle packs or "development" for explicit developer-only packs.',
        )

    companion = manifest["companion"]
    companion_path = f"{root}.companion"
    if expect_type(
        companion,
        dict,
        companion_path,
        errors,
        'Define "companion" as an object with "id", "displayName", and "traits".',
    ):
        expect_non_empty_string(
            companion.get("id"),
            f"{companion_path}.id",
            errors,
            'Set "companion.id" to a non-empty string identifying this companion, e.g. "night_buddy".',
        )
        expect_non_empty_string(
            companion.get("displayName"),
            f"{companion_path}.displayName",
            errors,
            'Set "companion.displayName" to the name shown to players, e.g. "Night Buddy".',
        )
        traits = companion.get("traits")
        traits_path = f"{companion_path}.traits"
        if expect_type(
            traits,
            list,
            traits_path,
            errors,
            'Set "companion.traits" to an array of short trait strings, e.g. ["calm", "playful"].',
        ):
            for i, trait in enumerate(traits):
                expect_non_empty_string(
                    trait,
                    f"{traits_path}[{i}]",
                    errors,
                    "Each trait must be a non-empty string, e.g. \"calm\".",
                )

    visual = manifest.get("visual")
    if visual is not None:
        visual_path = f"{root}.visual"
        if expect_type(
            visual,
            dict,
            visual_path,
            errors,
            'Define "visual" as an object, or omit the "visual" key entirely to use the code-drawn placeholder.',
        ):
            face_mode = visual.get("faceMode", "embedded")
            if face_mode not in ("embedded", "overlay_or_code"):
                add_error(
                    errors,
                    f"{visual_path}.faceMode",
                    f"must be 'embedded' or 'overlay_or_code', found {describe(face_mode)}",
                    'Use "overlay_or_code" for the repository-authored portable face fallback.',
                )
            scale = visual.get("scale")
            if scale is not None and (not is_number(scale) or float(scale) <= 0):
                add_error(
                    errors,
                    f"{visual_path}.scale",
                    f"must be > 0 when set, found {describe(scale)}",
                    'Set "visual.scale" to a number greater than 0 (e.g. 1.0), or remove the "scale" key to use the default.',
                )

            anchor = visual.get("anchor")
            if anchor is not None:
                anchor_path = f"{visual_path}.anchor"
                if expect_type(
                    anchor,
                    list,
                    anchor_path,
                    errors,
                    'Set "visual.anchor" to a two-number array [x, y], e.g. [0.5, 1.0], or remove the key.',
                ):
                    if len(anchor) != 2:
                        add_error(
                            errors,
                            anchor_path,
                            f"must have exactly 2 numbers, found {len(anchor)}",
                            'Set "visual.anchor" to normalized [x, y] coordinates, e.g. [0.5, 1.0].',
                        )
                    else:
                        for i, value in enumerate(anchor):
                            if not is_number(value):
                                add_error(
                                    errors,
                                    f"{anchor_path}[{i}]",
                                    f"must be numeric, found {describe(value)}",
                                    "Each anchor coordinate must be a number, typically between 0 and 1.",
                                )

            animations = visual.get("animations")
            if animations is not None:
                animations_path = f"{visual_path}.animations"
                if expect_type(
                    animations,
                    dict,
                    animations_path,
                    errors,
                    'Set "visual.animations" to an object mapping action names to animation JSON paths.',
                ):
                    for key, value in animations.items():
                        expect_non_empty_string(
                            key,
                            f"{animations_path} key",
                            errors,
                            "Animation keys must be non-empty action-name strings, e.g. \"idle\".",
                        )
                        expect_non_empty_string(
                            value,
                            f"{animations_path}[{key}]",
                            errors,
                            'Set this to a path like "character/animations/idle.json".',
                        )
                        if isinstance(value, str) and not is_repository_asset_path(value):
                            add_error(
                                errors,
                                f"{animations_path}[{key}]",
                                "must be a repository-relative or res:// asset path",
                                "Remove drive-letter, absolute, user://, traversal, and workstation-local paths.",
                            )

            sprites = visual.get("sprites")
            if sprites is not None:
                sprites_path = f"{visual_path}.sprites"
                if expect_type(
                    sprites,
                    dict,
                    sprites_path,
                    errors,
                    'Set "visual.sprites" to an object mapping action names to sprite image paths.',
                ):
                    for key, value in sprites.items():
                        expect_non_empty_string(
                            key,
                            f"{sprites_path} key",
                            errors,
                            "Sprite keys must be non-empty action-name strings, e.g. \"idle\".",
                        )
                        expect_non_empty_string(
                            value,
                            f"{sprites_path}[{key}]",
                            errors,
                            'Set this to a path like "character/idle.png".',
                        )
                        if isinstance(value, str) and not is_repository_asset_path(value):
                            add_error(
                                errors,
                                f"{sprites_path}[{key}]",
                                "must be a repository-relative or res:// asset path",
                                "Remove drive-letter, absolute, user://, traversal, and workstation-local paths.",
                            )

            emotes = visual.get("emotes")
            if isinstance(emotes, dict) and "manifest" in emotes:
                emote_path = emotes.get("manifest")
                if not is_repository_asset_path(emote_path):
                    add_error(
                        errors,
                        f"{visual_path}.emotes.manifest",
                        "must be a repository-relative or res:// asset path",
                        "Remove drive-letter, absolute, user://, traversal, and workstation-local paths.",
                    )

            ground = visual.get("ground")
            if isinstance(ground, dict) and ground.get("texture") is not None:
                ground_path = ground.get("texture")
                if not is_repository_asset_path(ground_path):
                    add_error(
                        errors,
                        f"{visual_path}.ground.texture",
                        "must be a repository-relative or res:// asset path",
                        "Remove drive-letter, absolute, user://, traversal, and workstation-local paths.",
                    )

    for field in ("idleActions", "reactionActions", "encounterActions"):
        value = manifest[field]
        field_path = f"{root}.{field}"
        if expect_type(
            value,
            list,
            field_path,
            errors,
            f'Set "{field}" to an array of action id strings.',
        ):
            if field != "encounterActions" and not value:
                add_error(
                    errors,
                    field_path,
                    "must not be empty",
                    f'Add at least one action id to "{field}", e.g. ["idle"].',
                )
            for i, item in enumerate(value):
                expect_non_empty_string(
                    item,
                    f"{field_path}[{i}]",
                    errors,
                    f'Each entry in "{field}" must be a non-empty action id string.',
                )

    event_rules = manifest["eventRules"]
    event_rules_path = f"{root}.eventRules"
    if expect_type(
        event_rules,
        list,
        event_rules_path,
        errors,
        'Set "eventRules" to an array (it may be empty, e.g. []).',
    ):
        for i, event in enumerate(event_rules):
            event_path = f"{event_rules_path}[{i}]"
            if not isinstance(event, dict):
                add_error(
                    errors,
                    event_path,
                    f"must be an object, found {describe(event)}",
                    'Each event rule must be an object with "id", "action", "weight", and "cooldownSeconds".',
                )
                continue

            expect_non_empty_string(
                event.get("id"),
                f"{event_path}.id",
                errors,
                'Set "id" to a unique non-empty string naming this event rule.',
            )
            expect_non_empty_string(
                event.get("action"),
                f"{event_path}.action",
                errors,
                'Add an "action" field naming the action id this rule triggers; it should match an entry '
                "in idleActions/reactionActions/encounterActions.",
            )
            weight = event.get("weight")
            if not is_number(weight) or float(weight) <= 0:
                add_error(
                    errors,
                    f"{event_path}.weight",
                    f"must be > 0, found {describe(weight)}",
                    'Set "weight" to a number greater than 0 controlling this event\'s relative pick '
                    "frequency, e.g. 1.0.",
                )
            cooldown = event.get("cooldownSeconds")
            if not is_int(cooldown) or cooldown < 1:
                add_error(
                    errors,
                    f"{event_path}.cooldownSeconds",
                    f"must be an integer >= 1, found {describe(cooldown)}",
                    'Set "cooldownSeconds" to the minimum number of seconds between repeats of this event.',
                )
            per_hour = event.get("perHour")
            if per_hour is not None and (not is_int(per_hour) or per_hour < 1):
                add_error(
                    errors,
                    f"{event_path}.perHour",
                    f"must be an integer >= 1 when set, found {describe(per_hour)}",
                    'Set "perHour" to a positive integer cap, or omit the key entirely for no cap.',
                )
            per_day = event.get("perDay")
            if per_day is not None and (not is_int(per_day) or per_day < 1):
                add_error(
                    errors,
                    f"{event_path}.perDay",
                    f"must be an integer >= 1 when set, found {describe(per_day)}",
                    'Set "perDay" to a positive integer cap, or omit the key entirely for no cap.',
                )

    return errors


def _tracked_repo_paths(repo_root: Path) -> set[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=repo_root,
        check=True,
        capture_output=True,
    )
    return {
        item.decode("utf-8").replace("\\", "/")
        for item in result.stdout.split(b"\0")
        if item
    }


def _resolve_asset_path(
    path_spec: str,
    pack_root: Path,
    runtime_root: Path,
    repo_root: Path,
) -> Path | None:
    if not is_repository_asset_path(path_spec):
        return None
    if path_spec.startswith("res://"):
        candidate = runtime_root / path_spec.removeprefix("res://")
    else:
        candidate = pack_root / path_spec
    resolved = candidate.resolve()
    try:
        resolved.relative_to(repo_root.resolve())
    except ValueError:
        return None
    return resolved


def validate_manifest_dependencies(
    manifest: dict[str, Any],
    manifest_path: Path,
    repo_root: Path,
    tracked_paths: set[str] | None = None,
) -> list[ValidationError]:
    """Validate the transitive files the shipping renderer actually dereferences."""
    errors: list[ValidationError] = []
    runtime_root = repo_root / "apps" / "runtime-godot"
    pack_root = manifest_path.parent
    tracked = tracked_paths if tracked_paths is not None else _tracked_repo_paths(repo_root)
    declared: list[tuple[str, str, bool]] = []
    visual = manifest.get("visual")
    if not isinstance(visual, dict):
        return errors

    for field in ("animations", "sprites"):
        values = visual.get(field)
        if not isinstance(values, dict):
            continue
        for key, value in values.items():
            if isinstance(value, str):
                declared.append((f"manifest.visual.{field}.{key}", value, field == "animations"))
    emotes = visual.get("emotes")
    if isinstance(emotes, dict) and isinstance(emotes.get("manifest"), str):
        declared.append(("manifest.visual.emotes.manifest", emotes["manifest"], False))
    ground = visual.get("ground")
    if isinstance(ground, dict) and isinstance(ground.get("texture"), str):
        declared.append(("manifest.visual.ground.texture", ground["texture"], False))

    def check_one(label: str, path_spec: str, dependency_pack_root: Path = pack_root) -> Path | None:
        resolved = _resolve_asset_path(path_spec, dependency_pack_root, runtime_root, repo_root)
        if resolved is None:
            add_error(errors, label, "uses a non-repository path", "Use a tracked pack-relative or res:// path.")
            return None
        rel = resolved.relative_to(repo_root.resolve()).as_posix()
        if not resolved.is_file():
            add_error(errors, label, f"references missing file {path_spec!r}", "Add the tracked file or remove the reference.")
            return None
        if rel not in tracked:
            add_error(errors, label, f"references untracked or ignored file {rel!r}", "Shipping dependencies must be tracked by git.")
            return None
        return resolved

    for label, path_spec, is_animation in declared:
        resolved = check_one(label, path_spec)
        if resolved is None or not is_animation:
            continue
        try:
            animation = load_json(resolved)
        except Exception as exc:  # noqa: BLE001
            add_error(errors, label, f"animation JSON is unreadable: {exc}", "Repair or remove the animation reference.")
            continue
        if not isinstance(animation, dict) or not isinstance(animation.get("sheet"), str):
            add_error(errors, label, "animation JSON has no string sheet path", "Declare a tracked sheet path.")
            continue
        animation_pack_root = pack_root
        runtime_relative = resolved.relative_to(runtime_root).parts
        if len(runtime_relative) >= 2 and runtime_relative[0] == "content":
            animation_pack_root = runtime_root / "content" / runtime_relative[1]
        check_one(f"{label}.sheet", animation["sheet"], animation_pack_root)

    if visual.get("faceMode", "embedded") == "overlay_or_code":
        fallback_rel = "apps/runtime-godot/scripts/visual/portable_buddy_fallback.gd"
        fallback_path = repo_root / fallback_rel
        if not fallback_path.is_file() or fallback_rel not in tracked:
            add_error(
                errors,
                "manifest.visual.faceMode",
                "portable face fallback implementation is missing or untracked",
                "Track the repository-owned fallback implementation.",
            )
    return errors


# ---------------------------------------------------------------------------
# Schema self-validation (--check-schema)
#
# This is NOT a general-purpose JSON Schema meta-validator: it structurally
# checks only the keyword subset that buddy-pack.schema.json actually uses
# (type, properties, required, items, additionalProperties, minLength/
# maxLength/minItems/maxItems, minimum/maximum/exclusiveMinimum/
# exclusiveMaximum, enum, $id/title/description), per draft 2020-12
# semantics for those keywords. It exists to catch typos and structural
# mistakes in the schema document itself -- e.g. a "required" entry with no
# matching "properties" key, or "type" set to something that isn't a real
# JSON Schema type name -- without adding a `jsonschema` dependency to a
# validator this package's README explicitly says is dependency-free.
# ---------------------------------------------------------------------------


def validate_schema_document(schema: Any) -> list[ValidationError]:
    errors: list[ValidationError] = []
    _check_schema_node(schema, SCHEMA_ROOT, errors, is_root=True)
    return errors


def _check_schema_node(
    node: Any,
    path: str,
    errors: list[ValidationError],
    is_root: bool = False,
) -> None:
    # Per JSON Schema 2020-12, a schema is either a JSON object or a boolean.
    # A boolean is only valid here as a *nested* sub-schema (e.g.
    # "additionalProperties": false) -- the root document must still be an
    # object declaring "$schema", so a top-level `true`/`false` schema is
    # rejected rather than silently passing this self-check.
    if isinstance(node, bool):
        if is_root:
            add_error(
                errors,
                f"{path}.$schema",
                "is missing or not a string",
                f'Add "$schema": "{EXPECTED_SCHEMA_DRAFT}" at the top of the schema so tooling and readers '
                "know which JSON Schema draft the keywords below follow.",
            )
        return
    if not isinstance(node, dict):
        add_error(
            errors,
            path,
            f"must be a JSON object (or boolean) schema, found {describe(node)}",
            "A schema node must be `{...}` (or `true`/`false`). Check for a stray value where an object was expected.",
        )
        return

    if is_root:
        declared = node.get("$schema")
        if not isinstance(declared, str) or not declared.strip():
            add_error(
                errors,
                f"{path}.$schema",
                "is missing or not a string",
                f'Add "$schema": "{EXPECTED_SCHEMA_DRAFT}" at the top of the schema so tooling and readers '
                "know which JSON Schema draft the keywords below follow.",
            )
        elif declared != EXPECTED_SCHEMA_DRAFT:
            add_error(
                errors,
                f"{path}.$schema",
                f"declares {declared!r}, but this self-check is pinned to {EXPECTED_SCHEMA_DRAFT!r}",
                f'Set "$schema" to "{EXPECTED_SCHEMA_DRAFT}" (draft 2020-12), or update EXPECTED_SCHEMA_DRAFT '
                "in validate_pack.py if the pack schema intentionally moved to a different draft.",
            )

    type_value = node.get("type")
    if type_value is not None:
        _check_type_keyword(type_value, f"{path}.type", errors)

    required_value = node.get("required")
    if required_value is not None:
        if not isinstance(required_value, list) or not all(isinstance(x, str) for x in required_value):
            add_error(
                errors,
                f"{path}.required",
                f"must be an array of strings, found {describe(required_value)}",
                'Set "required" to a list of property-name strings, e.g. ["id", "name"].',
            )
        else:
            properties = node.get("properties")
            if isinstance(properties, dict):
                for name in required_value:
                    if name not in properties:
                        add_error(
                            errors,
                            f"{path}.required",
                            f'lists "{name}" but "properties" has no matching key',
                            f'Add a "{name}" entry under "{path}.properties", or remove "{name}" from '
                            '"required" if it was a typo.',
                        )

    properties_value = node.get("properties")
    if properties_value is not None:
        if not isinstance(properties_value, dict):
            add_error(
                errors,
                f"{path}.properties",
                f"must be an object mapping property names to sub-schemas, found {describe(properties_value)}",
                'Set "properties" to `{"fieldName": {...schema...}, ...}`.',
            )
        else:
            for name, sub_schema in properties_value.items():
                _check_schema_node(sub_schema, f"{path}.properties.{name}", errors)

    items_value = node.get("items")
    if items_value is not None:
        _check_schema_node(items_value, f"{path}.items", errors)

    additional_props = node.get("additionalProperties")
    if additional_props is not None and not isinstance(additional_props, bool):
        _check_schema_node(additional_props, f"{path}.additionalProperties", errors)

    for length_key in ("minLength", "maxLength", "minItems", "maxItems"):
        value = node.get(length_key)
        if value is not None and (not is_int(value) or value < 0):
            add_error(
                errors,
                f"{path}.{length_key}",
                f"must be a non-negative integer, found {describe(value)}",
                f'Set "{length_key}" to an integer >= 0.',
            )

    for numeric_key in ("minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"):
        value = node.get(numeric_key)
        if value is not None and not is_number(value):
            add_error(
                errors,
                f"{path}.{numeric_key}",
                f"must be a number, found {describe(value)}",
                f'Set "{numeric_key}" to a numeric bound.',
            )

    enum_value = node.get("enum")
    if enum_value is not None and (not isinstance(enum_value, list) or not enum_value):
        add_error(
            errors,
            f"{path}.enum",
            f"must be a non-empty array of allowed values, found {describe(enum_value)}",
            'Set "enum" to a non-empty list of allowed literal values.',
        )

    for key in ("$id", "title", "description"):
        value = node.get(key)
        if value is not None and not isinstance(value, str):
            add_error(
                errors,
                f"{path}.{key}",
                f"must be a string, found {describe(value)}",
                f'Set "{key}" to a plain string.',
            )


def _check_type_keyword(type_value: Any, path: str, errors: list[ValidationError]) -> None:
    if isinstance(type_value, list):
        if not type_value:
            add_error(
                errors,
                path,
                "is an empty array",
                'List at least one JSON Schema type, e.g. ["string", "null"].',
            )
            return
        candidates = type_value
    else:
        candidates = [type_value]

    for candidate in candidates:
        if not isinstance(candidate, str) or candidate not in JSON_SCHEMA_PRIMITIVE_TYPES:
            add_error(
                errors,
                path,
                f"contains invalid type name {candidate!r}",
                f"Use one of: {', '.join(sorted(JSON_SCHEMA_PRIMITIVE_TYPES))}.",
            )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def run_check_schema(path: Path) -> int:
    if not path.exists():
        print(f"ERROR: schema file not found: {path}")
        return 2

    try:
        raw = load_json(path)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: invalid JSON: {exc}")
        return 2

    errors = validate_schema_document(raw)
    if errors:
        print(f"INVALID schema document -> {path}")
        for err in errors:
            print(f"- {err.format()}")
        return 1

    print(f"OK: schema document is a structurally valid draft 2020-12 schema -> {path}")
    return 0


def main() -> int:
    argv = sys.argv[1:]

    if argv and argv[0] == "--check-schema":
        schema_path = Path(argv[1]).resolve() if len(argv) > 1 else DEFAULT_SCHEMA_PATH
        return run_check_schema(schema_path)

    if len(argv) != 1:
        print("Usage: python validate_pack.py <manifest.json>")
        print("       python validate_pack.py --check-schema [schema.json]")
        return 2

    path = Path(argv[0]).resolve()
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
    if not errors:
        repo_root = Path(__file__).resolve().parents[2]
        errors.extend(validate_manifest_dependencies(raw, path, repo_root))
    if errors:
        print(f"INVALID manifest -> {path}")
        for err in errors:
            print(f"- {err.format()}")
        return 1

    print(f"OK: manifest valid -> {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
