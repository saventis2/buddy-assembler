#!/usr/bin/env python3
"""Fail closed when the declared v0.1 Windows payload drifts."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

from release_artifact_checks import load_inventory_contract
from validate_pack import load_json, validate_manifest, validate_manifest_dependencies

REQUIRED_TRACKED = {
    "apps/runtime-godot/project.godot",
    "apps/runtime-godot/scenes/LaunchRouter.tscn",
    "apps/runtime-godot/scenes/BuddyOverlay.tscn",
    "apps/runtime-godot/runtime/ui/chat_balloon.gd",
    "apps/runtime-godot/scripts/launch_router.gd",
    "apps/runtime-godot/scripts/buddy_overlay.gd",
    "apps/runtime-godot/scripts/content/content_loader.gd",
    "apps/runtime-godot/scripts/visual/portable_buddy_fallback.gd",
    "packages/content-validator/shipping_inventory.json",
}

FORBIDDEN_PREFIXES = (
    "res://addons/",
    "res://content/imported/",
    "res://content/intermediate/",
    "res://content/sample_pack/",
    "res://content/types/",
    "res://content/core_pack/character_visitor/",
    "res://content/core_pack/character/meta/",
    "res://runtime/actor/",
    "res://runtime/buddy/",
    "res://runtime/world/",
    "res://scenes/vertical_slice/",
    "res://tests/",
    "res://tools/",
)

CHAT_BALLOON_SOURCE = "apps/runtime-godot/runtime/ui/chat_balloon.gd"
LEGACY_CHAT_BALLOON_ROOT = "res://content/core_pack/ui/chat_balloon/"
LEGACY_CHAT_BALLOON_MARKERS = (
    LEGACY_CHAT_BALLOON_ROOT,
    '"nw.png"',
    '"n.png"',
    '"ne.png"',
    '"w.png"',
    '"c.png"',
    '"e.png"',
    '"sw.png"',
    '"s.png"',
    '"se.png"',
    '"arrow.png"',
)


def _setting(text: str, name: str) -> str:
    match = re.search(rf'(?m)^{re.escape(name)}="([^"]*)"$', text)
    return match.group(1) if match else ""


def _packed_strings(text: str, name: str) -> set[str]:
    match = re.search(rf"(?m)^{re.escape(name)}=PackedStringArray\((.*)\)$", text)
    if match is None:
        return set()
    parsed = json.loads(f"[{match.group(1)}]")
    if not isinstance(parsed, list) or not all(
        isinstance(item, str) for item in parsed
    ):
        return set()
    return set(parsed)


def _csv_resources(value: str) -> set[str]:
    return {f"res://{item.strip()}" for item in value.split(",") if item.strip()}


def validate_export_contract(preset: str, contract: dict[str, list[str]]) -> list[str]:
    failures: list[str] = []
    if _setting(preset, "export_filter") != "resources":
        failures.append(
            "export_filter must use the positive selected-resources closure"
        )
    selected = _packed_strings(preset, "export_files")
    expected_selected = set(contract["export_resources"])
    if selected != expected_selected:
        failures.append(
            f"selected resource closure drift: expected {sorted(expected_selected)}, got {sorted(selected)}"
        )
    includes = _csv_resources(_setting(preset, "include_filter"))
    expected_includes = set(contract["include_files"])
    if includes != expected_includes:
        failures.append(
            f"non-resource include closure drift: expected {sorted(expected_includes)}, got {sorted(includes)}"
        )
    if _setting(preset, "exclude_filter") != "":
        failures.append(
            "positive selected-resources closure must not rely on an exclusion filter"
        )

    approved = selected | includes | set(contract["pck_files"])
    for path in sorted(approved):
        if any(path.startswith(prefix) for prefix in FORBIDDEN_PREFIXES):
            failures.append(f"forbidden development path in shipping contract: {path}")
        lowered = path.lower()
        if ".wz" in lowered or lowered.endswith(".nx") or "\\" in path:
            failures.append(f"workstation/WZ/NX path in shipping contract: {path}")
    if not contract["pck_files"]:
        failures.append("exact PCK inventory contract is empty")
    return failures


def validate_chat_balloon_contract(
    source: str, contract: dict[str, list[str]]
) -> list[str]:
    failures: list[str] = []
    source_markers = [marker for marker in LEGACY_CHAT_BALLOON_MARKERS if marker in source]
    if source_markers:
        failures.append(
            "shipping chat balloon source references legacy PNG dependencies: "
            + ", ".join(source_markers)
        )

    shipping_paths = (
        contract["export_resources"]
        + contract["include_files"]
        + contract["pck_files"]
    )
    legacy_paths = sorted(
        path for path in shipping_paths if path.startswith(LEGACY_CHAT_BALLOON_ROOT)
    )
    if legacy_paths:
        failures.append(
            f"legacy chat balloon PNGs entered the shipping closure: {legacy_paths}"
        )
    return failures


def _source_repo_path(repo_root: Path, resource_path: str) -> tuple[Path, str]:
    relative = resource_path.removeprefix("res://")
    repo_relative = f"apps/runtime-godot/{relative}"
    return repo_root / repo_relative, repo_relative


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    runtime_root = repo_root / "apps" / "runtime-godot"
    contract_path = Path(__file__).resolve().parent / "shipping_inventory.json"
    failures: list[str] = []

    tracked_text = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=repo_root,
        check=True,
        capture_output=True,
    ).stdout
    tracked = {
        item.decode("utf-8").replace("\\", "/")
        for item in tracked_text.split(b"\0")
        if item
    }

    contract = load_inventory_contract(contract_path)
    required_tracked = set(REQUIRED_TRACKED)
    for resource_path in contract["export_resources"] + contract["include_files"]:
        _path, repo_relative = _source_repo_path(repo_root, resource_path)
        required_tracked.add(repo_relative)
    for relative in sorted(required_tracked):
        path = repo_root / relative
        if not path.is_file():
            failures.append(f"required shipping file is missing: {relative}")
        elif relative not in tracked:
            failures.append(
                f"required shipping file is untracked or ignored: {relative}"
            )

    audiences: dict[str, str] = {}
    content_root = runtime_root / "content"
    for manifest_path in sorted(content_root.glob("*/manifest.json")):
        manifest = load_json(manifest_path)
        if not isinstance(manifest, dict):
            failures.append(f"manifest root is not an object: {manifest_path}")
            continue
        pack_dir = manifest_path.parent.name
        audience = str(manifest.get("runtimeAudience", "user"))
        audiences[pack_dir] = audience
        for error in validate_manifest(manifest):
            failures.append(error.format())
        if audience == "user":
            for error in validate_manifest_dependencies(
                manifest, manifest_path, repo_root, tracked
            ):
                failures.append(error.format())

    if audiences != {
        "core_pack": "user",
        "night_pack": "user",
        "sample_pack": "development",
    }:
        failures.append(f"unexpected pack audience map: {audiences}")

    preset = (runtime_root / "export_presets.cfg").read_text(encoding="utf-8")
    failures.extend(validate_export_contract(preset, contract))
    chat_balloon_source = (repo_root / CHAT_BALLOON_SOURCE).read_text(encoding="utf-8")
    failures.extend(validate_chat_balloon_contract(chat_balloon_source, contract))

    if failures:
        print("shipping_closure: FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(
        "shipping_closure: PASS (positive source allowlist and exact PCK inventory contract)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
