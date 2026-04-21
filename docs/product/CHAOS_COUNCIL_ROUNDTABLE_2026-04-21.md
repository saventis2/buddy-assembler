# Chaos Council Roundtable - Interaction Core (TO)

Date: 2026-04-21  
Scope: TO Interaction Core evolution (chat + command loop + visible feedback)  
Council: Product, UX, Runtime, Gameplay, Economy, AI/Conversation, QA, Performance, Content, Player Advocate

Rubric: Impact (I), Feasibility (F), Risk (R), Composite = I + F - R
Decision tags: Accept, Hold, Reject, Merge

## Session 1 - Chat UX Flow and Friction

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Add persistent chat toggle button near buddy hitbox. | Obj: visual clutter. Obj: accidental opens. Def: improves discoverability. Def: helps non-hotkey users. | I4 F5 R2 C7 | Add compact icon with hover tooltip and cooldown on reopen. | Accept |
| 2 | Auto-open chat on first buddy line each session. | Obj: intrusive. Obj: steals focus. Def: teaches feature. Def: once-per-session only. | I3 F5 R3 C5 | Show one-time toast: "Press Open Chat" instead of forced open. | Merge |
| 3 | Add unread badge on chat button when buddy spoke recently. | Obj: notification fatigue. Obj: extra state. Def: reduces missed prompts. Def: subtle red dot only. | I4 F4 R2 C6 | Badge only for world/support prompts, not idle chatter. | Accept |
| 4 | Add quick-reply chips (Yes/No/Later) above input. | Obj: UI density. Obj: premature complexity. Def: boosts response rate. Def: keyboard optional. | I4 F3 R3 C4 | Limit chips to prompt-linked moments only. | Hold |
| 5 | Keep chat window position across restart. | Obj: stale off-screen positions. Obj: extra save plumbing. Def: continuity. Def: already saving other windows. | I3 F4 R2 C5 | Clamp to screen bounds on load. | Accept |
| 6 | Add conversation separator when long idle gap detected. | Obj: visual noise. Obj: no direct gameplay value. Def: readability improves. Def: cheap to implement. | I3 F5 R1 C7 | Insert separator after 10+ minutes silence only. | Accept |
| 7 | Add "pin chat" mode (always visible). | Obj: heavy distraction. Obj: edge cases with multi-monitor. Def: power-user value. Def: optional toggle. | I2 F3 R3 C2 | Defer; emulate with reopen shortcut first. | Reject |
| 8 | Add text-size options (S/M/L) for chat window. | Obj: setting bloat. Obj: localization unknown. Def: accessibility. Def: low risk. | I4 F4 R2 C6 | Start with M/L only, no global font system change. | Accept |
| 9 | Add clear-chat button with confirm. | Obj: accidental loss. Obj: low priority. Def: declutters long sessions. Def: simple safeguard. | I3 F5 R1 C7 | Keep session transcript cap + optional clear. | Accept |
| 10 | Add onboarding micro-walkthrough (3 steps). | Obj: too early polish. Obj: maintenance overhead. Def: conversion gains. Def: optional skip. | I3 F3 R2 C4 | Replace with single contextual hint this phase. | Merge |

