# PR Plan — path to V1

Rules: small, single-purpose, stacked. Every PR has goal, scope,
non-goals, test evidence, rollback note, and next-PR handoff. Do not
broaden scope. Do not add AI chat, generalized plugin scripting, or
multi-character simulation for V1.

Ordering note: **PR-13 must merge before PR-11.** Everything else is as
numbered.

| PR | Title | Goal | Gate |
|----|-------|------|------|
| 00 | Buddy-first mainline identity + top-level docs | Reframe README; land PROJECT_STATUS / PR_PLAN / DEFERRED / RELEASE_CHECKLIST | Docs only; no code moves |
| 01 | Repo rails | PR template, issue templates, CODEOWNERS, labels, review checklist | Review hygiene unblocked |
| 02 | CI import/export smoke + artifacts | Every PR proves Godot import + Windows export still work | Artifacts retained |
| 03 | Durable saves/settings | Versioned schema, corruption recovery, `user://` path | Cannot brick startup |
| 04 | Pack validation + runtime fallback | Missing/invalid content degrades gracefully | Validator output readable |
| 05 | RC scenario suite | Reproducible scenario checklist covering first run, restart, drag/click, idle, sleep, visits, invalid content, corrupted settings, export launch | Another contributor can run it |
| 06 | Perf instrumentation + idle burn-in | Custom metrics; 10-min and multi-hour idle recipes; baseline recorded | Baseline logged |
| 07 | Windows packaging + release smoke | Exported build launches outside editor; writable saves; packaging layout final; signing decisions documented | Release rehearsal passes |
| 08 | First-run onboarding + quiet defaults | Quiet first run, minimal setup, clear presence controls | UX reviewed |
| 09 | Minimal bond progression | Cadence/flavor changes (not a number); data-driven tuning | Tuning tables in content |
| 10 | State transition polish | No abrupt transitions; interaction semantics consistent | Scenario regressions clean |
| 11 | First polished companion pack | One ship-ready pack; content audit complete | **Blocked by PR-13** |
| 12 | Importer boundary cleanup + schema freeze | Runtime drops WZ/NX knowledge; internal content schema explicit | Schema versioned |
| 13 | Approved-snapshot promotion + provenance | Promotion repeatable; manifest exists for shipping content | Provenance manifest merged |
| 14 | Non-Maple content lane proof | Small custom/sample pack works end-to-end | Adapter seam proven |
| 15 | Launch docs + V1 exit criteria + deferred roadmap | Known issues, support/debug, exit criteria, deferred scope | Sign-off ready |

## PR template expectation (all PRs from PR-01 onward)

- **Goal**
- **Scope / Non-goals**
- **Test evidence** (commands, artifact links, screenshots)
- **Rollback note**
- **Next-PR handoff**
