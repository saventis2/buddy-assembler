extends RefCounted

const SUPPORTED_COMMANDS := [
	"help",
	"status",
	"pending",
	"mode",
	"reward",
	"world",
	"quiet",
	"freq",
	"chat",
	"memory",
	"remember",
	"forget",
	"cadence",
	"debug",
	"settings-check",
]


func resolve(input_text: String) -> Dictionary:
	var raw := input_text.strip_edges()
	if raw == "":
		return _result(false, "empty", "", {}, "empty_input", 0.0)

	if raw.begins_with("/"):
		return _resolve_slash(raw)

	var alias := _resolve_alias(raw.to_lower())
	if not alias.is_empty():
		return alias

	var intent := _resolve_intent(raw.to_lower())
	if not intent.is_empty():
		return intent

	return _result(false, "unknown", "", {}, "unknown_intent", 0.2)


func _resolve_slash(raw: String) -> Dictionary:
	var body := raw.substr(1).strip_edges()
	if body == "":
		return _result(false, "command", "", {}, "missing_command", 0.0)
	var tokens := body.split(" ", false)
	if tokens.is_empty():
		return _result(false, "command", "", {}, "missing_command", 0.0)

	var command := str(tokens[0]).to_lower()
	var args: Array = []
	for i in range(1, tokens.size()):
		args.append(str(tokens[i]))

	if not SUPPORTED_COMMANDS.has(command):
		return _result(false, "command", command, {}, "unknown_command", 0.0)

	return _validate_command(command, args)


func _validate_command(command: String, args: Array) -> Dictionary:
	if command in ["help", "status", "pending", "reward", "memory", "cadence", "settings-check"]:
		if not args.is_empty():
			return _result(false, "command", command, {}, "unexpected_args", 1.0)
		return _result(true, "command", command, {}, "ok", 1.0)

	if command == "mode":
		if args.size() != 1:
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		var mode := str(args[0]).to_lower()
		if mode not in ["home", "overlay"]:
			return _result(false, "command", command, {}, "invalid_arg", 1.0)
		return _result(true, "command", command, {"mode": mode}, "ok", 1.0)

	if command == "world":
		if args.size() != 1:
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		var decision := str(args[0]).to_lower()
		if decision not in ["engage", "skip", "complete"]:
			return _result(false, "command", command, {}, "invalid_arg", 1.0)
		return _result(true, "command", command, {"decision": decision}, "ok", 1.0)

	if command == "quiet":
		if args.size() != 1:
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		var level := str(args[0]).to_lower()
		if level not in ["lenient", "balanced", "strict"]:
			return _result(false, "command", command, {}, "invalid_arg", 1.0)
		return _result(true, "command", command, {"level": level}, "ok", 1.0)

	if command == "freq":
		if args.size() != 1:
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		var value := str(args[0]).to_lower()
		if value not in ["low", "normal", "high"]:
			return _result(false, "command", command, {}, "invalid_arg", 1.0)
		return _result(true, "command", command, {"value": value}, "ok", 1.0)

	if command == "chat":
		if args.is_empty():
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		var chat_action := str(args[0]).to_lower()
		if chat_action == "close":
			if args.size() != 1:
				return _result(false, "command", command, {}, "unexpected_args", 1.0)
			return _result(true, "command", command, {"action": chat_action}, "ok", 1.0)
		if chat_action == "clear":
			var confirm := args.size() > 1 and str(args[1]).to_lower() == "confirm"
			if args.size() > 2:
				return _result(false, "command", command, {}, "unexpected_args", 1.0)
			return _result(true, "command", command, {"action": chat_action, "confirm": confirm}, "ok", 1.0)
		if chat_action == "text":
			if args.size() != 2:
				return _result(false, "command", command, {}, "missing_arg", 1.0)
			var text_size := str(args[1]).to_lower()
			if text_size not in ["m", "l"]:
				return _result(false, "command", command, {}, "invalid_arg", 1.0)
			return _result(true, "command", command, {"action": chat_action, "size": text_size}, "ok", 1.0)
		if chat_action not in ["close", "clear", "text"]:
			return _result(false, "command", command, {}, "invalid_arg", 1.0)
		return _result(false, "command", command, {}, "invalid_arg", 1.0)

	if command == "remember":
		if args.is_empty():
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		var note := " ".join(args).strip_edges()
		if note == "":
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		return _result(true, "command", command, {"note": note}, "ok", 1.0)

	if command == "forget":
		if args.is_empty():
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		var id_text := str(args[0]).strip_edges()
		if id_text == "" or not id_text.is_valid_int():
			return _result(false, "command", command, {}, "invalid_arg", 1.0)
		var note_id := int(id_text)
		var confirm := false
		if args.size() > 1:
			confirm = str(args[1]).to_lower() == "confirm"
		return _result(true, "command", command, {"id": note_id, "confirm": confirm}, "ok", 1.0)

	if command == "debug":
		if args.size() != 1:
			return _result(false, "command", command, {}, "missing_arg", 1.0)
		var area := str(args[0]).to_lower()
		if area not in ["chat"]:
			return _result(false, "command", command, {}, "invalid_arg", 1.0)
		return _result(true, "command", command, {"area": area}, "ok", 1.0)

	return _result(false, "command", command, {}, "unsupported_command", 0.5)


