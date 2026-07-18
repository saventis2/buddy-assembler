#!/usr/bin/env python3
"""Run the single required Godot headless-suite contract."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


@dataclass(frozen=True)
class HeadlessCase:
    case_id: str
    scene: str | None
    args: tuple[str, ...]
    pass_marker: str


def load_toolchain(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    required = ("godot_version", "godot_release", "reported_version_prefix")
    if not isinstance(data, dict) or any(not str(data.get(key, "")).strip() for key in required):
        raise ValueError("toolchain contract is missing required Godot version fields")
    result = {key: str(data[key]) for key in required}
    version = result["godot_version"]
    if result["godot_release"] != f"{version}-stable":
        raise ValueError("toolchain Godot release does not match its version")
    if result["reported_version_prefix"] != f"{version}.stable":
        raise ValueError("toolchain reported-version prefix does not match its version")
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
        if scene is not None:
            if not scene.startswith("res://tests/") or not scene.endswith(".tscn"):
                raise ValueError(f"headless suite case {case_id!r} uses an invalid test scene: {scene}")
            scene_path = project / scene.removeprefix("res://")
            if not scene_path.is_file():
                raise ValueError(f"headless suite scene does not exist: {scene}")
        seen.add(case_id)
        cases.append(HeadlessCase(case_id, scene, tuple(args_value), marker))
    return cases


def run_suite(
    *,
    godot: str,
    project: Path,
    contract: Path,
    toolchain: Path,
    timeout_seconds: int,
    command_runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> int:
    expected = load_toolchain(toolchain)["reported_version_prefix"]
    version_result = command_runner(
        [godot, "--version"], capture_output=True, text=True, check=False, timeout=30
    )
    version_output = (version_result.stdout + version_result.stderr).strip()
    if version_result.returncode != 0 or not version_output.startswith(expected):
        print(
            f"headless_suite: Godot version mismatch; expected prefix {expected!r}, "
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

    executed = 0
    for case in cases:
        command = [godot, "--headless", "--path", str(project)]
        if case.scene is not None:
            command.append(case.scene)
        command.extend(case.args)
        print(f"\n=== {case.case_id} ===")
        try:
            result = command_runner(
                command,
                capture_output=True,
                text=True,
                check=False,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired:
            print(f"headless_suite[{case.case_id}]: timed out", file=sys.stderr)
            return 1
        output = result.stdout + result.stderr
        print(output, end="" if output.endswith("\n") else "\n")
        executed += 1
        if result.returncode != 0:
            print(
                f"headless_suite[{case.case_id}]: process exited {result.returncode}",
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
