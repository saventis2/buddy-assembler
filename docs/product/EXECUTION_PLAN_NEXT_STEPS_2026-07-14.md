# Execution Plan: Next Steps + Claude Model Assignments

Written 2026-07-14. Companion to `IMPROVEMENT_BACKLOG_BUILD_SEQUENCE.md`
(the wave ordering) and `COMPANION_PET_LANDSCAPE_2026-07-14.md` (the pet
research whose candidates slot in below). This doc adds two things:
**what to do next, in order**, and **which Claude model to use for which
kind of work** — both for the agent-driven development workflow used on
this repo, and (separately, and only if ever adopted) for LLM features
inside Buddy itself.

## 1. Where things stand (2026-07-14)

- **Merged this week:** PRs #47–#52 — root-CSV relocation (#97),
  provenance CI gate (#58), golden-image render tests (#52), Godot
  upgrade migration plan (#87, doc only), shared importer library
  (#46, `wz_shared.py`), companion-pet landscape research.
- **In flight (agents running):** #44 (split `character_tooling_gui.py`
  into headless-importable modules + thin tkinter shell) and the
  7-PR Dependabot triage (4 Actions SHA bumps, 3 Python tool bumps).
- **Queued:** #47 (headless CLI mode) — starts as soon as #44 merges,
  since both rework the same file.
- **Waiting on a human with Windows:** RC scenario suite run (#85) and
  perf burn-in (#77) against the exported build; review of
  `GODOT_UPGRADE_MIGRATION_PLAN.md` before any upgrade work starts.

## 2. Next steps, in order

### Batch A — finish the current wave (this week)
1. **#44 lands** → merge → **launch #47** (headless CLI for every GUI
   operation, built on the new operation-layer modules + `wz_shared`).
2. **Dependabot verdicts land** → merge the safe ones, leave findings
   open for maintainer review.
3. Nothing else new until these close — same one-file-one-owner rule
   that has kept this whole run conflict-free.

### Batch B — last of the Wave 2 infrastructure
4. **#69 typed-GDScript pass, incrementally.** Now unblocked (#98 lint
   tooling and #76 architecture doc both exist). Do it file-by-file in
   small PRs — never repo-wide in one shot — starting with the leaf
   scripts the dependency graph in #76 shows have no dependents, ending
   with `buddy_overlay.gd`. Headless parse + test suite is the only
   verification surface available to agents, so keep each PR small
   enough to eyeball.
5. **#59 schema semver** — sequence before any Wave 3 item that adds
   manifest fields, per the build-sequence doc.

### Batch C — Wave 3 product work (needs maintainer taste, agent labor)
6. **#18 personality presets** and **#23 tuning tables** first — the two
   intra-wave infrastructure items several others build on.
7. Then the flavor tier: **13/14/16/20/24** on top of #18; **19/22/40**
   on top of #23; **#25 → #26** in that order.
8. **Pet-research candidates slot in here:** A1 (status-glyph thought
   bubble) and A4 (milestone celebrations) pair naturally with #23's
   tuning tables; A2 (idle eye-tracking) is standalone runtime work; B1
   (deterministic first-run identity) attaches to FIRST_RUN_ONBOARDING;
   B3 (speech-redaction rule) is a one-paragraph doc constraint —
   cheapest item on this list, do it with the next docs PR.
9. **A3 (coding-agent awareness) gets a design one-pager only** — no
   code until the maintainer approves the state vocabulary and adapter
   shape; sequence the pager after #59.

### Batch D — gated / human-dependent
10. **Godot 4.6.3 upgrade** — only after the maintainer reviews the plan
    doc; then one upgrade PR, then #1 (tray icon) as a separate
    follow-up, then #28.
11. **RC suite + perf burn-in** — human-on-Windows; unblocks the release
    checklist, not agent work.

## 3. Which Claude model for which work (dev workflow)

Context: this repo is developed by Claude Code sessions that spawn
background subagents per task. The orchestrating session's model is
chosen in the app; each subagent can be pinned to `haiku`, `sonnet`,
`opus`, or `fable` (unpinned = inherits the orchestrator). Current
lineup and list pricing (per 1M tokens, as of 2026-07):

| Model | ID | Input / Output | Niche |
|---|---|---|---|
| Claude Fable 5 | `claude-fable-5` | $10 / $50 | Hardest long-horizon, most demanding reasoning |
| Claude Opus 4.8 | `claude-opus-4-8` | $5 / $25 | Default for capable agentic coding |
| Claude Sonnet 5 | `claude-sonnet-5` | $3 / $15 (intro $2 / $10 through 2026-08-31) | Near-Opus coding quality at lower cost |
| Claude Haiku 4.5 | `claude-haiku-4-5` | $1 / $5 (200K context) | Fast, simple, high-volume |

Assignments, matched to the batches above:

- **Orchestrator session** (planning, merging, conflict-safety,
  recovering dead agents): **Fable 5 or Opus 4.8.** This is where
  judgment concentrates — sequencing, PR review, deciding what *not*
  to do. A practical note from this very session: we hit the session
  usage cap four times running everything (orchestrator + all
  subagents) on the top-tier model. Pushing routine subagent work down
  a tier is the single biggest lever to stop that.
- **Behavior-preservation refactors** (#44, #47, the #69 typed-GDScript
  PRs): **Opus 4.8**, effort high/xhigh. These need the
  read-everything-first discipline and identity-proof verification the
  shared-library PR set as precedent. Fable 5 only if an Opus attempt
  produces a PR that fails its own parity harness.
- **Research/plan documents** (Godot plan, A3 design pager, future
  landscape docs): **Opus 4.8.** Web-research + synthesis is squarely
  its lane; Fable 5 is justified when the doc must reason about risk
  across the whole codebase at once.
- **Well-specified mechanical tasks** (Dependabot-style bumps, CSV/doc
  moves, adding a lint rule, B3's doc paragraph): **Sonnet 5.** At
  intro pricing this is ~5x cheaper than Fable per output token, and
  these tasks are exactly the "clear spec, low ambiguity" shape Sonnet 5
  handles at near-Opus quality.
- **Wave 3 flavor/content authoring** (preset dialogue lines, tuning
  table values, encounter flavor under #18/#23): **Sonnet 5** for
  volume drafting, with the **maintainer (not a bigger model) as the
  taste gate** — tone is a product decision, per the influence
  backlog's tone rubric.
- **High-volume validation/classification chores** (e.g. sweeping 83
  asset folders for metadata anomalies, bulk-checking manifest fields):
  **Haiku 4.5** — but note its 200K context; chunk the input rather
  than feeding whole trees.
- **Code review of agent PRs:** **Opus 4.8** with a coverage-first
  instruction ("report everything, filter downstream") — newer models
  follow conservative-reporting filters literally, which silently
  lowers recall.

Rules of thumb: pin subagents *down* a tier from the orchestrator by
default and promote only on failure; give every agent its full task
spec in one turn (all current models reward up-front specification);
keep one-file-one-owner scheduling regardless of model.

## 4. If Buddy itself ever calls Claude (not committed — design notes only)

Nothing in V1 calls any LLM at runtime, and nothing here changes that.
But two pet-landscape findings (Claude Buddy's LLM personality, OpenPets'
MCP speech bridge) make it worth pre-registering the model fit *if* the
maintainer ever opts in:

- **Runtime flavor speech** (short one-liners in the thought bubble,
  latency-sensitive, high frequency): **Haiku 4.5** — the only tier
  where per-interaction cost is negligible; cache the system/persona
  prefix; hard-cap `max_tokens` (~60). Must sit behind B3's redaction
  rule and an offline fallback to canned lines (the app must never
  require network).
- **Build-time content generation** (drafting a content pack's dialogue
  set or a generated buddy from a description, hatch-pet style):
  **Sonnet 5** via the Batches API (50% off, not latency-sensitive) —
  outputs land in the normal pack pipeline, so the validator +
  provenance gate (not the model) are the quality floor.
- **Nothing in Buddy needs Opus/Fable at runtime.** If a feature seems
  to, that's a sign it belongs in the dev/authoring pipeline, not the
  shipped app.

## 5. Standing constraints (unchanged)

- DEFERRED.md fence stays: 64/91/92/93 remain out of sequencing.
- Provenance/promotion applies to all imported or generated content.
- Anything touching the overlay's Windows behavior ultimately gates on
  the human RC pass — CI cannot observe it.
