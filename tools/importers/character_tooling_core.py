#!/usr/bin/env python3
"""WZ-domain logic for the character tooling GUI, importable without tkinter.

Backlog #44 (gated on #46 / PR #51): the pure and WZ-domain methods of
``character_tooling_gui.App`` live here as module functions so they can be
imported and tested headlessly (the dev sandbox has no tkinter/display) and
reused by the future headless CLI (backlog #47). Every function body is a
direct lift of the corresponding ``App`` method -- behavior preservation is
the contract, same as PR #51. Where a method read tk variables or ``self``
caches, that read moved to the (still-GUI-side) caller and is now an explicit
parameter; nothing else changed.

Deliberately NOT unified with near-duplicates elsewhere (see PR #51's
non-goals): ``read_int_field`` keeps the GUI's missing-``value`` semantics
(returns ``default``, unlike audit_dataset_metadata's ``_read_info_int``),
and ``detect_action_timeline`` keeps the GUI's filesystem+body-template
algorithm (no info/link chasing, unlike export_runtime_character_sprites).

Pillow is imported lazily inside ``build_gif``, following wz_shared's
convention, so the XML/CSV-only helpers work without Pillow installed.
"""

from __future__ import annotations

import zlib
from pathlib import Path
from typing import Optional
import xml.etree.ElementTree as ET

from wz_shared import (
    child_imgdir,
    count_action_frames,
    detect_actions_in_asset_dir,
    read_info_strings,
)


CLASS_PRESET_DEFS = {
    "Custom": {
        "job_mask": 0,
        "preferred_types": [],
        "preferred_actions": [],
    },
    "Warrior": {
        "job_mask": 1,
        "preferred_types": [130, 131, 132, 140, 141, 142, 143, 144],
        "preferred_actions": ["swingOF", "swingO1", "stabOF", "stand1", "walk1"],
    },
    "Mage": {
        "job_mask": 2,
        "preferred_types": [137, 138],
        "preferred_actions": ["stabO1", "swingO1", "stand1", "walk1"],
    },
    "Bowman": {
        "job_mask": 4,
        "preferred_types": [145, 146],
        "preferred_actions": ["shoot1", "shootF", "stand1", "walk1"],
    },
    "Thief": {
        "job_mask": 8,
        "preferred_types": [133, 147],
        "preferred_actions": ["stabO1", "swingO1", "stand1", "walk1"],
    },
    "Pirate": {
        "job_mask": 16,
        "preferred_types": [148, 149],
        "preferred_actions": ["swingO1", "shoot1", "stand1", "walk1"],
    },
}


# --------------------------------------------------------------------------
# Small pure helpers
# --------------------------------------------------------------------------

def int_or_none(raw: str) -> Optional[int]:
    raw = raw.strip()
    if not raw:
        return None
    return int(raw)


def coerce_bool(raw: object) -> bool:
    if isinstance(raw, bool):
        return raw
    if isinstance(raw, (int, float)):
        return bool(raw)
    if isinstance(raw, str):
        return raw.strip().lower() in {"1", "true", "yes", "on"}
    return False


def format_count_map(data: Optional[dict]) -> str:
    if not data:
        return "(none)"
    parts = []
    for key in sorted(data.keys()):
        parts.append(f"{key}:{data[key]}")
    return ", ".join(parts)


def build_character_identifier(id_kwargs: dict) -> str:
    keys = [
        "base_id",
        "head_id",
        "face_id",
        "hair_id",
        "accessory_id",
        "cap_id",
        "coat_id",
        "longcoat_id",
        "pants_id",
        "shoes_id",
        "glove_id",
        "cape_id",
        "shield_id",
        "weapon_id",
    ]
    payload = "|".join("" if id_kwargs.get(k) is None else str(id_kwargs.get(k)) for k in keys)
    return f"{zlib.crc32(payload.encode('utf-8')) & 0xFFFFFFFF:010d}"


# --------------------------------------------------------------------------
# Base.wz validation + name/metadata lookups
# --------------------------------------------------------------------------

def validate_base_wz(base_wz: Path) -> Optional[str]:
    if not base_wz.exists():
        return f"Base.wz path does not exist: {base_wz}"
    marker = base_wz / "Character" / "Character.wz"
    if not marker.exists():
        return f"Missing Character tree: {marker}"
    return None


def base_template_xml(base_wz: Path, base_id: int) -> Path:
    char_root = base_wz / "Character" / "Character.wz"
    return char_root / f"{base_id:08d}.img.xml"


