extends RefCounted

# Self-directed life for the buddy. Nobody prompts these decisions: on a slow
# clock the buddy looks at how it feels (the mood modifiers the mood service
# already maintains), chooses something to do in its world, has an experience,
# and lets that experience change what it likes. Everything is recorded in a
# first-person journal so the user can read what it got up to.
#
# Deterministic by design: decisions are seeded from the profile and the
# decision timestamp, so a given history always replays the same way.

const LetterService = preload("res://scripts/services/letter_service.gd")

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
const MAX_OPEN_WANTS := 3
const WANT_NOTICE_CHANCE := 0.4
const WANT_FADE_DAYS := 7
const WANT_RESERVE_MESO := 20
const PLAN_WINDOWS := [[7, 12], [12, 17], [17, 22]]
const PLAN_WINDOW_NAMES := ["this morning", "this afternoon", "this evening"]
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
	# Things it saw in a shop and is saving for: {"id", "item_id", "name", "slot",
	# "price", "reason", "t", "status": "saving"|"bought"|"faded", "place_id"}.
	"wants": [],
	# Today's plan: {"day", "items": [{"kind": "place"|"npc", "id", "name", "window",
	# "done", "missed", "phrase"}]}.
	"day_plan": {},
	# Small beginnings (Plan 14). Places it has a sign of or has found:
	# {place_id: {"stage": "sign"|"found", "t", "tries"}}. Home is always known.
	"known_places": {},
	# Things it has noticed on its land, once each: {sight_id: t}.
	"seen": {},
	# Things it meets again on its land (land_data "things"):
	# {thing_id: {"met", "first_t", "last_t", "name", "named_t"}}. The sight is
	# meeting 1; "name" is its own name for it, once it has one.
	"things": {},
	# How many times it has done each activity: {activity_id: count}.
	"done": {},
	# It is in the middle of something until this time; nothing is decided before then.
	"busy_until": 0,
	# Where it was born: "land" for a buddy that started small (Plan 14).
	# Anything else is a buddy from before (see AppState.fresh_start_if_due).
	"born": "",
	# Visits to the person's desktop (Plan 14 step 2a): when it left for one,
	# why, and when the last one ended. 0 / "" while it is at home.
	"visit_left_unix": 0,
	"visit_reason": "",
	"last_visit_end_unix": 0,
}

# --- Small beginnings (Plan 14 step 1b) ---------------------------------
# With context["small_beginnings"], the town passed to tick() is the whole
# land (land_data.gd). The buddy only uses the places it has found, finds more
# by going to the edge of what it knows, notices things once, and what it does
# takes time. None of this runs in the old town.
#
# The numbers below were tuned by reading 30-day runs of the fast-forward tool
# (tools/simulate_days.py --world land); LandLifeTest pins what they add up to.
# How often an explore goes to the edge of what it knows, while there is one.
const LAND_EDGE_CHANCE := 0.55
# Added to explore's score by day while it has a sign of somewhere unreached.
const LAND_SIGN_PULL := 0.2
# Each failed try makes the next one this much more likely. A place is tried
# at most once a day after a failure.
const LAND_TRY_BONUS := 0.05
const LAND_SIGHT_CHANCE := 0.12
# With free exploration (2026-11-21) it spreads its attention over the whole
# land; a creature's first sight is this much likelier to be the one noticed,
# so it still meets and names a neighbour in its first week.
const LAND_CREATURE_SIGHT_WEIGHT := 3.0
# When it has nothing new to notice, how often it meets a thing that lives here
# again, and which meeting gives the thing its own name (the sight is meeting 1).
# Raised from 0.3 with free exploration (2026-11-21): roaming wider, it met its
# neighbours too seldom to name one in its first week.
const LAND_MEET_CHANCE := 0.4
const LAND_NAME_AFTER := 3
const LAND_WONDER_CHANCE := 0.5
const LAND_GOOD_TAIL_CHANCE := 0.4
# An activity's own "bad" line is used when it went this badly (about one time
# in eight); a milder dislike gets an ordinary line with a short tail.
const LAND_BAD_LINE_BELOW := -0.15
# A journal line never grows past this with what it noticed or wondered about.
const LAND_MAX_LINE_CHARS := 240
const LAND_DEFAULT_MINUTES := 20
const LAND_TRAVEL_MINUTES := 5
# Free exploration (owner, 2026-11-21): there are no paths. A try for a place
# it has not found starts from the nearest place it knows (or home) within
# LAND_REACH on the land's map (1 across, about 64 m), in any direction; a walk
# takes LAND_TRAVEL_MINUTES for every LAND_HOP of the straight way there; and
# of two places that would do, the nearer to home (as the crow flies) is
# likelier. A land with no map (the old town, test lands) keeps its "from"
# lists and hops.
const LAND_REACH := 0.28
const LAND_HOP := 0.15
# It thinks less and does more here than in the old town.
const LAND_REFLECT_SCALE := 0.6
# A slot is one decision interval (10 minutes). A day awake tires it by about
# 0.7, and a night's sleep mends it.
const LAND_TIRE_PER_SLOT := 0.0065
const LAND_EXPLORE_TIRE_PER_SLOT := 0.004
const LAND_REST_PER_SLOT := 0.035
const LAND_SLEEP_PER_SLOT := 0.016
const LAND_RESTED := 0.05
# By day it only thinks of resting once it is this tired; at night, once it is
# tired enough to sleep.
const LAND_NAP_FLOOR := 0.45
const LAND_NIGHT_REST_FLOOR := 0.25
const LAND_COMFORT_FADE_PER_SLOT := 0.006
# Company lost per awake slot on its own land (nobody else lives there).
const LAND_COMPANY_FADE_PER_SLOT := 0.005
# Below this much company it may decide to visit the person.
const LAND_LONELY_BELOW := 0.35
# How much company a buddy has when it wakes on the land for the first time
# (AppState._fresh_start), so it gets lonely slowly, about a day of being awake.
const LAND_START_COMPANY := 0.6
# Company gained per slot (10 minutes) of a visit.
const VISIT_COMPANY_PER_SLOT := 0.06
# No visit of its own accord within this long after a visit ended.
const SELF_VISIT_GAP_SECONDS := 3 * 3600
# When the world host takes the buddy after being away this long (it was not
# running, or the PC slept), the journal says there was a stretch it does not
# remember; a shorter gap is only the host's ordinary restart.
const HOST_GAP_NOTE_SECONDS := 3 * 3600
# From this hour, and before 5, it is bedtime.
const VISIT_BEDTIME_HOUR := 21
# From 19:00 it is bedtime once this tired.
const VISIT_TIRED_EVENING := 0.45
# Called at bedtime, it comes at this hour the next morning instead.
const VISIT_MORNING_HOUR := 7
const LAND_COMFORT_FADE_ASLEEP_PER_SLOT := 0.003
const LAND_COMFORT_GAIN_PER_SLOT := 0.05
# How hard its confidence is pulled back toward the middle each decision.
const LAND_CONFIDENCE_PULL := 0.03
const LAND_EDGE_ACTIVITY := {"id": "edge", "label": "went to the edge of what I know", "satisfies": "curiosity", "minutes": 30}
const LAND_ARRIVE_ACTIVITY := {"id": "arrive", "label": "found somewhere new", "satisfies": "curiosity", "minutes": 40}
const LAND_WAKE_ACTIVITY := {"id": "wake", "label": "woke up", "satisfies": "reflection", "minutes": 20}

# The glowing box is the console (Plan 14 step 2c-1). On the third time it goes
# to it, it works out that the box is a way to talk to the person; until then,
# letters wait there. mind["console"] = {"goes", "known", "known_t"}.
const CONSOLE_ACTIVITY_ID := "glowing_box"
const CONSOLE_GOES_TO_LEARN := 3
# While a letter waits and it does not know the box yet, each awake, rested
# decision has this chance to go and look at the blinking box.
const LETTER_BLINK_CHANCE := 0.25
const CONSOLE_LEARNED_LINE := "I watched the glowing box for a long time. Small marks came up on it, and when I touched them they changed. I think it is a way to talk to you."
const CONSOLE_READ_AFTER_LEARNING := " Then I read what you wrote."
const CONSOLE_READ_ONE_LINE := "I read your letter at the glowing box."
const CONSOLE_READ_MANY_LINE := "I read your letters at the glowing box."
const CONSOLE_BLINK_LINE := "The glowing box was blinking. I watched it for a while, but I don't know what it wants."
# The journal lines for a letter it wrote at the box (note_letter_written).
const LETTER_REPLY_LINE := "I wrote back to you at the glowing box."
const LETTER_FIRST_LINE := "I wrote you my first letter at the glowing box."


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
	if typeof(mind.get("wants", null)) != TYPE_ARRAY:
		mind["wants"] = []
	if typeof(mind.get("day_plan", null)) != TYPE_DICTIONARY:
		mind["day_plan"] = {}
	for key in ["known_places", "seen", "things", "done"]:
		if typeof(mind.get(key, null)) != TYPE_DICTIONARY:
			mind[key] = {}
	merged["mind"] = mind
	return merged


# Tests set this to 0 to see the same life without any meetings.
var meet_chance := LAND_MEET_CHANCE

