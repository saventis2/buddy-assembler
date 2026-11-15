#!/usr/bin/env python3
"""Batch-export operation for the character tooling, importable without tkinter.

Backlog #44: the worker-thread body of ``character_tooling_gui.App.
on_batch_export`` (plus its two output-path helpers) lives here as
``run_batch_export`` so the future headless CLI (backlog #47) can drive the
same export pipeline the GUI uses. The loop body is a direct lift of the
original closure; the only transformation is parametrization:

- every ``self.batch_*.get()`` tk-variable read became an explicit keyword
  argument (the GUI snapshots them at worker-thread start, the same thread
  and moment the closure previously began reading them);
- ``self.after(0, lambda ...: self._append_batch_log(...))`` became
  ``log(...)`` with the identical message string (the GUI passes a ``log``
  callback that marshals onto the tk main loop via ``self.after``, exactly
  as before);
- ``render`` is injectable via ``render_fn`` (defaults to the real renderer)
  so the orchestration is unit-testable without WZ data.

Output files, summary JSON structure, and log lines are unchanged.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Callable, Optional

from render_character_frame import render
from character_tooling_core import (
    build_character_identifier,
    build_gif,
    detect_action_timeline,
    detect_actions_for_loadout,
    weapon_action_profile,
)
from wz_shared import build_sprite_sheet, normalize_action_frame_canvases


def resolve_batch_character_out_dir(
    base_out_dir: Path,
    id_kwargs: dict,
    *,
    use_character_folder: bool,
    character_id_raw: str,
) -> tuple[Path, Optional[str]]:
    if not use_character_folder:
        return base_out_dir, None
    character_id = character_id_raw if character_id_raw else build_character_identifier(id_kwargs)
    return base_out_dir / f"char_{character_id}", character_id


def resolve_single_action_postprocess_path(
    raw_path: str,
    *,
    out_dir: Path,
    base_out_dir: Path,
    default_name: str,
    use_character_folder: bool,
) -> Path:
    raw = raw_path.strip()
    candidate = Path(raw) if raw else (out_dir / default_name)
    if not candidate.is_absolute():
        return out_dir / candidate

    if use_character_folder:
        try:
            if candidate.parent.resolve() == base_out_dir.resolve():
                return out_dir / candidate.name
        except Exception:
            pass
    return candidate


def run_batch_export(
    *,
    base_wz: Path,
    base_out_dir: Path,
    prefix: str,
    id_kwargs: dict,
    all_actions: bool,
    action_source: str,
    single_action: str,
    auto_frames: bool,
    start_frame: int,
    end_frame: int,
    z_draw_order: str,
    hair_mode: str,
    use_character_folder: bool,
    character_id_raw: str,
    write_json: bool,
    use_action_delays: bool,
    normalize_canvas: bool,
    make_gif: bool,
    gif_path_raw: str,
    gif_duration_ms: int,
    make_sheet: bool,
    sheet_path_raw: str,
    sheet_cols: int,
    skip_unresolved: bool,
    min_layers: int,
    skill_id: Optional[int],
    skill_anim: str,
    log: Callable[[str], None],
    render_fn: Callable[..., dict] = render,
) -> dict:
    base_out_dir.mkdir(parents=True, exist_ok=True)
    base_id = int(id_kwargs["base_id"])
    weapon_profile = None
    weapon_id = id_kwargs.get("weapon_id")
    if weapon_id is not None:
        weapon_profile = weapon_action_profile(base_wz=base_wz, weapon_id=int(weapon_id))
    out_dir, character_id = resolve_batch_character_out_dir(
        base_out_dir,
        id_kwargs,
        use_character_folder=use_character_folder,
        character_id_raw=character_id_raw,
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    log(
        f"Batch character scope: out_dir={str(out_dir)}"
        + (f" character_id={character_id}" if character_id else "")
    )
    if weapon_profile is not None:
        log(
            "Weapon compatibility: "
            f"id={weapon_profile['weapon_id']} type={weapon_profile['weapon_type_code']} "
            f"afterImage={weapon_profile.get('info', {}).get('afterImage', '')} "
            f"supported_actions={len(weapon_profile.get('supported_actions', []))}"
        )
    if skill_id is not None:
        log(f"Skill overlay enabled: skill_id={skill_id} branch={skill_anim}")

    if all_actions:
        actions = detect_actions_for_loadout(
            base_wz=base_wz,
            id_kwargs=id_kwargs,
            mode=action_source,
        )
        log(
            f"All-actions mode using '{action_source}': {len(actions)} compatible actions detected."
        )
    else:
        actions = [single_action]
        if weapon_profile is not None:
            action_name = actions[0] if actions else ""
            if action_name and action_name not in set(weapon_profile.get("supported_actions", [])):
                log(
                    f"Warning: action '{action_name}' is not supported by weapon "
                    f"{weapon_profile['weapon_id']}; output may omit weapon."
                )

    all_actions_summary = []
    total_frames = 0
    total_skipped_frames = 0
    max_fallbacks_all_actions = 2
    default_delay_ms = gif_duration_ms
    for action in actions:
        if not action:
            continue
        if auto_frames:
            timeline = detect_action_timeline(
                base_wz,
                base_id,
                action,
                default_delay_ms=default_delay_ms,
            )
            frame_list = [int(row["frame"]) for row in timeline]
            frame_delay_map = {int(row["frame"]): int(row["delay_ms"]) for row in timeline}
        else:
            frame_list = list(range(start_frame, end_frame + 1))
            frame_delay_map = {f: default_delay_ms for f in frame_list}
        if not frame_list:
            log(f"Skipped action '{action}' (no frames found).")
            continue

        action_dir = out_dir / action
        action_dir.mkdir(parents=True, exist_ok=True)

        frame_pngs = []
        per_frame = []
        skipped_frames = []
        action_errors: list[str] = []
        for frame in frame_list:
            png_path = action_dir / f"{prefix}_{action}_{frame:03d}.png"
            json_path = (
                action_dir / f"{prefix}_{action}_{frame:03d}.json"
                if write_json
                else None
            )
            try:
                meta = render_fn(
                    base_wz=base_wz,
                    output_png=png_path,
                    action=action,
                    frame=frame,
                    output_json=json_path,
                    z_draw_order=z_draw_order,
                    hair_mode=hair_mode,
                    skill_id=skill_id,
                    skill_anim=skill_anim,
                    **id_kwargs,
                )
            except Exception as exc:  # noqa: BLE001
                err = f"render_error: {exc}"
                skipped_frames.append(
                    {
                        "frame": frame,
                        "png": str(png_path),
                        "reason": err,
                        "drawn_layers": 0,
                        "unresolved_count": 0,
                    }
                )
                action_errors.append(err)
                total_skipped_frames += 1
                log(f"Skipped {action} frame {frame}: {err}")
                continue
            unresolved_count = len(meta["unresolved"])
            drawn_layers = int(meta["drawn_layers"])
            fallback_count = int(meta.get("action_fallback_count", 0))
            weapon_sel_mode = ""
            weapon_entry_count = 0
            for row in meta.get("action_resolution", []):
                if str(row.get("asset_kind")) == "weapon":
                    weapon_sel_mode = str(row.get("selection_mode", ""))
                    weapon_entry_count = int(row.get("entry_count", 0) or 0)
                    break
            effective_min_layers = min_layers
            if weapon_sel_mode == "no_render_node" and weapon_entry_count == 0:
                # Keep climbing/idle sets even when this weapon family
                # intentionally has no drawable node for the action.
                effective_min_layers = max(1, min_layers - 1)

            skip_reason = None
            if skip_unresolved and unresolved_count > 0:
                skip_reason = f"unresolved={unresolved_count}"
            elif drawn_layers < effective_min_layers:
                skip_reason = f"layers={drawn_layers} (<{effective_min_layers})"
            elif all_actions and fallback_count > max_fallbacks_all_actions:
                skip_reason = f"fallbacks={fallback_count} (>{max_fallbacks_all_actions})"

            if skip_reason is not None:
                skipped_frames.append(
                    {
                        "frame": frame,
                        "png": str(png_path),
                        "reason": skip_reason,
                        "drawn_layers": drawn_layers,
                        "unresolved_count": unresolved_count,
                        "action_fallback_count": fallback_count,
                        "effective_min_layers": effective_min_layers,
                        "weapon_selection_mode": weapon_sel_mode,
                        "weapon_entry_count": weapon_entry_count,
                    }
                )
                total_skipped_frames += 1
                # Remove failed-quality outputs to avoid confusing the final set.
                try:
                    if png_path.exists():
                        png_path.unlink()
                    if json_path is not None and json_path.exists():
                        json_path.unlink()
                except Exception:
                    pass
                log(f"Skipped {action} frame {frame}: {skip_reason}")
                continue

            frame_pngs.append(png_path)
            delay_ms = int(frame_delay_map.get(frame, default_delay_ms))
            world_anchors = meta.get("world_anchors", {})
            per_frame.append(
                {
                    "frame": frame,
                    "png": str(png_path),
                    "json": str(json_path) if json_path is not None else None,
                    "delay_ms": delay_ms,
                    "drawn_layers": drawn_layers,
                    "unresolved_count": unresolved_count,
                    "action_fallback_count": fallback_count,
                    "effective_min_layers": effective_min_layers,
                    "weapon_selection_mode": weapon_sel_mode,
                    "weapon_entry_count": weapon_entry_count,
                    "frame_bounds_world": meta.get("frame_bounds_world"),
                    "world_anchors": world_anchors,
                    "selection_modes": {
                        str(r.get("asset_kind")): {
                            "selection_mode": r.get("selection_mode"),
                            "selected_action": r.get("selected_action"),
                            "selected_frame": r.get("selected_frame"),
                        }
                        for r in meta.get("action_resolution", [])
                    },
                }
            )
            log(f"Rendered {action} frame {frame}")

        gif_info = None
        gif_error = None
        sheet_info = None
        sheet_error = None
        normalization_info = None
        action_status = "ok"

        if not frame_pngs:
            action_status = "no_valid_frames"
            log(f"Skipped action '{action}' (no valid frames after quality filters).")
        else:
            if normalize_canvas:
                normalization_info = normalize_action_frame_canvases(per_frame)
                if normalization_info:
                    log(
                        f"Normalized {action}: frames={normalization_info['normalized_frames']} "
                        f"canvas={normalization_info['size'][0]}x{normalization_info['size'][1]}"
                    )

            if make_gif:
                if all_actions:
                    gif_path = action_dir / f"{prefix}_{action}.gif"
                else:
                    gif_path = resolve_single_action_postprocess_path(
                        gif_path_raw,
                        out_dir=action_dir,
                        base_out_dir=base_out_dir,
                        default_name=f"{prefix}_{action}.gif",
                        use_character_folder=use_character_folder,
                    )
                try:
                    durations_ms = None
                    if use_action_delays:
                        durations_ms = [int(row.get("delay_ms", default_delay_ms)) for row in per_frame]
                    gif_info = build_gif(
                        frame_paths=frame_pngs,
                        output_path=gif_path,
                        duration_ms=gif_duration_ms,
                        durations_ms=durations_ms,
                    )
                    log(f"GIF created: {gif_info['gif_path']}")
                except Exception as exc:  # noqa: BLE001
                    gif_error = str(exc)
                    action_errors.append(f"gif_error: {gif_error}")
                    action_status = "postprocess_error"
                    log(f"GIF failed for '{action}': {gif_error}")

            if make_sheet:
                if all_actions:
                    sheet_path = action_dir / f"{prefix}_{action}_sheet.png"
                else:
                    sheet_path = resolve_single_action_postprocess_path(
                        sheet_path_raw,
                        out_dir=action_dir,
                        base_out_dir=base_out_dir,
                        default_name=f"{prefix}_{action}_sheet.png",
                        use_character_folder=use_character_folder,
                    )
                try:
                    sheet_info = build_sprite_sheet(
                        frame_paths=frame_pngs,
                        output_path=sheet_path,
                        columns=sheet_cols,
                    )
                    log(f"Sprite sheet created: {sheet_info['sheet_path']}")
                except Exception as exc:  # noqa: BLE001
                    sheet_error = str(exc)
                    action_errors.append(f"sheet_error: {sheet_error}")
                    action_status = "postprocess_error"
                    log(f"Sprite sheet failed for '{action}': {sheet_error}")

        # Annotation only (no behavior change): keeps mypy 2.x from
        # over-narrowing the per-anchor value types.
        anchor_track: list[dict] = []
        for row in per_frame:
            wa = row.get("world_anchors", {}) if isinstance(row.get("world_anchors"), dict) else {}
            anchor_track.append(
                {
                    "frame": int(row.get("frame", 0)),
                    "delay_ms": int(row.get("delay_ms", default_delay_ms)),
                    "navel": wa.get("navel"),
                    "hand": wa.get("hand"),
                    "handMove": wa.get("handMove"),
                }
            )
        hand_deltas = []
        for i in range(1, len(anchor_track)):
            prev = anchor_track[i - 1]
            cur = anchor_track[i]
            p_hand = prev.get("hand")
            c_hand = cur.get("hand")
            if isinstance(p_hand, list) and isinstance(c_hand, list) and len(p_hand) == 2 and len(c_hand) == 2:
                hand_deltas.append(
                    {
                        "from_frame": int(prev["frame"]),
                        "to_frame": int(cur["frame"]),
                        "dx": int(c_hand[0]) - int(p_hand[0]),
                        "dy": int(c_hand[1]) - int(p_hand[1]),
                    }
                )

        all_actions_summary.append(
            {
                "action": action,
                "frame_range": [frame_list[0], frame_list[-1]],
                "requested_frame_count": len(frame_list),
                "timeline_duration_ms": sum(int(row.get("delay_ms", default_delay_ms)) for row in per_frame),
                "timeline_source": "body_delay" if use_action_delays else "fixed_duration",
                "frame_count": len(frame_pngs),
                "skipped_frame_count": len(skipped_frames),
                "skipped_frames": skipped_frames,
                "status": action_status,
                "errors": action_errors,
                "output_dir": str(action_dir),
                "normalization": normalization_info,
                "gif": gif_info,
                "gif_error": gif_error,
                "sprite_sheet": sheet_info,
                "sprite_sheet_error": sheet_error,
                "anchor_track": anchor_track,
                "hand_deltas": hand_deltas,
                "frames": per_frame,
            }
        )
        total_frames += len(frame_pngs)

    summary = {
        "mode": "all_actions" if all_actions else "single_action",
        "all_actions_source": action_source if all_actions else None,
        "weapon_profile": weapon_profile,
        "skill_overlay": {
            "enabled": skill_id is not None,
            "skill_id": skill_id,
            "skill_anim": skill_anim if skill_id is not None else None,
        },
        "per_character_folder": bool(use_character_folder),
        "per_action_folder": True,
        "character_id": character_id,
        "auto_frames": bool(auto_frames),
        "use_action_delays": bool(use_action_delays),
        "normalize_canvas_per_action": bool(normalize_canvas),
        "base_id": base_id,
        "requested_action_count": len(actions),
        "action_count": len(all_actions_summary),
        "total_frames": total_frames,
        "total_skipped_frames": total_skipped_frames,
        "quality_filter": {
            "skip_unresolved": bool(skip_unresolved),
            "min_layers": min_layers,
            "min_layers_when_weapon_missing_node": max(1, min_layers - 1),
            "max_fallbacks_all_actions": max_fallbacks_all_actions if all_actions else None,
        },
        "output_dir": str(out_dir),
        "base_output_dir": str(base_out_dir),
        "actions": all_actions_summary,
    }
    summary_name = (
        f"{prefix}_all_actions_batch_summary.json"
        if all_actions
        else f"{prefix}_{single_action}_batch_summary.json"
    )
    summary_path = out_dir / summary_name
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    summary["summary_path"] = str(summary_path)
    return summary
