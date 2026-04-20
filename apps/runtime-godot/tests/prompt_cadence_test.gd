extends Node

const PromptCadence = preload("res://scripts/utility/prompt_cadence.gd")

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("prompt_cadence_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("prompt_cadence_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("frequency_ordering", func(): return _test_frequency_ordering())
	_case("quiet_strict_expands_interval", func(): return _test_quiet_strict_expands_interval())
	_case("world_allows_faster_surface_than_support", func(): return _test_world_faster_than_support())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("prompt_cadence_test[%s]: %s" % [name, err])
	else:
		print("prompt_cadence_test[%s]: ok" % name)


func _base_settings() -> Dictionary:
	return {
		"promptFrequency": "normal",
		"interactionIntensity": "balanced",
		"quietModeStrictness": "balanced",
	}


func _test_frequency_ordering() -> Variant:
	var cadence := PromptCadence.new()
	var settings := _base_settings()
	settings["promptFrequency"] = "low"
	var low := cadence.min_interval_seconds(settings, false, "support")
	settings["promptFrequency"] = "normal"
	var normal := cadence.min_interval_seconds(settings, false, "support")
	settings["promptFrequency"] = "high"
	var high := cadence.min_interval_seconds(settings, false, "support")
	if not (low > normal and normal > high):
		return "expected low > normal > high intervals, got low=%d normal=%d high=%d" % [low, normal, high]
	return null


func _test_quiet_strict_expands_interval() -> Variant:
	var cadence := PromptCadence.new()
	var settings := _base_settings()
	settings["quietModeStrictness"] = "strict"
	settings["promptFrequency"] = "high"
	var strict_interval := cadence.min_interval_seconds(settings, true, "support")
	if strict_interval < 180:
		return "expected strict quiet interval floor >= 180, got %d" % strict_interval
	if cadence.can_emit(1000, 1000 + strict_interval - 1, settings, true, "support"):
		return "should not emit before strict interval passes"
	if not cadence.can_emit(1000, 1000 + strict_interval, settings, true, "support"):
		return "should emit after strict interval passes"
	return null


func _test_world_faster_than_support() -> Variant:
	var cadence := PromptCadence.new()
	var settings := _base_settings()
	settings["promptFrequency"] = "normal"
	var support_interval := cadence.min_interval_seconds(settings, false, "support")
	var world_interval := cadence.min_interval_seconds(settings, false, "world")
	if world_interval >= support_interval:
		return "expected world interval < support interval, got world=%d support=%d" % [world_interval, support_interval]
	return null
