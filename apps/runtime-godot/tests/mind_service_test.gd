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
	_case("suggestion_is_found_in_chat", func(): return _test_suggestion_is_found_in_chat())
	_case("suggestion_yes_steers_next_decision", func(): return _test_suggestion_yes_steers_next_decision())
	_case("suggestion_no_or_later", func(): return _test_suggestion_no_or_later())
	_case("talk_is_an_event", func(): return _test_talk_is_an_event())
	_case("news_to_share", func(): return _test_news_to_share())
	_case("want_noticed_at_the_shop", func(): return _test_want_noticed_at_the_shop())
	_case("want_bought_when_affordable", func(): return _test_want_bought_when_affordable())
	_case("no_trip_without_savings", func(): return _test_no_trip_without_savings())
	_case("wants_fade_after_a_week", func(): return _test_wants_fade_after_a_week())
	_case("day_plan_made_each_morning", func(): return _test_day_plan_made_each_morning())
	_case("day_plan_followed_or_missed", func(): return _test_day_plan_followed_or_missed())
	_case("suggestion_beats_want_and_plan", func(): return _test_suggestion_beats_want_and_plan())
	_case("catch_up_buys_each_want_once", func(): return _test_catch_up_buys_each_want_once())
	_case("yesterdays_plan_is_written_off", func(): return _test_yesterdays_plan_is_written_off())


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


func _talk_profile(feelings: Dictionary = {}, strain: float = 0.2) -> Dictionary:
	var profile := _profile({"energy_strain": strain, "social_fulfillment": 0.5})
	profile["mind"] = {"feelings": feelings}
	return profile


func _test_suggestion_is_found_in_chat() -> Variant:
	var svc := MindService.new()
	var mira := svc.find_target("go see Mira", TOWN, NPCS)
	if str(mira.get("kind", "")) != "npc" or str(mira.get("id", "")) != "mira":
		return "expected npc mira, got %s" % [mira]
	var cafe := svc.find_target("you should try the cafe", TOWN, NPCS)
	if str(cafe.get("kind", "")) != "place" or str(cafe.get("id", "")) != "cafe" or str(cafe.get("name", "")) != "the cafe":
		return "expected place cafe, got %s" % [cafe]
	if not svc.find_target("I got home late", TOWN, NPCS).is_empty():
		return "home must never be a target"
	if not svc.find_target("the pondering continues", TOWN, NPCS).is_empty():
		return "matches must be whole words"
	if not svc.is_suggestion("why don't you go to the pond"):
		return "cue not recognised"
	if svc.is_suggestion("I like the pond"):
		return "plain mention is not a suggestion"
	return null


func _test_suggestion_yes_steers_next_decision() -> Variant:
	var svc := MindService.new()
	var target := {"kind": "place", "id": "pond", "name": "the pond"}
	var answer := svc.consider(_talk_profile(), target, NOW, 12, TOWN, NPCS)
	if str(answer["answer"]) != "yes":
		return "expected yes, got %s" % [answer]
	var intention: Dictionary = answer["profile"]["mind"]["intention"]
	if str(intention.get("id", "")) != "pond" or str(intention.get("from", "")) != "suggestion":
		return "intention not set: %s" % [intention]
	if int(intention.get("until", 0)) != NOW + MindService.INTENTION_HOURS * 3600:
		return "intention expiry wrong"
	var result := svc.tick(answer["profile"], NPCS, NOW + MindService.DECISION_INTERVAL_SECONDS, {"hour": 12}, TOWN)
	var event: Dictionary = (result["events"] as Array)[0]
	if str(event.get("place_id", "")) != "pond":
		return "did not go to the pond: %s" % [event]
	if not str(event.get("text", "")).begins_with("You suggested the pond, so I went. "):
		return "text missing the suggestion prefix: %s" % str(event.get("text", ""))
	if str(event.get("because", "")) != "suggestion":
		return "event should carry because=suggestion"
	var after: Dictionary = result["profile"]["mind"]["intention"]
	if not after.is_empty():
		return "intention should be cleared once honoured"
	return null


