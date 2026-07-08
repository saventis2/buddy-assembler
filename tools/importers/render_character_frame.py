#!/usr/bin/env python3
"""Prototype renderer for a single MapleStory character frame from extracted Base.wz assets."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple
import xml.etree.ElementTree as ET

from PIL import Image


ANCHOR_PRIORITY = [
    "navel",
    "neck",
    "brow",
    "hand",
    "handMove",
    "earOverHead",
    "earBelowHead",
    "muzzle",
]

WEAPON_ANCHOR_PRIORITY = [
    "hand",
    "handMove",
    "navel",
    "neck",
    "brow",
    "earOverHead",
    "earBelowHead",
    "muzzle",
]

WEAPON_HAND_PROXY_PREFIXES = ("swing", "stab", "proneStab")
MELEE_WEAPON_TYPE_CODES = {
    130,
    131,
    132,
    133,
    134,
    140,
    141,
    142,
    148,
}
RANGED_WEAPON_TYPE_CODES = {
    145,
    146,
    147,
    149,
}
STRICT_METADATA_ALIGNMENT = True
ANCHOR_PROVIDER_KINDS = {"body", "head"}
SKILL_BRANCH_PRIORITY = ("effect", "effect0", "effect1", "hit", "ball", "prepare", "summon", "affected")

HAIR_MASK_SLOTS = {"H1", "H2", "H3", "H4", "H5", "H6", "Hf", "Hs", "Hb"}
FRONT_HAIR_Z_TAGS = {"hair", "hairOverHead", "hairShade", "hairBelowBody"}
BACK_HAIR_Z_TAGS = {
    "backHair",
    "backHairBelowCap",
    "backHairBelowCapWide",
    "backHairBelowCapNarrow",
    "backHairOverCape",
}
CAP_OVERHAIR_Z_TAGS = {"capOverHair", "backCapOverHair"}
VSLOT_TOKEN_RE = re.compile(r"[A-Z](?:[a-z]|[0-9])?")


@dataclass
class DrawEntry:
    asset_kind: str
    part_id: int
    node_path: Tuple[str, ...]
    png_path: Path
    z: str
    origin: Tuple[int, int]
    anchors: Dict[str, Tuple[int, int]]


@dataclass
class PlacedEntry:
    draw: DrawEntry
    top_left: Tuple[int, int]
    used_anchor: str
    z_index: int


class Asset:
    def __init__(self, kind: str, part_id: int, xml_path: Path):
        self.kind = kind
        self.part_id = part_id
        self.xml_path = xml_path
        self.img_dir = xml_path.with_suffix("")  # strip .xml => *.img directory
        self.root = ET.parse(xml_path).getroot()
        self.root_name = self.root.attrib.get("name", xml_path.stem)
        self.index: Dict[Tuple[str, ...], ET.Element] = {}
        self.last_selection: Dict[str, object] = {}
        self._index_tree(self.root, (self.root_name,))

    def _index_tree(self, node: ET.Element, path: Tuple[str, ...]) -> None:
        self.index[path] = node
        for child in node:
            name = child.attrib.get("name")
            if name:
                self._index_tree(child, path + (name,))

    def _child_imgdir(self, node: ET.Element, name: str) -> Optional[ET.Element]:
        for child in node:
            if child.tag == "imgdir" and child.attrib.get("name") == name:
                return child
        return None

    def _first_frame_node(self, action_node: ET.Element) -> ET.Element:
        frames = [c for c in action_node if c.tag == "imgdir"]
        if not frames:
            return action_node
        numeric = []
        for fr in frames:
            n = fr.attrib.get("name", "")
            if n.isdigit():
                numeric.append((int(n), fr))
        if numeric:
            numeric.sort(key=lambda x: x[0])
            return numeric[0][1]
        return frames[0]

    def _closest_frame_node(
        self,
        action_node: ET.Element,
        requested_frame: int,
    ) -> tuple[ET.Element, object]:
        frames = [c for c in action_node if c.tag == "imgdir"]
        if not frames:
            return action_node, None

        numeric: list[tuple[int, ET.Element]] = []
        for fr in frames:
            n = fr.attrib.get("name", "")
            if n.isdigit():
                numeric.append((int(n), fr))
        if numeric:
            numeric.sort(key=lambda x: (abs(x[0] - requested_frame), x[0]))
            picked, node = numeric[0]
            return node, picked

        first = frames[0]
        name = first.attrib.get("name", "")
        picked: object = int(name) if name.isdigit() else name
        return first, picked

    def _is_weapon_alert_anchor_outlier(self, frame_node: ET.Element) -> bool:
        # Some weapon "alert" nodes in v83 data are present but produce a
        # visibly detached sprite due extreme hand anchor offsets. Treat those
        # as bad nodes and fall back to a compatible idle action.
        if self.kind != "weapon":
            return False

        for child in frame_node:
            if child.tag != "canvas":
                continue
            canvas_name = child.attrib.get("name", "")
            if canvas_name not in ("weapon", ""):
                continue
            origin, anchors, _ = self._canvas_meta(child)
            hand = anchors.get("hand")
            if hand is None:
                continue
            local_hand_x = origin[0] + hand[0]
            local_hand_y = origin[1] + hand[1]
            if local_hand_x >= 58 and local_hand_y >= 52:
                return True
        return False

    def _find_top_action_node(self, name: str) -> Optional[ET.Element]:
        node = self._child_imgdir(self.root, name)
        if node is None:
            return None
        # Action nodes generally contain numeric frame imgdirs.
        if any(c.tag == "imgdir" and c.attrib.get("name", "").isdigit() for c in node):
            return node
        return None

    def _first_action_like_node(self) -> Optional[ET.Element]:
        for child in self.root:
            if child.tag != "imgdir":
                continue
            name = child.attrib.get("name", "")
            if name in ("info", "default", "front", "backDefault", "back"):
                continue
            if any(c.tag == "imgdir" and c.attrib.get("name", "").isdigit() for c in child):
                return child
        return None

    def select_render_node(self, action: str, frame: int) -> Optional[ET.Element]:
        requested_action = action
        requested_frame = frame
        self.last_selection = {
            "requested_action": requested_action,
            "requested_frame": requested_frame,
            "selected_action": None,
            "selected_frame": None,
            "selection_mode": "none",
        }

        # Preferred: action/frame
        action_node = self._find_top_action_node(action)
        if action_node is not None:
            frame_node = self._child_imgdir(action_node, str(frame))
            if frame_node is not None:
                if self.kind == "weapon" and action == "alert" and self._is_weapon_alert_anchor_outlier(frame_node):
                    for alt in _weapon_action_aliases(action, self.part_id):
                        if not alt or alt == action:
                            continue
                        alt_node = self._find_top_action_node(alt)
                        if alt_node is None:
                            continue
                        fallback_frame, picked = self._closest_frame_node(alt_node, frame)
                        self.last_selection.update(
                            {
                                "selected_action": alt,
                                "selected_frame": picked,
                                "selection_mode": "fallback_weapon_alert_outlier_alias_closest_frame",
                            }
                        )
                        return fallback_frame
                self.last_selection.update(
                    {
                        "selected_action": action,
                        "selected_frame": frame,
                        "selection_mode": "exact_action_exact_frame",
                    }
                )
                return frame_node
            fallback_frame, picked = self._closest_frame_node(action_node, frame)
            self.last_selection.update(
                {
                    "selected_action": action,
                    "selected_frame": picked,
                    "selection_mode": "exact_action_closest_frame",
                }
            )
            return fallback_frame

        # Secondary: strip numeric suffix on action name (alert4 => alert).
        stripped = re.sub(r"\d+$", "", action)
        if stripped and stripped != action:
            action_node = self._find_top_action_node(stripped)
            if action_node is not None:
                frame_node = self._child_imgdir(action_node, str(frame))
                if frame_node is not None:
                    self.last_selection.update(
                        {
                            "selected_action": stripped,
                            "selected_frame": frame,
                            "selection_mode": "fallback_strip_digits_exact_frame",
                        }
                    )
                    return frame_node
                fallback_frame, picked = self._closest_frame_node(action_node, frame)
                self.last_selection.update(
                    {
                        "selected_action": stripped,
                        "selected_frame": picked,
                        "selection_mode": "fallback_strip_digits_closest_frame",
                    }
                )
                return fallback_frame

        # Weapon-specific compatibility aliases (game-style action families).
        if self.kind == "weapon":
            for alt in _weapon_action_aliases(action, self.part_id):
                if not alt or alt in {action, stripped}:
                    continue
                action_node = self._find_top_action_node(alt)
                if action_node is None:
                    continue
                fallback_frame, picked = self._closest_frame_node(action_node, frame)
                self.last_selection.update(
                    {
                        "selected_action": alt,
                        "selected_frame": picked,
                        "selection_mode": "fallback_weapon_action_alias_closest_frame",
                    }
                )
                return fallback_frame

        # Avoid forcing cross-action fallback on weapons; this causes visible
        # misalignment on actions where the equipped weapon has no matching node.
        if self.kind != "weapon":
            # Common action fallbacks for compatibility across non-weapon items.
            for common in ("stand1", "stand2", "walk1", "walk2", "alert", "jump"):
                action_node = self._find_top_action_node(common)
                if action_node is not None:
                    fallback_frame, picked = self._closest_frame_node(action_node, frame)
                    self.last_selection.update(
                        {
                            "selected_action": common,
                            "selected_frame": picked,
                            "selection_mode": "fallback_common_action_closest_frame",
                        }
                    )
                    return fallback_frame

        # Fallbacks for static or atypical assets
        for name in ("default", "front", "backDefault", "back"):
            node = self._child_imgdir(self.root, name)
            if node is not None:
                self.last_selection.update(
                    {
                        "selected_action": name,
                        "selected_frame": None,
                        "selection_mode": "fallback_static_node",
                    }
                )
                return node

        # Last resort: first action-like node if present; never return root.
        if self.kind != "weapon":
            action_node = self._first_action_like_node()
            if action_node is not None:
                fallback_frame, picked = self._closest_frame_node(action_node, frame)
                self.last_selection.update(
                    {
                        "selected_action": action_node.attrib.get("name", ""),
                        "selected_frame": picked,
                        "selection_mode": "fallback_first_action_like_closest_frame",
                    }
                )
                return fallback_frame

        self.last_selection.update({"selection_mode": "no_render_node"})
        return None

    def resolve_uol(self, from_path: Tuple[str, ...], value: str) -> Optional[Tuple[str, ...]]:
        parts = [p for p in value.split("/") if p and p != "."]
        base = list(from_path[:-1])  # relative to parent node of uol
        for p in parts:
            if p == "..":
                if len(base) > 1:
                    base.pop()
            else:
                base.append(p)
        target = tuple(base)
        return target if target in self.index else None

    def _vector_xy(self, node: ET.Element, name: str) -> Optional[Tuple[int, int]]:
        for child in node:
            if child.tag == "vector" and child.attrib.get("name") == name:
                x = int(child.attrib.get("x", "0"))
                y = int(child.attrib.get("y", "0"))
                return (x, y)
        return None

    def _canvas_meta(self, canvas: ET.Element) -> Tuple[Tuple[int, int], Dict[str, Tuple[int, int]], str]:
        origin = (0, 0)
        anchors: Dict[str, Tuple[int, int]] = {}
        z = "unknown"
        for child in canvas:
            if child.tag == "vector" and child.attrib.get("name") == "origin":
                origin = (int(child.attrib.get("x", "0")), int(child.attrib.get("y", "0")))
            elif child.tag == "imgdir" and child.attrib.get("name") == "map":
                for vec in child:
                    if vec.tag == "vector":
                        an = vec.attrib.get("name")
                        if an:
                            anchors[an] = (
                                int(vec.attrib.get("x", "0")),
                                int(vec.attrib.get("y", "0")),
                            )
            elif child.tag == "string" and child.attrib.get("name") == "z":
                z = child.attrib.get("value", z)
        return origin, anchors, z

    def _collect_canvases(
        self,
        node: ET.Element,
        path: Tuple[str, ...],
        out: List[DrawEntry],
        visited: set[Tuple[str, ...]],
    ) -> None:
        node_name = path[-1]

        if node.tag == "uol":
            value = node.attrib.get("value", "")
            target_path = self.resolve_uol(path, value)
            if target_path is None or target_path in visited:
                return
            visited.add(target_path)
            self._collect_canvases(self.index[target_path], target_path, out, visited)
            return

        if node.tag == "canvas":
            origin, anchors, z = self._canvas_meta(node)
            rel = Path(*path[1:-1]) if len(path) > 2 else Path()
            png_path = self.img_dir / rel / f"{path[-1]}.png"
            out.append(
                DrawEntry(
                    asset_kind=self.kind,
                    part_id=self.part_id,
                    node_path=path,
                    png_path=png_path,
                    z=z,
                    origin=origin,
                    anchors=anchors,
                )
            )
            return

        if node.tag != "imgdir":
            return

        # Never render inventory icon metadata branches.
        if node_name == "info":
            return

        # Hair color variants are encoded under hairShade/<digit>.
        if self.kind == "hair" and node_name == "hairShade":
            color_key = str(self.part_id % 10)
            target = None
            for child in node:
                if child.attrib.get("name") == color_key:
                    target = child
                    break
            if target is None:
                for child in node:
                    if child.attrib.get("name") == "0":
                        target = child
                        break
            if target is not None:
                child_name = target.attrib.get("name")
                if child_name:
                    self._collect_canvases(target, path + (child_name,), out, visited)
                return

        for child in node:
            child_name = child.attrib.get("name")
            if not child_name:
                continue
            self._collect_canvases(child, path + (child_name,), out, visited)

    def build_draw_entries(self, action: str, frame: int) -> tuple[List[DrawEntry], dict]:
        start = self.select_render_node(action, frame)
        if start is None:
            return [], dict(self.last_selection)
        start_path: Optional[Tuple[str, ...]] = None
        for p, n in self.index.items():
            if n is start:
                start_path = p
                break
        if start_path is None:
            meta = dict(self.last_selection)
            meta["selection_mode"] = "node_not_indexed"
            return [], meta

        out: List[DrawEntry] = []
        self._collect_canvases(start, start_path, out, visited=set())
        return out, dict(self.last_selection)

    def build_draw_entries_from_start_path(self, start_path: Tuple[str, ...]) -> List[DrawEntry]:
        node = self.index.get(start_path)
        if node is None:
            return []
        out: List[DrawEntry] = []
        self._collect_canvases(node, start_path, out, visited=set())
        return out


def id_to_xml(category_dir: Path, part_id: int) -> Path:
    return category_dir / f"{part_id:08d}.img.xml"


def parse_zmap(base_wz: Path) -> Dict[str, int]:
    zmap = base_wz / "zmap.img.xml"
    if not zmap.exists():
        return {}
    root = ET.parse(zmap).getroot()
    order: Dict[str, int] = {}
    idx = 0
    for child in root:
        name = child.attrib.get("name")
        if name:
            order[name] = idx
            idx += 1
    return order


def _skill_xml_candidates(skill_id: int) -> list[str]:
    job = int(skill_id) // 10000
    cands = [f"{job}.img.xml"]
    if job < 1000:
        cands.append(f"{job:03d}.img.xml")
    # Deduplicate while preserving order.
    out: list[str] = []
    seen = set()
    for name in cands:
        if name in seen:
            continue
        seen.add(name)
        out.append(name)
    return out


def _load_skill_asset(base_wz: Path, skill_id: int) -> tuple[Optional[Asset], dict]:
    skill_root = base_wz / "Skill" / "Skill.wz"
    candidates = _skill_xml_candidates(skill_id)
    for name in candidates:
        xml_path = skill_root / name
        if not xml_path.exists():
            continue
        try:
            asset = Asset(kind="skill", part_id=int(skill_id), xml_path=xml_path)
            return asset, {"xml": str(xml_path), "candidate_names": candidates}
        except Exception as exc:  # noqa: BLE001
            return None, {"xml": str(xml_path), "candidate_names": candidates, "error": str(exc)}
    return None, {"candidate_names": candidates, "error": "skill_xml_not_found"}


def _pick_skill_branch_node(
    skill_asset: Asset,
    skill_id: int,
    skill_anim: str,
) -> tuple[Optional[Tuple[str, ...]], dict]:
    skill_id_s = str(int(skill_id))
    root = skill_asset.root_name
    entry_candidates = [
        (root, "skill", skill_id_s),
        (root, skill_id_s),
    ]
    entry_path: Optional[Tuple[str, ...]] = None
    for p in entry_candidates:
        if p in skill_asset.index:
            entry_path = p
            break
    if entry_path is None:
        return None, {"selection_mode": "skill_entry_not_found"}

    requested = (skill_anim or "auto").strip()
    branch_names: list[str] = []
    if requested and requested != "auto":
        branch_names.append(requested)
    for name in SKILL_BRANCH_PRIORITY:
        if name not in branch_names:
            branch_names.append(name)

    branch_path: Optional[Tuple[str, ...]] = None
    selected_branch = None
    if requested == "auto":
        # Allow direct frame nodes under skill entry when branch is omitted.
        has_numeric_direct = False
        entry_node = skill_asset.index[entry_path]
        for child in entry_node:
            if child.attrib.get("name", "").isdigit():
                has_numeric_direct = True
                break
        if has_numeric_direct:
            branch_path = entry_path
            selected_branch = "direct"

    if branch_path is None:
        for name in branch_names:
            p = entry_path + (name,)
            if p in skill_asset.index:
                branch_path = p
                selected_branch = name
                break

    if branch_path is None:
        return None, {
            "selection_mode": "skill_branch_not_found",
            "entry_path": "/".join(entry_path),
            "requested_branch": requested,
        }

    return branch_path, {
        "selection_mode": "skill_branch_selected",
        "entry_path": "/".join(entry_path),
        "selected_branch": selected_branch,
        "requested_branch": requested,
    }


def _pick_skill_frame_path(
    skill_asset: Asset,
    branch_path: Tuple[str, ...],
    requested_frame: int,
) -> tuple[Optional[Tuple[str, ...]], dict]:
    branch_node = skill_asset.index.get(branch_path)
    if branch_node is None:
        return None, {"selection_mode": "skill_branch_node_missing"}

    numeric_children: list[tuple[int, Tuple[str, ...], str]] = []
    for child in branch_node:
        name = child.attrib.get("name", "")
        if not name.isdigit():
            continue
        if child.tag not in ("imgdir", "canvas"):
            continue
        numeric_children.append((int(name), branch_path + (name,), child.tag))

    if numeric_children:
        numeric_children.sort(key=lambda x: (abs(x[0] - requested_frame), x[0]))
        chosen = numeric_children[0]
        return chosen[1], {
            "selection_mode": "skill_frame_closest",
            "selected_frame": chosen[0],
            "node_tag": chosen[2],
        }

    if branch_node.tag == "canvas":
        return branch_path, {
            "selection_mode": "skill_canvas_single",
            "selected_frame": requested_frame,
            "node_tag": "canvas",
        }

    if branch_node.tag == "imgdir":
        # Some branches hold a single composite node without numeric frames.
        has_canvas_desc = any(c.tag == "canvas" for c in branch_node)
        if has_canvas_desc:
            return branch_path, {
                "selection_mode": "skill_branch_direct",
                "selected_frame": requested_frame,
                "node_tag": "imgdir",
            }

    return None, {"selection_mode": "skill_frame_not_found"}


def build_skill_entries(
    base_wz: Path,
    skill_id: int,
    skill_anim: str,
    frame: int,
) -> tuple[List[DrawEntry], dict]:
    skill_asset, load_meta = _load_skill_asset(base_wz=base_wz, skill_id=skill_id)
    if skill_asset is None:
        return [], {
            "requested_skill_id": int(skill_id),
            "requested_branch": skill_anim,
            "requested_frame": int(frame),
            "selection_mode": "skill_asset_not_found",
            **load_meta,
        }

    branch_path, branch_meta = _pick_skill_branch_node(
        skill_asset=skill_asset,
        skill_id=skill_id,
        skill_anim=skill_anim,
    )
    if branch_path is None:
        return [], {
            "requested_skill_id": int(skill_id),
            "requested_branch": skill_anim,
            "requested_frame": int(frame),
            "selection_mode": "skill_branch_not_found",
            **load_meta,
            **branch_meta,
        }

    frame_path, frame_meta = _pick_skill_frame_path(
        skill_asset=skill_asset,
        branch_path=branch_path,
        requested_frame=frame,
    )
    if frame_path is None:
        return [], {
            "requested_skill_id": int(skill_id),
            "requested_branch": skill_anim,
            "requested_frame": int(frame),
            "selection_mode": "skill_frame_not_found",
            **load_meta,
            **branch_meta,
            **frame_meta,
        }

    entries = skill_asset.build_draw_entries_from_start_path(frame_path)
    for e in entries:
        # Keep skill layer ordering deterministic and isolated from equipment z.
        e.z = "skillOverlay"
    return entries, {
        "requested_skill_id": int(skill_id),
        "requested_branch": skill_anim,
        "requested_frame": int(frame),
        "selection_mode": "skill_ok" if entries else "skill_empty_entries",
        "selected_path": "/".join(frame_path),
        "entry_count": len(entries),
        **load_meta,
        **branch_meta,
        **frame_meta,
    }


def _is_weapon_hand_proxy_action(node_path: Tuple[str, ...]) -> bool:
    if len(node_path) < 2:
        return False
    action_name = str(node_path[1])
    return action_name.startswith(WEAPON_HAND_PROXY_PREFIXES)


def _weapon_action_aliases(action: str, part_id: Optional[int] = None) -> list[str]:
    # Conservative family-level aliases to keep weapon visibility when the
    # exact body action variant is absent for the equipped weapon.
    aliases: list[str] = []
    ranged_weapon = part_id is not None and _weapon_type_code(part_id) in RANGED_WEAPON_TYPE_CODES
    if ranged_weapon:
        # Ranged sets are sensitive to cross-family remapping; keep aliases
        # minimal to prevent detached/static weapon placements.
        table = {
            "alert": ["stand1", "walk1", "stand2", "walk2"],
            "stand2": ["stand1", "walk1", "alert"],
            "walk2": ["walk1", "stand1"],
        }
    else:
        table = {
            "alert": ["stand2", "stand1", "walk2", "walk1", "prone"],
            "stand1": ["stand2", "stand1", "walk2", "walk1", "alert", "prone"],
            "stand2": ["stand2", "stand1", "walk2", "walk1", "alert", "prone"],
            "walk1": ["walk2", "walk1", "stand2", "stand1"],
            "walk2": ["walk2", "walk1", "stand2", "stand1"],
            "swingO1": ["swingO1", "swingP1", "swingT1", "swingT2", "swingP2", "swingPF", "swingOF", "swingTF"],
            "swingO2": ["swingO2", "swingP2", "swingT2", "swingP1", "swingPF", "swingOF", "swingTF"],
            "swingO3": ["swingO3", "swingPF", "swingT3", "swingOF", "swingTF", "swingP2", "swingT2"],
            "swingOF": ["swingOF", "swingPF", "swingTF", "swingO3", "swingT3", "swingP2", "swingT2"],
            "swingT1": ["swingT1", "swingP1", "swingT2", "swingP2", "swingPF", "swingTF"],
            "swingT2": ["swingT2", "swingP2", "swingT1", "swingP1", "swingPF", "swingTF"],
            "swingT3": ["swingT3", "swingPF", "swingTF", "swingT2", "swingP2"],
            "swingTF": ["swingTF", "swingPF", "swingT3", "swingOF", "swingP2", "swingT2"],
            "swingP1": ["swingP1", "swingT1", "swingP2", "swingT2", "swingPF", "swingTF"],
            "swingP2": ["swingP2", "swingT2", "swingP1", "swingT1", "swingPF", "swingTF"],
            "swingPF": ["swingPF", "swingTF", "swingT3", "swingOF", "swingP2", "swingT2"],
            "stabO1": ["stabO1", "stabT1", "stabT2", "stabTF", "stabOF"],
            "stabO2": ["stabO2", "stabT2", "stabT1", "stabTF", "stabOF"],
            "stabOF": ["stabOF", "stabTF", "stabT2", "stabT1", "stabO2"],
            "stabT1": ["stabT1", "stabO1", "stabT2", "stabTF", "stabOF"],
            "stabT2": ["stabT2", "stabO2", "stabT1", "stabTF", "stabOF"],
            "stabTF": ["stabTF", "stabOF", "stabT2", "stabT1", "stabO2"],
            "prone": ["prone", "proneStab", "stand2"],
            "proneStab": ["proneStab", "prone", "stabTF", "stabT2", "stabT1"],
        }
    if action in table:
        aliases.extend(table[action])
    # Mild fallback for numeric suffixed variants.
    stripped = re.sub(r"\d+$", "", action)
    if stripped and stripped != action and stripped in table:
        aliases.extend(table[stripped])

    out: list[str] = []
    seen = set()
    for a in aliases:
        if not a or a in seen:
            continue
        seen.add(a)
        out.append(a)
    return out


def _weapon_type_code(part_id: int) -> int:
    return int(part_id) // 10000


def _is_melee_weapon(part_id: int) -> bool:
    return _weapon_type_code(part_id) in MELEE_WEAPON_TYPE_CODES


def _is_ranged_weapon(part_id: int) -> bool:
    return _weapon_type_code(part_id) in RANGED_WEAPON_TYPE_CODES


def place_entries(
    entries: Iterable[DrawEntry],
    z_order: Dict[str, int],
) -> Tuple[List[PlacedEntry], list[dict], Dict[str, Tuple[int, int]]]:
    world_anchors: Dict[str, Tuple[int, int]] = {"navel": (0, 0)}
    world_anchor_sources: Dict[str, str] = {"navel": "world_root"}
    asset_local_origins: Dict[Tuple[str, int], Tuple[int, int]] = {}
    unresolved: List[dict] = []
    entry_list = list(entries)
    placed_by_index: Dict[int, PlacedEntry] = {}
    pending: list[tuple[int, DrawEntry]] = list(enumerate(entry_list))

    def _entry_z_index(entry: DrawEntry) -> int:
        if entry.asset_kind == "skill":
            # Force skill overlays to render on top in front-last mode.
            return -10
        return z_order.get(entry.z, 1_000_000)

    def _maybe_publish_anchor(
        entry: DrawEntry,
        anchor_name: str,
        world_value: Tuple[int, int],
    ) -> None:
        if not STRICT_METADATA_ALIGNMENT:
            if anchor_name not in world_anchors:
                world_anchors[anchor_name] = world_value
                world_anchor_sources[anchor_name] = entry.asset_kind
            return

        if entry.asset_kind not in ANCHOR_PROVIDER_KINDS:
            return

        current_src = world_anchor_sources.get(anchor_name, "")
        # In strict mode, canonical anchors come only from provider kinds.
        if anchor_name not in world_anchors or current_src not in ANCHOR_PROVIDER_KINDS:
            world_anchors[anchor_name] = world_value
            world_anchor_sources[anchor_name] = entry.asset_kind

    def _try_place(entry: DrawEntry) -> Optional[Tuple[Tuple[int, int], str]]:
        asset_key = (entry.asset_kind, entry.part_id)
        chosen_anchor = ""
        top_left: Optional[Tuple[int, int]] = None

        if entry.anchors:
            local_names = set(entry.anchors.keys())
            # Some weapon attack nodes only expose a navel anchor. For those
            # combat actions, align that navel point to world hand so weapon
            # follow-through tracks the hand more naturally.
            if (
                not STRICT_METADATA_ALIGNMENT
                and
                entry.asset_kind == "weapon"
                and _is_melee_weapon(entry.part_id)
                and "hand" in world_anchors
                and "hand" not in local_names
                and "navel" in local_names
                and _is_weapon_hand_proxy_action(entry.node_path)
            ):
                local = (
                    entry.origin[0] + entry.anchors["navel"][0],
                    entry.origin[1] + entry.anchors["navel"][1],
                )
                target = world_anchors["hand"]
                top_left = (target[0] - local[0], target[1] - local[1])
                chosen_anchor = "hand_proxy_from_navel"

            anchor_priority = WEAPON_ANCHOR_PRIORITY if entry.asset_kind == "weapon" else ANCHOR_PRIORITY
            if top_left is None:
                for anchor in anchor_priority:
                    if anchor in local_names and anchor in world_anchors:
                        local = (
                            entry.origin[0] + entry.anchors[anchor][0],
                            entry.origin[1] + entry.anchors[anchor][1],
                        )
                        target = world_anchors[anchor]
                        top_left = (target[0] - local[0], target[1] - local[1])
                        chosen_anchor = anchor
                        break

            if top_left is None:
                for anchor in sorted(local_names):
                    if anchor in world_anchors:
                        local = (
                            entry.origin[0] + entry.anchors[anchor][0],
                            entry.origin[1] + entry.anchors[anchor][1],
                        )
                        target = world_anchors[anchor]
                        top_left = (target[0] - local[0], target[1] - local[1])
                        chosen_anchor = anchor
                        break

        if top_left is None:
            inherited_local_origin = asset_local_origins.get(asset_key)
            if inherited_local_origin is not None:
                top_left = (
                    inherited_local_origin[0] - entry.origin[0],
                    inherited_local_origin[1] - entry.origin[1],
                )
                chosen_anchor = "asset_origin_inherit"

        if top_left is None:
            return None
        return top_left, chosen_anchor

    # Resolve in passes so anchor-less hand layers can wait until an anchored
    # sibling from the same asset establishes a stable local-origin reference.
    while pending:
        progressed = False
        next_pending: list[tuple[int, DrawEntry]] = []
        for idx, entry in pending:
            resolved = _try_place(entry)
            if resolved is None:
                next_pending.append((idx, entry))
                continue

            top_left, chosen_anchor = resolved
            asset_key = (entry.asset_kind, entry.part_id)
            for an, vec in entry.anchors.items():
                _maybe_publish_anchor(
                    entry=entry,
                    anchor_name=an,
                    world_value=(
                        top_left[0] + entry.origin[0] + vec[0],
                        top_left[1] + entry.origin[1] + vec[1],
                    ),
                )

            if chosen_anchor != "origin_fallback":
                asset_local_origins[asset_key] = (
                    top_left[0] + entry.origin[0],
                    top_left[1] + entry.origin[1],
                )

            z_idx = _entry_z_index(entry)
            placed_by_index[idx] = PlacedEntry(
                draw=entry,
                top_left=top_left,
                used_anchor=chosen_anchor,
                z_index=z_idx,
            )
            progressed = True

        if not progressed:
            pending = next_pending
            break
        pending = next_pending

    # Final fallback for remaining entries that never gained anchor context.
    for idx, entry in pending:
        asset_key = (entry.asset_kind, entry.part_id)
        inherited_local_origin = asset_local_origins.get(asset_key)
        if inherited_local_origin is not None:
            top_left = (
                inherited_local_origin[0] - entry.origin[0],
                inherited_local_origin[1] - entry.origin[1],
            )
            chosen_anchor = "asset_origin_inherit"
        else:
            top_left = (-entry.origin[0], -entry.origin[1])
            chosen_anchor = "origin_fallback"

        for an, vec in entry.anchors.items():
            _maybe_publish_anchor(
                entry=entry,
                anchor_name=an,
                world_value=(
                    top_left[0] + entry.origin[0] + vec[0],
                    top_left[1] + entry.origin[1] + vec[1],
                ),
            )

        if chosen_anchor != "origin_fallback":
            asset_local_origins[asset_key] = (
                top_left[0] + entry.origin[0],
                top_left[1] + entry.origin[1],
            )

        z_idx = _entry_z_index(entry)
        placed_by_index[idx] = PlacedEntry(
            draw=entry,
            top_left=top_left,
            used_anchor=chosen_anchor,
            z_index=z_idx,
        )

    placed = [placed_by_index[i] for i in range(len(entry_list)) if i in placed_by_index]

    # Track missing pngs as unresolved output concerns.
    for p in placed:
        if not p.draw.png_path.exists():
            unresolved.append(
                {
                    "missing_png": str(p.draw.png_path),
                    "asset_kind": p.draw.asset_kind,
                    "part_id": p.draw.part_id,
                    "node_path": "/".join(p.draw.node_path),
                }
            )

    return placed, unresolved, dict(world_anchors)


def enforce_cap_over_hair(entries: List[PlacedEntry]) -> List[PlacedEntry]:
    """Keep non-hair/cap ordering intact while forcing hair to render before cap."""
    hair_cap_positions = []
    hair_items: List[PlacedEntry] = []
    cap_items: List[PlacedEntry] = []

    for i, entry in enumerate(entries):
        kind = entry.draw.asset_kind
        if kind == "hair":
            hair_cap_positions.append(i)
            hair_items.append(entry)
        elif kind == "cap":
            hair_cap_positions.append(i)
            cap_items.append(entry)

    if not hair_items or not cap_items:
        return entries

    reordered = list(entries)
    merged = hair_items + cap_items
    for i, pos in enumerate(hair_cap_positions):
        reordered[pos] = merged[i]
    return reordered


def apply_ranged_alert_hand_face_layer_fix(
    entries: List[PlacedEntry],
    action: str,
    weapon_id: Optional[int],
) -> None:
    # Narrow fix for ranged alert/heal where left-hand can incorrectly cover
    # face in composed output.
    if weapon_id is None or not _is_ranged_weapon(weapon_id):
        return
    if action not in {"alert", "heal"}:
        return

    face_z = None
    for entry in entries:
        if entry.draw.asset_kind == "face":
            face_z = entry.z_index if face_z is None else min(face_z, entry.z_index)
    if face_z is None:
        return

    for entry in entries:
        node_name = entry.draw.node_path[-1] if entry.draw.node_path else ""
        if entry.draw.asset_kind != "body":
            continue
        if node_name != "lHand":
            continue
        if entry.draw.z != "handBelowWeapon":
            continue
        entry.z_index = max(entry.z_index, face_z + 1)


def apply_offhand_visibility_policy(
    entries: List[PlacedEntry],
    action: str,
    weapon_id: Optional[int],
) -> tuple[List[PlacedEntry], dict]:
    removed_node_paths: list[str] = []
    if action not in {"alert", "heal"}:
        return entries, {"removed_node_paths": removed_node_paths}

    ranged_weapon = weapon_id is not None and _is_ranged_weapon(weapon_id)

    filtered: list[PlacedEntry] = []
    for entry in entries:
        node_name = entry.draw.node_path[-1] if entry.draw.node_path else ""
        if (
            entry.draw.asset_kind == "body"
            and node_name == "lHand"
            and (ranged_weapon or entry.used_anchor == "asset_origin_inherit")
        ):
            removed_node_paths.append("/".join(entry.draw.node_path))
            continue
        filtered.append(entry)

    return filtered, {"removed_node_paths": removed_node_paths}


def _info_string(asset: Asset, key: str) -> str:
    info_node = asset._child_imgdir(asset.root, "info")
    if info_node is None:
        return ""
    for child in info_node:
        if child.tag == "string" and child.attrib.get("name") == key:
            return child.attrib.get("value", "")
    return ""


def _vslot_tokens(vslot: str) -> set[str]:
    return set(VSLOT_TOKEN_RE.findall(vslot or ""))


def analyze_cap_hair_state(cap_asset: Optional[Asset], cap_entries: List[DrawEntry]) -> dict:
    if cap_asset is None or not cap_entries:
        return {
            "has_cap": False,
            "vslot": "",
            "hair_tokens": [],
            "full_hair_mask": False,
            "partial_hair_mask": False,
            "cap_over_hair_z": False,
        }

    vslot = _info_string(cap_asset, "vslot")
    tokens = _vslot_tokens(vslot)
    hair_tokens = sorted(tokens & HAIR_MASK_SLOTS)
    full_hair_mask = set(hair_tokens) == HAIR_MASK_SLOTS
    partial_hair_mask = bool(hair_tokens) and not full_hair_mask
    cap_over_hair_z = any(e.z in CAP_OVERHAIR_Z_TAGS for e in cap_entries)
    cap_front_over_hair = any(e.z == "capOverHair" for e in cap_entries)
    cap_back_over_hair = any(e.z == "backCapOverHair" for e in cap_entries)
    return {
        "has_cap": True,
        "vslot": vslot,
        "hair_tokens": hair_tokens,
        "full_hair_mask": full_hair_mask,
        "partial_hair_mask": partial_hair_mask,
        "cap_over_hair_z": cap_over_hair_z,
        "cap_front_over_hair": cap_front_over_hair,
        "cap_back_over_hair": cap_back_over_hair,
    }


def apply_hair_mode(
    entries: List[DrawEntry],
    cap_asset: Optional[Asset],
    hair_mode: str,
) -> tuple[List[DrawEntry], dict]:
    def _z_counts(rows: List[DrawEntry]) -> dict:
        counts: dict[str, int] = {}
        for row in rows:
            counts[row.z] = counts.get(row.z, 0) + 1
        return dict(sorted(counts.items(), key=lambda kv: kv[0]))

    cap_entries = [e for e in entries if e.asset_kind == "cap"]
    cap_state = analyze_cap_hair_state(cap_asset, cap_entries)
    all_hair = [e for e in entries if e.asset_kind == "hair"]

    removed = []
    removed_front = []
    removed_back = []
    reason = "none"
    if hair_mode == "force-hide":
        removed = [e for e in entries if e.asset_kind == "hair"]
        removed_front = list(removed)
        removed_back = []
        reason = "force-hide"
    elif hair_mode == "auto" and cap_state["has_cap"]:
        if cap_state["full_hair_mask"]:
            removed = [e for e in entries if e.asset_kind == "hair"]
            removed_front = list(removed)
            removed_back = []
            reason = "auto_full_mask_vslot"
        elif cap_state["partial_hair_mask"]:
            if cap_state["cap_front_over_hair"]:
                removed_front = [
                    e for e in entries if e.asset_kind == "hair" and e.z in FRONT_HAIR_Z_TAGS
                ]
            if cap_state["cap_back_over_hair"]:
                removed_back = [
                    e for e in entries if e.asset_kind == "hair" and e.z in BACK_HAIR_Z_TAGS
                ]
            if removed_front or removed_back:
                merged = {id(e): e for e in removed_front + removed_back}
                removed = list(merged.values())
                if removed_front and removed_back:
                    reason = "auto_partial_mask_overhair_front_and_back"
                elif removed_front:
                    reason = "auto_partial_mask_overhair_front_only"
                else:
                    reason = "auto_partial_mask_overhair_back_only"
        elif cap_state["cap_over_hair_z"]:
            # Rare fallback: cap advertises over-hair layering but omits hair vslot tokens.
            if cap_state["cap_front_over_hair"]:
                removed_front = [
                    e for e in entries if e.asset_kind == "hair" and e.z in FRONT_HAIR_Z_TAGS
                ]
            if cap_state["cap_back_over_hair"]:
                removed_back = [
                    e for e in entries if e.asset_kind == "hair" and e.z in BACK_HAIR_Z_TAGS
                ]
            if removed_front or removed_back:
                merged = {id(e): e for e in removed_front + removed_back}
                removed = list(merged.values())
                if removed_front and removed_back:
                    reason = "auto_overhair_no_vslot_tokens_front_and_back"
                elif removed_front:
                    reason = "auto_overhair_no_vslot_tokens_front_only"
                else:
                    reason = "auto_overhair_no_vslot_tokens_back_only"
    # force-show => removed stays empty.

    if removed:
        removed_ids = {id(e) for e in removed}
        filtered = [e for e in entries if id(e) not in removed_ids]
    else:
        filtered = entries
    kept_hair = [e for e in filtered if e.asset_kind == "hair"]
    removed_examples = [
        {
            "z": e.z,
            "part_id": e.part_id,
            "node_path": "/".join(e.node_path),
        }
        for e in removed[:40]
    ]

    policy = {
        "mode": hair_mode,
        "rule": reason,
        "removed_layers": len(removed),
        "removed_front_hair_layers": len(removed_front),
        "removed_back_hair_layers": len(removed_back),
        "hair_layers_total": len(all_hair),
        "hair_layers_kept": len(kept_hair),
        "hair_z_total": _z_counts(all_hair),
        "hair_z_kept": _z_counts(kept_hair),
        "hair_z_removed": _z_counts(removed),
        "removed_examples": removed_examples,
        "removed_examples_truncated": len(removed) > len(removed_examples),
        "removed_front_hair_only": reason == "auto_partial_mask_overhair_front_only",
        "cap_state": cap_state,
    }
    return filtered, policy


def render(
    base_wz: Path,
    output_png: Path,
    action: str,
    frame: int,
    base_id: int,
    head_id: int,
    face_id: int,
    hair_id: int,
    accessory_id: Optional[int],
    cap_id: Optional[int],
    coat_id: Optional[int],
    longcoat_id: Optional[int],
    pants_id: Optional[int],
    shoes_id: Optional[int],
    glove_id: Optional[int],
    cape_id: Optional[int],
    shield_id: Optional[int],
    weapon_id: Optional[int],
    skill_id: Optional[int] = None,
    skill_anim: str = "auto",
    output_json: Optional[Path] = None,
    z_draw_order: str = "front-last",
    hair_mode: str = "auto",
    include_face: bool = True,
) -> dict:
    char_root = base_wz / "Character" / "Character.wz"
    equipment_normalization: List[dict] = []

    # Normalize incompatible body armor combinations for stable composition.
    if longcoat_id is not None:
        if coat_id is not None:
            equipment_normalization.append(
                {
                    "rule": "longcoat_overrides_coat",
                    "removed_kind": "coat",
                    "removed_part_id": coat_id,
                    "active_longcoat_id": longcoat_id,
                }
            )
            coat_id = None
        if pants_id is not None:
            equipment_normalization.append(
                {
                    "rule": "longcoat_overrides_pants",
                    "removed_kind": "pants",
                    "removed_part_id": pants_id,
                    "active_longcoat_id": longcoat_id,
                }
            )
            pants_id = None

    specs = [
        ("body", base_id, char_root),
        ("head", head_id, char_root),
        ("face", face_id, char_root / "Face"),
        ("hair", hair_id, char_root / "Hair"),
    ]
    if accessory_id is not None:
        specs.append(("accessory", accessory_id, char_root / "Accessory"))
    if cap_id is not None:
        specs.append(("cap", cap_id, char_root / "Cap"))
    if coat_id is not None:
        specs.append(("coat", coat_id, char_root / "Coat"))
    if longcoat_id is not None:
        specs.append(("longcoat", longcoat_id, char_root / "Longcoat"))
    if pants_id is not None:
        specs.append(("pants", pants_id, char_root / "Pants"))
    if shoes_id is not None:
        specs.append(("shoes", shoes_id, char_root / "Shoes"))
    if glove_id is not None:
        specs.append(("glove", glove_id, char_root / "Glove"))
    if cape_id is not None:
        specs.append(("cape", cape_id, char_root / "Cape"))
    if shield_id is not None:
        specs.append(("shield", shield_id, char_root / "Shield"))
    if weapon_id is not None:
        specs.append(("weapon", weapon_id, char_root / "Weapon"))

    assets: List[Asset] = []
    cap_asset: Optional[Asset] = None
    missing_xml = []
    for kind, part_id, category_dir in specs:
        xml_path = id_to_xml(category_dir, part_id)
        if not xml_path.exists():
            missing_xml.append({"kind": kind, "part_id": part_id, "xml": str(xml_path)})
            continue
        asset = Asset(kind=kind, part_id=part_id, xml_path=xml_path)
        assets.append(asset)
        if kind == "cap":
            cap_asset = asset

    z_order = parse_zmap(base_wz)

    all_entries: List[DrawEntry] = []
    action_resolution: List[dict] = []
    action_fallbacks: List[dict] = []
    head_back_pose = False
    body_only_actions = action.startswith("ghost") or action in {"dead", "eburster"}
    for asset in assets:
        if body_only_actions and asset.kind != "body":
            action_resolution.append(
                {
                    "asset_kind": asset.kind,
                    "part_id": asset.part_id,
                    "requested_action": action,
                    "requested_frame": frame,
                    "selected_action": None,
                    "selected_frame": None,
                    "selection_mode": "suppressed_body_only_action",
                    "entry_count": 0,
                }
            )
            continue
        entries, sel = asset.build_draw_entries(action=action, frame=frame)
        if asset.kind == "head" and entries:
            # Back-facing head nodes (for example head/back) imply face/eyes
            # should not be rendered even if the face asset can fallback.
            if any(seg in {"back", "backDefault"} for e in entries for seg in e.node_path):
                head_back_pose = True
        if asset.kind == "face" and head_back_pose and entries:
            sel = dict(sel)
            sel["suppressed_from_selection_mode"] = sel.get("selection_mode")
            sel["selection_mode"] = "suppressed_back_head_pose"
            entries = []
        sel_row = {
            "asset_kind": asset.kind,
            "part_id": asset.part_id,
            **sel,
            "entry_count": len(entries),
        }
        action_resolution.append(sel_row)
        if len(entries) > 0 and sel.get("selection_mode") not in ("exact_action_exact_frame", "exact_action_first_frame"):
            action_fallbacks.append(sel_row)
        if not entries:
            # Missing weapon action nodes are common across action families
            # (e.g., weapon type mismatch); omit weapon layer instead of
            # marking the whole frame unresolved.
            if asset.kind != "weapon" and sel.get("selection_mode") != "suppressed_back_head_pose":
                missing_xml.append(
                    {
                        "kind": asset.kind,
                        "part_id": asset.part_id,
                        "missing_action_node": True,
                        "selection": sel,
                    }
                )
            continue
        all_entries.extend(entries)

    skill_selection = None
    if skill_id is not None:
        skill_entries, skill_selection = build_skill_entries(
            base_wz=base_wz,
            skill_id=int(skill_id),
            skill_anim=skill_anim,
            frame=frame,
        )
        skill_row = {
            "asset_kind": "skill",
            "part_id": int(skill_id),
            "requested_action": action,
            "requested_frame": frame,
            "selected_action": skill_selection.get("selected_branch"),
            "selected_frame": skill_selection.get("selected_frame"),
            "selection_mode": skill_selection.get("selection_mode"),
            "entry_count": len(skill_entries),
        }
        action_resolution.append(skill_row)
        if skill_entries:
            all_entries.extend(skill_entries)
        else:
            missing_xml.append(
                {
                    "kind": "skill",
                    "part_id": int(skill_id),
                    "missing_action_node": True,
                    "selection": skill_selection,
                }
            )
    all_entries, hair_policy = apply_hair_mode(
        entries=all_entries,
        cap_asset=cap_asset,
        hair_mode=hair_mode,
    )

    placed, unresolved, world_anchors = place_entries(all_entries, z_order=z_order)
    unresolved.extend(missing_xml)
    placed, offhand_policy = apply_offhand_visibility_policy(placed, action=action, weapon_id=weapon_id)
    apply_ranged_alert_hand_face_layer_fix(placed, action=action, weapon_id=weapon_id)

    # Load images and compute bounds.
    draw_queue = []
    min_x = 10**9
    min_y = 10**9
    max_x = -10**9
    max_y = -10**9

    reverse_z = z_draw_order == "front-last"
    ordered = sorted(placed, key=lambda x: (x.z_index, x.draw.asset_kind), reverse=reverse_z)
    ordered = enforce_cap_over_hair(ordered)

    for p in ordered:
        if not p.draw.png_path.exists():
            continue
        img = Image.open(p.draw.png_path).convert("RGBA")
        should_draw = not (p.draw.asset_kind == "face" and not include_face)
        x, y = p.top_left
        w, h = img.size
        min_x = min(min_x, x)
        min_y = min(min_y, y)
        max_x = max(max_x, x + w)
        max_y = max(max_y, y + h)
        draw_queue.append((p, img, should_draw))

    if not draw_queue:
        raise RuntimeError("No drawable PNG assets resolved for requested frame.")

    pad = 10
    width = (max_x - min_x) + pad * 2
    height = (max_y - min_y) + pad * 2
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    frame_left_world = min_x - pad
    frame_top_world = min_y - pad
    frame_right_world = max_x + pad
    frame_bottom_world = max_y + pad

    for p, img, should_draw in draw_queue:
        if not should_draw:
            continue
        x, y = p.top_left
        dx = x - min_x + pad
        dy = y - min_y + pad
        canvas.alpha_composite(img, (dx, dy))

    output_png.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_png)

    metadata = {
        "action": action,
        "frame": frame,
        "base_wz": str(base_wz),
        "output_png": str(output_png),
        "drawn_layers": len(draw_queue),
        "canvas_size": [width, height],
        "frame_bounds_world": {
            "left": frame_left_world,
            "top": frame_top_world,
            "right": frame_right_world,
            "bottom": frame_bottom_world,
        },
        "world_anchors": {k: [v[0], v[1]] for k, v in sorted(world_anchors.items(), key=lambda kv: kv[0])},
        "z_draw_order": z_draw_order,
        "hair_policy": hair_policy,
        "offhand_policy": offhand_policy,
        "skill_selection": skill_selection,
        "equipment_normalization": equipment_normalization,
        "action_resolution": action_resolution,
        "action_fallback_count": len(action_fallbacks),
        "action_fallbacks": action_fallbacks,
        "assets_loaded": [{"kind": a.kind, "part_id": a.part_id, "xml": str(a.xml_path)} for a in assets],
        "unresolved": unresolved,
        "draw_order": [
            {
                "asset_kind": p.draw.asset_kind,
                "part_id": p.draw.part_id,
                "z": p.draw.z,
                "z_index": p.z_index,
                "top_left": [p.top_left[0], p.top_left[1]],
                "origin": [p.draw.origin[0], p.draw.origin[1]],
                "asset_origin_world": [p.top_left[0] + p.draw.origin[0], p.top_left[1] + p.draw.origin[1]],
                "used_anchor": p.used_anchor,
                "anchors_local": {an: [vec[0], vec[1]] for an, vec in sorted(p.draw.anchors.items(), key=lambda kv: kv[0])},
                "anchors_world": {
                    an: [
                        p.top_left[0] + p.draw.origin[0] + vec[0],
                        p.top_left[1] + p.draw.origin[1] + vec[1],
                    ]
                    for an, vec in sorted(p.draw.anchors.items(), key=lambda kv: kv[0])
                },
                "png": str(p.draw.png_path),
                "node_path": "/".join(p.draw.node_path),
            }
            for p, _, _ in draw_queue
        ],
    }

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-wz",
        default=r"C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz",
        help="Path to extracted Base.wz directory",
    )
    parser.add_argument(
        "--action",
        default="stand1",
        help="Action/state name (for example stand1, walk1, swingO1)",
    )
    parser.add_argument("--frame", type=int, default=0, help="Frame index within action")
    parser.add_argument("--output-png", required=True, help="Output PNG path")
    parser.add_argument("--output-json", help="Optional output metadata JSON path")
    parser.add_argument(
        "--z-draw-order",
        choices=["front-last", "front-first"],
        default="front-last",
        help="Layer draw order; front-last is recommended for Maple zmap ordering",
    )
    parser.add_argument(
        "--hair-mode",
        choices=["auto", "force-show", "force-hide"],
        default="auto",
        help="Hair handling around caps: auto|force-show|force-hide",
    )
    parser.add_argument(
        "--exclude-face",
        action="store_true",
        help="Do not composite face layer into the output PNG (keeps metadata for overlay use).",
    )

    parser.add_argument("--starter-male", action="store_true", help="Apply starter male defaults")

    parser.add_argument("--base-id", type=int, default=2000)
    parser.add_argument("--head-id", type=int, default=12000)
    parser.add_argument("--face-id", type=int, default=20000)
    parser.add_argument("--hair-id", type=int, default=30000)

    parser.add_argument("--accessory-id", type=int)
    parser.add_argument("--cap-id", type=int)
    parser.add_argument("--coat-id", type=int)
    parser.add_argument("--longcoat-id", type=int)
    parser.add_argument("--pants-id", type=int)
    parser.add_argument("--shoes-id", type=int)
    parser.add_argument("--glove-id", type=int)
    parser.add_argument("--cape-id", type=int)
    parser.add_argument("--shield-id", type=int)
    parser.add_argument("--weapon-id", type=int)
    parser.add_argument("--skill-id", type=int, help="Optional skill ID to overlay (from Skill.wz)")
    parser.add_argument(
        "--skill-anim",
        default="auto",
        help="Skill animation branch (auto|effect|effect0|effect1|hit|ball|prepare|summon|affected)",
    )

    args = parser.parse_args()

    if args.starter_male:
        # Defaults from common v83 starter male selections.
        args.base_id = 2000
        args.head_id = 12000
        args.face_id = 20000
        args.hair_id = 30000
        if args.coat_id is None:
            args.coat_id = 1040002
        if args.pants_id is None:
            args.pants_id = 1060002
        if args.shoes_id is None:
            args.shoes_id = 1072001
        if args.weapon_id is None:
            args.weapon_id = 1302000

    metadata = render(
        base_wz=Path(args.base_wz),
        output_png=Path(args.output_png),
        action=args.action,
        frame=args.frame,
        base_id=args.base_id,
        head_id=args.head_id,
        face_id=args.face_id,
        hair_id=args.hair_id,
        accessory_id=args.accessory_id,
        cap_id=args.cap_id,
        coat_id=args.coat_id,
        longcoat_id=args.longcoat_id,
        pants_id=args.pants_id,
        shoes_id=args.shoes_id,
        glove_id=args.glove_id,
        cape_id=args.cape_id,
        shield_id=args.shield_id,
        weapon_id=args.weapon_id,
        skill_id=args.skill_id,
        skill_anim=args.skill_anim,
        output_json=Path(args.output_json) if args.output_json else None,
        z_draw_order=args.z_draw_order,
        hair_mode=args.hair_mode,
        include_face=not bool(args.exclude_face),
    )
    print(
        json.dumps(
            {
                "status": "ok",
                "output_png": str(args.output_png),
                "drawn_layers": metadata["drawn_layers"],
                "unresolved_count": len(metadata["unresolved"]),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