## Session 2 - Intent Parsing and Command Design

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Prioritize slash commands before NLP intents. | Obj: not natural UX. Obj: developer-centric. Def: deterministic behavior. Def: easy debugging. | I5 F5 R1 C9 | Keep slash-first with phrase aliases for natural input. | Accept |
| 2 | Add strict command grammar with usage errors. | Obj: brittle to typos. Obj: harsh UX. Def: predictable execution. Def: safer actions. | I4 F5 R2 C7 | Add fuzzy suggestions for nearest command. | Accept |
| 3 | Add alias dictionary for common phrasing. | Obj: maintenance burden. Obj: ambiguity growth. Def: user-friendly. Def: still deterministic map. | I5 F4 R2 C7 | Scope aliases to top 20 phrases. | Accept |
| 4 | Permit multi-command input in one line. | Obj: parser complexity. Obj: abuse/spam. Def: efficiency for power users. Def: can gate later. | I2 F2 R4 C0 | Keep single action per message for now. | Reject |
| 5 | Add command preview mode (`/do ?`). | Obj: unnecessary. Obj: extra parser surface. Def: reduces accidental actions. Def: good for new users. | I3 F3 R2 C4 | Add `/help` examples instead of preview parser. | Merge |
| 6 | Add cooldown on repeating same command quickly. | Obj: could block legit retries. Obj: hidden behavior. Def: anti-spam. Def: protects loops. | I4 F5 R1 C8 | 300ms per command key + user-facing notice. | Accept |
| 7 | Add unknown-intent fallback categories. | Obj: generic responses feel fake. Obj: complexity creep. Def: prevents dead ends. Def: supports guidance. | I4 F5 R1 C8 | Route unknowns to help/status suggestion matrix. | Accept |
| 8 | Add negative confirmation for destructive commands. | Obj: slows flow. Obj: none destructive now. Def: future-safe pattern. Def: consistency. | I2 F4 R1 C5 | Apply only to clear-chat currently. | Accept |
| 9 | Add command telemetry with success/fail reason. | Obj: noisy metrics. Obj: storage overhead. Def: critical for tuning. Def: low cost counters. | I5 F5 R1 C9 | Track by command + reason code only. | Accept |
| 10 | Add locale-aware parser now. | Obj: premature. Obj: no localization infra. Def: global users eventually. Def: reduces rewrite later. | I2 F2 R3 C1 | Keep parser English-first with clean extensibility hooks. | Hold |

## Session 3 - Buddy Response Quality and Tone

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Create tone matrix by mood x bond tier. | Obj: authoring load. Obj: risk inconsistency. Def: personalization boost. Def: core fantasy support. | I5 F4 R2 C7 | Start with 5 moods x 3 bond bands templates. | Accept |
| 2 | Add anti-repetition n-gram suppression for replies. | Obj: could force awkward phrasing. Obj: extra state. Def: avoids robotic loops. Def: measurable quality gain. | I4 F4 R2 C6 | 20-turn recent phrase blacklist with soft fallback. | Accept |
| 3 | Add empathy mirror for user sentiment words. | Obj: false positives. Obj: uncanny tone risks. Def: stronger companionship. Def: deterministic keyword map possible. | I4 F3 R3 C4 | Keep to small safe lexicon (stress/tired/proud). | Hold |
| 4 | Add "ask one follow-up" behavior after vague messages. | Obj: can feel pushy. Obj: may spam questions. Def: encourages true back-and-forth. Def: controllable cadence. | I4 F4 R2 C6 | Max one follow-up every 3 turns. | Accept |
| 5 | Distinguish system action replies vs social replies visually. | Obj: visual complexity. Obj: low value. Def: clarity for commands. Def: reduces confusion. | I3 F5 R1 C7 | Prefix action replies with subtle icon/tag. | Accept |
| 6 | Add occasional proactive check-ins from chat context. | Obj: interruption risk. Obj: noisy. Def: feels alive. Def: cadence already exists. | I3 F4 R3 C4 | Only during active chat window and low frequency. | Hold |
| 7 | Add confidence score and fallback if low. | Obj: overengineering deterministic map. Obj: not needed now. Def: prevents wrong action execution. Def: safer parser path. | I4 F4 R1 C7 | Use confidence gate only for action intents. | Accept |
| 8 | Add mini persona traits in response style. | Obj: stereotyped writing. Obj: extra authoring. Def: identity growth alignment. Def: replay value. | I4 F3 R2 C5 | Tie to top_trait only when confidence high. | Accept |
| 9 | Add support boundary rules (no manipulative guilt). | Obj: response constraints might feel flat. Obj: policy overhead. Def: user trust. Def: prevents bad UX. | I5 F5 R1 C9 | Encode banned response patterns and tests. | Accept |
| 10 | Add "response rationale" debug toggle. | Obj: immersion break. Obj: clutter. Def: tuning speed. Def: QA visibility. | I3 F4 R1 C6 | Telemetry-only debug panel, not user-facing by default. | Accept |

