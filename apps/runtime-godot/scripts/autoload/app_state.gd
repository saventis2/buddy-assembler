extends Node

const SaveStore = preload("res://scripts/persistence/save_store.gd")
const SchemaMigrations = preload("res://scripts/persistence/schema_migrations.gd")
const MindServiceScript = preload("res://scripts/services/mind_service.gd")
const UnlockTable = preload("res://scripts/progression/unlock_table.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")
const Whereabouts = preload("res://scripts/persistence/buddy_whereabouts.gd")

const SETTINGS_PATH := "user://settings.json"
const PROFILE_PATH := "user://profile.json"
const WORLD_STATE_PATH := "user://world_state.json"
const CORE_ECONOMY_PACK_ID := "core_pack"
const INVENTORY_BACKFILL_MIGRATION_VERSION := 2
const BACKUP_ROOT := "user://backups"
const BORN_ON_THE_LAND := "land"
# A process started with this user argument (after "--") never reads or writes
# the save files. The fast-forward tool always passes it.
const NO_SAVE_ARG := "--no-save"
# A process started with this user argument is the world host (Plan 14 step 2a):
# a headless process that lives the buddy's life on its land while it is at home.
const WORLD_HOST_ARG := "--world-host"
const HOST_DIR := "user://host"

const SERVICE_PATHS := {
    "identity": "res://scripts/services/identity_service.gd",
    "mood": "res://scripts/services/mood_service.gd",
    "bond": "res://scripts/services/bond_service.gd",
    "growth": "res://scripts/services/growth_service.gd",
    "economy": "res://scripts/services/economy_service.gd",
    "world": "res://scripts/services/world_service.gd",
    "report": "res://scripts/services/report_service.gd",
    "mind": "res://scripts/services/mind_service.gd",
    "memory": "res://scripts/services/memory_service.gd",
}

var settings := {}
var profile := {}
var world_state := {}
var _services: Dictionary = {}
# Content hash of what was last written per save file, so an unchanged file
# is not rewritten, and a debounce for saves requested every frame.
var _saved_digest: Dictionary = {}
var _deferred_save_pending := false
var _deferred_save_seconds := 0.0
# Fast-forward simulation (tests/life_sim.gd): a headless process can hand the
# buddy a clock of its own. Once it does, nothing is saved for the rest of the
# process, so a simulated life can never touch the real save files.
var _sim_clock_unix := 0
var _persistence_enabled := true
# Set when a buddy from before could not be backed up at launch (see
# fresh_start_if_due): it then stays in its old town for this run.
var _fresh_start_failed := false
# Whether a profile was on disk when this run loaded its state, read before
# anything could save. A brand-new install has none, so nothing to back up.
var _profile_was_on_disk := false
# Who this process is (Plan 14 step 2a): "solo" writes everything, as before;
# "host" and "desktop" write the buddy's files only while they hold the buddy,
# and only the desktop writes settings. See _may_write.
var _role := "solo"
var _holding := false
# Where the lock lives; tests point it at a folder of their own.
var _host_dir := HOST_DIR

const DEFERRED_SAVE_DELAY_SECONDS := 1.5
# Things the buddy can notice in a shop and want (Plan 13 C1+C2): wearable
# catalogue items, priced by rarity where the catalogue has no price.
const WANT_SLOTS := ["hat", "top", "bottom", "overall", "shoes", "gloves", "cape", "face_accessory", "eye_accessory"]
const WANT_PRICE_BY_RARITY := {"common": 40, "uncommon": 80, "rare": 150, "epic": 300, "legendary": 500}
const WANT_SHOP_SIZE := 40
var _want_shop_cache: Array = []
var _want_shop_catalog_size := -1


func _ready() -> void:
    _load_services()
    var args := OS.get_cmdline_user_args()
    if args.has(NO_SAVE_ARG):
        _start_without_saves()
        return
    if args.has(WORLD_HOST_ARG):
        _role = "host"
        _load_read_only()
        return
    # While a world host is running, it holds (or may take) the buddy, so every
    # other process only reads it: tests, tools and checks included. Only a real
    # launch then starts the visit (see is_real_launch and the overlay).
    var host_status := Whereabouts.read_status("%s/host.json" % HOST_DIR)
    if Whereabouts.is_alive(host_status, Time.get_unix_time_from_system()):
        _role = "desktop"
        _load_read_only()
        return
    # With no host running, only a real launch of the app becomes the desktop
    # because of the setting. A parse check, a test scene or a tool script also
    # starts this autoload, and none of them may start a world host.
    if _is_real_launch():
        var peeked: Dictionary = SaveStore.peek_versioned(
            SETTINGS_PATH,
            _default_settings,
            SchemaMigrations.SETTINGS_CURRENT_VERSION,
            SchemaMigrations.SETTINGS_MIGRATORS
        )
        # A new install has no settings.json: the defaults count.
        var s: Dictionary = peeked if not peeked.is_empty() else _default_settings()
        if bool(s.get("worldHost", true)) and bool(s.get("smallBeginnings", true)):
            _role = "desktop"
            _load_read_only()
            return
    load_state()


