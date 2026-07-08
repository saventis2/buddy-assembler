#!/usr/bin/env python3
"""Unit tests for record_perf_baseline.py.

Run with:
    python3 -m unittest apps/runtime-godot/tools/tests/test_record_perf_baseline.py -v

All logs here are hand-crafted to match the exact format written by
apps/runtime-godot/tests/idle_profile.gd (see that file's `_log`,
`_sample_memory`, and `_report_and_exit` functions) — they are NOT
output from a real burn-in run. That's the point of this file: it is
a synthetic-input format/logic check for the parser, not evidence
about actual runtime performance. A real 10-minute and multi-hour
burn-in against the exported Windows build is a separate, still-open
task (see docs/product/PERF_BASELINE.md).
"""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import record_perf_baseline as rpb  # noqa: E402


# A standard, "everything worked" log — mirrors idle_profile.gd's real
# output shape: header line, periodic sample lines, blank line, report
# block, footer line. Numbers are made up but internally consistent.
GOOD_LOG = """idle_profile: spawning 1 actor; duration=20 s
sample t=5.0s mem=47104 KB frames=300
sample t=10.0s mem=47104 KB frames=600
sample t=15.0s mem=47232 KB frames=900
sample t=20.0s mem=47232 KB frames=1200

=== Idle burn-in report ===
Duration:   20 s
Frames:     1200
Min dt:     15.90 ms (62.9 fps)
Max dt:     18.20 ms (54.9 fps)
Avg dt:     16.67 ms (60.0 fps)
Mem min:    47104 KB
Mem max:    47232 KB
Mem drift:  128 KB
===========================
"""

# What idle_profile.gd writes when the run never gets past warmup
# (_report_and_exit's `_frame_deltas.is_empty()` branch); saved with a
# ".fail" filename suffix by _flush(false).
FAIL_LOG = """idle_profile: spawning 1 actor; duration=2 s
idle_profile: no frames recorded
"""

# idle_profile.gd computes "Mem drift" from raw-byte min/max *before*
# converting to KB, but the per-sample "mem=... KB" lines are already
# floor-divided to KB. floor(a/1024)-floor(b/1024) can differ from
# floor((a-b)/1024) by 1, so a real log can legitimately show a Mem
# drift that doesn't equal max-min of the sample lines. This log
# reproduces that on purpose to exercise the cross-check.
ROUNDING_MISMATCH_LOG = """idle_profile: spawning 1 actor; duration=10 s
sample t=5.0s mem=47104 KB frames=300
sample t=10.0s mem=47105 KB frames=600

=== Idle burn-in report ===
Duration:   10 s
Frames:     600
Min dt:     16.60 ms (60.2 fps)
Max dt:     16.70 ms (59.9 fps)
Avg dt:     16.65 ms (60.1 fps)
Mem min:    47104 KB
Mem max:    47105 KB
Mem drift:  0 KB
===========================
"""

# A run shorter than SAMPLE_INTERVAL_SECONDS (5s) never calls
# _sample_memory(), so _mem_samples stays empty and idle_profile.gd's own
# fallback (`_mem_samples[0] if not empty else 0`) makes Mem min/max/drift
# all 0 — with zero "sample ..." lines in the log at all. The report block
# itself is still written normally since frame_deltas is non-empty.
ZERO_SAMPLES_LOG = """idle_profile: spawning 1 actor; duration=2 s

=== Idle burn-in report ===
Duration:   2 s
Frames:     120
Min dt:     16.60 ms (60.2 fps)
Max dt:     16.70 ms (59.9 fps)
Avg dt:     16.65 ms (60.1 fps)
Mem min:    0 KB
Mem max:    0 KB
Mem drift:  0 KB
===========================
"""

FAKE_BASELINE_DOC = """# Fake baseline doc (test fixture only)

## Baseline (to be filled on release rehearsal)

| Date (UTC) | Build            | Duration | Avg fps | Max dt ms | Mem drift KB | Notes |
|------------|------------------|----------|---------|-----------|--------------|-------|
| _TBD_      | exported v0.1-rc | 600 s    |         |           |              |       |
| _TBD_      | exported v0.1-rc | 10800 s  |         |           |              |       |

## Notes
Trailing section, must survive edits untouched.
"""