## Session 4 - Memory Model (Session now, Persistence later)

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Keep transcript in-memory ring buffer only. | Obj: loses history on restart. Obj: weak continuity. Def: safest now. Def: no schema risk. | I4 F5 R1 C8 | Cap 120 lines + rolling truncation notice. | Accept |
| 2 | Add memory tags per user turn (goal, mood, task). | Obj: classification errors. Obj: overhead. Def: better replies/actions. Def: deterministic map feasible. | I4 F4 R2 C6 | Start with 6 tags, no freeform summaries yet. | Accept |
| 3 | Add “session summary” generated every 20 turns. | Obj: might hallucinate context. Obj: unnecessary in deterministic phase. Def: better long-session recall. Def: cheap template summaries. | I3 F3 R3 C3 | Generate only structured counters, no prose summary. | Merge |
| 4 | Add "remember this" pin command (session). | Obj: command creep. Obj: UX confusion. Def: user agency. Def: useful for tasks/plans. | I4 F4 R2 C6 | `/remember <short note>` with 10-note cap. | Accept |
| 5 | Add implicit memory decay weights. | Obj: tuning burden. Obj: hidden behavior. Def: keeps context relevant. Def: avoids stale bias. | I3 F4 R2 C5 | Recent turns weight x2; tags decay by age buckets. | Accept |
| 6 | Add memory inspection command (`/memory`). | Obj: privacy concerns if shared screen. Obj: clutter. Def: transparency. Def: debugging essential. | I4 F5 R1 C8 | Show compact tags + pinned notes only. | Accept |
| 7 | Add correction command (`/forget <id>`). | Obj: index UX awkward. Obj: accidental deletions. Def: control over context. Def: cleanup support. | I3 F4 R2 C5 | Add confirmation for forget command. | Accept |
| 8 | Add cross-session persistence now. | Obj: out-of-scope risk. Obj: migration complexity. Def: continuity is core fantasy. Def: users expect memory. | I5 F2 R4 C3 | Document as next phase with schema proposal. | Hold |
| 9 | Add privacy mode to disable memory capture. | Obj: setting bloat. Obj: less personalization. Def: trust and compliance. Def: simple toggle. | I4 F5 R1 C8 | Respect existing support/productivity toggles + memory toggle. | Accept |
| 10 | Add memory quality metrics dashboard. | Obj: too technical. Obj: maintenance overhead. Def: tuning value high. Def: reuse telemetry panel. | I3 F4 R1 C6 | Add minimal counters only. | Accept |

## Session 5 - Menu Controls and Visible Effect Fidelity

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Add immediate visual confirmation for each settings change. | Obj: noisy bubble spam. Obj: duplicate with menu text. Def: confirms effect. Def: trust in controls. | I5 F5 R1 C9 | Use concise toast in chat + telemetry delta line. | Accept |
| 2 | Add live cadence indicator panel (events/prompts). | Obj: debug-heavy look. Obj: cognitive load. Def: makes hidden changes visible. Def: fixes current complaint directly. | I5 F4 R2 C7 | Optional "advanced" foldout in settings/chat. | Accept |
| 3 | Add per-setting explanation hover text. | Obj: UI busy. Obj: low impact. Def: onboarding aid. Def: reduces misuse. | I3 F4 R1 C6 | Tooltips only, no extra static text blocks. | Accept |
| 4 | Replace cycle buttons with explicit dropdowns. | Obj: larger refactor. Obj: keyboard parity work. Def: clarity. Def: less trial-and-error. | I4 F3 R3 C4 | Keep cycles now, add current+next preview text. | Merge |
| 5 | Add "test prompt now" button per cadence source. | Obj: can skew stats. Obj: test-only semantics confusing. Def: immediate verification. Def: excellent QA tool. | I4 F5 R1 C8 | Mark outputs as [demo] and exclude from reward logic. | Accept |
| 6 | Add applied-setting diff log in chat. | Obj: transcript noise. Obj: low player value. Def: auditability. Def: helps debugging. | I3 F4 R1 C6 | Keep last 5 setting changes only via `/status`. | Accept |
| 7 | Add setting presets (Cozy/Balanced/Deep profiles). | Obj: overlaps existing intensity. Obj: hidden overrides confusion. Def: one-click behavior bundles. Def: simplifies tuning. | I4 F4 R2 C6 | Presets set multiple fields with preview before apply. | Accept |
| 8 | Add reset-to-default per category. | Obj: accidental reset risk. Obj: extra buttons. Def: recoverability. Def: fast troubleshooting. | I4 F5 R1 C8 | Add confirm dialog and undo window (10s). | Accept |
| 9 | Add animation speed setting tied to intensity. | Obj: could break authored timing. Obj: quality risk. Def: makes intensity more visible. Def: perceived responsiveness. | I3 F2 R4 C1 | Defer; keep state frequency changes only. | Reject |
| 10 | Add settings health check (`/settings-check`). | Obj: command clutter. Obj: low player use. Def: catches invalid combos. Def: QA utility. | I3 F4 R1 C6 | Include in debug/help, not default surface. | Accept |

