#!/usr/bin/env python3
"""Negative and portability tests for the Gate 0 release artifact contract."""

from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

from release_artifact_checks import (
    read_pck_inventory,
    verify_pck,
    verify_sha256sums,
    write_sha256sums,
)


class ReleaseArtifactChecksTest(unittest.TestCase):
    @staticmethod
    def _write_synthetic_pck(path: Path, entries: list[str]) -> None:
        payload = bytearray(b"GDPC")
        payload.extend(struct.pack("<IIII", 2, 4, 2, 2))
        payload.extend(struct.pack("<IQ", 0, 0))
        payload.extend(struct.pack("<" + ("I" * 16), *([0] * 16)))
        payload.extend(struct.pack("<I", len(entries)))
        for entry in entries:
            encoded = entry.encode("utf-8")
            padded = encoded + (b"\0" * ((4 - (len(encoded) % 4)) % 4))
            payload.extend(struct.pack("<I", len(padded)))
            payload.extend(padded)
            payload.extend(struct.pack("<QQ", 0, 0))
            payload.extend(b"\0" * 16)
            payload.extend(struct.pack("<I", 0))
        path.write_bytes(payload)

    def test_checksum_paths_are_artifact_root_relative_and_verify(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "BuddyRuntime.exe").write_bytes(b"exe")
            (root / "BuddyRuntime.pck").write_bytes(b"pck")
            self.assertEqual(write_sha256sums(root), 2)
            manifest = (root / "SHA256SUMS").read_text(encoding="ascii")
            self.assertIn("  BuddyRuntime.exe\n", manifest)
            self.assertIn("  BuddyRuntime.pck\n", manifest)
            self.assertNotIn(str(root), manifest)
            self.assertEqual(verify_sha256sums(root), [])

    def test_missing_artifact_file_fails_verification(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = root / "BuddyRuntime.exe"
            payload.write_bytes(b"exe")
            write_sha256sums(root)
            payload.unlink()
            self.assertIn(
                "missing artifact file: BuddyRuntime.exe", verify_sha256sums(root)
            )

    def test_mismatched_artifact_file_fails_verification(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = root / "BuddyRuntime.exe"
            payload.write_bytes(b"before")
            write_sha256sums(root)
            payload.write_bytes(b"after")
            self.assertIn(
                "checksum mismatch: BuddyRuntime.exe", verify_sha256sums(root)
            )

    def test_unlisted_artifact_file_fails_verification(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "BuddyRuntime.exe").write_bytes(b"exe")
            write_sha256sums(root)
            (root / "surprise.dll").write_bytes(b"unexpected")
            self.assertIn(
                "unlisted artifact file: surprise.dll", verify_sha256sums(root)
            )

    def test_unexpected_exportable_resource_fails_pck_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            pck = root / "BuddyRuntime.pck"
            contract = root / "shipping_inventory.json"
            expected = ["res://project.binary", "res://scripts/launch_router.gd"]
            self._write_synthetic_pck(
                pck, expected + ["res://unexpected_exportable_resource.gd"]
            )
            contract.write_text(
                json.dumps(
                    {
                        "export_resources": [],
                        "include_files": [],
                        "pck_files": expected,
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                verify_pck(pck, contract),
                ["unexpected PCK file: res://unexpected_exportable_resource.gd"],
            )

    def test_reads_padded_godot_4_2_pck_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            pck = Path(temp) / "synthetic.pck"
            self._write_synthetic_pck(pck, ["res://project.binary"])
            self.assertEqual(read_pck_inventory(pck), {"res://project.binary"})


if __name__ == "__main__":
    unittest.main()
