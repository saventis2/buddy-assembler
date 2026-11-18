extends Node

# The house and land of a buddy that starts small (Plan 14 step 1b): the land's
# data, what the buddy knows, how it finds the rest, and how a month on the
# land reads. Cases 13 to 15 are tuning bands: their numbers are printed so the
# land can be tuned against them.

const LifeSim = preload("res://tests/life_sim.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")
const MindService = preload("res://scripts/services/mind_service.gd")
const LandData = preload("res://scripts/services/land_data.gd")

const NEEDS := ["energy", "comfort", "curiosity", "reflection"]
const MONTH_SEEDS := [21, 22, 23]
const TINY_LAND := {
	"home_place": "home",
	"paths": [["home", "pool"]],
	"tails": {"good": ["Good."], "bad": ["Bad."]},
	"places": [
		{"id": "home", "name": "the house", "opens": 0, "closes": 24, "distance": 0, "residents": [],
			"activities": [
				{"id": "sleep", "label": "went to bed", "satisfies": "energy", "until_hour": 6, "hours": [19, 5], "lines": ["I slept."]},
				{"id": "nap", "label": "had a nap", "satisfies": "energy", "minutes": 40, "hours": [5, 19], "lines": ["I napped."]},
				{"id": "tidy", "label": "tidied up", "satisfies": "comfort", "lines": ["I tidied.", "I tidied again."]},
				{"id": "think", "label": "sat and thought", "satisfies": "reflection", "lines": ["I thought."]},
				{"id": "look", "label": "looked about", "satisfies": "curiosity", "first": "I looked about for the first time.", "lines": ["I looked about.", "I looked about once more."]},
			],
			"sights": [{"id": "spot", "line": "There is a spot on the wall."}]},
		{"id": "pool", "name": "the pool", "opens": 0, "closes": 24, "distance": 2, "residents": [],
			"discover": {"from": ["home"], "sign": "I heard water.", "chance": 1.0, "blocked": ["Not yet."], "found": "I found the pool.", "wonder": ["I wonder about that water."]},
			"activities": [{"id": "paddle", "label": "paddled", "satisfies": "curiosity", "minutes": 30, "lines": ["I paddled."]}],
			"sights": []},
	],
}

