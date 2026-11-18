extends Node

# Plan 14 step 2c-1: letters arrive and are read at the glowing box. The mailbox
# (LetterService), how the buddy works out the box and reads (MindService on a
# small land), delivery from the desktop through the host's inbox (AppState and
# WorldHost.take_letters), and what memory keeps of it. No model. Everything this
# test writes goes under ROOT, and the AppState cases run in simulation, so
# nothing is saved.

const LetterService = preload("res://scripts/services/letter_service.gd")
const MindService = preload("res://scripts/services/mind_service.gd")
const MemoryService = preload("res://scripts/services/memory_service.gd")
const Whereabouts = preload("res://scripts/persistence/buddy_whereabouts.gd")
const WorldHost = preload("res://scripts/world_host.gd")
const LifeSim = preload("res://tests/life_sim.gd")

const ROOT := "user://letter_test"
const HOUR := 3600
const DAY := 86400

var _failed := 0
var _ran := 0
var _simulating := false


func _ready() -> void:
	_run_all()
	_wipe(ROOT)
	if _failed == 0:
		print("letter_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("letter_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_wipe(ROOT)
	_case("mailbox_basics", func(): return _test_mailbox_basics())
	_case("the_cap_keeps_waiting_letters", func(): return _test_the_cap())
	_case("waiting_letters_are_limited", func(): return _test_waiting_is_limited())
	_case("refusals", func(): return _test_refusals())
	_case("learning_the_box", func(): return _test_learning())
	_case("letters_wait_until_known", func(): return _test_letters_wait())
	_case("the_pull", func(): return _test_the_pull())
	_case("asleep_it_reads_after_waking", func(): return _test_asleep())
	_case("blinking", func(): return _test_blinking())
	_case("a_blinking_go_can_teach_it", func(): return _test_blink_go_teaches())
	_case("delivery_states", func(): return _test_delivery_states())
	_case("the_host_takes_letters", func(): return _test_host())
	_case("memory_keeps_it", func(): return _test_memory())
	# Last: these put the process into simulation.
	_case("the_town_is_unchanged", func(): return _test_town_unchanged())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("letter_test[%s]: %s" % [name, err])
	else:
		print("letter_test[%s]: ok" % name)


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		if FileAccess.file_exists(dir):
			DirAccess.remove_absolute(dir)
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir + "/" + sub)
	for file_name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + file_name)
	DirAccess.remove_absolute(dir)


# --- helpers -------------------------------------------------------------

func _service() -> MindService:
	var svc := MindService.new()
	svc.set_time_zone_bias_minutes(0)
	return svc


# A small land: the house (with the glowing box, which can be limited to some
# hours) and a pool a short way off.
func _land(box_hours: Variant = null) -> Dictionary:
	var box := {"id": "glowing_box", "label": "looked at the glowing box", "satisfies": "curiosity", "minutes": 20, "lines": ["I looked at the glowing box."]}
	if box_hours != null:
		box["hours"] = box_hours
	return {
		"home_place": "home",
		"paths": [["home", "pool"]],
		"tails": {"good": ["Good."], "bad": ["Bad."]},
		"places": [
			{"id": "home", "name": "the house", "opens": 0, "closes": 24, "distance": 0, "residents": [],
				"activities": [
					{"id": "sleep", "label": "went to bed", "satisfies": "energy", "until_hour": 6, "hours": [19, 5], "lines": ["I slept."]},
					{"id": "nap", "label": "had a nap", "satisfies": "energy", "minutes": 40, "hours": [5, 19], "lines": ["I napped."]},
					{"id": "tidy", "label": "tidied up", "satisfies": "comfort", "lines": ["I tidied."]},
					{"id": "think", "label": "sat and thought", "satisfies": "reflection", "lines": ["I thought."]},
					box,
				],
				"sights": []},
			{"id": "pool", "name": "the pool", "opens": 0, "closes": 24, "distance": 2, "residents": [],
				"discover": {"from": ["home"], "sign": "I heard water.", "chance": 1.0, "blocked": ["Not yet."], "found": "I found the pool.", "wonder": ["I wonder about that water."]},
				"activities": [{"id": "paddle", "label": "paddled", "satisfies": "curiosity", "minutes": 30, "lines": ["I paddled."]}],
				"sights": []},
		],
	}


func _home_only_land() -> Dictionary:
	var land: Dictionary = _land()
	land["places"] = [(land["places"] as Array)[0]]
	land["paths"] = []
	return land


func _context_at(t: int) -> Dictionary:
	var hour: int = int(Time.get_datetime_dict_from_unix_time(t).get("hour", 0))
	return {"small_beginnings": true, "plans": true, "hour": hour, "is_night": hour < 7 or hour >= 22}


func _at(day: int, hour: int, minute: int = 0) -> int:
	return LifeSim.DEFAULT_START_UNIX + (day - 1) * DAY + hour * HOUR + minute * 60


