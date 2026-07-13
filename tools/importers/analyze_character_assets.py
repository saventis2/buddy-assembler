#!/usr/bin/env python3
"""Extract structured character-system facts from an extracted MapleStory Base.wz tree."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, Iterable, Optional
import xml.etree.ElementTree as ET

from wz_shared import child_imgdir, utc_now_iso, write_csv


BASE_TEMPLATE_RE = re.compile(r"^\d{8}\.img\.xml$")


def read_scalar_map(imgdir: Optional[ET.Element]) -> Dict[str, str]:
    data: Dict[str, str] = {}
    if imgdir is None:
        return data
    for node in imgdir:
        if node.tag in {"string", "int", "short", "long"}:
            node_name = node.attrib.get("name")
            value = node.attrib.get("value")
            if node_name is not None and value is not None:
                data[node_name] = value
    return data


def canvas_map_anchors(canvas: ET.Element) -> Iterable[str]:
    map_node = child_imgdir(canvas, "map")
    if map_node is None:
        return []
    anchors = []
    for vec in map_node:
        if vec.tag == "vector":
            name = vec.attrib.get("name")
            if name:
                anchors.append(name)
    return anchors


def find_direct_string_value(parent: ET.Element, name: str) -> Optional[str]:
    for node in parent:
        if node.tag == "string" and node.attrib.get("name") == name:
            return node.attrib.get("value")
    return None


def parse_character_xml(xml_path: Path) -> dict:
    root = ET.parse(xml_path).getroot()

    top_actions = []
    info = child_imgdir(root, "info")
    info_data = read_scalar_map(info)
    islot = info_data.get("islot")
    vslot = info_data.get("vslot")
    cash = info_data.get("cash")

    z_layers = Counter()
    anchors = Counter()
    groups = Counter()
    delays = []
    uol_refs = []

    for child in root:
        if child.tag == "imgdir" and child.attrib.get("name") != "info":
            top_actions.append(child.attrib.get("name", ""))

    for node in root.iter():
        if node.tag == "canvas":
            z_value = find_direct_string_value(node, "z")
            if z_value:
                z_layers[z_value] += 1
            group_value = find_direct_string_value(node, "group")
            if group_value:
                groups[group_value] += 1
            for anchor in canvas_map_anchors(node):
                anchors[anchor] += 1
        elif node.tag == "int" and node.attrib.get("name") == "delay":
            raw = node.attrib.get("value")
            if raw is not None:
                try:
                    delays.append(int(raw))
                except ValueError:
                    pass
        elif node.tag == "uol":
            value = node.attrib.get("value")
            if value:
                uol_refs.append(value)

    return {
        "path": str(xml_path),
        "islot": islot,
        "vslot": vslot,
        "cash": cash,
        "top_actions": sorted({a for a in top_actions if a}),
        "z_layers": z_layers,
        "anchors": anchors,
        "groups": groups,
        "delay_values": delays,
        "uol_refs": uol_refs,
    }


def parse_make_char_info(make_char_xml: Path) -> dict:
    root = ET.parse(make_char_xml).getroot()
    result = {
        "info_profiles": defaultdict(lambda: defaultdict(dict)),
        "name_profiles": defaultdict(lambda: defaultdict(dict)),
    }

    info_node = child_imgdir(root, "Info")
    if info_node is not None:
        for profile in info_node:
            if profile.tag != "imgdir":
                continue
            profile_name = profile.attrib.get("name", "")
            for group in profile:
                if group.tag != "imgdir":
                    continue
                group_name = group.attrib.get("name", "")
                for val in group:
                    if val.tag == "int":
                        idx = val.attrib.get("name")
                        vv = val.attrib.get("value")
                        if idx is not None and vv is not None:
                            result["info_profiles"][profile_name][group_name][idx] = vv

    name_node = child_imgdir(root, "Name")
    if name_node is not None:
        for profile in name_node:
            if profile.tag != "imgdir":
                continue
            profile_name = profile.attrib.get("name", "")
            for group in profile:
                if group.tag != "imgdir":
                    continue
                group_name = group.attrib.get("name", "")
                for val in group:
                    if val.tag == "string":
                        key = val.attrib.get("name")
                        vv = val.attrib.get("value")
                        if key is not None and vv is not None:
                            result["name_profiles"][profile_name][group_name][key] = vv

    return result


def parse_eqp_names(eqp_xml: Path) -> dict:
    root = ET.parse(eqp_xml).getroot()
    eqp_outer = child_imgdir(root, "Eqp")
    if eqp_outer is None:
        return {"categories": {}, "total_named_entries": 0}

    categories = {}
    total_entries = 0
    for category in eqp_outer:
        if category.tag != "imgdir":
            continue
        category_name = category.attrib.get("name", "")
        count = 0
        for item in category:
            if item.tag != "imgdir":
                continue
            has_name = any(
                n.tag == "string" and n.attrib.get("name") == "name" for n in item
            )
            if has_name:
                count += 1
        categories[category_name] = count
        total_entries += count
    return {"categories": categories, "total_named_entries": total_entries}


def top_n(counter: Counter, n: int = 20) -> dict:
    return dict(counter.most_common(n))


def tokenize_vslot(vslot: str) -> list[str]:
    # Typical vslot values are packed uppercase groups, e.g. H1H2H3HfHsHb
    return re.findall(r"[A-Z][a-z]?\d*", vslot)


def analyze(base_wz: Path, output_dir: Path) -> dict:
    character_root = base_wz / "Character" / "Character.wz"
    etc_root = base_wz / "Etc" / "Etc.wz"
    string_root = base_wz / "String" / "String.wz"

    if not character_root.exists():
        raise FileNotFoundError(f"Character root not found: {character_root}")

    base_template_files = sorted(
        p for p in character_root.glob("*.img.xml") if BASE_TEMPLATE_RE.match(p.name)
    )
    category_dirs = sorted(p for p in character_root.iterdir() if p.is_dir())

    base_template_summaries = []
    all_actions = Counter()
    all_anchors = Counter()
    all_z_layers = Counter()
    all_groups = Counter()
    all_delays = []
    all_uol_count = 0

    for xml_path in base_template_files:
        parsed = parse_character_xml(xml_path)
        delays = parsed["delay_values"]
        all_delays.extend(delays)
        all_uol_count += len(parsed["uol_refs"])
        all_anchors.update(parsed["anchors"])
        all_z_layers.update(parsed["z_layers"])
        all_groups.update(parsed["groups"])
        for action in parsed["top_actions"]:
            all_actions[action] += 1

        base_template_summaries.append(
            {
                "template": xml_path.stem,
                "action_count": len(parsed["top_actions"]),
                "delay_entries": len(delays),
                "min_delay": min(delays) if delays else None,
                "max_delay": max(delays) if delays else None,
                "uol_refs": len(parsed["uol_refs"]),
            }
        )

    category_rows = []
    anchor_rows = []
    z_rows = []
    action_rows = []
    category_summary = {}

    for category in category_dirs:
        xml_files = sorted(category.glob("*.img.xml"))
        if not xml_files:
            continue

        islots = Counter()
        vslots = Counter()
        vslot_tokens = Counter()
        anchors = Counter()
        z_layers = Counter()
        groups = Counter()
        actions = Counter()
        delays = []
        uol_count = 0

        for xml_path in xml_files:
            parsed = parse_character_xml(xml_path)
            if parsed["islot"]:
                islots[parsed["islot"]] += 1
            if parsed["vslot"]:
                vslots[parsed["vslot"]] += 1
                for token in tokenize_vslot(parsed["vslot"]):
                    vslot_tokens[token] += 1
            anchors.update(parsed["anchors"])
            z_layers.update(parsed["z_layers"])
            groups.update(parsed["groups"])
            for action in parsed["top_actions"]:
                actions[action] += 1
            delays.extend(parsed["delay_values"])
            uol_count += len(parsed["uol_refs"])

        category_name = category.name
        category_summary[category_name] = {
            "xml_files": len(xml_files),
            "unique_islot": sorted(islots.keys()),
            "unique_vslot": sorted(vslots.keys()),
            "top_islot": top_n(islots, 10),
            "top_vslot": top_n(vslots, 10),
            "top_vslot_tokens": top_n(vslot_tokens, 20),
            "top_anchors": top_n(anchors, 20),
            "top_z_layers": top_n(z_layers, 30),
            "top_groups": top_n(groups, 20),
            "top_actions": top_n(actions, 30),
            "delay_stats": {
                "count": len(delays),
                "min": min(delays) if delays else None,
                "max": max(delays) if delays else None,
                "unique_values": sorted(set(delays))[:50],
            },
            "uol_refs": uol_count,
        }

        category_rows.append(
            {
                "category": category_name,
                "xml_files": len(xml_files),
                "unique_islot_count": len(islots),
                "unique_vslot_count": len(vslots),
                "unique_z_count": len(z_layers),
                "unique_anchor_count": len(anchors),
                "unique_action_count": len(actions),
                "delay_entries": len(delays),
                "uol_refs": uol_count,
            }
        )

        for anchor_name, cnt in anchors.most_common():
            anchor_rows.append(
                {"category": category_name, "anchor": anchor_name, "count": cnt}
            )
        for z_name, cnt in z_layers.most_common():
            z_rows.append({"category": category_name, "z_layer": z_name, "count": cnt})
        for action_name, cnt in actions.most_common():
            action_rows.append(
                {"category": category_name, "action": action_name, "count": cnt}
            )

    make_char_info_path = etc_root / "MakeCharInfo.img.xml"
    make_char_data = parse_make_char_info(make_char_info_path) if make_char_info_path.exists() else {}

    customization_rows = []
    if make_char_data:
        info_profiles = make_char_data["info_profiles"]
        name_profiles = make_char_data["name_profiles"]
        for profile_name, groups in info_profiles.items():
            for group_name, mapping in groups.items():
                labels = name_profiles.get(profile_name, {}).get(group_name, {})
                for idx, value in sorted(mapping.items(), key=lambda kv: int(kv[0])):
                    customization_rows.append(
                        {
                            "profile": profile_name,
                            "group": group_name,
                            "index": idx,
                            "value": value,
                            "label": labels.get(value, ""),
                        }
                    )

    eqp_path = string_root / "Eqp.img.xml"
    eqp_summary = parse_eqp_names(eqp_path) if eqp_path.exists() else {}

    summary = {
        "generated_at_utc": utc_now_iso(),
        "source_base_wz": str(base_wz),
        "character_root": str(character_root),
        "counts": {
            "base_templates": len(base_template_summaries),
            "character_categories_with_xml": len(category_summary),
            "total_actions_seen_in_templates": len(all_actions),
            "total_anchors_seen_in_templates": len(all_anchors),
            "total_z_layers_seen_in_templates": len(all_z_layers),
            "total_group_tags_seen_in_templates": len(all_groups),
            "total_delay_entries_in_templates": len(all_delays),
            "total_uol_refs_in_templates": all_uol_count,
        },
        "base_template_summary": base_template_summaries,
        "template_action_frequency": dict(sorted(all_actions.items(), key=lambda kv: kv[1], reverse=True)),
        "template_anchor_frequency": dict(sorted(all_anchors.items(), key=lambda kv: kv[1], reverse=True)),
        "template_z_frequency": dict(sorted(all_z_layers.items(), key=lambda kv: kv[1], reverse=True)),
        "template_group_frequency": dict(sorted(all_groups.items(), key=lambda kv: kv[1], reverse=True)),
        "category_summary": category_summary,
        "make_char_info": make_char_data,
        "eqp_name_summary": eqp_summary,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "character_reverse_engineering_summary.json").write_text(
        json.dumps(summary, indent=2),
        encoding="utf-8",
    )

    write_csv(
        output_dir / "character_categories.csv",
        sorted(category_rows, key=lambda r: r["category"]),
        [
            "category",
            "xml_files",
            "unique_islot_count",
            "unique_vslot_count",
            "unique_z_count",
            "unique_anchor_count",
            "unique_action_count",
            "delay_entries",
            "uol_refs",
        ],
    )

    write_csv(
        output_dir / "base_templates.csv",
        sorted(base_template_summaries, key=lambda r: r["template"]),
        ["template", "action_count", "delay_entries", "min_delay", "max_delay", "uol_refs"],
    )

    write_csv(
        output_dir / "anchor_frequency.csv",
        sorted(anchor_rows, key=lambda r: (r["category"], -r["count"], r["anchor"])),
        ["category", "anchor", "count"],
    )

    write_csv(
        output_dir / "z_layer_frequency.csv",
        sorted(z_rows, key=lambda r: (r["category"], -r["count"], r["z_layer"])),
        ["category", "z_layer", "count"],
    )

    write_csv(
        output_dir / "action_frequency.csv",
        sorted(action_rows, key=lambda r: (r["category"], -r["count"], r["action"])),
        ["category", "action", "count"],
    )

    write_csv(
        output_dir / "customization_presets.csv",
        sorted(
            customization_rows,
            key=lambda r: (
                r["profile"],
                int(r["group"]) if str(r["group"]).isdigit() else 9999,
                int(r["index"]) if str(r["index"]).isdigit() else 9999,
            ),
        ),
        ["profile", "group", "index", "value", "label"],
    )

    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-wz",
        default=r"C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz",
        help="Path to extracted Base.wz directory",
    )
    parser.add_argument(
        "--output",
        default="analysis/character_reverse_engineering",
        help="Directory for generated JSON/CSV outputs",
    )
    args = parser.parse_args()

    summary = analyze(Path(args.base_wz), Path(args.output))
    print(
        json.dumps(
            {
                "status": "ok",
                "output_dir": args.output,
                "base_templates": summary["counts"]["base_templates"],
                "categories_with_xml": summary["counts"]["character_categories_with_xml"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