var _failed := 0
var _ran := 0
var _month_cache: Array = []


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("land_life_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("land_life_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("land_is_well_formed", func(): return _test_land_is_well_formed())
	_case("starts_with_only_the_house", func(): return _test_starts_with_only_the_house())
	_case("the_old_town_is_unchanged", func(): return _test_the_old_town_is_unchanged())
	_case("known_filter_hides_the_unfound", func(): return _test_known_filter_hides_the_unfound())
	_case("a_sign_then_a_find", func(): return _test_a_sign_then_a_find())
	_case("a_failed_try_is_still_an_event", func(): return _test_a_failed_try_is_still_an_event())
	_case("what_it_does_takes_time", func(): return _test_what_it_does_takes_time())
	_case("hours_gate_what_it_does", func(): return _test_hours_gate_what_it_does())
	_case("first_time_lines_come_once", func(): return _test_first_time_lines_come_once())
	_case("things_are_noticed_once", func(): return _test_things_are_noticed_once())
	_case("own_seed_changes_the_life", func(): return _test_own_seed_changes_the_life())
	_case("same_seed_same_land_life", func(): return _test_same_seed_same_land_life())
	_case("a_month_on_the_land", func(): return _test_a_month_on_the_land())
	_case("no_need_is_pinned", func(): return _test_no_need_is_pinned())
	_case("it_sleeps_at_night", func(): return _test_it_sleeps_at_night())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("land_life_test[%s]: %s" % [name, err])
	else:
		print("land_life_test[%s]: ok" % name)


# --- helpers -------------------------------------------------------------

func _base_profile(seed_value: int = 1) -> Dictionary:
	return {
		"personality_seed": seed_value,
		"personality_seed_tag": "curious",
		"mood_modifiers": {"energy_strain": 0.2, "social_fulfillment": 0.0, "comfort": 0.5, "confidence": 0.5},
	}


func _start() -> int:
	return LifeSim.DEFAULT_START_UNIX + 9 * 3600


func _new_service() -> MindService:
	var svc := MindService.new()
	svc.set_time_zone_bias_minutes(0)
	return svc


func _context_at(t: int) -> Dictionary:
	var hour: int = int(Time.get_datetime_dict_from_unix_time(t).get("hour", 0))
	return {"small_beginnings": true, "plans": true, "hour": hour, "is_night": hour < 7 or hour >= 22}


# Lives the buddy on `land` from `start_unix` until `decisions` events have
# happened. The journal only keeps 40 entries, so this collects the events the
# ticks return, and the profile as it stood after each one ("profiles").
func _live(svc: MindService, profile: Dictionary, land: Dictionary, start_unix: int, decisions: int) -> Dictionary:
	var events: Array = []
	var profiles: Array = []
	var current: Dictionary = profile
	var t: int = start_unix
	for _loop in range(5000):
		var result: Dictionary = svc.tick(current, [], t, _context_at(t), land)
		current = result["profile"]
		for event_variant in result["events"]:
			events.append(event_variant)
			profiles.append(current.duplicate(true))
		var busy_until: int = int((current["mind"] as Dictionary).get("busy_until", 0))
		t = busy_until if busy_until > t else t + 600
		if events.size() >= decisions:
			break
	return {"profile": current, "events": events, "profiles": profiles}


func _hour_of(t: int) -> int:
	return int(Time.get_datetime_dict_from_unix_time(t).get("hour", 0))


func _setup_sim(small: bool) -> void:
	AppState.begin_simulation(2, LifeSim.DEFAULT_START_UNIX)
	var loaded: Dictionary = ContentLoader.load_with_fallback("core_pack", "", false)
	AppState.apply_loaded_pack(str(loaded.get("pack_id", "core_pack")), loaded.get("manifest", {}))
	AppState.settings["smallBeginnings"] = small


func _month_reports() -> Array:
	if _month_cache.is_empty():
		for seed_value in MONTH_SEEDS:
			_month_cache.append(LifeSim.run(AppState, {"days": 30, "seed": seed_value, "small_beginnings": true}))
	return _month_cache


# --- 1: the land's data ---------------------------------------------------

func _hours_error(hours_variant: Variant) -> String:
	if typeof(hours_variant) != TYPE_ARRAY or (hours_variant as Array).size() != 2:
		return "hours is not two numbers"
	var from_hour: Variant = (hours_variant as Array)[0]
	var to_hour: Variant = (hours_variant as Array)[1]
	if typeof(from_hour) not in [TYPE_INT, TYPE_FLOAT] or typeof(to_hour) not in [TYPE_INT, TYPE_FLOAT]:
		return "hours is not two numbers"
	if int(from_hour) != float(from_hour) or int(to_hour) != float(to_hour):
		return "hours is not two whole numbers"
	if int(from_hour) < 0 or int(from_hour) > 24 or int(to_hour) < 0 or int(to_hour) > 24:
		return "hours is outside 0..24"
	if int(from_hour) == int(to_hour):
		return "hours starts and ends at the same hour"
	return ""


func _line_error(line_variant: Variant, you_pattern: RegEx) -> String:
	if typeof(line_variant) != TYPE_STRING:
		return "is not a string"
	var line: String = str(line_variant)
	if line.length() < 1 or line.length() > 200:
		return "is %d characters (1..200)" % line.length()
	var first: String = line.substr(0, 1)
	if first != first.to_upper() or first == first.to_lower():
		return "does not start with an upper-case letter"
	if not [".", "!", "?"].has(line.substr(line.length() - 1, 1)):
		return "does not end with . ! or ?"
	if you_pattern.search(line) != null:
		return "speaks to the person (you/your/yours/you're)"
	return ""


# A String, or a Dictionary of strings, as lines.
func _text_lines(value: Variant) -> Array:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).values()
	return [value]


