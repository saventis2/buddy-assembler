#!/usr/bin/env python3
"""Turn a Godot idle_profile burn-in log into a PERF_BASELINE.md table row.

`apps/runtime-godot/tests/idle_profile.gd` (run via `tests/run_burn_in.ps1`)
writes a plain-text log to
`%APPDATA%\\Godot\\app_userdata\\Buddy Runtime\\perf\\idle_profile_<unix>.log`
that looks like this (see idle_profile.gd for the source of truth):

    idle_profile: spawning 1 actor; duration=600 s
    sample t=5.0s mem=47104 KB frames=298
    sample t=10.0s mem=47104 KB frames=598
    ...

    === Idle burn-in report ===
    Duration:   600 s
    Frames:     35847
    Min dt:     14.87 ms (67.3 fps)
    Max dt:     22.10 ms (45.2 fps)
    Avg dt:     16.66 ms (60.0 fps)
    Mem min:    47104 KB
    Mem max:    47232 KB
    Mem drift:  128 KB
    ===========================

A run that never gets past warmup writes `idle_profile: no frames
recorded` instead of a report block, and the file is saved with a
`.fail` suffix (see idle_profile.gd `_report_and_exit` / `_flush`).

This script parses the report block — plus the `sample ... mem=... KB`
lines for a sanity cross-check — and prints a single markdown row
matching the results table in docs/product/PERF_BASELINE.md:

    | Date (UTC) | Build | Duration | Avg fps | Max dt ms | Mem drift KB | Notes |

Every number in the row is read verbatim from what idle_profile.gd
itself already computed and wrote to the log (Avg fps from its "Avg
dt (... fps)" line, Max dt ms from its "Max dt" line, Mem drift KB
from its "Mem drift" line) — this script does not re-derive its own
definitions of those metrics.

IMPORTANT: this tool only reformats numbers that are already in the
log file you hand it. It cannot tell whether that log came from a
real multi-hour run against the exported Windows build or a 10-second
sanity check in the editor. Set --build and --notes honestly, and
don't feed it fabricated logs and represent the output as a real
measurement.

Usage:
    python apps/runtime-godot/tools/record_perf_baseline.py <log_file> --build "exported v0.1-rc"
    python apps/runtime-godot/tools/record_perf_baseline.py <log_file> --build "exported v0.1-rc" --update-baseline
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

# Path to docs/product/PERF_BASELINE.md, resolved relative to this file so
# it works regardless of the caller's current working directory.
#   apps/runtime-godot/tools/record_perf_baseline.py -> repo root is parents[3]
DEFAULT_BASELINE_DOC = (
    Path(__file__).resolve().parents[3] / "docs" / "product" / "PERF_BASELINE.md"
)

# --- idle_profile.gd log line patterns -------------------------------------
# Kept as line-anchored patterns (not a single blob regex) so a change to
# one line's format in idle_profile.gd doesn't silently break parsing of
# the rest, and failures point at exactly which field went missing.

# idle_profile.gd names its log file "idle_profile_<unix>[.fail].log" where
# <unix> comes from `str(Time.get_unix_time_from_system())`, a Godot float —
# so the timestamp may or may not have a fractional part. Accept both.
FILENAME_RE = re.compile(r"idle_profile_(\d+)(?:\.\d+)?(?:\.fail)?\.log$")

SPAWN_RE = re.compile(r"^idle_profile: spawning (\d+) actor; duration=(\d+) s$")
NO_FRAMES_RE = re.compile(r"^idle_profile: no frames recorded$")
SAMPLE_RE = re.compile(r"^sample t=([\d.]+)s mem=(\d+) KB frames=(\d+)$")
REPORT_START_RE = re.compile(r"^=== Idle burn-in report ===$")
REPORT_END_RE = re.compile(r"^=+$")

REPORT_FIELD_RES: dict[str, re.Pattern[str]] = {
    "duration": re.compile(r"^Duration:\s+(\d+) s$"),
    "frames": re.compile(r"^Frames:\s+(\d+)$"),
    "min": re.compile(r"^Min dt:\s+([\d.]+) ms \(([\d.]+) fps\)$"),
    "max": re.compile(r"^Max dt:\s+([\d.]+) ms \(([\d.]+) fps\)$"),
    "avg": re.compile(r"^Avg dt:\s+([\d.]+) ms \(([\d.]+) fps\)$"),
    "mem_min": re.compile(r"^Mem min:\s+(-?\d+) KB$"),
    "mem_max": re.compile(r"^Mem max:\s+(-?\d+) KB$"),
    "mem_drift": re.compile(r"^Mem drift:\s+(-?\d+) KB$"),
}

BASELINE_TABLE_HEADER_PREFIX = "| Date (UTC)"


@dataclass
class IdleProfileReport:
    """Values parsed straight out of an idle_profile.gd report block."""

    duration_s: int
    frames: int
    min_dt_ms: float
    min_fps: float
    max_dt_ms: float
    max_fps: float
    avg_dt_ms: float
    avg_fps: float
    mem_min_kb: int
    mem_max_kb: int
    mem_drift_kb: int
    sample_mem_kb: list[int] = field(default_factory=list)


class LogFormatError(ValueError):
    """The log file doesn't have the shape idle_profile.gd is known to write."""


