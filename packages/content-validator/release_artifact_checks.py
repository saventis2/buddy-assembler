#!/usr/bin/env python3
"""Create and verify the exact Gate 0 Windows artifact contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
from pathlib import Path
from typing import Any

PCK_MAGIC = b"GDPC"
PCK_DIRECTORY_ENCRYPTED = 1
CHECKSUM_LINE = re.compile(r"^([0-9a-f]{64})  (.+)$")


class PckFormatError(ValueError):
    """Raised when a PCK directory cannot be safely inspected."""


def _read_exact(handle: Any, length: int) -> bytes:
    data = handle.read(length)
    if len(data) != length:
        raise PckFormatError(
            f"truncated PCK directory: wanted {length} bytes, got {len(data)}"
        )
    return data


def _read_u32(handle: Any) -> int:
    return int(struct.unpack("<I", _read_exact(handle, 4))[0])


def _read_u64(handle: Any) -> int:
    return int(struct.unpack("<Q", _read_exact(handle, 8))[0])


def read_pck_inventory(pck_path: Path) -> set[str]:
    """Read the unencrypted Godot 4 PCK directory without extracting payloads."""
    paths: set[str] = set()
    with pck_path.open("rb") as handle:
        if _read_exact(handle, 4) != PCK_MAGIC:
            raise PckFormatError("missing Godot PCK header magic")
        pack_format = _read_u32(handle)
        engine_version = (_read_u32(handle), _read_u32(handle), _read_u32(handle))
        if pack_format != 2:
            raise PckFormatError(f"unsupported PCK format {pack_format}")
        if engine_version[:2] != (4, 2):
            raise PckFormatError(f"unexpected PCK engine version {engine_version}")
        flags = _read_u32(handle)
        _read_u64(handle)  # file base; offsets are not needed for inventory.
        for _ in range(16):
            _read_u32(handle)
        if flags & PCK_DIRECTORY_ENCRYPTED:
            raise PckFormatError("encrypted PCK directories cannot be audited")
        file_count = _read_u32(handle)
        if file_count > 100_000:
            raise PckFormatError(f"implausible PCK file count {file_count}")
        for _ in range(file_count):
            path_length = _read_u32(handle)
            if path_length == 0 or path_length > 1_048_576:
                raise PckFormatError(f"invalid PCK path length {path_length}")
            raw_path = _read_exact(handle, path_length).rstrip(b"\0")
            try:
                path = raw_path.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise PckFormatError("non-UTF-8 PCK path") from exc
            _read_u64(handle)
            _read_u64(handle)
            _read_exact(handle, 16)
            _read_u32(handle)
            if not path.startswith("res://"):
                raise PckFormatError(f"non-canonical PCK path {path!r}")
            if path in paths:
                raise PckFormatError(f"duplicate PCK path {path!r}")
            paths.add(path)
    return paths


def load_inventory_contract(contract_path: Path) -> dict[str, list[str]]:
    raw: Any = json.loads(contract_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("shipping inventory contract root must be an object")
    result: dict[str, list[str]] = {}
    for key in ("export_resources", "include_files", "pck_files"):
        value = raw.get(key)
        if not isinstance(value, list) or not all(
            isinstance(item, str) for item in value
        ):
            raise ValueError(
                f"shipping inventory contract {key!r} must be a string array"
            )
        if len(value) != len(set(value)):
            raise ValueError(f"shipping inventory contract {key!r} contains duplicates")
        result[key] = list(value)
    return result


def compare_pck_inventory(expected: set[str], actual: set[str]) -> list[str]:
    failures = [
        f"missing approved PCK file: {path}" for path in sorted(expected - actual)
    ]
    failures.extend(
        f"unexpected PCK file: {path}" for path in sorted(actual - expected)
    )
    return failures


def verify_pck(pck_path: Path, contract_path: Path) -> list[str]:
    contract = load_inventory_contract(contract_path)
    expected = set(contract["pck_files"])
    if not expected:
        return ["approved PCK inventory is empty"]
    return compare_pck_inventory(expected, read_pck_inventory(pck_path))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _artifact_files(root: Path, manifest: Path) -> list[Path]:
    manifest_resolved = manifest.resolve()
    return sorted(
        (
            path
            for path in root.rglob("*")
            if path.is_file() and path.resolve() != manifest_resolved
        ),
        key=lambda path: path.relative_to(root).as_posix(),
    )


def write_sha256sums(root: Path, manifest: Path | None = None) -> int:
    root = root.resolve()
    manifest = (manifest or root / "SHA256SUMS").resolve()
    if manifest.parent != root:
        raise ValueError("SHA256SUMS must be written at the artifact root")
    files = _artifact_files(root, manifest)
    if not files:
        raise ValueError("artifact root contains no payload files")
    lines = [f"{_sha256(path)}  {path.relative_to(root).as_posix()}" for path in files]
    with manifest.open("w", encoding="ascii", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    return len(files)


def _read_sha256sums(root: Path, manifest: Path) -> tuple[dict[str, str], list[str]]:
    entries: dict[str, str] = {}
    failures: list[str] = []
    for line_number, line in enumerate(
        manifest.read_text(encoding="ascii").splitlines(), start=1
    ):
        match = CHECKSUM_LINE.fullmatch(line)
        if match is None:
            failures.append(f"invalid SHA256SUMS line {line_number}")
            continue
        digest, relative_text = match.groups()
        relative = Path(relative_text)
        if relative.is_absolute() or ".." in relative.parts or "\\" in relative_text:
            failures.append(f"non-portable SHA256SUMS path: {relative_text}")
            continue
        normalized = relative.as_posix()
        if normalized in entries:
            failures.append(f"duplicate SHA256SUMS path: {normalized}")
            continue
        candidate = (root / relative).resolve()
        if root not in candidate.parents:
            failures.append(f"SHA256SUMS path escapes artifact root: {normalized}")
            continue
        entries[normalized] = digest
    return entries, failures


def verify_sha256sums(root: Path, manifest: Path | None = None) -> list[str]:
    root = root.resolve()
    manifest = (manifest or root / "SHA256SUMS").resolve()
    if not manifest.is_file():
        return ["missing SHA256SUMS"]
    entries, failures = _read_sha256sums(root, manifest)
    for relative, expected in sorted(entries.items()):
        path = root / Path(relative)
        if not path.is_file():
            failures.append(f"missing artifact file: {relative}")
        else:
            actual = _sha256(path)
            if actual != expected:
                failures.append(f"checksum mismatch: {relative}")
    actual_files = {
        path.relative_to(root).as_posix() for path in _artifact_files(root, manifest)
    }
    for relative in sorted(actual_files - set(entries)):
        failures.append(f"unlisted artifact file: {relative}")
    return failures


def _print_result(marker: str, failures: list[str], success: str) -> int:
    if failures:
        print(f"{marker}: FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"{marker}: PASS ({success})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    pck_parser = subparsers.add_parser("verify-pck")
    pck_parser.add_argument("--pck", type=Path, required=True)
    pck_parser.add_argument("--contract", type=Path, required=True)
    print_parser = subparsers.add_parser("print-pck")
    print_parser.add_argument("--pck", type=Path, required=True)
    write_parser = subparsers.add_parser("write-checksums")
    write_parser.add_argument("--root", type=Path, required=True)
    verify_parser = subparsers.add_parser("verify-checksums")
    verify_parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()

    if args.command == "verify-pck":
        failures = verify_pck(args.pck, args.contract)
        count = len(read_pck_inventory(args.pck)) if not failures else 0
        return _print_result("pck_inventory", failures, f"{count} exact files")
    if args.command == "print-pck":
        print(json.dumps(sorted(read_pck_inventory(args.pck)), indent=2))
        return 0
    if args.command == "write-checksums":
        count = write_sha256sums(args.root)
        print(f"checksums_write: PASS ({count} artifact-root-relative files)")
        return 0
    failures = verify_sha256sums(args.root)
    return _print_result(
        "checksums_verify", failures, "manifest and artifact layout agree"
    )


if __name__ == "__main__":
    raise SystemExit(main())