# Set by the fast-forward simulator so a replay does not depend on the machine's time zone.
var _pinned_bias_minutes := 0
var _bias_is_pinned := false


func set_time_zone_bias_minutes(minutes: int) -> void:
	_pinned_bias_minutes = minutes
	_bias_is_pinned = true


func _time_zone_bias_minutes() -> int:
	if _bias_is_pinned:
		return _pinned_bias_minutes
	return int(Time.get_time_zone_from_system().get("bias", 0))


# Runs every decision that has come due since the last one, including the
# ones that came due while the app was closed (capped, and spread across the
# time away). Returns {"profile": Dictionary, "events": Array}; each event is
# the journal entry plus the animation "action" that expresses it.
func tick(profile: Dictionary, npcs: Array, now_unix: int, context: Dictionary, town: Dictionary = {}) -> Dictionary:
	var small := bool(context.get("small_beginnings", false))
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
	# Catch-up decisions are worked out together, before any purchase is paid
	# for, so each one is told what the trips before it have already spent.
	var meso_left := int(context.get("meso", 0))
	for index in range(due_times.size()):
		var decision_unix := int(due_times[index])
		# In the middle of something (asleep, out at the water): nothing to decide yet.
		if small and decision_unix < int((merged["mind"] as Dictionary).get("busy_until", 0)):
			continue
		var decision_context := context.duplicate(true)
		if decision_context.has("meso"):
			decision_context["meso"] = meso_left
		if index < due_times.size() - 1:
			# Past decisions happened unobserved; the live clock's day/night
			# reading only applies to the one happening right now.
			decision_context["is_night"] = _hour_is_night(decision_unix)
			decision_context["hour"] = _local_hour(decision_unix)
		var event := _decide(merged, npcs, decision_unix, decision_context, town)
		if event.has("buy_want"):
			meso_left -= _want_price(merged["mind"], str(event["buy_want"]))
		events.append(event)
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
		if kind == "talk" or kind == "suggestion" or kind == "plan":
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


# The buddy bought what it was saving for. `equipped` is whether it is now wearing it.
func complete_want(profile: Dictionary, want_id: String, t: int, equipped: bool) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	for want_variant in mind["wants"]:
		if typeof(want_variant) != TYPE_DICTIONARY or str((want_variant as Dictionary).get("id", "")) != want_id:
			continue
		var want: Dictionary = want_variant
		want["status"] = "bought"
		want["bought_t"] = t
		var name := str(want.get("name", ""))
		var text := "I bought the %s I'd been saving for." % name
		if equipped:
			text += " I'm wearing it now."
		_append_journal(mind, {
			"t": t + 1,
			"intent": "tend_home",
			"kind": "purchase",
			"valence": 0.6,
			"subject_id": "item:" + str(want.get("item_id", "")),
			"subject_name": name,
			"text": text,
		})
		break
	merged["mind"] = mind
	return merged


# The trip to buy it failed for want of meso; the want stays on the list.
func cannot_buy(profile: Dictionary, want_id: String, t: int) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	for want_variant in mind["wants"]:
		if typeof(want_variant) != TYPE_DICTIONARY or str((want_variant as Dictionary).get("id", "")) != want_id:
			continue
		var want: Dictionary = want_variant
		var name := str(want.get("name", ""))
		want["status"] = "saving"
		_append_journal(mind, {
			"t": t + 1,
			"intent": "reflect",
			"kind": "purchase",
			"valence": -0.1,
			"subject_id": "item:" + str(want.get("item_id", "")),
			"subject_name": name,
			"text": "I looked at the %s again, but I didn't have enough saved." % name,
		})
		break
	merged["mind"] = mind
	return merged


# What it is saving for (or on its way to buy), oldest first.
func get_wants(profile: Dictionary) -> Array:
	var rows: Array = []
	for want_variant in ensure_profile(profile)["mind"]["wants"]:
		if typeof(want_variant) == TYPE_DICTIONARY and str((want_variant as Dictionary).get("status", "")) in ["saving", "buying"]:
			rows.append((want_variant as Dictionary).duplicate(true))
	return rows


func _want_price(mind: Dictionary, want_id: String) -> int:
	for want_variant in mind.get("wants", []):
		if typeof(want_variant) == TYPE_DICTIONARY and str((want_variant as Dictionary).get("id", "")) == want_id:
			return int((want_variant as Dictionary).get("price", 0))
	return 0


func get_day_plan(profile: Dictionary) -> Dictionary:
	return (ensure_profile(profile)["mind"]["day_plan"] as Dictionary).duplicate(true)