func _test_suggestion_no_or_later() -> Variant:
	var svc := MindService.new()
	var pond := {"kind": "place", "id": "pond", "name": "the pond"}
	var cafe := {"kind": "place", "id": "cafe", "name": "the cafe"}
	var no := svc.consider(_talk_profile({"place:pond": -0.6}), pond, NOW, 12, TOWN, NPCS)
	if str(no["answer"]) != "no":
		return "expected no, got %s" % [no]
	var journal: Array = no["profile"]["mind"]["journal"]
	var last: Dictionary = journal[journal.size() - 1]
	if str(last.get("kind", "")) != "suggestion" or not str(last.get("text", "")).contains("didn't feel like it"):
		return "refusal not journaled: %s" % [last]
	if not (no["profile"]["mind"]["intention"] as Dictionary).is_empty():
		return "a refusal must not set an intention"

	var late := svc.consider(_talk_profile(), pond, NOW, 23, TOWN, NPCS)
	if str(late["answer"]) != "later" or (late["profile"]["mind"]["intention"] as Dictionary).is_empty():
		return "night should be later with the intention kept: %s" % [late]

	var closed := svc.consider(_talk_profile(), cafe, NOW, 21, TOWN, NPCS)
	if str(closed["answer"]) != "later":
		return "closed cafe should be later, got %s" % [closed]
	var held := svc.tick(closed["profile"], NPCS, NOW + MindService.DECISION_INTERVAL_SECONDS, {"hour": 21}, TOWN)
	var held_event: Dictionary = (held["events"] as Array)[0]
	if held_event.has("because"):
		return "must not honour a closed place: %s" % [held_event]
	if (held["profile"]["mind"]["intention"] as Dictionary).is_empty():
		return "intention should survive while closed"

	# Tired: "later, after a rest", and it keeps to that while still tired.
	var tired_profile := _talk_profile()
	var tired_mods: Dictionary = {}
	if typeof(tired_profile.get("mood_modifiers", null)) == TYPE_DICTIONARY:
		tired_mods = (tired_profile["mood_modifiers"] as Dictionary).duplicate(true)
	tired_mods["energy_strain"] = 0.9
	tired_profile["mood_modifiers"] = tired_mods
	var tired := svc.consider(tired_profile, pond, NOW, 12, TOWN, NPCS)
	if str(tired["answer"]) != "later":
		return "a tired buddy should say later, got %s" % [tired]
	var still_tired := svc.tick(tired["profile"], NPCS, NOW + MindService.DECISION_INTERVAL_SECONDS, {"hour": 12}, TOWN)
	if ((still_tired["events"] as Array)[0] as Dictionary).has("because"):
		return "it promised to rest first, but went while still tired"
	if (still_tired["profile"]["mind"]["intention"] as Dictionary).is_empty():
		return "the plan should wait until it has rested"
	var after_rest: Dictionary = (still_tired["profile"] as Dictionary).duplicate(true)
	after_rest["mood_modifiers"]["energy_strain"] = 0.2
	var went := svc.tick(after_rest, NPCS, NOW + 2 * MindService.DECISION_INTERVAL_SECONDS, {"hour": 12}, TOWN)
	if str(((went["events"] as Array)[0] as Dictionary).get("because", "")) != "suggestion":
		return "after resting it should go, as it said it would"

	var expired := svc.consider(_talk_profile(), pond, NOW, 12, TOWN, NPCS)
	var past := NOW + (MindService.INTENTION_HOURS + 1) * 3600
	var gone := svc.tick(expired["profile"], NPCS, past, {"hour": 12}, TOWN)
	if not (gone["profile"]["mind"]["intention"] as Dictionary).is_empty():
		return "expired intention should be cleared"
	if (gone["events"] as Array)[0].has("because"):
		return "expired intention must not be honoured"
	return null


