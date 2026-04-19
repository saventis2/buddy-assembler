# Non-Maple Content Lane — Proof

**PR:** PR-14  
**Date:** 2026-04-20

## What this proves

The runtime content pipeline is generic. It does not require MapleStory assets
to function. Any pack conforming to `docs/product/CONTENT_SCHEMA.md` will load,
validate, and run — even with no visual assets at all (runtime falls back to
the code-drawn placeholder buddy).

## How it was proven

`content/sample_pack/` is a minimal companion pack with:
- `manifest.json` — schemaVersion 1, non-Maple companion id, no `visual` key
- `PROVENANCE.md` — all-original (empty) asset inventory

`ContentLoader.validate_manifest` and `validate_assets` both pass on this pack.
The CI `validate-content` step runs against all packs under `content/` including
`sample_pack` — a green CI run on this PR is the proof.

## Adapter seam

The seam is `ContentLoader.load_with_fallback`:
1. Load the selected pack.
2. If validation fails, fall back to `core_pack`.
3. If `core_pack` also fails, fall back to the built-in safe-mode manifest.

`sample_pack` proves tier 1 (selected pack succeeds). Tiers 2 and 3 are
covered by the `PackValidationTest` headless test (PR-04).

## Non-goals

- Providing actual custom artwork (deferred to content pipeline work)
- Shipping `sample_pack` to end users (it is a developer proof-of-concept)
