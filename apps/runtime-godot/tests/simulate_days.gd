extends Node

# Command-line fast-forward: lives a new buddy through N days and prints the
# report. Usage (after --): --no-save --days=N --seed=N --journal=all|firsts|none --world=town|land --out=<path>
# --no-save is required: it makes the app start without opening the save files
# (see AppState.NO_SAVE_ARG). tools/simulate_days.py, the launcher, passes it.

const LifeSim = preload("res://tests/life_sim.gd")

const DEFAULT_DAYS := 30
const MAX_DAYS := 3650


func _ready() -> void:
	# By now the app has started. Without --no-save it has already read the
	# save files, and may have written or renamed them, so refuse to go on.
	if not AppState.is_simulating():
		_fail("simulate_days: start this with tools/simulate_days.py. It passes %s so the save files are never opened." % AppState.NO_SAVE_ARG)
		return
	print("simulate_days: started without opening the save files")
	var days := DEFAULT_DAYS
	var seed_value := 1
	var journal := "firsts"
	var world := "land"
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == AppState.NO_SAVE_ARG:
			continue
		if text.begins_with("--days="):
			var value := text.substr(7)
			if not value.is_valid_int():
				_fail("simulate_days: bad --days value '%s'" % value)
				return
			days = int(value)
		elif text.begins_with("--seed="):
			var value := text.substr(7)
			if not value.is_valid_int():
				_fail("simulate_days: bad --seed value '%s'" % value)
				return
			seed_value = int(value)
		elif text.begins_with("--journal="):
			journal = text.substr(10)
		elif text.begins_with("--world="):
			world = text.substr(8)
		elif text.begins_with("--out="):
			out_path = text.substr(6)
		else:
			_fail("simulate_days: unknown argument '%s'" % text)
			return
	if days < 1 or days > MAX_DAYS:
		_fail("simulate_days: --days must be 1..%d" % MAX_DAYS)
		return
	if not ["all", "firsts", "none"].has(journal):
		_fail("simulate_days: --journal must be all, firsts or none")
		return

	if not ["town", "land"].has(world):
		_fail("simulate_days: --world must be town or land")
		return

	var started := Time.get_ticks_msec()
	var report: Dictionary = LifeSim.run(AppState, {"days": days, "seed": seed_value, "small_beginnings": world == "land"})
	if report.has("error"):
		_fail("simulate_days: " + str(report["error"]))
		return
	# One print per line: Godot cuts a single printed message off at about
	# 16 KB, which a long run's report is well past.
	for line in LifeSim.format_text(report, journal).split("\n"):
		print(line)

	if out_path != "":
		var folder := out_path.get_base_dir()
		if folder != "" and DirAccess.make_dir_recursive_absolute(folder) != OK:
			_fail("simulate_days: cannot create folder '%s'" % folder)
			return
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			_fail("simulate_days: cannot write '%s'" % out_path)
			return
		file.store_string(JSON.stringify(report, "\t", true))
		file.close()
		print("simulate_days: wrote %s" % out_path)

	print("simulate_days: took %d ms" % (Time.get_ticks_msec() - started))
	print("simulate_days: DONE (%d days, %d decisions)" % [days, int(report["totals"]["decisions"])])
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
