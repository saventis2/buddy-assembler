extends Node

# Headless test for SaveStore durability guarantees.
#
# Exits with code 0 on success, 1 on any failed assertion. Run via:
#   godot --headless --path . res://tests/SaveStoreTest.tscn
#
# All test files are written under user://save_store_test/ and removed
# between cases so the test is idempotent across CI runs.

const SaveStore = preload("res://scripts/persistence/save_store.gd")
const SchemaMigrations = preload("res://scripts/persistence/schema_migrations.gd")

const TEST_DIR := "user://save_store_test"

var _failed := 0
var _ran := 0


func _ready() -> void:
    _run_all()
    if _failed == 0:
        print("save_store_test: PASS (%d cases)" % _ran)
        get_tree().quit(0)
    else:
        push_error("save_store_test: FAIL (%d/%d failed)" % [_failed, _ran])
        get_tree().quit(1)


func _run_all() -> void:
    _case("fresh_returns_defaults", func(): _test_fresh_returns_defaults())
    _case("roundtrip_preserves_data", func(): _test_roundtrip_preserves_data())
    _case("atomic_write_no_partial", func(): _test_atomic_write_no_partial())
    _case("corrupt_json_quarantined", func(): _test_corrupt_json_quarantined())
    _case("newer_version_quarantined", func(): _test_newer_version_quarantined())
    _case("migration_steps_old_to_current", func(): _test_migration_steps())
    _case("missing_migrator_quarantines", func(): _test_missing_migrator_quarantines())
    _case("profile_v1_to_v2_migration_shape", func(): _test_profile_v1_to_v2_shape())


func _case(name: String, body: Callable) -> void:
    _ran += 1
    _prepare_dir()
    var err: Variant = body.call()
    if err != null and typeof(err) == TYPE_STRING and err != "":
        _failed += 1
        push_error("save_store_test[%s]: %s" % [name, err])
    else:
        print("save_store_test[%s]: ok" % name)


func _prepare_dir() -> void:
    var da := DirAccess.open("user://")
    if da == null:
        DirAccess.make_dir_recursive_absolute(TEST_DIR)
        return
    if DirAccess.dir_exists_absolute(TEST_DIR):
        _remove_recursive(TEST_DIR)
    DirAccess.make_dir_recursive_absolute(TEST_DIR)


func _remove_recursive(path: String) -> void:
    var da := DirAccess.open(path)
    if da == null:
        return
    da.list_dir_begin()
    var entry := da.get_next()
    while entry != "":
        var full := path + "/" + entry
        if da.current_is_dir():
            _remove_recursive(full)
        else:
            DirAccess.remove_absolute(full)
        entry = da.get_next()
    da.list_dir_end()
    DirAccess.remove_absolute(path)


# --- helpers -----------------------------------------------------------

func _defaults() -> Dictionary:
    return {"schemaVersion": 2, "name": "default", "value": 0}


func _write_raw(path: String, text: String) -> void:
    var f := FileAccess.open(path, FileAccess.WRITE)
    f.store_string(text)
    f.flush()
    f.close()


func _list_names(path: String) -> Array:
    var out: Array = []
    var da := DirAccess.open(path)
    if da == null:
        return out
    da.list_dir_begin()
    var e := da.get_next()
    while e != "":
        if e != "." and e != "..":
            out.append(e)
        e = da.get_next()
    da.list_dir_end()
    return out


# --- cases -------------------------------------------------------------

func _test_fresh_returns_defaults() -> Variant:
    var path := TEST_DIR + "/settings.json"
    var d = SaveStore.load_versioned(path, _defaults, 2, {})
    if int(d.get("schemaVersion", 0)) != 2:
        return "expected schemaVersion 2, got %s" % [d]
    if String(d.get("name", "")) != "default":
        return "defaults not used"
    return null


func _test_roundtrip_preserves_data() -> Variant:
    var path := TEST_DIR + "/settings.json"
    var payload := {"schemaVersion": 2, "name": "persisted", "value": 42}
    if not SaveStore.write_json(path, payload):
        return "write_json returned false"
    var d = SaveStore.load_versioned(path, _defaults, 2, {})
    if String(d.get("name", "")) != "persisted":
        return "name not preserved"
    if int(d.get("value", -1)) != 42:
        return "value not preserved"
    return null


