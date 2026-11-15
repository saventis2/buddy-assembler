#!/usr/bin/env python3
"""Build a categorized MapleStory character item catalogue from extracted Base.wz."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Dict
import xml.etree.ElementTree as ET

from wz_shared import FALLBACK_ANALYSIS_DIR, FALLBACK_BASE_WZ, child_imgdir, safe_name, utc_now_iso, write_csv


def _extract_info(xml_path: Path) -> dict:
    root = ET.parse(xml_path).getroot()
    info = child_imgdir(root, "info")
    out = {"islot": "", "vslot": "", "cash": ""}
    if info is None:
        return out
    for node in info:
        if node.tag == "string" and node.attrib.get("name") in ("islot", "vslot"):
            out[node.attrib.get("name", "")] = node.attrib.get("value", "")
        elif node.tag == "int" and node.attrib.get("name") == "cash":
            out["cash"] = node.attrib.get("value", "")
    return out


def _load_eqp_names(base_wz: Path) -> Dict[int, dict]:
    eqp_xml = base_wz / "String" / "String.wz" / "Eqp.img.xml"
    if not eqp_xml.exists():
        return {}
    root = ET.parse(eqp_xml).getroot()
    eqp_outer = child_imgdir(root, "Eqp")
    out: Dict[int, dict] = {}
    if eqp_outer is None:
        return out

    for category_node in eqp_outer:
        if category_node.tag != "imgdir":
            continue
        category = category_node.attrib.get("name", "")
        for item_node in category_node:
            if item_node.tag != "imgdir":
                continue
            raw_id = item_node.attrib.get("name", "")
            if not raw_id.isdigit():
                continue
            item_id = int(raw_id)
            name = ""
            desc = ""
            for child in item_node:
                if child.tag == "string" and child.attrib.get("name") == "name":
                    name = child.attrib.get("value", "")
                elif child.tag == "string" and child.attrib.get("name") == "desc":
                    desc = child.attrib.get("value", "")
            if name or desc:
                out[item_id] = {"name": name, "desc": desc, "eqp_category": category}
    return out


def build_catalogue(base_wz: Path, output_dir: Path) -> dict:
    char_root = base_wz / "Character" / "Character.wz"
    if not char_root.exists():
        raise FileNotFoundError(f"Character root not found: {char_root}")

    eqp_names = _load_eqp_names(base_wz)
    headers = [
        "part_category",
        "id",
        "name",
        "desc",
        "eqp_category",
        "islot",
        "vslot",
        "cash",
        "xml_relpath",
        "png_dir_relpath",
    ]

    categories = []
    for d in sorted(char_root.iterdir()):
        if d.is_dir() and not d.name[:1].isdigit():
            categories.append(d)

    all_rows = []
    by_category = defaultdict(list)

    for cat_dir in categories:
        part_category = cat_dir.name
        xmls = sorted(cat_dir.glob("*.img.xml"))
        for xml_path in xmls:
            stem = xml_path.stem  # 00030000.img
            raw_id = stem.replace(".img", "")
            if not raw_id.isdigit():
                continue
            item_id = int(raw_id)

            info = _extract_info(xml_path)
            name_info = eqp_names.get(item_id, {})
            row = {
                "part_category": part_category,
                "id": str(item_id),
                "name": name_info.get("name", ""),
                "desc": name_info.get("desc", ""),
                "eqp_category": name_info.get("eqp_category", ""),
                "islot": info.get("islot", ""),
                "vslot": info.get("vslot", ""),
                "cash": info.get("cash", ""),
                "xml_relpath": str(xml_path.relative_to(base_wz)).replace("\\", "/"),
                "png_dir_relpath": str(xml_path.with_suffix("").relative_to(base_wz)).replace("\\", "/"),
            }
            all_rows.append(row)
            by_category[part_category].append(row)

    output_dir.mkdir(parents=True, exist_ok=True)

    # Master CSV
    all_rows_sorted = sorted(all_rows, key=lambda r: (r["part_category"], int(r["id"])))
    write_csv(output_dir / "catalogue_all.csv", all_rows_sorted, headers)

    # Per-category CSVs
    for cat, rows in sorted(by_category.items()):
        rows_sorted = sorted(rows, key=lambda r: int(r["id"]))
        write_csv(output_dir / f"catalogue_{safe_name(cat)}.csv", rows_sorted, headers)

    summary = {
        "generated_at_utc": utc_now_iso(),
        "base_wz": str(base_wz),
        "character_root": str(char_root),
        "output_dir": str(output_dir),
        "total_items": len(all_rows_sorted),
        "categories": {
            cat: {
                "count": len(rows),
                "with_names": sum(1 for r in rows if r["name"]),
            }
            for cat, rows in sorted(by_category.items())
        },
    }
    (output_dir / "catalogue_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    # Human index
    lines = [
        "# Character Item Catalogue",
        "",
        f"- Generated: {summary['generated_at_utc']}",
        f"- Source: `{base_wz}`",
        f"- Total items: **{summary['total_items']}**",
        "",
        "## Categories",
        "",
    ]
    for cat, info in sorted(summary["categories"].items()):
        lines.append(
            f"- **{cat}**: {info['count']} items ({info['with_names']} with mapped names) "
            f"- `catalogue_{safe_name(cat)}.csv`"
        )
    lines += [
        "",
        "## Files",
        "",
        "- `catalogue_all.csv`",
        "- `catalogue_summary.json`",
        "- `catalogue_<category>.csv` per part category",
    ]
    (output_dir / "catalogue_index.md").write_text("\n".join(lines), encoding="utf-8")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-wz",
        default=FALLBACK_BASE_WZ,
        help="Path to extracted Base.wz directory",
    )
    parser.add_argument(
        "--output-dir",
        default=FALLBACK_ANALYSIS_DIR + r"\catalogue",
        help="Directory for generated catalogue files",
    )
    args = parser.parse_args()

    summary = build_catalogue(Path(args.base_wz), Path(args.output_dir))
    print(
        json.dumps(
            {
                "status": "ok",
                "total_items": summary["total_items"],
                "category_count": len(summary["categories"]),
                "output_dir": args.output_dir,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