# False for the processes that are not the app itself: a scene or script named
# on the command line, an editor or import run, and the two smoke tests. Pure,
# so tests can call it. (The engine removes the arguments it handles itself,
# such as --headless, --path and --quit, before OS.get_cmdline_args() sees
# them, so those can only be told apart by the display server; see
# _is_real_launch.)
func _is_real_launch_args(engine_args: PackedStringArray, user_args: PackedStringArray) -> bool:
    for arg in engine_args:
        if ["--quit", "--quit-after", "-s", "--script", "--check-only", "--import", "-e", "--editor"].has(arg):
            return false
        if (arg.ends_with(".tscn") or arg.ends_with(".scn")) and arg != "res://scenes/LaunchRouter.tscn":
            return false
    for arg in user_args:
        if arg == "--ci-startup-smoke" or arg == "--verify-export-closure":
            return false
    return true


func _is_real_launch() -> bool:
    # The app always has a window. A headless process that is not the world host
    # (the CI parse check `--headless --quit`, a tool) is never the desktop.
    if DisplayServer.get_name() == "headless":
        return false
    return _is_real_launch_args(OS.get_cmdline_args(), OS.get_cmdline_user_args())


# Whether this process is the app itself, with its window: only then does the
# overlay start the visit (which may start a world host).
func is_real_launch() -> bool:
    return _is_real_launch()


# For the world host and the desktop app at startup: everything is read without
# writing or renaming anything, because neither holds the buddy yet.
func _load_read_only() -> void:
    var peeked_settings: Dictionary = SaveStore.peek_versioned(
        SETTINGS_PATH, _default_settings, SchemaMigrations.SETTINGS_CURRENT_VERSION, SchemaMigrations.SETTINGS_MIGRATORS
    )
    settings = peeked_settings if not peeked_settings.is_empty() else _default_settings()
    var peeked_profile: Dictionary = SaveStore.peek_versioned(
        PROFILE_PATH, _default_profile, SchemaMigrations.PROFILE_CURRENT_VERSION, SchemaMigrations.PROFILE_MIGRATORS
    )
    profile = peeked_profile if not peeked_profile.is_empty() else _default_profile()
    var peeked_world: Dictionary = SaveStore.peek_versioned(
        WORLD_STATE_PATH, _default_world_state, SchemaMigrations.WORLD_STATE_CURRENT_VERSION, SchemaMigrations.WORLD_STATE_MIGRATORS
    )
    world_state = peeked_world if not peeked_world.is_empty() else _default_world_state()
    profile = _ensure_profile_modules(profile)
    world_state = _ensure_world_modules(world_state)
    _reconcile_progression_from_xp()
    _sync_growth_mode_flags()
    _refresh_unlocks()
    _prune_event_buckets()


# For a process started with NO_SAVE_ARG: default state, saving off, and the
# save files never opened. Loading normally can already write them (a pending
# migration) or rename them (a damaged file), which a tool that promises not
# to touch the save must not do, even while the app is starting up.
func _start_without_saves() -> void:
    _persistence_enabled = false
    _deferred_save_pending = false
    settings = _default_settings()
    profile = _ensure_profile_modules(_default_profile())
    world_state = _ensure_world_modules(_default_world_state())
    _reconcile_progression_from_xp()
    _sync_growth_mode_flags()
    _refresh_unlocks()
    _prune_event_buckets()


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


func load_state(include_settings: bool = true) -> void:
    _profile_was_on_disk = FileAccess.file_exists(PROFILE_PATH)
    if include_settings:
        settings = SaveStore.load_versioned(
            SETTINGS_PATH,
            _default_settings,
            SchemaMigrations.SETTINGS_CURRENT_VERSION,
            SchemaMigrations.SETTINGS_MIGRATORS
        )
    else:
        # A process that does not own settings.json never renames a damaged one.
        var peeked: Dictionary = SaveStore.peek_versioned(
            SETTINGS_PATH,
            _default_settings,
            SchemaMigrations.SETTINGS_CURRENT_VERSION,
            SchemaMigrations.SETTINGS_MIGRATORS
        )
        settings = peeked if not peeked.is_empty() else _default_settings()
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
    if not _persistence_enabled:
        return
    _deferred_save_pending = false
    _write_if_changed(SETTINGS_PATH, settings)
    _write_if_changed(PROFILE_PATH, profile)
    _write_if_changed(WORLD_STATE_PATH, _persistable_world_state())


# Saves soon rather than now. For callers that fire every frame (the window
# position while the buddy walks or is dragged), where writing each time
# stalls rendering.
func flush_soon() -> void:
    if not _persistence_enabled:
        return
    if not _deferred_save_pending:
        _deferred_save_seconds = 0.0
    _deferred_save_pending = true


