extends Node2D

const BUDDY_RADIUS := 34.0
const FALLBACK_HIT_RADIUS := 44.0
const IDLE_SWAY_SPEED := 0.9
const IDLE_SWAY_DISTANCE_X := 0.0
const IDLE_SWAY_DISTANCE_Y := 0.0
const FLOOR_PADDING := 14.0
const SPRITE_VIEW_MARGIN := 4.0
const DESKTOP_FLOOR_CONTACT_OFFSET_Y := 10.0
const CHARACTER_FLOOR_OFFSET_PX := 15.0
const ACTION_EXTRA_FLOOR_OFFSET := {
    "sleep": 15.0,
}
const DEFAULT_ROAM_SPEED_PX_PER_SEC := 96.0
const FLOOR_SETTLE_SPEED_PX_PER_SEC := 720.0
const SETTINGS_WINDOW_OFFSET := Vector2i(56, 56)
const SETTINGS_WINDOW_MIN_SIZE := Vector2i(320, 380)
const SETTINGS_WINDOW_DEFAULT_SIZE := Vector2i(360, 460)
const CHAT_TRANSCRIPT_MAX_LINES := 120
const CHAT_SEPARATOR_IDLE_SECONDS := 600
const CHAT_RECENT_REPLY_MAX := 20
const CHAT_FOLLOW_UP_MIN_TURNS := 3
const CHAT_MEMORY_MAX_NOTES := 10
const CHAT_FONT_SIZE_M := 13
const CHAT_FONT_SIZE_L := 16
const SETTINGS_CHANGE_HISTORY_MAX := 20
const DEFAULT_SPRITE_ANCHOR := Vector2(0.5, 1.0)
const NO_PIVOT := Vector2(-1.0, -1.0)
const SLEEP_PIVOT_OVERFLOW_BLEND := 1.0
const SIT_PIVOT_OVERFLOW_BLEND := 1.0
const DEFAULT_EMOTE_MANIFEST_PATH := "character/emotes/manifest.json"
const SIT_CHAIR_FRAME_PATH := "effects/chair_basic/frames/000.png"
const SIT_CHAIR_EFFECT_PATH := "effects/chair_basic/effect.json"
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
const ChatCommandRouter = preload("res://scripts/interaction/chat_command_router.gd")
const ProductivityTracker = preload("res://scripts/utility/productivity_tracker.gd")
const PromptCadence = preload("res://scripts/utility/prompt_cadence.gd")
const ManualVerificationReport = preload("res://scripts/utility/manual_verification_report.gd")

@onready var tick_timer: Timer = $TickTimer
@onready var telemetry_timer: Timer = $TelemetryTimer
@onready var telemetry_label: Label = $Telemetry/Label
@onready var settings_window: Window = $SettingsWindow
@onready var settings_label: RichTextLabel = $SettingsWindow/MarginContainer/SettingsVBox/SettingsLabel
@onready var settings_btn_event_freq: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnEventFreq
@onready var settings_btn_prompt_freq: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnPromptFreq
@onready var settings_btn_quiet: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnQuietStrict
@onready var settings_btn_intensity: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnIntensity
@onready var settings_btn_mode: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnMode
@onready var settings_btn_pack: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnPack
@onready var settings_btn_demo_support: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnDemoSupport
@onready var settings_btn_demo_world: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnDemoWorld
@onready var settings_btn_reward: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnReward
@onready var settings_btn_telemetry: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnTelemetry
@onready var settings_btn_restart: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnRestart
@onready var settings_btn_quit: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnQuit
@onready var settings_btn_chat: Button = $SettingsWindow/MarginContainer/SettingsVBox/ControlsGrid/BtnChat
@onready var settings_floor_slider: HSlider = $SettingsWindow/MarginContainer/SettingsVBox/FloorAdjustBox/FloorAdjustRow/FloorAdjustSlider
@onready var settings_floor_value: Label = $SettingsWindow/MarginContainer/SettingsVBox/FloorAdjustBox/FloorAdjustRow/FloorAdjustValue
@onready var chat_window: Window = $ChatWindow
@onready var chat_log: RichTextLabel = $ChatWindow/MarginContainer/ChatVBox/ChatLog
@onready var chat_input: LineEdit = $ChatWindow/MarginContainer/ChatVBox/ChatInputRow/ChatInput
@onready var chat_send: Button = $ChatWindow/MarginContainer/ChatVBox/ChatInputRow/ChatSend
@onready var chat_balloon: Node2D = $ChatBalloon
@onready var welcome_label: Label = $WelcomeLayer/WelcomeLabel

var _engine := BehaviorEngine.new()
var _encounters := EncounterScheduler.new()
var _chat_router := ChatCommandRouter.new()
var _productivity := ProductivityTracker.new()
var _prompt_cadence := PromptCadence.new()
var _manual_verification_report := ManualVerificationReport.new()
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
var _settings_menu_open := false
var _chat_window_open := false
var _manual_emote_until_unix := 0
var _last_face_texture_path := ""
var _roam_speed_px_per_sec := DEFAULT_ROAM_SPEED_PX_PER_SEC
var _roam_direction := 1
var _roam_subpixel_x := 0.0
var _floor_settle_active := false
var _bond_phrase_active := false
var _last_idle_phrase_unix := 0
var _away_report_shown := false
var _continuity_hint_shown := false
var _last_auto_prompt_unix := 0
var _last_auto_prompt_by_source := {}
var _deferred_world_prompt := {}
var _desktop_floor_offset_adjust := 0.0
var _sit_chair_texture: Texture2D = null
var _sit_chair_origin_px := Vector2.ZERO
var _chat_turn_user_count := 0
var _chat_turn_buddy_count := 0
var _chat_cmd_ok_count := 0
var _chat_cmd_fail_count := 0
var _chat_cmd_reason_counts := {}
var _chat_cmd_last_key_by_action := {}
var _chat_last_command_id := ""
var _chat_last_reason_code := ""
var _chat_last_line_unix := 0
var _chat_recent_buddy_norm_lines: Array = []
var _chat_last_followup_turn := -100
var _chat_memory_tag_counts := {
    "goal": 0,
    "mood": 0,
    "task": 0,
    "reward": 0,
    "world": 0,
    "support": 0,
}
var _chat_memory_turn_tags: Array = []
var _chat_memory_notes: Array = []
var _chat_memory_next_note_id := 1
var _chat_memory_pending_forget_id := -1
var _chat_memory_pending_forget_until := 0
var _chat_unread_prompt_count := 0
var _chat_cmd_latency_last_ms := 0
var _chat_cmd_latency_total_ms := 0
var _chat_cmd_latency_samples := 0
var _settings_undo_snapshot := {}
var _settings_undo_until_unix := 0
var _settings_change_history: Array = []


func _ready() -> void:
    position = Vector2.ZERO
    _desktop_floor_offset_adjust = _read_floor_offset_adjust_setting()
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
    _configure_settings_window()
    _configure_chat_window()
    _refresh_telemetry()
    if AppState.is_first_run():
        _show_welcome_once()
    else:
        _show_while_away_report_once()


func _configure_window() -> void:
    # Force subwindows (like F10 settings) to become real OS windows,
    # not embedded UI panels inside the transparent overlay viewport.
    get_viewport().gui_embed_subwindows = false
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
            elif key_event.keycode == KEY_F1:
                _export_manual_verification_snapshot()
            elif key_event.keycode == KEY_F2:
                if key_event.shift_pressed:
                    _show_auto_prompt("Demo support prompt (Shift+F2).", "support")
                else:
                    _cycle_prompt_frequency()
            elif key_event.keycode == KEY_F5:
                _cycle_home_mode()
            elif key_event.keycode == KEY_F7:
                if key_event.shift_pressed:
                    _show_world_prompt(
                        {
                            "type": "encounter",
                            "npcName": "Demo",
                            "text": "Demo world prompt for cadence check.",
                        }
                    )
                else:
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
                _toggle_settings_menu()
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
                var before := AppState.get_telemetry_snapshot()
                _dragging = true
                _drag_offset = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
                _state = "happy"
                _set_emote_from_state(_state)
                _set_visual_for_state(_state)
                AppState.record_interaction("pet")
                var after := AppState.get_telemetry_snapshot()
                _show_progress_feedback(before, after)
                _productivity.note_user_activity(int(Time.get_unix_time_from_system()))
                queue_redraw()
            elif not button_event.pressed:
                _dragging = false
                AppState.set_window_state(
                    DisplayServer.window_get_current_screen(),
                    DisplayServer.window_get_position()
                )
                _floor_settle_active = true
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


