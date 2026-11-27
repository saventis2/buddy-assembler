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

Run = tuple[dict[str, object], dict[str, object]]
PLACEHOLDER = "0001-01-01T00:00:00Z"


def _job(name: str, started: str, completed: str) -> dict[str, object]:
    return {"name": name, "startedAt": started, "completedAt": completed}


def _run(run_id: int, created: str, *jobs: dict[str, object], attempt: int = 1) -> Run:
    listing: dict[str, object] = {"databaseId": run_id, "createdAt": created, "attempt": attempt}
    return listing, {"jobs": list(jobs)}


class FakeGh:
    """Answers the gh calls ci_tripwires makes, from canned JSON."""

    def __init__(self, visibility: str, runs: list[Run]):
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

    def viewed(self) -> list[int]:
        return [int(call[2]) for call in self.calls if call[:2] == ["run", "view"]]


def _fast(*extra: dict[str, object]) -> list[Run]:
    """Three quick runs, each with ``extra`` jobs added.

    Each run's jobs start and end apart, so taking the wrong job shows. Waits
    40, 20 and 30 s (median 30); longest jobs 115, 170 and 87 s (median 115).
    """
    return [
        _run(
            1, "2026-11-16T08:00:00Z",
            _job("linux", "2026-11-16T08:00:05Z", "2026-11-16T08:02:00Z"),
            _job("windows", "2026-11-16T08:00:40Z", "2026-11-16T08:01:50Z"),
            *extra,
        ),
        _run(
            2, "2026-11-16T09:00:00Z",
            _job("linux", "2026-11-16T09:00:10Z", "2026-11-16T09:03:00Z"),
            _job("windows", "2026-11-16T09:00:20Z", "2026-11-16T09:01:20Z"),
            *extra,
        ),
        _run(
            3, "2026-11-16T10:00:00Z",
            _job("linux", "2026-11-16T10:00:03Z", "2026-11-16T10:01:30Z"),
            _job("windows", "2026-11-16T10:00:30Z", "2026-11-16T10:01:40Z"),
            *extra,
        ),
    ]


FAST = _fast()


def _quiet_main(fake: FakeGh) -> tuple[int, str]:
    err = io.StringIO()
    with mock.patch.object(ci_tripwires, "_gh", fake), contextlib.redirect_stdout(
        io.StringIO()
    ), contextlib.redirect_stderr(err):
        result = ci_tripwires.main([])
    return result, err.getvalue()