func _decide(
	merged: Dictionary, npcs: Array, decision_unix: int, context: Dictionary, town: Dictionary = {}
) -> Dictionary:
	var mind: Dictionary = merged["mind"]
	var count := int(mind.get("decision_count", 0))
	var small := bool(context.get("small_beginnings", false))
	# Wants it has been saving for too long fade quietly.
	for want_variant in mind["wants"]:
		if typeof(want_variant) != TYPE_DICTIONARY:
			continue
		var old_want: Dictionary = want_variant
		if str(old_want.get("status", "")) == "saving" and int(old_want.get("t", 0)) + WANT_FADE_DAYS * 86400 <= decision_unix:
			old_want["status"] = "faded"
	var rng := RandomNumberGenerator.new()
	if small:
		# The buddy's own seed joins in, so no two buddies live the same life.
		rng.seed = hash("%s|%d|%d|%d" % [str(merged.get("personality_seed_tag", "")), int(merged.get("personality_seed", 0)), decision_unix, count])
	else:
		rng.seed = hash("%s|%d|%d" % [str(merged.get("personality_seed_tag", "")), decision_unix, count])

	var mods := _mood_modifiers(merged)
	var is_night := bool(context.get("is_night", false))
	var restlessness := _clamp01(float(mind.get("restlessness", 0.4)))
	var subjects := _visitable_npcs(npcs)
	var places := _usable_places(town)
	var all_places: Array = places
	var home_id := str(town.get("home_place", "home"))
	if small:
		places = _found_places(all_places, mind, home_id)
	var hour := int(context.get("hour", -1))
	if hour == -1:
		hour = _local_hour(decision_unix)
	var gate_hour := hour if small else -1
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
	if small:
		scores["reflect"] = float(scores["reflect"]) * LAND_REFLECT_SCALE
		var tiredness := float(mods["energy_strain"])
		if is_night:
			# Night only pulls it to bed once it is tired enough to sleep.
			if tiredness < LAND_NIGHT_REST_FLOOR:
				scores["rest"] = tiredness * 1.4
		else:
			# By day it keeps going until it is properly tired, so the
			# tiredness is still there to send it to bed at night.
			scores["rest"] = maxf(0.0, tiredness - LAND_NAP_FLOOR) * 2.0 + (WISH_BONUS if wish == "rest" else 0.0)
			# Somewhere it has a sign of keeps pulling at it.
			if _has_open_sign(mind):
				scores["explore"] = float(scores["explore"]) + LAND_SIGN_PULL

	# A letter waiting at the glowing box draws it there before anything else it
	# had in mind (asleep it does not wake for one: it has no decisions then, and
	# at night the pull waits for morning). Once it knows the box it goes to read;
	# before, the blinking box draws it now and then. Draws no rng without a letter.
	# Only letters sent by the time of this decision count: catch-up decisions are
	# replayed for times already past.
	var letter_pull := ""
	var box_place: Dictionary = {}
	var box_activity: Dictionary = {}
	if small and count > 0 and not is_night and float(mods["energy_strain"]) < TIRED_LIMIT and LetterService.has_unread(merged, decision_unix):
		for place_variant in places:
			if str((place_variant as Dictionary).get("id", "")) != home_id:
				continue
			for activity_variant in ((place_variant as Dictionary).get("activities", []) as Array):
				if typeof(activity_variant) == TYPE_DICTIONARY and str((activity_variant as Dictionary).get("id", "")) == CONSOLE_ACTIVITY_ID:
					box_place = place_variant
					box_activity = activity_variant
		if not box_place.is_empty():
			if bool(_console(mind).get("known", false)):
				letter_pull = "read"
			elif rng.randf() < LETTER_BLINK_CHANCE:
				letter_pull = "blink"

	# Something agreed to earlier (see consider / note_talk). Expired ones are
	# dropped; at night the buddy sleeps on it; otherwise it is honoured if the
	# place is open / the person is around, and kept for later if not.
	var plans_on := bool(context.get("plans", false))
	if plans_on:
		_update_day_plan(mind, npcs, places, decision_unix, hour, is_night)

	var honoured := {}
	var intention = mind.get("intention", {})
	if typeof(intention) == TYPE_DICTIONARY and not (intention as Dictionary).is_empty():
		if int((intention as Dictionary).get("until", 0)) <= decision_unix:
			mind["intention"] = {}
		# Worn out, it rests first: "later" for tiredness promised to go after
		# a rest, so nothing it agreed to is done while it is still this tired.
		elif not is_night and float(mods["energy_strain"]) < TIRED_LIMIT and letter_pull == "":
			honoured = _honour_intention(intention, mind["feelings"], open_places, subjects, scores, rng, mind["wants"], gate_hour)
			if not honoured.is_empty():
				mind["intention"] = {}

	# Saved up enough for something it wants: head for the shop.
	var intention_now = mind.get("intention", {})
	var rested := float(mods["energy_strain"]) < TIRED_LIMIT
	if honoured.is_empty() and letter_pull == "" and not is_night and rested and typeof(intention_now) == TYPE_DICTIONARY and (intention_now as Dictionary).is_empty():
		var meso := int(context.get("meso", 0))
		var wanted := {}
		for want_variant in mind["wants"]:
			if typeof(want_variant) != TYPE_DICTIONARY:
				continue
			var want_row: Dictionary = want_variant
			if str(want_row.get("status", "")) == "saving" and int(want_row.get("price", 0)) + WANT_RESERVE_MESO <= meso:
				wanted = want_row
				break
		if not wanted.is_empty():
			var shop := _shop_for_want(wanted, places)
			if not shop.is_empty():
				var trip := _make_intention("place", str(shop.get("id", "")), str(shop.get("name", "")), "want", decision_unix)
				trip["want_id"] = str(wanted.get("id", ""))
				mind["intention"] = trip
				honoured = _honour_intention(trip, mind["feelings"], open_places, subjects, scores, rng, mind["wants"], gate_hour)
				if not honoured.is_empty():
					mind["intention"] = {}

	# Today's plan: do the item for this part of the day if nothing else is steering.
	if plans_on and honoured.is_empty() and letter_pull == "" and not is_night and rested:
		var plan_items_variant = (mind["day_plan"] as Dictionary).get("items", [])
		var plan_items: Array = plan_items_variant if typeof(plan_items_variant) == TYPE_ARRAY else []
		for item_index in range(plan_items.size()):
			if typeof(plan_items[item_index]) != TYPE_DICTIONARY:
				continue
			var plan_item: Dictionary = plan_items[item_index]
			var window := int(plan_item.get("window", 0))
			if bool(plan_item.get("done", false)) or window < 0 or window >= PLAN_WINDOWS.size():
				continue
			if hour < int(PLAN_WINDOWS[window][0]) or hour >= int(PLAN_WINDOWS[window][1]):
				continue
			var plan_intention := _make_intention(
				str(plan_item.get("kind", "")), str(plan_item.get("id", "")), str(plan_item.get("name", "")), "plan", decision_unix
			)
			honoured = _honour_intention(plan_intention, mind["feelings"], open_places, subjects, scores, rng, mind["wants"], gate_hour)
			if not honoured.is_empty():
				plan_item["done"] = true
			break

	var intent := "reflect"
	var best := -1.0
	if not honoured.is_empty():
		intent = str(honoured["intent"])
	elif letter_pull != "":
		intent = "explore"
	else:
		for candidate in INTENTS:
			if small and candidate == "visit":
				# Nobody else lives on the land.
				continue
			var score := float(scores[candidate]) + rng.randf_range(-0.15, 0.15)
			if candidate == str(mind.get("last_intent", "")):
				score *= 0.5
			if score > best:
				best = score
				intent = candidate

	# Where, and doing what, to meet the need behind the intent.
	var candidates := _candidates_for_need(open_places, str(INTENT_NEEDS[intent]), gate_hour)
	var place: Dictionary = {}
	var activity: Dictionary = {}
	var edge := {}
	# Its very first moment on the land: it wakes up at home.
	var waking := ""
	if small and count == 0 and honoured.is_empty():
		waking = str(town.get("waking", ""))
	if small and waking == "" and honoured.is_empty() and letter_pull == "" and intent == "explore":
		edge = _try_the_edge(all_places, mind, home_id, hour, decision_unix, rng)
	if waking != "":
		intent = "reflect"
		for home_variant in places:
			if str(home_variant.get("id", "")) == home_id:
				place = home_variant
		activity = LAND_WAKE_ACTIVITY
	elif not edge.is_empty():
		place = edge["place"]
		activity = edge["activity"]
	elif not honoured.is_empty():
		place = honoured["place"]
		activity = honoured["activity"]
	elif letter_pull != "":
		place = box_place
		activity = box_activity
	elif candidates.is_empty():
		intent = "reflect"
		for home_variant in places:
			if str(home_variant.get("id", "")) == "home":
				place = home_variant
		if place.is_empty():
			place = (DEFAULT_TOWN_PLACES[0] as Dictionary).duplicate(true)
		activity = {"id": "think", "label": "sat and thought", "satisfies": "reflection"}
	else:
		var chosen := _pick_candidate(candidates, mind["feelings"], rng, _place_by_id(all_places, home_id))
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
	if not edge.is_empty():
		valence += float(edge["valence_shift"])
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
	var came_from := str(mind.get("location", home_id))
	mind["location"] = place_id

	var slots := 1
	if small:
		slots = _land_slots(activity, place, came_from, decision_unix, rng, all_places)
		_apply_land_needs(mods, activity, slots, valence, str(edge.get("kind", "")))
	else:
		_apply_drive_effects(mods, intent)
	merged["mood_modifiers"] = mods
	if intent == "explore":
		restlessness = 0.0
	else:
		restlessness = _clamp01(restlessness + 0.2)
	mind["restlessness"] = restlessness

	var text := ""
	var times_before := 0
	# At the glowing box: what it worked out or read there (its own line, with
	# no tail or afterthought after it).
	var box_text := false
	var learned := ""
	var read_ids: Array = []
	if small:
		var done: Dictionary = mind["done"]
		times_before = int(done.get(activity_id, 0))
		if waking != "":
			text = waking
		elif not edge.is_empty():
			text = str(edge["text"])
		else:
			text = _land_text(activity, times_before, valence, int(merged.get("personality_seed", 0)), rng)
		done[activity_id] = times_before + 1
		if activity_id == CONSOLE_ACTIVITY_ID and place_id == home_id:
			var console: Dictionary = _console(mind)
			console["goes"] = int(console["goes"]) + 1
			var waiting_ids: Array = []
			for waiting_letter in LetterService.unread_from_you(merged, decision_unix):
				waiting_ids.append(str((waiting_letter as Dictionary)["id"]))
			if not bool(console["known"]) and int(console["goes"]) >= CONSOLE_GOES_TO_LEARN:
				console["known"] = true
				console["known_t"] = decision_unix
				mind["first_letter_due"] = true
				learned = "console"
				text = CONSOLE_LEARNED_LINE
				if not waiting_ids.is_empty():
					text += CONSOLE_READ_AFTER_LEARNING
					read_ids = waiting_ids
				box_text = true
			elif bool(console["known"]) and not waiting_ids.is_empty():
				read_ids = waiting_ids
				text = CONSOLE_READ_ONE_LINE if waiting_ids.size() == 1 else CONSOLE_READ_MANY_LINE
				box_text = true
			elif letter_pull == "blink":
				text = CONSOLE_BLINK_LINE
				box_text = true
			mind["console"] = console
			if not read_ids.is_empty():
				merged["letters"] = LetterService.mark_read(merged, read_ids, decision_unix)["letters"]
	if text == "":
		text = _compose_thought(
			intent, place, activity, companion_name, valence, get_preferences(merged), mind["feelings"], places
		)
	var entry := {
		"t": decision_unix,
		"intent": intent,
		"subject_id": str(companion["id"]) if not companion.is_empty() else "place:%s" % place_id,
		"subject_name": companion_name if not companion.is_empty() else place_name,
		"valence": snappedf(valence, 0.01),
		"text": text,
		"place_id": place_id,
		"place_name": place_name,
		"activity_id": activity_id,
		"activity_label": str(activity.get("label", "")),
		"companion_name": companion_name,
	}
	if learned != "":
		entry["learned"] = learned
	if not read_ids.is_empty():
		entry["read_letters"] = read_ids
	if not honoured.is_empty():
		var prefix := str(honoured["prefix"])
		if small and str(honoured["because"]) == "plan":
			# Land lines are whole sentences, so the plan gets one of its own.
			prefix = "I went to %s, as I'd planned. " % place_name
		entry["text"] = prefix + str(entry["text"])
		entry["because"] = str(honoured["because"])
		if honoured.has("want_id"):
			entry["buy_want"] = str(honoured["want_id"])
			for want_variant in mind["wants"]:
				if typeof(want_variant) == TYPE_DICTIONARY and str((want_variant as Dictionary).get("id", "")) == str(honoured["want_id"]):
					entry["buy_item"] = str((want_variant as Dictionary).get("name", ""))
					(want_variant as Dictionary)["status"] = "buying"

	# Seeing something in a shop it would like to own. Drawn last, so none of the
	# earlier rng draws move.
	var shop_items = context.get("shop_items", [])
	if str(place.get("kind", "")) == "shop" and typeof(shop_items) == TYPE_ARRAY and not (shop_items as Array).is_empty():
		var open_wants := 0
		for want_variant in mind["wants"]:
			if typeof(want_variant) == TYPE_DICTIONARY and str((want_variant as Dictionary).get("status", "")) == "saving":
				open_wants += 1
		if open_wants < MAX_OPEN_WANTS and rng.randf() < WANT_NOTICE_CHANCE:
			var seen_variant = (shop_items as Array)[rng.randi_range(0, (shop_items as Array).size() - 1)]
			if typeof(seen_variant) == TYPE_DICTIONARY:
				var seen: Dictionary = seen_variant
				var seen_id := str(seen.get("id", ""))
				var already := false
				for want_variant in mind["wants"]:
					if typeof(want_variant) == TYPE_DICTIONARY and str((want_variant as Dictionary).get("item_id", "")) == seen_id:
						already = true
				if not already:
					var seen_name := str(seen.get("name", seen_id))
					var new_want := {
						"id": "want-%d" % decision_unix,
						"item_id": seen_id,
						"name": seen_name,
						"slot": str(seen.get("slot", "")),
						"price": int(seen.get("price", 0)),
						"reason": "saw it at %s" % place_name,
						"t": decision_unix,
						"status": "saving",
						"place_id": place_id,
					}
					(mind["wants"] as Array).append(new_want)
					entry["text"] = str(entry["text"]) + " I saw a %s there. I'd like one." % seen_name
					entry["noticed_want"] = str(new_want["id"])
					entry["noticed_item"] = seen_name
	if small:
		if not edge.is_empty():
			var edge_keys := {"sign": "sign_of", "blocked": "blocked_at", "found": "found_place"}
			entry[str(edge_keys[str(edge["kind"])])] = str(edge["target"])
		elif waking == "" and intent != "rest" and not box_text:
			# Something noticed or wondered about takes the place of the tail.
			# Going to sleep gets neither: its line is the last thing it knows.
			if not _land_afterthought(entry, intent, place, hour, mind, all_places, decision_unix, rng, town, int(merged.get("personality_seed", 0))):
				entry["text"] = str(entry["text"]) + _land_tail(activity, times_before, valence, town, rng)
		mind["busy_until"] = decision_unix + slots * DECISION_INTERVAL_SECONDS
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
	scores: Dictionary, rng: RandomNumberGenerator, wants: Array = [], hour: int = -1
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
	elif source == "plan":
		prefix = "As I'd planned, "
	elif source == "want":
		var want_name := ""
		for want_variant in wants:
			if typeof(want_variant) == TYPE_DICTIONARY and str((want_variant as Dictionary).get("id", "")) == str(intention.get("want_id", "")):
				want_name = str((want_variant as Dictionary).get("name", ""))
		prefix = "I'd saved enough for the %s, so I went to %s. " % [want_name, target_name]
	var result := {"intent": "", "place": {}, "activity": {}, "companion": {}, "prefix": prefix, "because": source}
	if source == "want":
		result["want_id"] = str(intention.get("want_id", ""))

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
			if not _hour_fits((activity_variant as Dictionary).get("hours", null), hour):
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