def load_eqp_name_index(base_wz: Path) -> dict[int, dict]:
    """Parse String.wz Eqp name table. Uncached; the GUI caches per path."""
    eqp_xml = base_wz / "String" / "String.wz" / "Eqp.img.xml"
    if not eqp_xml.exists():
        return {}

    root = ET.parse(eqp_xml).getroot()
    eqp_outer = child_imgdir(root, "Eqp")
    idx: dict[int, dict] = {}
    if eqp_outer is not None:
        for category_node in eqp_outer:
            if category_node.tag != "imgdir":
                continue
            category = category_node.attrib.get("name", "")
            for item_node in category_node:
                if item_node.tag != "imgdir":
                    continue
                raw_id = item_node.attrib.get("name", "")
                if not raw_id.isdigit():
                    continue
                item_id = int(raw_id)
                item_name = ""
                for child in item_node:
                    if child.tag == "string" and child.attrib.get("name") == "name":
                        item_name = child.attrib.get("value", "")
                        break
                if item_name:
                    idx[item_id] = {"category": category, "name": item_name}

    return idx


def read_int_field(parent: ET.Element, name: str, default: int = 0) -> int:
    """GUI semantics on a missing ``value`` attribute: return ``default``.

    Near-duplicate of audit_dataset_metadata's ``_read_info_int`` which is
    deliberately NOT unified (PR #51 non-goal): that one returns 0 via its
    ``"0"`` fallback even when ``default != 0``.
    """
    for child in parent:
        if child.tag == "int" and child.attrib.get("name") == name:
            raw = child.attrib.get("value", "")
            try:
                return int(raw)
            except Exception:  # noqa: BLE001
                return default
    return default


def load_weapon_meta_index(base_wz: Path, eqp_names: dict[int, dict]) -> dict[int, dict]:
    """Parse per-weapon reqJob/reqLevel/... + action list. Uncached."""
    weapon_dir = base_wz / "Character" / "Character.wz" / "Weapon"
    out: dict[int, dict] = {}
    if weapon_dir.exists():
        for xml_path in weapon_dir.glob("*.img.xml"):
            raw_id = xml_path.name.replace(".img.xml", "")
            if not raw_id.isdigit():
                continue
            item_id = int(raw_id)
            info_node: Optional[ET.Element] = None
            try:
                root = ET.parse(xml_path).getroot()
            except Exception:  # noqa: BLE001
                continue
            for child in root:
                if child.tag == "imgdir" and child.attrib.get("name") == "info":
                    info_node = child
                    break
            if info_node is None:
                continue

            actions = []
            for child in root:
                if child.tag != "imgdir":
                    continue
                name = child.attrib.get("name", "")
                if not name or name == "info":
                    continue
                has_numeric_frame = False
                for frame_node in child:
                    if frame_node.tag == "imgdir" and frame_node.attrib.get("name", "").isdigit():
                        has_numeric_frame = True
                        break
                if has_numeric_frame:
                    actions.append(name)
            actions = sorted(set(actions))
            out[item_id] = {
                "item_id": item_id,
                "weapon_type": item_id // 10000,
                "name": (eqp_names.get(item_id) or {}).get("name", ""),
                "req_job": read_int_field(info_node, "reqJob", default=0),
                "req_level": read_int_field(info_node, "reqLevel", default=0),
                "req_str": read_int_field(info_node, "reqSTR", default=0),
                "req_dex": read_int_field(info_node, "reqDEX", default=0),
                "req_int": read_int_field(info_node, "reqINT", default=0),
                "req_luk": read_int_field(info_node, "reqLUK", default=0),
                "actions": actions,
            }

    return out


def pick_weapon_for_class(
    class_name: str,
    *,
    body_actions: set[str],
    weapons: dict[int, dict],
) -> Optional[dict]:
    preset = CLASS_PRESET_DEFS.get(class_name)
    if not preset or class_name == "Custom":
        return None

    job_mask = int(preset.get("job_mask", 0) or 0)
    preferred_types = set(int(x) for x in preset.get("preferred_types", []))
    preferred_actions = [str(x) for x in preset.get("preferred_actions", [])]
    candidates = []
    for meta in weapons.values():
        actions = set(meta.get("actions") or [])
        if not actions:
            continue
        req_job = int(meta.get("req_job", 0) or 0)
        if req_job != 0 and job_mask != 0 and (req_job & job_mask) == 0:
            continue
        common_actions = actions & body_actions if body_actions else actions
        if not common_actions:
            continue

        action_rank = 1
        chosen_action = ""
        for idx, a in enumerate(preferred_actions):
            if a in common_actions:
                action_rank = 0
                chosen_action = a
                break
        if not chosen_action:
            chosen_action = sorted(common_actions)[0]

        type_rank = 0 if int(meta.get("weapon_type", 0)) in preferred_types else 1
        req_level = int(meta.get("req_level", 0) or 0)
        req_job_rank = 0 if req_job != 0 else 1
        candidates.append(
            (
                req_job_rank,
                type_rank,
                action_rank,
                req_level,
                int(meta.get("item_id", 0)),
                chosen_action,
                meta,
            )
        )

    if not candidates:
        return None
    candidates.sort()
    picked = dict(candidates[0][6])
    picked["suggested_action"] = candidates[0][5]
    return picked


