#!/usr/bin/env python3
"""Diff two extracted MapleStory Character.wz trees with change classification."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, Optional, Tuple
import xml.etree.ElementTree as ET


def sha1_file(path: Path) -> str:
    h = hashlib.sha1()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def node_children_with_names(node: ET.Element) -> Iterable[Tuple[str, ET.Element]]:
    for child in node:
        name = child.attrib.get("name")
        if name:
            yield name, child


@dataclass
class XmlFeatures:
    islot: Optional[str]
    vslot: Optional[str]
    actions: set[str]
    delays: Dict[str, str]
    z_values: Dict[str, str]
    origins: Dict[str, Tuple[str, str]]
    anchors: Dict[str, Tuple[str, str]]
    uol_values: Dict[str, str]


def extract_xml_features(xml_path: Path) -> XmlFeatures:
    root = ET.parse(xml_path).getroot()
    info = None
    for child in root:
        if child.tag == "imgdir" and child.attrib.get("name") == "info":
            info = child
            break

    islot = None
    vslot = None
    if info is not None:
        for node in info:
            if node.tag == "string" and node.attrib.get("name") == "islot":
                islot = node.attrib.get("value")
            if node.tag == "string" and node.attrib.get("name") == "vslot":
                vslot = node.attrib.get("value")

    actions = set()
    for child in root:
        if child.tag == "imgdir":
            name = child.attrib.get("name")
            if name and name != "info":
                actions.add(name)

    delays: Dict[str, str] = {}
    z_values: Dict[str, str] = {}
    origins: Dict[str, Tuple[str, str]] = {}
    anchors: Dict[str, Tuple[str, str]] = {}
    uol_values: Dict[str, str] = {}

    def walk(node: ET.Element, path: Tuple[str, ...]) -> None:
        for name, child in node_children_with_names(node):
            child_path = path + (name,)
            p = "/".join(child_path)

            if child.tag == "int" and child.attrib.get("name") == "delay":
                val = child.attrib.get("value")
                if val is not None:
                    delays[p] = val

            elif child.tag == "string" and child.attrib.get("name") == "z":
                val = child.attrib.get("value")
                if val is not None:
                    z_values[p] = val

            elif child.tag == "vector" and child.attrib.get("name") == "origin":
                x = child.attrib.get("x", "0")
                y = child.attrib.get("y", "0")
                origins[p] = (x, y)

            elif child.tag == "uol":
                val = child.attrib.get("value")
                if val is not None:
                    uol_values[p] = val

            # map anchors under ".../map/<anchor>"
            if child.tag == "vector" and len(path) >= 1 and path[-1] == "map":
                x = child.attrib.get("x", "0")
                y = child.attrib.get("y", "0")
                anchors[p] = (x, y)

            walk(child, child_path)

    walk(root, (root.attrib.get("name", xml_path.stem),))
    return XmlFeatures(
        islot=islot,
        vslot=vslot,
        actions=actions,
        delays=delays,
        z_values=z_values,
        origins=origins,
        anchors=anchors,
        uol_values=uol_values,
    )


def impact_from_flags(flags: set[str]) -> str:
    if "compatibility" in flags or "composition" in flags:
        return "breaking_visual_alignment"
    if "structural" in flags or "timing" in flags:
        return "behavioral_animation_change"
    if "art" in flags:
        return "cosmetic"
    return "none"


def write_csv(path: Path, rows: list[dict], headers: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def diff_character_trees(
    old_base_wz: Path,
    new_base_wz: Path,
    output_dir: Path,
    xml_compare: str = "size",
    png_compare: str = "size",
    include_unchanged: bool = False,
    skip_png: bool = False,
) -> dict:
    old_char = old_base_wz / "Character" / "Character.wz"
    new_char = new_base_wz / "Character" / "Character.wz"
    if not old_char.exists():
        raise FileNotFoundError(f"Old Character.wz not found: {old_char}")
    if not new_char.exists():
        raise FileNotFoundError(f"New Character.wz not found: {new_char}")

    same_tree = old_base_wz.resolve() == new_base_wz.resolve()
    if same_tree:
        output_dir.mkdir(parents=True, exist_ok=True)
        write_csv(
            output_dir / "character_xml_diff.csv",
            [],
            ["path", "change_type", "classifications", "impact", "details"],
        )
        write_csv(
            output_dir / "character_png_diff.csv",
            [],
            ["path", "change_type"],
        )
        summary = {
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "old_base_wz": str(old_base_wz),
            "new_base_wz": str(new_base_wz),
            "counts": {
                "xml_total_old": 0,
                "xml_total_new": 0,
                "xml_changed": 0,
                "png_total_old": 0,
                "png_total_new": 0,
                "png_changed": 0,
            },
            "xml_classification_counts": {},
            "xml_impact_counts": {},
            "png_change_counts": {},
            "png_scan_mode": "identity-shortcut",
        }
        (output_dir / "character_diff_summary.json").write_text(
            json.dumps(summary, indent=2),
            encoding="utf-8",
        )
        return summary

    old_xml = {p.relative_to(old_char).as_posix(): p for p in old_char.rglob("*.img.xml")}
    new_xml = {p.relative_to(new_char).as_posix(): p for p in new_char.rglob("*.img.xml")}
    old_png: Dict[str, Path] = {}
    new_png: Dict[str, Path] = {}
    if not skip_png:
        old_png = {p.relative_to(old_char).as_posix(): p for p in old_char.rglob("*.png")}
        new_png = {p.relative_to(new_char).as_posix(): p for p in new_char.rglob("*.png")}

    xml_rows = []
    xml_flag_counts = Counter()
    xml_impact_counts = Counter()

    all_xml_keys = sorted(set(old_xml.keys()) | set(new_xml.keys()))
    for key in all_xml_keys:
        old_path = old_xml.get(key)
        new_path = new_xml.get(key)
        flags: set[str] = set()
        detail = []
        change_type = "unchanged"

        if old_path is None:
            flags.add("structural")
            change_type = "added"
            detail.append("file_added")
        elif new_path is None:
            flags.add("structural")
            change_type = "removed"
            detail.append("file_removed")
        else:
            old_size = old_path.stat().st_size
            new_size = new_path.stat().st_size
            maybe_same = old_size == new_size
            if xml_compare == "hash" and maybe_same:
                maybe_same = sha1_file(old_path) == sha1_file(new_path)

            if not maybe_same:
                old_f = extract_xml_features(old_path)
                new_f = extract_xml_features(new_path)

                if old_f.actions != new_f.actions:
                    flags.add("structural")
                    detail.append("actions_changed")
                if old_f.uol_values != new_f.uol_values:
                    flags.add("structural")
                    detail.append("uol_refs_changed")
                if old_f.delays != new_f.delays:
                    flags.add("timing")
                    detail.append("delays_changed")
                if (
                    old_f.z_values != new_f.z_values
                    or old_f.origins != new_f.origins
                    or old_f.anchors != new_f.anchors
                ):
                    flags.add("composition")
                    detail.append("z_origin_anchor_changed")
                if old_f.islot != new_f.islot or old_f.vslot != new_f.vslot:
                    flags.add("compatibility")
                    detail.append("islot_vslot_changed")

                if flags:
                    change_type = "modified"

        impact = impact_from_flags(flags)
        if flags:
            for f in flags:
                xml_flag_counts[f] += 1
            xml_impact_counts[impact] += 1

        if include_unchanged or change_type != "unchanged":
            xml_rows.append(
                {
                    "path": key,
                    "change_type": change_type,
                    "classifications": ",".join(sorted(flags)),
                    "impact": impact,
                    "details": ",".join(detail),
                }
            )

    png_rows = []
    png_change_counts = Counter()
    if not skip_png:
        all_png_keys = sorted(set(old_png.keys()) | set(new_png.keys()))
        for key in all_png_keys:
            old_path = old_png.get(key)
            new_path = new_png.get(key)
            if old_path is None:
                ct = "added"
            elif new_path is None:
                ct = "removed"
            else:
                old_size = old_path.stat().st_size
                new_size = new_path.stat().st_size
                if old_size != new_size:
                    ct = "modified"
                elif png_compare == "hash":
                    old_sig = sha1_file(old_path)
                    new_sig = sha1_file(new_path)
                    ct = "unchanged" if old_sig == new_sig else "modified"
                else:
                    ct = "unchanged"
            if include_unchanged or ct != "unchanged":
                png_rows.append({"path": key, "change_type": ct})
            png_change_counts[ct] += 1

    # Any changed PNG is an art change.
    art_changed_png = png_change_counts["added"] + png_change_counts["removed"] + png_change_counts["modified"]

    summary = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "old_base_wz": str(old_base_wz),
        "new_base_wz": str(new_base_wz),
        "counts": {
            "xml_total_old": len(old_xml),
            "xml_total_new": len(new_xml),
            "xml_changed": sum(
                1 for r in xml_rows if r["change_type"] in ("added", "removed", "modified")
            ),
            "png_total_old": len(old_png) if not skip_png else 0,
            "png_total_new": len(new_png) if not skip_png else 0,
            "png_changed": int(art_changed_png),
        },
        "xml_classification_counts": dict(xml_flag_counts),
        "xml_impact_counts": dict(xml_impact_counts),
        "png_change_counts": dict(png_change_counts),
        "png_scan_mode": "skipped" if skip_png else png_compare,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "character_diff_summary.json").write_text(
        json.dumps(summary, indent=2),
        encoding="utf-8",
    )

    write_csv(
        output_dir / "character_xml_diff.csv",
        xml_rows,
        ["path", "change_type", "classifications", "impact", "details"],
    )
    write_csv(
        output_dir / "character_png_diff.csv",
        png_rows,
        ["path", "change_type"],
    )

    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old-base-wz", required=True, help="Old extracted Base.wz path")
    parser.add_argument("--new-base-wz", required=True, help="New extracted Base.wz path")
    parser.add_argument("--output-dir", required=True, help="Output directory for diff artifacts")
    parser.add_argument(
        "--xml-compare",
        choices=["size", "hash"],
        default="size",
        help="XML pre-check mode before deep classification: size (fast) or hash (accurate, slower)",
    )
    parser.add_argument(
        "--png-compare",
        choices=["size", "hash"],
        default="size",
        help="PNG diff mode: size (fast) or hash (accurate, slow)",
    )
    parser.add_argument(
        "--include-unchanged",
        action="store_true",
        help="Include unchanged files in CSV outputs (can be very large/slower)",
    )
    parser.add_argument(
        "--skip-png",
        action="store_true",
        help="Skip PNG diff scan (fast, XML-only classification)",
    )
    args = parser.parse_args()

    summary = diff_character_trees(
        old_base_wz=Path(args.old_base_wz),
        new_base_wz=Path(args.new_base_wz),
        output_dir=Path(args.output_dir),
        xml_compare=args.xml_compare,
        png_compare=args.png_compare,
        include_unchanged=args.include_unchanged,
        skip_png=args.skip_png,
    )
    print(
        json.dumps(
            {
                "status": "ok",
                "xml_changed": summary["counts"]["xml_changed"],
                "png_changed": summary["counts"]["png_changed"],
                "output_dir": args.output_dir,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