func _test_land_is_well_formed() -> Variant:
	var land: Dictionary = LandData.LAND.duplicate(true)
	var svc := _new_service()
	var you_pattern := RegEx.new()
	you_pattern.compile("(?i)\\byou(?:'re|rs|r)?\\b")
	var places: Array = land.get("places", [])
	if places.is_empty():
		return "the land has no places"
	var home_id: String = str(land.get("home_place", ""))
	if str((places[0] as Dictionary).get("id", "")) != home_id:
		return "the first place is not home_place"
	var waking_problem := _line_error(land.get("waking", null), you_pattern)
	if waking_problem != "":
		return "the waking line %s" % waking_problem
	var place_ids := {}
	var activity_ids := {}
	var sight_ids := {}
	for place_variant in places:
		var place: Dictionary = place_variant
		var place_id: String = str(place.get("id", ""))
		if place_ids.has(place_id):
			return "place %s: id is not unique" % place_id
		place_ids[place_id] = true
	for place_variant in places:
		var place: Dictionary = place_variant
		var place_id: String = str(place.get("id", ""))
		if str(place.get("name", "")).strip_edges() == "":
			return "place %s: name is empty" % place_id
		var map_variant: Variant = place.get("map", null)
		if typeof(map_variant) != TYPE_ARRAY or (map_variant as Array).size() != 2:
			return "place %s: map is not two numbers" % place_id
		for coordinate in map_variant:
			if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or float(coordinate) < 0.0 or float(coordinate) > 1.0:
				return "place %s: map is outside 0..1" % place_id
		var opens: int = int(place.get("opens", -1))
		var closes: int = int(place.get("closes", -1))
		if not (0 <= opens and opens < closes and closes <= 24):
			return "place %s: opens/closes is not 0 <= opens < closes <= 24" % place_id
		if float(place.get("distance", -1)) < 0.0:
			return "place %s: distance is below 0" % place_id
		var activities: Array = place.get("activities", [])
		if activities.is_empty():
			return "place %s: has no activities" % place_id
		for activity_variant in activities:
			var activity: Dictionary = activity_variant
			var activity_id: String = str(activity.get("id", ""))
			var where := "place %s activity %s" % [place_id, activity_id]
			if activity_id == "" or activity_ids.has(activity_id):
				return "%s: id is empty or not unique across the land" % where
			if ["edge", "arrive", "wake"].has(activity_id):
				return "%s: id is reserved" % where
			if activity.has("until_hour"):
				var until_hour: Variant = activity["until_hour"]
				if typeof(until_hour) != TYPE_INT or int(until_hour) < 0 or int(until_hour) > 23:
					return "%s: until_hour is not a whole hour 0..23" % where
			activity_ids[activity_id] = true
			if str(activity.get("label", "")).strip_edges() == "":
				return "%s: label is empty" % where
			if not NEEDS.has(str(activity.get("satisfies", ""))):
				return "%s: satisfies is not one of energy, comfort, curiosity, reflection" % where
			var lines_variant: Variant = activity.get("lines", null)
			if typeof(lines_variant) != TYPE_ARRAY or (lines_variant as Array).size() < 2:
				return "%s: needs at least 2 lines" % where
			if activity.has("minutes"):
				var minutes: float = float(activity["minutes"])
				if minutes < 10.0 or minutes > 240.0:
					return "%s: minutes is outside 10..240" % where
			if activity.has("hours"):
				var hours_problem := _hours_error(activity["hours"])
				if hours_problem != "":
					return "%s: %s" % [where, hours_problem]
			var written: Array = []
			if activity.has("first"):
				written.append(activity["first"])
			written.append_array(lines_variant)
			if activity.has("bad"):
				written.append_array(activity["bad"])
			for line_variant in written:
				var line_problem := _line_error(line_variant, you_pattern)
				if line_problem != "":
					return "%s: line '%s' %s" % [where, str(line_variant), line_problem]
		var sights: Array = place.get("sights", [])
		for sight_variant in sights:
			var sight: Dictionary = sight_variant
			var sight_id: String = str(sight.get("id", ""))
			var sight_where := "place %s sight %s" % [place_id, sight_id]
			if sight_id == "" or sight_ids.has(sight_id):
				return "%s: id is empty or not unique across the land" % sight_where
			sight_ids[sight_id] = true
			if str(sight.get("line", "")).strip_edges() == "":
				return "%s: line is empty" % sight_where
			var sight_line_problem := _line_error(sight["line"], you_pattern)
			if sight_line_problem != "":
				return "%s: line '%s' %s" % [sight_where, str(sight["line"]), sight_line_problem]
			if sight.has("hours"):
				var sight_hours_problem := _hours_error(sight["hours"])
				if sight_hours_problem != "":
					return "%s: %s" % [sight_where, sight_hours_problem]
		if place_id == home_id:
			continue
		var discover_variant: Variant = place.get("discover", null)
		if typeof(discover_variant) != TYPE_DICTIONARY:
			return "place %s: has no discover" % place_id
		var discover: Dictionary = discover_variant
		var discover_where := "place %s discover" % place_id
		var from_variant: Variant = discover.get("from", null)
		if typeof(from_variant) != TYPE_ARRAY or (from_variant as Array).is_empty():
			return "%s: from is empty" % discover_where
		for from_id in from_variant:
			if not place_ids.has(str(from_id)) or str(from_id) == place_id:
				return "%s: from '%s' is not another place" % [discover_where, str(from_id)]
		var chance: float = float(discover.get("chance", 0.0))
		if chance <= 0.0 or chance > 1.0:
			return "%s: chance is not above 0 and at most 1" % discover_where
		var found_variant: Variant = discover.get("found", "")
		if typeof(found_variant) == TYPE_DICTIONARY:
			for from_id in from_variant:
				if str((found_variant as Dictionary).get(str(from_id), "")).strip_edges() == "":
					return "%s: found has no line for %s" % [discover_where, str(from_id)]
		elif typeof(found_variant) != TYPE_STRING or str(found_variant).strip_edges() == "":
			return "%s: found is empty" % discover_where
		var sign_variant: Variant = discover.get("sign", null)
		if typeof(sign_variant) == TYPE_DICTIONARY:
			for from_id in from_variant:
				if str((sign_variant as Dictionary).get(str(from_id), "")).strip_edges() == "":
					return "%s: sign has no line for %s" % [discover_where, str(from_id)]
		elif typeof(sign_variant) != TYPE_STRING:
			return "%s: sign is not a string or a dictionary" % discover_where
		var blocked_variant: Variant = discover.get("blocked", [])
		var wonder_variant: Variant = discover.get("wonder", null)
		if typeof(blocked_variant) != TYPE_ARRAY:
			return "%s: blocked is not an array" % discover_where
		if typeof(wonder_variant) != TYPE_ARRAY:
			return "%s: wonder is not an array" % discover_where
		if chance < 1.0 and ((blocked_variant as Array).is_empty() or (wonder_variant as Array).is_empty()):
			return "%s: chance is below 1 but blocked or wonder is empty" % discover_where
		var discover_lines: Array = []
		# A sign of "" means the place has no sign stage.
		if not (typeof(sign_variant) == TYPE_STRING and str(sign_variant) == ""):
			discover_lines.append_array(_text_lines(sign_variant))
		discover_lines.append_array(_text_lines(found_variant))
		discover_lines.append_array(blocked_variant)
		discover_lines.append_array(wonder_variant)
		for discover_line in discover_lines:
			var discover_problem := _line_error(discover_line, you_pattern)
			if discover_problem != "":
				return "%s: line '%s' %s" % [discover_where, str(discover_line), discover_problem]
	var tails: Dictionary = land.get("tails", {})
	for tail_key in ["good", "bad"]:
		var tail_lines: Variant = tails.get(tail_key, null)
		if typeof(tail_lines) != TYPE_ARRAY or (tail_lines as Array).is_empty():
			return "tails %s is empty" % tail_key
		for tail_line in tail_lines:
			var tail_problem := _line_error(tail_line, you_pattern)
			if tail_problem != "":
				return "tails %s: line '%s' %s" % [tail_key, str(tail_line), tail_problem]
	# Everything can be reached by starting from home.
	var reached := {home_id: true}
	var grew := true
	while grew:
		grew = false
		for place_variant in places:
			var place: Dictionary = place_variant
			var place_id: String = str(place.get("id", ""))
			if reached.has(place_id) or not place.has("discover"):
				continue
			for from_id in (place["discover"] as Dictionary).get("from", []):
				if reached.has(str(from_id)):
					reached[place_id] = true
					grew = true
					break
	for place_id in place_ids.keys():
		if not reached.has(place_id):
			return "place %s cannot be reached from home" % place_id
	# Home always has something for each need.
	var home: Dictionary = places[0]
	for hour in range(24):
		for need in NEEDS:
			var offered := false
			for activity_variant in home["activities"]:
				var activity: Dictionary = activity_variant
				if str(activity.get("satisfies", "")) == need and svc._hour_fits(activity.get("hours", null), hour):
					offered = true
			if not offered:
				return "home offers nothing for %s at hour %d" % [need, hour]
	for path_variant in land.get("paths", []):
		if typeof(path_variant) != TYPE_ARRAY or (path_variant as Array).size() != 2:
			return "a path is not two place ids"
		for path_id in path_variant:
			if not place_ids.has(str(path_id)):
				return "path names a place that does not exist: %s" % str(path_id)
	return null


