#!/usr/bin/env python3
"""Build an Item.wz-wide catalogue (Cash/Consume/Etc/Install/Pet/Special)."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any
import xml.etree.ElementTree as ET

from wz_shared import FALLBACK_ANALYSIS_DIR, FALLBACK_BASE_WZ, child_imgdir, safe_name, utc_now_iso, write_csv


STRING_FILE_BY_ITEM_ROOT = {
    "Cash": "Cash.img.xml",
    "Consume": "Consume.img.xml",
    "Etc": "Etc.img.xml",
    "Install": "Ins.img.xml",
    "Pet": "Pet.img.xml",
    # Special item names are often under Cash/Etc depending on ID family.
    # We keep explicit support open and let fallback-by-id handle misses.
    "Special": None,
}


def _parse_item_name_map(string_xml: Path) -> dict[int, dict[str, str]]:
    if not string_xml.exists():
        return {}
    root = ET.parse(string_xml).getroot()
    out: dict[int, dict[str, str]] = {}

    def walk(node: ET.Element) -> None:
        if node.tag != "imgdir":
            return
        node_name = str(node.attrib.get("name", "")).strip()
        if node_name.isdigit():
            item_id = int(node_name)
            name = ""
            desc = ""
            for child in node:
                if child.tag == "string" and child.attrib.get("name") == "name":
                    name = str(child.attrib.get("value", ""))
                elif child.tag == "string" and child.attrib.get("name") == "desc":
                    desc = str(child.attrib.get("value", ""))
            if name or desc:
                out[item_id] = {"name": name, "desc": desc}
        for child in node:
            if child.tag == "imgdir":
                walk(child)

    walk(root)
    return out


def _load_name_maps(base_wz: Path) -> dict[str, dict[int, dict[str, str]]]:
    string_root = base_wz / "String" / "String.wz"
    maps: dict[str, dict[int, dict[str, str]]] = {}
    for item_root, string_file in STRING_FILE_BY_ITEM_ROOT.items():
        if string_file is None:
            maps[item_root] = {}
            continue
        maps[item_root] = _parse_item_name_map(string_root / string_file)

    # Fallback pool for categories where a direct mapping file is unclear.
    fallback_pool: dict[int, dict[str, str]] = {}
    for key in ("Cash", "Consume", "Etc", "Install", "Pet"):
        fallback_pool.update(maps.get(key, {}))
    maps["_fallback"] = fallback_pool
    return maps


def _extract_info_values(item_node: ET.Element) -> dict[str, str]:
    info = child_imgdir(item_node, "info")
    out = {
        "price": "",
        "cash_flag": "",
        "slot_max": "",
        "has_icon": "0",
        "has_icon_raw": "0",
    }
    scan_nodes = [info] if info is not None else [item_node]
    for scan_node in scan_nodes:
        for child in scan_node:
            tag = child.tag
            name = str(child.attrib.get("name", ""))
            value = str(child.attrib.get("value", ""))
            if tag == "canvas" and name == "icon":
                out["has_icon"] = "1"
            elif tag == "canvas" and name == "iconRaw":
                out["has_icon_raw"] = "1"
            elif tag == "imgdir" and name == "icon":
                out["has_icon"] = "1"
            elif tag == "imgdir" and name == "iconRaw":
                out["has_icon_raw"] = "1"
            elif tag == "int" and name == "price":
                out["price"] = value
            elif tag == "int" and name == "cash":
                out["cash_flag"] = value
            elif tag == "int" and name == "slotMax":
                out["slot_max"] = value
    return out


def build_catalogue(base_wz: Path, output_dir: Path) -> dict[str, Any]:
    item_root = base_wz / "Item" / "Item.wz"
    if not item_root.exists():
        raise FileNotFoundError(f"Item root not found: {item_root}")

    name_maps = _load_name_maps(base_wz)
    headers = [
        "item_root",
        "group_file",
        "id",
        "name",
        "desc",
        "has_icon",
        "has_icon_raw",
        "price",
        "cash_flag",
        "slot_max",
        "xml_relpath",
        "png_dir_relpath",
        "icon_png_relpath",
        "icon_raw_png_relpath",
    ]

    rows_all: list[dict[str, str]] = []
    rows_by_root: dict[str, list[dict[str, str]]] = defaultdict(list)

    item_roots = [d for d in sorted(item_root.iterdir()) if d.is_dir()]
    for root_dir in item_roots:
        root_name = root_dir.name
        root_names = name_maps.get(root_name, {})
        fallback_names = name_maps.get("_fallback", {})
        group_xmls = sorted(root_dir.glob("*.img.xml"))

        for group_xml in group_xmls:
            xml_rel = str(group_xml.relative_to(base_wz)).replace("\\", "/")
            group_name = group_xml.stem.replace(".img", "")
            group_png_dir = group_xml.with_suffix("")
            root = ET.parse(group_xml).getroot()

            item_entries: list[tuple[str, ET.Element, bool]] = []
            for item_node in root:
                if item_node.tag != "imgdir":
                    continue
                item_id_raw = str(item_node.attrib.get("name", "")).strip()
                if not item_id_raw.isdigit():
                    continue
                item_entries.append((item_id_raw, item_node, False))

            root_id_raw = str(root.attrib.get("name", "")).replace(".img", "").strip()
            if not item_entries and root_id_raw.isdigit():
                item_entries.append((root_id_raw, root, True))

            for item_id_raw, item_node, is_root_item in item_entries:
                item_id = int(item_id_raw)
                info = _extract_info_values(item_node)

                name_info = root_names.get(item_id) or fallback_names.get(item_id) or {}
                item_base_dir = group_png_dir if is_root_item else (group_png_dir / item_id_raw)
                item_png_dir = item_base_dir / "info"
                icon_png = item_png_dir / "icon.png"
                icon_raw_png = item_png_dir / "iconRaw.png"

                row = {
                    "item_root": root_name,
                    "group_file": group_name,
                    "id": str(item_id),
                    "name": str(name_info.get("name", "")),
                    "desc": str(name_info.get("desc", "")),
                    "has_icon": info["has_icon"],
                    "has_icon_raw": info["has_icon_raw"],
                    "price": info["price"],
                    "cash_flag": info["cash_flag"],
                    "slot_max": info["slot_max"],
                    "xml_relpath": xml_rel,
                    "png_dir_relpath": str(item_png_dir.relative_to(base_wz)).replace("\\", "/"),
                    "icon_png_relpath": str(icon_png.relative_to(base_wz)).replace("\\", "/"),
                    "icon_raw_png_relpath": str(icon_raw_png.relative_to(base_wz)).replace("\\", "/"),
                }
                rows_all.append(row)
                rows_by_root[root_name].append(row)

    rows_all.sort(key=lambda r: (r["item_root"], int(r["id"])))
    output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(output_dir / "itemwz_catalogue_all.csv", rows_all, headers)
    for root_name, rows in sorted(rows_by_root.items()):
        rows_sorted = sorted(rows, key=lambda r: int(r["id"]))
        write_csv(output_dir / f"itemwz_catalogue_{safe_name(root_name)}.csv", rows_sorted, headers)

    summary = {
        "generated_at_utc": utc_now_iso(),
        "base_wz": str(base_wz),
        "item_root": str(item_root),
        "output_dir": str(output_dir),
        "total_items": len(rows_all),
        "roots": {
            name: {
                "count": len(rows),
                "with_names": sum(1 for r in rows if r["name"]),
                "with_icon": sum(1 for r in rows if r["has_icon"] == "1"),
            }
            for name, rows in sorted(rows_by_root.items())
        },
    }
    (output_dir / "itemwz_catalogue_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    lines = [
        "# Item.wz Catalogue",
        "",
        f"- Generated: {summary['generated_at_utc']}",
        f"- Source: `{base_wz}`",
        f"- Total items: **{summary['total_items']}**",
        "",
        "## Roots",
        "",
    ]
    for root_name, info in sorted(summary["roots"].items()):
        lines.append(
            f"- **{root_name}**: {info['count']} items "
            f"({info['with_names']} with names, {info['with_icon']} with icon canvas)"
        )
    lines += [
        "",
        "## Files",
        "",
        "- `itemwz_catalogue_all.csv`",
        "- `itemwz_catalogue_summary.json`",
        "- `itemwz_catalogue_<root>.csv`",
    ]
    (output_dir / "itemwz_catalogue_index.md").write_text("\n".join(lines), encoding="utf-8")
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
        default=FALLBACK_ANALYSIS_DIR + r"\catalogue_itemwz",
        help="Directory for generated catalogue files",
    )
    args = parser.parse_args()

    summary = build_catalogue(Path(args.base_wz), Path(args.output_dir))
    print(
        json.dumps(
            {
                "status": "ok",
                "total_items": summary["total_items"],
                "root_count": len(summary["roots"]),
                "output_dir": args.output_dir,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