func _configure_settings_window() -> void:
    if settings_window == null:
        return
    settings_window.transient = false
    settings_window.exclusive = false
    settings_window.borderless = false
    settings_window.visible = false
    settings_window.unresizable = false
    settings_window.min_size = SETTINGS_WINDOW_MIN_SIZE
    settings_window.size = SETTINGS_WINDOW_DEFAULT_SIZE
    settings_window.title = "Maple Buddy Menu"
    settings_window.wrap_controls = true
    settings_window.always_on_top = true
    settings_window.close_requested.connect(func() -> void:
        settings_window.hide()
        _settings_menu_open = false
    )
    settings_btn_event_freq.pressed.connect(func() -> void:
        _cycle_event_frequency()
    )
    settings_btn_event_freq.tooltip_text = "Controls world-event cadence. Low is calmer; high is busier."
    settings_btn_prompt_freq.pressed.connect(func() -> void:
        _cycle_prompt_frequency()
    )
    settings_btn_prompt_freq.tooltip_text = "Controls support-prompt cadence. Low reduces interruptions."
    settings_btn_quiet.pressed.connect(func() -> void:
        _cycle_quiet_strictness()
    )
    settings_btn_quiet.tooltip_text = "Strict suppresses almost all non-critical prompts."
    settings_btn_intensity.pressed.connect(func() -> void:
        _cycle_interaction_intensity()
    )
    settings_btn_intensity.tooltip_text = "Cozy = lighter progression cadence, Deep = denser progression cadence."
    settings_btn_mode.pressed.connect(func() -> void:
        _cycle_home_mode()
    )
    settings_btn_mode.tooltip_text = "Switch between Home behavior and Overlay behavior."
    settings_btn_pack.pressed.connect(func() -> void:
        _cycle_pack()
    )
    settings_btn_pack.tooltip_text = "Cycles active content pack for visuals/content mappings."
    settings_btn_demo_support.pressed.connect(func() -> void:
        _show_auto_prompt("Demo support prompt (menu).", "support")
    )
    settings_btn_demo_support.tooltip_text = "Manual support prompt trigger for cadence verification."
    settings_btn_demo_world.pressed.connect(func() -> void:
        _show_world_prompt(
            {
                "type": "encounter",
                "npcName": "Demo",
                "text": "Demo world prompt from menu.",
            }
        )
    )
    settings_btn_demo_world.tooltip_text = "Manual world prompt trigger for cadence verification."
    settings_btn_reward.pressed.connect(func() -> void:
        _open_debug_reward_box()
    )
    settings_btn_reward.tooltip_text = "Opens a debug reward box using current economy state."
    settings_btn_telemetry.pressed.connect(func() -> void:
        _telemetry_enabled = not _telemetry_enabled
        _refresh_telemetry()
    )
    settings_btn_telemetry.tooltip_text = "Toggles runtime telemetry overlay."
    settings_btn_restart.pressed.connect(func() -> void:
        _restart_runtime()
    )
    settings_btn_restart.tooltip_text = "Restarts runtime process/scene and preserves saved state."
    settings_btn_quit.pressed.connect(func() -> void:
        _quit_runtime()
    )
    settings_btn_quit.tooltip_text = "Closes runtime process."
    settings_btn_chat.pressed.connect(func() -> void:
        _toggle_chat_window()
    )
    settings_btn_chat.tooltip_text = "Opens/closes the Buddy Chat popout window."
    if settings_floor_slider != null:
        settings_floor_slider.value_changed.connect(func(value: float) -> void:
            _set_floor_offset_adjust(value)
        )
        settings_floor_slider.set_value_no_signal(_desktop_floor_offset_adjust)


func _configure_chat_window() -> void:
    if chat_window == null:
        return
    chat_window.transient = false
    chat_window.exclusive = false
    chat_window.borderless = false
    chat_window.visible = false
    chat_window.always_on_top = true
    chat_window.unresizable = false
    chat_window.title = "Buddy Chat"
    chat_window.close_requested.connect(func() -> void:
        chat_window.hide()
        _chat_window_open = false
    )
    if chat_send != null:
        chat_send.pressed.connect(func() -> void:
            _send_chat_input()
        )
    if chat_input != null:
        chat_input.text_submitted.connect(func(_submitted: String) -> void:
            _send_chat_input()
        )
    _apply_chat_text_size()


func _draw() -> void:
    var center := _draw_center
    if _current_texture == null:
        _load_core_character_animation_fallbacks()
        _load_core_character_sprite_fallbacks()
        _set_visual_for_state(_state, true)

    _draw_sit_chair(center)
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
        viewport_size.y - SPRITE_VIEW_MARGIN + DESKTOP_FLOOR_CONTACT_OFFSET_Y + _desktop_floor_offset_adjust
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
    _flush_deferred_world_prompt(int(now_unix))
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

    if home_mode == "home":
        if not context.has("forced_action"):
            context["forced_action"] = _select_home_mode_action(now_unix)
    else:
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
        if not _show_world_prompt(world_prompt):
            _deferred_world_prompt = world_prompt.duplicate(true)
            _manual_verification_report.record_prompt_metric("world", "deferred")
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
    _set_setting_with_audit("eventFrequency", values[index], "cycle")
    AppState.flush()
    _emit_setting_feedback("eventFrequency", values[index])
    _update_balloon_position()
    _buddy_say("Event frequency: %s (Shift+F7 demo prompt)" % values[index])
    _refresh_telemetry()


