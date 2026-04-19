# core_pack — V1 Content Audit

**Audited:** 2026-04-20  
**Pack version:** 1.0.0 (bumped from 0.1.1 in this PR)  
**Auditor:** J (project lead)  
**CI gate:** `validate-content` passes on all commits

---

## Audit scope

This audit confirms `core_pack` is ship-ready for V1:

- All manifest-referenced assets exist on disk.
- All actions known to the runtime (`idle`, `sit`, `sleep`, `wander`, `happy`, `gift`, `visitor`) have both animation JSON and fallback sprite.
- `bond_tiers.json` progression data is present and parseable.
- `manifest.json` validates against `ContentLoader.CONTENT_SCHEMA_VERSION = 1`.

---

## Actions coverage matrix

| Action | Animation JSON | Sprite PNG | Emote semantic |
|--------|---------------|-----------|----------------|
| `idle` | ✅ `character/animations/idle.json` | ✅ `character/idle.png` | `default` |
| `wander` | ✅ `character/animations/wander.json` | ✅ `character/wander.png` | `default` |
| `sit` | ✅ `character/animations/sit.json` | ✅ `character/sit.png` | `default` |
| `sleep` | ✅ `character/animations/sleep.json` | ✅ `character/sleep.png` | `blink` |
| `happy` | ✅ `character/animations/happy.json` | ✅ `character/happy.png` | `smile` |
| `gift` | ✅ `character/animations/gift.json` | ✅ `character/gift.png` | `love` |
| `visitor` | ✅ `character/animations/visitor.json` | ✅ `character/visitor.png` | `wink` |

No missing assets. All 7 actions fully covered.

---

## Progression data

| File | Status |
|------|--------|
| `progression/bond_tiers.json` | ✅ Present; schema valid; 3 cadence tiers; 4 unlock rows |

---

## Known extras (not referenced by manifest, not a gap)

The following assets exist in `character/` but are not referenced by the V1
manifest. They are available for future packs or states:

- `alt_idle.png` / `animations/alt_idle.json`
- `climb.png` / `animations/climb.json`
- `fly.png` / `animations/fly.json`
- `animations/stab.json`, `animations/swing.json` (combat actions, V1 deferred)

These are harmless; the runtime ignores unreferenced assets.

---

## CI validation

`validate-content` step in `runtime-smoke.yml` runs `ContentLoader.validate_manifest`
+ `validate_assets` against every pack. It must pass green before this PR merges.

---

## Result

**PASS — core_pack 1.0.0 is ship-ready for V1.**
