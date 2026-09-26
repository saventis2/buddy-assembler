# Content Pack Schema — V1

**Schema version:** 1.0.0 (`schemaSemver`; major 1 = `schemaVersion`)  
**Runtime constant:** `ContentLoader.CONTENT_SCHEMA_VERSION` (major only)  
**Migration notes:** [`CONTENT_SCHEMA_MIGRATIONS.md`](CONTENT_SCHEMA_MIGRATIONS.md)

The runtime only speaks the internal pack format described here. WZ/NX and all
MapleStory-specific formats are handled exclusively by importer tooling
(the Python scripts under `tools/importers/`, relocated there from the
repo root in PR-12 — see `README.md`) which produces content conforming
to this spec. The runtime has no WZ/NX awareness.

---

## Directory layout

```
content/<pack_id>/
  manifest.json          # required
  character/             # sprite / animation assets
  character_visitor/     # optional visitor-character assets
  effects/               # optional overlay effects
  terrain/               # optional ground tile
  ui/                    # optional UI chrome
  progression/           # optional progression override (e.g. bond_tiers.json)
```

---

## manifest.json

```json
{
  "schemaVersion": 1,
  "schemaSemver": "1.0.0",
  "runtimeAudience": "user",
  "id": "<pack_id>",
  "name": "<display name>",
  "version": "<semver>",
  "companion": {
    "id": "<companion_id>",
    "displayName": "<display name>",
    "traits": ["calm", "playful"]
  },
  "visual": {
    "faceMode": "embedded",
    "scale": 2.35,
    "anchor": [0.5, 1.0],
    "animations": {
      "<action>": "character/animations/<action>.json"
    },
    "sprites": {
      "<action>": "character/<action>.png"
    },
    "groundTile": {
      "path": "terrain/ground.png",
      "tileX": true,
      "scale": 1.0,
      "alpha": 1.0,
      "align": "top",
      "floorOffset": 0.0,
      "xOffset": 0.0,
      "surfaceYPx": 0.0
    },
    "faceOverlays": {
      "manifestPath": "character/emotes/manifest.json"
    }
  },
  "idleActions": ["idle", "sit", "wander"],
  "reactionActions": ["happy"],
  "encounterActions": ["gift", "visitor"],
  "eventRules": [
    {
      "id": "<event_id>",
      "action": "<action>",
      "trigger": "random",
      "weight": 1.0,
      "per_hour": 1,
      "per_day": 4
    }
  ]
}
```

### Required fields

| Field | Type | Notes |
|-------|------|-------|
| `schemaVersion` | integer | Schema major; must equal `CONTENT_SCHEMA_VERSION` (currently 1) |
| `schemaSemver` | string | Full `MAJOR.MINOR.PATCH` schema revision (currently `1.0.0`); major must equal `schemaVersion`. See *Schema versioning* |
| `runtimeAudience` | string | Optional; `user` (default) or `development` |
| `id` | string | Matches directory name |
| `name` | string | Display name |
| `version` | string | Semver |
| `companion` | object | See above |
| `idleActions` | array | At minimum `["idle"]` |
| `reactionActions` | array | Played on user interactions |
| `eventRules` | array | May be empty |

### Optional fields

| Field | Type | Notes |
|-------|------|-------|
| `visual` | object | If omitted or unusable, the tracked core idle asset is used |
| `encounterActions` | array | Actions playable via event rules |
| `items` | array | Optional runtime item definitions (id, category, rarity, theme) |
| `currencies` | object | Optional currency defaults (for V1, usually `crystals`) |
| `rewardBoxes` | array | Optional themed reward-box definitions |
| `home` | object | Optional home scene + decor slot defaults |
| `npcs` | array | Optional NPC cast (`id`, `name`, `role`, `dialoguePool`) |
| `quests` | array | Optional quest pool with `rewards` payload |
| `encounters` | array | Optional encounter pool with engage/skip rewards |

`visual.faceMode` is `embedded`, which renders the approved composed character
asset without adding replacement face or eye graphics. If selected visual
content is missing or unusable, the runtime displays the tracked
`res://content/core_pack/character/idle.png` asset fully inside the viewport.
Asset paths must be pack-relative or `res://`; drive-letter,
filesystem-absolute, `user://`, traversal, missing, ignored, and untracked
dependencies fail validation.

`runtimeAudience: development` packs are absent from the normal user cycle.
Developers can exercise them from a source checkout with
`--allow-development-packs`; release exports omit their resources.

### Curated WZ whitelist note (V1)

- Runtime can consume curated item rows through `items` in the pack manifest.
- For V1, use a controlled shortlist (`sourceType: "wz_whitelist_v1"`) and avoid broad ingest.
- `rewardBoxes[].possibleItems` should reference these curated IDs.

---

## Schema versioning (semver contract)

