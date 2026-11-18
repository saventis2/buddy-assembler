extends Node

# Plan 14 step 2b-1: today's short-term list, the nightly pass that turns it
# into long-term memories, fading, the alone belief, and the report.

const MemoryService = preload("res://scripts/services/memory_service.gd")

const DAY := 86400
const T0 := 1_800_000_000

const SIGN_LINE := "A path of worn stones ran up into the mist."
const OWL_LINE := "An owl watched me from the fence."

var _failed := 0
var _ran := 0
var _svc := MemoryService.new()


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("memory_night_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("memory_night_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("today_collects_and_caps", func(): return _test_today_collects_and_caps())
	_case("pass_needs_sleep_or_a_day", func(): return _test_pass_needs_sleep_or_a_day())
	_case("pass_makes_memories", func(): return _test_pass_makes_memories())
	_case("a_second_night_reinforces", func(): return _test_a_second_night_reinforces())
	_case("unused_memories_fade", func(): return _test_unused_memories_fade())
	_case("alone_after_a_week", func(): return _test_alone_after_a_week())
	_case("first_pass_moves_what_it_knew", func(): return _test_first_pass_moves_what_it_knew())
	_case("lines_read_well", func(): return _test_lines_read_well())
	_case("land_memories_only_when_relevant", func(): return _test_land_memories_only_when_relevant())
	_case("report_traces_every_memory", func(): return _test_report_traces_every_memory())
	_case("first_pass_counts_once", func(): return _test_first_pass_counts_once())
	_case("a_day_without_sleep_before_the_first_pass", func(): return _test_a_day_without_sleep_before_the_first_pass())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("memory_night_test[%s]: %s" % [name, err])
	else:
		print("memory_night_test[%s]: ok" % name)


func _land() -> Dictionary:
	return {
		"home_place": "home",
		"places": [
			{"id": "home", "name": "the house", "activities": [
				{"id": "sleep", "label": "went to bed", "until_hour": 6},
				{"id": "nap", "label": "had a nap"},
			], "sights": []},
			{"id": "orchard", "name": "the old orchard", "activities": [
				{"id": "wander", "label": "wandered about"},
			], "sights": [{"id": "owl", "line": OWL_LINE}]},
			{"id": "cliff", "name": "the Eastern Cliff", "activities": [],
				"discover": {"sign": SIGN_LINE, "found": "A cliff.", "blocked": ["No."]}, "sights": []},
		],
	}


func _event(t: int, place: String, place_name: String, activity: String, label: String, valence: float, extra: Dictionary = {}) -> Dictionary:
	var event := {
		"t": t, "place_id": place, "place_name": place_name, "activity_id": activity,
		"activity_label": label, "valence": valence, "text": "I did something.",
	}
	for key in extra.keys():
		event[key] = extra[key]
	return event


func _fresh() -> Dictionary:
	return _svc.ensure_profile({"mind": {}})


func _edge(profile: Dictionary, r: String, o: String) -> Dictionary:
	for edge in profile["memory"]["edges"]:
		if str(edge.get("r", "")) == r and str(edge.get("o", "")) == o:
			return edge
	return {}


func _night(profile: Dictionary, events: Array, now: int) -> Dictionary:
	var noted: Dictionary = _svc.note_today(profile, events, _land())
	return _svc.nightly_pass(noted, _land(), now)


func _test_today_collects_and_caps() -> Variant:
	var events: Array = [
		_event(T0, "orchard", "the old orchard", "wander", "wandered about", 0.2, {"found_place": "orchard", "text": "I found an orchard."}),
		_event(T0 + 1, "home", "the house", "look", "looked about", 0.0, {"sign_of": "cliff", "text": SIGN_LINE}),
		_event(T0 + 2, "home", "the house", "look", "looked about", -0.2, {"blocked_at": "cliff", "text": "I turned back."}),
		_event(T0 + 3, "orchard", "the old orchard", "wander", "wandered about", 0.1, {"sight": "owl", "text": OWL_LINE}),
	]
	var out: Dictionary = _svc.note_today(_fresh(), events, _land())
	var today: Array = out["memory"]["today"]
	if today.size() != 4:
		return "expected 4 items, got %d" % today.size()
	if str(today[0].get("found", "")) != "orchard" or str(today[1].get("sign", "")) != "cliff":
		return "found or sign missing from today"
	if str(today[2].get("blocked", "")) != "cliff" or str(today[3].get("sight", "")) != "owl":
		return "blocked or sight missing from today"
	if str(today[0].get("activity", "")) != "wander" or str(today[0].get("place_name", "")) != "the old orchard":
		return "activity or place missing from today"
	var many: Array = []
	for i in MemoryService.TODAY_LIMIT + 50:
		many.append(_event(T0 + i, "home", "the house", "nap", "had a nap", 0.0))
	var capped: Dictionary = _svc.note_today(_fresh(), many, _land())
	var kept: Array = capped["memory"]["today"]
	if kept.size() != MemoryService.TODAY_LIMIT:
		return "today is not capped (%d)" % kept.size()
	if int(kept[0]["t"]) != T0 + 50:
		return "the oldest items were not the ones dropped"
	return null


func _test_pass_needs_sleep_or_a_day() -> Variant:
	var nap: Array = [_event(T0, "home", "the house", "nap", "had a nap", 0.0)]
	var sleep: Array = [_event(T0, "home", "the house", "sleep", "went to bed", 0.0)]
	var fresh: Dictionary = _fresh()
	if _svc.night_pass_due(fresh, nap, _land(), T0):
		return "a nap started the pass"
	if not _svc.night_pass_due(fresh, sleep, _land(), T0):
		return "going to bed did not start the pass"
	var after: Dictionary = _night(fresh, nap, T0 + 10)
	var later: Dictionary = _svc.note_today(after, nap, _land())
	if _svc.night_pass_due(later, nap, _land(), T0 + DAY - 100):
		return "the pass ran before a day had passed"
	if not _svc.night_pass_due(later, nap, _land(), T0 + 10 + DAY):
		return "the pass did not run after a day awake"
	var empty: Dictionary = _svc.nightly_pass(later, _land(), T0 + 20)
	if _svc.night_pass_due(empty, nap, _land(), T0 + 20 + DAY):
		return "the pass ran with nothing in today"
	return null


func _test_pass_makes_memories() -> Variant:
	var events: Array = [
		_event(T0, "orchard", "the old orchard", "wander", "wandered about", -0.4, {"found_place": "orchard", "text": "I found an orchard."}),
		_event(T0 + 10, "home", "the house", "look", "looked about", 0.0, {"sign_of": "cliff", "text": SIGN_LINE}),
		_event(T0 + 20, "home", "the house", "look", "looked about", 0.0, {"blocked_at": "cliff", "text": "I turned back."}),
		_event(T0 + 30, "orchard", "the old orchard", "wander", "wandered about", 0.0, {"sight": "owl", "text": OWL_LINE}),
		_event(T0 + 40, "home", "the house", "nap", "had a nap", 0.6),
		# A liking needs a few goes (LIKED_MIN_DONE): three happy naps, and
		# wandering about that went badly more often than not.
		_event(T0 + 50, "home", "the house", "nap", "had a nap", 0.6),
		_event(T0 + 60, "home", "the house", "nap", "had a nap", 0.6),
		_event(T0 + 70, "orchard", "the old orchard", "wander", "wandered about", -0.4),
		_event(T0 + 80, "orchard", "the old orchard", "wander", "wandered about", -0.4),
	]
	var out: Dictionary = _night(_fresh(), events, T0 + 100)
	if _edge(out, "found", "place:orchard").is_empty():
		return "no found memory"
	var heard: Dictionary = _edge(out, "heard_of", "place:cliff")
	if heard.is_empty():
		return "no heard_of memory"
	if str(heard["o_label"]) != SIGN_LINE or str(heard["o_label"]).contains("Cliff"):
		return "the sign memory is not in its own words: " + str(heard["o_label"])
	if _edge(out, "couldnt_reach", "place:cliff").is_empty():
		return "no couldnt_reach memory"
	var noticed: Dictionary = _edge(out, "noticed", "sight:owl")
	if noticed.is_empty() or str(noticed["o_label"]) != OWL_LINE:
		return "no noticed memory with the sight's line"
	if _edge(out, "went_to", "place:orchard").is_empty():
		return "no went_to memory"
	if _edge(out, "did", "activity:wander").is_empty() or _edge(out, "did", "activity:nap").is_empty():
		return "no did memory"
	if _edge(out, "liked", "activity:nap").is_empty():
		return "no liked memory for a happy nap"
	if _edge(out, "disliked", "activity:wander").is_empty():
		return "no disliked memory for an unhappy wander"
	if not _edge(out, "liked", "activity:wander").is_empty() or not _edge(out, "disliked", "activity:nap").is_empty():
		return "a feeling was filed the wrong way round"
	if (out["memory"]["today"] as Array).size() != 0:
		return "today was not emptied"
	if int(out["memory"].get("last_pass_t", 0)) != T0 + 100:
		return "last_pass_t not set"
	if str(_edge(out, "found", "place:orchard").get("source", "")) != "land":
		return "land memories are not marked source land"
	return null


func _test_a_second_night_reinforces() -> Variant:
	var first: Dictionary = _night(_fresh(), [_event(T0, "orchard", "the old orchard", "wander", "wandered about", 0.0)], T0 + 100)
	var before: Dictionary = _edge(first, "went_to", "place:orchard")
	var second: Dictionary = _night(first, [_event(T0 + DAY, "orchard", "the old orchard", "wander", "wandered about", 0.0)], T0 + DAY + 100)
	var edges: int = 0
	for edge in second["memory"]["edges"]:
		if str(edge["r"]) == "went_to" and str(edge["o"]) == "place:orchard":
			edges += 1
	if edges != 1:
		return "expected one went_to edge, got %d" % edges
	var after: Dictionary = _edge(second, "went_to", "place:orchard")
	if int(after["count"]) != 2:
		return "count is %d, not 2" % int(after["count"])
	if float(after["strength"]) <= float(before["strength"]):
		return "a second night did not make it stronger"
	return null


func _test_unused_memories_fade() -> Variant:
	var first: Dictionary = _night(_fresh(), [
		_event(T0, "orchard", "the old orchard", "wander", "wandered about", 0.0),
		_event(T0 + 5, "cliff", "the Eastern Cliff", "look", "looked about", 0.0),
	], T0 + 100)
	if _edge(first, "went_to", "place:cliff").is_empty():
		return "setup: no went_to cliff"
	var later_t: int = T0 + 84 * DAY
	var second: Dictionary = _night(first, [_event(later_t, "orchard", "the old orchard", "wander", "wandered about", 0.0)], later_t + 100)
	if not _edge(second, "went_to", "place:cliff").is_empty():
		return "an unused memory was not forgotten after 4 half-lives"
	if _edge(second, "went_to", "place:orchard").is_empty():
		return "a reinforced memory was forgotten"
	return null


func _test_alone_after_a_week() -> Variant:
	var one: Dictionary = _night(_fresh(), [_event(T0, "home", "the house", "nap", "had a nap", 0.0)], T0 + 100)
	var near: Dictionary = _svc.nightly_pass(one, _land(), T0 + 100 + MemoryService.ALONE_DAYS * DAY - 10)
	if not _edge(near, "believes", "belief:alone").is_empty():
		return "it believed it was alone before a week"
	var week: Dictionary = _svc.nightly_pass(near, _land(), T0 + 100 + MemoryService.ALONE_DAYS * DAY)
	var belief: Dictionary = _edge(week, "believes", "belief:alone")
	if belief.is_empty():
		return "no belief after a week"
	var next: Dictionary = _svc.nightly_pass(week, _land(), T0 + 100 + (MemoryService.ALONE_DAYS + 1) * DAY)
	var stronger: Dictionary = _edge(next, "believes", "belief:alone")
	if float(stronger["strength"]) <= float(belief["strength"]):
		return "the belief did not grow the next night"
	var believes: int = 0
	for edge in next["memory"]["edges"]:
		if str(edge["r"]) == "believes":
			believes += 1
	if believes != 1:
		return "expected one belief, got %d" % believes
	return null


# The mind's records already include today, so the first pass must not count
# what happened today twice (three naps are three, not six).
func _test_first_pass_counts_once() -> Variant:
	var profile: Dictionary = _svc.ensure_profile({"mind": {
		"known_places": {"orchard": {"stage": "found", "t": T0, "tries": 0}},
		"seen": {"owl": T0 + 10},
		"done": {"nap": 3, "wander": 2, "look": 1},
	}})
	var events: Array = [
		_event(T0, "orchard", "the old orchard", "wander", "wandered about", 0.0, {"found_place": "orchard", "text": "I found an orchard."}),
		_event(T0 + 10, "orchard", "the old orchard", "look", "looked about", 0.0, {"sight": "owl", "text": OWL_LINE}),
		_event(T0 + 20, "home", "the house", "nap", "had a nap", 0.2),
		_event(T0 + 30, "home", "the house", "nap", "had a nap", 0.2),
		_event(T0 + 40, "home", "the house", "nap", "had a nap", 0.2),
	]
	var out: Dictionary = _night(profile, events, T0 + 100)
	var expected := {"nap": 3, "wander": 2, "look": 1}
	for activity_id in expected.keys():
		var did: Dictionary = _edge(out, "did", "activity:" + str(activity_id))
		if did.is_empty() or int(did["count"]) != int(expected[activity_id]):
			return "%s should be remembered %d times, not %s" % [str(activity_id), int(expected[activity_id]), str(did.get("count", "none"))]
	if int(_edge(out, "found", "place:orchard").get("count", 0)) != 1:
		return "the place found today was counted twice"
	if int(_edge(out, "noticed", "sight:owl").get("count", 0)) != 1:
		return "the sight noticed today was counted twice"
	return null


# Before its first pass there is no last pass to count from: a buddy that never
# chooses to sleep still sorts its day once a day.
func _test_a_day_without_sleep_before_the_first_pass() -> Variant:
	var profile: Dictionary = _svc.note_today(_fresh(), [_event(T0, "home", "the house", "look", "looked about", 0.0)], _land())
	if _svc.night_pass_due(profile, [], _land(), T0 + 3600):
		return "a pass was due an hour after its first decision"
	if not _svc.night_pass_due(profile, [], _land(), T0 + DAY):
		return "no pass after a day without sleep, before its first pass"
	return null


func _test_first_pass_moves_what_it_knew() -> Variant:
	var profile: Dictionary = _svc.ensure_profile({"mind": {
		"known_places": {"orchard": {"stage": "found", "t": T0 - DAY, "tries": 0}, "cliff": {"stage": "sign", "t": T0 - DAY, "tries": 1}},
		"seen": {"owl": T0 - DAY},
		"done": {"nap": 3},
	}})
	var out: Dictionary = _svc.nightly_pass(profile, _land(), T0)
	if _edge(out, "found", "place:orchard").is_empty():
		return "no found edge from known_places"
	var heard: Dictionary = _edge(out, "heard_of", "place:cliff")
	if heard.is_empty() or str(heard["o_label"]) != SIGN_LINE:
		return "no heard_of edge carrying the sign line"
	var noticed: Dictionary = _edge(out, "noticed", "sight:owl")
	if noticed.is_empty() or str(noticed["o_label"]) != OWL_LINE:
		return "no noticed edge from seen"
	var did: Dictionary = _edge(out, "did", "activity:nap")
	if did.is_empty() or int(did["count"]) != 3:
		return "no did edge with its count from done"
	if int(out["memory"].get("first_pass_t", 0)) != T0:
		return "first_pass_t not set"
	return null


func _test_lines_read_well() -> Variant:
	var cases: Array = [
		["found", "the old orchard", 1, "you found the old orchard earlier today"],
		["noticed", OWL_LINE, 1, "you noticed: " + OWL_LINE],
		["heard_of", SIGN_LINE, 1, "you noticed a sign of somewhere you have not been: " + SIGN_LINE],
		["couldnt_reach", "I turned back.", 1, "you tried to get somewhere and could not: I turned back."],
		["did", "had a nap", 1, "you had a nap earlier today"],
		["did", "had a nap", 4, "you have had a nap 4 times, last earlier today"],
		["liked", "had a nap", 1, "you liked it when you had a nap"],
		["disliked", "wandered about", 1, "you did not like it when you wandered about"],
		["believes", "you are the only one here", 1, "you have come to believe you are the only one here"],
	]
	for row in cases:
		var edge := {"s": "self", "s_label": "you", "r": row[0], "o_label": row[1], "count": row[2], "seen": T0}
		var line: String = _svc._render_edge(edge, T0 + 60)
		if line != row[3]:
			return "'%s' read as '%s'" % [row[3], line]
	return null


func _test_land_memories_only_when_relevant() -> Variant:
	var events: Array = [
		_event(T0, "orchard", "the old orchard", "wander", "wandered about", 0.0, {"found_place": "orchard", "text": "I found an orchard."}),
		_event(T0 + 5, "orchard", "the old orchard", "wander", "wandered about", 0.0, {"sight": "owl", "text": OWL_LINE}),
	]
	var out: Dictionary = _night(_fresh(), events, T0 + 100)
	var unrelated: Dictionary = _svc.recall(out, "how is the weather today", T0 + 200)
	if not (unrelated["facts"] as Array).is_empty():
		return "an unrelated sentence brought land memories: " + str(unrelated["facts"])
	var related: Dictionary = _svc.recall(out, "tell me about the orchard", T0 + 200)
	var named := false
	for line in related["facts"]:
		if str(line).contains("orchard"):
			named = true
	if not named:
		return "a sentence naming the place did not bring its memories"
	return null


func _test_report_traces_every_memory() -> Variant:
	var profile: Dictionary = _svc.ensure_profile({"mind": {
		"known_places": {"orchard": {"stage": "found", "t": T0, "tries": 0}, "cliff": {"stage": "sign", "t": T0, "tries": 0}},
		"seen": {"owl": T0},
		"done": {"wander": 2, "look": 1, "nap": 1},
	}})
	var events: Array = [
		_event(T0, "orchard", "the old orchard", "wander", "wandered about", 0.0, {"found_place": "orchard", "text": "I found an orchard."}),
		_event(T0 + 5, "orchard", "the old orchard", "wander", "wandered about", 0.0, {"sight": "owl", "text": OWL_LINE}),
		_event(T0 + 10, "home", "the house", "look", "looked about", 0.0, {"sign_of": "cliff", "text": SIGN_LINE}),
		_event(T0 + 20, "home", "the house", "nap", "had a nap", 0.6),
	]
	var out: Dictionary = _night(profile, events, T0 + 100)
	var report: Dictionary = _svc.land_memory_report(out)
	if int(report["untraceable"]) != 0:
		return "a normal profile has %d untraceable memories" % int(report["untraceable"])
	if int(report["total_edges"]) < 5 or int(report["today"]) != 0:
		return "the report counts are off: " + str(report)
	var edges: Array = out["memory"]["edges"]
	edges.append({"id": 999, "s": "self", "s_label": "you", "r": "noticed", "o": "sight:unknown", "o_label": "x",
		"t": T0, "seen": T0, "count": 1, "strength": 0.7, "importance": 0.5, "source": "land", "pinned": false, "from_talks": []})
	var bad: Dictionary = _svc.land_memory_report(out)
	if int(bad["untraceable"]) != 1:
		return "an invented sight was not flagged (untraceable %d)" % int(bad["untraceable"])
	return null
