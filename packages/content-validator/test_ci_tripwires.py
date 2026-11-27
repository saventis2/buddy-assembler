from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Sequence
from unittest import mock


MODULE_PATH = Path(__file__).with_name("ci_tripwires.py")
SPEC = importlib.util.spec_from_file_location("ci_tripwires", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
ci_tripwires = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ci_tripwires
SPEC.loader.exec_module(ci_tripwires)


def _run(run_id: int, created: str, started: str, completed: str) -> tuple[dict[str, object], dict[str, object]]:
    listing: dict[str, object] = {"databaseId": run_id, "createdAt": created}
    jobs: dict[str, object] = {
        "jobs": [
            {"name": "linux", "startedAt": started, "completedAt": completed},
            {"name": "windows", "startedAt": started, "completedAt": completed},
        ]
    }
    return listing, jobs


class FakeGh:
    """Answers the gh calls ci_tripwires makes, from canned JSON."""

    def __init__(self, visibility: str, runs: list[tuple[dict[str, object], dict[str, object]]]):
        self.visibility = visibility
        self.runs = runs
        self.calls: list[list[str]] = []

    def __call__(self, args: Sequence[str]) -> str:
        self.calls.append(list(args))
        if list(args[:2]) == ["repo", "view"]:
            return json.dumps({"visibility": self.visibility})
        if list(args[:2]) == ["run", "list"]:
            return json.dumps([listing for listing, _ in self.runs])
        if list(args[:2]) == ["run", "view"]:
            run_id = int(args[2])
            return json.dumps(next(jobs for listing, jobs in self.runs if listing["databaseId"] == run_id))
        raise AssertionError(f"unexpected gh call: {args}")


FAST = [
    _run(1, "2026-11-16T08:00:00Z", "2026-11-16T08:00:05Z", "2026-11-16T08:02:00Z"),
    _run(2, "2026-11-16T09:00:00Z", "2026-11-16T09:00:10Z", "2026-11-16T09:03:00Z"),
    _run(3, "2026-11-16T10:00:00Z", "2026-11-16T10:00:03Z", "2026-11-16T10:01:30Z"),
]


class TripwireTests(unittest.TestCase):
    def test_public_and_fast_trips_nothing(self) -> None:
        trips, notes = ci_tripwires.check(FakeGh("PUBLIC", FAST))
        self.assertEqual(trips, [])
        self.assertTrue(any("median of the last 3 main runs" in note for note in notes))

    def test_private_repository_trips(self) -> None:
        trips, _ = ci_tripwires.check(FakeGh("PRIVATE", FAST))
        self.assertEqual(len(trips), 1)
        self.assertIn("private", trips[0])

    def test_slow_median_run_trips(self) -> None:
        slow = [
            _run(1, "2026-11-16T08:00:00Z", "2026-11-16T08:00:05Z", "2026-11-16T08:08:00Z"),
            _run(2, "2026-11-16T09:00:00Z", "2026-11-16T09:00:05Z", "2026-11-16T09:07:00Z"),
            FAST[2],
        ]
        trips, _ = ci_tripwires.check(FakeGh("PUBLIC", slow))
        self.assertEqual(len(trips), 1)
        self.assertIn("median run takes", trips[0])

    def test_slow_median_queue_trips(self) -> None:
        queued = [
            _run(1, "2026-11-16T08:00:00Z", "2026-11-16T08:06:00Z", "2026-11-16T08:07:00Z"),
            _run(2, "2026-11-16T09:00:00Z", "2026-11-16T09:05:30Z", "2026-11-16T09:06:00Z"),
            FAST[2],
        ]
        trips, _ = ci_tripwires.check(FakeGh("PUBLIC", queued))
        self.assertEqual(len(trips), 1)
        self.assertIn("median queue wait", trips[0])

    def test_one_slow_run_alone_does_not_trip(self) -> None:
        one_slow = [
            _run(1, "2026-11-16T08:00:00Z", "2026-11-16T08:09:00Z", "2026-11-16T08:20:00Z"),
            FAST[1],
            FAST[2],
        ]
        trips, _ = ci_tripwires.check(FakeGh("PUBLIC", one_slow))
        self.assertEqual(trips, [])

    def test_too_few_runs_is_a_note_not_a_trip(self) -> None:
        trips, notes = ci_tripwires.check(FakeGh("PUBLIC", FAST[:2]))
        self.assertEqual(trips, [])
        self.assertTrue(any("speed is not judged" in note for note in notes))

    def test_main_exit_codes(self) -> None:
        cases = (
            (FakeGh("PUBLIC", FAST), 0),
            (FakeGh("PRIVATE", FAST), 1),
        )
        for fake, expected in cases:
            with self.subTest(expected=expected):
                with mock.patch.object(ci_tripwires, "_gh", fake), contextlib.redirect_stdout(
                    io.StringIO()
                ), contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(ci_tripwires.main([]), expected)

    def test_gh_failure_is_reported_not_passed(self) -> None:
        def broken(args: Sequence[str]) -> str:
            raise subprocess.CalledProcessError(1, ["gh", *args])

        err = io.StringIO()
        with mock.patch.object(ci_tripwires, "_gh", broken), contextlib.redirect_stdout(
            io.StringIO()
        ), contextlib.redirect_stderr(err):
            self.assertEqual(ci_tripwires.main([]), 2)
        self.assertIn("could not check", err.getvalue())


if __name__ == "__main__":
    unittest.main()
