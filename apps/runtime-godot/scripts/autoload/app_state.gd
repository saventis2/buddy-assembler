extends Node

const SaveStore = preload("res://scripts/persistence/save_store.gd")
const SchemaMigrations = preload("res://scripts/persistence/schema_migrations.gd")
const UnlockTable = preload("res://scripts/progression/unlock_table.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")

const SETTINGS_PATH := "user://settings.json"
const PROFILE_PATH := "user://profile.json"
const WORLD_STATE_PATH := "user://world_state.json"
const CORE_ECONOMY_PACK_ID := "core_pack"
const INVENTORY_BACKFILL_MIGRATION_VERSION := 2

const SERVICE_PATHS := {
    "identity": "res://scripts/services/identity_service.gd",
    "mood": "res://scripts/services/mood_service.gd",
    "bond": "res://scripts/services/bond_service.gd",
    "growth": "res://scripts/services/growth_service.gd",
    "economy": "res://scripts/services/economy_service.gd",
    "world": "res://scripts/services/world_service.gd",
    "report": "res://scripts/services/report_service.gd",
}

var settings := {}
var profile := {}
var world_state := {}
var _services: Dictionary = {}


func _ready() -> void:
    _load_services()
    load_state()


func _load_services() -> void:
    _services.clear()
    for key in SERVICE_PATHS.keys():
        var path := str(SERVICE_PATHS[key])
        var script = load(path)
        if script == null:
            push_warning("app_state: service %s missing at %s" % [key, path])
            continue
        if not script.can_instantiate():
            push_warning("app_state: service %s could not instantiate from %s" % [key, path])
            continue
        var instance = script.new()
        _services[key] = instance


func load_state() -> void:
    settings = SaveStore.load_versioned(
        SETTINGS_PATH,
        _default_settings,
        SchemaMigrations.SETTINGS_CURRENT_VERSION,
        SchemaMigrations.SETTINGS_MIGRATORS
    )
    profile = SaveStore.load_versioned(
        PROFILE_PATH,
        _default_profile,
        SchemaMigrations.PROFILE_CURRENT_VERSION,
        SchemaMigrations.PROFILE_MIGRATORS
    )
    world_state = SaveStore.load_versioned(
        WORLD_STATE_PATH,
        _default_world_state,
        SchemaMigrations.WORLD_STATE_CURRENT_VERSION,
        SchemaMigrations.WORLD_STATE_MIGRATORS
    )

    profile = _ensure_profile_modules(profile)
    world_state = _ensure_world_modules(world_state)
    _reconcile_progression_from_xp()
    var inventory_backfill_changed := _run_inventory_backfill_migration_once()
    _sync_growth_mode_flags()
    _refresh_unlocks()
    _prune_event_buckets()
    _refresh_while_away_report()
    if inventory_backfill_changed:
        flush()


func flush() -> void:
    SaveStore.write_json(SETTINGS_PATH, settings)
    SaveStore.write_json(PROFILE_PATH, profile)
    SaveStore.write_json(WORLD_STATE_PATH, world_state)


func record_interaction(kind: String) -> void:
    profile["total_interactions"] = int(profile.get("total_interactions", 0)) + 1
    profile = _call_profile_service("identity", "record_interaction", [profile, kind])
    var xp_curve := UnlockTable.xp_curve()
    profile = _call_profile_service(
        "bond",
        "apply_interaction",
        [profile, kind, UnlockTable.xp_per_level(), UnlockTable.max_level(), xp_curve]
    )
    profile = _call_profile_service(
        "mood",
        "apply_interaction",
        [profile, kind, is_quiet_hours_now()]
    )
    _sync_growth_mode_flags()
    profile = _call_profile_service("growth", "apply_interaction", [profile, kind])
    world_state = _call_world_service("economy", "grant_meso", [world_state, "interaction:%s" % kind, 1])
    _refresh_unlocks()
    flush()


func apply_behavior(action_id: String) -> void:
    world_state["last_action"] = action_id
    world_state["last_tick_unix"] = Time.get_unix_time_from_system()

    if action_id == "gift":
        profile["gifts_seen"] = int(profile.get("gifts_seen", 0)) + 1
        world_state = _call_world_service("economy", "grant_meso", [world_state, "behavior:gift", 3])
    elif action_id == "visitor":
        world_state = _call_world_service("economy", "grant_meso", [world_state, "behavior:visitor", 2])
    elif action_id == "sleep":
        world_state = _call_world_service("economy", "grant_meso", [world_state, "behavior:sleep", 1])

    var xp_curve := UnlockTable.xp_curve()
    profile = _call_profile_service(
        "bond",
        "apply_behavior",
        [profile, action_id, UnlockTable.xp_per_level(), UnlockTable.max_level(), xp_curve]
    )
    profile = _call_profile_service("mood", "apply_behavior", [profile, action_id])
    _sync_growth_mode_flags()
    profile = _call_profile_service("growth", "apply_behavior", [profile, action_id])
    profile = _call_profile_service("identity", "record_behavior", [profile, action_id])
    _refresh_unlocks()
    flush()


