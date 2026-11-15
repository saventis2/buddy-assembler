#!/usr/bin/env python3
"""Shared helpers for the importer/analysis scripts in tools/importers/.

Backlog #46: logic that was verbatim-duplicated (or duplicated modulo variable
names / type annotations) across the 15 sibling scripts lives here exactly
once. Every function body is a direct lift of the original per-script copy --
behavior preservation is the contract. Where two original copies genuinely
differed, the difference is exposed as a parameter (see
``normalize_action_frame_canvases``'s ``sync_bounds_metadata`` and
``write_csv``'s ``headers=None`` mode) rather than silently unified.

This module deliberately stays flat (no package/subpackage) and stdlib-only at
import time: Pillow is imported lazily inside the two image helpers so the
XML/CSV-only scripts keep working in environments without Pillow, exactly as
they did before extraction.
"""

from __future__ import annotations

import csv
import json
import math
import os
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

# --------------------------------------------------------------------------
# Path resolution (CLI arg > BUDDY_ASSEMBLER_* env var > hardcoded fallback)
#
# Precedence mechanism introduced by backlog #45 into build_wz_index.py and
# character_tooling_gui.py; documented in Character-Tooling.md. The fallback
# constants are the maintainer's local Windows paths, unchanged.
# --------------------------------------------------------------------------

BASE_WZ_ENV_VAR = "BUDDY_ASSEMBLER_BASE_WZ"
ANALYSIS_DIR_ENV_VAR = "BUDDY_ASSEMBLER_ANALYSIS_DIR"
FALLBACK_BASE_WZ = r"C:\Users\GGPC\OneDrive\Desktop\83 complete\Base.wz"
FALLBACK_ANALYSIS_DIR = r"C:\Users\GGPC\OneDrive\Desktop\83 complete\analysis"


def resolve_default_path(cli_value: str | None, env_var: str, fallback: str) -> str:
    """Resolve a default path setting.

    Precedence: explicit CLI value > environment variable > hardcoded
    fallback (the maintainer's local machine path). See Character-Tooling.md.
    """
    if cli_value:
        return cli_value
    env_value = os.environ.get(env_var)
    if env_value:
        return env_value
    return fallback


def resolve_base_wz(cli_value: str | None = None) -> Path:
    """Resolve the Base.wz directory path.

    Precedence: explicit --base-wz CLI value > BUDDY_ASSEMBLER_BASE_WZ
    environment variable > hardcoded fallback (the maintainer's local
    machine path). See Character-Tooling.md.
    """
    return Path(resolve_default_path(cli_value, BASE_WZ_ENV_VAR, FALLBACK_BASE_WZ))


# --------------------------------------------------------------------------
# WZ-XML tree helpers
# --------------------------------------------------------------------------

def child_imgdir(node: ET.Element, name: str) -> Optional[ET.Element]:
    """Return the direct child <imgdir name=...> of ``node``, or None."""
    for child in node:
        if child.tag == "imgdir" and child.attrib.get("name") == name:
            return child
    return None


def find_imgdir_path(node: ET.Element, path: list[str]) -> Optional[ET.Element]:
    """Walk nested <imgdir> children by name; None if any segment is missing."""
    cur = node
    for segment in path:
        nxt = None
        for child in cur:
            if child.tag == "imgdir" and child.attrib.get("name") == segment:
                nxt = child
                break
        if nxt is None:
            return None
        cur = nxt
    return cur


# --------------------------------------------------------------------------
# info/link chain + frame-delay timeline helpers
#
# These were byte-identical between analyze_npc_animation_links.py and
# export_runtime_character_sprites.py.
# --------------------------------------------------------------------------

def asset_id_from_xml(xml_path: Path) -> str:
    return xml_path.stem.replace(".img", "")


def extract_info_link(root: ET.Element) -> str | None:
    info = child_imgdir(root, "info")
    if info is None:
        return None
    for node in info:
        if node.attrib.get("name") != "link":
            continue
        if node.tag not in {"string", "int"}:
            continue
        value = str(node.attrib.get("value", "")).strip()
        if value:
            return value
    return None


def resolve_link_target_xml(current_xml: Path, link_value: str) -> Path | None:
    raw = str(link_value).strip()
    if not raw:
        return None

    base_dir = current_xml.parent
    width = len(asset_id_from_xml(current_xml))
    candidates: list[str] = []
    if raw.endswith(".img.xml"):
        candidates.append(raw)
    else:
        candidates.append(f"{raw}.img.xml")
    if raw.isdigit():
        candidates.append(f"{raw.zfill(width)}.img.xml")
        candidates.append(f"{int(raw):0{width}d}.img.xml")
        candidates.append(f"{int(raw)}.img.xml")

    seen: set[str] = set()
    for name in candidates:
        if name in seen:
            continue
        seen.add(name)
        candidate = base_dir / name
        if candidate.exists():
            return candidate
    return None