func _cycle_prompt_frequency() -> void:
    var current := str(AppState.settings.get("promptFrequency", "normal"))
    var values := ["low", "normal", "high"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    _set_setting_with_audit("promptFrequency", values[index], "cycle")
    AppState.flush()
    _emit_setting_feedback("promptFrequency", values[index])
    _update_balloon_position()
    _buddy_say("Prompt frequency: %s (Shift+F2 demo prompt)" % values[index])
    _refresh_telemetry()


func _cycle_interaction_intensity() -> void:
    var current := str(AppState.settings.get("interactionIntensity", "balanced"))
    var values := ["cozy", "balanced", "deep"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    _set_setting_with_audit("interactionIntensity", values[index], "cycle")
    AppState.flush()
    _emit_setting_feedback("interactionIntensity", values[index])
    _update_balloon_position()
    _buddy_say("Interaction intensity: %s" % values[index])
    _refresh_telemetry()


func _cycle_quiet_strictness() -> void:
    var current := str(AppState.settings.get("quietModeStrictness", "balanced"))
    var values := ["lenient", "balanced", "strict"]
    var index := values.find(current)
    if index < 0:
        index = 1
    index = (index + 1) % values.size()
    _set_setting_with_audit("quietModeStrictness", values[index], "cycle")
    AppState.flush()
    _emit_setting_feedback("quietModeStrictness", values[index])
    _update_balloon_position()
    _buddy_say("Quiet strictness: %s" % values[index])
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

    if not roam_state:
        var floor_locked := _clamp_window_to_screen(current_pos, current_screen)
        if floor_locked.y != floor_y and (_floor_settle_active or current_pos.y != floor_y):
            var dir := 1 if floor_locked.y < floor_y else -1
            var step := int(round(FLOOR_SETTLE_SPEED_PX_PER_SEC * delta)) * dir
            if step == 0:
                step = dir
            floor_locked.y += step
            if (dir > 0 and floor_locked.y > floor_y) or (dir < 0 and floor_locked.y < floor_y):
                floor_locked.y = floor_y
        else:
            floor_locked.y = floor_y
        if floor_locked.y == floor_y:
            _floor_settle_active = false
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
    var ids := ContentLoader.list_cycleable_pack_ids()
    if ids.is_empty():
        _update_balloon_position()
        _buddy_say("No valid content packs found.")
        return
    if ids.size() == 1:
        var only_pack := str(ids[0])
        var loaded_only := ContentLoader.load_with_fallback(only_pack)
        var only_manifest_variant = loaded_only.get("manifest", null)
        if typeof(only_manifest_variant) != TYPE_DICTIONARY:
            _update_balloon_position()
            _buddy_say("Pack load failed: %s" % only_pack)
            return
        _active_pack_id = str(loaded_only.get("pack_id", only_pack))
        _active_manifest = only_manifest_variant as Dictionary
        _allowed_actions = ContentLoader.gather_action_ids(_active_manifest)
        _encounters.configure(
            _active_manifest.get("eventRules", []),
            int(AppState.profile.get("personality_seed", 0))
        )
        _load_visual_assets(_active_pack_id, _active_manifest)
        AppState.apply_loaded_pack(_active_pack_id, _active_manifest)
        _update_balloon_position()
        _buddy_say("Only valid pack available: %s" % _active_pack_id)
        _refresh_telemetry()
        return

    var current := str(AppState.settings.get("selectedPackId", "core_pack"))
    var index := ids.find(current)
    if index < 0:
        index = 0
    else:
        index = (index + 1) % ids.size()

    var next_pack := str(ids[index])
    var loaded := ContentLoader.load_with_fallback(next_pack)
    var manifest_variant = loaded.get("manifest", null)
    if typeof(manifest_variant) != TYPE_DICTIONARY:
        _update_balloon_position()
        _buddy_say("Pack load failed: %s" % next_pack)
        return

    _active_pack_id = str(loaded.get("pack_id", next_pack))
    _active_manifest = manifest_variant as Dictionary
    _allowed_actions = ContentLoader.gather_action_ids(_active_manifest)
    _encounters.configure(
        _active_manifest.get("eventRules", []),
        int(AppState.profile.get("personality_seed", 0))
    )
    _load_visual_assets(_active_pack_id, _active_manifest)
    AppState.apply_loaded_pack(_active_pack_id, _active_manifest)
    _update_balloon_position()
    _buddy_say(
        "Active pack: %s (%d available; visual deltas can be subtle)" % [_active_pack_id, ids.size()]
    )
    _refresh_telemetry()


func _on_telemetry_timer_timeout() -> void:
    _refresh_telemetry()


func _refresh_telemetry() -> void:
    telemetry_label.visible = _telemetry_enabled
    if not telemetry_label.visible:
        _refresh_settings_menu()
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
    var prompt_metrics := _manual_verification_report.get_prompt_metrics()
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
        "prompt freq: %s" % str(AppState.settings.get("promptFrequency", "normal")),
        "prompt metrics: s+%d s-%d w+%d w-%d wd%d" % [
            int(prompt_metrics.get("support_shown", 0)),
            int(prompt_metrics.get("support_suppressed", 0)),
            int(prompt_metrics.get("world_shown", 0)),
            int(prompt_metrics.get("world_suppressed", 0)),
            int(prompt_metrics.get("world_deferred", 0)),
        ],
        "chat turns: you=%d buddy=%d" % [_chat_turn_user_count, _chat_turn_buddy_count],
        "chat cmd: ok=%d fail=%d last=%s (%s)" % [
            _chat_cmd_ok_count,
            _chat_cmd_fail_count,
            _chat_last_command_id,
            _chat_last_reason_code,
        ],
        "chat cmd latency: last=%dms avg=%dms" % [
            _chat_cmd_latency_last_ms,
            int(round(float(_chat_cmd_latency_total_ms) / max(1, _chat_cmd_latency_samples))),
        ],
        "settings recent: %s" % _recent_settings_change_summary(3),
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
        "F1 export snapshot  F2 prompt freq  F3 quiet strict  F4 intensity",
        "F5 mode  F6 telemetry",
        "F7 freq (Shift+F7 demo)  F8 monitor",
        "F9 pack  F10 settings  F11 reward  F12 world",
        "Shift+F2 demo support prompt  Shift+F7 demo world prompt",
    ]
    telemetry_label.text = "\n".join(lines)
    _refresh_settings_menu()


func _toggle_settings_menu() -> void:
    _settings_menu_open = not _settings_menu_open
    _layout_settings_window()
    _refresh_settings_menu()


func _toggle_chat_window() -> void:
    _chat_window_open = not _chat_window_open
    _layout_chat_window()
    if _chat_window_open:
        _chat_unread_prompt_count = 0
        _refresh_settings_menu()
    if _chat_window_open and chat_input != null:
        chat_input.grab_focus()


func _layout_settings_window() -> void:
    if settings_window == null:
        return
    if _settings_menu_open:
        var main_screen := DisplayServer.window_get_current_screen()
        var usable := DisplayServer.screen_get_usable_rect(main_screen)
        var max_size := Vector2i(
            maxi(SETTINGS_WINDOW_MIN_SIZE.x, int(usable.size.x * 0.45)),
            maxi(SETTINGS_WINDOW_MIN_SIZE.y, int(usable.size.y * 0.8))
        )
        var target_size := settings_window.size
        target_size.x = clampi(target_size.x, SETTINGS_WINDOW_MIN_SIZE.x, max_size.x)
        target_size.y = clampi(target_size.y, SETTINGS_WINDOW_MIN_SIZE.y, max_size.y)
        settings_window.size = target_size

        var main_pos: Vector2i = DisplayServer.window_get_position()
        var target_pos := main_pos + SETTINGS_WINDOW_OFFSET
        var max_x := usable.position.x + maxi(0, usable.size.x - target_size.x)
        var max_y := usable.position.y + maxi(0, usable.size.y - target_size.y)
        target_pos.x = clampi(target_pos.x, usable.position.x, max_x)
        target_pos.y = clampi(target_pos.y, usable.position.y, max_y)
        settings_window.position = target_pos
        settings_window.show()
        settings_window.grab_focus()
    else:
        settings_window.hide()


func _layout_chat_window() -> void:
    if chat_window == null:
        return
    if _chat_window_open:
        var main_screen := DisplayServer.window_get_current_screen()
        var usable := DisplayServer.screen_get_usable_rect(main_screen)
        var target_size := chat_window.size
        target_size.x = clampi(target_size.x, 320, maxi(320, int(usable.size.x * 0.6)))
        target_size.y = clampi(target_size.y, 220, maxi(220, int(usable.size.y * 0.6)))
        chat_window.size = target_size
        var main_pos: Vector2i = DisplayServer.window_get_position()
        var target_pos := main_pos + Vector2i(72, 72)
        var max_x := usable.position.x + maxi(0, usable.size.x - target_size.x)
        var max_y := usable.position.y + maxi(0, usable.size.y - target_size.y)
        target_pos.x = clampi(target_pos.x, usable.position.x, max_x)
        target_pos.y = clampi(target_pos.y, usable.position.y, max_y)
        chat_window.position = target_pos
        chat_window.show()
        chat_window.grab_focus()
    else:
        chat_window.hide()


func _refresh_settings_menu() -> void:
    if settings_label == null:
        return

    var snapshot := AppState.get_telemetry_snapshot()
    var prompt_metrics := _manual_verification_report.get_prompt_metrics()
    var lock_remaining := maxi(0, _manual_emote_until_unix - int(Time.get_unix_time_from_system()))

    var text := ""
    text += "[center][b][color=#FFD77A]Maple Buddy Menu[/color][/b][/center]\n"
    text += "[center][color=#E7D9B4]Separate movable popout[/color][/center]\n\n"
    text += "[b][color=#FFCF6E]Character[/color][/b]\n"
    text += "[color=#F4E9CF]State:[/color] %s   [color=#F4E9CF]Mood:[/color] %s   [color=#F4E9CF]Growth:[/color] %d\n" % [
        _state, str(snapshot.get("mood", "calm")), int(snapshot.get("growth_stage", 1))
    ]
    text += "[color=#F4E9CF]Bond:[/color] Lv %d   XP %d   [color=#F4E9CF]Trust:[/color] %.2f\n" % [
        int(snapshot.get("bond_level", 1)), int(snapshot.get("bond_xp", 0)), float(snapshot.get("trust_value", 0.2))
    ]
    text += "[color=#F4E9CF]Pack:[/color] %s   [color=#F4E9CF]Mode:[/color] %s\n\n" % [
        str(snapshot.get("active_pack", "core_pack")), str(snapshot.get("home_mode", "overlay"))
    ]
    text += "[b][color=#FFCF6E]System[/color][/b]\n"
    text += "[color=#F4E9CF]Event Freq:[/color] %s   [color=#F4E9CF]Prompt Freq:[/color] %s\n" % [
        str(AppState.settings.get("eventFrequency", "normal")),
        str(AppState.settings.get("promptFrequency", "normal"))
    ]
    text += "[color=#F4E9CF]Floor Adjust (TO):[/color] %s\n" % _format_floor_adjust_text(_desktop_floor_offset_adjust)
    text += "[color=#F4E9CF]Quiet:[/color] %s (%s)\n" % [
        str(AppState.settings.get("quietModeStrictness", "balanced")),
        "on" if AppState.is_quiet_hours_now() else "off"
    ]
    text += "[color=#F4E9CF]Prompts:[/color] s+%d s-%d w+%d w-%d wd%d\n\n" % [
        int(prompt_metrics.get("support_shown", 0)),
        int(prompt_metrics.get("support_suppressed", 0)),
        int(prompt_metrics.get("world_shown", 0)),
        int(prompt_metrics.get("world_suppressed", 0)),
        int(prompt_metrics.get("world_deferred", 0))
    ]
    text += "[b][color=#FFCF6E]Hotkeys[/color][/b]\n"
    text += "[color=#F4E9CF]F2[/color] prompt  [color=#F4E9CF]Shift+F2[/color] demo support\n"
    text += "[color=#F4E9CF]F3[/color] quiet  [color=#F4E9CF]F4[/color] intensity\n"
    text += "[color=#F4E9CF]F5[/color] home  [color=#F4E9CF]F7[/color] events  [color=#F4E9CF]F8[/color] monitor\n"
    text += "[color=#F4E9CF]F9[/color] pack  [color=#F4E9CF]F11[/color] reward  [color=#F4E9CF]F12[/color] world\n\n"
    text += "[b][color=#FFCF6E]Emote Debug[/color][/b]\n"
    text += "[color=#F4E9CF]Lock:[/color] %ds\n" % lock_remaining
    text += "[color=#F4E9CF]1-0:[/color] happy/sad/angry/surprised/love/wink/sleepy/sick/pain/default"
    settings_label.bbcode_enabled = true
    settings_label.text = text

    settings_btn_event_freq.text = "Event Freq (F7): %s" % str(AppState.settings.get("eventFrequency", "normal"))
    settings_btn_prompt_freq.text = "Prompt Freq (F2): %s" % str(AppState.settings.get("promptFrequency", "normal"))
    settings_btn_quiet.text = "Quiet (F3): %s" % str(AppState.settings.get("quietModeStrictness", "balanced"))
    settings_btn_intensity.text = "Intensity (F4): %s" % str(AppState.settings.get("interactionIntensity", "balanced"))
    settings_btn_mode.text = "Mode (F5): %s" % str(snapshot.get("home_mode", "overlay"))
    settings_btn_pack.text = "Cycle Pack (F9): %s" % str(snapshot.get("active_pack", "core_pack"))
    settings_btn_demo_support.text = "Demo Support (Shift+F2)"
    settings_btn_demo_world.text = "Demo World (Shift+F7)"
    settings_btn_reward.text = "Open Reward Box (F11)"
    settings_btn_telemetry.text = "Telemetry (F6): %s" % ("on" if _telemetry_enabled else "off")
    settings_btn_restart.text = "Restart Runtime"
    settings_btn_quit.text = "Quit Runtime"
    var unread_suffix := ""
    if _chat_unread_prompt_count > 0:
        unread_suffix = " (%d new)" % _chat_unread_prompt_count
    settings_btn_chat.text = "Chat: %s%s" % [("Open" if _chat_window_open else "Closed"), unread_suffix]
    if settings_floor_slider != null:
        settings_floor_slider.set_value_no_signal(_desktop_floor_offset_adjust)
    if settings_floor_value != null:
        settings_floor_value.text = _format_floor_adjust_text(_desktop_floor_offset_adjust)


func _read_floor_offset_adjust_setting() -> float:
    var raw = AppState.settings.get("desktopFloorOffsetAdjust", 0.0)
    return clampf(float(raw), -20.0, 20.0)


func _set_floor_offset_adjust(raw_value: float) -> void:
    var next_value := clampf(roundf(raw_value), -20.0, 20.0)
    if is_equal_approx(next_value, _desktop_floor_offset_adjust):
        return
    _desktop_floor_offset_adjust = next_value
    AppState.settings["desktopFloorOffsetAdjust"] = _desktop_floor_offset_adjust
    AppState.flush()
    _draw_center = _floor_point()
    _update_balloon_position()
    queue_redraw()
    if settings_floor_value != null:
        settings_floor_value.text = _format_floor_adjust_text(_desktop_floor_offset_adjust)
    _refresh_telemetry()


func _format_floor_adjust_text(value: float) -> String:
    var rounded := int(roundf(value))
    var sign := "+" if rounded >= 0 else ""
    return "%s%d px" % [sign, rounded]


func _buddy_say(line: String, source_kind: String = "") -> void:
    if line == "":
        return
    line = _normalize_buddy_reply(line)
    _chat_turn_buddy_count += 1
    if not _chat_window_open and (source_kind == "support" or source_kind == "world"):
        _chat_unread_prompt_count += 1
        _refresh_settings_menu()
    _update_balloon_position()
    chat_balloon.show_text(line)
    _append_chat_line("Buddy", line, "#F4E9CF")


func _append_chat_line(speaker: String, text: String, color_hex: String) -> void:
    if chat_log == null:
        return
    var now_unix := int(Time.get_unix_time_from_system())
    if _chat_last_line_unix > 0 and now_unix - _chat_last_line_unix >= CHAT_SEPARATOR_IDLE_SECONDS:
        chat_log.append_text("[color=#6A7D8F]---------- session pause ----------[/color]\n")
    _chat_last_line_unix = now_unix
    var safe_speaker := speaker.replace("[", "").replace("]", "")
    var safe_text := text.replace("[", "\\[").replace("]", "\\]")
    var row := "[color=%s][b]%s:[/b][/color] %s\n" % [color_hex, safe_speaker, safe_text]
    chat_log.append_text(row)
    var line_count := chat_log.get_line_count()
    if line_count > CHAT_TRANSCRIPT_MAX_LINES:
        var full_text := chat_log.text
        var parts := full_text.split("\n")
        var keep_from: int = maxi(0, parts.size() - CHAT_TRANSCRIPT_MAX_LINES)
        var trimmed := "\n".join(parts.slice(keep_from, parts.size()))
        chat_log.text = trimmed
    chat_log.scroll_to_line(chat_log.get_line_count())


func _send_chat_input() -> void:
    if chat_input == null:
        return
    var raw := chat_input.text.strip_edges()
    if raw == "":
        return
    chat_input.text = ""
    _chat_turn_user_count += 1
    _append_chat_line("You", raw, "#9FD9FF")
    _capture_chat_memory(raw)
    AppState.record_interaction("chat_reply")
    _productivity.note_user_activity(int(Time.get_unix_time_from_system()))

    var started_ms := Time.get_ticks_msec()
    var resolved := _chat_router.resolve(raw)
    var outcome := _execute_resolved_chat(raw, resolved)
    outcome["elapsed_ms"] = Time.get_ticks_msec() - started_ms
    _record_chat_command_outcome(outcome)
    var reply := str(outcome.get("message", ""))
    if reply != "":
        _buddy_say(reply)
    _refresh_telemetry()


func _generate_chat_reply(user_text: String) -> String:
    var msg := user_text.to_lower()
    var snap := AppState.get_telemetry_snapshot()
    var mood := str(snap.get("mood", "calm"))
    var bond_level := int(snap.get("bond_level", 1))
    var world := AppState.get_world_snapshot()
    var tone := _tone_prefix(mood, bond_level)

    if msg.find("hello") >= 0 or msg.find("hi") >= 0 or msg.find("hey") >= 0:
        return "%sHey. I am here with you." % tone
    if msg.find("help") >= 0:
        return "%sI can do quick things: rewards (F11), world prompts (F12), and mode toggle (F5)." % tone
    if msg.find("quest") >= 0 or msg.find("world") >= 0:
        var pending_q := str(world.get("pending_quest_id", ""))
        var pending_e := str(world.get("pending_encounter_id", ""))
        if pending_q != "" or pending_e != "":
            return "%sWe have something pending. Press F12 and we can resolve it." % tone
        return "%sNo pending quest right now. I can ping one when events roll." % tone
    if msg.find("reward") >= 0 or msg.find("box") >= 0:
        return "%sOpen a reward box with F11 and I will call out what we get." % tone
    if msg.find("sleep") >= 0 or msg.find("tired") >= 0:
        return "%sIf you want quiet mode, right-click me to sleep and I will keep calm." % tone
    if msg.find("mode") >= 0 or msg.find("home") >= 0 or msg.find("overlay") >= 0:
        var home_mode := str(world.get("home_mode", "overlay"))
        return "%sCurrent mode is %s. Press F5 to switch." % [tone, home_mode]
    if msg.find("thanks") >= 0 or msg.find("thank you") >= 0:
        return "%sAlways. Bond level is %d and climbing." % [tone, bond_level]
    if _should_ask_follow_up(msg):
        _chat_last_followup_turn = _chat_turn_user_count
        return "%sCan you tell me a bit more so I can help better?" % tone

    if mood == "sleepy":
        return "%sI am a bit sleepy, but I am still listening." % tone
    if mood == "curious":
        return "%sTell me more. I am curious." % tone
    if mood == "happy":
        return "%sNice. I like chatting with you." % tone
    return "%sGot it. Want to do rewards, quests, or just hang out?" % tone


func _execute_resolved_chat(raw_text: String, resolved: Dictionary) -> Dictionary:
    var ok := bool(resolved.get("ok", false))
    var kind := str(resolved.get("kind", "unknown"))
    var action_id := str(resolved.get("action_id", ""))
    var params_variant = resolved.get("params", {})
    var params: Dictionary = params_variant if typeof(params_variant) == TYPE_DICTIONARY else {}
    var reason := str(resolved.get("reason_code", "unknown"))
    var confidence := float(resolved.get("confidence", 0.0))

    if kind == "command":
        if not ok:
            return _action_result(
                false,
                "command.%s" % action_id,
                "I could not run that command (%s). Use /help." % reason,
                reason
            )
        if confidence < 0.60:
            return _action_result(false, "command.%s" % action_id, "I am not confident enough to run that command.", "low_confidence")
        var throttle := _throttle_command(action_id)
        if not bool(throttle.get("ok", false)):
            return throttle
        return _execute_chat_command(action_id, params)

    if kind == "intent" and ok:
        return _action_result(true, "intent.%s" % action_id, _generate_chat_reply(raw_text), "ok")

    return _action_result(false, "intent.unknown", "I did not catch that. Try /help.", "unknown_intent")


func _execute_chat_command(command: String, params: Dictionary) -> Dictionary:
    if command == "help":
        return _action_result(
            true,
            "command.help",
            "Commands: /help /status /pending /mode home|overlay /reward /world engage|skip|complete /quiet lenient|balanced|strict /freq low|normal|high /chat close|clear [confirm]|text m|l /memory /remember <note> /forget <id> [confirm] /cadence /debug chat /settings-check /preset cozy|balanced|deep /settings reset [confirm]|undo",
            "ok"
        )
    if command == "status":
        var snap := AppState.get_telemetry_snapshot()
        var world := AppState.get_world_snapshot()
        var msg := "Status: Lv %d XP %d Mood %s Mode %s Crystals %d" % [
            int(snap.get("bond_level", 1)),
            int(snap.get("bond_xp", 0)),
            str(snap.get("mood", "calm")),
            str(world.get("home_mode", "overlay")),
            int(snap.get("crystals", 0)),
        ]
        var recent := _recent_settings_change_summary(5)
        if recent != "":
            msg += " | settings: %s" % recent
        return _action_result(true, "command.status", msg, "ok")
    if command == "pending":
        var world_pending := AppState.get_world_snapshot()
        var q := str(world_pending.get("pending_quest_id", ""))
        var e := str(world_pending.get("pending_encounter_id", ""))
        if q == "" and e == "":
            return _action_result(true, "command.pending", "No pending quest or encounter.", "ok")
        return _action_result(true, "command.pending", "Pending: quest=%s encounter=%s" % [q, e], "ok")
    if command == "mode":
        var mode := str(params.get("mode", "overlay"))
        _set_home_mode_explicit(mode)
        return _action_result(true, "command.mode", "Mode set to %s." % mode, "ok")
    if command == "reward":
        _open_debug_reward_box()
        return _action_result(true, "command.reward", "", "ok")
    if command == "world":
        var decision := str(params.get("decision", "complete"))
        if decision == "skip":
            _resolve_world_prompt(false)
        else:
            _resolve_world_prompt(true)
        return _action_result(true, "command.world", "", "ok")
    if command == "quiet":
        var level := str(params.get("level", "balanced"))
        _set_setting_with_audit("quietModeStrictness", level, "command")
        AppState.flush()
        _emit_setting_feedback("quietModeStrictness", level)
        return _action_result(true, "command.quiet", "Quiet strictness set to %s." % level, "ok")
    if command == "freq":
        var value := str(params.get("value", "normal"))
        _set_setting_with_audit("promptFrequency", value, "command")
        _set_setting_with_audit("eventFrequency", value, "command")
        AppState.flush()
        _emit_setting_feedback("freq", value)
        return _action_result(true, "command.freq", "Prompt/Event frequency set to %s." % value, "ok")
    if command == "chat":
        var action := str(params.get("action", ""))
        if action == "close":
            _chat_window_open = false
            _layout_chat_window()
            return _action_result(true, "command.chat", "Chat window closed.", "ok")
        if action == "clear":
            var confirm := bool(params.get("confirm", false))
            if not confirm:
                return _action_result(false, "command.chat", "Confirm with /chat clear confirm", "confirm_required")
            if chat_log != null:
                chat_log.clear()
            return _action_result(true, "command.chat", "Chat transcript cleared.", "ok")
        if action == "text":
            var size := str(params.get("size", "m"))
            _set_setting_with_audit("chatTextSize", size, "command")
            AppState.flush()
            _apply_chat_text_size()
            return _action_result(true, "command.chat", "Chat text size set to %s." % size.to_upper(), "ok")
        return _action_result(false, "command.chat", "Unknown chat action.", "invalid_arg")
    if command == "memory":
        return _action_result(true, "command.memory", _build_memory_summary(), "ok")
    if command == "remember":
        var note := str(params.get("note", "")).strip_edges()
        if note == "":
            return _action_result(false, "command.remember", "Missing note text. Use /remember <note>", "missing_arg")
        return _remember_note(note)
    if command == "forget":
        var note_id := int(params.get("id", -1))
        var confirm := bool(params.get("confirm", false))
        return _forget_note(note_id, confirm)
    if command == "cadence":
        return _action_result(true, "command.cadence", _build_cadence_summary(), "ok")
    if command == "debug":
        var area := str(params.get("area", ""))
        if area == "chat":
            return _action_result(true, "command.debug", _build_chat_debug_summary(), "ok")
        return _action_result(false, "command.debug", "Unknown debug area.", "invalid_arg")
    if command == "settings-check":
        return _action_result(true, "command.settings-check", _run_settings_check(), "ok")
    if command == "preset":
        var preset := str(params.get("preset", "balanced"))
        return _apply_settings_preset(preset)
    if command == "settings":
        var settings_action := str(params.get("action", ""))
        if settings_action == "reset":
            var confirm := bool(params.get("confirm", false))
            return _reset_settings_with_undo(confirm)
        if settings_action == "undo":
            return _undo_settings_reset()
        return _action_result(false, "command.settings", "Unknown settings action.", "invalid_arg")

    return _action_result(false, "command.%s" % command, "Unsupported command.", "unsupported_command")


func _tone_prefix(mood: String, bond_level: int) -> String:
    var bond_band := 0
    if bond_level >= 12:
        bond_band = 2
    elif bond_level >= 6:
        bond_band = 1
    if mood == "sleepy":
        return ["", "Hey... ", "Hey friend... "][bond_band]
    if mood == "happy":
        return ["", "Nice! ", "Nice! I am glad you are here. "][bond_band]
    if mood == "curious":
        return ["", "Hmm. ", "Hmm, tell me more. "][bond_band]
    if mood == "frustrated":
        return ["", "Okay. ", "Okay, we can handle this. "][bond_band]
    if mood == "calm":
        return ["", "Alright. ", "Alright, teammate. "][bond_band]
    return ""


func _should_ask_follow_up(msg: String) -> bool:
    var compact := msg.strip_edges()
    if compact == "":
        return false
    if compact.begins_with("/"):
        return false
    if _chat_turn_user_count - _chat_last_followup_turn < CHAT_FOLLOW_UP_MIN_TURNS:
        return false
    var noisy_keywords := [
        "reward",
        "world",
        "quest",
        "mode",
        "help",
        "quiet",
        "freq",
        "sleep",
        "tired",
    ]
    for key in noisy_keywords:
        if compact.find(key) >= 0:
            return false
    var words := compact.split(" ", false)
    return words.size() <= 3


func _normalize_buddy_reply(line: String) -> String:
    var normalized := line.strip_edges().to_lower()
    if normalized == "":
        return line
    if _chat_recent_buddy_norm_lines.has(normalized):
        line = _rewrite_repetitive_reply(line)
        normalized = line.strip_edges().to_lower()
    _chat_recent_buddy_norm_lines.append(normalized)
    if _chat_recent_buddy_norm_lines.size() > CHAT_RECENT_REPLY_MAX:
        _chat_recent_buddy_norm_lines.remove_at(0)
    return line


func _rewrite_repetitive_reply(line: String) -> String:
    if line.find("?") >= 0:
        return "Let me rephrase: %s" % line
    if line.find("Press F") >= 0:
        return "%s (shortcut reminder)" % line
    return "%s Let us keep going." % line


func _capture_chat_memory(raw_text: String) -> void:
    var tags := _extract_memory_tags(raw_text)
    for tag in tags:
        var count := int(_chat_memory_tag_counts.get(tag, 0))
        _chat_memory_tag_counts[tag] = count + 1
    _chat_memory_turn_tags.append(
        {
            "turn": _chat_turn_user_count,
            "text": raw_text.strip_edges(),
            "tags": tags,
            "ts": int(Time.get_unix_time_from_system()),
        }
    )
    if _chat_memory_turn_tags.size() > 40:
        _chat_memory_turn_tags.remove_at(0)


func _extract_memory_tags(raw_text: String) -> Array:
    var msg := raw_text.to_lower()
    var tags: Array = []
    var rules := {
        "goal": ["plan", "goal", "next", "later", "todo"],
        "mood": ["tired", "stressed", "happy", "sad", "upset", "excited"],
        "task": ["work", "task", "finish", "start", "focus", "meeting"],
        "reward": ["reward", "box", "crystal", "item", "loot"],
        "world": ["quest", "encounter", "world", "village", "npc"],
        "support": ["help", "remind", "check", "support"],
    }
    for tag_key in rules.keys():
        var keys: Array = rules[tag_key]
        for key_variant in keys:
            var key := str(key_variant)
            if msg.find(key) >= 0:
                tags.append(tag_key)
                break
    return tags


func _build_memory_summary() -> String:
    var tags_summary := []
    for key in _chat_memory_tag_counts.keys():
        var value := int(_chat_memory_tag_counts.get(key, 0))
        if value > 0:
            tags_summary.append("%s:%d" % [key, value])
    if tags_summary.is_empty():
        tags_summary.append("none")
    var notes_summary := []
    for note_variant in _chat_memory_notes:
        var note: Dictionary = note_variant
        notes_summary.append("#%d %s" % [int(note.get("id", 0)), str(note.get("text", ""))])
    if notes_summary.is_empty():
        notes_summary.append("none")
    return "Memory tags [%s] | notes [%s]" % [", ".join(tags_summary), " ; ".join(notes_summary)]


func _remember_note(note_text: String) -> Dictionary:
    if _chat_memory_notes.size() >= CHAT_MEMORY_MAX_NOTES:
        return _action_result(false, "command.remember", "Memory notes are full (10). Forget one first.", "memory_full")
    var note := {
        "id": _chat_memory_next_note_id,
        "text": note_text,
        "ts": int(Time.get_unix_time_from_system()),
    }
    _chat_memory_notes.append(note)
    _chat_memory_next_note_id += 1
    return _action_result(true, "command.remember", "Saved note #%d." % int(note.get("id", 0)), "ok")


func _forget_note(note_id: int, confirm: bool) -> Dictionary:
    if note_id <= 0:
        return _action_result(false, "command.forget", "Invalid note id.", "invalid_arg")
    if not confirm:
        _chat_memory_pending_forget_id = note_id
        _chat_memory_pending_forget_until = int(Time.get_unix_time_from_system()) + 10
        return _action_result(
            false,
            "command.forget",
            "Confirm with /forget %d confirm (within 10s)." % note_id,
            "confirm_required"
        )
    var now_unix := int(Time.get_unix_time_from_system())
    if _chat_memory_pending_forget_id != note_id or now_unix > _chat_memory_pending_forget_until:
        return _action_result(false, "command.forget", "Forget confirmation expired. Run /forget <id> again.", "confirm_expired")
    for i in range(_chat_memory_notes.size()):
        var note: Dictionary = _chat_memory_notes[i]
        if int(note.get("id", -1)) == note_id:
            _chat_memory_notes.remove_at(i)
            _chat_memory_pending_forget_id = -1
            _chat_memory_pending_forget_until = 0
            return _action_result(true, "command.forget", "Forgot note #%d." % note_id, "ok")
    return _action_result(false, "command.forget", "Note not found.", "missing_note")


func _apply_chat_text_size() -> void:
    if chat_log == null:
        return
    var mode := str(AppState.settings.get("chatTextSize", "m")).to_lower()
    var size := CHAT_FONT_SIZE_L if mode == "l" else CHAT_FONT_SIZE_M
    chat_log.add_theme_font_size_override("normal_font_size", size)
    if chat_input != null:
        chat_input.add_theme_font_size_override("font_size", size)
    if chat_send != null:
        chat_send.add_theme_font_size_override("font_size", size)


func _build_cadence_summary() -> String:
    var now_unix := int(Time.get_unix_time_from_system())
    var quiet_mode := AppState.is_quiet_hours_now()
    var info_variant = _prompt_cadence.debug_snapshot(now_unix, AppState.settings, quiet_mode)
    if typeof(info_variant) != TYPE_DICTIONARY:
        return "Cadence diagnostics unavailable."
    var info: Dictionary = info_variant
    var pieces := []
    for source in ["support", "world", "chat"]:
        var source_variant = info.get(source, {})
        if typeof(source_variant) != TYPE_DICTIONARY:
            continue
        var source_data: Dictionary = source_variant
        pieces.append(
            "%s c=%d/%d min=%ss" % [
                source,
                int(source_data.get("recent_count", 0)),
                int(source_data.get("burst_cap", 0)),
                int(source_data.get("min_interval_s", 0)),
            ]
        )
    return "Cadence: %s" % " | ".join(pieces)


func _build_chat_debug_summary() -> String:
    var reason_pairs := []
    for reason_key in _chat_cmd_reason_counts.keys():
        reason_pairs.append("%s=%d" % [str(reason_key), int(_chat_cmd_reason_counts.get(reason_key, 0))])
    reason_pairs.sort()
    var reasons := ", ".join(reason_pairs)
    if reasons == "":
        reasons = "none"
    var avg_latency := int(round(float(_chat_cmd_latency_total_ms) / max(1, _chat_cmd_latency_samples)))
    return "Chat debug: turns(y/b)=%d/%d cmd(ok/fail)=%d/%d latency(last/avg)=%d/%d reasons[%s]" % [
        _chat_turn_user_count,
        _chat_turn_buddy_count,
        _chat_cmd_ok_count,
        _chat_cmd_fail_count,
        _chat_cmd_latency_last_ms,
        avg_latency,
        reasons,
    ]


func _run_settings_check() -> String:
    var issues := []
    var freq := str(AppState.settings.get("promptFrequency", "normal"))
    var event_freq := str(AppState.settings.get("eventFrequency", "normal"))
    var quiet := str(AppState.settings.get("quietModeStrictness", "balanced"))
    var intensity := str(AppState.settings.get("interactionIntensity", "balanced"))
    var chat_text_size := str(AppState.settings.get("chatTextSize", "m")).to_lower()
    if freq not in ["low", "normal", "high"]:
        issues.append("promptFrequency invalid")
    if event_freq not in ["low", "normal", "high"]:
        issues.append("eventFrequency invalid")
    if quiet not in ["lenient", "balanced", "strict"]:
        issues.append("quietModeStrictness invalid")
    if intensity not in ["cozy", "balanced", "deep"]:
        issues.append("interactionIntensity invalid")
    if chat_text_size not in ["m", "l"]:
        issues.append("chatTextSize invalid")
    if issues.is_empty():
        return "Settings check passed."
    return "Settings check warnings: %s" % ", ".join(issues)


func _apply_settings_preset(preset: String) -> Dictionary:
    var chosen := preset.to_lower()
    var preset_values := {}
    if chosen == "cozy":
        preset_values = {
            "eventFrequency": "low",
            "promptFrequency": "low",
            "interactionIntensity": "cozy",
            "quietModeStrictness": "strict",
        }
    elif chosen == "deep":
        preset_values = {
            "eventFrequency": "high",
            "promptFrequency": "high",
            "interactionIntensity": "deep",
            "quietModeStrictness": "lenient",
        }
    else:
        chosen = "balanced"
        preset_values = {
            "eventFrequency": "normal",
            "promptFrequency": "normal",
            "interactionIntensity": "balanced",
            "quietModeStrictness": "balanced",
        }

    _capture_settings_undo_snapshot()
    for key in preset_values.keys():
        _set_setting_with_audit(key, preset_values[key], "preset:%s" % chosen)
    AppState.flush()
    _refresh_settings_menu()
    _refresh_telemetry()
    return _action_result(
        true,
        "command.preset",
        "Preset applied: %s (use /settings undo within 10s)." % chosen,
        "ok"
    )


func _reset_settings_with_undo(confirm: bool) -> Dictionary:
    if not confirm:
        return _action_result(false, "command.settings", "Confirm with /settings reset confirm", "confirm_required")
    _capture_settings_undo_snapshot()
    _set_setting_with_audit("eventFrequency", "normal", "settings_reset")
    _set_setting_with_audit("promptFrequency", "normal", "settings_reset")
    _set_setting_with_audit("interactionIntensity", "balanced", "settings_reset")
    _set_setting_with_audit("quietModeStrictness", "balanced", "settings_reset")
    _set_setting_with_audit("chatTextSize", "m", "settings_reset")
    AppState.flush()
    _apply_chat_text_size()
    _refresh_settings_menu()
    _refresh_telemetry()
    return _action_result(
        true,
        "command.settings",
        "Settings reset to defaults (use /settings undo within 10s).",
        "ok"
    )


func _undo_settings_reset() -> Dictionary:
    var now_unix := int(Time.get_unix_time_from_system())
    if _settings_undo_snapshot.is_empty():
        return _action_result(false, "command.settings", "No settings undo snapshot available.", "missing_undo")
    if now_unix > _settings_undo_until_unix:
        _settings_undo_snapshot.clear()
        _settings_undo_until_unix = 0
        return _action_result(false, "command.settings", "Settings undo window expired.", "undo_expired")
    for key in _settings_undo_snapshot.keys():
        _set_setting_with_audit(key, _settings_undo_snapshot[key], "settings_undo")
    AppState.flush()
    _apply_chat_text_size()
    _refresh_settings_menu()
    _refresh_telemetry()
    _settings_undo_snapshot.clear()
    _settings_undo_until_unix = 0
    return _action_result(true, "command.settings", "Settings restored from undo snapshot.", "ok")


func _capture_settings_undo_snapshot() -> void:
    _settings_undo_snapshot = {
        "eventFrequency": str(AppState.settings.get("eventFrequency", "normal")),
        "promptFrequency": str(AppState.settings.get("promptFrequency", "normal")),
        "interactionIntensity": str(AppState.settings.get("interactionIntensity", "balanced")),
        "quietModeStrictness": str(AppState.settings.get("quietModeStrictness", "balanced")),
        "chatTextSize": str(AppState.settings.get("chatTextSize", "m")),
    }
    _settings_undo_until_unix = int(Time.get_unix_time_from_system()) + 10


func _set_setting_with_audit(key: String, value: Variant, source: String) -> bool:
    var old_value = AppState.settings.get(key, null)
    if old_value == value:
        return false
    AppState.settings[key] = value
    _record_settings_change(key, old_value, value, source)
    return true


func _record_settings_change(key: String, old_value: Variant, new_value: Variant, source: String) -> void:
    _settings_change_history.append(
        {
            "ts": int(Time.get_unix_time_from_system()),
            "key": key,
            "old": str(old_value),
            "new": str(new_value),
            "source": source,
        }
    )
    if _settings_change_history.size() > SETTINGS_CHANGE_HISTORY_MAX:
        _settings_change_history.remove_at(0)


func _recent_settings_change_summary(max_items: int) -> String:
    if _settings_change_history.is_empty():
        return ""
    var start := maxi(0, _settings_change_history.size() - max_items)
    var entries: Array = _settings_change_history.slice(start, _settings_change_history.size())
    var parts := []
    for entry_variant in entries:
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        parts.append("%s=%s" % [str(entry.get("key", "")), str(entry.get("new", ""))])
    return ", ".join(parts)


func _action_result(ok: bool, action_id: String, message: String, reason_code: String) -> Dictionary:
    return {
        "ok": ok,
        "action_id": action_id,
        "message": message,
        "reason_code": reason_code,
    }


func _record_chat_command_outcome(outcome: Dictionary) -> void:
    var action_id := str(outcome.get("action_id", ""))
    var reason_code := str(outcome.get("reason_code", "unknown"))
    var ok := bool(outcome.get("ok", false))
    _chat_last_command_id = action_id
    _chat_last_reason_code = reason_code
    if ok:
        _chat_cmd_ok_count += 1
    else:
        _chat_cmd_fail_count += 1
    var count := int(_chat_cmd_reason_counts.get(reason_code, 0))
    _chat_cmd_reason_counts[reason_code] = count + 1
    var elapsed_ms := int(outcome.get("elapsed_ms", 0))
    if elapsed_ms > 0:
        _chat_cmd_latency_last_ms = elapsed_ms
        _chat_cmd_latency_total_ms += elapsed_ms
        _chat_cmd_latency_samples += 1


func _throttle_command(action_id: String) -> Dictionary:
    var now_ms := Time.get_ticks_msec()
    var key := "command:%s" % action_id
    var last_ms := int(_chat_cmd_last_key_by_action.get(key, 0))
    if now_ms - last_ms < 300:
        return _action_result(false, "command.%s" % action_id, "That was too fast. Try again.", "throttled")
    _chat_cmd_last_key_by_action[key] = now_ms
    return _action_result(true, "command.%s" % action_id, "", "ok")


func _set_home_mode_explicit(mode: String) -> void:
    var next_mode := "home" if mode == "home" else "overlay"
    AppState.set_home_mode(next_mode)
    if next_mode == "home":
        _state = _select_home_mode_action(int(Time.get_unix_time_from_system()))
    else:
        _state = "idle"
    _set_emote_from_state(_state)
    _set_visual_for_state(_state, true)
    _update_balloon_position()
    _refresh_telemetry()


func _emit_setting_feedback(key: String, value: String) -> void:
    _append_chat_line("System", "Applied %s=%s" % [key, value], "#B8F8C6")


func _restart_runtime() -> void:
    call_deferred("_restart_runtime_deferred")


func _restart_runtime_deferred() -> void:
    AppState.flush()
    if settings_window != null:
        settings_window.hide()
    _settings_menu_open = false
    var relaunched := false
    if not OS.has_feature("editor"):
        var relaunch_err := OS.create_instance(OS.get_cmdline_user_args())
        relaunched = relaunch_err == OK
    if relaunched:
        get_tree().quit()
    else:
        get_tree().reload_current_scene()


func _quit_runtime() -> void:
    AppState.flush()
    get_tree().quit()


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
    _sit_chair_texture = null
    _sit_chair_origin_px = Vector2.ZERO

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
    _load_sit_chair_assets(pack_id)
    _ground_enabled = false
    _ground_texture = null
    _set_emote_from_state(_state)
    _set_visual_for_state(_state, true)
    _update_mouse_region()


func _draw_sit_chair(center: Vector2) -> void:
    if _state != "sit":
        return
    if _sit_chair_texture == null:
        return
    var tex_size := _sit_chair_texture.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return
    var scale := maxf(0.2, _sprite_scale)
    var draw_size := tex_size * scale
    var top_left := center - (_sit_chair_origin_px * scale)
    draw_texture_rect(_sit_chair_texture, Rect2(top_left, draw_size), false)


func _load_sit_chair_assets(pack_id: String) -> void:
    _sit_chair_texture = _resolve_texture(SIT_CHAIR_FRAME_PATH, pack_id)
    var origin := _load_sit_chair_origin(pack_id)
    if _sit_chair_texture == null and pack_id != "core_pack":
        _sit_chair_texture = _resolve_texture(SIT_CHAIR_FRAME_PATH, "core_pack")
        origin = _load_sit_chair_origin("core_pack")
    if _sit_chair_texture == null:
        return
    var tex_size := _sit_chair_texture.get_size()
    if tex_size.x <= 0.0 or tex_size.y <= 0.0:
        return
    if origin == Vector2.ZERO:
        origin = Vector2(tex_size.x * 0.5, tex_size.y)
    _sit_chair_origin_px = origin


func _load_sit_chair_origin(pack_id: String) -> Vector2:
    var raw := _resolve_text(SIT_CHAIR_EFFECT_PATH, pack_id)
    if raw == "":
        return Vector2.ZERO
    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        return Vector2.ZERO
    var effect: Dictionary = parsed
    var frames_variant = effect.get("frames", [])
    if typeof(frames_variant) != TYPE_ARRAY or (frames_variant as Array).is_empty():
        return Vector2.ZERO
    var first_variant = (frames_variant as Array)[0]
    if typeof(first_variant) != TYPE_DICTIONARY:
        return Vector2.ZERO
    var first: Dictionary = first_variant
    var origin_variant = first.get("origin_px", [])
    if typeof(origin_variant) != TYPE_ARRAY or (origin_variant as Array).size() < 2:
        return Vector2.ZERO
    var values: Array = origin_variant
    return Vector2(float(values[0]), float(values[1]))


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
    var effective_pivot_y := tex_size.y
    if use_pivot:
        var pivot_to_use := _current_frame_pivot_px
        if pivot_to_use.y > tex_size.y:
            var overflow := pivot_to_use.y - tex_size.y
            var overflow_blend := _pivot_overflow_blend_for_action(_current_visual_action)
            pivot_to_use.y = tex_size.y + (overflow * overflow_blend)
        var extra_offset := float(ACTION_EXTRA_FLOOR_OFFSET.get(_current_visual_action, 0.0))
        effective_pivot_y = clampf(
            pivot_to_use.y - CHARACTER_FLOOR_OFFSET_PX - extra_offset,
            0.0,
            tex_size.y
        )
        var effective_pivot := Vector2(pivot_to_use.x, effective_pivot_y)
        top_left = center - (effective_pivot * scale)
        # Keep floor contact exact across state/animation changes to prevent
        # cumulative visible drift on the desktop overlay.
        var contact_y := top_left.y + (effective_pivot_y * scale)
        top_left.y += center.y - contact_y
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
    var now_unix := int(Time.get_unix_time_from_system())
    if _bond_phrase_active:
        return
    if now_unix - _last_idle_phrase_unix < 18:
        return
    var tier := AppState.get_bond_tier()
    var phrases: Variant = tier.get("idle_phrases", null)
    if typeof(phrases) != TYPE_ARRAY or (phrases as Array).is_empty():
        return
    var phrase := str((phrases as Array)[randi() % (phrases as Array).size()])
    if phrase == "" or phrase == "...":
        return
    _bond_phrase_active = true
    _last_idle_phrase_unix = now_unix
    _update_balloon_position()
    _buddy_say(phrase)
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
    _buddy_say(summary)
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
    _buddy_say(hint)
    await get_tree().create_timer(4.0).timeout
    chat_balloon.hide_bubble()


func _open_debug_reward_box() -> void:
    var box_ids := AppState.get_reward_box_ids()
    if box_ids.is_empty():
        _update_balloon_position()
        _buddy_say("No reward boxes configured.")
        return
    var preferred := "cozy_box" if box_ids.has("cozy_box") else str(box_ids[0])
    var result := AppState.open_reward_box(preferred)
    _update_balloon_position()
    if bool(result.get("ok", false)):
        var item_name := str(result.get("item_name", "item"))
        var item_rarity := str(result.get("item_rarity", "common"))
        if bool(result.get("duplicate", false)):
            var recycle := int(result.get("recycle_crystals", 0))
            _buddy_say(
                "Opened %s: %s [%s] (duplicate +%d crystals)"
                % [preferred, item_name, item_rarity, recycle]
            )
        else:
            _buddy_say("Opened %s: %s [%s]" % [preferred, item_name, item_rarity])
    else:
        var reason := str(result.get("reason", "unavailable"))
        _buddy_say("Could not open %s (%s)" % [preferred, reason])


func _show_world_prompt(prompt: Dictionary) -> bool:
    var prompt_type := str(prompt.get("type", ""))
    var npc_name := str(prompt.get("npcName", "Villager"))
    var text := str(prompt.get("text", ""))
    if text == "":
        return false
    var line := ""
    if prompt_type == "encounter":
        line = "%s: %s (F12 engage / Shift+F12 skip)" % [npc_name, text]
    else:
        line = "%s: %s (F12 complete)" % [npc_name, text]
    return _show_auto_prompt(line, "world")


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
            _buddy_say("%s encounter %s: %s" % [npc, action_word, reward_text])
        else:
            _buddy_say("No encounter to resolve.")
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
            _buddy_say("%s quest complete: %s" % [npc_name, reward_line])
        else:
            _buddy_say("No quest to complete.")
        _refresh_telemetry()
        return

    _buddy_say("No pending world prompt.")


func _cycle_home_mode() -> void:
    var snapshot := AppState.get_world_snapshot()
    var current_mode := str(snapshot.get("home_mode", "overlay"))
    var next_mode := "home" if current_mode != "home" else "overlay"
    AppState.set_home_mode(next_mode)
    if next_mode == "home":
        _state = _select_home_mode_action(int(Time.get_unix_time_from_system()))
    else:
        _state = "idle"
    _set_emote_from_state(_state)
    _set_visual_for_state(_state, true)
    _update_balloon_position()
    var home_name := str(snapshot.get("home_scene_id", "cozy_starter_room"))
    if next_mode == "home":
        var wall_decor := str(snapshot.get("home_wall_decor", ""))
        var suffix := ""
        if wall_decor != "":
            suffix = " wall decor: %s" % wall_decor
        _buddy_say("Home mode active (%s)%s" % [home_name, suffix])
    else:
        _buddy_say("Overlay mode active.")
    _refresh_telemetry()


func _select_home_mode_action(now_unix: int) -> String:
    var dt := Time.get_datetime_dict_from_system()
    var hour := int(dt.get("hour", 12))
    if (hour < 6 or hour >= 22) and _allowed_actions.has("sleep"):
        return "sleep"
    if _allowed_actions.has("sit") and int(now_unix / 12) % 2 == 0:
        return "sit"
    if _allowed_actions.has("happy") and int(now_unix / 18) % 3 == 0:
        return "happy"
    if _allowed_actions.has("idle"):
        return "idle"
    return "default"


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
    _show_auto_prompt(line, "support")


func _show_progress_feedback(before: Dictionary, after: Dictionary) -> void:
    if typeof(before) != TYPE_DICTIONARY or typeof(after) != TYPE_DICTIONARY:
        return
    var before_xp := int(before.get("bond_xp", 0))
    var after_xp := int(after.get("bond_xp", 0))
    var before_level := int(before.get("bond_level", 1))
    var after_level := int(after.get("bond_level", 1))
    var before_unlocks := int(before.get("unlock_count", 0))
    var after_unlocks := int(after.get("unlock_count", 0))
    var msg := "Bond XP: %d -> %d (Lv %d)" % [before_xp, after_xp, after_level]
    if after_level > before_level:
        msg += " level up!"
    if after_unlocks > before_unlocks:
        msg += " unlock +%d" % (after_unlocks - before_unlocks)
    _update_balloon_position()
    _buddy_say(msg)


func _show_auto_prompt(line: String, source_kind: String) -> bool:
    if line == "":
        return false
    var now_unix := int(Time.get_unix_time_from_system())
    var quiet_mode := AppState.is_quiet_hours_now()
    var source_last := int(_last_auto_prompt_by_source.get(source_kind, 0))
    if not _prompt_cadence.can_emit(
        _last_auto_prompt_unix,
        now_unix,
        AppState.settings,
        quiet_mode,
        source_kind,
        source_last
    ):
        _manual_verification_report.record_prompt_metric(source_kind, "suppressed")
        return false
    _update_balloon_position()
    _buddy_say(line, source_kind)
    _last_auto_prompt_unix = now_unix
    _last_auto_prompt_by_source[source_kind] = now_unix
    _prompt_cadence.note_emit(now_unix, source_kind)
    _manual_verification_report.record_prompt_metric(source_kind, "shown")
    return true


func _flush_deferred_world_prompt(now_unix: int) -> void:
    if _deferred_world_prompt.is_empty():
        return
    var quiet_mode := AppState.is_quiet_hours_now()
    var source_last := int(_last_auto_prompt_by_source.get("world", 0))
    if _prompt_cadence.can_emit(
        _last_auto_prompt_unix,
        now_unix,
        AppState.settings,
        quiet_mode,
        "world",
        source_last
    ):
        var queued: Dictionary = _deferred_world_prompt.duplicate(true)
        _deferred_world_prompt.clear()
        _show_world_prompt(queued)


func _export_manual_verification_snapshot() -> void:
    var now_unix := int(Time.get_unix_time_from_system())
    var snapshot := _manual_verification_report.build_snapshot(
        AppState.settings,
        AppState.get_telemetry_snapshot(),
        AppState.get_world_snapshot(),
        now_unix,
        _last_auto_prompt_unix,
        not _deferred_world_prompt.is_empty()
    )
    var user_dir := "user://manual_verification"
    var absolute_dir := ProjectSettings.globalize_path(user_dir)
    var mkdir_code := DirAccess.make_dir_recursive_absolute(absolute_dir)
    if mkdir_code != OK:
        _update_balloon_position()
        _buddy_say("Snapshot export failed (mkdir).")
        return
    var dt := Time.get_datetime_dict_from_unix_time(now_unix)
    var filename := "plan5_snapshot_%04d%02d%02d_%02d%02d%02d.json" % [
        int(dt.get("year", 1970)),
        int(dt.get("month", 1)),
        int(dt.get("day", 1)),
        int(dt.get("hour", 0)),
        int(dt.get("minute", 0)),
        int(dt.get("second", 0)),
    ]
    var user_path := "%s/%s" % [user_dir, filename]
    var file := FileAccess.open(user_path, FileAccess.WRITE)
    if file == null:
        _update_balloon_position()
        _buddy_say("Snapshot export failed (write).")
        return
    file.store_string(JSON.stringify(snapshot, "\t"))
    file.close()
    _update_balloon_position()
    _buddy_say("Manual snapshot exported: %s" % user_path)
