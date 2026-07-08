#!/usr/bin/env python3
"""Build weapon->action compatibility reports from extracted Base.wz source."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Dict, List, Set
import xml.etree.ElementTree as ET


def detect_actions_in_asset_dir(asset_dir: Path) -> Set[str]:
    if not asset_dir.exists() or not asset_dir.is_dir():
        return set()
    actions: Set[str] = set()
    for child in asset_dir.iterdir():
        if not child.is_dir():
            continue
        name = child.name
        if not name or name == "info":
            continue
        has_png = any(child.rglob("*.png"))
        if has_png:
            actions.add(name)
    return actions


def read_info_strings(xml_path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not xml_path.exists():
        return out
    try:
        root = ET.parse(xml_path).getroot()
    except Exception:
        return out
    info_node = None
    for child in root:
        if child.tag == "imgdir" and child.attrib.get("name") == "info":
            info_node = child
            break
    if info_node is None:
        return out
    for child in info_node:
        if child.tag == "string":
            key = child.attrib.get("name", "")
            if key:
                out[key] = child.attrib.get("value", "")
    return out


def frame_counts(asset_dir: Path, actions: Set[str]) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for action in sorted(actions):
        action_dir = asset_dir / action
        count = 0
        if action_dir.exists() and action_dir.is_dir():
            for child in action_dir.iterdir():
                if not child.is_dir():
                    continue
                if not child.name.isdigit():
                    continue
                if any(child.glob("*.png")):
                    count += 1
        out[action] = count
    return out


def parse_weapon_id_from_xml_name(name: str) -> int | None:
    # Expected: 01452011.img.xml
    if not name.endswith(".img.xml"):
        return None
    stem = name[:-8]  # strip .img.xml
    if not stem.isdigit():
        return None
    return int(stem)


def build_profiles(base_wz: Path) -> List[dict]:
    weapon_root = base_wz / "Character" / "Character.wz" / "Weapon"
    profiles: List[dict] = []
    for xml_path in sorted(weapon_root.glob("*.img.xml")):
        wid = parse_weapon_id_from_xml_name(xml_path.name)
        if wid is None:
            continue
        asset_dir = xml_path.with_suffix("")  # strips .xml -> *.img
        actions = detect_actions_in_asset_dir(asset_dir)
        info = read_info_strings(xml_path)
        profiles.append(
            {
                "weapon_id": wid,
                "weapon_type_code": wid // 10000,
                "asset_dir": str(asset_dir),
                "xml": str(xml_path),
                "info": info,
                "supported_actions": sorted(actions),
                "frame_counts": frame_counts(asset_dir, actions),
            }
        )
    return profiles


def build_type_matrix(profiles: List[dict]) -> List[dict]:
    by_type: Dict[int, List[set[str]]] = {}
    for row in profiles:
        t = int(row["weapon_type_code"])
        by_type.setdefault(t, []).append(set(row.get("supported_actions", [])))

    rows: List[dict] = []
    for t in sorted(by_type):
        sets = by_type[t]
        if not sets:
            common: set[str] = set()
            union: set[str] = set()
        else:
            common = set(sets[0])
            union = set()
            for s in sets:
                common &= s
                union |= s
        rows.append(
            {
                "weapon_type_code": t,
                "weapon_count": len(sets),
                "common_actions": sorted(common),
                "union_actions": sorted(union),
            }
        )
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-wz",
        default=r"C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz",
        help="Path to extracted Base.wz root",
    )
    parser.add_argument(
        "--output-dir",
        default=r"C:\Users\GGPC\OneDrive\Desktop\83 complete\analysis\dataset_audit",
        help="Directory for report outputs",
    )
    parser.add_argument(
        "--weapon-id",
        action="append",
        type=int,
        help="Optional weapon id filter; pass multiple times to report specific weapons",
    )
    args = parser.parse_args()

    base_wz = Path(args.base_wz)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    profiles = build_profiles(base_wz=base_wz)
    type_matrix = build_type_matrix(profiles)

    all_json = out_dir / "weapon_action_profiles.json"
    type_json = out_dir / "weapon_type_action_matrix.json"
    type_csv = out_dir / "weapon_type_action_matrix.csv"

    all_json.write_text(json.dumps(profiles, indent=2), encoding="utf-8")
    type_json.write_text(json.dumps(type_matrix, indent=2), encoding="utf-8")

    with type_csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["weapon_type_code", "weapon_count", "common_actions", "union_actions_count"])
        for row in type_matrix:
            w.writerow(
                [
                    row["weapon_type_code"],
                    row["weapon_count"],
                    " ".join(row["common_actions"]),
                    len(row["union_actions"]),
                ]
            )

    result = {
        "status": "ok",
        "profiles_count": len(profiles),
        "type_count": len(type_matrix),
        "all_profiles_json": str(all_json),
        "type_matrix_json": str(type_json),
        "type_matrix_csv": str(type_csv),
    }

    if args.weapon_id:
        requested = set(args.weapon_id)
        selected = [row for row in profiles if int(row["weapon_id"]) in requested]
        selected_json = out_dir / "weapon_action_profiles_selected.json"
        selected_json.write_text(json.dumps(selected, indent=2), encoding="utf-8")
        result["selected_profiles_json"] = str(selected_json)
        result["selected_count"] = len(selected)

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

