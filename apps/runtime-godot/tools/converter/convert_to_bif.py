#!/usr/bin/env python3
"""Converter stub for buddy intermediate format (BIF).

This intentionally avoids runtime coupling to Maple formats. The converter is
the only place where source-specific transforms should live.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate minimal BIF fixtures.")
    parser.add_argument(
        "--output-dir",
        default="content/intermediate",
        help="Output folder for generated BIF files.",
    )
    parser.add_argument(
        "--source-hash",
        default="unknown",
        help="Hash of the source bundle for provenance metadata.",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)

    actor = {
        "kind": "actor",
        "actor_id": "demo_actor_001",
        "display_name": "Demo Buddy",
        "semantic_defaults": {
            "idle": "idle",
            "walk": "walk",
            "jump": "jump",
            "happy_emote": "happy_emote",
        },
        "metadata": {
            "source_hash": args.source_hash,
            "converter_version": "0.1.0",
            "source_path": "offline_source_bundle",
        },
    }
    anim = {
        "kind": "anim",
        "clip_id": "happy_emote",
        "loop": False,
        "frames": [
            {
                "texture_path": "res://content/core_pack/character/happy.png",
                "delay_ms": 180,
                "anchor_px": [0, 0],
            }
        ],
        "metadata": {
            "source_hash": args.source_hash,
            "converter_version": "0.1.0",
            "source_action": "happy",
        },
    }
    map_payload = {
        "kind": "map",
        "map_id": "test_map_001",
        "spawn_point": {"x": 96, "y": 60},
        "footholds": [{"x0": 16, "y0": 180, "x1": 320, "y1": 180}],
        "ladders": [],
        "portals": [],
        "interaction_markers": {"desk_left": {"x": 220, "y": 145}},
        "metadata": {
            "source_hash": args.source_hash,
            "converter_version": "0.1.0",
            "source_path": "offline_source_bundle",
        },
    }

    _write_json(output_dir / "bif_actor.bif", actor)
    _write_json(output_dir / "bif_anim.bif", anim)
    _write_json(output_dir / "bif_map.bif", map_payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
