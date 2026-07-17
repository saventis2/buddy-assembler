# Non-Maple Content Lane — Proof

**PR:** PR-14  
**Date:** 2026-04-20

## What this proves

The runtime content pipeline is generic. It does not require MapleStory assets
to function. A conforming pack can load and validate with no visual assets;
the runtime then uses the complete repository-authored emergency buddy.

## How it was proven

`content/sample_pack/` is a minimal companion pack with:
- `manifest.json` — schemaVersion 1, non-Maple companion id, no `visual` key
- `PROVENANCE.md` — all-original (empty) asset inventory

`ContentLoader.validate_manifest` and `validate_assets` both pass on this pack.
The CI `validate-content` step runs against all packs under `content/` including
`sample_pack`. It is marked `runtimeAudience: development`, is tested through
the explicit development path, and cannot enter the production pack cycle.

## Adapter seam

The seam is `ContentLoader.load_with_fallback`:
1. Load the selected pack.
2. If validation fails, fall back to `core_pack`.
3. If `core_pack` also fails, fall back to the built-in safe-mode manifest.

`sample_pack` proves tier 1 only when development packs are explicitly
enabled. The production path falls back from a stale development selection to
`core_pack`; tiers 2 and 3 remain covered by `PackValidationTest`.

## Non-goals

- Providing actual custom artwork (deferred to content pipeline work)
- Shipping `sample_pack` to end users (it is a developer proof-of-concept)
