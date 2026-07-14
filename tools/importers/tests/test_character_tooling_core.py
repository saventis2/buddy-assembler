"""Unit tests for tools/importers/character_tooling_core.py (backlog #44).

Each test pins the exact behavior the extracted function inherited from its
``character_tooling_gui.App`` method, using synthetic fixtures (no real WZ
data -- same constraint as every prior importer-tooling task). Run with:

    python3 -m unittest discover -s tools/importers/tests -v
"""

from __future__ import annotations

import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import character_tooling_core as core  # noqa: E402


def _mkpng(path: Path, width: int = 1, height: int = 1, color=(255, 0, 0, 255)) -> None:
    from PIL import Image

    path.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (width, height), color)
    img.save(path)
    img.close()


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class TestSmallHelpers(unittest.TestCase):
    def test_int_or_none(self) -> None:
        self.assertIsNone(core.int_or_none(""))
        self.assertIsNone(core.int_or_none("   "))
        self.assertEqual(core.int_or_none(" 42 "), 42)
        with self.assertRaises(ValueError):
            core.int_or_none("abc")

    def test_coerce_bool(self) -> None:
        self.assertTrue(core.coerce_bool(True))
        self.assertFalse(core.coerce_bool(False))
        self.assertTrue(core.coerce_bool(1))
        self.assertFalse(core.coerce_bool(0))
        self.assertTrue(core.coerce_bool(0.5))
        self.assertTrue(core.coerce_bool(" TRUE "))
        self.assertTrue(core.coerce_bool("yes"))
        self.assertTrue(core.coerce_bool("on"))
        self.assertTrue(core.coerce_bool("1"))
        self.assertFalse(core.coerce_bool("0"))
        self.assertFalse(core.coerce_bool("no"))
        self.assertFalse(core.coerce_bool(None))
        self.assertFalse(core.coerce_bool([1]))

    def test_format_count_map(self) -> None:
        self.assertEqual(core.format_count_map(None), "(none)")
        self.assertEqual(core.format_count_map({}), "(none)")
        self.assertEqual(core.format_count_map({"b": 2, "a": 1}), "a:1, b:2")

    def test_build_character_identifier_stable_and_none_empty_equivalent(self) -> None:
        ids: dict[str, object] = {"base_id": 2000, "head_id": 12000, "weapon_id": 1302000}
        first = core.build_character_identifier(ids)
        second = core.build_character_identifier(dict(ids))
        self.assertEqual(first, second)
        self.assertEqual(len(first), 10)
        self.assertTrue(first.isdigit())
        # None slots serialize as "" -- absent key and None key are identical.
        with_none = dict(ids)
        with_none["cap_id"] = None
        self.assertEqual(core.build_character_identifier(with_none), first)
        # Changing any slot changes the identifier.
        changed = dict(ids)
        changed["weapon_id"] = 1302001
        self.assertNotEqual(core.build_character_identifier(changed), first)


