"""Schema semver contract tests for validate_pack.py (backlog #59).

Policy under test is documented in docs/product/CONTENT_SCHEMA.md
("Schema versioning"): unsupported major -> reject, newer minor within the
supported major -> accept with warning, newer patch -> accept silently.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import re
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from typing import Any
from unittest import mock


MODULE_PATH = Path(__file__).with_name("validate_pack.py")
SPEC = importlib.util.spec_from_file_location("validate_pack", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
validate_pack = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validate_pack
SPEC.loader.exec_module(validate_pack)

REPO_ROOT = MODULE_PATH.parents[2]
CONTENT_DIR = REPO_ROOT / "apps" / "runtime-godot" / "content"
SHIPPED_MANIFESTS = sorted(CONTENT_DIR.glob("*/manifest.json"))
SCHEMA_PATH = REPO_ROOT / "packages" / "content-schema" / "buddy-pack.schema.json"
CONTENT_LOADER = REPO_ROOT / "apps" / "runtime-godot" / "scripts" / "content" / "content_loader.gd"
SCHEMA_DOC = REPO_ROOT / "docs" / "product" / "CONTENT_SCHEMA.md"
MIGRATIONS_DOC = REPO_ROOT / "docs" / "product" / "CONTENT_SCHEMA_MIGRATIONS.md"
CURRENT = validate_pack.format_semver(validate_pack.CURRENT_SCHEMA_SEMVER)


def base_manifest() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "schemaSemver": CURRENT,
        "id": "semver-pack",
        "name": "Semver Pack",
        "version": "0.0.1",
        "companion": {"id": "semver-buddy", "displayName": "Semver Buddy", "traits": ["calm"]},
        "idleActions": ["idle"],
        "reactionActions": ["happy"],
        "encounterActions": [],
        "eventRules": [],
    }


def with_fields(**fields: Any) -> dict[str, Any]:
    manifest = base_manifest()
    manifest.update(fields)
    return manifest


def error_paths(manifest: dict[str, Any]) -> list[str]:
    return [err.path for err in validate_pack.validate_manifest(manifest)]


class ParseSchemaSemverTests(unittest.TestCase):
    def test_accepts_strict_semver(self) -> None:
        self.assertEqual(validate_pack.parse_schema_semver("1.0.0"), (1, 0, 0))
        self.assertEqual(validate_pack.parse_schema_semver("1.12.3"), (1, 12, 3))

    def test_rejects_non_strict_forms(self) -> None:
        for value in ("1", "1.0", "v1.0.0", "01.0.0", "1.0.0-beta", "1.0.0+build", " 1.0.0", "", 1, 1.0, None):
            with self.subTest(value=value):
                self.assertIsNone(validate_pack.parse_schema_semver(value))


class ManifestSemverPolicyTests(unittest.TestCase):
    def test_current_version_is_valid_without_warnings(self) -> None:
        manifest = base_manifest()
        self.assertEqual(validate_pack.validate_manifest(manifest), [])
        self.assertEqual(validate_pack.collect_manifest_warnings(manifest), [])

    def test_missing_schema_semver_is_rejected(self) -> None:
        manifest = base_manifest()
        del manifest["schemaSemver"]
        self.assertIn("manifest.schemaSemver", error_paths(manifest))

    def test_malformed_schema_semver_is_rejected(self) -> None:
        for value in ("1.0", "v1.0.0", 1, "one"):
            with self.subTest(value=value):
                errors = validate_pack.validate_manifest(with_fields(schemaSemver=value))
                self.assertEqual([e.path for e in errors], ["manifest.schemaSemver"])
                self.assertIn("MAJOR.MINOR.PATCH", errors[0].problem)

    def test_unsupported_semver_major_is_rejected(self) -> None:
        for value in ("2.0.0", "0.9.0"):
            with self.subTest(value=value):
                errors = validate_pack.validate_manifest(with_fields(schemaSemver=value))
                self.assertEqual([e.path for e in errors], ["manifest.schemaSemver"])
                self.assertIn("unsupported schema major version", errors[0].problem)

    def test_unsupported_integer_major_is_rejected(self) -> None:
        # Previously the validator accepted any integer >= 1 while the runtime
        # rejected anything above CONTENT_SCHEMA_VERSION.
        errors = validate_pack.validate_manifest(with_fields(schemaVersion=2))
        paths = [e.path for e in errors]
        self.assertIn("manifest.schemaVersion", paths)
        self.assertTrue(any("unsupported schema major version 2" in e.problem for e in errors))

    def test_future_major_in_both_fields_is_rejected(self) -> None:
        errors = validate_pack.validate_manifest(with_fields(schemaVersion=2, schemaSemver="2.0.0"))
        self.assertEqual(
            sorted(e.path for e in errors), ["manifest.schemaSemver", "manifest.schemaVersion"]
        )

    def test_newer_minor_is_accepted_with_warning(self) -> None:
        manifest = with_fields(schemaSemver="1.9.0")
        self.assertEqual(validate_pack.validate_manifest(manifest), [])
        warnings = validate_pack.collect_manifest_warnings(manifest)
        self.assertEqual([w.path for w in warnings], ["manifest.schemaSemver"])
        self.assertIn("newer than this validator", warnings[0].problem)

    def test_newer_patch_is_accepted_silently(self) -> None:
        manifest = with_fields(schemaSemver="1.0.9")
        self.assertEqual(validate_pack.validate_manifest(manifest), [])
        self.assertEqual(validate_pack.collect_manifest_warnings(manifest), [])

    def test_major_mismatch_is_rejected(self) -> None:
        # Only reachable if SUPPORTED_SCHEMA_MAJOR moves; simulate major 2 support.
        with mock.patch.object(validate_pack, "SUPPORTED_SCHEMA_MAJOR", 2):
            errors = validate_pack.validate_manifest(with_fields(schemaVersion=2, schemaSemver="2.0.0"))
            self.assertEqual(errors, [])
            errors = validate_pack.validate_manifest(with_fields(schemaVersion=1, schemaSemver="2.0.0"))
        self.assertTrue(any("does not match schemaVersion" in e.problem for e in errors))


class CliSemverTests(unittest.TestCase):
    def run_cli(self, manifest: dict[str, Any]) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "manifest.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            out = io.StringIO()
            with mock.patch.object(sys, "argv", ["validate_pack.py", str(path)]):
                with contextlib.redirect_stdout(out):
                    code = validate_pack.main()
        return code, out.getvalue()

    def test_cli_warns_but_passes_on_newer_minor(self) -> None:
        code, output = self.run_cli(with_fields(schemaSemver="1.4.0"))
        self.assertEqual(code, 0, output)
        self.assertIn("WARNING: manifest.schemaSemver", output)
        self.assertIn("OK: manifest valid", output)

    def test_cli_fails_on_unsupported_major(self) -> None:
        code, output = self.run_cli(with_fields(schemaVersion=2, schemaSemver="2.0.0"))
        self.assertEqual(code, 1, output)
        self.assertIn("unsupported schema major version", output)


class ContractDriftTests(unittest.TestCase):
    def test_supported_major_matches_runtime_constant(self) -> None:
        source = CONTENT_LOADER.read_text(encoding="utf-8")
        match = re.search(r"^const CONTENT_SCHEMA_VERSION := (\d+)\s*$", source, re.MULTILINE)
        self.assertIsNotNone(match, "CONTENT_SCHEMA_VERSION not found in content_loader.gd")
        assert match is not None
        self.assertEqual(int(match.group(1)), validate_pack.SUPPORTED_SCHEMA_MAJOR)
        self.assertEqual(validate_pack.CURRENT_SCHEMA_SEMVER[0], validate_pack.SUPPORTED_SCHEMA_MAJOR)

    def test_shipped_packs_declare_known_schema_revision(self) -> None:
        self.assertEqual(len(SHIPPED_MANIFESTS), 3)
        for path in SHIPPED_MANIFESTS:
            with self.subTest(pack=path.parent.name):
                manifest = json.loads(path.read_text(encoding="utf-8"))
                parsed = validate_pack.parse_schema_semver(manifest.get("schemaSemver"))
                self.assertIsNotNone(parsed)
                assert parsed is not None
                self.assertLessEqual(parsed, validate_pack.CURRENT_SCHEMA_SEMVER)
                self.assertEqual(manifest.get("schemaVersion"), parsed[0])
                self.assertEqual(validate_pack.validate_manifest(manifest), [])
                self.assertEqual(validate_pack.collect_manifest_warnings(manifest), [])

    def test_schema_document_declares_semver_field(self) -> None:
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertIn("schemaSemver", schema["required"])
        prop = schema["properties"]["schemaSemver"]
        self.assertEqual(prop["type"], "string")
        pattern: re.Pattern[str] = re.compile(str(prop["pattern"]))
        self.assertRegex(CURRENT, pattern)
        self.assertNotRegex(
            f"{validate_pack.SUPPORTED_SCHEMA_MAJOR + 1}.0.0", pattern
        )
        self.assertEqual(
            schema["properties"]["schemaVersion"]["maximum"], validate_pack.SUPPORTED_SCHEMA_MAJOR
        )
        self.assertIn(f"current: {CURRENT}", prop["description"])

    def test_every_current_version_has_migration_notes(self) -> None:
        notes = MIGRATIONS_DOC.read_text(encoding="utf-8")
        heading = re.compile(rf"^## {re.escape(CURRENT)}(\s|$)", re.MULTILINE)
        self.assertRegex(notes, heading, f"add a '## {CURRENT}' entry to {MIGRATIONS_DOC.name}")

    def test_schema_doc_names_current_version(self) -> None:
        doc = SCHEMA_DOC.read_text(encoding="utf-8")
        self.assertIn(f"**Schema version:** {CURRENT} ", doc)

    def test_manifest_fixtures_carry_semver_so_negatives_fail_for_their_own_reason(self) -> None:
        fixture = json.loads(
            (MODULE_PATH.parent / "fixtures" / "invalid_missing_action.json").read_text(encoding="utf-8")
        )
        errors = validate_pack.validate_manifest(deepcopy(fixture))
        self.assertEqual([e.path for e in errors], ["manifest.eventRules[0].action"])


if __name__ == "__main__":
    unittest.main()
