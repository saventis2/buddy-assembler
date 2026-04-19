#!/usr/bin/env python3
"""Approve current BIF content as the developer-accepted snapshot.

Reads all .bif files in content/intermediate/, records their source_hash values
into content/promotion_log.json. Run this after manually reviewing generated content.

Usage:
    python apps/runtime-godot/tools/approve_content_snapshot.py
    python apps/runtime-godot/tools/approve_content_snapshot.py --intermediate-dir content/intermediate
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Approve current BIF content snapshot.")
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
        print(f"[ERROR] Intermediate dir not found: {intermediate_dir}")
        return 1

    bif_files = sorted(intermediate_dir.glob("*.bif"))
    if not bif_files:
        print("[SKIP] No .bif files found — nothing to approve.")
        return 0

    existing: dict = {}
    if promotion_log_path.exists():
        try:
            existing = json.loads(promotion_log_path.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"[WARN] Could not read existing promotion log: {exc} — starting fresh.")

    approved_at = datetime.now(timezone.utc).isoformat()
    updated = 0

    for bif_path in bif_files:
        try:
            data = json.loads(bif_path.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"[ERROR] {bif_path.name}: cannot parse — {exc}")
            continue

        meta = data.get("metadata", {})
        source_hash = str(meta.get("source_hash", "")) if isinstance(meta, dict) else ""

        filename = bif_path.name
        prev_hash = existing.get(filename, "")
        if prev_hash == source_hash:
            print(f"[UNCHANGED] {filename} (hash={source_hash!r})")
        else:
            print(f"[APPROVED]  {filename} (hash={source_hash!r})")
            updated += 1

        existing[filename] = source_hash

    existing["_approved_at"] = approved_at

    promotion_log_path.parent.mkdir(parents=True, exist_ok=True)
    promotion_log_path.write_text(
        json.dumps(existing, indent=2), encoding="utf-8"
    )
    print(f"\nPromotion log written: {promotion_log_path} ({updated} entries updated, approved_at={approved_at})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
