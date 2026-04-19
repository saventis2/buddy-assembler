"""Index uncatalogued WZ asset trees (Effect, Install chairs) into flat CSVs + an INDEX.md.

Existing catalogs under `Artifacts/catalogue/` and `analysis/catalogue_itemwz/`
already cover Character parts and core Item categories. Missing, and hit
repeatedly during runtime wiring, are:

  - Effect.wz/BasicEff.img/*  (LevelUp sparkle, Buff, Flame, Teleport, ...)
  - Effect.wz/CharacterEff.img, ItemEff.img, OnUserEff.img
  - Item.wz/Install/0301.img/*  (chairs — visual furniture for the sit action)

For each leaf we emit: id, name/path, frame_count, first_frame_png, size range.
"""

from __future__ import annotations

import csv
import xml.etree.ElementTree as ET
from pathlib import Path

BASE_WZ = Path(r"C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz")
OUT_ROOT = Path(__file__).resolve().parent / "analysis" / "wz_index"


def _find_imgdirs(node: ET.Element, path: list[str]) -> ET.Element | None:
    cur = node
    for name in path:
        nxt = None
        for child in cur:
            if child.tag == "imgdir" and child.attrib.get("name") == name:
                nxt = child
                break
        if nxt is None:
            return None
        cur = nxt
    return cur


def _canvas_summary(node: ET.Element) -> dict:
    """Return frame_count, size range, whether children are numeric canvases."""
    canvases = [c for c in node if c.tag == "canvas" and c.attrib.get("name", "").isdigit()]
    if not canvases:
        return {"frame_count": 0, "w_min": 0, "w_max": 0, "h_min": 0, "h_max": 0}
    widths = [int(c.attrib.get("width", 0)) for c in canvases]
    heights = [int(c.attrib.get("height", 0)) for c in canvases]
    return {
        "frame_count": len(canvases),
        "w_min": min(widths),
        "w_max": max(widths),
        "h_min": min(heights),
        "h_max": max(heights),
    }


def index_effect_img(img_name: str) -> list[dict]:
    """Index all top-level imgdirs inside an Effect.wz/<img>.img file."""
    xml_path = BASE_WZ / "Effect" / "Effect.wz" / f"{img_name}.xml"
    png_root = BASE_WZ / "Effect" / "Effect.wz" / img_name
    if not xml_path.exists():
        return []

    rows: list[dict] = []
    tree = ET.parse(xml_path)
    root = tree.getroot()
    for effect_dir in root:
        if effect_dir.tag != "imgdir":
            continue
        effect_name = effect_dir.attrib.get("name", "")
        # Some effects are nested one level deeper (e.g. MonsterBook/cardGet).
        # Record both the flat top-level summary and any child imgdirs.
        summary = _canvas_summary(effect_dir)
        if summary["frame_count"] > 0:
            rows.append(_effect_row(img_name, [effect_name], summary, png_root))
        for sub in effect_dir:
            if sub.tag != "imgdir":
                continue
            sub_summary = _canvas_summary(sub)
            if sub_summary["frame_count"] > 0:
                rows.append(
                    _effect_row(
                        img_name,
                        [effect_name, sub.attrib.get("name", "")],
                        sub_summary,
                        png_root,
                    )
                )
    return rows


def _effect_row(img_name: str, path: list[str], summary: dict, png_root: Path) -> dict:
    first_frame = png_root.joinpath(*path) / "0.png"
    return {
        "img": img_name,
        "path": "/".join(path),
        "frame_count": summary["frame_count"],
        "w_range": f"{summary['w_min']}-{summary['w_max']}",
        "h_range": f"{summary['h_min']}-{summary['h_max']}",
        "first_frame": str(first_frame) if first_frame.exists() else "",
    }


def index_install_chairs() -> list[dict]:
    """Each chair is Item.wz/Install/0301.img/<id>/effect/0.png + info/icon.png."""
    xml_path = BASE_WZ / "Item" / "Item.wz" / "Install" / "0301.img.xml"
    png_root = BASE_WZ / "Item" / "Item.wz" / "Install" / "0301.img"
    if not xml_path.exists():
        return []

    rows: list[dict] = []
    tree = ET.parse(xml_path)
    for item in tree.getroot():
        if item.tag != "imgdir":
            continue
        item_id = item.attrib.get("name", "")
        effect_node = None
        info_node = None
        for sub in item:
            if sub.tag == "imgdir" and sub.attrib.get("name") == "effect":
                effect_node = sub
            elif sub.tag == "imgdir" and sub.attrib.get("name") == "info":
                info_node = sub
        if effect_node is None:
            continue
        summary = _canvas_summary(effect_node)
        origin_x, origin_y = _first_canvas_origin(effect_node)
        name = ""
        if info_node is not None:
            for field in info_node:
                if field.tag == "string" and field.attrib.get("name") == "name":
                    name = field.attrib.get("value", "")
                    break
        first_frame = png_root / item_id / "effect" / "0.png"
        rows.append({
            "id": item_id,
            "name": name,
            "frame_count": summary["frame_count"],
            "width": summary["w_max"],
            "height": summary["h_max"],
            "origin_x": origin_x,
            "origin_y": origin_y,
            "first_frame": str(first_frame) if first_frame.exists() else "",
        })
    return rows


def _first_canvas_origin(node: ET.Element) -> tuple[int, int]:
    for canvas in node:
        if canvas.tag != "canvas":
            continue
        for child in canvas:
            if child.tag == "vector" and child.attrib.get("name") == "origin":
                return int(child.attrib.get("x", 0)), int(child.attrib.get("y", 0))
    return 0, 0


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def write_index_md(summaries: dict[str, tuple[Path, int]]) -> None:
    lines = ["# WZ Asset Index", "",
             "Auto-generated by `build_wz_index.py`. Flat CSVs for uncatalogued",
             "Effect.wz effects and Install chairs, keyed to their source PNGs.",
             "Pair with the existing `Artifacts/catalogue/` (Character parts)",
             "and `analysis/catalogue_itemwz/` (Item catalogs).", ""]
    for label, (csv_path, row_count) in summaries.items():
        rel = csv_path.relative_to(OUT_ROOT.parent.parent)
        lines.append(f"- **{label}** — {row_count} entries — [`{rel}`]({rel.as_posix()})")
    (OUT_ROOT / "INDEX.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    summaries: dict[str, tuple[Path, int]] = {}

    for img_name in ("BasicEff.img", "CharacterEff.img", "ItemEff.img", "OnUserEff.img"):
        rows = index_effect_img(img_name)
        csv_path = OUT_ROOT / f"effects_{img_name.replace('.img', '')}.csv"
        write_csv(csv_path, rows)
        summaries[f"Effect.wz / {img_name}"] = (csv_path, len(rows))
        print(f"{img_name}: {len(rows)} entries")

    chair_rows = index_install_chairs()
    chairs_csv = OUT_ROOT / "install_chairs_0301.csv"
    write_csv(chairs_csv, chair_rows)
    summaries["Item.wz / Install / 0301.img (chairs)"] = (chairs_csv, len(chair_rows))
    print(f"chairs: {len(chair_rows)} entries")

    write_index_md(summaries)
    print(f"Wrote INDEX.md -> {OUT_ROOT / 'INDEX.md'}")


if __name__ == "__main__":
    main()