# A buddy that has been on its land a while, rested, at home. `mind_extra` and
# `letters` (items) are put on it.
func _buddy(seed_value: int, mind_extra: Dictionary = {}, items: Array = []) -> Dictionary:
	var svc := _service()
	var profile: Dictionary = svc.ensure_profile({
		"personality_seed": seed_value,
		"personality_seed_tag": "curious",
		"mood_modifiers": {"energy_strain": 0.2, "social_fulfillment": 0.5, "comfort": 0.5, "confidence": 0.5},
	})
	var mind: Dictionary = profile["mind"]
	mind["born"] = "land"
	mind["decision_count"] = 5
	for key in mind_extra.keys():
		mind[key] = mind_extra[key]
	profile["mind"] = mind
	if not items.is_empty():
		profile["letters"] = {"items": items}
	return profile


func _letter(id: String, t: int, read_t: int = 0) -> Dictionary:
	return {"id": id, "from": "you", "text": "Hello " + id, "t": t, "read_t": read_t, "reply_due": read_t > 0, "reply_to": ""}


# One decision at time t. Returns {"profile", "event"} (event is {} if none was due).
func _decide_at(svc: MindService, profile: Dictionary, land: Dictionary, t: int) -> Dictionary:
	var current: Dictionary = profile.duplicate(true)
	(current["mind"] as Dictionary)["last_decision_unix"] = t - 600
	var result: Dictionary = svc.tick(current, [], t, _context_at(t), land)
	var events: Array = result["events"]
	return {"profile": result["profile"], "event": events[0] if not events.is_empty() else {}}


# Decisions from `start` on, one after another (each when the last is done), until
# `stop` returns true for an event. Returns {"profile", "event", "t", "events"}.
func _live_until(svc: MindService, profile: Dictionary, land: Dictionary, start: int, stop: Callable) -> Dictionary:
	var current: Dictionary = profile
	var t := start
	var events: Array = []
	for _loop in range(4000):
		var result: Dictionary = svc.tick(current, [], t, _context_at(t), land)
		current = result["profile"]
		for event_variant in result["events"]:
			events.append(event_variant)
			if bool(stop.call(event_variant)):
				return {"profile": current, "event": event_variant, "t": t, "events": events}
		var busy_until: int = int((current["mind"] as Dictionary).get("busy_until", 0))
		t = busy_until if busy_until > t else t + 600
	return {"profile": current, "event": {}, "t": t, "events": events}


func _is_box(event: Variant) -> bool:
	return str((event as Dictionary).get("activity_id", "")) == "glowing_box"


func _letter_row(profile: Dictionary, id: String) -> Dictionary:
	for item in LetterService.ensure_letters(profile)["letters"]["items"]:
		if str((item as Dictionary)["id"]) == id:
			return item
	return {}


# --- 1: the mailbox --------------------------------------------------------

func _test_mailbox_basics() -> Variant:
	var empty := {}
	if LetterService.has_unread(empty) or not LetterService.unread_from_you(empty).is_empty():
		return "an empty profile should have nothing unread"
	var added: Dictionary = LetterService.add_from_you(empty, "100-aaaaaaaa", "  Hello   there \nHow are you?  ", 100)
	if not bool(added["ok"]) or str(added["id"]) != "100-aaaaaaaa":
		return "a good letter should be added under its id: %s" % str(added)
	var profile: Dictionary = added["profile"]
	var row: Dictionary = _letter_row(profile, "100-aaaaaaaa")
	if str(row.get("text", "")) != "Hello there \nHow are you?":
		return "ends stripped, line breaks kept, spaces collapsed; got %s" % JSON.stringify(row.get("text", ""))
	if str(row["from"]) != "you" or int(row["t"]) != 100 or int(row["read_t"]) != 0 or bool(row["reply_due"]) or str(row["reply_to"]) != "":
		return "a new letter is yours, unread, with no reply due: %s" % str(row)
	if not LetterService.has_unread(profile) or LetterService.unread_from_you(profile).size() != 1:
		return "the new letter should be waiting"
	# Asking twice changes nothing.
	var again: Dictionary = LetterService.add_from_you(profile, "100-aaaaaaaa", "A different text", 200)
	if not bool(again["ok"]) or LetterService.ensure_letters(again["profile"])["letters"]["items"].size() != 1:
		return "a duplicate id should be ok and add nothing"
	if str(_letter_row(again["profile"], "100-aaaaaaaa")["text"]) != "Hello there \nHow are you?":
		return "a duplicate id should not change the letter"
	var second: Dictionary = LetterService.add_from_you(profile, "101-bbbbbbbb", "Second", 101)
	profile = second["profile"]
	var unread: Array = LetterService.unread_from_you(profile)
	if unread.size() != 2 or str((unread[0] as Dictionary)["id"]) != "100-aaaaaaaa":
		return "unread should be oldest first: %s" % str(unread)
	# Reading sets the time and the reply that is now due, once.
	var read: Dictionary = LetterService.mark_read(profile, ["100-aaaaaaaa"], 500)
	var read_row: Dictionary = _letter_row(read, "100-aaaaaaaa")
	if int(read_row["read_t"]) != 500 or not bool(read_row["reply_due"]):
		return "mark_read should set read_t and reply_due: %s" % str(read_row)
	if LetterService.unread_from_you(read).size() != 1:
		return "one letter should still be waiting"
	var read_again: Dictionary = LetterService.mark_read(read, ["100-aaaaaaaa"], 900)
	if int(_letter_row(read_again, "100-aaaaaaaa")["read_t"]) != 500:
		return "a letter already read keeps its first read time"
	# Malformed entries are dropped.
	var messy := {"letters": {"items": [5, {"id": ""}, {"id": "x", "from": "nobody", "text": "t", "t": 1}, {"id": "y", "from": "you", "text": "", "t": 1}, _letter("good", 7)]}}
	var cleaned: Array = LetterService.ensure_letters(messy)["letters"]["items"]
	if cleaned.size() != 1 or str((cleaned[0] as Dictionary)["id"]) != "good":
		return "ensure_letters should keep only well-formed letters: %s" % str(cleaned)
	var made: String = LetterService.new_id(1234)
	var shape := RegEx.new()
	shape.compile("^1234-[0-9a-f]{8}$")
	if shape.search(made) == null:
		return "new_id should look like an inbox request id: %s" % made
	return null


