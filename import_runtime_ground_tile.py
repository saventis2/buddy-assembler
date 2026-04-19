#!/usr/bin/env python3
"""Import a Maple terrain tile PNG into the runtime content pack."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image


def _safe_name(value: str) -> str:
    out = []
    for ch in value:
        if ch.isalnum() or ch in {"-", "_"}:
            out.append(ch)
        else:
            out.append("_")
    return "".join(out).strip("_")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-wz",
        default=r"C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz",
        help="Path to extracted Base.wz root",
    )
    parser.add_argument("--tile-set", default="citySG", help="Tile set name under Map/Map.wz/Tile")
    parser.add_argument("--group", default="bsc", help="Tile group folder (example: bsc, enH0)")
    parser.add_argument("--index", type=int, default=0, help="Tile frame index")
    parser.add_argument(
        "--output-dir",
        default="apps/runtime-godot/content/core_pack/terrain",
        help="Output directory inside repo",
    )
    parser.add_argument(
        "--output-name",
        default="",
        help="Optional output filename (default: ground_<tile-set>_<group>_<index>.png)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent
    base_wz = Path(args.base_wz).resolve()
    source = (
        base_wz
        / "Map"
        / "Map.wz"
        / "Tile"
        / f"{args.tile_set}.img"
        / args.group
        / f"{int(args.index)}.png"
    )
    if not source.exists():
        raise SystemExit(f"Tile PNG not found: {source}")

    out_dir = (repo_root / args.output_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    output_name = args.output_name.strip()
    if not output_name:
        output_name = "ground_%s_%s_%d.png" % (
            _safe_name(args.tile_set),
            _safe_name(args.group),
            int(args.index),
        )
    target = out_dir / output_name
    shutil.copy2(source, target)

    with Image.open(target) as im:
        width, height = im.size

    rel_target = target.relative_to(repo_root).as_posix()
    payload = {
        "imported_from": str(source),
        "target": str(target),
        "size": [width, height],
        "manifest_ground_snippet": {
            "enabled": True,
            "texture": rel_target.replace("apps/runtime-godot/content/core_pack/", ""),
            "tile_x": True,
            "scale": 1.0,
            "alpha": 1.0,
            "align": "top",
            "floor_offset_y": 0.0,
            "x_offset": 0.0,
        },
    }
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

