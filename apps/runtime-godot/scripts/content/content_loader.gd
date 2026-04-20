extends RefCounted

const CONTENT_ROOT := "res://content"
const CORE_PACK_ID := "core_pack"
const BUILTIN_PACK_ID := "__builtin_safe"
const CONTENT_SCHEMA_VERSION := 1
const REQUIRED_KEYS := [
    "schemaVersion",
    "id",
    "name",
    "version",
    "companion",
    "idleActions",
    "reactionActions",
    "eventRules",
]

# Last-resort synthetic manifest. The runtime returns to this when the
# user's selected pack AND core_pack both fail validation. It references
# no external assets so it cannot itself fail an asset check — the buddy
# falls back to a code-drawn placeholder, but the app still launches.
const BUILTIN_FALLBACK_MANIFEST := {
    "schemaVersion": 1,
    "id": "builtin-safe",
    "name": "Built-in Safe Mode",
    "version": "0.0.0",
    "companion": {
        "id": "builtin-buddy",
        "displayName": "Buddy (safe mode)",
        "traits": ["calm"],
    },
    "idleActions": ["idle"],
    "reactionActions": ["happy"],
    "encounterActions": [],
    "eventRules": [],
}


static func list_pack_ids(root_override: String = "") -> Array:
    var root := root_override if root_override != "" else CONTENT_ROOT
    var ids := []
    var dir := DirAccess.open(root)
    if dir == null:
        return ids

    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name == "":
            break
        if name.begins_with("."):
            continue
        if dir.current_is_dir():
            ids.append(name)
    dir.list_dir_end()
    ids.sort()
    return ids


static func list_cycleable_pack_ids(root_override: String = "") -> Array:
    var ids := list_pack_ids(root_override)
    var cycleable: Array = []
    for pack_id in ids:
        var loaded := load_pack(str(pack_id), root_override)
        if bool(loaded.get("ok", false)):
            cycleable.append(str(pack_id))
    cycleable.sort()
    return cycleable


static func load_pack(pack_id: String, root_override: String = "") -> Dictionary:
    var root := root_override if root_override != "" else CONTENT_ROOT
    var pack_root := "%s/%s" % [root, pack_id]
    var manifest_path := "%s/manifest.json" % pack_root
    if not FileAccess.file_exists(manifest_path):
        return {
            "ok": false,
            "pack_id": pack_id,
            "pack_root": pack_root,
            "manifest_path": manifest_path,
            "manifest": {},
            "errors": ["Manifest not found: %s" % manifest_path],
        }

    var file := FileAccess.open(manifest_path, FileAccess.READ)
    if file == null:
        return {
            "ok": false,
            "pack_id": pack_id,
            "pack_root": pack_root,
            "manifest_path": manifest_path,
            "manifest": {},
            "errors": ["Could not open manifest: %s" % manifest_path],
        }

    var raw := file.get_as_text()
    file.close()

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {
            "ok": false,
            "pack_id": pack_id,
            "pack_root": pack_root,
            "manifest_path": manifest_path,
            "manifest": {},
            "errors": ["Manifest root must be object"],
        }

    var manifest := parsed as Dictionary
    var errors := validate_manifest(manifest)
    if errors.is_empty():
        errors = validate_assets(manifest, pack_root)
    return {
        "ok": errors.is_empty(),
        "pack_id": pack_id,
        "pack_root": pack_root,
        "manifest_path": manifest_path,
        "manifest": manifest,
        "errors": errors,
    }


# Deterministic fallback cascade. Callers should prefer this over
# calling load_pack directly so the runtime always has a usable manifest.
#
# Returns a dictionary with:
#   pack_id         : id of the pack actually in use
#   manifest        : the manifest dict (never empty)
#   source_tier     : "selected" | "core" | "builtin"
#   fallback_reason : "" when source_tier == "selected", else a short
#                     human-readable string
#   errors_by_tier  : { "<tier>": Array[String] } of validation errors
#                     collected on the way down
static func load_with_fallback(selected_pack_id: String, root_override: String = "") -> Dictionary:
    var errors_by_tier := {}

    var selected := load_pack(selected_pack_id, root_override)
    if bool(selected.get("ok", false)):
        return {
            "pack_id": selected.get("pack_id", selected_pack_id),
            "manifest": selected.get("manifest", {}),
            "source_tier": "selected",
            "fallback_reason": "",
            "errors_by_tier": errors_by_tier,
        }
    errors_by_tier[selected_pack_id] = selected.get("errors", [])
    push_warning("content: selected pack %s failed: %s" % [selected_pack_id, selected.get("errors", [])])

    if selected_pack_id != CORE_PACK_ID:
        var core := load_pack(CORE_PACK_ID, root_override)
        if bool(core.get("ok", false)):
            return {
                "pack_id": CORE_PACK_ID,
                "manifest": core.get("manifest", {}),
                "source_tier": "core",
                "fallback_reason": "selected pack failed validation",
                "errors_by_tier": errors_by_tier,
            }
        errors_by_tier[CORE_PACK_ID] = core.get("errors", [])
        push_warning("content: core_pack failed: %s" % [core.get("errors", [])])

    return {
        "pack_id": BUILTIN_PACK_ID,
        "manifest": BUILTIN_FALLBACK_MANIFEST.duplicate(true),
        "source_tier": "builtin",
        "fallback_reason": "selected and core_pack both failed validation",
        "errors_by_tier": errors_by_tier,
    }