## Session 6 - Prompt Cadence, Spam Control, Quiet Behavior

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Split cooldowns per source (support/world/chat). | Obj: complexity. Obj: tuning burden. Def: avoids source starvation. Def: better control. | I5 F4 R2 C7 | Keep global floor + per-source additive cooldown. | Accept |
| 2 | Add burst budget per 10-minute window. | Obj: may mute urgent prompts. Obj: hidden caps. Def: anti-spam core. Def: predictable rate ceiling. | I5 F5 R1 C9 | Source-specific budgets + override for critical world events. | Accept |
| 3 | Quiet strict mode suppresses all non-critical prompts. | Obj: dead-feeling buddy. Obj: too silent. Def: user respect. Def: expected strict behavior. | I4 F5 R1 C8 | Preserve only direct user replies and command results. | Accept |
| 4 | Lenient quiet mode still allows low-frequency support hints. | Obj: inconsistent with quiet concept. Obj: user confusion. Def: avoids total silence. Def: aligns with lenient label. | I3 F5 R1 C7 | Add clear wording in menu for each quiet mode. | Accept |
| 5 | Add adaptive cooldown when user ignores 3 prompts. | Obj: might hide useful prompts. Obj: behavior opacity. Def: respects disengagement. Def: reduces annoyance. | I4 F4 R2 C6 | Cooldown multiplier decays back after interaction. | Accept |
| 6 | Add "Do not disturb for 30m" command. | Obj: overlaps quiet hours. Obj: yet another toggle. Def: immediate control. Def: practical during calls. | I4 F4 R1 C7 | `/dnd 30` temporary override with countdown. | Accept |
| 7 | Add explicit prompt categories in each message. | Obj: immersion loss. Obj: visual noise. Def: transparency. Def: helps tuning. | I3 F4 R1 C6 | Category tags only in chat popout, not bubble. | Accept |
| 8 | Penalize repeated identical prompt templates. | Obj: template pool size low. Obj: may force weak alternatives. Def: anti-repetition. Def: measurable improvement. | I4 F4 R2 C6 | Maintain recent-template blacklist of 6. | Accept |
| 9 | Add late-session compassion mode (shorter, quieter tone). | Obj: tone branching complexity. Obj: subjective quality. Def: matches context. Def: better user fit. | I4 F4 R2 C6 | Activate after lateSession + strict/lenient mapping. | Accept |
| 10 | Add cadence debug command (`/cadence`). | Obj: player-facing complexity. Obj: low use. Def: QA speed and trust. Def: minimal implementation. | I3 F5 R1 C7 | Keep accessible through chat only. | Accept |

## Session 7 - Reward and World Command Loop Integration

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Add conversational reward open: "open cozy box". | Obj: parser ambiguity. Obj: accidental spend. Def: high delight. Def: obvious value. | I5 F4 R2 C7 | Require confirmation when crystals below threshold. | Accept |
| 2 | Add world resolve command with explicit mode. | Obj: too many variants. Obj: user confusion. Def: deterministic control. Def: maps existing F12 behavior. | I5 F5 R1 C9 | `/world engage|skip|complete` canonical form. | Accept |
| 3 | Add pre-action status preview before spend/resolve. | Obj: extra verbosity. Obj: slows flow. Def: prevents mistakes. Def: trust boost. | I4 F4 R1 C7 | Preview only when risk/high-cost. | Accept |
| 4 | Add post-action summary line with deltas. | Obj: repetitive text. Obj: overlap telemetry. Def: visible progress. Def: motivating feedback. | I5 F5 R1 C9 | Standardized delta format (+crystals, item, bond). | Accept |
| 5 | Add rollback for failed action side-effects. | Obj: already mostly atomic. Obj: complexity. Def: safety guarantees. Def: future-proof. | I4 F3 R2 C5 | Add transaction wrapper helper and error code mapping. | Accept |
| 6 | Add command shortcut for pending checks (`/pending`). | Obj: low novelty. Obj: one more command. Def: practical. Def: improves discoverability of tasks. | I4 F5 R1 C8 | Show quest+encounter status + suggested command. | Accept |
| 7 | Add item explanation command (`/item <id|name>`). | Obj: parser ambiguity for names. Obj: content dependency. Def: improves reward meaning. Def: encourages collection. | I4 F4 R2 C6 | Support last-earned item alias first. | Accept |
| 8 | Allow chat to trigger monitor move (F8 equivalent). | Obj: surprising side-effect. Obj: possible annoyance. Def: accessibility alternative. Def: deterministic command possible. | I2 F4 R3 C3 | Defer monitor/system commands out of interaction scope. | Reject |
| 9 | Add command-level permission guard. | Obj: overkill offline app. Obj: complexity. Def: protects future multi-actor actions. Def: safer boundaries. | I3 F3 R2 C4 | Keep simple allowed-action registry, no auth stack. | Merge |
| 10 | Add world auto-suggestion after idle prompt. | Obj: could feel pushy. Obj: prompt fatigue. Def: reduces dead ends. Def: contextual guidance. | I4 F4 R2 C6 | Suggest only when pending exists and chat is open. | Accept |

