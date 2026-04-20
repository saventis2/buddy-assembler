# Buddy Runtime Modularity and Failure-Isolation Plan

## Goal

Ensure module-level failures do not crash the full companion loop.

## Module Boundaries

- `IdentityService`: persistent individuality and preference drift.
- `MoodService`: current emotional state transitions.
- `BondService`: relationship progression and trust.
- `GrowthService`: stage and stat progression.
- `EconomyService`: wallet, inventory, reward transactions, box rolls.
- `ReportService`: while-away summary generation.

`AppState` is orchestrator only; it should not own feature-specific logic when a
module exists.

## Failure-Isolation Rules

- Service load is optional; missing module triggers warning and default behavior.
- Service return values must be validated before state write-back.
- If a service returns invalid shape, keep prior state and continue loop.
- Preserve deterministic core behavior when higher layers degrade.

## Data Contracts

- Profile and world-state schema versions are explicit and migrated.
- Service methods receive plain dictionaries and return dictionary output.
- No service can assume external modules are available.

## Rollout Strategy

1. Add modules and keep old behavior-compatible defaults.
2. Route `AppState` paths through modules with fallback.
3. Expand telemetry to reveal module outputs.
4. Add migration + runtime tests before broader feature growth.

## Guardrails

- Do not couple gameplay logic to renderer internals.
- Do not couple reward economy to one content source.
- Keep broad ingest optional; curated whitelists are release-safe path.