# --- 2, 3: the world, behind the setting -----------------------------------

func _test_starts_with_only_the_house() -> Variant:
	_setup_sim(true)
	var start: int = LifeSim.DEFAULT_START_UNIX
	if not AppState.small_beginnings():
		return "small_beginnings() is false with the setting on"
	var places: Array = AppState.get_town().get("places", [])
	if places.size() != 1 or str((places[0] as Dictionary).get("id", "")) != "home":
		return "the town it knows should be exactly the house, got %d places" % places.size()
	if not AppState._world_npcs().is_empty():
		return "someone else lives on the land"
	if not AppState.tick_world_events(start).is_empty():
		return "a quest or encounter came up on the land"
	var positions: Dictionary = AppState.get_town_map().get("positions", {})
	if positions.size() != 1:
		return "the map shows %d places, expected 1" % positions.size()
	return null


func _test_the_old_town_is_unchanged() -> Variant:
	_setup_sim(false)
	if AppState.small_beginnings():
		return "small_beginnings() is true with the setting off"
	var places: Array = AppState.get_town().get("places", [])
	if places.size() != 8:
		return "the old town has %d places, expected 8" % places.size()
	if AppState._world_npcs().size() != 6:
		return "the old town has %d townspeople, expected 6" % AppState._world_npcs().size()
	return null


