#!/usr/bin/env python3
import argparse
import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "content" / "core_pack" / "manifest.json"
BINDINGS_PATH = ROOT / "content" / "core_pack" / "item_bindings_full.csv"


def parse_args():
    p = argparse.ArgumentParser(description="Sync manifest items from bindings CSV.")
    p.add_argument("--manifest", type=Path, default=MANIFEST_PATH)
    p.add_argument("--bindings", type=Path, default=BINDINGS_PATH)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument(
        "--add-missing",
        action="store_true",
        help="Append items that exist in bindings but not in manifest.",
    )
    p.add_argument(
        "--max-add",
        type=int,
        default=0,
        help="Cap number of missing items appended (0 = no cap).",
    )
    return p.parse_args()


def _to_int_or_none(value: str):
    value = (value or "").strip()
    if not value:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def load_bindings(bindings_path: Path):
    out = {}
    with bindings_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            runtime_id = (row.get("runtime_id") or "").strip()
            if not runtime_id:
                continue
            out[runtime_id] = row
    return out


def apply_row_to_item(item: dict, row: dict) -> None:
    if row.get("wz_name"):
        item["name"] = row["wz_name"].strip()
    if row.get("wz_desc"):
        item["description"] = row["wz_desc"].strip()
    if row.get("wz_id"):
        item["wzId"] = row["wz_id"].strip()
    if row.get("wz_root"):
        item["wzRoot"] = row["wz_root"].strip()
    if row.get("wz_group"):
        item["wzGroup"] = row["wz_group"].strip()
    if row.get("wz_icon_relpath"):
        item["wzIconPath"] = row["wz_icon_relpath"].strip()
    if row.get("icon_asset"):
        item["iconAsset"] = row["icon_asset"].strip()
    if row.get("equip_slot"):
        item["equipSlot"] = row["equip_slot"].strip()
    if row.get("category"):
        item["category"] = row["category"].strip()

    price = _to_int_or_none(row.get("wz_price", ""))
    slot_max = _to_int_or_none(row.get("wz_slot_max", ""))
    if price is not None:
        item["price"] = price
    if slot_max is not None:
        item["slotMax"] = slot_max


def make_item_from_row(runtime_id: str, row: dict) -> dict:
    item = {
        "id": runtime_id,
        "category": (row.get("category") or "materials").strip() or "materials",
        "rarity": "common",
        "primaryTheme": "cozy",
    }
    apply_row_to_item(item, row)
    if "name" not in item or not str(item["name"]).strip():
        item["name"] = runtime_id
    return item


def main():
    args = parse_args()
    manifest_path: Path = args.manifest
    bindings_path: Path = args.bindings

    with manifest_path.open("r", encoding="utf-8") as f:
        manifest = json.load(f)

    bindings = load_bindings(bindings_path)
    items = manifest.get("items", [])
    if not isinstance(items, list):
        items = []
        manifest["items"] = items

    changed = 0
    added = 0
    seen_ids = set()

    for item in items:
        if not isinstance(item, dict):
            continue
        runtime_id = str(item.get("id", "")).strip()
        if runtime_id:
            seen_ids.add(runtime_id)
        if not runtime_id or runtime_id not in bindings:
            continue

        row = bindings[runtime_id]
        before = json.dumps(item, ensure_ascii=False, sort_keys=True)
        apply_row_to_item(item, row)
        after = json.dumps(item, ensure_ascii=False, sort_keys=True)
        if before != after:
            changed += 1

    if args.add_missing:
        cap = max(0, int(args.max_add))
        for runtime_id, row in bindings.items():
            if runtime_id in seen_ids:
                continue
            items.append(make_item_from_row(runtime_id, row))
            added += 1
            if cap > 0 and added >= cap:
                break

    if not args.dry_run:
        with manifest_path.open("w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
            f.write("\n")

    print(f"updated_items={changed}")
    print(f"added_items={added}")
    print(f"dry_run={args.dry_run}")
    print(f"manifest={manifest_path}")
    print(f"bindings={bindings_path}")


if __name__ == "__main__":
    main()
