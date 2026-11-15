extends Node

const MindService = preload("res://scripts/services/mind_service.gd")

const NOW := 1_800_000_000
const NPCS := [
	{"id": "pip", "name": "Pip"},
	{"id": "mira", "name": "Mira"},
]
const TOWN := {
	"home_place": "home",
	"places": [
		{"id": "home", "name": "home", "opens": 0, "closes": 24, "distance": 0, "residents": [],
			"activities": [
				{"id": "nap", "label": "had a nap", "satisfies": "energy"},
				{"id": "tidy", "label": "tidied up", "satisfies": "comfort"},
				{"id": "think", "label": "sat and thought", "satisfies": "reflection"},
			]},
		{"id": "cafe", "name": "the cafe", "opens": 8, "closes": 20, "distance": 1, "residents": ["pip"],
			"activities": [
				{"id": "tea", "label": "had tea", "satisfies": "comfort"},
				{"id": "catch_up", "label": "caught up over a drink", "satisfies": "social"},
			]},
		{"id": "pond", "name": "the pond", "opens": 0, "closes": 24, "distance": 2, "residents": [],
			"activities": [
				{"id": "skip_stones", "label": "skipped stones", "satisfies": "curiosity"},
			]},
	],
}

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("mind_service_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("mind_service_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("first_tick_decides_once", func(): return _test_first_tick_decides_once())
	_case("no_decision_before_interval", func(): return _test_no_decision_before_interval())
	_case("catch_up_is_capped_and_ordered", func(): return _test_catch_up_is_capped_and_ordered())
	_case("decisions_are_deterministic", func(): return _test_decisions_are_deterministic())
	_case("exhaustion_leads_to_rest", func(): return _test_exhaustion_leads_to_rest())
	_case("experience_shapes_feelings", func(): return _test_experience_shapes_feelings())
	_case("journal_is_bounded", func(): return _test_journal_is_bounded())
	_case("malformed_state_is_repaired", func(): return _test_malformed_state_is_repaired())
	_case("town_decisions_name_a_real_place", func(): return _test_town_decisions_name_a_real_place())
	_case("closed_places_are_not_visited", func(): return _test_closed_places_are_not_visited())
	_case("companion_is_a_resident", func(): return _test_companion_is_a_resident())
	_case("feelings_split_by_place_activity_npc", func(): return _test_feelings_split_by_place_activity_npc())
	_case("location_follows_decisions", func(): return _test_location_follows_decisions())
	_case("no_town_falls_back_to_home", func(): return _test_no_town_falls_back_to_home())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("mind_service_test[%s]: %s" % [name, err])
	else:
		print("mind_service_test[%s]: ok" % name)


func _profile(mods: Dictionary = {}) -> Dictionary:
	var base := {"energy_strain": 0.2, "social_fulfillment": 0.5, "comfort": 0.5, "confidence": 0.5}
	for key in mods.keys():
		base[key] = mods[key]
	return {"personality_seed_tag": "curious", "mood_modifiers": base}


func _test_first_tick_decides_once() -> Variant:
	var svc := MindService.new()
	var result := svc.tick(_profile(), NPCS, NOW, {})
	var events: Array = result["events"]
	if events.size() != 1:
		return "expected exactly one decision on first tick, got %d" % events.size()
	var event: Dictionary = events[0]
	if not MindService.INTENTS.has(str(event.get("intent", ""))):
		return "unknown intent: %s" % [event]
	if str(event.get("text", "")) == "" or str(event.get("action", "")) == "":
		return "event must carry a thought and an action: %s" % [event]
	if svc.get_journal(result["profile"], 0).size() != 1:
		return "journal should hold the first entry"
	return null


func _test_no_decision_before_interval() -> Variant:
	var svc := MindService.new()
	var first := svc.tick(_profile(), NPCS, NOW, {})
	var soon := svc.tick(first["profile"], NPCS, NOW + MindService.DECISION_INTERVAL_SECONDS - 1, {})
	if not (soon["events"] as Array).is_empty():
		return "decided again before the interval elapsed"
	var due := svc.tick(first["profile"], NPCS, NOW + MindService.DECISION_INTERVAL_SECONDS, {})
	if (due["events"] as Array).size() != 1:
		return "expected one decision once the interval elapsed"
	return null


func _test_catch_up_is_capped_and_ordered() -> Variant:
	var svc := MindService.new()
	var first := svc.tick(_profile(), NPCS, NOW, {})
	var later := NOW + MindService.DECISION_INTERVAL_SECONDS * 500
	var result := svc.tick(first["profile"], NPCS, later, {})
	var events: Array = result["events"]
	if events.size() != MindService.MAX_CATCHUP_DECISIONS:
		return "expected %d catch-up decisions, got %d" % [MindService.MAX_CATCHUP_DECISIONS, events.size()]
	var previous := 0
	for event in events:
		var stamp := int(event.get("t", 0))
		if stamp <= previous:
			return "catch-up decisions are not in time order"
		previous = stamp
	if previous != later:
		return "last catch-up decision should land on now"
	return null


func _test_decisions_are_deterministic() -> Variant:
	var a := MindService.new().tick(_profile(), NPCS, NOW, {})
	var b := MindService.new().tick(_profile(), NPCS, NOW, {})
	if JSON.stringify(a) != JSON.stringify(b):
		return "same history produced different decisions"
	return null


func _test_exhaustion_leads_to_rest() -> Variant:
	var svc := MindService.new()
	var tired := _profile({"energy_strain": 1.0, "social_fulfillment": 1.0, "comfort": 1.0})
	var result := svc.tick(tired, NPCS, NOW, {"is_night": true})
	var event: Dictionary = (result["events"] as Array)[0]
	if str(event.get("intent", "")) != "rest":
		return "an exhausted buddy at night should rest, chose %s" % str(event.get("intent", ""))
	if str(event.get("action", "")) != "sleep":
		return "rest should be acted out as sleep"
	var strain := float(result["profile"]["mood_modifiers"]["energy_strain"])
	if strain >= 1.0:
		return "resting did not reduce energy strain"
	return null


func _test_experience_shapes_feelings() -> Variant:
	var svc := MindService.new()
	var profile := _profile({"social_fulfillment": 0.0})
	var seen_subject := ""
	for step in range(40):
		var result := svc.tick(profile, NPCS, NOW + step * MindService.DECISION_INTERVAL_SECONDS, {})
		profile = result["profile"]
		for event in result["events"]:
			if str(event.get("subject_id", "")) != "":
				seen_subject = str(event["subject_id"])
	if seen_subject == "":
		return "buddy never visited or explored anything in 40 decisions"
	if is_zero_approx(svc.feeling_for(profile, seen_subject)):
		return "an experienced subject should leave a feeling behind"
	var preferences := svc.get_preferences(profile)
	if str(preferences.get("favourite", "")) == "":
		return "buddy should have a favourite after 40 decisions"
	for value in (profile["mind"]["feelings"] as Dictionary).values():
		if float(value) < -1.0 or float(value) > 1.0:
			return "feeling out of range: %s" % value
	return null


func _test_journal_is_bounded() -> Variant:
	var svc := MindService.new()
	var profile := _profile()
	for step in range(MindService.JOURNAL_LIMIT + 15):
		profile = svc.tick(profile, NPCS, NOW + step * MindService.DECISION_INTERVAL_SECONDS, {})["profile"]
	var journal := svc.get_journal(profile, 0)
	if journal.size() != MindService.JOURNAL_LIMIT:
		return "journal should cap at %d, has %d" % [MindService.JOURNAL_LIMIT, journal.size()]
	if svc.get_journal(profile, 5).size() != 5:
		return "limited journal read should return 5 entries"
	return null


func _test_malformed_state_is_repaired() -> Variant:
	var svc := MindService.new()
	var broken := {"mind": {"feelings": "nope", "journal": 7}, "mood_modifiers": "bad"}
	var result := svc.tick(broken, [null, {"name": "no id"}, 3], NOW, {})
	var events: Array = result["events"]
	if events.size() != 1:
		return "malformed state should still yield one decision"
	if str((events[0] as Dictionary).get("intent", "")) == "visit":
		return "visit chosen with no valid NPCs"
	return null


func _run_town(steps: int, context: Dictionary, town: Dictionary) -> Dictionary:
	var svc := MindService.new()
	var profile := _profile({"social_fulfillment": 0.0})
	var events: Array = []
	for step in range(steps):
		var result := svc.tick(profile, NPCS, NOW + step * MindService.DECISION_INTERVAL_SECONDS, context, town)
		profile = result["profile"]
		events.append_array(result["events"])
	return {"profile": profile, "events": events}


func _test_town_decisions_name_a_real_place() -> Variant:
	var events: Array = _run_town(30, {"hour": 12}, TOWN)["events"]
	for event in events:
		var place_id := str(event.get("place_id", ""))
		var place := {}
		for row in TOWN["places"]:
			if str(row["id"]) == place_id:
				place = row
		if place.is_empty():
			return "event names a place outside the town: %s" % [event]
		var found := false
		for activity in place["activities"]:
			if str(activity["id"]) == str(event.get("activity_id", "")):
				found = true
		if not found:
			return "activity does not exist at %s: %s" % [place_id, event]
		var text := str(event.get("text", ""))
		# Reflection keeps its own favourite / least-favourite wording.
		var names_place := text.contains(str(place["name"])) or text.contains("home") or str(event.get("intent", "")) == "reflect"
		if text == "" or not names_place:
			return "text does not mention the place: %s" % text
	return null


func _test_closed_places_are_not_visited() -> Variant:
	var events: Array = _run_town(30, {"hour": 3}, TOWN)["events"]
	for event in events:
		if str(event.get("place_id", "")) == "cafe":
			return "visited the cafe while it was closed"
	return null


func _test_companion_is_a_resident() -> Variant:
	var events: Array = _run_town(40, {"hour": 12}, TOWN)["events"]
	for event in events:
		var companion := str(event.get("companion_name", ""))
		if companion != "" and (str(event.get("place_id", "")) != "cafe" or companion != "Pip"):
			return "companion is not a resident of the place: %s" % [event]
	return null


func _test_feelings_split_by_place_activity_npc() -> Variant:
	var profile: Dictionary = _run_town(40, {"hour": 12}, TOWN)["profile"]
	var has_place := false
	var has_activity := false
	for key in (profile["mind"]["feelings"] as Dictionary).keys():
		if str(key).begins_with("place:"):
			has_place = true
		if str(key).begins_with("activity:"):
			has_activity = true
	if not has_place or not has_activity:
		return "feelings should carry place: and activity: keys"
	return null


func _test_location_follows_decisions() -> Variant:
	var result := _run_town(10, {"hour": 12}, TOWN)
	var events: Array = result["events"]
	var last: Dictionary = events[events.size() - 1]
	if str(result["profile"]["mind"]["location"]) != str(last["place_id"]):
		return "mind location should match the last decision's place"
	return null


func _test_no_town_falls_back_to_home() -> Variant:
	var svc := MindService.new()
	var profile := _profile({"social_fulfillment": 0.0})
	for step in range(20):
		var result := svc.tick(profile, NPCS, NOW + step * MindService.DECISION_INTERVAL_SECONDS, {})
		profile = result["profile"]
		for event in result["events"]:
			if str(event.get("place_id", "")) != "home":
				return "without a town every decision should be at home: %s" % [event]
	return null