# --- 4: what it knows -------------------------------------------------------

func _test_known_filter_hides_the_unfound() -> Variant:
	var svc := _new_service()
	var profile := _base_profile()
	var town: Dictionary = svc.known_town(profile, TINY_LAND.duplicate(true))
	var places: Array = town.get("places", [])
	if places.size() != 1 or str((places[0] as Dictionary).get("id", "")) != "home":
		return "an unfound pool is in the known town"
	if not (town.get("paths", []) as Array).is_empty():
		return "a path to the unfound pool is in the known town"
	if not svc.find_target("let's go to the pool", town, []).is_empty():
		return "it can be sent to a place it has not found"
	profile["mind"] = {"known_places": {"pool": {"stage": "found", "t": 1, "tries": 0}}}
	town = svc.known_town(profile, TINY_LAND.duplicate(true))
	if (town.get("places", []) as Array).size() != 2:
		return "a found pool is missing from the known town"
	if (town.get("paths", []) as Array).size() != 1:
		return "the path to a found pool is missing"
	var target: Dictionary = svc.find_target("let's go to the pool", town, [])
	if str(target.get("id", "")) != "pool":
		return "it cannot be sent to a place it has found"
	return null


# --- 5, 6: finding places ---------------------------------------------------

func _test_a_sign_then_a_find() -> Variant:
	var svc := _new_service()
	var lived := _live(svc, _base_profile(), TINY_LAND.duplicate(true), _start(), 200)
	var signs := 0
	var sign_index := -1
	var found_index := -1
	var events: Array = lived["events"]
	for index in range(events.size()):
		var event: Dictionary = events[index]
		if str(event.get("sign_of", "")) == "pool":
			signs += 1
			sign_index = index
			if str(event["text"]) != "I heard water." or str(event["place_id"]) != "home":
				return "the sign reads '%s' at %s" % [str(event["text"]), str(event["place_id"])]
		if str(event.get("found_place", "")) == "pool":
			if found_index != -1:
				return "the pool was found twice"
			found_index = index
			if str(event["text"]) != "I found the pool." or str(event["place_id"]) != "pool":
				return "the find reads '%s' at %s" % [str(event["text"]), str(event["place_id"])]
	if signs != 1:
		return "expected exactly one sign of the pool, got %d" % signs
	if found_index == -1:
		return "the pool was never found in %d events" % events.size()
	if found_index < sign_index:
		return "the pool was found before its sign"
	for index in range(found_index):
		if str((events[index] as Dictionary).get("activity_id", "")) == "paddle":
			return "it paddled in the pool before finding it"
	return null