def get_body_id_pools(base_wz: Path) -> dict[str, list[int]]:
    """Scan Character.wz for base-body/head template ids. Uncached."""
    pools: dict[str, list[int]] = {"base_id": [], "head_id": []}
    char_root = base_wz / "Character" / "Character.wz"
    if char_root.exists():
        for xml_path in char_root.glob("*.img.xml"):
            raw = xml_path.name.replace(".img.xml", "")
            if not raw.isdigit():
                continue
            item_id = int(raw)
            if 2000 <= item_id < 10000:
                pools["base_id"].append(item_id)
            elif 10000 <= item_id < 20000:
                pools["head_id"].append(item_id)

    pools["base_id"] = sorted(set(pools["base_id"]))
    pools["head_id"] = sorted(set(pools["head_id"]))
    return pools


# --------------------------------------------------------------------------
# Action / frame / timeline detection
# --------------------------------------------------------------------------

def detect_actions(base_wz: Path, base_id: int) -> list[str]:
    body_dir = base_wz / "Character" / "Character.wz" / f"{base_id:08d}.img"
    return sorted(detect_actions_in_asset_dir(body_dir))


def weapon_action_profile(base_wz: Path, weapon_id: int) -> dict:
    char_root = base_wz / "Character" / "Character.wz"
    weapon_dir = char_root / "Weapon" / f"{int(weapon_id):08d}.img"
    weapon_xml = char_root / "Weapon" / f"{int(weapon_id):08d}.img.xml"

    actions = sorted(detect_actions_in_asset_dir(weapon_dir))
    frame_counts = count_action_frames(weapon_dir, actions)
    info_strings = read_info_strings(weapon_xml)

    return {
        "weapon_id": int(weapon_id),
        "weapon_type_code": int(weapon_id) // 10000,
        "weapon_dir": str(weapon_dir),
        "weapon_xml": str(weapon_xml),
        "supported_actions": actions,
        "frame_counts": frame_counts,
        "info": info_strings,
    }


def detect_actions_for_loadout(base_wz: Path, id_kwargs: dict, mode: str) -> list[str]:
    base_id = int(id_kwargs.get("base_id"))
    char_root = base_wz / "Character" / "Character.wz"
    body_dir = char_root / f"{base_id:08d}.img"
    body_actions = detect_actions_in_asset_dir(body_dir)
    if mode == "body-only":
        return sorted(body_actions)
    include_weapon_actions = mode == "loadout-intersection-with-weapon"

    # Normalize incompatible armor combo the same way as the renderer.
    coat_id = id_kwargs.get("coat_id")
    longcoat_id = id_kwargs.get("longcoat_id")
    pants_id = id_kwargs.get("pants_id")
    if longcoat_id is not None:
        coat_id = None
        pants_id = None

    core_asset_dirs: list[Path] = []
    head_id = id_kwargs.get("head_id")
    if head_id is not None:
        core_asset_dirs.append(char_root / f"{int(head_id):08d}.img")
    hair_id = id_kwargs.get("hair_id")
    if hair_id is not None:
        core_asset_dirs.append(char_root / "Hair" / f"{int(hair_id):08d}.img")
    if coat_id is not None:
        core_asset_dirs.append(char_root / "Coat" / f"{int(coat_id):08d}.img")
    if longcoat_id is not None:
        core_asset_dirs.append(char_root / "Longcoat" / f"{int(longcoat_id):08d}.img")
    if pants_id is not None:
        core_asset_dirs.append(char_root / "Pants" / f"{int(pants_id):08d}.img")
    shoes_id = id_kwargs.get("shoes_id")
    if shoes_id is not None:
        core_asset_dirs.append(char_root / "Shoes" / f"{int(shoes_id):08d}.img")
    if include_weapon_actions:
        weapon_id = id_kwargs.get("weapon_id")
        if weapon_id is not None:
            core_asset_dirs.append(char_root / "Weapon" / f"{int(weapon_id):08d}.img")

    compatible = set(body_actions)
    for asset_dir in core_asset_dirs:
        aset = detect_actions_in_asset_dir(asset_dir)
        if aset:
            compatible &= aset

    if not compatible:
        if include_weapon_actions:
            # Strict mode: empty means no safe action intersection for this
            # full loadout, including weapon compatibility.
            return []
        # Safety fallback to base template actions if non-weapon
        # intersection is empty.
        return sorted(body_actions)
    return sorted(compatible)