# Asset-existence pass. Returns errors for any referenced animation JSON
# or sprite PNG that does not resolve under pack_root. Intentionally
# narrow: we only check the fields the renderer actually dereferences
# during a normal boot. The dev-time validator in
# packages/content-validator/ owns deeper pack audits.
static func validate_assets(manifest: Dictionary, pack_root: String) -> Array:
    var errors: Array = []
    var visual_variant = manifest.get("visual", null)
    if typeof(visual_variant) != TYPE_DICTIONARY:
        return errors
    var visual: Dictionary = visual_variant

    for field in ["animations", "sprites"]:
        var group_variant = visual.get(field, null)
        if typeof(group_variant) != TYPE_DICTIONARY:
            continue
        var group: Dictionary = group_variant
        for key in group.keys():
            var rel := str(group[key])
            if rel == "":
                continue
            var abs_path := _resolve_asset_path(rel, pack_root)
            if abs_path == "":
                continue  # absolute res:// path left to Godot; skip
            if not FileAccess.file_exists(abs_path):
                errors.append(
                    "visual.%s.%s -> %s (missing at %s)" % [field, key, rel, abs_path]
                )
    return errors


static func _resolve_asset_path(rel: String, pack_root: String) -> String:
    if rel.begins_with("res://") or rel.begins_with("user://"):
        return rel  # caller treats as already-absolute; we don't check
    return "%s/%s" % [pack_root, rel]


