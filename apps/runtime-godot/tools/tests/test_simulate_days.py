#!/usr/bin/env python3
"""Unit tests for simulate_days.py, with a fake Godot (no Godot needed)."""

from __future__ import annotations

import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import simulate_days as sim  # noqa: E402

REPORTED = "4.2.2.stable.official.15073afe3"


class FakeGodot:
    def __init__(self, *, version: str = REPORTED, done: bool = True) -> None:
        self.version = version
        self.done = done
        self.calls: list[list[str]] = []

    def __call__(self, command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
        self.calls.append(list(command))
        if command[1:] == ["--version"]:
            return subprocess.CompletedProcess(command, 0, self.version + "\n", "")
        if "--import" in command:
            return subprocess.CompletedProcess(command, 0, "imported\n", "")
        out = "report text\n"
        if self.done:
            out += "simulate_days: DONE (3 days, 432 decisions)\n"
        return subprocess.CompletedProcess(command, 0, out, "")


def make_project(root: Path, *, imported: bool) -> Path:
    project = root / "project"
    project.mkdir()
    (project / "toolchain.json").write_text(
        json.dumps(
            {
                "godot_version": "4.2.2",
                "godot_release": "4.2.2-stable",
                "reported_version": REPORTED,
            }
        ),
        encoding="utf-8",
    )
    if imported:
        (project / ".godot").mkdir()
    return project


def run(
    fake: FakeGodot, project: Path, out: Path | None = None, world: str = "town"
) -> tuple[int, str, str]:
    stdout, stderr = io.StringIO(), io.StringIO()
    with redirect_stdout(stdout), redirect_stderr(stderr):
        code = sim.run_simulation(
            godot="godot",
            project=project,
            days=3,
            seed=7,
            journal="none",
            world=world,
            out=out,
            command_runner=fake,
        )
    return code, stdout.getvalue(), stderr.getvalue()


class SimulateDaysTests(unittest.TestCase):
    def test_refuses_a_different_godot_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = make_project(Path(tmp), imported=True)
            fake = FakeGodot(version="4.6.2.stable.official.deadbeef")
            code, _out, err = run(fake, project)
            self.assertEqual(code, 1)
            self.assertIn("version mismatch", err)
            self.assertIn("project.godot", err)
            self.assertEqual(len(fake.calls), 1)

    def test_fails_when_the_done_marker_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = make_project(Path(tmp), imported=True)
            code, _out, err = run(FakeGodot(done=False), project)
            self.assertEqual(code, 1)
            self.assertIn("DONE", err)

    def test_passes_arguments_through_and_makes_out_absolute(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = make_project(Path(tmp), imported=True)
            fake = FakeGodot()
            code, out, _err = run(fake, project, Path("report.json"))
            self.assertEqual(code, 0)
            self.assertIn("simulate_days: DONE", out)
            command = fake.calls[-1]
            self.assertEqual(
                command[:6],
                ["godot", "--headless", "--path", str(project), sim.SCENE, "--"],
            )
            self.assertEqual(
                command[6:11], [sim.NO_SAVE_ARG, "--days=3", "--seed=7", "--journal=none", "--world=town"]
            )
            out_arg = command[11]
            self.assertTrue(out_arg.startswith("--out="))
            self.assertTrue(Path(out_arg.removeprefix("--out=")).is_absolute())

    def test_world_land_reaches_the_godot_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = make_project(Path(tmp), imported=True)
            fake = FakeGodot()
            code, _out, _err = run(fake, project, world="land")
            self.assertEqual(code, 0)
            self.assertIn("--world=land", fake.calls[-1])

    def test_imports_only_when_godot_folder_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fresh = FakeGodot()
            code, _out, _err = run(fresh, make_project(Path(tmp), imported=False))
            self.assertEqual(code, 0)
            imports = [call for call in fresh.calls if "--import" in call]
            self.assertEqual(len(imports), 1)
            self.assertEqual(imports[0][-2:], ["--", sim.NO_SAVE_ARG])
        with tempfile.TemporaryDirectory() as tmp:
            warm = FakeGodot()
            code, _out, _err = run(warm, make_project(Path(tmp), imported=True))
            self.assertEqual(code, 0)
            self.assertEqual(sum("--import" in call for call in warm.calls), 0)


if __name__ == "__main__":
    unittest.main()
