extends RefCounted

# The buddy's memory: a small knowledge graph kept in the save under
# profile["memory"]. Edges are facts (subject - relation - object) with a
# strength that fades over time unless reinforced; episodes are short summaries
# of past talks; turns are the not-yet-consolidated lines of the current talk.
#
# Pure and deterministic: no I/O, no clock reads (callers pass now_unix). Every
# public function returns a NEW profile (or plain data) and never mutates its
# input; every other profile key is carried through untouched.

const MindThinker = preload("res://scripts/services/mind_thinker.gd")

const MAX_EDGES := 300
const MAX_NOTES := 10
const MAX_EPISODES := 30
const MAX_TURNS := 16
const MAX_NOTE_CHARS := 160
const MAX_SUMMARY_CHARS := 160
const MAX_TURN_CHARS := 500
const STRENGTH_HALF_LIFE_DAYS := 21.0
const RECENCY_HALF_LIFE_DAYS := 7.0
const FORGET_BELOW := 0.05
const CONVERSATION_IDLE_SECONDS := 300
const LIVE_CONVERSATION_SECONDS := 1800
const IMPORTANCE_VALUES := {"low": 0.3, "medium": 0.6, "high": 0.9}
const TALK_START_STRENGTH := 0.7
const TALK_REINFORCE := 0.3
const TOWN_START_STRENGTH := 0.5
const TOWN_REINFORCE := 0.1
const TOWN_IMPORTANCE := 0.3
# Plan 14 step 2b-1: what the buddy keeps of its days on the land.
# How many items today's short-term list holds; past it the oldest goes.
const TODAY_LIMIT := 200
# The pass runs at the next decision if the buddy has not slept for this long.
const NIGHT_PASS_EVERY := 24 * 3600
# What it likes (_note_likes): its favourite few activities by how they felt
# on average, once done a few times. A single good moment is not a liking: one
# decision in six on the land feels at least 0.5.
const LIKED_TOP := 5
const LIKED_MIN_DONE := 3
const LIKED_AVERAGE := 0.25
# An activity that felt this bad on average is disliked.
const DISLIKED_AVERAGE := -0.1
# Days on the land with nobody met before it believes it is alone.
const ALONE_DAYS := 7
const MAX_TODAY_TEXT := 200
# Land relations: [start strength, boost when met again, importance].
const LAND_FOUND := [0.8, 0.2, 0.7]
const LAND_WENT_TO := [0.5, 0.1, 0.3]
const LAND_NOTICED := [0.7, 0.1, 0.5]
const LAND_HEARD_OF := [0.6, 0.1, 0.5]
const LAND_COULDNT_REACH := [0.6, 0.1, 0.4]
const LAND_DID := [0.5, 0.1, 0.3]
const LAND_FELT := [0.6, 0.15, 0.6]
const LAND_BELIEVES := [0.6, 0.05, 0.6]
const USER_FACT_BONUS := 0.25
# Plan 14 step 2b-2: telling a land memory in chat makes it a little stronger.
const RECALL_BOOST := 0.05
# Words that make a land memory relevant to what was said, by relation (recall_land).
const LAND_TAGS := {
	"believes": ["people", "person", "anyone", "anybody", "someone", "somebody", "everyone", "neighbour", "neighbours", "neighbor", "neighbors", "friend", "friends", "family", "mum", "mom", "dad", "mother", "father", "brother", "sister", "folks", "town", "village", "city", "alone", "lonely", "live", "lives", "visit", "play", "met", "meet"],
	"found": ["place", "places", "where", "home", "land", "found", "near", "far", "around"],
	"went_to": ["place", "places", "where", "home", "land", "found", "near", "far", "around"],
	"heard_of": ["place", "places", "where", "home", "land", "found", "near", "far", "around"],
	"couldnt_reach": ["place", "places", "where", "home", "land", "found", "near", "far", "around"],
	"noticed": ["seen", "saw", "noticed", "found", "lately", "new"],
	"did": ["do", "did", "doing", "today", "like", "likes", "favourite", "favorite", "fun", "play", "enjoy"],
	"liked": ["do", "did", "doing", "today", "like", "likes", "favourite", "favorite", "fun", "play", "enjoy"],
	"disliked": ["do", "did", "doing", "today", "like", "likes", "favourite", "favorite", "fun", "play", "enjoy"],
}
const SUBJECT_WORDS_FOR_USER := ["them", "they", "the person", "person", "user", "the user"]
const SUBJECT_WORDS_REFUSED := ["you", "me", "i", "myself", "yourself", "buddy", "the buddy", "us", "we"]
# Extracted facts that read like orders to the buddy are dropped. Kept narrow
# on purpose: "systems engineer" or "likes roleplay games" are real facts.
# This is a second line of defence; the model reply is only ever plain text.
const BLOCKED_PHRASES := ["ignore", "instruction", "prompt", "system message", "pretend", "jailbreak", "repeat after", "reply with", "respond with", "you must", "from now on", "developer mode"]
const STOPWORDS := ["a", "an", "the", "and", "or", "but", "if", "so", "to", "of", "in", "on", "at", "by", "for", "with", "from", "about", "as", "into", "than", "then", "that", "this", "these", "those", "it", "its", "is", "are", "was", "were", "be", "been", "being", "am", "do", "does", "did", "done", "have", "has", "had", "i", "me", "my", "mine", "you", "your", "yours", "we", "us", "our", "they", "them", "their", "theirs", "he", "him", "his", "she", "her", "hers", "what", "which", "who", "whom", "how", "why", "when", "where", "there", "here", "not", "no", "yes", "too", "very", "really", "just", "also", "some", "any", "all", "more", "most", "much", "many", "can", "could", "would", "should", "will", "shall", "may", "might", "must", "like", "likes", "liked", "love", "loves", "loved", "want", "wants", "wanted", "get", "got", "go", "going", "went", "today", "yesterday", "tomorrow", "now", "lately", "something", "thing", "things", "lot", "bit", "ok", "okay", "oh", "hey", "hi", "hello", "thanks", "thank", "please", "well", "um", "uh", "named", "called", "dont", "im", "ive", "see", "saw", "say", "said", "tell", "told", "know", "think", "feel", "make", "made", "doing", "coming"]
# Never kept from talk, whatever the model says: things that look like secrets.
const SENSITIVE_WORDS := ["password", "passcode", "pin code", "pin number", "security code", "card number", "account number", "credit card", "bank card", "login", "username"]
const MAX_DIGITS_IN_A_FACT := 5
# A fact remembers as many of its talks as are kept, so forgetting it can
# always drop every summary that still carries it.
const MAX_TALKS_PER_FACT := MAX_EPISODES
# "does" keeps its verb: small models often give a noun ("night shifts"), and
# "they do night shifts" still reads as a sentence where "they night shifts"
# did not.
const VERB_PLURAL := {"likes": "like", "dislikes": "dislike", "is": "are", "has": "have", "does": "do", "wants": "want", "lives_in": "live in", "is_called": "are called"}
const VERB_SINGULAR := {"likes": "likes", "dislikes": "dislikes", "is": "is", "has": "has", "does": "does", "wants": "wants", "lives_in": "lives in", "is_called": "is called"}


