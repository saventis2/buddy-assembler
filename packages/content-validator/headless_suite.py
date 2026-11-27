#!/usr/bin/env python3
"""Run the single required Godot headless-suite contract."""

from __future__ import annotations

import argparse
import contextlib
import json
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator


STARTUP_ERROR_PATTERN = re.compile(
    r"^\s*(?:SCRIPT ERROR|ERROR):|\bParse Error\b", re.IGNORECASE
)

# A case may carry its own measured limit (about 1.5x its p95 time over at
# least five local runs) and never more than this. Every other case uses the
# runner's --timeout. There is no global raise and no local-only override.
MAX_CASE_TIMEOUT_SECONDS = 600

# One required suite or capture at a time on a machine: a second Godot run
# shares the CPU, pushes slow cases past their limits and spoils timings, so
# it is refused, not warned. Capture tools take the same lock.
MACHINE_LOCK_NAME = "buddy-runtime-godot.lock"
LOCK_BLOCKED_EXIT = 2


@dataclass(frozen=True)
class HeadlessCase:
    case_id: str
    scene: str | None
    args: tuple[str, ...]
    pass_marker: str
    timeout_seconds: int | None = None


def load_toolchain(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    required = ("godot_version", "godot_release", "reported_version")
    if not isinstance(data, dict) or any(not str(data.get(key, "")).strip() for key in required):
        raise ValueError("toolchain contract is missing required Godot version fields")
    result = {key: str(data[key]) for key in required}
    version = result["godot_version"]
    if result["godot_release"] != f"{version}-stable":
        raise ValueError("toolchain Godot release does not match its version")
    if not result["reported_version"].startswith(f"{version}.stable.official."):
        raise ValueError("toolchain reported version is not the official declared Godot version")
    return result


def load_contract(path: Path, project: Path) -> list[HeadlessCase]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        raise ValueError("required headless suite must use schema_version 1")
    rows = data.get("tests") if isinstance(data, dict) else None
    if not isinstance(rows, list) or not rows:
        raise ValueError("required headless suite must declare at least one test")

    cases: list[HeadlessCase] = []
    seen: set[str] = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ValueError(f"headless suite row {index} is not an object")
        case_id = str(row.get("id", "")).strip()
        marker = str(row.get("pass_marker", "")).strip()
        scene_value = row.get("scene")
        scene = str(scene_value).strip() if scene_value is not None else None
        args_value = row.get("args", [])
        if not case_id or case_id in seen:
            raise ValueError(f"headless suite id is empty or duplicated: {case_id!r}")
        if not marker:
            raise ValueError(f"headless suite case {case_id!r} has no PASS marker")
        if not isinstance(args_value, list) or any(not isinstance(arg, str) for arg in args_value):
            raise ValueError(f"headless suite case {case_id!r} args must be a string list")
        if scene is None and not args_value:
            raise ValueError(f"headless suite case {case_id!r} has neither a scene nor arguments")
        timeout_value = row.get("timeout_seconds")
        if timeout_value is not None and (
            not isinstance(timeout_value, int)
            or isinstance(timeout_value, bool)
            or not 1 <= timeout_value <= MAX_CASE_TIMEOUT_SECONDS
        ):
            raise ValueError(
                f"headless suite case {case_id!r} timeout_seconds must be an integer "
                f"from 1 to {MAX_CASE_TIMEOUT_SECONDS}"
            )
        if scene is not None:
            if not scene.startswith("res://tests/") or not scene.endswith(".tscn"):
                raise ValueError(f"headless suite case {case_id!r} uses an invalid test scene: {scene}")
            scene_path = project / scene.removeprefix("res://")
            if not scene_path.is_file():
                raise ValueError(f"headless suite scene does not exist: {scene}")
        seen.add(case_id)
        cases.append(HeadlessCase(case_id, scene, tuple(args_value), marker, timeout_value))
    return cases


def _startup_error_line(output: str) -> str | None:
    return next((line for line in output.splitlines() if STARTUP_ERROR_PATTERN.search(line)), None)


# The machine lock is an OS file lock on one byte, so the system releases it
# when its holder exits, even on a crash, and no stale lock file can block.
if sys.platform == "win32":
    import msvcrt

    def _lock_byte(fd: int) -> None:
        msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)

    def _unlock_byte(fd: int) -> None:
        msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)

else:
    import fcntl

    def _lock_byte(fd: int) -> None:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def _unlock_byte(fd: int) -> None:
        fcntl.flock(fd, fcntl.LOCK_UN)


def default_machine_lock_path() -> Path:
    return Path(tempfile.gettempdir()) / MACHINE_LOCK_NAME


