# buddy-assembler

A desktop MapleStory character tooling suite for working with extracted `Base.wz` assets.

At the moment this repo is focused on:
- building item catalogues from extracted character data
- rendering single composed character frames
- exporting animation frame sequences, GIFs, and sprite sheets
- diffing two extracted `Character.wz` trees
- auditing alignment, fallback, and metadata quality
- reporting weapon-to-action compatibility from source assets

The current operator workflow is:
1. Generate or load a catalogue
2. Apply item IDs to a build
3. Render a single frame
4. Batch export a full action or action set
5. Run audit or diff tools when validating output

## Main entrypoint

The primary operator entrypoint is the desktop GUI:

```powershell
python character_tooling_gui.py
```

## Main scripts

- `character_tooling_gui.py` — desktop GUI orchestrator
- `render_character_frame.py` — single-frame renderer
- `build_item_catalogue.py` — catalogue generator
- `diff_character_assets.py` — extracted tree diff tool
- `alignment_audit.py` — batch alignment and quality audit
- `weapon_action_compatibility_report.py` — weapon action compatibility reporting
- `analyze_character_assets.py` — reverse-engineering and dataset analysis
- `audit_dataset_metadata.py` — metadata coverage audit

## Documentation

- `docs/REPO_INDEX.md` — indexed view of the repo and what each file does
- `docs/ARCHITECTURE.md` — architecture, data flow, and current structural notes
- `docs/WORKFLOW.md` — practical operator workflow guide
- `docs/DEVLOGS/Session-Log-2026-04-15.md` — copied devlog location for future cleanup

## Current state

This repo already has real functionality, but it is still early in its public-facing structure.

Things to be aware of:
- some script defaults currently point at machine-specific Windows paths
- the GUI file is large and currently acts as the main orchestration layer
- the repo name is broader than the current MapleStory-specific implementation

## Suggested next cleanup steps

- move machine-specific defaults into config or first-run setup
- split the GUI into smaller modules by tab or feature area
- move session logs into a dedicated `docs/` or `devlogs/` area
- add an install/dependency file if one is not yet present

## Notes

This project assumes you are working with an extracted MapleStory `Base.wz` tree and related XML/PNG asset folders.