func apply_loaded_pack(pack_id: String, manifest: Dictionary) -> void:
    settings["selectedPackId"] = pack_id
    world_state["activePackId"] = pack_id
    world_state["activeVisualPackId"] = pack_id
    world_state["activePackManifestVersion"] = str(manifest.get("version", ""))
    profile = _call_profile_service("identity", "configure_from_manifest", [profile, manifest], false)
    world_state = _call_world_service("world", "configure_from_manifest", [world_state, manifest], false)
    var economy_manifest := _resolve_economy_manifest(manifest)
    world_state = _call_world_service("economy", "configure_from_manifest", [world_state, economy_manifest], false)
    world_state["activeEconomyPackId"] = str(economy_manifest.get("id", CORE_ECONOMY_PACK_ID))
    _backfill_inventory_from_catalog()
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
    profile = _ensure_profile_modules(profile)
    _refresh_unlocks()
    flush()
    return true


func get_behavior_context(allowed_actions: Array = []) -> Dictionary:
    var mood_ctx: Dictionary = _call_service_with_fallback("mood", "get_context", [profile], {})
    var growth_ctx: Dictionary = _call_service_with_fallback("growth", "get_context", [profile], {})
    var identity_ctx: Dictionary = _call_service_with_fallback("identity", "get_context", [profile], {})
    var world_snapshot: Dictionary = _call_service_with_fallback("world", "get_snapshot", [world_state], {})
    return {
        "is_night": _is_night(),
        "bond_level": int(profile.get("bond_level", 1)),
        "trust_value": float(profile.get("trust_value", 0.2)),
        "quiet_mode": is_quiet_hours_now(),
        "event_frequency": str(settings.get("eventFrequency", "normal")),
        "interaction_intensity": str(settings.get("interactionIntensity", "balanced")),
        "quiet_strictness": str(settings.get("quietModeStrictness", "balanced")),
        "allowed_actions": allowed_actions,
        "unlocked_actions": get_unlocked_actions(),
        "dominant_mood": str(mood_ctx.get("dominant_mood", "calm")),
        "growth_stage": int(growth_ctx.get("growth_stage", 1)),
        "top_trait": str(identity_ctx.get("top_trait", "curiosity")),
        "home_mode": str(world_snapshot.get("home_mode", "overlay")),
    }


func get_last_active_summary() -> String:
    return str(profile.get("last_active_summary", ""))


func get_continuity_digest() -> Array:
    var digest = profile.get("continuity_digest", [])
    return digest if typeof(digest) == TYPE_ARRAY else []


func get_latest_continuity_line() -> String:
    var digest := get_continuity_digest()
    if digest.is_empty():
        return ""
    var tail = digest[-1]
    if typeof(tail) != TYPE_DICTIONARY:
        return ""
    return str((tail as Dictionary).get("line", ""))


func get_continuity_hint() -> String:
    if not bool(settings.get("continuityDigestEnabled", true)):
        return ""
    var digest := get_continuity_digest()
    if digest.size() < 2:
        return ""
    var first = digest[digest.size() - 2]
    var last = digest[digest.size() - 1]
    if typeof(first) != TYPE_DICTIONARY or typeof(last) != TYPE_DICTIONARY:
        return ""
    var a := str((first as Dictionary).get("line", ""))
    var b := str((last as Dictionary).get("line", ""))
    if a == "" or b == "":
        return ""
    return "Last time: %s Now: %s" % [a, b]


func clear_last_active_summary() -> void:
    profile["last_active_summary"] = ""
    SaveStore.write_json(PROFILE_PATH, profile)


func open_reward_box(box_id: String) -> Dictionary:
    var seed := int(profile.get("personality_seed", 0)) + int(Time.get_unix_time_from_system())
    var result = _call_service_with_fallback("economy", "open_reward_box", [world_state, box_id, seed], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "service_failure"}
    if bool(result.get("ok", false)):
        var next_world = result.get("world_state", {})
        if typeof(next_world) == TYPE_DICTIONARY:
            world_state = next_world
            flush()
        return {
            "ok": true,
            "reason": "",
            "item_id": str(result.get("item", {}).get("id", "")),
            "item_name": str(result.get("item", {}).get("name", "")),
            "item_rarity": str(result.get("item", {}).get("rarity", "")),
            "duplicate": bool(result.get("duplicate", false)),
            "recycle_meso": int(result.get("recycleMeso", result.get("recycleCrystals", 0))),
            "recycle_crystals": int(result.get("recycleCrystals", 0)),
        }
    return {"ok": false, "reason": str(result.get("reason", "unknown"))}


func get_reward_box_ids() -> Array:
    var ids = _call_service_with_fallback("economy", "list_reward_box_ids", [world_state], [])
    return ids if typeof(ids) == TYPE_ARRAY else []


