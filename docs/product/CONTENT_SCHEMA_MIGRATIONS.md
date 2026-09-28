# Content Pack Schema — Migration Notes

This file records every change to the content-pack manifest schema
(`packages/content-schema/buddy-pack.schema.json`), one entry per version.
The versioning policy (what patch, minor, and major bumps mean, and how the
validator and runtime react to each) is in
[`CONTENT_SCHEMA.md` → Schema versioning](CONTENT_SCHEMA.md#schema-versioning-semver-contract).

**Every schema version bump MUST add an entry here in the same PR.**
`packages/content-validator/test_validate_pack.py` fails if the validator's
`CURRENT_SCHEMA_SEMVER` has no `## <version>` heading in this file.

Newest entries go first. Each entry uses this template:

```markdown
## X.Y.Z — <short title>

- **Bump kind:** patch | minor | major
- **Changes:** what was added, removed, or tightened (field paths).
- **Pack author action:** what an existing pack must do (for a minor bump,
  usually "none; optionally adopt field X").
- **Runtime / validator:** matching code changes (constants bumped, new checks).
- **Shipped packs migrated:** yes/no, and which ones.
```

---

## 1.0.0 — Baseline semver contract

- **Bump kind:** baseline (first versioned release of the existing V1 schema).
- **Changes:** Added required string field `schemaSemver` (`"1.0.0"`),
  alongside the existing integer `schemaVersion`, which is now defined as
  the schema major. Every other field keeps the shape it had before this
  entry. The validator now also rejects `schemaVersion` values other than
  the supported major (1). Before this change it accepted any integer
  ≥ 1, even though the runtime rejected values above 1.
- **Pack author action:** add `"schemaSemver": "1.0.0"` next to
  `"schemaVersion": 1`. The runtime ignores the new field, so packs that
  lack it still load at runtime. They fail only `validate_pack.py`.
- **Runtime / validator:** No runtime change. `content_loader.gd` already
  rejects `schemaVersion > CONTENT_SCHEMA_VERSION` and ignores unknown
  keys. The validator gained `SUPPORTED_SCHEMA_MAJOR = 1`,
  `CURRENT_SCHEMA_SEMVER = 1.0.0`, and the newer-minor warning.
- **Shipped packs migrated:** yes: `core_pack`, `night_pack`, `sample_pack`.
