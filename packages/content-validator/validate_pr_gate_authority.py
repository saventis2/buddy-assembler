#!/usr/bin/env python3
"""Fail closed when a pull request changes base-owned CI gate authority.

This program is checked out from the pull request base by the
``pull_request_target`` sentinel. Candidate Git objects are fetched only as
bounded REST data and are never written, executed, imported, or interpolated
into a command.
"""

from __future__ import annotations

import sys

if __name__ == "__main__" and sys.flags.isolated != 1:
    print("gate_authority: FAIL: isolated Python execution is required", file=sys.stderr)
    raise SystemExit(2)

import argparse
import base64
import binascii
import json
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


API_ROOT = "https://api.github.com"
API_VERSION = "2022-11-28"
USER_AGENT = "buddy-gate-authority/1.0"
REQUEST_TIMEOUT_SECONDS = 10
MAX_EVENT_BYTES = 1_000_000
MAX_RESPONSE_BYTES = 2_000_000
MAX_BLOB_BYTES = 1_000_000
MAX_TREE_ENTRIES = 20_000
WORKFLOW_PREFIX = ".github/workflows/"
FROZEN_PROTECTED_PATHS = (
    "packages/content-validator/validate_pr_gate_authority.py",
    "packages/content-validator/validate_ci_contract.py",
    "packages/content-validator/headless_suite.py",
)
_SHA = re.compile(r"^[0-9a-f]{40}$")
_REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
_ALLOWED_ACTIONS = {"opened", "synchronize", "reopened", "ready_for_review"}


class GateAuthorityError(ValueError):
    """Expected fail-closed input or transport error."""


@dataclass(frozen=True)
class PullRequestIdentity:
    repository: str
    base_sha: str
    head_sha: str


def _require_sha(value: object, label: str) -> str:
    if not isinstance(value, str) or _SHA.fullmatch(value) is None:
        raise GateAuthorityError(f"{label} must be a lowercase 40-hex SHA")
    return value


