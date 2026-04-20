extends RefCounted

var _focus_start_unix := 0
var _last_user_activity_unix := 0
var _last_event_unix := 0
var _celebrate_sent := false
var _break_sent := false
var _late_hint_sent := false


func tick(now_unix: int, settings: Dictionary) -> Dictionary:
    if not bool(settings.get("productivityOptIn", false)):
        _reset(now_unix)
        return {}

    if _focus_start_unix <= 0:
        _focus_start_unix = now_unix
    if _last_user_activity_unix <= 0:
        _last_user_activity_unix = now_unix

    var interaction_intensity := str(settings.get("interactionIntensity", "balanced"))
    var quiet_strictness := str(settings.get("quietModeStrictness", "balanced"))
    var quiet_now := _is_quiet_now(settings)
    if quiet_now and quiet_strictness == "strict":
        return {}

    var focus_seconds: int = maxi(0, now_unix - _focus_start_unix)
    var intensity_scale := _intensity_threshold_scale(interaction_intensity)
    var celebrate_threshold := int(float(int(settings.get("focusCelebrateMinutes", 20)) * 60) * intensity_scale)
    var break_threshold := int(float(int(settings.get("breakSuggestMinutes", 45)) * 60) * intensity_scale)
    var late_hour_start := int(settings.get("lateSessionHourStart", 23))

    var event_cooldown_seconds := 180
    if interaction_intensity == "cozy":
        event_cooldown_seconds = 240
    elif interaction_intensity == "deep":
        event_cooldown_seconds = 120

    if (now_unix - _last_event_unix) < event_cooldown_seconds:
        return {}

    if not _celebrate_sent and focus_seconds >= celebrate_threshold:
        _celebrate_sent = true
        _last_event_unix = now_unix
        return {
            "id": "focus-celebration",
            "action": "happy",
            "kind": "celebrate",
        }

    if not _break_sent and focus_seconds >= break_threshold:
        _break_sent = true
        _last_event_unix = now_unix
        return {
            "id": "break-suggestion",
            "action": "sit",
            "kind": "break",
        }

    if not _late_hint_sent and _is_late_session(now_unix, late_hour_start):
        _late_hint_sent = true
        _last_event_unix = now_unix
        return {
            "id": "late-session-checkin",
            "action": "sleep",
            "kind": "late",
        }

    return {}


func note_user_activity(now_unix: int) -> void:
    if _focus_start_unix <= 0:
        _focus_start_unix = now_unix
    _last_user_activity_unix = now_unix


func note_session_reset(now_unix: int) -> void:
    _reset(now_unix)


func focus_minutes(now_unix: int) -> int:
    if _focus_start_unix <= 0:
        return 0
    var total_seconds: int = maxi(0, now_unix - _focus_start_unix)
    return int(total_seconds / 60)


func get_context(now_unix: int, settings: Dictionary) -> Dictionary:
    if _focus_start_unix <= 0:
        _focus_start_unix = now_unix
    if _last_user_activity_unix <= 0:
        _last_user_activity_unix = now_unix

    var focus_mins := focus_minutes(now_unix)
    var idle_minutes := int(maxi(0, now_unix - _last_user_activity_unix) / 60)
    var late_hour_start := int(settings.get("lateSessionHourStart", 23))
    var late_session := _is_late_session(now_unix, late_hour_start)
    var activity_state := "steady"
    if late_session:
        activity_state = "late_session"
    elif focus_mins >= int(settings.get("focusCelebrateMinutes", 20)):
        activity_state = "focused"
    elif idle_minutes >= int(settings.get("idleCheckinMinutes", 20)):
        activity_state = "idle"

    return {
        "activity_state": activity_state,
        "focus_minutes": focus_mins,
        "idle_minutes": idle_minutes,
        "late_session": late_session,
    }


func _reset(now_unix: int) -> void:
    _focus_start_unix = now_unix
    _last_user_activity_unix = now_unix
    _last_event_unix = 0
    _celebrate_sent = false
    _break_sent = false
    _late_hint_sent = false


func _intensity_threshold_scale(interaction_intensity: String) -> float:
    if interaction_intensity == "cozy":
        return 1.25
    if interaction_intensity == "deep":
        return 0.75
    return 1.0


func _is_quiet_now(settings: Dictionary) -> bool:
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


func _is_late_session(now_unix: int, late_hour_start: int) -> bool:
    var dt := Time.get_datetime_dict_from_unix_time(now_unix)
    var hour := int(dt.get("hour", 12))
    return hour >= late_hour_start
