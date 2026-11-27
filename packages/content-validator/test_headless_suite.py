from __future__ import annotations

import contextlib
import importlib.util
import io
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

    def _one_case(self, root: Path, extra: dict[str, object]) -> Path:
        contract = root / "suite.json"
        case = {"id": "one", "args": ["--", "--smoke"], "pass_marker": "PASS", **extra}
        contract.write_text(json.dumps({"schema_version": 1, "tests": [case]}), encoding="utf-8")
        return contract

    def test_case_timeout_is_optional_and_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertIsNone(
                headless_suite.load_contract(self._one_case(root, {}), root)[0].timeout_seconds
            )
            for good in (1, headless_suite.MAX_CASE_TIMEOUT_SECONDS):
                with self.subTest(good=good):
                    contract = self._one_case(root, {"timeout_seconds": good})
                    self.assertEqual(
                        headless_suite.load_contract(contract, root)[0].timeout_seconds, good
                    )
            for bad in (0, -5, headless_suite.MAX_CASE_TIMEOUT_SECONDS + 1, "90", True, 1.5):
                with self.subTest(bad=bad):
                    contract = self._one_case(root, {"timeout_seconds": bad})
                    with self.assertRaisesRegex(ValueError, "timeout_seconds"):
                        headless_suite.load_contract(contract, root)