def parse_delay_ms(raw: Any) -> int | None:
    if raw is None:
        return None
    try:
        value = int(str(raw).strip())
    except Exception:
        return None
    return max(1, value)


def extract_node_delay_ms(frame_node: ET.Element) -> int | None:
    for child in frame_node:
        if child.attrib.get("name") != "delay":
            continue
        if child.tag not in {"int", "string"}:
            continue
        parsed = parse_delay_ms(child.attrib.get("value"))
        if parsed is not None:
            return parsed
    return None


def resolve_uol_target_frame(value: str) -> int | None:
    raw = str(value).strip()
    if not raw:
        return None
    if raw.isdigit():
        return int(raw)
    tokens = [tok for tok in raw.split("/") if tok not in {"", "."}]
    for token in reversed(tokens):
        if token.isdigit():
            return int(token)
    return None


def resolve_frame_delay_ms(
    frame_idx: int,
    frame_nodes: dict[int, ET.Element],
    default_delay_ms: int,
    visited: set[int] | None = None,
) -> int:
    if visited is None:
        visited = set()
    if frame_idx in visited:
        return default_delay_ms
    visited.add(frame_idx)

    frame_node = frame_nodes.get(frame_idx)
    if frame_node is None:
        return default_delay_ms

    direct = extract_node_delay_ms(frame_node)
    if direct is not None:
        return direct

    if frame_node.tag == "uol":
        target = resolve_uol_target_frame(frame_node.attrib.get("value", ""))
        if target is not None:
            return resolve_frame_delay_ms(target, frame_nodes, default_delay_ms, visited)

    return default_delay_ms


def build_timeline_from_action_node(action_node: ET.Element, default_delay_ms: int) -> list[dict[str, int]]:
    frame_nodes: dict[int, ET.Element] = {}
    for child in action_node:
        name = str(child.attrib.get("name", "")).strip()
        if not name.isdigit():
            continue
        if child.tag not in {"imgdir", "canvas", "uol"}:
            continue
        frame_nodes[int(name)] = child

    if not frame_nodes:
        return [{"frame": 0, "delay_ms": default_delay_ms}]

    timeline: list[dict[str, int]] = []
    for frame_idx in sorted(frame_nodes.keys()):
        delay_ms = resolve_frame_delay_ms(frame_idx, frame_nodes, default_delay_ms)
        timeline.append({"frame": int(frame_idx), "delay_ms": int(delay_ms)})
    return timeline


# --------------------------------------------------------------------------
# Filesystem action detection + info-string reading
#
# Duplicated between weapon_action_compatibility_report.py and
# character_tooling_gui.py.
# --------------------------------------------------------------------------

def detect_actions_in_asset_dir(asset_dir: Path) -> set[str]:
    """Action folder names under an extracted *.img dir that contain PNGs."""
    if not asset_dir.exists() or not asset_dir.is_dir():
        return set()
    actions: set[str] = set()
    for child in asset_dir.iterdir():
        if not child.is_dir():
            continue
        name = child.name
        if not name or name == "info":
            continue
        has_png = any(child.rglob("*.png"))
        if has_png:
            actions.add(name)
    return actions


def count_action_frames(asset_dir: Path, actions: Iterable[str]) -> dict[str, int]:
    """Per-action count of numeric frame folders that contain PNGs."""
    out: dict[str, int] = {}
    for action in sorted(actions):
        action_dir = asset_dir / action
        count = 0
        if action_dir.exists() and action_dir.is_dir():
            for child in action_dir.iterdir():
                if not child.is_dir():
                    continue
                if not child.name.isdigit():
                    continue
                if any(child.glob("*.png")):
                    count += 1
        out[action] = count
    return out


def read_info_strings(xml_path: Path) -> dict[str, str]:
    """All <string> fields of the top-level info imgdir; {} on any failure."""
    out: dict[str, str] = {}
    if not xml_path.exists():
        return out
    try:
        root = ET.parse(xml_path).getroot()
    except Exception:
        return out
    info_node = child_imgdir(root, "info")
    if info_node is None:
        return out
    for child in info_node:
        if child.tag == "string":
            key = child.attrib.get("name", "")
            if key:
                out[key] = child.attrib.get("value", "")
    return out


# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------

def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def safe_name(s: str) -> str:
    return "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in s).strip("_")


def write_csv(path: Path, rows: list[dict[str, Any]], headers: list[str] | None = None) -> None:
    """Write dict rows as CSV, creating parent directories.

    Two historical modes, preserved exactly:
      - ``headers`` given: always writes the header row, even for empty
        ``rows`` (build_item_catalogue.py / build_itemwz_catalogue.py /
        diff_character_assets.py / analyze_character_assets.py behavior --
        diff relies on header-only CSVs in its identity-shortcut path).
      - ``headers=None``: derive headers from the first row and write
        NOTHING when ``rows`` is empty (build_wz_index.py behavior).
    """
    if headers is None:
        if not rows:
            return
        headers = list(rows[0].keys())
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


