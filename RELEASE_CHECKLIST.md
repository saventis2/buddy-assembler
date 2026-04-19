# Release Checklist

Top-level release gate. Authoritative detailed checklist:
`docs/product/WINDOWS_RELEASE_CHECKLIST.md`. This file stays short on
purpose — it exists so a reviewer can tell at a glance what a release
requires without hunting.

"Works in editor" is **not** sufficient. Every claim below must be
verified against the **exported Windows build**.

## Pre-release gates (must all be green)

- [ ] PR-02 CI smoke green on the release commit (import + Windows export).
- [x] PR-03 durable saves/settings: versioned, corruption-recoverable,
      `user://` path. Gated by `tests/SaveStoreTest.tscn` in CI.
- [x] PR-04 pack validator: shipping manifests pass; missing/invalid
      content falls back deterministically (selected → core → builtin).
      Gated by `tests/PackValidationTest.tscn` in CI.
- [x] PR-05 scenario suite: first run, restart, drag/click, idle, sleep,
      visits, invalid content, corrupted settings, export launch. See
      `docs/product/RC_SCENARIO_SUITE.md`. All nine rows must be P on
      the exported Windows build before tagging.
- [ ] PR-06 perf baselines: 10-min idle and multi-hour idle recorded.
- [ ] PR-07 exported build: launches outside editor; writable saves;
      packaging layout final; signing decision recorded.
- [ ] PR-13 provenance manifest present for all shipping content.

## Launch artifacts

- [ ] Exported Windows build (signed or signing-decision documented).
- [ ] `SHA256SUMS` for release artifacts.
- [ ] Release notes + known-issues (PR-15).
- [ ] Rollback note: previous release tag + restore steps.

## Rollback plan

- Previous known-good release tag recorded here: _TBD at first release_.
- Rollback = retag, republish artifacts, revert default update channel
  pointer (if any). No runtime data migration needed because saves are
  versioned (PR-03).
