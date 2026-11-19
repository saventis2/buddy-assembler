# Plan 10 — WZ Ingest Pipeline (Controlled Batches)

Updated: 2026-04-23

## Goal

Scale content ingest from local WZ extraction in safe, reviewable chunks without
committing the original WZ library to git.

## Source Path (local only)

- Default WZ root used by tooling:
  - `C:/Users/GGPC/OneDrive/Desktop/83 complete/Base.wz`
- This path stays external to the repository.

### Important: Super-root Layout

In this project, `Base.wz` is an extracted super-root that already contains:

- `Character/`
- `Item/`
- `String/`
- and other major content groups.

This means extracting `83/*.wz` into separate sibling folders under
`83 complete` is usually redundant for ingest and can duplicate data.

## One-command Batch Ingest

Run from repo root:

```powershell
python apps/runtime-godot/tools/run_wz_ingest_batch.py --batch-size 250 --batches 1 --categories gear
```

Common variants:

```powershell
# Ingest mixed progression categories
python apps/runtime-godot/tools/run_wz_ingest_batch.py --batch-size 300 --categories gear,food,materials

# Dry-run (preview add phase only)
python apps/runtime-godot/tools/run_wz_ingest_batch.py --batch-size 300 --categories gear --dry-run --skip-checks
```

## What the pipeline does

1. Sync missing catalog items from `item_bindings_full.csv` into manifest.
2. Import icon files for manifest items from the WZ root.
3. Run headless checks (unless `--skip-checks`).
4. Emit a JSON summary report:
   - `docs/product/WZ_INGEST_LAST_RUN.json`

## Category Control

`sync_manifest_items_from_bindings.py` now supports:

- `--categories gear,food,materials`

This limits what gets added in that batch while preserving existing items.

## Review Protocol

After each ingest batch:

1. Inspect manifest/item delta.
2. Run headless checks.
3. Smoke-test inventory in runtime (`I`) and paper-doll readout.
4. Commit only repository assets/metadata (never the external WZ source tree).

## Notes

- This workflow assumes `item_bindings_full.csv` is already generated.
- If icon mismatch appears, run targeted repairs before next batch.
- If ingest delta is `0` repeatedly, treat source as saturated and pivot to
  runtime/content improvements instead of forced re-extraction.
