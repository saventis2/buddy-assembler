#!/usr/bin/env python3
"""Inspect MapleStory NPC animation timelines, delay fields, and link chaining."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any
import xml.etree.ElementTree as ET

from wz_shared import (
    FALLBACK_BASE_WZ,
    asset_id_from_xml,
    build_timeline_from_action_node,
    child_imgdir,
    extract_info_link,
    resolve_link_target_xml,
)


def resolve_npc_action(
    base_wz: Path,
    npc_id: int,
    action: str,
    *,
    default_delay_ms: int,
    max_frames: int,
    max_link_depth: int,
) -> dict[str, Any]:
    npc_root = base_wz / "Npc" / "Npc.wz"
    start_xml = npc_root / f"{int(npc_id):07d}.img.xml"
    if not start_xml.exists():
        return {
            "ok": False,
            "reason": "npc_xml_missing",
            "requested_npc_id": int(npc_id),
            "requested_action": action,
            "start_xml": str(start_xml),
            "link_chain": [],
            "timeline": [],
        }

    safe_default = max(1, int(default_delay_ms))
    seen: set[Path] = set()
    chain: list[str] = []
    current_xml = start_xml
    depth = 0

    while depth <= max_link_depth:
        if current_xml in seen:
            return {
                "ok": False,
                "reason": "link_cycle",
                "requested_npc_id": int(npc_id),
                "requested_action": action,
                "resolved_xml": str(current_xml),
                "link_chain": chain,
                "timeline": [],
            }
        seen.add(current_xml)

        root = ET.parse(current_xml).getroot()
        chain.append(asset_id_from_xml(current_xml))
        action_node = child_imgdir(root, action)
        if action_node is not None:
            timeline = build_timeline_from_action_node(action_node, safe_default)
            return {
                "ok": True,
                "reason": "ok",
                "requested_npc_id": int(npc_id),
                "requested_action": action,
                "resolved_npc_id": int(chain[-1]),
                "resolved_xml": str(current_xml),
                "link_chain": chain,
                "timeline": timeline[: max(1, int(max_frames))],
            }

        link_value = extract_info_link(root)
        if not link_value:
            return {
                "ok": False,
                "reason": "action_missing",
                "requested_npc_id": int(npc_id),
                "requested_action": action,
                "resolved_xml": str(current_xml),
                "link_chain": chain,
                "timeline": [],
            }

        linked_xml = resolve_link_target_xml(current_xml, link_value)
        if linked_xml is None:
            return {
                "ok": False,
                "reason": "link_target_missing",
                "requested_npc_id": int(npc_id),
                "requested_action": action,
                "resolved_xml": str(current_xml),
                "link_value": link_value,
                "link_chain": chain,
                "timeline": [],
            }

        current_xml = linked_xml
        depth += 1

    return {
        "ok": False,
        "reason": "max_link_depth",
        "requested_npc_id": int(npc_id),
        "requested_action": action,
        "resolved_xml": str(current_xml),
        "link_chain": chain,
        "timeline": [],
    }


def scan_npc_dataset(base_wz: Path, *, scan_limit: int) -> dict[str, Any]:
    npc_root = base_wz / "Npc" / "Npc.wz"
    xml_files = sorted(npc_root.glob("*.img.xml"))
    if scan_limit > 0:
        xml_files = xml_files[:scan_limit]

    total = 0
    with_link = 0
    delay_int = 0
    delay_string = 0
    action_name_counts: dict[str, int] = {}

    for xml_path in xml_files:
        try:
            root = ET.parse(xml_path).getroot()
        except Exception:
            continue
        total += 1

        link_value = extract_info_link(root)
        if link_value:
            with_link += 1

        for child in root:
            if child.tag != "imgdir":
                continue
            name = child.attrib.get("name", "")
            if name and name != "info":
                action_name_counts[name] = action_name_counts.get(name, 0) + 1

        for node in root.iter():
            if node.attrib.get("name") != "delay":
                continue
            if node.tag == "int":
                delay_int += 1
            elif node.tag == "string":
                delay_string += 1

    top_actions = sorted(action_name_counts.items(), key=lambda kv: (-kv[1], kv[0]))[:20]
    return {
        "scanned_npcs": total,
        "with_link": with_link,
        "with_link_ratio": (with_link / total) if total else 0.0,
        "delay_fields": {
            "int": delay_int,
            "string": delay_string,
        },
        "top_actions": [{"action": action, "count": count} for action, count in top_actions],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-wz",
        default=FALLBACK_BASE_WZ,
        help="Path to extracted Base.wz directory",
    )
    parser.add_argument("--npc-id", type=int, default=2004, help="NPC id to inspect")
    parser.add_argument("--action", default="stand", help="Action to resolve (for example stand, blink, move)")
    parser.add_argument("--default-delay-ms", type=int, default=120, help="Fallback delay when frame delay is absent")
    parser.add_argument("--max-frames", type=int, default=12, help="Max timeline frames to return")
    parser.add_argument("--max-link-depth", type=int, default=8, help="Max NPC link chain depth")
    parser.add_argument("--scan-limit", type=int, default=1500, help="How many NPC XML files to scan for aggregate stats")
    parser.add_argument("--output-json", default="", help="Optional output JSON file path")
    args = parser.parse_args()

    base_wz = Path(args.base_wz)
    resolution = resolve_npc_action(
        base_wz=base_wz,
        npc_id=args.npc_id,
        action=args.action,
        default_delay_ms=max(1, int(args.default_delay_ms)),
        max_frames=max(1, int(args.max_frames)),
        max_link_depth=max(1, int(args.max_link_depth)),
    )
    scan = scan_npc_dataset(base_wz, scan_limit=max(0, int(args.scan_limit)))

    payload = {
        "resolution": resolution,
        "scan": scan,
    }
    print(json.dumps(payload, indent=2))

    if args.output_json.strip():
        out_path = Path(args.output_json).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"Wrote: {out_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