func tick_world_events(now_unix: int) -> Dictionary:
    var result = _call_service_with_fallback("world", "tick_world", [world_state, profile, now_unix], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {}
    var next_world = result.get("world_state", {})
    if typeof(next_world) == TYPE_DICTIONARY:
        world_state = next_world
    if bool(result.get("changed", false)):
        flush()
    var prompt = result.get("prompt", {})
    return prompt if typeof(prompt) == TYPE_DICTIONARY else {}


func get_world_snapshot() -> Dictionary:
    var snapshot = _call_service_with_fallback("world", "get_snapshot", [world_state], {})
    return snapshot if typeof(snapshot) == TYPE_DICTIONARY else {}


func set_home_mode(mode: String) -> void:
    world_state = _call_world_service("world", "set_home_mode", [world_state, mode], false)
    flush()


func complete_pending_quest() -> Dictionary:
    var result = _call_service_with_fallback("world", "complete_pending_quest", [world_state], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "service_failure"}
    if not bool(result.get("ok", false)):
        return {"ok": false, "reason": str(result.get("reason", "unknown"))}

    var next_world = result.get("world_state", {})
    if typeof(next_world) == TYPE_DICTIONARY:
        world_state = next_world

    _apply_reward_payload("quest:%s" % str(result.get("quest", {}).get("id", "")), result.get("rewards", {}))
    flush()
    return {
        "ok": true,
        "quest_id": str(result.get("quest", {}).get("id", "")),
        "npc_name": str(result.get("npcName", "Villager")),
        "meso": int(result.get("rewards", {}).get("meso", result.get("rewards", {}).get("crystals", 0))),
        "crystals": int(result.get("rewards", {}).get("crystals", 0)),
        "item_name": str(_resolve_reward_item_name(result.get("rewards", {}).get("itemId", ""))),
    }


func resolve_pending_encounter(engage: bool) -> Dictionary:
    var result = _call_service_with_fallback("world", "resolve_pending_encounter", [world_state, engage], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "service_failure"}
    if not bool(result.get("ok", false)):
        return {"ok": false, "reason": str(result.get("reason", "unknown"))}

    var next_world = result.get("world_state", {})
    if typeof(next_world) == TYPE_DICTIONARY:
        world_state = next_world

    var encounter_id := str(result.get("encounter", {}).get("id", ""))
    var source := "encounter:%s:%s" % [encounter_id, "engage" if engage else "skip"]
    _apply_reward_payload(source, result.get("rewards", {}))
    var drop_item_name := ""
    if engage:
        var table_id := str(result.get("dropTableId", ""))
        if table_id != "":
            var drop_ctx := {
                "level": int(profile.get("bond_level", 1)),
                "job_id": str(profile.get("job_id", "explorer_buddy")),
                "job_primary_stat": str(profile.get("job_primary_stat", "charisma")),
                "job_drop_bias": profile.get("job_drop_bias", []),
            }
            var drop_seed := int(profile.get("personality_seed", 0)) + int(Time.get_unix_time_from_system())
            var drop_result = _call_service_with_fallback(
                "economy",
                "roll_drop_table",
                [world_state, table_id, drop_ctx, drop_seed],
                {}
            )
            if typeof(drop_result) == TYPE_DICTIONARY and bool(drop_result.get("ok", false)):
                if typeof(drop_result.get("world_state", null)) == TYPE_DICTIONARY:
                    world_state = drop_result.get("world_state", {})
                drop_item_name = str(drop_result.get("item", {}).get("name", ""))
    flush()
    return {
        "ok": true,
        "encounter_id": encounter_id,
        "engaged": engage,
        "npc_name": str(result.get("npcName", "Villager")),
        "meso": int(result.get("rewards", {}).get("meso", result.get("rewards", {}).get("crystals", 0))),
        "crystals": int(result.get("rewards", {}).get("crystals", 0)),
        "item_name": str(_resolve_reward_item_name(result.get("rewards", {}).get("itemId", ""))),
        "drop_item_name": drop_item_name,
    }


func get_telemetry_snapshot() -> Dictionary:
    var unlock_count := 0
    var unlocks = profile.get("unlocks", [])
    if typeof(unlocks) == TYPE_ARRAY:
        unlock_count = (unlocks as Array).size()
    var econ_snapshot: Dictionary = _call_service_with_fallback("economy", "get_snapshot", [world_state], {})
    var world_snapshot: Dictionary = _call_service_with_fallback("world", "get_snapshot", [world_state], {})
    var catalog_size := 0
    var catalog_variant = world_state.get("item_catalog", {})
    if typeof(catalog_variant) == TYPE_DICTIONARY:
        catalog_size = (catalog_variant as Dictionary).size()
    var xp_progress := _xp_progress_snapshot(
        int(profile.get("bond_xp", 0)),
        int(profile.get("bond_level", 1))
    )
    return {
        "bond_level": int(profile.get("bond_level", 1)),
        "bond_xp": int(profile.get("bond_xp", 0)),
        "trust_value": float(profile.get("trust_value", 0.2)),
        "mood": str(profile.get("dominant_mood", "calm")),
        "growth_stage": int(profile.get("growth_stage", 1)),
        "job_id": str(profile.get("job_id", "explorer_buddy")),
        "job_name": str(profile.get("job_name", "Explorer Buddy")),
        "job_primary_stat": str(profile.get("job_primary_stat", "charisma")),
        "job_drop_bias": profile.get("job_drop_bias", []),
        "stat_points_unspent": int(profile.get("stat_points_unspent", 0)),
        "stat_points_spent": int(profile.get("stat_points_spent", 0)),
        "total_interactions": int(profile.get("total_interactions", 0)),
        "gifts_seen": int(profile.get("gifts_seen", 0)),
        "active_pack": str(world_state.get("activePackId", settings.get("selectedPackId", "core_pack"))),
        "visual_pack_id": str(world_state.get("activeVisualPackId", world_state.get("activePackId", settings.get("selectedPackId", "core_pack")))),
        "economy_pack_id": str(world_state.get("activeEconomyPackId", CORE_ECONOMY_PACK_ID)),
        "catalog_size": catalog_size,
        "xp_into_level": int(xp_progress.get("into", 0)),
        "xp_to_next": int(xp_progress.get("need", UnlockTable.xp_per_level())),
        "xp_is_max": bool(xp_progress.get("is_max", false)),
        "last_action": str(world_state.get("last_action", "idle")),
        "last_event_id": str(world_state.get("last_event_id", "")),
        "unlock_count": unlock_count,
        "meso": int(econ_snapshot.get("meso", econ_snapshot.get("crystals", 0))),
        "crystals": int(econ_snapshot.get("meso", econ_snapshot.get("crystals", 0))),
        "inventory_count": int(econ_snapshot.get("inventory_count", 0)),
        "inventory_quarantine_count": int(econ_snapshot.get("quarantine_count", 0)),
        "duplicate_recycle_total": int(econ_snapshot.get("duplicate_recycle_total", 0)),
        "box_open_stats": econ_snapshot.get("box_open_stats", {}),
        "home_scene_id": str(world_snapshot.get("home_scene_id", "cozy_starter_room")),
        "home_mode": str(world_snapshot.get("home_mode", "overlay")),
        "home_wall_decor": str(world_snapshot.get("home_wall_decor", "")),
        "pending_quest_id": str(world_snapshot.get("pending_quest_id", "")),
        "pending_encounter_id": str(world_snapshot.get("pending_encounter_id", "")),
        "last_world_event_id": str(world_snapshot.get("last_world_event_id", "")),
        "interaction_intensity": str(settings.get("interactionIntensity", "balanced")),
        "quiet_strictness": str(settings.get("quietModeStrictness", "balanced")),
        "continuity_digest_count": get_continuity_digest().size(),
    }


func get_stats_snapshot() -> Dictionary:
    var growth_ctx: Dictionary = _call_service_with_fallback("growth", "get_context", [profile], {})
    var stats_variant = growth_ctx.get("stats", {})
    var stats: Dictionary = stats_variant if typeof(stats_variant) == TYPE_DICTIONARY else {}
    var xp_progress := _xp_progress_snapshot(
        int(profile.get("bond_xp", 0)),
        int(profile.get("bond_level", 1))
    )
    return {
        "stats": stats.duplicate(true),
        "growth_stage": int(profile.get("growth_stage", 1)),
        "bond_level": int(profile.get("bond_level", 1)),
        "bond_xp": int(profile.get("bond_xp", 0)),
        "xp_into_level": int(xp_progress.get("into", 0)),
        "xp_to_next": int(xp_progress.get("need", UnlockTable.xp_per_level())),
        "xp_is_max": bool(xp_progress.get("is_max", false)),
        "job_id": str(profile.get("job_id", "explorer_buddy")),
        "job_name": str(profile.get("job_name", "Explorer Buddy")),
        "job_primary_stat": str(profile.get("job_primary_stat", "charisma")),
        "job_drop_bias": profile.get("job_drop_bias", []),
        "auto_assign_stats": bool(profile.get("auto_assign_stats", false)),
        "stat_points_unspent": int(profile.get("stat_points_unspent", 0)),
        "stat_points_spent": int(profile.get("stat_points_spent", 0)),
    }


func allocate_stat_point(stat_id: String, count: int = 1) -> Dictionary:
    var result = _call_service_with_fallback("growth", "allocate_stat_point", [profile, stat_id, count], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "service_failure"}
    if bool(result.get("ok", false)):
        var next_profile = result.get("profile", {})
        if typeof(next_profile) == TYPE_DICTIONARY:
            profile = next_profile
            _refresh_unlocks()
            flush()
        return {
            "ok": true,
            "reason": "",
            "stat_id": str(result.get("stat_id", stat_id)),
            "spent": int(result.get("spent", 0)),
            "new_value": int(result.get("new_value", 0)),
        }
    return {"ok": false, "reason": str(result.get("reason", "unknown"))}


func get_inventory_snapshot() -> Dictionary:
    var snap = _call_service_with_fallback("economy", "get_inventory_snapshot", [world_state], {})
    if typeof(snap) != TYPE_DICTIONARY:
        return {
            "meso": 0,
            "crystals": 0,
            "inventory": [],
            "equipped_slots": {},
            "inventory_count": 0,
            "quarantine_count": 0,
        }
    return snap


func repair_inventory_catalog() -> Dictionary:
    var result = _call_service_with_fallback("economy", "repair_inventory_from_catalog", [world_state], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "service_failure"}
    if typeof(result.get("world_state", null)) == TYPE_DICTIONARY:
        world_state = result.get("world_state", {})
        flush()
    return {
        "ok": bool(result.get("ok", false)),
        "changed": bool(result.get("changed", false)),
        "recovered_count": int(result.get("recovered_count", 0)),
        "remaining_quarantine_count": int(result.get("remaining_quarantine_count", 0)),
    }


func clear_inventory_debug() -> Dictionary:
    var result = _call_service_with_fallback("economy", "clear_inventory", [world_state, true], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "service_failure"}
    if typeof(result.get("world_state", null)) == TYPE_DICTIONARY:
        world_state = result.get("world_state", {})
        flush()
    return {
        "ok": bool(result.get("ok", false)),
        "reason": str(result.get("reason", "")),
        "removed_count": int(result.get("removed_count", 0)),
        "unequipped_count": int(result.get("unequipped_count", 0)),
        "cleared_quarantine": bool(result.get("cleared_quarantine", false)),
    }


func use_inventory_item(instance_id: int) -> Dictionary:
    var item_lookup = _call_service_with_fallback("economy", "get_item_instance", [world_state, instance_id], {})
    if typeof(item_lookup) != TYPE_DICTIONARY or not bool(item_lookup.get("ok", false)):
        return {"ok": false, "reason": str(item_lookup.get("reason", "missing_item"))}
    var item_variant = item_lookup.get("item", {})
    if typeof(item_variant) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "invalid_item"}
    var item: Dictionary = item_variant
    var category := str(item.get("category", "")).to_lower()
    if category == "gear":
        return {"ok": false, "reason": "equip_only"}
    if not _is_usable_item_category(category):
        return {"ok": false, "reason": "not_usable_category"}

    var before := {
        "bond_level": int(profile.get("bond_level", 1)),
        "bond_xp": int(profile.get("bond_xp", 0)),
        "mood": str(profile.get("dominant_mood", "calm")),
        "trust_value": float(profile.get("trust_value", 0.2)),
        "stat_points_unspent": int(profile.get("stat_points_unspent", 0)),
        "meso": int(get_inventory_snapshot().get("meso", get_inventory_snapshot().get("crystals", 0))),
        "crystals": int(get_inventory_snapshot().get("meso", get_inventory_snapshot().get("crystals", 0))),
    }

    var consume_result = _call_service_with_fallback("economy", "consume_item_instance", [world_state, instance_id], {})
    if typeof(consume_result) != TYPE_DICTIONARY or not bool(consume_result.get("ok", false)):
        return {"ok": false, "reason": str(consume_result.get("reason", "consume_failed"))}
    var next_world = consume_result.get("world_state", {})
    if typeof(next_world) == TYPE_DICTIONARY:
        world_state = next_world

    _apply_item_use_effect(item)
    _refresh_unlocks()
    flush()
    var after := {
        "bond_level": int(profile.get("bond_level", 1)),
        "bond_xp": int(profile.get("bond_xp", 0)),
        "mood": str(profile.get("dominant_mood", "calm")),
        "trust_value": float(profile.get("trust_value", 0.2)),
        "stat_points_unspent": int(profile.get("stat_points_unspent", 0)),
        "meso": int(get_inventory_snapshot().get("meso", get_inventory_snapshot().get("crystals", 0))),
        "crystals": int(get_inventory_snapshot().get("meso", get_inventory_snapshot().get("crystals", 0))),
    }
    return {
        "ok": true,
        "reason": "",
        "item": item,
        "effect_summary": _build_item_use_effect_summary(item, before, after),
        "before": before,
        "after": after,
    }