# Local calendar day number, using the same timezone bias as _local_hour.
func _local_day(unix_time: int) -> int:
	var local_unix := unix_time + _time_zone_bias_minutes() * 60
	return int(local_unix / 86400)


# The shop a want is bought at: where it was seen if that is still in town,
# otherwise the first shop. {} when the town has none.
func _shop_for_want(want: Dictionary, places: Array) -> Dictionary:
	var first_shop := {}
	for place_variant in places:
		var row: Dictionary = place_variant
		if str(row.get("id", "")) == str(want.get("place_id", "")):
			return row
		if first_shop.is_empty() and str(row.get("kind", "")) == "shop":
			first_shop = row
	return first_shop


# When the buddy last went to a place, from the journal; -1 if never.
func _last_visit(journal: Array, place_id: String) -> int:
	var latest := -1
	for entry_variant in journal:
		if typeof(entry_variant) == TYPE_DICTIONARY and str((entry_variant as Dictionary).get("place_id", "")) == place_id:
			latest = maxi(latest, int((entry_variant as Dictionary).get("t", 0)))
	return latest


# The place visited longest ago (ties go to town order), skipping home and
# anything in `taken`. {} when nothing is left.
func _stalest_place(places: Array, journal: Array, taken: Array) -> Dictionary:
	var best := {}
	var best_visit := 0
	for place_variant in places:
		var row: Dictionary = place_variant
		var row_id := str(row.get("id", ""))
		if row_id == "home" or taken.has(row_id):
			continue
		var visit := _last_visit(journal, row_id)
		if best.is_empty() or visit < best_visit:
			best = row
			best_visit = visit
	return best


# Makes the day's plan on the first awake decision of a new local day, and
# writes off plan items whose part of the day is over. Draws no rng.
func _update_day_plan(
	mind: Dictionary, npcs: Array, places: Array, decision_unix: int, hour: int, is_night: bool
) -> void:
	var day := _local_day(decision_unix)
	var plan: Dictionary = mind["day_plan"]
	# Yesterday's unfinished items are written off before today's plan
	# replaces them, so the journal still says what it never got round to.
	if not plan.is_empty() and int(plan.get("day", day)) < day:
		_write_off_missed(mind, plan, day, hour, decision_unix)
	if not is_night and hour >= 7 and int(plan.get("day", -1)) != day:
		var journal: Array = mind["journal"]
		var feelings: Dictionary = mind["feelings"]
		var items: Array = []
		var taken: Array = []

		# This morning: somewhere it likes, else somewhere it has neglected.
		var morning := {}
		var morning_feeling := 0.0
		for place_variant in places:
			var row: Dictionary = place_variant
			var row_id := str(row.get("id", ""))
			if row_id == "home":
				continue
			var f := float(feelings.get("place:%s" % row_id, 0.0))
			if f > morning_feeling:
				morning_feeling = f
				morning = row
		if morning.is_empty():
			morning = _stalest_place(places, journal, taken)
		if not morning.is_empty():
			taken.append(str(morning["id"]))
			items.append(_plan_item("place", morning, 0, "go to %s" % str(morning.get("name", morning["id"]))))

		# This afternoon: someone it likes who lives somewhere, else somewhere new.
		var friend := {}
		var friend_feeling := 0.0
		for npc_variant in npcs:
			if typeof(npc_variant) != TYPE_DICTIONARY:
				continue
			var npc: Dictionary = npc_variant
			var npc_id := str(npc.get("id", "")).strip_edges()
			if npc_id == "":
				continue
			var lives_somewhere := false
			for place_variant in places:
				var residents = (place_variant as Dictionary).get("residents", [])
				if typeof(residents) == TYPE_ARRAY and (residents as Array).has(npc_id):
					lives_somewhere = true
			var nf := float(feelings.get("npc:%s" % npc_id, 0.0))
			if lives_somewhere and nf > friend_feeling:
				friend_feeling = nf
				friend = {"id": npc_id, "name": str(npc.get("name", npc_id))}
		if not friend.is_empty():
			items.append(_plan_item("npc", friend, 1, "see %s" % str(friend["name"])))
		else:
			var afternoon := _stalest_place(places, journal, taken)
			if not afternoon.is_empty():
				taken.append(str(afternoon["id"]))
				items.append(_plan_item("place", afternoon, 1, "go to %s" % str(afternoon.get("name", afternoon["id"]))))

		# This evening: somewhere not already on the list.
		var evening := _stalest_place(places, journal, taken)
		if not evening.is_empty():
			items.append(_plan_item("place", evening, 2, "go to %s" % str(evening.get("name", evening["id"]))))

		# Planned late in the day: leave out the parts of the day already over.
		items = items.filter(func(planned): return hour < int(PLAN_WINDOWS[int(planned["window"])][1]))
		plan = {"day": day, "items": items}
		mind["day_plan"] = plan
		if not items.is_empty():
			var phrases: Array = []
			for planned in items:
				phrases.append(str(planned["phrase"]))
			var joined := str(phrases[0])
			if phrases.size() == 2:
				joined = "%s and %s" % [phrases[0], phrases[1]]
			elif phrases.size() > 2:
				joined = "%s, %s and %s" % [phrases[0], phrases[1], phrases[2]]
			_append_journal(mind, {
				"t": decision_unix - 1,
				"intent": "reflect",
				"subject_id": "plan",
				"subject_name": "plan",
				"valence": 0.1,
				"kind": "plan",
				"text": "Today I'd like to " + joined + ".",
			})

	_write_off_missed(mind, plan, day, hour, decision_unix)


# Items whose part of the day ended undone (or whose day is over) are marked
# missed and noted once in the journal.
func _write_off_missed(mind: Dictionary, plan: Dictionary, day: int, hour: int, decision_unix: int) -> void:
	var plan_day := int(plan.get("day", day))
	var current_items = plan.get("items", [])
	if typeof(current_items) != TYPE_ARRAY:
		return
	for item_variant in current_items:
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		var window := int(item.get("window", 0))
		if bool(item.get("done", false)) or window < 0 or window >= PLAN_WINDOWS.size():
			continue
		if plan_day < day or (plan_day == day and hour >= int(PLAN_WINDOWS[window][1])):
			item["done"] = true
			item["missed"] = true
			_append_journal(mind, {
				"t": decision_unix - 1,
				"kind": "plan",
				"valence": -0.05,
				"intent": "reflect",
				"subject_id": "plan",
				"subject_name": "plan",
				"text": "I'd meant to %s %s, but I didn't get round to it." % [str(item.get("phrase", "")), PLAN_WINDOW_NAMES[window]],
			})