@contextlib.contextmanager
def machine_lock(path: Path) -> Iterator[bool]:
    """Hold the machine-wide Godot lock while the block runs, if it is free.

    Yields True while it holds the lock, or False, holding nothing, when
    another process (or another handle in this one) already has it.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a+b") as handle:
        handle.seek(0)
        try:
            _lock_byte(handle.fileno())
        except OSError:
            yield False
            return
        try:
            yield True
        finally:
            handle.seek(0)
            _unlock_byte(handle.fileno())


def run_suite(
    *,
    godot: str,
    project: Path,
    contract: Path,
    toolchain: Path,
    timeout_seconds: int,
    command_runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    lock_path: Path | None = None,
    clock: Callable[[], float] = time.monotonic,
) -> int:
    lock_file = lock_path if lock_path is not None else default_machine_lock_path()
    with machine_lock(lock_file) as held:
        if not held:
            print(
                "headless_suite: blocked: another Godot suite or capture holds the "
                f"machine lock ({lock_file}); run one at a time",
                file=sys.stderr,
            )
            return LOCK_BLOCKED_EXIT
        return _run_suite_locked(
            godot=godot,
            project=project,
            contract=contract,
            toolchain=toolchain,
            timeout_seconds=timeout_seconds,
            command_runner=command_runner,
            clock=clock,
        )


def _run_suite_locked(
    *,
    godot: str,
    project: Path,
    contract: Path,
    toolchain: Path,
    timeout_seconds: int,
    command_runner: Callable[..., subprocess.CompletedProcess[str]],
    clock: Callable[[], float],
) -> int:
    expected = load_toolchain(toolchain)["reported_version"]
    version_result = command_runner(
        [godot, "--version"], capture_output=True, text=True, check=False, timeout=30
    )
    version_output = (version_result.stdout + version_result.stderr).strip()
    if version_result.returncode != 0 or version_output != expected:
        print(
            f"headless_suite: Godot version mismatch; expected exact {expected!r}, "
            f"got exit={version_result.returncode} output={version_output!r}",
            file=sys.stderr,
        )
        return 1
    print(f"headless_suite: Godot {version_output}")

    try:
        cases = load_contract(contract, project)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"headless_suite: invalid contract: {exc}", file=sys.stderr)
        return 1

    # Godot 4.2.2 can return 1 from a successful Windows headless import while
    # emitting only display/importer warnings. Treat the import as a cache-
    # population prepass and let the required startup/scene cases make success
    # authoritative: a missing import or parse failure makes those cases red.
    print("\n=== clean-checkout-import ===")
    try:
        import_result = command_runner(
            [godot, "--headless", "--path", str(project), "--import"],
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        print("headless_suite[clean-checkout-import]: timed out", file=sys.stderr)
        return 1
    import_output = import_result.stdout + import_result.stderr
    print(import_output, end="" if import_output.endswith("\n") else "\n")
    print(f"headless_suite: import prepass exit={import_result.returncode} (non-authoritative)")

    executed = 0
    for case in cases:
        limit = case.timeout_seconds if case.timeout_seconds is not None else timeout_seconds
        command = [godot, "--headless", "--path", str(project)]
        if case.scene is not None:
            command.append(case.scene)
        command.extend(case.args)
        print(f"\n=== {case.case_id} ===")
        started = clock()
        try:
            result = command_runner(
                command,
                capture_output=True,
                text=True,
                check=False,
                timeout=limit,
            )
        except subprocess.TimeoutExpired:
            print(f"headless_suite[{case.case_id}]: timed out after {limit} s", file=sys.stderr)
            return 1
        elapsed = clock() - started
        output = result.stdout + result.stderr
        print(output, end="" if output.endswith("\n") else "\n")
        # Every case's time, so limits are set from measurements.
        print(f"headless_suite[{case.case_id}]: took {elapsed:.1f} s (limit {limit} s)")
        executed += 1
        if result.returncode != 0:
            print(
                f"headless_suite[{case.case_id}]: process exited {result.returncode}",
                file=sys.stderr,
            )
            return 1
        if case.args == ("--", "--ci-startup-smoke"):
            error_line = _startup_error_line(output)
            if error_line is not None:
                print(
                    f"headless_suite[{case.case_id}]: startup emitted an error: {error_line}",
                    file=sys.stderr,
                )
                return 1
        if case.pass_marker not in output.splitlines():
            print(
                f"headless_suite[{case.case_id}]: missing exact marker line {case.pass_marker!r}",
                file=sys.stderr,
            )
            return 1

    if executed == 0:
        print("headless_suite: zero tests executed", file=sys.stderr)
        return 1
    print(f"\nheadless_suite: PASS ({executed} tests)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--toolchain", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=90)
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    return run_suite(
        godot=args.godot,
        project=args.project.resolve(),
        contract=args.contract.resolve(),
        toolchain=args.toolchain.resolve(),
        timeout_seconds=args.timeout,
    )


if __name__ == "__main__":
    raise SystemExit(main())
