extends Node2D

const BUDDY_RADIUS := 34.0
const FALLBACK_HIT_RADIUS := 44.0
const IDLE_SWAY_SPEED := 0.9
const IDLE_SWAY_DISTANCE_X := 0.0
const IDLE_SWAY_DISTANCE_Y := 0.0
const FLOOR_PADDING := 14.0
const SPRITE_VIEW_MARGIN := 4.0
const DESKTOP_FLOOR_CONTACT_OFFSET_Y := 28.0
const DEFAULT_ROAM_SPEED_PX_PER_SEC := 96.0
const DEFAULT_SPRITE_ANCHOR := Vector2(0.5, 1.0)
const NO_PIVOT := Vector2(-1.0, -1.0)
const SLEEP_PIVOT_OVERFLOW_BLEND := 0.85
const SIT_PIVOT_OVERFLOW_BLEND := 1.0
const DEFAULT_EMOTE_MANIFEST_PATH := "character/emotes/manifest.json"
const DEFAULT_STATE_EMOTES := {
    "idle": "default",
    "wander": "default",
    "sit": "default",
    "sleep": "blink",
    "happy": "smile",
    "gift": "love",
    "visitor": "wink",
}
const DEBUG_EMOTE_KEYS := {
    KEY_1: "happy",
    KEY_2: "sad",
    KEY_3: "angry",
    KEY_4: "surprised",
    KEY_5: "love",
    KEY_6: "wink",
    KEY_7: "sleepy",
    KEY_8: "sick",
    KEY_9: "pain",
    KEY_0: "default",
}
const EMOTE_DRAW_OFFSETS := {
    "love": Vector2(0.0, -4.0),
}

const BehaviorEngine = preload("res://scripts/behavior/behavior_engine.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")
const EncounterScheduler = preload("res://scripts/encounters/encounter_scheduler.gd")
const ProductivityTracker = preload("res://scripts/utility/productivity_tracker.gd")

@onready var tick_timer: Timer = $TickTimer
@onready var telemetry_timer: Timer = $TelemetryTimer
@onready var telemetry_label: Label = $Telemetry/Label
@onready var chat_balloon: Node2D = $ChatBalloon
@onready var welcome_label: Label = $WelcomeLayer/WelcomeLabel

var _engine := BehaviorEngine.new()
var _encounters := EncounterScheduler.new()
var _productivity := ProductivityTracker.new()
var _state := "idle"
var _dragging := false
var _drag_offset := Vector2i.ZERO
var _bob_time := 0.0
var _allowed_actions := []
var _active_manifest := {}
var _active_pack_id := "core_pack"
var _last_event_id := ""
var _draw_center := Vector2.ZERO
var _floor_padding := FLOOR_PADDING
var _telemetry_enabled := false
var _action_animations: Dictionary = {}
var _action_textures: Dictionary = {}
var _current_texture: Texture2D = null
var _sprite_scale: float = 2.35
var _sprite_anchor := DEFAULT_SPRITE_ANCHOR
var _current_frame_anchor := DEFAULT_SPRITE_ANCHOR
var _ground_enabled := false
var _ground_texture: Texture2D = null
var _ground_tile_x := true
var _ground_scale := 1.0
var _ground_alpha := 1.0
var _ground_align := "top"
var _ground_floor_offset_y := 0.0
var _ground_x_offset := 0.0
var _ground_source_path := ""
var _current_sprite_path := ""
var _current_visual_action := ""
var _current_animation_frames: Array = []
var _current_animation_durations: Array = []
var _current_animation_anchors: Array = []
var _current_animation_pivots: Array = []
var _current_animation_loop := true
var _current_animation_index := 0
var _current_animation_elapsed := 0.0
var _current_frame_pivot_px := NO_PIVOT
var _max_loaded_pivot_px_y := 0.0
var _current_sprite_rect := Rect2()
var _ground_surface_y_px := 0.0
var _state_emote_map: Dictionary = {}
var _face_emote_manifest: Dictionary = {}
var _face_overlay_frames: Array = []
var _face_texture_cache: Dictionary = {}
var _active_emote_semantic := "default"
var _active_face_variant := "default"
var _debug_emote_panel_enabled := false
var _manual_emote_until_unix := 0
var _last_face_texture_path := ""
var _roam_speed_px_per_sec := DEFAULT_ROAM_SPEED_PX_PER_SEC
var _roam_direction := 1
var _roam_subpixel_x := 0.0
var _bond_phrase_active := false
var _away_report_shown := false
var _continuity_hint_shown := false


func _ready() -> void:
    position = Vector2.ZERO
    _draw_center = _floor_point()
    _configure_window()
    _restore_window_state()
    _load_content_pack()

    _engine.configure(int(AppState.profile.get("personality_seed", 0)))
    _encounters.configure(
        _active_manifest.get("eventRules", []),
        int(AppState.profile.get("personality_seed", 0))
    )

    tick_timer.timeout.connect(_on_tick_timer_timeout)
    telemetry_timer.timeout.connect(_on_telemetry_timer_timeout)
    set_process(true)
    set_process_input(true)
    _productivity.note_session_reset(int(Time.get_unix_time_from_system()))
    telemetry_label.visible = false
    _refresh_telemetry()
    if AppState.is_first_run():
        _show_welcome_once()
    else:
        _show_while_away_report_once()


func _configure_window() -> void:
    get_viewport().transparent_bg = true
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
    DisplayServer.window_set_title("Buddy Runtime")
    _update_mouse_region()


func _update_mouse_region() -> void:
    # Avoid shaped passthrough regions; some Windows setups render them as a visible bubble.
    DisplayServer.window_set_mouse_passthrough(PackedVector2Array())


func _input(event: InputEvent) -> void:
    if event is InputEventKey:
        var key_event := event as InputEventKey
        if key_event.pressed and not key_event.echo:
            if key_event.keycode == KEY_F6:
                _telemetry_enabled = not _telemetry_enabled
                _refresh_telemetry()
            elif key_event.keycode == KEY_F5:
                _cycle_home_mode()
            elif key_event.keycode == KEY_F7:
                _cycle_event_frequency()
            elif key_event.keycode == KEY_F4:
                _cycle_interaction_intensity()
            elif key_event.keycode == KEY_F3:
                _cycle_quiet_strictness()
            elif key_event.keycode == KEY_F8:
                _move_to_next_monitor()
            elif key_event.keycode == KEY_F9:
                _cycle_pack()
            elif key_event.keycode == KEY_F10:
                _debug_emote_panel_enabled = not _debug_emote_panel_enabled
                _refresh_telemetry()
            elif key_event.keycode == KEY_F11:
                _open_debug_reward_box()
            elif key_event.keycode == KEY_F12:
                _resolve_world_prompt(not key_event.shift_pressed)
            elif DEBUG_EMOTE_KEYS.has(key_event.keycode):
                var semantic := str(DEBUG_EMOTE_KEYS[key_event.keycode])
                _set_emote_from_semantic(semantic, true, 12.0)
                _refresh_telemetry()

    if event is InputEventMouseButton:
        var button_event := event as InputEventMouseButton
        if button_event.button_index == MOUSE_BUTTON_LEFT:
            if button_event.pressed and _hit_test(button_event.position):
                _dragging = true
                _drag_offset = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
                _state = "happy"
                _set_emote_from_state(_state)
                _set_visual_for_state(_state)
                AppState.record_interaction("pet")
                _productivity.note_user_activity(int(Time.get_unix_time_from_system()))
                queue_redraw()
            elif not button_event.pressed:
                _dragging = false
                AppState.set_window_state(
                    DisplayServer.window_get_current_screen(),
                    DisplayServer.window_get_position()
                )
                _return_to_idle_after_drag()
        elif button_event.button_index == MOUSE_BUTTON_RIGHT and button_event.pressed:
            if _hit_test(button_event.position):
                _state = "sleep" if _state != "sleep" else "idle"
                _set_emote_from_state(_state)
                _set_visual_for_state(_state)
                AppState.record_interaction("toggle_sleep")
                _productivity.note_user_activity(int(Time.get_unix_time_from_system()))
                queue_redraw()

    if event is InputEventMouseMotion and _dragging:
        var mouse_pos := DisplayServer.mouse_get_position()
        var next_pos := mouse_pos - _drag_offset
        var screen_index := _screen_for_point(mouse_pos)
        if screen_index < 0:
            screen_index = DisplayServer.window_get_current_screen()
        next_pos = _clamp_window_to_screen(next_pos, screen_index)
        DisplayServer.window_set_current_screen(screen_index)
        DisplayServer.window_set_position(next_pos)


