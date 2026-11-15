#!/usr/bin/env python3
"""Build a canonical WZ item map by joining WZ string + item/equipment extracts.

Input default:
  C:/Users/GGPC/OneDrive/Desktop/83 complete/Base.wz

Outputs:
  - CSV (runtime-friendly bindings)
  - JSON (full normalized rows)
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Dict, Iterable, List, Optional
import xml.etree.ElementTree as ET


DEFAULT_WZ_ROOT = Path("C:/Users/GGPC/OneDrive/Desktop/83 complete/Base.wz")
DEFAULT_OUT_CSV = Path("apps/runtime-godot/content/core_pack/item_bindings_full.csv")
DEFAULT_OUT_JSON = Path("apps/runtime-godot/content/core_pack/item_bindings_full.json")

STRING_FILES = (
    "Consume.img.xml",
    "Eqp.img.xml",
    "Etc.img.xml",
    "Cash.img.xml",
)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--wz-root",
        type=Path,
        action="append",
        default=None,
        help="WZ root folder. Can be provided multiple times.",
    )
    p.add_argument("--out-csv", type=Path, default=DEFAULT_OUT_CSV)
    p.add_argument("--out-json", type=Path, default=DEFAULT_OUT_JSON)
    p.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Optional max rows for quick iteration (0 = no limit).",
    )
    return p.parse_args()


def node_name(elem: ET.Element) -> str:
    return (elem.attrib.get("name") or "").strip()


def child_named(elem: ET.Element, name: str) -> Optional[ET.Element]:
    for child in elem:
        if node_name(child) == name:
            return child
    return None


def find_nested_imgdir(elem: ET.Element, parts: Iterable[str]) -> Optional[ET.Element]:
    cur = elem
    for part in parts:
        nxt = child_named(cur, part)
        if nxt is None or nxt.tag != "imgdir":
            return None
        cur = nxt
    return cur


def find_nested_value(elem: ET.Element, parts: Iterable[str]) -> Optional[str]:
    cur = elem
    parts = list(parts)
    for i, part in enumerate(parts):
        nxt = child_named(cur, part)
        if nxt is None:
            return None
        if i == len(parts) - 1:
            return (nxt.attrib.get("value") or "").strip()
        if nxt.tag != "imgdir":
            return None
        cur = nxt
    return None


def load_string_maps(wz_root: Path) -> Dict[str, Dict[str, str]]:
    string_root = wz_root / "String" / "String.wz"
    out: Dict[str, Dict[str, str]] = {}
    for filename in STRING_FILES:
        path = string_root / filename
        if not path.exists():
            continue
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError:
            continue
        for entry in root:
            if entry.tag != "imgdir":
                continue
            item_id = node_name(entry)
            if not item_id:
                continue
            row = out.setdefault(item_id, {})
            for child in entry:
                if child.tag != "string":
                    continue
                k = node_name(child)
                v = (child.attrib.get("value") or "").strip()
                if k and v:
                    row[k] = v
    return out


def load_eqp_string_map(wz_root: Path) -> Dict[str, Dict[str, str]]:
    """Load equipment names/descriptions from String.wz/Eqp.img.xml.

    Structure is nested (Eqp -> group -> item_id), unlike flat item string sheets.
    """
    path = wz_root / "String" / "String.wz" / "Eqp.img.xml"
    out: Dict[str, Dict[str, str]] = {}
    if not path.exists():
        return out
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return out

    eqp_root = find_nested_imgdir(root, ("Eqp",))
    if eqp_root is None:
        return out

    for group in eqp_root:
        if group.tag != "imgdir":
            continue
        for entry in group:
            if entry.tag != "imgdir":
                continue
            item_id = node_name(entry)
            if not item_id.isdigit():
                continue
            row = out.setdefault(item_id, {})
            for child in entry:
                if child.tag != "string":
                    continue
                k = node_name(child)
                v = (child.attrib.get("value") or "").strip()
                if k and v:
                    row[k] = v
    return out


def category_from_root(root_name: str) -> str:
    key = root_name.lower()
    if key == "consume":
        return "food"
    if key == "equip":
        return "gear"
    if key == "install":
        return "decor"
    if key == "etc":
        return "materials"
    if key == "cash":
        return "gifts"
    return "materials"


def runtime_id_for(wz_id: str, wz_name: str) -> str:
    slug = wz_name.lower().strip()
    if slug:
        safe = []
        for ch in slug:
            if ch.isalnum():
                safe.append(ch)
            elif ch in (" ", "-", "_"):
                safe.append("-")
        joined = "".join(safe).strip("-")
        while "--" in joined:
            joined = joined.replace("--", "-")
        if joined:
            return f"wz-{joined}"
    return f"wz-{wz_id}"


def _equip_slot_from_wz_id(wz_id: str) -> str:
    """Derive equip slot from Maple-style item id prefixes when available."""
    key = (wz_id or "").strip()
    if len(key) < 3 or not key.isdigit():
        return ""
    prefix3 = key[:3]
    if prefix3 == "100":
        return "hat"
    if prefix3 == "101":
        return "face_accessory"
    if prefix3 == "102":
        return "eye_accessory"
    if prefix3 == "103":
        return "earrings"
    if prefix3 == "104":
        return "top"
    if prefix3 == "105":
        return "overall"
    if prefix3 == "106":
        return "bottom"
    if prefix3 == "107":
        return "shoes"
    if prefix3 == "108":
        return "gloves"
    if prefix3 == "109":
        return "shield"
    if prefix3 == "110":
        return "cape"
    if prefix3 == "111":
        return "ring1"
    if prefix3 == "112":
        return "pendant1"
    if prefix3 == "113":
        return "belt"
    if prefix3 == "114":
        return "medal"
    if prefix3 == "115":
        return "shoulder"
    if prefix3 == "116":
        return "pocket"
    if prefix3 == "118":
        return "badge"
    if prefix3 == "119":
        return "emblem"
    if prefix3 in {"121", "122", "123", "124", "125", "126", "127", "128", "129"}:
        return "weapon"
    if prefix3 in {"130", "131", "132", "133", "134", "135", "136", "137", "138", "140", "141", "142", "143", "144", "145", "146", "147", "148", "149", "152", "153", "154", "155", "156", "157", "158", "159", "170"}:
        return "weapon"
    return ""


def equip_slot_from_group(group: str, wz_id: str = "") -> str:
    key = group.lower().strip()
    if key == "accessory":
        # Accessory.* is polymorphic in WZ, so prefer id-derived slots.
        slot = _equip_slot_from_wz_id(wz_id)
        if slot:
            return slot
    mapping = {
        "weapon": "weapon",
        "shield": "shield",
        "cap": "hat",
        "accessory": "face_accessory",
        "coat": "top",
        "longcoat": "overall",
        "pants": "bottom",
        "shoes": "shoes",
        "glove": "gloves",
        "cape": "cape",
        "ring": "ring1",
        "dragon": "badge",
        "medal": "medal",
        "belt": "belt",
        "shoulder": "shoulder",
        "emblem": "emblem",
        "pocket": "pocket",
        "face": "face_accessory",
        "eye": "eye_accessory",
        "earring": "earrings",
        "earrings": "earrings",
    }
    return mapping.get(key, "")


def runtime_id_for_equip(wz_id: str, group: str) -> str:
    return f"wz-{group.lower()}-{wz_id}"


def build_item_rows(
    wz_root: Path,
    string_map: Dict[str, Dict[str, str]],
    limit: int = 0,
) -> List[Dict[str, object]]:
    item_root = wz_root / "Item" / "Item.wz"
    rows: List[Dict[str, object]] = []
    if not item_root.exists():
        return rows

    xml_paths = sorted(item_root.rglob("*.img.xml"))
    for xml_path in xml_paths:
        rel = xml_path.relative_to(wz_root).as_posix()
        parts = rel.split("/")
        if len(parts) < 4:
            continue
        # Item/Item.wz/<root>/<group>.img.xml
        wz_root_name = parts[2]
        group_file = parts[3]
        wz_group = group_file.replace(".img.xml", "")

        try:
            tree_root = ET.parse(xml_path).getroot()
        except ET.ParseError:
            continue

        for entry in tree_root:
            if entry.tag != "imgdir":
                continue
            wz_id = node_name(entry)
            if not wz_id.isdigit():
                continue

            strings = string_map.get(wz_id, {})
            wz_name = strings.get("name", "").strip()
            wz_desc = strings.get("desc", "").strip()
            if not wz_name:
                wz_name = f"Item {wz_id}"

            price_raw = find_nested_value(entry, ("info", "price")) or ""
            slot_raw = (
                find_nested_value(entry, ("info", "slotMax"))
                or find_nested_value(entry, ("spec", "slotMax"))
                or ""
            )

            runtime_id = runtime_id_for(wz_id, wz_name)
            icon_rel = (
                f"Item/Item.wz/{wz_root_name}/{wz_group}.img/{wz_id}/info/icon.png"
            )
            category = category_from_root(wz_root_name)

            rows.append(
                {
                    "runtime_id": runtime_id,
                    "wz_id": wz_id,
                    "wz_root": wz_root_name,
                    "wz_group": wz_group,
                    "wz_name": wz_name,
                    "wz_desc": wz_desc,
                    "wz_price": int(price_raw) if price_raw.isdigit() else "",
                    "wz_slot_max": int(slot_raw) if slot_raw.isdigit() else "",
                    "wz_icon_relpath": icon_rel,
                    "icon_asset": f"icons/items/{runtime_id}.png",
                    "equip_slot": "",
                    "category": category,
                }
            )

            if limit > 0 and len(rows) >= limit:
                return rows
    return rows


def build_equip_rows(
    wz_root: Path,
    eqp_string_map: Dict[str, Dict[str, str]],
    limit: int = 0,
) -> List[Dict[str, object]]:
    """Build canonical rows for Character.wz equipment that provide equip icons."""
    character_root = wz_root / "Character" / "Character.wz"
    rows: List[Dict[str, object]] = []
    if not character_root.exists():
        return rows

    # Character/<Group>/<XXXXXXXX>.img/info/icon.png
    icon_paths = sorted(character_root.glob("*/*.img/info/icon.png"))
    for icon_path in icon_paths:
        try:
            rel = icon_path.relative_to(wz_root).as_posix()
        except ValueError:
            continue
        parts = rel.split("/")
        if len(parts) < 5:
            continue
        group = parts[2]
        img_file = parts[3]
        if not img_file.endswith(".img"):
            continue
        raw_id = img_file.replace(".img", "")
        wz_id = raw_id.lstrip("0")
        if not wz_id.isdigit():
            continue
        if wz_id == "":
            wz_id = "0"

        strings = eqp_string_map.get(wz_id, {})
        wz_name = strings.get("name", "").strip()
        wz_desc = strings.get("desc", "").strip()
        if not wz_name:
            wz_name = f"{group} {wz_id}"

        runtime_id = runtime_id_for_equip(wz_id, group)
        rows.append(
            {
                "runtime_id": runtime_id,
                "wz_id": wz_id,
                "wz_root": "Character",
                "wz_group": group,
                "wz_name": wz_name,
                "wz_desc": wz_desc,
                "wz_price": "",
                "wz_slot_max": "",
                "wz_icon_relpath": rel,
                "icon_asset": f"icons/items/{runtime_id}.png",
                "equip_slot": equip_slot_from_group(group, wz_id=wz_id),
                "category": "gear",
            }
        )
        if limit > 0 and len(rows) >= limit:
            return rows
    return rows


def dedupe_rows(rows: List[Dict[str, object]]) -> List[Dict[str, object]]:
    by_id: Dict[str, Dict[str, object]] = {}
    for row in rows:
        rid = str(row.get("runtime_id", "")).strip()
        if not rid:
            continue
        if rid not in by_id:
            by_id[rid] = row
            continue
        existing = by_id[rid]
        # Prefer row with explicit equip slot and non-generic naming.
        pick = existing
        if str(existing.get("equip_slot", "")).strip() == "" and str(row.get("equip_slot", "")).strip() != "":
            pick = row
        elif str(existing.get("wz_name", "")).lower().startswith("item ") and not str(row.get("wz_name", "")).lower().startswith("item "):
            pick = row
        by_id[rid] = pick
    return list(by_id.values())


def write_csv(path: Path, rows: List[Dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "runtime_id",
        "wz_id",
        "wz_root",
        "wz_group",
        "wz_name",
        "wz_desc",
        "wz_price",
        "wz_slot_max",
        "wz_icon_relpath",
        "icon_asset",
        "equip_slot",
        "category",
    ]
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_json(path: Path, rows: List[Dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main() -> int:
    args = parse_args()
    wz_roots: List[Path] = args.wz_root if args.wz_root else [DEFAULT_WZ_ROOT]
    missing = [p for p in wz_roots if not p.exists()]
    if missing:
        for path in missing:
            print(f"error: wz root missing: {path}")
        return 1

    rows: List[Dict[str, object]] = []
    for wz_root in wz_roots:
        strings = load_string_maps(wz_root)
        eqp_strings = load_eqp_string_map(wz_root)
        rows.extend(build_item_rows(wz_root, strings, limit=0))
        rows.extend(build_equip_rows(wz_root, eqp_strings, limit=0))
    rows = dedupe_rows(rows)
    if int(args.limit) > 0:
        rows = rows[: int(args.limit)]
    rows.sort(key=lambda r: (str(r["wz_root"]), str(r["wz_group"]), str(r["wz_id"])))

    write_csv(args.out_csv, rows)
    write_json(args.out_json, rows)

    print("wz_roots=%s" % ",".join(str(p) for p in wz_roots))
    print(f"rows={len(rows)}")
    print(f"out_csv={args.out_csv}")
    print(f"out_json={args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