func _process(delta: float) -> void:
    if not _deferred_save_pending:
        return
    _deferred_save_seconds += delta
    if _deferred_save_seconds >= DEFERRED_SAVE_DELAY_SECONDS:
        flush()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
        if _deferred_save_pending:
            flush()


# The item catalogue is a copy of the content pack's item list (thousands of
# rows, several megabytes). It is rebuilt from the pack on every launch by
# apply_loaded_pack, so it is left out of the save file.
func _persistable_world_state() -> Dictionary:
    var slim := world_state.duplicate(false)
    slim.erase("item_catalog")
    return slim


# Who may write which save file (Plan 14 step 2a). The buddy is in one place at
# a time: the files holding it (profile, world state) are written only by the
# process that holds it; settings.json belongs to the desktop app.
func _may_write(path: String) -> bool:
    if _role == "solo":
        return true
    if path == SETTINGS_PATH:
        return _role == "desktop"
    if path == PROFILE_PATH or path == WORLD_STATE_PATH:
        return _still_holding()
    return false


# Holding is only as good as the lock. A process that froze for longer than the
# stale time can find its lock taken over by the other one; from then on it must
# not write the buddy's files, whatever it thought before.
func _still_holding() -> bool:
    if not _holding:
        return false
    if Whereabouts.holds(_host_dir, _role, OS.get_process_id()):
        return true
    push_warning("app_state: the buddy's lock is no longer this process's; it stops writing the buddy")
    _holding = false
    return false


func role() -> String:
    return _role


func is_holding_buddy() -> bool:
    return _still_holding()


# This process takes the buddy: reads its files for real (the holder is the only
# one who may write them) and, in a new world, runs the fresh start. The caller
# must already hold the lock (buddy_whereabouts.gd).
func take_buddy() -> void:
    if _role == "desktop":
        # Keeps a pending window position; only settings.json is writable yet.
        flush()
    _holding = true
    load_state(_role != "host")
    var fresh: Dictionary = fresh_start_if_due()
    if str(fresh.get("status", "")) == "started" and str(fresh.get("backup", "")) != "":
        var shown := ProjectSettings.globalize_path(str(fresh["backup"]))
        print("app_state: the buddy from before is saved in %s" % shown)
        if _role == "host":
            # settings.json is not the host's to write, so it says so in host.json.
            var status := Whereabouts.read_status("%s/host.json" % HOST_DIR)
            status["freshStartBackup"] = str(fresh["backup"])
            Whereabouts.write_status("%s/host.json" % HOST_DIR, status)


# Hands the buddy back: writes what it has, and stops writing its files.
func release_buddy() -> void:
    flush()
    _holding = false


# For the host, which only reads settings.json (the desktop app owns it): picks up
# a change made there. A missing or damaged file keeps what it had.
func reload_settings_read_only() -> void:
    var peeked: Dictionary = SaveStore.peek_versioned(
        SETTINGS_PATH, _default_settings, SchemaMigrations.SETTINGS_CURRENT_VERSION, SchemaMigrations.SETTINGS_MIGRATORS
    )
    if not peeked.is_empty():
        settings = peeked


# For a process that does not hold the buddy and only shows what it is doing.
func reload_buddy_read_only() -> void:
    var peeked: Dictionary = SaveStore.peek_versioned(
        PROFILE_PATH, _default_profile, SchemaMigrations.PROFILE_CURRENT_VERSION, SchemaMigrations.PROFILE_MIGRATORS
    )
    # The holder's write removes then renames, so the file can be missing for a moment.
    if peeked.is_empty():
        return
    profile = _ensure_profile_modules(peeked)


func _write_if_changed(path: String, data: Dictionary) -> void:
    if not _persistence_enabled:
        return
    if not _may_write(path):
        return
    var digest := JSON.stringify(data).md5_text()
    if str(_saved_digest.get(path, "")) == digest and FileAccess.file_exists(path):
        return
    if SaveStore.write_json(path, data):
        _saved_digest[path] = digest


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
    world_state["last_tick_unix"] = _clock_unix()

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
    # On the land the mind keeps the needs (they move with time and with what
    # it does), so the desktop animation only changes the mood that is shown.
    var kept_needs = profile.get("mood_modifiers", null)
    profile = _call_profile_service("mood", "apply_behavior", [profile, action_id])
    if small_beginnings() and typeof(kept_needs) == TYPE_DICTIONARY:
        profile["mood_modifiers"] = (kept_needs as Dictionary).duplicate(true)
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
    world_state["last_event_unix"] = _clock_unix()
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
    flush_soon()


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
    if not _persistence_enabled or not _may_write(PROFILE_PATH):
        return
    SaveStore.write_json(PROFILE_PATH, profile)


