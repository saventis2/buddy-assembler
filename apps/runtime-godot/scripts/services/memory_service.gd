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
const USER_FACT_BONUS := 0.25
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
const MAX_TALKS_PER_FACT := 10
const VERB_PLURAL := {"likes": "like", "dislikes": "dislike", "is": "are", "has": "have", "does": "", "wants": "want", "lives_in": "live in", "is_called": "are called"}
const VERB_SINGULAR := {"likes": "likes", "dislikes": "dislikes", "is": "is", "has": "has", "does": "", "wants": "wants", "lives_in": "lives in", "is_called": "is called"}


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


# --- Forgetting --------------------------------------------------------------

func forget(profile: Dictionary, id: int) -> Dictionary:
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
	return {"profile": out, "ok": found}


func forget_all(profile: Dictionary) -> Dictionary:
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
	return out


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


func recall(profile: Dictionary, text: String, now_unix: int) -> Dictionary:
	var memory: Dictionary = _read(profile)
	var words: Array = _keys(text)

	var scored: Array = []
	for edge in memory["edges"]:
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
		if str(edge.get("source", "")) == "town" and relevant <= 0.0:
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
