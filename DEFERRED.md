# Deferred from V1

These are intentionally **not** in scope for V1. Do not reopen in a PR
unless the V1 exit criteria in `PR_PLAN.md` are signed off.

## Product scope fences

- Free-form AI chat (no LLM integration in V1).
- Generalized plugin / runtime scripting surface.
- Multi-character world simulation beyond the existing single-companion +
  optional visitor pattern.
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
