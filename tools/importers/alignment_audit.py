#!/usr/bin/env python3
"""Alignment and animation audit for MapleStory batch-render metadata."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Optional, Tuple
import xml.etree.ElementTree as ET

from wz_shared import utc_now_iso, write_csv


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return default


def _to_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default


def _counter_to_dict(counter: Counter) -> dict[str, int]:
    return {str(k): int(v) for k, v in counter.most_common()}


def _taxonomy_from_unresolved(row: dict) -> str:
    if row.get("missing_action_node"):
        return "missing_action_node"
    if "missing_png" in row:
        return "missing_png"
    if "xml" in row and "kind" in row:
        return "missing_xml"
    return "other_unresolved"


def _reason_taxonomy(reason: str) -> str:
    if reason.startswith("unresolved="):
        return "unresolved_filter"
    if reason.startswith("fallbacks="):
        return "fallback_filter"
    if reason.startswith("layers="):
        return "min_layers_filter"
    if reason.startswith("render_error:"):
        return "render_error"
    return "other_skip_reason"


def _anchor_threshold(anchor: str, base: float) -> float:
    if anchor in {"hand", "handMove", "muzzle"}:
        return base * 2.0
    return base


def _is_virtual_anchor(anchor: str) -> bool:
    return anchor in {"asset_origin_inherit", "hand_proxy_from_navel"}


def _is_dynamic_action(action: str) -> bool:
    a = action.lower()
    dynamic_prefixes = (
        "swing",
        "stab",
        "shoot",
        "prone",
        "jump",
        "fly",
        "heal",
        "rush",
        "dash",
        "blast",
        "combo",
    )
    return a.startswith(dynamic_prefixes)


@dataclass
class Finding:
    severity: str
    category: str
    message: str
    action: str = ""
    frame: str = ""
    asset_kind: str = ""
    metric: str = ""
    value: str = ""
    threshold: str = ""
    evidence: str = ""


class XmlIndex:
    def __init__(self, xml_path: Path):
        self.xml_path = xml_path
        self.root = ET.parse(xml_path).getroot()
        self.index: dict[Tuple[str, ...], ET.Element] = {}
        root_name = self.root.attrib.get("name", xml_path.stem)
        self._index_tree(self.root, (root_name,))

    def _index_tree(self, node: ET.Element, path: Tuple[str, ...]) -> None:
        self.index[path] = node
        for child in node:
            name = child.attrib.get("name")
            if name:
                self._index_tree(child, path + (name,))

    def canvas_meta(self, node_path: str) -> Optional[dict]:
        parts = tuple(p for p in node_path.split("/") if p)
        node = self.index.get(parts)
        if node is None or node.tag != "canvas":
            return None
        origin = (0, 0)
        anchors: set[str] = set()
        z = ""
        for child in node:
            if child.tag == "vector" and child.attrib.get("name") == "origin":
                origin = (
                    _to_int(child.attrib.get("x", "0")),
                    _to_int(child.attrib.get("y", "0")),
                )
            elif child.tag == "imgdir" and child.attrib.get("name") == "map":
                for vec in child:
                    if vec.tag == "vector" and vec.attrib.get("name"):
                        anchors.add(vec.attrib["name"])
            elif child.tag == "string" and child.attrib.get("name") == "z":
                z = child.attrib.get("value", "")
        return {
            "origin": [origin[0], origin[1]],
            "anchors": sorted(anchors),
            "z": z,
        }


def run_alignment_audit(
    batch_summary_path: Path,
    base_wz: Path,
    out_dir: Path,
    max_jitter_px: float = 6.0,
    max_fallback_rate: float = 0.35,
    allow_origin_fallback_kinds: Optional[Iterable[str]] = None,
) -> dict:
    if allow_origin_fallback_kinds is None:
        allow_origin_fallback_kinds = ("body",)

    allow_origin_set = {str(x).strip().lower() for x in allow_origin_fallback_kinds if str(x).strip()}
    if not batch_summary_path.exists():
        raise FileNotFoundError(f"Batch summary not found: {batch_summary_path}")
    if not base_wz.exists():
        raise FileNotFoundError(f"Base.wz path not found: {base_wz}")

    out_dir.mkdir(parents=True, exist_ok=True)
    summary = json.loads(batch_summary_path.read_text(encoding="utf-8"))

    findings: list[Finding] = []
    xml_cache: dict[Path, XmlIndex] = {}

    anchor_usage = Counter()
    anchor_usage_by_kind: dict[str, Counter] = defaultdict(Counter)
    draw_count_by_kind = Counter()
    origin_fallback_by_kind = Counter()
    multi_anchor_combo_counts = Counter()
    multi_anchor_by_kind = Counter()
    fallback_mode_counts = Counter()
    unresolved_taxonomy = Counter()
    skipped_reason_counts = Counter()

    action_metrics: dict[str, dict] = {}
    stability_points: dict[str, dict[tuple, list[dict]]] = defaultdict(lambda: defaultdict(list))
    z_sets_by_action_sig: dict[str, dict[tuple, set[str]]] = defaultdict(lambda: defaultdict(set))

    actions = summary.get("actions", []) or []
    for action_row in actions:
        action = str(action_row.get("action", ""))
        skipped = action_row.get("skipped_frames", []) or []
        skip_counter = Counter()
        for row in skipped:
            reason = str(row.get("reason", ""))
            if reason:
                skip_counter[reason] += 1
                skipped_reason_counts[reason] += 1
        action_metrics[action] = {
            "status": str(action_row.get("status", "")),
            "frames_listed": len(action_row.get("frames", []) or []),
            "frames_with_metadata": 0,
            "frames_missing_metadata": 0,
            "total_assets": 0,
            "fallback_assets": 0,
            "frame_fallback_counts": [],
            "drawn_layers": [],
            "unresolved_entries": 0,
            "frames_with_unresolved": 0,
            "skip_reason_counts": skip_counter,
            "origin_fallback_count": 0,
            "draw_order_rows": 0,
            "fallback_mode_counts": Counter(),
        }

    missing_frame_json: list[str] = []
    parsed_frame_count = 0

    for action_row in actions:
        action = str(action_row.get("action", ""))
        frame_rows = action_row.get("frames", []) or []
        for frame_row in frame_rows:
            png_raw = str(frame_row.get("png", "")).strip()
            if not png_raw:
                continue
            png_path = Path(png_raw)
            meta_path = png_path.with_suffix(".json")
            if not meta_path.exists():
                action_metrics[action]["frames_missing_metadata"] += 1
                missing_frame_json.append(str(meta_path))
                continue

            frame_meta = json.loads(meta_path.read_text(encoding="utf-8"))
            parsed_frame_count += 1
            action_metrics[action]["frames_with_metadata"] += 1

            action_resolution = frame_meta.get("action_resolution", []) or []
            action_fallbacks = frame_meta.get("action_fallbacks", []) or []
            unresolved_rows = frame_meta.get("unresolved", []) or []
            draw_order = frame_meta.get("draw_order", []) or []
            frame_idx = _to_int(frame_meta.get("frame", frame_row.get("frame", 0)))

            action_metrics[action]["total_assets"] += len(action_resolution)
            action_metrics[action]["fallback_assets"] += len(action_fallbacks)
            action_metrics[action]["frame_fallback_counts"].append(len(action_fallbacks))
            action_metrics[action]["drawn_layers"].append(_to_int(frame_meta.get("drawn_layers", 0)))
            action_metrics[action]["unresolved_entries"] += len(unresolved_rows)
            action_metrics[action]["draw_order_rows"] += len(draw_order)
            action_metrics[action]["fallback_mode_counts"].update(
                str(x.get("selection_mode", "")) for x in action_fallbacks if x.get("selection_mode")
            )

            for fb in action_fallbacks:
                mode = str(fb.get("selection_mode", ""))
                if mode:
                    fallback_mode_counts[mode] += 1

            if unresolved_rows:
                action_metrics[action]["frames_with_unresolved"] += 1
            for unr in unresolved_rows:
                tax = _taxonomy_from_unresolved(unr)
                unresolved_taxonomy[tax] += 1

            assets_loaded = frame_meta.get("assets_loaded", []) or []
            asset_xml_map: dict[tuple[str, int], Path] = {}
            for row in assets_loaded:
                kind = str(row.get("kind", ""))
                part_id = _to_int(row.get("part_id", 0))
                xml_raw = str(row.get("xml", ""))
                if kind and part_id and xml_raw:
                    asset_xml_map[(kind, part_id)] = Path(xml_raw)

            for row in draw_order:
                kind = str(row.get("asset_kind", ""))
                part_id = _to_int(row.get("part_id", 0))
                z = str(row.get("z", ""))
                anchor = str(row.get("used_anchor", ""))
                node_path = str(row.get("node_path", ""))
                top_left_raw = row.get("top_left", [0, 0])
                if isinstance(top_left_raw, list) and len(top_left_raw) >= 2:
                    top_left = (_to_int(top_left_raw[0]), _to_int(top_left_raw[1]))
                else:
                    top_left = (0, 0)

                draw_count_by_kind[kind] += 1
                anchor_usage[anchor] += 1
                anchor_usage_by_kind[kind][anchor] += 1

                if anchor == "origin_fallback":
                    origin_fallback_by_kind[kind] += 1
                    action_metrics[action]["origin_fallback_count"] += 1

                canvas_meta = None
                xml_path = asset_xml_map.get((kind, part_id))
                if xml_path and xml_path.exists():
                    if xml_path not in xml_cache:
                        xml_cache[xml_path] = XmlIndex(xml_path)
                    canvas_meta = xml_cache[xml_path].canvas_meta(node_path)

                anchors = set()
                if canvas_meta is not None:
                    anchors = set(canvas_meta.get("anchors", []))
                    if len(anchors) > 1:
                        combo_key = "+".join(sorted(anchors))
                        multi_anchor_combo_counts[combo_key] += 1
                        multi_anchor_by_kind[kind] += 1
                    if (
                        anchors
                        and anchor
                        and anchor != "origin_fallback"
                        and not _is_virtual_anchor(anchor)
                        and anchor not in anchors
                    ):
                        findings.append(
                            Finding(
                                severity="medium",
                                category="anchor_mismatch",
                                action=action,
                                frame=str(frame_idx),
                                asset_kind=kind,
                                metric="used_anchor_not_in_canvas_map",
                                value=anchor,
                                threshold="in-canvas anchors",
                                message=(
                                    f"Used anchor '{anchor}' is not present on node map anchors."
                                ),
                                evidence=json.dumps(
                                    {"node_path": node_path, "anchors": sorted(anchors)},
                                    ensure_ascii=False,
                                ),
                            )
                        )

                node_leaf = node_path.split("/")[-1] if node_path else ""
                sig = (kind, part_id, node_leaf)
                stability_points[action][sig].append(
                    {
                        "frame": frame_idx,
                        "top_left": top_left,
                        "anchor": anchor,
                        "node_path": node_path,
                        "z": z,
                    }
                )
                if z:
                    z_sets_by_action_sig[action][sig].add(z)

            hp = frame_meta.get("hair_policy", {}) or {}
            cap_state = hp.get("cap_state", {}) or {}
            if cap_state.get("has_cap"):
                removed_layers = _to_int(hp.get("removed_layers", 0))
                if cap_state.get("full_hair_mask") and removed_layers == 0:
                    findings.append(
                        Finding(
                            severity="high",
                            category="cap_hair_policy",
                            action=action,
                            frame=str(frame_idx),
                            metric="full_mask_without_hair_removal",
                            value=str(removed_layers),
                            threshold=">0 removed layers",
                            message="Cap advertises full hair mask but no hair layers were removed.",
                            evidence=json.dumps(cap_state, ensure_ascii=False),
                        )
                    )

    # Aggregate skipped reasons and action compatibility findings.
    for action, stats in action_metrics.items():
        total_assets = _to_int(stats["total_assets"], 0)
        fallback_assets = _to_int(stats["fallback_assets"], 0)
        fallback_rate = (fallback_assets / total_assets) if total_assets > 0 else 0.0
        stats["fallback_rate"] = fallback_rate

        if fallback_rate > max_fallback_rate and total_assets > 0:
            severity = "high" if fallback_rate > (max_fallback_rate * 2.0) else "medium"
            findings.append(
                Finding(
                    severity=severity,
                    category="action_compatibility",
                    action=action,
                    metric="fallback_rate",
                    value=f"{fallback_rate:.3f}",
                    threshold=f"<= {max_fallback_rate:.3f}",
                    message=(
                        f"Fallback rate is high for action '{action}' ({fallback_assets}/{total_assets} assets)."
                    ),
                    evidence=json.dumps(_counter_to_dict(stats["fallback_mode_counts"]), ensure_ascii=False),
                )
            )

        if stats["status"] == "no_valid_frames":
            top_reason = ""
            if stats["skip_reason_counts"]:
                top_reason = stats["skip_reason_counts"].most_common(1)[0][0]
            findings.append(
                Finding(
                    severity="high",
                    category="action_coverage",
                    action=action,
                    metric="no_valid_frames",
                    value=str(stats["frames_listed"]),
                    threshold=">0 valid frames",
                    message=f"Action '{action}' ended with no valid frames after filtering.",
                    evidence=top_reason,
                )
            )

        if stats["frames_missing_metadata"] > 0:
            findings.append(
                Finding(
                    severity="medium",
                    category="metadata_coverage",
                    action=action,
                    metric="missing_frame_metadata",
                    value=str(stats["frames_missing_metadata"]),
                    threshold="0",
                    message=f"Frame metadata JSON files are missing for action '{action}'.",
                )
            )

        row_count = _to_int(stats["draw_order_rows"], 0)
        origin_fallback_count = _to_int(stats["origin_fallback_count"], 0)
        if row_count > 0 and origin_fallback_count > 0:
            origin_rate = origin_fallback_count / row_count
            stats["origin_fallback_rate"] = origin_rate
            if "body" not in allow_origin_set and origin_fallback_count > 0:
                findings.append(
                    Finding(
                        severity="medium",
                        category="anchor_quality",
                        action=action,
                        metric="origin_fallback_rate",
                        value=f"{origin_rate:.3f}",
                        threshold="0",
                        message="Origin fallback occurred but 'body' is not in allow list.",
                    )
                )

    # Kind-level origin fallback checks.
    for kind, count in origin_fallback_by_kind.items():
        draws = draw_count_by_kind.get(kind, 0)
        rate = (count / draws) if draws else 0.0
        allowed = kind.lower() in allow_origin_set
        if count > 0 and not allowed:
            findings.append(
                Finding(
                    severity="medium",
                    category="anchor_quality",
                    asset_kind=kind,
                    metric="origin_fallback_rate",
                    value=f"{rate:.3f}",
                    threshold="0",
                    message=f"Origin fallback observed for non-allowed asset kind '{kind}'.",
                    evidence=json.dumps({"count": count, "draws": draws}, ensure_ascii=False),
                )
            )
        elif count > 0 and allowed and rate > 0.10:
            findings.append(
                Finding(
                    severity="low",
                    category="anchor_quality",
                    asset_kind=kind,
                    metric="origin_fallback_rate",
                    value=f"{rate:.3f}",
                    threshold="<= 0.10",
                    message=f"Origin fallback rate is elevated for allowed kind '{kind}'.",
                    evidence=json.dumps({"count": count, "draws": draws}, ensure_ascii=False),
                )
            )

    # Positional stability and z-volatility checks.
    jitter_stats_by_action: dict[str, dict[str, float | int]] = {}
    for action, sig_map in stability_points.items():
        pairs_checked = 0
        pairs_exceeded = 0
        max_delta = 0.0
        dynamic_action = _is_dynamic_action(action)

        for sig, points in sig_map.items():
            points_sorted = sorted(points, key=lambda x: (_to_int(x["frame"]), x["node_path"]))
            z_set = z_sets_by_action_sig[action].get(sig, set())
            if len(z_set) > 1:
                findings.append(
                    Finding(
                        severity="low",
                        category="layer_consistency",
                        action=action,
                        asset_kind=str(sig[0]),
                        metric="z_volatility",
                        value=str(len(z_set)),
                        threshold="1",
                        message="Node signature uses multiple z layers across frames.",
                        evidence=json.dumps(
                            {"signature": [str(x) for x in sig], "z_layers": sorted(z_set)},
                            ensure_ascii=False,
                        ),
                    )
                )

            for i in range(1, len(points_sorted)):
                prev = points_sorted[i - 1]
                cur = points_sorted[i]
                prev_frame = _to_int(prev["frame"])
                cur_frame = _to_int(cur["frame"])
                if cur_frame - prev_frame != 1:
                    continue
                p0 = prev["top_left"]
                p1 = cur["top_left"]
                dx = _to_float(p1[0]) - _to_float(p0[0])
                dy = _to_float(p1[1]) - _to_float(p0[1])
                dist = math.hypot(dx, dy)
                anchor = str(cur.get("anchor", ""))
                threshold = _anchor_threshold(anchor, max_jitter_px)
                if dynamic_action:
                    # Attack/mobility actions have intentionally large frame deltas.
                    threshold *= 4.0
                if anchor == "hand_proxy_from_navel":
                    # Hand-proxy weapon placement intentionally amplifies delta
                    # when combat arcs move the hand quickly.
                    threshold *= 2.0
                pairs_checked += 1
                if dist > max_delta:
                    max_delta = dist
                if dist > threshold:
                    pairs_exceeded += 1
                    severity = "medium" if dist > (threshold * 1.6) else "low"
                    findings.append(
                        Finding(
                            severity=severity,
                            category="positional_stability",
                            action=action,
                            frame=str(cur_frame),
                            asset_kind=str(sig[0]),
                            metric="top_left_delta_px",
                            value=f"{dist:.2f}",
                            threshold=f"<= {threshold:.2f}",
                            message="Frame-to-frame position delta exceeds jitter threshold.",
                            evidence=json.dumps(
                                {
                                    "signature": [str(x) for x in sig],
                                    "from_frame": prev_frame,
                                    "to_frame": cur_frame,
                                    "dx": round(dx, 3),
                                    "dy": round(dy, 3),
                                    "anchor": anchor,
                                },
                                ensure_ascii=False,
                            ),
                        )
                    )

        exceed_rate = (pairs_exceeded / pairs_checked) if pairs_checked else 0.0
        jitter_stats_by_action[action] = {
            "pairs_checked": pairs_checked,
            "pairs_exceeded": pairs_exceeded,
            "exceed_rate": round(exceed_rate, 4),
            "max_delta_px": round(max_delta, 3),
        }

    # Aggregate skipped reason findings.
    for reason, count in skipped_reason_counts.most_common():
        taxonomy = _reason_taxonomy(reason)
        if taxonomy in {"unresolved_filter", "render_error"} and count > 0:
            severity = "high" if taxonomy == "render_error" else "medium"
            findings.append(
                Finding(
                    severity=severity,
                    category="batch_filtering",
                    metric=taxonomy,
                    value=str(count),
                    threshold="0",
                    message=f"Batch skipped frames due to '{reason}'.",
                )
            )

    # Build report payload.
    severity_counts = Counter(f.severity for f in findings)
    category_counts = Counter(f.category for f in findings)

    findings_rows: list[dict[str, Any]] = [
        {
            "severity": f.severity,
            "category": f.category,
            "action": f.action,
            "frame": f.frame,
            "asset_kind": f.asset_kind,
            "metric": f.metric,
            "value": f.value,
            "threshold": f.threshold,
            "message": f.message,
            "evidence": f.evidence,
        }
        for f in findings
    ]
    report = {
        "generated_at_utc": utc_now_iso(),
        "inputs": {
            "batch_summary_path": str(batch_summary_path),
            "base_wz": str(base_wz),
            "out_dir": str(out_dir),
            "max_jitter_px": max_jitter_px,
            "max_fallback_rate": max_fallback_rate,
            "allow_origin_fallback_kinds": sorted(allow_origin_set),
        },
        "batch_context": {
            "mode": summary.get("mode"),
            "action_count": len(actions),
            "total_frames": _to_int(summary.get("total_frames", 0)),
            "total_skipped_frames": _to_int(summary.get("total_skipped_frames", 0)),
            "quality_filter": summary.get("quality_filter", {}),
        },
        "coverage": {
            "parsed_frame_metadata_count": parsed_frame_count,
            "missing_frame_metadata_count": len(missing_frame_json),
            "missing_frame_metadata_examples": missing_frame_json[:30],
        },
        "metrics": {
            "severity_counts": _counter_to_dict(severity_counts),
            "category_counts": _counter_to_dict(category_counts),
            "anchor_usage_overall": _counter_to_dict(anchor_usage),
            "anchor_usage_by_kind": {k: _counter_to_dict(v) for k, v in sorted(anchor_usage_by_kind.items())},
            "origin_fallback_by_kind": _counter_to_dict(origin_fallback_by_kind),
            "multi_anchor_combo_counts": _counter_to_dict(multi_anchor_combo_counts),
            "multi_anchor_by_kind": _counter_to_dict(multi_anchor_by_kind),
            "fallback_mode_counts": _counter_to_dict(fallback_mode_counts),
            "unresolved_taxonomy": _counter_to_dict(unresolved_taxonomy),
            "skipped_reason_counts": _counter_to_dict(skipped_reason_counts),
            "jitter_stats_by_action": jitter_stats_by_action,
            "action_metrics": {
                action: {
                    "status": stats["status"],
                    "frames_listed": stats["frames_listed"],
                    "frames_with_metadata": stats["frames_with_metadata"],
                    "frames_missing_metadata": stats["frames_missing_metadata"],
                    "total_assets": stats["total_assets"],
                    "fallback_assets": stats["fallback_assets"],
                    "fallback_rate": round(_to_float(stats.get("fallback_rate", 0.0)), 4),
                    "frames_with_unresolved": stats["frames_with_unresolved"],
                    "unresolved_entries": stats["unresolved_entries"],
                    "skip_reason_counts": _counter_to_dict(stats["skip_reason_counts"]),
                    "fallback_mode_counts": _counter_to_dict(stats["fallback_mode_counts"]),
                    "origin_fallback_count": stats["origin_fallback_count"],
                    "origin_fallback_rate": round(_to_float(stats.get("origin_fallback_rate", 0.0)), 4),
                    "drawn_layers_min": min(stats["drawn_layers"]) if stats["drawn_layers"] else None,
                    "drawn_layers_max": max(stats["drawn_layers"]) if stats["drawn_layers"] else None,
                    "drawn_layers_avg": (
                        round(sum(stats["drawn_layers"]) / len(stats["drawn_layers"]), 3)
                        if stats["drawn_layers"]
                        else None
                    ),
                }
                for action, stats in sorted(action_metrics.items())
            },
        },
        "findings": findings_rows,
    }

    report_path = out_dir / "alignment_audit_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    findings_csv = out_dir / "alignment_findings.csv"
    write_csv(
        findings_csv,
        findings_rows,
        [
            "severity",
            "category",
            "action",
            "frame",
            "asset_kind",
            "metric",
            "value",
            "threshold",
            "message",
            "evidence",
        ],
    )

    top_findings = findings_rows[:20]
    summary_md = out_dir / "alignment_summary.md"
    lines = [
        "# Alignment Audit Summary",
        "",
        f"- Generated: {report['generated_at_utc']}",
        f"- Batch summary: `{batch_summary_path}`",
        f"- Parsed frame metadata files: **{parsed_frame_count}**",
        f"- Missing frame metadata files: **{len(missing_frame_json)}**",
        "",
        "## Finding Counts",
        "",
    ]
    if severity_counts:
        for sev, cnt in severity_counts.most_common():
            lines.append(f"- **{sev}**: {cnt}")
    else:
        lines.append("- No findings.")

    lines += [
        "",
        "## Top Categories",
        "",
    ]
    if category_counts:
        for cat, cnt in category_counts.most_common(8):
            lines.append(f"- `{cat}`: {cnt}")
    else:
        lines.append("- None")

    lines += [
        "",
        "## Anchor Usage (Top)",
        "",
    ]
    if anchor_usage:
        for name, cnt in anchor_usage.most_common(8):
            lines.append(f"- `{name}`: {cnt}")
    else:
        lines.append("- No draw-order anchor data found.")

    lines += [
        "",
        "## Skipped Reason Counts",
        "",
    ]
    if skipped_reason_counts:
        for reason, cnt in skipped_reason_counts.most_common(8):
            lines.append(f"- `{reason}`: {cnt}")
    else:
        lines.append("- No skipped-frame reasons in batch summary.")

    lines += [
        "",
        "## Notable Findings",
        "",
    ]
    if top_findings:
        for row in top_findings:
            loc = ""
            if row["action"]:
                loc = f" action={row['action']}"
            if row["frame"]:
                loc += f" frame={row['frame']}"
            if row["asset_kind"]:
                loc += f" kind={row['asset_kind']}"
            lines.append(
                f"- **{row['severity']}** `{row['category']}`{loc}: {row['message']}"
            )
    else:
        lines.append("- None")

    summary_md.write_text("\n".join(lines), encoding="utf-8")

    return {
        "status": "ok",
        "report_path": str(report_path),
        "findings_csv": str(findings_csv),
        "summary_md": str(summary_md),
        "finding_count": len(findings),
        "severity_counts": _counter_to_dict(severity_counts),
        "parsed_frame_metadata_count": parsed_frame_count,
        "missing_frame_metadata_count": len(missing_frame_json),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch-summary", required=True, help="Path to batch summary JSON")
    parser.add_argument("--base-wz", required=True, help="Path to extracted Base.wz")
    parser.add_argument("--out-dir", required=True, help="Output directory for audit artifacts")
    parser.add_argument("--max-jitter-px", type=float, default=6.0, help="Maximum allowed frame delta in pixels")
    parser.add_argument(
        "--max-fallback-rate",
        type=float,
        default=0.35,
        help="Action-level fallback-rate warning threshold",
    )
    parser.add_argument(
        "--allow-origin-fallback-kinds",
        default="body",
        help="Comma-separated list of asset kinds allowed to use origin_fallback (default: body)",
    )
    args = parser.parse_args()

    allow_kinds = [x.strip() for x in args.allow_origin_fallback_kinds.split(",") if x.strip()]
    result = run_alignment_audit(
        batch_summary_path=Path(args.batch_summary),
        base_wz=Path(args.base_wz),
        out_dir=Path(args.out_dir),
        max_jitter_px=args.max_jitter_px,
        max_fallback_rate=args.max_fallback_rate,
        allow_origin_fallback_kinds=allow_kinds,
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