func _process(delta: float) -> void:
    _bob_time += delta
    _update_window_roam(delta)
    var base_center := _floor_point()
    if not _dragging and _state != "sleep":
        _draw_center = base_center + Vector2(
            sin(_bob_time * IDLE_SWAY_SPEED) * IDLE_SWAY_DISTANCE_X,
            sin(_bob_time * IDLE_SWAY_SPEED) * IDLE_SWAY_DISTANCE_Y
        )
    elif _state == "sleep":
        _draw_center = base_center
    else:
        _draw_center = base_center
    _advance_animation(delta)
    queue_redraw()


func _draw() -> void:
    var center := _draw_center
    if _current_texture == null:
        _load_core_character_animation_fallbacks()
        _load_core_character_sprite_fallbacks()
        _set_visual_for_state(_state, true)

    if _draw_character_sprite(center):
        _draw_face_overlay()
        return

    var missing_rect := Rect2(center - Vector2(34.0, 34.0), Vector2(68.0, 68.0))
    draw_rect(missing_rect, Color(0.15, 0.02, 0.02, 0.7), true)
    draw_rect(missing_rect, Color(0.92, 0.28, 0.28, 0.95), false, 2.0)
    draw_line(missing_rect.position, missing_rect.end, Color(0.92, 0.28, 0.28, 0.95), 2.0)
    draw_line(
        Vector2(missing_rect.position.x, missing_rect.end.y),
        Vector2(missing_rect.end.x, missing_rect.position.y),
        Color(0.92, 0.28, 0.28, 0.95),
        2.0
    )


func _center_point() -> Vector2:
    var viewport_size: Vector2 = get_viewport_rect().size
    return viewport_size * 0.5


func _floor_point() -> Vector2:
    var viewport_size: Vector2 = get_viewport_rect().size
    return Vector2(
        viewport_size.x * 0.5,
        viewport_size.y - SPRITE_VIEW_MARGIN + DESKTOP_FLOOR_CONTACT_OFFSET_Y
    )


func _base_floor_reference_y(viewport_size: Vector2) -> float:
    return viewport_size.y - _floor_padding + _ground_floor_offset_y


func _ground_draw_size() -> Vector2:
    if _ground_texture == null:
        return Vector2.ZERO
    return _ground_texture.get_size() * maxf(0.05, _ground_scale)


func _ground_draw_y(viewport_size: Vector2, draw_size: Vector2) -> float:
    var draw_y := _base_floor_reference_y(viewport_size)
    if _ground_align == "center":
        draw_y -= draw_size.y * 0.5
    elif _ground_align == "bottom":
        draw_y -= draw_size.y
    return draw_y


func _ground_surface_y(viewport_size: Vector2) -> float:
    if _ground_texture == null:
        return _base_floor_reference_y(viewport_size)
    var scale := maxf(0.05, _ground_scale)
    var draw_size := _ground_draw_size()
    var draw_y := _ground_draw_y(viewport_size, draw_size)
    return draw_y + (_ground_surface_y_px * scale)


func _hit_test(point: Vector2) -> bool:
    if _current_texture != null:
        var hit_rect := _sprite_rect_for_texture(_draw_center, _current_texture).grow(8.0)
        _current_sprite_rect = hit_rect
        return hit_rect.has_point(point)
    return point.distance_to(_draw_center) <= FALLBACK_HIT_RADIUS


func _on_tick_timer_timeout() -> void:
    var now_unix := Time.get_unix_time_from_system()
    var context := AppState.get_behavior_context(_allowed_actions)
    var activity_context := _productivity.get_context(now_unix, AppState.settings)
    for key in activity_context.keys():
        context[key] = activity_context[key]
    var home_mode := str(context.get("home_mode", "overlay"))

    var productivity_event := _productivity.tick(now_unix, AppState.settings)
    if not productivity_event.is_empty():
        var prod_event_id := str(productivity_event.get("id", ""))
        var prod_action := str(productivity_event.get("action", "happy"))
        context["forced_action"] = prod_action
        _last_event_id = prod_event_id
        AppState.record_event_trigger(prod_event_id, prod_action)
        _show_support_hint(productivity_event)

    if home_mode != "home":
        var selected_event := _encounters.tick(now_unix, context)
        if not selected_event.is_empty():
            var event_id := str(selected_event.get("id", ""))
            var action_id := str(selected_event.get("action", "gift"))
            var per_hour := int(selected_event.get("per_hour", 1))
            var per_day := int(selected_event.get("per_day", 4))
            if not context.has("forced_action") and AppState.try_consume_event_budget(event_id, per_hour, per_day):
                context["forced_action"] = action_id
                _last_event_id = event_id
                AppState.record_event_trigger(event_id, action_id)

    var was_sleeping := _state == "sleep"
    var action := _engine.tick(now_unix, context)
    var new_state := str(action.get("id", "idle"))
    if was_sleeping and not context.has("forced_action"):
        new_state = "sleep"
    _state = new_state
    _set_emote_from_state(_state)
    _set_visual_for_state(_state)
    AppState.apply_behavior(_state)
    var world_prompt := AppState.tick_world_events(int(now_unix))
    if not world_prompt.is_empty():
        _show_world_prompt(world_prompt)
    _refresh_telemetry()
    if _state == "idle":
        _maybe_show_bond_phrase()


func _is_night() -> bool:
    var now := Time.get_datetime_dict_from_system()
    var hour := int(now.get("hour", 12))
    return hour < 7 or hour >= 22


func _load_content_pack() -> void:
    var selected_pack := str(AppState.settings.get("selectedPackId", "core_pack"))
    var loaded := ContentLoader.load_with_fallback(selected_pack)

    var source_tier := str(loaded.get("source_tier", "selected"))
    if source_tier != "selected":
        print(
            "content: pack fallback — tier=%s reason=%s errors_by_tier=%s"
            % [source_tier, loaded.get("fallback_reason", ""), loaded.get("errors_by_tier", {})]
        )

    _active_pack_id = str(loaded.get("pack_id", "core_pack"))
    _active_manifest = loaded.get("manifest", {})
    _allowed_actions = ContentLoader.gather_action_ids(_active_manifest)
    if _allowed_actions.is_empty():
        _allowed_actions = ["idle", "sit", "sleep", "wander", "happy", "gift", "visitor"]

    _load_visual_assets(_active_pack_id, _active_manifest)
    AppState.apply_loaded_pack(_active_pack_id, _active_manifest)