func _test_the_cap() -> Variant:
	var items: Array = []
	for i in range(5):
		items.append(_letter("w%d" % i, 1 + i))
	for i in range(5):
		items.append(_letter("r%d" % i, 6 + i, 50))
	for i in range(55):
		items.append({"id": "b%d" % i, "from": "buddy", "text": "Letter %d" % i, "t": 11 + i, "read_t": 0, "reply_due": false, "reply_to": ""})
	var profile := {"letters": {"items": items}}
	var added: Dictionary = LetterService.add_from_you(profile, "new-1", "One more", 1000)
	var kept: Array = LetterService.ensure_letters(added["profile"])["letters"]["items"]
	if kept.size() != LetterService.MAX_LETTERS:
		return "the cap should hold %d letters, got %d" % [LetterService.MAX_LETTERS, kept.size()]
	for id in ["w0", "w1", "w2", "w3", "w4", "r0", "r1", "r2", "r3", "r4", "new-1"]:
		if _letter_row(added["profile"], id).is_empty():
			return "%s is waiting or due and must be kept" % id
	if not _letter_row(added["profile"], "b0").is_empty() or _letter_row(added["profile"], "b5").is_empty() == false:
		return "the oldest letters that are neither waiting nor due go first (b0..b5 dropped, b6 kept)"
	if _letter_row(added["profile"], "b6").is_empty():
		return "b6 should still be there"
	# Letters still waiting to be read are never dropped for the cap; with that
	# many waiting, a new one has to wait too.
	var waiting: Array = []
	for i in range(LetterService.MAX_LETTERS + 2):
		waiting.append(_letter("q%d" % i, i + 1))
	var full: Dictionary = LetterService.add_from_you({"letters": {"items": waiting}}, "q-last", "Last", 5000)
	if bool(full["ok"]) or str(full["reason"]) != "too_many_waiting":
		return "with that many waiting, a new letter waits too: %s" % str(full.get("reason", ""))
	if LetterService.ensure_letters(full["profile"])["letters"]["items"].size() != LetterService.MAX_LETTERS + 2:
		return "waiting letters are never dropped for the cap"
	# Answers that never came do not hold the mailbox open for ever: past the
	# cap, once nothing else can go, the oldest unanswered letter goes.
	var due: Array = []
	for i in range(LetterService.MAX_LETTERS):
		due.append(_letter("d%d" % i, i + 1, 100 + i))
	var trimmed: Dictionary = LetterService.add_from_you({"letters": {"items": due}}, "d-new", "Another", 9000)
	var due_kept: Array = LetterService.ensure_letters(trimmed["profile"])["letters"]["items"]
	if due_kept.size() != LetterService.MAX_LETTERS or not _letter_row(trimmed["profile"], "d0").is_empty() or _letter_row(trimmed["profile"], "d-new").is_empty():
		return "past the cap the oldest unanswered letter should go: %d kept" % due_kept.size()
	return null