func _test_talk_is_an_event() -> Variant:
	var svc := MindService.new()
	var profile := svc.note_talk(_talk_profile(), "They told me about the pond.", ["I love the pond"], NOW, TOWN, NPCS)
	var social := float(profile["mood_modifiers"]["social_fulfillment"])
	if not is_equal_approx(social, 0.75):
		return "social fulfillment should rise by 0.25, got %s" % social
	var journal: Array = profile["mind"]["journal"]
	var last: Dictionary = journal[journal.size() - 1]
	if str(last.get("kind", "")) != "talk" or str(last.get("text", "")) != "We talked. They told me about the pond.":
		return "talk not journaled: %s" % [last]
	var intention: Dictionary = profile["mind"]["intention"]
	if str(intention.get("id", "")) != "pond" or str(intention.get("from", "")) != "talk":
		return "talk should leave an intention for the pond: %s" % [intention]
	var result := svc.tick(profile, NPCS, NOW + MindService.DECISION_INTERVAL_SECONDS, {"hour": 12}, TOWN)
	var event: Dictionary = (result["events"] as Array)[0]
	if str(event.get("place_id", "")) != "pond":
		return "did not go to the pond: %s" % [event]
	if not str(event.get("text", "")).begins_with("You mentioned the pond, so I went."):
		return "text missing the talk prefix: %s" % str(event.get("text", ""))

	var plain := svc.note_talk(_talk_profile(), "", ["hello"], NOW, TOWN, NPCS)
	var plain_journal: Array = plain["mind"]["journal"]
	if str((plain_journal[plain_journal.size() - 1] as Dictionary).get("text", "")) != "We talked for a while.":
		return "empty summary wording wrong"
	if not (plain["mind"]["intention"] as Dictionary).is_empty():
		return "nothing mentioned, so no intention"
	return null


func _test_news_to_share() -> Variant:
	var svc := MindService.new()
	var profile := _talk_profile()
	for step in range(3):
		profile = svc.tick(profile, NPCS, NOW + step * MindService.DECISION_INTERVAL_SECONDS, {"hour": 12}, TOWN)["profile"]
	var big_t := NOW + 100000
	var journal: Array = profile["mind"]["journal"]
	journal.append({"t": big_t, "intent": "visit", "valence": 0.8, "text": "Something wonderful happened."})
	journal.append({"t": big_t + 10, "intent": "visit", "valence": 0.95, "kind": "talk", "text": "We talked."})
	journal.append({"t": big_t + 20, "intent": "reflect", "valence": -0.95, "kind": "suggestion", "text": "No."})
	var news := svc.pick_news(profile)
	if int(news.get("t", 0)) != big_t:
		return "expected the 0.8 entry, got %s" % [news]
	var shared := svc.mark_shared(profile, big_t)
	if not svc.pick_news(shared).is_empty():
		return "shared news should not be offered again: %s" % [svc.pick_news(shared)]

	var talked := svc.note_talk(profile, "Chat.", [], big_t + 500, TOWN, NPCS)
	if not svc.pick_news(talked).is_empty():
		return "entries older than the last talk should not be news: %s" % [svc.pick_news(talked)]
	return null


const SHOP_ITEMS := [
	{"id": "wz-red-bandana", "name": "Red Bandana", "slot": "hat", "price": 50},
	{"id": "wz-blue-cape", "name": "Blue Cape", "slot": "cape", "price": 80},
]


# The fixture town plus a market (the fixture has no shop of its own).
func _shop_town() -> Dictionary:
	var town := TOWN.duplicate(true)
	(town["places"] as Array).append({
		"id": "market", "name": "the market", "kind": "shop", "opens": 9, "closes": 18, "distance": 1,
		"residents": [],
		"activities": [{"id": "browse", "label": "browsed the stalls", "satisfies": "curiosity"}],
	})
	return town


# A unix time that reads as hour:minute local time, `day` days after NOW's day.
func _local_unix(day: int, hour: int, minute: int = 0) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var midnight := int((NOW + bias) / 86400) * 86400 - bias
	return midnight + day * 86400 + hour * 3600 + minute * 60


# One decision at exactly `t`, whatever the profile's last decision was.
func _decide_at(svc: MindService, profile: Dictionary, t: int, context: Dictionary, town: Dictionary) -> Dictionary:
	var fresh := svc.ensure_profile(profile)
	fresh["mind"]["last_decision_unix"] = 0
	var result := svc.tick(fresh, NPCS, t, context, town)
	return {"profile": result["profile"], "event": (result["events"] as Array)[0]}


func _saving_want(t: int, price: int = 50) -> Dictionary:
	return {
		"id": "want-%d" % t, "item_id": "wz-red-bandana", "name": "Red Bandana", "slot": "hat",
		"price": price, "reason": "saw it at the market", "t": t, "status": "saving", "place_id": "market",
	}


func _profile_with_wants(wants: Array) -> Dictionary:
	var profile := MindService.new().ensure_profile(_talk_profile())
	profile["mind"]["wants"] = wants
	return profile