class ParseLogTests(unittest.TestCase):
    def test_happy_path_fields(self) -> None:
        report = rpb.parse_log(GOOD_LOG)
        self.assertEqual(report.duration_s, 20)
        self.assertEqual(report.frames, 1200)
        self.assertEqual(report.max_dt_ms, 18.20)
        self.assertEqual(report.max_fps, 54.9)
        self.assertEqual(report.avg_dt_ms, 16.67)
        self.assertEqual(report.avg_fps, 60.0)
        self.assertEqual(report.mem_min_kb, 47104)
        self.assertEqual(report.mem_max_kb, 47232)
        self.assertEqual(report.mem_drift_kb, 128)
        self.assertEqual(report.sample_mem_kb, [47104, 47104, 47232, 47232])

    def test_fail_log_raises_with_clear_reason(self) -> None:
        with self.assertRaises(rpb.LogFormatError) as ctx:
            rpb.parse_log(FAIL_LOG)
        self.assertIn("no frames recorded", str(ctx.exception))

    def test_garbage_text_raises(self) -> None:
        with self.assertRaises(rpb.LogFormatError) as ctx:
            rpb.parse_log("this is not an idle_profile log\njust noise\n")
        self.assertIn("report", str(ctx.exception))

    def test_truncated_report_raises(self) -> None:
        truncated = GOOD_LOG.split("Mem drift:")[0]  # cut before the closing '===' line
        with self.assertRaises(rpb.LogFormatError):
            rpb.parse_log(truncated)

    def test_rounding_mismatch_log_still_parses_authoritative_drift(self) -> None:
        report = rpb.parse_log(ROUNDING_MISMATCH_LOG)
        # The log's own "Mem drift" line (0) is authoritative even though
        # max-min of the sample lines (47105-47104=1) disagrees.
        self.assertEqual(report.mem_drift_kb, 0)
        sample_derived = max(report.sample_mem_kb) - min(report.sample_mem_kb)
        self.assertEqual(sample_derived, 1)
        self.assertNotEqual(sample_derived, report.mem_drift_kb)

    def test_zero_samples_still_parses_report(self) -> None:
        # A run shorter than the 5s sample interval has no "sample ..."
        # lines at all; the report block must still parse cleanly.
        report = rpb.parse_log(ZERO_SAMPLES_LOG)
        self.assertEqual(report.sample_mem_kb, [])
        self.assertEqual(report.mem_drift_kb, 0)
        self.assertEqual(report.duration_s, 2)


class DeriveDateTests(unittest.TestCase):
    def test_from_integer_timestamp_filename(self) -> None:
        date_str, source = rpb.derive_date(Path("idle_profile_1745020800.log"), None)
        expected = datetime.fromtimestamp(1745020800, tz=timezone.utc).date().isoformat()
        self.assertEqual(date_str, expected)
        self.assertIn("1745020800", source)

    def test_from_fractional_timestamp_filename(self) -> None:
        # Time.get_unix_time_from_system() is a float in Godot, so str()
        # of it may carry a fractional part in the real filename.
        date_str, _source = rpb.derive_date(Path("idle_profile_1745020800.523.log"), None)
        expected = datetime.fromtimestamp(1745020800, tz=timezone.utc).date().isoformat()
        self.assertEqual(date_str, expected)

    def test_fail_suffix_filename_still_parses_timestamp(self) -> None:
        date_str, _source = rpb.derive_date(Path("idle_profile_1745020800.fail.log"), None)
        expected = datetime.fromtimestamp(1745020800, tz=timezone.utc).date().isoformat()
        self.assertEqual(date_str, expected)

    def test_non_matching_filename_falls_back_to_today(self) -> None:
        date_str, source = rpb.derive_date(Path("renamed_log.txt"), None)
        self.assertEqual(date_str, datetime.now(timezone.utc).date().isoformat())
        self.assertIn("fallback", source)

    def test_explicit_date_overrides(self) -> None:
        date_str, source = rpb.derive_date(Path("idle_profile_1745020800.log"), "2026-07-07")
        self.assertEqual(date_str, "2026-07-07")
        self.assertIn("--date", source)

    def test_explicit_date_bad_format_rejected(self) -> None:
        with self.assertRaises(ValueError):
            rpb.derive_date(Path("idle_profile_1745020800.log"), "07/07/2026")