class RunnerTests(unittest.TestCase):
    def _contracts(self, root: Path, case_timeout: int | None = None) -> tuple[Path, Path]:
        toolchain = root / "toolchain.json"
        toolchain.write_text(
            json.dumps(
                {
                    "godot_version": "4.2.2",
                    "godot_release": "4.2.2-stable",
                    "reported_version": "4.2.2.stable.official.test",
                }
            ),
            encoding="utf-8",
        )
        case: dict[str, object] = {
            "id": "startup",
            "args": ["--", "--ci-startup-smoke"],
            "pass_marker": "startup: PASS",
        }
        if case_timeout is not None:
            case["timeout_seconds"] = case_timeout
        contract = root / "suite.json"
        contract.write_text(
            json.dumps({"schema_version": 1, "tests": [case]}),
            encoding="utf-8",
        )
        return contract, toolchain

    def _runner(self, child: object) -> mock.Mock:
        return mock.Mock(
            side_effect=[
                subprocess.CompletedProcess(
                    ["godot", "--version"], 0, "4.2.2.stable.official.test\n", ""
                ),
                subprocess.CompletedProcess(["godot", "--import"], 1, "import warning\n", ""),
                child,
            ]
        )

    def _run_with(self, child: subprocess.CompletedProcess[str]) -> int:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            contract, toolchain = self._contracts(root)
            return headless_suite.run_suite(
                godot="godot",
                project=root,
                contract=contract,
                toolchain=toolchain,
                timeout_seconds=10,
                command_runner=self._runner(child),
                lock_path=root / "machine.lock",
            )

    def _run_capturing(
        self, root: Path, runner: mock.Mock, case_timeout: int | None, lock: Path | None = None
    ) -> tuple[int, str, str]:
        contract, toolchain = self._contracts(root, case_timeout)
        out, err = io.StringIO(), io.StringIO()
        ticks = iter((100.0, 102.5))
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            result = headless_suite.run_suite(
                godot="godot",
                project=root,
                contract=contract,
                toolchain=toolchain,
                timeout_seconds=10,
                command_runner=runner,
                lock_path=lock if lock is not None else root / "machine.lock",
                clock=lambda: next(ticks),
            )
        return result, out.getvalue(), err.getvalue()

    def test_case_uses_its_own_limit_and_logs_its_time(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = self._runner(subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", ""))
            result, out, _ = self._run_capturing(Path(tmp), runner, 42)
        self.assertEqual(result, 0)
        self.assertEqual(runner.call_args_list[2].kwargs["timeout"], 42)
        self.assertIn("headless_suite[startup]: took 2.5 s (limit 42 s)", out.splitlines())

    def test_case_without_its_own_limit_uses_the_runner_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = self._runner(subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", ""))
            result, out, _ = self._run_capturing(Path(tmp), runner, None)
        self.assertEqual(result, 0)
        self.assertEqual(runner.call_args_list[2].kwargs["timeout"], 10)
        self.assertIn("headless_suite[startup]: took 2.5 s (limit 10 s)", out.splitlines())

    def test_timeout_names_the_case_limit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runner = self._runner(subprocess.TimeoutExpired(["godot"], 42))
            result, _, err = self._run_capturing(Path(tmp), runner, 42)
        self.assertEqual(result, 1)
        self.assertIn("headless_suite[startup]: timed out after 42 s", err)

    def test_second_suite_is_blocked_by_the_machine_lock(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lock = root / "machine.lock"
            runner = self._runner(subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", ""))
            with headless_suite.machine_lock(lock) as held:
                self.assertTrue(held)
                result, _, err = self._run_capturing(root, runner, None, lock)
        self.assertEqual(result, headless_suite.LOCK_BLOCKED_EXIT)
        self.assertIn("machine lock", err)
        runner.assert_not_called()

    def test_machine_lock_is_released_after_a_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lock = root / "machine.lock"
            for attempt in range(2):
                with self.subTest(attempt=attempt):
                    runner = self._runner(
                        subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", "")
                    )
                    result, _, _ = self._run_capturing(root, runner, None, lock)
                    self.assertEqual(result, 0)

    def test_machine_lock_blocks_another_process(self) -> None:
        holder_code = (
            "import importlib.util, sys\n"
            "from pathlib import Path\n"
            "spec = importlib.util.spec_from_file_location('headless_suite', sys.argv[1])\n"
            "module = importlib.util.module_from_spec(spec)\n"
            "sys.modules['headless_suite'] = module\n"
            "spec.loader.exec_module(module)\n"
            "with module.machine_lock(Path(sys.argv[2])) as held:\n"
            "    print('held' if held else 'busy', flush=True)\n"
            "    sys.stdin.read()\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lock = root / "machine.lock"
            holder = subprocess.Popen(
                [sys.executable, "-I", "-c", holder_code, str(MODULE_PATH), str(lock)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                text=True,
            )
            try:
                assert holder.stdout is not None and holder.stdin is not None
                self.assertEqual(holder.stdout.readline().strip(), "held")
                runner = self._runner(
                    subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", "")
                )
                blocked, _, _ = self._run_capturing(root, runner, None, lock)
                runner.assert_not_called()
            finally:
                if holder.stdin is not None:
                    holder.stdin.close()
                holder.wait(timeout=30)
                if holder.stdout is not None:
                    holder.stdout.close()
            runner = self._runner(subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", ""))
            after, _, _ = self._run_capturing(root, runner, None, lock)
        self.assertEqual(blocked, headless_suite.LOCK_BLOCKED_EXIT)
        self.assertEqual(after, 0)

    def test_child_failure_is_not_false_green(self) -> None:
        result = self._run_with(subprocess.CompletedProcess(["godot"], 9, "startup: PASS\n", ""))
        self.assertEqual(result, 1)

    def test_nonzero_import_prepass_is_tolerated_when_required_case_passes(self) -> None:
        result = self._run_with(subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", ""))
        self.assertEqual(result, 0)

    def test_missing_pass_marker_is_not_false_green(self) -> None:
        result = self._run_with(subprocess.CompletedProcess(["godot"], 0, "no marker\n", ""))
        self.assertEqual(result, 1)

    def test_pass_marker_must_be_a_complete_line(self) -> None:
        result = self._run_with(
            subprocess.CompletedProcess(["godot"], 0, "prefix startup: PASS suffix\n", "")
        )
        self.assertEqual(result, 1)

    def test_startup_error_diagnostic_is_not_false_green(self) -> None:
        diagnostics = (
            "SCRIPT ERROR: Invalid call\n",
            "Parse Error: Expected expression\n",
            "ERROR: Failed loading resource\n",
        )
        for diagnostic in diagnostics:
            with self.subTest(diagnostic=diagnostic):
                result = self._run_with(
                    subprocess.CompletedProcess(
                        ["godot"], 0, f"startup: PASS\n{diagnostic}", ""
                    )
                )
                self.assertEqual(result, 1)


if __name__ == "__main__":
    unittest.main()