# At most MAX_WAITING letters wait unread, on the buddy's side and on the
# desktop's (which also counts what it sent and has not seen arrive).
func _test_waiting_is_limited() -> Variant:
	var profile := {}
	for i in range(LetterService.MAX_WAITING):
		var added: Dictionary = LetterService.add_from_you(profile, "", "Letter %d" % i, 100 + i)
		if not bool(added["ok"]):
			return "letter %d should go: %s" % [i, str(added["reason"])]
		profile = added["profile"]
	var one_more: Dictionary = LetterService.add_from_you(profile, "", "One too many", 500)
	if bool(one_more["ok"]) or str(one_more["reason"]) != "too_many_waiting":
		return "letter %d should wait: %s" % [LetterService.MAX_WAITING + 1, str(one_more.get("reason", ""))]
	# Once it reads them there is room again.
	var ids: Array = []
	for row in LetterService.unread_from_you(profile):
		ids.append(str((row as Dictionary)["id"]))
	if not bool(LetterService.add_from_you(LetterService.mark_read(profile, ids, 600), "", "Now there is room", 700)["ok"]):
		return "once it has read them, a new letter goes"
	# The desktop holds back the same letter before writing it to the inbox.
	_sim()
	var saved_role: String = AppState._role
	var saved_holding: bool = AppState._holding
	var saved_dir: String = AppState._host_dir
	var base := "%s/waiting" % ROOT
	_wipe(base)
	AppState._host_dir = base
	AppState._role = "desktop"
	AppState._holding = false
	AppState._letters_outbox.clear()
	var now: int = AppState._now_unix()
	Whereabouts.write_status("%s/host.json" % base, {"pid": 1, "heartbeat": float(now)})
	var problem := ""
	for i in range(LetterService.MAX_WAITING):
		var sent: Dictionary = AppState.letters_send("Desktop letter %d" % i)
		if not bool(sent["ok"]):
			problem = "desktop letter %d should go: %s" % [i, str(sent)]
			break
	if problem == "":
		var too_many: Dictionary = AppState.letters_send("One too many")
		if bool(too_many["ok"]) or str(too_many["reason"]) != "too_many_waiting":
			problem = "the desktop should hold back letter %d: %s" % [LetterService.MAX_WAITING + 1, str(too_many)]
	AppState._role = saved_role
	AppState._holding = saved_holding
	AppState._host_dir = saved_dir
	AppState._letters_outbox.clear()
	_wipe(base)
	return problem if problem != "" else null


# --- 2: refusals -----------------------------------------------------------

func _sim() -> void:
	if _simulating:
		return
	_simulating = true
	AppState.begin_simulation(3, LifeSim.DEFAULT_START_UNIX)


func _test_refusals() -> Variant:
	var empty := {}
	var long_text: String = "a".repeat(LetterService.MAX_LETTER_CHARS + 1)
	var exact: String = "a".repeat(LetterService.MAX_LETTER_CHARS)
	var table := [
		["   \n  ", "empty"],
		[long_text, "too_long"],
		["my password is hunter2", "sensitive"],
		["call me on 021 555 1234", "sensitive"],
		[exact, ""],
		["Hello, how is your day?", ""],
	]
	for row in table:
		var result: Dictionary = LetterService.add_from_you(empty, "x-1", str(row[0]), 10)
		if str(result["reason"]) != str(row[1]) or bool(result["ok"]) != (str(row[1]) == ""):
			return "'%s...' should give reason '%s', got %s" % [str(row[0]).substr(0, 20), str(row[1]), str(result)]
		if str(row[1]) != "" and not LetterService.ensure_letters(result["profile"])["letters"]["items"].is_empty():
			return "a refused letter must not be stored"
	# The desktop refuses the same texts before anything is written to the inbox.
	_sim()
	var saved_role: String = AppState._role
	var saved_holding: bool = AppState._holding
	var saved_dir: String = AppState._host_dir
	var base := "%s/refusals" % ROOT
	_wipe(base)
	AppState._host_dir = base
	AppState._role = "desktop"
	AppState._holding = false
	var now: int = AppState._now_unix()
	Whereabouts.write_status("%s/host.json" % base, {"pid": 1, "heartbeat": float(now)})
	var problem := ""
	for row in table:
		var sent: Dictionary = AppState.letters_send(str(row[0]))
		if str(row[1]) != "" and (bool(sent["ok"]) or str(sent["reason"]) != str(row[1])):
			problem = "the desktop should refuse '%s...' (%s): %s" % [str(row[0]).substr(0, 20), str(row[1]), str(sent)]
	var inbox: PackedStringArray = DirAccess.get_files_at("%s/inbox" % base)
	# Only the two good texts may have been written.
	if problem == "" and inbox.size() != 2:
		problem = "only the two good letters belong in the inbox, found %d files" % inbox.size()
	# With no host running, nothing is sent.
	Whereabouts.write_status("%s/host.json" % base, {"pid": 1, "heartbeat": float(now - 1000)})
	var no_host: Dictionary = AppState.letters_send("Anybody there?")
	if problem == "" and (bool(no_host["ok"]) or str(no_host["reason"]) != "no_host"):
		problem = "with no host alive the desktop cannot send: %s" % str(no_host)
	AppState._role = saved_role
	AppState._holding = saved_holding
	AppState._host_dir = saved_dir
	AppState._letters_outbox.clear()
	_wipe(base)
	return problem if problem != "" else null


# --- 3: working out the box ------------------------------------------------

# Returns the buddy's first three trips to the glowing box on a land of just the
# house, plus a fourth: {"goes": [{"event", "profile"}...]}.
func _four_goes(seed_value: int) -> Dictionary:
	var svc := _service()
	var land: Dictionary = _home_only_land()
	var current: Dictionary = _buddy(seed_value, {"decision_count": 1})
	var t: int = _at(1, 8)
	var goes: Array = []
	for _n in range(4):
		var found: Dictionary = _live_until(svc, current, land, t, func(e): return _is_box(e))
		if (found["event"] as Dictionary).is_empty():
			return {"goes": goes}
		current = found["profile"]
		goes.append({"event": found["event"], "profile": current.duplicate(true)})
		# Mind the flag between goes: it is only set once.
		if goes.size() == 3:
			(current["mind"] as Dictionary)["first_letter_due"] = false
		t = int(found["t"]) + 600
	return {"goes": goes}