func _test_atomic_write_no_partial() -> Variant:
    # After write_json returns, there must not be a stale .tmp sibling.
    var path := TEST_DIR + "/settings.json"
    SaveStore.write_json(path, {"schemaVersion": 2, "name": "a", "value": 1})
    var entries := _list_names(TEST_DIR)
    for e in entries:
        if String(e).ends_with(".tmp"):
            return "temp file leaked: %s" % e
    return null


func _test_corrupt_json_quarantined() -> Variant:
    var path := TEST_DIR + "/settings.json"
    _write_raw(path, "{not valid json")
    var d = SaveStore.load_versioned(path, _defaults, 2, {})
    if String(d.get("name", "")) != "default":
        return "expected defaults after corruption"
    var entries := _list_names(TEST_DIR)
    var found_quarantine := false
    for e in entries:
        if String(e).begins_with("settings.json.corrupt-") and String(e).ends_with(".bad_json"):
            found_quarantine = true
            break
    if not found_quarantine:
        return "no quarantine file found; entries=%s" % [entries]
    return null


func _test_newer_version_quarantined() -> Variant:
    var path := TEST_DIR + "/settings.json"
    SaveStore.write_json(path, {"schemaVersion": 999, "name": "from-future", "value": 7})
    var d = SaveStore.load_versioned(path, _defaults, 2, {})
    if String(d.get("name", "")) != "default":
        return "expected defaults when save is newer than runtime"
    var entries := _list_names(TEST_DIR)
    for e in entries:
        if String(e).ends_with(".newer_than_runtime"):
            return null
    return "no newer_than_runtime quarantine; entries=%s" % [entries]


func _test_migration_steps() -> Variant:
    var path := TEST_DIR + "/settings.json"
    SaveStore.write_json(path, {"schemaVersion": 1, "name": "old"})
    var migrators := {
        1: func(old: Dictionary) -> Dictionary:
            var next := old.duplicate(true)
            next["value"] = 100
            return next,
    }
    var d = SaveStore.load_versioned(path, _defaults, 2, migrators)
    if int(d.get("schemaVersion", 0)) != 2:
        return "expected schemaVersion 2 after migration"
    if int(d.get("value", -1)) != 100:
        return "migrator did not set value; got %s" % [d]
    if String(d.get("name", "")) != "old":
        return "original field lost across migration"
    return null


func _test_missing_migrator_quarantines() -> Variant:
    var path := TEST_DIR + "/settings.json"
    SaveStore.write_json(path, {"schemaVersion": 1, "name": "old"})
    var d = SaveStore.load_versioned(path, _defaults, 2, {})
    if String(d.get("name", "")) != "default":
        return "expected defaults when no migrator available"
    var entries := _list_names(TEST_DIR)
    for e in entries:
        if String(e).ends_with(".no_migrator_v1"):
            return null
    return "no no_migrator quarantine; entries=%s" % [entries]


func _test_profile_v1_to_v2_shape() -> Variant:
    var path := TEST_DIR + "/profile.json"
    SaveStore.write_json(
        path,
        {
            "schemaVersion": 1,
            "name": "legacy-buddy",
            "bond_xp": 10,
            "bond_level": 1,
            "personality_seed": 12345,
        }
    )

    var d = SaveStore.load_versioned(
        path,
        func() -> Dictionary:
            return {
                "schemaVersion": 2,
                "name": "default",
                "bond_xp": 0,
                "bond_level": 1,
                "trust_value": 0.2,
                "dominant_mood": "calm",
                "growth_stage": 1,
                "stats": {
                    "strength": 1,
                    "dexterity": 1,
                    "charisma": 1,
                    "endurance": 1,
                    "wisdom": 1,
                    "knowledge": 1,
                },
            },
        SchemaMigrations.PROFILE_CURRENT_VERSION,
        SchemaMigrations.PROFILE_MIGRATORS
    )

    if int(d.get("schemaVersion", 0)) != 2:
        return "expected schemaVersion 2, got %s" % [d]
    if String(d.get("name", "")) != "legacy-buddy":
        return "legacy name not preserved"
    if not d.has("trust_value"):
        return "trust_value missing after migration"
    if not d.has("dominant_mood"):
        return "dominant_mood missing after migration"
    if not d.has("growth_stage"):
        return "growth_stage missing after migration"
    if typeof(d.get("stats", null)) != TYPE_DICTIONARY:
        return "stats missing or invalid after migration"
    return null