The manifest schema is versioned with [semver](https://semver.org/)
`MAJOR.MINOR.PATCH`. A manifest declares two fields that must agree:

- `schemaSemver` (string): the full schema revision the pack was authored
  against, e.g. `"1.0.0"`. Digits only; no `v` prefix, leading zeros, or
  pre-release/build suffix.
- `schemaVersion` (integer): the major of `schemaSemver`. This is the only
  part the runtime reads (`ContentLoader.CONTENT_SCHEMA_VERSION`).

The newest revision the tooling knows is `CURRENT_SCHEMA_SEMVER` in
`packages/content-validator/validate_pack.py` (currently `1.0.0`).
`SUPPORTED_SCHEMA_MAJOR` in the same file must equal the runtime's
`CONTENT_SCHEMA_VERSION`; a unit test fails if the two drift.

### What each kind of bump means

| Bump | Allowed changes | Examples |
|------|-----------------|----------|
| **Patch** (`1.0.x`) | No change to what is valid. Documentation, clarified wording, and hint text only. | Fixing a typo in this doc; improving a validator error hint. |
| **Minor** (`1.x.0`) | Additive and backward-compatible only: **new optional fields**, or new values accepted where older packs stay valid. Every pack valid under `1.N` stays valid under `1.N+1`, and a runtime that ignores the new field still loads the pack correctly. | A new optional manifest field (e.g. an optional `minimum_runtime_version`, an optional string table) that the runtime treats as absent when missing. |
| **Major** (`x.0.0`) | Any **breaking** change: a new required field; a removed or renamed field; a narrowed type, range, or enum; or changed meaning of an existing field. Requires bumping `CONTENT_SCHEMA_VERSION` in the runtime and `SUPPORTED_SCHEMA_MAJOR` in the validator in the same PR, plus migrating every shipped pack. | Making author/license fields required; changing an asset path format. |

When unsure, treat the change as major. A field that starts optional and
later becomes required needs a minor bump to add it, then a major bump to
require it.

### What the validator and runtime do

| Pack declares | Validator (`validate_pack.py`) | Runtime (`content_loader.gd`) |
|---------------|--------------------------------|-------------------------------|
| Same major, minor/patch ≤ current | Accept | Accept |
| Same major, **newer patch** | Accept silently | Accept (reads major only) |
| Same major, **newer minor** | **Accept with a warning** (`WARNING:` line, exit 0). Fields added after the known minor are not checked. | Accept. Unknown optional fields are ignored. |
| **Unsupported major** (either field) | **Reject** with a clear "unsupported schema major version" error | `schemaVersion` above `CONTENT_SCHEMA_VERSION`: reject the pack and fall back to `core_pack` |
| `schemaSemver` missing or malformed, or its major ≠ `schemaVersion` | Reject | Not checked (the runtime reads only `schemaVersion`) |

Shipped packs under `apps/runtime-godot/content/` must never trigger the
newer-minor warning. Their `schemaSemver` must be at or below
`CURRENT_SCHEMA_SEMVER`, and a unit test enforces this.

### Bump procedure (required for every version bump)

1. Classify the change as patch, minor, or major using the table above.
2. Update `buddy-pack.schema.json`, and update `validate_pack.py` in the
   same PR, including `CURRENT_SCHEMA_SEMVER` (and `SUPPORTED_SCHEMA_MAJOR`
   plus the runtime's `CONTENT_SCHEMA_VERSION` for a major bump).
3. **Add a migration-notes entry** for the new version to
   [`CONTENT_SCHEMA_MIGRATIONS.md`](CONTENT_SCHEMA_MIGRATIONS.md). This is
   required for every bump, including patches. A unit test fails if
   `CURRENT_SCHEMA_SEMVER` has no entry there.
4. Update the version at the top of this document (test-enforced), and
   update shipped packs' `schemaSemver` if they adopt the new revision.

---

## Animation JSON format

```json
{
  "loop": true,
  "frames": ["character/animations/idle/0.png", "..."],
  "durations": [0.12, 0.14],
  "anchors": [[0.5, 1.0]],
  "pivots": [[-1, -1]],
  "face_overlays": ["", "character/emotes/default/0.png"]
}
```

`pivots` values of `[-1, -1]` mean no pivot (use anchor only).

---

## Importer boundary

- The runtime reads only the internal format above.
- Any WZ/NX → internal conversion belongs in `tools/importers/`.
- A content pack that references a `schemaVersion > CONTENT_SCHEMA_VERSION`
  will be rejected with a clear error; the runtime falls back to `core_pack`.

---

## Dynamic speech content

Any dynamically generated text rendered in Buddy's speech or thought
bubbles MUST be redacted locally before display. This covers agent status,
activity snippets, model-generated lines, and any other text not authored
verbatim in a content pack. Redaction MUST remove or mask file-system paths,
URLs, secrets and tokens (API keys, credentials, bearer or session tokens),
and multiline code. It MUST run on-device before the text reaches the
renderer, and it MUST NOT depend on a network service. Text that cannot be
safely redacted MUST NOT be shown; the runtime falls back to a canned line.
Static, pack-authored dialogue (for example `npcs[].dialoguePool`) is
reviewed content and is outside this rule. This rule follows OpenPets'
pattern (see `COMPANION_PET_LANDSCAPE_2026-07-14.md`, B3) and applies from
the first feature that routes dynamic text into a bubble.