func _test_learning() -> Variant:
	var run: Dictionary = _four_goes(4)
	var goes: Array = run["goes"]
	if goes.size() != 4:
		return "expected four trips to the glowing box, got %d" % goes.size()
	for index in range(2):
		var e: Dictionary = goes[index]["event"]
		var mind: Dictionary = goes[index]["profile"]["mind"]
		if e.has("learned") or bool((mind.get("console", {}) as Dictionary).get("known", false)):
			return "go %d should not teach it" % (index + 1)
		if int((mind["console"] as Dictionary)["goes"]) != index + 1:
			return "go %d should be counted: %s" % [index + 1, str(mind["console"])]
		if str(e["text"]) == MindService.CONSOLE_LEARNED_LINE:
			return "go %d should not read as learning" % (index + 1)
	var third: Dictionary = goes[2]["event"]
	var third_mind: Dictionary = goes[2]["profile"]["mind"]
	var console: Dictionary = third_mind["console"]
	if str(third.get("learned", "")) != "console" or str(third["text"]) != MindService.CONSOLE_LEARNED_LINE:
		return "the third go works it out, with its line: %s" % str(third)
	if not bool(console["known"]) or int(console["known_t"]) != int(third["t"]) or int(console["goes"]) != 3:
		return "known and known_t should be set on the third go: %s" % str(console)
	if not bool(third_mind.get("first_letter_due", false)):
		return "first_letter_due should be set for step 2c-2"
	var fourth: Dictionary = goes[3]["event"]
	var fourth_mind: Dictionary = goes[3]["profile"]["mind"]
	if fourth.has("learned") or str(fourth["text"]).begins_with("I watched the glowing box for a long time"):
		return "a fourth go does not learn it again"
	if bool(fourth_mind.get("first_letter_due", false)) or int((fourth_mind["console"] as Dictionary)["known_t"]) != int(third["t"]):
		return "learning happens once: %s" % str(fourth_mind)
	return null


# --- 4: letters wait until the box is known --------------------------------

func _test_letters_wait() -> Variant:
	var svc := _service()
	var land: Dictionary = _land()
	var base: Dictionary = _buddy(2, {}, [_letter("L1", _at(1, 8))])
	var found: Dictionary = _live_until(svc, base, land, _at(1, 9), func(e): return _is_box(e))
	if (found["event"] as Dictionary).is_empty():
		return "it never went to the glowing box"
	var after: Dictionary = found["profile"]
	if (found["event"] as Dictionary).has("read_letters") or int(_letter_row(after, "L1")["read_t"]) != 0:
		return "before it knows the box, a go there leaves the letter unread: %s" % str(found["event"])
	if str((found["event"] as Dictionary)["text"]).contains("I read your letter"):
		return "the line must not say it read anything"
	# Once it knows the box, the next go reads.
	var mind: Dictionary = after["mind"]
	mind["console"] = {"goes": 3, "known": true, "known_t": int(found["t"])}
	after["mind"] = mind
	var next_t: int = maxi(int(mind.get("busy_until", 0)), int(found["t"]) + 600)
	var next: Dictionary = _decide_at(svc, after, land, next_t)
	var e: Dictionary = next["event"]
	if not _is_box(e) or int(_letter_row(next["profile"], "L1")["read_t"]) != next_t:
		return "once it knows the box, the next go reads the letter: %s" % str(e)
	return null


# --- 5: the pull -----------------------------------------------------------

