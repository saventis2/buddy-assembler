extends RefCounted

const CONTENT_ROOT := "res://content"
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


static func list_pack_ids() -> Array:
    var ids := []
    var dir := DirAccess.open(CONTENT_ROOT)
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


static func load_pack(pack_id: String) -> Dictionary:
    var manifest_path := "%s/%s/manifest.json" % [CONTENT_ROOT, pack_id]
    if not FileAccess.file_exists(manifest_path):
        return {
            "ok": false,
            "pack_id": pack_id,
            "manifest_path": manifest_path,
            "manifest": {},
            "errors": ["Manifest not found: %s" % manifest_path],
        }

    var file := FileAccess.open(manifest_path, FileAccess.READ)
    if file == null:
        return {
            "ok": false,
            "pack_id": pack_id,
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
            "manifest_path": manifest_path,
            "manifest": {},
            "errors": ["Manifest root must be object"],
        }

    var manifest := parsed as Dictionary
    var errors := validate_manifest(manifest)
    return {
        "ok": errors.is_empty(),
        "pack_id": pack_id,
        "manifest_path": manifest_path,
        "manifest": manifest,
        "errors": errors,
    }


static func validate_manifest(manifest: Dictionary) -> Array:
    var errors := []
    for key in REQUIRED_KEYS:
        if not manifest.has(key):
            errors.append("Missing required key: %s" % key)
    if not errors.is_empty():
        return errors

    if typeof(manifest.get("schemaVersion")) != TYPE_INT:
        errors.append("schemaVersion must be integer")
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