def _require_mapping(value: object, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise GateAuthorityError(f"{label} must be an object")
    return value


def _require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise GateAuthorityError(f"{label} must be a non-empty string")
    return value


def _require_repository(value: object, label: str) -> str:
    repository = _require_string(value, label)
    if _REPOSITORY.fullmatch(repository) is None:
        raise GateAuthorityError(f"{label} is not a supported owner/repository identity")
    return repository


def _require_positive_int(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise GateAuthorityError(f"{label} must be a positive integer")
    return value


def _event_identity(event: object, trusted_base_sha: str) -> PullRequestIdentity:
    root = _require_mapping(event, "event")
    action = _require_string(root.get("action"), "event.action")
    if action not in _ALLOWED_ACTIONS:
        raise GateAuthorityError("event.action is outside the sentinel trigger contract")
    repository = _require_mapping(root.get("repository"), "event.repository")
    repository_name = _require_repository(
        repository.get("full_name"), "event.repository.full_name"
    )
    repository_id = _require_positive_int(repository.get("id"), "event.repository.id")
    pull_request = _require_mapping(root.get("pull_request"), "event.pull_request")
    base = _require_mapping(pull_request.get("base"), "event.pull_request.base")
    base_repository = _require_mapping(
        base.get("repo"), "event.pull_request.base.repo"
    )
    if _require_repository(
        base_repository.get("full_name"), "event.pull_request.base.repo.full_name"
    ) != repository_name or _require_positive_int(
        base_repository.get("id"), "event.pull_request.base.repo.id"
    ) != repository_id:
        raise GateAuthorityError("event pull request base repository does not match event repository")
    if base.get("ref") != "main":
        raise GateAuthorityError("event pull request base ref is not main")
    base_sha = _require_sha(base.get("sha"), "event.pull_request.base.sha")
    if base_sha != trusted_base_sha:
        raise GateAuthorityError("event pull request base SHA does not match trusted checkout")
    head = _require_mapping(pull_request.get("head"), "event.pull_request.head")
    head_repository = _require_mapping(
        head.get("repo"), "event.pull_request.head.repo"
    )
    _require_repository(
        head_repository.get("full_name"), "event.pull_request.head.repo.full_name"
    )
    _require_positive_int(head_repository.get("id"), "event.pull_request.head.repo.id")
    return PullRequestIdentity(
        repository=repository_name,
        base_sha=base_sha,
        head_sha=_require_sha(head.get("sha"), "event.pull_request.head.sha"),
    )


def _read_json_file(path: Path) -> object:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise GateAuthorityError(f"cannot read event file: {exc}") from exc
    if len(data) > MAX_EVENT_BYTES:
        raise GateAuthorityError("event file exceeds the size limit")
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GateAuthorityError("event file is not valid UTF-8 JSON") from exc


def _trusted_checkout_sha(repo_root: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    if result.returncode != 0:
        raise GateAuthorityError("cannot determine trusted checkout SHA")
    return _require_sha(result.stdout.strip(), "trusted checkout SHA")


class GitHubRest:
    """Tiny bounded GitHub REST reader with no candidate-code execution path."""

    def __init__(self, token: str | None, opener: Callable[..., Any] = urlopen) -> None:
        self._token = token
        self._opener = opener

    def get_json(self, path: str) -> object:
        request = Request(f"{API_ROOT}{path}")
        request.add_header("Accept", "application/vnd.github+json")
        request.add_header("X-GitHub-Api-Version", API_VERSION)
        request.add_header("User-Agent", USER_AGENT)
        if self._token:
            request.add_header("Authorization", f"Bearer {self._token}")
        try:
            with self._opener(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                content_length = response.headers.get("Content-Length")
                if content_length is not None and (
                    not content_length.isdecimal() or int(content_length) > MAX_RESPONSE_BYTES
                ):
                    raise GateAuthorityError("GitHub response exceeds the size limit")
                data = response.read(MAX_RESPONSE_BYTES + 1)
        except (HTTPError, URLError, OSError, TimeoutError) as exc:
            raise GateAuthorityError(f"GitHub REST request failed: {type(exc).__name__}") from exc
        if len(data) > MAX_RESPONSE_BYTES:
            raise GateAuthorityError("GitHub response exceeds the size limit")
        try:
            return json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise GateAuthorityError("GitHub REST response is not valid UTF-8 JSON") from exc


def _git_path(repository: str, suffix: str) -> str:
    return f"/repos/{quote(repository, safe='/')}{suffix}"


def _candidate_tree(client: GitHubRest, identity: PullRequestIdentity) -> dict[str, dict[str, Any]]:
    commit = _require_mapping(
        client.get_json(_git_path(identity.repository, f"/git/commits/{identity.head_sha}")),
        "candidate commit response",
    )
    if _require_sha(commit.get("sha"), "candidate commit response.sha") != identity.head_sha:
        raise GateAuthorityError("candidate commit response SHA does not match event head SHA")
    tree = _require_mapping(commit.get("tree"), "candidate commit response.tree")
    tree_sha = _require_sha(tree.get("sha"), "candidate commit response.tree.sha")
    response = _require_mapping(
        client.get_json(_git_path(identity.repository, f"/git/trees/{tree_sha}?recursive=1")),
        "candidate tree response",
    )
    if _require_sha(response.get("sha"), "candidate tree response.sha") != tree_sha:
        raise GateAuthorityError("candidate tree response SHA does not match candidate commit")
    if response.get("truncated") is not False:
        raise GateAuthorityError("candidate tree response is truncated or missing truncation status")
    entries = response.get("tree")
    if not isinstance(entries, list) or len(entries) > MAX_TREE_ENTRIES:
        raise GateAuthorityError("candidate tree response has an invalid entry list")
    result: dict[str, dict[str, Any]] = {}
    for entry in entries:
        item = _require_mapping(entry, "candidate tree entry")
        path = _require_string(item.get("path"), "candidate tree entry.path")
        parts = path.split("/")
        if (
            "\x00" in path
            or path.startswith("/")
            or "\\" in path
            or any(part in ("", ".", "..") for part in parts)
            or path in result
        ):
            raise GateAuthorityError("candidate tree contains an invalid or duplicate path")
        entry_type = item.get("type")
        mode = item.get("mode")
        if not isinstance(entry_type, str) or not isinstance(mode, str):
            raise GateAuthorityError("candidate tree entry has malformed type or mode")
        if entry_type not in ("blob", "tree", "commit"):
            raise GateAuthorityError("candidate tree entry has an unsupported type")
        frozen = path.startswith(WORKFLOW_PREFIX) or path in FROZEN_PROTECTED_PATHS
        if entry_type == "blob":
            _require_sha(item.get("sha"), "candidate tree entry.sha")
            size = item.get("size")
            if not isinstance(size, int) or isinstance(size, bool) or size < 0:
                raise GateAuthorityError("candidate blob has an invalid size")
        else:
            _require_sha(item.get("sha"), "candidate tree entry.sha")
        if frozen:
            if entry_type != "blob":
                raise GateAuthorityError("candidate frozen path is not a regular blob")
            if mode == "120000":
                raise GateAuthorityError("candidate frozen path is a symlink")
            if mode not in ("100644", "100755"):
                raise GateAuthorityError("candidate frozen blob has a non-regular mode")
            if item["size"] > MAX_BLOB_BYTES:
                raise GateAuthorityError("candidate blob has an invalid size")
        result[path] = item
    return result


def _base_frozen_files(repo_root: Path) -> dict[str, bytes]:
    workflow_root = repo_root / ".github" / "workflows"
    if not workflow_root.is_dir() or workflow_root.is_symlink():
        raise GateAuthorityError("trusted checkout workflow directory is unavailable")
    paths = [
        *sorted(path for path in workflow_root.rglob("*") if path.is_file()),
        *(repo_root / relative for relative in FROZEN_PROTECTED_PATHS),
    ]
    result: dict[str, bytes] = {}
    for path in paths:
        if path.is_symlink() or not path.is_file():
            raise GateAuthorityError("trusted checkout frozen path is not a regular file")
        relative = path.relative_to(repo_root).as_posix()
        if relative in result:
            raise GateAuthorityError("trusted checkout has duplicate frozen paths")
        try:
            data = path.read_bytes()
            data.decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            raise GateAuthorityError("trusted checkout frozen path is not valid UTF-8") from exc
        if len(data) > MAX_BLOB_BYTES:
            raise GateAuthorityError("trusted checkout frozen path exceeds the size limit")
        result[relative] = data
    return result


def _candidate_blob(client: GitHubRest, identity: PullRequestIdentity, entry: dict[str, Any]) -> bytes:
    sha = _require_sha(entry.get("sha"), "candidate blob SHA")
    response = _require_mapping(
        client.get_json(_git_path(identity.repository, f"/git/blobs/{sha}")),
        "candidate blob response",
    )
    if _require_sha(response.get("sha"), "candidate blob response.sha") != sha:
        raise GateAuthorityError("candidate blob response SHA does not match tree entry")
    if response.get("encoding") != "base64" or not isinstance(response.get("content"), str):
        raise GateAuthorityError("candidate blob response has an unsupported encoding")
    try:
        encoded = response["content"].replace("\n", "").replace("\r", "")
        data = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise GateAuthorityError("candidate blob response is not valid base64") from exc
    expected_size = entry.get("size")
    if len(data) > MAX_BLOB_BYTES or len(data) != expected_size:
        raise GateAuthorityError("candidate blob response has an invalid size")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise GateAuthorityError("candidate frozen blob is not valid UTF-8") from exc
    return data


def validate(
    event_path: Path,
    repo_root: Path,
    *,
    token: str | None = None,
    opener: Callable[..., Any] = urlopen,
    trusted_base_sha: str | None = None,
) -> list[str]:
    """Return fail-closed errors without writing, importing, or running candidate data."""
    try:
        base_sha = trusted_base_sha or _trusted_checkout_sha(repo_root)
        identity = _event_identity(_read_json_file(event_path), _require_sha(base_sha, "trusted base SHA"))
        client = GitHubRest(token, opener)
        tree = _candidate_tree(client, identity)
        base_files = _base_frozen_files(repo_root)
        candidate_workflows = {path for path in tree if path.startswith(WORKFLOW_PREFIX)}
        base_workflows = {path for path in base_files if path.startswith(WORKFLOW_PREFIX)}
        if candidate_workflows != base_workflows:
            raise GateAuthorityError("candidate workflow path set differs from trusted base")
        for path, base_bytes in base_files.items():
            entry = tree.get(path)
            if entry is None:
                raise GateAuthorityError("candidate frozen path is missing")
            if entry.get("type") != "blob" or entry.get("mode") == "120000":
                raise GateAuthorityError("candidate frozen path is not a regular blob")
            if _candidate_blob(client, identity, entry) != base_bytes:
                raise GateAuthorityError("candidate frozen path bytes differ from trusted base")
    except GateAuthorityError as exc:
        return [str(exc)]
    return []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", type=Path, required=True)
    args = parser.parse_args(argv)
    errors = validate(args.event, Path(__file__).resolve().parents[2], token=os.getenv("GITHUB_TOKEN"))
    if errors:
        for error in errors:
            print(f"gate_authority: FAIL: {error}", file=sys.stderr)
        return 1
    print("gate_authority: PASS (candidate gate authority matches trusted base)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