func _test_the_pull() -> Variant:
	var svc := _service()
	var land: Dictionary = _land()
	var known := {"console": {"goes": 3, "known": true, "known_t": 5}}
	var t: int = _at(2, 10)
	for seed_value in [1, 2, 3, 4, 5]:
		# At home, awake and rested: the next decision is the glowing box.
		var buddy: Dictionary = _buddy(seed_value, known, [_letter("A", t - 900)])
		var done: Dictionary = _decide_at(svc, buddy, land, t)
		var e: Dictionary = done["event"]
		var row: Dictionary = _letter_row(done["profile"], "A")
		if not _is_box(e) or str(e["place_id"]) != "home":
			return "seed %d: with a letter waiting it should go to the box: %s" % [seed_value, str(e)]
		if str(e["text"]) != MindService.CONSOLE_READ_ONE_LINE or e.get("read_letters", []) != ["A"]:
			return "seed %d: it reads the letter and says so: %s" % [seed_value, str(e)]
		if int(row["read_t"]) != t or not bool(row["reply_due"]):
			return "seed %d: read_t and reply_due should be set: %s" % [seed_value, str(row)]
		if LetterService.has_unread(done["profile"]):
			return "seed %d: nothing should be left waiting" % seed_value
	# Two letters are read together.
	var two: Dictionary = _decide_at(svc, _buddy(1, known, [_letter("A", t - 900), _letter("B", t - 800)]), land, t)
	if str((two["event"] as Dictionary)["text"]) != MindService.CONSOLE_READ_MANY_LINE or ((two["event"] as Dictionary)["read_letters"] as Array).size() != 2:
		return "two waiting letters are read at once: %s" % str(two["event"])
	# It comes before a wish and something it agreed to.
	var promise := {"kind": "place", "id": "pool", "name": "the pool", "from": "suggestion", "t": t - 100, "until": t + 5000}
	var busy_mind: Dictionary = known.duplicate(true)
	busy_mind["intention"] = promise
	busy_mind["wish"] = "explore"
	var before: Dictionary = _decide_at(svc, _buddy(2, busy_mind, [_letter("A", t - 900)]), land, t)
	if not _is_box(before["event"]) or ((before["profile"]["mind"] as Dictionary)["intention"] as Dictionary).is_empty():
		return "the box comes before a wish or a promise, which is kept for later: %s" % str(before["event"])
	# Away from home it goes home to the glowing box.
	for seed_value in [1, 2, 3]:
		var away_mind: Dictionary = known.duplicate(true)
		away_mind["location"] = "pool"
		away_mind["known_places"] = {"pool": {"stage": "found", "t": t - 5000, "tries": 0}}
		var away: Dictionary = _decide_at(svc, _buddy(seed_value, away_mind, [_letter("A", t - 900)]), land, t)
		var ae: Dictionary = away["event"]
		if not _is_box(ae) or str(ae["place_id"]) != "home" or str((away["profile"]["mind"] as Dictionary)["location"]) != "home":
			return "seed %d: from the pool it should head home to the box: %s" % [seed_value, str(ae)]
		if int(_letter_row(away["profile"], "A")["read_t"]) != t:
			return "seed %d: and read the letter" % seed_value
	# Too tired, it does not go.
	var tired: Dictionary = _buddy(1, known, [_letter("A", t - 900)])
	(tired["mood_modifiers"] as Dictionary)["energy_strain"] = 0.9
	var slept: Dictionary = _decide_at(svc, tired, land, t)
	if (slept["event"] as Dictionary).has("read_letters"):
		return "a worn out buddy rests first: %s" % str(slept["event"])
	return null


# --- 6: asleep -------------------------------------------------------------

func _test_asleep() -> Variant:
	var svc := _service()
	# No natural trips to the box before 7, so only the pull can take it there.
	var land: Dictionary = _land([7, 22])
	var known := {"console": {"goes": 3, "known": true, "known_t": 5}, "busy_until": _at(2, 6, 30), "location": "home"}
	var asleep: Dictionary = _buddy(2, known, [_letter("N", _at(1, 23, 30))])
	# Asleep at three in the morning: no decision, and nothing is read.
	var night: Dictionary = _decide_at(svc, asleep, land, _at(2, 3))
	if not (night["event"] as Dictionary).is_empty() or int(_letter_row(night["profile"], "N")["read_t"]) != 0:
		return "a sleeping buddy decides nothing and reads nothing: %s" % str(night["event"])
	# The wake decision comes first, and is not the letter.
	var wake: Dictionary = _decide_at(svc, night["profile"], land, _at(2, 6, 30))
	var we: Dictionary = wake["event"]
	if we.is_empty() or _is_box(we) or int(_letter_row(wake["profile"], "N")["read_t"]) != 0:
		return "the wake decision comes before the box, and the letter is still waiting: %s" % str(we)
	# Then, in the morning, the box.
	var t: int = maxi(_at(2, 7), int((wake["profile"]["mind"] as Dictionary).get("busy_until", 0)))
	var morning: Dictionary = _decide_at(svc, wake["profile"], land, t)
	var me: Dictionary = morning["event"]
	if not _is_box(me) or int(_letter_row(morning["profile"], "N")["read_t"]) != t:
		return "after it wakes the next decision is the box, and it reads: %s" % str(me)
	return null


# --- 7: blinking -----------------------------------------------------------

func _test_blinking() -> Variant:
	var svc := _service()
	var land: Dictionary = _land()
	var trials := 400
	var blinks := 0
	for i in range(trials):
		var t: int = _at(2, 8) + i * 97
		var done: Dictionary = _decide_at(svc, _buddy(1 + i % 7, {}, [_letter("W", t - 3000)]), land, t)
		var e: Dictionary = done["event"]
		if str(e["text"]) == MindService.CONSOLE_BLINK_LINE:
			blinks += 1
			if not _is_box(e) or e.has("read_letters") or int(_letter_row(done["profile"], "W")["read_t"]) != 0:
				return "a blinking trip is to the box and reads nothing: %s" % str(e)
	var share: float = float(blinks) / float(trials)
	if share < 0.17 or share > 0.33:
		return "about a quarter of decisions should go to the blinking box, got %d of %d" % [blinks, trials]
	# Nothing blinks when no letter waits.
	for i in range(100):
		var t: int = _at(2, 8) + i * 97
		var quiet: Dictionary = _decide_at(svc, _buddy(1 + i % 7), land, t)
		if str((quiet["event"] as Dictionary)["text"]) == MindService.CONSOLE_BLINK_LINE:
			return "no letter, no blinking"
	return null


