# Review Checklist

Every PR must clear this list before merge. Reviewers: request changes
if any line cannot be checked.

## Shape

- [ ] PR is small and single-purpose. Scope creep → split.
- [ ] PR body fills in Goal, Scope / Non-goals, Test evidence, Rollback
      note, Next-PR handoff, and the PR queue reference.
- [ ] PR is labeled with one `area:*` and one `type:*` label. Add
      `risk:*` labels where applicable.
- [ ] `PR_PLAN.md` entry is consistent with this PR; if the PR invents
      new scope, either revise `PR_PLAN.md` in this PR or split it out.

## Truth

- [ ] No claim of "works" is backed only by editor play. Runtime-affecting
      claims reference the exported Windows build.
- [ ] Test evidence is reproducible (commands, artifacts, or linked CI run).
- [ ] Rollback note is concrete. Data/schema implications are explicit.

## Content and provenance

- [ ] No proprietary binary assets are added. Public Maple references
      are used only for taxonomy, availability discovery, naming/state
      reference, or validation cases.
- [ ] Any derived internal resource records provenance and
      transformation notes.
- [ ] Runtime does not learn about WZ/NX schemas. Runtime consumes
      internal content packs only.

## Saves, settings, packaging

- [ ] Saves and settings paths live under `user://`.
- [ ] Schema changes include a version bump and a migration or a
      safe-regenerate path. Corruption cannot brick startup.
- [ ] Packaging-affecting changes are called out and referenced against
      `RELEASE_CHECKLIST.md`.

## V1 scope fences (`DEFERRED.md`)

- [ ] PR does not introduce free-form AI chat.
- [ ] PR does not introduce a generalized plugin / scripting runtime.
- [ ] PR does not introduce multi-character world simulation beyond the
      existing single-companion + optional visitor pattern.
- [ ] PR does not add cross-platform support work for V1.

## Merge gate

- [ ] CI is green (content validator; CI import/export smoke once PR-02 lands).
- [ ] CODEOWNERS have approved.
- [ ] PR queue order respected. If this is PR-11, PR-13 has merged first.
