# Buddy V1 Build Plan - Milestone Execution

## Intent

Convert the V1 product and system specs into implementation slices with clear
acceptance gates and low integration risk.

## Sequencing Rule

Use this plan as the active implementation source for buddy systems. Legacy
vertical-slice docs remain valid for runtime stability constraints.

## Milestone 1 - Identity/Mood/Bond Core (Current)

Build:

- Persistent profile/world schema v2.
- Modular identity, mood, bond, growth services with fail-soft defaults.
- Expanded behavior context weighting beyond bond-only.
- While-away summary reporting.
- Telemetry visibility for mood/trust/growth/economy counters.

Accept:

- Old saves migrate into v2 without startup break.
- Runtime still boots when optional service data is missing.
- Mood/bond/growth shifts are observable in telemetry and behavior.

## Milestone 2 - Economy Foundation (Curated WZ)

Build:

- Item/currency/reward-box schema extensions.
- Curated whitelist of WZ-derived items/effects/rates for V1.
- Crystal earn hooks for interaction/behavior events.
- First reward-box open flow with duplicate-tolerant handling.

Accept:

- User can earn crystals from multiple activity types.
- User can receive at least one item from curated box table.
- No broad ingest dependency required for release.

## Milestone 3 - World Layer Stub

Build:

- Home scene differentiation from overlay mode.
- Initial NPC cast and quest/event contract.
- Optional encounter shell integrated with existing event budget controls.

Accept:

- One quest-like flow and one encounter flow can complete with rewards.
- Skipping encounter preserves pleasant baseline loop.

## Milestone 4 - Tuning + Anti-Repetition

Build:

- Rotation and cadence tuning for lines/events/rewards.
- Preference drift and reciprocity tuning.
- Drop-rate and rarity pacing pass.

Accept:

- Short repeat sessions avoid immediate repetition fatigue.
- High-rarity pulls remain meaningful and infrequent.

## Test and Verification Gates

- Headless parse + save-store + pack validation checks pass.
- Manual desktop scenario checklist pass for interaction quality.
- Migration fixtures cover schema v1 -> v2 profile/world transforms.

## Deferred to Post-V1

- Broad WZ ingest.
- Deep AI autonomy/memory architecture.
- Complex party combat and large village simulation.