func _test_want_noticed_at_the_shop() -> Variant:
	var svc := MindService.new()
	var town := _shop_town()
	var profile := _talk_profile()
	var start := _local_unix(0, 12)
	var context := {"shop_items": SHOP_ITEMS}
	var noticed := false
	for step in range(30):
		var t := start + step * MindService.DECISION_INTERVAL_SECONDS
		var steered := svc.consider(profile, {"kind": "place", "id": "market", "name": "the market"}, t - 1, 12, town, NPCS)
		var result := _decide_at(svc, steered["profile"], t, context, town)
		profile = result["profile"]
		var event: Dictionary = result["event"]
		if svc.get_wants(profile).size() > MindService.MAX_OPEN_WANTS:
			return "more than %d saving wants" % MindService.MAX_OPEN_WANTS
		if noticed or not event.has("noticed_want"):
			continue
		noticed = true
		var wants := svc.get_wants(profile)
		var want: Dictionary = wants[wants.size() - 1]
		if str(want["id"]) != str(event["noticed_want"]) or str(want["id"]) != "want-%d" % t:
			return "want id should match the event and the time: %s / %s" % [want, event]
		if str(want["status"]) != "saving" or str(want["place_id"]) != "market" or int(want["t"]) != t:
			return "want has the wrong shape: %s" % [want]
		if str(want["reason"]) != "saw it at the market" or typeof(want["price"]) != TYPE_INT:
			return "want reason or price wrong: %s" % [want]
		var matched := false
		for item in SHOP_ITEMS:
			if str(item["id"]) == str(want["item_id"]) and str(item["name"]) == str(want["name"]) \
					and str(item["slot"]) == str(want["slot"]) and int(item["price"]) == int(want["price"]):
				matched = true
		if not matched:
			return "want does not match a shop item: %s" % [want]
		if not str(event.get("text", "")).contains(" I saw a %s there. I'd like one." % str(want["name"])):
			return "text should mention the item: %s" % str(event.get("text", ""))
	if not noticed:
		return "never noticed a want in 30 decisions at the shop"
	return null


func _test_want_bought_when_affordable() -> Variant:
	var svc := MindService.new()
	var town := _shop_town()
	var t := _local_unix(0, 12)
	var profile := _profile_with_wants([_saving_want(t - 3600)])
	var result := _decide_at(svc, profile, t, {"meso": 100}, town)
	var event: Dictionary = result["event"]
	if str(event.get("buy_want", "")) != "want-%d" % (t - 3600):
		return "should have gone to buy the want: %s" % [event]
	if not str(event.get("text", "")).begins_with("I'd saved enough for the Red Bandana, so I went to"):
		return "text missing the want prefix: %s" % str(event.get("text", ""))
	if str(event.get("place_id", "")) != "market" or str(event.get("because", "")) != "want":
		return "should have gone to the market because of the want: %s" % [event]
	if not (result["profile"]["mind"]["intention"] as Dictionary).is_empty():
		return "intention should be cleared once honoured"
	var bought := svc.complete_want(result["profile"], str(event["buy_want"]), t, true)
	var wants: Array = bought["mind"]["wants"]
	if str(wants[0]["status"]) != "bought" or int(wants[0]["bought_t"]) != t:
		return "want should be bought: %s" % [wants[0]]
	if not svc.get_wants(bought).is_empty():
		return "a bought want is no longer being saved for"
	var journal: Array = bought["mind"]["journal"]
	var last: Dictionary = journal[journal.size() - 1]
	if str(last["text"]) != "I bought the Red Bandana I'd been saving for. I'm wearing it now." or str(last["kind"]) != "purchase":
		return "purchase not journaled: %s" % [last]
	var unknown := svc.complete_want(result["profile"], "nope", t, false)
	if JSON.stringify(unknown) != JSON.stringify(result["profile"]):
		return "an unknown want id must leave the profile alone"
	return null


func _test_no_trip_without_savings() -> Variant:
	var svc := MindService.new()
	var town := _shop_town()
	var t := _local_unix(0, 12)
	var profile := _profile_with_wants([_saving_want(t - 3600)])
	var result := _decide_at(svc, profile, t, {"meso": 60}, town)
	var event: Dictionary = result["event"]
	if event.has("buy_want") or str(event.get("because", "")) == "want":
		return "50 + 20 reserve is more than 60, so no trip: %s" % [event]
	if not (result["profile"]["mind"]["intention"] as Dictionary).is_empty():
		return "no intention without savings"
	var sad := svc.cannot_buy(result["profile"], "want-%d" % (t - 3600), t)
	var journal: Array = sad["mind"]["journal"]
	if not str((journal[journal.size() - 1] as Dictionary)["text"]).contains("didn't have enough saved"):
		return "failed purchase not journaled: %s" % [journal[journal.size() - 1]]
	if svc.get_wants(sad).size() != 1:
		return "the want should still be saving"
	return null