## Session 8 - Telemetry, Observability, Debug Surface

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Track chat turn metrics in telemetry snapshot. | Obj: minor overhead. Obj: metric sprawl. Def: core interaction KPI. Def: needed for tuning. | I5 F5 R1 C9 | Add counts + last turn timestamp only. | Accept |
| 2 | Track command success/fail with reason codes. | Obj: too technical for UI. Obj: extra maintenance. Def: fast bug triage. Def: parser tuning data. | I5 F5 R1 C9 | Keep compact reason enum set. | Accept |
| 3 | Add `/debug chat` summary command. | Obj: user confusion. Obj: command clutter. Def: power QA tool. Def: non-invasive surface. | I3 F5 R1 C7 | Hidden from default help; shown in advanced help. | Accept |
| 4 | Add rotating log file for chat actions. | Obj: disk writes/privacy. Obj: cleanup complexity. Def: repro aid. Def: postmortem utility. | I3 F3 R3 C3 | Keep memory-only debug unless explicit export command. | Hold |
| 5 | Add one-click telemetry snapshot export from chat. | Obj: duplicates F1 path. Obj: clutter. Def: chat-centric workflow. Def: useful for testers. | I4 F4 R1 C7 | `/snapshot` command calls existing exporter. | Accept |
| 6 | Add runtime warning banner for fallback paths used. | Obj: immersion break. Obj: non-user friendly. Def: catches content load regressions quickly. Def: critical for QA. | I3 F4 R2 C5 | Show banner only when telemetry/debug enabled. | Accept |
| 7 | Add setting change events to telemetry timeline. | Obj: verbose. Obj: minor value. Def: root-cause analysis. Def: confirms user actions. | I4 F5 R1 C8 | Keep last 20 events ring buffer. | Accept |
| 8 | Add chat quality score estimate (heuristic). | Obj: noisy metric. Obj: subjective. Def: can detect poor loops. Def: guides iteration. | I3 F3 R2 C4 | Defer until baseline command telemetry stabilizes. | Hold |
| 9 | Add command latency measurement. | Obj: micro-optimization. Obj: mostly local operations. Def: catches stalls. Def: cheap timer wrapper. | I3 F5 R1 C7 | Measure parse+execute elapsed ms by command. | Accept |
| 10 | Add error budget target for command failures. | Obj: process overhead. Obj: too formal. Def: shipping discipline. Def: clear quality bar. | I4 F4 R1 C7 | Set target <2% non-user-caused command fails. | Accept |

