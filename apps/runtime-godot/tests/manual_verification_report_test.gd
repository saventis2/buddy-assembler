extends Node

const ManualVerificationReport = preload("res://scripts/utility/manual_verification_report.gd")

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("manual_verification_report_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("manual_verification_report_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("records_prompt_metrics", func(): return _test_records_prompt_metrics())
	_case("builds_snapshot_with_expected_fields", func(): return _test_builds_snapshot_with_expected_fields())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("manual_verification_report_test[%s]: %s" % [name, err])
	else:
		print("manual_verification_report_test[%s]: ok" % name)


func _test_records_prompt_metrics() -> Variant:
	var report := ManualVerificationReport.new()
	report.record_prompt_metric("support", "shown")
	report.record_prompt_metric("support", "shown")
	report.record_prompt_metric("world", "suppressed")
	report.record_prompt_metric("world", "deferred")
	var metrics := report.get_prompt_metrics()
	if int(metrics.get("support_shown", 0)) != 2:
		return "expected support_shown count 2"
	if int(metrics.get("world_suppressed", 0)) != 1:
		return "expected world_suppressed count 1"
	if int(metrics.get("world_deferred", 0)) != 1:
		return "expected world_deferred count 1"
	return null


func _test_builds_snapshot_with_expected_fields() -> Variant:
	var report := ManualVerificationReport.new()
	report.record_prompt_metric("support", "shown")
	var now_unix := 1_700_000_000
	var settings := {
		"quietHoursEnabled": true,
		"quietHoursStart": 22,
		"quietHoursEnd": 7,
		"promptFrequency": "normal",
	}
	var telemetry := {"bond_level": 3, "mood": "calm"}
	var world := {"pending_quest_id": "quest-a"}
	var snap := report.build_snapshot(settings, telemetry, world, now_unix, now_unix - 10, true)
	if int(snap.get("generated_unix", 0)) != now_unix:
		return "generated_unix mismatch"
	var metrics = snap.get("prompt_metrics", {})
	if typeof(metrics) != TYPE_DICTIONARY:
		return "prompt_metrics missing"
	if int((metrics as Dictionary).get("support_shown", 0)) != 1:
		return "support_shown not carried into snapshot"
	if not bool(snap.get("has_deferred_world_prompt", false)):
		return "expected deferred world prompt flag true"
	if int(snap.get("seconds_since_last_auto_prompt", -1)) != 10:
		return "unexpected seconds_since_last_auto_prompt"
	return null