func _test_blink_go_teaches() -> Variant:
	var svc := _service()
	var land: Dictionary = _land()
	var picked := 0
	for i in range(300):
		var t: int = _at(2, 8) + i * 97
		var buddy: Dictionary = _buddy(1 + i % 5, {"console": {"goes": 2, "known": false, "known_t": 0}}, [_letter("W", t - 3000)])
		var done: Dictionary = _decide_at(svc, buddy, land, t)
		var e: Dictionary = done["event"]
		if not _is_box(e):
			continue
		picked += 1
		if str(e.get("learned", "")) != "console" or str(e["text"]) != MindService.CONSOLE_LEARNED_LINE + MindService.CONSOLE_READ_AFTER_LEARNING:
			return "the learning go wins over the blinking line, and then it reads: %s" % str(e)
		if e.get("read_letters", []) != ["W"] or int(_letter_row(done["profile"], "W")["read_t"]) != t:
			return "on the learning go the waiting letter is read too: %s" % str(e)
	if picked == 0:
		return "no decision went to the box"
	return null


# --- 8: delivery states ----------------------------------------------------

func _test_delivery_states() -> Variant:
	var profile := {"letters": {"items": [_letter("in-box", 100), _letter("was-read", 100, 400)]}}
	var table := [
		["was-read", false, 100, 1000, "read"],
		["in-box", false, 100, 1000, "waiting"],
		["in-box", true, 100, 1000, "waiting"],
		["sent-now", true, 990, 1000, "on_its_way"],
		["sent-now", false, 990, 1000, "on_its_way"],
		["file-still-there", true, 100, 100000, "on_its_way"],
		["gone", false, 100, 100 + LetterService.LOST_AFTER_SECONDS - 1, "on_its_way"],
		["gone", false, 100, 100 + LetterService.LOST_AFTER_SECONDS, "lost"],
	]
	for row in table:
		var got: String = LetterService.delivery_state(profile, str(row[0]), bool(row[1]), int(row[2]), int(row[3]))
		if got != str(row[4]):
			return "%s (file %s, sent %d, now %d) should be %s, got %s" % [str(row[0]), str(row[1]), int(row[2]), int(row[3]), str(row[4]), got]
	return null


# --- 9: the host -----------------------------------------------------------

func _test_host() -> Variant:
	_sim()
	var saved_role: String = AppState._role
	var saved_holding: bool = AppState._holding
	var saved_dir: String = AppState._host_dir
	var base := "%s/host" % ROOT
	_wipe(base)
	AppState._letters_outbox.clear()
	AppState._host_dir = base
	AppState._role = "desktop"
	AppState._holding = false
	var now: int = AppState._now_unix()
	Whereabouts.write_status("%s/host.json" % base, {"pid": 1, "heartbeat": float(now)})
	var problem := ""
	# The desktop sends one through the inbox and shows it on its way.
	var sent: Dictionary = AppState.letters_send("Hello, how is your day?")
	var id: String = str(sent.get("id", ""))
	if not bool(sent.get("ok", false)) or str(sent.get("via", "")) != "inbox" or id == "" or not AppState.letters_inbox_file_exists(id):
		problem = "a desktop letter goes to the inbox: %s" % str(sent)
	if problem == "" and AppState.letters_delivery_state(id, now) != "on_its_way":
		problem = "it is on its way while the file is there"
	if problem == "" and AppState.letters_items().size() != 1:
		problem = "the desktop lists what it has sent"
	# The host takes the inbox. A kind it does not know is ignored; the letter is
	# stored under the request's own id, however old.
	var requests: Array = Whereabouts.take_requests(base)
	requests.append({"kind": "something_new", "id": "999-cccccccc", "text": "ignored", "t": now})
	AppState._role = "solo"
	var host: Node = WorldHost.new()
	host.take_letters(requests)
	host.free()
	var items: Array = AppState.letters_items()
	if problem == "" and (items.size() != 1 or str((items[0] as Dictionary)["id"]) != id or str((items[0] as Dictionary)["text"]) != "Hello, how is your day?"):
		problem = "the host should store the letter under its id and ignore the other kind: %s" % str(items)
	if problem == "" and AppState.letters_delivery_state(id, now) != "waiting":
		problem = "in the mailbox and unread it is waiting"
	# A request taken twice changes nothing.
	var host_again: Node = WorldHost.new()
	host_again.take_letters([{"kind": "letter", "id": id, "text": "Again", "t": now + 5}])
	host_again.free()
	if problem == "" and AppState.letters_items().size() != 1:
		problem = "the same request twice is stored once"
	# A letter that was dropped (an old host) shows as lost, and can be sent again.
	AppState._role = "desktop"
	var lost: Dictionary = AppState.letters_send("Are you there?")
	Whereabouts.take_requests(base)
	AppState.set_sim_clock(now + LetterService.LOST_AFTER_SECONDS + 5)
	Whereabouts.write_status("%s/host.json" % base, {"pid": 1, "heartbeat": float(now + LetterService.LOST_AFTER_SECONDS + 5)})
	if problem == "" and AppState.letters_delivery_state(str(lost["id"]), now) != "lost":
		problem = "a dropped letter shows as lost"
	if problem == "":
		var resent: Dictionary = AppState.letters_send("Are you there?", str(lost["id"]))
		var listed: Array = AppState.letters_items()
		var seen_lost := false
		for row in listed:
			if str((row as Dictionary)["id"]) == str(lost["id"]):
				seen_lost = true
		if not bool(resent["ok"]) or seen_lost:
			problem = "sending again replaces the lost one: %s" % str(resent)
	AppState._role = saved_role
	AppState._holding = saved_holding
	AppState._host_dir = saved_dir
	AppState.set_sim_clock(now)
	_wipe(base)
	return problem if problem != "" else null


