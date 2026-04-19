# Project Status

Snapshot date: 2026-04-19. Authoritative: `docs/product/MILESTONE_STATUS.md`.

## Identity

This repo ships a Windows desktop buddy (`apps/runtime-godot/`). Legacy
MapleStory importer/reverse-engineering tooling lives at the repo root
and will be relocated under a `tools/importers/` area in a later PR
(see `PR_PLAN.md` → PR-12). Importer tooling is a **dev-host** concern;
the runtime does **not** depend on WZ/NX schemas at runtime.

## What is landed on `main`

- Godot runtime vertical slice: BuddyActor, idle/drag/sleep/visit states,
  face emote rotation, gift pipeline, chair overlay, Effect.wz-derived
  overlays (baked to PNG), ChatBalloon 9-slice bubble.
- Character rendering + animation export pipeline (Python).
- Product docs under `docs/product/` (V1 PRD, milestone status, execution
  plan, decision register, Windows release checklist, PR architecture
  checklist, next 10 actions).

## What is NOT yet landed

- Buddy-first mainline identity (this PR, PR-00).
- Repo rails: PR template, CODEOWNERS, labels, review checklist (PR-01).
- CI import/export smoke + artifact retention (PR-02).
- ~~Save/settings versioning and corruption recovery (PR-03).~~ **Landed in PR-03.**
- ~~Pack validation + runtime fallback (PR-04).~~ **Landed in PR-04.**
- ~~RC scenario suite (PR-05).~~ **Landed in PR-05** —
  `docs/product/RC_SCENARIO_SUITE.md`.
- ~~Perf instrumentation + burn-in (PR-06).~~ **Landed in PR-06** —
  `docs/product/PERF_BASELINE.md` + `tests/IdleProfile.tscn`. Baseline
  table populated at release rehearsal.
- ~~Final Windows packaging + release smoke (PR-07).~~ **Landed in PR-07** —
  `docs/product/PACKAGING.md`, export preset metadata finalized,
  SHA256SUMS generated in CI, V1 unsigned with SmartScreen path
  documented.
- ~~First-run onboarding (PR-08).~~ **Landed in PR-08** —
  `docs/product/FIRST_RUN_ONBOARDING.md`, `firstRunSeen` flag in
  settings, 6-second welcome tooltip on first launch.
- Bond cadence (PR-09); transition polish (PR-10); shipped companion
  pack (PR-11).
- Schema freeze + importer boundary cleanup (PR-12).
- Provenance manifest + snapshot promotion (PR-13).
- Non-Maple content lane proof (PR-14).
- Launch docs + V1 exit criteria (PR-15).

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

## Pointers

- Roadmap / queue: `PR_PLAN.md`
- Scope fences: `DEFERRED.md`
- Release gate: `RELEASE_CHECKLIST.md` → `docs/product/WINDOWS_RELEASE_CHECKLIST.md`
- Current milestone detail: `docs/product/MILESTONE_STATUS.md`
- Product intent: `docs/product/V1_PRD.md`
