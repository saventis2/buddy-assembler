# PR Architecture Checklist

Use this checklist before merging any PR into `main`.

---

## Architecture Invariants (must-never-violate)

These are hard constraints. A PR that violates any of these should not merge.

- [ ] **No Maple-specific code in `apps/runtime-godot/`**
  The runtime only speaks BIF (buddy intermediate format). All Maple-specific transforms stay in Python tooling or `tools/converter/`. The runtime must remain format-agnostic.

- [ ] **Content packs are data-only**
  `manifest.json` and associated content files contain no logic. Behavior lives in GDScript; content packs supply IDs, paths, and parameters only.

- [ ] **Cache invalidated on skin swap**
  Any PR that changes character skin, actor definition, or appearance at runtime must call `buddy_actor.on_skin_swap()` (or `animation_controller.invalidate_all()` directly) to prevent stale cached frames.

- [ ] **`buddy_overlay.gd` stays self-contained**
  The overlay script must not import from `scenes/vertical_slice/` or `runtime/`. Its dependencies are `scripts/behavior/`, `scripts/content/`, `scripts/encounters/`, `scripts/utility/`, and `scripts/autoload/` only.

- [ ] **BIF importer is format-version gated**
  If the BIF schema changes, bump `FORMAT_VERSION` in `buddy_importer_plugin_import.gd` and document the migration.

---

## Per-Area Checklist

### Tooling (`render_character_frame.py`, `export_runtime_character_sprites.py`, GUI)

- [ ] `python -m py_compile` passes on all modified `.py` files
- [ ] Existing batch export output is unaffected (run a test render and spot-check)
- [ ] No machine-specific absolute paths introduced without a config/arg fallback

### Runtime (`apps/runtime-godot/scripts/`, `runtime/`)

- [ ] Headless check passes: `pwsh ./apps/runtime-godot/tests/run_headless_checks.ps1`
- [ ] Smoke floor-lock test passes (included in above)
- [ ] No `print()` calls left in non-test code (use `push_warning` / `push_error` for diagnostics)
- [ ] No new `@export` vars added to `buddy_overlay.gd` that break headless startup

### Content Pipeline (`content/`, `tools/`)

- [ ] Content promotion verified (from repo root — the script's defaults are
      cwd-relative and silently skip otherwise; also enforced in CI by the
      `verify-provenance` job in `content-validator.yml`):
      `python apps/runtime-godot/tools/verify_content_promotion.py --intermediate-dir apps/runtime-godot/content/intermediate --promotion-log apps/runtime-godot/content/promotion_log.json`
- [ ] If new `.bif` files added: run `approve_content_snapshot.py` and commit `promotion_log.json`
- [ ] Pack manifests validated: `python packages/content-validator/validate.py content/core_pack/manifest.json`

### Tests

- [ ] New behavior has at least one test (smoke test, headless scene, or documented scenario checklist item)
- [ ] `SCENARIO_CHECKLIST.md` updated if a new interactive behavior was added

---

## Pre-Merge Gates

| Gate | Command | Required |
|------|---------|----------|
| Headless parse + smoke test | `pwsh ./apps/runtime-godot/tests/run_headless_checks.ps1` | Yes |
| Python syntax check | `python -m py_compile <changed files>` | Yes |
| Content promotion check | `python apps/runtime-godot/tools/verify_content_promotion.py --intermediate-dir apps/runtime-godot/content/intermediate --promotion-log apps/runtime-godot/content/promotion_log.json` (CI: `verify-provenance` job) | Yes (if content changed) |
| Pack validation | `python packages/content-validator/validate.py ...` | Yes (if manifest changed) |
| Interactive vertical-slice run | Manual — see `SCENARIO_CHECKLIST.md` | Before milestone releases |

---

## Architecture Summary (quick reference)

```
buddy-assembler/
├── apps/runtime-godot/          # Godot 4 runtime (format-agnostic)
│   ├── scripts/                 # Overlay logic (buddy_overlay.gd + autoloads)
│   ├── runtime/                 # Vertical slice runtime (actor, world, etc.)
│   ├── content/                 # Content packs (data only)
│   │   ├── core_pack/           # Default character pack
│   │   ├── night_pack/          # Second content pack
│   │   └── intermediate/        # BIF files awaiting Godot import
│   ├── tools/                   # Python tooling (BIF conversion, promotion)
│   ├── tests/                   # Headless test scenes and scripts
│   └── addons/buddy_importer/   # BIF → .tres Godot importer plugin
│
├── packages/
│   ├── content-schema/          # JSON schema contract for packs
│   └── content-validator/       # CLI validator for manifests
│
└── (MapleStory tooling scripts) # Python tooling — isolated from runtime
```