func equip_inventory_item(instance_id: int) -> Dictionary:
    var result = _call_service_with_fallback("economy", "equip_item_instance", [world_state, instance_id], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "service_failure"}
    if not bool(result.get("ok", false)):
        return {"ok": false, "reason": str(result.get("reason", "equip_failed"))}
    var next_world = result.get("world_state", {})
    if typeof(next_world) == TYPE_DICTIONARY:
        world_state = next_world
    flush()
    return {
        "ok": true,
        "reason": "",
        "slot": str(result.get("slot", "")),
        "item": result.get("item", {}),
    }


func unequip_inventory_slot(slot_id: String) -> Dictionary:
    var result = _call_service_with_fallback("economy", "unequip_slot", [world_state, slot_id], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "service_failure"}
    if not bool(result.get("ok", false)):
        return {"ok": false, "reason": str(result.get("reason", "unequip_failed"))}
    var next_world = result.get("world_state", {})
    if typeof(next_world) == TYPE_DICTIONARY:
        world_state = next_world
    flush()
    return {
        "ok": true,
        "reason": "",
        "slot": str(result.get("slot", "")),
    }


func seed_test_inventory() -> Dictionary:
    var catalog_variant = world_state.get("item_catalog", {})
    if typeof(catalog_variant) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "missing_catalog", "added": 0, "categories": []}
    var catalog: Dictionary = catalog_variant
    if catalog.is_empty():
        return {"ok": false, "reason": "empty_catalog", "added": 0, "categories": []}

    # Prefer known WZ-linked items first so icon QA has distinct, visible icons.
    var target_item_ids := [
        "wz-tri-colored-dango",
        "wz-fruity-candy",
        "wz-green-halloween-stick-candy",
        "wz-stone-golem-rubble",
        "wz-ridleys-stone",
        "wz-rocky-mask-doll",
    ]
    var used_ids := {}
    var added := 0
    var added_categories: Array = []

    for id_variant in target_item_ids:
        var item_id := str(id_variant)
        if item_id == "" or not catalog.has(item_id):
            continue
        var row_variant = catalog.get(item_id, {})
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var selected_item: Dictionary = (row_variant as Dictionary).duplicate(true)
        var category := str(selected_item.get("category", "")).to_lower()
        world_state = _call_world_service(
            "economy",
            "grant_item",
            [world_state, "debug:seed_inventory:%s" % category, selected_item],
            false
        )
        used_ids[item_id] = true
        added += 1
        if category != "" and not added_categories.has(category):
            added_categories.append(category)

    # Ensure tab coverage if a category has no seeded item from the preferred set.
    var target_categories := ["food", "gifts", "gear", "decor", "materials", "training_items"]
    for cat_variant in target_categories:
        var category := str(cat_variant)
        if added_categories.has(category):
            continue
        var selected_item: Dictionary = {}
        for row_variant in catalog.values():
            if typeof(row_variant) != TYPE_DICTIONARY:
                continue
            var row: Dictionary = row_variant
            var row_id := str(row.get("id", ""))
            if used_ids.has(row_id):
                continue
            if str(row.get("category", "")).to_lower() != category:
                continue
            selected_item = row.duplicate(true)
            break
        if selected_item.is_empty():
            continue
        world_state = _call_world_service(
            "economy",
            "grant_item",
            [world_state, "debug:seed_inventory:%s" % category, selected_item],
            false
        )
        var selected_id := str(selected_item.get("id", ""))
        if selected_id != "":
            used_ids[selected_id] = true
        added += 1
        added_categories.append(category)

    # Add multiple gear-slot examples so model swap testing has visible alternatives.
    var target_gear_slots := [
        "weapon",
        "hat",
        "shield",
        "cape",
        "overall",
        "top",
        "bottom",
        "shoes",
        "gloves",
        "face_accessory",
        "eye_accessory",
        "earrings",
        "ring1",
        "pendant1",
        "belt",
        "shoulder",
    ]
    var added_gear_slots := {}
    for row_variant in catalog.values():
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        if str(row.get("category", "")).to_lower() != "gear":
            continue
        var row_id := str(row.get("id", ""))
        if row_id == "" or used_ids.has(row_id):
            continue
        var slot := str(row.get("equipSlot", "")).to_lower().strip_edges()
        if slot == "" or not target_gear_slots.has(slot) or added_gear_slots.has(slot):
            continue
        var selected_item: Dictionary = row.duplicate(true)
        world_state = _call_world_service(
            "economy",
            "grant_item",
            [world_state, "debug:seed_inventory:gear:%s" % slot, selected_item],
            false
        )
        used_ids[row_id] = true
        added_gear_slots[slot] = true
        added += 1

    flush()
    return {"ok": added > 0, "reason": "", "added": added, "categories": added_categories}


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


