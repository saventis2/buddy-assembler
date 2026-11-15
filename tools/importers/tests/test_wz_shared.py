"""Unit tests for tools/importers/wz_shared.py (backlog #46).

Each test pins the exact behavior the shared function inherited from the
per-script copies it replaced, using synthetic fixtures (no real WZ data --
same constraint as every prior importer-tooling task). Run with:

    python3 -m unittest discover -s tools/importers/tests -v
"""

from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
import unittest.mock
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import wz_shared  # noqa: E402


def _mkpng(path: Path, width: int = 1, height: int = 1, color=(255, 0, 0, 255)) -> None:
    from PIL import Image

    path.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (width, height), color)
    img.save(path)
    img.close()


class TestPathResolution(unittest.TestCase):
    def test_cli_value_wins(self) -> None:
        with unittest.mock.patch.dict("os.environ", {"X_ENV": "/from-env"}):
            self.assertEqual(
                wz_shared.resolve_default_path("/from-cli", "X_ENV", "/fallback"),
                "/from-cli",
            )

    def test_env_value_beats_fallback(self) -> None:
        with unittest.mock.patch.dict("os.environ", {"X_ENV": "/from-env"}):
            self.assertEqual(
                wz_shared.resolve_default_path(None, "X_ENV", "/fallback"),
                "/from-env",
            )

    def test_fallback_when_nothing_set(self) -> None:
        with unittest.mock.patch.dict("os.environ", {}, clear=True):
            self.assertEqual(
                wz_shared.resolve_default_path(None, "X_ENV", "/fallback"),
                "/fallback",
            )
            self.assertEqual(
                wz_shared.resolve_default_path("", "X_ENV", "/fallback"),
                "/fallback",
            )

    def test_resolve_base_wz_precedence(self) -> None:
        with unittest.mock.patch.dict(
            "os.environ", {wz_shared.BASE_WZ_ENV_VAR: "/env/base"}, clear=True
        ):
            self.assertEqual(wz_shared.resolve_base_wz("/cli/base"), Path("/cli/base"))
            self.assertEqual(wz_shared.resolve_base_wz(None), Path("/env/base"))
        with unittest.mock.patch.dict("os.environ", {}, clear=True):
            self.assertEqual(
                wz_shared.resolve_base_wz(None), Path(wz_shared.FALLBACK_BASE_WZ)
            )


class TestXmlHelpers(unittest.TestCase):
    def test_child_imgdir(self) -> None:
        root = ET.fromstring(
            '<imgdir name="root">'
            '<string name="info"/>'
            '<imgdir name="info"><int name="cash" value="1"/></imgdir>'
            '<imgdir name="stand1"/>'
            "</imgdir>"
        )
        node = wz_shared.child_imgdir(root, "info")
        self.assertIsNotNone(node)
        assert node is not None
        self.assertEqual(node.tag, "imgdir")  # the <string name="info"/> is skipped
        self.assertIsNotNone(wz_shared.child_imgdir(root, "stand1"))
        self.assertIsNone(wz_shared.child_imgdir(root, "walk1"))

    def test_find_imgdir_path(self) -> None:
        root = ET.fromstring(
            '<imgdir name="root">'
            '<imgdir name="a"><imgdir name="b"><canvas name="0"/></imgdir></imgdir>'
            "</imgdir>"
        )
        node = wz_shared.find_imgdir_path(root, ["a", "b"])
        self.assertIsNotNone(node)
        assert node is not None
        self.assertEqual(node.attrib.get("name"), "b")
        self.assertIsNone(wz_shared.find_imgdir_path(root, ["a", "missing"]))
        # Empty path returns the starting node (both original copies did this).
        self.assertIs(wz_shared.find_imgdir_path(root, []), root)


