#!/usr/bin/env python3
"""Report and repair missing manifest item icons.

Repairs by assigning category-based fallback iconAsset when current icon asset
is missing on disk.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_ROOT = ROOT / "content" / "core_pack"
MANIFEST = PACK_ROOT / "manifest.json"
REPORT_CSV = ROOT.parent / "docs" / "product" / "WZ_ICON_MISSING_REPORT.csv"

FALLBACK_BY_CATEGORY = {
    "food": "effects/gift_box/frames/000.png",
    "gifts": "effects/gift_box/frames/000.png",
    "gear": "effects/happy_sparkle/frames/000.png",
    "training_items": "effects/gift_box/frames/000.png",
    "evolution_items": "effects/levelup/frames/000.png",
    "materials": "effects/levelup/frames/000.png",
    "decor": "effects/chair_basic/frames/000.png",
    "quest_items": "effects/levelup/frames/000.png",
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--report", type=Path, default=REPORT_CSV)
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()


def is_local_asset_missing(icon_asset: str) -> bool:
    if not icon_asset:
        return True
    if icon_asset.startswith("res://"):
        full = ROOT / icon_asset.replace("res://", "", 1)
        return not full.exists()
    else:
        full = PACK_ROOT / icon_asset
    return not full.exists()


def choose_fallback(category: str) -> str:
    key = (category or "").strip().lower()
    return FALLBACK_BY_CATEGORY.get(key, "effects/levelup/frames/000.png")


def main() -> int:
    args = parse_args()
    manifest_path: Path = args.manifest
    report_path: Path = args.report

    if not manifest_path.exists():
        print(f"error: manifest missing: {manifest_path}")
        return 2

    with manifest_path.open("r", encoding="utf-8") as f:
        manifest = json.load(f)

    items = manifest.get("items", [])
    if not isinstance(items, list):
        print("error: manifest.items is not a list")
        return 2

    missing_rows: list[dict] = []
    repaired = 0

    for item in items:
        if not isinstance(item, dict):
            continue
        item_id = str(item.get("id", "")).strip()
        category = str(item.get("category", "")).strip().lower()
        icon_asset = str(item.get("iconAsset", "")).strip()
        if not is_local_asset_missing(icon_asset):
            continue
        fallback = choose_fallback(category)
        missing_rows.append(
            {
                "id": item_id,
                "category": category,
                "name": str(item.get("name", "")).strip(),
                "wzId": str(item.get("wzId", "")).strip(),
                "iconAssetBefore": icon_asset,
                "iconAssetAfter": fallback,
                "wzIconPath": str(item.get("wzIconPath", "")).strip(),
            }
        )
        item["iconAsset"] = fallback
        item["iconFallbackApplied"] = True
        repaired += 1

    report_path.parent.mkdir(parents=True, exist_ok=True)
    with report_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "id",
                "category",
                "name",
                "wzId",
                "iconAssetBefore",
                "iconAssetAfter",
                "wzIconPath",
            ],
        )
        writer.writeheader()
        writer.writerows(missing_rows)

    if not args.dry_run:
        with manifest_path.open("w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
            f.write("\n")

    print(f"missing_icon_rows={len(missing_rows)}")
    print(f"repaired={repaired}")
    print(f"dry_run={args.dry_run}")
    print(f"report={report_path}")
    print(f"manifest={manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