func get_bond_tier() -> Dictionary:
    var level := int(profile.get("bond_level", 1))
    var tier := UnlockTable.cadence_for_level(level)
    var mood := str(profile.get("dominant_mood", "calm"))
    if mood in ["worried", "sleepy"]:
        var phrases: Array = tier.get("idle_phrases", []).duplicate(true)
        if not phrases.has("Staying near you helps."):
            phrases.append("Staying near you helps.")
        tier["idle_phrases"] = phrases
    return tier


func is_first_run() -> bool:
    return not bool(settings.get("firstRunSeen", false))


func mark_first_run_seen() -> void:
    settings["firstRunSeen"] = true
    SaveStore.write_json(SETTINGS_PATH, settings)


func _ensure_profile_modules(input_profile: Dictionary) -> Dictionary:
    var merged := input_profile.duplicate(true)
    merged = _call_profile_service("identity", "ensure_profile", [merged], false)
    merged = _call_profile_service("mood", "ensure_profile", [merged], false)
    merged = _call_profile_service("bond", "ensure_profile", [merged], false)
    merged = _call_profile_service("growth", "ensure_profile", [merged], false)
    return merged


func _reconcile_progression_from_xp() -> void:
    var xp_curve := UnlockTable.xp_curve()
    profile = _call_profile_service(
        "bond",
        "reconcile_profile",
        [profile, UnlockTable.xp_per_level(), UnlockTable.max_level(), xp_curve],
        false
    )
    profile = _call_profile_service("growth", "reconcile_stat_points", [profile], false)