func _test_wants_fade_after_a_week() -> Variant:
	var svc := MindService.new()
	var t := _local_unix(0, 12)
	var profile := _profile_with_wants([_saving_want(t - 8 * 86400)])
	var result := _decide_at(svc, profile, t, {}, _shop_town())
	if str(result["profile"]["mind"]["wants"][0]["status"]) != "faded":
		return "an 8 day old want should have faded: %s" % [result["profile"]["mind"]["wants"]]
	if not svc.get_wants(result["profile"]).is_empty():
		return "get_wants should exclude faded wants"
	return null


func _plan_entries(profile: Dictionary) -> Array:
	var rows: Array = []
	for entry in profile["mind"]["journal"]:
		if str(entry.get("kind", "")) == "plan":
			rows.append(entry)
	return rows


func _test_day_plan_made_each_morning() -> Variant:
	var svc := MindService.new()
	var town := _shop_town()
	var context := {"plans": true}
	var first := _decide_at(svc, _talk_profile(), _local_unix(0, 8), context, town)
	var entries := _plan_entries(first["profile"])
	if entries.size() != 1 or not str(entries[0]["text"]).begins_with("Today I'd like to "):
		return "plan not journaled: %s" % [entries]
	var plan := svc.get_day_plan(first["profile"])
	var items: Array = plan["items"]
	if items.size() < 1 or items.size() > 3:
		return "plan should have 1 to 3 items: %s" % [plan]
	var previous_window := -1
	for item in items:
		if int(item["window"]) <= previous_window:
			return "windows should ascend: %s" % [plan]
		previous_window = int(item["window"])
	var second := _decide_at(svc, first["profile"], _local_unix(0, 8, 30), context, town)
	if _plan_entries(second["profile"]).size() != 1 or JSON.stringify(svc.get_day_plan(second["profile"])) != JSON.stringify(plan):
		return "the plan should not be rebuilt the same day"
	var next_day := _decide_at(svc, second["profile"], _local_unix(1, 8), context, town)
	if int(svc.get_day_plan(next_day["profile"])["day"]) != int(plan["day"]) + 1 or _plan_entries(next_day["profile"]).size() < 2:
		return "the next morning should make a new plan: %s" % [svc.get_day_plan(next_day["profile"])]
	var late := _decide_at(svc, _talk_profile(), _local_unix(0, 13), context, town)
	for item in svc.get_day_plan(late["profile"])["items"]:
		if int(item["window"]) == 0:
			return "a plan made after lunch must not include this morning: %s" % [svc.get_day_plan(late["profile"])]
	var quiet := _decide_at(svc, _talk_profile(), _local_unix(0, 8), {}, town)
	if not _plan_entries(quiet["profile"]).is_empty() or not svc.get_day_plan(quiet["profile"]).is_empty():
		return "no plan unless plans is on"
	return null


func _test_day_plan_followed_or_missed() -> Variant:
	var svc := MindService.new()
	var town := _shop_town()
	var context := {"plans": true}
	var followed := _decide_at(svc, _talk_profile(), _local_unix(0, 9), context, town)
	var event: Dictionary = followed["event"]
	if not str(event.get("text", "")).begins_with("As I'd planned, I went to"):
		return "should have followed the morning plan: %s" % str(event.get("text", ""))
	var morning: Dictionary = svc.get_day_plan(followed["profile"])["items"][0]
	if not bool(morning["done"]) or bool(morning["missed"]):
		return "morning item should be done: %s" % [morning]

	# 7am: the cafe (the morning item) is still shut, so it is left undone.
	var early := _decide_at(svc, _talk_profile(), _local_unix(0, 7), context, town)
	var waiting: Dictionary = svc.get_day_plan(early["profile"])["items"][0]
	if bool(waiting["done"]):
		return "a shut place should leave the item undone: %s" % [waiting]
	var later := _decide_at(svc, early["profile"], _local_unix(0, 13), context, town)
	var missed: Dictionary = svc.get_day_plan(later["profile"])["items"][0]
	if not bool(missed["done"]) or not bool(missed["missed"]):
		return "morning item should be missed by 1pm: %s" % [missed]
	var found := false
	for entry in _plan_entries(later["profile"]):
		if str(entry["text"]).contains("but I didn't get round to it"):
			found = true
	if not found:
		return "the missed item was not journaled: %s" % [_plan_entries(later["profile"])]
	return null