class TestValidateBaseWz(unittest.TestCase):
    def test_missing_path(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            missing = Path(td) / "nope"
            err = core.validate_base_wz(missing)
            assert err is not None
            self.assertIn("does not exist", err)

    def test_missing_character_tree(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            err = core.validate_base_wz(Path(td))
            assert err is not None
            self.assertIn("Missing Character tree", err)

    def test_valid(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            (Path(td) / "Character" / "Character.wz").mkdir(parents=True)
            self.assertIsNone(core.validate_base_wz(Path(td)))


class TestBaseTemplateXml(unittest.TestCase):
    def test_zero_padded_path(self) -> None:
        base = Path("/base")
        self.assertEqual(
            core.base_template_xml(base, 2000),
            base / "Character" / "Character.wz" / "00002000.img.xml",
        )


class TestEqpNameIndex(unittest.TestCase):
    def test_missing_file_returns_empty(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            self.assertEqual(core.load_eqp_name_index(Path(td)), {})

    def test_parses_names_and_skips_non_digit_and_unnamed(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            _write(
                base / "String" / "String.wz" / "Eqp.img.xml",
                '<imgdir name="Eqp.img">'
                '<imgdir name="Eqp">'
                '<imgdir name="Weapon">'
                '<imgdir name="1302000"><string name="name" value="Sword"/></imgdir>'
                '<imgdir name="1302001"><string name="desc" value="no name field"/></imgdir>'
                '<imgdir name="notdigit"><string name="name" value="Bad"/></imgdir>'
                "</imgdir>"
                '<imgdir name="Cap">'
                '<imgdir name="1002000"><string name="name" value="Blue Bandana"/></imgdir>'
                "</imgdir>"
                "</imgdir>"
                "</imgdir>",
            )
            idx = core.load_eqp_name_index(base)
            self.assertEqual(
                idx,
                {
                    1302000: {"category": "Weapon", "name": "Sword"},
                    1002000: {"category": "Cap", "name": "Blue Bandana"},
                },
            )


class TestReadIntField(unittest.TestCase):
    def test_present_int(self) -> None:
        node = ET.fromstring('<imgdir><int name="reqJob" value="1"/></imgdir>')
        self.assertEqual(core.read_int_field(node, "reqJob"), 1)

    def test_absent_returns_default(self) -> None:
        node = ET.fromstring("<imgdir/>")
        self.assertEqual(core.read_int_field(node, "reqJob", default=7), 7)

    def test_missing_value_attribute_returns_default(self) -> None:
        # GUI semantics (deliberately NOT audit_dataset_metadata's): a bare
        # <int name=...> without value falls back to the caller's default.
        node = ET.fromstring('<imgdir><int name="reqJob"/></imgdir>')
        self.assertEqual(core.read_int_field(node, "reqJob", default=7), 7)

    def test_non_numeric_value_returns_default(self) -> None:
        node = ET.fromstring('<imgdir><int name="reqJob" value="x"/></imgdir>')
        self.assertEqual(core.read_int_field(node, "reqJob", default=3), 3)

    def test_non_int_tag_ignored(self) -> None:
        node = ET.fromstring('<imgdir><string name="reqJob" value="9"/></imgdir>')
        self.assertEqual(core.read_int_field(node, "reqJob"), 0)


def _make_weapon_fixture(base: Path) -> None:
    weapon_dir = base / "Character" / "Character.wz" / "Weapon"
    _write(
        weapon_dir / "01302000.img.xml",
        '<imgdir name="01302000.img">'
        '<imgdir name="info">'
        '<int name="reqJob" value="1"/><int name="reqLevel" value="10"/>'
        '<int name="reqSTR" value="35"/>'
        "</imgdir>"
        '<imgdir name="stand1"><imgdir name="0"/></imgdir>'
        '<imgdir name="swingO1"><imgdir name="0"/><imgdir name="1"/></imgdir>'
        '<imgdir name="emptyaction"><string name="x" value="y"/></imgdir>'
        "</imgdir>",
    )
    _write(
        weapon_dir / "01472000.img.xml",
        '<imgdir name="01472000.img">'
        '<imgdir name="info"><int name="reqJob" value="8"/><int name="reqLevel" value="5"/></imgdir>'
        '<imgdir name="stabO1"><imgdir name="0"/></imgdir>'
        '<imgdir name="stand1"><imgdir name="0"/></imgdir>'
        "</imgdir>",
    )
    # No info node: skipped entirely.
    _write(weapon_dir / "01312000.img.xml", '<imgdir name="01312000.img"><imgdir name="stand1"><imgdir name="0"/></imgdir></imgdir>')
    # Non-digit stem: skipped.
    _write(weapon_dir / "Afterimage.img.xml", '<imgdir name="Afterimage.img"><imgdir name="info"/></imgdir>')


class TestWeaponMetaIndex(unittest.TestCase):
    def test_parses_requirements_and_actions(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            _make_weapon_fixture(base)
            eqp_names = {1302000: {"category": "Weapon", "name": "Sword"}}
            out = core.load_weapon_meta_index(base, eqp_names)
            self.assertEqual(sorted(out.keys()), [1302000, 1472000])
            sword = out[1302000]
            self.assertEqual(sword["name"], "Sword")
            self.assertEqual(sword["weapon_type"], 130)
            self.assertEqual(sword["req_job"], 1)
            self.assertEqual(sword["req_level"], 10)
            self.assertEqual(sword["req_str"], 35)
            self.assertEqual(sword["req_dex"], 0)
            # Only imgdirs with numeric frame children count as actions.
            self.assertEqual(sword["actions"], ["stand1", "swingO1"])
            claw = out[1472000]
            self.assertEqual(claw["name"], "")
            self.assertEqual(claw["actions"], ["stabO1", "stand1"])

    def test_missing_weapon_dir(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            self.assertEqual(core.load_weapon_meta_index(Path(td), {}), {})


class TestPickWeaponForClass(unittest.TestCase):
    def _weapons(self) -> dict[int, dict]:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            _make_weapon_fixture(base)
            return core.load_weapon_meta_index(base, {1302000: {"category": "Weapon", "name": "Sword"}})

    def test_custom_returns_none(self) -> None:
        self.assertIsNone(
            core.pick_weapon_for_class("Custom", body_actions={"stand1"}, weapons=self._weapons())
        )
        self.assertIsNone(
            core.pick_weapon_for_class("NoSuchClass", body_actions={"stand1"}, weapons=self._weapons())
        )

    def test_warrior_prefers_matching_job_and_type(self) -> None:
        weapons = self._weapons()
        picked = core.pick_weapon_for_class(
            "Warrior", body_actions={"stand1", "swingO1", "walk1"}, weapons=weapons
        )
        assert picked is not None
        self.assertEqual(picked["item_id"], 1302000)
        # Preferred action list ("swingO1" before "stand1") drives the pick.
        self.assertEqual(picked["suggested_action"], "swingO1")

    def test_job_mask_filters_out_wrong_class(self) -> None:
        weapons = self._weapons()
        picked = core.pick_weapon_for_class(
            "Thief", body_actions={"stand1", "stabO1"}, weapons=weapons
        )
        assert picked is not None
        self.assertEqual(picked["item_id"], 1472000)
        self.assertEqual(picked["suggested_action"], "stabO1")

    def test_no_common_actions_returns_none(self) -> None:
        weapons = self._weapons()
        picked = core.pick_weapon_for_class(
            "Warrior", body_actions={"prone"}, weapons=weapons
        )
        self.assertIsNone(picked)


class TestBodyIdPools(unittest.TestCase):
    def test_pools_partitioned_and_sorted(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            char_root = base / "Character" / "Character.wz"
            for name in ("00002001.img.xml", "00002000.img.xml", "00012000.img.xml",
                         "00025000.img.xml", "notdigit.img.xml"):
                _write(char_root / name, "<imgdir/>")
            pools = core.get_body_id_pools(base)
            self.assertEqual(pools["base_id"], [2000, 2001])
            self.assertEqual(pools["head_id"], [12000])

    def test_missing_root(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            pools = core.get_body_id_pools(Path(td))
            self.assertEqual(pools, {"base_id": [], "head_id": []})


class TestActionDetection(unittest.TestCase):
    def _make_body(self, base: Path, base_id: int = 2000) -> Path:
        body_dir = base / "Character" / "Character.wz" / f"{base_id:08d}.img"
        _mkpng(body_dir / "stand1" / "0" / "body.png")
        _mkpng(body_dir / "walk1" / "0" / "body.png")
        _mkpng(body_dir / "walk1" / "1" / "body.png")
        (body_dir / "info").mkdir(parents=True, exist_ok=True)
        return body_dir

    def test_detect_actions(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            self._make_body(base)
            self.assertEqual(core.detect_actions(base, 2000), ["stand1", "walk1"])

    def test_detect_action_frames_from_filesystem(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            self._make_body(base)
            self.assertEqual(core.detect_action_frames(base, 2000, "walk1"), [0, 1])

    def test_detect_action_frames_missing_action_dir(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            self._make_body(base)
            self.assertEqual(core.detect_action_frames(base, 2000, "prone"), [])

    def test_detect_action_frames_xml_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            body_dir = base / "Character" / "Character.wz" / "00002000.img"
            (body_dir / "alert").mkdir(parents=True)  # exists but has no PNG frames
            _write(
                base / "Character" / "Character.wz" / "00002000.img.xml",
                '<imgdir name="00002000.img">'
                '<imgdir name="alert"><imgdir name="0"/><imgdir name="2"/></imgdir>'
                "</imgdir>",
            )
            self.assertEqual(core.detect_action_frames(base, 2000, "alert"), [0, 2])

    def test_detect_action_frames_xml_fallback_defaults_to_frame_zero(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            body_dir = base / "Character" / "Character.wz" / "00002000.img"
            (body_dir / "alert").mkdir(parents=True)
            _write(
                base / "Character" / "Character.wz" / "00002000.img.xml",
                '<imgdir name="00002000.img"><imgdir name="alert"/></imgdir>',
            )
            self.assertEqual(core.detect_action_frames(base, 2000, "alert"), [0])

    def test_weapon_action_profile(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            weapon_dir = base / "Character" / "Character.wz" / "Weapon" / "01302000.img"
            _mkpng(weapon_dir / "stand1" / "0" / "weapon.png")
            _mkpng(weapon_dir / "swingO1" / "0" / "weapon.png")
            _mkpng(weapon_dir / "swingO1" / "1" / "weapon.png")
            _write(
                base / "Character" / "Character.wz" / "Weapon" / "01302000.img.xml",
                '<imgdir name="01302000.img">'
                '<imgdir name="info"><string name="afterImage" value="swordOL"/></imgdir>'
                "</imgdir>",
            )
            profile = core.weapon_action_profile(base, 1302000)
            self.assertEqual(profile["weapon_id"], 1302000)
            self.assertEqual(profile["weapon_type_code"], 130)
            self.assertEqual(profile["supported_actions"], ["stand1", "swingO1"])
            self.assertEqual(profile["frame_counts"], {"stand1": 1, "swingO1": 2})
            self.assertEqual(profile["info"], {"afterImage": "swordOL"})


class TestDetectActionsForLoadout(unittest.TestCase):
    def _make_asset(self, root: Path, rel: str, actions: list[str]) -> None:
        for action in actions:
            _mkpng(root / rel / action / "0" / "part.png")

    def test_body_only_mode(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            char_root = Path(td) / "Character" / "Character.wz"
            self._make_asset(char_root, "00002000.img", ["stand1", "walk1", "prone"])
            self._make_asset(char_root, "Weapon/01302000.img", ["stand1"])
            actions = core.detect_actions_for_loadout(
                Path(td),
                {"base_id": 2000, "weapon_id": 1302000, "head_id": None, "hair_id": None},
                "body-only",
            )
            self.assertEqual(actions, ["prone", "stand1", "walk1"])

    def test_intersection_with_weapon(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            char_root = Path(td) / "Character" / "Character.wz"
            self._make_asset(char_root, "00002000.img", ["stand1", "walk1", "prone"])
            self._make_asset(char_root, "00012000.img", ["stand1", "walk1", "prone"])
            self._make_asset(char_root, "Weapon/01302000.img", ["stand1", "walk1"])
            actions = core.detect_actions_for_loadout(
                Path(td),
                {"base_id": 2000, "head_id": 12000, "weapon_id": 1302000},
                "loadout-intersection-with-weapon",
            )
            self.assertEqual(actions, ["stand1", "walk1"])

    def test_intersection_without_weapon_ignores_weapon_dir(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            char_root = Path(td) / "Character" / "Character.wz"
            self._make_asset(char_root, "00002000.img", ["stand1", "walk1"])
            self._make_asset(char_root, "Weapon/01302000.img", ["stand1"])
            actions = core.detect_actions_for_loadout(
                Path(td),
                {"base_id": 2000, "weapon_id": 1302000},
                "loadout-intersection",
            )
            self.assertEqual(actions, ["stand1", "walk1"])

    def test_longcoat_suppresses_coat_and_pants(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            char_root = Path(td) / "Character" / "Character.wz"
            self._make_asset(char_root, "00002000.img", ["stand1", "walk1"])
            self._make_asset(char_root, "Longcoat/01050000.img", ["stand1", "walk1"])
            # Coat/Pants dirs would restrict to stand1 only -- must be ignored.
            self._make_asset(char_root, "Coat/01040002.img", ["stand1"])
            self._make_asset(char_root, "Pants/01060002.img", ["stand1"])
            actions = core.detect_actions_for_loadout(
                Path(td),
                {
                    "base_id": 2000,
                    "coat_id": 1040002,
                    "pants_id": 1060002,
                    "longcoat_id": 1050000,
                },
                "loadout-intersection",
            )
            self.assertEqual(actions, ["stand1", "walk1"])

    def test_empty_intersection_strict_vs_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            char_root = Path(td) / "Character" / "Character.wz"
            self._make_asset(char_root, "00002000.img", ["stand1"])
            self._make_asset(char_root, "Weapon/01302000.img", ["swingO1"])
            strict = core.detect_actions_for_loadout(
                Path(td),
                {"base_id": 2000, "weapon_id": 1302000},
                "loadout-intersection-with-weapon",
            )
            self.assertEqual(strict, [])
            # Non-weapon mode: weapon dir is not consulted at all, so the
            # body's own actions survive.
            relaxed = core.detect_actions_for_loadout(
                Path(td),
                {"base_id": 2000, "weapon_id": 1302000},
                "loadout-intersection",
            )
            self.assertEqual(relaxed, ["stand1"])


class TestDetectActionTimeline(unittest.TestCase):
    def _fixture(self, td: str) -> Path:
        base = Path(td)
        body_dir = base / "Character" / "Character.wz" / "00002000.img"
        _mkpng(body_dir / "walk1" / "0" / "body.png")
        _mkpng(body_dir / "walk1" / "1" / "body.png")
        _mkpng(body_dir / "walk1" / "2" / "body.png")
        _write(
            base / "Character" / "Character.wz" / "00002000.img.xml",
            '<imgdir name="00002000.img">'
            '<imgdir name="walk1">'
            '<imgdir name="0"><int name="delay" value="180"/></imgdir>'
            '<imgdir name="1"><int name="delay" value="-5"/></imgdir>'
            '<imgdir name="2"/>'
            "</imgdir>"
            "</imgdir>",
        )
        return base

    def test_delays_from_template_with_default_fill(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = self._fixture(td)
            timeline = core.detect_action_timeline(base, 2000, "walk1", default_delay_ms=120)
            self.assertEqual(
                timeline,
                [
                    {"frame": 0, "delay_ms": 180},
                    {"frame": 1, "delay_ms": 1},  # non-positive delay clamps to 1
                    {"frame": 2, "delay_ms": 120},  # missing delay -> default
                ],
            )

    def test_no_frames_returns_empty(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = self._fixture(td)
            self.assertEqual(
                core.detect_action_timeline(base, 2000, "prone", default_delay_ms=120), []
            )

    def test_default_delay_clamped_to_one(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = self._fixture(td)
            timeline = core.detect_action_timeline(base, 2000, "walk1", default_delay_ms=0)
            self.assertEqual(timeline[2], {"frame": 2, "delay_ms": 1})

    def test_missing_template_xml_uses_default(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            body_dir = base / "Character" / "Character.wz" / "00002000.img"
            _mkpng(body_dir / "stand1" / "0" / "body.png")
            timeline = core.detect_action_timeline(base, 2000, "stand1", default_delay_ms=90)
            self.assertEqual(timeline, [{"frame": 0, "delay_ms": 90}])


class TestBuildGif(unittest.TestCase):
    def _mk_multicolor(self, path: Path) -> None:
        # Multi-color first frame so the master palette isn't degenerate
        # (a solid-color palette would quantize every frame identically and
        # Pillow would then merge the duplicate frames).
        from PIL import Image

        path.parent.mkdir(parents=True, exist_ok=True)
        img = Image.new("RGBA", (4, 4), (255, 0, 0, 255))
        img.putpixel((0, 0), (0, 255, 0, 255))
        img.putpixel((1, 0), (0, 0, 0, 255))
        img.putpixel((2, 0), (255, 255, 255, 255))
        img.save(path)
        img.close()

    def test_builds_gif_with_per_frame_durations(self) -> None:
        from PIL import Image

        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            f0 = base / "f0.png"
            f1 = base / "f1.png"
            self._mk_multicolor(f0)
            _mkpng(f1, 2, 2, (0, 255, 0, 255))  # smaller: centered onto 4x4
            out = base / "sub" / "anim.gif"
            info = core.build_gif([f0, f1], out, duration_ms=120, durations_ms=[100, 250])
            self.assertTrue(out.exists())
            self.assertEqual(info["gif_path"], str(out))
            self.assertEqual(info["size"], [4, 4])
            self.assertEqual(info["frame_count"], 2)
            self.assertEqual(info["duration_ms"], 120)
            self.assertEqual(info["durations_ms"], [100, 250])
            self.assertEqual(info["total_duration_ms"], 350)
            self.assertEqual(info["mode"], "opaque_flattened")
            self.assertEqual(info["bg_rgb"], [0, 0, 0])
            self.assertGreater(info["bytes"], 0)
            with Image.open(out) as gif:
                self.assertEqual(getattr(gif, "n_frames"), 2)
                gif.seek(0)
                self.assertEqual(gif.info["duration"], 100)
                gif.seek(1)
                self.assertEqual(gif.info["duration"], 250)

    def test_fixed_duration_when_durations_length_mismatch(self) -> None:
        from PIL import Image

        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            f0 = base / "f0.png"
            f1 = base / "f1.png"
            self._mk_multicolor(f0)
            _mkpng(f1, 2, 2, (0, 255, 0, 255))
            out = base / "anim.gif"
            info = core.build_gif([f0, f1], out, duration_ms=80, durations_ms=[100])
            # Length-mismatched durations fall back to the fixed duration for
            # the actual GIF frames, but the metadata still echoes the raw
            # durations list -- pinned original GUI behavior.
            self.assertEqual(info["durations_ms"], [100])
            self.assertEqual(info["total_duration_ms"], 100)
            with Image.open(out) as gif:
                gif.seek(0)
                self.assertEqual(gif.info["duration"], 80)


class TestCatalogueHelpers(unittest.TestCase):
    def test_normalize_catalogue_rows_passthrough(self) -> None:
        rows = [{"id": "1", "part_category": "Coat"}]
        self.assertIs(core.normalize_catalogue_rows(rows, itemwz_mode=False), rows)

    def test_normalize_catalogue_rows_itemwz_mapping(self) -> None:
        rows = [
            {
                "id": "2000000",
                "item_root": "Consume",
                "group_file": "0200.img",
                "slot_max": "100",
                "price": "10",
            }
        ]
        out = core.normalize_catalogue_rows(rows, itemwz_mode=True)
        self.assertEqual(out[0]["part_category"], "Consume")
        self.assertEqual(out[0]["eqp_category"], "0200.img")
        self.assertEqual(out[0]["islot"], "100")
        self.assertEqual(out[0]["vslot"], "10")
        # Original row is not mutated.
        self.assertNotIn("part_category", rows[0])

    def test_infer_slot_from_catalogue_categories(self) -> None:
        self.assertEqual(core.infer_slot_from_catalogue_categories("Weapon", ""), "weapon_id")
        self.assertEqual(core.infer_slot_from_catalogue_categories("", "Cap"), "cap_id")
        # Normalization: case, spaces, underscores.
        self.assertEqual(core.infer_slot_from_catalogue_categories("Long_coat", ""), "longcoat_id")
        self.assertEqual(core.infer_slot_from_catalogue_categories(" LONG COAT ", ""), "longcoat_id")
        # part_category wins over eqp_category.
        self.assertEqual(core.infer_slot_from_catalogue_categories("Cape", "Weapon"), "cape_id")
        self.assertIsNone(core.infer_slot_from_catalogue_categories("Taming", "Mob"))
        self.assertIsNone(core.infer_slot_from_catalogue_categories("", ""))

    def test_resolve_catalogue_icon_path_prefers_png_dir_relpath(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            _mkpng(base / "Item" / "Item.wz" / "0200.img" / "info" / "icon.png")
            _mkpng(
                base / "Character" / "Character.wz" / "Cap" / "01002000.img" / "info" / "icon.png"
            )
            item = {
                "id": "1002000",
                "part_category": "Cap",
                "png_dir_relpath": "Item/Item.wz/0200.img",
            }
            resolved = core.resolve_catalogue_icon_path(base, item)
            self.assertEqual(resolved, base / "Item" / "Item.wz" / "0200.img" / "info" / "icon.png")

    def test_resolve_catalogue_icon_path_guesses_from_id_and_category(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            icon = (
                base / "Character" / "Character.wz" / "Cap" / "01002000.img" / "info" / "iconRaw.png"
            )
            _mkpng(icon)
            item = {"id": "1002000", "part_category": "Cap"}
            self.assertEqual(core.resolve_catalogue_icon_path(base, item), icon)

    def test_resolve_catalogue_icon_path_missing(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            (base / "x").mkdir()
            self.assertIsNone(core.resolve_catalogue_icon_path(base, {"id": "1", "part_category": "Cap"}))

    def test_resolve_catalogue_icon_path_nonexistent_base(self) -> None:
        self.assertIsNone(
            core.resolve_catalogue_icon_path(Path("/definitely/not/here"), {"id": "1"})
        )


class TestClassPresets(unittest.TestCase):
    def test_preset_names_unchanged(self) -> None:
        self.assertEqual(
            list(core.CLASS_PRESET_DEFS.keys()),
            ["Custom", "Warrior", "Mage", "Bowman", "Thief", "Pirate"],
        )


if __name__ == "__main__":
    unittest.main()
