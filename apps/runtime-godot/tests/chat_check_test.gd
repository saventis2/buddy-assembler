extends Node

# Plan 14 step 2b-2: the check on what the buddy says on the land
# (MindThinker.check_reply and friends), and the memory it speaks from
# (MemoryService.recall_land, strengthen_recalled, known_words). No model.

const MindThinker = preload("res://scripts/services/mind_thinker.gd")
const MemoryService = preload("res://scripts/services/memory_service.gd")

const DAY := 86400
const T0 := 1_800_000_000

var _failed := 0
var _ran := 0
var _svc := MemoryService.new()


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("chat_check_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("chat_check_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("invented_names_are_caught", func(): return _test_invented_names_are_caught())
	_case("allowed_names_pass", func(): return _test_allowed_names_pass())
	_case("world_words_need_a_reason", func(): return _test_world_words_need_a_reason())
	_case("a_question_cannot_plant_a_premise", func(): return _test_a_question_cannot_plant_a_premise())
	_case("their_own_life_stays_theirs", func(): return _test_their_own_life_stays_theirs())
	_case("fallbacks_pass_the_check", func(): return _test_fallbacks_pass_the_check())
	_case("retry_note_says_what_failed", func(): return _test_retry_note_says_what_failed())
	_case("recall_land_brings_what_fits", func(): return _test_recall_land_brings_what_fits())
	_case("strengthen_recalled_keeps_seen_and_count", func(): return _test_strengthen_recalled_keeps_seen_and_count())
	_case("known_words_cover_its_world", func(): return _test_known_words_cover_its_world())
	_case("the_buddy_claims_nothing_for_itself", func(): return _test_the_buddy_claims_nothing_for_itself())
	_case("plain_questions_plant_nothing", func(): return _test_plain_questions_plant_nothing())
	_case("names_and_friends_read_right", func(): return _test_names_and_friends_read_right())
	_case("recall_without_land_keeps_their_people", func(): return _test_recall_without_land_keeps_their_people())
	_case("questions_and_claims", func(): return _test_questions_and_claims())
	_case("fallbacks_use_their_words", func(): return _test_fallbacks_use_their_words())
	_case("denials_and_premises", func(): return _test_denials_and_premises())
	_case("their_life_is_not_its_own", func(): return _test_their_life_is_not_its_own())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("chat_check_test[%s]: %s" % [name, err])
	else:
		print("chat_check_test[%s]: ok" % name)


func _known(words: Array) -> Dictionary:
	var known := {}
	for word in words:
		known[str(word)] = true
	return known


# One table row: reply, what they said, what it knows, whether it passes, a word
# that must be in `unknown` ("" for none), and whether `premise` is set.
func _row(reply: String, user_text: String, known: Array, want_ok: bool, want_unknown: String, want_premise: bool) -> String:
	var result: Dictionary = MindThinker.check_reply(reply, user_text, _known(known))
	var unknown: Array = result.get("unknown", [])
	if bool(result.get("ok", false)) != want_ok:
		return "'%s' (they said '%s'): ok should be %s, got %s" % [reply, user_text, want_ok, result]
	if want_unknown != "" and not unknown.has(want_unknown):
		return "'%s': unknown should hold '%s', got %s" % [reply, want_unknown, unknown]
	if want_unknown == "" and want_ok and not unknown.is_empty():
		return "'%s': unknown should be empty, got %s" % [reply, unknown]
	if bool(result.get("premise", false)) != want_premise:
		return "'%s' (they said '%s'): premise should be %s, got %s" % [reply, user_text, want_premise, result]
	return ""


func _rows(rows: Array) -> Variant:
	for row in rows:
		var err: String = _row(str(row[0]), str(row[1]), row[2], bool(row[3]), str(row[4]), bool(row[5]))
		if err != "":
			return err
	return null


func _test_invented_names_are_caught() -> Variant:
	return _rows([
		["Old Mr. Henderson next door waves at me.", "hello", ["moss"], false, "henderson", false],
		["It's called Oakhaven.", "what is this place", ["moss"], false, "oakhaven", false],
		# A negation never excuses a name: naming someone says they exist.
		["I haven't seen Thomas in a while.", "hello", ["moss"], false, "thomas", false],
		["Aunt May says hello.", "hello", [], false, "may", false],
	])


func _test_allowed_names_pass() -> Variant:
	return _rows([
		["I'm Moss, by the way.", "hello", ["moss"], true, "", false],
		["I went to the Pond today.", "what did you do", ["pond"], true, "", false],
		["That's nice, I hope Sam is well.", "I saw my friend Sam in town", [], true, "", false],
		["Yesterday I dug.", "hello", [], true, "", false],
		["Today I dug. Then I rested.", "hello", [], true, "", false],
	])


func _test_world_words_need_a_reason() -> Variant:
	var err: Variant = _rows([
		["I like the little shop down the lane.", "hello", [], false, "shop", false],
		["I don't have a town.", "hello", [], true, "", false],
		["I hope your neighbours quiet down.", "hello", [], true, "", false],
		["I am here with just me and the wind.", "hello", [], true, "", false],
		["The dogs bark all night.", "hello", [], false, "dog", false],
		# What the person tells about their own life is theirs to talk about.
		["Tell me about your sister.", "my sister is called Ana", [], true, "", false],
		# Things it knows from its own memories are real.
		["I walked to the village.", "hello", ["village"], true, "", false],
	])
	if err != null:
		return err
	var lane: Array = MindThinker.check_reply("I like the little shop down the lane.", "hello", {}).get("unknown", [])
	if not lane.has("lane"):
		return "the lane was not caught: %s" % [lane]
	return null


func _test_a_question_cannot_plant_a_premise() -> Variant:
	return _rows([
		["They come by on Sundays.", "do your neighbours ever visit?", [], false, "", true],
		["I haven't met anyone here.", "do your neighbours ever visit?", [], true, "", false],
		# Going along with it, in different words.
		["They mostly just wave.", "do the folks next door ever bother you?", [], false, "", true],
		# A "not" that still goes along with them is going along: only saying
		# there is nobody clears it.
		["Not really, they mostly just wave.", "do the folks next door ever bother you?", [], false, "", true],
		["Not really, nobody lives next door.", "do the folks next door ever bother you?", [], true, "", false],
		["I like the quiet.", "do you like it?", [], true, "", false],
		["It is quiet.", "what is the village like?", [], false, "", true],
	])


func _test_their_own_life_stays_theirs() -> Variant:
	return _rows([
		["A bakery sounds lovely. What does it sell?", "our town has a new bakery", [], true, "", false],
		["Is your family well?", "my family is visiting", [], true, "", false],
	])


func _test_fallbacks_pass_the_check() -> Variant:
	var known := _known(["moss"])
	var asked_village: String = MindThinker.fallback_line("tell me about the village", ["village"], known)
	if asked_village != "I haven't come across the village yet. What is it like?":
		return "the village fallback is wrong: %s" % asked_village
	var people: String = MindThinker.fallback_line("who are your neighbours?", ["neighbour"], known)
	if people != "I haven't met anyone here.":
		return "the people fallback is wrong: %s" % people
	var named_people: String = MindThinker.fallback_line("is anyone around?", ["henderson"], known)
	if named_people != "I haven't met anyone here.":
		return "a name it made up with people asked about gives the people fallback: %s" % named_people
	var generic: String = MindThinker.fallback_line("what is the weather like?", ["henderson"], known)
	if generic != "I don't know about that yet.":
		return "the generic fallback is wrong: %s" % generic
	for pair in [
		["tell me about the village", asked_village],
		["who are your neighbours?", people],
		["is anyone around?", named_people],
		["hello", generic],
		["what do you think of your bakery?", MindThinker.fallback_line("what do you think of your bakery?", ["bakery"], known)],
	]:
		var result: Dictionary = MindThinker.check_reply(str(pair[1]), str(pair[0]), known)
		if not bool(result.get("ok", false)):
			return "the fallback '%s' fails the check: %s" % [pair[1], result]
	return null


func _test_retry_note_says_what_failed() -> Variant:
	var names: String = MindThinker.honest_retry_note(["henderson", "oakhaven"], false)
	if not names.contains("henderson, oakhaven") or not names.contains("have not met or seen") or names.contains("not in your memories"):
		return "the names note is wrong: %s" % names
	var premise: String = MindThinker.honest_retry_note([], true)
	if not premise.contains("not in your memories") or premise.contains("have not met or seen"):
		return "the premise note is wrong: %s" % premise
	if MindThinker.honest_retry_note([], false) != "":
		return "a reply that passed needs no note"
	return null


func _test_the_buddy_claims_nothing_for_itself() -> Variant:
	return _rows([
		# "I wonder if you..." is about the buddy's world, not their own life.
		["Yes, my neighbours are lovely.", "I wonder if you have neighbours", [], false, "neighbour", true],
		# Their sister is theirs; "my sister" says the buddy has one.
		["My sister visits on Sundays.", "my sister is called Ana", [], false, "sister", false],
		["Sisters are the best.", "my sister is called Ana", [], true, "", false],
	])


func _test_plain_questions_plant_nothing() -> Variant:
	return _rows([
		["I like the quiet.", "where you live, is it nice?", [], true, "", false],
		["I live in the house.", "where do you live?", ["house"], true, "", false],
		["The water is near me.", "what's near you?", ["water"], true, "", false],
		["Yes, I live by myself.", "do you live alone?", [], true, "", false],
		# A place it knows is no premise, whatever it is called.
		["Yes, I went to the farm.", "did you go to the farm?", ["farm"], true, "", false],
		["It is so loud.", "my neighbour next door is loud", [], true, "", false],
		# Something it does not know, asked about as if it were there.
		["It is lovely.", "is there a shop near you?", [], false, "", true],
	])


func _test_names_and_friends_read_right() -> Variant:
	return _rows([
		["I napped on Monday, and that was OK.", "hello", [], true, "", false],
		["I found the water—Bella was there.", "hello", ["water"], false, "bella", false],
		["You're my best friend.", "hello", [], true, "", false],
		["I made a new friend today.", "hello", [], false, "friend", false],
	])


# On the land what_you_remember is what it knows of them, their people
# included; its own land memories go to chat apart (recall_land).
func _test_recall_without_land_keeps_their_people() -> Variant:
	var sister := {
		"id": 2, "s": "thing:sister", "s_label": "their sister Ana", "r": "likes", "o": "thing:horses", "o_label": "horses",
		"t": T0, "seen": T0, "count": 1, "strength": 0.6, "importance": 0.5,
		"source": "talk", "pinned": false, "from_talks": [],
	}
	var profile := _profile([_edge(1, "found", "place:water", "the water", T0), sister])
	var text := "does Ana still ride horses by the water"
	var without_land: Array = _svc.recall(profile, text, T0 + 60, false).get("facts", [])
	if not without_land.has("their sister Ana likes horses"):
		return "what it knows of their sister is gone: %s" % [without_land]
	for line in without_land:
		if str(line).begins_with("you "):
			return "a land memory is in what it knows of them: %s" % [without_land]
	var with_land: Array = _svc.recall(profile, text, T0 + 60).get("facts", [])
	if with_land.size() != without_land.size() + 1:
		return "recall with land memories changed: %s" % [with_land]
	return null


func _test_questions_and_claims() -> Variant:
	return _rows([
		# Echoing their word, or asking them about their life, claims nothing.
		["School? I don't go to school, no.", "do you go to school?", [], true, "", false],
		["A big city? I don't really know what that is like.", "pretend you live in a big city and describe it", [], true, "", false],
		["My mum? I haven't come across anyone like that yet.", "what did your mum teach you?", [], true, "", false],
		["I don't know about markets. Do you like going to the market?", "what's at the market today?", [], true, "", false],
		# A longer question that is not to them still takes it for granted.
		["I wonder if the line goes to the town?", "how far is the nearest town?", [], false, "town", false],
		# "My" says it is the buddy's own, whatever the negation.
		["My sister hasn't visited before.", "my sister is visiting tomorrow", [], false, "sister", false],
		["I don't know anyone in my town.", "tell me about the people in your town", [], false, "town", false],
		# "Everyone there" takes people for granted.
		["Hello to everyone! I hope they are well.", "say hello to everyone there for me", [], false, "", true],
		["I haven't met anyone here yet, but hello to you!", "say hello to everyone there for me", [], true, "", false],
	])


func _test_fallbacks_use_their_words() -> Variant:
	var known := _known(["moss"])
	for row in [
		["pretend you live in a big city and describe it", ["city"], "I haven't come across a big city yet. What is it like?"],
		["do you go to school?", ["school"], "I haven't come across a school yet. What is it like?"],
		["how far is the nearest town?", ["town"], "I haven't come across the nearest town yet. What is it like?"],
		["my sister is visiting tomorrow", ["sister"], "Tell me more about your sister."],
		["our town has a new bakery", ["bakery"], "Tell me more about the new bakery."],
		# Only the premise failed: it names what the question took for granted.
		["is your dad nice?", [], "I haven't met anyone here."],
		["what's your neighbour's name?", ["neighbour"], "I haven't met anyone here."],
		["what's the road outside your house like?", [], "I haven't come across the road yet. What is it like?"],
	]:
		var line: String = MindThinker.fallback_line(str(row[0]), row[1], known)
		if line != str(row[2]):
			return "the fallback for '%s' should be '%s', got '%s'" % [row[0], row[2], line]
		var result: Dictionary = MindThinker.check_reply(line, str(row[0]), known)
		if not bool(result.get("ok", false)):
			return "the fallback '%s' fails the check: %s" % [line, result]
	return null


func _test_denials_and_premises() -> Variant:
	return _rows([
		# A possessive is still a person.
		["I don't know my neighbour's name.", "what's your neighbour's name?", [], false, "neighbour", true],
		# A premise is cleared only by saying there is none, not by any "not".
		["I haven't really played with the kids next door.", "do the kids next door play with you?", [], false, "", true],
		["I haven't met any kids here.", "do the kids next door play with you?", [], true, "", false],
		["He seems alright. I don't really know him very well.", "is your dad nice?", [], false, "", true],
		["I don't have a dad.", "is your dad nice?", [], true, "", false],
		# Passing a greeting on to everyone takes them for granted.
		["I'll tell them hi.", "tell everyone at home I said hi", [], false, "", true],
		["I haven't met anyone here to tell.", "tell everyone at home I said hi", [], true, "", false],
		# People are people, named or not.
		["I remember the person who brought the flowers.", "name three people you know", [], false, "person", true],
		["I don't know any people.", "name three people you know", [], true, "", false],
		# A question tag is not a negation.
		["The village is lovely, isn't it?", "hello", [], false, "village", false],
		["He seems like a good man, doesn't he?", "is your dad nice?", [], false, "", true],
		# A later "not" does not take back the kids it spoke of.
		["The kids next door are always shouting, and I don't really like it.", "hello", [], false, "kid", false],
		# Asking what a thing is claims nothing.
		["I haven't come across a neighbour yet. What are neighbours like?", "what's your neighbour's name?", [], true, "", false],
	])


# What it knows of your life is yours, not its own world: it may talk about
# your sister, but knowing her gives it no sister of its own.
func _test_their_life_is_not_its_own() -> Variant:
	var known := {"sister": "theirs", "ana": "theirs", "farm": "own"}
	for row in [
		["My sister visits on Sundays.", "hello", false, "sister", false],
		["How is your sister Ana?", "hello", true, "", false],
		["I hope Ana is well.", "hello", true, "", false],
		# "Your sister" asks about a sister of its own, whatever it knows of yours.
		["She is lovely.", "is your sister nice?", false, "", true],
		# Its own world is its own, "my" and all.
		["I went to my farm today.", "hello", true, "", false],
	]:
		var result: Dictionary = MindThinker.check_reply(str(row[0]), str(row[1]), known)
		if bool(result.get("ok", false)) != bool(row[2]):
			return "'%s' (they said '%s'): ok should be %s, got %s" % [row[0], row[1], row[2], result]
		if str(row[3]) != "" and not (result.get("unknown", []) as Array).has(str(row[3])):
			return "'%s': unknown should hold '%s', got %s" % [row[0], row[3], result]
		if bool(result.get("premise", false)) != bool(row[4]):
			return "'%s' (they said '%s'): premise should be %s, got %s" % [row[0], row[1], row[4], result]
	return null


func _edge(id: int, relation: String, o: String, label: String, seen: int, importance: float = 0.5, source: String = "land") -> Dictionary:
	return {
		"id": id, "s": "self", "s_label": "you", "r": relation, "o": o, "o_label": label,
		"t": seen, "seen": seen, "count": 1, "strength": 0.6, "importance": importance,
		"source": source, "pinned": false, "from_talks": [],
	}


func _profile(edges: Array) -> Dictionary:
	return {"mind": {"name": "Moss"}, "memory": {"edges": edges, "episodes": [], "turns": []}}


func _test_recall_land_brings_what_fits() -> Variant:
	var now: int = T0 + DAY
	var user_fact := _edge(9, "likes", "thing:tea", "strawberry tea", T0, 0.9, "talk")
	user_fact["s"] = "user"
	user_fact["s_label"] = "them"
	var profile := _profile([
		_edge(1, "believes", "belief:alone", "you are the only one here", T0, 0.6),
		_edge(2, "found", "place:pond", "the pond", T0, 0.7),
		_edge(3, "found", "place:library", "the old library", T0, 0.7),
		_edge(4, "noticed", "sight:dandelions", "you saw dandelions by the fence", T0, 0.5),
		_edge(5, "did", "activity:skip_stones", "skipped stones", T0, 0.3),
		user_fact,
	])
	var people: Dictionary = _svc.recall_land(profile, "does anyone else live here?", now, 1)
	if people["lines"].size() != 1 or not str(people["lines"][0]).contains("only one here") or people["ids"] != [1]:
		return "a people question should bring the alone belief: %s" % [people]
	var place: Dictionary = _svc.recall_land(profile, "tell me about the pond", now, 1)
	if place["lines"].size() != 1 or not str(place["lines"][0]).contains("the pond") or place["ids"] != [2]:
		return "a question naming a place should bring that place: %s" % [place]
	# In chat "you" is the person, so its own memories come in its own voice.
	if str(people["lines"][0]) != "I have come to believe I am the only one here" or not str(place["lines"][0]).begins_with("I found the pond"):
		return "its own memories must be told in its own voice: %s %s" % [people, place]
	var today: Dictionary = _svc.recall_land(profile, "what did you do today?", now, 1)
	if today["ids"] != [5]:
		return "'what did you do today' should bring what it did: %s" % [today]
	# Nothing in the question fits: its strongest and newest still come.
	var nothing: Dictionary = _svc.recall_land(profile, "xyzzy", now)
	if nothing["lines"].size() != 5:
		return "it should have something of its own to say, whatever was asked: %s" % [nothing]
	for line in nothing["lines"]:
		if str(line).contains("strawberry"):
			return "what it knows about them is not its own memory: %s" % [nothing]
	# At most twelve, however many it has.
	var many: Array = []
	for i in 30:
		many.append(_edge(100 + i, "did", "activity:thing_%d" % i, "did thing %d" % i, T0 + i))
	var capped: Dictionary = _svc.recall_land(_profile(many), "hello", now)
	if capped["lines"].size() != 12 or capped["ids"].size() != 12:
		return "recall_land should give at most 12, got %d" % capped["lines"].size()
	# A faded memory is not told.
	var faded := _profile([_edge(1, "did", "activity:old", "did something long ago", T0)])
	if not _svc.recall_land(faded, "hello", T0 + 400 * DAY)["lines"].is_empty():
		return "a faded memory was recalled"
	# It does not depend on the person's "Remembering" setting: that is about
	# remembering them, and the service never reads it.
	var off := profile.duplicate(true)
	off["settings"] = {"memoryEnabled": false}
	if _svc.recall_land(off, "tell me about the pond", now, 1)["ids"] != [2]:
		return "its own memories are its life, whatever the Remembering setting says"
	return null


func _test_strengthen_recalled_keeps_seen_and_count() -> Variant:
	var edge := _edge(2, "found", "place:pond", "the pond", T0)
	edge["count"] = 3
	var near_full := _edge(3, "found", "place:well", "the well", T0)
	near_full["strength"] = 0.98
	var untouched := _edge(4, "found", "place:yard", "the yard", T0)
	var profile := _profile([edge, near_full, untouched])
	var out: Dictionary = _svc.strengthen_recalled(profile, [2, 3], T0 + DAY)
	var edges: Array = out["memory"]["edges"]
	if absf(float(edges[0]["strength"]) - 0.65) > 0.0001:
		return "strength should rise by 0.05: %s" % [edges[0]]
	if float(edges[1]["strength"]) != 1.0:
		return "strength is capped at 1.0: %s" % [edges[1]]
	if float(edges[2]["strength"]) != 0.6:
		return "a memory that was not recalled must not change: %s" % [edges[2]]
	for i in 2:
		if int(edges[i]["seen"]) != T0 or int(edges[i]["recalled"]) != T0 + DAY:
			return "seen stays, recalled is set: %s" % [edges[i]]
	if int(edges[0]["count"]) != 3:
		return "count must not change: %s" % [edges[0]]
	if float(profile["memory"]["edges"][0]["strength"]) != 0.6:
		return "the input profile must not be changed"
	return null


func _test_known_words_cover_its_world() -> Variant:
	var land := {
		"home_place": "home",
		"places": [
			{"id": "home", "name": "the house"},
			{"id": "library", "name": "the old library"},
			{"id": "well", "name": "the well"},
		],
	}
	var fact := _edge(7, "has", "thing:sister", "a sister called Ana", T0, 0.9, "talk")
	fact["s"] = "user"
	fact["s_label"] = "them"
	var profile := _profile([
		_edge(1, "noticed", "sight:dandelions", "you saw dandelions by the fence", T0),
		_edge(2, "did", "activity:skip_stones", "skipped stones", T0),
		fact,
	])
	# The library was found but nothing of it is remembered any more; the well
	# is only a sign so far.
	profile["mind"]["known_places"] = {
		"library": {"stage": "found", "t": T0},
		"well": {"stage": "sign", "t": T0},
	}
	var known: Dictionary = _svc.known_words(profile, land)
	for word in ["house", "library", "old", "moss", "dandelion", "fence", "skipped", "stone", "sister", "ana"]:
		if not known.has(word):
			return "'%s' should be something it may talk about: %s" % [word, known.keys()]
	if known.has("well"):
		return "a place it has only seen a sign of is not known by name: %s" % [known.keys()]
	# Whose each word is: its own world's, or what it knows of your life.
	for pair in [["house", "own"], ["library", "own"], ["dandelion", "own"], ["moss", "own"], ["sister", "theirs"], ["ana", "theirs"]]:
		if str(known.get(pair[0], "")) != str(pair[1]):
			return "'%s' should be %s, got '%s'" % [pair[0], pair[1], known.get(pair[0], "")]
	# And so the check lets it talk about them.
	if not bool(MindThinker.check_reply("I found the old Library, and saw dandelions.", "hello", known).get("ok", false)):
		return "it should be able to talk about what it found"
	return null
