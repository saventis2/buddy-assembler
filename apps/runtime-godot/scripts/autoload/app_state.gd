extends Node

const SaveStore = preload("res://scripts/persistence/save_store.gd")
const UnlockTable = preload("res://scripts/progression/unlock_table.gd")

const SETTINGS_PATH := "user://settings.json"
const PROFILE_PATH := "user://profile.json"
const WORLD_STATE_PATH := "user://world_state.json"

var settings := {}
var profile := {}
var world_state := {}


func _ready() -> void:
    load_state()


func load_state() -> void:
    settings = _merge_defaults(
        SaveStore.read_json(SETTINGS_PATH, _default_settings()),
        _default_settings()
    )
    profile = _merge_defaults(
        SaveStore.read_json(PROFILE_PATH, _default_profile()),
        _default_profile()
    )
    world_state = _merge_defaults(
        SaveStore.read_json(WORLD_STATE_PATH, _default_world_state()),
        _default_world_state()
    )
    _refresh_unlocks()
    _prune_event_buckets()


func flush() -> void:
    SaveStore.write_json(SETTINGS_PATH, settings)
    SaveStore.write_json(PROFILE_PATH, profile)
    SaveStore.write_json(WORLD_STATE_PATH, world_state)


func record_interaction(kind: String) -> void:
    var total := int(profile.get("total_interactions", 0))
    profile["total_interactions"] = total + 1

    var xp := int(profile.get("bond_xp", 0))
    if kind == "pet":
        xp += 2
    else:
        xp += 1
    profile["bond_xp"] = xp
    _apply_level_from_xp()
    flush()


func apply_behavior(action_id: String) -> void:
    world_state["last_action"] = action_id
    world_state["last_tick_unix"] = Time.get_unix_time_from_system()

    if action_id == "gift":
        var gifts := int(profile.get("gifts_seen", 0))
        profile["gifts_seen"] = gifts + 1
        profile["bond_xp"] = int(profile.get("bond_xp", 0)) + 3
        _apply_level_from_xp()

    flush()


func apply_loaded_pack(pack_id: String, manifest: Dictionary) -> void:
    settings["selectedPackId"] = pack_id
    world_state["activePackId"] = pack_id
    world_state["activePackManifestVersion"] = str(manifest.get("version", ""))
    flush()


func get_unlocked_actions() -> Array:
    return UnlockTable.unlocked_action_ids(int(profile.get("bond_level", 1)))


func record_event_trigger(event_id: String, action_id: String) -> void:
    world_state["last_event_id"] = event_id
    world_state["last_event_action"] = action_id
    world_state["last_event_unix"] = Time.get_unix_time_from_system()
    flush()


func try_consume_event_budget(event_id: String, per_hour: int, per_day: int) -> bool:
    if event_id == "":
        return false

    var hour_buckets: Dictionary = world_state.get("event_hour_buckets", {})
    var day_buckets: Dictionary = world_state.get("event_day_buckets", {})

    var hour_key := _current_hour_key()
    var day_key := _current_day_key()

    if not hour_buckets.has(hour_key):
        hour_buckets[hour_key] = {}
    if not day_buckets.has(day_key):
        day_buckets[day_key] = {}

    var hour_row: Dictionary = hour_buckets[hour_key]
    var day_row: Dictionary = day_buckets[day_key]
    var hour_count := int(hour_row.get(event_id, 0))
    var day_count := int(day_row.get(event_id, 0))

    if per_hour > 0 and hour_count >= per_hour:
        return false
    if per_day > 0 and day_count >= per_day:
        return false

    hour_row[event_id] = hour_count + 1
    day_row[event_id] = day_count + 1
    hour_buckets[hour_key] = hour_row
    day_buckets[day_key] = day_row
    world_state["event_hour_buckets"] = hour_buckets
    world_state["event_day_buckets"] = day_buckets
    _prune_event_buckets()
    flush()
    return true


func set_window_state(screen_index: int, window_pos: Vector2i) -> void:
    settings["preferredScreen"] = screen_index
    settings["lastWindowPosition"] = [window_pos.x, window_pos.y]
    flush()


func get_window_state() -> Dictionary:
    var pos = settings.get("lastWindowPosition", [120, 120])
    var x := 120
    var y := 120
    if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 2:
        x = int(pos[0])
        y = int(pos[1])
    return {
        "preferredScreen": int(settings.get("preferredScreen", 0)),
        "position": Vector2i(x, y),
    }


func export_profile(path: String) -> bool:
    return SaveStore.write_json(path, profile)


