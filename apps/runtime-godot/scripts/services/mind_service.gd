extends RefCounted

# Self-directed life for the buddy. Nobody prompts these decisions: on a slow
# clock the buddy looks at how it feels (the mood modifiers the mood service
# already maintains), chooses something to do in its world, has an experience,
# and lets that experience change what it likes. Everything is recorded in a
# first-person journal so the user can read what it got up to.
#
# Deterministic by design: decisions are seeded from the profile and the
# decision timestamp, so a given history always replays the same way.

const DECISION_INTERVAL_SECONDS := 600
const MAX_CATCHUP_DECISIONS := 8
const JOURNAL_LIMIT := 40
const FEELING_MEMORY := 0.85
const WISH_BONUS := 0.35
const MAX_THOUGHT_CHARS := 200
const INTENTS := ["rest", "visit", "explore", "tend_home", "reflect"]
const INTENT_ACTIONS := {
	"rest": "sleep",
	"visit": "visitor",
	"explore": "happy",
	"tend_home": "sit",
	"reflect": "idle",
}
const INTENTION_HOURS := 12
const TALK_SOCIAL_BONUS := 0.25
const DISLIKE_LIMIT := -0.35
const TIRED_LIMIT := 0.75
const SUGGESTION_CUES := [
	"go to", "go see", "go and see", "go visit", "visit", "head to", "head over", "pop over",
	"pop into", "drop by", "try the", "check out", "you should", "why don't you", "why not go",
	"how about", "say hi to", "say hello to",
]
const INTENT_NEEDS := {
	"rest": "energy",
	"visit": "social",
	"explore": "curiosity",
	"tend_home": "comfort",
	"reflect": "reflection",
}
# Used when no town is supplied: a single always-open home.
const DEFAULT_TOWN_PLACES := [
	{"id": "home", "name": "home", "opens": 0, "closes": 24, "distance": 0, "residents": [],
		"activities": [
			{"id": "nap", "label": "had a nap", "satisfies": "energy"},
			{"id": "tidy", "label": "tidied up", "satisfies": "comfort"},
			{"id": "think", "label": "sat and thought", "satisfies": "reflection"},
		]},
]
const MIND_DEFAULTS := {
	"location": "home",
	"last_decision_unix": 0,
	"decision_count": 0,
	"restlessness": 0.4,
	"last_intent": "",
	"wish": "",
	"feelings": {},
	"journal": [],
	# Something the buddy agreed to do, from a suggestion or a place mentioned in
	# a talk: {"kind": "place"|"npc", "id", "name", "from": "suggestion"|"talk", "t", "until"}.
	"intention": {},
	"last_talk_unix": 0,
	"last_shared_t": 0,
}


func ensure_profile(profile: Dictionary) -> Dictionary:
	var merged := profile.duplicate(true)
	var mind_variant = merged.get("mind", null)
	var mind: Dictionary = {}
	if typeof(mind_variant) == TYPE_DICTIONARY:
		mind = (mind_variant as Dictionary).duplicate(true)
	# Constants are read-only all the way down, so copy before handing out.
	var defaults := MIND_DEFAULTS.duplicate(true)
	for key in defaults.keys():
		if not mind.has(key):
			mind[key] = defaults[key]
	if typeof(mind.get("feelings", null)) != TYPE_DICTIONARY:
		mind["feelings"] = {}
	if typeof(mind.get("journal", null)) != TYPE_ARRAY:
		mind["journal"] = []
	merged["mind"] = mind
	return merged


# Runs every decision that has come due since the last one, including the
# ones that came due while the app was closed (capped, and spread across the
# time away). Returns {"profile": Dictionary, "events": Array}; each event is
# the journal entry plus the animation "action" that expresses it.
func tick(profile: Dictionary, npcs: Array, now_unix: int, context: Dictionary, town: Dictionary = {}) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var last := int(mind.get("last_decision_unix", 0))
	var due_times: Array = []
	if last <= 0 or now_unix < last:
		due_times.append(now_unix)
	else:
		var due := int((now_unix - last) / DECISION_INTERVAL_SECONDS)
		if due > MAX_CATCHUP_DECISIONS:
			due = MAX_CATCHUP_DECISIONS
		for i in range(due):
			var remaining := due - 1 - i
			due_times.append(now_unix - remaining * DECISION_INTERVAL_SECONDS)

	var events: Array = []
	for index in range(due_times.size()):
		var decision_unix := int(due_times[index])
		var decision_context := context.duplicate(true)
		if index < due_times.size() - 1:
			# Past decisions happened unobserved; the live clock's day/night
			# reading only applies to the one happening right now.
			decision_context["is_night"] = _hour_is_night(decision_unix)
			decision_context["hour"] = _local_hour(decision_unix)
		events.append(_decide(merged, npcs, decision_unix, decision_context, town))
	return {"profile": merged, "events": events}


