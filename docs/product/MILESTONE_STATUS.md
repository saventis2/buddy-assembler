# Milestone Status

Updated: 2026-04-23 (Plan 9 inventory/progression/drop coupling)

> Update (2026-04-20): buddy-system milestone tracking is now coordinated with
> `BUDDY_V1_BUILD_PLAN_MILESTONE_EXECUTION_2026-04-20.md` for identity/economy/world
> sequencing beyond vertical-slice runtime polish.
>
> Execution todo queue now tracked in:
> `BUDDY_TODO_EXECUTION_QUEUE.md`

## Plan 12A (Autonomous Mind, offline) - 2026-11-15

- [done] `mind_service.gd`: unprompted decisions every 10 min (rest / visit / explore / tend home / reflect)
- [done] Drives reuse mood modifiers; per-subject feelings learned from each experience
- [done] Catch-up of decisions missed while closed (capped at 8)
- [done] First-person journal (`/journal`), spoken thought + acted-out animation, silent in quiet hours
- [done] `autonomyEnabled` setting (default on); `MindServiceTest` (8 cases) in required headless suite
- [open] Notes left for the buddy, visible places: see `PLAN12_AUTONOMOUS_MIND.md`

## Plan 13 (Town and conversation) - 2026-11-16

- [done] A1 town as data: eight places with hours, activities and residents; the mind picks real places and companions
- [done] B1 conversation: free chat through the local model, the buddy chooses its own name, "Talks back" setting
- [done] B2 graph memory: facts and talk summaries in the save, recalled into chat, Menu > Memory to see and forget them, "Remembers you" setting
- [done] B3 talk changes the buddy: suggestions it decides on and carries out, talks as events, a hello with news when the chat opens
- [done] C1+C2 part 1: wants it notices in town, saves for, buys and wears; a day plan it follows; `/wants`
- [open] A2 town map, A3 changing town, C1+C2 part 2 (asking you, a Wants window, projects), C4 reflection, C5 making things

## Plan 12B (Thinking model via local Ollama) - 2026-11-15

- [done] `mind_thinker.gd`: request builder, strict reply parser and sanitiser
- [done] Overlay sends each live decision to Ollama; reply rewrites the journal entry and is spoken
- [done] Model's `want` gives a one-off bonus to the next decision
- [done] Silent fallback to built-in wording when Ollama is absent or misbehaves
- [done] Settings `mindModelEnabled` / `mindModelUrl` / `mindModelName` (default `gemma3:4b`)
- [done] `MindThinkerTest` (9 cases) in required headless suite; end-to-end run against a stand-in server
- [open] Run against a real Ollama server and judge wording and latency

## Integration (2026-11-15)

- [done] `feature-to-next-pass` (Stats/Inventory/Wardrobe, economy tuning, WZ item bindings) merged with `main` (Gate 0, gate authority, tooling split)
- [done] Required headless suite green on pinned Godot 4.2.2 (14 tests); Python lint/type/test and content/shipping validators green
- [open] Windows export + RC scenario suite on the merged build not yet re-run

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
- [done] Added `WorldEconomyFlowTest` coverage for quest/encounter/recycle loops

## Plan 5 (Manual Desktop Verification Gate — 2026-04-21)

- [in_progress] Automated pre-check gate passed via `run_headless_checks.ps1`
- [done] Manual checklist runbook/log created:
  `PLAN5_MANUAL_VERIFICATION_LOG_2026-04-21.md`
- [done] Added guided manual checklist logger:
  `apps/runtime-godot/tests/run_manual_checklist.ps1`
- [done] Added one-command Plan 5 gate runner:
  `apps/runtime-godot/tests/run_plan5_gate.ps1`
- [done] Added in-runtime manual snapshot export (`F1`) with prompt-cadence evidence counters
- [done] Added `ManualVerificationReportTest` and wired it into headless checks
- [done] Fixed gate-runner gap: now auto-launches runtime + vertical-slice sessions for manual checks
- [done] Fixed default manual checklist log output path to repo `docs/product/`
- [done] Added pet interaction progression feedback text (bond XP/level/unlock delta)
- [done] Added explicit pack-cycle feedback text for `F9` actions
- [done] Added vertical-slice `M` speech trigger and immediate bracket-duration validation path
- [done] Switched vertical-slice key handling to `_input` for stronger hotkey reliability
- [done] Interactive desktop confirmation (TO track) PASS=16 / FAIL=0 / PENDING=0
- [done] Plan 5 gate status: PASS

## Plan 6 (Companion Depth Foundation — 2026-04-20)

