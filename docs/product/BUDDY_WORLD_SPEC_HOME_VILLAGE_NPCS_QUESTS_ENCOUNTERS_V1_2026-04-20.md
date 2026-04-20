# Buddy World Spec - Home, Village, NPCs, Quests, Encounters (V1)

## Purpose

Define the first playable world layer that supports identity, mood, bond, and
economy without introducing brittle dependencies.

## V1 Outcomes

- Home mode exists and is clearly distinct from overlay mode.
- User can see at least one decor/reward object represented in home context.
- User can encounter at least one named NPC and complete one quest-like flow.
- User can trigger or skip a lightweight encounter and still keep core loop stable.

## World Model

### Home

- Single scene profile with "cozy starter room" baseline.
- Decor integration is slot-based in V1 (`wall`, `floor`, `display`) to avoid free-form
  placement complexity.
- Home mood hints derive from current buddy mood plus last routine summary.

### Village (Implied in V1)

- Not fully explorable in V1.
- Represented as event layer and NPC visit stream.
- Each village event includes: source NPC, tone tag, optional reward payload.

### NPCs

Initial cast:

- `Mira` (mentor): training nudges, growth-flavored quests.
- `Pip` (friend): social/bond prompts, gift-oriented quests.
- `Rook` (rival): optional encounter hooks and challenge quests.

Per-NPC minimum fields:

- `id`, `name`, `role`, `affinity`, `availability`, `dialoguePool`.

## Quest/Event System

### Quest Categories in V1

- Daily care.
- Bond moments.
- Training milestone.
- Home upkeep.
- Village errand.

### Quest Contract (Runtime)

- `id`, `type`, `requirements`, `rewards`, `repeatability`, `narrativeText`.
- Rewards can include crystals, items, mood impact, and NPC affinity delta.

### Event Rotation Rules

- Avoid immediate repeat of the same quest ID.
- Enforce per-hour/per-day budget (already supported by event bucket tracking).
- Favor unresolved or underused categories when possible.

## Encounter System (Optional)

- Encounters are skippable and never block care loop.
- Resolution model is lightweight: `engage` or `skip`.
- Early encounter output:
  - `engage`: crystal/material reward and mood/bond variation.
  - `skip`: neutral or low-impact outcome, no penalty spike.

## Cross-System Links

- Identity influences NPC flavor text and quest weighting.
- Mood influences encounter prompt tone and quest suggestion style.
- Bond influences trustful/personal lines and optional higher-tier quests.
- Economy provides reward payloads for quests/encounters and home objects.

## Acceptance Criteria

- Entering home mode shows at least one world-state signal.
- One NPC interaction path can complete and reward properly.
- One encounter path can resolve without breaking overlay state.
- World events rotate with visible variety over short repeated sessions.