func import_profile(path: String) -> bool:
    var imported = SaveStore.read_json(path, {})
    if imported.is_empty():
        return false
    profile = _merge_defaults(imported, _default_profile())
    _refresh_unlocks()
    flush()
    return true


func get_telemetry_snapshot() -> Dictionary:
    var unlock_count := 0
    var unlocks = profile.get("unlocks", [])
    if typeof(unlocks) == TYPE_ARRAY:
        unlock_count = (unlocks as Array).size()
    return {
        "bond_level": int(profile.get("bond_level", 1)),
        "bond_xp": int(profile.get("bond_xp", 0)),
        "total_interactions": int(profile.get("total_interactions", 0)),
        "gifts_seen": int(profile.get("gifts_seen", 0)),
        "active_pack": str(world_state.get("activePackId", settings.get("selectedPackId", "core_pack"))),
        "last_action": str(world_state.get("last_action", "idle")),
        "last_event_id": str(world_state.get("last_event_id", "")),
        "unlock_count": unlock_count,
    }


func is_quiet_hours_now() -> bool:
    if not bool(settings.get("quietHoursEnabled", true)):
        return false

    var start_hour := int(settings.get("quietHoursStart", 22))
    var end_hour := int(settings.get("quietHoursEnd", 7))
    var now := Time.get_datetime_dict_from_system()
    var hour := int(now.get("hour", 12))

    if start_hour == end_hour:
        return true
    if start_hour < end_hour:
        return hour >= start_hour and hour < end_hour
    return hour >= start_hour or hour < end_hour


func _apply_level_from_xp() -> void:
    var xp := int(profile.get("bond_xp", 0))
    var level := 1 + int(xp / 25)
    profile["bond_level"] = max(1, level)
    _refresh_unlocks()


func _refresh_unlocks() -> void:
    var level := int(profile.get("bond_level", 1))
    var unlock_rows := UnlockTable.unlocked_rows_for_level(level)
    var unlock_ids := []
    for row in unlock_rows:
        unlock_ids.append(str(row.get("id", "")))
    profile["unlocks"] = unlock_ids


func _default_settings() -> Dictionary:
    return {
        "schemaVersion": 1,
        "opacity": 1.0,
        "scale": 1.0,
        "quietHoursEnabled": true,
        "quietHoursStart": 22,
        "quietHoursEnd": 7,
        "eventFrequency": "normal",
        "productivityOptIn": false,
        "focusCelebrateMinutes": 20,
        "breakSuggestMinutes": 45,
        "selectedPackId": "core_pack",
        "preferredScreen": 0,
        "lastWindowPosition": [120, 120],
    }


func _default_profile() -> Dictionary:
    return {
        "schemaVersion": 1,
        "name": "Buddy",
        "bond_xp": 0,
        "bond_level": 1,
        "gifts_seen": 0,
        "total_interactions": 0,
        "personality_seed": Time.get_unix_time_from_system(),
        "unlocks": [],
    }


func _default_world_state() -> Dictionary:
    return {
        "schemaVersion": 1,
        "last_action": "idle",
        "last_tick_unix": 0,
        "last_event_id": "",
        "last_event_action": "",
        "last_event_unix": 0,
        "activePackId": "core_pack",
        "activePackManifestVersion": "",
        "event_hour_buckets": {},
        "event_day_buckets": {},
    }


func _merge_defaults(target: Dictionary, defaults: Dictionary) -> Dictionary:
    var merged := defaults.duplicate(true)
    for key in target.keys():
        merged[key] = target[key]
    return merged


func _current_day_key() -> String:
    var now := Time.get_datetime_dict_from_system()
    return "%04d-%02d-%02d" % [
        int(now.get("year", 1970)),
        int(now.get("month", 1)),
        int(now.get("day", 1)),
    ]


func _current_hour_key() -> String:
    var now := Time.get_datetime_dict_from_system()
    return "%04d-%02d-%02dT%02d" % [
        int(now.get("year", 1970)),
        int(now.get("month", 1)),
        int(now.get("day", 1)),
        int(now.get("hour", 0)),
    ]


func _prune_event_buckets() -> void:
    var hour_buckets: Dictionary = world_state.get("event_hour_buckets", {})
    var day_buckets: Dictionary = world_state.get("event_day_buckets", {})
    var keep_day := _current_day_key()
    var keep_hour := _current_hour_key()

    for key in hour_buckets.keys():
        if str(key) != keep_hour:
            hour_buckets.erase(key)

    for key in day_buckets.keys():
        if str(key) != keep_day:
            day_buckets.erase(key)

    world_state["event_hour_buckets"] = hour_buckets
    world_state["event_day_buckets"] = day_buckets