func _test_a_failed_try_is_still_an_event() -> Variant:
	var land: Dictionary = TINY_LAND.duplicate(true)
	var pool: Dictionary = (land["places"] as Array)[1]
	pool["discover"]["sign"] = ""
	pool["discover"]["chance"] = 0.0001
	var svc := _new_service()
	var lived := _live(svc, _base_profile(), land, _start(), 300)
	var events: Array = lived["events"]
	var profiles: Array = lived["profiles"]
	var blocked := 0
	var found_index := -1
	var last_blocked_index := -1
	var last_blocked_day := -1
	for index in range(events.size()):
		var event: Dictionary = events[index]
		if str(event.get("blocked_at", "")) == "pool":
			blocked += 1
			last_blocked_index = index
			if str(event["text"]) != "Not yet." or str(event["place_id"]) != "home":
				return "a failed try reads '%s' at %s" % [str(event["text"]), str(event["place_id"])]
			# After a failure it leaves the place for another day.
			var day: int = int(int(event["t"]) / 86400)
			if day == last_blocked_day:
				return "it tried the pool twice in one day after failing"
			last_blocked_day = day
			if blocked == 1:
				var stage: String = str((((profiles[index] as Dictionary)["mind"] as Dictionary)["known_places"] as Dictionary).get("pool", {}).get("stage", ""))
				if stage != "sign":
					return "after a failed try the pool's stage is '%s', expected sign" % stage
		if str(event.get("found_place", "")) == "pool" and found_index == -1:
			found_index = index
	# The pool is nearly out of reach here, so most days end in a failed try;
	# each one makes the next a little more likely.
	if blocked < 2:
		return "expected at least 2 failed tries in %d events, got %d" % [events.size(), blocked]
	if found_index != -1 and last_blocked_index > found_index:
		return "a failed try came after the find"
	return null


# --- 7, 8: time and hours ---------------------------------------------------

func _test_what_it_does_takes_time() -> Variant:
	var svc := _new_service()
	var start: int = _start()
	var land: Dictionary = TINY_LAND.duplicate(true)
	var first: Dictionary = svc.tick(_base_profile(), [], start, _context_at(start), land)
	if (first["events"] as Array).size() != 1:
		return "the first tick made %d events" % (first["events"] as Array).size()
	var busy_until: int = int((first["profile"]["mind"] as Dictionary).get("busy_until", 0))
	if busy_until <= start:
		return "it was not busy after deciding (busy_until %d)" % busy_until
	var early: Dictionary = svc.tick(first["profile"], [], busy_until - 1, _context_at(busy_until - 1), land)
	if not (early["events"] as Array).is_empty():
		return "it decided something while still busy"
	var later: Dictionary = svc.tick(first["profile"], [], busy_until, _context_at(busy_until), land)
	if (later["events"] as Array).size() != 1:
		return "it made %d events when it was free again" % (later["events"] as Array).size()
	var tired := _base_profile()
	tired["mood_modifiers"]["energy_strain"] = 0.8
	var night: int = LifeSim.DEFAULT_START_UNIX + 22 * 3600
	var slept: Dictionary = svc.tick(tired, [], night, {"small_beginnings": true, "plans": true, "hour": 22, "is_night": true}, land)
	var events: Array = slept["events"]
	if events.size() != 1 or str((events[0] as Dictionary).get("activity_id", "")) != "sleep":
		return "a tired buddy at 22:00 did not go to bed"
	var slept_for: int = int((slept["profile"]["mind"] as Dictionary).get("busy_until", 0)) - night
	if slept_for < 5 * 3600 or slept_for > 11 * 3600:
		return "it slept for %d seconds, expected 5 to 11 hours" % slept_for
	var rested: float = float(slept["profile"]["mood_modifiers"]["energy_strain"])
	if not is_equal_approx(rested, MindService.LAND_RESTED):
		return "energy_strain after sleeping is %s, expected %s" % [str(rested), str(MindService.LAND_RESTED)]
	return null


func _test_hours_gate_what_it_does() -> Variant:
	var svc := _new_service()
	var land: Dictionary = TINY_LAND.duplicate(true)
	var worn := _base_profile()
	worn["mood_modifiers"]["energy_strain"] = 0.95
	var noon: int = LifeSim.DEFAULT_START_UNIX + 12 * 3600
	var by_day: Dictionary = svc.tick(worn, [], noon, {"small_beginnings": true, "plans": true, "hour": 12, "is_night": false}, land)
	var day_events: Array = by_day["events"]
	if day_events.size() != 1 or str((day_events[0] as Dictionary).get("activity_id", "")) != "nap":
		return "a worn out buddy at noon did not nap"
	var late: int = LifeSim.DEFAULT_START_UNIX + 23 * 3600
	var by_night: Dictionary = svc.tick(worn, [], late, {"small_beginnings": true, "plans": true, "hour": 23, "is_night": true}, land)
	var night_events: Array = by_night["events"]
	if night_events.size() != 1 or str((night_events[0] as Dictionary).get("activity_id", "")) != "sleep":
		return "a worn out buddy at 23:00 did not go to bed"
	var lived := _live(_new_service(), _base_profile(), land, _start(), 150)
	for event_variant in lived["events"]:
		var event: Dictionary = event_variant
		var hour := _hour_of(int(event["t"]))
		if str(event.get("activity_id", "")) == "sleep" and hour >= 8 and hour <= 18:
			return "it went to bed at %d:00" % hour
	return null