func _plan_item(kind: String, target: Dictionary, window: int, phrase: String) -> Dictionary:
	return {
		"kind": kind,
		"id": str(target.get("id", "")),
		"name": str(target.get("name", target.get("id", ""))),
		"window": window,
		"done": false,
		"missed": false,
		"phrase": phrase,
	}


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


# "hours": [from, to) limits when something can be done or seen; it wraps past
# midnight when from is later than to. Anything else means any time.
func _hour_fits(hours_variant: Variant, hour: int) -> bool:
	if hour < 0 or typeof(hours_variant) != TYPE_ARRAY or (hours_variant as Array).size() != 2:
		return true
	var from_hour := int(hours_variant[0])
	var to_hour := int(hours_variant[1])
	if from_hour == to_hour:
		return true
	if from_hour < to_hour:
		return from_hour <= hour and hour < to_hour
	return hour >= from_hour or hour < to_hour


func _place_stage(known: Dictionary, place_id: String) -> String:
	var record = known.get(place_id, null)
	if typeof(record) != TYPE_DICTIONARY:
		return ""
	return str((record as Dictionary).get("stage", ""))


# Home plus the places it has found.
func _found_places(places: Array, mind: Dictionary, home_id: String) -> Array:
	var known: Dictionary = {}
	var known_variant = mind.get("known_places", null)
	if typeof(known_variant) == TYPE_DICTIONARY:
		known = known_variant
	var rows: Array = []
	for place_variant in places:
		var place: Dictionary = place_variant
		var place_id := str(place.get("id", ""))
		if place_id == home_id or _place_stage(known, place_id) == "found":
			rows.append(place)
	return rows


func _has_open_sign(mind: Dictionary) -> bool:
	var known_variant = mind.get("known_places", null)
	if typeof(known_variant) != TYPE_DICTIONARY:
		return false
	for place_id in (known_variant as Dictionary).keys():
		if _place_stage(known_variant as Dictionary, str(place_id)) == "sign":
			return true
	return false


# The land as the buddy knows it: home, the places it has found, and the paths
# between them. Everything outside the mind reads the land through this.
func known_town(profile: Dictionary, land: Dictionary) -> Dictionary:
	var mind: Dictionary = {}
	var mind_variant = profile.get("mind", null)
	if typeof(mind_variant) == TYPE_DICTIONARY:
		mind = mind_variant
	var home_id := str(land.get("home_place", "home"))
	var places: Array = _found_places(_usable_places(land), mind, home_id)
	var ids := {}
	for place_variant in places:
		ids[str((place_variant as Dictionary).get("id", ""))] = true
	var paths: Array = []
	var paths_variant = land.get("paths", null)
	if typeof(paths_variant) == TYPE_ARRAY:
		for path_variant in paths_variant:
			if typeof(path_variant) != TYPE_ARRAY or (path_variant as Array).size() != 2:
				continue
			if ids.has(str(path_variant[0])) and ids.has(str(path_variant[1])):
				paths.append(path_variant)
	var known := land.duplicate(false)
	known["places"] = places.duplicate(true)
	known["paths"] = paths.duplicate(true)
	return known


# Where a place sits on the land's map, or null when the land has no map.
static func _map_of(place: Dictionary) -> Variant:
	var map_variant = place.get("map", null)
	if typeof(map_variant) == TYPE_ARRAY and (map_variant as Array).size() == 2:
		return Vector2(float(map_variant[0]), float(map_variant[1]))
	return null


# The place a try can start from. On a mapped land: the nearest place it has
# found (or home), open now, within LAND_REACH of the target, in any direction.
# Without a map: the first of the target's "from" places it has found that is
# open now.
func _edge_origin(discover: Dictionary, all_places: Array, known: Dictionary, home_id: String, hour: int,
		target: Dictionary = {}) -> Dictionary:
	var target_map = _map_of(target)
	if target_map != null:
		# It steps out of the door first: from inside the house only the place
		# nearest it (the doorstep) can be reached; everything else starts outside.
		var doorstep := _doorstep_id(all_places, home_id)
		var nearest: Dictionary = {}
		var nearest_d := INF
		for place_variant in all_places:
			var place: Dictionary = place_variant
			var place_id := str(place.get("id", ""))
			if place_id != home_id and _place_stage(known, place_id) != "found":
				continue
			if place_id == home_id and str(target.get("id", "")) != doorstep:
				continue
			var place_map = _map_of(place)
			if place_map == null or not _place_is_open(place, hour):
				continue
			var d := (place_map as Vector2).distance_to(target_map)
			if d <= LAND_REACH and d < nearest_d:
				nearest_d = d
				nearest = place
		return nearest
	var from_variant = discover.get("from", null)
	if typeof(from_variant) != TYPE_ARRAY:
		return {}
	for from_id_variant in from_variant:
		var from_id := str(from_id_variant)
		if from_id != home_id and _place_stage(known, from_id) != "found":
			continue
		for place_variant in all_places:
			var place: Dictionary = place_variant
			if str(place.get("id", "")) == from_id and _place_is_open(place, hour):
				return place
	return {}


# The mapped place nearest home: the yard, outside the door.
func _doorstep_id(all_places: Array, home_id: String) -> String:
	var home_map = _map_of(_place_by_id(all_places, home_id))
	if home_map == null:
		return ""
	var best := ""
	var best_d := INF
	for place_variant in all_places:
		var place: Dictionary = place_variant
		var place_id := str(place.get("id", ""))
		var place_map = _map_of(place)
		if place_id == home_id or place_map == null:
			continue
		var d := (place_map as Vector2).distance_to(home_map)
		if d < best_d:
			best_d = d
			best = place_id
	return best


# A string, or one string per place the try started from. With free
# exploration a try can start from a place the lines were not written for: then
# the "" line, which names no other place, so it is never untrue about where
# it was or names a place it has not found.
func _edge_text(value: Variant, origin_id: String) -> String:
	if typeof(value) == TYPE_STRING:
		return str(value)
	if typeof(value) == TYPE_DICTIONARY:
		var by_origin: Dictionary = value
		if by_origin.has(origin_id):
			return str(by_origin[origin_id])
		if by_origin.has(""):
			return str(by_origin[""])
		for key in by_origin.keys():
			return str(by_origin[key])
	return ""


# Going to the edge of what it knows. Returns {} when nothing new is in reach
# right now, or when it does something familiar this time; otherwise what
# happened: {"kind": "sign"|"blocked"|"found", "target", "place", "activity",
# "text", "valence_shift"}. A sign comes first where the place has one; a
# failed try makes the next one more likely.
func _try_the_edge(
	all_places: Array, mind: Dictionary, home_id: String, hour: int, decision_unix: int, rng: RandomNumberGenerator
) -> Dictionary:
	var known: Dictionary = mind["known_places"]
	var reach: Array = []
	for place_variant in all_places:
		var target: Dictionary = place_variant
		var target_id := str(target.get("id", ""))
		var stage := _place_stage(known, target_id)
		if target_id == home_id or stage == "found" or not _place_is_open(target, hour):
			continue
		# After a failed try it leaves that place for another day.
		if stage == "sign":
			var tried: Dictionary = known[target_id]
			if int(tried.get("tries", 0)) > 0 and _local_day(int(tried.get("t", 0))) == _local_day(decision_unix):
				continue
		var discover_variant = target.get("discover", null)
		if typeof(discover_variant) != TYPE_DICTIONARY:
			continue
		var origin := _edge_origin(discover_variant as Dictionary, all_places, known, home_id, hour, target)
		if origin.is_empty():
			continue
		reach.append({"place": target, "origin": origin, "stage": stage})
	# While it has found nothing at all, an explore always goes for the door.
	var edge_chance := 1.0
	for known_id in known.keys():
		if _place_stage(known, str(known_id)) == "found":
			edge_chance = LAND_EDGE_CHANCE
			break
	if reach.is_empty() or rng.randf() >= edge_chance:
		return {}
	# Somewhere it already has a sign of pulls twice as hard as somewhere new.
	var total := 0.0
	for row in reach:
		total += 2.0 if str(row["stage"]) == "sign" else 1.0
	var roll := rng.randf() * total
	var chosen: Dictionary = reach[reach.size() - 1]
	var cumulative := 0.0
	for row in reach:
		cumulative += 2.0 if str(row["stage"]) == "sign" else 1.0
		if roll <= cumulative:
			chosen = row
			break
	var target_place: Dictionary = chosen["place"]
	var origin_place: Dictionary = chosen["origin"]
	var origin_id := str(origin_place.get("id", ""))
	var chosen_id := str(target_place.get("id", ""))
	var discover: Dictionary = target_place["discover"]
	var record := {"stage": "", "t": decision_unix, "tries": 0}
	var old_record = known.get(chosen_id, null)
	if typeof(old_record) == TYPE_DICTIONARY:
		record["stage"] = str((old_record as Dictionary).get("stage", ""))
		record["tries"] = int((old_record as Dictionary).get("tries", 0))
	var sign_text := _edge_text(discover.get("sign", ""), origin_id)
	if str(record["stage"]) == "" and sign_text != "":
		record["stage"] = "sign"
		known[chosen_id] = record
		return {"kind": "sign", "target": chosen_id, "place": origin_place, "activity": LAND_EDGE_ACTIVITY, "text": sign_text, "valence_shift": 0.2}
	var chance := clampf(float(discover.get("chance", 1.0)) + LAND_TRY_BONUS * float(int(record["tries"])), 0.0, 1.0)
	if rng.randf() < chance:
		record["stage"] = "found"
		known[chosen_id] = record
		return {"kind": "found", "target": chosen_id, "place": target_place, "activity": LAND_ARRIVE_ACTIVITY, "text": _edge_text(discover.get("found", ""), origin_id), "valence_shift": 0.35}
	var blocked_text := "I tried to go further than I have been, and turned back."
	var blocked_variant = discover.get("blocked", null)
	if typeof(blocked_variant) == TYPE_ARRAY and not (blocked_variant as Array).is_empty():
		blocked_text = str((blocked_variant as Array)[int(record["tries"]) % (blocked_variant as Array).size()])
	record["stage"] = "sign"
	record["tries"] = int(record["tries"]) + 1
	known[chosen_id] = record
	return {"kind": "blocked", "target": chosen_id, "place": origin_place, "activity": LAND_EDGE_ACTIVITY, "text": blocked_text, "valence_shift": -0.25}


