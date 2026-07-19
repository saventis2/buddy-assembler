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

    def _insert_run_shell_default(self, path: Path, target: str | None) -> None:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        default = 'defaults:\n  run:\n    shell: python -c "raise SystemExit(0)" {0}\n'
        if target is None:
            lines[0:0] = default.splitlines(keepends=True)
        else:
            matches = [
                index for index, line in enumerate(lines) if line.rstrip("\r\n") == target
            ]
            self.assertEqual(len(matches), 1)
            indent = len(target) - len(target.lstrip()) + 2
            lines[matches[0] + 1 : matches[0] + 1] = [
                f"{' ' * indent}defaults:\n",
                f"{' ' * (indent + 2)}run:\n",
                f"{' ' * (indent + 4)}shell: python -c \"raise SystemExit(0)\" {{0}}\n",
            ]
        path.write_text("".join(lines), encoding="utf-8")

    def _insert_matrix_step_decoy(self, path: Path, job_id: str, name: str) -> None:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        target = f"- name: {name}"
        starts = [index for index, line in enumerate(lines) if line.strip() == target]
        self.assertEqual(len(starts), 1)
        start = starts[0]
        item_indent = len(lines[start]) - len(lines[start].lstrip())
        end = start + 1
        while end < len(lines):
            child = lines[end]
            child_indent = len(child) - len(child.lstrip())
            if child.strip() and child_indent <= item_indent:
                break
            end += 1
        step = [f"    {line}" if line.strip() else line for line in lines[start:end]]

        job_target = f"  {job_id}:"
        job_matches = [
            index for index, line in enumerate(lines) if line.rstrip("\r\n") == job_target
        ]
        self.assertEqual(len(job_matches), 1)
        insertion = [
            "    strategy:\n",
            "      matrix:\n",
            "        include:\n",
            *step,
        ]
        job_index = job_matches[0]
        lines[job_index + 1 : job_index + 1] = insertion
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

    def test_authority_workflow_digests_match_repository(self) -> None:
        for relative, expected in validate_ci_contract._AUTHORITY_WORKFLOW_SHA256.items():
            with self.subTest(workflow=relative):
                text = (REPO_ROOT / relative).read_text(encoding="utf-8")
                self.assertEqual(
                    validate_ci_contract._normalized_text_sha256(text), expected
                )

    def test_runtime_workflow_digest_rejects_top_level_bash_env(self) -> None:
        def mutate(root: Path) -> None:
            self._insert_direct_key(
                root / ".github/workflows/runtime-smoke.yml",
                "env:",
                "BASH_ENV: /tmp/buddy-ci-skip.sh",
            )

        errors = self._errors_after(mutate)
        self.assertIn(
            "runtime workflow differs from canonical full-file authority digest",
            errors,
        )

    def test_runtime_workflow_digest_rejects_runtime_dir_decoy(self) -> None:
        def mutate(root: Path) -> None:
            self._replace(
                root / ".github/workflows/runtime-smoke.yml",
                "  RUNTIME_DIR: apps/runtime-godot",
                "  RUNTIME_DIR: .ci/decoy-runtime",
            )

        errors = self._errors_after(mutate)
        self.assertIn(
            "runtime workflow differs from canonical full-file authority digest",
            errors,
        )

    def test_runtime_workflow_digest_rejects_prior_github_env_poisoning(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            target = "      - name: Required headless suite (shared local/CI contract)"
            injected = (
                "      - name: Poison required shell environment\n"
                "        run: |\n"
                "          printf 'exit 0\\n' > /tmp/buddy-ci-skip.sh\n"
                "          echo 'BASH_ENV=/tmp/buddy-ci-skip.sh' >> \"$GITHUB_ENV\"\n\n"
            )
            self._replace(path, target, injected + target)

        errors = self._errors_after(mutate)
        self.assertIn(
            "runtime workflow differs from canonical full-file authority digest",
            errors,
        )

    def test_runtime_workflow_digest_rejects_prior_github_path_poisoning(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            target = "      - name: Required headless suite (shared local/CI contract)"
            injected = (
                "      - name: Prepend fake Python\n"
                "        run: |\n"
                "          mkdir -p /tmp/buddy-ci-bin\n"
                "          printf '#!/bin/sh\\nexit 0\\n' > /tmp/buddy-ci-bin/python\n"
                "          chmod +x /tmp/buddy-ci-bin/python\n"
                "          echo /tmp/buddy-ci-bin >> \"$GITHUB_PATH\"\n\n"
            )
            self._replace(path, target, injected + target)

        errors = self._errors_after(mutate)
        self.assertIn(
            "runtime workflow differs from canonical full-file authority digest",
            errors,
        )

    def test_runtime_workflow_digest_rejects_prior_runner_overwrite(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            target = "      - name: Required headless suite (shared local/CI contract)"
            injected = (
                "      - name: Replace required runner\n"
                "        run: |\n"
                "          printf 'raise SystemExit(0)\\n' > "
                "packages/content-validator/headless_suite.py\n\n"
            )
            self._replace(path, target, injected + target)

        errors = self._errors_after(mutate)
        self.assertIn(
            "runtime workflow differs from canonical full-file authority digest",
            errors,
        )

    def test_python_workflow_digest_rejects_prior_github_path_poisoning(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/python-lint.yml"
            target = "      - name: Importer Python unit suite (zero tests fails)"
            injected = (
                "      - name: Prepend fake Python\n"
                "        run: |\n"
                "          mkdir -p /tmp/buddy-ci-bin\n"
                "          printf '#!/bin/sh\\nexit 0\\n' > /tmp/buddy-ci-bin/python\n"
                "          chmod +x /tmp/buddy-ci-bin/python\n"
                "          echo /tmp/buddy-ci-bin >> \"$GITHUB_PATH\"\n\n"
            )
            self._replace(path, target, injected + target)

        errors = self._errors_after(mutate)
        self.assertIn(
            "python workflow differs from canonical full-file authority digest",
            errors,
        )

    def test_runtime_workflow_digest_rejects_quoted_duplicate_job(self) -> None:
        def mutate(root: Path) -> None:
            self._replace(
                root / ".github/workflows/runtime-smoke.yml",
                "jobs:\n  parse-and-smoke:",
                "jobs:\n"
                '  "parse-and-smoke":\n'
                "    runs-on: ubuntu-latest\n"
                "    steps: []\n"
                "  parse-and-smoke:",
            )

        errors = self._errors_after(mutate)
        self.assertIn(
            "runtime workflow differs from canonical full-file authority digest",
            errors,
        )

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
                "          env -u PYTEST_ADDOPTS python -m pytest -q -o addopts= tools/importers/tests",
                "          # env -u PYTEST_ADDOPTS python -m pytest -q -o addopts= tools/importers/tests",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("tools/importers/tests" in error for error in errors), errors)

    def test_python_suite_job_cannot_be_disabled_or_nonblocking(self) -> None:
        for setting in ("if: false", "continue-on-error: true"):
            with self.subTest(setting=setting):
                def mutate(root: Path, job_setting: str = setting) -> None:
                    self._insert_direct_key(
                        root / ".github/workflows/python-lint.yml",
                        "  python-lint:",
                        job_setting,
                    )

                errors = self._errors_after(mutate)
                self.assertTrue(any("required suite" in error for error in errors), errors)

    def test_python_suite_job_cannot_depend_on_a_skipped_job(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/python-lint.yml"
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
            self._insert_direct_key(path, "  python-lint:", "needs: skipped-prerequisite")

        errors = self._errors_after(mutate)
        self.assertTrue(any("required suite" in error for error in errors), errors)

    def test_python_suite_steps_cannot_be_disabled_or_nonblocking(self) -> None:
        step_names = (
            "Importer Python unit suite (zero tests fails)",
            "Runtime-tool Python unit suite (zero tests fails)",
            "CI-contract Python unit suite (zero tests fails)",
        )
        for step_name in step_names:
            for setting in ("if: false", "continue-on-error: true"):
                with self.subTest(step=step_name, setting=setting):
                    def mutate(
                        root: Path,
                        name: str = step_name,
                        step_setting: str = setting,
                    ) -> None:
                        self._insert_direct_key(
                            root / ".github/workflows/python-lint.yml",
                            f"      - name: {name}",
                            step_setting,
                        )

                    errors = self._errors_after(mutate)
                    self.assertTrue(any("required suite" in error for error in errors), errors)

    def test_python_suite_steps_must_remain_in_python_lint_job(self) -> None:
        step_names = (
            "Importer Python unit suite (zero tests fails)",
            "Runtime-tool Python unit suite (zero tests fails)",
            "CI-contract Python unit suite (zero tests fails)",
        )
        for step_name in step_names:
            with self.subTest(step=step_name):
                def mutate(root: Path, name: str = step_name) -> None:
                    path = root / ".github/workflows/python-lint.yml"
                    self._replace(
                        path,
                        "jobs:\n",
                        "jobs:\n"
                        "  decoy-python:\n"
                        "    runs-on: ubuntu-latest\n"
                        "    steps:\n"
                        "      - run: echo decoy\n\n",
                    )
                    self._relocate_step(path, name, "decoy-python")

                errors = self._errors_after(mutate)
                self.assertTrue(any("required suite" in error for error in errors), errors)

    def test_python_suite_commands_cannot_follow_early_success_exit(self) -> None:
        paths = (
            "tools/importers/tests",
            "apps/runtime-godot/tools/tests",
            "packages/content-validator",
        )
        for path in paths:
            with self.subTest(path=path):
                def mutate(root: Path, suite_path: str = path) -> None:
                    command = (
                        "          env -u PYTEST_ADDOPTS python -m pytest -q -o addopts= "
                        f"{suite_path}"
                    )
                    self._replace(
                        root / ".github/workflows/python-lint.yml",
                        command,
                        f"          exit 0\n{command}",
                    )

                errors = self._errors_after(mutate)
                self.assertTrue(any(path in error for error in errors), errors)

    def test_python_suite_explicit_false_requires_authority_digest_update(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/python-lint.yml"
            self._insert_direct_key(path, "  python-lint:", "continue-on-error: false")
            for step_name in (
                "Importer Python unit suite (zero tests fails)",
                "Runtime-tool Python unit suite (zero tests fails)",
                "CI-contract Python unit suite (zero tests fails)",
            ):
                self._insert_direct_key(
                    path,
                    f"      - name: {step_name}",
                    "continue-on-error: false",
                )

        self.assertEqual(
            self._errors_after(mutate),
            ["python workflow differs from canonical full-file authority digest"],
        )

    def test_required_steps_reject_custom_direct_shells(self) -> None:
        cases = (
            (
                ".github/workflows/runtime-smoke.yml",
                "      - name: Required headless suite (shared local/CI contract)",
                "shared headless contract",
            ),
            (
                ".github/workflows/runtime-smoke.yml",
                "        shell: pwsh",
                "exported default startup",
            ),
            *(
                (
                    ".github/workflows/python-lint.yml",
                    f"      - name: {step_name}",
                    path,
                )
                for step_name, path in (
                    ("Importer Python unit suite (zero tests fails)", "tools/importers/tests"),
                    (
                        "Runtime-tool Python unit suite (zero tests fails)",
                        "apps/runtime-godot/tools/tests",
                    ),
                    (
                        "CI-contract Python unit suite (zero tests fails)",
                        "packages/content-validator",
                    ),
                )
            ),
        )
        for relative, target, expected_error in cases:
            with self.subTest(target=target):
                def mutate(
                    root: Path,
                    workflow: str = relative,
                    mutation_target: str = target,
                ) -> None:
                    path = root / workflow
                    custom_shell = 'shell: python -c "raise SystemExit(0)" {0}'
                    if mutation_target == "        shell: pwsh":
                        self._replace(
                            path,
                            "      - name: Start and cleanly exit exported default runtime\n"
                            "        shell: pwsh",
                            "      - name: Start and cleanly exit exported default runtime\n"
                            f"        {custom_shell}",
                        )
                    else:
                        self._insert_direct_key(path, mutation_target, custom_shell)

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_required_jobs_reject_defaults_run_shell(self) -> None:
        cases = (
            (".github/workflows/runtime-smoke.yml", "  parse-and-smoke:", "shared headless contract"),
            (".github/workflows/runtime-smoke.yml", "  windows-export:", "exported default startup"),
            (".github/workflows/python-lint.yml", "  python-lint:", "required suite"),
        )
        for relative, target, expected_error in cases:
            with self.subTest(target=target):
                def mutate(
                    root: Path,
                    workflow: str = relative,
                    job: str = target,
                ) -> None:
                    self._insert_run_shell_default(root / workflow, job)

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_workflow_defaults_run_shell_fails(self) -> None:
        cases = (
            (".github/workflows/runtime-smoke.yml", "runtime workflow must not set defaults.run.shell"),
            (".github/workflows/python-lint.yml", "python workflow must not set defaults.run.shell"),
        )
        for relative, expected_error in cases:
            with self.subTest(workflow=relative):
                def mutate(root: Path, workflow: str = relative) -> None:
                    self._insert_run_shell_default(root / workflow, None)

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_required_steps_reject_yaml_alias_keys(self) -> None:
        cases = (
            (
                ".github/workflows/runtime-smoke.yml",
                "      - name: Required headless suite (shared local/CI contract)",
                "runtime workflow must not use YAML anchors or aliases",
            ),
            (
                ".github/workflows/runtime-smoke.yml",
                "      - name: Start and cleanly exit exported default runtime",
                "runtime workflow must not use YAML anchors or aliases",
            ),
            (
                ".github/workflows/python-lint.yml",
                "      - name: Importer Python unit suite (zero tests fails)",
                "python workflow must not use YAML anchors or aliases",
            ),
        )
        for relative, target, expected_error in cases:
            with self.subTest(target=target):
                def mutate(
                    root: Path,
                    workflow: str = relative,
                    mutation_target: str = target,
                ) -> None:
                    path = root / workflow
                    self._replace(path, "name:", "name: &authority_key if #",)
                    self._insert_direct_key(path, mutation_target, "*authority_key: false")

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_run_body_anchor_tokens_only_require_authority_digest_update(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                '          $ErrorActionPreference = "Stop"\n'
                "          pwsh -NoProfile -File apps/runtime-godot/tests/test_run_burn_in.ps1",
                '          $ErrorActionPreference = "Stop"\n'
                '          Write-Host "&authority_key *authority_key"\n'
                "          pwsh -NoProfile -File apps/runtime-godot/tests/test_run_burn_in.ps1",
            )

        self.assertEqual(
            self._errors_after(mutate),
            ["runtime workflow differs from canonical full-file authority digest"],
        )

    def test_escaped_required_step_key_fails_closed(self) -> None:
        def mutate(root: Path) -> None:
            self._insert_direct_key(
                root / ".github/workflows/runtime-smoke.yml",
                "      - name: Required headless suite (shared local/CI contract)",
                '"\\x69f": false',
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("shared headless contract" in error for error in errors), errors)

    def test_python_workflow_authority_mappings_reject_env(self) -> None:
        cases = (
            ("top-level", None, "python workflow has non-canonical top-level contract metadata"),
            ("job", "  python-lint:", "required suite"),
            ("step", "      - name: Importer Python unit suite (zero tests fails)", "required suite"),
        )
        for scope, target, expected_error in cases:
            with self.subTest(scope=scope):
                def mutate(root: Path, mapping_target: str | None = target) -> None:
                    path = root / ".github/workflows/python-lint.yml"
                    if mapping_target is None:
                        original = path.read_text(encoding="utf-8")
                        path.write_text(
                            "env:\n  PYTEST_ADDOPTS: --collect-only\n" + original,
                            encoding="utf-8",
                        )
                    else:
                        self._insert_direct_key(
                            path,
                            mapping_target,
                            "env: {PYTEST_ADDOPTS: --collect-only}",
                        )

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_python_suite_collect_only_environment_cannot_bypass_execution(self) -> None:
        def mutate(root: Path) -> None:
            self._insert_direct_key(
                root / ".github/workflows/python-lint.yml",
                "  python-lint:",
                "env: {PYTEST_ADDOPTS: --collect-only}",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("required suite" in error for error in errors), errors)

    def test_python_suite_command_must_clear_pytest_options(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/python-lint.yml"
            self._replace(
                path,
                "          env -u PYTEST_ADDOPTS python -m pytest -q -o addopts= tools/importers/tests",
                "          python -m pytest -q tools/importers/tests",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("tools/importers/tests" in error for error in errors), errors)

    def test_required_steps_cannot_be_satisfied_by_matrix_decoys(self) -> None:
        cases = (
            (
                ".github/workflows/runtime-smoke.yml",
                "parse-and-smoke",
                "Required headless suite (shared local/CI contract)",
                "shared headless contract",
            ),
            (
                ".github/workflows/runtime-smoke.yml",
                "windows-export",
                "Start and cleanly exit exported default runtime",
                "exported default startup",
            ),
            (
                ".github/workflows/python-lint.yml",
                "python-lint",
                "CI-contract Python unit suite (zero tests fails)",
                "packages/content-validator",
            ),
        )
        for relative, job_id, step_name, expected_error in cases:
            with self.subTest(step=step_name):
                def mutate(
                    root: Path,
                    workflow_path: str = relative,
                    job: str = job_id,
                    name: str = step_name,
                ) -> None:
                    path = root / workflow_path
                    self._insert_direct_key(path, f"      - name: {name}", "if: false")
                    self._insert_matrix_step_decoy(path, job, name)

                errors = self._errors_after(mutate)
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_required_runtime_blocks_reject_conditional_wrappers(self) -> None:
        def wrap_linux(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "          set -euo pipefail\n",
                "          if false; then\n          set -euo pipefail\n",
            )
            self._replace(
                path,
                "            --timeout 90 2>&1 | tee headless-suite.log\n",
                "            --timeout 90 2>&1 | tee headless-suite.log\n          fi\n",
            )

        linux_errors = self._errors_after(wrap_linux)
        self.assertTrue(
            any("shared headless contract" in error for error in linux_errors),
            linux_errors,
        )

        def wrap_windows(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                '          $ErrorActionPreference = "Stop"\n',
                '          if ($false) {\n          $ErrorActionPreference = "Stop"\n',
            )
            self._replace(
                path,
                '            Write-Error "Exported default runtime did not emit the exact startup PASS marker"\n'
                "            exit 1\n"
                "          }\n",
                '            Write-Error "Exported default runtime did not emit the exact startup PASS marker"\n'
                "            exit 1\n"
                "          }\n"
                "          }\n",
            )

        windows_errors = self._errors_after(wrap_windows)
        self.assertTrue(
            any("exported default startup" in error for error in windows_errors),
            windows_errors,
        )

    def test_exported_startup_rejects_success_exit_before_postconditions(self) -> None:
        def mutate(root: Path) -> None:
            path = root / ".github/workflows/runtime-smoke.yml"
            self._replace(
                path,
                "            Tee-Object -FilePath ..\\..\\win-startup-smoke.log\n"
                "          if ($LASTEXITCODE -ne 0) {\n",
                "            Tee-Object -FilePath ..\\..\\win-startup-smoke.log\n"
                "          exit 0\n"
                "          if ($LASTEXITCODE -ne 0) {\n",
            )

        errors = self._errors_after(mutate)
        self.assertTrue(any("exported default startup" in error for error in errors), errors)

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