def parse_log(text: str) -> IdleProfileReport:
    """Parse the text of an idle_profile_<unix>.log file.

    Raises LogFormatError with a human-readable reason if the report
    block is missing or a field inside it doesn't match.
    """
    lines = [line.strip() for line in text.splitlines()]

    sample_mem_kb: list[int] = []
    for line in lines:
        m = SAMPLE_RE.match(line)
        if m:
            sample_mem_kb.append(int(m.group(2)))

    start_idx: int | None = None
    end_idx: int | None = None
    for i, line in enumerate(lines):
        if start_idx is None and REPORT_START_RE.match(line):
            start_idx = i
            continue
        if start_idx is not None and i > start_idx and REPORT_END_RE.match(line):
            end_idx = i
            break

    if start_idx is None:
        if any(NO_FRAMES_RE.match(line) for line in lines):
            raise LogFormatError(
                "log records a failed run ('idle_profile: no frames recorded') — "
                "there is no report block to read. This happens when --duration is "
                "too short to get past the 30-frame warmup; re-run with a longer "
                "--duration."
            )
        raise LogFormatError(
            "no '=== Idle burn-in report ===' block found — this doesn't look "
            "like a completed idle_profile.gd log."
        )
    if end_idx is None:
        raise LogFormatError(
            "found the '=== Idle burn-in report ===' header but not its closing "
            "'===' line — log looks truncated."
        )

    block = lines[start_idx : end_idx + 1]
    matches: dict[str, re.Match[str]] = {}
    for key, pattern in REPORT_FIELD_RES.items():
        found = next((pattern.match(line) for line in block if pattern.match(line)), None)
        if found is None:
            raise LogFormatError(
                f"report block is missing the field matched by {pattern.pattern!r} "
                "(idle_profile.gd's log format may have changed)."
            )
        matches[key] = found

    min_dt_ms, min_fps = (float(g) for g in matches["min"].groups())
    max_dt_ms, max_fps = (float(g) for g in matches["max"].groups())
    avg_dt_ms, avg_fps = (float(g) for g in matches["avg"].groups())

    return IdleProfileReport(
        duration_s=int(matches["duration"].group(1)),
        frames=int(matches["frames"].group(1)),
        min_dt_ms=min_dt_ms,
        min_fps=min_fps,
        max_dt_ms=max_dt_ms,
        max_fps=max_fps,
        avg_dt_ms=avg_dt_ms,
        avg_fps=avg_fps,
        mem_min_kb=int(matches["mem_min"].group(1)),
        mem_max_kb=int(matches["mem_max"].group(1)),
        mem_drift_kb=int(matches["mem_drift"].group(1)),
        sample_mem_kb=sample_mem_kb,
    )


def derive_date(log_path: Path, cli_date: str | None) -> tuple[str, str]:
    """Return (YYYY-MM-DD, human-readable source) for the Date (UTC) column."""
    if cli_date:
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", cli_date):
            raise ValueError(f"--date must be YYYY-MM-DD, got {cli_date!r}")
        return cli_date, "explicit --date"

    m = FILENAME_RE.search(log_path.name)
    if m:
        ts = int(m.group(1))
        date_str = datetime.fromtimestamp(ts, tz=timezone.utc).date().isoformat()
        return date_str, f"derived from unix timestamp {ts} in filename {log_path.name!r}"

    today = datetime.now(timezone.utc).date().isoformat()
    return (
        today,
        "fallback: today's UTC date — filename didn't match "
        "'idle_profile_<unix>[.fail].log' so no run timestamp could be recovered",
    )


def format_row(
    report: IdleProfileReport, *, date_str: str, build: str, notes: str
) -> list[str]:
    """Build the table-row cells, in PERF_BASELINE.md column order."""
    return [
        date_str,
        build,
        f"{report.duration_s} s",
        f"{report.avg_fps:.1f}",
        f"{report.max_dt_ms:.2f}",
        str(report.mem_drift_kb),
        notes,
    ]


def _split_row(line: str) -> list[str]:
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [cell.strip() for cell in s.split("|")]


def _render_table(rows: list[list[str]]) -> list[str]:
    """Render rows (row 0 = header, rest = data) as a padded GFM table."""
    ncols = len(rows[0])
    widths = [3] * ncols
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    lines = ["| " + " | ".join(rows[0][i].ljust(widths[i]) for i in range(ncols)) + " |"]
    lines.append("|" + "|".join("-" * (widths[i] + 2) for i in range(ncols)) + "|")
    for row in rows[1:]:
        lines.append("| " + " | ".join(row[i].ljust(widths[i]) for i in range(ncols)) + " |")
    return lines