static func validate_manifest(manifest: Dictionary) -> Array:
    var errors := []
    for key in REQUIRED_KEYS:
        if not manifest.has(key):
            errors.append("Missing required key: %s" % key)
    if not errors.is_empty():
        return errors

    var sv = manifest.get("schemaVersion")
    # JSON.parse_string returns numbers as float, so accept integer-valued floats.
    var sv_ok := typeof(sv) == TYPE_INT or (typeof(sv) == TYPE_FLOAT and float(sv) == float(int(sv)))
    if not sv_ok:
        errors.append("schemaVersion must be integer")
    elif int(sv) > CONTENT_SCHEMA_VERSION:
        errors.append(
            "schemaVersion %d exceeds runtime maximum %d — update the runtime to load this pack"
            % [int(sv), CONTENT_SCHEMA_VERSION]
        )
    if _is_blank(manifest.get("id")):
        errors.append("id must be non-empty string")
    if _is_blank(manifest.get("name")):
        errors.append("name must be non-empty string")
    if _is_blank(manifest.get("version")):
        errors.append("version must be non-empty string")

    var companion = manifest.get("companion")
    if typeof(companion) != TYPE_DICTIONARY:
        errors.append("companion must be object")
    else:
        if _is_blank(companion.get("id")):
            errors.append("companion.id must be non-empty string")
        if _is_blank(companion.get("displayName")):
            errors.append("companion.displayName must be non-empty string")

    var visual_variant = manifest.get("visual", null)
    if visual_variant != null:
        if typeof(visual_variant) != TYPE_DICTIONARY:
            errors.append("visual must be object when set")
        else:
            var visual: Dictionary = visual_variant
            var scale_raw = visual.get("scale", null)
            if scale_raw != null:
                if typeof(scale_raw) != TYPE_FLOAT and typeof(scale_raw) != TYPE_INT:
                    errors.append("visual.scale must be numeric")
                elif float(scale_raw) <= 0.0:
                    errors.append("visual.scale must be > 0")

            var anchor_raw = visual.get("anchor", null)
            if anchor_raw != null:
                if typeof(anchor_raw) != TYPE_ARRAY or (anchor_raw as Array).size() != 2:
                    errors.append("visual.anchor must be [x, y]")

            var animations_variant = visual.get("animations", null)
            if animations_variant != null:
                if typeof(animations_variant) != TYPE_DICTIONARY:
                    errors.append("visual.animations must be object")
                else:
                    var animations: Dictionary = animations_variant
                    for key in animations.keys():
                        if _is_blank(key):
                            errors.append("visual.animations key must be non-empty")
                        if _is_blank(animations[key]):
                            errors.append("visual.animations value must be non-empty string")

            var sprites_variant = visual.get("sprites", null)
            if sprites_variant != null:
                if typeof(sprites_variant) != TYPE_DICTIONARY:
                    errors.append("visual.sprites must be object")
                else:
                    var sprites: Dictionary = sprites_variant
                    for key in sprites.keys():
                        if _is_blank(key):
                            errors.append("visual.sprites key must be non-empty")
                        if _is_blank(sprites[key]):
                            errors.append("visual.sprites value must be non-empty string")

    for field in ["idleActions", "reactionActions"]:
        var values = manifest.get(field)
        if typeof(values) != TYPE_ARRAY or (values as Array).is_empty():
            errors.append("%s must be non-empty array" % field)

    var event_rules = manifest.get("eventRules")
    if typeof(event_rules) != TYPE_ARRAY:
        errors.append("eventRules must be array")

    var items_variant = manifest.get("items", null)
    if items_variant != null:
        if typeof(items_variant) != TYPE_ARRAY:
            errors.append("items must be array when set")
        else:
            for row_variant in (items_variant as Array):
                if typeof(row_variant) != TYPE_DICTIONARY:
                    errors.append("items entries must be objects")
                    continue
                var row: Dictionary = row_variant
                for field in ["id", "name", "category", "rarity", "primaryTheme"]:
                    if _is_blank(row.get(field, "")):
                        errors.append("items.%s must be non-empty string" % field)

    var currencies_variant = manifest.get("currencies", null)
    if currencies_variant != null and typeof(currencies_variant) != TYPE_DICTIONARY:
        errors.append("currencies must be object when set")

    var reward_boxes_variant = manifest.get("rewardBoxes", null)
    if reward_boxes_variant != null:
        if typeof(reward_boxes_variant) != TYPE_ARRAY:
            errors.append("rewardBoxes must be array when set")
        else:
            for box_variant in (reward_boxes_variant as Array):
                if typeof(box_variant) != TYPE_DICTIONARY:
                    errors.append("rewardBoxes entries must be objects")
                    continue
                var box: Dictionary = box_variant
                if _is_blank(box.get("id", "")):
                    errors.append("rewardBoxes.id must be non-empty string")
                if _is_blank(box.get("theme", "")):
                    errors.append("rewardBoxes.theme must be non-empty string")
                var cost = box.get("cost", null)
                if typeof(cost) != TYPE_INT and typeof(cost) != TYPE_FLOAT:
                    errors.append("rewardBoxes.cost must be numeric")
                elif int(cost) <= 0:
                    errors.append("rewardBoxes.cost must be > 0")

    var npcs_variant = manifest.get("npcs", null)
    if npcs_variant != null:
        if typeof(npcs_variant) != TYPE_ARRAY:
            errors.append("npcs must be array when set")
        else:
            for npc_variant in (npcs_variant as Array):
                if typeof(npc_variant) != TYPE_DICTIONARY:
                    errors.append("npcs entries must be objects")
                    continue
                var npc: Dictionary = npc_variant
                if _is_blank(npc.get("id", "")):
                    errors.append("npcs.id must be non-empty string")
                if _is_blank(npc.get("name", "")):
                    errors.append("npcs.name must be non-empty string")
                if npc.has("dialoguePool") and typeof(npc.get("dialoguePool")) != TYPE_ARRAY:
                    errors.append("npcs.dialoguePool must be array when set")

    var quests_variant = manifest.get("quests", null)
    if quests_variant != null:
        if typeof(quests_variant) != TYPE_ARRAY:
            errors.append("quests must be array when set")
        else:
            for quest_variant in (quests_variant as Array):
                if typeof(quest_variant) != TYPE_DICTIONARY:
                    errors.append("quests entries must be objects")
                    continue
                var quest: Dictionary = quest_variant
                if _is_blank(quest.get("id", "")):
                    errors.append("quests.id must be non-empty string")
                if _is_blank(quest.get("type", "")):
                    errors.append("quests.type must be non-empty string")
                if quest.has("rewards") and typeof(quest.get("rewards")) != TYPE_DICTIONARY:
                    errors.append("quests.rewards must be object when set")

    var encounters_variant = manifest.get("encounters", null)
    if encounters_variant != null:
        if typeof(encounters_variant) != TYPE_ARRAY:
            errors.append("encounters must be array when set")
        else:
            for encounter_variant in (encounters_variant as Array):
                if typeof(encounter_variant) != TYPE_DICTIONARY:
                    errors.append("encounters entries must be objects")
                    continue
                var encounter: Dictionary = encounter_variant
                if _is_blank(encounter.get("id", "")):
                    errors.append("encounters.id must be non-empty string")
                if _is_blank(encounter.get("action", "")):
                    errors.append("encounters.action must be non-empty string")

    var home_variant = manifest.get("home", null)
    if home_variant != null and typeof(home_variant) != TYPE_DICTIONARY:
        errors.append("home must be object when set")

    return errors


static func gather_action_ids(manifest: Dictionary) -> Array:
    var ids := []
    for field in ["idleActions", "reactionActions", "encounterActions"]:
        var values = manifest.get(field, [])
        if typeof(values) != TYPE_ARRAY:
            continue
        for value in values:
            var action_id := str(value)
            if action_id == "":
                continue
            ids.append(action_id)

    var unique := []
    var seen := {}
    for action_id in ids:
        if seen.has(action_id):
            continue
        seen[action_id] = true
        unique.append(action_id)
    return unique


static func _is_blank(value: Variant) -> bool:
    if typeof(value) != TYPE_STRING:
        return true
    return str(value).strip_edges() == ""
