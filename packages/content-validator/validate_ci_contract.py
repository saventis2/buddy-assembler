#!/usr/bin/env python3
"""Validate that local and CI test/toolchain contracts cannot drift silently."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from headless_suite import load_contract, load_toolchain


def validate(repo: Path) -> list[str]:
    errors: list[str] = []
    runtime = repo / "apps" / "runtime-godot"
    toolchain_path = runtime / "toolchain.json"
    suite_path = runtime / "tests" / "required_headless_scenes.json"
    workflow_path = repo / ".github" / "workflows" / "runtime-smoke.yml"
    python_workflow_path = repo / ".github" / "workflows" / "python-lint.yml"
    local_runner_path = runtime / "tests" / "run_headless_checks.ps1"
    burn_in_path = runtime / "tests" / "run_burn_in.ps1"
    project_path = runtime / "project.godot"

    try:
        toolchain = load_toolchain(toolchain_path)
        cases = load_contract(suite_path, runtime)
    except (OSError, ValueError) as exc:
        return [str(exc)]

    workflow = workflow_path.read_text(encoding="utf-8")
    python_workflow = python_workflow_path.read_text(encoding="utf-8")
    local_runner = local_runner_path.read_text(encoding="utf-8")
    burn_in = burn_in_path.read_text(encoding="utf-8")
    project = project_path.read_text(encoding="utf-8")

    version_match = re.search(r'^\s*GODOT_VERSION:\s*"([^"]+)"\s*$', workflow, re.MULTILINE)
    release_match = re.search(r'^\s*GODOT_RELEASE:\s*"([^"]+)"\s*$', workflow, re.MULTILINE)
    if version_match is None or version_match.group(1) != toolchain["godot_version"]:
        errors.append("runtime workflow GODOT_VERSION differs from toolchain.json")
    if release_match is None or release_match.group(1) != toolchain["godot_release"]:
        errors.append("runtime workflow GODOT_RELEASE differs from toolchain.json")
    expected_feature = ".".join(toolchain["godot_version"].split(".")[:2])
    if f'config/features=PackedStringArray("{expected_feature}")' not in project:
        errors.append("project.godot feature version differs from toolchain.json")

    if "required_headless_scenes.json" not in workflow or "headless_suite.py" not in workflow:
        errors.append("runtime workflow does not execute the shared headless contract")
    if "required_headless_scenes.json" not in local_runner or "headless_suite.py" not in local_runner:
        errors.append("local headless script does not execute the shared headless contract")
    if "toolchain.json" not in local_runner or "toolchain.json" not in burn_in:
        errors.append("local runtime scripts do not consume the Godot toolchain contract")

    contract_scenes = {case.scene for case in cases if case.scene is not None}
    tracked_test_scenes = {
        f"res://tests/{path.name}" for path in (runtime / "tests").glob("*Test.tscn")
    }
    missing_from_contract = sorted(tracked_test_scenes - contract_scenes)
    stale_contract_scenes = sorted(contract_scenes - tracked_test_scenes)
    if missing_from_contract:
        errors.append(f"tracked required scenes absent from contract: {missing_from_contract}")
    if stale_contract_scenes:
        errors.append(f"contract scenes absent from checkout: {stale_contract_scenes}")

    required_python_paths = (
        "tools/importers/tests",
        "apps/runtime-godot/tools/tests",
        "packages/content-validator",
    )
    if "python -m pytest" not in python_workflow or any(
        path not in python_workflow for path in required_python_paths
    ):
        errors.append("python workflow does not execute every required Python test suite")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args(argv)
    errors = validate(args.repo_root.resolve())
    if errors:
        for error in errors:
            print(f"ci_contract: FAIL: {error}", file=sys.stderr)
        return 1
    print("ci_contract: PASS (toolchain, required scenes, local runner, CI, Python suites)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