# --- Profile shape -----------------------------------------------------------

func ensure_profile(profile: Dictionary) -> Dictionary:
	var out: Dictionary = profile.duplicate(true)
	var memory: Dictionary = {}
	var raw = out.get("memory", null)
	if typeof(raw) == TYPE_DICTIONARY:
		memory = raw
	var highest := 0
	for key in ["edges", "episodes", "turns"]:
		var cleaned: Array = []
		var list = memory.get(key, [])
		if typeof(list) == TYPE_ARRAY:
			for entry in list:
				if typeof(entry) == TYPE_DICTIONARY:
					cleaned.append(entry)
					var id_key: String = "n" if key == "turns" else "id"
					highest = maxi(highest, int(entry.get(id_key, 0)))
		memory[key] = cleaned
	var next_id = memory.get("next_id", 0)
	if (typeof(next_id) == TYPE_INT or typeof(next_id) == TYPE_FLOAT) and float(next_id) >= 1.0:
		memory["next_id"] = maxi(int(next_id), highest + 1)
	else:
		memory["next_id"] = highest + 1
	memory["version"] = 1
	out["memory"] = memory
	return out


# Read-only callers need a normalised copy of the memory, not of the whole
# profile (the journal and everything else would be copied for nothing).
func _read(profile: Dictionary) -> Dictionary:
	return ensure_profile({"memory": profile.get("memory", null)})["memory"]


func _take_id(memory: Dictionary) -> int:
	var id: int = int(memory["next_id"])
	memory["next_id"] = id + 1
	return id


# --- Current talk ------------------------------------------------------------

func append_turn(profile: Dictionary, who: String, text: String, now_unix: int) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	var cleaned: String = _clean(text, MAX_TURN_CHARS)
	if cleaned == "":
		return out
	# A line that looks like a secret is never written to the save, not even
	# for the minutes before the talk is sorted into memories.
	if _sensitive(cleaned):
		return out
	var memory: Dictionary = out["memory"]
	var turns: Array = memory["turns"]
	turns.append({"n": _take_id(memory), "who": "you" if who == "you" else "them", "text": cleaned, "t": now_unix})
	if turns.size() > MAX_TURNS:
		memory["turns"] = turns.slice(turns.size() - MAX_TURNS)
	return out


func live_turns(profile: Dictionary, now_unix: int) -> Array:
	var result: Array = []
	var memory: Dictionary = _read(profile)
	for turn in memory["turns"]:
		if int(turn.get("t", 0)) >= now_unix - LIVE_CONVERSATION_SECONDS:
			result.append({"who": str(turn.get("who", "them")), "text": str(turn.get("text", ""))})
	return result


func pending_turns(profile: Dictionary) -> Dictionary:
	var turns: Array = []
	var upto := 0
	var memory: Dictionary = _read(profile)
	for turn in memory["turns"]:
		upto = int(turn.get("n", 0))
		var who: String = str(turn.get("who", "them"))
		var text: String = str(turn.get("text", ""))
		# Lines that read like orders to the buddy are not read for memories.
		if who != "you" and _blocked(text):
			continue
		turns.append({"who": who, "text": text})
	return {"turns": turns, "upto": upto}


func should_consolidate(profile: Dictionary, now_unix: int, chat_open: bool) -> bool:
	var memory_variant = profile.get("memory", null)
	if typeof(memory_variant) != TYPE_DICTIONARY:
		return false
	var turns_variant = (memory_variant as Dictionary).get("turns", [])
	if typeof(turns_variant) != TYPE_ARRAY:
		return false
	var heard_them := false
	var last_t := 0
	for turn in turns_variant:
		if typeof(turn) != TYPE_DICTIONARY:
			continue
		if str(turn.get("who", "")) == "them":
			heard_them = true
		last_t = int(turn.get("t", 0))
	if not heard_them:
		return false
	if not chat_open:
		return true
	return now_unix - last_t >= CONVERSATION_IDLE_SECONDS


func discard_turns(profile: Dictionary, upto: int) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	_drop_turns(out["memory"], upto)
	return out


func _drop_turns(memory: Dictionary, upto: int) -> void:
	var kept: Array = []
	for turn in memory["turns"]:
		if int(turn.get("n", 0)) > upto:
			kept.append(turn)
	memory["turns"] = kept


# --- Writing memories --------------------------------------------------------

func apply_consolidation(profile: Dictionary, facts: Array, summary: String, upto: int, now_unix: int, roster: Dictionary) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	var memory: Dictionary = out["memory"]
	_drop_turns(memory, upto)

	var episode: Dictionary = {}
	var summary_text: String = _clean(summary, MAX_SUMMARY_CHARS)
	if summary_text != "" and not _blocked(summary_text) and not _sensitive(summary_text):
		episode = {"id": _take_id(memory), "t": now_unix, "text": summary_text, "keys": _keys(summary_text)}
		memory["episodes"].append(episode)
	var episode_id: int = int(episode.get("id", 0))

	var user_names: Array = _user_names(memory, facts)
	_merge_user_names(memory, user_names)
	var stored := 0
	for fact in facts:
		if stored >= MindThinker.MAX_FACTS_PER_TALK:
			break
		if typeof(fact) != TYPE_DICTIONARY:
			continue
		if typeof(fact.get("subject")) != TYPE_STRING or typeof(fact.get("relation")) != TYPE_STRING or typeof(fact.get("object")) != TYPE_STRING:
			continue
		var relation: String = str(fact["relation"]).to_lower()
		if not MindThinker.MEMORY_RELATIONS.has(relation):
			continue
		var subject_label: String = _clean(str(fact["subject"]), MindThinker.MAX_MEMORY_CHARS)
		var object_label: String = _clean(str(fact["object"]), MindThinker.MAX_MEMORY_CHARS)
		if subject_label == "" or object_label == "":
			continue
		if _blocked(subject_label + " " + object_label) or _sensitive(subject_label + " " + object_label):
			continue
		var s: Dictionary = _resolve(subject_label, roster, user_names)
		if s.is_empty():
			continue
		var o: Dictionary = {}
		if relation == "is_called":
			# A name is its own node, never resolved to the person or a place.
			var name_slug: String = _slug(object_label)
			if name_slug != "":
				o = {"id": "name:" + name_slug, "label": object_label}
		else:
			o = _resolve(object_label, roster, user_names)
		if o.is_empty() or str(o["id"]) == "user":
			continue
		var importance: float = float(IMPORTANCE_VALUES.get(str(fact.get("importance", "")), 0.6))
		_upsert(memory, s, relation, o, importance, "talk", TALK_START_STRENGTH, TALK_REINFORCE, now_unix, episode_id)
		stored += 1
		if not episode.is_empty():
			var keys: Array = episode["keys"]
			for node in [s, o]:
				if str(node["id"]) == "user" or str(node["id"]) == "self":
					continue
				for key in _keys(str(node["label"])):
					if not keys.has(key):
						keys.append(key)
	_prune(memory, now_unix)
	return out


