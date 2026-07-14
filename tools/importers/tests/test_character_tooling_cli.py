#!/usr/bin/env python3
"""Tests for the headless character tooling CLI (backlog #47).

Every subcommand is driven end to end against the synthetic fixture tree
(tests/fixtures/synthetic_base_wz/), the same fixture the golden-image tests
use to run the real renderer. Each command is exercised both via a direct
``main([...])`` call (fast, in-process, exit-code assertions) and, for the
render/help surface, via a ``subprocess`` of the module so the argparse wiring
and ``python -m``-style entry stay covered.

The CLI adds no domain logic, so these tests assert on the seam behaviour:
exit codes, that the render path reproduces the checked-in golden pixels
through the CLI, that batch-export writes the expected files, and that
``--help`` stays stable for the top parser and each subcommand.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import character_tooling_cli as cli  # noqa: E402

TESTS_DIR = Path(__file__).resolve().parent
FIXTURE_BASE_WZ = TESTS_DIR / "fixtures" / "synthetic_base_wz"
GOLDEN_PNG = TESTS_DIR / "fixtures" / "golden" / "stand1_frame0.png"
CLI_SCRIPT = TESTS_DIR.parent / "character_tooling_cli.py"

# The golden combo (body + head + face + hair + coat, stand1 frame 0). Passing
# --no-starter-male and clearing the starter fill slots reproduces exactly the
# combo test_render_character_frame_golden.py renders.
GOLDEN_ARGS = [
    "--base-wz", str(FIXTURE_BASE_WZ),
    "--action", "stand1", "--frame", "0",
    "--no-starter-male",
    "--base-id", "2000", "--head-id", "12000",
    "--face-id", "20000", "--hair-id", "30000",
    "--coat-id", "1040002",
    "--pants-id", "", "--shoes-id", "", "--weapon-id", "",
]


def _run_cli(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CLI_SCRIPT), *args],
        capture_output=True,
        text=True,
    )


class ValidateCommandTests(unittest.TestCase):
    def test_validate_ok_exit_zero(self) -> None:
        self.assertEqual(cli.main(["validate", "--base-wz", str(FIXTURE_BASE_WZ), "--quiet"]), 0)

    def test_validate_missing_exit_nonzero(self) -> None:
        self.assertEqual(cli.main(["validate", "--base-wz", str(FIXTURE_BASE_WZ / "nope")]), 1)

    def test_validate_subprocess_message_on_stderr(self) -> None:
        proc = _run_cli(["validate", "--base-wz", str(FIXTURE_BASE_WZ / "nope")])
        self.assertEqual(proc.returncode, 1)
        self.assertIn("does not exist", proc.stderr)


class ListActionsCommandTests(unittest.TestCase):
    def test_body_only_lists_stand1(self) -> None:
        proc = _run_cli(
            ["list-actions", "--base-wz", str(FIXTURE_BASE_WZ), "--action-source", "body-only"]
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.split(), ["stand1"])

    def test_json_mode_shape(self) -> None:
        proc = _run_cli(
            ["list-actions", "--base-wz", str(FIXTURE_BASE_WZ), "--action-source", "body-only", "--json"]
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["action_source"], "body-only")
        self.assertEqual(payload["actions"], ["stand1"])

    def test_with_weapon_source_intersection_empty_is_faithful(self) -> None:
        # The fixture hair asset has only a 'default' node, so the strict
        # with-weapon intersection is legitimately empty. The CLI must return
        # that unchanged (exit 0, no invented actions).
        rc = cli.main(
            ["list-actions", "--base-wz", str(FIXTURE_BASE_WZ), "--json",
             "--action-source", "loadout-intersection-with-weapon"]
        )
        self.assertEqual(rc, 0)


class RenderFrameCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.out_dir = Path(self.tmpdir.name)

    def _assert_matches_golden(self, png: Path) -> None:
        rendered = Image.open(png).convert("RGBA")
        golden = Image.open(GOLDEN_PNG).convert("RGBA")
        self.assertEqual(rendered.size, golden.size)
        self.assertEqual(rendered.tobytes(), golden.tobytes())

    def test_render_frame_main_matches_golden(self) -> None:
        out_png = self.out_dir / "cli_render.png"
        rc = cli.main(["render-frame", *GOLDEN_ARGS, "--output-png", str(out_png)])
        self.assertEqual(rc, 0)
        self._assert_matches_golden(out_png)

    def test_render_frame_subprocess_matches_golden(self) -> None:
        out_png = self.out_dir / "cli_render_sub.png"
        proc = _run_cli(["render-frame", *GOLDEN_ARGS, "--output-png", str(out_png)])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self._assert_matches_golden(out_png)

    def test_render_frame_writes_json_sidecar(self) -> None:
        out_png = self.out_dir / "r.png"
        out_json = self.out_dir / "r.json"
        rc = cli.main(
            ["render-frame", *GOLDEN_ARGS, "--output-png", str(out_png), "--output-json", str(out_json)]
        )
        self.assertEqual(rc, 0)
        self.assertTrue(out_json.exists())
        json.loads(out_json.read_text(encoding="utf-8"))


class BatchExportCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.out_dir = Path(self.tmpdir.name) / "batch"

    def _batch_args(self, extra: list[str]) -> list[str]:
        return [
            "batch-export",
            "--base-wz", str(FIXTURE_BASE_WZ),
            "--output-dir", str(self.out_dir),
            "--action", "stand1",
            "--no-starter-male",
            "--coat-id", "1040002",
            "--pants-id", "", "--shoes-id", "", "--weapon-id", "",
            "--min-layers", "6",
            "--prefix", "anim",
            *extra,
        ]

    def test_batch_export_produces_outputs(self) -> None:
        rc = cli.main(self._batch_args(["--quiet"]))
        self.assertEqual(rc, 0)

        pngs = list(self.out_dir.rglob("anim_stand1_000.png"))
        gifs = list(self.out_dir.rglob("anim_stand1.gif"))
        sheets = list(self.out_dir.rglob("anim_stand1_sheet.png"))
        summaries = list(self.out_dir.rglob("anim_stand1_batch_summary.json"))
        self.assertEqual(len(pngs), 1, "expected one rendered frame PNG")
        self.assertEqual(len(gifs), 1, "expected one GIF")
        self.assertEqual(len(sheets), 1, "expected one sprite sheet")
        self.assertEqual(len(summaries), 1, "expected one summary JSON")

        summary = json.loads(summaries[0].read_text(encoding="utf-8"))
        self.assertEqual(summary["mode"], "single_action")
        self.assertEqual(summary["total_frames"], 1)
        self.assertEqual(summary["total_skipped_frames"], 0)

    def test_batch_export_frame_matches_golden(self) -> None:
        rc = cli.main(self._batch_args(["--no-make-gif", "--no-make-sheet", "--no-normalize-canvas", "--quiet"]))
        self.assertEqual(rc, 0)
        pngs = list(self.out_dir.rglob("anim_stand1_000.png"))
        self.assertEqual(len(pngs), 1)
        rendered = Image.open(pngs[0]).convert("RGBA")
        golden = Image.open(GOLDEN_PNG).convert("RGBA")
        self.assertEqual(rendered.tobytes(), golden.tobytes())

    def test_batch_export_default_min_layers_skips_thin_frame(self) -> None:
        # No behavior drift: the GUI default min_layers=8 filters the fixture's
        # 6-layer frame, so nothing is kept. The CLI must reproduce that.
        args = [
            "batch-export",
            "--base-wz", str(FIXTURE_BASE_WZ),
            "--output-dir", str(self.out_dir),
            "--action", "stand1",
            "--no-starter-male", "--coat-id", "1040002",
            "--pants-id", "", "--shoes-id", "", "--weapon-id", "",
            "--quiet",
        ]
        rc = cli.main(args)
        self.assertEqual(rc, 0)
        summaries = list(self.out_dir.rglob("anim_stand1_batch_summary.json"))
        self.assertEqual(len(summaries), 1)
        summary = json.loads(summaries[0].read_text(encoding="utf-8"))
        self.assertEqual(summary["total_frames"], 0)

    def test_batch_export_missing_prefix_exit_nonzero(self) -> None:
        rc = cli.main(self._batch_args(["--prefix", "  ", "--quiet"]))
        self.assertEqual(rc, 1)


class HelpStabilityTests(unittest.TestCase):
    def test_top_level_help_lists_all_subcommands(self) -> None:
        proc = _run_cli(["--help"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for name in ("validate", "list-actions", "render-frame", "batch-export"):
            self.assertIn(name, proc.stdout)

    def test_subcommand_help_returns_zero(self) -> None:
        for name in ("validate", "list-actions", "render-frame", "batch-export"):
            with self.subTest(command=name):
                proc = _run_cli([name, "--help"])
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertIn("usage:", proc.stdout)

    def test_batch_help_documents_gui_defaults(self) -> None:
        proc = _run_cli(["batch-export", "--help"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        # Stable, load-bearing default markers mirrored from the GUI widgets.
        self.assertIn("--no-make-gif", proc.stdout)
        self.assertIn("--min-layers", proc.stdout)
        self.assertIn("--action-source", proc.stdout)


if __name__ == "__main__":
    unittest.main()