func _ensure_world_modules(input_world: Dictionary) -> Dictionary:
    var merged := input_world.duplicate(true)
    merged = _call_world_service("world", "ensure_world_state", [merged], false)
    merged = _call_world_service("economy", "ensure_world_state", [merged], false)
    return merged


func _resolve_economy_manifest(visual_manifest: Dictionary) -> Dictionary:
    var loaded_core := ContentLoader.load_pack(CORE_ECONOMY_PACK_ID)
    if bool(loaded_core.get("ok", false)):
        var core_manifest_variant = loaded_core.get("manifest", null)
        if typeof(core_manifest_variant) == TYPE_DICTIONARY:
            return (core_manifest_variant as Dictionary).duplicate(true)
    return visual_manifest.duplicate(true)


func _backfill_inventory_from_catalog() -> bool:
    var result = _call_service_with_fallback("economy", "backfill_inventory_from_catalog", [world_state], {})
    if typeof(result) != TYPE_DICTIONARY:
        return false
    if typeof(result.get("world_state", null)) == TYPE_DICTIONARY:
        world_state = result.get("world_state", {})
    return bool(result.get("changed", false))


func _run_inventory_backfill_migration_once() -> bool:
    var applied_version := int(settings.get("inventoryBackfillMigrationVersion", 0))
    var changed := _backfill_inventory_from_catalog()
    if applied_version < INVENTORY_BACKFILL_MIGRATION_VERSION:
        settings["inventoryBackfillMigrationVersion"] = INVENTORY_BACKFILL_MIGRATION_VERSION
        return true
    return changed


func _apply_reward_payload(source_type: String, rewards_variant: Variant) -> void:
    if typeof(rewards_variant) != TYPE_DICTIONARY:
        return
    var rewards: Dictionary = rewards_variant
    var meso := int(rewards.get("meso", rewards.get("crystals", 0)))
    if meso > 0:
        world_state = _call_world_service("economy", "grant_meso", [world_state, source_type, meso], false)

    var item_id := str(rewards.get("itemId", ""))
    if item_id == "":
        return
    var item := _resolve_reward_item(item_id)
    world_state = _call_world_service("economy", "grant_item", [world_state, source_type, item], false)


