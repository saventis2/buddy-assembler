extends Node

# Plan 14 step 4: the 3D view of the land (LandView). What it builds from what
# the buddy knows, where the card stands and how it walks, the light for the
# hour and the weather, and the mist over what is not found yet. Headless, so
# nothing here looks at pixels; the render harness does that by eye.
#
# Expected noise: Godot 4.2's headless (dummy) renderer prints
# 'Parameter "m" is null' (mesh_get_surface_count) once for each primitive
# shape and each Label3D the view makes. It is the engine's, not a failure.

const LandView = preload("res://scripts/land_view.gd")
const LandData = preload("res://scripts/services/land_data.gd")
const WorldService = preload("res://scripts/services/world_service.gd")

const NOW := 1800000000
# Pacific/Auckland in summer, so the local clock is 13 hours ahead.
const BIAS := 780

var _failed := 0
var _ran := 0
var _layout := {}


func _ready() -> void:
	_layout = WorldService.new().town_map(LandData.LAND)
	_run_all()
	if _failed == 0:
		print("land_view_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("land_view_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("snapshot_from_the_save", func(): return _test_snapshot_from())
	_case("routes_follow_known_paths", func(): return _test_routes())
	_case("walking_takes_time_and_arrives", func(): return _test_walking())
	_case("it_builds_what_it_knows", func(): return _test_builds())
	_case("the_card_stands_where_it_is", func(): return _test_card_stands())
	_case("a_new_decision_is_walked", func(): return _test_new_decision())
	_case("indoors_the_roof_comes_off", func(): return _test_roof())
	_case("the_sky_follows_the_clock_and_weather", func(): return _test_sky())
	_case("a_found_place_clears_its_mist", func(): return _test_mist_clears())
	# Prototype: the view's own UI (the prototype_ui switch).
	_case("ui_is_opt_in", func(): return _test_ui_opt_in())
	_case("ui_status_follows_the_buddy", func(): return _test_ui_status())
	_case("ui_world_keeps_to_the_world", func(): return _test_ui_world())
	_case("ui_fits_every_size", func(): return _test_ui_layout())
	_case("ui_reads_what_is_clicked", func(): return _test_ui_pick())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("land_view_test[%s]: %s" % [name, err])
	else:
		print("land_view_test[%s]: ok" % name)


# --- helpers -------------------------------------------------------------

func _known(found: Array, signs: Array = []) -> Dictionary:
	var out := {}
	for id in found:
		out[id] = {"stage": "found"}
	for id in signs:
		out[id] = {"stage": "sign"}
	return out


func _entry(t: int, place_id: String, intent: String, extra: Dictionary = {}) -> Dictionary:
	var entry := {"t": t, "place_id": place_id, "intent": intent, "activity_id": "act_%s" % intent,
		"activity_label": "doing %s" % intent}
	for key in extra.keys():
		entry[key] = extra[key]
	return entry


func _profile(found: Array, signs: Array, where: String, journal: Array, busy_until: int) -> Dictionary:
	return {"personality_seed": 21, "mind": {"location": where, "busy_until": busy_until,
		"known_places": _known(found, signs), "journal": journal}}


func _snap(profile: Dictionary, now: int = NOW, small: bool = true) -> Dictionary:
	return LandView.snapshot_from(profile, LandData.LAND, _layout, small, now, BIAS, "Pip")


func _point(id: String) -> Vector3:
	return LandView.place_point((_layout["positions"] as Dictionary)[id])


func _view(snapshot: Dictionary) -> Node:
	var view = LandView.new()
	view.live = false
	view.size = Vector2(320, 200)
	add_child(view)
	view.set_snapshot(snapshot)
	return view


func _drop(view: Node) -> void:
	remove_child(view)
	view.free()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _tick(view: Node, seconds: float, step: float = 0.5) -> void:
	var left := seconds
	while left > 0.0:
		view.tick(minf(step, left))
		left -= step


const DAY3 := ["home", "yard", "wood_heap", "big_tree", "patch"]


# --- cases ---------------------------------------------------------------

func _test_snapshot_from() -> Variant:
	var journal := [
		_entry(NOW - 7200, "yard", "tend_home"),
		_entry(NOW - 3600, "big_tree", "explore", {"sign_of": "gate"}),
	]
	var profile := {"personality_seed": 21, "mind": {"location": "big_tree", "busy_until": NOW + 600,
		"known_places": {"yard": {"stage": "found"}, "gate": {"stage": "sign"}, "water": {"stage": "seen"},
			"patch": "not a record"},
		"journal": journal}}
	var snap := _snap(profile)
	var known: Dictionary = snap["known"]
	if known != {"yard": "found", "gate": "sign", "home": "found"}:
		return "known was %s" % str(known)
	if str(snap["where"]) != "big_tree" or int(snap["busy_until"]) != NOW + 600:
		return "where/busy_until: %s %s" % [snap["where"], snap["busy_until"]]
	var last: Dictionary = snap["last"]
	if int(last["t"]) != NOW - 3600 or str(last["place_id"]) != "big_tree" or str(last["intent"]) != "explore":
		return "last was %s" % str(last)
	if str(last["activity_id"]) != "act_explore" or str(last["label"]) != "doing explore":
		return "last activity was %s" % str(last)
	if str(last["edge"]) != "sign" or str(last["toward"]) != "gate":
		return "edge was %s toward %s" % [last["edge"], last["toward"]]
	if str(snap["came_from"]) != "yard":
		return "came_from was %s" % snap["came_from"]
	if str(snap["name"]) != "Pip" or not bool(snap["small"]) or str(snap["home"]) != "home":
		return "name/small/home: %s" % str(snap)
	if (snap["places"] as Array).size() != (LandData.LAND["places"] as Array).size():
		return "not every place came through: %d" % (snap["places"] as Array).size()
	if (snap["paths"] as Array).size() != (LandData.LAND["paths"] as Array).size():
		return "not every path came through"
	var weather: Dictionary = snap["weather"]
	if not ["clear", "cloudy", "rain"].has(str(weather["kind"])):
		return "weather was %s" % str(weather)
	var blocked := _snap({"mind": {"journal": [_entry(NOW, "home", "explore", {"blocked_at": "water"})]}})
	if str((blocked["last"] as Dictionary)["edge"]) != "blocked" or str((blocked["last"] as Dictionary)["toward"]) != "water":
		return "a blocked try was %s" % str(blocked["last"])
	# No mind at all: at home, nothing known but home.
	var bare := _snap({})
	if str(bare["where"]) != "home" or not (bare["last"] as Dictionary).is_empty() or bare["known"] != {"home": "found"}:
		return "a missing mind gave %s" % str(bare)
	if str(bare["came_from"]) != "" or int(bare["busy_until"]) != 0:
		return "a missing mind gave came_from/busy_until %s %s" % [bare["came_from"], bare["busy_until"]]
	# The old town: every place found.
	var town := _snap(profile, NOW, false)
	var town_known: Dictionary = town["known"]
	if town_known.size() != (town["places"] as Array).size():
		return "the town should have every place found, got %d" % town_known.size()
	for id in town_known.keys():
		if str(town_known[id]) != "found":
			return "town place %s was %s" % [id, town_known[id]]
	# The save is data: wrong types must not crash.
	var odd: Array = [
		{"mind": "nope"},
		{"mind": {"journal": "x", "known_places": 5, "location": 7, "busy_until": "9"}},
		{"mind": {"journal": [1, "a", null, {"t": "x"}], "known_places": {"yard": 3}}, "personality_seed": "abc"},
		{"mind": {"location": null, "busy_until": [1], "journal": [{"place_id": 4, "sign_of": 2}]}},
	]
	for profile_variant in odd:
		var made := _snap(profile_variant)
		if typeof(made.get("known", null)) != TYPE_DICTIONARY:
			return "a strange profile gave no known: %s" % str(profile_variant)
	var no_layout := LandView.snapshot_from({}, {}, {}, true, NOW, 0, "")
	if str(no_layout["name"]) != "Buddy" or not (no_layout["places"] as Array).is_empty():
		return "an empty land gave %s" % str(no_layout)
	return ""


func _test_routes() -> Variant:
	var paths: Array = (_layout["paths"] as Array)
	var open := {}
	for id in ["home", "yard", "patch", "long_grass", "water"]:
		open[id] = true
	var way: Array = LandView.route(paths, "home", "water", open)
	if way != ["home", "yard", "patch", "long_grass", "water"]:
		return "the way to the water was %s" % str(way)
	open.erase("long_grass")
	var blocked: Array = LandView.route(paths, "home", "water", open)
	if not blocked.is_empty():
		return "with the long grass unknown there should be no way, got %s" % str(blocked)
	var same: Array = LandView.route(paths, "yard", "yard", {})
	if same != ["yard"]:
		return "the same place should be [id], got %s" % str(same)
	var next_door: Array = LandView.route(paths, "home", "yard", {})
	if next_door != ["home", "yard"]:
		return "the way to a neighbour was %s" % str(next_door)
	return ""


func _test_walking() -> Variant:
	var a := Vector3(0, 0, 0)
	var b := Vector3(8, 0, 0)
	var c := Vector3(8, 0, 6)
	var points: Array = [a, b, c]
	var total := 14.0
	var speed := LandView.WALK_SPEED
	var at_start: Dictionary = LandView.walk_at(points, 100.0, 100.0)
	if (at_start["pos"] as Vector3).distance_to(a) > 0.001 or not bool(at_start["walking"]):
		return "at the start: %s" % str(at_start)
	var before: Dictionary = LandView.walk_at(points, 100.0, 90.0)
	if (before["pos"] as Vector3).distance_to(a) > 0.001:
		return "before the start it should wait at the first point: %s" % str(before)
	var half: Dictionary = LandView.walk_at(points, 100.0, 100.0 + total * 0.5 / speed)
	# Half of 14 m is 7 m: still on the first segment, heading +X.
	if (half["pos"] as Vector3).distance_to(Vector3(7, 0, 0)) > 0.001 or not bool(half["walking"]):
		return "halfway: %s" % str(half)
	if (half["dir"] as Vector3).distance_to(Vector3(1, 0, 0)) > 0.001:
		return "the first segment heads +X, got %s" % str(half["dir"])
	var turned: Dictionary = LandView.walk_at(points, 100.0, 100.0 + 11.0 / speed)
	if (turned["pos"] as Vector3).distance_to(Vector3(8, 0, 3)) > 0.001 or (turned["dir"] as Vector3).distance_to(Vector3(0, 0, 1)) > 0.001:
		return "after the corner: %s" % str(turned)
	var done: Dictionary = LandView.walk_at(points, 100.0, 100.0 + total / speed + 1.0)
	if (done["pos"] as Vector3).distance_to(c) > 0.001 or bool(done["walking"]) or (done["dir"] as Vector3).length() > 0.001:
		return "at the end: %s" % str(done)
	return ""


func _test_builds() -> Variant:
	var profile := _profile(DAY3, ["gate"], "home", [_entry(NOW - 3600, "home", "reflect")], NOW + 600)
	var view := _view(_snap(profile))
	for id in DAY3:
		if view.place_node(id) == null:
			_drop(view)
			return "no place node for %s" % id
	for id in ["gate", "water", "dark_trees"]:
		if view.place_node(id) != null:
			_drop(view)
			return "%s should be under mist, not built" % id
	# Paths only between found places: home-yard, yard-wood_heap, yard-big_tree, yard-patch.
	if view.path_count() != 4:
		var n: int = view.path_count()
		_drop(view)
		return "expected 4 paths, got %d" % n
	if view.label_count() != DAY3.size():
		var n: int = view.label_count()
		_drop(view)
		return "expected %d labels, got %d" % [DAY3.size(), n]
	var water: String = view.mist_blob_near(_point("water"))
	if water != "dense":
		_drop(view)
		return "mist near the water should be dense, got '%s'" % water
	var gate: String = view.mist_blob_near(_point("gate"))
	if gate != "thin":
		_drop(view)
		return "mist near the gate should be thin, got '%s'" % gate
	var yard: String = view.mist_blob_near(_point("yard"))
	if yard != "":
		_drop(view)
		return "there should be no mist at the yard, got '%s'" % yard
	var states: Dictionary = view.mist_states()
	if int(states.get("dense", 0)) <= 0 or int(states.get("thin", 0)) <= 0 or int(states.get("clear", 0)) != 0:
		_drop(view)
		return "mist states were %s" % str(states)
	_drop(view)
	var land_all := {}
	for place_variant in (LandData.LAND["places"] as Array):
		land_all[(place_variant as Dictionary)["id"]] = true
	var full_profile := _profile(land_all.keys(), [], "home", [], 0)
	var full := _view(_snap(full_profile))
	var full_meshes: int = full.mesh_count()
	var full_places := 0
	for id in land_all.keys():
		if full.place_node(id) != null:
			full_places += 1
	_drop(full)
	print("land_view_test: with the whole land found: %d meshes" % full_meshes)
	if full_places != land_all.size():
		return "with everything found %d of %d places were built" % [full_places, land_all.size()]
	if full_meshes >= 700:
		return "the whole land is %d meshes, expected under 700" % full_meshes
	return ""


func _test_card_stands() -> Variant:
	var yard := _point("yard")
	var cases: Array = [
		["tend_home", NOW + 3600, "sit"],
		["rest", NOW + 3600, "sleep"],
		["explore", NOW + 3600, "happy"],
		["tend_home", NOW - 10, "idle"],
	]
	for row_variant in cases:
		var row: Array = row_variant
		var profile := _profile(DAY3, [], "yard", [_entry(NOW - 3600, "yard", str(row[0]))], int(row[1]))
		var view := _view(_snap(profile))
		view.tick(0.0)
		var card: Node3D = view.card_node()
		var off := _flat(card.position, yard)
		var pose: String = view.card_pose_now()
		var walking: bool = view.card_walking()
		var shown := card.visible
		_drop(view)
		if off > 0.2:
			return "%s: the card is %.2f m from the yard" % [row[0], off]
		if pose != str(row[2]) or walking or not shown:
			return "%s busy until %d: pose '%s' walking %s shown %s, expected '%s'" % [row[0], int(row[1]) - NOW, pose, walking, shown, row[2]]
	var away := _view(_snap(_profile(DAY3, [], "visiting", [_entry(NOW - 3600, "yard", "tend_home")], NOW + 600)))
	away.tick(0.0)
	var hidden: bool = not away.card_node().visible
	var pose_away: String = away.card_pose_now()
	_drop(away)
	if not hidden or pose_away != "":
		return "while visiting the card should be hidden with no pose, got shown=%s pose '%s'" % [not hidden, pose_away]
	return ""


func _test_new_decision() -> Variant:
	var yard := _point("yard")
	var tree := _point("big_tree")
	var first_journal := [_entry(NOW - 3600, "yard", "tend_home")]
	var view := _view(_snap(_profile(DAY3, [], "yard", first_journal, NOW + 600)))
	view.tick(0.0)
	if view.card_walking():
		_drop(view)
		return "it should be standing at the yard to begin with"
	var second_journal := first_journal.duplicate(true)
	second_journal.append(_entry(NOW + 4, "big_tree", "explore"))
	view.set_snapshot(_snap(_profile(DAY3, [], "big_tree", second_journal, NOW + 900), NOW + 5))
	if not view.card_walking() or view.card_pose_now() != "wander":
		var pose: String = view.card_pose_now()
		_drop(view)
		return "a new decision should start a walk, got pose '%s'" % pose
	view.tick(2.0)
	var pos: Vector3 = view.card_node().position
	var from_yard := _flat(pos, yard)
	var to_tree := _flat(pos, tree)
	var span := _flat(yard, tree)
	if from_yard < 1.0 or to_tree < 1.0 or absf(from_yard + to_tree - span) > 0.2:
		_drop(view)
		return "after 2 s it should be between the yard and the tree: %.2f from the yard, %.2f from the tree, span %.2f" % [from_yard, to_tree, span]
	# The desktop's next refresh carries a whole second that is behind the view's
	# clock (NOW + 6 against NOW + 7): the walk must not jump back.
	view.set_snapshot(_snap(_profile(DAY3, [], "big_tree", second_journal, NOW + 900), NOW + 6))
	var refreshed := _flat(view.card_node().position, yard)
	if refreshed < from_yard - 0.001:
		_drop(view)
		return "a refresh moved the walk back from %.2f to %.2f m out of the yard" % [from_yard, refreshed]
	_tick(view, span / LandView.WALK_SPEED + 2.0)
	var arrived := _flat(view.card_node().position, tree)
	var walking: bool = view.card_walking()
	var pose_after: String = view.card_pose_now()
	_drop(view)
	if arrived > 0.2 or walking:
		return "it should have arrived at the tree: %.2f m away, walking %s" % [arrived, walking]
	if pose_after != "happy":
		return "arrived and busy exploring, expected 'happy', got '%s'" % pose_after
	return ""


func _test_roof() -> Variant:
	var home_view := _view(_snap(_profile(DAY3, [], "home", [_entry(NOW - 3600, "home", "rest")], NOW + 600)))
	home_view.tick(0.0)
	var indoors: bool = not home_view.roof_visible()
	_drop(home_view)
	if not indoors:
		return "at home the roof should come off"
	var yard_view := _view(_snap(_profile(DAY3, [], "yard", [_entry(NOW - 3600, "yard", "tend_home")], NOW + 600)))
	yard_view.tick(0.0)
	var roofed: bool = yard_view.roof_visible()
	_drop(yard_view)
	if not roofed:
		return "away from home the roof should be on"
	return ""


func _test_sky() -> Variant:
	var clear := {"cover": 0.0, "rain": 0.0}
	var noon: Dictionary = LandView.sky_at(12.0, clear)
	if float(noon["sun_energy"]) < 0.9 or float(noon["night"]) > 0.01:
		return "noon: %s" % str(noon)
	var midnight: Dictionary = LandView.sky_at(0.0, clear)
	if float(midnight["night"]) < 0.99 or (midnight["sky"] as Color).get_luminance() >= 0.15:
		return "midnight: %s" % str(midnight)
	var dusk: Dictionary = LandView.sky_at(19.5, clear)
	var sun_color: Color = dusk["sun_color"]
	if sun_color.r - sun_color.b <= 0.3:
		return "dusk light should be warm, got %s" % str(sun_color)
	var wet: Dictionary = LandView.sky_at(12.0, {"cover": 1.0, "rain": 0.9})
	if float(wet["sun_energy"]) >= 0.6 * float(noon["sun_energy"]):
		return "rain should dim the sun: %s against %s" % [wet["sun_energy"], noon["sun_energy"]]
	var sun_dir: Vector3 = noon["sun_dir"]
	if sun_dir.y >= 0.0:
		return "the light should travel downward, got %s" % str(sun_dir)
	# In a view: it rains, and the rain shows.
	var profile := _profile(DAY3, [], "home", [_entry(NOW - 3600, "home", "reflect")], NOW + 600)
	var rainy := _snap(profile)
	rainy["weather"] = {"kind": "rain", "day": "wet", "cover": 1.0, "rain": 0.9, "from": NOW, "until": NOW + 10800}
	var view := _view(rainy)
	_tick(view, 30.0)
	var raining: bool = view.rain_emitting()
	_drop(view)
	if not raining:
		return "in rain the rain should be emitting"
	var dry := _snap(profile)
	dry["weather"] = {"kind": "clear", "day": "fair", "cover": 0.0, "rain": 0.0, "from": NOW, "until": NOW + 10800}
	var dry_view := _view(dry)
	_tick(dry_view, 30.0)
	var drizzling: bool = dry_view.rain_emitting()
	_drop(dry_view)
	if drizzling:
		return "in clear weather there should be no rain"
	return ""


func _test_mist_clears() -> Variant:
	# Each spot of land belongs to its nearest place (a found, b a sign, c unknown).
	var pts := {"a": Vector3(0, 0, 0), "b": Vector3(20, 0, 0), "c": Vector3(0, 0, 20)}
	var stages := {"a": "found", "b": "sign"}
	var rule_cases: Array = [
		[Vector3(9, 0, 0), "clear", "nearest a found place, though past CLEAR_RADIUS"],
		[Vector3(12, 0, 0), "thin", "nearest a place it has a sign of"],
		[Vector3(0, 0, 12), "dense", "nearest a place it has not found"],
		[Vector3(-20, 0, 0), "dense", "farther than MIST_NEAR from every place"],
	]
	for rule_variant in rule_cases:
		var rule: Array = rule_variant
		var got: String = LandView.mist_state(rule[0], pts, stages, [])
		if got != str(rule[1]):
			return "%s: expected %s, got %s" % [rule[2], rule[1], got]
	var near_found: String = LandView.mist_state(Vector3(4, 0, 0), {"a": Vector3.ZERO, "z": Vector3(5, 0, 0)}, {"a": "found"}, [])
	if near_found != "clear":
		return "within CLEAR_RADIUS of a found place it should be clear, got %s" % near_found
	var water := _point("water")
	var journal := [_entry(NOW - 3600, "home", "reflect")]
	var before := _view(_snap(_profile(DAY3, [], "home", journal, NOW + 600)))
	var dense: String = before.mist_blob_near(water)
	if dense != "dense":
		_drop(before)
		return "before it is found the mist at the water should be dense, got '%s'" % dense
	if before.place_node("water") != null:
		_drop(before)
		return "the water should not be built before it is found"
	var found := DAY3 + ["water"]
	before.set_snapshot(_snap(_profile(found, [], "home", journal, NOW + 600), NOW + 1))
	_tick(before, 5.0)
	var after: String = before.mist_blob_near(water)
	var built: bool = before.place_node("water") != null
	_drop(before)
	if after != "":
		return "after it is found the mist at the water should be gone, got '%s'" % after
	if not built:
		return "the water should be built once it is found"
	return ""


# --- prototype: the view's own UI ------------------------------------------

func _ui_snap(profile: Dictionary, now: int = NOW, items := false) -> Dictionary:
	var snap := _snap(profile, now)
	snap["prototype_ui"] = true
	snap["prototype_items"] = items
	snap["ui_world"] = LandView.ui_world_from(profile, LandData.LAND)
	return snap


func _land_entry(t: int, place_id: String, activity_id: String, text: String, extra: Dictionary = {}) -> Dictionary:
	var entry := {"t": t, "place_id": place_id, "intent": "explore", "activity_id": activity_id,
		"activity_label": "sat on the step", "text": text, "companion_name": ""}
	for key in extra.keys():
		entry[key] = extra[key]
	return entry


# Off unless switched on; on, it adds no meshes to the land.
func _test_ui_opt_in() -> Variant:
	var land_all := {}
	for place_variant in (LandData.LAND["places"] as Array):
		land_all[(place_variant as Dictionary)["id"]] = true
	var profile := _profile(land_all.keys(), [], "home", [], 0)
	var plain := _view(_snap(profile))
	var plain_meshes: int = plain.mesh_count()
	var plain_ui: Control = plain.ui_root()
	_drop(plain)
	if plain_ui != null:
		return "with no prototype_ui the view should make no UI"
	if plain_meshes != 507:
		return "the whole land without the switches should be 507 meshes, got %d" % plain_meshes
	var with_ui := _view(_ui_snap(profile))
	var ui_meshes: int = with_ui.mesh_count()
	var ui_made: bool = with_ui.ui_root() != null
	with_ui.set_snapshot(_snap(profile, NOW + 1))
	var freed: bool = with_ui.ui_root() == null
	_drop(with_ui)
	if not ui_made:
		return "prototype_ui should make the UI"
	if ui_meshes != plain_meshes:
		return "the UI should add no meshes: %d with it, %d without" % [ui_meshes, plain_meshes]
	if not freed:
		return "switching prototype_ui off should free the UI"
	return ""


# Walking, arrived and busy, asleep, away; and the land's clock and weather.
func _test_ui_status() -> Variant:
	var first := [_entry(NOW - 3600, "yard", "tend_home")]
	var view := _view(_ui_snap(_profile(DAY3, [], "yard", first, NOW + 600)))
	view.tick(0.0)
	var arrived: Array = view.ui_text()["status"]
	if arrived[0] != "Pip is at the yard." or arrived[1] != "Pip is busy there.":
		_drop(view)
		return "standing busy at the yard, got %s" % str(arrived)
	var sky: Array = view.ui_text()["sky"]
	if sky[0] != "21:00" or not str(sky[1]).begins_with("Night, "):
		_drop(view)
		return "the land's clock should read 21:00 at night, got %s" % str(sky)
	var second := first.duplicate(true)
	second.append(_entry(NOW + 4, "big_tree", "explore"))
	view.set_snapshot(_ui_snap(_profile(DAY3, [], "big_tree", second, NOW + 900), NOW + 5))
	view.tick(0.5)
	var walking: Array = view.ui_text()["status"]
	if walking[0] != "Pip is walking to the big tree." or walking[1] != "Pip came from the yard.":
		_drop(view)
		return "on the way to the big tree, got %s" % str(walking)
	_tick(view, _flat(_point("yard"), _point("big_tree")) / LandView.WALK_SPEED + 2.0)
	var there: Array = view.ui_text()["status"]
	_drop(view)
	if there[0] != "Pip is at the big tree.":
		return "after the walk it should be at the big tree, got %s" % str(there)
	var asleep := _view(_ui_snap(_profile(DAY3, [], "home", [_entry(NOW - 3600, "home", "rest")], NOW + 600)))
	asleep.tick(0.0)
	var sleeping: Array = asleep.ui_text()["status"]
	_drop(asleep)
	if sleeping[0] != "Pip is at home." or sleeping[1] != "Pip is asleep.":
		return "asleep at home, got %s" % str(sleeping)
	var away := _view(_ui_snap(_profile(DAY3, [], "visiting", [_entry(NOW - 3600, "yard", "tend_home")], NOW + 600)))
	away.tick(0.0)
	var visiting: Array = away.ui_text()["status"]
	_drop(away)
	if visiting[0] != "Pip is visiting." or visiting[1] != "Pip is away from the land.":
		return "while it visits, got %s" % str(visiting)
	return ""


# Only lines the world wrote reach the UI; a place it has only a sign of is
# never named; things are titled by its own name or its words for them.
func _test_ui_world() -> Variant:
	var journal := [
		_land_entry(NOW - 9000, "yard", "step_sit", "I sat on the step with my feet in the dust."),
		_land_entry(NOW - 8000, "yard", "step_sit", "SECRET letter line", {"read_letters": ["l1"]}),
		_land_entry(NOW - 7000, "yard", "step_sit", "SECRET plan line", {"because": "suggestion"}),
		_land_entry(NOW - 6000, "yard", "step_sit", "SECRET companion line", {"companion_name": "Sam"}),
		_land_entry(NOW - 5000, "visiting", "step_sit", "SECRET visit line"),
		_land_entry(NOW - 4000, "home", "glowing_box", "SECRET glowing box line"),
		_land_entry(NOW - 3000, "yard", "chat_reply", "SECRET unknown line"),
		_land_entry(NOW - 2000, "yard", "edge", "Not far off, something glints.", {"sign_of": "gate"}),
		_land_entry(NOW - 1000, "yard", "step_sit", "SECRET newest line", {"read_letters": ["l2"]}),
	]
	var profile := _profile(DAY3, ["gate"], "yard", journal, 0)
	profile["mind"]["seen"] = {"grey_feather": NOW - 8500}
	profile["mind"]["things"] = {"wren": {"met": 4, "first_t": NOW - 9000, "last_t": NOW - 8000, "name": "the little shouter", "named_t": NOW - 8000}}
	var world := LandView.ui_world_from(profile, LandData.LAND)
	var dumped := JSON.stringify(world)
	if dumped.contains("SECRET"):
		return "a private line reached the UI: %s" % dumped
	var lines: Array = world["journal"]
	if lines.size() != 2 or str((lines[0] as Dictionary)["text"]) != "Not far off, something glints.":
		return "expected the two world lines, newest first, got %s" % str(lines)
	if str(world["last_label"]) != "":
		return "the newest decision is private, so no activity should show, got '%s'" % world["last_label"]
	var gate: Dictionary = (world["place_words"] as Dictionary).get("gate", {})
	if str(gate.get("origin_id", "")) != "yard":
		return "the gate's sign should be from the yard, got %s" % str(gate)
	var feather: Dictionary = (world["item_words"] as Dictionary).get("yard/grey_feather", {})
	if not bool(feather.get("observed", false)) or str(feather.get("text", "")) == "":
		return "the grey feather was seen and should have its line, got %s" % str(feather)
	var wren: Dictionary = (world["item_words"] as Dictionary).get("yard/wren", {})
	if str(wren.get("title", "")) != "the little shouter":
		return "the wren should go by its own name, got %s" % str(wren)
	for key in (world["item_words"] as Dictionary).keys():
		if not DAY3.has(str(key).get_slice("/", 0)):
			return "%s is at a place it has not found" % key
	var view := _view(_ui_snap(profile))
	view.tick(0.0)
	view._ui_open("index")
	var index: Array = view.ui_page_lines()
	view._ui_open("place:gate")
	var sign_title: String = view.ui_text()["title"]
	var sign_page: Array = view.ui_page_lines()
	_drop(view)
	if not index.has("[Something beyond the yard]"):
		return "the index should list the gate as something beyond the yard, got %s" % str(index)
	if sign_title != "Something beyond the yard" or str(index + sign_page).contains("the gate"):
		return "the gate must not be named before it is found: %s / %s" % [sign_title, str(sign_page)]
	return ""


# Wide, standard and compact: every part inside the view, none on another.
func _test_ui_layout() -> Variant:
	var profile := _profile(DAY3, ["gate"], "yard", [_land_entry(NOW - 600, "yard", "step_sit", "I sat on the step.")], NOW + 600)
	for row in [[Vector2(480, 320), "compact"], [Vector2(756, 480), "standard"], [Vector2(1280, 760), "wide"]]:
		var view = LandView.new()
		view.live = false
		view.size = row[0]
		add_child(view)
		view.set_snapshot(_ui_snap(profile))
		view.tick(0.0)
		view._ui_open("index")
		var mode: String = view.ui_text()["mode"]
		var area := Rect2(Vector2.ZERO, row[0])
		var rects := {}
		for part in ["status", "sky", "preview", "bar", "drawer"]:
			var control: Control = view._ui_parts[part]
			if control.visible:
				rects[part] = control.get_rect()
		_drop(view)
		if mode != str(row[1]):
			return "%s should be the %s layout, got %s" % [str(row[0]), row[1], mode]
		for part in rects.keys():
			var rect: Rect2 = rects[part]
			if not area.grow(0.5).encloses(rect):
				return "%s: the %s %s is outside the view" % [mode, part, str(rect)]
		var names: Array = rects.keys()
		for i in range(names.size()):
			for j in range(i + 1, names.size()):
				var a: Rect2 = rects[names[i]]
				var b: Rect2 = rects[names[j]]
				if a.grow(-0.5).intersects(b.grow(-0.5)):
					return "%s: the %s and the %s overlap (%s, %s)" % [mode, names[i], names[j], str(a), str(b)]
	return ""


# A click on a thing opens its page; one in the empty sky opens nothing.
func _test_ui_pick() -> Variant:
	var profile := _profile(DAY3, [], "yard", [_entry(NOW - 3600, "yard", "tend_home")], NOW + 600)
	profile["mind"]["seen"] = {"grey_feather": NOW - 3000}
	var view := _view(_ui_snap(profile, NOW, true))
	view.size = Vector2(1280, 760)
	view.tick(0.0)
	var target: Node3D = null
	for entry in view._item_nodes:
		if str(entry.place) == "yard" and str(entry.id) == "grey_feather":
			target = entry.node
	if target == null:
		_drop(view)
		return "the grey feather should be at the yard"
	var camera: Camera3D = view._camera
	var centre: Vector3 = view._world_bounds(target).get_center()
	camera.look_at_from_position(centre + Vector3(0.0, 3.0, 2.5), centre, Vector3.UP)
	var at := camera.unproject_position(centre)
	var picked: Dictionary = view._ui_pick(at)
	camera.look_at_from_position(centre + Vector3(0.0, 2.0, 0.0), centre + Vector3(0.0, 12.0, -6.0), Vector3.UP)
	var sky: Dictionary = view._ui_pick(Vector2(640, 380))
	camera.look_at_from_position(centre + Vector3(0.0, 3.0, 2.5), centre, Vector3.UP)
	view._ui_click(at)
	var page: String = view.ui_text()["page"]
	var title: String = view.ui_text()["title"]
	_drop(view)
	if str(picked.get("key", "")) != "yard/grey_feather":
		return "a click on the feather should pick it, got %s" % str(picked)
	if not sky.is_empty():
		return "a click in the empty sky should pick nothing, got %s" % str(sky)
	if page != "item:yard/grey_feather" or title != "Something Pip noticed":
		return "the click should open the feather's page, got page '%s' title '%s'" % [page, title]
	return ""
