from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Callable


MODULE_PATH = Path(__file__).with_name("validate_ci_contract.py")
sys.path.insert(0, str(MODULE_PATH.parent))
SPEC = importlib.util.spec_from_file_location("validate_ci_contract", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
validate_ci_contract = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validate_ci_contract)

REPO_ROOT = MODULE_PATH.parents[2]
FIXTURE_FILES = (
    ".github/workflows/runtime-smoke.yml",
    ".github/workflows/python-lint.yml",
    "apps/runtime-godot/project.godot",
    "apps/runtime-godot/toolchain.json",
    "apps/runtime-godot/tests/required_headless_scenes.json",
    "apps/runtime-godot/tests/run_burn_in.ps1",
    "apps/runtime-godot/tests/run_headless_checks.ps1",
)


class CiContractDriftTests(unittest.TestCase):
    def _fixture(self, root: Path) -> None:
        for relative in FIXTURE_FILES:
            source = REPO_ROOT / relative
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        source_tests = REPO_ROOT / "apps/runtime-godot/tests"
        target_tests = root / "apps/runtime-godot/tests"
        for source in source_tests.glob("*Test.tscn"):
            shutil.copy2(source, target_tests / source.name)

    def _replace(self, path: Path, old: str, new: str) -> None:
        original = path.read_text(encoding="utf-8")
        self.assertIn(old, original)
        path.write_text(original.replace(old, new, 1), encoding="utf-8")

    def _errors_after(self, mutation: Callable[[Path], None] | None = None) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._fixture(root)
            if mutation is not None:
                mutation(root)
            return validate_ci_contract.validate(root)

    def test_repository_contract_passes(self) -> None:
        self.assertEqual(self._errors_after(), [])

    def test_removing_project_startup_case_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / "apps/runtime-godot/tests/required_headless_scenes.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            data["tests"] = [row for row in data["tests"] if row["id"] != "project-startup"]
            path.write_text(json.dumps(data), encoding="utf-8")

        errors = self._errors_after(mutate)
        self.assertTrue(any("exactly one project-startup" in error for error in errors), errors)

    def test_drifting_project_startup_arguments_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / "apps/runtime-godot/tests/required_headless_scenes.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            startup = next(row for row in data["tests"] if row["id"] == "project-startup")
            startup["args"] = ["--", "--different-smoke"]
            path.write_text(json.dumps(data), encoding="utf-8")

        errors = self._errors_after(mutate)
        self.assertTrue(any("exact startup contract" in error for error in errors), errors)

    def test_commenting_shared_ci_runner_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "          python packages/content-validator/headless_suite.py \\",
                "          # python packages/content-validator/headless_suite.py \\",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("actively execute the shared" in error for error in errors), errors)

    def test_commenting_exported_startup_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "          & $exe --headless -- --ci-startup-smoke 2>&1 |",
                "          # & $exe --headless -- --ci-startup-smoke 2>&1 |",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("exported default startup" in error for error in errors), errors)

    def test_commenting_python_suite_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/python-lint.yml"
            self._replace(
                path,
                "          python -m pytest -q tools/importers/tests",
                "          # python -m pytest -q tools/importers/tests",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("tools/importers/tests" in error for error in errors), errors)

    def test_commenting_local_runner_invocation_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / "apps/runtime-godot/tests/run_headless_checks.ps1"
            self._replace(path, "& $Python $runner `", "# & $Python $runner `")

        errors = self._errors_after(mutate)
        self.assertTrue(any("local headless script" in error for error in errors), errors)

    def test_gui_binary_cache_regression_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "godot-windows-console-${{ env.GODOT_RELEASE }}-v1",
                "godot-windows-${{ env.GODOT_RELEASE }}",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("console executable" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