def detect_action_frames(base_wz: Path, base_id: int, action: str) -> list[int]:
    body_dir = base_wz / "Character" / "Character.wz" / f"{base_id:08d}.img"
    action_dir = body_dir / action
    if not action_dir.exists() or not action_dir.is_dir():
        return []
    if action_dir.exists() and action_dir.is_dir():
        fs_frames = []
        for child in action_dir.iterdir():
            if not child.is_dir():
                continue
            name = child.name
            if not name.isdigit():
                continue
            if any(child.glob("*.png")):
                fs_frames.append(int(name))
        if fs_frames:
            return sorted(set(fs_frames))

    xml_path = base_template_xml(base_wz, base_id)
    if not xml_path.exists():
        return []
    root = ET.parse(xml_path).getroot()
    action_node = None
    for child in root:
        if child.tag == "imgdir" and child.attrib.get("name") == action:
            action_node = child
            break
    if action_node is None:
        return []
    frames = []
    for child in action_node:
        if child.tag == "imgdir":
            n = child.attrib.get("name", "")
            if n.isdigit():
                frames.append(int(n))
    if not frames:
        return [0]
    return sorted(set(frames))


def detect_action_timeline(
    base_wz: Path,
    base_id: int,
    action: str,
    *,
    default_delay_ms: int,
) -> list[dict]:
    """GUI timeline algorithm: filesystem frame detection + body-template
    delay map. Deliberately NOT unified with export_runtime_character_sprites'
    same-named method (info/link chain + max_frames cap) -- PR #51 non-goal.
    """
    frames = detect_action_frames(base_wz, base_id, action)
    if not frames:
        return []

    delay_map: dict[int, int] = {}
    xml_path = base_template_xml(base_wz, base_id)
    if xml_path.exists():
        try:
            root = ET.parse(xml_path).getroot()
            action_node = None
            for child in root:
                if child.tag == "imgdir" and child.attrib.get("name") == action:
                    action_node = child
                    break
            if action_node is not None:
                for frame_node in action_node:
                    if frame_node.tag != "imgdir":
                        continue
                    n = frame_node.attrib.get("name", "")
                    if not n.isdigit():
                        continue
                    frame_i = int(n)
                    delay_i = None
                    for m in frame_node:
                        if m.tag == "int" and m.attrib.get("name") == "delay":
                            raw = m.attrib.get("value")
                            if raw is not None:
                                try:
                                    delay_i = int(raw)
                                except ValueError:
                                    delay_i = None
                            break
                    if delay_i is not None:
                        delay_map[frame_i] = max(1, delay_i)
        except Exception:
            delay_map = {}

    safe_default = max(1, int(default_delay_ms))
    return [{"frame": f, "delay_ms": delay_map.get(f, safe_default)} for f in frames]


# --------------------------------------------------------------------------
# GIF building (Pillow imported lazily -- see module docstring)
# --------------------------------------------------------------------------

