extends Node

# A process started with "-- --no-save" (AppState.NO_SAVE_ARG) must never open
# the save files, not even while the app starts up: a normal start can write
# them (a pending migration) or rename them (a damaged file). The fast-forward
# tool relies on this. The suite runs this scene with that argument; it writes
# nothing, and only reads the save files' checksums.

const LifeSim = preload("res://tests/life_sim.gd")

const SAVE_PATHS := ["user://profile.json", "user://settings.json", "user://world_state.json"]

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("no_save_start_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("no_save_start_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("the_app_started_without_saves", func(): return _test_the_app_started_without_saves())
	_case("it_started_from_defaults", func(): return _test_it_started_from_defaults())
	_case("a_simulated_life_runs", func(): return _test_a_simulated_life_runs())
	_case("nothing_on_disk_changes", func(): return _test_nothing_on_disk_changes())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("no_save_start_test[%s]: %s" % [name, err])
	else:
		print("no_save_start_test[%s]: ok" % name)


func _disk_state() -> Dictionary:
	var state := {}
	for path in SAVE_PATHS:
		state[path] = FileAccess.get_md5(path) if FileAccess.file_exists(path) else "missing"
	return state


func _test_the_app_started_without_saves() -> Variant:
	if not OS.get_cmdline_user_args().has(AppState.NO_SAVE_ARG):
		return "this scene must be run with -- %s" % AppState.NO_SAVE_ARG
	# Saving was already off when the first scene started, before any simulation.
	if not AppState.is_simulating():
		return "saving is still on in a process started with %s" % AppState.NO_SAVE_ARG
	# load_state() records this before it reads anything, so false means it never ran.
	if AppState._profile_was_on_disk:
		return "the app looked at the save files while starting"
	return null


func _test_it_started_from_defaults() -> Variant:
	if JSON.stringify(AppState.settings, "", true) != JSON.stringify(AppState._default_settings(), "", true):
		return "settings are not the defaults"
	var mind: Dictionary = AppState.profile.get("mind", {})
	if int(mind.get("decision_count", -1)) != 0 or not (mind.get("journal", []) as Array).is_empty():
		return "the profile is not a new one"
	if str(AppState.profile.get("name", "")) != str(AppState._default_profile().get("name", "")):
		return "the profile is not the default one"
	return null


func _test_a_simulated_life_runs() -> Variant:
	var report: Dictionary = LifeSim.run(AppState, {"days": 1, "seed": 1, "small_beginnings": true})
	if report.has("error"):
		return "run failed: " + str(report["error"])
	if (report["rows"] as Array).is_empty():
		return "a simulated day wrote no journal rows"
	return null


func _test_nothing_on_disk_changes() -> Variant:
	# Everything below would write if saving were on, so do not even try then.
	if not AppState.is_simulating():
		return "saving is on, so this case was not run"
	var before := _disk_state()
	var had_backups := DirAccess.dir_exists_absolute(AppState.BACKUP_ROOT)
	AppState.flush()
	AppState.flush_soon()
	AppState._process(10.0)
	AppState.clear_last_active_summary()
	AppState.mark_first_run_seen()
	# What a real launch does next. A process that never saves must not copy a
	# backup either.
	var fresh: Dictionary = AppState.fresh_start_if_due()
	if str(fresh.get("status", "")) != "not_due" or str(fresh.get("backup", "")) != "":
		return "the fresh start ran in a process that must not touch the save: %s" % JSON.stringify(fresh)
	var after := _disk_state()
	if JSON.stringify(before, "", true) != JSON.stringify(after, "", true):
		return "save files changed: %s -> %s" % [JSON.stringify(before), JSON.stringify(after)]
	if DirAccess.dir_exists_absolute(AppState.BACKUP_ROOT) != had_backups:
		return "a backups folder appeared"
	return null
