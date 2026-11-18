# Deferred from V1

These are intentionally **not** in scope for V1. Do not reopen in a PR
unless the V1 exit criteria in `PR_PLAN.md` are signed off.

## Product scope fences

- Free-form AI chat: **reopened 2026-11-16** by Plan 13 (scope-reopen,
  updated together with `docs/product/V1_PRD.md`). Ordinary chat text gets an
  in-character reply from an optional local Ollama model, and the buddy
  chooses its own name. Commands never reach the model, and the model's
  output is only ever shown as cleaned text. Still deferred: hosted or cloud
  models, voice, and the model doing anything beyond words and the buddy's
  existing choices. See `docs/product/PLAN13_TOWN_AND_CONVERSATION.md`.
- Generalized plugin / runtime scripting surface.
- Multi-character world simulation beyond the existing single-companion +
  optional visitor pattern. Narrowed 2026-11-17 by D-007 (Plan 14, updated
  together with `docs/product/V1_PRD.md`): a buddy that starts small lives
  alone, and the six town characters, their quests and encounters are switched
  off for it and kept as an archive. Other characters stay deferred to a later
  plan. Also, from 2026-11-18 (D-010): a watchdog that keeps the world host
  running is deferred to the move to Nexus. And from 2026-11-18 (D-012): the
  buddy is told nothing about its world, and what it says on the land is
  checked against its own memory; from 2026-11-19 (step 2c-1) letters you write
  arrive and are read at its console, and its writing back stays deferred to
  step 2c-2.
- Cross-platform parity (macOS, Linux, mobile).
- Marketplace or user-submitted content hosting.

## Content / animation deferrals (from `docs/product/MILESTONE_STATUS.md`)

- `hit` body action — requires combat/damage trigger wiring.
- `sit2`, `rope` body actions — low marginal value over `sit` / `ladder`.
- `shoot1` body action — requires bow/gun weapon swap; default combo
  wand silently omits weapon layer per the v1 weapon-action compat rule.
- Sleep "Zz" balloon overlay — not in `Effect.wz`.
- Heart/aura overlays for love/excited emotes — no clean Effect.wz
  source.

## Engineering deferrals

- Code signing and notarization beyond "decision documented" in PR-07.
- Auto-update channel.
- Telemetry beyond opt-in local perf metrics.
- Cloud save.
- Replacement of current Maple83 folder/asset dependency with a fully
  independent default content lane (must be planned as an explicit migration,
  not an incidental cleanup).

## Re-entry rule

A deferred item may return to scope only via: (1) a closed V1 with
published exit criteria, or (2) an explicit scope-reopen PR that
updates this file and `docs/product/V1_PRD.md` together.
