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

    def _relocate_step(self, path: Path, name: str, destination_job: str) -> None:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        target = f"- name: {name}"
        starts = [index for index, line in enumerate(lines) if line.strip() == target]
        self.assertEqual(len(starts), 1)
        start = starts[0]
        step_indent = len(lines[start]) - len(lines[start].lstrip())
        end = start + 1
        while end < len(lines):
            indent = len(lines[end]) - len(lines[end].lstrip())
            if lines[end].strip() and indent <= step_indent:
                break
            end += 1
        step = lines[start:end]
        del lines[start:end]

        job_line = next(
            index
            for index, line in enumerate(lines)
            if line.strip() == f"{destination_job}:"
        )
        job_indent = len(lines[job_line]) - len(lines[job_line].lstrip())
        steps_line = next(
            index
            for index in range(job_line + 1, len(lines))
            if lines[index].strip() == "steps:"
            and len(lines[index]) - len(lines[index].lstrip()) == job_indent + 2
        )
        lines[steps_line + 1 : steps_line + 1] = step
        path.write_text("".join(lines), encoding="utf-8")

    def _insert_direct_key(self, path: Path, target: str, rendered_key_value: str) -> None:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        matches = [index for index, line in enumerate(lines) if line.rstrip("\r\n") == target]
        self.assertEqual(len(matches), 1)
        index = matches[0]
        indent = len(target) - len(target.lstrip()) + 2
        lines.insert(index + 1, f"{' ' * indent}{rendered_key_value}\n")
        path.write_text("".join(lines), encoding="utf-8")

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

    def test_disabling_required_ci_runner_step_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "      - name: Required headless suite (shared local/CI contract)\n        run: |",
                "      - name: Required headless suite (shared local/CI contract)\n"
                "        if: false\n"
                "        run: |",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("shared headless contract" in error for error in errors), errors)

    def test_allowing_required_ci_runner_failure_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "      - name: Required headless suite (shared local/CI contract)\n        run: |",
                "      - name: Required headless suite (shared local/CI contract)\n"
                "        continue-on-error: true\n"
                "        run: |",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("shared headless contract" in error for error in errors), errors)

    def test_required_ci_runner_pipeline_must_propagate_failure(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "      - name: Required headless suite (shared local/CI contract)\n"
                "        run: |\n"
                "          set -euo pipefail\n"
                "          python packages/content-validator/headless_suite.py \\",
                "      - name: Required headless suite (shared local/CI contract)\n"
                "        run: |\n"
                "          set -eu\n"
                "          python packages/content-validator/headless_suite.py \\",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("shared headless contract" in error for error in errors), errors)

    def test_required_jobs_cannot_be_disabled(self) -> None:
        cases = (
            ("parse-and-smoke", "shared headless contract"),
            ("windows-export", "exported default startup"),
        )
        for job, expected_error in cases:
            with self.subTest(job=job):
                def mutate(root: Path, job_id: str = job) -> None:
                    path = root / ".github/workflows/runtime-smoke.yml"
                    self._replace(
                        path,
                        f"  {job_id}:\n    name:",
                        f"  {job_id}:\n    if: false\n    name:",
                    )

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_required_jobs_cannot_allow_or_dynamically_ignore_failure(self) -> None:
        cases = (
            ("parse-and-smoke", "true", "shared headless contract"),
            (
                "parse-and-smoke",
                "${{ github.event_name == 'push' }}",
                "shared headless contract",
            ),
            ("windows-export", "true", "exported default startup"),
            (
                "windows-export",
                "${{ github.event_name == 'push' }}",
                "exported default startup",
            ),
        )
        for job, value, expected_error in cases:
            with self.subTest(job=job, value=value):
                def mutate(root: Path, job_id: str = job, setting: str = value) -> None:
                    path = root / ".github/workflows/runtime-smoke.yml"
                    self._replace(
                        path,
                        f"  {job_id}:\n    name:",
                        f"  {job_id}:\n    continue-on-error: {setting}\n    name:",
                    )

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_required_steps_must_remain_in_their_required_jobs(self) -> None:
        cases = (
            (
                "Required headless suite (shared local/CI contract)",
                "windows-export",
                "shared headless contract",
            ),
            (
                "Start and cleanly exit exported default runtime",
                "parse-and-smoke",
                "exported default startup",
            ),
        )
        for step_name, destination_job, expected_error in cases:
            with self.subTest(step=step_name, destination=destination_job):
                def mutate(
                    root: Path,
                    name: str = step_name,
                    destination: str = destination_job,
                ) -> None:
                    self._relocate_step(
                        root / ".github/workflows/runtime-smoke.yml",
                        name,
                        destination,
                    )

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_required_jobs_cannot_depend_on_a_skipped_job(self) -> None:
        cases = (
            ("parse-and-smoke", "shared headless contract"),
            ("windows-export", "exported default startup"),
        )
        for job, expected_error in cases:
            with self.subTest(job=job):
                def mutate(root: Path, job_id: str = job) -> None:
                    path = root / ".github/workflows/runtime-smoke.yml"
                    self._replace(
                        path,
                        "jobs:\n",
                        "jobs:\n"
                        "  skipped-prerequisite:\n"
                        "    if: false\n"
                        "    runs-on: ubuntu-latest\n"
                        "    steps:\n"
                        "      - run: exit 1\n\n",
                    )
                    self._insert_direct_key(
                        path,
                        f"  {job_id}:",
                        "needs: skipped-prerequisite",
                    )

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_required_job_and_step_metadata_keys_cannot_hide_by_yaml_style(self) -> None:
        scopes = (
            ("  parse-and-smoke:", "shared headless contract"),
            ("  windows-export:", "exported default startup"),
            (
                "      - name: Required headless suite (shared local/CI contract)",
                "shared headless contract",
            ),
            (
                "      - name: Start and cleanly exit exported default runtime",
                "exported default startup",
            ),
        )
        mutations = (
            ("'if': false", "quoted-if"),
            ("if : false", "spaced-if"),
            ('"continue-on-error": true', "quoted-continue"),
            ("continue-on-error : true", "spaced-continue"),
        )
        for target, expected_error in scopes:
            for rendered_key_value, label in mutations:
                with self.subTest(target=target, mutation=label):
                    def mutate(
                        root: Path,
                        mapping_target: str = target,
                        setting: str = rendered_key_value,
                    ) -> None:
                        self._insert_direct_key(
                            root / ".github/workflows/runtime-smoke.yml",
                            mapping_target,
                            setting,
                        )

                    errors = self._errors_after(mutate)
                    self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_duplicate_continue_on_error_cannot_hide_later_true(self) -> None:
        scopes = (
            ("  parse-and-smoke:", "shared headless contract"),
            ("  windows-export:", "exported default startup"),
            (
                "      - name: Required headless suite (shared local/CI contract)",
                "shared headless contract",
            ),
            (
                "      - name: Start and cleanly exit exported default runtime",
                "exported default startup",
            ),
        )
        for target, expected_error in scopes:
            with self.subTest(target=target):
                def mutate(root: Path, mapping_target: str = target) -> None:
                    path = root / ".github/workflows/runtime-smoke.yml"
                    self._insert_direct_key(path, mapping_target, "continue-on-error: true")
                    self._insert_direct_key(path, mapping_target, "continue-on-error: false")

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_required_commands_cannot_follow_early_success_exit(self) -> None:
        cases = (
            (
                "          python packages/content-validator/headless_suite.py \\",
                "          exit 0\n"
                "          python packages/content-validator/headless_suite.py \\",
                "shared headless contract",
            ),
            (
                "          & $exe --headless -- --ci-startup-smoke 2>&1 |",
                "          exit 0\n"
                "          & $exe --headless -- --ci-startup-smoke 2>&1 |",
                "exported default startup",
            ),
        )
        for old, new, expected_error in cases:
            with self.subTest(command=old.strip()):
                def mutate(
                    root: Path,
                    command: str = old,
                    replacement: str = new,
                ) -> None:
                    self._replace(
                        root / ".github/workflows/runtime-smoke.yml",
                        command,
                        replacement,
                    )

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

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

    def test_disabling_exported_startup_step_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "      - name: Start and cleanly exit exported default runtime\n        shell: pwsh",
                "      - name: Start and cleanly exit exported default runtime\n"
                "        if: false\n"
                "        shell: pwsh",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("exported default startup" in error for error in errors), errors)

    def test_allowing_exported_startup_failure_fails(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "      - name: Start and cleanly exit exported default runtime\n        shell: pwsh",
                "      - name: Start and cleanly exit exported default runtime\n"
                "        continue-on-error: true\n"
                "        shell: pwsh",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("exported default startup" in error for error in errors), errors)

    def test_exported_startup_must_check_process_exit(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "          if ($LASTEXITCODE -ne 0) {\n"
                "            Write-Error \"Exported default-runtime startup failed",
                "          if ($false) {\n"
                "            Write-Error \"Exported default-runtime startup failed",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("exported default startup" in error for error in errors), errors)

    def test_exported_startup_must_reject_error_log(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "          if (Select-String -Path ..\\..\\win-startup-smoke.log "
                "-Pattern '^\\s*(SCRIPT ERROR|ERROR):|\\bParse Error\\b' -Quiet) {",
                "          if ($false) {",
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
                "godot-windows-console-pair-${{ env.GODOT_RELEASE }}-v2",
                "godot-windows-${{ env.GODOT_RELEASE }}",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("console/main pair" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