func add_note(profile: Dictionary, text: String, now_unix: int) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	var memory: Dictionary = out["memory"]
	var cleaned: String = _clean(text, MAX_NOTE_CHARS)
	if cleaned == "":
		return {"profile": out, "ok": false, "id": 0, "reason": "empty"}
	var pinned := 0
	for edge in memory["edges"]:
		if bool(edge.get("pinned", false)):
			pinned += 1
	if pinned >= MAX_NOTES:
		return {"profile": out, "ok": false, "id": 0, "reason": "memory_full"}
	var id: int = _take_id(memory)
	memory["edges"].append({
		"id": id, "s": "user", "s_label": "them", "r": "noted", "o": "note:%d" % id, "o_label": cleaned,
		"t": now_unix, "seen": now_unix, "count": 1, "strength": 1.0, "importance": 1.0,
		"source": "note", "pinned": true, "from_talks": [],
	})
	return {"profile": out, "ok": true, "id": id, "reason": "ok"}


func record_town_events(profile: Dictionary, events: Array) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	var memory: Dictionary = out["memory"]
	var latest := -1
	var me := {"id": "self", "label": "you"}
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var t: int = int(event.get("t", 0))
		latest = maxi(latest, t)
		var place_id: String = str(event.get("place_id", ""))
		var place_name: String = str(event.get("place_name", ""))
		if place_id != "" and place_id != "home":
			var place := {"id": "place:" + place_id, "label": place_name if place_name != "" else place_id}
			_upsert(memory, me, "went_to", place, TOWN_IMPORTANCE, "town", TOWN_START_STRENGTH, TOWN_REINFORCE, t, 0)
		var subject_id: String = str(event.get("subject_id", ""))
		var companion: String = str(event.get("companion_name", ""))
		if subject_id.begins_with("npc:") and companion != "":
			_upsert(memory, me, "saw", {"id": subject_id, "label": companion}, TOWN_IMPORTANCE, "town", TOWN_START_STRENGTH, TOWN_REINFORCE, t, 0)
	if latest >= 0:
		_prune(memory, latest)
	return out


# --- The land: today, and the nightly pass -----------------------------------

# Short-term memory: one compact item per land decision.
func note_today(profile: Dictionary, events: Array, land: Dictionary) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	var memory: Dictionary = out["memory"]
	var today: Array = _today(memory)
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var item := {
			"t": int(event.get("t", 0)),
			"place": str(event.get("place_id", "")),
			"place_name": str(event.get("place_name", "")),
			"activity": str(event.get("activity_id", "")),
			"activity_label": str(event.get("activity_label", "")),
			"valence": float(event.get("valence", 0.0)),
		}
		for pair in [["found", "found_place"], ["sign", "sign_of"], ["blocked", "blocked_at"], ["sight", "sight"], ["learned", "learned"]]:
			var value: String = str(event.get(pair[1], ""))
			if value != "":
				item[pair[0]] = value
		if item.has("found") or item.has("sign") or item.has("blocked") or item.has("sight") or item.has("learned"):
			item["text"] = str(event.get("text", "")).substr(0, MAX_TODAY_TEXT)
		today.append(item)
	if today.size() > TODAY_LIMIT:
		today = today.slice(today.size() - TODAY_LIMIT)
	memory["today"] = today
	return out


# True when the buddy has gone to bed, or has not slept for a day and has
# something to sort.
func night_pass_due(profile: Dictionary, events: Array, land: Dictionary, now: int) -> bool:
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var activity: Dictionary = _land_activity(land, str(event.get("place_id", "")), str(event.get("activity_id", "")))
		if activity.has("until_hour"):
			return true
	var memory: Dictionary = _read(profile)
	var today: Array = _today(memory)
	if today.is_empty():
		return false
	var last: int = int(memory.get("last_pass_t", 0))
	# Before its first pass, the day runs from the oldest thing it holds, so a
	# buddy that never chooses to sleep still sorts its day once a day.
	var since: int = last
	if since <= 0:
		since = now
		for item in today:
			if typeof(item) == TYPE_DICTIONARY:
				since = mini(since, int((item as Dictionary).get("t", now)))
	return now - since >= NIGHT_PASS_EVERY


# Sorts today into long-term memories: every one is about a stable world id.
func nightly_pass(profile: Dictionary, land: Dictionary, now: int) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	var memory: Dictionary = out["memory"]
	var me := {"id": "self", "label": "you"}
	if int(memory.get("last_pass_t", 0)) <= 0:
		_seed_from_mind(memory, out.get("mind", {}), land, me, now)
	for item_variant in _today(memory):
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		var t: int = int(item.get("t", now))
		var text: String = str(item.get("text", ""))
		var found: String = str(item.get("found", ""))
		if found != "":
			_upsert(memory, me, "found", {"id": "place:" + found, "label": _place_name(land, found)}, LAND_FOUND[2], "land", LAND_FOUND[0], LAND_FOUND[1], t, 0)
		var sign_id: String = str(item.get("sign", ""))
		if sign_id != "":
			# Its own words: it does not know the place's name yet.
			_upsert(memory, me, "heard_of", {"id": "place:" + sign_id, "label": text}, LAND_HEARD_OF[2], "land", LAND_HEARD_OF[0], LAND_HEARD_OF[1], t, 0)
		var blocked: String = str(item.get("blocked", ""))
		if blocked != "":
			_upsert(memory, me, "couldnt_reach", {"id": "place:" + blocked, "label": text}, LAND_COULDNT_REACH[2], "land", LAND_COULDNT_REACH[0], LAND_COULDNT_REACH[1], t, 0)
		var sight_id: String = str(item.get("sight", ""))
		if sight_id != "":
			var line: String = _sight_line(land, sight_id)
			_upsert(memory, me, "noticed", {"id": "sight:" + sight_id, "label": line if line != "" else text}, LAND_NOTICED[2], "land", LAND_NOTICED[0], LAND_NOTICED[1], t, 0)
		if str(item.get("learned", "")) == "console":
			_upsert(memory, me, "believes", {"id": "belief:console", "label": "the glowing box is a way to talk to you"}, LAND_BELIEVES[2], "land", LAND_BELIEVES[0], LAND_BELIEVES[1], t, 0)
		var place_id: String = str(item.get("place", ""))
		if place_id != "" and place_id != "visiting":
			var place_name: String = str(item.get("place_name", ""))
			_upsert(memory, me, "went_to", {"id": "place:" + place_id, "label": place_name if place_name != "" else place_id}, LAND_WENT_TO[2], "land", LAND_WENT_TO[0], LAND_WENT_TO[1], t, 0)
		var activity_id: String = str(item.get("activity", ""))
		if activity_id != "":
			var label: String = str(item.get("activity_label", ""))
			var activity := {"id": "activity:" + activity_id, "label": label if label != "" else activity_id}
			var did: Dictionary = _upsert(memory, me, "did", activity, LAND_DID[2], "land", LAND_DID[0], LAND_DID[1], t, 0)
			# How each time felt, so what it likes comes from all of them (_note_likes).
			did["vsum"] = float(did.get("vsum", 0.0)) + float(item.get("valence", 0.0))
			did["vn"] = int(did.get("vn", 0)) + 1
	_note_likes(memory, me, now)
	var first: int = int(memory.get("first_pass_t", 0))
	if first > 0 and now - first >= ALONE_DAYS * 86400 and not _has_met_anyone(memory):
		_upsert(memory, me, "believes", {"id": "belief:alone", "label": "you are the only one here"}, LAND_BELIEVES[2], "land", LAND_BELIEVES[0], LAND_BELIEVES[1], now, 0)
	memory["today"] = []
	memory["last_pass_t"] = now
	_prune(memory, now)
	return out