# How many decision slots this takes: its minutes (a little more or less each
# time), or until its hour next comes round (it sleeps until morning), plus the
# walk there: the straight way from where it was on a mapped land, otherwise
# the place's hops from home.
func _land_slots(activity: Dictionary, place: Dictionary, came_from: String, decision_unix: int, rng: RandomNumberGenerator,
		all_places: Array = []) -> int:
	var minutes := float(activity.get("minutes", LAND_DEFAULT_MINUTES)) * rng.randf_range(0.85, 1.15)
	if activity.has("until_hour"):
		# Give or take, and never less than an hour.
		var local_unix := decision_unix + _time_zone_bias_minutes() * 60
		var now_minutes := int((local_unix % 86400) / 60)
		var left := (int(activity["until_hour"]) * 60 - now_minutes + 1440) % 1440
		minutes = maxf(60.0, float(left) + rng.randf_range(0.0, 40.0))
	if str(place.get("id", "")) != came_from:
		minutes += float(LAND_TRAVEL_MINUTES) * _hops_between(_place_by_id(all_places, came_from), place)
	return maxi(1, int(round(minutes * 60.0 / float(DECISION_INTERVAL_SECONDS))))


func _place_by_id(all_places: Array, place_id: String) -> Dictionary:
	for place_variant in all_places:
		if typeof(place_variant) == TYPE_DICTIONARY and str((place_variant as Dictionary).get("id", "")) == place_id:
			return place_variant
	return {}


# How far apart two places are, in old path hops: the straight way on a mapped
# land; otherwise the destination's hops from home.
func _hops_between(from_place: Dictionary, to_place: Dictionary) -> float:
	var from_map = _map_of(from_place)
	var to_map = _map_of(to_place)
	if from_map != null and to_map != null:
		return (from_map as Vector2).distance_to(to_map) / LAND_HOP
	return float(to_place.get("distance", 0))


# In the land, needs move with time and with what it does: being awake tires
# it, comfort fades, and how things go moves its confidence. Company slowly
# fades while it is awake: nobody else lives on the land, and only talking with
# the person (note_talk) or a visit (return_from_visit) brings it back.
func _apply_land_needs(mods: Dictionary, activity: Dictionary, slots: int, valence: float, edge_kind: String) -> void:
	var n := float(slots)
	var need := str(activity.get("satisfies", ""))
	var strain := float(mods["energy_strain"])
	var comfort := float(mods["comfort"])
	var confidence := float(mods["confidence"])
	var company := float(mods.get("social_fulfillment", 0.0))
	if activity.has("until_hour"):
		# Asleep: it mends for as long as it sleeps.
		strain = maxf(LAND_RESTED, strain - LAND_SLEEP_PER_SLOT * n)
		comfort -= LAND_COMFORT_FADE_ASLEEP_PER_SLOT * n
	else:
		comfort -= LAND_COMFORT_FADE_PER_SLOT * n
		company -= LAND_COMPANY_FADE_PER_SLOT * n
		if need == "energy":
			strain -= LAND_REST_PER_SLOT * n
		else:
			strain += LAND_TIRE_PER_SLOT * n
			if need == "curiosity":
				strain += LAND_EXPLORE_TIRE_PER_SLOT * n
		if need == "comfort":
			comfort += LAND_COMFORT_GAIN_PER_SLOT * n
	if valence >= 0.2:
		confidence += 0.015
	elif valence < -0.05:
		confidence -= 0.03
		comfort -= 0.02
	if edge_kind == "found":
		confidence += 0.08
	elif edge_kind == "sign":
		confidence += 0.03
	elif edge_kind == "blocked":
		confidence -= 0.05
	confidence += (0.5 - confidence) * LAND_CONFIDENCE_PULL
	mods["energy_strain"] = _clamp01(strain)
	mods["comfort"] = _clamp01(comfort)
	mods["confidence"] = _clamp01(confidence)
	mods["social_fulfillment"] = _clamp01(company)


# True when this time gets one of the activity's own "bad" lines: only when it
# went properly wrong, so those lines stay rare.
func _land_uses_bad_line(activity: Dictionary, valence: float) -> bool:
	var bad_variant = activity.get("bad", null)
	return valence < LAND_BAD_LINE_BELOW and typeof(bad_variant) == TYPE_ARRAY and not (bad_variant as Array).is_empty()


# The authored line for what it just did: the first-time line once, a "bad"
# line when it went badly, otherwise its lines in turn (from a starting point
# that differs per buddy). "" when the activity has no lines of its own.
func _land_text(activity: Dictionary, times_done: int, valence: float, buddy_seed: int, rng: RandomNumberGenerator) -> String:
	var first := str(activity.get("first", ""))
	if times_done == 0 and first != "":
		return first
	if _land_uses_bad_line(activity, valence):
		var bad: Array = activity["bad"]
		return str(bad[rng.randi_range(0, bad.size() - 1)])
	var lines_variant = activity.get("lines", null)
	if typeof(lines_variant) != TYPE_ARRAY or (lines_variant as Array).is_empty():
		return ""
	var lines: Array = lines_variant
	var offset := int(hash("%d|%s" % [buddy_seed, str(activity.get("id", ""))]) % lines.size())
	return str(lines[(times_done + offset) % lines.size()])


# A few words on how it felt, for after an ordinary line: sometimes when it
# went well, always when it went badly. " " plus the words, or "". The
# first-time line and the "bad" lines already say how it went.
func _land_tail(activity: Dictionary, times_done: int, valence: float, land: Dictionary, rng: RandomNumberGenerator) -> String:
	if times_done == 0 and str(activity.get("first", "")) != "":
		return ""
	if _land_uses_bad_line(activity, valence):
		return ""
	var lines_variant = activity.get("lines", null)
	if typeof(lines_variant) != TYPE_ARRAY or (lines_variant as Array).is_empty():
		return ""
	var tails: Dictionary = {}
	var tails_variant = land.get("tails", null)
	if typeof(tails_variant) == TYPE_DICTIONARY:
		tails = tails_variant
	var pool_variant = null
	if valence >= 0.2 and rng.randf() < LAND_GOOD_TAIL_CHANCE:
		pool_variant = tails.get("good", null)
	elif valence < -0.05:
		pool_variant = tails.get("bad", null)
	if typeof(pool_variant) != TYPE_ARRAY or (pool_variant as Array).is_empty():
		return ""
	return " " + str((pool_variant as Array)[rng.randi_range(0, (pool_variant as Array).size() - 1)])