class TestLinkHelpers(unittest.TestCase):
    def test_asset_id_from_xml(self) -> None:
        self.assertEqual(wz_shared.asset_id_from_xml(Path("0002004.img.xml")), "0002004")
        self.assertEqual(wz_shared.asset_id_from_xml(Path("x/9010000.img.xml")), "9010000")

    def test_extract_info_link(self) -> None:
        root = ET.fromstring(
            '<imgdir name="r"><imgdir name="info">'
            '<int name="link" value="2004"/>'
            "</imgdir></imgdir>"
        )
        self.assertEqual(wz_shared.extract_info_link(root), "2004")
        root2 = ET.fromstring(
            '<imgdir name="r"><imgdir name="info">'
            '<vector name="link" x="1" y="2"/>'
            '<string name="link" value="  9010000  "/>'
            "</imgdir></imgdir>"
        )
        # Non string/int nodes are skipped; value is stripped.
        self.assertEqual(wz_shared.extract_info_link(root2), "9010000")
        root3 = ET.fromstring('<imgdir name="r"><imgdir name="info"/></imgdir>')
        self.assertIsNone(wz_shared.extract_info_link(root3))
        root4 = ET.fromstring('<imgdir name="r"/>')
        self.assertIsNone(wz_shared.extract_info_link(root4))

    def test_resolve_link_target_xml(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            (base / "0002004.img.xml").write_text("<imgdir name='0002004.img'/>")
            (base / "9010000.img.xml").write_text("<imgdir name='9010000.img'/>")
            current = base / "0002004.img.xml"
            # digit link zero-padded to current id width (7 here)
            self.assertEqual(
                wz_shared.resolve_link_target_xml(current, "9010000"),
                base / "9010000.img.xml",
            )
            # short digit link is padded: "2004" -> "0002004.img.xml"
            self.assertEqual(
                wz_shared.resolve_link_target_xml(current, "2004"),
                base / "0002004.img.xml",
            )
            # explicit filename form
            self.assertEqual(
                wz_shared.resolve_link_target_xml(current, "9010000.img.xml"),
                base / "9010000.img.xml",
            )
            self.assertIsNone(wz_shared.resolve_link_target_xml(current, "1234567"))
            self.assertIsNone(wz_shared.resolve_link_target_xml(current, "   "))


class TestDelayHelpers(unittest.TestCase):
    def test_parse_delay_ms(self) -> None:
        self.assertIsNone(wz_shared.parse_delay_ms(None))
        self.assertIsNone(wz_shared.parse_delay_ms(""))
        self.assertIsNone(wz_shared.parse_delay_ms("abc"))
        self.assertEqual(wz_shared.parse_delay_ms(" 120 "), 120)
        # Clamped to minimum 1 (both original copies did this).
        self.assertEqual(wz_shared.parse_delay_ms("0"), 1)
        self.assertEqual(wz_shared.parse_delay_ms(-50), 1)

    def test_extract_node_delay_ms(self) -> None:
        node = ET.fromstring(
            '<imgdir name="0">'
            '<vector name="delay" x="1" y="1"/>'
            '<string name="delay" value="180"/>'
            "</imgdir>"
        )
        self.assertEqual(wz_shared.extract_node_delay_ms(node), 180)
        node2 = ET.fromstring('<imgdir name="0"><int name="z" value="5"/></imgdir>')
        self.assertIsNone(wz_shared.extract_node_delay_ms(node2))

    def test_resolve_uol_target_frame(self) -> None:
        self.assertEqual(wz_shared.resolve_uol_target_frame("3"), 3)
        self.assertEqual(wz_shared.resolve_uol_target_frame("../2"), 2)
        self.assertEqual(wz_shared.resolve_uol_target_frame("a/b/7"), 7)
        self.assertIsNone(wz_shared.resolve_uol_target_frame(""))
        self.assertIsNone(wz_shared.resolve_uol_target_frame("abc"))

    def test_resolve_frame_delay_ms_uol_and_cycles(self) -> None:
        f0 = ET.fromstring('<imgdir name="0"><int name="delay" value="150"/></imgdir>')
        f1 = ET.fromstring('<uol name="1" value="0"/>')
        f2 = ET.fromstring('<uol name="2" value="3"/>')
        f3 = ET.fromstring('<uol name="3" value="2"/>')  # cycle with 2
        frames = {0: f0, 1: f1, 2: f2, 3: f3}
        self.assertEqual(wz_shared.resolve_frame_delay_ms(0, frames, 99), 150)
        self.assertEqual(wz_shared.resolve_frame_delay_ms(1, frames, 99), 150)  # via uol
        self.assertEqual(wz_shared.resolve_frame_delay_ms(2, frames, 99), 99)  # cycle -> default
        self.assertEqual(wz_shared.resolve_frame_delay_ms(7, frames, 99), 99)  # missing

    def test_build_timeline_from_action_node(self) -> None:
        action = ET.fromstring(
            '<imgdir name="stand">'
            '<imgdir name="info"/>'
            '<imgdir name="2"><int name="delay" value="300"/></imgdir>'
            '<imgdir name="0"><int name="delay" value="100"/></imgdir>'
            '<uol name="1" value="0"/>'
            '<imgdir name="notdigit"/>'
            "</imgdir>"
        )
        timeline = wz_shared.build_timeline_from_action_node(action, 120)
        self.assertEqual(
            timeline,
            [
                {"frame": 0, "delay_ms": 100},
                {"frame": 1, "delay_ms": 100},  # inherited via uol
                {"frame": 2, "delay_ms": 300},
            ],
        )

    def test_build_timeline_empty_action_node(self) -> None:
        action = ET.fromstring('<imgdir name="stand"><imgdir name="info"/></imgdir>')
        self.assertEqual(
            wz_shared.build_timeline_from_action_node(action, 77),
            [{"frame": 0, "delay_ms": 77}],
        )


class TestActionDetection(unittest.TestCase):
    def test_detect_actions_in_asset_dir(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td) / "01302000.img"
            _mkpng(base / "stand1" / "0" / "weapon.png")
            _mkpng(base / "walk1" / "0" / "weapon.png")
            (base / "empty_action").mkdir(parents=True)
            _mkpng(base / "info" / "icon.png")  # 'info' always excluded
            (base / "stray.png").write_bytes(b"not-a-dir")
            self.assertEqual(
                wz_shared.detect_actions_in_asset_dir(base), {"stand1", "walk1"}
            )
            self.assertEqual(
                wz_shared.detect_actions_in_asset_dir(Path(td) / "missing"), set()
            )

    def test_count_action_frames(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td) / "01302000.img"
            _mkpng(base / "stand1" / "0" / "weapon.png")
            _mkpng(base / "stand1" / "1" / "weapon.png")
            (base / "stand1" / "2").mkdir()  # numeric but no png
            (base / "stand1" / "effect").mkdir()  # non-numeric ignored
            _mkpng(base / "walk1" / "0" / "weapon.png")
            counts = wz_shared.count_action_frames(base, {"walk1", "stand1", "ghost"})
            self.assertEqual(counts, {"ghost": 0, "stand1": 2, "walk1": 1})

    def test_read_info_strings(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            xml_path = Path(td) / "01302000.img.xml"
            xml_path.write_text(
                '<imgdir name="01302000.img"><imgdir name="info">'
                '<string name="islot" value="Wp"/>'
                '<string name="afterImage" value="swordOL"/>'
                '<int name="cash" value="0"/>'
                "</imgdir></imgdir>"
            )
            self.assertEqual(
                wz_shared.read_info_strings(xml_path),
                {"islot": "Wp", "afterImage": "swordOL"},
            )
            self.assertEqual(wz_shared.read_info_strings(Path(td) / "nope.xml"), {})
            bad = Path(td) / "bad.xml"
            bad.write_text("<imgdir")
            self.assertEqual(wz_shared.read_info_strings(bad), {})
            no_info = Path(td) / "noinfo.xml"
            no_info.write_text('<imgdir name="x"/>')
            self.assertEqual(wz_shared.read_info_strings(no_info), {})


class TestOutputHelpers(unittest.TestCase):
    def test_utc_now_iso_parses_and_is_utc(self) -> None:
        stamp = wz_shared.utc_now_iso()
        parsed = datetime.fromisoformat(stamp)
        self.assertIsNotNone(parsed.tzinfo)
        self.assertEqual(parsed.utcoffset().total_seconds(), 0)  # type: ignore[union-attr]

    def test_safe_name(self) -> None:
        self.assertEqual(wz_shared.safe_name("Cash Item/Etc"), "Cash_Item_Etc")
        self.assertEqual(wz_shared.safe_name("-keep-dash_"), "-keep-dash")
        self.assertEqual(wz_shared.safe_name("__x__"), "x")
        self.assertEqual(wz_shared.safe_name("!!!"), "")

    def test_write_csv_with_headers_writes_header_for_empty_rows(self) -> None:
        # diff_character_assets.py identity-shortcut relies on this.
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "sub" / "out.csv"
            wz_shared.write_csv(path, [], ["a", "b"])
            self.assertEqual(path.read_bytes(), b"a,b\r\n")

    def test_write_csv_derived_headers_skips_empty_rows(self) -> None:
        # build_wz_index.py behavior: no rows -> no file at all.
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "out.csv"
            wz_shared.write_csv(path, [])
            self.assertFalse(path.exists())

    def test_write_csv_derived_headers_from_first_row(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "out.csv"
            wz_shared.write_csv(path, [{"img": "a", "n": 1}, {"img": "b", "n": 2}])
            with path.open(newline="", encoding="utf-8") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(rows, [{"img": "a", "n": "1"}, {"img": "b", "n": "2"}])

    def test_write_csv_explicit_headers_content(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "out.csv"
            wz_shared.write_csv(path, [{"a": "1", "b": "x,y"}], ["a", "b"])
            self.assertEqual(path.read_bytes(), b'a,b\r\n1,"x,y"\r\n')


class TestSpriteSheet(unittest.TestCase):
    def test_build_sprite_sheet_layout(self) -> None:
        from PIL import Image

        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            p0 = base / "f0.png"
            p1 = base / "f1.png"
            p2 = base / "f2.png"
            _mkpng(p0, 4, 6)
            _mkpng(p1, 2, 2)
            _mkpng(p2, 4, 4)
            out = base / "sheets" / "sheet.png"
            info = wz_shared.build_sprite_sheet([p0, p1, p2], out, columns=2)
            # cell = max(4,2,4)+2*2 x max(6,2,4)+2*2 = 8x10; 2 cols, 2 rows
            self.assertEqual(info["cell_size"], [8, 10])
            self.assertEqual(info["sheet_size"], [16, 20])
            self.assertEqual(info["rows"], 2)
            self.assertEqual(info["cols"], 2)
            self.assertEqual(len(info["layout"]), 3)
            self.assertEqual(info["layout"][0]["row"], 0)
            self.assertEqual(info["layout"][2]["row"], 1)
            # frame 1 (2x2) centered in 4x6 content box: x = 8+2+(4-2)//2
            self.assertEqual(info["layout"][1]["x"], 8 + 2 + 1)
            self.assertEqual(info["layout"][1]["y"], 0 + 2 + 2)
            with Image.open(out) as sheet:
                self.assertEqual(sheet.size, (16, 20))

    def test_build_sprite_sheet_clamps_columns(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            p0 = base / "f0.png"
            _mkpng(p0, 2, 2)
            info = wz_shared.build_sprite_sheet([p0], base / "s.png", columns=0)
            self.assertEqual(info["cols"], 1)


class TestNormalizeActionFrameCanvases(unittest.TestCase):
    def _rows(self, base: Path) -> list[dict]:
        p0 = base / "f0.png"
        p1 = base / "f1.png"
        _mkpng(p0, 4, 4)
        _mkpng(p1, 6, 2)
        j1 = base / "f1.json"
        j1.write_text(
            json.dumps({"frame_bounds_world": {"left": 0, "top": 0, "right": 6, "bottom": 2}}),
            encoding="utf-8",
        )
        return [
            {
                "png": str(p0),
                "json": None,
                "frame_bounds_world": {"left": -2, "top": -2, "right": 2, "bottom": 2},
            },
            {
                "png": str(p1),
                "json": str(j1),
                "frame_bounds_world": {"left": 0, "top": 0, "right": 6, "bottom": 2},
            },
        ]

    def test_gui_mode_no_bounds_metadata(self) -> None:
        from PIL import Image

        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            rows = self._rows(base)
            info = wz_shared.normalize_action_frame_canvases(rows)
            assert info is not None
            # union bounds: left -2, top -2, right 6, bottom 2 -> 8x4
            self.assertEqual(info["size"], [8, 4])
            self.assertEqual(info["normalized_frames"], 2)
            self.assertEqual(rows[0]["normalized_canvas_offset"], {"x": 0, "y": 0})
            self.assertEqual(rows[1]["normalized_canvas_offset"], {"x": 2, "y": 2})
            # GUI behavior: no effective_bounds_world, sidecar json untouched.
            self.assertNotIn("effective_bounds_world", rows[0])
            self.assertNotIn("effective_bounds_world", rows[1])
            payload = json.loads((base / "f1.json").read_text(encoding="utf-8"))
            self.assertEqual(
                payload["frame_bounds_world"],
                {"left": 0, "top": 0, "right": 6, "bottom": 2},
            )
            for name in ("f0.png", "f1.png"):
                with Image.open(base / name) as im:
                    self.assertEqual(im.size, (8, 4))

    def test_export_mode_syncs_bounds_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            rows = self._rows(base)
            info = wz_shared.normalize_action_frame_canvases(rows, sync_bounds_metadata=True)
            assert info is not None
            expected_bounds = {"left": -2, "top": -2, "right": 6, "bottom": 2}
            self.assertEqual(rows[0]["effective_bounds_world"], expected_bounds)
            self.assertEqual(rows[1]["effective_bounds_world"], expected_bounds)
            payload = json.loads((base / "f1.json").read_text(encoding="utf-8"))
            self.assertEqual(payload["frame_bounds_world"], expected_bounds)
            self.assertEqual(payload["normalized_canvas_offset"], {"x": 2, "y": 2})
            self.assertEqual(payload["normalized_canvas_size"], [8, 4])

    def test_single_frame_returns_none(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            p0 = base / "f0.png"
            _mkpng(p0, 4, 4)
            rows = [
                {
                    "png": str(p0),
                    "frame_bounds_world": {"left": 0, "top": 0, "right": 4, "bottom": 4},
                }
            ]
            self.assertIsNone(wz_shared.normalize_action_frame_canvases(rows))

    def test_rows_with_missing_png_or_bounds_filtered(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            p0 = base / "f0.png"
            _mkpng(p0, 4, 4)
            rows = [
                {"png": str(p0), "frame_bounds_world": {"left": 0, "top": 0, "right": 4, "bottom": 4}},
                {"png": str(base / "missing.png"), "frame_bounds_world": {"left": 0, "top": 0, "right": 4, "bottom": 4}},
                {"png": str(p0), "frame_bounds_world": {"left": 0, "top": 0}},  # incomplete bounds
                {"png": "", "frame_bounds_world": {"left": 0, "top": 0, "right": 4, "bottom": 4}},
            ]
            # Only one usable row survives filtering -> None.
            self.assertIsNone(wz_shared.normalize_action_frame_canvases(rows))


if __name__ == "__main__":
    unittest.main()