func _restore_window_state() -> void:
    var state := AppState.get_window_state()
    var preferred_screen := _normalize_screen_index(int(state.get("preferredScreen", 0)))
    var preferred_pos: Vector2i = Vector2i(120, 120)
    var preferred_raw = state.get("position", Vector2i(120, 120))
    if typeof(preferred_raw) == TYPE_VECTOR2I:
        preferred_pos = preferred_raw

    DisplayServer.window_set_current_screen(preferred_screen)
    var clamped := _clamp_window_to_screen(preferred_pos, preferred_screen)
    DisplayServer.window_set_position(clamped)


func _normalize_screen_index(index: int) -> int:
    var count := DisplayServer.get_screen_count()
    if count <= 0:
        return 0
    if index < 0:
        return 0
    if index >= count:
        return count - 1
    return index


func _screen_rect(screen_index: int) -> Rect2i:
    var normalized := _normalize_screen_index(screen_index)
    return DisplayServer.screen_get_usable_rect(normalized)


func _screen_for_point(point: Vector2i) -> int:
    var count := DisplayServer.get_screen_count()
    for i in range(count):
        var rect := _screen_rect(i)
        if rect.has_point(point):
            return i
    return -1


func _clamp_window_to_screen(next_pos: Vector2i, screen_index: int) -> Vector2i:
    var rect := _screen_rect(screen_index)
    var window_size := DisplayServer.window_get_size()
    var max_x: int = rect.position.x + maxi(0, rect.size.x - window_size.x)
    var max_y: int = rect.position.y + maxi(0, rect.size.y - window_size.y)
    return Vector2i(
        clampi(next_pos.x, rect.position.x, max_x),
        clampi(next_pos.y, rect.position.y, max_y)
    )