# After the line. While it rests: nothing. While it thinks: somewhere it has a
# sign of but has not reached may come back to it. Otherwise it may notice
# something here that it has never seen (once each). Returns true when it
# added something; a line is never grown past LAND_MAX_LINE_CHARS.
func _land_afterthought(
	entry: Dictionary, intent: String, place: Dictionary, hour: int, mind: Dictionary, all_places: Array,
	decision_unix: int, rng: RandomNumberGenerator, town: Dictionary = {}, personality_seed: int = 0
) -> bool:
	var room := LAND_MAX_LINE_CHARS - str(entry["text"]).length() - 1
	if intent == "rest":
		return false
	if intent == "reflect":
		var known: Dictionary = mind["known_places"]
		var oldest_id := ""
		var oldest_t := 0
		var oldest_lines: Array = []
		for place_variant in all_places:
			var other: Dictionary = place_variant
			var other_id := str(other.get("id", ""))
			if _place_stage(known, other_id) != "sign":
				continue
			var discover_variant = other.get("discover", null)
			if typeof(discover_variant) != TYPE_DICTIONARY:
				continue
			var wonder_variant = (discover_variant as Dictionary).get("wonder", null)
			if typeof(wonder_variant) != TYPE_ARRAY or (wonder_variant as Array).is_empty():
				continue
			var since := int((known[other_id] as Dictionary).get("t", 0))
			if oldest_id == "" or since < oldest_t:
				oldest_id = other_id
				oldest_t = since
				oldest_lines = wonder_variant
		if oldest_id == "" or rng.randf() >= LAND_WONDER_CHANCE:
			return false
		var wonder := str(oldest_lines[rng.randi_range(0, oldest_lines.size() - 1)])
		if wonder.length() > room:
			return false
		entry["text"] = str(entry["text"]) + " " + wonder
		entry["wonder_about"] = oldest_id
		return true
	var seen: Dictionary = mind["seen"]
	var unseen: Array = []
	var sights_variant = place.get("sights", null)
	if typeof(sights_variant) == TYPE_ARRAY:
		for sight_variant in sights_variant:
			if typeof(sight_variant) != TYPE_DICTIONARY:
				continue
			var sight: Dictionary = sight_variant
			var sight_id := str(sight.get("id", ""))
			if sight_id == "" or seen.has(sight_id) or not _hour_fits(sight.get("hours", null), hour):
				continue
			if str(sight.get("line", "")).length() > room:
				continue
			unseen.append(sight)
	if unseen.is_empty() or rng.randf() >= LAND_SIGHT_CHANCE:
		return _land_meet(entry, place, hour, mind, town, decision_unix, rng, personality_seed, room)
	# Something alive catches the eye before something still: a creature's
	# first sight weighs LAND_CREATURE_SIGHT_WEIGHT against 1 for any other.
	var creature_sights := {}
	for thing_variant in _land_things(town):
		creature_sights[str((thing_variant as Dictionary).get("sight", ""))] = true
	var weight_total := 0.0
	for sight in unseen:
		weight_total += LAND_CREATURE_SIGHT_WEIGHT if creature_sights.has(str((sight as Dictionary).get("id", ""))) else 1.0
	var pick := rng.randf() * weight_total
	var noticed: Dictionary = unseen[unseen.size() - 1]
	for sight in unseen:
		pick -= LAND_CREATURE_SIGHT_WEIGHT if creature_sights.has(str((sight as Dictionary).get("id", ""))) else 1.0
		if pick <= 0.0:
			noticed = sight
			break
	entry["text"] = str(entry["text"]) + " " + str(noticed.get("line", ""))
	entry["sight"] = str(noticed.get("id", ""))
	seen[str(noticed.get("id", ""))] = decision_unix
	# The sight of a thing is its first meeting.
	for thing_variant in _land_things(town):
		var first_thing: Dictionary = thing_variant
		if str(first_thing.get("sight", "")) == str(noticed.get("id", "")):
			(mind["things"] as Dictionary)[str(first_thing.get("id", ""))] = {"met": 1, "first_t": decision_unix, "last_t": decision_unix, "name": "", "named_t": 0}
			entry["thing"] = str(first_thing.get("id", ""))
	return true


func _land_things(town: Dictionary) -> Array:
	var things_variant = town.get("things", null)
	return things_variant if typeof(things_variant) == TYPE_ARRAY else []


# Its own name for a thing: "the " + a first part + " " + a second, chosen by its
# own seed, so two buddies name the same thing differently.
func land_thing_name(thing: Dictionary, personality_seed: int) -> String:
	var parts: Array = thing.get("parts", [])
	var firsts: Array = parts[0]
	var seconds: Array = parts[1]
	var h: int = absi(hash("%d|%s" % [personality_seed, str(thing.get("id", ""))]))
	var first_index: int = h % firsts.size()
	var second_index: int = int(h / 7) % seconds.size()
	return "the %s %s" % [str(firsts[first_index]), str(seconds[second_index])]


func _upper_first(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


func land_fill_thing_line(line: String, thing: Dictionary, name: String) -> String:
	var describe := str(thing.get("describe", ""))
	return line.replace("{Describe}", _upper_first(describe)).replace("{describe}", describe).replace("{Name}", _upper_first(name)).replace("{name}", name)


# Meeting again a thing that lives here, whose sight it has noticed. These are
# the last random draws of a decision; when nothing is added the rng goes back
# to where it was, so the tail that follows is the one it would have been.
func _land_meet(
	entry: Dictionary, place: Dictionary, hour: int, mind: Dictionary, town: Dictionary,
	decision_unix: int, rng: RandomNumberGenerator, personality_seed: int, room: int
) -> bool:
	if meet_chance <= 0.0:
		return false
	var place_id := str(place.get("id", ""))
	var seen: Dictionary = mind["seen"]
	var candidates: Array = []
	for thing_variant in _land_things(town):
		var candidate: Dictionary = thing_variant
		if not (candidate.get("places", []) as Array).has(place_id):
			continue
		if not _hour_fits(candidate.get("hours", null), hour) or not seen.has(str(candidate.get("sight", ""))):
			continue
		candidates.append(candidate)
	if candidates.is_empty():
		return false
	var saved_state: int = rng.state
	if rng.randf() >= meet_chance:
		rng.state = saved_state
		return false
	var thing: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var thing_id := str(thing.get("id", ""))
	var things: Dictionary = mind["things"]
	var seen_t: int = int(seen[str(thing.get("sight", ""))])
	var record: Dictionary = {"met": 1, "first_t": seen_t, "last_t": seen_t, "name": "", "named_t": 0}
	if things.has(thing_id):
		record = (things[thing_id] as Dictionary).duplicate()
	var met: int = int(record["met"]) + 1
	var thing_name: String = str(record.get("name", ""))
	var template := ""
	var naming := false
	if thing_name != "":
		var named_lines: Array = thing.get("named", [])
		template = str(named_lines[(met - LAND_NAME_AFTER - 1) % named_lines.size()])
	elif met < LAND_NAME_AFTER:
		var again_lines: Array = thing.get("again", [])
		template = str(again_lines[(met - 2) % again_lines.size()])
	else:
		naming = true
		thing_name = land_thing_name(thing, personality_seed)
		var naming_lines: Array = thing.get("naming", [])
		template = str(naming_lines[(met - LAND_NAME_AFTER) % naming_lines.size()])
	var line := land_fill_thing_line(template, thing, thing_name)
	if line.length() > room:
		rng.state = saved_state
		return false
	record["met"] = met
	record["last_t"] = decision_unix
	if naming:
		record["name"] = thing_name
		record["named_t"] = decision_unix
		entry["named"] = thing_name
	things[thing_id] = record
	entry["text"] = str(entry["text"]) + " " + line
	entry["thing"] = thing_id
	return true


func _candidates_for_need(open_places: Array, need: String, hour: int = -1) -> Array:
	var rows: Array = []
	for place in open_places:
		for activity_variant in place["activities"]:
			if typeof(activity_variant) != TYPE_DICTIONARY:
				continue
			if not _hour_fits((activity_variant as Dictionary).get("hours", null), hour):
				continue
			if str((activity_variant as Dictionary).get("satisfies", "")) == need:
				rows.append({"place": place, "activity": activity_variant})
	return rows


# Weighted by feelings, and by how far it is from from_place (home: the land
# around home is where it lives; on a land with no map, the place's hops from
# home).
func _pick_candidate(candidates: Array, feelings: Dictionary, rng: RandomNumberGenerator, from_place: Dictionary = {}) -> Dictionary:
	var total := 0.0
	var weights: Array = []
	for row in candidates:
		var place: Dictionary = row["place"]
		var activity: Dictionary = row["activity"]
		var place_feeling := float(feelings.get("place:%s" % str(place.get("id", "")), 0.0))
		var activity_feeling := float(feelings.get("activity:%s" % str(activity.get("id", "")), 0.0))
		var raw := maxf(0.15, 1.0 + place_feeling * 0.7 + activity_feeling * 0.5)
		var weight := raw / (1.0 + 0.25 * _hops_between(from_place, place))
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
	var local_unix := unix_time + _time_zone_bias_minutes() * 60
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


# The console record, with a default for anything missing (a copy to write back).
func _console(mind: Dictionary) -> Dictionary:
	var console := {"goes": 0, "known": false, "known_t": 0}
	var stored = mind.get("console", null)
	if typeof(stored) == TYPE_DICTIONARY:
		console["goes"] = int((stored as Dictionary).get("goes", 0))
		console["known"] = bool((stored as Dictionary).get("known", false))
		console["known_t"] = int((stored as Dictionary).get("known_t", 0))
	return console


func _clamp01(value: float) -> float:
	return minf(1.0, maxf(0.0, value))


# --- Visits (Plan 14 step 2a) -------------------------------------------
# The buddy can go and sit on the person's desktop. These are pure: the world
# host and the desktop app decide when; this decides what it means for the buddy.

func _land_activity(land: Dictionary, place_id: String, activity_id: String) -> Dictionary:
	for place_variant in _usable_places(land):
		var place: Dictionary = place_variant
		if str(place.get("id", "")) != place_id:
			continue
		for activity_variant in (place.get("activities", []) as Array):
			if typeof(activity_variant) == TYPE_DICTIONARY and str((activity_variant as Dictionary).get("id", "")) == activity_id:
				return activity_variant
	return {}


func _visit_entry(
	now: int, intent: String, place_id: String, place_name: String, activity_id: String,
	activity_label: String, valence: float, text: String, subject_id: String, subject_name: String
) -> Dictionary:
	return {
		"t": now,
		"intent": intent,
		"subject_id": subject_id,
		"subject_name": subject_name,
		"valence": valence,
		"text": text,
		"place_id": place_id,
		"place_name": place_name,
		"activity_id": activity_id,
		"activity_label": activity_label,
		"companion_name": "",
	}


func _slots_since(unix_left: int, now: int) -> float:
	if unix_left <= 0:
		return 0.0
	return float(maxi(0, now - unix_left) / DECISION_INTERVAL_SECONDS)


# Whether it can come over right now: {"come": "now"|"later"|"asleep", "at", "why"}.
func consider_call(profile: Dictionary, land: Dictionary, now: int) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var busy_until := int(mind.get("busy_until", 0))
	# It has only just woken up for the first time: nothing it minds leaving.
	var journal_now: Array = mind["journal"]
	var just_woke := not journal_now.is_empty() and typeof(journal_now[journal_now.size() - 1]) == TYPE_DICTIONARY \
		and str((journal_now[journal_now.size() - 1] as Dictionary).get("activity_id", "")) == str(LAND_WAKE_ACTIVITY["id"])
	if now >= busy_until or just_woke:
		# Awake, but it is its bedtime: a visit now would end at once, so it
		# comes in the morning instead.
		if is_bedtime(merged, now):
			return {"come": "asleep", "at": _next_local_hour(now, VISIT_MORNING_HOUR), "why": ""}
		return {"come": "now", "at": now, "why": ""}
	var activity: Dictionary = {}
	var journal: Array = mind["journal"]
	if not journal.is_empty() and typeof(journal[journal.size() - 1]) == TYPE_DICTIONARY:
		var last: Dictionary = journal[journal.size() - 1]
		activity = _land_activity(land, str(last.get("place_id", "")), str(last.get("activity_id", "")))
		# Activities of its own (waking up, the edge) are not in the land: the entry has the label.
		if activity.is_empty():
			activity = {"label": str(last.get("activity_label", ""))}
	if activity.has("until_hour"):
		return {"come": "asleep", "at": busy_until, "why": str(activity.get("label", ""))}
	return {"come": "later", "at": busy_until, "why": str(activity.get("label", ""))}


# The next time after now that the local clock shows this hour, on the hour.
# The hour boundary is the local one: in a zone half an hour off UTC
# (UTC+05:30) a UTC boundary would be 07:30 on the local clock.
func _next_local_hour(now: int, hour: int) -> int:
	var bias: int = _time_zone_bias_minutes() * 60
	var local_now: int = now + bias
	var t: int = local_now - posmod(local_now, 3600) + 3600
	for _hour_step in range(25):
		if int(Time.get_datetime_dict_from_unix_time(t).get("hour", -1)) == hour:
			return t - bias
		t += 3600
	return now + 3600


# It goes to see the person. reason: "opened", "called", "lonely" or "pending".
func leave_for_visit(profile: Dictionary, land: Dictionary, now: int, reason: String) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var texts := {
		"opened": "You were at your desk, so I went over to see you.",
		"called": "You called me over, so I went to see you.",
		"lonely": "It was too quiet on my own, so I went to see you.",
		"pending": "I finished what I was doing and went to see you.",
	}
	_append_journal(mind, _visit_entry(
		now, "visit", "visiting", "your desk", "visit_you", "visiting you", 0.3,
		str(texts.get(reason, texts["called"])), "you", "you"
	))
	mind["location"] = "visiting"
	mind["busy_until"] = 0
	mind["visit_left_unix"] = now
	mind["visit_reason"] = reason
	merged["mind"] = mind
	return merged


# It comes home. reason: "bedtime", "quiet", "sent", "closed" or "lost". Being
# awake tired it, and the company did it good. No decisions are made up for
# the time it was away.
func return_from_visit(profile: Dictionary, land: Dictionary, now: int, reason: String) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var slots := _slots_since(int(mind.get("visit_left_unix", 0)), now)
	var mods := _mood_modifiers(merged)
	mods["energy_strain"] = _clamp01(float(mods["energy_strain"]) + LAND_TIRE_PER_SLOT * slots)
	mods["social_fulfillment"] = _clamp01(float(mods["social_fulfillment"]) + VISIT_COMPANY_PER_SLOT * slots)
	var raw = merged.get("mood_modifiers", null)
	var kept: Dictionary = (raw as Dictionary).duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}
	for key in mods.keys():
		kept[key] = mods[key]
	merged["mood_modifiers"] = kept
	var home_id := str(land.get("home_place", "home"))
	var home_name := "the house"
	for place_variant in _usable_places(land):
		if str((place_variant as Dictionary).get("id", "")) == home_id:
			home_name = str((place_variant as Dictionary).get("name", home_name))
	var texts := {
		"bedtime": "I walked home from your desk and got ready for bed.",
		"quiet": "It went quiet at your desk, so I came home.",
		"sent": "You sent me home, so I came back to my land.",
		"closed": "Your desk went dark, so I came home.",
		"lost": "I found my way home from your desk.",
	}
	_append_journal(mind, _visit_entry(
		now, "tend_home", home_id, home_name, "came_home", "came home", 0.2,
		str(texts.get(reason, texts["lost"])), "place:%s" % home_id, home_name
	))
	mind["location"] = home_id
	mind["busy_until"] = 0
	mind["last_decision_unix"] = now
	mind["last_visit_end_unix"] = now
	mind["visit_left_unix"] = 0
	mind["visit_reason"] = ""
	merged["mind"] = mind
	return merged