def update_baseline_doc(doc_path: Path, new_row: list[str]) -> str:
    """Insert new_row into the PERF_BASELINE.md results table in place.

    If an unfilled `_TBD_` placeholder row with a matching Duration cell
    exists, that row is replaced. Otherwise the row is appended. A row
    that already has a real (non-`_TBD_`) date is never overwritten, so
    re-running this against a doc that already has real results for a
    given duration adds a new row instead of clobbering history.

    Returns a short human-readable description of the action taken.
    """
    if not doc_path.exists():
        raise ValueError(f"baseline doc not found: {doc_path}")

    original_text = doc_path.read_text(encoding="utf-8")
    lines = original_text.splitlines()

    header_idx = next(
        (i for i, line in enumerate(lines) if line.strip().startswith(BASELINE_TABLE_HEADER_PREFIX)),
        None,
    )
    if header_idx is None or header_idx + 1 >= len(lines):
        raise ValueError(
            f"could not find a results table (header row starting with "
            f"{BASELINE_TABLE_HEADER_PREFIX!r}) in {doc_path}"
        )

    data_start = header_idx + 2  # skip header + '---' separator row
    data_end = data_start
    while data_end < len(lines) and lines[data_end].lstrip().startswith("|"):
        data_end += 1

    header_cells = _split_row(lines[header_idx])
    data_rows = [_split_row(line) for line in lines[data_start:data_end]]

    duration_cell = new_row[2]
    replaced = False
    for i, row in enumerate(data_rows):
        if len(row) >= 3 and row[0].strip() == "_TBD_" and row[2].strip() == duration_cell:
            data_rows[i] = new_row
            replaced = True
            break
    if not replaced:
        data_rows.append(new_row)

    table_lines = _render_table([header_cells, *data_rows])
    new_lines = lines[:header_idx] + table_lines + lines[data_end:]
    new_text = "\n".join(new_lines)
    if original_text.endswith("\n"):
        new_text += "\n"
    doc_path.write_text(new_text, encoding="utf-8")

    return "replaced the '_TBD_' placeholder row for" if replaced else "appended a new row for"


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Format an idle_profile burn-in log as a PERF_BASELINE.md table row.",
    )
    parser.add_argument("log_file", type=Path, help="Path to an idle_profile_<unix>.log file.")
    parser.add_argument(
        "--build",
        default=None,
        help="Build column text, e.g. 'exported v0.1-rc' or 'editor-play (dev)'. "
        "Required to be meaningful — omitting it fills in 'TBD'.",
    )
    parser.add_argument(
        "--date",
        default=None,
        help="Override the Date (UTC) column (YYYY-MM-DD). Default: derived from "
        "the unix timestamp in the log filename.",
    )
    parser.add_argument("--notes", default="", help="Notes column text (default: empty).")
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="Also patch --baseline-doc's results table in place, not just print the row.",
    )
    parser.add_argument(
        "--baseline-doc",
        type=Path,
        default=DEFAULT_BASELINE_DOC,
        help=f"Path to PERF_BASELINE.md (default: {DEFAULT_BASELINE_DOC}).",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print parsing diagnostics and a sample-based cross-check to stderr.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)

    if not args.log_file.exists():
        print(f"[ERROR] log file not found: {args.log_file}", file=sys.stderr)
        return 1

    text = args.log_file.read_text(encoding="utf-8", errors="replace")
    try:
        report = parse_log(text)
    except LogFormatError as exc:
        print(f"[ERROR] {args.log_file}: {exc}", file=sys.stderr)
        return 1

    if args.verbose:
        print(
            f"[INFO] parsed report: duration={report.duration_s}s frames={report.frames} "
            f"avg={report.avg_dt_ms:.2f}ms({report.avg_fps:.1f}fps) "
            f"max={report.max_dt_ms:.2f}ms mem_drift={report.mem_drift_kb}KB "
            f"({len(report.sample_mem_kb)} memory samples)",
            file=sys.stderr,
        )
        if report.sample_mem_kb:
            sample_drift = max(report.sample_mem_kb) - min(report.sample_mem_kb)
            if sample_drift != report.mem_drift_kb:
                print(
                    f"[WARN] max-min of the 'sample ... mem=' lines' KB values "
                    f"({sample_drift} KB) differs from the log's own 'Mem drift' line "
                    f"({report.mem_drift_kb} KB). This is expected integer-rounding "
                    "noise (idle_profile.gd computes drift from raw bytes, samples "
                    "are pre-truncated to KB) — using the log's own reported value.",
                    file=sys.stderr,
                )

    try:
        date_str, date_source = derive_date(args.log_file, args.date)
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    if args.verbose:
        print(f"[INFO] Date (UTC) = {date_str} ({date_source})", file=sys.stderr)

    build = args.build
    if not build:
        print(
            "[WARN] no --build given; Build column set to 'TBD'. Pass --build "
            "\"exported v0.1-rc\" (or similar) to record a real result.",
            file=sys.stderr,
        )
        build = "TBD"

    row = format_row(report, date_str=date_str, build=build, notes=args.notes)
    print("| " + " | ".join(row) + " |")

    if args.update_baseline:
        try:
            action = update_baseline_doc(args.baseline_doc, row)
        except ValueError as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 1
        print(
            f"[OK] {action} Duration={report.duration_s} s in {args.baseline_doc}",
            file=sys.stderr,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