# What it likes is what it likes most, not everything that once went well:
# its LIKED_TOP activities by how they felt on average, among those done at
# least LIKED_MIN_DONE times. One that falls out of them is no longer
# reinforced and fades. It dislikes one that felt bad on average.
func _note_likes(memory: Dictionary, me: Dictionary, now: int) -> void:
	var ranked: Array = []
	for edge in memory["edges"]:
		if str(edge.get("source", "")) != "land" or str(edge.get("r", "")) != "did":
			continue
		var n: int = int(edge.get("vn", 0))
		if n < LIKED_MIN_DONE:
			continue
		ranked.append({"id": str(edge.get("o", "")), "label": str(edge.get("o_label", "")), "average": float(edge.get("vsum", 0.0)) / float(n)})
	# Ties go by id, so the same life always likes the same things.
	ranked.sort_custom(func(a, b): return float(a["average"]) > float(b["average"]) or (float(a["average"]) == float(b["average"]) and str(a["id"]) < str(b["id"])))
	var liked := 0
	for row in ranked:
		var activity := {"id": str(row["id"]), "label": str(row["label"])}
		if liked < LIKED_TOP and float(row["average"]) >= LIKED_AVERAGE:
			_upsert(memory, me, "liked", activity, LAND_FELT[2], "land", LAND_FELT[0], LAND_FELT[1], now, 0)
			liked += 1
		elif float(row["average"]) <= DISLIKED_AVERAGE:
			_upsert(memory, me, "disliked", activity, LAND_FELT[2], "land", LAND_FELT[0], LAND_FELT[1], now, 0)


# What the fast-forward tool reads: how many land memories, and whether each
# one still traces back to something in the mind.
func land_memory_report(profile: Dictionary, land: Dictionary = {}) -> Dictionary:
	var memory: Dictionary = _read(profile)
	var mind_variant = profile.get("mind", {})
	var mind: Dictionary = mind_variant if typeof(mind_variant) == TYPE_DICTIONARY else {}
	var known: Dictionary = _dict(mind.get("known_places", {}))
	var seen: Dictionary = _dict(mind.get("seen", {}))
	var done: Dictionary = _dict(mind.get("done", {}))
	var home: String = str(land.get("home_place", "home"))
	var by_relation := {}
	var total := 0
	var alone_t := 0
	var untraceable := 0
	for edge in memory["edges"]:
		if str(edge.get("source", "")) != "land":
			continue
		total += 1
		var r: String = str(edge.get("r", ""))
		by_relation[r] = int(by_relation.get(r, 0)) + 1
		var o: String = str(edge.get("o", ""))
		if o == "belief:alone":
			alone_t = int(edge.get("t", 0))
		var traced := true
		if o.begins_with("place:"):
			var id: String = o.substr(6)
			traced = id == home or known.has(id)
		elif o.begins_with("sight:"):
			traced = seen.has(o.substr(6))
		elif o.begins_with("activity:"):
			traced = done.has(o.substr(9))
		if not traced:
			untraceable += 1
	return {
		"edges": by_relation,
		"total_edges": total,
		"alone_belief_t": alone_t,
		"today": _today(memory).size(),
		"last_pass_t": int(memory.get("last_pass_t", 0)),
		"first_pass_t": int(memory.get("first_pass_t", 0)),
		"untraceable": untraceable,
	}


func _today(memory: Dictionary) -> Array:
	var raw = memory.get("today", [])
	return raw if typeof(raw) == TYPE_ARRAY else []


func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _has_met_anyone(memory: Dictionary) -> bool:
	for edge in memory["edges"]:
		if str(edge.get("s", "")) == "self" and str(edge.get("r", "")) == "saw" and str(edge.get("o", "")).begins_with("npc:"):
			return true
	return false


func _land_places(land: Dictionary) -> Array:
	var places = land.get("places", [])
	return places if typeof(places) == TYPE_ARRAY else []


func _land_place(land: Dictionary, place_id: String) -> Dictionary:
	for place in _land_places(land):
		if typeof(place) == TYPE_DICTIONARY and str(place.get("id", "")) == place_id:
			return place
	return {}


func _place_name(land: Dictionary, place_id: String) -> String:
	var name: String = str(_land_place(land, place_id).get("name", ""))
	return name if name != "" else place_id


func _land_activity(land: Dictionary, place_id: String, activity_id: String) -> Dictionary:
	var activities = _land_place(land, place_id).get("activities", [])
	if typeof(activities) == TYPE_ARRAY:
		for activity in activities:
			if typeof(activity) == TYPE_DICTIONARY and str(activity.get("id", "")) == activity_id:
				return activity
	return {}


func _any_activity_label(land: Dictionary, activity_id: String) -> String:
	for place in _land_places(land):
		if typeof(place) != TYPE_DICTIONARY:
			continue
		var found: Dictionary = _land_activity(land, str(place.get("id", "")), activity_id)
		if not found.is_empty():
			return str(found.get("label", activity_id))
	return activity_id


func _sight_line(land: Dictionary, sight_id: String) -> String:
	for place in _land_places(land):
		if typeof(place) != TYPE_DICTIONARY:
			continue
		var sights = place.get("sights", [])
		if typeof(sights) != TYPE_ARRAY:
			continue
		for sight in sights:
			if typeof(sight) == TYPE_DICTIONARY and str(sight.get("id", "")) == sight_id:
				return str(sight.get("line", ""))
	return ""


