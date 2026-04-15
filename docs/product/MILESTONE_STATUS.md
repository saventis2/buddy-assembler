# Milestone Status

Updated: 2026-04-16

## Phase 0 (Clarification/Stabilization)

- [done] Execution plan recorded
- [done] Decision register recorded
- [done] V1 PRD recorded
- [done] Repo/runtime/content boundaries created

## Phase 1 (Runtime Core)

- [done] Transparent always-on-top runtime scaffold
- [done] Drag/click/sleep interactions
- [done] Deterministic weighted behavior core
- [done] Save/settings/profile/world persistence
- [done] Unlock table wiring
- [done] Encounter scheduler + event budgets
- [done] Multi-monitor clamp/restore logic
- [done] Headless runtime parse check
- [pending] Interactive multi-monitor drag verification in local desktop session

## Phase 2 (Content Pipeline)

- [done] Content schema contract file
- [done] Manifest validator CLI
- [done] Core pack + second pack
- [done] CI workflow for pack validation
- [done] BIF converter and importer scaffold for Maple-agnostic ingestion

## Phase 3 (Vertical Slice Runtime)

- [done] Internal imported actor resource path wired end-to-end
- [done] Vertical-slice map + actor scene (`idle`, `walk`, `jump`, `happy_emote`)
- [done] Buddy command bridge (`play_emote("happy")`)
- [done] Launch router with `--vertical-slice` mode flag
- [done] Direction-facing sprite flip during movement
- [done] Floor lock fallback to prevent actor falling through map floor
- [done] Jump animation priority corrected (walk no longer overrides jump start)
- [done] Emote command path visibly plays `happy_emote` in vertical slice
- [done] Top-of-window control hint now wraps and remains readable

## Phase 4 (Utility Layer)

- [done] Opt-in productivity tracker module
- [done] Focus celebration and break suggestion event hooks

## Remaining Blocker

- Interactive desktop verification still requires manual run (headless checks
  are complete).
