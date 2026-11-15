#!/usr/bin/env python3
"""Headless CLI over the character tooling operations (backlog #47).

Gated on #46 (``wz_shared.py``, PR #51) and #44 (the GUI split into
``character_tooling_core`` / ``character_tooling_ops``, PR #55): this module
is a *thin* argparse shell that lets every meaningful operation of
``character_tooling_gui.py`` run without tkinter or a display. It adds NO new
WZ-domain logic -- each subcommand marshals command-line flags into the exact
same ``character_tooling_core`` / ``character_tooling_ops`` functions the GUI
calls, with defaults mirrored from the GUI widgets (cited per-flag in the PR
body), and maps the ops ``log`` callback onto plain stdout.

Subcommands:

  validate       -- ``core.validate_base_wz`` gate (GUI on_batch_export /
                    on_render use it before every run).
  list-actions   -- ``core.detect_actions_for_loadout`` (the GUI "all actions"
                    detection; --action-source mirrors the batch combobox).
  render-frame   -- single ``render_character_frame.render`` mirroring the GUI
                    Render tab (same starter-male / slot-id defaults).
  batch-export   -- ``ops.run_batch_export`` (the GUI Batch tab's worker body),
                    every widget exposed as a flag with the GUI's default.

Path resolution follows the repo convention (CLI arg > BUDDY_ASSEMBLER_*
env var > maintainer fallback) via ``wz_shared.resolve_base_wz``. Exit code is
0 on success, nonzero with a stderr message on failure.

Purely-interactive GUI surfaces are deliberately out of scope; see the PR body
for the full list. Single-frame rendering also already ships as a standalone
headless CLI (``render_character_frame.py``); ``render-frame`` here mirrors the
GUI Render *tab*'s defaults (starter-male on, populated slot ids) rather than
that script's bare-flag defaults.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Optional, Sequence

from render_character_frame import render
from character_tooling_core import (
    detect_actions_for_loadout,
    int_or_none,
    validate_base_wz,
)
from character_tooling_ops import run_batch_export
from wz_shared import BASE_WZ_ENV_VAR, resolve_base_wz


# --------------------------------------------------------------------------
# Shared argument groups
# --------------------------------------------------------------------------

def _opt_int(raw: str) -> Optional[int]:
    """argparse type for optional slot ids: '' -> None, else int (core semantics)."""
    return int_or_none(raw)


def _add_base_wz_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--base-wz",
        default=None,
        help=(
            "Path to extracted Base.wz directory. Falls back to the "
            f"{BASE_WZ_ENV_VAR} environment variable, then to the "
            "maintainer's local default if neither is set."
        ),
    )


def _add_id_arguments(parser: argparse.ArgumentParser) -> None:
    """Character slot-id flags, defaults mirrored from the GUI Render-tab
    StringVars (character_tooling_gui.py lines 396-410) and its starter-male
    fill (_render_id_kwargs, lines 282-292)."""
    parser.add_argument("--base-id", type=int, default=2000)
    parser.add_argument("--head-id", type=int, default=12000)
    parser.add_argument("--face-id", type=int, default=20000)
    parser.add_argument("--hair-id", type=int, default=30000)
    parser.add_argument("--accessory-id", type=_opt_int, default=None)
    parser.add_argument("--cap-id", type=_opt_int, default=None)
    parser.add_argument("--coat-id", type=_opt_int, default=1040002)
    parser.add_argument("--longcoat-id", type=_opt_int, default=None)
    parser.add_argument("--pants-id", type=_opt_int, default=1060002)
    parser.add_argument("--shoes-id", type=_opt_int, default=1072001)
    parser.add_argument("--glove-id", type=_opt_int, default=None)
    parser.add_argument("--cape-id", type=_opt_int, default=None)
    parser.add_argument("--shield-id", type=_opt_int, default=None)
    parser.add_argument("--weapon-id", type=_opt_int, default=1302000)
    parser.add_argument(
        "--starter-male",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Apply v83 starter-male body/head + fill empty coat/pants/shoes/weapon (GUI default: on).",
    )


def _id_kwargs_from_args(args: argparse.Namespace) -> dict:
    """Assemble render()/ops id kwargs exactly as GUI App._render_id_kwargs
    (character_tooling_gui.py lines 265-293) does: explicit ids plus the
    starter-male fill for empty coat/pants/shoes/weapon."""
    kwargs = {
        "base_id": int(args.base_id),
        "head_id": int(args.head_id),
        "face_id": int(args.face_id),
        "hair_id": int(args.hair_id),
        "accessory_id": args.accessory_id,
        "cap_id": args.cap_id,
        "coat_id": args.coat_id,
        "longcoat_id": args.longcoat_id,
        "pants_id": args.pants_id,
        "shoes_id": args.shoes_id,
        "glove_id": args.glove_id,
        "cape_id": args.cape_id,
        "shield_id": args.shield_id,
        "weapon_id": args.weapon_id,
    }
    if args.starter_male:
        kwargs["base_id"] = 2000
        kwargs["head_id"] = 12000
        if kwargs["coat_id"] is None:
            kwargs["coat_id"] = 1040002
        if kwargs["pants_id"] is None:
            kwargs["pants_id"] = 1060002
        if kwargs["shoes_id"] is None:
            kwargs["shoes_id"] = 1072001
        if kwargs["weapon_id"] is None:
            kwargs["weapon_id"] = 1302000
    return kwargs


def _make_log(quiet: bool):
    if quiet:
        return lambda _msg: None
    return lambda msg: print(msg)


# --------------------------------------------------------------------------
# Subcommand handlers (each returns a process exit code)
# --------------------------------------------------------------------------

def cmd_validate(args: argparse.Namespace) -> int:
    base_wz = resolve_base_wz(args.base_wz)
    err = validate_base_wz(base_wz)
    if err:
        print(err, file=sys.stderr)
        return 1
    if not args.quiet:
        print(f"OK: {base_wz}")
    return 0


def cmd_list_actions(args: argparse.Namespace) -> int:
    base_wz = resolve_base_wz(args.base_wz)
    err = validate_base_wz(base_wz)
    if err:
        print(err, file=sys.stderr)
        return 1
    id_kwargs = _id_kwargs_from_args(args)
    actions = detect_actions_for_loadout(
        base_wz=base_wz,
        id_kwargs=id_kwargs,
        mode=args.action_source,
    )
    if args.json:
        print(json.dumps({"action_source": args.action_source, "actions": actions}, indent=2))
    else:
        for action in actions:
            print(action)
    return 0


def cmd_render_frame(args: argparse.Namespace) -> int:
    base_wz = resolve_base_wz(args.base_wz)
    err = validate_base_wz(base_wz)
    if err:
        print(err, file=sys.stderr)
        return 1
    output_png = Path(args.output_png)
    output_json = Path(args.output_json) if args.output_json else None
    id_kwargs = _id_kwargs_from_args(args)
    meta = render(
        base_wz=base_wz,
        output_png=output_png,
        action=args.action,
        frame=args.frame,
        output_json=output_json,
        z_draw_order=args.z_draw_order,
        hair_mode=args.hair_mode,
        **id_kwargs,
    )
    if not args.quiet:
        print(
            json.dumps(
                {
                    "status": "ok",
                    "output_png": str(output_png),
                    "drawn_layers": meta["drawn_layers"],
                    "unresolved_count": len(meta["unresolved"]),
                },
                indent=2,
            )
        )
    return 0


def cmd_batch_export(args: argparse.Namespace) -> int:
    base_wz = resolve_base_wz(args.base_wz)
    err = validate_base_wz(base_wz)
    if err:
        print(err, file=sys.stderr)
        return 1
    if not args.prefix.strip():
        print("File prefix is required.", file=sys.stderr)
        return 1
    id_kwargs = _id_kwargs_from_args(args)
    log = _make_log(args.quiet)
    try:
        summary = run_batch_export(
            base_wz=base_wz,
            base_out_dir=Path(args.output_dir),
            prefix=args.prefix.strip(),
            id_kwargs=id_kwargs,
            all_actions=bool(args.all_actions),
            action_source=args.action_source,
            single_action=args.action.strip(),
            auto_frames=bool(args.auto_frames),
            start_frame=int(args.start_frame),
            end_frame=int(args.end_frame),
            z_draw_order=args.z_draw_order,
            hair_mode=args.hair_mode,
            use_character_folder=bool(args.character_folder),
            character_id_raw=args.character_id.strip(),
            write_json=bool(args.write_json),
            use_action_delays=bool(args.use_action_delays),
            normalize_canvas=bool(args.normalize_canvas),
            make_gif=bool(args.make_gif),
            gif_path_raw=args.gif_path,
            gif_duration_ms=int(args.gif_duration),
            make_sheet=bool(args.make_sheet),
            sheet_path_raw=args.sheet_path,
            sheet_cols=int(args.sheet_cols),
            skip_unresolved=bool(args.skip_unresolved),
            min_layers=int(args.min_layers),
            skill_id=args.skill_id,
            skill_anim=args.skill_anim.strip() or "auto",
            log=log,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"Batch failed: {exc}", file=sys.stderr)
        return 1
    if not args.quiet:
        print(
            f"Batch export complete: {summary['summary_path']} "
            f"(actions={summary['action_count']} total_frames={summary['total_frames']} "
            f"total_skipped_frames={summary['total_skipped_frames']})"
        )
    return 0


# --------------------------------------------------------------------------
# Parser wiring
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="character_tooling_cli",
        description="Headless CLI over the character tooling operations (backlog #47).",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # validate
    p_validate = subparsers.add_parser(
        "validate", help="Check that a Base.wz directory has the expected Character tree."
    )
    _add_base_wz_argument(p_validate)
    p_validate.add_argument("--quiet", action="store_true", help="Suppress the success line.")
    p_validate.set_defaults(func=cmd_validate)

    # list-actions
    p_list = subparsers.add_parser(
        "list-actions",
        help="List compatible actions for a loadout (core.detect_actions_for_loadout).",
    )
    _add_base_wz_argument(p_list)
    _add_id_arguments(p_list)
    p_list.add_argument(
        "--action-source",
        choices=["loadout-intersection-with-weapon", "loadout-intersection", "body-only"],
        default="loadout-intersection-with-weapon",
        help="Action detection mode (GUI batch default: loadout-intersection-with-weapon).",
    )
    p_list.add_argument("--json", action="store_true", help="Emit a JSON object instead of one action per line.")
    p_list.add_argument("--quiet", action="store_true", help="Accepted for symmetry; no effect on this command.")
    p_list.set_defaults(func=cmd_list_actions)

    # render-frame
    p_render = subparsers.add_parser(
        "render-frame",
        help="Render a single character frame (render_character_frame.render), GUI Render-tab defaults.",
    )
    _add_base_wz_argument(p_render)
    _add_id_arguments(p_render)
    p_render.add_argument("--action", default="stand1", help="Action/state name (GUI Render default: stand1).")
    p_render.add_argument("--frame", type=int, default=0, help="Frame index within action (GUI default: 0).")
    p_render.add_argument("--output-png", required=True, help="Output PNG path.")
    p_render.add_argument("--output-json", default=None, help="Optional output metadata JSON path.")
    p_render.add_argument(
        "--z-draw-order",
        choices=["front-last", "front-first"],
        default="front-last",
        help="Layer draw order (GUI default: front-last).",
    )
    p_render.add_argument(
        "--hair-mode",
        choices=["auto", "force-show", "force-hide"],
        default="auto",
        help="Hair handling around caps (GUI default: auto).",
    )
    p_render.add_argument("--quiet", action="store_true", help="Suppress the JSON status summary.")
    p_render.set_defaults(func=cmd_render_frame)

    # batch-export
    p_batch = subparsers.add_parser(
        "batch-export",
        help="Batch-render an action (or all compatible actions) to PNGs + GIF/sheet (ops.run_batch_export).",
    )
    _add_base_wz_argument(p_batch)
    _add_id_arguments(p_batch)
    p_batch.add_argument("--output-dir", required=True, help="Base output directory (GUI Batch: batch_output_dir).")
    p_batch.add_argument("--prefix", default="anim", help="Output filename prefix (GUI default: anim).")
    p_batch.add_argument("--action", default="walk1", help="Single action when --no-all-actions (GUI default: walk1).")
    p_batch.add_argument(
        "--all-actions",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Export every compatible action instead of one (GUI default: off).",
    )
    p_batch.add_argument(
        "--action-source",
        choices=["loadout-intersection-with-weapon", "loadout-intersection", "body-only"],
        default="loadout-intersection-with-weapon",
        help="Action detection mode for --all-actions (GUI default: loadout-intersection-with-weapon).",
    )
    p_batch.add_argument(
        "--auto-frames",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Detect the action's frame timeline instead of using --start/--end-frame (GUI default: on).",
    )
    p_batch.add_argument("--start-frame", type=int, default=0, help="First frame when --no-auto-frames (GUI default: 0).")
    p_batch.add_argument("--end-frame", type=int, default=3, help="Last frame when --no-auto-frames (GUI default: 3).")
    p_batch.add_argument(
        "--z-draw-order",
        choices=["front-last", "front-first"],
        default="front-last",
        help="Layer draw order (GUI default: front-last).",
    )
    p_batch.add_argument(
        "--hair-mode",
        choices=["auto", "force-show", "force-hide"],
        default="auto",
        help="Hair handling around caps (GUI default: auto).",
    )
    p_batch.add_argument(
        "--character-folder",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Nest output under a per-character char_<id> folder (GUI default: on).",
    )
    p_batch.add_argument("--character-id", default="", help="Explicit numeric character id for the folder (GUI default: derived).")
    p_batch.add_argument(
        "--write-json",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Write per-frame metadata JSON sidecars (GUI default: on).",
    )
    p_batch.add_argument(
        "--use-action-delays",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Use per-frame body delays for GIF timing (GUI default: on).",
    )
    p_batch.add_argument(
        "--normalize-canvas",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Re-center each action's frames onto a shared canvas (GUI default: on).",
    )
    p_batch.add_argument(
        "--make-gif",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Build a GIF per action (GUI default: on).",
    )
    p_batch.add_argument("--gif-path", default="", help="GIF output path for single-action mode (GUI Batch: batch_gif_path).")
    p_batch.add_argument("--gif-duration", type=int, default=120, help="GIF frame duration ms / default delay (GUI default: 120).")
    p_batch.add_argument(
        "--make-sheet",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Build a sprite sheet per action (GUI default: on).",
    )
    p_batch.add_argument("--sheet-path", default="", help="Sprite-sheet output path for single-action mode (GUI Batch: batch_sheet_path).")
    p_batch.add_argument("--sheet-cols", type=int, default=8, help="Sprite-sheet column count (GUI default: 8).")
    p_batch.add_argument(
        "--skip-unresolved",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Drop frames that have unresolved layers (GUI default: on).",
    )
    p_batch.add_argument("--min-layers", type=int, default=8, help="Minimum drawn layers to keep a frame (GUI default: 8).")
    p_batch.add_argument("--skill-id", type=_opt_int, default=None, help="Optional skill id to overlay (GUI default: none).")
    p_batch.add_argument(
        "--skill-anim",
        choices=["auto", "effect", "effect0", "effect1", "hit", "ball", "prepare", "summon", "affected"],
        default="auto",
        help="Skill animation branch (GUI default: auto).",
    )
    p_batch.add_argument("--quiet", action="store_true", help="Suppress per-frame log lines and the final summary line.")
    p_batch.set_defaults(func=cmd_batch_export)

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