## Session 9 - Failure Modes and Recovery

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Standardize error object for all command actions. | Obj: refactor cost. Obj: existing mixed returns. Def: consistency. Def: easier handling/tests. | I5 F4 R2 C7 | Introduce adapter layer first, full migration later. | Accept |
| 2 | Graceful handling for empty/whitespace input. | Obj: trivial. Obj: low impact. Def: polish and robustness. Def: avoids junk logs. | I3 F5 R1 C7 | Ignore input silently unless repeated; then hint. | Accept |
| 3 | Handle unknown pack/content state during commands. | Obj: edge case heavy. Obj: complexity. Def: current known risk area. Def: avoids hard failures. | I4 F4 R2 C6 | Fallback response + suggest `/status`. | Accept |
| 4 | Add retry guidance when command fails. | Obj: repetitive text. Obj: might mask real errors. Def: better UX recovery. Def: reduces frustration. | I4 F5 R1 C8 | Include one actionable next step only. | Accept |
| 5 | Add command timeout guard (e.g., 1s). | Obj: local ops usually instant. Obj: extra plumbing. Def: prevents lockups from future calls. Def: safe default. | I3 F4 R2 C5 | Timeout wrappers for world/reward calls only. | Accept |
| 6 | Add crash-safe behavior if chat window node missing. | Obj: unlikely in production scene. Obj: code noise. Def: defensive coding. Def: test resilience. | I3 F5 R1 C7 | Null-safe fallbacks already present; add test coverage. | Merge |
| 7 | Add duplicate-send guard on Enter spam. | Obj: might block fast users. Obj: timing sensitivity. Def: avoids accidental double actions. Def: common UX issue. | I4 F4 R1 C7 | Debounce send for 150ms and disable button briefly. | Accept |
| 8 | Add state reconciliation after restart relaunch. | Obj: partial state already saved. Obj: complexity. Def: restart reliability issue history. Def: user trust. | I4 F4 R2 C6 | Validate key settings on boot and warn on mismatch. | Accept |
| 9 | Add fallback to bubble-only if chat window fails. | Obj: hides underlying issue. Obj: incomplete experience. Def: keeps core companion alive. Def: graceful degradation. | I4 F5 R1 C8 | Emit telemetry warning + one-time user notice. | Accept |
| 10 | Add explicit tests for all command failure codes. | Obj: test maintenance load. Obj: might slow iteration. Def: prevents regressions. Def: high confidence shipping. | I5 F4 R1 C8 | Table-driven test matrix for parser+executor. | Accept |

## Session 10 - Prioritization, Sequencing, MVP Cut Lines

| Round | Proposal | Debate (Objections / Defenses) | Judgment | Upgrade | Decision |
|---|---|---|---|---|---|
| 1 | Phase A: command router + chat loop hardening first. | Obj: less flashy. Obj: user-visible novelty delayed. Def: foundation required. Def: reduces rework. | I5 F5 R1 C9 | Include one visible feature each phase for momentum. | Accept |
| 2 | Phase B: settings visibility and cadence diagnostics. | Obj: debug-heavy for users. Obj: UI expansion risk. Def: addresses current trust gap. Def: immediate clarity gain. | I5 F4 R2 C7 | Keep advanced diagnostics collapsible. | Accept |
| 3 | Phase C: tone/memory polish and anti-repetition. | Obj: may feel like polish only. Obj: slower to quantify. Def: key to perceived "alive" quality. Def: retention impact. | I4 F4 R2 C6 | Tie to measurable repeat-rate and turn-depth metrics. | Accept |
| 4 | Cut multi-command parser from MVP. | Obj: power-users lose speed. Obj: less ambitious. Def: cuts risk sharply. Def: clearer UX. | I4 F5 R1 C8 | Revisit after stable command telemetry. | Accept |
| 5 | Cut cross-session memory from MVP. | Obj: continuity reduced. Obj: user expectation mismatch. Def: avoids migration risk now. Def: matches prior scope lock. | I4 F5 R1 C8 | Keep explicit roadmap item with schema draft next phase. | Accept |
| 6 | Cut monitor/system control commands from chat. | Obj: less complete command set. Obj: some accessibility loss. Def: avoids unsafe side effects. Def: keeps focus on interaction core. | I3 F5 R1 C7 | Keep keyboard/system controls outside chat for now. | Accept |
| 7 | Keep `/help`, `/status`, `/pending`, `/reward`, `/world`, `/mode` in MVP. | Obj: command count still high. Obj: learning curve. Def: high utility set. Def: maps current runtime features. | I5 F4 R1 C8 | Add concise categorized help output. | Accept |
| 8 | Define MVP quality gates before next merge. | Obj: gate overhead. Obj: potential delay. Def: avoids churn. Def: objective ship criteria. | I5 F5 R1 C9 | Require parser tests + manual scenario pass. | Accept |
| 9 | Require player-advocate review on final copy tone. | Obj: slows iteration. Obj: subjective edits. Def: reduces uncanny/annoying lines. Def: preserves buddy fantasy. | I4 F4 R1 C7 | One focused copy pass at end of Phase C. | Accept |
| 10 | Freeze MVP after 2 consecutive green gates + user validation. | Obj: can postpone desired extras. Obj: strict cutoff. Def: prevents endless scope creep. Def: enables ship momentum. | I5 F5 R1 C9 | Freeze and branch for post-MVP experiments. | Accept |

