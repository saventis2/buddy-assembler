extends Node

# The fresh start (Plan 14 step 1c): backing up the save, and replacing only the
# buddy. Everything this test writes goes under ROOT. It never writes the real
# save files: every AppState case starts with begin_simulation (after which
# AppState never saves) and calls _fresh_start with paths under ROOT.

const SaveStore = preload("res://scripts/persistence/save_store.gd")
const LifeSim = preload("res://tests/life_sim.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")
const LandData = preload("res://scripts/services/land_data.gd")

const ROOT := "user://fresh_start_test"

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("fresh_start_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("fresh_start_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_wipe(ROOT)
	_case("backup_copies_every_file", func(): return _test_backup_copies_every_file())
	_case("backup_is_never_overwritten", func(): return _test_backup_is_never_overwritten())
	_case("backup_failure_returns_empty", func(): return _test_backup_failure_returns_empty())
	_case("an_old_buddy_is_put_away_and_a_new_one_wakes", func(): return _test_old_buddy_put_away())
	_case("a_land_buddy_is_left_alone", func(): return _test_land_buddy_left_alone())
	_case("a_new_install_needs_no_backup", func(): return _test_new_install())
	_case("the_setting_off_means_no_fresh_start", func(): return _test_setting_off())
	_case("a_failed_backup_changes_nothing", func(): return _test_failed_backup())
	_case("a_new_buddy_wakes_up", func(): return _test_new_buddy_wakes_up())
	_wipe(ROOT)


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("fresh_start_test[%s]: %s" % [name, err])
	else:
		print("fresh_start_test[%s]: ok" % name)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("fresh_start_test: cannot write %s" % path)
		return
	file.store_string(text)
	file.close()


func _md5(path: String) -> String:
	return FileAccess.get_md5(path) if FileAccess.file_exists(path) else "missing"


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		if FileAccess.file_exists(dir):
			DirAccess.remove_absolute(dir)
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + "/" + sub)
	for file_name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + file_name)
	DirAccess.remove_absolute(dir)


func _make_old_buddy() -> void:
	AppState.profile["bond_xp"] = 300
	var mind: Dictionary = AppState.profile["mind"]
	mind["decision_count"] = 5
	mind["journal"] = [{"t": 1, "text": "I went to the pond."}]
	mind["name"] = "Old Buddy"
	mind["born"] = ""
	AppState.profile["mind"] = mind


func _mind() -> Dictionary:
	return AppState.profile["mind"]


func _test_backup_copies_every_file() -> Variant:
	var paths := [ROOT + "/a/profile.json", ROOT + "/a/settings.json", ROOT + "/a/world_state.json"]
	_write(paths[0], "{\"profile\": 1}")
	_write(paths[1], "{\"settings\": 22}")
	_write(paths[2], "{\"world\": 333}")
	var before: Array = []
	for p in paths:
		before.append(_md5(p))
	var all_paths: Array = paths.duplicate()
	all_paths.append(ROOT + "/a/missing.json")
	var folder := SaveStore.backup_files(all_paths, ROOT + "/b", "label")
	if folder != ROOT + "/b/label":
		return "backup returned '%s'" % folder
	for i in range(paths.size()):
		var copy: String = folder + "/" + str(paths[i]).get_file()
		if _md5(copy) != before[i]:
			return "%s is not an exact copy" % copy
		if _md5(paths[i]) != before[i]:
			return "%s changed" % paths[i]
	if FileAccess.file_exists(folder + "/missing.json"):
		return "a missing file was invented in the backup"
	return null


func _test_backup_is_never_overwritten() -> Variant:
	var first_md5 := _md5(ROOT + "/b/label/profile.json")
	_write(ROOT + "/a/profile.json", "{\"profile\": \"changed\"}")
	var paths := [ROOT + "/a/profile.json", ROOT + "/a/settings.json", ROOT + "/a/world_state.json"]
	var folder := SaveStore.backup_files(paths, ROOT + "/b", "label")
	if folder != ROOT + "/b/label-2":
		return "second backup went to '%s'" % folder
	if _md5(ROOT + "/b/label/profile.json") != first_md5:
		return "the first backup was overwritten"
	return null


func _test_backup_failure_returns_empty() -> Variant:
	_write(ROOT + "/blocker", "i am a file")
	var folder := SaveStore.backup_files([ROOT + "/a/profile.json"], ROOT + "/blocker/x", "label")
	if folder != "":
		return "backup into a blocked folder returned '%s'" % folder
	return null


func _test_old_buddy_put_away() -> Variant:
	if not AppState.begin_simulation(1, LifeSim.DEFAULT_START_UNIX):
		return "begin_simulation refused"
	AppState.settings["smallBeginnings"] = true
	_make_old_buddy()
	var profile_path := ROOT + "/old/profile.json"
	var settings_path := ROOT + "/old/settings.json"
	var world_path := ROOT + "/old/world_state.json"
	_write(profile_path, JSON.stringify(AppState.profile))
	_write(settings_path, "{\"s\": 1}")
	_write(world_path, "{\"w\": 2}")
	var paths := [settings_path, profile_path, world_path]
	var md5s := {}
	for p in paths:
		md5s[p] = _md5(p)
	var world_before := JSON.stringify(AppState.world_state, "", true)
	var result: Dictionary = AppState._fresh_start(true, paths, ROOT + "/old/backups")
	if str(result.get("status", "")) != "started":
		return "status was %s" % str(result.get("status", ""))
	var backup := str(result.get("backup", ""))
	if not backup.begins_with(ROOT + "/old/backups/before-small-beginnings-"):
		return "backup folder was '%s'" % backup
	for p in paths:
		if _md5(backup + "/" + str(p).get_file()) != md5s[p]:
			return "backup of %s is not an exact copy" % p
		if _md5(p) != md5s[p]:
			return "original %s changed" % p
	var mind := _mind()
	if str(mind.get("born", "")) != "land":
		return "the new buddy was not born on the land"
	if int(mind.get("decision_count", -1)) != 0:
		return "decision_count was %s" % str(mind.get("decision_count"))
	if not (mind.get("journal", []) as Array).is_empty():
		return "the new buddy kept a journal"
	if str(mind.get("name", "")) != "":
		return "the new buddy kept the old name"
	if int(AppState.profile.get("bond_xp", -1)) != 0:
		return "bond_xp was %s" % str(AppState.profile.get("bond_xp"))
	if JSON.stringify(AppState.world_state, "", true) != world_before:
		return "the world state changed"
	if str(AppState.settings.get("freshStartBackup", "")) != backup:
		return "freshStartBackup was not recorded"
	return null


