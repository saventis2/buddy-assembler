#!/usr/bin/env python3
"""Export Buddy Assembler sprites and sprite-sheet animations for runtime-godot."""

from __future__ import annotations

import argparse
import json
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from render_character_frame import render
from wz_shared import (
    asset_id_from_xml,
    build_sprite_sheet,
    build_timeline_from_action_node,
    child_imgdir,
    extract_info_link,
    normalize_action_frame_canvases,
    resolve_link_target_xml,
)


STATE_CONFIGS: dict[str, dict[str, Any]] = {
    "idle": {"action": "stand1", "key_frame": 0, "loop": True},
    "wander": {"action": "walk1", "key_frame": 0, "loop": True},
    "sit": {"action": "sit", "key_frame": 0, "loop": True},
    "sleep": {"action": "prone", "key_frame": 0, "loop": True},
    "happy": {"action": "alert", "key_frame": 0, "loop": True},
    # gift: heal action (both hands raised, palms up) — the gift-box icon
    # overlay is placed between the hands at runtime.
    "gift": {"action": "heal", "key_frame": 0, "loop": True},
    "visitor": {"action": "walk1", "key_frame": 1, "loop": True},
    # Phase B additions: real visually-distinct WZ body actions.
    # shoot1 intentionally omitted: the default combo weapon (1312007 wand)
    # does not support ranged actions — per the v1 rule, the weapon layer
    # would be silently omitted, leaving a ranged pose with no weapon.
    # Add only when a compatible bow/gun is selected.
    "fly": {"action": "fly", "key_frame": 0, "loop": True},
    "climb": {"action": "ladder", "key_frame": 0, "loop": True},
    "swing": {"action": "swingO1", "key_frame": 0, "loop": False},
    "stab": {"action": "stabT1", "key_frame": 0, "loop": False},
    "alt_idle": {"action": "stand2", "key_frame": 0, "loop": True},
}


def _to_int_or_none(value: Any) -> int | None:
    if value is None:
        return None
    raw = str(value).strip()
    if not raw:
        return None
    return int(raw)