# --- 9, 10: noticing --------------------------------------------------------

func _test_first_time_lines_come_once() -> Variant:
	var lived := _live(_new_service(), _base_profile(), TINY_LAND.duplicate(true), _start(), 400)
	var first_line := "I looked about for the first time."
	var looks := 0
	for event_variant in lived["events"]:
		var event: Dictionary = event_variant
		if str(event.get("activity_id", "")) != "look":
			continue
		looks += 1
		if looks == 1 and not str(event["text"]).begins_with(first_line):
			return "the first look reads '%s'" % str(event["text"])
		if looks > 1 and str(event["text"]).begins_with(first_line):
			return "look number %d repeated the first-time line" % looks
	if looks < 3:
		return "it only looked about %d times in 400 events" % looks
	return null


func _test_things_are_noticed_once() -> Variant:
	var lived := _live(_new_service(), _base_profile(), TINY_LAND.duplicate(true), _start(), 300)
	var noticed := 0
	for event_variant in lived["events"]:
		var event: Dictionary = event_variant
		if str(event.get("sight", "")) == "spot":
			noticed += 1
			if not str(event["text"]).ends_with("There is a spot on the wall."):
				return "the sight line is not at the end: '%s'" % str(event["text"])
	if noticed != 1:
		return "the spot was noticed %d times, expected once" % noticed
	if not ((lived["profile"]["mind"] as Dictionary)["seen"] as Dictionary).has("spot"):
		return "mind.seen does not have the spot"
	return null


# --- 11, 12: its own life ---------------------------------------------------

func _life_signature(seed_value: int) -> String:
	var lived := _live(_new_service(), _base_profile(seed_value), LandData.LAND.duplicate(true), _start(), 40)
	var rows: Array = []
	for event_variant in lived["events"]:
		var event: Dictionary = event_variant
		rows.append([str(event.get("activity_id", "")), str(event.get("text", ""))])
	return JSON.stringify(rows, "", true)


func _test_own_seed_changes_the_life() -> Variant:
	if _life_signature(1) == _life_signature(2):
		return "buddies with seeds 1 and 2 lived the same life"
	if _life_signature(1) != _life_signature(1):
		return "the same buddy lived two different lives"
	return null


func _test_same_seed_same_land_life() -> Variant:
	var first: Dictionary = LifeSim.run(AppState, {"days": 3, "seed": 31, "small_beginnings": true})
	var second: Dictionary = LifeSim.run(AppState, {"days": 3, "seed": 31, "small_beginnings": true})
	if first.has("error") or second.has("error"):
		return "run failed"
	if (first["rows"] as Array).is_empty():
		return "no journal rows"
	if JSON.stringify(first["rows"], "", true) != JSON.stringify(second["rows"], "", true):
		return "rows differ between two runs of the same seed"
	if JSON.stringify(first["days"], "", true) != JSON.stringify(second["days"], "", true):
		return "days differ between two runs of the same seed"
	return null


# --- 13 to 15: a month on the land (tuning bands) ------------------------------

func _firsts_by_day(report: Dictionary, last_day: int) -> int:
	var count := 0
	var days: Array = report["days"]
	for index in range(mini(last_day, days.size())):
		for first_variant in (days[index] as Dictionary)["firsts"]:
			if str((first_variant as Dictionary).get("kind", "")) == "place":
				count += 1
	return count


func _first_days(report: Dictionary) -> int:
	var count := 0
	for day_variant in report["days"]:
		for first_variant in (day_variant as Dictionary)["firsts"]:
			if ["place", "sign", "sight", "activity"].has(str((first_variant as Dictionary).get("kind", ""))):
				count += 1
				break
	return count


func _need_text(totals: Dictionary, key: String) -> String:
	var row: Dictionary = (totals["needs"] as Dictionary)[key]
	return "%s..%s (%s)" % [str(row["min"]), str(row["max"]), str(row["at_limit_share"])]


