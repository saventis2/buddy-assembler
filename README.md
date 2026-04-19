# buddy-assembler

A Windows desktop buddy — a small, ambient companion that lives on your
screen through long work or study sessions without being noisy or
distracting.

The shipping product is the Godot runtime under `apps/runtime-godot/`.
The Python scripts at the repo root are **dev-host importer / tooling**
used to build internal content packs; they are not part of the runtime
and will move under `tools/importers/` in a later PR (see `PR_PLAN.md`
→ PR-12).

## Start here

- `PROJECT_STATUS.md` — what is landed and what is not
- `PR_PLAN.md` — ordered path to V1
- `DEFERRED.md` — explicit out-of-V1 scope
- `RELEASE_CHECKLIST.md` — release gate summary
- `docs/product/V1_PRD.md` — product intent and V1 ship criteria
- `docs/product/MILESTONE_STATUS.md` — current milestone detail

## Product runtime

- `apps/runtime-godot/` — Windows-first desktop buddy runtime
- `apps/runtime-godot/README.md` — runtime overview
- `apps/runtime-godot/README_VERTICAL_SLICE.md` — current vertical slice

## Content pack pipeline

- `packages/content-schema/` — content pack schema contract
- `packages/content-validator/` — local schema/pack validation tool
- Runtime consumes internal content packs only. The runtime does **not**
  depend on WZ/NX structures directly.

## Legacy / importer tooling (dev-host only)

These Python scripts at the repo root generate internal content from
extracted source trees. They are not part of the shipped runtime.

- `character_tooling_gui.py` — desktop GUI orchestrator
- `render_character_frame.py` — single-frame renderer
- `build_item_catalogue.py` / `build_itemwz_catalogue.py` — catalogue generators
- `diff_character_assets.py` — extracted tree diff tool
- `alignment_audit.py` — batch alignment and quality audit
- `weapon_action_compatibility_report.py` — weapon action compatibility reporting
- `analyze_npc_animation_links.py` — NPC animation + link-chain inspection
- `export_runtime_character_sprites.py` — runtime companion sprite/animation exporter
- `import_runtime_ground_tile.py` — imports map tile terrain into runtime content packs
- `analyze_character_assets.py` — reverse-engineering and dataset analysis
- `audit_dataset_metadata.py` — metadata coverage audit
- `build_wz_index.py` / `export_effect_sprites.py` — WZ catalog / Effect.wz export helpers

Run:

```powershell
python character_tooling_gui.py
```

Importer defaults may point at machine-specific Windows paths; these
will be moved into config / first-run setup as part of the PR-12
boundary cleanup.

## Deeper documentation

- `docs/REPO_INDEX.md` — indexed view of the repo
- `docs/ARCHITECTURE.md` — architecture and data flow
- `docs/WORKFLOW.md` — operator workflow guide
- `docs/product/` — PRD, decisions, execution plan, release checklist
- `docs/DEVLOGS/` — session logs

## IP / provenance posture

No WZ/NX or other proprietary binary assets are committed to this
repository. Public MapleStory v83 references are used only for
taxonomy, availability discovery, naming/state reference, and
validation cases. Any derived internal resource records provenance and
transformation notes; a provenance manifest for shipping content is
formalized in PR-13. The codebase preserves the ability to replace
Maple-derived references with non-Maple sources (PR-14 proves this
seam).
