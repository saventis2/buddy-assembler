#!/usr/bin/env python3
"""Run one controlled WZ ingest batch:
1) add missing items from full bindings into manifest
2) import matching icons for manifest items
3) optionally run headless checks
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYNC = ROOT / "tools" / "sync_manifest_items_from_bindings.py"
IMPORT = ROOT / "tools" / "import_item_icons_from_wz_root.py"
CHECKS = ROOT / "tests" / "run_headless_checks.ps1"
MANIFEST = ROOT / "content" / "core_pack" / "manifest.json"
FULL_BINDINGS = ROOT / "content" / "core_pack" / "item_bindings_full.csv"
DEFAULT_WZ_ROOT = Path("C:/Users/GGPC/OneDrive/Desktop/83 complete/Base.wz")
DEFAULT_REPORT = ROOT.parent.parent / "docs" / "product" / "WZ_INGEST_LAST_RUN.json"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--batch-size", type=int, default=100)
    p.add_argument(
        "--batches",
        type=int,
        default=1,
        help="How many add/import batches to run in sequence.",
    )
    p.add_argument("--wz-root", type=Path, default=DEFAULT_WZ_ROOT)
    p.add_argument(
        "--categories",
        type=str,
        default="",
        help="Optional comma-separated categories to ingest (e.g. gear,food).",
    )
    p.add_argument(
        "--report-out",
        type=Path,
        default=DEFAULT_REPORT,
        help="JSON summary output path.",
    )
    p.add_argument("--skip-checks", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()


def run(cmd: list[str], cwd: Path) -> None:
    print(">", " ".join(cmd))
    proc = subprocess.run(cmd, cwd=str(cwd))
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


def manifest_item_count(manifest_path: Path) -> int:
    if not manifest_path.exists():
        return 0
    with manifest_path.open("r", encoding="utf-8") as f:
        payload = json.load(f)
    items = payload.get("items", [])
    return len(items) if isinstance(items, list) else 0


def main() -> int:
    args = parse_args()
    if args.batch_size <= 0:
        print("error: --batch-size must be > 0")
        return 2
    if args.batches <= 0:
        print("error: --batches must be > 0")
        return 2
    if not FULL_BINDINGS.exists():
        print(f"error: full bindings missing: {FULL_BINDINGS}")
        return 2
    if not args.wz_root.exists():
        print(f"error: wz root missing: {args.wz_root}")
        return 2

    before_count = manifest_item_count(MANIFEST)
    category_str = args.categories.strip()
    summary = {
        "manifest_before": before_count,
        "manifest_after": before_count,
        "batch_size": int(args.batch_size),
        "batches": int(args.batches),
        "dry_run": bool(args.dry_run),
        "skip_checks": bool(args.skip_checks),
        "categories": category_str if category_str else "all",
        "wz_root": str(args.wz_root),
        "report_out": str(args.report_out),
    }

    for idx in range(args.batches):
        print(f"=== ingest batch {idx + 1}/{args.batches} ===")
        sync_cmd = [
            sys.executable,
            str(SYNC),
            "--manifest",
            str(MANIFEST),
            "--bindings",
            str(FULL_BINDINGS),
            "--add-missing",
            "--max-add",
            str(args.batch_size),
        ]
        if category_str:
            sync_cmd += ["--categories", category_str]
        if args.dry_run:
            sync_cmd.append("--dry-run")
        run(sync_cmd, ROOT)

        if not args.dry_run:
            import_cmd = [
                sys.executable,
                str(IMPORT),
                "--manifest",
                str(MANIFEST),
                "--bindings",
                str(FULL_BINDINGS),
                "--wz-root",
                str(args.wz_root),
            ]
            run(import_cmd, ROOT)

    after_count = manifest_item_count(MANIFEST)
    summary["manifest_after"] = after_count
    summary["manifest_delta"] = after_count - before_count

    if not args.skip_checks:
        run(
            [
                "pwsh",
                "-NoLogo",
                "-File",
                str(CHECKS),
            ],
            ROOT,
        )
        summary["headless_checks"] = "ran"
    else:
        summary["headless_checks"] = "skipped"

    report_out = args.report_out
    if not report_out.is_absolute():
        report_out = (ROOT / report_out).resolve()
    report_out.parent.mkdir(parents=True, exist_ok=True)
    with report_out.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"report={report_out}")
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