# --- 10: memory ------------------------------------------------------------

func _test_memory() -> Variant:
	var mem := MemoryService.new()
	var land: Dictionary = _home_only_land()
	var run: Dictionary = _four_goes(7)
	var goes: Array = run["goes"]
	if goes.size() < 3:
		return "needed three trips to the box"
	var learned: Dictionary = goes[2]["event"]
	var profile: Dictionary = goes[2]["profile"]
	var noted: Dictionary = mem.note_today(profile, [learned], land)
	var today: Array = noted["memory"]["today"]
	var last: Dictionary = today[today.size() - 1]
	if str(last.get("learned", "")) != "console" or not str(last.get("text", "")).begins_with("I watched the glowing box"):
		return "short-term memory keeps what it learned, with its words: %s" % str(last)
	var sorted_out: Dictionary = mem.nightly_pass(noted, land, int(learned["t"]) + DAY)
	var belief := {}
	for edge in sorted_out["memory"]["edges"]:
		if str((edge as Dictionary).get("o", "")) == "belief:console":
			belief = edge
	if belief.is_empty() or str(belief["r"]) != "believes" or str(belief["o_label"]) != "the glowing box is a way to talk to you" or str(belief["source"]) != "land":
		return "the nightly pass turns it into a believes edge: %s" % str(belief)
	# Another night does not make a second one.
	var again: Dictionary = mem.nightly_pass(sorted_out, land, int(learned["t"]) + 2 * DAY)
	var count := 0
	for edge in again["memory"]["edges"]:
		if str((edge as Dictionary).get("o", "")) == "belief:console":
			count += 1
	if count != 1:
		return "one belief, not %d" % count
	# A letter that was read is an event of the day like any other.
	var svc := _service()
	var known := {"console": {"goes": 3, "known": true, "known_t": 5}}
	var t: int = _at(2, 10)
	var read: Dictionary = _decide_at(svc, _buddy(3, known, [_letter("A", t - 900)]), _land(), t)
	var read_noted: Dictionary = mem.note_today(read["profile"], [read["event"]], _land())
	var read_today: Array = read_noted["memory"]["today"]
	if read_today.is_empty() or str((read_today[read_today.size() - 1] as Dictionary).get("activity", "")) != "glowing_box":
		return "the reading goes into today's memory: %s" % str(read_today)
	return null


# --- 11: the old town ------------------------------------------------------

func _test_town_unchanged() -> Variant:
	var svc := _service()
	var land: Dictionary = _land()
	# The old town: nothing is a console, whatever a letter says.
	var profile: Dictionary = _buddy(2, {"born": ""}, [_letter("T", _at(1, 8))])
	var current: Dictionary = profile
	var t: int = _at(1, 8)
	for _n in range(80):
		var hour: int = int(Time.get_datetime_dict_from_unix_time(t).get("hour", 0))
		var result: Dictionary = svc.tick(current, [], t, {"small_beginnings": false, "plans": false, "hour": hour, "is_night": hour < 7 or hour >= 22}, land)
		current = result["profile"]
		for event_variant in result["events"]:
			var e: Dictionary = event_variant
			if e.has("learned") or e.has("read_letters"):
				return "the town knows nothing of letters: %s" % str(e)
		t += 600
	var mind: Dictionary = current["mind"]
	if mind.has("console") or mind.has("first_letter_due"):
		return "the town's mind has no console: %s" % str(mind.keys())
	if int(_letter_row(current, "T")["read_t"]) != 0:
		return "the town does not read letters"
	# The desktop's wrappers do nothing there either.
	_sim()
	var before_count: int = AppState.letters_items().size()
	AppState.settings["smallBeginnings"] = false
	var refused: Dictionary = AppState.letters_send("Hello")
	AppState.letters_receive({"kind": "letter", "id": "1-aaaaaaaa", "text": "Hello", "t": 1})
	var after_count: int = AppState.letters_items().size()
	AppState.settings["smallBeginnings"] = true
	if bool(refused["ok"]) or str(refused["reason"]) != "town" or after_count != before_count:
		return "no letters in the old town: %s, %d before and %d after" % [str(refused), before_count, after_count]
	return null
