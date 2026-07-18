# Project Status

Snapshot date: 2026-04-20. Authoritative: `docs/product/MILESTONE_STATUS.md`.

## Identity

This repo ships a Windows desktop buddy (`apps/runtime-godot/`). Legacy
MapleStory importer/reverse-engineering tooling lives under
`tools/importers/` (relocated from the repo root in PR-12; see
`PR_PLAN.md` → PR-12). Importer tooling is a **dev-host** concern;
the runtime does **not** depend on WZ/NX schemas at runtime.

## What is landed on `main`

- Godot runtime vertical slice: BuddyActor, idle/drag/sleep/visit states,
  embedded composed character frames, gift pipeline, chair overlay,
  Effect.wz-derived overlays (baked to PNG), ChatBalloon 9-slice bubble.
  Runtime face-overlay rotation remains deferred until its approved assets are
  tracked in the shipping closure.
- Character rendering + animation export pipeline (Python).
- Product docs under `docs/product/` (V1 PRD, milestone status, execution
  plan, decision register, Windows release checklist, PR architecture
  checklist, next 10 actions).

## PR queue status

- PR-00 through PR-15 are merged. **PR-12 is now fully landed**: the
  content schema freeze half merged 2026-04-20 (`CONTENT_SCHEMA_VERSION = 1`,
  rejection of unsupported `schemaVersion`, `docs/product/CONTENT_SCHEMA.md`),
  and the importer-boundary half — relocating the 15 root Python scripts to
  `tools/importers/` — has now landed. `tools/importers/` exists and holds
  the importer/analysis scripts. See `README.md` for the current script
  inventory.
- Remaining **release-gating** work is release rehearsal and evidence
  capture only — source of truth: `RELEASE_CHECKLIST.md`, whose tag
  gates never listed the PR-12 relocation, and that was intentional: the
  affected scripts are dev-host-only tooling with no runtime impact, so
  relocating them was never a release-tag blocker. That relocation has now
  been completed as separate, non-blocking dev-tooling cleanup rather than
  as gate work.

## Temporary Maple83 dependency contract (current phase)

- Current runtime/content workflow intentionally uses MapleStory v83-derived
  references and assets from local extracted folders while V1 stabilizes.
- This is currently an accepted delivery constraint and should **not** be
  broken by cleanup PRs.
- Runtime must still consume project-native internal content structures;
  importer/provenance metadata may carry Maple-origin references for now.
- Replacement/hardening of this dependency is post-V1 roadmap work and must
  be done with explicit migration planning.

## What remains before tag

- Execute `docs/product/RC_SCENARIO_SUITE.md` against exported Windows
  artifact and record results.
- Populate `docs/product/PERF_BASELINE.md` release table (10-min and
  multi-hour runs).
- Verify final release artifact + `SHA256SUMS` and record previous-good tag
  rollback pointer.

## Truth checks

- "Works in editor" ≠ shipping truth. All release assertions must be made
  against the exported Windows build.
- Saves/settings must live under `user://` with versioning and safe
  regeneration on corruption (PR-03 gates this claim).
- Runtime must consume internal pack format only. WZ/NX awareness belongs
  to the importer, not the runtime (PR-04/PR-12 gate this claim).

## IP / provenance posture

- No WZ/NX or other proprietary binary assets are committed.
- Maple v83 references are used for taxonomy, availability discovery,
  naming/state reference, and validation cases only.
- Derived internal resources must record provenance and transformation
  notes (formalized in PR-13).

## Lessons learned (2026-04-20)

- Keep one release-truth source. If launch docs and release checklist diverge,
  treat checklist as authoritative until reconciled.
- Avoid false-green sign-off language before export-based rehearsal evidence
  is attached.
- Keep generated editor/import files out of review scope to preserve PR
  signal and reduce merge friction.
- Preserve temporary dependencies explicitly in docs so cleanup does not
  accidentally break the current delivery path.

## Pointers

- Roadmap / queue: `PR_PLAN.md`
- Scope fences: `DEFERRED.md`
- Release gate: `RELEASE_CHECKLIST.md` → `docs/product/WINDOWS_RELEASE_CHECKLIST.md`
- Current milestone detail: `docs/product/MILESTONE_STATUS.md`
- Product intent: `docs/product/V1_PRD.md`