func _test_a_month_on_the_land() -> Variant:
	var reports := _month_reports()
	for index in range(reports.size()):
		var report: Dictionary = reports[index]
		if report.has("error"):
			return "run failed: " + str(report["error"])
		var totals: Dictionary = report["totals"]
		var found: int = ((report["final"] as Dictionary)["known_places"]["found"] as Array).size()
		print("land_life_test: month seed %d found %d by_day1 %d by_day7 %d first_days %d top10 %s signs %d sights %d blocked %d night_rows %d strain %s comfort %s confidence %s" % [
			int(MONTH_SEEDS[index]), found, _firsts_by_day(report, 1), _firsts_by_day(report, 7), _first_days(report),
			str(totals["top10_share"]), int(totals["signs"]), int(totals["sights"]), int(totals["blocked_tries"]), int(totals["night_rows"]),
			_need_text(totals, "energy_strain"), _need_text(totals, "comfort"), _need_text(totals, "confidence")])
	for index in range(reports.size()):
		var report: Dictionary = reports[index]
		var totals: Dictionary = report["totals"]
		var seed_value: int = int(MONTH_SEEDS[index])
		var found: int = ((report["final"] as Dictionary)["known_places"]["found"] as Array).size()
		# Observed over seeds 1-5 and 21-23 when tuned (2026-11): all 13 places
		# found, the last on day 8 to 12; 3 to 6 on day 1; 10 to 12 by day 7;
		# 13 to 19 failed tries; something new on 26 to 29 days; the ten most
		# common lines 6.5% to 7.8% of the journal.
		if found < 11:
			return "seed %d found %d places, expected at least 11" % [seed_value, found]
		var day_one: int = _firsts_by_day(report, 1)
		if day_one < 2 or day_one > 7:
			return "seed %d found %d places on day 1, expected 2 to 7" % [seed_value, day_one]
		if _firsts_by_day(report, 7) < 8:
			return "seed %d found %d places by day 7, expected at least 8" % [seed_value, _firsts_by_day(report, 7)]
		if int(totals["blocked_tries"]) < 6:
			return "seed %d had %d failed tries, expected at least 6" % [seed_value, int(totals["blocked_tries"])]
		if _first_days(report) < 22:
			return "seed %d had something new on %d days, expected at least 22" % [seed_value, _first_days(report)]
		if float(totals["top10_share"]) >= 0.15:
			return "seed %d: the ten most common lines cover %s of the journal" % [seed_value, str(totals["top10_share"])]
		if int(totals["companions_met"]) != 0:
			return "seed %d met %d companions on a land nobody else lives on" % [seed_value, int(totals["companions_met"])]
		if (totals["intents"] as Dictionary).has("visit"):
			return "seed %d chose to visit someone" % seed_value
	return null


func _test_no_need_is_pinned() -> Variant:
	var reports := _month_reports()
	for index in range(reports.size()):
		var report: Dictionary = reports[index]
		if report.has("error"):
			return "run failed: " + str(report["error"])
		for key in ["energy_strain", "comfort", "confidence"]:
			var row: Dictionary = ((report["totals"] as Dictionary)["needs"] as Dictionary)[key]
			if float(row["at_limit_share"]) >= 0.15:
				return "seed %d: %s sat at a limit %s of the time" % [int(MONTH_SEEDS[index]), key, str(row["at_limit_share"])]
			# Observed when tuned: tiredness 0..0.72, comfort 0.39..1, confidence 0.13..1.
			if float(row["max"]) - float(row["min"]) < 0.3:
				return "seed %d: %s only moved %s..%s" % [int(MONTH_SEEDS[index]), key, str(row["min"]), str(row["max"])]
	return null


func _test_it_sleeps_at_night() -> Variant:
	var reports := _month_reports()
	for index in range(reports.size()):
		var report: Dictionary = reports[index]
		if report.has("error"):
			return "run failed: " + str(report["error"])
		# Observed when tuned: 7 to 13 rows before 05:00, all on the first
		# night (it wakes at midnight in a house it does not know), and 31
		# sleeps in 30 days.
		var night_rows: int = int((report["totals"] as Dictionary)["night_rows"])
		if night_rows > 30:
			return "seed %d had %d journal rows between midnight and 5, expected at most 30" % [int(MONTH_SEEDS[index]), night_rows]
		var sleeps := 0
		for row_variant in report["rows"]:
			if str((row_variant as Dictionary).get("activity_id", "")) == "sleep":
				sleeps += 1
		if sleeps < 28 or sleeps > 34:
			return "seed %d went to bed %d times in 30 days, expected 28 to 34" % [int(MONTH_SEEDS[index]), sleeps]
	return null