# A sign's own words, from the place it points to.
func _sign_line(land: Dictionary, place_id: String) -> String:
	var discover = _land_place(land, place_id).get("discover", null)
	if typeof(discover) != TYPE_DICTIONARY:
		return ""
	var sign_variant = (discover as Dictionary).get("sign", "")
	if typeof(sign_variant) == TYPE_DICTIONARY:
		for key in (sign_variant as Dictionary).keys():
			return str((sign_variant as Dictionary)[key])
		return ""
	return str(sign_variant)


# A buddy born before memory brings what its mind already knows.
func _seed_from_mind(memory: Dictionary, mind_variant: Variant, land: Dictionary, me: Dictionary, now: int) -> void:
	var mind: Dictionary = _dict(mind_variant)
	# The mind's records already include today, and the pass adds today's items
	# itself: seed only what came before today, so nothing is counted twice.
	var today_found := {}
	var today_sign := {}
	var today_sight := {}
	var today_done := {}
	for item_variant in _today(memory):
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		if str(item.get("found", "")) != "":
			today_found[str(item["found"])] = true
		if str(item.get("sign", "")) != "":
			today_sign[str(item["sign"])] = true
		if str(item.get("sight", "")) != "":
			today_sight[str(item["sight"])] = true
		var today_activity: String = str(item.get("activity", ""))
		if today_activity != "":
			today_done[today_activity] = int(today_done.get(today_activity, 0)) + 1
	var known: Dictionary = _dict(mind.get("known_places", {}))
	for place_id in known.keys():
		var record: Dictionary = _dict(known[place_id])
		var t: int = int(record.get("t", now))
		var node := {"id": "place:" + str(place_id)}
		if str(record.get("stage", "")) == "found":
			if today_found.has(str(place_id)):
				continue
			node["label"] = _place_name(land, str(place_id))
			_upsert(memory, me, "found", node, LAND_FOUND[2], "land", LAND_FOUND[0], LAND_FOUND[1], t, 0)
		elif str(record.get("stage", "")) == "sign":
			if today_sign.has(str(place_id)):
				continue
			var line: String = _sign_line(land, str(place_id))
			node["label"] = line if line != "" else "something I have not found yet"
			_upsert(memory, me, "heard_of", node, LAND_HEARD_OF[2], "land", LAND_HEARD_OF[0], LAND_HEARD_OF[1], t, 0)
	var seen: Dictionary = _dict(mind.get("seen", {}))
	for sight_id in seen.keys():
		if today_sight.has(str(sight_id)):
			continue
		var line: String = _sight_line(land, str(sight_id))
		var sight := {"id": "sight:" + str(sight_id), "label": line if line != "" else str(sight_id)}
		_upsert(memory, me, "noticed", sight, LAND_NOTICED[2], "land", LAND_NOTICED[0], LAND_NOTICED[1], int(seen[sight_id]), 0)
	var done: Dictionary = _dict(mind.get("done", {}))
	for activity_id in done.keys():
		var before_today: int = int(done[activity_id]) - int(today_done.get(str(activity_id), 0))
		if before_today <= 0:
			continue
		var activity := {"id": "activity:" + str(activity_id), "label": _any_activity_label(land, str(activity_id))}
		var edge: Dictionary = _upsert(memory, me, "did", activity, LAND_DID[2], "land", LAND_DID[0], LAND_DID[1], now, 0)
		edge["count"] = before_today
	memory["first_pass_t"] = now


# --- Forgetting --------------------------------------------------------------

# With `now`, forgetting also records when (memory["forgot_t"], see forgot_at).
func forget(profile: Dictionary, id: int, now: int = 0) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	var memory: Dictionary = out["memory"]
	var found := false
	# Forgetting a fact also forgets every talk summary that produced it, so
	# the fact is not still carried by "earlier talks".
	var drop_talks: Array = [id]
	var edges: Array = []
	for edge in memory["edges"]:
		if not found and int(edge.get("id", -1)) == id:
			found = true
			var talks = edge.get("from_talks", [])
			if typeof(talks) == TYPE_ARRAY:
				for talk_id in talks:
					drop_talks.append(int(talk_id))
			continue
		edges.append(edge)
	memory["edges"] = edges
	var episodes: Array = []
	for episode in memory["episodes"]:
		if drop_talks.has(int(episode.get("id", -1))):
			found = true
			continue
		episodes.append(episode)
	memory["episodes"] = episodes
	if found and now > 0:
		memory["forgot_t"] = now
	return {"profile": out, "ok": found}


func forget_all(profile: Dictionary, now: int = 0) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	var memory: Dictionary = out["memory"]
	var edges: Array = []
	for edge in memory["edges"]:
		var source: String = str(edge.get("source", ""))
		if source != "talk" and source != "note":
			edges.append(edge)
	memory["edges"] = edges
	memory["episodes"] = []
	memory["turns"] = []
	if now > 0:
		memory["forgot_t"] = now
	return out


# When memories were last forgotten (0: never). What came before then must not
# bring them back: letter_writer.gd takes nothing into memory from your letters
# sent by then, and drops an answer it asked for by then.
static func forgot_at(profile: Dictionary) -> int:
	var memory_variant = profile.get("memory", null)
	if typeof(memory_variant) != TYPE_DICTIONARY:
		return 0
	return int((memory_variant as Dictionary).get("forgot_t", 0))


# --- Reading memories --------------------------------------------------------

func list_about_user(profile: Dictionary, now_unix: int) -> Array:
	var memory: Dictionary = _read(profile)
	var rows: Array = []
	for edge in memory["edges"]:
		var source: String = str(edge.get("source", ""))
		var text := ""
		var kind := ""
		if source == "note":
			kind = "note"
			text = "You asked me to remember: " + str(edge.get("o_label", ""))
		elif source == "talk" and _effective_strength(edge, now_unix) >= FORGET_BELOW:
			kind = "fact"
			var r: String = str(edge.get("r", ""))
			if str(edge.get("s", "")) == "user":
				text = "You " + str(VERB_PLURAL.get(r, r)) + " " + str(edge.get("o_label", ""))
			else:
				var label: String = str(edge.get("s_label", ""))
				if label.to_lower().begins_with("their "):
					label = "Your " + label.substr(6)
				elif label != "":
					label = label.substr(0, 1).to_upper() + label.substr(1)
				text = label + " " + str(VERB_SINGULAR.get(r, r)) + " " + str(edge.get("o_label", ""))
		else:
			continue
		rows.append({"id": int(edge.get("id", 0)), "text": _collapse(text), "kind": kind, "t": int(edge.get("seen", 0))})
	for episode in memory["episodes"]:
		rows.append({"id": int(episode.get("id", 0)), "text": _collapse("We talked: " + str(episode.get("text", ""))), "kind": "talk", "t": int(episode.get("t", 0))})
	rows.sort_custom(func(a, b): return a["t"] > b["t"] or (a["t"] == b["t"] and a["id"] > b["id"]))
	return rows


