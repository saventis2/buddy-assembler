from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("headless_suite.py")
SPEC = importlib.util.spec_from_file_location("headless_suite", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
headless_suite = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = headless_suite
SPEC.loader.exec_module(headless_suite)


class ContractTests(unittest.TestCase):
    def test_empty_suite_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            contract = root / "suite.json"
            contract.write_text('{"schema_version": 1, "tests": []}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "at least one test"):
                headless_suite.load_contract(contract, root)

    def test_duplicate_id_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tests = root / "tests"
            tests.mkdir()
            (tests / "OneTest.tscn").write_text("[gd_scene format=3]", encoding="utf-8")
            contract = root / "suite.json"
            contract.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "tests": [
                            {"id": "one", "scene": "res://tests/OneTest.tscn", "pass_marker": "PASS"},
                            {"id": "one", "args": ["--", "--smoke"], "pass_marker": "PASS"},
                        ]
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "duplicated"):
                headless_suite.load_contract(contract, root)


class RunnerTests(unittest.TestCase):
    def _contracts(self, root: Path) -> tuple[Path, Path]:
        toolchain = root / "toolchain.json"
        toolchain.write_text(
            json.dumps(
                {
                    "godot_version": "4.2.2",
                    "godot_release": "4.2.2-stable",
                    "reported_version_prefix": "4.2.2.stable",
                }
            ),
            encoding="utf-8",
        )
        contract = root / "suite.json"
        contract.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "tests": [
                        {
                            "id": "startup",
                            "args": ["--", "--ci-startup-smoke"],
                            "pass_marker": "startup: PASS",
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        return contract, toolchain

    def _run_with(self, child: subprocess.CompletedProcess[str]) -> int:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            contract, toolchain = self._contracts(root)
            runner = mock.Mock(
                side_effect=[
                    subprocess.CompletedProcess(["godot", "--version"], 0, "4.2.2.stable.test\n", ""),
                    child,
                ]
            )
            return headless_suite.run_suite(
                godot="godot",
                project=root,
                contract=contract,
                toolchain=toolchain,
                timeout_seconds=10,
                command_runner=runner,
            )

    def test_child_failure_is_not_false_green(self) -> None:
        result = self._run_with(subprocess.CompletedProcess(["godot"], 9, "startup: PASS\n", ""))
        self.assertEqual(result, 1)

    def test_missing_pass_marker_is_not_false_green(self) -> None:
        result = self._run_with(subprocess.CompletedProcess(["godot"], 0, "no marker\n", ""))
        self.assertEqual(result, 1)

    def test_pass_marker_must_be_a_complete_line(self) -> None:
        result = self._run_with(
            subprocess.CompletedProcess(["godot"], 0, "prefix startup: PASS suffix\n", "")
        )
        self.assertEqual(result, 1)


if __name__ == "__main__":
    unittest.main()
