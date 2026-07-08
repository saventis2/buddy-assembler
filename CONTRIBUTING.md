# Contributing

This repo ships a Windows desktop buddy app. The shipping runtime is the
Godot 4.2 project under `apps/runtime-godot/`; the Python scripts at the
repo root are dev-host importer/tooling used to build internal content
packs and are not part of the runtime.

## Start here

Before opening an issue or PR, read README.md's "Start here" list:

- `PROJECT_STATUS.md` — what is landed and what is not
- `PR_PLAN.md` — ordered path to V1
- `DEFERRED.md` — explicit out-of-V1 scope
- `RELEASE_CHECKLIST.md` — release gate summary
- `docs/product/V1_PRD.md` — product intent and V1 ship criteria
- `docs/product/MILESTONE_STATUS.md` — current milestone detail

If what you want to work on isn't already queued in `PR_PLAN.md`, check
`DEFERRED.md` first — some things (free-form AI chat, a generalized
plugin/scripting runtime, multi-character world simulation beyond the
existing single-companion + optional visitor pattern, cross-platform
support for V1) are explicitly out of scope and won't be accepted.

## Dev environment

- **Python tooling** (importer scripts under `tools/importers/`): `pip
  install -r requirements.txt` (currently just `Pillow`). Entry point is
  `python tools/importers/character_tooling_gui.py`; see
  `docs/WORKFLOW.md` for the operator flow.
- **Godot runtime**: the shipping runtime is pinned to **Godot 4.2**
  (see `config/features` in `apps/runtime-godot/project.godot`). Use a
  matching Godot 4.2 editor/console build.
- **Headless checks**: before proposing a runtime change, run

  ```powershell
  pwsh ./apps/runtime-godot/tests/run_headless_checks.ps1
  ```

  This verifies the project parses cleanly and runs the smoke
  floor-lock and save-store durability tests. Add `--profile` to also
  run the frame-time profiling scene.

## How to propose a change

PRs in this repo follow the rules in `PR_PLAN.md`:

> small, single-purpose, stacked. Every PR has goal, scope,
> non-goals, test evidence, rollback note, and next-PR handoff.

In practice:

- Keep each PR scoped to one concern. If you find yourself listing many
  scope bullets in the PR body, split it into multiple stacked PRs.
- If your change isn't already a numbered entry in `PR_PLAN.md`'s
  table, either add it there or call it out explicitly as an ad hoc
  improvement outside the numbered queue.
- Respect PR queue ordering where it's called out (e.g. `PR_PLAN.md`
  currently requires PR-13 to merge before PR-11).
- Fill in every section of `.github/pull_request_template.md`: **Goal**,
  **Scope / Non-goals**, **Test evidence**, **Rollback note**,
  **Next-PR handoff**, and **PR queue reference**. Reviewers will bounce
  PRs that skip a section.
- "Works in editor" is not sufficient evidence for runtime-affecting
  changes — the exported Windows build is the release truth. Link a CI
  run or attach an artifact where possible.
- Label the PR with one `area:*` and one `type:*` label, plus `risk:*`
  labels where applicable.

## Code review expectations

Every PR is checked against `docs/REVIEW_CHECKLIST.md` before merge,
covering PR shape, evidence/truth standards, content and provenance
rules, saves/settings/packaging safety, the V1 scope fences in
`DEFERRED.md`, and the merge gate (CI green, CODEOWNERS approval, queue
order respected). Read it before you open a PR — reviewers will request
changes against any unchecked line.

See `.github/CODEOWNERS` for who owns review of which paths.

## IP / provenance posture

See README.md's "IP / provenance posture" section. In short: no WZ/NX
or other proprietary binary assets are committed to this repository,
and public MapleStory v83 references are used only for taxonomy,
availability discovery, naming/state reference, and validation cases.
Any PR that touches content derivation must keep to that posture; see
`docs/REVIEW_CHECKLIST.md`'s "Content and provenance" section for the
specific checks reviewers apply.

## Reporting issues

Use the existing issue templates rather than a blank issue (blank
issues are disabled):

- **Bug report** (`.github/ISSUE_TEMPLATE/bug.yml`) — runtime or
  importer misbehavior. State whether you saw it in the exported
  Windows build or in editor play; the exported build is the release
  truth.
- **Content / pack issue** (`.github/ISSUE_TEMPLATE/content.yml`) — a
  content pack, animation, overlay, or asset looks wrong or missing.
- **Release / packaging issue** (`.github/ISSUE_TEMPLATE/release.yml`)
  — problems with the Windows export, packaging, saves, or release
  smoke.

Before filing, check `PROJECT_STATUS.md` and `PR_PLAN.md` in case the
item is already known or already queued (see the contact links on the
issue chooser).

## Licensing

This repository does not currently declare a license. Licensing terms
are a decision reserved for the repo owner; by submitting a
contribution you agree it may be used under whatever license terms the
repo owner subsequently sets for the project.