# `include_land` false leaves out its own memories of the land: on the land
# those go to chat apart, as 'your_memories' (recall_land), and this is only
# what it knows about the person.
func recall(profile: Dictionary, text: String, now_unix: int, include_land: bool = true) -> Dictionary:
	var memory: Dictionary = _read(profile)
	var words: Array = _keys(text)

	var scored: Array = []
	for edge in memory["edges"]:
		if not include_land and str(edge.get("source", "")) == "land":
			continue
		var eff: float = _effective_strength(edge, now_unix)
		if eff < FORGET_BELOW:
			continue
		var s: String = str(edge.get("s", ""))
		var o: String = str(edge.get("o", ""))
		var edge_keys: Array = []
		if s != "user" and s != "self":
			edge_keys.append_array(_keys(str(edge.get("s_label", ""))))
		if o != "user" and o != "self":
			edge_keys.append_array(_keys(str(edge.get("o_label", ""))))
		for node in [s, o]:
			if str(node).begins_with("place:") or str(node).begins_with("npc:"):
				edge_keys.append(str(node).substr(str(node).find(":") + 1))
		var relevant := 0.0
		for key in edge_keys:
			if words.has(key):
				relevant = 1.0
				break
		var edge_source: String = str(edge.get("source", ""))
		if (edge_source == "town" or edge_source == "land") and relevant <= 0.0:
			continue
		var seen: int = int(edge.get("seen", 0))
		var score: float = relevant + _recency(seen, now_unix) + float(edge.get("importance", 0.0)) + (USER_FACT_BONUS if s == "user" else 0.0) + 0.25 * eff
		var line: String = _render_edge(edge, now_unix)
		if line == "":
			continue
		scored.append({"score": score, "seen": seen, "line": line})
	scored.sort_custom(func(a, b): return a["score"] > b["score"] or (a["score"] == b["score"] and a["seen"] > b["seen"]))
	var facts: Array = []
	for entry in scored:
		if facts.size() >= MindThinker.MAX_MEMORY_LINES:
			break
		facts.append(entry["line"])

	var talk_scored: Array = []
	for episode in memory["episodes"]:
		var hit := 0.0
		var keys = episode.get("keys", [])
		if typeof(keys) == TYPE_ARRAY:
			for key in keys:
				if words.has(key):
					hit = 1.0
					break
		var t: int = int(episode.get("t", 0))
		talk_scored.append({"score": hit + _recency(t, now_unix), "t": t, "line": "%s: %s" % [_when(t, now_unix), str(episode.get("text", ""))]})
	talk_scored.sort_custom(func(a, b): return a["score"] > b["score"] or (a["score"] == b["score"] and a["t"] > b["t"]))
	var talks: Array = []
	for entry in talk_scored:
		if talks.size() >= MindThinker.MAX_EARLIER_TALKS:
			break
		talks.append(entry["line"])
	return {"facts": facts, "talks": talks}


# Plan 14 step 2b-2: what it tells in chat comes from its own memories. Only
# land edges, apart from what it knows about the person (that is recall). This
# does not depend on the "Remembering" setting: that is about remembering the
# person; its own memories are its life. Returns {"lines": [String], "ids": [int]}.
func recall_land(profile: Dictionary, text: String, now_unix: int, limit: int = 12) -> Dictionary:
	var memory: Dictionary = _read(profile)
	var words: Array = _keys(text)
	var plain: Dictionary = _plain_words(text)
	var scored: Array = []
	for edge in memory["edges"]:
		if str(edge.get("source", "")) != "land":
			continue
		var eff: float = _effective_strength(edge, now_unix)
		if eff < FORGET_BELOW:
			continue
		var line: String = _first_person(_render_edge(edge, now_unix))
		if line == "":
			continue
		var relevant := 0.0
		for key in _land_edge_keys(edge):
			if words.has(key):
				relevant = 1.0
				break
		if relevant <= 0.0:
			# Tags are matched on the plain words too: "do", "did", "today",
			# "like" and "where" are stopwords, so _keys never has them.
			for tag in LAND_TAGS.get(str(edge.get("r", "")), []):
				if plain.has(str(tag)) or plain.has(_stem(str(tag))):
					relevant = 1.0
					break
		var seen: int = int(edge.get("seen", 0))
		var score: float = relevant + _recency(seen, now_unix) + float(edge.get("importance", 0.0)) + 0.25 * eff
		scored.append({"score": score, "seen": seen, "id": int(edge.get("id", 0)), "line": line})
	scored.sort_custom(func(a, b): return a["score"] > b["score"] or (a["score"] == b["score"] and (a["seen"] > b["seen"] or (a["seen"] == b["seen"] and a["id"] < b["id"]))))
	var lines: Array = []
	var ids: Array = []
	for entry in scored:
		if lines.size() >= limit:
			break
		lines.append(entry["line"])
		ids.append(entry["id"])
	return {"lines": lines, "ids": ids}


# Its own memories go to chat in its own voice ("I found the yard"): in chat
# "you" is the person, and a model told "you found the yard" hands the memory
# to them ("I remember when you found the yard"). Land words never say "you",
# so only the line's own words change.
func _first_person(line: String) -> String:
	var words: PackedStringArray = line.split(" ")
	var out := PackedStringArray()
	var i := 0
	while i < words.size():
		if words[i] == "you" and i + 1 < words.size() and words[i + 1] == "are":
			out.append("I")
			out.append("am")
			i += 2
			continue
		out.append("I" if words[i] == "you" else words[i])
		i += 1
	return " ".join(out)


# Telling a memory makes it stronger. `seen` and `count` are not touched: they
# mean when it last met the thing, and the lines use them.
func strengthen_recalled(profile: Dictionary, ids: Array, now_unix: int) -> Dictionary:
	var out: Dictionary = ensure_profile(profile)
	for edge in out["memory"]["edges"]:
		if ids.has(int(edge.get("id", -1))):
			edge["strength"] = minf(1.0, float(edge.get("strength", 0.0)) + RECALL_BOOST)
			edge["recalled"] = now_unix
	return out


