extends Node

# Plan 14 step 2b-2: measures what the buddy says on the land. Lives a fresh
# buddy through N days (the same fast-forward as simulate_days), then asks it
# questions through the real chat path: the same memory recall, request,
# check, honest retry and fallback as buddy_overlay.gd, with a real model.
# Not part of the required suite (it needs Ollama); for the reviewer.
#
# --mode=letters (step 2c-2) treats each question as a letter from you and measures
# what the buddy writes back: the request is AppState.letters_request_body, the
# very one the letter writer sends, with the same check, honest retry and fallback.
#
# Usage (after --): --no-save --questions=<json> [--seed=N] [--model=<name>]
#                   [--url=<ollama>] [--out=<path>] [--mode=chat|letters]
# The questions file is {"sets": {name: [question]}, "days": [1, 7, 30], "repeats": 2}.
# --no-save is required, as for simulate_days: nothing here can touch the save.
# --out gets one JSON row per reply (JSON lines).

const LifeSim = preload("res://tests/life_sim.gd")
const MindThinker = preload("res://scripts/services/mind_thinker.gd")

var _http: HTTPRequest
var _model := MindThinker.DEFAULT_MODEL
var _endpoint := ""
var _mode := "chat"
var _rows: Array = []
# set name -> {"first": n, "retry": n, "fallback": n, "error": n}
var _summary := {}


func _ready() -> void:
	if not AppState.is_simulating():
		_fail("chat_eval: start this with --no-save (%s) so the save files are never opened." % AppState.NO_SAVE_ARG)
		return
	print("chat_eval: started without opening the save files")
	var questions_path := ""
	var seed_value := 1
	var url := MindThinker.DEFAULT_URL
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == AppState.NO_SAVE_ARG:
			continue
		if text.begins_with("--questions="):
			questions_path = text.substr(12)
		elif text.begins_with("--seed="):
			var value := text.substr(7)
			if not value.is_valid_int():
				_fail("chat_eval: bad --seed value '%s'" % value)
				return
			seed_value = int(value)
		elif text.begins_with("--model="):
			_model = text.substr(8)
		elif text.begins_with("--url="):
			url = text.substr(6)
		elif text.begins_with("--out="):
			out_path = text.substr(6)
		elif text.begins_with("--mode="):
			_mode = text.substr(7)
			if _mode != "chat" and _mode != "letters":
				_fail("chat_eval: --mode must be chat or letters")
				return
		else:
			_fail("chat_eval: unknown argument '%s'" % text)
			return
	_endpoint = MindThinker.endpoint(url)
	if _endpoint == "":
		_fail("chat_eval: --url must be a plain http(s) address")
		return
	if questions_path == "" or not FileAccess.file_exists(questions_path):
		_fail("chat_eval: --questions=<path to json> is needed")
		return
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(questions_path))
	if typeof(spec) != TYPE_DICTIONARY or typeof((spec as Dictionary).get("sets", null)) != TYPE_DICTIONARY or typeof((spec as Dictionary).get("days", null)) != TYPE_ARRAY:
		_fail("chat_eval: the questions file must be {\"sets\": {name: [question]}, \"days\": [..], \"repeats\": N}")
		return
	_http = HTTPRequest.new()
	_http.timeout = MindThinker.REQUEST_TIMEOUT_SECONDS
	_http.body_size_limit = MindThinker.MAX_REPLY_BYTES
	_http.max_redirects = 0
	add_child(_http)
	_run(spec, seed_value, out_path)


func _run(spec: Dictionary, seed_value: int, out_path: String) -> void:
	var sets: Dictionary = spec["sets"]
	var repeats: int = maxi(1, int(spec.get("repeats", 1)))
	for day_variant in spec["days"]:
		var day: int = int(day_variant)
		# A fresh life each time, as long as asked.
		var report: Dictionary = LifeSim.run(AppState, {"days": day, "seed": seed_value, "small_beginnings": true})
		if report.has("error"):
			_fail("chat_eval: " + str(report["error"]))
			return
		print("chat_eval: day %d, asking" % day)
		for set_name in sets.keys():
			if not _summary.has(set_name):
				_summary[set_name] = {"first": 0, "retry": 0, "fallback": 0, "error": 0}
			for question_variant in sets[set_name]:
				for i in repeats:
					var row: Dictionary = await _ask(str(question_variant))
					row["day"] = day
					row["set"] = str(set_name)
					row["i"] = i
					_rows.append(row)
					var source: String = str(row["final_source"])
					_summary[set_name][source if _summary[set_name].has(source) else "error"] += 1
	if out_path != "":
		var folder := out_path.get_base_dir()
		if folder != "" and DirAccess.make_dir_recursive_absolute(folder) != OK:
			_fail("chat_eval: cannot create folder '%s'" % folder)
			return
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			_fail("chat_eval: cannot write '%s'" % out_path)
			return
		for row in _rows:
			file.store_line(JSON.stringify(row))
		file.close()
		print("chat_eval: wrote %s" % out_path)
	for set_name in _summary.keys():
		var counts: Dictionary = _summary[set_name]
		print("chat_eval: %s: first %d, retry %d, fallback %d, error %d" % [set_name, counts["first"], counts["retry"], counts["fallback"], counts["error"]])
	print("chat_eval: DONE (%d replies)" % _rows.size())
	get_tree().quit(0)