class FormatRowTests(unittest.TestCase):
    def test_row_cells_match_perf_baseline_columns(self) -> None:
        report = rpb.parse_log(GOOD_LOG)
        row = rpb.format_row(report, date_str="2026-07-07", build="exported v0.1-rc", notes="n/a")
        self.assertEqual(
            row,
            ["2026-07-07", "exported v0.1-rc", "20 s", "60.0", "18.20", "128", "n/a"],
        )


class UpdateBaselineDocTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.doc_path = Path(self.tmpdir.name) / "fake_baseline.md"
        self.doc_path.write_text(FAKE_BASELINE_DOC, encoding="utf-8")

    def test_replaces_matching_tbd_placeholder(self) -> None:
        row = ["2026-07-07", "exported v0.1-rc", "600 s", "60.0", "18.20", "128", "note"]
        action = rpb.update_baseline_doc(self.doc_path, row)
        self.assertIn("replaced", action)

        text = self.doc_path.read_text(encoding="utf-8")
        self.assertIn("2026-07-07", text)
        self.assertIn("128", text)
        # The 10800s placeholder must be untouched.
        self.assertIn("_TBD_", text)
        self.assertIn("10800 s", text)
        # Trailing content outside the table must survive.
        self.assertIn("Trailing section, must survive edits untouched.", text)

    def test_informational_build_does_not_clobber_release_placeholder(self) -> None:
        # Bug regression: an editor-play/informational run whose Duration
        # happens to match a release-rehearsal `_TBD_` placeholder (600 s,
        # reserved for "exported v0.1-rc") must NOT claim that placeholder's
        # slot. It should be appended as its own separate row instead, and
        # the release-rehearsal placeholder must survive untouched so a
        # real release-rehearsal run can still fill it in later.
        row = ["2026-07-08", "editor-play (dev)", "600 s", "60.0", "18.20", "128", "smoke"]
        action = rpb.update_baseline_doc(self.doc_path, row)
        self.assertIn("appended", action)

        text = self.doc_path.read_text(encoding="utf-8")
        rows = [_row for _row in (rpb._split_row(line) for line in text.splitlines()) if _row and _row[0]]
        # The release-rehearsal placeholder for 600 s must still be intact
        # (column widths may be re-padded when a wider Build value is
        # added, so compare parsed cells rather than a literal substring).
        self.assertIn(["_TBD_", "exported v0.1-rc", "600 s", "", "", "", ""], rows)
        # The other placeholder is untouched too.
        self.assertIn(["_TBD_", "exported v0.1-rc", "10800 s", "", "", "", ""], rows)
        # The informational run was recorded as its own new row.
        self.assertIn(
            ["2026-07-08", "editor-play (dev)", "600 s", "60.0", "18.20", "128", "smoke"],
            rows,
        )
        self.assertEqual(text.count("_TBD_"), 2)

    def test_appends_when_no_duration_matches(self) -> None:
        row = ["2026-07-07", "editor-play (dev)", "60 s", "60.0", "17.00", "0", "smoke"]
        rpb.update_baseline_doc(self.doc_path, row)
        text = self.doc_path.read_text(encoding="utf-8")
        self.assertIn("60 s", text)
        # Both original placeholders remain since neither matched duration=60s.
        self.assertEqual(text.count("_TBD_"), 2)

    def test_never_clobbers_an_already_recorded_row(self) -> None:
        first_row = ["2026-07-07", "exported v0.1-rc", "600 s", "60.0", "18.20", "128", ""]
        rpb.update_baseline_doc(self.doc_path, first_row)

        second_row = ["2026-07-08", "exported v0.1-rc2", "600 s", "61.0", "19.00", "200", ""]
        action = rpb.update_baseline_doc(self.doc_path, second_row)
        self.assertIn("appended", action)

        text = self.doc_path.read_text(encoding="utf-8")
        self.assertIn("2026-07-07", text)  # first real row preserved
        self.assertIn("2026-07-08", text)  # second real row added
        self.assertEqual(text.count("600 s"), 2)

    def test_missing_table_raises(self) -> None:
        no_table_doc = Path(self.tmpdir.name) / "no_table.md"
        no_table_doc.write_text("# Just a heading, no table here.\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            rpb.update_baseline_doc(no_table_doc, ["a", "b", "c"])


class MainCliTests(unittest.TestCase):
    def _run_main(self, argv: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = rpb.main(argv)
        return code, out.getvalue(), err.getvalue()

    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)

    def _write(self, name: str, content: str) -> Path:
        p = Path(self.tmpdir.name) / name
        p.write_text(content, encoding="utf-8")
        return p

    def test_success_exit_code_and_row(self) -> None:
        log_path = self._write("idle_profile_1745020800.log", GOOD_LOG)
        code, out, _err = self._run_main([str(log_path), "--build", "exported v0.1-rc"])
        self.assertEqual(code, 0)
        self.assertEqual(
            out.strip(),
            "| 2025-04-19 | exported v0.1-rc | 20 s | 60.0 | 18.20 | 128 |  |",
        )

    def test_missing_build_warns_and_uses_tbd(self) -> None:
        log_path = self._write("idle_profile_1745020800.log", GOOD_LOG)
        code, out, err = self._run_main([str(log_path)])
        self.assertEqual(code, 0)
        self.assertIn("| TBD |", out)
        self.assertIn("[WARN]", err)

    def test_fail_log_exit_code_1(self) -> None:
        log_path = self._write("idle_profile_1745020900.fail.log", FAIL_LOG)
        code, _out, err = self._run_main([str(log_path)])
        self.assertEqual(code, 1)
        self.assertIn("[ERROR]", err)

    def test_missing_file_exit_code_1(self) -> None:
        code, _out, err = self._run_main([str(Path(self.tmpdir.name) / "nope.log")])
        self.assertEqual(code, 1)
        self.assertIn("not found", err)

    def test_rounding_mismatch_warns_but_uses_authoritative_value(self) -> None:
        log_path = self._write("idle_profile_1745020950.log", ROUNDING_MISMATCH_LOG)
        code, out, err = self._run_main([str(log_path), "--build", "x", "--verbose"])
        self.assertEqual(code, 0)
        self.assertIn("[WARN]", err)
        self.assertIn("| 0 |", out)  # authoritative "Mem drift: 0 KB", not the sample-derived 1

    def test_zero_samples_log_no_spurious_warning(self) -> None:
        log_path = self._write("idle_profile_1745020800.log", ZERO_SAMPLES_LOG)
        code, out, err = self._run_main([str(log_path), "--build", "x", "--verbose"])
        self.assertEqual(code, 0)
        self.assertNotIn("[WARN]", err)
        self.assertIn("| 0 |", out)

    def test_update_baseline_end_to_end(self) -> None:
        doc_path = self._write("fake_baseline.md", FAKE_BASELINE_DOC)
        log_path = self._write("idle_profile_1745021000.log", GOOD_LOG.replace("duration=20 s", "duration=600 s")
                                .replace("Duration:   20 s", "Duration:   600 s"))
        code, _out, err = self._run_main(
            [
                str(log_path),
                "--build",
                "exported v0.1-rc",
                "--update-baseline",
                "--baseline-doc",
                str(doc_path),
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("[OK]", err)
        text = doc_path.read_text(encoding="utf-8")
        self.assertNotIn("| _TBD_      | exported v0.1-rc | 600 s", text)
        self.assertIn("600 s", text)
        self.assertIn("10800 s", text)  # untouched placeholder still present


if __name__ == "__main__":
    unittest.main()