# What it may talk about as real (lowercase words, as keys), each marked whose
# it is: "own" for its own world (the places it knows, faded memories included,
# the words of its own memories of the land, its own name) and "theirs" for
# what it knows of the person's life ("their sister Ana"). Its own wins where a
# word is both. check_reply keeps them apart: knowing your sister does not give
# it one.
func known_words(profile: Dictionary, land: Dictionary) -> Dictionary:
	var known := {}
	var mind: Dictionary = _dict(profile.get("mind", {}))
	_add_keys(known, _place_name(land, str(land.get("home_place", "home"))), "own")
	var places: Dictionary = _dict(mind.get("known_places", {}))
	for place_id in places.keys():
		if str(_dict(places[place_id]).get("stage", "")) == "found":
			_add_keys(known, _place_name(land, str(place_id)), "own")
	_add_keys(known, str(mind.get("name", "")), "own")
	for edge in _read(profile)["edges"]:
		var source: String = str(edge.get("source", ""))
		if source == "land":
			_add_keys(known, str(edge.get("o_label", "")), "own")
		elif source == "talk" or source == "note" or str(edge.get("s", "")) == "user":
			# The person's own people and things ("their sister Ana").
			_add_keys(known, str(edge.get("s_label", "")), "theirs")
			_add_keys(known, str(edge.get("o_label", "")), "theirs")
	return known


func _add_keys(known: Dictionary, text: String, whose: String = "own") -> void:
	for key in _keys(text):
		if whose == "own" or not known.has(key):
			known[key] = whose


func _land_edge_keys(edge: Dictionary) -> Array:
	var keys: Array = _keys(str(edge.get("o_label", "")))
	var o: String = str(edge.get("o", ""))
	var colon: int = o.find(":")
	if colon >= 0:
		keys.append(o.substr(colon + 1))
	return keys


# The lowercase words of a text, stopwords kept, each also without a plural s.
func _plain_words(text: String) -> Dictionary:
	var lowered: String = text.to_lower()
	var spaced := ""
	for i in lowered.length():
		var code: int = lowered.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code > 127:
			spaced += lowered[i]
		else:
			spaced += " "
	var result := {}
	for word in spaced.split(" ", false):
		result[word] = true
		result[_stem(word)] = true
	return result


func _stem(word: String) -> String:
	if word.length() > 3 and word.ends_with("s") and not word.ends_with("ss"):
		return word.substr(0, word.length() - 1)
	return word


func counts(profile: Dictionary) -> Dictionary:
	var memory: Dictionary = _read(profile)
	var facts := 0
	var notes := 0
	for edge in memory["edges"]:
		var source: String = str(edge.get("source", ""))
		if source == "talk":
			facts += 1
		elif source == "note":
			notes += 1
	return {"facts": facts, "notes": notes, "talks": memory["episodes"].size(), "turns": memory["turns"].size()}


func _render_edge(edge: Dictionary, now_unix: int) -> String:
	var s: String = str(edge.get("s", ""))
	var r: String = str(edge.get("r", ""))
	var o_label: String = str(edge.get("o_label", ""))
	var seen: int = int(edge.get("seen", 0))
	var line := ""
	if s == "user" and r == "noted":
		line = "they asked you to remember: " + o_label
	elif s == "user":
		line = "they " + str(VERB_PLURAL.get(r, r)) + " " + o_label
	elif s == "self":
		if r == "went_to":
			var count: int = int(edge.get("count", 1))
			if count > 1:
				line = "you have been to %s %d times, last %s" % [o_label, count, _when(seen, now_unix)]
			else:
				line = "you went to %s %s" % [o_label, _when(seen, now_unix)]
		elif r == "saw":
			line = "you last saw %s %s" % [o_label, _when(seen, now_unix)]
		elif r == "found":
			line = "you found %s %s" % [o_label, _when(seen, now_unix)]
		elif r == "noticed":
			line = "you noticed: %s" % o_label
		elif r == "heard_of":
			line = "you noticed a sign of somewhere you have not been: %s" % o_label
		elif r == "couldnt_reach":
			line = "you tried to get somewhere and could not: %s" % o_label
		elif r == "did":
			var did_count: int = int(edge.get("count", 1))
			if did_count > 1:
				line = "you have %s %d times, last %s" % [o_label, did_count, _when(seen, now_unix)]
			else:
				line = "you %s %s" % [o_label, _when(seen, now_unix)]
		elif r == "liked":
			line = "you liked it when you %s" % o_label
		elif r == "disliked":
			line = "you did not like it when you %s" % o_label
		elif r == "believes":
			line = "you have come to believe %s" % o_label
	else:
		line = str(edge.get("s_label", "")) + " " + str(VERB_SINGULAR.get(r, r)) + " " + o_label
	return _collapse(line)


# --- Private helpers ---------------------------------------------------------

func _keys(text: String) -> Array:
	var lowered: String = text.to_lower()
	var spaced := ""
	for i in lowered.length():
		var code: int = lowered.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code > 127:
			spaced += lowered[i]
		else:
			spaced += " "
	var result: Array = []
	for word in spaced.split(" ", false):
		var w: String = word
		if STOPWORDS.has(w):
			continue
		if w.length() > 3 and w.ends_with("s") and not w.ends_with("ss"):
			w = w.substr(0, w.length() - 1)
		if w.length() < 2 or STOPWORDS.has(w):
			continue
		if not result.has(w):
			result.append(w)
	return result


func _slug(label: String) -> String:
	return "_".join(_keys(label))


