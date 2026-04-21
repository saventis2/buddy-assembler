extends RefCounted

const BASE_INTERVALS := {
	"low": 90,
	"normal": 45,
	"high": 22,
}

var _recent_emits_by_source := {}


func min_interval_seconds(
	settings: Dictionary,
	quiet_mode: bool,
	source_kind: String = "support"
) -> int:
	var frequency := str(settings.get("promptFrequency", "normal"))
	var base := int(BASE_INTERVALS.get(frequency, BASE_INTERVALS["normal"]))

	if source_kind == "world":
		base = int(round(float(base) * 0.85))
	elif source_kind == "chat":
		base = int(round(float(base) * 0.70))

	var interaction_intensity := str(settings.get("interactionIntensity", "balanced"))
	if interaction_intensity == "cozy":
		base = int(round(float(base) * 1.20))
	elif interaction_intensity == "deep":
		base = int(round(float(base) * 0.80))

	if quiet_mode:
		var quiet_strictness := str(settings.get("quietModeStrictness", "balanced"))
		if quiet_strictness == "strict":
			base = maxi(base, 180)
		elif quiet_strictness == "balanced":
			base = int(round(float(base) * 1.50))
		else:
			base = int(round(float(base) * 1.20))

	base += _source_additive_seconds(source_kind)
	return clampi(base, 8, 300)


func can_emit(
	last_prompt_unix: int,
	now_unix: int,
	settings: Dictionary,
	quiet_mode: bool,
	source_kind: String = "support",
	source_last_prompt_unix: int = -1
) -> bool:
	var reference_last := source_last_prompt_unix if source_last_prompt_unix > 0 else last_prompt_unix
	if reference_last > 0:
		if (now_unix - reference_last) < min_interval_seconds(settings, quiet_mode, source_kind):
			return false

	var recent := _pruned_recent(now_unix, source_kind)
	var cap := _burst_cap_per_10m(settings, source_kind, quiet_mode)
	return recent.size() < cap


func note_emit(now_unix: int, source_kind: String = "support") -> void:
	var recent := _pruned_recent(now_unix, source_kind)
	recent.append(now_unix)
	_recent_emits_by_source[source_kind] = recent


func debug_snapshot(now_unix: int, settings: Dictionary, quiet_mode: bool) -> Dictionary:
	var out := {}
	var sources := ["support", "world", "chat"]
	for source in sources:
		var recent := _pruned_recent(now_unix, source)
		out[source] = {
			"recent_count": recent.size(),
			"burst_cap": _burst_cap_per_10m(settings, source, quiet_mode),
			"min_interval_s": min_interval_seconds(settings, quiet_mode, source),
		}
	return out


func _source_additive_seconds(source_kind: String) -> int:
	if source_kind == "support":
		return 8
	if source_kind == "world":
		return 4
	if source_kind == "chat":
		return 0
	return 6


func _burst_cap_per_10m(settings: Dictionary, source_kind: String, quiet_mode: bool) -> int:
	var base := 4
	var freq := str(settings.get("promptFrequency", "normal"))
	if freq == "low":
		base = 2
	elif freq == "high":
		base = 6

	var intensity := str(settings.get("interactionIntensity", "balanced"))
	if intensity == "cozy":
		base -= 1
	elif intensity == "deep":
		base += 1

	if source_kind == "world":
		base += 1
	elif source_kind == "chat":
		base += 2

	if quiet_mode:
		var quiet_strictness := str(settings.get("quietModeStrictness", "balanced"))
		if quiet_strictness == "strict":
			base = mini(base, 1)
		elif quiet_strictness == "balanced":
			base = mini(base, 2)

	return clampi(base, 1, 10)


func _pruned_recent(now_unix: int, source_kind: String) -> Array:
	var existing_variant = _recent_emits_by_source.get(source_kind, [])
	var existing: Array = existing_variant if typeof(existing_variant) == TYPE_ARRAY else []
	var recent: Array = []
	for ts_variant in existing:
		var ts := int(ts_variant)
		if now_unix - ts <= 600:
			recent.append(ts)
	_recent_emits_by_source[source_kind] = recent
	return recent
