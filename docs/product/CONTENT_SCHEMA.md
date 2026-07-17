# Content Pack Schema — V1

**Schema version:** 1  
**Runtime constant:** `ContentLoader.CONTENT_SCHEMA_VERSION`

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
    "faceMode": "overlay_or_code",
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
| `schemaVersion` | integer | Must equal `CONTENT_SCHEMA_VERSION` (currently 1) |
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
| `visual` | object | If omitted or unusable, the complete code-drawn emergency buddy is used |
| `encounterActions` | array | Actions playable via event rules |
| `items` | array | Optional runtime item definitions (id, category, rarity, theme) |
| `currencies` | object | Optional currency defaults (for V1, usually `crystals`) |
| `rewardBoxes` | array | Optional themed reward-box definitions |
| `home` | object | Optional home scene + decor slot defaults |
| `npcs` | array | Optional NPC cast (`id`, `name`, `role`, `dialoguePool`) |
| `quests` | array | Optional quest pool with `rewards` payload |
| `encounters` | array | Optional encounter pool with engage/skip rewards |

`visual.faceMode` is `embedded` by default. `overlay_or_code` preserves a
valid repository asset overlay when available and otherwise draws the
repository-authored portable face over the tracked body. Asset paths must be
pack-relative or `res://`; drive-letter, filesystem-absolute, `user://`,
traversal, missing, ignored, and untracked dependencies fail validation.

`runtimeAudience: development` packs are absent from the normal user cycle.
Developers can exercise them from a source checkout with
`--allow-development-packs`; release exports omit their resources.

### Curated WZ whitelist note (V1)

- Runtime can consume curated item rows through `items` in the pack manifest.
- For V1, use a controlled shortlist (`sourceType: "wz_whitelist_v1"`) and avoid broad ingest.
- `rewardBoxes[].possibleItems` should reference these curated IDs.

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