def build_gif(
    frame_paths: list[Path],
    output_path: Path,
    duration_ms: int,
    durations_ms: Optional[list[int]] = None,
    bg_rgb: tuple[int, int, int] = (0, 0, 0),
) -> dict:
    from PIL import Image

    imgs = [Image.open(p).convert("RGBA") for p in frame_paths]
    try:
        max_w = max(im.width for im in imgs)
        max_h = max(im.height for im in imgs)
        normalized = []
        for im in imgs:
            if im.width == max_w and im.height == max_h:
                normalized.append(im.copy())
            else:
                canvas = Image.new("RGBA", (max_w, max_h), (0, 0, 0, 0))
                ox = (max_w - im.width) // 2
                oy = (max_h - im.height) // 2
                canvas.alpha_composite(im, (ox, oy))
                normalized.append(canvas)

        # Flatten to opaque RGB to avoid viewer-dependent transparency/disposal ghosting.
        flattened = []
        for im in normalized:
            bg = Image.new("RGBA", (max_w, max_h), (bg_rgb[0], bg_rgb[1], bg_rgb[2], 255))
            bg.alpha_composite(im)
            flattened.append(bg.convert("RGB"))

        master_palette = flattened[0].quantize(colors=256, method=Image.Quantize.MEDIANCUT)
        paletted = [fr.quantize(palette=master_palette, dither=Image.Dither.FLOYDSTEINBERG) for fr in flattened]

        output_path.parent.mkdir(parents=True, exist_ok=True)
        if durations_ms and len(durations_ms) == len(paletted):
            gif_duration: int | list[int] = [max(1, int(d)) for d in durations_ms]
        else:
            gif_duration = duration_ms
        paletted[0].save(
            output_path,
            save_all=True,
            append_images=paletted[1:],
            duration=gif_duration,
            loop=0,
            optimize=False,
            disposal=2,
        )
        if not output_path.exists() or output_path.stat().st_size <= 0:
            raise RuntimeError(f"GIF was not written correctly: {output_path}")
        return {
            "gif_path": str(output_path),
            "size": [max_w, max_h],
            "frame_count": len(paletted),
            "duration_ms": duration_ms,
            "durations_ms": [max(1, int(d)) for d in durations_ms] if durations_ms else None,
            "total_duration_ms": (
                sum(max(1, int(d)) for d in durations_ms)
                if durations_ms
                else int(duration_ms) * len(paletted)
            ),
            "bytes": int(output_path.stat().st_size),
            "mode": "opaque_flattened",
            "bg_rgb": [bg_rgb[0], bg_rgb[1], bg_rgb[2]],
        }
    finally:
        for im in imgs:
            im.close()
        for im in locals().get("normalized", []):
            im.close()
        for im in locals().get("flattened", []):
            im.close()
        for im in locals().get("paletted", []):
            im.close()


# --------------------------------------------------------------------------
# Catalogue helpers
# --------------------------------------------------------------------------

def normalize_catalogue_rows(raw_rows: list[dict], *, itemwz_mode: bool) -> list[dict]:
    if not itemwz_mode:
        return raw_rows

    normalized: list[dict] = []
    for row in raw_rows:
        out = dict(row)
        out["part_category"] = str(row.get("item_root", ""))
        out["eqp_category"] = str(row.get("group_file", ""))
        out["islot"] = str(row.get("slot_max", ""))
        out["vslot"] = str(row.get("price", ""))
        normalized.append(out)
    return normalized


def infer_slot_from_catalogue_categories(
    part_category: str,
    eqp_category: str,
) -> Optional[str]:
    aliases = {
        "face": "face_id",
        "hair": "hair_id",
        "accessory": "accessory_id",
        "cap": "cap_id",
        "coat": "coat_id",
        "longcoat": "longcoat_id",
        "pants": "pants_id",
        "shoes": "shoes_id",
        "glove": "glove_id",
        "cape": "cape_id",
        "shield": "shield_id",
        "weapon": "weapon_id",
    }
    for raw in (part_category, eqp_category):
        key = (raw or "").strip().lower().replace("_", "").replace(" ", "")
        if key in aliases:
            return aliases[key]
    return None


def resolve_catalogue_icon_path(base_wz: Path, item: dict) -> Optional[Path]:
    if not base_wz.exists():
        return None

    candidate_paths: list[Path] = []

    png_dir_relpath = str(item.get("png_dir_relpath", "")).strip()
    if png_dir_relpath:
        png_dir = base_wz / Path(png_dir_relpath)
        candidate_paths.append(png_dir / "info" / "icon.png")
        candidate_paths.append(png_dir / "info" / "iconRaw.png")

    xml_relpath = str(item.get("xml_relpath", "")).strip()
    if xml_relpath:
        xml_path = base_wz / Path(xml_relpath)
        item_dir = xml_path.with_suffix("")
        candidate_paths.append(item_dir / "info" / "icon.png")
        candidate_paths.append(item_dir / "info" / "iconRaw.png")

    item_id = str(item.get("id", "")).strip()
    part_category = str(item.get("part_category", "")).strip()
    if item_id.isdigit() and part_category:
        padded = f"{int(item_id):08d}.img"
        guessed = base_wz / "Character" / "Character.wz" / part_category / padded / "info"
        candidate_paths.append(guessed / "icon.png")
        candidate_paths.append(guessed / "iconRaw.png")

    seen: set[str] = set()
    for path in candidate_paths:
        key = str(path).lower()
        if key in seen:
            continue
        seen.add(key)
        if path.exists() and path.is_file():
            return path
    return None