# One question, the way buddy_overlay.gd answers it: check, one honest retry,
# then the fallback.
func _ask(question: String) -> Dictionary:
	var known: Dictionary = AppState.memory_known_words()
	var context := {}
	if _mode == "letters":
		context = {"work": {"kind": "reply", "letter": {"id": "eval", "text": question, "t": AppState._now_unix()}}}
	else:
		var recalled: Dictionary = AppState.memory_recall_land(question)
		# On the land what_you_remember holds only what it knows about them.
		var memory: Dictionary = AppState.memory_recall(question, false)
		context = {
			"about": _about(), "recent": _recent_journal_texts(4), "turns": [], "user_text": question,
			"town": {}, "memory": memory, "decision": "", "say": "", "land": true, "your_memories": recalled.get("lines", []),
		}
	var row := {"question": question, "first": "", "first_check": {}, "retry": "", "final": "", "final_source": "error"}
	var first: Dictionary = await _send(_body(context, ""))
	if not bool(first.get("ok", false)) and not _unreadable(first):
		row["error"] = str(first.get("reason", ""))
		return row
	row["first"] = str(first.get("reply", ""))
	# As in letter_writer.gd, an unreadable letter counts as a failed check with
	# nothing named: one retry, then the fallback.
	var checked: Dictionary = MindThinker.check_reply(str(first["reply"]), question, known) if bool(first.get("ok", false)) else {"ok": false, "unknown": [], "premise": false, "unreadable": str(first.get("reason", ""))}
	row["first_check"] = checked
	if bool(checked.get("ok", false)):
		row["final"] = str(first["reply"])
		row["final_source"] = "first"
		return row
	var note: String = MindThinker.honest_retry_note(checked.get("unknown", []), bool(checked.get("premise", false)), checked.get("held", []))
	var retry: Dictionary = await _send(_body(context, note))
	if not bool(retry.get("ok", false)) and not _unreadable(retry):
		row["error"] = str(retry.get("reason", ""))
		return row
	row["retry"] = str(retry.get("reply", ""))
	var rechecked: Dictionary = MindThinker.check_reply(str(retry["reply"]), question, known) if bool(retry.get("ok", false)) else {"ok": false, "unknown": [], "premise": false, "unreadable": str(retry.get("reason", ""))}
	row["retry_check"] = rechecked
	if bool(rechecked.get("ok", false)):
		row["final"] = str(retry["reply"])
		row["final_source"] = "retry"
	else:
		if _mode == "letters":
			row["final"] = MindThinker.letter_fallback(question, rechecked.get("unknown", []), known, false)
		else:
			row["final"] = MindThinker.fallback_line(question, rechecked.get("unknown", []), known)
		row["final_source"] = "fallback"
	return row


# Letters mode only: a reply that came back but could not be read (not a network
# or server failure) is treated like the writer treats it, not as an error.
func _unreadable(result: Dictionary) -> bool:
	if _mode != "letters":
		return false
	var reason := str(result.get("reason", ""))
	return not (reason.begins_with("transport_") or reason.begins_with("http_") or reason.begins_with("request_error"))


func _body(context: Dictionary, extra_task: String) -> String:
	if _mode == "letters":
		return AppState.letters_request_body(_model, context["work"], extra_task)
	return MindThinker.build_chat_request(
		_model, context["about"], context["recent"], context["turns"], str(context["user_text"]), context["town"], context["memory"],
		str(context["decision"]), str(context["say"]), bool(context["land"]), context["your_memories"], extra_task
	)


# {"ok": bool, "reply": String, "reason": String}
func _send(body: String) -> Dictionary:
	var error: int = _http.request(_endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		return {"ok": false, "reply": "", "reason": "request_error_%d" % error}
	var result: Array = await _http.request_completed
	# Let the signal finish before the next request goes out on the same node:
	# a request started from inside request_completed never completed.
	await get_tree().process_frame
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "reply": "", "reason": "transport_%d" % int(result[0])}
	if int(result[1]) != 200:
		return {"ok": false, "reply": "", "reason": "http_%d" % int(result[1])}
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	if _mode == "letters":
		var letter: Dictionary = MindThinker.parse_letter_reply(text)
		return {"ok": bool(letter["ok"]), "reply": str(letter["letter"]), "reason": str(letter["reason"])}
	return MindThinker.parse_chat_reply(text)


func _about() -> Dictionary:
	var mind: Dictionary = {}
	if typeof(AppState.profile.get("mind", null)) == TYPE_DICTIONARY:
		mind = AppState.profile["mind"]
	var here := ""
	var location: String = str(mind.get("location", ""))
	var places_variant = AppState.get_town().get("places", [])
	if typeof(places_variant) == TYPE_ARRAY:
		for place in places_variant:
			if typeof(place) == TYPE_DICTIONARY and str((place as Dictionary).get("id", "")) == location:
				here = str((place as Dictionary).get("name", ""))
	return {"name": str(mind.get("name", "")), "mood": "calm", "doing_now": "idle", "where_you_are": here}


func _recent_journal_texts(limit: int) -> Array:
	var recent: Array = []
	for entry_variant in AppState.get_mind_journal(limit):
		if typeof(entry_variant) == TYPE_DICTIONARY:
			recent.append(str((entry_variant as Dictionary).get("text", "")))
	return recent


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