func open_reward_box(box_id: String) -> Dictionary:
    var seed := int(profile.get("personality_seed", 0)) + int(_clock_unix())
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
    # No quests or encounters on the land.
    if small_beginnings():
        return {}
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


# Plan 14: the buddy starts with a house and the land round it, alone. False
# for this run if a buddy from before could not be backed up at launch.
func small_beginnings() -> bool:
    return bool(settings.get("smallBeginnings", true)) and not _fresh_start_failed


func _land() -> Dictionary:
    var land = _call_service_with_fallback("world", "get_land", [], {})
    return land if typeof(land) == TYPE_DICTIONARY else {}


# --- Fresh start (Plan 14 step 1c) ---------------------------------------
# In the small-beginnings world every buddy is born on the land. A buddy from
# before is put away first: its save files are copied to a dated folder under
# BACKUP_ROOT, which is never overwritten, and only then does a new buddy wake
# up. Only the buddy starts over: settings, items, wardrobe and meso are kept.
# If the copy fails nothing is changed, and the old buddy carries on in its
# old town for this run. Called once at launch by launch_router.gd, never by
# tests or the simulator.
# Returns {"status": "not_due"|"started"|"backup_failed", "backup": String}.
func fresh_start_if_due() -> Dictionary:
    # A process that never saves (the fast-forward tool, a simulation) leaves
    # the save folder alone: no backup is copied and nothing is replaced.
    if not _persistence_enabled:
        return {"status": "not_due", "backup": ""}
    return _fresh_start(_profile_was_on_disk, [SETTINGS_PATH, PROFILE_PATH, WORLD_STATE_PATH], BACKUP_ROOT)


# `had_profile` is whether a buddy was saved before this run started. It is not
# read from disk here: loading can already have written a default profile.
func _fresh_start(had_profile: bool, save_paths: Array, backup_root: String) -> Dictionary:
    if not bool(settings.get("smallBeginnings", true)):
        return {"status": "not_due", "backup": ""}
    var mind_variant = profile.get("mind", null)
    if typeof(mind_variant) == TYPE_DICTIONARY and str((mind_variant as Dictionary).get("born", "")) == BORN_ON_THE_LAND:
        return {"status": "not_due", "backup": ""}
    var backup_dir := ""
    # With no buddy from before there is nothing to put away.
    if had_profile:
        var today := _clock_datetime()
        var label := "before-small-beginnings-%04d-%02d-%02d" % [int(today.get("year", 0)), int(today.get("month", 0)), int(today.get("day", 0))]
        backup_dir = SaveStore.backup_files(save_paths, backup_root, label)
        if backup_dir == "":
            push_warning("app_state: could not back up the save; the buddy from before stays for this run")
            _fresh_start_failed = true
            return {"status": "backup_failed", "backup": ""}
    var fresh := _ensure_profile_modules(_default_profile())
    var mind: Dictionary = fresh["mind"]
    mind["born"] = BORN_ON_THE_LAND
    fresh["mind"] = mind
    # It is not lonely yet: on its land its need for company falls slowly from
    # here, and a visit to you fills it up again (Plan 14 step 2a).
    var mods_variant = fresh.get("mood_modifiers", {})
    var mods: Dictionary = (mods_variant as Dictionary).duplicate() if typeof(mods_variant) == TYPE_DICTIONARY else {}
    mods["social_fulfillment"] = MindServiceScript.LAND_START_COMPANY
    fresh["mood_modifiers"] = mods
    profile = fresh
    _reconcile_progression_from_xp()
    _sync_growth_mode_flags()
    _refresh_unlocks()
    if backup_dir != "":
        settings["freshStartBackup"] = backup_dir
    flush()
    return {"status": "started", "backup": backup_dir}


# The places the buddy can go: the town, or on the land only what it has found.
func get_town() -> Dictionary:
    if small_beginnings():
        # The one place everything outside the mind reads the land.
        var known = _call_service_with_fallback("mind", "known_town", [profile, _land()], {})
        return known if typeof(known) == TYPE_DICTIONARY else {}
    var town = _call_service_with_fallback("world", "get_town", [world_state], {})
    return town if typeof(town) == TYPE_DICTIONARY else {}


