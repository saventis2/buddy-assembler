extends Node2D

const BUDDY_RADIUS := 34.0
const FALLBACK_HIT_RADIUS := 44.0
const IDLE_SWAY_SPEED := 0.9
const IDLE_SWAY_DISTANCE_X := 0.0
const IDLE_SWAY_DISTANCE_Y := 0.0
const FLOOR_PADDING := 14.0
const SPRITE_VIEW_MARGIN := 4.0
const DEFAULT_SPRITE_ANCHOR := Vector2(0.5, 1.0)
const NO_PIVOT := Vector2(-1.0, -1.0)
const SLEEP_PIVOT_OVERFLOW_BLEND := 0.5

const BehaviorEngine = preload("res://scripts/behavior/behavior_engine.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")
const EncounterScheduler = preload("res://scripts/encounters/encounter_scheduler.gd")
const ProductivityTracker = preload("res://scripts/utility/productivity_tracker.gd")

@onready var tick_timer: Timer = $TickTimer
@onready var telemetry_timer: Timer = $TelemetryTimer
@onready var telemetry_label: Label = $Telemetry/Label

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
            elif key_event.keycode == KEY_F7:
                _cycle_event_frequency()
            elif key_event.keycode == KEY_F8:
                _move_to_next_monitor()
            elif key_event.keycode == KEY_F9:
                _cycle_pack()

    if event is InputEventMouseButton:
        var button_event := event as InputEventMouseButton
        if button_event.button_index == MOUSE_BUTTON_LEFT:
            if button_event.pressed and _hit_test(button_event.position):
                _dragging = true
                _drag_offset = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
                _state = "happy"
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
        elif button_event.button_index == MOUSE_BUTTON_RIGHT and button_event.pressed:
            if _hit_test(button_event.position):
                _state = "sleep" if _state != "sleep" else "idle"
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
    return Vector2(viewport_size.x * 0.5, viewport_size.y - SPRITE_VIEW_MARGIN)


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
    var context := {
        "is_night": _is_night(),
        "bond_level": int(AppState.profile.get("bond_level", 1)),
        "quiet_mode": AppState.is_quiet_hours_now(),
        "event_frequency": str(AppState.settings.get("eventFrequency", "normal")),
        "allowed_actions": _allowed_actions,
        "unlocked_actions": AppState.get_unlocked_actions(),
    }

    var productivity_event := _productivity.tick(now_unix, AppState.settings)
    if not productivity_event.is_empty():
        var prod_event_id := str(productivity_event.get("id", ""))
        var prod_action := str(productivity_event.get("action", "happy"))
        context["forced_action"] = prod_action
        _last_event_id = prod_event_id
        AppState.record_event_trigger(prod_event_id, prod_action)

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

    var action := _engine.tick(now_unix, context)
    _state = str(action.get("id", "idle"))
    _set_visual_for_state(_state)
    AppState.apply_behavior(_state)
    _refresh_telemetry()


func _is_night() -> bool:
    var now := Time.get_datetime_dict_from_system()
    var hour := int(now.get("hour", 12))
    return hour < 7 or hour >= 22


func _load_content_pack() -> void:
    var selected_pack := str(AppState.settings.get("selectedPackId", "core_pack"))
    var loaded := ContentLoader.load_pack(selected_pack)
    if not bool(loaded.get("ok", false)):
        loaded = ContentLoader.load_pack("core_pack")
        selected_pack = "core_pack"

    _active_pack_id = selected_pack
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
    return Rect2i(
        DisplayServer.screen_get_position(normalized),
        DisplayServer.screen_get_size(normalized)
    )


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
    telemetry_label.visible = _telemetry_enabled
    if not _telemetry_enabled:
        return

    var snapshot := AppState.get_telemetry_snapshot()
    var lines := [
        "state: %s" % _state,
        "level: %d  xp: %d" % [int(snapshot.get("bond_level", 1)), int(snapshot.get("bond_xp", 0))],
        "pack: %s" % str(snapshot.get("active_pack", "core_pack")),
        "freq: %s  quiet: %s" % [
            str(AppState.settings.get("eventFrequency", "normal")),
            "on" if AppState.is_quiet_hours_now() else "off"
        ],
        "focus mins: %d  prod: %s" % [
            _productivity.focus_minutes(int(Time.get_unix_time_from_system())),
            "on" if bool(AppState.settings.get("productivityOptIn", false)) else "off"
        ],
        "screen: %d" % DisplayServer.window_get_current_screen(),
        "pack id: %s" % _active_pack_id,
        "sprite: %s" % _sprite_debug_label(),
        "ground: disabled",
        "last event: %s" % _last_event_id,
        "F6 telemetry  F7 freq  F8 monitor  F9 pack",
    ]
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
        # Prone/sleep exports use world-floor pivots that can sit below the cropped frame.
        # Keep part of that overflow so sleep lands between floating and over-sunk.
        if _current_visual_action == "sleep":
            if pivot_to_use.y > tex_size.y:
                var overflow := pivot_to_use.y - tex_size.y
                pivot_to_use.y = tex_size.y + (overflow * SLEEP_PIVOT_OVERFLOW_BLEND)
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
    var raw := _resolve_text(path_spec, pack_id)
    if raw == "":
        return {}

    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var animation_data: Dictionary = parsed

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
        "max_pivot_y": max_pivot_y,
        "loop": bool(animation_data.get("loop", true)),
    }


func _resolve_text(path_spec: String, pack_id: String) -> String:
    var res_candidates: Array[String] = []
    if path_spec.begins_with("res://"):
        res_candidates.append(path_spec)
    else:
        res_candidates.append("res://content/%s/%s" % [pack_id, path_spec])

    for res_path in res_candidates:
        var from_res := _read_text_file(res_path)
        if from_res != "":
            return from_res

        var fs_path := ProjectSettings.globalize_path(res_path)
        var from_fs := _read_text_file(fs_path)
        if from_fs != "":
            return from_fs

    if not path_spec.begins_with("res://"):
        var from_direct := _read_text_file(path_spec)
        if from_direct != "":
            return from_direct
    return ""


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
        var res_path := "res://content/core_pack/character/animations/%s.json" % action_id
        var animation := _load_animation_spec(res_path, "core_pack")
        if not animation.is_empty():
            _action_animations[action_id] = animation
            var max_pivot_variant = animation.get("max_pivot_y", 0.0)
            if typeof(max_pivot_variant) == TYPE_INT or typeof(max_pivot_variant) == TYPE_FLOAT:
                _max_loaded_pivot_px_y = maxf(_max_loaded_pivot_px_y, float(max_pivot_variant))


func _load_core_character_sprite_fallbacks() -> void:
    var actions := ["idle", "wander", "sit", "sleep", "happy", "gift", "visitor"]
    for action_id in actions:
        var res_path := "res://content/core_pack/character/%s.png" % action_id
        var texture := _resolve_texture(res_path, "core_pack")
        if texture != null:
            _action_textures[action_id] = texture
