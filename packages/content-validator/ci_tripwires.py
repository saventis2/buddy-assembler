#!/usr/bin/env python3
"""Check the council's Q2 tripwires on CI cost and speed, read-only.

Part of the local gate before pushing a row of the land view stack. It fails
when CI should move from "every check on every PR" to the gated policy (the
Linux pack and verify-pck on every PR, the Windows export gated), which only
the owner can land:

- the repository is not public, so standard-runner minutes bill (both
  Runtime smoke jobs then fail on every run as well);
- over the last three successful Runtime smoke runs on main, the median wait
  for a runner was over 5 minutes, or the median run took over 6 minutes.

A run's wait is its slowest job's wait for a runner, and its time is its
longest job's own time, so a Windows job stuck in the queue counts as waiting,
not running. Only successful first attempts are sampled: cancelled and failed
runs stop early and would make CI look quicker than it is, and a re-run's jobs
start long after the run was created.

Exit codes: 0 pass, 1 a tripwire tripped, 2 GitHub could not be read, 3 too
few runs to judge speed. Only 0 is a pass. It reads GitHub through the gh CLI
and changes nothing.
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any, Callable, Sequence


WORKFLOW = "Runtime smoke"
SAMPLE_RUNS = 3
# How many successful main runs to look through for SAMPLE_RUNS usable ones.
LISTED_RUNS = 10
QUEUE_LIMIT_SECONDS = 300
RUN_LIMIT_SECONDS = 360
# GitHub reports a time that never happened, such as a skipped job's start,
# as 0001-01-01T00:00:00Z.
EARLIEST_REAL_TIME = datetime(2000, 1, 1, tzinfo=timezone.utc)

EXIT_PASS = 0
EXIT_TRIPPED = 1
EXIT_UNREADABLE = 2
EXIT_INCONCLUSIVE = 3

GhRunner = Callable[[Sequence[str]], str]


def _gh(args: Sequence[str]) -> str:
    result = subprocess.run(
        ["gh", *args], capture_output=True, text=True, check=True, timeout=60
    )
    return result.stdout


def _when(value: object) -> datetime | None:
    """A real moment from GitHub, or None for a missing time or a placeholder."""
    if not isinstance(value, str) or not value:
        return None
    moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment if moment >= EARLIEST_REAL_TIME else None


def _run_times(gh: GhRunner, run: dict[str, Any]) -> tuple[float, float] | None:
    """(wait seconds, run seconds) for one run, or None without usable times.

    The wait is the longest any job waited for a runner after the run was
    created, and the time is the longest any job then took. Jobs that never
    ran, which carry placeholder times, are left out.
    """
    created = _when(run.get("createdAt"))
    if created is None:
        return None
    data = json.loads(gh(["run", "view", str(run["databaseId"]), "--json", "jobs"]))
    jobs = data.get("jobs") if isinstance(data, dict) else None
    waits: list[float] = []
    times: list[float] = []
    for job in jobs if isinstance(jobs, list) else []:
        if not isinstance(job, dict):
            continue
        started = _when(job.get("startedAt"))
        completed = _when(job.get("completedAt"))
        if started is None or completed is None or completed < started:
            continue
        waits.append(max(0.0, (started - created).total_seconds()))
        times.append((completed - started).total_seconds())
    if not times:
        return None
    return max(waits), max(times)


def check(gh: GhRunner = _gh) -> tuple[list[str], list[str], list[str]]:
    """Return (trips, unknowns, notes).

    Any trip means CI should move to the gated policy. Any unknown means a
    tripwire could not be judged, which is not a pass.
    """
    trips: list[str] = []
    unknowns: list[str] = []
    notes: list[str] = []
    repo = json.loads(gh(["repo", "view", "--json", "visibility"]))
    visibility = str(repo.get("visibility", "")) if isinstance(repo, dict) else ""
    if visibility.upper() != "PUBLIC":
        trips.append(
            f"the repository is {visibility.lower() or 'not public'}, so Actions minutes bill"
        )
    else:
        notes.append("the repository is public: standard-runner minutes are unbilled")

    listed = json.loads(
        gh(
            [
                "run", "list",
                "--workflow", WORKFLOW,
                "--branch", "main",
                "--event", "push",
                "--status", "success",
                "--limit", str(LISTED_RUNS),
                "--json", "databaseId,createdAt,attempt",
            ]
        )
    )
    times: list[tuple[float, float]] = []
    for run in listed if isinstance(listed, list) else []:
        if len(times) == SAMPLE_RUNS:
            break
        if not isinstance(run, dict) or run.get("attempt", 1) != 1:
            continue
        measured = _run_times(gh, run)
        if measured is not None:
            times.append(measured)
    if len(times) < SAMPLE_RUNS:
        unknowns.append(
            f"only {len(times)} of the last {LISTED_RUNS} successful {WORKFLOW} runs on "
            f"main have usable job times, and {SAMPLE_RUNS} are needed to judge speed"
        )
        return trips, unknowns, notes
    queue = statistics.median(each[0] for each in times)
    duration = statistics.median(each[1] for each in times)
    notes.append(
        f"median of the last {SAMPLE_RUNS} main runs: wait {queue:.0f} s, run {duration:.0f} s"
    )
    if queue > QUEUE_LIMIT_SECONDS:
        trips.append(f"the median wait for a runner is {queue:.0f} s, over {QUEUE_LIMIT_SECONDS} s")
    if duration > RUN_LIMIT_SECONDS:
        trips.append(f"the median run takes {duration:.0f} s, over {RUN_LIMIT_SECONDS} s")
    return trips, unknowns, notes


def main(argv: list[str] | None = None) -> int:
    argparse.ArgumentParser(description=__doc__).parse_args(argv)
    try:
        trips, unknowns, notes = check(_gh)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as exc:
        print(f"ci_tripwires: could not check: {exc}", file=sys.stderr)
        return EXIT_UNREADABLE
    for note in notes:
        print(f"ci_tripwires: {note}")
    if trips:
        for trip in trips:
            print(f"ci_tripwires: TRIP: {trip}", file=sys.stderr)
        print(
            "ci_tripwires: move CI to the gated policy (council Q2) before pushing more rows",
            file=sys.stderr,
        )
        return EXIT_TRIPPED
    if unknowns:
        for unknown in unknowns:
            print(f"ci_tripwires: INCONCLUSIVE: {unknown}", file=sys.stderr)
        print(
            "ci_tripwires: not a pass: check the Runtime smoke runs on main by hand "
            "before pushing more rows",
            file=sys.stderr,
        )
        return EXIT_INCONCLUSIVE
    print("ci_tripwires: PASS")
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
