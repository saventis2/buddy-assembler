#!/usr/bin/env python3
"""Fast-forward a brand-new buddy through N simulated days and print its life.

Runs `res://tests/SimulateDays.tscn` headless. The simulation drives the real
AppState code with a supplied clock and never writes the save files. See
apps/runtime-godot/README.md ("Fast-forward").

    python apps/runtime-godot/tools/simulate_days.py --godot <path> \\
        [--days 30] [--seed 1] [--journal firsts] [--world land|town] [--out report.json]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Callable, TextIO

PROJECT_DEFAULT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "packages" / "content-validator"))
import headless_suite  # noqa: E402

SCENE = "res://tests/SimulateDays.tscn"
NO_SAVE_ARG = "--no-save"
DONE_PREFIX = "simulate_days: DONE"
TIMEOUT_SECONDS = 3600


def _echo(text: str, stream: TextIO | None = None) -> None:
    """Print text without dying on a console that cannot show every character."""
    target = stream if stream is not None else sys.stdout
    encoding = getattr(target, "encoding", None) or "utf-8"
    safe = text.encode(encoding, "replace").decode(encoding, "replace")
    print(safe, end="" if safe.endswith("\n") else "\n", file=target)


def run_simulation(
    *,
    godot: str,
    project: Path,
    days: int,
    seed: int,
    journal: str,
    world: str,
    out: Path | None,
    command_runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> int:
    try:
        expected = headless_suite.load_toolchain(project / "toolchain.json")["reported_version"]
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"simulate_days: cannot read toolchain.json: {exc}", file=sys.stderr)
        return 1
    version_result = command_runner(
        [godot, "--version"], capture_output=True, text=True, check=False, timeout=30
    )
    version_output = (version_result.stdout + version_result.stderr).strip()
    if version_result.returncode != 0 or version_output != expected:
        print(
            f"simulate_days: Godot version mismatch; expected exact {expected!r}, "
            f"got exit={version_result.returncode} output={version_output!r}. "
            "Refusing to run: a different Godot version rewrites project.godot.",
            file=sys.stderr,
        )
        return 1

    if not (project / ".godot").exists():
        print("simulate_days: first run, importing the project")
        # Like the headless suite: a Windows import can exit 1 and still work,
        # so this only fills the cache and the simulation below decides.
        command_runner(
            [godot, "--headless", "--path", str(project), "--import"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
            timeout=TIMEOUT_SECONDS,
        )

    # --no-save comes first: the app then starts without opening the save files,
    # so not even its start-up (a pending migration, a damaged file) can touch them.
    args = [NO_SAVE_ARG, f"--days={days}", f"--seed={seed}", f"--journal={journal}", f"--world={world}"]
    if out is not None:
        args.append(f"--out={out.resolve()}")
    command = [godot, "--headless", "--path", str(project), SCENE, "--", *args]
    try:
        result = command_runner(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        print("simulate_days: timed out", file=sys.stderr)
        return 1
    if result.stdout:
        _echo(result.stdout)
    if result.stderr:
        _echo(result.stderr, sys.stderr)
    if result.returncode != 0:
        print(f"simulate_days: Godot exited {result.returncode}", file=sys.stderr)
        return 1
    if not any(line.startswith(DONE_PREFIX) for line in result.stdout.splitlines()):
        print(f"simulate_days: no '{DONE_PREFIX}' line in the output", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--journal", choices=("all", "firsts", "none"), default="firsts")
    parser.add_argument("--world", choices=("town", "land"), default="land")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--project", type=Path, default=PROJECT_DEFAULT)
    args = parser.parse_args(argv)
    if not 1 <= args.days <= 3650:
        parser.error("--days must be between 1 and 3650")
    return run_simulation(
        godot=args.godot,
        project=args.project.resolve(),
        days=args.days,
        seed=args.seed,
        journal=args.journal,
        world=args.world,
        out=args.out,
    )


if __name__ == "__main__":
    raise SystemExit(main())
