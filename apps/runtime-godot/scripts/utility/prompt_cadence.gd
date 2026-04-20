extends RefCounted

const BASE_INTERVALS := {
	"low": 90,
	"normal": 45,
	"high": 22,
}


func min_interval_seconds(
	settings: Dictionary,
	quiet_mode: bool,
	source_kind: String = "support"
) -> int:
	var frequency := str(settings.get("promptFrequency", "normal"))
	var base := int(BASE_INTERVALS.get(frequency, BASE_INTERVALS["normal"]))

	# World prompts can surface slightly faster than support hints.
	if source_kind == "world":
		base = int(round(float(base) * 0.85))

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

	return clampi(base, 8, 300)


func can_emit(
	last_prompt_unix: int,
	now_unix: int,
	settings: Dictionary,
	quiet_mode: bool,
	source_kind: String = "support"
) -> bool:
	if last_prompt_unix <= 0:
		return true
	return (now_unix - last_prompt_unix) >= min_interval_seconds(settings, quiet_mode, source_kind)