func _cycle_event_frequency() -> void:
    var current := str(AppState.settings.get("eventFrequency", "normal"))
    var values := ["low", "normal", "high"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    AppState.settings["eventFrequency"] = values[index]
    AppState.flush()
    _refresh_telemetry()


func _cycle_interaction_intensity() -> void:
    var current := str(AppState.settings.get("interactionIntensity", "balanced"))
    var values := ["cozy", "balanced", "deep"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    AppState.settings["interactionIntensity"] = values[index]
    AppState.flush()
    _update_balloon_position()
    chat_balloon.show_text("Interaction intensity: %s" % values[index])
    _refresh_telemetry()


func _cycle_quiet_strictness() -> void:
    var current := str(AppState.settings.get("quietModeStrictness", "balanced"))
    var values := ["lenient", "balanced", "strict"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    AppState.settings["quietModeStrictness"] = values[index]
    AppState.flush()
    _update_balloon_position()
    chat_balloon.show_text("Quiet strictness: %s" % values[index])
    _refresh_telemetry()


func _move_to_next_monitor() -> void:
    var count := DisplayServer.get_screen_count()
    if count <= 1:
        return
    var current := _normalize_screen_index(DisplayServer.window_get_current_screen())
    var next_screen: int = (current + 1) % count
    DisplayServer.window_set_current_screen(next_screen)
    var current_pos := DisplayServer.window_get_position()
    var clamped := _clamp_window_to_screen(current_pos, next_screen)
    DisplayServer.window_set_position(clamped)
    AppState.set_window_state(next_screen, clamped)
    _refresh_telemetry()


func _update_window_roam(delta: float) -> void:
    if _dragging:
        return

    var roam_state := _state == "wander" or _state == "visitor"
    var current_screen := _normalize_screen_index(DisplayServer.window_get_current_screen())
    var screen_rect := _screen_rect(current_screen)
    var window_size := DisplayServer.window_get_size()
    var floor_y := screen_rect.position.y + maxi(0, screen_rect.size.y - window_size.y)

    var current_pos := DisplayServer.window_get_position()
    if current_pos.y != floor_y:
        current_pos.y = floor_y

    if not roam_state:
        var floor_locked := _clamp_window_to_screen(current_pos, current_screen)
        if floor_locked != DisplayServer.window_get_position():
            DisplayServer.window_set_position(floor_locked)
            AppState.set_window_state(current_screen, floor_locked)
        return

    var speed := maxf(12.0, _roam_speed_px_per_sec)
    var move_px := (float(_roam_direction) * speed * delta) + _roam_subpixel_x
    var step := int(round(move_px))
    _roam_subpixel_x = move_px - float(step)
    if step == 0:
        step = _roam_direction

    var min_x := screen_rect.position.x
    var max_x := screen_rect.position.x + maxi(0, screen_rect.size.x - window_size.x)
    var next_x := current_pos.x + step
    if next_x <= min_x:
        next_x = min_x
        _roam_direction = 1
    elif next_x >= max_x:
        next_x = max_x
        _roam_direction = -1

    var next_pos := Vector2i(next_x, floor_y)
    if next_pos != DisplayServer.window_get_position():
        DisplayServer.window_set_position(next_pos)
        AppState.set_window_state(current_screen, next_pos)


func _cycle_pack() -> void:
    var ids := ContentLoader.list_pack_ids()
    if ids.is_empty():
        return

    var current := str(AppState.settings.get("selectedPackId", "core_pack"))
    var index := ids.find(current)
    if index < 0:
        index = 0
    else:
        index = (index + 1) % ids.size()

    var next_pack := str(ids[index])
    var loaded := ContentLoader.load_pack(next_pack)
    if not bool(loaded.get("ok", false)):
        return

    _active_pack_id = next_pack
    _active_manifest = loaded.get("manifest", {})
    _allowed_actions = ContentLoader.gather_action_ids(_active_manifest)
    _encounters.configure(
        _active_manifest.get("eventRules", []),
        int(AppState.profile.get("personality_seed", 0))
    )
    _load_visual_assets(_active_pack_id, _active_manifest)
    AppState.apply_loaded_pack(_active_pack_id, _active_manifest)
    _refresh_telemetry()


func _on_telemetry_timer_timeout() -> void:
    _refresh_telemetry()


func _refresh_telemetry() -> void:
    telemetry_label.visible = _telemetry_enabled or _debug_emote_panel_enabled
    if not telemetry_label.visible:
        return

    var snapshot := AppState.get_telemetry_snapshot()
    var cozy_open_count := 0
    var heroic_open_count := 0
    var box_stats_variant = snapshot.get("box_open_stats", {})
    if typeof(box_stats_variant) == TYPE_DICTIONARY:
        var box_stats: Dictionary = box_stats_variant
        if box_stats.has("cozy") and typeof(box_stats["cozy"]) == TYPE_DICTIONARY:
            cozy_open_count = int((box_stats["cozy"] as Dictionary).get("opens", 0))
        if box_stats.has("heroic") and typeof(box_stats["heroic"]) == TYPE_DICTIONARY:
            heroic_open_count = int((box_stats["heroic"] as Dictionary).get("opens", 0))
    var lines: Array[String] = [
        "state: %s" % _state,
        "emote: %s -> %s" % [_active_emote_semantic, _active_face_variant],
        "face src: %s" % _last_face_texture_path,
        "level: %d  xp: %d" % [int(snapshot.get("bond_level", 1)), int(snapshot.get("bond_xp", 0))],
        "mood: %s  growth: %d  trust: %.2f" % [
            str(snapshot.get("mood", "calm")),
            int(snapshot.get("growth_stage", 1)),
            float(snapshot.get("trust_value", 0.2)),
        ],
        "crystals: %d  items: %d" % [
            int(snapshot.get("crystals", 0)),
            int(snapshot.get("inventory_count", 0)),
        ],
        "dup recycle crystals: %d" % int(snapshot.get("duplicate_recycle_total", 0)),
        "theme opens: cozy=%d heroic=%d" % [cozy_open_count, heroic_open_count],
        "pack: %s" % str(snapshot.get("active_pack", "core_pack")),
        "freq: %s  quiet: %s" % [
            str(AppState.settings.get("eventFrequency", "normal")),
            "on" if AppState.is_quiet_hours_now() else "off"
        ],
        "intensity: %s  quiet strict: %s" % [
            str(snapshot.get("interaction_intensity", "balanced")),
            str(snapshot.get("quiet_strictness", "balanced")),
        ],
        "continuity entries: %d" % int(snapshot.get("continuity_digest_count", 0)),
        "focus mins: %d  prod: %s" % [
            _productivity.focus_minutes(int(Time.get_unix_time_from_system())),
            "on" if bool(AppState.settings.get("productivityOptIn", false)) else "off"
        ],
        "screen: %d" % DisplayServer.window_get_current_screen(),
        "pack id: %s" % _active_pack_id,
        "sprite: %s" % _sprite_debug_label(),
        "ground: disabled",
        "last event: %s" % _last_event_id,
        "mode: %s  wall decor: %s" % [
            str(snapshot.get("home_mode", "overlay")),
            str(snapshot.get("home_wall_decor", "")),
        ],
        "home: %s" % str(snapshot.get("home_scene_id", "cozy_starter_room")),
        "pending quest: %s" % str(snapshot.get("pending_quest_id", "")),
        "pending encounter: %s" % str(snapshot.get("pending_encounter_id", "")),
        "world event: %s" % str(snapshot.get("last_world_event_id", "")),
        "F3 quiet strict  F4 intensity  F5 mode  F6 telemetry  F7 freq  F8 monitor",
        "F9 pack  F10 emotes  F11 reward  F12 world",
    ]
    if _debug_emote_panel_enabled:
        var lock_remaining := maxi(0, _manual_emote_until_unix - int(Time.get_unix_time_from_system()))
        lines.append("manual emote lock: %ds" % lock_remaining)
        lines.append("emote hotkeys: 1 happy 2 sad 3 angry 4 surprised 5 love")
        lines.append("6 wink 7 sleepy 8 sick 9 pain 0 default")
    telemetry_label.text = "\n".join(lines)


func _load_visual_assets(pack_id: String, manifest: Dictionary) -> void:
    _action_animations.clear()
    _action_textures.clear()
    _current_texture = null
    _ground_enabled = false
    _ground_texture = null
    _ground_tile_x = true
    _ground_scale = 1.0
    _ground_alpha = 1.0
    _ground_align = "top"
    _floor_padding = FLOOR_PADDING
    _ground_floor_offset_y = 0.0
    _ground_x_offset = 0.0
    _ground_surface_y_px = 0.0
    _ground_source_path = ""
    _current_sprite_path = ""
    _current_visual_action = ""
    _reset_current_animation()
    _sprite_scale = 2.35
    _sprite_anchor = DEFAULT_SPRITE_ANCHOR
    _max_loaded_pivot_px_y = 0.0
    _face_emote_manifest.clear()
    _face_overlay_frames.clear()
    _face_texture_cache.clear()
    _state_emote_map = DEFAULT_STATE_EMOTES.duplicate()
    _active_emote_semantic = "default"
    _active_face_variant = "default"
    _manual_emote_until_unix = 0
    _last_face_texture_path = ""

    var visual_variant = manifest.get("visual", {})
    if typeof(visual_variant) == TYPE_DICTIONARY:
        var visual: Dictionary = visual_variant
        var scale_raw = visual.get("scale", 1.45)
        if typeof(scale_raw) == TYPE_INT or typeof(scale_raw) == TYPE_FLOAT:
            _sprite_scale = maxf(0.2, float(scale_raw))

        var anchor_raw = visual.get("anchor", [])
        if typeof(anchor_raw) == TYPE_ARRAY and (anchor_raw as Array).size() >= 2:
            var anchor_array: Array = anchor_raw
            _sprite_anchor = Vector2(
                clampf(float(anchor_array[0]), 0.0, 1.0),
                clampf(float(anchor_array[1]), 0.0, 1.0)
            )

        var animations_variant = visual.get("animations", {})
        if typeof(animations_variant) == TYPE_DICTIONARY:
            var animations: Dictionary = animations_variant
            for action_key in animations.keys():
                var action_id := str(action_key)
                var rel_path := str(animations[action_key])
                if action_id == "" or rel_path == "":
                    continue
                var animation := _load_animation_spec(rel_path, pack_id)
                if not animation.is_empty():
                    _action_animations[action_id] = animation
                    var max_pivot_variant = animation.get("max_pivot_y", 0.0)
                    if typeof(max_pivot_variant) == TYPE_INT or typeof(max_pivot_variant) == TYPE_FLOAT:
                        _max_loaded_pivot_px_y = maxf(_max_loaded_pivot_px_y, float(max_pivot_variant))

        var emote_manifest_rel := ""
        var emotes_variant = visual.get("emotes", {})
        if typeof(emotes_variant) == TYPE_DICTIONARY:
            var emotes: Dictionary = emotes_variant
            emote_manifest_rel = str(emotes.get("manifest", ""))
            var state_map_variant = emotes.get("state_map", {})
            if typeof(state_map_variant) == TYPE_DICTIONARY:
                _state_emote_map = (state_map_variant as Dictionary).duplicate()
        if emote_manifest_rel == "":
            emote_manifest_rel = DEFAULT_EMOTE_MANIFEST_PATH
        _face_emote_manifest = _load_emote_manifest(emote_manifest_rel, pack_id)

        var sprites_variant = visual.get("sprites", {})
        if typeof(sprites_variant) == TYPE_DICTIONARY:
            var sprites: Dictionary = sprites_variant
            for action_key in sprites.keys():
                var action_id := str(action_key)
                var rel_path := str(sprites[action_key])
                if action_id == "" or rel_path == "":
                    continue

                var texture := _resolve_texture(rel_path, pack_id)
                if texture != null:
                    _action_textures[action_id] = texture

    if _action_animations.is_empty():
        _load_core_character_animation_fallbacks()
    if _action_textures.is_empty():
        _load_core_character_sprite_fallbacks()
    _ground_enabled = false
    _ground_texture = null
    _set_emote_from_state(_state)
    _set_visual_for_state(_state, true)
    _update_mouse_region()


func _set_visual_for_state(action_id: String, force_reset: bool = false) -> void:
    var selected_animation_action := action_id
    var animation_variant = _action_animations.get(selected_animation_action, {})
    var use_animation := false
    if typeof(animation_variant) == TYPE_DICTIONARY and not (animation_variant as Dictionary).is_empty():
        use_animation = true
    else:
        selected_animation_action = "idle"
        animation_variant = _action_animations.get(selected_animation_action, {})
        if typeof(animation_variant) == TYPE_DICTIONARY and not (animation_variant as Dictionary).is_empty():
            use_animation = true

    if use_animation:
        var animation_data: Dictionary = animation_variant
        if force_reset or selected_animation_action != _current_visual_action:
            _apply_animation(selected_animation_action, animation_data)
        return

    var found = _action_textures.get(action_id, null)
    var source_action := action_id
    if found == null:
        found = _action_textures.get("idle", null)
        source_action = "idle"

    _reset_current_animation()
    _face_overlay_frames.clear()
    _current_visual_action = source_action
    if found is Texture2D:
        _current_texture = found
        _current_frame_anchor = _sprite_anchor
        _current_frame_pivot_px = NO_PIVOT
        _current_sprite_path = source_action
    else:
        _current_texture = null
        _current_frame_anchor = _sprite_anchor
        _current_frame_pivot_px = NO_PIVOT
        _current_sprite_path = ""


func _apply_animation(action_id: String, animation_data: Dictionary) -> void:
    _reset_current_animation()
    _face_overlay_frames.clear()
    _current_visual_action = action_id
    _current_animation_loop = bool(animation_data.get("loop", true))

    var frames_variant = animation_data.get("frames", [])
    if typeof(frames_variant) == TYPE_ARRAY:
        _current_animation_frames = (frames_variant as Array).duplicate()
    var durations_variant = animation_data.get("durations", [])
    if typeof(durations_variant) == TYPE_ARRAY:
        _current_animation_durations = (durations_variant as Array).duplicate()
    var anchors_variant = animation_data.get("anchors", [])
    if typeof(anchors_variant) == TYPE_ARRAY:
        _current_animation_anchors = (anchors_variant as Array).duplicate()
    var pivots_variant = animation_data.get("pivots", [])
    if typeof(pivots_variant) == TYPE_ARRAY:
        _current_animation_pivots = (pivots_variant as Array).duplicate()
    var face_overlays_variant = animation_data.get("face_overlays", [])
    if typeof(face_overlays_variant) == TYPE_ARRAY:
        _face_overlay_frames = (face_overlays_variant as Array).duplicate()

    if _current_animation_frames.is_empty():
        _current_texture = null
        _current_frame_anchor = _sprite_anchor
        _current_sprite_path = ""
        return

    if _current_animation_durations.is_empty():
        _current_animation_durations.resize(_current_animation_frames.size())
        for i in range(_current_animation_durations.size()):
            _current_animation_durations[i] = 0.12
    while _current_animation_durations.size() < _current_animation_frames.size():
        _current_animation_durations.append(0.12)
    while _current_animation_anchors.size() < _current_animation_frames.size():
        _current_animation_anchors.append(_sprite_anchor)
    while _current_animation_pivots.size() < _current_animation_frames.size():
        _current_animation_pivots.append(NO_PIVOT)

    _current_animation_index = 0
    _current_animation_elapsed = 0.0
    var first_frame = _current_animation_frames[0]
    if first_frame is Texture2D:
        _current_texture = first_frame
    else:
        _current_texture = null
    _current_frame_anchor = _anchor_for_current_animation_frame()
    _current_frame_pivot_px = _pivot_for_current_animation_frame()
    _current_sprite_path = "%s (anim %d/%d)" % [action_id, _current_animation_index + 1, _current_animation_frames.size()]


func _reset_current_animation() -> void:
    _current_animation_frames.clear()
    _current_animation_durations.clear()
    _current_animation_anchors.clear()
    _current_animation_pivots.clear()
    _face_overlay_frames.clear()
    _current_animation_index = 0
    _current_animation_elapsed = 0.0
    _current_animation_loop = true
    _current_frame_anchor = _sprite_anchor
    _current_frame_pivot_px = NO_PIVOT


func _advance_animation(delta: float) -> void:
    if _current_animation_frames.size() <= 1:
        return
    _current_animation_elapsed += delta

    var guard := 0
    while guard < 16:
        guard += 1
        var frame_duration := _duration_for_current_animation_frame()
        if _current_animation_elapsed < frame_duration:
            break
        _current_animation_elapsed -= frame_duration

        if _current_animation_index + 1 < _current_animation_frames.size():
            _current_animation_index += 1
        elif _current_animation_loop:
            _current_animation_index = 0
        else:
            _current_animation_index = _current_animation_frames.size() - 1
            _current_animation_elapsed = 0.0
            break

        var tex_variant = _current_animation_frames[_current_animation_index]
        if tex_variant is Texture2D:
            _current_texture = tex_variant
        _current_frame_anchor = _anchor_for_current_animation_frame()
        _current_frame_pivot_px = _pivot_for_current_animation_frame()
        _current_sprite_path = "%s (anim %d/%d)" % [
            _current_visual_action,
            _current_animation_index + 1,
            _current_animation_frames.size(),
        ]


func _anchor_for_current_animation_frame() -> Vector2:
    if _current_animation_anchors.is_empty():
        return _sprite_anchor
    var index := mini(_current_animation_index, _current_animation_anchors.size() - 1)
    var raw = _current_animation_anchors[index]
    if raw is Vector2:
        return raw
    if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
        var values: Array = raw
        return Vector2(float(values[0]), float(values[1]))
    return _sprite_anchor


func _pivot_for_current_animation_frame() -> Vector2:
    if _current_animation_pivots.is_empty():
        return NO_PIVOT
    var index := mini(_current_animation_index, _current_animation_pivots.size() - 1)
    var raw = _current_animation_pivots[index]
    if raw is Vector2:
        return raw
    if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
        var values: Array = raw
        return Vector2(float(values[0]), float(values[1]))
    return NO_PIVOT


func _duration_for_current_animation_frame() -> float:
    if _current_animation_durations.is_empty():
        return 0.12
    var index := mini(_current_animation_index, _current_animation_durations.size() - 1)
    var raw = _current_animation_durations[index]
    if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
        return maxf(0.03, float(raw))
    return 0.12


func _sprite_debug_label() -> String:
    if _current_sprite_path != "":
        return _current_sprite_path
    return "fallback"


func _ground_debug_label() -> String:
    if not _ground_enabled:
        return "off"
    if _ground_texture == null:
        return "missing"
    if _ground_source_path != "":
        return _ground_source_path
    return "on"


func _auto_adjust_floor_padding_to_loaded_pivots() -> void:
    if _max_loaded_pivot_px_y <= 0.0:
        return

    var floor_y := _floor_point().y
    var max_pivot_scaled := _max_loaded_pivot_px_y * _sprite_scale
    var top_y := floor_y - max_pivot_scaled
    if top_y >= SPRITE_VIEW_MARGIN:
        return

    var required_delta := SPRITE_VIEW_MARGIN - top_y
    _floor_padding = maxf(2.0, _floor_padding - required_delta)


func _draw_character_sprite(center: Vector2) -> bool:
    if _current_texture == null:
        return false

    var tex_size: Vector2 = _current_texture.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return false

    _current_sprite_rect = _sprite_rect_for_texture(center, _current_texture)
    draw_texture_rect(_current_texture, _current_sprite_rect, false)
    return true


func _draw_face_overlay() -> void:
    if _current_texture == null:
        return
    if _face_overlay_frames.is_empty():
        return
    if _current_animation_index < 0 or _current_animation_index >= _face_overlay_frames.size():
        return

    var frame_overlay_variant = _face_overlay_frames[_current_animation_index]
    if typeof(frame_overlay_variant) != TYPE_DICTIONARY:
        return
    var frame_overlay: Dictionary = frame_overlay_variant
    if frame_overlay.is_empty():
        return

    var face_texture := _resolve_face_texture_for_overlay(frame_overlay)
    if face_texture == null:
        return

    var local_pos_variant = frame_overlay.get("local_top_left", [])
    if typeof(local_pos_variant) != TYPE_ARRAY or (local_pos_variant as Array).size() < 2:
        return
    var local_pos_arr: Array = local_pos_variant
    var local_top_left := Vector2(float(local_pos_arr[0]), float(local_pos_arr[1]))
    var emote_offset = EMOTE_DRAW_OFFSETS.get(_active_emote_semantic, Vector2.ZERO)
    if emote_offset is Vector2:
        local_top_left += emote_offset

    var source_size: Vector2 = _current_texture.get_size()
    if source_size.x <= 0.0 or source_size.y <= 0.0:
        return

    var scale_x := _current_sprite_rect.size.x / source_size.x
    var scale_y := _current_sprite_rect.size.y / source_size.y
    var face_size := face_texture.get_size()
    var draw_rect := Rect2(
        _current_sprite_rect.position + Vector2(local_top_left.x * scale_x, local_top_left.y * scale_y),
        Vector2(face_size.x * scale_x, face_size.y * scale_y)
    )
    draw_texture_rect(face_texture, draw_rect, false)


func _draw_ground() -> void:
    if not _ground_enabled:
        return
    if _ground_texture == null:
        return

    var draw_size := _ground_draw_size()
    if draw_size.x <= 0.0 or draw_size.y <= 0.0:
        return

    var viewport_size: Vector2 = get_viewport_rect().size
    var draw_y := _ground_draw_y(viewport_size, draw_size)

    var modulate := Color(1.0, 1.0, 1.0, clampf(_ground_alpha, 0.0, 1.0))
    if _ground_tile_x:
        var start_x := fmod(_ground_x_offset, draw_size.x)
        if start_x > 0.0:
            start_x -= draw_size.x
        var draw_x := start_x
        var guard := 0
        while draw_x < viewport_size.x and guard < 256:
            guard += 1
            draw_texture_rect(
                _ground_texture,
                Rect2(Vector2(draw_x, draw_y), draw_size),
                false,
                modulate
            )
            draw_x += draw_size.x
    else:
        var centered_x := ((viewport_size.x - draw_size.x) * 0.5) + _ground_x_offset
        draw_texture_rect(
            _ground_texture,
            Rect2(Vector2(centered_x, draw_y), draw_size),
            false,
            modulate
        )


func _set_emote_from_state(state_id: String) -> void:
    if int(Time.get_unix_time_from_system()) < _manual_emote_until_unix:
        return
    var semantic := str(_state_emote_map.get(state_id, "default"))
    _set_emote_from_semantic(semantic, false, 0.0)


func _set_emote_from_semantic(semantic: String, lock_manual: bool = false, lock_seconds: float = 0.0) -> void:
    var next_semantic := semantic.strip_edges().to_lower()
    if next_semantic == "":
        next_semantic = "default"
    if lock_manual:
        _manual_emote_until_unix = int(Time.get_unix_time_from_system() + maxf(0.0, lock_seconds))
    _active_emote_semantic = next_semantic
    _active_face_variant = str(_face_emote_manifest.get(next_semantic, next_semantic))
    if _active_face_variant == "":
        _active_face_variant = "default"


func _load_emote_manifest(path_spec: String, pack_id: String) -> Dictionary:
    var fallback := {
        "default": "default",
        "happy": "smile",
        "sad": "cry",
        "angry": "angry",
        "surprised": "bewildered",
        "love": "love",
        "wink": "wink",
        "sleepy": "blink",
        "sick": "vomit",
        "pain": "pain",
    }
    var raw := _resolve_text(path_spec, pack_id)
    if raw == "":
        return fallback

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) == TYPE_DICTIONARY:
        return parsed as Dictionary
    return fallback


func _resolve_face_texture_for_overlay(frame_overlay: Dictionary) -> Texture2D:
    var default_path := str(frame_overlay.get("default_png", ""))
    if default_path == "":
        return null
    var cache_key := "%s|%s" % [_active_face_variant, default_path]
    if _face_texture_cache.has(cache_key):
        var cached = _face_texture_cache[cache_key]
        if cached is Texture2D:
            _last_face_texture_path = "%s (cached)" % cache_key
            return cached
        _last_face_texture_path = "missing (cached): %s" % cache_key
        return null

    var resolved: Texture2D = null
    for candidate in _face_variant_candidates(default_path, _active_face_variant):
        resolved = _resolve_texture(candidate, _active_pack_id)
        if resolved != null:
            _last_face_texture_path = candidate
            break

    _face_texture_cache[cache_key] = resolved
    if resolved == null:
        _last_face_texture_path = "missing: %s" % cache_key
    return resolved


func _face_variant_candidates(default_path: String, variant: String) -> Array[String]:
    var candidates: Array[String] = []
    if variant == "" or variant == "default":
        candidates.append(default_path)
        return candidates

    if default_path.find("/default/face.png") >= 0:
        candidates.append(default_path.replace("/default/face.png", "/%s/0/face.png" % variant))
        candidates.append(default_path.replace("/default/face.png", "/%s/face.png" % variant))
    if default_path.find("\\default\\face.png") >= 0:
        candidates.append(default_path.replace("\\default\\face.png", "\\%s\\0\\face.png" % variant))
        candidates.append(default_path.replace("\\default\\face.png", "\\%s\\face.png" % variant))
    if default_path.find("/default/0/face.png") >= 0:
        candidates.append(default_path.replace("/default/0/face.png", "/%s/0/face.png" % variant))
        candidates.append(default_path.replace("/default/0/face.png", "/%s/face.png" % variant))
    if default_path.find("\\default\\0\\face.png") >= 0:
        candidates.append(default_path.replace("\\default\\0\\face.png", "\\%s\\0\\face.png" % variant))
        candidates.append(default_path.replace("\\default\\0\\face.png", "\\%s\\face.png" % variant))

    candidates.append(default_path)
    return candidates


func _sprite_rect_for_texture(center: Vector2, texture: Texture2D) -> Rect2:
    var tex_size: Vector2 = texture.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return Rect2(center, Vector2.ZERO)

    var viewport_size: Vector2 = get_viewport_rect().size
    var scale := _fit_scale_for_viewport(tex_size, viewport_size)
    var draw_size: Vector2 = tex_size * scale
    var use_pivot := _current_frame_pivot_px.y >= 0.0
    var top_left := Vector2.ZERO
    if use_pivot:
        var pivot_to_use := _current_frame_pivot_px
        if pivot_to_use.y > tex_size.y:
            var overflow := pivot_to_use.y - tex_size.y
            var overflow_blend := _pivot_overflow_blend_for_action(_current_visual_action)
            pivot_to_use.y = tex_size.y + (overflow * overflow_blend)
        top_left = center - (pivot_to_use * scale)
    else:
        var anchor := _current_frame_anchor
        anchor.x = clampf(anchor.x, -3.0, 3.0)
        anchor.y = clampf(anchor.y, -3.0, 3.0)
        top_left = center - Vector2(draw_size.x * anchor.x, draw_size.y * anchor.y)
    var min_x := SPRITE_VIEW_MARGIN
    var min_y := SPRITE_VIEW_MARGIN
    var max_x := viewport_size.x - draw_size.x - SPRITE_VIEW_MARGIN
    var max_y := viewport_size.y - draw_size.y - SPRITE_VIEW_MARGIN
    top_left.x = clampf(top_left.x, min_x, maxf(min_x, max_x))
    if not use_pivot:
        top_left.y = clampf(top_left.y, min_y, maxf(min_y, max_y))
    return Rect2(top_left, draw_size)


func _pivot_overflow_blend_for_action(action_id: String) -> float:
    if action_id == "sleep":
        # Keep prone between floating and over-sunk.
        return SLEEP_PIVOT_OVERFLOW_BLEND
    if action_id == "sit":
        # Preserve full chair-height offset exported in sit metadata.
        return SIT_PIVOT_OVERFLOW_BLEND
    # Use exported per-frame pivot metadata to keep a consistent floor anchor
    # across idle/walk/happy/etc animations.
    return 1.0


func _fit_scale_for_viewport(tex_size: Vector2, viewport_size: Vector2) -> float:
    var max_width := maxf(32.0, viewport_size.x - (SPRITE_VIEW_MARGIN * 2.0))
    var max_height := maxf(32.0, viewport_size.y - (SPRITE_VIEW_MARGIN * 2.0))
    var width_scale := max_width / tex_size.x
    var height_scale := max_height / tex_size.y
    return minf(_sprite_scale, minf(width_scale, height_scale))


func _effective_hit_radius() -> float:
    if _current_texture != null:
        var tex_size: Vector2 = _current_texture.get_size() * _sprite_scale
        return maxf(FALLBACK_HIT_RADIUS, maxf(tex_size.x, tex_size.y) * 0.28)
    return FALLBACK_HIT_RADIUS


func _resolve_texture(path_spec: String, pack_id: String) -> Texture2D:
    var res_candidates: Array[String] = []
    if path_spec.begins_with("res://"):
        res_candidates.append(path_spec)
    else:
        res_candidates.append("res://content/%s/%s" % [pack_id, path_spec])

    for res_path in res_candidates:
        if ResourceLoader.exists(res_path):
            var resource = load(res_path)
            if resource is Texture2D:
                return resource

        var fs_path := ProjectSettings.globalize_path(res_path)
        var loaded_fs := _load_texture_from_file(fs_path)
        if loaded_fs != null:
            return loaded_fs

    if not path_spec.begins_with("res://"):
        var direct_loaded := _load_texture_from_file(path_spec)
        if direct_loaded != null:
            return direct_loaded

    return null


func _load_texture_from_file(fs_path: String) -> Texture2D:
    if not FileAccess.file_exists(fs_path):
        return null

    var image := Image.new()
    var err := image.load(fs_path)
    if err != OK:
        return null

    return ImageTexture.create_from_image(image)


func _load_animation_spec(path_spec: String, pack_id: String) -> Dictionary:
    var text_bundle := _resolve_text_with_source(path_spec, pack_id)
    var raw := str(text_bundle.get("text", ""))
    if raw == "":
        return {}
    var animation_source_path := str(text_bundle.get("source", ""))

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var animation_data: Dictionary = parsed
    var animation_state := str(animation_data.get("state", ""))
    var animation_dir := animation_source_path.get_base_dir()

    var sheet_path := str(animation_data.get("sheet", ""))
    if sheet_path == "":
        return {}
    var sheet_texture := _resolve_texture(sheet_path, pack_id)
    if sheet_texture == null:
        return {}

    var frames_variant = animation_data.get("frames", [])
    if typeof(frames_variant) != TYPE_ARRAY:
        return {}

    var frames: Array = []
    var durations: Array = []
    var anchors: Array = []
    var pivots: Array = []
    var face_overlays: Array = []
    var max_pivot_y := 0.0
    for frame_variant in frames_variant:
        if typeof(frame_variant) != TYPE_DICTIONARY:
            continue
        var frame_data: Dictionary = frame_variant
        var rect_variant = frame_data.get("rect", [])
        if typeof(rect_variant) != TYPE_ARRAY or (rect_variant as Array).size() < 4:
            continue
        var rect_values: Array = rect_variant
        var rect_x := int(rect_values[0])
        var rect_y := int(rect_values[1])
        var rect_w := int(rect_values[2])
        var rect_h := int(rect_values[3])
        if rect_w <= 0 or rect_h <= 0:
            continue

        var atlas := AtlasTexture.new()
        atlas.atlas = sheet_texture
        atlas.region = Rect2(rect_x, rect_y, rect_w, rect_h)
        frames.append(atlas)
        var source_frame := int(frame_data.get("source_frame", int(frame_data.get("index", 0))))
        face_overlays.append(_load_face_overlay_for_frame(animation_dir, animation_state, source_frame))

        var duration_ms_raw = frame_data.get("duration_ms", 120)
        var duration_seconds := 0.12
        if typeof(duration_ms_raw) == TYPE_FLOAT or typeof(duration_ms_raw) == TYPE_INT:
            duration_seconds = maxf(0.03, float(duration_ms_raw) / 1000.0)
        durations.append(duration_seconds)

        var frame_anchor := _sprite_anchor
        var frame_pivot := NO_PIVOT
        var pivot_variant = frame_data.get("pivot_px", [])
        if typeof(pivot_variant) == TYPE_ARRAY and (pivot_variant as Array).size() >= 2:
            var pivot_array: Array = pivot_variant
            var pivot_x := float(pivot_array[0])
            var pivot_y := float(pivot_array[1])
            frame_pivot = Vector2(pivot_x, pivot_y)
            max_pivot_y = maxf(max_pivot_y, pivot_y)
            if rect_w > 0 and rect_h > 0:
                frame_anchor = Vector2(pivot_x / float(rect_w), pivot_y / float(rect_h))

        anchors.append(frame_anchor)
        pivots.append(frame_pivot)

    if frames.is_empty():
        return {}

    return {
        "frames": frames,
        "durations": durations,
        "anchors": anchors,
        "pivots": pivots,
        "face_overlays": face_overlays,
        "max_pivot_y": max_pivot_y,
        "loop": bool(animation_data.get("loop", true)),
    }


func _load_face_overlay_for_frame(animation_dir: String, animation_state: String, source_frame: int) -> Dictionary:
    if animation_dir == "" or animation_state == "":
        return {}
    var frame_rel_path := "%s/frames/%03d.json" % [animation_state, source_frame]
    var metadata_path := animation_dir.path_join(frame_rel_path)
    var raw := _read_text_file(metadata_path)
    if raw == "":
        return {}

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var metadata: Dictionary = parsed
    var bounds_variant = metadata.get("frame_bounds_world", {})
    if typeof(bounds_variant) != TYPE_DICTIONARY:
        return {}
    var bounds: Dictionary = bounds_variant
    var bounds_left := float(bounds.get("left", 0.0))
    var bounds_top := float(bounds.get("top", 0.0))

    var draw_order_variant = metadata.get("draw_order", [])
    if typeof(draw_order_variant) != TYPE_ARRAY:
        return {}
    var draw_order: Array = draw_order_variant
    for entry_variant in draw_order:
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        if str(entry.get("asset_kind", "")) != "face":
            continue
        var top_left_variant = entry.get("top_left", [])
        if typeof(top_left_variant) != TYPE_ARRAY or (top_left_variant as Array).size() < 2:
            continue
        var top_left: Array = top_left_variant
        var local_x := float(top_left[0]) - bounds_left
        var local_y := float(top_left[1]) - bounds_top
        var default_path := str(entry.get("png", ""))
        if default_path == "":
            continue
        return {
            "default_png": default_path,
            "local_top_left": [local_x, local_y],
        }
    return {}


func _resolve_text(path_spec: String, pack_id: String) -> String:
    var bundle := _resolve_text_with_source(path_spec, pack_id)
    return str(bundle.get("text", ""))


func _resolve_text_with_source(path_spec: String, pack_id: String) -> Dictionary:
    var res_candidates: Array[String] = []
    if path_spec.begins_with("res://"):
        res_candidates.append(path_spec)
    else:
        res_candidates.append("res://content/%s/%s" % [pack_id, path_spec])

    for res_path in res_candidates:
        var from_res := _read_text_file(res_path)
        if from_res != "":
            return {"text": from_res, "source": res_path}

        var fs_path := ProjectSettings.globalize_path(res_path)
        var from_fs := _read_text_file(fs_path)
        if from_fs != "":
            return {"text": from_fs, "source": fs_path}

    if not path_spec.begins_with("res://"):
        var from_direct := _read_text_file(path_spec)
        if from_direct != "":
            return {"text": from_direct, "source": path_spec}
    return {}


func _read_text_file(path: String) -> String:
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var content := file.get_as_text()
    file.close()
    return content


func _load_core_character_animation_fallbacks() -> void:
    var actions := ["idle", "wander", "sit", "sleep", "happy", "gift", "visitor"]
    for action_id in actions:
        var res_path: String = "res://content/core_pack/character/animations/%s.json" % action_id
        var animation := _load_animation_spec(res_path, "core_pack")
        if not animation.is_empty():
            _action_animations[action_id] = animation
            var max_pivot_variant = animation.get("max_pivot_y", 0.0)
            if typeof(max_pivot_variant) == TYPE_INT or typeof(max_pivot_variant) == TYPE_FLOAT:
                _max_loaded_pivot_px_y = maxf(_max_loaded_pivot_px_y, float(max_pivot_variant))


func _load_core_character_sprite_fallbacks() -> void:
    var actions := ["idle", "wander", "sit", "sleep", "happy", "gift", "visitor"]
    for action_id in actions:
        var res_path: String = "res://content/core_pack/character/%s.png" % action_id
        var texture := _resolve_texture(res_path, "core_pack")
        if texture != null:
            _action_textures[action_id] = texture


func _maybe_show_bond_phrase() -> void:
    if _bond_phrase_active or randi() % 6 != 0:
        return
    var tier := AppState.get_bond_tier()
    var phrases: Variant = tier.get("idle_phrases", null)
    if typeof(phrases) != TYPE_ARRAY or (phrases as Array).is_empty():
        return
    var phrase := str((phrases as Array)[randi() % (phrases as Array).size()])
    if phrase == "" or phrase == "...":
        return
    _bond_phrase_active = true
    _update_balloon_position()
    chat_balloon.show_text(phrase)
    await get_tree().create_timer(4.0).timeout
    chat_balloon.hide_bubble()
    _bond_phrase_active = false


func _update_balloon_position() -> void:
    var head_y := _current_sprite_rect.position.y if _current_sprite_rect.size.y > 0.0 else _draw_center.y - 80.0
    chat_balloon.position = Vector2(_draw_center.x, head_y)


func _return_to_idle_after_drag() -> void:
    await get_tree().create_timer(0.5).timeout
    if not _dragging:
        _state = "idle"
        _set_emote_from_state(_state)
        _set_visual_for_state(_state)
        queue_redraw()


func _show_welcome_once() -> void:
    welcome_label.visible = true
    AppState.mark_first_run_seen()
    await get_tree().create_timer(6.0).timeout
    welcome_label.visible = false


func _show_while_away_report_once() -> void:
    if _away_report_shown:
        return
    _away_report_shown = true
    var summary := AppState.get_last_active_summary()
    if summary == "":
        return
    _update_balloon_position()
    chat_balloon.show_text(summary)
    await get_tree().create_timer(5.0).timeout
    chat_balloon.hide_bubble()
    AppState.clear_last_active_summary()
    _show_continuity_hint_once()


func _show_continuity_hint_once() -> void:
    if _continuity_hint_shown or not bool(AppState.settings.get("supportHintsEnabled", true)):
        return
    _continuity_hint_shown = true
    var hint := AppState.get_continuity_hint()
    if hint == "":
        return
    _update_balloon_position()
    chat_balloon.show_text(hint)
    await get_tree().create_timer(4.0).timeout
    chat_balloon.hide_bubble()


func _open_debug_reward_box() -> void:
    var box_ids := AppState.get_reward_box_ids()
    if box_ids.is_empty():
        _update_balloon_position()
        chat_balloon.show_text("No reward boxes configured.")
        return
    var preferred := "cozy_box" if box_ids.has("cozy_box") else str(box_ids[0])
    var result := AppState.open_reward_box(preferred)
    _update_balloon_position()
    if bool(result.get("ok", false)):
        var item_name := str(result.get("item_name", "item"))
        var item_rarity := str(result.get("item_rarity", "common"))
        if bool(result.get("duplicate", false)):
            var recycle := int(result.get("recycle_crystals", 0))
            chat_balloon.show_text(
                "Opened %s: %s [%s] (duplicate +%d crystals)"
                % [preferred, item_name, item_rarity, recycle]
            )
        else:
            chat_balloon.show_text("Opened %s: %s [%s]" % [preferred, item_name, item_rarity])
    else:
        var reason := str(result.get("reason", "unavailable"))
        chat_balloon.show_text("Could not open %s (%s)" % [preferred, reason])


func _show_world_prompt(prompt: Dictionary) -> void:
    var prompt_type := str(prompt.get("type", ""))
    var npc_name := str(prompt.get("npcName", "Villager"))
    var text := str(prompt.get("text", ""))
    if text == "":
        return
    _update_balloon_position()
    if prompt_type == "encounter":
        chat_balloon.show_text("%s: %s (F12 engage / Shift+F12 skip)" % [npc_name, text])
    else:
        chat_balloon.show_text("%s: %s (F12 complete)" % [npc_name, text])


func _resolve_world_prompt(engage_encounter: bool) -> void:
    var world_snapshot := AppState.get_world_snapshot()
    var pending_encounter := str(world_snapshot.get("pending_encounter_id", ""))
    var pending_quest := str(world_snapshot.get("pending_quest_id", ""))
    _update_balloon_position()
    if pending_encounter != "":
        var encounter_result := AppState.resolve_pending_encounter(engage_encounter)
        if bool(encounter_result.get("ok", false)):
            var npc := str(encounter_result.get("npc_name", "Villager"))
            var crystals := int(encounter_result.get("crystals", 0))
            var item_name := str(encounter_result.get("item_name", ""))
            var action_word := "engaged" if engage_encounter else "skipped"
            var reward_text := "+%d crystals" % crystals
            if item_name != "":
                reward_text += " + %s" % item_name
            chat_balloon.show_text("%s encounter %s: %s" % [npc, action_word, reward_text])
        else:
            chat_balloon.show_text("No encounter to resolve.")
        _refresh_telemetry()
        return

    if pending_quest != "":
        var quest_result := AppState.complete_pending_quest()
        if bool(quest_result.get("ok", false)):
            var npc_name := str(quest_result.get("npc_name", "Villager"))
            var crystals_value := int(quest_result.get("crystals", 0))
            var reward_line := "+%d crystals" % crystals_value
            var item := str(quest_result.get("item_name", ""))
            if item != "":
                reward_line += " + %s" % item
            chat_balloon.show_text("%s quest complete: %s" % [npc_name, reward_line])
        else:
            chat_balloon.show_text("No quest to complete.")
        _refresh_telemetry()
        return

    chat_balloon.show_text("No pending world prompt.")


func _cycle_home_mode() -> void:
    var snapshot := AppState.get_world_snapshot()
    var current_mode := str(snapshot.get("home_mode", "overlay"))
    var next_mode := "home" if current_mode != "home" else "overlay"
    AppState.set_home_mode(next_mode)
    _update_balloon_position()
    var home_name := str(snapshot.get("home_scene_id", "cozy_starter_room"))
    if next_mode == "home":
        var wall_decor := str(snapshot.get("home_wall_decor", ""))
        var suffix := ""
        if wall_decor != "":
            suffix = " wall decor: %s" % wall_decor
        chat_balloon.show_text("Home mode active (%s)%s" % [home_name, suffix])
    else:
        chat_balloon.show_text("Overlay mode active.")
    _refresh_telemetry()


func _show_support_hint(productivity_event: Dictionary) -> void:
    if not bool(AppState.settings.get("supportHintsEnabled", true)):
        return
    var event_id := str(productivity_event.get("id", ""))
    var line := ""
    if event_id == "focus-celebration":
        line = "You are focused. Nice momentum."
    elif event_id == "break-suggestion":
        line = "Quick stretch break could help."
    elif event_id == "late-session-checkin":
        line = "It is getting late. Want to wind down?"
    if line == "":
        return
    _update_balloon_position()
    chat_balloon.show_text(line)
