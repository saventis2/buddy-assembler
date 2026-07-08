#!/usr/bin/env python3
"""Inspect MapleStory NPC animation timelines, delay fields, and link chaining."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any
import xml.etree.ElementTree as ET


def _child_imgdir(node: ET.Element, name: str) -> ET.Element | None:
    for child in node:
        if child.tag == "imgdir" and child.attrib.get("name") == name:
            return child
    return None


def _asset_id_from_xml(xml_path: Path) -> str:
    return xml_path.stem.replace(".img", "")


def _extract_info_link(root: ET.Element) -> str | None:
    info = _child_imgdir(root, "info")
    if info is None:
        return None
    for node in info:
        if node.attrib.get("name") != "link":
            continue
        if node.tag not in {"string", "int"}:
            continue
        value = str(node.attrib.get("value", "")).strip()
        if value:
            return value
    return None


def _resolve_link_target_xml(current_xml: Path, link_value: str) -> Path | None:
    raw = str(link_value).strip()
    if not raw:
        return None

    base_dir = current_xml.parent
    width = len(_asset_id_from_xml(current_xml))
    candidates: list[str] = []
    if raw.endswith(".img.xml"):
        candidates.append(raw)
    else:
        candidates.append(f"{raw}.img.xml")
    if raw.isdigit():
        candidates.append(f"{raw.zfill(width)}.img.xml")
        candidates.append(f"{int(raw):0{width}d}.img.xml")
        candidates.append(f"{int(raw)}.img.xml")

    seen: set[str] = set()
    for name in candidates:
        if name in seen:
            continue
        seen.add(name)
        candidate = base_dir / name
        if candidate.exists():
            return candidate
    return None


def _parse_delay_ms(raw: Any) -> int | None:
    if raw is None:
        return None
    try:
        value = int(str(raw).strip())
    except Exception:
        return None
    return max(1, value)


def _extract_node_delay_ms(frame_node: ET.Element) -> int | None:
    for child in frame_node:
        if child.attrib.get("name") != "delay":
            continue
        if child.tag not in {"int", "string"}:
            continue
        parsed = _parse_delay_ms(child.attrib.get("value"))
        if parsed is not None:
            return parsed
    return None


def _resolve_uol_target_frame(value: str) -> int | None:
    raw = str(value).strip()
    if not raw:
        return None
    if raw.isdigit():
        return int(raw)
    tokens = [tok for tok in raw.split("/") if tok not in {"", "."}]
    for token in reversed(tokens):
        if token.isdigit():
            return int(token)
    return None


def _resolve_frame_delay_ms(
    frame_idx: int,
    frame_nodes: dict[int, ET.Element],
    default_delay_ms: int,
    visited: set[int] | None = None,
) -> int:
    if visited is None:
        visited = set()
    if frame_idx in visited:
        return default_delay_ms
    visited.add(frame_idx)

    frame_node = frame_nodes.get(frame_idx)
    if frame_node is None:
        return default_delay_ms

    direct = _extract_node_delay_ms(frame_node)
    if direct is not None:
        return direct

    if frame_node.tag == "uol":
        target = _resolve_uol_target_frame(frame_node.attrib.get("value", ""))
        if target is not None:
            return _resolve_frame_delay_ms(target, frame_nodes, default_delay_ms, visited)

    return default_delay_ms


def _build_timeline_from_action_node(action_node: ET.Element, default_delay_ms: int) -> list[dict[str, int]]:
    frame_nodes: dict[int, ET.Element] = {}
    for child in action_node:
        name = str(child.attrib.get("name", "")).strip()
        if not name.isdigit():
            continue
        if child.tag not in {"imgdir", "canvas", "uol"}:
            continue
        frame_nodes[int(name)] = child

    if not frame_nodes:
        return [{"frame": 0, "delay_ms": default_delay_ms}]

    timeline: list[dict[str, int]] = []
    for frame_idx in sorted(frame_nodes.keys()):
        delay_ms = _resolve_frame_delay_ms(frame_idx, frame_nodes, default_delay_ms)
        timeline.append({"frame": int(frame_idx), "delay_ms": int(delay_ms)})
    return timeline


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
        chain.append(_asset_id_from_xml(current_xml))
        action_node = _child_imgdir(root, action)
        if action_node is not None:
            timeline = _build_timeline_from_action_node(action_node, safe_default)
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

        link_value = _extract_info_link(root)
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

        linked_xml = _resolve_link_target_xml(current_xml, link_value)
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

        link_value = _extract_info_link(root)
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
        default=r"C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz",
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
