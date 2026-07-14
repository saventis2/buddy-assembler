"""Unit tests for tools/importers/character_tooling_ops.py (backlog #44).

``run_batch_export`` is the GUI's batch-export worker, extracted headlessly.
These tests drive it with an injected ``render_fn`` stub (no real WZ data /
renderer needed) and pin the orchestration behavior it inherited: frame
loops, quality filters, per-character/per-action folders, GIF/sprite-sheet
post-processing, summary JSON shape, and log messages. Run with:

    python3 -m unittest discover -s tools/importers/tests -v
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import character_tooling_ops as ops  # noqa: E402
from character_tooling_core import build_character_identifier  # noqa: E402


def _mk_multicolor_png(path: Path, size: int = 4) -> None:
    from PIL import Image

    path.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (size, size), (255, 0, 0, 255))
    img.putpixel((0, 0), (0, 255, 0, 255))
    img.putpixel((1, 0), (0, 0, 255, 255))
    img.save(path)
    img.close()


class TestResolveBatchCharacterOutDir(unittest.TestCase):
    def test_disabled_returns_base_dir(self) -> None:
        base = Path("/out")
        out_dir, character_id = ops.resolve_batch_character_out_dir(
            base, {"base_id": 2000}, use_character_folder=False, character_id_raw="123"
        )
        self.assertEqual(out_dir, base)
        self.assertIsNone(character_id)

    def test_explicit_id_wins(self) -> None:
        base = Path("/out")
        out_dir, character_id = ops.resolve_batch_character_out_dir(
            base, {"base_id": 2000}, use_character_folder=True, character_id_raw="777"
        )
        self.assertEqual(out_dir, base / "char_777")
        self.assertEqual(character_id, "777")

    def test_derived_identifier_fallback(self) -> None:
        base = Path("/out")
        id_kwargs = {"base_id": 2000, "head_id": 12000}
        expected = build_character_identifier(id_kwargs)
        out_dir, character_id = ops.resolve_batch_character_out_dir(
            base, id_kwargs, use_character_folder=True, character_id_raw=""
        )
        self.assertEqual(character_id, expected)
        self.assertEqual(out_dir, base / f"char_{expected}")


class TestResolveSingleActionPostprocessPath(unittest.TestCase):
    def test_empty_uses_default_in_out_dir(self) -> None:
        out = ops.resolve_single_action_postprocess_path(
            "",
            out_dir=Path("/out/char_1/walk1"),
            base_out_dir=Path("/out"),
            default_name="anim_walk1.gif",
            use_character_folder=True,
        )
        self.assertEqual(out, Path("/out/char_1/walk1/anim_walk1.gif"))

    def test_relative_path_joined_to_out_dir(self) -> None:
        out = ops.resolve_single_action_postprocess_path(
            "my.gif",
            out_dir=Path("/out/walk1"),
            base_out_dir=Path("/out"),
            default_name="anim.gif",
            use_character_folder=False,
        )
        self.assertEqual(out, Path("/out/walk1/my.gif"))

    def test_absolute_inside_base_redirected_when_per_character(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_out = Path(td)
            out_dir = base_out / "char_9" / "walk1"
            out = ops.resolve_single_action_postprocess_path(
                str(base_out / "anim.gif"),
                out_dir=out_dir,
                base_out_dir=base_out,
                default_name="x.gif",
                use_character_folder=True,
            )
            self.assertEqual(out, out_dir / "anim.gif")

    def test_absolute_elsewhere_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            other = Path(td) / "elsewhere" / "anim.gif"
            out = ops.resolve_single_action_postprocess_path(
                str(other),
                out_dir=Path(td) / "out" / "walk1",
                base_out_dir=Path(td) / "out",
                default_name="x.gif",
                use_character_folder=True,
            )
            self.assertEqual(out, other)

    def test_absolute_inside_base_kept_when_not_per_character(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_out = Path(td)
            target = base_out / "anim.gif"
            out = ops.resolve_single_action_postprocess_path(
                str(target),
                out_dir=base_out / "walk1",
                base_out_dir=base_out,
                default_name="x.gif",
                use_character_folder=False,
            )
            self.assertEqual(out, target)


def _stub_render_factory(plan: dict):
    """render_fn stub: writes a PNG (+ optional JSON) and returns the meta
    dict configured in ``plan`` for (action, frame); raises if the plan says
    'raise'."""

    calls: list[dict] = []

    def render_fn(*, base_wz, output_png, action, frame, output_json, z_draw_order,
                  hair_mode, skill_id=None, skill_anim="auto", **id_kwargs):
        calls.append(
            {
                "action": action,
                "frame": frame,
                "z_draw_order": z_draw_order,
                "hair_mode": hair_mode,
                "skill_id": skill_id,
                "skill_anim": skill_anim,
                "id_kwargs": id_kwargs,
            }
        )
        spec = plan.get((action, frame), {})
        if spec.get("raise"):
            raise RuntimeError(spec["raise"])
        _mk_multicolor_png(output_png)
        if output_json is not None:
            output_json.write_text("{}", encoding="utf-8")
        return {
            "output_png": str(output_png),
            "drawn_layers": spec.get("drawn_layers", 10),
            "unresolved": spec.get("unresolved", []),
            "action_fallback_count": spec.get("action_fallback_count", 0),
            "action_resolution": spec.get("action_resolution", []),
            "world_anchors": spec.get("world_anchors", {"navel": [0, 0], "hand": [frame, 2 * frame]}),
            "frame_bounds_world": spec.get(
                "frame_bounds_world", {"left": 0, "top": 0, "right": 4, "bottom": 4}
            ),
        }

    return render_fn, calls


def _base_kwargs(base_wz: Path, base_out_dir: Path, **overrides) -> dict:
    kwargs = dict(
        base_wz=base_wz,
        base_out_dir=base_out_dir,
        prefix="anim",
        id_kwargs={"base_id": 2000, "head_id": 12000, "weapon_id": None},
        all_actions=False,
        action_source="loadout-intersection-with-weapon",
        single_action="walk1",
        auto_frames=False,
        start_frame=0,
        end_frame=2,
        z_draw_order="front-last",
        hair_mode="auto",
        use_character_folder=False,
        character_id_raw="",
        write_json=True,
        use_action_delays=True,
        normalize_canvas=False,
        make_gif=True,
        gif_path_raw="",
        gif_duration_ms=120,
        make_sheet=True,
        sheet_path_raw="",
        sheet_cols=8,
        skip_unresolved=True,
        min_layers=8,
        skill_id=None,
        skill_anim="auto",
    )
    kwargs.update(overrides)
    return kwargs


class TestRunBatchExportSingleAction(unittest.TestCase):
    def test_exports_frames_gif_sheet_and_summary(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            out = Path(td) / "out"
            render_fn, calls = _stub_render_factory({})
            logs: list[str] = []
            summary = ops.run_batch_export(
                **_base_kwargs(base_wz, out), log=logs.append, render_fn=render_fn
            )

            self.assertEqual(summary["mode"], "single_action")
            self.assertIsNone(summary["all_actions_source"])
            self.assertIsNone(summary["weapon_profile"])
            self.assertEqual(summary["base_id"], 2000)
            self.assertEqual(summary["total_frames"], 3)
            self.assertEqual(summary["total_skipped_frames"], 0)
            self.assertEqual(summary["character_id"], None)
            self.assertEqual(summary["output_dir"], str(out))
            self.assertEqual(len(calls), 3)
            self.assertEqual(calls[0]["id_kwargs"], {"base_id": 2000, "head_id": 12000, "weapon_id": None})

            action_dir = out / "walk1"
            for frame in range(3):
                self.assertTrue((action_dir / f"anim_walk1_{frame:03d}.png").exists())
                self.assertTrue((action_dir / f"anim_walk1_{frame:03d}.json").exists())
            self.assertTrue((action_dir / "anim_walk1.gif").exists())
            self.assertTrue((action_dir / "anim_walk1_sheet.png").exists())

            row = summary["actions"][0]
            self.assertEqual(row["action"], "walk1")
            self.assertEqual(row["frame_range"], [0, 2])
            self.assertEqual(row["status"], "ok")
            # Fixed-frame mode: every delay is the GIF duration.
            self.assertEqual([f["delay_ms"] for f in row["frames"]], [120, 120, 120])
            self.assertEqual(row["timeline_source"], "body_delay")
            self.assertEqual(row["timeline_duration_ms"], 360)
            # Anchor track and hand deltas derive from render metadata.
            self.assertEqual([a["hand"] for a in row["anchor_track"]], [[0, 0], [1, 2], [2, 4]])
            self.assertEqual(
                row["hand_deltas"],
                [
                    {"from_frame": 0, "to_frame": 1, "dx": 1, "dy": 2},
                    {"from_frame": 1, "to_frame": 2, "dx": 1, "dy": 2},
                ],
            )

            summary_path = out / "anim_walk1_batch_summary.json"
            self.assertTrue(summary_path.exists())
            self.assertEqual(summary["summary_path"], str(summary_path))
            on_disk = json.loads(summary_path.read_text(encoding="utf-8"))
            self.assertEqual(on_disk["total_frames"], 3)
            # summary_path key is added only after writing the file.
            self.assertNotIn("summary_path", on_disk)

            self.assertIn("Rendered walk1 frame 0", logs)
            self.assertIn(f"Batch character scope: out_dir={out}", logs)

    def test_quality_filters_skip_and_delete_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            out = Path(td) / "out"
            plan = {
                ("walk1", 1): {"drawn_layers": 2},  # below min_layers=8
                ("walk1", 2): {"unresolved": [{"part": "cap"}]},
            }
            render_fn, _ = _stub_render_factory(plan)
            logs: list[str] = []
            summary = ops.run_batch_export(
                **_base_kwargs(base_wz, out, make_gif=False, make_sheet=False),
                log=logs.append,
                render_fn=render_fn,
            )
            self.assertEqual(summary["total_frames"], 1)
            self.assertEqual(summary["total_skipped_frames"], 2)
            row = summary["actions"][0]
            self.assertEqual(row["skipped_frame_count"], 2)
            reasons = {s["frame"]: s["reason"] for s in row["skipped_frames"]}
            self.assertEqual(reasons[1], "layers=2 (<8)")
            self.assertEqual(reasons[2], "unresolved=1")
            action_dir = out / "walk1"
            # Skipped frames' outputs are deleted; the good frame remains.
            self.assertTrue((action_dir / "anim_walk1_000.png").exists())
            self.assertFalse((action_dir / "anim_walk1_001.png").exists())
            self.assertFalse((action_dir / "anim_walk1_001.json").exists())
            self.assertFalse((action_dir / "anim_walk1_002.png").exists())
            self.assertIn("Skipped walk1 frame 1: layers=2 (<8)", logs)
            self.assertIn("Skipped walk1 frame 2: unresolved=1", logs)

    def test_weapon_missing_node_relaxes_min_layers(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            out = Path(td) / "out"
            plan = {
                ("walk1", 0): {
                    "drawn_layers": 7,  # < min_layers=8, but weapon has no node
                    "action_resolution": [
                        {"asset_kind": "weapon", "selection_mode": "no_render_node", "entry_count": 0}
                    ],
                },
                ("walk1", 1): {"drawn_layers": 7},  # no weapon row: still skipped
                ("walk1", 2): {"drawn_layers": 7},
            }
            render_fn, _ = _stub_render_factory(plan)
            summary = ops.run_batch_export(
                **_base_kwargs(base_wz, out, make_gif=False, make_sheet=False),
                log=lambda _msg: None,
                render_fn=render_fn,
            )
            row = summary["actions"][0]
            kept = [f["frame"] for f in row["frames"]]
            self.assertEqual(kept, [0])
            self.assertEqual(row["frames"][0]["effective_min_layers"], 7)
            self.assertEqual(row["frames"][0]["weapon_selection_mode"], "no_render_node")
            self.assertEqual(
                {s["frame"] for s in row["skipped_frames"]}, {1, 2}
            )

    def test_render_error_is_captured_per_frame(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            out = Path(td) / "out"
            plan = {("walk1", 1): {"raise": "boom"}}
            render_fn, _ = _stub_render_factory(plan)
            logs: list[str] = []
            summary = ops.run_batch_export(
                **_base_kwargs(base_wz, out, make_gif=False, make_sheet=False),
                log=logs.append,
                render_fn=render_fn,
            )
            row = summary["actions"][0]
            self.assertEqual(row["errors"], ["render_error: boom"])
            self.assertEqual(row["skipped_frames"][0]["reason"], "render_error: boom")
            self.assertEqual(row["status"], "ok")  # render errors alone don't flip status
            self.assertIn("Skipped walk1 frame 1: render_error: boom", logs)

    def test_per_character_folder_and_skill_overlay(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            out = Path(td) / "out"
            render_fn, calls = _stub_render_factory({})
            logs: list[str] = []
            summary = ops.run_batch_export(
                **_base_kwargs(
                    base_wz,
                    out,
                    use_character_folder=True,
                    character_id_raw="42",
                    skill_id=1001,
                    skill_anim="effect",
                    make_gif=False,
                    make_sheet=False,
                ),
                log=logs.append,
                render_fn=render_fn,
            )
            self.assertEqual(summary["character_id"], "42")
            self.assertEqual(summary["per_character_folder"], True)
            self.assertEqual(summary["output_dir"], str(out / "char_42"))
            self.assertEqual(summary["base_output_dir"], str(out))
            self.assertEqual(
                summary["skill_overlay"],
                {"enabled": True, "skill_id": 1001, "skill_anim": "effect"},
            )
            self.assertTrue((out / "char_42" / "walk1" / "anim_walk1_000.png").exists())
            self.assertEqual(calls[0]["skill_id"], 1001)
            self.assertEqual(calls[0]["skill_anim"], "effect")
            self.assertIn(
                f"Batch character scope: out_dir={out / 'char_42'} character_id=42", logs
            )
            self.assertIn("Skill overlay enabled: skill_id=1001 branch=effect", logs)

    def test_weapon_profile_and_unsupported_action_warning(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"  # no weapon assets: supported_actions == []
            out = Path(td) / "out"
            render_fn, _ = _stub_render_factory({})
            logs: list[str] = []
            summary = ops.run_batch_export(
                **_base_kwargs(
                    base_wz,
                    out,
                    id_kwargs={"base_id": 2000, "head_id": 12000, "weapon_id": 1302000},
                    make_gif=False,
                    make_sheet=False,
                ),
                log=logs.append,
                render_fn=render_fn,
            )
            self.assertEqual(summary["weapon_profile"]["weapon_id"], 1302000)
            self.assertEqual(summary["weapon_profile"]["supported_actions"], [])
            self.assertIn(
                "Warning: action 'walk1' is not supported by weapon 1302000; "
                "output may omit weapon.",
                logs,
            )
            self.assertTrue(
                any(log.startswith("Weapon compatibility: id=1302000 type=130") for log in logs)
            )

    def test_normalize_canvas_repaints_frames_onto_union_bounds(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            out = Path(td) / "out"
            plan = {
                ("walk1", 0): {"frame_bounds_world": {"left": 0, "top": 0, "right": 4, "bottom": 4}},
                ("walk1", 1): {"frame_bounds_world": {"left": -2, "top": 0, "right": 2, "bottom": 4}},
                ("walk1", 2): {"frame_bounds_world": {"left": 0, "top": -1, "right": 4, "bottom": 3}},
            }
            render_fn, _ = _stub_render_factory(plan)
            summary = ops.run_batch_export(
                **_base_kwargs(base_wz, out, normalize_canvas=True, make_gif=False, make_sheet=False),
                log=lambda _msg: None,
                render_fn=render_fn,
            )
            row = summary["actions"][0]
            self.assertIsNotNone(row["normalization"])
            self.assertEqual(row["normalization"]["size"], [6, 5])
            self.assertEqual(row["normalization"]["normalized_frames"], 3)
            # GUI mode: no sidecar-JSON sync, no effective_bounds_world key.
            self.assertNotIn("effective_bounds_world", row["frames"][0])

    def test_explicit_gif_and_sheet_paths_single_action(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            out = Path(td) / "out"
            gif_target = Path(td) / "explicit" / "my.gif"
            sheet_target = Path(td) / "explicit" / "my_sheet.png"
            render_fn, _ = _stub_render_factory({})
            summary = ops.run_batch_export(
                **_base_kwargs(
                    base_wz,
                    out,
                    gif_path_raw=str(gif_target),
                    sheet_path_raw=str(sheet_target),
                ),
                log=lambda _msg: None,
                render_fn=render_fn,
            )
            row = summary["actions"][0]
            self.assertTrue(gif_target.exists())
            self.assertTrue(sheet_target.exists())
            self.assertEqual(row["gif"]["gif_path"], str(gif_target))
            self.assertEqual(row["sprite_sheet"]["sheet_path"], str(sheet_target))
            self.assertEqual(row["gif"]["durations_ms"], [120, 120, 120])


class TestRunBatchExportAllActions(unittest.TestCase):
    def _make_body(self, base_wz: Path) -> None:
        body_dir = base_wz / "Character" / "Character.wz" / "00002000.img"
        for action, frames in (("stand1", [0]), ("walk1", [0, 1])):
            for frame in frames:
                _mk_multicolor_png(body_dir / action / str(frame) / "body.png")
        xml = (
            '<imgdir name="00002000.img">'
            '<imgdir name="stand1"><imgdir name="0"><int name="delay" value="500"/></imgdir></imgdir>'
            '<imgdir name="walk1">'
            '<imgdir name="0"><int name="delay" value="150"/></imgdir>'
            '<imgdir name="1"/>'
            "</imgdir>"
            "</imgdir>"
        )
        (base_wz / "Character" / "Character.wz" / "00002000.img.xml").write_text(
            xml, encoding="utf-8"
        )

    def test_all_actions_auto_frames_with_template_delays(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            self._make_body(base_wz)
            out = Path(td) / "out"
            render_fn, calls = _stub_render_factory({})
            logs: list[str] = []
            summary = ops.run_batch_export(
                **_base_kwargs(
                    base_wz,
                    out,
                    all_actions=True,
                    action_source="body-only",
                    auto_frames=True,
                    make_sheet=False,
                ),
                log=logs.append,
                render_fn=render_fn,
            )
            self.assertEqual(summary["mode"], "all_actions")
            self.assertEqual(summary["all_actions_source"], "body-only")
            self.assertEqual(summary["requested_action_count"], 2)
            self.assertEqual(summary["action_count"], 2)
            self.assertEqual(summary["total_frames"], 3)
            self.assertEqual(
                summary["quality_filter"]["max_fallbacks_all_actions"], 2
            )
            self.assertIn(
                "All-actions mode using 'body-only': 2 compatible actions detected.", logs
            )

            by_action = {row["action"]: row for row in summary["actions"]}
            # Auto-frame delays come from the body template; missing delay
            # falls back to gif_duration_ms.
            self.assertEqual([f["delay_ms"] for f in by_action["stand1"]["frames"]], [500])
            self.assertEqual([f["delay_ms"] for f in by_action["walk1"]["frames"]], [150, 120])
            # All-actions mode: GIFs are always per-action files in the action dir.
            self.assertTrue((out / "stand1" / "anim_stand1.gif").exists())
            self.assertTrue((out / "walk1" / "anim_walk1.gif").exists())
            self.assertEqual(by_action["walk1"]["gif"]["durations_ms"], [150, 120])

            summary_path = out / "anim_all_actions_batch_summary.json"
            self.assertTrue(summary_path.exists())

    def test_all_actions_excessive_fallbacks_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base_wz = Path(td) / "wz"
            self._make_body(base_wz)
            out = Path(td) / "out"
            plan = {("stand1", 0): {"action_fallback_count": 3}}
            render_fn, _ = _stub_render_factory(plan)
            summary = ops.run_batch_export(
                **_base_kwargs(
                    base_wz,
                    out,
                    all_actions=True,
                    action_source="body-only",
                    auto_frames=True,
                    make_gif=False,
                    make_sheet=False,
                ),
                log=lambda _msg: None,
                render_fn=render_fn,
            )
            by_action = {row["action"]: row for row in summary["actions"]}
            self.assertEqual(by_action["stand1"]["status"], "no_valid_frames")
            self.assertEqual(
                by_action["stand1"]["skipped_frames"][0]["reason"], "fallbacks=3 (>2)"
            )
            self.assertEqual(by_action["walk1"]["frame_count"], 2)


if __name__ == "__main__":
    unittest.main()