# --------------------------------------------------------------------------
# Image helpers (Pillow imported lazily -- see module docstring)
#
# Duplicated between character_tooling_gui.py and
# export_runtime_character_sprites.py.
# --------------------------------------------------------------------------

def build_sprite_sheet(
    frame_paths: list[Path],
    output_path: Path,
    columns: int,
    cell_padding: int = 2,
) -> dict[str, Any]:
    from PIL import Image

    imgs = [Image.open(p).convert("RGBA") for p in frame_paths]
    try:
        max_w = max(im.width for im in imgs)
        max_h = max(im.height for im in imgs)
        cols = max(1, int(columns))
        rows = math.ceil(len(imgs) / cols)

        cell_w = max_w + cell_padding * 2
        cell_h = max_h + cell_padding * 2
        sheet_w = cols * cell_w
        sheet_h = rows * cell_h

        sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
        layout: list[dict[str, Any]] = []
        for i, im in enumerate(imgs):
            r = i // cols
            c = i % cols
            x = c * cell_w + cell_padding + (max_w - im.width) // 2
            y = r * cell_h + cell_padding + (max_h - im.height) // 2
            sheet.alpha_composite(im, (x, y))
            layout.append(
                {
                    "index": i,
                    "row": r,
                    "col": c,
                    "x": x,
                    "y": y,
                    "w": im.width,
                    "h": im.height,
                    "png": str(frame_paths[i]),
                }
            )

        output_path.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(output_path)
        return {
            "sheet_path": str(output_path),
            "sheet_size": [sheet_w, sheet_h],
            "cell_size": [cell_w, cell_h],
            "rows": rows,
            "cols": cols,
            "layout": layout,
        }
    finally:
        for im in imgs:
            im.close()


def normalize_action_frame_canvases(
    per_frame_rows: list[dict[str, Any]],
    *,
    sync_bounds_metadata: bool = False,
) -> dict[str, Any] | None:
    """Re-render each frame PNG onto a shared union-bounds canvas.

    The two original copies differed in exactly one way, now parameterized:
    with ``sync_bounds_metadata=True`` (export_runtime_character_sprites.py
    behavior) each row additionally gains ``effective_bounds_world`` and its
    sidecar ``json`` metadata file is rewritten to match the normalized
    canvas; with the default ``False`` (character_tooling_gui.py behavior)
    neither happens.
    """
    from PIL import Image

    rows: list[tuple[dict[str, Any], Path, dict[str, Any]]] = []
    for row in per_frame_rows:
        png_raw = row.get("png")
        bounds = row.get("frame_bounds_world")
        if not isinstance(png_raw, str) or not png_raw:
            continue
        if not isinstance(bounds, dict):
            continue
        if not all(k in bounds for k in ("left", "top", "right", "bottom")):
            continue
        png_path = Path(png_raw)
        if not png_path.exists():
            continue
        rows.append((row, png_path, bounds))

    if len(rows) <= 1:
        return None

    left = min(int(bounds["left"]) for _, _, bounds in rows)
    top = min(int(bounds["top"]) for _, _, bounds in rows)
    right = max(int(bounds["right"]) for _, _, bounds in rows)
    bottom = max(int(bounds["bottom"]) for _, _, bounds in rows)
    width = right - left
    height = bottom - top
    if width <= 0 or height <= 0:
        return None

    normalized = 0
    for row, png_path, bounds in rows:
        src = Image.open(png_path).convert("RGBA")
        canvas = None
        try:
            canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            dx = int(bounds["left"]) - left
            dy = int(bounds["top"]) - top
            canvas.alpha_composite(src, (dx, dy))
            canvas.save(png_path)
            row["normalized_canvas_offset"] = {"x": dx, "y": dy}
            row["normalized_canvas_size"] = [width, height]
            if sync_bounds_metadata:
                row["effective_bounds_world"] = {
                    "left": left,
                    "top": top,
                    "right": right,
                    "bottom": bottom,
                }
                # Keep frame metadata in sync with normalized canvas so runtime
                # face overlay placement (derived from frame_bounds_world + draw_order)
                # remains pixel-accurate after re-centering.
                json_raw = row.get("json")
                if isinstance(json_raw, str) and json_raw:
                    json_path = Path(json_raw)
                    if json_path.exists():
                        try:
                            payload = json.loads(json_path.read_text(encoding="utf-8"))
                            if isinstance(payload, dict):
                                payload["frame_bounds_world"] = {
                                    "left": left,
                                    "top": top,
                                    "right": right,
                                    "bottom": bottom,
                                }
                                payload["normalized_canvas_offset"] = {"x": dx, "y": dy}
                                payload["normalized_canvas_size"] = [width, height]
                                json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
                        except Exception:
                            # Non-fatal; image normalization still succeeded.
                            pass
            normalized += 1
        finally:
            src.close()
            if canvas is not None:
                canvas.close()

    return {
        "enabled": True,
        "normalized_frames": normalized,
        "bounds_world": {"left": left, "top": top, "right": right, "bottom": bottom},
        "size": [width, height],
    }
