from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from urllib.error import URLError


MODULE_PATH = Path(__file__).with_name("validate_pr_gate_authority.py")
SPEC = importlib.util.spec_from_file_location("validate_pr_gate_authority", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
gate_authority = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gate_authority
SPEC.loader.exec_module(gate_authority)

REPO_ROOT = MODULE_PATH.parents[2]
BASE_SHA = "a" * 40
HEAD_SHA = "b" * 40
TREE_SHA = "c" * 40


class FakeResponse:
    def __init__(self, body: bytes, content_length: str | None = None) -> None:
        self._body = body
        self.headers: dict[str, str] = {}
        if content_length is not None:
            self.headers["Content-Length"] = content_length

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self, limit: int) -> bytes:
        return self._body


class FakeApi:
    def __init__(self, responses: dict[str, FakeResponse | Exception]) -> None:
        self.responses = responses
        self.requests: list[Any] = []

    def __call__(self, request: Any, timeout: int) -> FakeResponse:
        self.requests.append(request)
        response = self.responses[request.full_url]
        if isinstance(response, Exception):
            raise response
        return response


class GateAuthorityTests(unittest.TestCase):
    def _base_files(self) -> dict[str, bytes]:
        return {
            ".github/workflows/gate-authority.yml": b"name: Gate Authority\n",
            ".github/workflows/content-validator.yml": b"name: Content Validator\n",
            ".github/workflows/python-lint.yml": b"name: Python lint\n",
            ".github/workflows/runtime-smoke.yml": b"name: Runtime smoke\n",
            "packages/content-validator/validate_pr_gate_authority.py": b"print('base self')\n",
            "packages/content-validator/validate_ci_contract.py": b"print('base validator')\n",
            "packages/content-validator/headless_suite.py": b"print('base helper')\n",
        }

    def _write_base(self, root: Path, files: dict[str, bytes]) -> None:
        for relative, data in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def _event(self) -> dict[str, Any]:
        return {
            "action": "opened",
            "repository": {"full_name": "owner/repo", "id": 1},
            "pull_request": {
                "base": {
                    "ref": "main",
                    "sha": BASE_SHA,
                    "repo": {"full_name": "owner/repo", "id": 1},
                },
                "head": {
                    "sha": HEAD_SHA,
                    "repo": {"full_name": "fork/repo", "id": 2},
                },
            },
        }

    def _write_event(self, root: Path, event: object) -> Path:
        path = root / "event.json"
        path.write_text(json.dumps(event), encoding="utf-8")
        return path

    def _api_for(
        self,
        files: dict[str, bytes],
        *,
        tree_entries: list[dict[str, Any]] | None = None,
        tree_payload: object | None = None,
        blob_overrides: dict[str, bytes] | None = None,
    ) -> FakeApi:
        entries = tree_entries or [
            {
                "path": path,
                "mode": "100644",
                "type": "blob",
                "sha": hashlib.sha1(data).hexdigest(),
                "size": len(data),
            }
            for path, data in sorted(files.items())
        ]
        responses: dict[str, FakeResponse | Exception] = {
            f"{gate_authority.API_ROOT}/repos/owner/repo/git/commits/{HEAD_SHA}": FakeResponse(
                json.dumps({"sha": HEAD_SHA, "tree": {"sha": TREE_SHA}}).encode()
            ),
            f"{gate_authority.API_ROOT}/repos/owner/repo/git/trees/{TREE_SHA}?recursive=1": FakeResponse(
                json.dumps(
                    tree_payload
                    if tree_payload is not None
                    else {"sha": TREE_SHA, "truncated": False, "tree": entries}
                ).encode()
            ),
        }
        overrides = blob_overrides or {}
        for entry in entries:
            if entry.get("type") != "blob" or entry.get("mode") == "120000":
                continue
            path = entry["path"]
            data = overrides.get(path, files.get(path, b""))
            content = base64.encodebytes(data).decode("ascii")
            responses[
                f"{gate_authority.API_ROOT}/repos/owner/repo/git/blobs/{entry['sha']}"
            ] = FakeResponse(
                json.dumps(
                    {"sha": entry["sha"], "encoding": "base64", "content": content}
                ).encode()
            )
        return FakeApi(responses)

    def _validate(
        self,
        root: Path,
        files: dict[str, bytes],
        *,
        event: object | None = None,
        api: FakeApi | None = None,
    ) -> tuple[list[str], FakeApi]:
        event_path = self._write_event(root, self._event() if event is None else event)
        fake_api = api or self._api_for(files)
        return (
            gate_authority.validate(
                event_path,
                root,
                token="test-token",
                opener=fake_api,
                trusted_base_sha=BASE_SHA,
            ),
            fake_api,
        )

    def test_exact_good_candidate_passes_with_fixed_data_requests(self) -> None:
        files = self._base_files()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._write_base(root, files)
            errors, api = self._validate(root, files)

        self.assertEqual(errors, [])
        self.assertTrue(api.requests)
        self.assertTrue(
            all(request.get_header("Authorization") == "Bearer test-token" for request in api.requests)
        )
        requested_blobs = {
            request.full_url.rsplit("/", 1)[-1]
            for request in api.requests
            if "/git/blobs/" in request.full_url
        }
        self.assertEqual(requested_blobs, {hashlib.sha1(data).hexdigest() for data in files.values()})

    def test_simultaneous_if_false_workflow_change_fails(self) -> None:
        base = self._base_files()
        candidate = dict(base)
        candidate[".github/workflows/content-validator.yml"] += (
            b"jobs:\n  validate-content:\n    steps:\n"
            b"      - name: Verify CI/toolchain suite contract\n"
            b"        if: false\n"
        )
        candidate[".github/workflows/python-lint.yml"] += (
            b"jobs:\n  python-lint:\n    steps:\n"
            b"      - name: CI-contract Python unit suite (zero tests fails)\n"
            b"        if: false\n"
            b"      - name: Verify CI/toolchain contract authority (redundant)\n"
            b"        if: false\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._write_base(root, base)
            errors, _ = self._validate(root, candidate)

        self.assertEqual(errors, ["candidate frozen path bytes differ from trusted base"])

    def test_new_or_deleted_workflow_fails(self) -> None:
        base = self._base_files()
        cases = {
            "new": {**base, ".github/workflows/evil.yml": b"name: Evil\n"},
            "nested": {**base, ".github/workflows/nested/evil.yml": b"name: Evil\n"},
            "deleted": {key: value for key, value in base.items() if key != ".github/workflows/gate-authority.yml"},
        }
        for name, candidate in cases.items():
            with self.subTest(change=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self._write_base(root, base)
                errors, _ = self._validate(root, candidate)
                self.assertEqual(errors, ["candidate workflow path set differs from trusted base"])

    def test_changed_self_validator_or_helper_fails(self) -> None:
        base = self._base_files()
        for path in gate_authority.FROZEN_PROTECTED_PATHS:
            with self.subTest(path=path), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self._write_base(root, base)
                candidate = dict(base)
                candidate[path] += b"# changed\n"
                errors, _ = self._validate(root, candidate)
                self.assertEqual(errors, ["candidate frozen path bytes differ from trusted base"])

    def test_invalid_event_head_repository_or_base_fails(self) -> None:
        cases: dict[str, object] = {}
        invalid_action = self._event()
        invalid_action["action"] = "closed"
        cases["action"] = invalid_action
        invalid_head = self._event()
        invalid_head["pull_request"]["head"]["sha"] = HEAD_SHA.upper()
        cases["head"] = invalid_head
        invalid_repository = self._event()
        invalid_repository["pull_request"]["base"]["repo"]["id"] = 99
        cases["repository"] = invalid_repository
        invalid_base = self._event()
        invalid_base["pull_request"]["base"]["ref"] = "release"
        cases["base"] = invalid_base
        files = self._base_files()
        for name, event in cases.items():
            with self.subTest(event=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self._write_base(root, files)
                errors, _ = self._validate(root, files, event=event)
                self.assertEqual(len(errors), 1)

    def test_malformed_oversize_non_utf8_and_api_errors_fail(self) -> None:
        files = self._base_files()
        cases: dict[str, FakeApi] = {}
        malformed = self._api_for(
            files,
            tree_payload={"sha": TREE_SHA, "truncated": False, "tree": {}},
        )
        cases["malformed"] = malformed
        oversize = self._api_for(files)
        tree_url = f"{gate_authority.API_ROOT}/repos/owner/repo/git/trees/{TREE_SHA}?recursive=1"
        oversize.responses[tree_url] = FakeResponse(b"{}", str(gate_authority.MAX_RESPONSE_BYTES + 1))
        cases["oversize"] = oversize
        non_utf8_files = dict(files)
        non_utf8_files["packages/content-validator/headless_suite.py"] = b"\xff"
        non_utf8 = self._api_for(non_utf8_files)
        cases["non_utf8"] = non_utf8
        api_error = self._api_for(files)
        commit_url = f"{gate_authority.API_ROOT}/repos/owner/repo/git/commits/{HEAD_SHA}"
        api_error.responses[commit_url] = URLError("offline")
        cases["api_error"] = api_error
        for name, api in cases.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self._write_base(root, files)
                errors, _ = self._validate(root, files, api=api)
                self.assertEqual(len(errors), 1)
                if name == "non_utf8":
                    self.assertEqual(errors, ["candidate frozen blob is not valid UTF-8"])

    def test_symlink_nonblob_duplicate_and_truncated_tree_fail(self) -> None:
        files = self._base_files()
        base_entries = [
            {
                "path": path,
                "mode": "100644",
                "type": "blob",
                "sha": hashlib.sha1(data).hexdigest(),
                "size": len(data),
            }
            for path, data in sorted(files.items())
        ]
        symlink_entries = [dict(entry) for entry in base_entries]
        symlink_entries[0]["mode"] = "120000"
        symlink = self._api_for(files, tree_entries=symlink_entries)
        nonblob_entries = [dict(entry) for entry in base_entries]
        nonblob_entries[0]["mode"] = "040000"
        nonblob_entries[0]["type"] = "tree"
        nonblob = self._api_for(files, tree_entries=nonblob_entries)
        duplicate_entries = [*base_entries, dict(base_entries[1])]
        duplicate = self._api_for(files, tree_entries=duplicate_entries)
        truncated = self._api_for(
            files,
            tree_payload={"sha": TREE_SHA, "truncated": True, "tree": []},
        )
        for name, api, expected in (
            ("symlink", symlink, "candidate frozen path is a symlink"),
            ("nonblob", nonblob, "candidate frozen path is not a regular blob"),
            ("duplicate", duplicate, "candidate tree contains an invalid or duplicate path"),
            ("truncated", truncated, "candidate tree response is truncated or missing truncation status"),
        ):
            with self.subTest(case=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self._write_base(root, files)
                errors, _ = self._validate(root, files, api=api)
                self.assertEqual(errors, [expected])

    def test_unrelated_oversized_blob_is_ignored_but_frozen_one_fails(self) -> None:
        files = self._base_files()
        entries = [
            {
                "path": path,
                "mode": "100644",
                "type": "blob",
                "sha": hashlib.sha1(data).hexdigest(),
                "size": len(data),
            }
            for path, data in sorted(files.items())
        ]
        unrelated_entries = [
            *entries,
            {
                "path": "apps/runtime-godot/assets/large.bin",
                "mode": "100644",
                "type": "blob",
                "sha": "d" * 40,
                "size": gate_authority.MAX_BLOB_BYTES + 1,
            },
        ]
        frozen_entries = [dict(entry) for entry in entries]
        frozen_entries[0]["size"] = gate_authority.MAX_BLOB_BYTES + 1
        unrelated = self._api_for(files, tree_entries=unrelated_entries)
        frozen = self._api_for(files, tree_entries=frozen_entries)
        for name, api, expected in (
            ("unrelated", unrelated, []),
            ("frozen", frozen, ["candidate blob has an invalid size"]),
        ):
            with self.subTest(case=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self._write_base(root, files)
                errors, _ = self._validate(root, files, api=api)
                self.assertEqual(errors, expected)

    def test_frozen_requested_paths_are_exact(self) -> None:
        self.assertEqual(
            gate_authority.FROZEN_PROTECTED_PATHS,
            (
                "packages/content-validator/validate_pr_gate_authority.py",
                "packages/content-validator/validate_ci_contract.py",
                "packages/content-validator/headless_suite.py",
            ),
        )

    def test_cli_requires_isolation_before_shadowable_imports(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / "validate_pr_gate_authority.py"
            shutil.copy2(MODULE_PATH, script)
            urllib_marker = root / "urllib-marker"
            site_marker = root / "site-marker"
            decoy_urllib = root / "urllib"
            decoy_urllib.mkdir()
            (decoy_urllib / "__init__.py").write_text(
                f"from pathlib import Path\nPath({str(urllib_marker)!r}).write_text('ran')\n",
                encoding="utf-8",
            )
            (root / "sitecustomize.py").write_text(
                f"from pathlib import Path\nPath({str(site_marker)!r}).write_text('ran')\n",
                encoding="utf-8",
            )

            direct = subprocess.run(
                [sys.executable, str(script)],
                cwd=root,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(direct.returncode, 2)
            self.assertIn("isolated Python execution is required", direct.stderr)
            self.assertFalse(urllib_marker.exists())
            site_marker.unlink(missing_ok=True)
            isolated = subprocess.run(
                [sys.executable, "-I", str(script)],
                cwd=root,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(isolated.returncode, 2)
            self.assertFalse(urllib_marker.exists())
            self.assertFalse(site_marker.exists())

    def test_workflow_contract_is_base_owned_and_read_only(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/gate-authority.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("name: Gate Authority", workflow)
        self.assertIn("pull_request_target:", workflow)
        self.assertIn("branches:\n      - main", workflow)
        self.assertIn("types: [opened, synchronize, reopened, ready_for_review]", workflow)
        self.assertIn("permissions:\n  contents: read", workflow)
        self.assertIn("name: Validate PR gate authority", workflow)
        self.assertIn("timeout-minutes: 5", workflow)
        self.assertIn(
            "uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0",
            workflow,
        )
        self.assertIn("ref: ${{ github.event.pull_request.base.sha }}", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn(
            "uses: actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1",
            workflow,
        )
        self.assertIn(
            'python -I packages/content-validator/validate_pr_gate_authority.py --event "$GITHUB_EVENT_PATH"',
            workflow,
        )
        self.assertNotIn("paths:", workflow)
        self.assertNotIn("paths-ignore:", workflow)
        self.assertNotIn("continue-on-error:", workflow)
        self.assertNotIn("if:", workflow)
        self.assertNotIn("secrets.", workflow)
        run = workflow.rsplit("run: |", 1)[1]
        self.assertNotIn("github.event", run)


if __name__ == "__main__":
    unittest.main()