- [done] Added activity-state context (`focused`, `idle`, `late_session`) from productivity tracker
- [done] Added interaction-intensity + quiet-strictness knobs to behavior/encounter weighting
- [done] Added user-facing support hints for focus/break/late-session events
- [done] Added continuity digest memory in profile + continuity hint line on resume
- [done] Added `CompanionDepthTest` coverage and wired it into headless checks
- [done] Added cadence ordering regression for `eventFrequency` (`low < normal < high`)
- [done] Added prompt-frequency setting + auto-prompt cadence guard with deferred world prompt display
- [done] Added `PromptCadenceTest` and wired it into headless checks
- [done] Added hourly productivity-hint cap and regression coverage for non-intrusive cadence
- [done] Final manual UX pass confirms hint cadence is non-intrusive in desktop usage

## Plan 7 (Economy Tuning Pass 2 — 2026-04-20)

- [done] Added duplicate recycle cap tied to reward-box cost (anti-exploit)
- [done] Added low-value streak protection for reward-box opens
- [done] Added per-theme reward-box open telemetry (`box_open_stats`)
- [done] Surfaced theme-open telemetry + pulled rarity in overlay debug readout
- [done] Added `EconomyTuningTest` and wired it into headless checks

## Plan 8 (World Variety Expansion — 2026-04-20)

- [done] Expanded manifest/world defaults with additional NPC cast (Tala, Quill, Fenn)
- [done] Added home-upkeep and social quest categories to world content rotation
- [done] Added optional encounter variants with distinct reward profiles
- [done] Upgraded anti-repeat picker to avoid recent category-group reuse (not only ID reuse)
- [done] Added `WorldVarietyTest` and wired it into `run_headless_checks.ps1`

## Plan 9A (WZ Equipment Data Spine — 2026-04-23)

- [done] Extended canonical WZ map builder to ingest Character equipment rows
- [done] Added equip-slot mapping in canonical bindings output
- [done] Rebuilt `item_bindings_full.csv/json` with gear category rows included
- [done] Synced manifest via full bindings add-missing path (+gear rows)
- [done] Imported icons for full manifest rows with `missing=0`

## Plan 9C (Progression Consistency — 2026-04-23)

- [done] Added load-time XP->level reconciliation via bond service
- [done] Added stat-point reconciliation floor (earned minus spent)
- [done] Exposed XP progress fields to telemetry/stats snapshots
- [done] Updated `/status` and stats window with XP progress + next unlock hint
- [done] Added targeted progression regression checks (`ProgressionConsistencyTest`)

## Plan 9B (Inventory/Paper-Doll Expansion — 2026-04-23)

- [done] Expanded inventory paper-doll panel into grouped Maple-style slot families
- [done] Added group-level unequip controls for combat/style/accessory slot groups
- [done] Kept item-level use/equip/unequip actions while broadening equipped-state visibility

## Plan 9D (Job/Drop Coupling Upgrade — 2026-04-23)

- [done] Added `job_drop_bias` propagation from manifest jobs into profile state
- [done] Included `job_primary_stat` + `job_drop_bias` in encounter drop-roll context
- [done] Upgraded drop weighting using job affinity, category bias, primary-stat, and slot hints
- [done] Added economy regression case validating context-sensitive drop bias

## Plan 10A (Controlled WZ Ingest Pipeline — 2026-04-23)

- [done] Added category-scoped manifest sync via `--categories`
- [done] Added batch ingest JSON reporting (`WZ_INGEST_LAST_RUN.json`)
- [done] Documented repeatable ingest flow in `PLAN10_WZ_INGEST_PIPELINE.md`

## Plan 10B (Content Expansion Batches — 2026-04-23)

- [in_progress] Execute first category-bounded ingest batch and validate runtime behavior
- [done] First bounded ingest dry-run executed (`gear`, delta=0, report emitted)
- [done] First non-dry-run bounded ingest executed (`food,materials`, delta=0)
- [done] Headless verification gate passed post-ingest (no regressions)

## Plan 10C (Next Expansion Source Pass — 2026-04-23)

- [in_progress] Regenerate/expand canonical source bindings to discover net-new ingest rows
- [done] Rebuilt canonical bindings from current source set (`rows=11122`)
- [done] Verified saturation on sync dry-run (`added_items=0`)
- [done] Added multi-root canonical ingest support in tooling
- [done] Confirmed current extracted `Base.wz` is super-root (contains Character/Item/String/etc)
- [done] Closed duplicate-extraction branch for active planning

## Plan 11A (Runtime Depth from Existing Dataset — 2026-04-23)

- [in_progress] Shift execution focus from ingest expansion to runtime depth/clarity improvements
- [done] Improved cadence visibility in TO/settings and setting-change speech feedback
- [done] Added progression readability in stats window (session deltas + upcoming unlock preview)
- [done] Added inventory quick iteration controls (sort cycling + quick activate/use/unequip)
- [done] Headless verification gate passed after runtime UI updates

## Plan 11B (TO Manual UX Verification Sweep — 2026-04-23)

- [in_progress] Run manual TO UX sweep focused on cadence/progression/inventory quick controls

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
- [deferred] Face-emote metadata and debug semantics exist, but the variant
  PNGs are not part of the tracked v0.1 shipping closure. The portable runtime
  preserves the embedded composed frames and does not draw replacement faces.
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