func _apply_item_use_effect(item: Dictionary) -> void:
    var category := str(item.get("category", "")).to_lower()
    var effect_variant = item.get("effectProfile", {})
    var effect: Dictionary = effect_variant if typeof(effect_variant) == TYPE_DICTIONARY else {}

    if category == "food":
        var mood := str(effect.get("mood", "happy"))
        if mood == "":
            mood = "happy"
        profile["dominant_mood"] = mood
        profile["trust_value"] = clampf(float(profile.get("trust_value", 0.2)) + 0.01, 0.0, 1.0)
        world_state = _call_world_service("economy", "grant_meso", [world_state, "item_use:food", 1], false)
        return

    if category == "gifts":
        var xp_curve := UnlockTable.xp_curve()
        profile = _call_profile_service(
            "bond",
            "apply_interaction",
            [profile, "gift", UnlockTable.xp_per_level(), UnlockTable.max_level(), xp_curve],
            false
        )
        profile = _call_profile_service(
            "mood",
            "apply_interaction",
            [profile, "gift", is_quiet_hours_now()],
            false
        )
        return

    if category == "training_items":
        profile["stat_points_unspent"] = int(profile.get("stat_points_unspent", 0)) + 1
        return

    if category == "materials":
        world_state = _call_world_service("economy", "grant_meso", [world_state, "item_use:materials", 1], false)
        return


func _is_usable_item_category(category: String) -> bool:
    return category in ["food", "gifts", "training_items", "materials"]


func _build_item_use_effect_summary(item: Dictionary, before: Dictionary, after: Dictionary) -> Array:
    var lines: Array = []
    var category := str(item.get("category", "")).to_lower()
    lines.append("category=%s" % category)

    var before_mood := str(before.get("mood", ""))
    var after_mood := str(after.get("mood", ""))
    if before_mood != after_mood and after_mood != "":
        lines.append("mood %s -> %s" % [before_mood, after_mood])

    var before_meso := int(before.get("meso", before.get("crystals", 0)))
    var after_meso := int(after.get("meso", after.get("crystals", 0)))
    var meso_delta := after_meso - before_meso
    if meso_delta != 0:
        lines.append("meso %+d" % meso_delta)

    var before_xp := int(before.get("bond_xp", 0))
    var after_xp := int(after.get("bond_xp", 0))
    var before_level := int(before.get("bond_level", 1))
    var after_level := int(after.get("bond_level", 1))
    if before_level != after_level:
        lines.append("bond level %d -> %d" % [before_level, after_level])
    if after_xp != before_xp:
        lines.append("bond xp %+d" % (after_xp - before_xp))

    var before_trust := float(before.get("trust_value", 0.0))
    var after_trust := float(after.get("trust_value", 0.0))
    if absf(after_trust - before_trust) >= 0.001:
        lines.append("trust %+0.02f" % (after_trust - before_trust))

    var before_sp := int(before.get("stat_points_unspent", 0))
    var after_sp := int(after.get("stat_points_unspent", 0))
    if after_sp != before_sp:
        lines.append("stat points %+d" % (after_sp - before_sp))

    if lines.size() <= 1:
        lines.append("effect applied")
    return lines


func _resolve_reward_item(item_id: String) -> Dictionary:
    var catalog_variant = world_state.get("item_catalog", {})
    if typeof(catalog_variant) == TYPE_DICTIONARY:
        var catalog: Dictionary = catalog_variant
        if catalog.has(item_id) and typeof(catalog[item_id]) == TYPE_DICTIONARY:
            return (catalog[item_id] as Dictionary).duplicate(true)
    return {
        "id": item_id,
        "name": item_id.capitalize(),
        "category": "quest_items",
        "rarity": "common",
        "primaryTheme": "cozy",
        "sourceType": "world_fallback",
    }


func _resolve_reward_item_name(item_id: String) -> String:
    if item_id == "":
        return ""
    var item := _resolve_reward_item(item_id)
    return str(item.get("name", item_id))


func _refresh_while_away_report() -> void:
    var now_unix := Time.get_unix_time_from_system()
    var report: Dictionary = _call_service_with_fallback(
        "report",
        "generate_while_away_report",
        [profile, world_state, now_unix],
        {}
    )
    var summary := str(report.get("summary", ""))
    if summary != "":
        profile["last_active_summary"] = summary
        _append_continuity_line(summary, int(report.get("elapsed_minutes", 0)))


func _append_continuity_line(summary: String, elapsed_minutes: int) -> void:
    if summary == "" or not bool(settings.get("continuityDigestEnabled", true)):
        return
    var digest: Array = get_continuity_digest()
    digest.append(
        {
            "line": summary,
            "elapsed_minutes": elapsed_minutes,
            "timestamp": Time.get_unix_time_from_system(),
        }
    )
    if digest.size() > 10:
        digest = digest.slice(digest.size() - 10, digest.size())
    profile["continuity_digest"] = digest


func _call_profile_service(name: String, method: String, args: Array, write_back: bool = true) -> Dictionary:
    var fallback := profile.duplicate(true) if not profile.is_empty() else _default_profile()
    var result = _call_service_with_fallback(name, method, args, fallback)
    if typeof(result) != TYPE_DICTIONARY:
        return fallback
    if write_back:
        profile = result
    return result


