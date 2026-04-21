extends Node

const ChatCommandRouter = preload("res://scripts/interaction/chat_command_router.gd")

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("chat_command_router_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("chat_command_router_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("help_command_ok", func(): return _test_help_command_ok())
	_case("mode_missing_arg", func(): return _test_mode_missing_arg())
	_case("world_invalid_arg", func(): return _test_world_invalid_arg())
	_case("remember_requires_note", func(): return _test_remember_requires_note())
	_case("forget_requires_numeric_id", func(): return _test_forget_requires_numeric_id())
	_case("chat_clear_parses_confirm", func(): return _test_chat_clear_parses_confirm())
	_case("preset_accepts_known_values", func(): return _test_preset_accepts_known_values())
	_case("settings_reset_confirm_and_undo", func(): return _test_settings_reset_confirm_and_undo())
	_case("debug_only_chat_area", func(): return _test_debug_only_chat_area())
	_case("unknown_command_rejected", func(): return _test_unknown_command_rejected())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("chat_command_router_test[%s]: %s" % [name, err])
	else:
		print("chat_command_router_test[%s]: ok" % name)


func _test_help_command_ok() -> Variant:
	var router := ChatCommandRouter.new()
	var result := router.resolve("/help")
	if not bool(result.get("ok", false)):
		return "expected /help to be ok"
	if str(result.get("action_id", "")) != "help":
		return "expected action_id=help"
	return null


func _test_mode_missing_arg() -> Variant:
	var router := ChatCommandRouter.new()
	var result := router.resolve("/mode")
	if bool(result.get("ok", false)):
		return "expected /mode with missing arg to fail"
	if str(result.get("reason_code", "")) != "missing_arg":
		return "expected reason_code=missing_arg"
	return null


func _test_world_invalid_arg() -> Variant:
	var router := ChatCommandRouter.new()
	var result := router.resolve("/world maybe")
	if bool(result.get("ok", false)):
		return "expected /world maybe to fail"
	if str(result.get("reason_code", "")) != "invalid_arg":
		return "expected reason_code=invalid_arg"
	return null


func _test_remember_requires_note() -> Variant:
	var router := ChatCommandRouter.new()
	var result := router.resolve("/remember")
	if bool(result.get("ok", false)):
		return "expected /remember to fail without note"
	if str(result.get("reason_code", "")) != "missing_arg":
		return "expected reason_code=missing_arg"
	return null


func _test_forget_requires_numeric_id() -> Variant:
	var router := ChatCommandRouter.new()
	var result := router.resolve("/forget abc")
	if bool(result.get("ok", false)):
		return "expected /forget abc to fail"
	if str(result.get("reason_code", "")) != "invalid_arg":
		return "expected reason_code=invalid_arg"
	return null


func _test_chat_clear_parses_confirm() -> Variant:
	var router := ChatCommandRouter.new()
	var result := router.resolve("/chat clear confirm")
	if not bool(result.get("ok", false)):
		return "expected /chat clear confirm to pass"
	var params_variant = result.get("params", {})
	if typeof(params_variant) != TYPE_DICTIONARY:
		return "params missing"
	var params: Dictionary = params_variant
	if str(params.get("action", "")) != "clear":
		return "expected action=clear"
	if not bool(params.get("confirm", false)):
		return "expected confirm=true"
	return null


func _test_preset_accepts_known_values() -> Variant:
	var router := ChatCommandRouter.new()
	var result := router.resolve("/preset cozy")
	if not bool(result.get("ok", false)):
		return "expected /preset cozy to pass"
	var bad := router.resolve("/preset turbo")
	if bool(bad.get("ok", false)):
		return "expected /preset turbo to fail"
	if str(bad.get("reason_code", "")) != "invalid_arg":
		return "expected reason_code=invalid_arg"
	return null


func _test_settings_reset_confirm_and_undo() -> Variant:
	var router := ChatCommandRouter.new()
	var reset := router.resolve("/settings reset confirm")
	if not bool(reset.get("ok", false)):
		return "expected /settings reset confirm to pass"
	var params_variant = reset.get("params", {})
	if typeof(params_variant) != TYPE_DICTIONARY:
		return "params missing"
	var params: Dictionary = params_variant
	if str(params.get("action", "")) != "reset":
		return "expected action=reset"
	if not bool(params.get("confirm", false)):
		return "expected confirm=true"
	var undo := router.resolve("/settings undo")
	if not bool(undo.get("ok", false)):
		return "expected /settings undo to pass"
	return null


func _test_debug_only_chat_area() -> Variant:
	var router := ChatCommandRouter.new()
	var ok := router.resolve("/debug chat")
	if not bool(ok.get("ok", false)):
		return "expected /debug chat to pass"
	var bad := router.resolve("/debug world")
	if bool(bad.get("ok", false)):
		return "expected /debug world to fail"
	if str(bad.get("reason_code", "")) != "invalid_arg":
		return "expected reason_code=invalid_arg"
	return null


func _test_unknown_command_rejected() -> Variant:
	var router := ChatCommandRouter.new()
	var result := router.resolve("/not-real")
	if bool(result.get("ok", false)):
		return "expected unknown command to fail"
	if str(result.get("reason_code", "")) != "unknown_command":
		return "expected reason_code=unknown_command"
	return null