class TripwireTests(unittest.TestCase):
    def test_public_and_fast_trips_nothing(self) -> None:
        trips, unknowns, notes = ci_tripwires.check(FakeGh("PUBLIC", FAST))
        self.assertEqual(trips, [])
        self.assertEqual(unknowns, [])
        self.assertIn("median of the last 3 main runs: wait 30 s, run 115 s", notes)

    def test_private_repository_trips(self) -> None:
        trips, _, _ = ci_tripwires.check(FakeGh("PRIVATE", FAST))
        self.assertEqual(len(trips), 1)
        self.assertIn("private", trips[0])

    def test_slow_median_run_trips(self) -> None:
        slow = [
            _run(1, "2026-11-16T08:00:00Z", _job("linux", "2026-11-16T08:00:05Z", "2026-11-16T08:08:00Z")),
            _run(2, "2026-11-16T09:00:00Z", _job("linux", "2026-11-16T09:00:05Z", "2026-11-16T09:07:00Z")),
            FAST[2],
        ]
        trips, _, _ = ci_tripwires.check(FakeGh("PUBLIC", slow))
        self.assertEqual(len(trips), 1)
        self.assertIn("median run takes", trips[0])

    def test_slow_median_wait_trips(self) -> None:
        queued = [
            _run(1, "2026-11-16T08:00:00Z", _job("linux", "2026-11-16T08:06:00Z", "2026-11-16T08:07:00Z")),
            _run(2, "2026-11-16T09:00:00Z", _job("linux", "2026-11-16T09:05:30Z", "2026-11-16T09:06:00Z")),
            FAST[2],
        ]
        trips, _, _ = ci_tripwires.check(FakeGh("PUBLIC", queued))
        self.assertEqual(len(trips), 1)
        self.assertIn("median wait for a runner", trips[0])

    def test_a_queued_windows_job_counts_as_waiting_not_running(self) -> None:
        # Linux starts at once; Windows waits six minutes, then runs 70 s.
        def stuck(run_id: int, hour: int) -> Run:
            day = f"2026-11-16T{hour:02d}"
            return _run(
                run_id, f"{day}:00:00Z",
                _job("linux", f"{day}:00:05Z", f"{day}:02:00Z"),
                _job("windows", f"{day}:06:00Z", f"{day}:07:10Z"),
            )

        trips, _, notes = ci_tripwires.check(FakeGh("PUBLIC", [stuck(1, 8), stuck(2, 9), stuck(3, 10)]))
        self.assertEqual(len(trips), 1, trips)
        self.assertIn("median wait for a runner is 360 s", trips[0])
        self.assertIn("median of the last 3 main runs: wait 360 s, run 115 s", notes)

    def test_one_slow_run_alone_does_not_trip(self) -> None:
        one_slow = [
            _run(1, "2026-11-16T08:00:00Z", _job("linux", "2026-11-16T08:09:00Z", "2026-11-16T08:20:00Z")),
            FAST[1],
            FAST[2],
        ]
        trips, unknowns, _ = ci_tripwires.check(FakeGh("PUBLIC", one_slow))
        self.assertEqual(trips, [])
        self.assertEqual(unknowns, [])

    def test_only_successful_first_attempts_are_sampled(self) -> None:
        rerun = _run(
            9, "2026-11-16T07:00:00Z",
            _job("linux", "2026-11-16T09:00:00Z", "2026-11-16T09:02:00Z"),
            attempt=2,
        )
        fake = FakeGh("PUBLIC", [rerun, *FAST])
        trips, unknowns, _ = ci_tripwires.check(fake)
        self.assertEqual((trips, unknowns), ([], []))
        listing = next(call for call in fake.calls if call[:2] == ["run", "list"])
        self.assertEqual(listing[listing.index("--status") + 1], "success")
        self.assertNotIn(9, fake.viewed())

    def test_placeholder_times_are_left_out(self) -> None:
        # A skipped job reports 0001-01-01 for both times: it never ran.
        skipped = _job("deploy", PLACEHOLDER, PLACEHOLDER)
        never_ran = _run(7, "2026-11-16T07:00:00Z", skipped)
        trips, unknowns, notes = ci_tripwires.check(FakeGh("PUBLIC", [never_ran, *_fast(skipped)]))
        self.assertEqual((trips, unknowns), ([], []))
        self.assertIn("median of the last 3 main runs: wait 30 s, run 115 s", notes)

    def test_too_few_runs_is_inconclusive_not_a_pass(self) -> None:
        trips, unknowns, _ = ci_tripwires.check(FakeGh("PUBLIC", FAST[:2]))
        self.assertEqual(trips, [])
        self.assertEqual(len(unknowns), 1)
        result, err = _quiet_main(FakeGh("PUBLIC", FAST[:2]))
        self.assertEqual(result, ci_tripwires.EXIT_INCONCLUSIVE)
        self.assertIn("INCONCLUSIVE", err)

    def test_main_exit_codes(self) -> None:
        cases = (
            (FakeGh("PUBLIC", FAST), 0),
            (FakeGh("PRIVATE", FAST), 1),
            (FakeGh("PRIVATE", FAST[:1]), 1),
            (FakeGh("PUBLIC", []), 3),
        )
        for fake, expected in cases:
            with self.subTest(expected=expected, runs=len(fake.runs)):
                self.assertEqual(_quiet_main(fake)[0], expected)

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
