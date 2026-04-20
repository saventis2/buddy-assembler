extends RefCounted

const DEFAULT_METRICS := {
	"support_shown": 0,
	"support_suppressed": 0,
	"world_shown": 0,
	"world_suppressed": 0,
	"world_deferred": 0,
}

var _prompt_metrics: Dictionary = DEFAULT_METRICS.duplicate(true)


func record_prompt_metric(source_kind: String, outcome: String) -> void:
	if source_kind == "" or outcome == "":
		return
	var key := "%s_%s" % [source_kind, outcome]
	_prompt_metrics[key] = int(_prompt_metrics.get(key, 0)) + 1


func get_prompt_metrics() -> Dictionary:
	return _prompt_metrics.duplicate(true)


func build_snapshot(
	settings: Dictionary,
	telemetry: Dictionary,
	world_snapshot: Dictionary,
	now_unix: int,
	last_auto_prompt_unix: int,
	has_deferred_world_prompt: bool
) -> Dictionary:
	var quiet_now := false
	if typeof(settings) == TYPE_DICTIONARY:
		quiet_now = _is_quiet_now(settings, now_unix)
	return {
		"generated_unix": now_unix,
		"prompt_metrics": get_prompt_metrics(),
		"last_auto_prompt_unix": last_auto_prompt_unix,
		"seconds_since_last_auto_prompt": maxi(0, now_unix - last_auto_prompt_unix) if last_auto_prompt_unix > 0 else -1,
		"has_deferred_world_prompt": has_deferred_world_prompt,
		"settings": settings.duplicate(true) if typeof(settings) == TYPE_DICTIONARY else {},
		"quiet_mode_now": quiet_now,
		"telemetry": telemetry.duplicate(true) if typeof(telemetry) == TYPE_DICTIONARY else {},
		"world_snapshot": world_snapshot.duplicate(true) if typeof(world_snapshot) == TYPE_DICTIONARY else {},
	}


func _is_quiet_now(settings: Dictionary, now_unix: int) -> bool:
	if not bool(settings.get("quietHoursEnabled", true)):
		return false
	var start_hour := int(settings.get("quietHoursStart", 22))
	var end_hour := int(settings.get("quietHoursEnd", 7))
	var now := Time.get_datetime_dict_from_unix_time(now_unix)
	var hour := int(now.get("hour", 12))
	if start_hour == end_hour:
		return true
	if start_hour < end_hour:
		return hour >= start_hour and hour < end_hour
	return hour >= start_hour or hour < end_hour