# Lets the buddy make any self-directed decisions that have come due
# (including ones from while the app was closed). Returns the resulting
# journal events, oldest first; empty when nothing was due or autonomy is off.
func tick_mind(now_unix: int) -> Array:
    # The buddy's life on its land runs only at home, in the world host.
    if _role == "desktop":
        return []
    if not bool(settings.get("autonomyEnabled", true)):
        return []
    var small := small_beginnings()
    if small:
        # In the middle of something (asleep, out at the water): nothing is due.
        var mind_variant = profile.get("mind", null)
        if typeof(mind_variant) == TYPE_DICTIONARY and now_unix < int((mind_variant as Dictionary).get("busy_until", 0)):
            return []
    var npcs: Array = _world_npcs()
    var context := {
        "is_night": _is_night(),
        "top_trait": "",
        "hour": int(_clock_datetime().get("hour", 12)),
        "meso": int(get_inventory_snapshot().get("meso", 0)),
        "shop_items": _want_shop_items(),
        "plans": true,
        "small_beginnings": small,
    }
    var identity_ctx = _call_service_with_fallback("identity", "get_context", [profile], {})
    if typeof(identity_ctx) == TYPE_DICTIONARY:
        context["top_trait"] = str(identity_ctx.get("top_trait", ""))
    var town: Dictionary = _land() if small else get_town()
    var result = _call_service_with_fallback("mind", "tick", [profile, npcs, now_unix, context, town], {})
    if typeof(result) != TYPE_DICTIONARY:
        return []
    var events = result.get("events", [])
    if typeof(events) != TYPE_ARRAY or (events as Array).is_empty():
        return []
    var next_profile = result.get("profile", null)
    if typeof(next_profile) == TYPE_DICTIONARY:
        profile = next_profile
        # Where it went and who it saw are facts, so the memory graph links
        # them with what the person says about the same places and people.
        _call_profile_service("memory", "record_town_events", [profile, events])
        for event_variant in events:
            if typeof(event_variant) == TYPE_DICTIONARY and str((event_variant as Dictionary).get("buy_want", "")) != "":
                _buy_want(str((event_variant as Dictionary)["buy_want"]), int((event_variant as Dictionary).get("t", 0)))
        flush()
    return events


# An even spread of wearable catalogue items for the town's shop, built once
# per catalogue.
func _want_shop_items() -> Array:
    var catalog_variant = world_state.get("item_catalog", {})
    if typeof(catalog_variant) != TYPE_DICTIONARY:
        return []
    var catalog: Dictionary = catalog_variant
    if catalog.size() == _want_shop_catalog_size:
        return _want_shop_cache
    var rows: Array = []
    var ids: Array = catalog.keys()
    ids.sort()
    for id_variant in ids:
        var item_variant = catalog[id_variant]
        if typeof(item_variant) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = item_variant
        var slot := str(item.get("equipSlot", "")).strip_edges()
        var item_name := str(item.get("name", "")).strip_edges()
        if not WANT_SLOTS.has(slot) or item_name == "" or item_name.length() > 32 or str(item.get("wzId", "")) == "":
            continue
        var price := int(item.get("price", 0))
        if price <= 0:
            price = int(WANT_PRICE_BY_RARITY.get(str(item.get("rarity", "")).to_lower(), 80))
        rows.append({"id": str(id_variant), "name": item_name, "slot": slot, "price": price})
    var shop: Array = []
    if not rows.is_empty():
        var step := maxi(1, int(rows.size() / WANT_SHOP_SIZE))
        for index in range(0, rows.size(), step):
            shop.append(rows[index])
            if shop.size() >= WANT_SHOP_SIZE:
                break
    _want_shop_cache = shop
    _want_shop_catalog_size = catalog.size()
    return shop


# The buddy buys something it saved up for. It puts it on only if nothing is
# worn in that slot, so it never undoes an outfit chosen in the Wardrobe.
func _buy_want(want_id: String, decision_unix: int) -> void:
    var want: Dictionary = {}
    for row in mind_wants():
        if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("id", "")) == want_id:
            want = row
    if want.is_empty():
        return
    # The wallet may have changed since the trip was planned: keep the reserve.
    if int(get_inventory_snapshot().get("meso", 0)) < int(want.get("price", 0)) + MindServiceScript.WANT_RESERVE_MESO:
        _call_profile_service("mind", "cannot_buy", [profile, want_id, decision_unix])
        return
    var spent = _call_service_with_fallback(
        "economy", "spend_meso", [world_state, "purchase:%s" % want_id, int(want.get("price", 0))], {}
    )
    if typeof(spent) != TYPE_DICTIONARY or not bool(spent.get("ok", false)):
        _call_profile_service("mind", "cannot_buy", [profile, want_id, decision_unix])
        return
    world_state = spent["world_state"]
    var item_id := str(want.get("item_id", ""))
    var row: Dictionary = {"id": item_id, "name": str(want.get("name", "")), "equipSlot": str(want.get("slot", ""))}
    var catalog_variant = world_state.get("item_catalog", {})
    if typeof(catalog_variant) == TYPE_DICTIONARY and typeof((catalog_variant as Dictionary).get(item_id, null)) == TYPE_DICTIONARY:
        row = ((catalog_variant as Dictionary)[item_id] as Dictionary).duplicate(true)
        row["id"] = item_id
    world_state = _call_world_service("economy", "grant_item", [world_state, "purchase:%s" % want_id, row], false)
    var instance_id := int(world_state.get("next_item_instance_id", 1)) - 1
    var slots_variant = get_inventory_snapshot().get("equipped_slots", {})
    var slot_free := true
    if typeof(slots_variant) == TYPE_DICTIONARY:
        slot_free = int((slots_variant as Dictionary).get(str(want.get("slot", "")), -1)) <= 0
    var equipped := false
    if slot_free:
        equipped = bool(equip_inventory_item(instance_id).get("ok", false))
    _call_profile_service("mind", "complete_want", [profile, want_id, decision_unix, equipped])


