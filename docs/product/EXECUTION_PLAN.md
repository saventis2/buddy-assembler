# Buddy Product Execution Plan

Recorded on: 2026-04-15
Owner: product/runtime track

## Goal

Ship a Windows-first desktop buddy that is delightful, non-intrusive, and
technically stable, then extend into content and utility layers.

## Scope Guardrails

- Keep MapleStory tooling behavior unchanged.
- Build companion runtime in isolated directories.
- Ship deterministic behavior first.
- Delay AI/chat features until retention is proven.

## Phase Plan

### Phase 0 - Clarification and Stabilization

- Lock decision register and V1 PRD.
- Establish runtime/content/tooling folder boundaries.
- Define content manifest contract and validator.

### Phase 1 - Runtime Core

- Transparent always-on-top overlay runtime.
- Drag and interaction loop.
- Deterministic weighted behavior loop.
- Local save/settings/world-state persistence.

### Phase 2 - Content Pipeline

- Data-driven core companion pack.
- Pack schema validation and import checks.
- Runtime-side loading contract.

### Phase 3 - Delight and Progression

- Attachment/bond level loop.
- Unlock cadence and event variability.
- Better animation/reaction coverage.

### Phase 4 - Utility Layer

- Optional focus celebration.
- Optional break suggestions with strict cooldown policy.

### Phase 5 - Future Expansion

- Optional AI layer.
- Optional social/content marketplace patterns.

## Vertical Slice Definition

Initial vertical slice is complete when all of the following are true:

1. Companion overlay appears with transparent background.
2. User can drag the companion.
3. Companion reacts to click/pet interactions.
4. Behavior loop changes state over time with cooldowns.
5. Save files persist and restore bond level and settings.
6. Core content manifest validates with local validator.

