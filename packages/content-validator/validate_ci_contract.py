#!/usr/bin/env python3
"""Validate that local and CI test/toolchain contracts cannot drift silently."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

from headless_suite import load_contract, load_toolchain


_AUTHORITY_WORKFLOW_SHA256 = {
    ".github/workflows/runtime-smoke.yml": (
        "9f16f5a4b2909c781710ef8b9cd04607ff936320c7b88d9ed360f988580dda2a"
    ),
    ".github/workflows/python-lint.yml": (
        "0f19dfd99a79f0e50f6a8d46cf2a1d89b75547358d7496713798729f09c648fc"
    ),
}


def _normalized_text_sha256(text: str) -> str:
    """Hash exact text after universal-newline normalization.

    ``Path.read_text`` normalizes checkout CRLF and LF to ``\n`` while retaining
    terminal-newline presence. Everything else, including comments and
    whitespace, remains authority-bearing. Any legitimate edit to either gate
    workflow must intentionally update this digest and the contract tests in
    the same reviewed change.
    """
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


_STRUCTURAL_ANCHOR_OR_ALIAS = re.compile(r"(?<!\S)[&*][^\s\[\]{},]+")


def _workflow_has_structural_anchor_or_alias(workflow: str) -> bool:
    """Reject YAML indirection outside literal run blocks.

    The contract validator intentionally inspects the narrow workflow shape
    without a YAML dependency. YAML aliases can otherwise turn a syntactically
    unrelated key into ``if`` or ``continue-on-error`` after parsing. Literal
    run bodies are commands rather than workflow structure, so skip them.
    """
    lines = workflow.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        indent = len(line) - len(line.lstrip())
        if line.strip() in ("run: |", "run: >"):
            index += 1
            while index < len(lines):
                child = lines[index]
                child_indent = len(child) - len(child.lstrip())
                if child.strip() and child_indent <= indent:
                    break
                index += 1
            continue
        stripped = line.lstrip()
        if not stripped.startswith("#") and _STRUCTURAL_ANCHOR_OR_ALIAS.search(line):
            return True
        index += 1
    return False


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


def _mapping_has_run_shell_default(mapping: str) -> bool:
    """Return whether this mapping defines ``defaults.run.shell`` directly."""
    lines = mapping.splitlines()
    if not lines:
        return False
    mapping_indent = len(lines[0]) - len(lines[0].lstrip())
    defaults = f"{' ' * (mapping_indent + 2)}defaults:"
    runs = f"{' ' * (mapping_indent + 4)}run:"
    shell_prefix = f"{' ' * (mapping_indent + 6)}shell:"
    for index, line in enumerate(lines):
        if line != defaults:
            continue
        end = index + 1
        while end < len(lines):
            child = lines[end]
            child_indent = len(child) - len(child.lstrip())
            if child.strip() and child_indent <= mapping_indent + 2:
                break
            end += 1
        for run_index in range(index + 1, end):
            if lines[run_index] != runs:
                continue
            run_end = run_index + 1
            while run_end < end:
                child = lines[run_end]
                child_indent = len(child) - len(child.lstrip())
                if child.strip() and child_indent <= mapping_indent + 4:
                    break
                run_end += 1
            if any(line.startswith(shell_prefix) for line in lines[run_index + 1 : run_end]):
                return True
    return False


def _workflow_has_run_shell_default(workflow: str) -> bool:
    """Return whether a workflow-level ``defaults.run.shell`` is present."""
    lines = workflow.splitlines()
    for index, line in enumerate(lines):
        if line != "defaults:":
            continue
        end = index + 1
        while end < len(lines):
            child = lines[end]
            child_indent = len(child) - len(child.lstrip())
            if child.strip() and child_indent <= 0:
                break
            end += 1
        for run_index in range(index + 1, end):
            if lines[run_index] != "  run:":
                continue
            if any(line.startswith("    shell:") for line in lines[run_index + 1 : end]):
                return True
    return False


def _workflow_has_only_canonical_top_level_lines(
    workflow: str, canonical_lines: tuple[str, ...]
) -> bool:
    """Reject unexpected top-level workflow metadata before YAML can resolve it."""
    found: list[str] = []
    for line in workflow.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if len(line) - len(line.lstrip()) == 0:
            if line not in canonical_lines:
                return False
            found.append(line)
    return sorted(found) == sorted(canonical_lines)


def _mapping_has_only_canonical_direct_lines(
    mapping: str, canonical_lines: tuple[str, ...]
) -> bool:
    """Require canonical direct mapping metadata, allowing one explicit false."""
    lines = mapping.splitlines()
    if not lines:
        return False
    mapping_indent = len(lines[0]) - len(lines[0].lstrip())
    found: list[str] = []
    explicit_false = 0
    for line in lines[1:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if len(line) - len(line.lstrip()) != mapping_indent + 2:
            continue
        if line == f"{' ' * (mapping_indent + 2)}continue-on-error: false":
            explicit_false += 1
            continue
        if line not in canonical_lines:
            return False
        found.append(line)
    return explicit_false <= 1 and sorted(found) == sorted(canonical_lines)


def _required_step_has_only_canonical_direct_lines(
    step: str,
    name: str,
    canonical_lines: tuple[str, ...],
) -> bool:
    """Require a named step's direct metadata to be exactly authoritative."""
    lines = step.splitlines()
    if not lines:
        return False
    item_indent = len(lines[0]) - len(lines[0].lstrip())
    if lines[0] != f"{' ' * item_indent}- name: {name}":
        return False
    found: list[str] = []
    explicit_false = 0
    for line in lines[1:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if len(line) - len(line.lstrip()) != item_indent + 2:
            continue
        if line == f"{' ' * (item_indent + 2)}continue-on-error: false":
            explicit_false += 1
            continue
        if line not in canonical_lines:
            return False
        found.append(line)
    return explicit_false <= 1 and sorted(found) == sorted(canonical_lines)


def _required_step_enforces(
    workflow: str,
    job_id: str,
    name: str,
    exact_run_lines: tuple[str, ...],
    required_shell: str | None = None,
    required_working_directory: str | None = None,
) -> bool:
    job = _named_workflow_job(workflow, job_id)
    canonical_job_lines = {
        "parse-and-smoke": (
            "    name: Parse + headless smoke (Linux)",
            "    runs-on: ubuntu-latest",
            "    timeout-minutes: 15",
            "    steps:",
        ),
        "windows-export": (
            "    name: Windows export (release-truth artifact)",
            "    runs-on: windows-latest",
            "    timeout-minutes: 30",
            "    steps:",
        ),
        "python-lint": ("    runs-on: ubuntu-latest", "    steps:"),
    }
    if job is None or not _mapping_has_only_canonical_direct_lines(
        job, canonical_job_lines[job_id]
    ):
        return False
    step = _direct_named_job_step(job, name)
    if step is None:
        return False
    canonical_step_lines: tuple[str, ...] = ("        run: |",)
    if required_shell is None:
        if required_working_directory is not None:
            return False
    else:
        if required_working_directory is None:
            return False
        canonical_step_lines = (
            f"        shell: {required_shell}",
            f"        working-directory: {required_working_directory}",
            "        run: |",
        )
    if not _required_step_has_only_canonical_direct_lines(
        step, name, canonical_step_lines
    ):
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

    workflow_digests = (
        ("runtime", workflow_path, workflow),
        ("python", python_workflow_path, python_workflow),
    )
    for label, workflow_file_path, text in workflow_digests:
        relative = workflow_file_path.relative_to(repo).as_posix()
        expected_digest = _AUTHORITY_WORKFLOW_SHA256[relative]
        if _normalized_text_sha256(text) != expected_digest:
            errors.append(
                f"{label} workflow differs from canonical full-file authority digest"
            )

    if _workflow_has_structural_anchor_or_alias(workflow):
        errors.append("runtime workflow must not use YAML anchors or aliases in workflow structure")
    if _workflow_has_structural_anchor_or_alias(python_workflow):
        errors.append("python workflow must not use YAML anchors or aliases in workflow structure")
    if _workflow_has_run_shell_default(workflow):
        errors.append("runtime workflow must not set defaults.run.shell")
    if _workflow_has_run_shell_default(python_workflow):
        errors.append("python workflow must not set defaults.run.shell")
    if not _workflow_has_only_canonical_top_level_lines(
        workflow, ("name: Runtime smoke", "on:", "env:", "jobs:")
    ):
        errors.append("runtime workflow has non-canonical top-level contract metadata")
    if not _workflow_has_only_canonical_top_level_lines(
        python_workflow, ("name: Python lint", "on:", "jobs:")
    ):
        errors.append("python workflow has non-canonical top-level contract metadata")

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
        required_shell="pwsh",
        required_working_directory="build/windows",
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
    for step_name, suite_relative in required_python_suites:
        expected_command = (
            "env -u PYTEST_ADDOPTS python -m pytest -q -o addopts= "
            f"{suite_relative}"
        )
        if not _required_step_enforces(
            python_workflow,
            "python-lint",
            step_name,
            (expected_command,),
        ):
            errors.append(
                "python workflow does not actively execute required suite: "
                f"{suite_relative}"
            )
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