func mind_wants() -> Array:
    var wants = _call_service_with_fallback("mind", "get_wants", [profile], [])
    return wants if typeof(wants) == TYPE_ARRAY else []


# Stores the thinking model's wording for a decision already in the journal.
func apply_mind_thought(decision_unix: int, thought: String, want: String) -> void:
    var result = _call_service_with_fallback(
        "mind", "apply_thought", [profile, decision_unix, thought, want], null
    )
    if typeof(result) == TYPE_DICTIONARY:
        profile = result
        flush()


# --- Memory (Plan 13 B2) -------------------------------------------------
# What the buddy remembers about the person lives in profile["memory"]. The
# memoryEnabled setting stops anything new being kept or used; what is
# already kept can still be listed and forgotten.
func memory_enabled() -> bool:
    return bool(settings.get("memoryEnabled", true))


func _memory_roster() -> Dictionary:
    var npcs: Array = _world_npcs()
    var places_variant = get_town().get("places", [])
    return {"places": places_variant if typeof(places_variant) == TYPE_ARRAY else [], "npcs": npcs}


func _now_unix() -> int:
    return int(_clock_unix())


func is_simulating() -> bool:
    return not _persistence_enabled


func _clock_unix() -> float:
    if _sim_clock_unix > 0:
        return float(_sim_clock_unix)
    return Time.get_unix_time_from_system()


func _clock_datetime() -> Dictionary:
    if _sim_clock_unix > 0:
        return Time.get_datetime_dict_from_unix_time(_sim_clock_unix)
    return Time.get_datetime_dict_from_system()


func set_sim_clock(unix_time: int) -> void:
    if not is_simulating() or unix_time <= 0:
        return
    _sim_clock_unix = unix_time


# The economy deep-copies world_state on every call, so the ~11,000-row item
# catalogue makes each simulated decision slow. The buddy only ever looks at
# the shop's items, so a simulation keeps just those rows. The shop list is
# the same before and after.
func trim_catalog_for_simulation() -> void:
    if not is_simulating():
        return
    var catalog_variant = world_state.get("item_catalog", {})
    if typeof(catalog_variant) != TYPE_DICTIONARY:
        return
    var catalog: Dictionary = catalog_variant
    var kept := {}
    for row in _want_shop_items():
        var item_id := str((row as Dictionary).get("id", ""))
        if catalog.has(item_id):
            kept[item_id] = catalog[item_id]
    world_state["item_catalog"] = kept
    _want_shop_cache = []
    _want_shop_catalog_size = -1


# Starts a simulated life for the headless fast-forward tool. One way: the
# process never saves again. The simulated time is read as plain local time
# (no time zone), so a run is the same on every machine. Returns false and
# changes nothing outside a headless process.
func begin_simulation(seed_value: int, start_unix: int) -> bool:
    if DisplayServer.get_name() != "headless" or start_unix <= 0:
        push_error("app_state: begin_simulation needs a headless process and a start time")
        return false
    _persistence_enabled = false
    # A simulated life is always solo: tick_mind returns nothing in the desktop role.
    _role = "solo"
    _holding = false
    _fresh_start_failed = false
    _deferred_save_pending = false
    _sim_clock_unix = start_unix
    _load_services()
    var mind_service = _services.get("mind", null)
    if mind_service != null:
        mind_service.set_time_zone_bias_minutes(0)
    _want_shop_cache = []
    _want_shop_catalog_size = -1
    settings = _default_settings()
    settings["mindModelEnabled"] = false
    settings["chatModelEnabled"] = false
    profile = _default_profile()
    profile["personality_seed"] = seed_value
    # The mind seeds its decisions from this tag (not from personality_seed), so
    # it is what makes one simulated seed live a different life from another.
    profile["personality_seed_tag"] = "sim-%d" % seed_value
    world_state = _default_world_state()
    profile = _ensure_profile_modules(profile)
    world_state = _ensure_world_modules(world_state)
    _reconcile_progression_from_xp()
    _sync_growth_mode_flags()
    _refresh_unlocks()
    _prune_event_buckets()
    return true


func memory_note_turn(who: String, text: String) -> void:
    if not memory_enabled():
        return
    _call_profile_service("memory", "append_turn", [profile, who, text, _now_unix()])
    flush()


func memory_live_turns() -> Array:
    if not memory_enabled():
        return []
    var turns = _call_service_with_fallback("memory", "live_turns", [profile, _now_unix()], [])
    return turns if typeof(turns) == TYPE_ARRAY else []


