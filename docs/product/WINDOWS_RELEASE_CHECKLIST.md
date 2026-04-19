# Windows Release Checklist

## Build

1. Export runtime from Godot using Windows preset.
2. Verify executable launches without editor installed.
3. Verify default save path (`user://`) is writable.

## Validation

1. Run content validator against all shipping manifests.
2. Run runtime scenario checklist from `apps/runtime-godot/tests/SCENARIO_CHECKLIST.md`.
3. Confirm no crash on missing/invalid pack selection fallback.

## Performance

1. Capture idle CPU and memory after 10 minutes.
2. Capture idle CPU and memory after 3 hours.
3. Confirm no noticeable input lag while companion is active.

## Packaging

1. Include runtime README and known limitations.
2. Include rollback/revert steps for previous release.
3. Tag release and archive exact content manifests shipped.

