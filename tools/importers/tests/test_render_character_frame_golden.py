#!/usr/bin/env python3
"""Golden-image regression tests for render_character_frame.py.

Run with:
    python3 -m unittest tools/importers/tests/test_render_character_frame_golden.py -v

The fixture tree under tests/fixtures/synthetic_base_wz/ is hand-built
synthetic data that mimics the extracted Base.wz XML+PNG layout closely
enough for the *real* renderer to run its full composition path end to
end (asset XML indexing, action/frame selection, anchor chaining
navel -> neck -> brow, zmap layer ordering, alpha compositing). It is
NOT real MapleStory v83 content - the real extracted asset trees exist
only on the maintainer's machine, same constraint as every importer
tooling task in this repo (see build_asset_inventory.py --synthetic for
the same pattern).

So these tests answer exactly one question: "did a code change alter the
composed pixel output for a known input?" They say nothing about whether
a real character composed from real assets looks correct - that remains
a human-with-real-assets judgement.

The checked-in golden reference (tests/fixtures/golden/stand1_frame0.png)
was produced by running the renderer CLI against this fixture. Comparison
against the golden is pixel-level (decoded RGBA bytes), not PNG-file-byte
level, so the test stays strict on rendered content while tolerating PNG
encoder differences across Pillow/zlib versions. Determinism note: the
render path has no randomness or timestamp dependence (PIL does not emit
a tIME chunk by default); repeat renders in one environment are
byte-identical, which test_repeat_renders_are_byte_identical pins down.

If a deliberate rendering change alters the output, regenerate the golden:
    python3 tools/importers/render_character_frame.py \
        --base-wz tools/importers/tests/fixtures/synthetic_base_wz \
        --action stand1 --frame 0 \
        --base-id 2000 --head-id 12000 --face-id 20000 --hair-id 30000 \
        --coat-id 1040002 \
        --output-png tools/importers/tests/fixtures/golden/stand1_frame0.png
and call out the intentional pixel change in the PR.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_character_frame as rcf  # noqa: E402

TESTS_DIR = Path(__file__).resolve().parent
FIXTURE_BASE_WZ = TESTS_DIR / "fixtures" / "synthetic_base_wz"
GOLDEN_PNG = TESTS_DIR / "fixtures" / "golden" / "stand1_frame0.png"
RENDER_SCRIPT = TESTS_DIR.parent / "render_character_frame.py"

# The one known combo the golden covers: body + head + face + hair + coat,
# stand1 frame 0. IDs mirror the real starter-male defaults so the fixture
# XML filenames follow the real 8-digit id_to_xml() convention.
COMBO = {
    "action": "stand1",
    "frame": 0,
    "base_id": 2000,
    "head_id": 12000,
    "face_id": 20000,
    "hair_id": 30000,
    "coat_id": 1040002,
}


def render_fixture(output_png: Path, output_json: Path | None = None) -> dict:
    """Invoke the real render() against the synthetic fixture tree."""
    return rcf.render(
        base_wz=FIXTURE_BASE_WZ,
        output_png=output_png,
        action=COMBO["action"],
        frame=COMBO["frame"],
        base_id=COMBO["base_id"],
        head_id=COMBO["head_id"],
        face_id=COMBO["face_id"],
        hair_id=COMBO["hair_id"],
        accessory_id=None,
        cap_id=None,
        coat_id=COMBO["coat_id"],
        longcoat_id=None,
        pants_id=None,
        shoes_id=None,
        glove_id=None,
        cape_id=None,
        shield_id=None,
        weapon_id=None,
        output_json=output_json,
    )


def pixel_diff_report(a: Image.Image, b: Image.Image) -> str:
    """Human-readable summary of how two same-size RGBA images differ."""
    pa, pb = a.load(), b.load()
    diffs = [
        (x, y)
        for y in range(a.height)
        for x in range(a.width)
        if pa[x, y] != pb[x, y]
    ]
    if not diffs:
        return "no differing pixels"
    xs = [d[0] for d in diffs]
    ys = [d[1] for d in diffs]
    first = diffs[0]
    return (
        f"{len(diffs)} differing pixel(s); bbox x=[{min(xs)},{max(xs)}] "
        f"y=[{min(ys)},{max(ys)}]; first diff at {first}: "
        f"rendered={pa[first]} golden={pb[first]}"
    )


class GoldenImageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.out_dir = Path(self.tmpdir.name)

    def test_render_matches_checked_in_golden_pixels(self) -> None:
        out_png = self.out_dir / "rendered.png"
        render_fixture(out_png)

        rendered = Image.open(out_png).convert("RGBA")
        golden = Image.open(GOLDEN_PNG).convert("RGBA")

        self.assertEqual(
            rendered.size,
            golden.size,
            f"canvas size changed: rendered={rendered.size} golden={golden.size}",
        )
        if rendered.tobytes() != golden.tobytes():
            self.fail(
                "rendered output differs from golden reference: "
                + pixel_diff_report(rendered, golden)
            )

    def test_repeat_renders_are_byte_identical(self) -> None:
        # Determinism gate for the golden approach itself: two renders in
        # the same environment must produce identical PNG files, byte for
        # byte. (Cross-environment byte equality is NOT assumed - the
        # golden comparison above is pixel-level for that reason.)
        out_a = self.out_dir / "a.png"
        out_b = self.out_dir / "b.png"
        render_fixture(out_a)
        render_fixture(out_b)
        self.assertEqual(out_a.read_bytes(), out_b.read_bytes())

    def test_composition_metadata_is_stable(self) -> None:
        # Pins the non-pixel half of the composition contract: anchor
        # chaining and z ordering. Failures here localise a golden-pixel
        # mismatch to placement logic vs. compositing.
        out_png = self.out_dir / "rendered.png"
        metadata = render_fixture(out_png)

        self.assertEqual(metadata["drawn_layers"], 6)
        self.assertEqual(metadata["unresolved"], [])
        self.assertEqual(metadata["canvas_size"], [40, 65])
        self.assertEqual(
            metadata["world_anchors"],
            {"brow": [0, -27], "navel": [0, 0], "neck": [0, -14]},
        )
        # Back-to-front draw order under the fixture zmap (front-last mode).
        self.assertEqual(
            [(d["asset_kind"], d["z"]) for d in metadata["draw_order"]],
            [
                ("body", "body"),
                ("body", "arm"),
                ("coat", "mail"),
                ("head", "head"),
                ("face", "face"),
                ("hair", "hair"),
            ],
        )
        # Face and hair intentionally exercise the static-node fallback
        # (real Face imgs have no stand1 node either); body/head/coat must
        # resolve the exact action+frame.
        modes = {
            row["asset_kind"]: row["selection_mode"]
            for row in metadata["action_resolution"]
        }
        self.assertEqual(modes["body"], "exact_action_exact_frame")
        self.assertEqual(modes["head"], "exact_action_exact_frame")
        self.assertEqual(modes["coat"], "exact_action_exact_frame")
        self.assertEqual(modes["face"], "fallback_static_node")
        self.assertEqual(modes["hair"], "fallback_static_node")

    def test_cli_end_to_end_matches_golden(self) -> None:
        # Same render through the actual command-line entry point, so the
        # argparse wiring stays covered too.
        out_png = self.out_dir / "cli.png"
        proc = subprocess.run(
            [
                sys.executable,
                str(RENDER_SCRIPT),
                "--base-wz",
                str(FIXTURE_BASE_WZ),
                "--action",
                COMBO["action"],
                "--frame",
                str(COMBO["frame"]),
                "--base-id",
                str(COMBO["base_id"]),
                "--head-id",
                str(COMBO["head_id"]),
                "--face-id",
                str(COMBO["face_id"]),
                "--hair-id",
                str(COMBO["hair_id"]),
                "--coat-id",
                str(COMBO["coat_id"]),
                "--output-png",
                str(out_png),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)

        rendered = Image.open(out_png).convert("RGBA")
        golden = Image.open(GOLDEN_PNG).convert("RGBA")
        self.assertEqual(rendered.size, golden.size)
        if rendered.tobytes() != golden.tobytes():
            self.fail(
                "CLI output differs from golden reference: "
                + pixel_diff_report(rendered, golden)
            )


if __name__ == "__main__":
    unittest.main()
