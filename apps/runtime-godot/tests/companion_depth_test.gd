extends Node

const ProductivityTracker = preload("res://scripts/utility/productivity_tracker.gd")
const EncounterScheduler = preload("res://scripts/encounters/encounter_scheduler.gd")

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("companion_depth_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("companion_depth_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("productivity_intensity_thresholds", func(): return _test_productivity_intensity_thresholds())
	_case("productivity_strict_quiet_suppression", func(): return _test_productivity_strict_quiet_suppression())
	_case("encounter_quiet_strictness_behavior", func(): return _test_encounter_quiet_strictness_behavior())
	_case("encounter_frequency_setting_cadence", func(): return _test_encounter_frequency_setting_cadence())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("companion_depth_test[%s]: %s" % [name, err])
	else:
		print("companion_depth_test[%s]: ok" % name)


func _base_settings() -> Dictionary:
	return {
		"productivityOptIn": true,
		"focusCelebrateMinutes": 20,
		"breakSuggestMinutes": 45,
		"interactionIntensity": "balanced",
		"quietModeStrictness": "balanced",
		"quietHoursEnabled": false,
		"quietHoursStart": 22,
		"quietHoursEnd": 7,
		"lateSessionHourStart": 23,
		"idleCheckinMinutes": 20,
	}


func _test_productivity_intensity_thresholds() -> Variant:
	var tracker := ProductivityTracker.new()
	var settings_deep := _base_settings()
	settings_deep["interactionIntensity"] = "deep"
	tracker.note_session_reset(100)
	var deep_event := tracker.tick(100 + (16 * 60), settings_deep)
	if str(deep_event.get("id", "")) != "focus-celebration":
		return "expected deep intensity to trigger focus celebration by 16m"

	var tracker_cozy := ProductivityTracker.new()
	var settings_cozy := _base_settings()
	settings_cozy["interactionIntensity"] = "cozy"
	tracker_cozy.note_session_reset(100)
	var cozy_event := tracker_cozy.tick(100 + (16 * 60), settings_cozy)
	if not cozy_event.is_empty():
		return "expected cozy intensity to suppress early celebration at 16m"
	return null


func _test_productivity_strict_quiet_suppression() -> Variant:
	var tracker := ProductivityTracker.new()
	var settings := _base_settings()
	settings["interactionIntensity"] = "deep"
	settings["quietHoursEnabled"] = true
	settings["quietHoursStart"] = 0
	settings["quietHoursEnd"] = 0
	settings["quietModeStrictness"] = "strict"
	tracker.note_session_reset(100)
	var event_strict := tracker.tick(100 + (30 * 60), settings)
	if not event_strict.is_empty():
		return "expected strict quiet mode to suppress productivity hints"

	var tracker_lenient := ProductivityTracker.new()
	settings["quietModeStrictness"] = "lenient"
	tracker_lenient.note_session_reset(100)
	var event_lenient := tracker_lenient.tick(100 + (30 * 60), settings)
	if event_lenient.is_empty():
		return "expected lenient quiet mode to allow productivity hint"
	return null


func _test_encounter_quiet_strictness_behavior() -> Variant:
	var scheduler := EncounterScheduler.new()
	scheduler.configure(
		[
			{
				"id": "visitor-hello",
				"action": "visitor",
				"weight": 1.0,
				"cooldownSeconds": 1,
				"perHour": 2,
				"perDay": 6,
			}
		],
		12345
	)

	var strict_context := {
		"quiet_mode": true,
		"quiet_strictness": "strict",
		"event_frequency": "high",
		"interaction_intensity": "deep",
	}
	for i in range(120):
		var strict_row := scheduler.tick(1000 + i, strict_context)
		if not strict_row.is_empty():
			return "strict quiet mode should never emit encounter rows"

	var lenient_context := {
		"quiet_mode": true,
		"quiet_strictness": "lenient",
		"event_frequency": "high",
		"interaction_intensity": "deep",
	}
	var saw_lenient := false
	for i in range(400):
		var lenient_row := scheduler.tick(2000 + i, lenient_context)
		if not lenient_row.is_empty():
			saw_lenient = true
			break
	if not saw_lenient:
		return "expected at least one encounter under lenient quiet settings"
	return null


func _count_events_for_frequency(frequency: String) -> int:
	var scheduler := EncounterScheduler.new()
	scheduler.configure(
		[
			{
				"id": "visitor-hello",
				"action": "visitor",
				"weight": 1.0,
				"cooldownSeconds": 1,
				"perHour": 9999,
				"perDay": 9999,
			}
		],
		24680
	)
	var context := {
		"quiet_mode": false,
		"quiet_strictness": "balanced",
		"event_frequency": frequency,
		"interaction_intensity": "balanced",
		"activity_state": "steady",
	}
	var count := 0
	for i in range(2400):
		if not scheduler.tick(10000 + i, context).is_empty():
			count += 1
	return count


func _test_encounter_frequency_setting_cadence() -> Variant:
	var low_count := _count_events_for_frequency("low")
	var normal_count := _count_events_for_frequency("normal")
	var high_count := _count_events_for_frequency("high")
	if not (low_count < normal_count and normal_count < high_count):
		return "expected cadence ordering low < normal < high, got %d < %d < %d" % [low_count, normal_count, high_count]
	return null