func _test_land_buddy_left_alone() -> Variant:
	var paths := [ROOT + "/old/settings.json", ROOT + "/old/profile.json", ROOT + "/old/world_state.json"]
	var result: Dictionary = AppState._fresh_start(true, paths, ROOT + "/old/backups")
	if str(result.get("status", "")) != "not_due":
		return "status was %s" % str(result.get("status", ""))
	var folders := DirAccess.get_directories_at(ROOT + "/old/backups")
	if folders.size() != 1:
		return "expected one backup folder, found %d" % folders.size()
	return null


func _test_new_install() -> Variant:
	if not AppState.begin_simulation(1, LifeSim.DEFAULT_START_UNIX):
		return "begin_simulation refused"
	AppState.settings["smallBeginnings"] = true
	# On a new install, loading can already have written a default profile by
	# the time the fresh start runs. That file is not a buddy from before.
	var none := ROOT + "/none/profile.json"
	_write(none, JSON.stringify(AppState.profile))
	var result: Dictionary = AppState._fresh_start(false, [none], ROOT + "/none/backups")
	if str(result.get("status", "")) != "started":
		return "status was %s" % str(result.get("status", ""))
	if str(result.get("backup", "")) != "":
		return "a backup was made with nothing to back up"
	if DirAccess.dir_exists_absolute(ROOT + "/none/backups"):
		return "a backups folder was made with nothing to back up"
	if str(_mind().get("born", "")) != "land":
		return "the new buddy was not born on the land"
	return null


func _test_setting_off() -> Variant:
	if not AppState.begin_simulation(1, LifeSim.DEFAULT_START_UNIX):
		return "begin_simulation refused"
	AppState.settings["smallBeginnings"] = false
	_make_old_buddy()
	var path := ROOT + "/off/profile.json"
	_write(path, JSON.stringify(AppState.profile))
	var result: Dictionary = AppState._fresh_start(true, [path], ROOT + "/off/backups")
	if str(result.get("status", "")) != "not_due":
		return "status was %s" % str(result.get("status", ""))
	if str(_mind().get("born", "")) != "":
		return "the buddy was replaced with the setting off"
	if int(AppState.profile.get("bond_xp", 0)) != 300:
		return "bond_xp changed with the setting off"
	if DirAccess.dir_exists_absolute(ROOT + "/off/backups"):
		return "a backup was made with the setting off"
	return null


func _test_failed_backup() -> Variant:
	if not AppState.begin_simulation(1, LifeSim.DEFAULT_START_UNIX):
		return "begin_simulation refused"
	AppState.settings["smallBeginnings"] = true
	_make_old_buddy()
	var path := ROOT + "/fail/profile.json"
	_write(path, JSON.stringify(AppState.profile))
	_write(ROOT + "/fail/blocker", "i am a file")
	var md5_before := _md5(path)
	var result: Dictionary = AppState._fresh_start(true, [path], ROOT + "/fail/blocker/backups")
	if str(result.get("status", "")) != "backup_failed":
		return "status was %s" % str(result.get("status", ""))
	if int(AppState.profile.get("bond_xp", 0)) != 300:
		return "bond_xp changed after a failed backup"
	if str(_mind().get("born", "")) != "":
		return "the buddy was replaced after a failed backup"
	if _md5(path) != md5_before:
		return "the profile file changed after a failed backup"
	if AppState.small_beginnings():
		return "the old town should carry on for this run"
	if not AppState.begin_simulation(1, LifeSim.DEFAULT_START_UNIX):
		return "begin_simulation refused"
	if not AppState.small_beginnings():
		return "a new run should be back to the default"
	return null


func _test_new_buddy_wakes_up() -> Variant:
	if not AppState.begin_simulation(1, LifeSim.DEFAULT_START_UNIX):
		return "begin_simulation refused"
	var loaded: Dictionary = ContentLoader.load_with_fallback("core_pack", "", false)
	AppState.apply_loaded_pack(str(loaded.get("pack_id", "core_pack")), loaded.get("manifest", {}))
	AppState.trim_catalog_for_simulation()
	AppState.settings["smallBeginnings"] = true
	var none := ROOT + "/wake/profile.json"
	var result: Dictionary = AppState._fresh_start(false, [none], ROOT + "/wake/backups")
	if str(result.get("status", "")) != "started":
		return "status was %s" % str(result.get("status", ""))
	var events: Array = AppState.tick_mind(LifeSim.DEFAULT_START_UNIX)
	if events.size() != 1:
		return "expected one event, got %d" % events.size()
	var text := str((events[0] as Dictionary).get("text", ""))
	if text != str(LandData.LAND["waking"]):
		return "first event was '%s'" % text
	return null
