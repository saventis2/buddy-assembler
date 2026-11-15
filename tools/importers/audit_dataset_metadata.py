#!/usr/bin/env python3
"""Audit MapleStory extracted dataset coverage and metadata availability."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
import xml.etree.ElementTree as ET

from wz_shared import child_imgdir, utc_now_iso


CORE_TREES = [
    "Character",
    "Item",
    "String",
    "Skill",
    "Effect",
    "Map",
    "Mob",
    "Npc",
    "Quest",
    "UI",
]

EQP_CATEGORIES = [
    "Accessory",
    "Cap",
    "Cape",
    "Coat",
    "Dragon",
    "Face",
    "Glove",
    "Hair",
    "Longcoat",
    "Pants",
    "PetEquip",
    "Ring",
    "Shield",
    "Shoes",
    "TamingMob",
    "Weapon",
]

INFO_FIELDS = [
    "islot",
    "vslot",
    "cash",
    "reqJob",
    "reqLevel",
    "reqSTR",
    "reqDEX",
    "reqINT",
    "reqLUK",
]


def _has_info_field(info_node: ET.Element, field: str) -> bool:
    tag = "string" if field in {"islot", "vslot"} else "int"
    for child in info_node:
        if child.tag == tag and child.attrib.get("name") == field:
            return True
    return False


def _read_info_int(info_node: ET.Element, field: str, default: int = 0) -> int:
    for child in info_node:
        if child.tag == "int" and child.attrib.get("name") == field:
            try:
                return int(child.attrib.get("value", "0"))
            except Exception:  # noqa: BLE001
                return default
    return default


def _read_info_string(info_node: ET.Element, field: str, default: str = "") -> str:
    for child in info_node:
        if child.tag == "string" and child.attrib.get("name") == field:
            return child.attrib.get("value", default)
    return default


def _count_name_entries(eqp_img_xml: Path) -> int:
    if not eqp_img_xml.exists():
        return 0
    root = ET.parse(eqp_img_xml).getroot()
    eqp_outer = child_imgdir(root, "Eqp")
    if eqp_outer is None:
        return 0
    total = 0
    for category in eqp_outer:
        if category.tag != "imgdir":
            continue
        for item in category:
            if item.tag == "imgdir":
                total += 1
    return total


def audit(base_wz: Path) -> dict:
    character_root = base_wz / "Character" / "Character.wz"
    item_root = base_wz / "Item" / "Item.wz"
    string_root = base_wz / "String" / "String.wz"

    tree_presence = {}
    for tree in CORE_TREES:
        tree_presence[tree] = (base_wz / tree).exists()

    category_stats = {}
    req_job_dist = Counter()
    weapon_type_dist = Counter()
    weapon_action_counts = Counter()
    weapon_action_presence = Counter()

    for category in EQP_CATEGORIES:
        category_dir = character_root / category
        xml_files = sorted(category_dir.glob("*.img.xml")) if category_dir.exists() else []
        png_dirs = sorted(category_dir.glob("*.img")) if category_dir.exists() else []
        info_field_presence = Counter()
        parsed = 0
        for xml_path in xml_files:
            try:
                root = ET.parse(xml_path).getroot()
            except Exception:  # noqa: BLE001
                continue
            info_node = child_imgdir(root, "info")
            if info_node is None:
                continue
            parsed += 1
            for field in INFO_FIELDS:
                if _has_info_field(info_node, field):
                    info_field_presence[field] += 1
            if category == "Weapon":
                raw_id = xml_path.name.replace(".img.xml", "")
                if not raw_id.isdigit():
                    continue
                item_id = int(raw_id)
                req_job = _read_info_int(info_node, "reqJob", default=0)
                req_job_dist[str(req_job)] += 1
                weapon_type_dist[str(item_id // 10000)] += 1
                action_count = 0
                for action_node in root:
                    if action_node.tag != "imgdir":
                        continue
                    action_name = action_node.attrib.get("name", "")
                    if not action_name or action_name == "info":
                        continue
                    has_numeric_frame = False
                    for frame_node in action_node:
                        if frame_node.tag == "imgdir" and frame_node.attrib.get("name", "").isdigit():
                            has_numeric_frame = True
                            break
                    if has_numeric_frame:
                        action_count += 1
                        weapon_action_presence[action_name] += 1
                weapon_action_counts[str(action_count)] += 1

        category_stats[category] = {
            "xml_files": len(xml_files),
            "png_dirs": len(png_dirs),
            "parsed_info_nodes": parsed,
            "info_field_presence": dict(info_field_presence),
            "info_field_coverage_pct": {
                field: round((info_field_presence.get(field, 0) / parsed * 100.0), 2) if parsed else 0.0
                for field in INFO_FIELDS
            },
        }

    eqp_img_xml = string_root / "Eqp.img.xml"
    name_entry_count = _count_name_entries(eqp_img_xml)

    install_xmls = sorted((item_root / "Install").glob("*.img.xml")) if (item_root / "Install").exists() else []
    install_req_fields = Counter()
    for path in install_xmls:
        try:
            root = ET.parse(path).getroot()
        except Exception:  # noqa: BLE001
            continue
        for child in root.iter("int"):
            name = child.attrib.get("name", "")
            if name.startswith("req"):
                install_req_fields[name] += 1

    return {
        "generated_at_utc": utc_now_iso(),
        "base_wz": str(base_wz),
        "tree_presence": tree_presence,
        "character_equipment_categories": category_stats,
        "weapon_req_job_distribution": dict(req_job_dist),
        "weapon_type_distribution": dict(weapon_type_dist),
        "weapon_action_count_distribution": dict(weapon_action_counts),
        "weapon_action_presence_top": dict(weapon_action_presence.most_common(30)),
        "string_eqp_name_entries": name_entry_count,
        "item_install_req_field_counts": dict(install_req_fields),
        "paths": {
            "character_root": str(character_root),
            "item_root": str(item_root),
            "string_root": str(string_root),
            "string_eqp_img_xml": str(eqp_img_xml),
        },
    }


def render_markdown(report: dict) -> str:
    lines = []
    lines.append("# Dataset Metadata Audit")
    lines.append("")
    lines.append(f"- Generated: {report['generated_at_utc']}")
    lines.append(f"- Base.wz: `{report['base_wz']}`")
    lines.append("")
    lines.append("## Core Tree Presence")
    lines.append("")
    for name, exists in report["tree_presence"].items():
        lines.append(f"- `{name}`: {'yes' if exists else 'no'}")
    lines.append("")
    lines.append("## Character Equipment Metadata Coverage")
    lines.append("")
    for category, row in report["character_equipment_categories"].items():
        lines.append(f"### {category}")
        lines.append(f"- XML files: {row['xml_files']}")
        lines.append(f"- Parsed `info` nodes: {row['parsed_info_nodes']}")
        cov = row["info_field_coverage_pct"]
        cov_line = ", ".join(f"{k}={cov.get(k, 0.0)}%" for k in INFO_FIELDS)
        lines.append(f"- Field coverage: {cov_line}")
        lines.append("")
    lines.append("## Weapon Metadata")
    lines.append("")
    lines.append(f"- reqJob distribution: `{report['weapon_req_job_distribution']}`")
    lines.append(f"- weapon type distribution: `{report['weapon_type_distribution']}`")
    lines.append(f"- action-count distribution: `{report['weapon_action_count_distribution']}`")
    lines.append(f"- top action presence: `{report['weapon_action_presence_top']}`")
    lines.append("")
    lines.append("## Name Tables")
    lines.append("")
    lines.append(f"- `String.wz/Eqp.img.xml` entries: {report['string_eqp_name_entries']}")
    lines.append("")
    lines.append("## Item Install Req Fields")
    lines.append("")
    lines.append(f"- counts: `{report['item_install_req_field_counts']}`")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit metadata coverage in extracted Base.wz dataset.")
    parser.add_argument("--base-wz", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    base_wz = Path(args.base_wz)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = audit(base_wz)
    md = render_markdown(report)

    report_path = out_dir / "dataset_metadata_audit_report.json"
    summary_path = out_dir / "dataset_metadata_audit_summary.md"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    summary_path.write_text(md, encoding="utf-8")

    print(
        json.dumps(
            {
                "report_path": str(report_path),
                "summary_path": str(summary_path),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