def _load_combo(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Combo root must be object")
    return data


def _build_render_kwargs(combo: dict[str, Any]) -> dict[str, Any]:
    ids = combo.get("ids", {})
    if not isinstance(ids, dict):
        raise ValueError("Combo ids must be object")

    return {
        "base_id": _to_int_or_none(ids.get("base_id")) or 2000,
        "head_id": _to_int_or_none(ids.get("head_id")) or 12000,
        "face_id": _to_int_or_none(ids.get("face_id")) or 20000,
        "hair_id": _to_int_or_none(ids.get("hair_id")) or 30000,
        "accessory_id": _to_int_or_none(ids.get("accessory_id")),
        "cap_id": _to_int_or_none(ids.get("cap_id")),
        "coat_id": _to_int_or_none(ids.get("coat_id")),
        "longcoat_id": _to_int_or_none(ids.get("longcoat_id")),
        "pants_id": _to_int_or_none(ids.get("pants_id")),
        "shoes_id": _to_int_or_none(ids.get("shoes_id")),
        "glove_id": _to_int_or_none(ids.get("glove_id")),
        "cape_id": _to_int_or_none(ids.get("cape_id")),
        "shield_id": _to_int_or_none(ids.get("shield_id")),
        "weapon_id": _to_int_or_none(ids.get("weapon_id")),
        "z_draw_order": str(combo.get("z_draw_order", "front-last")),
        "hair_mode": str(combo.get("hair_mode", "auto")),
    }


def _base_template_xml(base_wz: Path, base_id: int) -> Path:
    return base_wz / "Character" / "Character.wz" / f"{int(base_id):08d}.img.xml"


def _resolve_action_node_with_links(
    base_wz: Path,
    base_id: int,
    action: str,
    *,
    max_depth: int = 8,
) -> dict[str, Any]:
    start_xml = _base_template_xml(base_wz, base_id)
    if not start_xml.exists():
        return {
            "ok": False,
            "reason": "base_xml_missing",
            "xml_path": str(start_xml),
            "action_node": None,
            "root": None,
            "link_chain": [],
        }

    chain: list[str] = []
    seen: set[Path] = set()
    current_xml = start_xml
    depth = 0

    while depth <= max_depth:
        if current_xml in seen:
            return {
                "ok": False,
                "reason": "link_cycle",
                "xml_path": str(current_xml),
                "action_node": None,
                "root": None,
                "link_chain": chain,
            }
        seen.add(current_xml)

        root = ET.parse(current_xml).getroot()
        chain.append(asset_id_from_xml(current_xml))

        action_node = child_imgdir(root, action)
        if action_node is not None:
            return {
                "ok": True,
                "reason": "ok",
                "xml_path": str(current_xml),
                "action_node": action_node,
                "root": root,
                "link_chain": chain,
            }

        link_value = extract_info_link(root)
        if not link_value:
            return {
                "ok": False,
                "reason": "action_missing",
                "xml_path": str(current_xml),
                "action_node": None,
                "root": root,
                "link_chain": chain,
            }

        linked_xml = resolve_link_target_xml(current_xml, link_value)
        if linked_xml is None:
            return {
                "ok": False,
                "reason": "link_target_missing",
                "xml_path": str(current_xml),
                "action_node": None,
                "root": root,
                "link_chain": chain,
            }

        current_xml = linked_xml
        depth += 1

    return {
        "ok": False,
        "reason": "max_link_depth",
        "xml_path": str(current_xml),
        "action_node": None,
        "root": None,
        "link_chain": chain,
    }


def _detect_action_timeline(
    base_wz: Path,
    base_id: int,
    action: str,
    *,
    default_delay_ms: int,
    max_frames: int,
) -> list[dict[str, int]]:
    safe_default = max(1, int(default_delay_ms))
    resolved = _resolve_action_node_with_links(base_wz, base_id, action)
    if not bool(resolved.get("ok", False)):
        return []

    action_node = resolved.get("action_node")
    if action_node is None:
        return []
    timeline = build_timeline_from_action_node(action_node, safe_default)
    return timeline[: max(1, int(max_frames))]


def _safe_relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except Exception:
        return path.as_posix()


def _export_state_animation(
    *,
    state: str,
    action: str,
    loop: bool,
    base_wz: Path,
    render_kwargs: dict[str, Any],
    pack_root: Path,
    anim_dir: Path,
    default_delay_ms: int,
    max_frames: int,
    sheet_cols: int,
    floor_world_ref: int | None,
    include_face: bool,
) -> tuple[Path | None, list[str]]:
    warnings: list[str] = []
    timeline = _detect_action_timeline(
        base_wz=base_wz,
        base_id=int(render_kwargs["base_id"]),
        action=action,
        default_delay_ms=default_delay_ms,
        max_frames=max_frames,
    )
    if not timeline:
        warnings.append(f"{state}: no timeline frames detected for action '{action}'")
        return None, warnings

    state_frame_dir = anim_dir / state / "frames"
    state_frame_dir.mkdir(parents=True, exist_ok=True)
    per_frame: list[dict[str, Any]] = []

    for i, row in enumerate(timeline):
        src_frame = int(row["frame"])
        delay_ms = int(row["delay_ms"])
        png_path = state_frame_dir / f"{i:03d}.png"
        json_path = state_frame_dir / f"{i:03d}.json"
        try:
            meta = render(
                base_wz=base_wz,
                output_png=png_path,
                action=action,
                frame=src_frame,
                output_json=json_path,
                include_face=include_face,
                **render_kwargs,
            )
            per_frame.append(
                {
                    "index": i,
                    "source_frame": src_frame,
                    "delay_ms": delay_ms,
                    "png": str(png_path),
                    "json": str(json_path),
                    "frame_bounds_world": meta.get("frame_bounds_world"),
                }
            )
        except Exception as exc:  # noqa: BLE001
            warnings.append(f"{state}: frame {src_frame} render failed ({exc})")

    if not per_frame:
        warnings.append(f"{state}: no frames rendered successfully")
        return None, warnings

    normalize_info = normalize_action_frame_canvases(per_frame, sync_bounds_metadata=True)

    frame_paths = [Path(row["png"]) for row in per_frame]
    sheet_path = anim_dir / f"{state}_sheet.png"
    sheet_info = build_sprite_sheet(
        frame_paths=frame_paths,
        output_path=sheet_path,
        columns=sheet_cols,
    )

    layout = sheet_info["layout"]
    frames: list[dict[str, Any]] = []
    for i, row in enumerate(per_frame):
        rect = layout[i]
        rect_w = int(rect["w"])
        rect_h = int(rect["h"])

        bounds_variant = row.get("effective_bounds_world")
        if not isinstance(bounds_variant, dict):
            if normalize_info is not None and isinstance(normalize_info.get("bounds_world"), dict):
                bounds_variant = normalize_info.get("bounds_world")
            elif isinstance(row.get("frame_bounds_world"), dict):
                bounds_variant = row.get("frame_bounds_world")
            else:
                bounds_variant = {"left": 0, "top": 0, "right": rect_w, "bottom": rect_h}

        left_world = int(bounds_variant.get("left", 0))
        top_world = int(bounds_variant.get("top", 0))
        bottom_world = int(bounds_variant.get("bottom", rect_h))
        pivot_world_x = 0
        pivot_world_y = int(floor_world_ref) if floor_world_ref is not None else bottom_world
        pivot_px_x = pivot_world_x - left_world
        pivot_px_y = pivot_world_y - top_world

        frames.append(
            {
                "index": int(row["index"]),
                "source_frame": int(row["source_frame"]),
                "duration_ms": int(row["delay_ms"]),
                "rect": [int(rect["x"]), int(rect["y"]), rect_w, rect_h],
                "pivot_px": [pivot_px_x, pivot_px_y],
                "pivot_world": [pivot_world_x, pivot_world_y],
            }
        )

    anim_json_path = anim_dir / f"{state}.json"
    anim_payload = {
        "schema": "buddy_animation_v1",
        "state": state,
        "source_action": action,
        "loop": bool(loop),
        "floor_world_ref": int(floor_world_ref) if floor_world_ref is not None else None,
        "sheet": _safe_relative(sheet_path, pack_root),
        "sheet_size": sheet_info["sheet_size"],
        "cell_size": sheet_info["cell_size"],
        "frame_count": len(frames),
        "frames": frames,
    }
    anim_json_path.write_text(json.dumps(anim_payload, indent=2), encoding="utf-8")
    return anim_json_path, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description="Export runtime-godot buddy sprites and animations from saved combo.")
    parser.add_argument(
        "--combo-json",
        default="combinations/last_combo.json",
        help="Path to buddy combo JSON (default: combinations/last_combo.json)",
    )
    parser.add_argument(
        "--output-dir",
        default="apps/runtime-godot/content/core_pack/character",
        help="Output static sprite directory",
    )
    parser.add_argument(
        "--metadata-dir",
        default="apps/runtime-godot/content/core_pack/character/meta",
        help="Output static metadata directory",
    )
    parser.add_argument(
        "--anim-dir",
        default="apps/runtime-godot/content/core_pack/character/animations",
        help="Output animation metadata + sheet directory",
    )
    parser.add_argument(
        "--base-wz",
        default="",
        help="Optional override Base.wz path (otherwise combo base_wz is used)",
    )
    parser.add_argument(
        "--default-delay-ms",
        type=int,
        default=120,
        help="Default frame delay for actions without explicit delay metadata",
    )
    parser.add_argument(
        "--max-frames",
        type=int,
        default=8,
        help="Max frames per state animation to export",
    )
    parser.add_argument(
        "--sheet-cols",
        type=int,
        default=8,
        help="Sprite sheet columns",
    )
    parser.add_argument(
        "--export-animations",
        dest="export_animations",
        action="store_true",
        default=True,
        help="Export animation metadata + sprite sheets (default: enabled)",
    )
    parser.add_argument(
        "--bake-face",
        action="store_true",
        help="Composite face layer into output PNGs (default: off for runtime overlay emotes).",
    )
    parser.add_argument(
        "--no-export-animations",
        dest="export_animations",
        action="store_false",
        help="Only export static state sprites",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    combo_path = (repo_root / args.combo_json).resolve()
    out_dir = (repo_root / args.output_dir).resolve()
    meta_dir = (repo_root / args.metadata_dir).resolve()
    anim_dir = (repo_root / args.anim_dir).resolve()
    pack_root = out_dir.parent

    if not combo_path.exists():
        raise SystemExit(f"Combo file not found: {combo_path}")

    combo = _load_combo(combo_path)
    base_wz_raw = args.base_wz.strip() if args.base_wz else str(combo.get("base_wz", "")).strip()
    if not base_wz_raw:
        raise SystemExit("No base_wz path provided in combo or --base-wz")
    base_wz = Path(base_wz_raw)
    if not base_wz.exists():
        raise SystemExit(f"Base.wz path does not exist: {base_wz}")

    render_kwargs = _build_render_kwargs(combo)
    out_dir.mkdir(parents=True, exist_ok=True)
    meta_dir.mkdir(parents=True, exist_ok=True)
    if args.export_animations:
        anim_dir.mkdir(parents=True, exist_ok=True)

    generated_static: dict[str, Path] = {}
    generated_anim: dict[str, Path] = {}
    failures: list[str] = []
    warnings: list[str] = []
    floor_world_ref: int | None = None

    for state, cfg in STATE_CONFIGS.items():
        action = str(cfg["action"])
        key_frame = int(cfg.get("key_frame", 0))
        output_png = out_dir / f"{state}.png"
        output_json = meta_dir / f"{state}.json"
        try:
            static_meta = render(
                base_wz=base_wz,
                output_png=output_png,
                action=action,
                frame=key_frame,
                output_json=output_json,
                include_face=bool(args.bake_face),
                **render_kwargs,
            )
            generated_static[state] = output_png
            if state == "idle":
                bounds = static_meta.get("frame_bounds_world") if isinstance(static_meta, dict) else None
                if isinstance(bounds, dict):
                    bottom = bounds.get("bottom")
                    if isinstance(bottom, int):
                        floor_world_ref = int(bottom)
            print(f"OK: static {state} -> {output_png}")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"{state}: static render failed ({exc})")
            print(f"WARN: static render failed for {state} ({action}:{key_frame}) -> {exc}")

        if args.export_animations:
            anim_json, state_warnings = _export_state_animation(
                state=state,
                action=action,
                loop=bool(cfg.get("loop", True)),
                base_wz=base_wz,
                render_kwargs=render_kwargs,
                pack_root=pack_root,
                anim_dir=anim_dir,
                default_delay_ms=max(1, int(args.default_delay_ms)),
                max_frames=max(1, int(args.max_frames)),
                sheet_cols=max(1, int(args.sheet_cols)),
                floor_world_ref=floor_world_ref,
                include_face=bool(args.bake_face),
            )
            warnings.extend(state_warnings)
            if anim_json is not None:
                generated_anim[state] = anim_json
                print(f"OK: anim {state} -> {anim_json}")

    if "idle" in generated_static:
        idle_png = generated_static["idle"]
        idle_json = meta_dir / "idle.json"
        for state in STATE_CONFIGS:
            target_png = out_dir / f"{state}.png"
            target_json = meta_dir / f"{state}.json"
            if target_png.exists():
                continue
            shutil.copy2(idle_png, target_png)
            if idle_json.exists():
                shutil.copy2(idle_json, target_json)
            print(f"FALLBACK: copied idle static sprite for {state}")

    if failures:
        print("Completed with static export failures:")
        for row in failures:
            print(f"- {row}")
    if warnings:
        print("Completed with warnings:")
        for row in warnings:
            print(f"- {row}")
    if not failures and not warnings:
        print("Export completed with no warnings.")

    print(
        json.dumps(
            {
                "static_states": sorted(generated_static.keys()),
                "animated_states": sorted(generated_anim.keys()),
                "static_dir": str(out_dir),
                "anim_dir": str(anim_dir) if args.export_animations else None,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
