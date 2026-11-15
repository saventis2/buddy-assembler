extends Node

# Headless test for ContentLoader validation and fallback cascade.
#
# Exits 0 on success, 1 on failure. Uses user://pack_validation_test/
# as a sandbox so we can materialize broken packs without touching the
# shipped res:// content.

const ContentLoader = preload("res://scripts/content/content_loader.gd")

const ROOT := "user://pack_validation_test"

var _failed := 0
var _ran := 0


func _ready() -> void:
    _run_all()
    if _failed == 0:
        print("pack_validation_test: PASS (%d cases)" % _ran)
        get_tree().quit(0)
    else:
        push_error("pack_validation_test: FAIL (%d/%d failed)" % [_failed, _ran])
        get_tree().quit(1)


func _run_all() -> void:
    _case("valid_manifest_passes", func(): return _test_valid_manifest_passes())
    _case("world_contract_optional_valid", func(): return _test_world_contract_optional_valid())
    _case("world_contract_invalid_npc_fails", func(): return _test_world_contract_invalid_npc_fails())
    _case("missing_required_key_fails", func(): return _test_missing_required_key_fails())
    _case("malformed_json_fails", func(): return _test_malformed_json_fails())
    _case("missing_manifest_file_fails", func(): return _test_missing_manifest_file_fails())
    _case("missing_asset_flagged", func(): return _test_missing_asset_flagged())
    _case("fallback_selected", func(): return _test_fallback_selected())
    _case("fallback_to_core", func(): return _test_fallback_to_core())
    _case("fallback_to_builtin", func(): return _test_fallback_to_builtin())
    _case("unsafe_asset_path_rejected", func(): return _test_unsafe_asset_path_rejected())
    _case("development_pack_excluded", func(): return _test_development_pack_excluded())
    _case("development_selection_falls_back", func(): return _test_development_selection_falls_back())
    _case("development_pack_explicit_path", func(): return _test_development_pack_explicit_path())


func _case(name: String, body: Callable) -> void:
    _ran += 1
    _reset_root()
    var err: Variant = body.call()
    if err != null and typeof(err) == TYPE_STRING and err != "":
        _failed += 1
        push_error("pack_validation_test[%s]: %s" % [name, err])
    else:
        print("pack_validation_test[%s]: ok" % name)


# --- filesystem helpers -------------------------------------------------

func _reset_root() -> void:
    if DirAccess.dir_exists_absolute(ROOT):
        _remove_recursive(ROOT)
    DirAccess.make_dir_recursive_absolute(ROOT)


func _remove_recursive(path: String) -> void:
    var da := DirAccess.open(path)
    if da == null:
        return
    da.list_dir_begin()
    var entry := da.get_next()
    while entry != "":
        if entry != "." and entry != "..":
            var full := path + "/" + entry
            if da.current_is_dir():
                _remove_recursive(full)
            else:
                DirAccess.remove_absolute(full)
        entry = da.get_next()
    da.list_dir_end()
    DirAccess.remove_absolute(path)


func _write_text(path: String, text: String) -> void:
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var f := FileAccess.open(path, FileAccess.WRITE)
    f.store_string(text)
    f.flush()
    f.close()


func _valid_manifest_dict(id: String) -> Dictionary:
    return {
        "schemaVersion": 1,
        "id": id,
        "name": "Test Pack %s" % id,
        "version": "0.0.1",
        "companion": {"id": "t-%s" % id, "displayName": "Tester"},
        "idleActions": ["idle"],
        "reactionActions": ["happy"],
        "eventRules": [],
    }


func _write_pack(pack_id: String, manifest: Dictionary) -> void:
    _write_text(
        "%s/%s/manifest.json" % [ROOT, pack_id],
        JSON.stringify(manifest, "  ")
    )


# --- cases --------------------------------------------------------------

func _test_valid_manifest_passes() -> Variant:
    _write_pack("good", _valid_manifest_dict("good"))
    var r := ContentLoader.load_pack("good", ROOT)
    if not bool(r.get("ok", false)):
        return "load_pack errors=%s" % [r.get("errors", [])]
    return null


func _test_world_contract_optional_valid() -> Variant:
    var m := _valid_manifest_dict("world-ok")
    m["home"] = {"sceneId": "cozy_starter_room", "decorSlots": {"wall": "item"}}
    m["npcs"] = [{"id": "mira", "name": "Mira", "role": "mentor", "dialoguePool": ["Hi"]}]
    m["quests"] = [{"id": "quest-a", "type": "bond", "rewards": {"crystals": 1}}]
    m["encounters"] = [{"id": "encounter-a", "action": "visitor"}]
    _write_pack("world-ok", m)
    var r := ContentLoader.load_pack("world-ok", ROOT)
    if not bool(r.get("ok", false)):
        return "expected optional world fields to pass, got %s" % [r.get("errors", [])]
    return null


func _test_world_contract_invalid_npc_fails() -> Variant:
    var m := _valid_manifest_dict("world-bad")
    m["npcs"] = [{"id": "mira"}]
    _write_pack("world-bad", m)
    var r := ContentLoader.load_pack("world-bad", ROOT)
    if bool(r.get("ok", false)):
        return "expected failure for npc without name"
    var errors: Array = r.get("errors", [])
    for e in errors:
        if String(e).find("npcs.name") != -1:
            return null
    return "expected npcs.name validation error, got %s" % [errors]