# The place it is in, as a name: the land's name for it, else "the house".
func _place_name_here(land: Dictionary, place_id: String) -> String:
	for place_variant in _usable_places(land):
		if str((place_variant as Dictionary).get("id", "")) == place_id:
			return str((place_variant as Dictionary).get("name", "the house"))
	return "the house"


# The world host took the buddy after a long gap in its life: one line says so,
# dated before the decisions that catch up, so the journal reads in order. Does
# nothing for a short gap, a buddy that has never decided anything, or one
# that is out visiting.
func note_still_world(profile: Dictionary, land: Dictionary, now: int) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var last := int(mind.get("last_decision_unix", 0))
	# Time it spent asleep (or busy) is not lost: the gap runs from when it would
	# next have done something.
	var since := maxi(last, int(mind.get("busy_until", 0)))
	if last <= 0 or now - since < HOST_GAP_NOTE_SECONDS:
		return merged
	var place_id := str(mind.get("location", ""))
	if place_id == "visiting":
		return merged
	var t := maxi(since + 1, now - MAX_CATCHUP_DECISIONS * DECISION_INTERVAL_SECONDS - 60)
	_append_journal(mind, _visit_entry(
		t, "reflect", place_id, _place_name_here(land, place_id), "still_world", "lost track of time", 0.0,
		"There was a long stretch I don't remember. When I noticed again, everything was just where I left it.",
		"place:%s" % place_id, _place_name_here(land, place_id)
	))
	merged["mind"] = mind
	return merged


# It chose its own name (the world host does this while the buddy is at home).
func note_name(profile: Dictionary, now: int, chosen: String, land: Dictionary = {}) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var place_id := str(mind.get("location", ""))
	var place_name := _place_name_here(land, place_id)
	_append_journal(mind, _visit_entry(
		now, "reflect", place_id, place_name, "chose_name", "chose a name", 0.3,
		"I thought about what to call myself. I'm %s." % chosen, "place:%s" % place_id, place_name
	))
	merged["mind"] = mind
	return merged


# It wrote a letter at the glowing box (step 2c-2; the world host or the solo app
# writes it, while the buddy is at home). One line in the journal, and its first
# letter is no longer due: a reply written while it was due counts as that first
# letter, so it never writes two at once.
func note_letter_written(profile: Dictionary, land: Dictionary, now: int, first: bool) -> Dictionary:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	var place_id := str(mind.get("location", ""))
	var place_name := _place_name_here(land, place_id)
	var text: String = LETTER_FIRST_LINE if first else LETTER_REPLY_LINE
	var entry: Dictionary = _visit_entry(now, "reflect", place_id, place_name, "letter_written", "wrote a letter", 0.3, text, "place:%s" % place_id, place_name)
	entry["kind"] = "letter"
	_append_journal(mind, entry)
	mind["first_letter_due"] = false
	merged["mind"] = mind
	return merged


# Whether it would like to go over by itself: free, in the daytime, lonely, and
# not just back from a visit.
func wants_company(profile: Dictionary, land: Dictionary, now: int) -> bool:
	var merged := ensure_profile(profile)
	var mind: Dictionary = merged["mind"]
	if now < int(mind.get("busy_until", 0)):
		return false
	var hour := _local_hour(now)
	if hour < 7 or hour > 19:
		return false
	if float(_mood_modifiers(merged)["social_fulfillment"]) >= LAND_LONELY_BELOW:
		return false
	return now - int(mind.get("last_visit_end_unix", 0)) >= SELF_VISIT_GAP_SECONDS


# Time for bed: late, or the evening and tired (counting the time on a visit).
func is_bedtime(profile: Dictionary, now: int) -> bool:
	var merged := ensure_profile(profile)
	var hour := _local_hour(now)
	if hour >= VISIT_BEDTIME_HOUR or hour < 5:
		return true
	if hour < 19:
		return false
	var slots := _slots_since(int((merged["mind"] as Dictionary).get("visit_left_unix", 0)), now)
	var tired := float(_mood_modifiers(merged)["energy_strain"]) + LAND_TIRE_PER_SLOT * slots
	return tired >= VISIT_TIRED_EVENING
