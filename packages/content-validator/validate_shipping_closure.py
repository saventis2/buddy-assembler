#!/usr/bin/env python3
"""Fail closed when the declared v0.1 Windows payload drifts."""

from __future__ import annotations

import re
from pathlib import Path

from validate_pack import load_json, validate_manifest, validate_manifest_dependencies

REQUIRED_JSON_INCLUDES = {
    "content/core_pack/manifest.json",
    "content/core_pack/character/animations/idle.json",
    "content/core_pack/character/animations/wander.json",
    "content/core_pack/character/animations/sit.json",
    "content/core_pack/character/animations/sleep.json",
    "content/core_pack/character/animations/happy.json",
    "content/core_pack/character/animations/gift.json",
    "content/core_pack/character/animations/visitor.json",
    "content/core_pack/character/emotes/manifest.json",
    "content/core_pack/effects/chair_basic/effect.json",
    "content/core_pack/progression/bond_tiers.json",
    "content/night_pack/manifest.json",
}

REQUIRED_EXCLUDES = {
    "addons/*",
    "content/promotion_log.json",
    "content/core_pack/character/alt_idle*",
    "content/core_pack/character/climb*",
    "content/core_pack/character/fly*",
    "content/core_pack/character/stab*",
    "content/core_pack/character/swing*",
    "content/core_pack/character/animations/alt_idle*",
    "content/core_pack/character/animations/climb*",
    "content/core_pack/character/animations/fly*",
    "content/core_pack/character/animations/stab*",
    "content/core_pack/character/animations/swing*",
    "content/core_pack/character/animations/idle/*",
    "content/core_pack/character/animations/wander/*",
    "content/core_pack/character/animations/sit/*",
    "content/core_pack/character/animations/sleep/*",
    "content/core_pack/character/animations/happy/*",
    "content/core_pack/character/animations/gift/*",
    "content/core_pack/character/animations/visitor/*",
    "content/core_pack/character/emotes/face_variants.json",
    "content/core_pack/character/meta/*",
    "content/core_pack/character_visitor/*",
    "content/core_pack/effects/gift_box/*",
    "content/core_pack/effects/happy_sparkle/*",
    "content/core_pack/effects/levelup/*",
    "content/core_pack/effects/visitor_arrival/*",
    "content/core_pack/effects/visitor_depart/*",
    "content/core_pack/ui/*",
    "content/imported/*",
    "content/intermediate/*",
    "content/sample_pack/*",
    "content/types/*",
    "runtime/actor/*",
    "runtime/buddy/*",
    "runtime/world/*",
    "scenes/vertical_slice/*",
    "tests/*",
    "tools/*",
}

REQUIRED_TRACKED = {
    "apps/runtime-godot/project.godot",
    "apps/runtime-godot/scenes/LaunchRouter.tscn",
    "apps/runtime-godot/scenes/BuddyOverlay.tscn",
    "apps/runtime-godot/runtime/ui/chat_balloon.gd",
    "apps/runtime-godot/scripts/visual/portable_buddy_fallback.gd",
    "apps/runtime-godot/content/core_pack/effects/chair_basic/frames/000.png",
}


def _setting(text: str, name: str) -> str:
    match = re.search(rf'(?m)^{re.escape(name)}="([^"]*)"$', text)
    return match.group(1) if match else ""


def _csv(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip()}


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    runtime_root = repo_root / "apps" / "runtime-godot"
    failures: list[str] = []

    tracked_text = __import__("subprocess").run(
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

    for relative in sorted(REQUIRED_TRACKED):
        path = repo_root / relative
        if not path.is_file():
            failures.append(f"required shipping file is missing: {relative}")
        elif relative not in tracked:
            failures.append(f"required shipping file is untracked or ignored: {relative}")

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
            for error in validate_manifest_dependencies(manifest, manifest_path, repo_root, tracked):
                failures.append(error.format())

    if audiences != {"core_pack": "user", "night_pack": "user", "sample_pack": "development"}:
        failures.append(f"unexpected pack audience map: {audiences}")

    preset_path = runtime_root / "export_presets.cfg"
    preset = preset_path.read_text(encoding="utf-8")
    if _setting(preset, "export_filter") != "all_resources":
        failures.append("export_filter must use the reviewed all_resources-plus-denylist closure")
    includes = _csv(_setting(preset, "include_filter"))
    excludes = _csv(_setting(preset, "exclude_filter"))
    if includes != REQUIRED_JSON_INCLUDES:
        failures.append(f"JSON include closure drift: expected {sorted(REQUIRED_JSON_INCLUDES)}, got {sorted(includes)}")
    missing_excludes = REQUIRED_EXCLUDES - excludes
    if missing_excludes:
        failures.append(f"development/demo exclusions missing: {sorted(missing_excludes)}")

    if failures:
        print("shipping_closure: FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("shipping_closure: PASS (2 user packs, 1 development pack, narrowed Windows payload)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
