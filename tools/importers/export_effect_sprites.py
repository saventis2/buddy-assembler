"""Extract Effect.wz overlay sprites for the runtime.

Parses a single effect imgdir (e.g. BasicEff.img/LevelUp) into:
  <dst>/frames/NNN.png
  <dst>/effect.json   { "frames": [ {"origin_px": [x, y], "delay_ms": int} ], "loop": bool }

Effect.wz canvases are much simpler than Character.wz: each frame is a canvas
with an `origin` vector and (sometimes) a `delay` int. No skeleton / anchors.
Overlay anchoring at runtime: the canvas's `origin` is the foot-contact pivot
for floor-anchored effects (e.g. LevelUp). The renderer subtracts `origin`
from the draw top-left so the foot point lands at the actor's floor contact.
"""

from __future__ import annotations

import argparse
import json
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

DEFAULT_DELAY_MS = 90


def _find_imgdir(root: ET.Element, path: list[str]) -> ET.Element | None:
    node = root
    for segment in path:
        found = None
        for child in node:
            if child.tag == "imgdir" and child.attrib.get("name") == segment:
                found = child
                break
        if found is None:
            return None
        node = found
    return node


def extract_effect(
    effect_wz_root: Path,
    img_file: str,
    effect_path: list[str],
    dst_dir: Path,
    loop: bool = False,
) -> None:
    xml_path = effect_wz_root / f"{img_file}.xml"
    png_dir = effect_wz_root / img_file
    for sub in effect_path:
        png_dir = png_dir / sub

    if not xml_path.exists():
        raise FileNotFoundError(f"Effect XML not found: {xml_path}")
    if not png_dir.exists():
        raise FileNotFoundError(f"Effect PNG dir not found: {png_dir}")

    tree = ET.parse(xml_path)
    node = _find_imgdir(tree.getroot(), effect_path)
    if node is None:
        raise ValueError(f"imgdir path {effect_path} not found in {xml_path}")

    frames: list[dict] = []
    canvases = sorted(
        (c for c in node if c.tag == "canvas"),
        key=lambda c: int(c.attrib.get("name", "0")),
    )
    for canvas in canvases:
        name = canvas.attrib["name"]
        origin_x = 0
        origin_y = 0
        delay_ms = DEFAULT_DELAY_MS
        for child in canvas:
            if child.tag == "vector" and child.attrib.get("name") == "origin":
                origin_x = int(child.attrib.get("x", 0))
                origin_y = int(child.attrib.get("y", 0))
            elif child.tag == "int" and child.attrib.get("name") == "delay":
                delay_ms = int(child.attrib.get("value", DEFAULT_DELAY_MS))
        frames.append(
            {"name": name, "origin_px": [origin_x, origin_y], "delay_ms": delay_ms}
        )

    frames_out = dst_dir / "frames"
    frames_out.mkdir(parents=True, exist_ok=True)

    for idx, f in enumerate(frames):
        src_png = png_dir / f"{f['name']}.png"
        if not src_png.exists():
            raise FileNotFoundError(f"Missing frame PNG: {src_png}")
        shutil.copyfile(src_png, frames_out / f"{idx:03d}.png")

    manifest = {
        "source": f"{img_file}/" + "/".join(effect_path),
        "loop": loop,
        "frames": [
            {"origin_px": f["origin_px"], "delay_ms": f["delay_ms"]} for f in frames
        ],
    }
    (dst_dir / "effect.json").write_text(json.dumps(manifest, indent=2))
    print(f"Wrote {len(frames)} frames -> {dst_dir}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--effect-wz-root",
        default=r"C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz\Effect\Effect.wz",
    )
    parser.add_argument("--img", default="BasicEff.img")
    parser.add_argument("--path", nargs="+", required=True, help="imgdir path, e.g. LevelUp")
    parser.add_argument("--dst", required=True, type=Path)
    parser.add_argument("--loop", action="store_true")
    args = parser.parse_args()

    extract_effect(
        effect_wz_root=Path(args.effect_wz_root),
        img_file=args.img,
        effect_path=args.path,
        dst_dir=args.dst,
        loop=args.loop,
    )


if __name__ == "__main__":
    main()