func _test_suggestion_beats_want_and_plan() -> Variant:
	var svc := MindService.new()
	var town := _shop_town()
	var t := _local_unix(0, 9)
	var profile := _profile_with_wants([_saving_want(t - 3600)])
	var steered := svc.consider(profile, {"kind": "place", "id": "pond", "name": "the pond"}, t - 1, 9, town, NPCS)
	if str(steered["answer"]) != "yes":
		return "expected yes, got %s" % [steered]
	var context := {"plans": true, "meso": 100}
	var first := _decide_at(svc, steered["profile"], t, context, town)
	var event: Dictionary = first["event"]
	if str(event.get("because", "")) != "suggestion" or str(event.get("place_id", "")) != "pond" or event.has("buy_want"):
		return "the suggestion should win: %s" % [event]
	var second := _decide_at(svc, first["profile"], t + MindService.DECISION_INTERVAL_SECONDS, context, town)
	var next_event: Dictionary = second["event"]
	if str(next_event.get("buy_want", "")) != "want-%d" % (t - 3600):
		return "the want trip should come next: %s" % [next_event]
	return null


func _test_catch_up_buys_each_want_once() -> Variant:
	var svc := MindService.new()
	var town := _shop_town()
	var profile := svc.ensure_profile(_talk_profile())
	profile["mind"]["wants"] = [_saving_want(NOW - 3600, 50)]
	profile["mind"]["last_decision_unix"] = _local_unix(0, 11) - 3 * MindService.DECISION_INTERVAL_SECONDS
	# Enough for one purchase, not two: three catch-up decisions, one trip.
	var result := svc.tick(profile, NPCS, _local_unix(0, 11), {"meso": 100, "shop_items": []}, town)
	var trips := 0
	for event in result["events"]:
		if (event as Dictionary).has("buy_want"):
			trips += 1
	if trips != 1:
		return "one want, one trip: got %d" % trips
	# Two wants and plenty of money: each bought once, never the same one twice.
	var two := svc.ensure_profile(_talk_profile())
	var second := _saving_want(NOW - 1800, 30)
	second["id"] = "want-second"
	second["item_id"] = "wz-blue-cape"
	two["mind"]["wants"] = [_saving_want(NOW - 3600, 30), second]
	two["mind"]["last_decision_unix"] = _local_unix(0, 11) - 4 * MindService.DECISION_INTERVAL_SECONDS
	var both := svc.tick(two, NPCS, _local_unix(0, 11), {"meso": 500, "shop_items": []}, town)
	var bought: Array = []
	for event in both["events"]:
		if (event as Dictionary).has("buy_want"):
			if bought.has(str(event["buy_want"])):
				return "the same want was bought twice: %s" % [bought]
			bought.append(str(event["buy_want"]))
	if bought.size() != 2:
		return "both wants should get a trip: %s" % [bought]
	return null


func _test_yesterdays_plan_is_written_off() -> Variant:
	var svc := MindService.new()
	var town := _shop_town()
	var context := {"plans": true}
	var day_one := _decide_at(svc, _talk_profile(), _local_unix(0, 8), context, town)
	var items: Array = svc.get_day_plan(day_one["profile"])["items"]
	var undone := 0
	for item in items:
		if not bool(item["done"]):
			undone += 1
	if undone == 0:
		return "the test needs an unfinished item from day one"
	# The app was closed all evening; next morning the old plan is replaced.
	var day_two := _decide_at(svc, day_one["profile"], _local_unix(1, 8), context, town)
	var missed := 0
	for entry in day_two["profile"]["mind"]["journal"]:
		if str((entry as Dictionary).get("text", "")).contains("but I didn't get round to it"):
			missed += 1
	if missed < undone:
		return "yesterday's unfinished items were lost: %d of %d noted" % [missed, undone]
	if int(svc.get_day_plan(day_two["profile"])["day"]) != int(svc.get_day_plan(day_one["profile"])["day"]) + 1:
		return "today's plan should replace yesterday's"
	return null