func memory_should_consolidate(chat_open: bool) -> bool:
    if not memory_enabled():
        return false
    return bool(_call_service_with_fallback("memory", "should_consolidate", [profile, _now_unix(), chat_open], false))


func memory_pending_turns() -> Dictionary:
    var pending = _call_service_with_fallback("memory", "pending_turns", [profile], {})
    return pending if typeof(pending) == TYPE_DICTIONARY else {}


func memory_apply_consolidation(facts: Array, summary: String, upto: int) -> void:
    if not memory_enabled():
        return
    _call_profile_service("memory", "apply_consolidation", [profile, facts, summary, upto, _now_unix(), _memory_roster()])
    flush()


func memory_discard_turns(upto: int) -> void:
    _call_profile_service("memory", "discard_turns", [profile, upto])
    flush()


func memory_recall(text: String) -> Dictionary:
    if not memory_enabled():
        return {}
    var recalled = _call_service_with_fallback("memory", "recall", [profile, text, _now_unix()], {})
    return recalled if typeof(recalled) == TYPE_DICTIONARY else {}


# Returns {"ok": bool, "id": int, "reason": String}.
func memory_add_note(text: String) -> Dictionary:
    if not memory_enabled():
        return {"ok": false, "id": 0, "reason": "memory_off"}
    var result = _call_service_with_fallback("memory", "add_note", [profile, text, _now_unix()], {})
    if typeof(result) != TYPE_DICTIONARY:
        return {"ok": false, "id": 0, "reason": "service_failure"}
    if bool(result.get("ok", false)) and typeof(result.get("profile", null)) == TYPE_DICTIONARY:
        profile = result["profile"]
        flush()
    return {"ok": bool(result.get("ok", false)), "id": int(result.get("id", 0)), "reason": str(result.get("reason", ""))}


func memory_forget(memory_id: int) -> bool:
    var result = _call_service_with_fallback("memory", "forget", [profile, memory_id], {})
    if typeof(result) != TYPE_DICTIONARY or not bool(result.get("ok", false)):
        return false
    if typeof(result.get("profile", null)) == TYPE_DICTIONARY:
        profile = result["profile"]
        flush()
    return true


func memory_forget_all() -> void:
    _call_profile_service("memory", "forget_all", [profile])
    flush()


func memory_list() -> Array:
    var rows = _call_service_with_fallback("memory", "list_about_user", [profile, _now_unix()], [])
    return rows if typeof(rows) == TYPE_ARRAY else []


# --- Talk changes the buddy (Plan 13 B3) --------------------------------
func _world_npcs() -> Array:
    # Nobody else lives on the land.
    if small_beginnings():
        return []
    var world_variant = world_state.get("world", null)
    if typeof(world_variant) == TYPE_DICTIONARY:
        var npcs_variant = (world_variant as Dictionary).get("npcs", [])
        if typeof(npcs_variant) == TYPE_ARRAY:
            return npcs_variant
    return []


func _local_hour_now() -> int:
    return int(_clock_datetime().get("hour", 12))


# The town place or character the person is suggesting it go to, if any.
# Only while it acts on its own: otherwise nothing would ever carry it out.
func mind_find_suggestion(text: String) -> Dictionary:
    if not bool(settings.get("autonomyEnabled", true)):
        return {}
    if not bool(_call_service_with_fallback("mind", "is_suggestion", [text], false)):
        return {}
    var target = _call_service_with_fallback("mind", "find_target", [text, get_town(), _world_npcs()], {})
    return target if typeof(target) == TYPE_DICTIONARY else {}


# The buddy decides (yes, later or no); returns {"answer", "reason"}.
func mind_consider(target: Dictionary) -> Dictionary:
    var result = _call_service_with_fallback(
        "mind", "consider", [profile, target, _now_unix(), _local_hour_now(), get_town(), _world_npcs()], {}
    )
    if typeof(result) != TYPE_DICTIONARY:
        return {"answer": "", "reason": ""}
    if typeof(result.get("profile", null)) == TYPE_DICTIONARY:
        profile = result["profile"]
        flush()
    return {"answer": str(result.get("answer", "")), "reason": str(result.get("reason", ""))}


# --- Visits (Plan 14 step 2a) --------------------------------------------
# Whether it can come over now ({"come": "now"|"later"|"asleep", "at", "why"}).
func mind_consider_call(now: int) -> Dictionary:
    var answer = _call_service_with_fallback("mind", "consider_call", [profile, _land(), now], {})
    return answer if typeof(answer) == TYPE_DICTIONARY else {"come": "now", "at": now, "why": ""}


# These three are for the process that holds the buddy only.
func mind_leave_for_visit(now: int, reason: String) -> void:
    var result = _call_service_with_fallback("mind", "leave_for_visit", [profile, _land(), now, reason], null)
    if typeof(result) == TYPE_DICTIONARY:
        profile = result
        flush()