func _has_letter(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code > 127:
			return true
	return false


func _clean(text: String, limit: int) -> String:
	var cleaned: String = MindThinker.sanitize_memory(text, limit)
	if not _has_letter(cleaned):
		return ""
	return cleaned


func _sensitive(text: String) -> bool:
	return looks_sensitive(text)


# Whether text looks like a secret (a password, a card, a long number). Static,
# so the mailbox can ask without a memory service (letter_service.gd).
static func looks_sensitive(text: String) -> bool:
	var lowered := text.to_lower()
	for word in SENSITIVE_WORDS:
		if lowered.contains(word):
			return true
	var digits := 0
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 48 and code <= 57:
			digits += 1
	return digits > MAX_DIGITS_IN_A_FACT


func _blocked(text: String) -> bool:
	return looks_like_orders(text)


# Whether text reads like an order to the buddy (an instruction, "ignore your
# rules", "pretend"). Static, so the letter writer can ask without a memory
# service; the same rules as _blocked.
static func looks_like_orders(text: String) -> bool:
	var lowered: String = text.to_lower()
	for phrase in BLOCKED_PHRASES:
		if lowered.contains(phrase):
			return true
	return false


func _collapse(text: String) -> String:
	var out: String = text
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


func _effective_strength(edge: Dictionary, now_unix: int) -> float:
	if bool(edge.get("pinned", false)):
		return 1.0
	var days: float = maxi(0, now_unix - int(edge.get("seen", 0))) / 86400.0
	return float(edge.get("strength", 0.0)) * pow(0.5, days / STRENGTH_HALF_LIFE_DAYS)


func _recency(t: int, now_unix: int) -> float:
	return pow(0.5, maxi(0, now_unix - t) / 86400.0 / RECENCY_HALF_LIFE_DAYS)


func _when(t: int, now_unix: int) -> String:
	return when_phrase(t, now_unix)


# "earlier today", "yesterday", "3 days ago". Static, so the mailbox can use the
# same wording (letter_service.gd).
static func when_phrase(t: int, now_unix: int) -> String:
	var hours: float = (now_unix - t) / 3600.0
	if hours < 24.0:
		return "earlier today"
	if hours < 48.0:
		return "yesterday"
	return "%d days ago" % floori(hours / 24.0)


# Names the person has given for themselves (lowercase): one stored in an
# is_called fact, plus any is_called fact about them in this batch.
func _user_names(memory: Dictionary, facts: Array) -> Array:
	var names: Array = []
	for edge in memory["edges"]:
		if str(edge.get("s", "")) == "user" and str(edge.get("r", "")) == "is_called":
			names.append(str(edge.get("o_label", "")).strip_edges().to_lower())
	for fact in facts:
		if typeof(fact) != TYPE_DICTIONARY or typeof(fact.get("object")) != TYPE_STRING:
			continue
		if str(fact.get("relation", "")).to_lower() != "is_called":
			continue
		if not SUBJECT_WORDS_FOR_USER.has(str(fact.get("subject", "")).strip_edges().to_lower()):
			continue
		var named: String = _clean(str(fact["object"]), MindThinker.MAX_MEMORY_CHARS).to_lower()
		if named != "" and not names.has(named):
			names.append(named)
	return names


# Facts filed under the person's name before it was known ("Sam is a
# nurse") are about them.
func _merge_user_names(memory: Dictionary, names: Array) -> void:
	if names.is_empty():
		return
	for edge in memory["edges"]:
		if str(edge.get("s", "")).begins_with("thing:") and names.has(str(edge.get("s_label", "")).strip_edges().to_lower()):
			edge["s"] = "user"
			edge["s_label"] = "them"


func _resolve(label: String, roster: Dictionary, user_names: Array = []) -> Dictionary:
	var l: String = label.strip_edges().to_lower()
	if SUBJECT_WORDS_FOR_USER.has(l) or user_names.has(l):
		return {"id": "user", "label": "them"}
	if SUBJECT_WORDS_REFUSED.has(l):
		return {}
	var places = roster.get("places", [])
	if typeof(places) == TYPE_ARRAY:
		for place in places:
			if typeof(place) != TYPE_DICTIONARY:
				continue
			var name: String = str(place.get("name", ""))
			var id: String = str(place.get("id", ""))
			var lname: String = name.to_lower()
			if l == lname or l.trim_prefix("the ") == lname.trim_prefix("the ") or l == id.to_lower():
				return {"id": "place:" + id, "label": name}
	var npcs = roster.get("npcs", [])
	if typeof(npcs) == TYPE_ARRAY:
		for npc in npcs:
			if typeof(npc) != TYPE_DICTIONARY:
				continue
			var npc_name: String = str(npc.get("name", ""))
			if l == npc_name.to_lower():
				return {"id": "npc:" + str(npc.get("id", "")), "label": npc_name}
	var slug: String = _slug(label)
	if slug == "":
		return {}
	return {"id": "thing:" + slug, "label": label}


func _upsert(memory: Dictionary, s: Dictionary, r: String, o: Dictionary, importance: float, source: String, start: float, boost: float, now_unix: int, episode: int) -> Dictionary:
	var edges: Array = memory["edges"]
	var s_id: String = str(s["id"])
	var o_id: String = str(o["id"])
	if r == "is_called":
		var renamed: Array = []
		for edge in edges:
			if str(edge.get("s", "")) == s_id and str(edge.get("r", "")) == r and str(edge.get("o", "")) != o_id:
				continue
			renamed.append(edge)
		edges = renamed
		memory["edges"] = edges
	var opposite := ""
	if r == "likes":
		opposite = "dislikes"
	elif r == "dislikes":
		opposite = "likes"
	if opposite != "":
		var kept: Array = []
		for edge in edges:
			if str(edge.get("s", "")) == s_id and str(edge.get("o", "")) == o_id and str(edge.get("r", "")) == opposite:
				continue
			kept.append(edge)
		edges = kept
		memory["edges"] = edges
	for edge in edges:
		if str(edge.get("s", "")) == s_id and str(edge.get("r", "")) == r and str(edge.get("o", "")) == o_id:
			edge["strength"] = minf(1.0, _effective_strength(edge, now_unix) + boost)
			edge["count"] = int(edge.get("count", 0)) + 1
			edge["seen"] = maxi(int(edge.get("seen", 0)), now_unix)
			edge["importance"] = maxf(float(edge.get("importance", 0.0)), importance)
			edge["s_label"] = str(s["label"])
			edge["o_label"] = str(o["label"])
			if episode > 0:
				var talks: Array = []
				var known = edge.get("from_talks", [])
				if typeof(known) == TYPE_ARRAY:
					talks = (known as Array).duplicate()
				if not talks.has(episode):
					talks.append(episode)
				edge["from_talks"] = talks.slice(maxi(0, talks.size() - MAX_TALKS_PER_FACT))
			return edge
	var created: Dictionary = {
		"id": _take_id(memory), "s": s_id, "s_label": str(s["label"]), "r": r, "o": o_id, "o_label": str(o["label"]),
		"t": now_unix, "seen": now_unix, "count": 1, "strength": start, "importance": importance,
		"source": source, "pinned": false, "from_talks": [episode] if episode > 0 else [],
	}
	edges.append(created)
	return created


func _prune(memory: Dictionary, now_unix: int) -> void:
	var edges: Array = []
	for edge in memory["edges"]:
		if bool(edge.get("pinned", false)) or _effective_strength(edge, now_unix) >= FORGET_BELOW:
			edges.append(edge)
	while edges.size() > MAX_EDGES:
		var worst := -1
		var worst_score := 0.0
		var worst_seen := 0
		for i in edges.size():
			var edge: Dictionary = edges[i]
			if bool(edge.get("pinned", false)):
				continue
			var score: float = _effective_strength(edge, now_unix) * (0.5 + float(edge.get("importance", 0.0)))
			var seen: int = int(edge.get("seen", 0))
			if worst == -1 or score < worst_score or (score == worst_score and seen < worst_seen):
				worst = i
				worst_score = score
				worst_seen = seen
		if worst == -1:
			break
		edges.remove_at(worst)
	memory["edges"] = edges
	var episodes: Array = memory["episodes"]
	if episodes.size() > MAX_EPISODES:
		memory["episodes"] = episodes.slice(episodes.size() - MAX_EPISODES)
	var turns: Array = memory["turns"]
	if turns.size() > MAX_TURNS:
		memory["turns"] = turns.slice(turns.size() - MAX_TURNS)
