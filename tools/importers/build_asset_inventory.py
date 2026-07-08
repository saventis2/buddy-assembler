#!/usr/bin/env python3
"""Unified asset inventory across both local MapleStory v83 asset trees.

The maintainer keeps two local trees on their Windows machine (neither is
present in this repo or in any sandbox that runs this script):

  - "83 complete" — the already-unpacked tree. Existing scripts
    (`build_item_catalogue.py`, `build_itemwz_catalogue.py`,
    `build_wz_index.py`, `analyze_character_assets.py`) already treat this
    as a folder hierarchy of `<Category>\\<Category>.wz\\<Img>.img.xml`
    (stdlib `xml.etree.ElementTree`, zero WZ-binary-parsing dependency)
    with sibling numbered-PNG folders for canvas frames. Those scripts
    take a `--base-wz` path that points at a `Base.wz` folder *inside*
    "83 complete" (confirmed by the `source_base_wz` / `base_wz` fields
    recorded in this repo's committed `analysis/**/*.json` outputs).

  - "83" — per the maintainer directly: "the compressed files, just in
    case we need to check if anything was lost during extraction." Its
    on-disk format is UNCONFIRMED. It could be raw `.wz` binary client
    files, `.zip`/other archives, or plain directories, and different
    top-level entries could even use different formats. We do NOT assume
    a format: each top-level entry is classified independently at
    runtime (see `classify_entry`) and handled defensively. Anything we
    can't open with stdlib is recorded as an opaque blob (name/size/
    mtime/sha256 only) rather than failing the run.

This tool is an ORCHESTRATOR, not a reimplementation:

  1. It walks both trees into a flat, per-file manifest (the genuinely
     new piece — nothing existing does this).
  2. It cross-checks "83" against "83 complete" per top-level category so
     "did extraction lose anything" is answerable at a glance, instead of
     requiring a manual diff of two file trees.
  3. It invokes the three existing category scripts against "83 complete"
     and merges their already-proven output into one unified logical-
     asset table, plus a deliberately SHALLOW first-pass scan (top-level
     imgdir name + immediate child count + whether a name/string field is
     nearby -- same spirit as `audit_dataset_metadata.py`) for the eight
     categories nothing above covers yet: Map, Mob, Npc, Quest, Skill,
     Sound, String, UI. That shallow layer is explicitly NOT equivalent
     depth to the Item/Effect/Character coverage -- deepening it is
     follow-up work, out of scope here.
  4. Everything is stored in a stdlib `sqlite3` database (so entries are
     actually findable via `WHERE name LIKE ...`), plus CSV + a generated
     `INDEX.md` under `analysis/asset_inventory/`, matching the existing
     `analysis/catalogue_itemwz/` and `analysis/wz_index/` convention.

Storage layout produced under --output-dir (default `analysis/asset_inventory/`):
  - asset_inventory.db           sqlite3 db: file_manifest, completeness_check, logical_asset
  - file_manifest.csv            flat per-file manifest (both trees)
  - completeness_cross_check.csv per-category 83-vs-83-complete comparison
  - logical_asset_index.csv      unified logical-asset master index
  - INDEX.md                     human-readable summary

CLI query mode:
  build_asset_inventory.py --skip-build --search "sunny day"
    -> LIKE search across name/path/category in the existing db, no rebuild.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sqlite3
import sys
import zipfile
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional

import xml.etree.ElementTree as ET

# --------------------------------------------------------------------------
# Defaults / fallbacks
#
# Consistent with sibling scripts (build_item_catalogue.py etc.) which
# hardcode the maintainer's Desktop paths as a *default*. Unlike those
# scripts, --source-83 / --source-complete let the caller override at
# runtime -- these hardcoded values are only a documented fallback so this
# tool still "just works" for the maintainer without extra flags.
# --------------------------------------------------------------------------
DEFAULT_SOURCE_COMPLETE = r"C:\Users\GGPC\OneDrive\Desktop\83 complete"
DEFAULT_SOURCE_83 = r"C:\Users\GGPC\OneDrive\Desktop\83"

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "analysis" / "asset_inventory"

# Categories called out explicitly in the task / mirrored from
# audit_dataset_metadata.py's CORE_TREES. Used to drive the shallow scan
# and to give the completeness cross-check a stable category vocabulary.
KNOWN_CATEGORIES = [
    "Character", "Item", "String", "Skill", "Effect",
    "Map", "Mob", "Npc", "Quest", "Sound", "UI",
]

# Categories with a dedicated, already-proven deep parser above. Anything
# else in KNOWN_CATEGORIES (or found on disk) falls back to the shallow scan.
DEEP_COVERAGE_CATEGORIES = {"Character", "Item", "Effect"}

# --------------------------------------------------------------------------
# Hashing strategy
#
# Full-hashing every file in a real v83 tree (hundreds of thousands of
# files -- mostly tiny per-frame PNGs, but also a handful of large audio /
# minimap composites) is impractical to do unconditionally. Strategy:
#   - size <= FULL_HASH_MAX_BYTES (default 8 MiB): sha256 over the full
#     file content ("full"). Covers the overwhelming majority of assets
#     (XML, per-frame PNGs, small icons) with an exact, dedup-capable hash.
#   - size >  FULL_HASH_MAX_BYTES: sha256 over (first 64 KiB + last 64 KiB
#     + encoded size) only ("sampled"). Cheap, still catches truncation /
#     gross corruption, without paying full I/O on rare large files.
#   - --no-hash: skip hashing entirely ("skipped"), for a fast first pass
#     over an unfamiliar tree.
# This is a documented, tunable heuristic (--full-hash-max-bytes), not a
# claim of cryptographic completeness for large files.
# --------------------------------------------------------------------------
DEFAULT_FULL_HASH_MAX_BYTES = 8 * 1024 * 1024  # 8 MiB
SAMPLE_CHUNK_BYTES = 64 * 1024  # 64 KiB head/tail sample for large files
READ_CHUNK_BYTES = 1024 * 1024

NUMBERED_PNG_RE = re.compile(r"^\d+\.png$", re.IGNORECASE)


# ==========================================================================
# Section 1: flat file-manifest walker
# ==========================================================================

@dataclass
class FileRecord:
    source_tree: str          # '83' | '83_complete'
    top_level_category: str   # e.g. 'Character', 'Item', ...
    relpath: str               # forward-slash relative path from the category root
    filename: str
    extension: str
    size_bytes: int
    mtime_utc: str
    sha256: Optional[str]
    hash_type: str             # 'full' | 'sampled' | 'skipped' | 'error'
    entry_format: str          # 'file' | 'zip_member' | 'opaque_blob'
    archive_name: Optional[str] = None


def classify_entry(path: Path) -> str:
    """Classify a top-level entry under the '83' tree defensively.

    Returns 'directory', 'zip', or 'opaque'. We never guess based on
    extension alone -- zipfile.is_zipfile() actually reads the header.
    """
    if path.is_dir():
        return "directory"
    if path.is_file():
        try:
            if zipfile.is_zipfile(path):
                return "zip"
        except OSError:
            pass
        return "opaque"
    return "opaque"


def compute_hash(path: Path, size: int, full_hash_max_bytes: int, no_hash: bool) -> tuple[Optional[str], str]:
    if no_hash:
        return None, "skipped"
    try:
        h = hashlib.sha256()
        if size <= full_hash_max_bytes:
            with path.open("rb") as f:
                for chunk in iter(lambda: f.read(READ_CHUNK_BYTES), b""):
                    h.update(chunk)
            return h.hexdigest(), "full"
        with path.open("rb") as f:
            h.update(f.read(SAMPLE_CHUNK_BYTES))
            try:
                f.seek(max(size - SAMPLE_CHUNK_BYTES, 0))
            except OSError:
                pass
            h.update(f.read(SAMPLE_CHUNK_BYTES))
        h.update(str(size).encode("utf-8"))
        return h.hexdigest(), "sampled"
    except OSError:
        return None, "error"


def _mtime_iso(stat_result) -> str:
    try:
        return datetime.fromtimestamp(stat_result.st_mtime, tz=timezone.utc).isoformat()
    except (OSError, OverflowError, ValueError):
        return ""


def walk_plain_directory(
    root: Path,
    source_tree: str,
    top_level_category: str,
    category_root: Path,
    full_hash_max_bytes: int,
    no_hash: bool,
) -> Iterator[FileRecord]:
    """Recurse a plain directory, yielding one FileRecord per file.

    `category_root` is the path relpaths are computed relative to (so two
    trees rooted differently on disk still produce comparable relpaths).
    """
    for entry in sorted(root.rglob("*")):
        if not entry.is_file():
            continue
        try:
            st = entry.stat()
        except OSError:
            continue
        sha256, hash_type = compute_hash(entry, st.st_size, full_hash_max_bytes, no_hash)
        relpath = str(entry.relative_to(category_root)).replace("\\", "/")
        yield FileRecord(
            source_tree=source_tree,
            top_level_category=top_level_category,
            relpath=relpath,
            filename=entry.name,
            extension=entry.suffix.lower(),
            size_bytes=st.st_size,
            mtime_utc=_mtime_iso(st),
            sha256=sha256,
            hash_type=hash_type,
            entry_format="file",
        )


def walk_zip_entry(
    zip_path: Path,
    source_tree: str,
    top_level_category: str,
    category_root: Path,
) -> Iterator[FileRecord]:
    """List members of a zip archive without extracting.

    Zip CRC32 is available for free from the archive index but is not the
    same algorithm as the rest of the manifest (sha256), so we record it
    isn't computed here (sha256=None, hash_type='skipped') rather than
    mixing hash algorithms in one column.
    """
    archive_relpath = str(zip_path.relative_to(category_root)).replace("\\", "/")
    try:
        with zipfile.ZipFile(zip_path) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                name = info.filename.replace("\\", "/")
                try:
                    mtime = datetime(*info.date_time, tzinfo=timezone.utc).isoformat()
                except ValueError:
                    mtime = ""
                yield FileRecord(
                    source_tree=source_tree,
                    top_level_category=top_level_category,
                    relpath=f"{archive_relpath}!/{name}",
                    filename=name.rsplit("/", 1)[-1],
                    extension=Path(name).suffix.lower(),
                    size_bytes=info.file_size,
                    mtime_utc=mtime,
                    sha256=None,
                    hash_type="skipped",
                    entry_format="zip_member",
                    archive_name=archive_relpath,
                )
    except (zipfile.BadZipFile, OSError):
        # Passed is_zipfile() but couldn't actually be listed -- fall back
        # to recording it as an opaque blob so the run still completes.
        yield from walk_opaque_entry(zip_path, source_tree, top_level_category, category_root, DEFAULT_FULL_HASH_MAX_BYTES, False)


def walk_opaque_entry(
    path: Path,
    source_tree: str,
    top_level_category: str,
    category_root: Path,
    full_hash_max_bytes: int,
    no_hash: bool,
) -> Iterator[FileRecord]:
    """Record an unreadable entry (raw .wz binary, unsupported archive, ...)
    as a single opaque blob: name/size/mtime/sha256 only, no attempt to
    look inside it.
    """
    try:
        st = path.stat()
    except OSError:
        return
    sha256, hash_type = compute_hash(path, st.st_size, full_hash_max_bytes, no_hash)
    relpath = str(path.relative_to(category_root)).replace("\\", "/")
    yield FileRecord(
        source_tree=source_tree,
        top_level_category=top_level_category,
        relpath=relpath,
        filename=path.name,
        extension=path.suffix.lower(),
        size_bytes=st.st_size,
        mtime_utc=_mtime_iso(st),
        sha256=sha256,
        hash_type=hash_type,
        entry_format="opaque_blob",
    )


def _category_root(source_root: Path) -> Path:
    """Sibling scripts point --base-wz at a `Base.wz` folder *inside* the
    tree root (confirmed via committed analysis/*.json `base_wz` fields).
    If a `Base.wz` *directory* exists, treat its children as the
    categories; otherwise fall back to the tree root's own immediate
    children. This keeps both trees on the same category vocabulary when
    they share the Base.wz wrapper, while staying defensive if "83" does
    not -- including the case where "83" has a raw `Base.wz` *file*
    (an unextracted WZ binary blob) rather than a directory, which must
    fall through to source_root and be picked up by the classify_entry()
    dispatch (as an opaque blob) instead of being handed to iterdir(),
    which would raise NotADirectoryError.
    """
    candidate = source_root / "Base.wz"
    if candidate.is_dir():
        return candidate
    return source_root


def walk_complete_tree(source_complete: Path, full_hash_max_bytes: int, no_hash: bool) -> Iterator[FileRecord]:
    """'83 complete' is documented/known to be a plain unpacked directory
    tree -- no format detection needed, just recurse.
    """
    root = _category_root(source_complete)
    if not root.exists():
        return
    for top_entry in sorted(root.iterdir()):
        if not top_entry.is_dir():
            # Stray file directly under Base.wz (unexpected but not fatal).
            yield from walk_opaque_entry(top_entry, "83_complete", top_entry.stem, root, full_hash_max_bytes, no_hash)
            continue
        yield from walk_plain_directory(top_entry, "83_complete", top_entry.name, root, full_hash_max_bytes, no_hash)


def walk_83_tree(source_83: Path, full_hash_max_bytes: int, no_hash: bool) -> Iterator[FileRecord]:
    """'83' ("the compressed files") has an UNCONFIRMED format. Each
    top-level entry is classified independently and handled defensively:
      - plain directory  -> recurse
      - zip archive       -> list members, don't extract
      - anything else     -> opaque blob (name/size/mtime/sha256 only)
    """
    root = _category_root(source_83)
    if not root.exists():
        return
    for top_entry in sorted(root.iterdir()):
        category = top_entry.name.split(".")[0]
        kind = classify_entry(top_entry)
        if kind == "directory":
            yield from walk_plain_directory(top_entry, "83", category, root, full_hash_max_bytes, no_hash)
        elif kind == "zip":
            yield from walk_zip_entry(top_entry, "83", category, root)
        else:
            yield from walk_opaque_entry(top_entry, "83", category, root, full_hash_max_bytes, no_hash)


# ==========================================================================
# Section 2: sqlite storage
# ==========================================================================

def open_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        DROP TABLE IF EXISTS file_manifest;
        CREATE TABLE file_manifest (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_tree TEXT NOT NULL,
            top_level_category TEXT NOT NULL,
            relpath TEXT NOT NULL,
            filename TEXT NOT NULL,
            extension TEXT,
            size_bytes INTEGER,
            mtime_utc TEXT,
            sha256 TEXT,
            hash_type TEXT,
            entry_format TEXT,
            archive_name TEXT
        );
        CREATE INDEX idx_manifest_filename ON file_manifest(filename);
        CREATE INDEX idx_manifest_category ON file_manifest(top_level_category);
        CREATE INDEX idx_manifest_relpath ON file_manifest(relpath);
        CREATE INDEX idx_manifest_source ON file_manifest(source_tree);

        DROP TABLE IF EXISTS completeness_check;
        CREATE TABLE completeness_check (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            present_in_83 INTEGER,
            present_in_complete INTEGER,
            file_count_83 INTEGER,
            file_count_complete INTEGER,
            total_size_83 INTEGER,
            total_size_complete INTEGER,
            count_delta INTEGER,
            size_delta INTEGER,
            entry_format_83 TEXT,
            flag TEXT
        );
        CREATE INDEX idx_completeness_category ON completeness_check(category);

        DROP TABLE IF EXISTS logical_asset;
        CREATE TABLE logical_asset (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id TEXT,
            name TEXT,
            category TEXT,
            subcategory TEXT,
            source_script TEXT NOT NULL,
            frame_count INTEGER,
            first_frame_path TEXT,
            xml_relpath TEXT,
            extra_json TEXT
        );
        CREATE INDEX idx_logical_name ON logical_asset(name);
        CREATE INDEX idx_logical_category ON logical_asset(category);
        CREATE INDEX idx_logical_asset_id ON logical_asset(asset_id);
        CREATE INDEX idx_logical_source_script ON logical_asset(source_script);
        """
    )
    conn.commit()


def insert_manifest_rows(conn: sqlite3.Connection, records: Iterable[FileRecord]) -> int:
    rows = [
        (
            r.source_tree, r.top_level_category, r.relpath, r.filename, r.extension,
            r.size_bytes, r.mtime_utc, r.sha256, r.hash_type, r.entry_format, r.archive_name,
        )
        for r in records
    ]
    conn.executemany(
        """INSERT INTO file_manifest
           (source_tree, top_level_category, relpath, filename, extension,
            size_bytes, mtime_utc, sha256, hash_type, entry_format, archive_name)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        rows,
    )
    conn.commit()
    return len(rows)


def insert_logical_asset_rows(conn: sqlite3.Connection, rows: list[dict[str, Any]]) -> int:
    payload = [
        (
            r.get("asset_id"), r.get("name"), r.get("category"), r.get("subcategory"),
            r["source_script"], r.get("frame_count"), r.get("first_frame_path"),
            r.get("xml_relpath"), json.dumps(r.get("extra", {}), ensure_ascii=False),
        )
        for r in rows
    ]
    conn.executemany(
        """INSERT INTO logical_asset
           (asset_id, name, category, subcategory, source_script, frame_count,
            first_frame_path, xml_relpath, extra_json)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        payload,
    )
    conn.commit()
    return len(payload)


def insert_completeness_rows(conn: sqlite3.Connection, rows: list[dict[str, Any]]) -> int:
    payload = [
        (
            r["category"], int(r["present_in_83"]), int(r["present_in_complete"]),
            r["file_count_83"], r["file_count_complete"], r["total_size_83"], r["total_size_complete"],
            r["count_delta"], r["size_delta"], r["entry_format_83"], r["flag"],
        )
        for r in rows
    ]
    conn.executemany(
        """INSERT INTO completeness_check
           (category, present_in_83, present_in_complete, file_count_83, file_count_complete,
            total_size_83, total_size_complete, count_delta, size_delta, entry_format_83, flag)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        payload,
    )
    conn.commit()
    return len(payload)


# ==========================================================================
# Section 2b: 83-vs-83-complete completeness cross-check
# ==========================================================================

def build_completeness_check(manifest_records: list[FileRecord]) -> list[dict[str, Any]]:
    by_key: dict[tuple[str, str], list[FileRecord]] = {}
    for r in manifest_records:
        by_key.setdefault((r.source_tree, r.top_level_category), []).append(r)

    categories = sorted({cat for (_, cat) in by_key.keys()})
    rows = []
    for category in categories:
        recs_83 = by_key.get(("83", category), [])
        recs_complete = by_key.get(("83_complete", category), [])
        present_83 = len(recs_83) > 0
        present_complete = len(recs_complete) > 0
        count_83 = len(recs_83)
        count_complete = len(recs_complete)
        size_83 = sum(r.size_bytes for r in recs_83)
        size_complete = sum(r.size_bytes for r in recs_complete)
        formats_83 = {r.entry_format for r in recs_83}
        entry_format_83 = "/".join(sorted(formats_83)) if formats_83 else ""

        if not present_83:
            flag = "missing_in_83"
        elif not present_complete:
            flag = "missing_in_complete"
        elif formats_83 == {"opaque_blob"}:
            # A single opaque blob vs many extracted files is expected --
            # we can't see inside the blob, so a raw count/size comparison
            # isn't meaningful. Flag distinctly instead of a false alarm.
            flag = "opaque_not_comparable"
        else:
            count_delta = count_complete - count_83
            ratio = (count_delta / count_complete) if count_complete else 0.0
            if abs(ratio) > 0.10:
                flag = "count_mismatch"
            else:
                size_delta = size_complete - size_83
                size_ratio = (size_delta / size_complete) if size_complete else 0.0
                flag = "size_mismatch" if abs(size_ratio) > 0.10 else "ok"

        rows.append({
            "category": category,
            "present_in_83": present_83,
            "present_in_complete": present_complete,
            "file_count_83": count_83,
            "file_count_complete": count_complete,
            "total_size_83": size_83,
            "total_size_complete": size_complete,
            "count_delta": count_complete - count_83,
            "size_delta": size_complete - size_83,
            "entry_format_83": entry_format_83,
            "flag": flag,
        })
    return rows


# ==========================================================================
# Section 3: unified logical-asset master index
# ==========================================================================

def _load_sibling_module(module_name: str):
    """Import a sibling importer script as a module. All four category
    scripts live next to this file (under `tools/importers/`); importing
    (rather than shelling out) lets us reuse their return values /
    functions directly instead of reimplementing WZ-XML parsing.
    """
    import importlib

    sibling_dir = str(Path(__file__).resolve().parent)
    if sibling_dir not in sys.path:
        sys.path.insert(0, sibling_dir)
    return importlib.import_module(module_name)


def _read_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _numbered_frame_probe(base_wz: Path, dir_relpath: str) -> tuple[Optional[str], Optional[int]]:
    """Cheap O(1)-per-asset probe: does `dir_relpath` (directly under
    base_wz) contain numbered PNG frames? Character part sprites are
    nested one level deeper per-action, so this frequently finds nothing
    for Character rows -- that's expected and left as None ("if-any"),
    not an error. We deliberately do NOT recurse to find nested frames;
    that would mean re-deriving analyze_character_assets.py's action/z
    logic, which is out of scope for this orchestrator.
    """
    if not dir_relpath:
        return None, None
    dir_path = base_wz / dir_relpath
    if not dir_path.is_dir():
        return None, None
    try:
        numbered = sorted(
            (p.name for p in dir_path.iterdir() if p.is_file() and NUMBERED_PNG_RE.match(p.name)),
            key=lambda n: int(n.split(".")[0]),
        )
    except OSError:
        return None, None
    if not numbered:
        return None, None
    return f"{dir_relpath}/{numbered[0]}", len(numbered)


def collect_character_catalogue(base_wz: Path, component_dir: Path) -> list[dict[str, Any]]:
    """Invoke build_item_catalogue.py's build_catalogue() against the
    given base_wz, then read back its own catalogue_all.csv -- i.e. reuse
    its already-proven output rather than re-parsing the XML ourselves.
    """
    mod = _load_sibling_module("build_item_catalogue")
    try:
        mod.build_catalogue(base_wz, component_dir)
    except FileNotFoundError:
        return []
    rows = _read_csv_rows(component_dir / "catalogue_all.csv")
    out = []
    for row in rows:
        first_frame, frame_count = _numbered_frame_probe(base_wz, row.get("png_dir_relpath", ""))
        out.append({
            "asset_id": row.get("id"),
            "name": row.get("name") or row.get("id"),
            "category": row.get("part_category"),
            "subcategory": row.get("eqp_category"),
            "source_script": "build_item_catalogue",
            "frame_count": frame_count,
            "first_frame_path": first_frame,
            "xml_relpath": row.get("xml_relpath"),
            "extra": row,
        })
    return out


def collect_itemwz_catalogue(base_wz: Path, component_dir: Path) -> list[dict[str, Any]]:
    """Same pattern as collect_character_catalogue but for
    build_itemwz_catalogue.py (Cash/Consume/Etc/Install/Pet/Special).
    """
    mod = _load_sibling_module("build_itemwz_catalogue")
    try:
        mod.build_catalogue(base_wz, component_dir)
    except FileNotFoundError:
        return []
    rows = _read_csv_rows(component_dir / "itemwz_catalogue_all.csv")
    out = []
    for row in rows:
        has_icon = row.get("has_icon") == "1"
        out.append({
            "asset_id": row.get("id"),
            "name": row.get("name") or row.get("id"),
            "category": row.get("item_root"),
            "subcategory": row.get("group_file"),
            "source_script": "build_itemwz_catalogue",
            # No numbered-frame sequence for Item.wz entries -- "equivalent"
            # signal is whether a renderable icon frame exists at all.
            "frame_count": 1 if has_icon else 0,
            "first_frame_path": row.get("icon_png_relpath") if has_icon else None,
            "xml_relpath": row.get("xml_relpath"),
            "extra": row,
        })
    return out


def _relativize(base_wz: Path, raw_path: str) -> Optional[str]:
    """build_wz_index.py's own rows store first_frame as an absolute path
    (it always has, even in this repo's committed analysis/wz_index/*.csv --
    a pre-existing quirk of that script, not something we're introducing).
    Relativize it against base_wz here so this unified table's paths are
    consistent with every other source_script's relpath convention.
    """
    if not raw_path:
        return None
    try:
        return str(Path(raw_path).relative_to(base_wz)).replace("\\", "/")
    except ValueError:
        return raw_path.replace("\\", "/")


def collect_wz_index(base_wz: Path) -> list[dict[str, Any]]:
    """build_wz_index.py's index_effect_img()/index_install_chairs() read
    a module-level BASE_WZ constant rather than taking it as a parameter.
    We reuse the functions as-is (no reimplementation) and point that
    constant at our base_wz for the duration of the call -- the functions
    already return structured rows directly, no CSV round-trip needed.
    """
    mod = _load_sibling_module("build_wz_index")
    original_base_wz = mod.BASE_WZ
    mod.BASE_WZ = base_wz
    try:
        out: list[dict[str, Any]] = []
        for img_name in ("BasicEff.img", "CharacterEff.img", "ItemEff.img", "OnUserEff.img"):
            for row in mod.index_effect_img(img_name):
                out.append({
                    "asset_id": row.get("path"),
                    "name": row.get("path"),
                    "category": "Effect",
                    "subcategory": img_name.replace(".img", ""),
                    "source_script": "build_wz_index",
                    "frame_count": row.get("frame_count"),
                    "first_frame_path": _relativize(base_wz, row.get("first_frame")),
                    "xml_relpath": None,
                    "extra": row,
                })
        for row in mod.index_install_chairs():
            out.append({
                "asset_id": row.get("id"),
                "name": row.get("name") or row.get("id"),
                "category": "Item",
                "subcategory": "Install/0301 (chairs)",
                "source_script": "build_wz_index",
                "frame_count": row.get("frame_count"),
                "first_frame_path": _relativize(base_wz, row.get("first_frame")),
                "xml_relpath": None,
                "extra": row,
            })
        return out
    finally:
        mod.BASE_WZ = original_base_wz


def _child_imgdir_or_canvas_count(root: ET.Element) -> int:
    return sum(1 for c in root if c.tag in ("imgdir", "canvas"))


def _has_nearby_name_field(root: ET.Element) -> bool:
    for child in root:
        if child.tag == "string" and child.attrib.get("name") in ("name", "desc"):
            return True
        for grandchild in child:
            if grandchild.tag == "string" and grandchild.attrib.get("name") in ("name", "desc"):
                return True
    return False


def collect_shallow_scan(base_wz: Path, category: str) -> list[dict[str, Any]]:
    """Deliberately shallow first pass for categories with no dedicated
    parser yet (Map, Mob, Npc, Quest, Skill, Sound, String, UI): top-level
    imgdir name + immediate child count + whether a name/string field is
    present nearby. Same spirit as audit_dataset_metadata.py's sampling --
    NOT equivalent depth to the Item/Effect/Character coverage above.
    Going deeper on any of these categories is explicitly out of scope
    for this PR (see PR description's Next-PR handoff).
    """
    cat_wz_dir = base_wz / category / f"{category}.wz"
    if not cat_wz_dir.exists():
        return []
    out = []
    for xml_path in sorted(cat_wz_dir.rglob("*.img.xml")):
        try:
            root = ET.parse(xml_path).getroot()
        except ET.ParseError:
            continue
        out.append({
            "asset_id": xml_path.stem.replace(".img", ""),
            "name": xml_path.stem,
            "category": category,
            "subcategory": str(xml_path.parent.relative_to(cat_wz_dir)).replace("\\", "/") if xml_path.parent != cat_wz_dir else "",
            "source_script": "shallow_scan",
            "frame_count": None,
            "first_frame_path": None,
            "xml_relpath": str(xml_path.relative_to(base_wz)).replace("\\", "/"),
            "extra": {
                "immediate_child_count": _child_imgdir_or_canvas_count(root),
                "has_name_field_nearby": _has_nearby_name_field(root),
            },
        })
    return out


def build_logical_asset_index(base_wz: Path, components_dir: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    rows.extend(collect_character_catalogue(base_wz, components_dir / "character_catalogue"))
    rows.extend(collect_itemwz_catalogue(base_wz, components_dir / "itemwz_catalogue"))
    rows.extend(collect_wz_index(base_wz))
    for category in KNOWN_CATEGORIES:
        if category in DEEP_COVERAGE_CATEGORIES:
            continue
        rows.extend(collect_shallow_scan(base_wz, category))
    return rows


# ==========================================================================
# Output: CSV + INDEX.md
# ==========================================================================

def write_manifest_csv(path: Path, records: list[FileRecord]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    headers = ["source_tree", "top_level_category", "relpath", "filename", "extension",
               "size_bytes", "mtime_utc", "sha256", "hash_type", "entry_format", "archive_name"]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=headers)
        w.writeheader()
        for r in records:
            w.writerow(asdict(r))


def write_completeness_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    headers = ["category", "present_in_83", "present_in_complete", "file_count_83", "file_count_complete",
               "total_size_83", "total_size_complete", "count_delta", "size_delta", "entry_format_83", "flag"]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=headers)
        w.writeheader()
        w.writerows(rows)


def write_logical_asset_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    headers = ["asset_id", "name", "category", "subcategory", "source_script", "frame_count", "first_frame_path", "xml_relpath"]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=headers)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in headers})


def write_index_md(
    path: Path,
    manifest_records: list[FileRecord],
    completeness_rows: list[dict[str, Any]],
    logical_rows: list[dict[str, Any]],
    db_path: Path,
    synthetic: bool,
) -> None:
    lines = ["# Unified Asset Inventory", ""]
    lines.append(
        "Auto-generated by `build_asset_inventory.py`. Orchestrates the existing "
        "`build_item_catalogue.py`, `build_itemwz_catalogue.py`, and `build_wz_index.py` "
        "against \"83 complete\", cross-checks it against \"83\" (the compressed/unextracted "
        "tree, format detected defensively per top-level entry), and stores both a flat "
        "per-file manifest and a unified logical-asset index in `asset_inventory.db` "
        "(sqlite3) plus these CSVs."
    )
    lines.append("")
    if synthetic:
        lines.append(
            "> **This run used synthetic fixture data**, not the real v83 asset trees "
            "(those live on the maintainer's local Windows machine only). See the PR "
            "description's Test evidence section."
        )
        lines.append("")

    by_tree: dict[str, int] = {}
    for r in manifest_records:
        by_tree[r.source_tree] = by_tree.get(r.source_tree, 0) + 1
    lines.append("## File manifest")
    lines.append("")
    lines.append(f"- Total files indexed: **{len(manifest_records)}**")
    for tree, count in sorted(by_tree.items()):
        lines.append(f"  - `{tree}`: {count}")
    lines.append("- Full CSV: `file_manifest.csv`")
    lines.append(f"- sqlite table: `file_manifest` in `{db_path.name}`")
    lines.append("")

    lines.append("## 83-vs-83-complete completeness cross-check")
    lines.append("")
    lines.append("| Category | In 83 | In complete | Count 83 | Count complete | Flag |")
    lines.append("|---|---|---|---|---|---|")
    for row in sorted(completeness_rows, key=lambda r: r["category"]):
        lines.append(
            f"| {row['category']} | {'yes' if row['present_in_83'] else 'no'} | "
            f"{'yes' if row['present_in_complete'] else 'no'} | {row['file_count_83']} | "
            f"{row['file_count_complete']} | {row['flag']} |"
        )
    lines.append("")
    lines.append("Flags: `ok`, `count_mismatch` / `size_mismatch` (>10% delta), "
                  "`missing_in_83`, `missing_in_complete`, and `opaque_not_comparable` "
                  "(the 83-side entry is an unreadable single blob -- a raw WZ binary "
                  "vs many extracted files is expected, not evidence of loss).")
    lines.append("- Full CSV: `completeness_cross_check.csv`")
    lines.append("")

    by_source: dict[str, int] = {}
    for r in logical_rows:
        by_source[r["source_script"]] = by_source.get(r["source_script"], 0) + 1
    lines.append("## Unified logical-asset master index")
    lines.append("")
    lines.append(f"- Total logical assets: **{len(logical_rows)}**")
    for source, count in sorted(by_source.items()):
        depth = "deep (existing parser)" if source != "shallow_scan" else "SHALLOW first pass -- not equivalent depth"
        lines.append(f"  - `{source}`: {count} ({depth})")
    lines.append("")
    lines.append(
        "Shallow-scan categories (Map, Mob, Npc, Quest, Skill, Sound, String, UI) record "
        "only top-level imgdir name + immediate child count + whether a name/string field "
        "is nearby. Deepening any of these to Item/Effect/Character-level detail is "
        "follow-up work -- see the PR's Next-PR handoff."
    )
    lines.append("- Full CSV: `logical_asset_index.csv`")
    lines.append(f"- sqlite table: `logical_asset` in `{db_path.name}`")
    lines.append("")
    lines.append("## Querying")
    lines.append("")
    lines.append("```")
    lines.append("python build_asset_inventory.py --skip-build --search \"sunny day\"")
    lines.append(f"sqlite3 {db_path.name} \"SELECT * FROM logical_asset WHERE name LIKE '%chair%';\"")
    lines.append("```")
    lines.append("")

    path.write_text("\n".join(lines), encoding="utf-8")


# ==========================================================================
# Search / query CLI mode
# ==========================================================================

def run_search(db_path: Path, term: str, limit: int) -> None:
    if not db_path.exists():
        print(f"No database found at {db_path}. Run a build first (omit --skip-build).", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    like = f"%{term}%"

    print(f"=== logical_asset matches for {term!r} ===")
    for row in conn.execute(
        """SELECT asset_id, name, category, subcategory, source_script, frame_count, first_frame_path
           FROM logical_asset
           WHERE name LIKE ? OR asset_id LIKE ? OR category LIKE ? OR subcategory LIKE ?
           LIMIT ?""",
        (like, like, like, like, limit),
    ):
        print(dict(row))

    print(f"\n=== file_manifest matches for {term!r} ===")
    for row in conn.execute(
        """SELECT source_tree, top_level_category, relpath, filename, size_bytes
           FROM file_manifest
           WHERE filename LIKE ? OR relpath LIKE ? OR top_level_category LIKE ?
           LIMIT ?""",
        (like, like, like, limit),
    ):
        print(dict(row))
    conn.close()


# ==========================================================================
# Orchestration entry point
# ==========================================================================

def run_build(
    source_83: Path,
    source_complete: Path,
    output_dir: Path,
    db_path: Path,
    full_hash_max_bytes: int,
    no_hash: bool,
    synthetic: bool,
) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    components_dir = output_dir / "_components"

    manifest_records: list[FileRecord] = []
    manifest_records.extend(walk_83_tree(source_83, full_hash_max_bytes, no_hash))
    manifest_records.extend(walk_complete_tree(source_complete, full_hash_max_bytes, no_hash))

    completeness_rows = build_completeness_check(manifest_records)

    base_wz = _category_root(source_complete)
    logical_rows = build_logical_asset_index(base_wz, components_dir)

    conn = open_db(db_path)
    create_schema(conn)
    insert_manifest_rows(conn, manifest_records)
    insert_completeness_rows(conn, completeness_rows)
    insert_logical_asset_rows(conn, logical_rows)
    conn.close()

    write_manifest_csv(output_dir / "file_manifest.csv", manifest_records)
    write_completeness_csv(output_dir / "completeness_cross_check.csv", completeness_rows)
    write_logical_asset_csv(output_dir / "logical_asset_index.csv", logical_rows)
    write_index_md(output_dir / "INDEX.md", manifest_records, completeness_rows, logical_rows, db_path, synthetic)

    return {
        "manifest_files": len(manifest_records),
        "completeness_categories": len(completeness_rows),
        "logical_assets": len(logical_rows),
        "output_dir": str(output_dir),
        "db_path": str(db_path),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-83", default=DEFAULT_SOURCE_83,
                         help="Path to the '83' (compressed/unextracted) tree. "
                              "Format is detected defensively per top-level entry.")
    parser.add_argument("--source-complete", default=DEFAULT_SOURCE_COMPLETE,
                         help="Path to the '83 complete' (already-unpacked) tree.")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR),
                         help="Directory for CSV/INDEX.md output (default: analysis/asset_inventory/).")
    parser.add_argument("--db-path", default=None,
                         help="sqlite3 db path (default: <output-dir>/asset_inventory.db).")
    parser.add_argument("--full-hash-max-bytes", type=int, default=DEFAULT_FULL_HASH_MAX_BYTES,
                         help=f"Files at or below this size get a full sha256; larger files get a "
                              f"head+tail+size sampled hash (default: {DEFAULT_FULL_HASH_MAX_BYTES}).")
    parser.add_argument("--no-hash", action="store_true",
                         help="Skip hashing entirely (hash_type='skipped') for a fast first pass.")
    parser.add_argument("--skip-build", action="store_true",
                         help="Don't rebuild -- just run --search against the existing db.")
    parser.add_argument("--search", default=None,
                         help="LIKE-search name/path/category in the (existing or freshly built) db and print matches.")
    parser.add_argument("--search-limit", type=int, default=50, help="Max rows per table for --search.")
    parser.add_argument("--synthetic", action="store_true",
                         help="Mark this run's INDEX.md as synthetic-fixture verification, not a real v83 run.")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    db_path = Path(args.db_path) if args.db_path else output_dir / "asset_inventory.db"

    if not args.skip_build:
        summary = run_build(
            source_83=Path(args.source_83),
            source_complete=Path(args.source_complete),
            output_dir=output_dir,
            db_path=db_path,
            full_hash_max_bytes=args.full_hash_max_bytes,
            no_hash=args.no_hash,
            synthetic=args.synthetic,
        )
        print(json.dumps({"status": "ok", **summary}, indent=2))

    if args.search:
        run_search(db_path, args.search, args.search_limit)


if __name__ == "__main__":
    main()