---

## Ranked Backlog (Top 20)

| Rank | Item | Score Context | Decision |
|---|---|---|---|
| 1 | Slash-first deterministic router + aliases | high impact, high feasibility, low risk | Accept |
| 2 | Per-source prompt cooldown + burst budgets | directly reduces spam/fatigue | Accept |
| 3 | Command telemetry (ok/fail + reason) | enables reliable tuning | Accept |
| 4 | Immediate visible feedback for settings changes | addresses trust gap in controls | Accept |
| 5 | Standardized action result object | consistency + testability | Accept |
| 6 | Tone matrix by mood x bond | stronger personalization | Accept |
| 7 | Anti-repetition phrase suppression | prevents robotic responses | Accept |
| 8 | `/pending` status + suggestion | reduces dead-end interactions | Accept |
| 9 | Post-action delta summary format | makes progression visible | Accept |
| 10 | Session memory tags + `/memory` inspect | better conversational continuity | Accept |
| 11 | `/remember` and `/forget` session notes | user agency over context | Accept |
| 12 | Chat unread badge (prompt-only) | discoverability without noise | Accept |
| 13 | Settings presets + reset/undo | easier behavior tuning | Accept |
| 14 | Follow-up question cadence limiter | enables real dialogue feel | Accept |
| 15 | Quiet-mode strict behavior clarity | user respect + predictability | Accept |
| 16 | Error/retry guidance templates | smoother recovery path | Accept |
| 17 | Command latency telemetry | reliability signal | Accept |
| 18 | Duplicate-send debounce | avoids accidental repeats | Accept |
| 19 | Transcript clear with confirm | session hygiene | Accept |
| 20 | Text-size accessibility options | readability improvement | Accept |

## Decision Register (Accepted / Hold / Rejected)

### Accepted (high-priority)
- Deterministic command router with aliases and confidence gate for action intents.
- Session-only memory system with tags, inspect, remember/forget commands.
- Visible settings-effect confirmations and advanced cadence diagnostics.
- Prompt anti-spam budgets, per-source cooldowns, adaptive ignore backoff.
- World/reward command integration with standardized action-result payloads.
- Telemetry expansion for chat turns, command results, latency, and settings timeline.
- Failure-safe handling and table-driven command error tests.

### Hold (explicitly deferred)
- Cross-session memory persistence and rolling prose summaries.
- Full locale-aware parser.
- Proactive check-ins outside active chat window.
- Chat quality heuristic score and on-disk rotating chat logs.

### Rejected (this phase)
- Multi-command single-line parser.
- Pin-chat always-on mode as default UX path.
- Animation speed coupling to intensity.
- Chat-driven monitor/system commands.

## Implementation Order (for next execution pass)

1. Router foundation and result-object unification.
2. Command set MVP (`/help`, `/status`, `/pending`, `/mode`, `/reward`, `/world`, `/quiet`, `/freq`, `/chat close`).
3. Session memory tags + inspect/remember/forget.
4. Cadence budget split + anti-spam + quiet strict behavior.
5. Settings visibility layer (toast/chat deltas + optional diagnostics).
6. Tone matrix + anti-repetition + follow-up cadence.
7. Telemetry and test matrix hardening.

## Open Risks and Mitigations

1. Alias ambiguity causes wrong action.  
Mitigation: command confidence gate + explicit confirmation for risky actions.

2. Chat spam from command/result loops.  
Mitigation: per-command debounce + prompt budgets + source cooldowns.

3. Response tone inconsistency across mood states.  
Mitigation: authored tone matrix + copy pass + test fixtures.

4. Hidden behavior still confusing users.  
Mitigation: visible setting deltas and `/status` clarity output.

5. Regression risk in world/reward command actions.  
Mitigation: unified result object + table-driven error tests + telemetry reason codes.

## Cut List (out of this implementation slice)

- Persistent memory across sessions.
- LLM-backed open-ended responses.
- Multi-command parsing.
- Full localization parser.
- Always-on pinned chat UI mode.