func mind_return_from_visit(now: int, reason: String) -> void:
    var result = _call_service_with_fallback("mind", "return_from_visit", [profile, _land(), now, reason], null)
    if typeof(result) == TYPE_DICTIONARY:
        profile = result
        flush()


# For the world host, when it takes the buddy after a long gap.
func mind_note_still_world(now: int) -> void:
    var before := _mind_journal_size()
    var result = _call_service_with_fallback("mind", "note_still_world", [profile, _land(), now], null)
    if typeof(result) == TYPE_DICTIONARY:
        profile = result
        if _mind_journal_size() > before:
            flush()


# For the world host: the buddy has chosen its name.
func mind_note_name(now: int, chosen: String) -> void:
    var result = _call_service_with_fallback("mind", "note_name", [profile, now, chosen, _land()], null)
    if typeof(result) == TYPE_DICTIONARY:
        profile = result
        (profile["mind"] as Dictionary)["name"] = chosen
        flush()


func _mind_journal_size() -> int:
    var mind_variant = profile.get("mind", null)
    if typeof(mind_variant) != TYPE_DICTIONARY:
        return 0
    var journal_variant = (mind_variant as Dictionary).get("journal", [])
    return (journal_variant as Array).size() if typeof(journal_variant) == TYPE_ARRAY else 0


func mind_wants_company(now: int) -> bool:
    return bool(_call_service_with_fallback("mind", "wants_company", [profile, _land(), now], false))


func mind_is_bedtime(now: int) -> bool:
    return bool(_call_service_with_fallback("mind", "is_bedtime", [profile, now], false))


# A finished talk is an event in its day (social need, journal, maybe a wish).
func mind_note_talk(summary: String, lines: Array) -> void:
    _call_profile_service("mind", "note_talk", [profile, summary, lines, _now_unix(), get_town(), _world_npcs()])
    flush()


func mind_pick_news() -> Dictionary:
    var news = _call_service_with_fallback("mind", "pick_news", [profile], {})
    return news if typeof(news) == TYPE_DICTIONARY else {}


func mind_mark_shared(entry_t: int) -> void:
    _call_profile_service("mind", "mark_shared", [profile, entry_t])
    flush()


func get_town_map() -> Dictionary:
    var layout = _call_service_with_fallback("world", "town_map", [get_town()], {})
    return layout if typeof(layout) == TYPE_DICTIONARY else {}


func mind_day_plan() -> Dictionary:
    var plan = _call_service_with_fallback("mind", "get_day_plan", [profile], {})
    return plan if typeof(plan) == TYPE_DICTIONARY else {}


func get_mind_preferences() -> Dictionary:
    var preferences = _call_service_with_fallback("mind", "get_preferences", [profile], {})
    return preferences if typeof(preferences) == TYPE_DICTIONARY else {}


func get_mind_journal(limit: int = 5) -> Array:
    var journal = _call_service_with_fallback("mind", "get_journal", [profile, limit], [])
    return journal if typeof(journal) == TYPE_ARRAY else []


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
            var drop_seed := int(profile.get("personality_seed", 0)) + int(_clock_unix())
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
    var now := _clock_datetime()
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
    if not _persistence_enabled or not _may_write(SETTINGS_PATH):
        return
    SaveStore.write_json(SETTINGS_PATH, settings)


func _ensure_profile_modules(input_profile: Dictionary) -> Dictionary:
    var merged := input_profile.duplicate(true)
    merged = _call_profile_service("identity", "ensure_profile", [merged], false)
    merged = _call_profile_service("mood", "ensure_profile", [merged], false)
    merged = _call_profile_service("bond", "ensure_profile", [merged], false)
    merged = _call_profile_service("growth", "ensure_profile", [merged], false)
    merged = _call_profile_service("mind", "ensure_profile", [merged], false)
    merged = _call_profile_service("memory", "ensure_profile", [merged], false)
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
    var now_unix := _clock_unix()
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
            "timestamp": _clock_unix(),
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
        "autonomyEnabled": true,
        "smallBeginnings": true,
        "worldHost": true,
        "inventoryCompact": false,
        "mindModelEnabled": true,
        "mindModelUrl": "http://127.0.0.1:11434",
        "mindModelName": "gemma3:4b",
        "chatModelEnabled": true,
        "chatBackend": "ollama",
        "chatModelName": "gemma3:4b",
        "memoryEnabled": true,
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
        "personality_seed": _clock_unix(),
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
    var now := _clock_datetime()
    return "%04d-%02d-%02d" % [
        int(now.get("year", 1970)),
        int(now.get("month", 1)),
        int(now.get("day", 1)),
    ]


func _current_hour_key() -> String:
    var now := _clock_datetime()
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
    var now := _clock_datetime()
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
