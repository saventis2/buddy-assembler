extends RefCounted

var _focus_start_unix := 0
var _last_event_unix := 0
var _celebrate_sent := false
var _break_sent := false


func tick(now_unix: int, settings: Dictionary) -> Dictionary:
    if not bool(settings.get("productivityOptIn", false)):
        _reset(now_unix)
        return {}

    if _focus_start_unix <= 0:
        _focus_start_unix = now_unix

    var focus_seconds: int = maxi(0, now_unix - _focus_start_unix)
    var celebrate_threshold := int(settings.get("focusCelebrateMinutes", 20)) * 60
    var break_threshold := int(settings.get("breakSuggestMinutes", 45)) * 60

    if (now_unix - _last_event_unix) < 180:
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

    return {}


func note_user_activity(now_unix: int) -> void:
    if _focus_start_unix <= 0:
        _focus_start_unix = now_unix


func note_session_reset(now_unix: int) -> void:
    _reset(now_unix)


func focus_minutes(now_unix: int) -> int:
    if _focus_start_unix <= 0:
        return 0
    var total_seconds: int = maxi(0, now_unix - _focus_start_unix)
    return int(total_seconds / 60)


func _reset(now_unix: int) -> void:
    _focus_start_unix = now_unix
    _last_event_unix = 0
    _celebrate_sent = false
    _break_sent = false