func _test_missing_required_key_fails() -> Variant:
    var m := _valid_manifest_dict("bad")
    m.erase("eventRules")
    _write_pack("bad", m)
    var r := ContentLoader.load_pack("bad", ROOT)
    if bool(r.get("ok", false)):
        return "expected failure when eventRules missing"
    var errors: Array = r.get("errors", [])
    for e in errors:
        if String(e).find("eventRules") != -1:
            return null
    return "errors did not mention eventRules: %s" % [errors]


func _test_malformed_json_fails() -> Variant:
    _write_text("%s/broken/manifest.json" % ROOT, "{ not json")
    var r := ContentLoader.load_pack("broken", ROOT)
    if bool(r.get("ok", false)):
        return "expected failure on malformed JSON"
    return null


func _test_missing_manifest_file_fails() -> Variant:
    DirAccess.make_dir_recursive_absolute("%s/empty" % ROOT)
    var r := ContentLoader.load_pack("empty", ROOT)
    if bool(r.get("ok", false)):
        return "expected failure when manifest.json is absent"
    return null


func _test_missing_asset_flagged() -> Variant:
    var m := _valid_manifest_dict("visual")
    m["visual"] = {
        "animations": {"idle": "character/animations/idle.json"},
        "sprites": {"idle": "character/idle.png"},
    }
    _write_pack("visual", m)
    # No assets written — both references should be flagged.
    var r := ContentLoader.load_pack("visual", ROOT)
    if bool(r.get("ok", false)):
        return "expected asset-existence failure"
    var errs: Array = r.get("errors", [])
    var found_anim := false
    var found_sprite := false
    for e in errs:
        var s := String(e)
        if s.find("animations.idle") != -1:
            found_anim = true
        if s.find("sprites.idle") != -1:
            found_sprite = true
    if not (found_anim and found_sprite):
        return "expected both animation and sprite missing errors; got %s" % [errs]
    return null


func _test_fallback_selected() -> Variant:
    _write_pack("chosen", _valid_manifest_dict("chosen"))
    var r := ContentLoader.load_with_fallback("chosen", ROOT)
    if String(r.get("source_tier", "")) != "selected":
        return "expected source_tier=selected, got %s" % r
    if String(r.get("pack_id", "")) != "chosen":
        return "expected pack_id=chosen, got %s" % r
    return null


func _test_fallback_to_core() -> Variant:
    # Selected pack does not exist; core_pack is valid.
    _write_pack("core_pack", _valid_manifest_dict("core-pack"))
    var r := ContentLoader.load_with_fallback("missing", ROOT)
    if String(r.get("source_tier", "")) != "core":
        return "expected source_tier=core, got %s" % r
    if String(r.get("pack_id", "")) != "core_pack":
        return "expected pack_id=core_pack, got %s" % r
    var ebt: Dictionary = r.get("errors_by_tier", {})
    if not ebt.has("missing"):
        return "expected errors_by_tier to include 'missing'; got %s" % [ebt]
    return null


func _test_fallback_to_builtin() -> Variant:
    # Neither selected nor core_pack exist.
    var r := ContentLoader.load_with_fallback("missing", ROOT)
    if String(r.get("source_tier", "")) != "builtin":
        return "expected source_tier=builtin, got %s" % r
    if String(r.get("pack_id", "")) != ContentLoader.BUILTIN_PACK_ID:
        return "expected builtin pack id, got %s" % r
    var m: Dictionary = r.get("manifest", {})
    if not m.has("idleActions"):
        return "builtin manifest missing idleActions"
    return null


func _test_unsafe_asset_path_rejected() -> Variant:
    var m := _valid_manifest_dict("unsafe")
    m["visual"] = {"sprites": {"idle": "C:/workstation-only/face.png"}}
    _write_pack("unsafe", m)
    var r := ContentLoader.load_pack("unsafe", ROOT)
    if bool(r.get("ok", false)):
        return "expected drive-letter asset path to fail"
    for error in r.get("errors", []):
        if String(error).find("non-repository path") >= 0:
            return null
    return "expected non-repository path error, got %s" % [r.get("errors", [])]


func _test_development_pack_excluded() -> Variant:
    var core := _valid_manifest_dict("core-pack")
    core["runtimeAudience"] = "user"
    var dev := _valid_manifest_dict("dev-pack")
    dev["runtimeAudience"] = "development"
    _write_pack("core_pack", core)
    _write_pack("dev_pack", dev)
    var production_ids := ContentLoader.list_cycleable_pack_ids(ROOT)
    if production_ids.has("dev_pack"):
        return "development pack leaked into production cycle: %s" % [production_ids]
    return null


func _test_development_selection_falls_back() -> Variant:
    var core := _valid_manifest_dict("core-pack")
    core["runtimeAudience"] = "user"
    var dev := _valid_manifest_dict("dev-pack")
    dev["runtimeAudience"] = "development"
    _write_pack("core_pack", core)
    _write_pack("dev_pack", dev)
    var loaded := ContentLoader.load_with_fallback("dev_pack", ROOT)
    if str(loaded.get("source_tier", "")) != "core":
        return "stale development selection did not fall back to core: %s" % [loaded]
    return null


func _test_development_pack_explicit_path() -> Variant:
    var dev := _valid_manifest_dict("dev-pack")
    dev["runtimeAudience"] = "development"
    _write_pack("dev_pack", dev)
    var ids := ContentLoader.list_cycleable_pack_ids(ROOT, true)
    if not ids.has("dev_pack"):
        return "explicit development cycle did not expose dev_pack: %s" % [ids]
    var loaded := ContentLoader.load_with_fallback("dev_pack", ROOT, true)
    if str(loaded.get("source_tier", "")) != "selected":
        return "explicit development load failed: %s" % [loaded]
    return null
