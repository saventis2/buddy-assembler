extends Node

const LifeSim = preload("res://tests/life_sim.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")
const MindService = preload("res://scripts/services/mind_service.gd")

const SAVE_PATHS := ["user://profile.json", "user://settings.json", "user://world_state.json"]

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("life_sim_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("life_sim_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


# nothing_is_saved must stay first: it needs the process to still be unsimulated
# when it records what is on disk.
func _run_all() -> void:
	_case("nothing_is_saved", func(): return _test_nothing_is_saved())
	_case("same_seed_same_life", func(): return _test_same_seed_same_life())
	_case("different_seed_differs", func(): return _test_different_seed_differs())
	_case("clock_is_the_sim_clock", func(): return _test_clock_is_the_sim_clock())
	_case("report_has_every_slot", func(): return _test_report_has_every_slot())
	_case("a_week_has_some_life", func(): return _test_a_week_has_some_life())
	_case("mind_time_zone_can_be_pinned", func(): return _test_mind_time_zone_can_be_pinned())
	_case("catalog_trim_keeps_the_shop", func(): return _test_catalog_trim_keeps_the_shop())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("life_sim_test[%s]: %s" % [name, err])
	else:
		print("life_sim_test[%s]: ok" % name)


func _disk_state() -> Dictionary:
	var state := {}
	for path in SAVE_PATHS:
		state[path] = FileAccess.get_md5(path) if FileAccess.file_exists(path) else "missing"
	return state


func _slots_per_day() -> int:
	return int(86400 / MindService.DECISION_INTERVAL_SECONDS)


func _test_nothing_is_saved() -> Variant:
	var before := _disk_state()
	var report: Dictionary = LifeSim.run(AppState, {"days": 1, "seed": 5})
	if report.has("error"):
		return "run failed: " + str(report["error"])
	if not AppState.is_simulating():
		return "AppState should be simulating after a run"
	AppState.flush()
	AppState.flush_soon()
	AppState._process(10.0)
	AppState.clear_last_active_summary()
	AppState.mark_first_run_seen()
	var after := _disk_state()
	if JSON.stringify(before, "", true) != JSON.stringify(after, "", true):
		return "save files changed: %s -> %s" % [JSON.stringify(before), JSON.stringify(after)]
	return null


func _test_same_seed_same_life() -> Variant:
	var first: Dictionary = LifeSim.run(AppState, {"days": 3, "seed": 11})
	var second: Dictionary = LifeSim.run(AppState, {"days": 3, "seed": 11})
	if first.has("error") or second.has("error"):
		return "run failed"
	if (first["rows"] as Array).is_empty():
		return "no journal rows"
	if JSON.stringify(first["rows"], "", true) != JSON.stringify(second["rows"], "", true):
		return "rows differ between two runs of the same seed"
	if JSON.stringify(first["days"], "", true) != JSON.stringify(second["days"], "", true):
		return "days differ between two runs of the same seed"
	return null


func _test_different_seed_differs() -> Variant:
	var first: Dictionary = LifeSim.run(AppState, {"days": 3, "seed": 11})
	var second: Dictionary = LifeSim.run(AppState, {"days": 3, "seed": 12})
	if first.has("error") or second.has("error"):
		return "run failed"
	if JSON.stringify(first["rows"], "", true) == JSON.stringify(second["rows"], "", true):
		return "seeds 11 and 12 lived the same life"
	return null


func _test_clock_is_the_sim_clock() -> Variant:
	var start: int = LifeSim.DEFAULT_START_UNIX
	if not AppState.begin_simulation(3, start):
		return "begin_simulation refused"
	AppState.set_sim_clock(start + 3 * 3600)
	if not bool(AppState.get_behavior_context().get("is_night", false)):
		return "03:00 should be night"
	if AppState._now_unix() != start + 3 * 3600:
		return "_now_unix is not the sim clock"
	AppState.set_sim_clock(start + 12 * 3600)
	if bool(AppState.get_behavior_context().get("is_night", true)):
		return "12:00 should not be night"
	AppState.set_sim_clock(0)
	if AppState._now_unix() != start + 12 * 3600:
		return "set_sim_clock(0) should be ignored"
	var report: Dictionary = LifeSim.run(AppState, {"days": 1, "seed": 3})
	for row_variant in report["rows"]:
		var row: Dictionary = row_variant
		var stamp: Dictionary = Time.get_datetime_dict_from_unix_time(int(row["t"]))
		if int(row["hour"]) != int(stamp["hour"]) or int(row["minute"]) != int(stamp["minute"]):
			return "row at %d has the wrong clock %d:%d" % [int(row["t"]), int(row["hour"]), int(row["minute"])]
	return null


func _test_report_has_every_slot() -> Variant:
	var report: Dictionary = LifeSim.run(AppState, {"days": 2, "seed": 4})
	if report.has("error"):
		return "run failed: " + str(report["error"])
	for key in ["schema", "config", "not_simulated", "rows", "days", "totals", "final"]:
		if not report.has(key):
			return "report is missing " + key
	var days: Array = report["days"]
	if days.size() != 2:
		return "expected 2 days, got %d" % days.size()
	for day_variant in days:
		var day: Dictionary = day_variant
		for key in ["day", "decisions", "intents", "places", "companions", "firsts", "new_texts", "meso", "mood", "open_wants", "purchases"]:
			if not day.has(key):
				return "day is missing " + key
		if int(day["decisions"]) != _slots_per_day():
			return "day %d made %d decisions, expected %d" % [int(day["day"]), int(day["decisions"]), _slots_per_day()]
	var totals: Dictionary = report["totals"]
	for key in ["decisions", "rows", "distinct_texts", "distinct_text_ratio", "flat_days", "longest_flat_streak", "places_visited", "companions_met", "wants_noticed", "purchases", "intents"]:
		if not totals.has(key):
			return "totals is missing " + key
	if int(totals["decisions"]) != 2 * _slots_per_day():
		return "wrong total decisions"
	for key in ["location", "favourite", "least", "feelings", "wants", "bond_level", "top_trait", "meso", "journal_tail"]:
		if not (report["final"] as Dictionary).has(key):
			return "final is missing " + key
	if not LifeSim.format_text(report, "firsts").contains("Day 1"):
		return "format_text lost the day blocks"
	return null


func _test_a_week_has_some_life() -> Variant:
	for seed_value in [11, 12, 13]:
		var report: Dictionary = LifeSim.run(AppState, {"days": 7, "seed": seed_value})
		if report.has("error"):
			return "run failed: " + str(report["error"])
		var totals: Dictionary = report["totals"]
		print("life_sim_test: week seed %d places %d intents %d distinct_texts %d ratio %s companions %d wants %d purchases %d flat_days %d" % [
			seed_value, int(totals["places_visited"]), (totals["intents"] as Dictionary).size(), int(totals["distinct_texts"]),
			str(totals["distinct_text_ratio"]), int(totals["companions_met"]), int(totals["wants_noticed"]), int(totals["purchases"]), int(totals["flat_days"])])
		# Observed over seeds 11-13: 7 places, 5 intents, 71-78 distinct texts.
		if int(totals["places_visited"]) < 4:
			return "seed %d visited %d places" % [seed_value, int(totals["places_visited"])]
		if (totals["intents"] as Dictionary).size() < 4:
			return "seed %d used %d intents" % [seed_value, (totals["intents"] as Dictionary).size()]
		if int(totals["distinct_texts"]) < 30:
			return "seed %d wrote %d distinct texts" % [seed_value, int(totals["distinct_texts"])]
	return null


func _test_mind_time_zone_can_be_pinned() -> Variant:
	# 13:00 UTC on 2027-01-01. Twelve hours east of UTC it is already the next
	# local day; pinned to UTC it is still the first.
	var utc_unix: int = LifeSim.DEFAULT_START_UNIX + 13 * 3600
	var town := {
		"home_place": "home",
		"places": [
			{"id": "home", "name": "home", "opens": 0, "closes": 24, "distance": 0, "residents": [],
				"activities": [{"id": "nap", "label": "had a nap", "satisfies": "energy"}]},
			{"id": "pond", "name": "the pond", "opens": 0, "closes": 24, "distance": 2, "residents": [],
				"activities": [{"id": "skip_stones", "label": "skipped stones", "satisfies": "curiosity"}]},
		],
	}
	var plan_days := []
	for bias in [0, 720]:
		var svc := MindService.new()
		svc.set_time_zone_bias_minutes(bias)
		var profile := {"personality_seed_tag": "curious", "mood_modifiers": {"energy_strain": 0.2, "social_fulfillment": 0.5, "comfort": 0.5, "confidence": 0.5}}
		var result: Dictionary = svc.tick(profile, [], utc_unix, {"plans": true, "hour": 13}, town)
		var plan: Dictionary = svc.get_day_plan(result["profile"])
		if not plan.has("day"):
			return "no day plan was made at bias %d" % bias
		plan_days.append(int(plan["day"]))
	if plan_days[0] != int(utc_unix / 86400):
		return "bias 0 gave day %d, expected %d" % [plan_days[0], int(utc_unix / 86400)]
	if plan_days[1] != plan_days[0] + 1:
		return "bias 720 gave day %d, expected %d" % [plan_days[1], plan_days[0] + 1]
	return null


func _test_catalog_trim_keeps_the_shop() -> Variant:
	if not AppState.begin_simulation(2, LifeSim.DEFAULT_START_UNIX):
		return "begin_simulation refused"
	var loaded: Dictionary = ContentLoader.load_with_fallback("core_pack", "", false)
	AppState.apply_loaded_pack(str(loaded.get("pack_id", "core_pack")), loaded.get("manifest", {}))
	var full_size: int = (AppState.world_state["item_catalog"] as Dictionary).size()
	var before: String = JSON.stringify(AppState._want_shop_items(), "", true)
	AppState.trim_catalog_for_simulation()
	var trimmed_size: int = (AppState.world_state["item_catalog"] as Dictionary).size()
	var after: String = JSON.stringify(AppState._want_shop_items(), "", true)
	if before == "[]":
		return "the shop list is empty, so this proves nothing"
	if before != after:
		return "the shop list changed after the trim"
	if trimmed_size >= full_size or trimmed_size > AppState.WANT_SHOP_SIZE:
		return "catalogue went from %d to %d rows" % [full_size, trimmed_size]
	return null
