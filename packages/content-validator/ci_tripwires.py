#!/usr/bin/env python3
"""Check the council's Q2 tripwires on CI cost and speed, read-only.

Part of the local gate before pushing a row of the land view stack. It fails
when CI should move from "every check on every PR" to the gated policy (the
Linux pack and verify-pck on every PR, the Windows export gated), which only
the owner can land:

- the repository is not public, so standard-runner minutes bill (the
  Runtime smoke workflow then fails on every run as well);
- over the last three completed Runtime smoke runs on main, the median wait
  for a runner was over 5 minutes, or the median run took over 6 minutes.

It reads GitHub through the gh CLI and changes nothing.
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from datetime import datetime
from typing import Any, Callable, Sequence


WORKFLOW = "Runtime smoke"
SAMPLE_RUNS = 3
QUEUE_LIMIT_SECONDS = 300
RUN_LIMIT_SECONDS = 360

GhRunner = Callable[[Sequence[str]], str]


def _gh(args: Sequence[str]) -> str:
    result = subprocess.run(
        ["gh", *args], capture_output=True, text=True, check=True, timeout=60
    )
    return result.stdout


def _when(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def _run_times(gh: GhRunner, run: dict[str, Any]) -> tuple[float, float] | None:
    """(queue seconds, run seconds) for one run, from its jobs' own times.

    A run's createdAt and startedAt are the same moment, so the wait for a
    runner shows only in when its first job started.
    """
    data = json.loads(gh(["run", "view", str(run["databaseId"]), "--json", "jobs"]))
    jobs = data.get("jobs", []) if isinstance(data, dict) else []
    starts = [_when(str(job["startedAt"])) for job in jobs if job.get("startedAt")]
    ends = [_when(str(job["completedAt"])) for job in jobs if job.get("completedAt")]
    if not starts or not ends:
        return None
    first = min(starts)
    queue = (first - _when(str(run["createdAt"]))).total_seconds()
    return queue, (max(ends) - first).total_seconds()


def check(gh: GhRunner = _gh) -> tuple[list[str], list[str]]:
    """Return (trips, notes). Any trip means CI should move to the gated policy."""
    trips: list[str] = []
    notes: list[str] = []
    repo = json.loads(gh(["repo", "view", "--json", "visibility"]))
    visibility = str(repo.get("visibility", "")) if isinstance(repo, dict) else ""
    if visibility.upper() != "PUBLIC":
        trips.append(
            f"the repository is {visibility.lower() or 'not public'}, so Actions minutes bill"
        )
    else:
        notes.append("the repository is public: standard-runner minutes are unbilled")

    runs = json.loads(
        gh(
            [
                "run", "list",
                "--workflow", WORKFLOW,
                "--branch", "main",
                "--event", "push",
                "--status", "completed",
                "--limit", str(SAMPLE_RUNS),
                "--json", "databaseId,createdAt",
            ]
        )
    )
    times = [
        each
        for each in (_run_times(gh, run) for run in (runs if isinstance(runs, list) else []))
        if each is not None
    ]
    if len(times) < SAMPLE_RUNS:
        notes.append(
            f"only {len(times)} completed {WORKFLOW} runs on main have job times; "
            "speed is not judged"
        )
        return trips, notes
    queue = statistics.median(each[0] for each in times)
    duration = statistics.median(each[1] for each in times)
    notes.append(
        f"median of the last {SAMPLE_RUNS} main runs: queue {queue:.0f} s, run {duration:.0f} s"
    )
    if queue > QUEUE_LIMIT_SECONDS:
        trips.append(f"the median queue wait is {queue:.0f} s, over {QUEUE_LIMIT_SECONDS} s")
    if duration > RUN_LIMIT_SECONDS:
        trips.append(f"the median run takes {duration:.0f} s, over {RUN_LIMIT_SECONDS} s")
    return trips, notes


def main(argv: list[str] | None = None) -> int:
    argparse.ArgumentParser(description=__doc__).parse_args(argv)
    try:
        trips, notes = check(_gh)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as exc:
        print(f"ci_tripwires: could not check: {exc}", file=sys.stderr)
        return 2
    for note in notes:
        print(f"ci_tripwires: {note}")
    if trips:
        for trip in trips:
            print(f"ci_tripwires: TRIP: {trip}", file=sys.stderr)
        print(
            "ci_tripwires: move CI to the gated policy (council Q2) before pushing more rows",
            file=sys.stderr,
        )
        return 1
    print("ci_tripwires: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
