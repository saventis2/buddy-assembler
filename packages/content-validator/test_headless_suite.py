from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("headless_suite.py")
SPEC = importlib.util.spec_from_file_location("headless_suite", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
headless_suite = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = headless_suite
SPEC.loader.exec_module(headless_suite)

# A second process that takes the machine lock, says whether it got it, and
# holds it until its stdin closes.
_HOLDER_CODE = (
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


def _first_line(process: subprocess.Popen[str], seconds: float) -> str:
    """The process's first line of output, waiting no longer than ``seconds``.

    A holder that hangs before it prints must not hang the suite, and the CI
    job with it, so on a timeout the process is killed and "" returned.
    """
    stdout = process.stdout
    assert stdout is not None
    lines: queue.Queue[str] = queue.Queue()
    threading.Thread(target=lambda: lines.put(stdout.readline()), daemon=True).start()
    try:
        return lines.get(timeout=seconds).strip()
    except queue.Empty:
        process.kill()
        return ""


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

    def test_default_lock_is_the_users_own(self) -> None:
        if sys.platform == "win32":
            base = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
        else:
            base = Path.home() / ".cache"
        self.assertEqual(
            headless_suite.default_machine_lock_path(),
            base / "buddy-runtime" / headless_suite.MACHINE_LOCK_NAME,
        )

    def test_default_lock_ignores_the_temp_folder(self) -> None:
        # Two sessions with temp folders of their own must still share one lock.
        before = headless_suite.default_machine_lock_path()
        with tempfile.TemporaryDirectory() as elsewhere, mock.patch.dict(
            os.environ, {"TMPDIR": elsewhere, "TEMP": elsewhere, "TMP": elsewhere}
        ), mock.patch.object(tempfile, "tempdir", None):
            after = headless_suite.default_machine_lock_path()
        self.assertEqual(after, before)

    def test_lock_blocked_exit_is_its_own_code(self) -> None:
        # 1 is a failed suite, and 2 is argparse's usage error.
        self.assertNotIn(headless_suite.LOCK_BLOCKED_EXIT, (0, 1, 2))

    def test_machine_lock_unlocks_before_it_closes_the_file(self) -> None:
        # Windows asks for an explicit unlock: its release on close can lag.
        with tempfile.TemporaryDirectory() as tmp:
            lock = Path(tmp) / "machine.lock"
            with mock.patch.object(
                headless_suite, "_unlock_byte", wraps=headless_suite._unlock_byte
            ) as unlock:
                with headless_suite.machine_lock(lock) as held:
                    self.assertTrue(held)
                    unlock.assert_not_called()
                unlock.assert_called_once()

    @unittest.skipIf(sys.platform == "win32", "symlinks need privileges on Windows")
    def test_machine_lock_refuses_a_planted_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            victim = root / "victim.txt"
            lock = root / "machine.lock"
            lock.symlink_to(victim)
            with self.assertRaises(OSError):
                with headless_suite.machine_lock(lock):
                    pass
            self.assertFalse(victim.exists())

    def _start_holder(self, lock: Path) -> subprocess.Popen[str]:
        return subprocess.Popen(
            [sys.executable, "-I", "-c", _HOLDER_CODE, str(MODULE_PATH), str(lock)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )

    def _stop_holder(self, holder: subprocess.Popen[str]) -> None:
        if holder.stdin is not None:
            with contextlib.suppress(OSError):
                holder.stdin.close()
        try:
            holder.wait(timeout=30)
        except subprocess.TimeoutExpired:
            holder.kill()
            holder.wait(timeout=30)
        if holder.stdout is not None:
            holder.stdout.close()

    def test_machine_lock_blocks_another_process(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lock = root / "machine.lock"
            holder = self._start_holder(lock)
            try:
                self.assertEqual(_first_line(holder, 30), "held")
                runner = self._runner(
                    subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", "")
                )
                blocked, _, _ = self._run_capturing(root, runner, None, lock)
                runner.assert_not_called()
            finally:
                self._stop_holder(holder)
            runner = self._runner(subprocess.CompletedProcess(["godot"], 0, "startup: PASS\n", ""))
            after, _, _ = self._run_capturing(root, runner, None, lock)
        self.assertEqual(blocked, headless_suite.LOCK_BLOCKED_EXIT)
        self.assertEqual(after, 0)

    def test_machine_lock_is_released_when_its_holder_is_killed(self) -> None:
        # A hard kill runs no cleanup and no unlock: only the OS can free the
        # lock, which a stale lock file could never do.
        with tempfile.TemporaryDirectory() as tmp:
            lock = Path(tmp) / "machine.lock"
            holder = self._start_holder(lock)
            try:
                self.assertEqual(_first_line(holder, 30), "held")
                holder.kill()
                holder.wait(timeout=30)
            finally:
                self._stop_holder(holder)
            # Windows may take a moment to release a dead process's lock.
            deadline = time.monotonic() + 10
            while True:
                with headless_suite.machine_lock(lock) as held:
                    pass
                if held or time.monotonic() > deadline:
                    break
                time.sleep(0.1)
        self.assertTrue(held)

    def test_main_line_buffers_its_output(self) -> None:
        # CI pipes the runner through tee: block buffering would hold timing
        # lines back, and lose them if the job were killed mid-suite.
        out = io.TextIOWrapper(io.BytesIO(), encoding="utf-8")
        err = io.TextIOWrapper(io.BytesIO(), encoding="utf-8")
        self.assertFalse(out.line_buffering)
        with mock.patch.object(sys, "stdout", out), mock.patch.object(
            sys, "stderr", err
        ), mock.patch.object(headless_suite, "run_suite", return_value=0) as run:
            result = headless_suite.main(
                ["--project", "p", "--contract", "c.json", "--toolchain", "t.json"]
            )
        self.assertEqual(result, 0)
        run.assert_called_once()
        self.assertTrue(out.line_buffering)
        self.assertTrue(err.line_buffering)

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
