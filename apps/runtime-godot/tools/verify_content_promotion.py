#!/usr/bin/env python3
"""Verify that all BIF files in content/intermediate/ have been approved.

Reads content/promotion_log.json and checks that each .bif file's source_hash
matches the approved entry. Exits non-zero if any file is MISSING or STALE.

Usage:
    python apps/runtime-godot/tools/verify_content_promotion.py
    python apps/runtime-godot/tools/verify_content_promotion.py --intermediate-dir content/intermediate
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify BIF content promotion log.")
    parser.add_argument(
        "--intermediate-dir",
        default="content/intermediate",
        help="Directory containing .bif files (default: content/intermediate)",
    )
    parser.add_argument(
        "--promotion-log",
        default="content/promotion_log.json",
        help="Path to promotion_log.json (default: content/promotion_log.json)",
    )
    args = parser.parse_args()

    intermediate_dir = Path(args.intermediate_dir)
    promotion_log_path = Path(args.promotion_log)

    if not intermediate_dir.exists():
        print(f"[SKIP] Intermediate dir not found: {intermediate_dir}")
        return 0

    bif_files = sorted(intermediate_dir.glob("*.bif"))
    if not bif_files:
        print("[OK] No .bif files found — nothing to verify.")
        return 0

    approved: dict[str, str] = {}
    if promotion_log_path.exists():
        try:
            approved = json.loads(promotion_log_path.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"[WARN] Could not read promotion log: {exc}")

    all_ok = True
    for bif_path in bif_files:
        try:
            data = json.loads(bif_path.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"[ERROR] {bif_path.name}: cannot parse — {exc}")
            all_ok = False
            continue

        meta = data.get("metadata", {})
        source_hash = str(meta.get("source_hash", "")) if isinstance(meta, dict) else ""

        filename = bif_path.name
        if filename not in approved:
            print(f"[MISSING] {filename}: not in promotion log — run approve_content_snapshot.py")
            all_ok = False
        elif approved[filename] != source_hash:
            print(
                f"[STALE]   {filename}: "
                f"hash changed ({approved[filename]!r} -> {source_hash!r}) — "
                "re-run approve_content_snapshot.py after review"
            )
            all_ok = False
        else:
            print(f"[OK]      {filename}: approved (hash={source_hash!r})")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
