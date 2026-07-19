#!/usr/bin/env python3
"""Validate that local and CI test/toolchain contracts cannot drift silently."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from headless_suite import load_contract, load_toolchain


def _workflow_run_blocks(workflow: str) -> list[list[str]]:
    """Return active shell lines from YAML literal run blocks.

    This intentionally handles the narrow GitHub Actions shape used by this
    repository without adding a YAML dependency to the content-validator job.
    Comment-only lines are excluded so a disabled command cannot satisfy a
    gate-presence assertion.
    """
    lines = workflow.splitlines()
    blocks: list[list[str]] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        indent = len(line) - len(line.lstrip())
        if line.strip() not in ("run: |", "run: >"):
            index += 1
            continue
        index += 1
        block: list[str] = []
        while index < len(lines):
            child = lines[index]
            child_indent = len(child) - len(child.lstrip())
            if child.strip() and child_indent <= indent:
                break
            stripped = child.strip()
            if stripped and not stripped.startswith("#"):
                block.append(stripped)
            index += 1
        blocks.append(block)
    return blocks


def _active_script_lines(script: str) -> list[str]:
    return [
        line.strip()
        for line in script.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def _named_workflow_job(workflow: str, job_id: str) -> str | None:
    lines = workflow.splitlines()
    jobs = [index for index, line in enumerate(lines) if line == "jobs:"]
    if len(jobs) != 1:
        return None
    jobs_start = jobs[0] + 1
    jobs_end = jobs_start
    while jobs_end < len(lines):
        child = lines[jobs_end]
        child_indent = len(child) - len(child.lstrip())
        if (
            child.strip()
            and not child.lstrip().startswith("#")
            and child_indent == 0
        ):
            break
        jobs_end += 1

    target = f"  {job_id}:"
    matches = [
        index
        for index in range(jobs_start, jobs_end)
        if lines[index] == target
    ]
    if len(matches) != 1:
        return None
    start = matches[0]
    end = start + 1
    while end < jobs_end:
        child = lines[end]
        child_indent = len(child) - len(child.lstrip())
        if (
            child.strip()
            and not child.lstrip().startswith("#")
            and child_indent <= 2
        ):
            break
        end += 1
    return "\n".join(lines[start:end])


def _direct_named_job_step(job: str, name: str) -> str | None:
    lines = job.splitlines()
    if not lines:
        return None
    job_indent = len(lines[0]) - len(lines[0].lstrip())
    steps_indent = job_indent + 2
    steps_matches = [
        index
        for index, line in enumerate(lines[1:], start=1)
        if line == f"{' ' * steps_indent}steps:"
    ]
    if len(steps_matches) != 1:
        return None
    steps_start = steps_matches[0] + 1
    steps_end = steps_start
    while steps_end < len(lines):
        child = lines[steps_end]
        child_indent = len(child) - len(child.lstrip())
        if (
            child.strip()
            and not child.lstrip().startswith("#")
            and child_indent <= steps_indent
        ):
            break
        steps_end += 1

    item_indent = steps_indent + 2
    target = f"{' ' * item_indent}- name: {name}"
    matches = [
        index
        for index in range(steps_start, steps_end)
        if lines[index] == target
    ]
    if len(matches) != 1:
        return None
    start = matches[0]
    end = start + 1
    while end < steps_end:
        child = lines[end]
        child_indent = len(child) - len(child.lstrip())
        if (
            child.strip()
            and not child.lstrip().startswith("#")
            and child_indent <= item_indent
        ):
            break
        end += 1
    return "\n".join(lines[start:end])


def _direct_run_block(step: str) -> list[str] | None:
    lines = step.splitlines()
    if not lines:
        return None
    item_indent = len(lines[0]) - len(lines[0].lstrip())
    run_indent = item_indent + 2
    run_matches = [
        index
        for index, line in enumerate(lines[1:], start=1)
        if line == f"{' ' * run_indent}run: |"
    ]
    if len(run_matches) != 1:
        return None
    start = run_matches[0] + 1
    end = start
    while end < len(lines):
        child = lines[end]
        child_indent = len(child) - len(child.lstrip())
        if (
            child.strip()
            and not child.lstrip().startswith("#")
            and child_indent <= run_indent
        ):
            break
        end += 1
    return [
        line.strip()
        for line in lines[start:end]
        if line.strip() and not line.lstrip().startswith("#")
    ]


def _mapping_metadata_values(mapping: str, key: str) -> list[str]:
    lines = mapping.splitlines()
    indent = len(lines[0]) - len(lines[0].lstrip()) + 2
    key_forms = (key, f"'{key}'", f'"{key}"')
    key_pattern = "|".join(re.escape(form) for form in key_forms)
    pattern = re.compile(rf"^{' ' * indent}(?:{key_pattern})\s*:\s*(.*)$")
    values: list[str] = []
    for line in lines[1:]:
        match = pattern.match(line)
        if match is not None:
            values.append(match.group(1).strip())
    return values


def _mapping_enforces_failure(mapping: str) -> bool:
    if _mapping_metadata_values(mapping, "if"):
        return False
    if _mapping_metadata_values(mapping, "needs"):
        return False
    continue_values = _mapping_metadata_values(mapping, "continue-on-error")
    return len(continue_values) == 0 or (
        len(continue_values) == 1
        and continue_values[0].strip("'\"").casefold() == "false"
    )


def _required_step_enforces(
    workflow: str,
    job_id: str,
    name: str,
    exact_run_lines: tuple[str, ...],
) -> bool:
    job = _named_workflow_job(workflow, job_id)
    if job is None or not _mapping_enforces_failure(job):
        return False
    step = _direct_named_job_step(job, name)
    if step is None or not _mapping_enforces_failure(step):
        return False
    return _direct_run_block(step) == list(exact_run_lines)


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
    workflow_blocks = _workflow_run_blocks(workflow)
    local_runner_lines = _active_script_lines(local_runner)
    burn_in_lines = _active_script_lines(burn_in)

    version_match = re.search(r'^\s*GODOT_VERSION:\s*"([^"]+)"\s*$', workflow, re.MULTILINE)
    release_match = re.search(r'^\s*GODOT_RELEASE:\s*"([^"]+)"\s*$', workflow, re.MULTILINE)
    reported_match = re.search(
        r'^\s*GODOT_REPORTED_VERSION:\s*"([^"]+)"\s*$', workflow, re.MULTILINE
    )
    if version_match is None or version_match.group(1) != toolchain["godot_version"]:
        errors.append("runtime workflow GODOT_VERSION differs from toolchain.json")
    if release_match is None or release_match.group(1) != toolchain["godot_release"]:
        errors.append("runtime workflow GODOT_RELEASE differs from toolchain.json")
    if reported_match is None or reported_match.group(1) != toolchain["reported_version"]:
        errors.append("runtime workflow GODOT_REPORTED_VERSION differs from toolchain.json")
    expected_feature = ".".join(toolchain["godot_version"].split(".")[:2])
    if f'config/features=PackedStringArray("{expected_feature}")' not in project:
        errors.append("project.godot feature version differs from toolchain.json")

    required_ci_suite_command = (
        "set -euo pipefail",
        "python packages/content-validator/headless_suite.py \\",
        "--godot godot \\",
        "--project \"${RUNTIME_DIR}\" \\",
        "--contract \"${RUNTIME_DIR}/tests/required_headless_scenes.json\" \\",
        "--toolchain \"${RUNTIME_DIR}/toolchain.json\" \\",
        "--timeout 90 2>&1 | tee headless-suite.log",
    )
    if not _required_step_enforces(
        workflow,
        "parse-and-smoke",
        "Required headless suite (shared local/CI contract)",
        required_ci_suite_command,
    ):
        errors.append("runtime workflow does not actively execute the shared headless contract")

    required_local_suite_command = (
        "& $Python $runner `",
        "--contract $contract `",
        "--toolchain $toolchain `",
    )
    if not all(line in local_runner_lines for line in required_local_suite_command):
        errors.append("local headless script does not actively execute the shared headless contract")
    if '$toolchain = Join-Path $projectPath "toolchain.json"' not in local_runner_lines:
        errors.append("local headless script does not actively consume the Godot toolchain contract")
    if '$toolchainPath = Join-Path $runtime "toolchain.json"' not in burn_in_lines:
        errors.append("burn-in script does not actively consume the Godot toolchain contract")

    startup_cases = [case for case in cases if case.case_id == "project-startup"]
    if len(startup_cases) != 1:
        errors.append("headless contract must contain exactly one project-startup case")
    else:
        startup = startup_cases[0]
        if (
            startup.scene is not None
            or startup.args != ("--", "--ci-startup-smoke")
            or startup.pass_marker != "project_startup_smoke: PASS"
        ):
            errors.append("project-startup case does not match the exact startup contract")

    required_exported_startup = (
        '$ErrorActionPreference = "Stop"',
        "$PSNativeCommandUseErrorActionPreference = $false",
        '$exe = Join-Path (Get-Location).Path "BuddyRuntime.exe"',
        "& $exe --headless -- --ci-startup-smoke 2>&1 |",
        "Tee-Object -FilePath ..\\..\\win-startup-smoke.log",
        "if ($LASTEXITCODE -ne 0) {",
        'Write-Error "Exported default-runtime startup failed with exit $LASTEXITCODE"',
        "exit $LASTEXITCODE",
        "}",
        "if (Select-String -Path ..\\..\\win-startup-smoke.log -Pattern '^\\s*(SCRIPT ERROR|ERROR):|\\bParse Error\\b' -Quiet) {",
        'Write-Error "Exported default runtime emitted an error — see win-startup-smoke.log"',
        "exit 1",
        "}",
        "if (-not (Select-String -Path ..\\..\\win-startup-smoke.log -Pattern '^project_startup_smoke: PASS$' -Quiet)) {",
        'Write-Error "Exported default runtime did not emit the exact startup PASS marker"',
        "exit 1",
        "}",
    )
    if not _required_step_enforces(
        workflow,
        "windows-export",
        "Start and cleanly exit exported default runtime",
        required_exported_startup,
    ):
        errors.append("Windows workflow does not actively run and verify exported default startup")

    if (
        "godot-windows-console-pair-${{ env.GODOT_RELEASE }}-v2" not in workflow
        or not any(
            'Get-ChildItem $godotDir -Filter "Godot_v*_win64_console.exe"' in line
            for line in _active_script_lines(workflow)
        )
        or "$godotMainExe = $godotExe -replace '_console\\.exe$', '.exe'"
        not in _active_script_lines(workflow)
        or not any("& $env:GODOT_EXE --headless --import" in line for block in workflow_blocks for line in block)
        or not any("& $env:GODOT_EXE --headless --export-release" in line for block in workflow_blocks for line in block)
    ):
        errors.append("Windows workflow does not use the cache-isolated Godot console/main pair")

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

    required_python_suites = (
        ("Importer Python unit suite (zero tests fails)", "tools/importers/tests"),
        (
            "Runtime-tool Python unit suite (zero tests fails)",
            "apps/runtime-godot/tools/tests",
        ),
        ("CI-contract Python unit suite (zero tests fails)", "packages/content-validator"),
    )
    for step_name, path in required_python_suites:
        expected_command = f"python -m pytest -q {path}"
        if not _required_step_enforces(
            python_workflow,
            "python-lint",
            step_name,
            (expected_command,),
        ):
            errors.append(f"python workflow does not actively execute required suite: {path}")
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
