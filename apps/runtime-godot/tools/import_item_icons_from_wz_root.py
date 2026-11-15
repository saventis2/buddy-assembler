#!/usr/bin/env python3
import argparse
import csv
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "content" / "core_pack" / "manifest.json"
BINDINGS_PATH = ROOT / "content" / "core_pack" / "item_bindings_full.csv"
ICON_OUT_DIR = ROOT / "content" / "core_pack" / "icons" / "items"
DEFAULT_WZ_ROOT = Path("C:/Users/GGPC/OneDrive/Desktop/83 complete/Base.wz")


def parse_args():
    p = argparse.ArgumentParser(description="Import item icons from extracted WZ root.")
    p.add_argument("--manifest", type=Path, default=MANIFEST_PATH)
    p.add_argument("--bindings", type=Path, default=BINDINGS_PATH)
    p.add_argument("--wz-root", type=Path, default=DEFAULT_WZ_ROOT)
    p.add_argument("--icon-out", type=Path, default=ICON_OUT_DIR)
    return p.parse_args()


def _norm_rel(rel: str) -> str:
    return (rel or "").strip().replace("\\", "/").lstrip("/")


def _expand_rel_variants(rel: str):
    rel = _norm_rel(rel)
    if not rel:
        return []
    variants = [rel]
    if rel.endswith("/info/icon.png"):
        stem = rel[: -len("/info/icon.png")]
        variants.extend(
            [
                f"{stem}/icon.png",
                f"{stem}/iconRaw/0.png",
                f"{stem}/iconRaw/default/0.png",
                f"{stem}/iconRaw",
            ]
        )
    return variants


def _resolve_source(cands):
    for cand in cands:
        if not cand.exists():
            continue
        if cand.is_file():
            return cand
        # Some extracted WZ paths expose icon directories (e.g. iconRaw/0.png).
        if cand.is_dir():
            preferred = [cand / "0.png", cand / "default" / "0.png"]
            for p in preferred:
                if p.exists() and p.is_file():
                    return p
            frames = sorted(cand.glob("*.png"))
            if frames:
                return frames[0]
            nested_default = sorted((cand / "default").glob("*.png"))
            if nested_default:
                return nested_default[0]
    return None


def _candidate_paths(wz_root: Path, wz_rel: str):
    root = str(wz_root).replace("\\", "/").rstrip("/")
    cands = []
    for rel in _expand_rel_variants(wz_rel):
        rel_wo_item = rel[5:] if rel.startswith("Item/") else rel
        cands.extend(
            [
                f"{root}/{rel}",
                f"{root}/{rel_wo_item}",
                f"{root}/Base.wz/{rel}",
                f"{root}/Base.wz/{rel_wo_item}",
                f"{root}/Item/{rel_wo_item}",
                f"{root}/Base.wz/Item/{rel_wo_item}",
            ]
        )
    out = []
    seen = set()
    for c in cands:
        p = Path(c)
        key = str(p).lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def _load_bindings(bindings_path: Path):
    rows = {}
    with bindings_path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            rid = (row.get("runtime_id") or "").strip()
            if rid:
                rows[rid] = row
    return rows


def main():
    args = parse_args()
    manifest_path: Path = args.manifest
    bindings_path: Path = args.bindings
    wz_root: Path = args.wz_root
    icon_out_dir: Path = args.icon_out
    if not wz_root.exists():
        print(f"wz_root_missing={wz_root}")
        return

    icon_out_dir.mkdir(parents=True, exist_ok=True)
    bindings = _load_bindings(bindings_path)

    with manifest_path.open("r", encoding="utf-8") as f:
        manifest = json.load(f)

    copied = 0
    missing = 0
    items = manifest.get("items", [])
    for item in items:
        if not isinstance(item, dict):
            continue
        rid = str(item.get("id", "")).strip()
        if rid not in bindings:
            continue
        row = bindings[rid]
        wz_rel = row.get("wz_icon_relpath", "")
        source = _resolve_source(_candidate_paths(wz_root, wz_rel))
        if source is None:
            missing += 1
            continue
        out_name = f"{rid}.png"
        out_path = icon_out_dir / out_name
        shutil.copyfile(source, out_path)
        item["iconAsset"] = f"icons/items/{out_name}"
        copied += 1

    with manifest_path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"copied={copied}")
    print(f"missing={missing}")
    print(f"icon_out={icon_out_dir}")
    print(f"manifest={manifest_path}")
    print(f"bindings={bindings_path}")


if __name__ == "__main__":
    main()