func _resolve_alias(msg: String) -> Dictionary:
	if msg.find("open reward") >= 0 or msg.find("open box") >= 0 or msg.find("reward box") >= 0:
		return _result(true, "command", "reward", {}, "ok", 0.95)
	if msg.find("switch to home") >= 0 or msg.find("go home mode") >= 0:
		return _result(true, "command", "mode", {"mode": "home"}, "ok", 0.95)
	if msg.find("switch to overlay") >= 0 or msg.find("go overlay") >= 0:
		return _result(true, "command", "mode", {"mode": "overlay"}, "ok", 0.95)
	if msg.find("skip encounter") >= 0:
		return _result(true, "command", "world", {"decision": "skip"}, "ok", 0.9)
	if msg.find("engage encounter") >= 0 or msg.find("do encounter") >= 0:
		return _result(true, "command", "world", {"decision": "engage"}, "ok", 0.9)
	if msg.find("show status") >= 0 or msg.find("what is my status") >= 0:
		return _result(true, "command", "status", {}, "ok", 0.9)
	if msg.find("what is pending") >= 0 or msg.find("pending tasks") >= 0:
		return _result(true, "command", "pending", {}, "ok", 0.9)
	if msg.find("show memory") >= 0 or msg.find("memory status") >= 0:
		return _result(true, "command", "memory", {}, "ok", 0.9)
	if msg.find("quiet strict") >= 0:
		return _result(true, "command", "quiet", {"level": "strict"}, "ok", 0.9)
	if msg.find("quiet balanced") >= 0:
		return _result(true, "command", "quiet", {"level": "balanced"}, "ok", 0.9)
	if msg.find("quiet lenient") >= 0:
		return _result(true, "command", "quiet", {"level": "lenient"}, "ok", 0.9)
	if msg.find("set frequency low") >= 0:
		return _result(true, "command", "freq", {"value": "low"}, "ok", 0.9)
	if msg.find("set frequency normal") >= 0:
		return _result(true, "command", "freq", {"value": "normal"}, "ok", 0.9)
	if msg.find("set frequency high") >= 0:
		return _result(true, "command", "freq", {"value": "high"}, "ok", 0.9)
	return {}


func _resolve_intent(msg: String) -> Dictionary:
	if msg.find("hello") >= 0 or msg.find("hi") >= 0 or msg.find("hey") >= 0:
		return _result(true, "intent", "greeting", {}, "ok", 0.8)
	if msg.find("help") >= 0:
		return _result(true, "intent", "help", {}, "ok", 0.85)
	if msg.find("quest") >= 0 or msg.find("world") >= 0:
		return _result(true, "intent", "world", {}, "ok", 0.7)
	if msg.find("reward") >= 0 or msg.find("box") >= 0:
		return _result(true, "intent", "reward", {}, "ok", 0.7)
	if msg.find("sleep") >= 0 or msg.find("tired") >= 0:
		return _result(true, "intent", "rest", {}, "ok", 0.7)
	if msg.find("mode") >= 0 or msg.find("home") >= 0 or msg.find("overlay") >= 0:
		return _result(true, "intent", "mode", {}, "ok", 0.7)
	if msg.find("thanks") >= 0 or msg.find("thank you") >= 0:
		return _result(true, "intent", "thanks", {}, "ok", 0.8)
	return {}


func _result(ok: bool, kind: String, action_id: String, params: Dictionary, reason_code: String, confidence: float) -> Dictionary:
	return {
		"ok": ok,
		"kind": kind,
		"action_id": action_id,
		"params": params,
		"reason_code": reason_code,
		"confidence": confidence,
	}