# Replaces the template wording of the decision made at `decision_unix` with
# the buddy's own words, and records what it said it wants to do next. Both
# inputs come from a language model, so they are re-checked here: the thought
# must be non-empty and the wish must be one of the known intents.
func apply_thought(profile: Dictionary, decision_unix: int, thought: String, want: String) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var journal: Array = mind["journal"]
	var text := thought.strip_edges()
	if text == "" or text.length() > MAX_THOUGHT_CHARS:
		return merged
	for index in range(journal.size() - 1, -1, -1):
		var entry_variant = journal[index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if int(entry.get("t", 0)) != decision_unix:
			continue
		entry["text"] = text
		entry["voiced"] = true
		journal[index] = entry
		if INTENTS.has(want):
			mind["wish"] = want
		break
	mind["journal"] = journal
	merged["mind"] = mind
	return merged


func get_journal(profile: Dictionary, limit: int = 5) -> Array:
	var journal: Array = ensure_profile(profile)["mind"]["journal"]
	if limit <= 0 or journal.size() <= limit:
		return journal.duplicate(true)
	return journal.slice(journal.size() - limit, journal.size())


func feeling_for(profile: Dictionary, subject_id: String) -> float:
	var feelings: Dictionary = ensure_profile(profile)["mind"]["feelings"]
	return float(feelings.get(subject_id, 0.0))


# Highest- and lowest-rated subjects the buddy has formed an opinion about.
func get_preferences(profile: Dictionary) -> Dictionary:
	var feelings: Dictionary = ensure_profile(profile)["mind"]["feelings"]
	var favourite := ""
	var least := ""
	var keys := feelings.keys()
	keys.sort()
	for key in keys:
		var value := float(feelings[key])
		if favourite == "" or value > float(feelings[favourite]):
			favourite = str(key)
		if least == "" or value < float(feelings[least]):
			least = str(key)
	return {"favourite": favourite, "least": least}


# The first town character or place named in `text`, as whole words. Town
# characters are checked before places; home is never a target.
func find_target(text: String, town: Dictionary, npcs: Array) -> Dictionary:
	var lowered := text.to_lower()
	for npc_variant in npcs:
		if typeof(npc_variant) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_variant
		var npc_id := str(npc.get("id", "")).strip_edges()
		var npc_name := str(npc.get("name", "")).strip_edges()
		if npc_id == "" or npc_name == "":
			continue
		if _has_whole_word(lowered, npc_name.to_lower()):
			return {"kind": "npc", "id": npc_id, "name": npc_name}
	for place_variant in _usable_places(town):
		var place: Dictionary = place_variant
		var place_id := str(place.get("id", "")).strip_edges()
		var place_name := str(place.get("name", "")).strip_edges()
		if place_id == "" or place_name == "" or place_id == "home":
			continue
		var bare := place_name.to_lower()
		if bare.begins_with("the "):
			bare = bare.substr(4)
		if bare != "" and _has_whole_word(lowered, bare):
			return {"kind": "place", "id": place_id, "name": place_name}
	return {}


func is_suggestion(text: String) -> bool:
	var lowered := text.to_lower()
	for cue in SUGGESTION_CUES:
		if lowered.contains(str(cue)):
			return true
	return false


# The buddy's answer to a suggestion: "yes", "later" or "no", with its reason.
# Yes and later both become an intention; no is noted in the journal instead.
func consider(
	profile: Dictionary, target: Dictionary, now_unix: int, hour: int, town: Dictionary, npcs: Array
) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var kind := str(target.get("kind", ""))
	var target_id := str(target.get("id", ""))
	var target_name := str(target.get("name", target_id))
	var is_npc := kind == "npc"
	var key := ("npc:" if is_npc else "place:") + target_id
	var feelings: Dictionary = mind["feelings"]
	var f := float(feelings.get(key, 0.0))
	var night := hour < 7 or hour >= 22
	var mods := _mood_modifiers(merged)

	var reachable := false
	if is_npc:
		for place_variant in _usable_places(town):
			var place: Dictionary = place_variant
			var residents = place.get("residents", [])
			if _place_is_open(place, hour) and typeof(residents) == TYPE_ARRAY and (residents as Array).has(target_id):
				reachable = true
	else:
		var found := false
		for place_variant in _usable_places(town):
			var place: Dictionary = place_variant
			if str(place.get("id", "")) == target_id:
				found = true
				reachable = _place_is_open(place, hour)
		if not found:
			return {"profile": merged, "answer": "no", "reason": "you have not heard of it"}

	var answer := "yes"
	var reason := ""
	if f <= DISLIKE_LIMIT:
		answer = "no"
		reason = "you don't like it there"
		if is_npc:
			reason = "you and %s don't really get on" % target_name
	elif night:
		answer = "later"
		reason = "it's late, so you'll go tomorrow"
	elif float(mods["energy_strain"]) >= TIRED_LIMIT:
		answer = "later"
		reason = "you're tired, so you'll go after a rest"
	elif not reachable:
		answer = "later"
		reason = "it's closed right now, so you'll go when it opens"
		if is_npc:
			reason = "%s isn't around right now, so you'll go when they are" % target_name
	elif f >= 0.2:
		reason = "you like it there"
		if is_npc:
			reason = "you like %s's company" % target_name
	else:
		reason = "it sounds nice"
		if is_npc:
			reason = "it would be nice to see %s" % target_name

	if answer == "no":
		var text := "You suggested %s, but I didn't feel like it." % target_name
		if is_npc:
			text = "You said I should see %s, but I didn't feel like it." % target_name
		_append_journal(mind, {
			"t": now_unix,
			"intent": "reflect",
			"subject_id": key,
			"subject_name": target_name,
			"valence": 0.0,
			"kind": "suggestion",
			"text": text,
		})
	else:
		mind["intention"] = _make_intention(kind, target_id, target_name, "suggestion", now_unix)
	merged["mind"] = mind
	return {"profile": merged, "answer": answer, "reason": reason}


# A finished conversation is an event in the buddy's day: it lifts the mood,
# lands in the journal, and a place or person mentioned in it may become
# something the buddy plans to go and see.
func note_talk(
	profile: Dictionary, summary: String, lines: Array, now_unix: int, town: Dictionary, npcs: Array
) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var mods_variant = merged.get("mood_modifiers", null)
	var mods: Dictionary = {}
	if typeof(mods_variant) == TYPE_DICTIONARY:
		mods = (mods_variant as Dictionary).duplicate(true)
	mods["social_fulfillment"] = _clamp01(float(_mood_modifiers(merged)["social_fulfillment"]) + TALK_SOCIAL_BONUS)
	merged["mood_modifiers"] = mods

	var text := "We talked for a while."
	if summary.strip_edges() != "":
		text = "We talked. " + summary.strip_edges()
	if text.length() > MAX_THOUGHT_CHARS:
		text = text.substr(0, MAX_THOUGHT_CHARS)
	_append_journal(mind, {
		"t": now_unix,
		"intent": "visit",
		"subject_id": "you",
		"subject_name": "you",
		"valence": 0.3,
		"kind": "talk",
		"text": text,
	})
	mind["last_talk_unix"] = now_unix

	var intention = mind.get("intention", {})
	var live := false
	if typeof(intention) == TYPE_DICTIONARY and not (intention as Dictionary).is_empty():
		live = int((intention as Dictionary).get("until", 0)) > now_unix
	if not live:
		for line in lines:
			# A suggestion was already answered when it was made (see consider);
			# a "no" must not turn into a plan here.
			if typeof(line) != TYPE_STRING or is_suggestion(str(line)):
				continue
			var target := find_target(line, town, npcs)
			if not target.is_empty():
				mind["intention"] = _make_intention(
					str(target["kind"]), str(target["id"]), str(target["name"]), "talk", now_unix
				)
				break
	merged["mind"] = mind
	return merged


# The journal entry most worth telling the person about when they open the
# chat: newer than the last talk or share, and either strongly felt or
# involving someone. Returns {} when there is nothing.
func pick_news(profile: Dictionary) -> Dictionary:
	var mind: Dictionary = ensure_profile(profile)["mind"]
	var floor_t := maxi(int(mind.get("last_shared_t", 0)), int(mind.get("last_talk_unix", 0)))
	var best := {}
	var best_strength := -1.0
	var best_t := 0
	for entry_variant in mind["journal"]:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var t := int(entry.get("t", 0))
		if t <= floor_t:
			continue
		var kind := str(entry.get("kind", ""))
		if kind == "talk" or kind == "suggestion":
			continue
		var strength := absf(float(entry.get("valence", 0.0)))
		if strength < 0.15 and str(entry.get("companion_name", "")) == "" and not entry.has("because"):
			continue
		if strength > best_strength or (is_equal_approx(strength, best_strength) and t >= best_t):
			best = entry
			best_strength = strength
			best_t = t
	return best.duplicate(true)


func mark_shared(profile: Dictionary, t: int) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	mind["last_shared_t"] = maxi(int(mind.get("last_shared_t", 0)), t)
	merged["mind"] = mind
	return merged


func _decide(
	merged: Dictionary, npcs: Array, decision_unix: int, context: Dictionary, town: Dictionary = {}
) -> Dictionary:
	var mind: Dictionary = merged["mind"]
	var count := int(mind.get("decision_count", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d" % [str(merged.get("personality_seed_tag", "")), decision_unix, count])

	var mods := _mood_modifiers(merged)
	var is_night := bool(context.get("is_night", false))
	var restlessness := _clamp01(float(mind.get("restlessness", 0.4)))
	var subjects := _visitable_npcs(npcs)
	var places := _usable_places(town)
	var hour := int(context.get("hour", -1))
	if hour == -1:
		hour = _local_hour(decision_unix)
	var open_places: Array = []
	for place_row in places:
		if _place_is_open(place_row, hour):
			open_places.append(place_row)

	var scores := {
		"rest": float(mods["energy_strain"]) * 1.4 + (0.5 if is_night else 0.0),
		"visit": (1.0 - float(mods["social_fulfillment"])) * 1.2 * (0.3 if is_night else 1.0),
		"explore": restlessness * 1.1 * (0.3 if is_night else 1.0),
		"tend_home": (1.0 - float(mods["comfort"])) * 1.0,
		"reflect": 0.25 + (0.3 if count > 0 and count % 5 == 4 else 0.0),
	}
	# Something the buddy said it felt like doing next (see apply_thought).
	# It nudges one decision and is then spent, whether or not it won.
	var wish := str(mind.get("wish", ""))
	if INTENTS.has(wish):
		scores[wish] = float(scores[wish]) + WISH_BONUS
	mind["wish"] = ""
	if subjects.is_empty() or _candidates_for_need(open_places, "social").is_empty():
		scores["visit"] = 0.0
	if str(context.get("top_trait", "")) == "curiosity":
		scores["explore"] = float(scores["explore"]) + 0.2

	# Something agreed to earlier (see consider / note_talk). Expired ones are
	# dropped; at night the buddy sleeps on it; otherwise it is honoured if the
	# place is open / the person is around, and kept for later if not.
	var honoured := {}
	var intention = mind.get("intention", {})
	if typeof(intention) == TYPE_DICTIONARY and not (intention as Dictionary).is_empty():
		if int((intention as Dictionary).get("until", 0)) <= decision_unix:
			mind["intention"] = {}
		# Worn out, it rests first: "later" for tiredness promised to go after
		# a rest, so nothing it agreed to is done while it is still this tired.
		elif not is_night and float(mods["energy_strain"]) < TIRED_LIMIT:
			honoured = _honour_intention(intention, mind["feelings"], open_places, subjects, scores, rng)
			if not honoured.is_empty():
				mind["intention"] = {}

	var intent := "reflect"
	var best := -1.0
	if not honoured.is_empty():
		intent = str(honoured["intent"])
	else:
		for candidate in INTENTS:
			var score := float(scores[candidate]) + rng.randf_range(-0.15, 0.15)
			if candidate == str(mind.get("last_intent", "")):
				score *= 0.5
			if score > best:
				best = score
				intent = candidate

	# Where, and doing what, to meet the need behind the intent.
	var candidates := _candidates_for_need(open_places, str(INTENT_NEEDS[intent]))
	var place: Dictionary = {}
	var activity: Dictionary = {}
	if not honoured.is_empty():
		place = honoured["place"]
		activity = honoured["activity"]
	elif candidates.is_empty():
		intent = "reflect"
		for home_variant in places:
			if str(home_variant.get("id", "")) == "home":
				place = home_variant
		if place.is_empty():
			place = (DEFAULT_TOWN_PLACES[0] as Dictionary).duplicate(true)
		activity = {"id": "think", "label": "sat and thought", "satisfies": "reflection"}
	else:
		var chosen := _pick_candidate(candidates, mind["feelings"], rng)
		place = chosen["place"]
		activity = chosen["activity"]

	var companion := {}
	if not honoured.is_empty():
		companion = honoured["companion"]
	elif intent == "visit":
		var local_subjects: Array = []
		var residents_variant = place.get("residents", [])
		if typeof(residents_variant) == TYPE_ARRAY:
			for row in subjects:
				if (residents_variant as Array).has(str(row["id"]).trim_prefix("npc:")):
					local_subjects.append(row)
		companion = _pick_by_feeling(local_subjects, mind["feelings"], rng)

	# How the experience felt. Confidence tilts it slightly; the rest is the
	# world being the world.
	var valence := rng.randf_range(-0.25, 0.6) + (float(mods["confidence"]) - 0.5) * 0.3
	valence = clampf(valence, -1.0, 1.0)

	var place_id := str(place.get("id", "home"))
	var place_name := str(place.get("name", place_id))
	var activity_id := str(activity.get("id", ""))
	var companion_name := str(companion.get("name", ""))
	var feelings: Dictionary = mind["feelings"]
	_bump_feeling(feelings, "place:%s" % place_id, valence)
	_bump_feeling(feelings, "activity:%s" % activity_id, valence)
	if not companion.is_empty():
		_bump_feeling(feelings, str(companion["id"]), valence)
	mind["location"] = place_id

	_apply_drive_effects(mods, intent)
	merged["mood_modifiers"] = mods
	if intent == "explore":
		restlessness = 0.0
	else:
		restlessness = _clamp01(restlessness + 0.2)
	mind["restlessness"] = restlessness

	var entry := {
		"t": decision_unix,
		"intent": intent,
		"subject_id": str(companion["id"]) if not companion.is_empty() else "place:%s" % place_id,
		"subject_name": companion_name if not companion.is_empty() else place_name,
		"valence": snappedf(valence, 0.01),
		"text": _compose_thought(
			intent, place, activity, companion_name, valence, get_preferences(merged), mind["feelings"], places
		),
		"place_id": place_id,
		"place_name": place_name,
		"activity_id": activity_id,
		"activity_label": str(activity.get("label", "")),
		"companion_name": companion_name,
	}
	if not honoured.is_empty():
		entry["text"] = str(honoured["prefix"]) + str(entry["text"])
		entry["because"] = str(honoured["because"])
	var journal: Array = mind["journal"]
	journal.append(entry)
	if journal.size() > JOURNAL_LIMIT:
		journal = journal.slice(journal.size() - JOURNAL_LIMIT, journal.size())
	mind["journal"] = journal
	mind["last_intent"] = intent
	mind["last_decision_unix"] = decision_unix
	mind["decision_count"] = count + 1
	merged["mind"] = mind

	var event := entry.duplicate(true)
	event["action"] = str(INTENT_ACTIONS.get(intent, "idle"))
	return event


# Works out how to act on an intention right now. Returns {} when it cannot be
# done yet (closed, nobody around); otherwise the intent, place, activity,
# companion, and the wording for the journal. Only draws from rng when picking
# a companion for a visit.
func _honour_intention(
	intention: Dictionary, feelings: Dictionary, open_places: Array, subjects: Array,
	scores: Dictionary, rng: RandomNumberGenerator
) -> Dictionary:
	var kind := str(intention.get("kind", ""))
	var target_id := str(intention.get("id", ""))
	var target_name := str(intention.get("name", target_id))
	var source := str(intention.get("from", ""))
	var prefix := "You mentioned %s, so I went. " % target_name
	if source == "suggestion":
		prefix = "You suggested %s, so I went. " % target_name
		if kind == "npc":
			prefix = "You said I should see %s, so I did. " % target_name
	var result := {"intent": "", "place": {}, "activity": {}, "companion": {}, "prefix": prefix, "because": source}

	if kind == "npc":
		var npc_place: Dictionary = {}
		var best_feeling := -INF
		for place_variant in open_places:
			var row: Dictionary = place_variant
			var residents = row.get("residents", [])
			if typeof(residents) != TYPE_ARRAY or not (residents as Array).has(target_id):
				continue
			if _first_activity(row, "").is_empty():
				continue
			var feeling := float(feelings.get("place:%s" % str(row.get("id", "")), 0.0))
			if feeling > best_feeling:
				best_feeling = feeling
				npc_place = row
		if npc_place.is_empty():
			return {}
		var npc_activity := _first_activity(npc_place, "social")
		if npc_activity.is_empty():
			npc_activity = _first_activity(npc_place, "")
		var npc_companion := {"id": "npc:" + target_id, "name": target_name}
		for subject_row in subjects:
			if str(subject_row["id"]) == "npc:" + target_id:
				npc_companion = subject_row
		result["intent"] = "visit"
		result["place"] = npc_place
		result["activity"] = npc_activity
		result["companion"] = npc_companion
		return result

	if kind == "place":
		var target_place: Dictionary = {}
		for place_variant in open_places:
			if str((place_variant as Dictionary).get("id", "")) == target_id:
				target_place = place_variant
		if target_place.is_empty():
			return {}
		var chosen_intent := ""
		var chosen_activity: Dictionary = {}
		var best_score := -INF
		for activity_variant in target_place["activities"]:
			if typeof(activity_variant) != TYPE_DICTIONARY:
				continue
			var candidate := ""
			for intent_key in INTENTS:
				if str(INTENT_NEEDS[intent_key]) == str((activity_variant as Dictionary).get("satisfies", "")):
					candidate = str(intent_key)
			if candidate == "":
				continue
			if float(scores[candidate]) > best_score:
				best_score = float(scores[candidate])
				chosen_intent = candidate
				chosen_activity = activity_variant
		if chosen_intent == "":
			return {}
		var place_companion := {}
		if chosen_intent == "visit":
			var local_subjects: Array = []
			var residents_variant = target_place.get("residents", [])
			if typeof(residents_variant) == TYPE_ARRAY:
				for subject_row in subjects:
					if (residents_variant as Array).has(str(subject_row["id"]).trim_prefix("npc:")):
						local_subjects.append(subject_row)
			place_companion = _pick_by_feeling(local_subjects, feelings, rng)
		result["intent"] = chosen_intent
		result["place"] = target_place
		result["activity"] = chosen_activity
		result["companion"] = place_companion
		return result
	return {}


# The first activity at a place that satisfies `need` ("" means any), or {}.
func _first_activity(place: Dictionary, need: String) -> Dictionary:
	var activities = place.get("activities", [])
	if typeof(activities) != TYPE_ARRAY:
		return {}
	for activity_variant in activities:
		if typeof(activity_variant) != TYPE_DICTIONARY:
			continue
		if need == "" or str((activity_variant as Dictionary).get("satisfies", "")) == need:
			return activity_variant
	return {}


func _make_intention(kind: String, target_id: String, target_name: String, source: String, now_unix: int) -> Dictionary:
	return {
		"kind": kind,
		"id": target_id,
		"name": target_name,
		"from": source,
		"t": now_unix,
		"until": now_unix + INTENTION_HOURS * 3600,
	}


func _append_journal(mind: Dictionary, entry: Dictionary) -> void:
	var journal: Array = mind["journal"]
	journal.append(entry)
	if journal.size() > JOURNAL_LIMIT:
		journal = journal.slice(journal.size() - JOURNAL_LIMIT, journal.size())
	mind["journal"] = journal


func _is_ascii_letter(ch: String) -> bool:
	if ch == "":
		return false
	var code := ch.unicode_at(0)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)


# True when `word` appears in `text` with no ASCII letter touching either end.
func _has_whole_word(text: String, word: String) -> bool:
	var start := 0
	while true:
		var at := text.find(word, start)
		if at < 0:
			return false
		var before := text.substr(at - 1, 1) if at > 0 else ""
		var after := text.substr(at + word.length(), 1)
		if not _is_ascii_letter(before) and not _is_ascii_letter(after):
			return true
		start = at + 1
	return false


func _mood_modifiers(profile: Dictionary) -> Dictionary:
	var mods := {"energy_strain": 0.0, "social_fulfillment": 0.0, "comfort": 0.5, "confidence": 0.5}
	var raw = profile.get("mood_modifiers", null)
	if typeof(raw) == TYPE_DICTIONARY:
		for key in mods.keys():
			var value = (raw as Dictionary).get(key, mods[key])
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				mods[key] = _clamp01(float(value))
	return mods


func _apply_drive_effects(mods: Dictionary, intent: String) -> void:
	if intent == "rest":
		mods["energy_strain"] = _clamp01(float(mods["energy_strain"]) - 0.35)
	elif intent == "visit":
		mods["social_fulfillment"] = _clamp01(float(mods["social_fulfillment"]) + 0.3)
		mods["energy_strain"] = _clamp01(float(mods["energy_strain"]) + 0.05)
	elif intent == "explore":
		mods["energy_strain"] = _clamp01(float(mods["energy_strain"]) + 0.1)
		mods["confidence"] = _clamp01(float(mods["confidence"]) + 0.05)
	elif intent == "tend_home":
		mods["comfort"] = _clamp01(float(mods["comfort"]) + 0.25)
	elif intent == "reflect":
		mods["confidence"] = _clamp01(float(mods["confidence"]) + 0.05)


func _visitable_npcs(npcs: Array) -> Array:
	var rows: Array = []
	for npc_variant in npcs:
		if typeof(npc_variant) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_variant
		var npc_id := str(npc.get("id", "")).strip_edges()
		if npc_id == "":
			continue
		rows.append({"id": "npc:%s" % npc_id, "name": str(npc.get("name", npc_id))})
	return rows


# Liked subjects are chosen more often, disliked ones less, but never never:
# the buddy can still change its mind about somewhere it wrote off.
func _pick_by_feeling(rows: Array, feelings: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if rows.is_empty():
		return {}
	var total := 0.0
	var weights: Array = []
	for row in rows:
		var weight := maxf(0.15, 1.0 + float(feelings.get(str(row["id"]), 0.0)))
		weights.append(weight)
		total += weight
	var roll := rng.randf() * total
	var cumulative := 0.0
	for index in range(rows.size()):
		cumulative += float(weights[index])
		if roll <= cumulative:
			return rows[index]
	return rows[rows.size() - 1]


func _compose_thought(
	intent: String, place: Dictionary, activity: Dictionary, companion_name: String,
	valence: float, preferences: Dictionary, feelings: Dictionary, places: Array
) -> String:
	var liked := valence >= 0.2
	var disliked := valence < -0.05
	var at_home := str(place.get("id", "")) == "home"
	var label := str(activity.get("label", ""))
	if intent == "reflect":
		# Reflect on somewhere or someone, never on an activity label.
		var favourite := _strongest_place_or_person(feelings, true)
		if favourite != "" and float(feelings.get(favourite, 0.0)) > 0.15:
			if favourite.begins_with("npc:"):
				return "I've been thinking about %s. I like their company." % _subject_label(favourite, places).trim_suffix("'s")
			return "I've been thinking. I keep going back to %s; I think I like it there." % _subject_label(favourite, places)
		var least := _strongest_place_or_person(feelings, false)
		if least != "" and float(feelings.get(least, 0.0)) < -0.15:
			if least.begins_with("npc:"):
				return "I've been thinking about %s. I'm not sure we get on." % _subject_label(least, places).trim_suffix("'s")
			return "I've been thinking. I don't think %s is for me." % _subject_label(least, places)
		return "I sat and thought for a bit. I'm still working out what I like."
	var tone := "It was fine."
	if liked:
		tone = "It felt good." if at_home else "I didn't want to leave."
	elif disliked:
		tone = "I couldn't settle." if at_home else "Not sure it's for me."
	if at_home:
		return "I %s at home. %s" % [label, tone]
	var place_name := str(place.get("name", place.get("id", "")))
	if companion_name != "":
		return "I went to %s and %s with %s. %s" % [place_name, label, companion_name, tone]
	return "I went to %s and %s. %s" % [place_name, label, tone]


func _subject_label(subject_id: String, places: Array) -> String:
	if subject_id.begins_with("place:"):
		var place_id := subject_id.trim_prefix("place:")
		for place in places:
			if str(place.get("id", "")) == place_id:
				return str(place.get("name", place_id))
		return place_id
	if subject_id.begins_with("activity:"):
		var activity_id := subject_id.trim_prefix("activity:")
		for place in places:
			for activity in place.get("activities", []):
				if str(activity.get("id", "")) == activity_id:
					return str(activity.get("label", activity_id))
		return activity_id
	if subject_id.begins_with("npc:"):
		return subject_id.trim_prefix("npc:").capitalize() + "'s"
	return subject_id


# Rows with usable shape only; falls back to a lone always-open home.
func _usable_places(town: Dictionary) -> Array:
	var rows: Array = []
	var places_variant = town.get("places", null)
	if typeof(places_variant) == TYPE_ARRAY:
		for place_variant in places_variant:
			if typeof(place_variant) != TYPE_DICTIONARY:
				continue
			var place: Dictionary = place_variant
			if str(place.get("id", "")).strip_edges() == "":
				continue
			if typeof(place.get("activities", null)) != TYPE_ARRAY:
				continue
			rows.append(place)
	if rows.is_empty():
		return DEFAULT_TOWN_PLACES.duplicate(true)
	return rows


func _place_is_open(place: Dictionary, hour: int) -> bool:
	return int(place.get("opens", 0)) <= hour and hour < int(place.get("closes", 24))


func _candidates_for_need(open_places: Array, need: String) -> Array:
	var rows: Array = []
	for place in open_places:
		for activity_variant in place["activities"]:
			if typeof(activity_variant) != TYPE_DICTIONARY:
				continue
			if str((activity_variant as Dictionary).get("satisfies", "")) == need:
				rows.append({"place": place, "activity": activity_variant})
	return rows


func _pick_candidate(candidates: Array, feelings: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	var weights: Array = []
	for row in candidates:
		var place: Dictionary = row["place"]
		var activity: Dictionary = row["activity"]
		var place_feeling := float(feelings.get("place:%s" % str(place.get("id", "")), 0.0))
		var activity_feeling := float(feelings.get("activity:%s" % str(activity.get("id", "")), 0.0))
		var raw := maxf(0.15, 1.0 + place_feeling * 0.7 + activity_feeling * 0.5)
		var weight := raw / (1.0 + 0.25 * float(place.get("distance", 0)))
		weights.append(weight)
		total += weight
	var roll := rng.randf() * total
	var cumulative := 0.0
	for index in range(candidates.size()):
		cumulative += float(weights[index])
		if roll <= cumulative:
			return candidates[index]
	return candidates[candidates.size() - 1]


func _bump_feeling(feelings: Dictionary, key: String, valence: float) -> void:
	var previous := float(feelings.get(key, 0.0))
	feelings[key] = clampf(previous * FEELING_MEMORY + valence * 0.5, -1.0, 1.0)


func _local_hour(unix_time: int) -> int:
	var local_unix := unix_time + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return int(Time.get_datetime_dict_from_unix_time(local_unix).get("hour", 12))


# The most liked (or least liked) place or town character, by feeling.
func _strongest_place_or_person(feelings: Dictionary, want_highest: bool) -> String:
	var best := ""
	var keys := feelings.keys()
	keys.sort()
	for key_variant in keys:
		var key := str(key_variant)
		if key == "place:home":
			continue
		if not key.begins_with("place:") and not key.begins_with("npc:"):
			continue
		var value := float(feelings[key_variant])
		if best == "":
			best = key
		elif want_highest and value > float(feelings[best]):
			best = key
		elif not want_highest and value < float(feelings[best]):
			best = key
	return best


func _hour_is_night(unix_time: int) -> bool:
	var hour := _local_hour(unix_time)
	return hour < 7 or hour >= 22


func _clamp01(value: float) -> float:
	return minf(1.0, maxf(0.0, value))