func _call_world_service(name: String, method: String, args: Array, write_back: bool = true) -> Dictionary:
    var fallback := world_state.duplicate(true) if not world_state.is_empty() else _default_world_state()
    var result = _call_service_with_fallback(name, method, args, fallback)
    if typeof(result) == TYPE_DICTIONARY and result.has("world_state") and typeof(result.get("world_state")) == TYPE_DICTIONARY:
        result = result.get("world_state")
    if typeof(result) != TYPE_DICTIONARY:
        return fallback
    if write_back:
        world_state = result
    return result


func _call_service_with_fallback(name: String, method: String, args: Array, fallback: Variant) -> Variant:
    if not _services.has(name):
        return fallback
    var service = _services[name]
    if service == null or not service.has_method(method):
        return fallback
    var value = service.callv(method, args)
    if value == null:
        return fallback
    return value


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
        "promptFrequency": "normal",
        "interactionIntensity": "balanced",
        "quietModeStrictness": "balanced",
        "chatTextSize": "m",
        "continuityDigestEnabled": true,
        "supportHintsEnabled": true,
        "productivityOptIn": false,
        "focusCelebrateMinutes": 20,
        "breakSuggestMinutes": 45,
        "lateSessionHourStart": 23,
        "idleCheckinMinutes": 20,
        "selectedPackId": "core_pack",
        "desktopFloorOffsetAdjust": 0.0,
        "preferredScreen": 0,
        "lastWindowPosition": [120, 120],
        "firstRunSeen": false,
        "inventoryBackfillMigrationVersion": 0,
    }


func _default_profile() -> Dictionary:
    return {
        "schemaVersion": 2,
        "name": "Buddy",
        "base_type": "sprout",
        "personality_seed": Time.get_unix_time_from_system(),
        "personality_seed_tag": "curious",
        "current_personality_profile": {
            "curiosity": 0.55,
            "sociability": 0.45,
            "bravery": 0.40,
            "playfulness": 0.50,
            "diligence": 0.45,
            "independence": 0.35,
            "empathy": 0.55,
            "competitiveness": 0.30,
        },
        "likes": [],
        "dislikes": [],
        "interests": ["cozy"],
        "active_goals": ["settle-in"],
        "trait_history_summary": [],
        "interaction_counters": {},
        "bond_xp": 0,
        "bond_level": 1,
        "trust_value": 0.2,
        "recent_affection_memory": [],
        "recent_neglect_summary": [],
        "dominant_mood": "calm",
        "mood_modifiers": {
            "energy_strain": 0.0,
            "social_fulfillment": 0.0,
            "comfort": 0.5,
            "confidence": 0.5,
        },
        "mood_stability": 0.7,
        "last_mood_change_reason": "init",
        "growth_stage": 1,
        "stats": {
            "strength": 1,
            "dexterity": 1,
            "charisma": 1,
            "endurance": 1,
            "wisdom": 1,
            "knowledge": 1,
        },
        "milestone_flags": [],
        "trait_shifts": [],
        "unlocked_behaviors": [],
        "stat_points_unspent": 0,
        "stat_points_spent": 0,
        "gifts_seen": 0,
        "total_interactions": 0,
        "last_active_summary": "",
        "continuity_digest": [],
        "unlocks": [],
        "job_id": "explorer_buddy",
        "job_name": "Explorer Buddy",
        "job_primary_stat": "charisma",
        "job_drop_bias": [],
        "auto_assign_stats": false,
    }


func _sync_growth_mode_flags() -> void:
    profile["auto_assign_stats"] = str(settings.get("interactionIntensity", "balanced")).to_lower() == "idle"


func _default_world_state() -> Dictionary:
    return {
        "schemaVersion": 2,
        "last_action": "idle",
        "last_tick_unix": 0,
        "last_event_id": "",
        "last_event_action": "",
        "last_event_unix": 0,
        "activePackId": "core_pack",
        "activeVisualPackId": "core_pack",
        "activeEconomyPackId": "core_pack",
        "activePackManifestVersion": "",
        "event_hour_buckets": {},
        "event_day_buckets": {},
        "wallet": {"meso": 0, "crystals": 0},
        "inventory": [],
        "reward_transactions": [],
        "reward_boxes": {},
        "item_catalog": {},
        "world": {},
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


func _is_night() -> bool:
    var now := Time.get_datetime_dict_from_system()
    var hour := int(now.get("hour", 12))
    return hour < 7 or hour >= 22


func _xp_progress_snapshot(total_xp: int, level: int) -> Dictionary:
    var max_level := UnlockTable.max_level()
    var safe_level := clampi(level, 1, max_level)
    if safe_level >= max_level:
        return {"into": total_xp, "need": 0, "is_max": true}
    var curve := UnlockTable.xp_curve()
    if curve.size() >= 2 and safe_level >= 1 and safe_level < curve.size():
        var current_floor := int(curve[safe_level - 1])
        var next_floor := int(curve[safe_level])
        return {
            "into": maxi(0, total_xp - current_floor),
            "need": maxi(1, next_floor - current_floor),
            "is_max": false,
        }
    var xp_per_level := UnlockTable.xp_per_level()
    return {
        "into": total_xp % xp_per_level,
        "need": xp_per_level,
        "is_max": false,
    }
