# Milestone Status

Updated: 2026-04-20 (world-layer stub wiring added)

> Update (2026-04-20): buddy-system milestone tracking is now coordinated with
> `BUDDY_V1_BUILD_PLAN_MILESTONE_EXECUTION_2026-04-20.md` for identity/economy/world
> sequencing beyond vertical-slice runtime polish.

## Buddy Milestone 3 (World Layer Stub — 2026-04-20)

- [done] Added manifest-driven world contract fields (`home`, `npcs`, `quests`, `encounters`)
- [done] Added `world_service.gd` with pending quest/encounter rotation
- [done] Added AppState world hooks for prompt ticking + quest/encounter resolution
- [done] Added overlay controls for world flow (`F12` engage/complete, `Shift+F12` skip encounter)
- [done] Added home/overlay mode toggle (`F5`) with home-scene/decor telemetry
- [done] Wired rewards from quest/encounter outcomes into economy service transactions
- [done] Added recent-prompt anti-repeat guard for world quest/encounter rotation

## Buddy Milestone 4 (Tuning Pass — 2026-04-20)

- [done] Added short-history anti-repeat weighting in `BehaviorEngine` action picks
- [done] Added duplicate reward-box recycle crystals by rarity tier
- [done] Exposed duplicate recycle totals in runtime telemetry/debug output

## Phase 5 (Visual polish & WZ asset expansion — 2026-04-19)

- [done] Per-frame hand tracking for held-prop overlays (renderer parses
  `world_anchors.hand` + `pivot_world` per body frame)
- [done] Gift pipeline: weaponless `heal` body + WZ `04080000` gift_box icon
  in hand + WZ ChatBalloon speech bubble
- [done] Back-layer overlay system (chair_basic / Item.wz Install 03010000)
- [done] Effect.wz overlays wired: IncEXP (happy), Summoned (visitor arrival),
  Teleport (visitor depart)
- [done] Replaced Label-on-forehead bubble with WZ `UI.wz/ChatBalloon.img/0`
  9-slice Node2D
- [done] 14 face emote variants exposed (stunned, proud, embarrassed,
  sparkle, humming, kiss, bow, sleepy, sick, pain, wink, hot, vomit, despair,
  troubled) — base-name `semantic_defaults`, behavior rotation, hotkeys
  U/I/O/P/H/K/B
- [done] Visitor as second BuddyActor with distinct skin (walk-in, wave,
  walk-off + Teleport sparkle)
- [done] WZ catalog tooling: `build_wz_index.py` + `analysis/wz_index/`
  (BasicEff / CharacterEff / ItemEff / Install chairs)
- [done] `export_effect_sprites.py` extracts Effect.wz canvases with
  origin/delay metadata

### Deferred (require further extraction or design)

- [deferred] `hit` body action — needs combat/damage trigger wiring; no
  in-game source for damage events yet
- [deferred] `sit2`, `rope` body actions — low marginal value over `sit` /
  `ladder` already shipped
- [deferred] `shoot1` body action — requires bow/gun weapon swap (default
  combo wand silently omits weapon layer per v1 weapon-action compat rule)
- [deferred] Sleep "Zz" balloon overlay — not in `Effect.wz`; lives in
  `Character.wz` mob/face emote subsystem; needs separate extractor
- [deferred] Heart/aura overlays for love/excited emotes — no clean
  `Effect.wz` source found in `BasicEff`; would need `Item.wz` Cash
  consumables or `Skill.wz` particle scrub

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
- [done] Face-overlay emote architecture checkpoint recorded
  (`CHECKPOINT_2026-04-16_FACE_OVERLAY_ALIGNMENT.md`)
- [done] sit / sleep / gift / wander / visitor clips imported and wired
- [done] BehaviorEngine connected to BuddyBrain (fires events every 6s)
- [done] Vertical slice test keys for all behavior animations (S/Z/G/V/W)

## Phase 4 (Utility Layer)

- [done] Opt-in productivity tracker module
- [done] Focus celebration and break suggestion event hooks

## Remaining Blocker

- Interactive desktop verification still requires manual run (headless checks
  are complete).
