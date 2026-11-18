extends Node

# The world host (Plan 14 step 2a): a headless process that lives the buddy's
# life on its land while it is at home, and hands it to the desktop app when it
# visits. Started with `--headless -- --world-host` (launch_router.gd adds this
# node; there is no scene). While it holds the buddy it is the only process
# that writes profile.json and world_state.json; it never writes settings.json.
# The buddy is in one place at a time, by hand-over (buddy_whereabouts.gd).
# The host never calls a language model.

const Whereabouts = preload("res://scripts/persistence/buddy_whereabouts.gd")

const HOST_TICK_SECONDS := 10
const DESKTOP_REASONS := ["bedtime", "quiet", "sent", "closed"]
# After a hand-over the desktop has this long to take the buddy before the host
# counts it as lost and takes it back.
const HANDOVER_GRACE_SECONDS := 60
# A call older than this (from an app that has since closed) is not answered.
const REQUEST_MAX_AGE_SECONDS := 600

var _base: String = AppState.HOST_DIR
var _timer: Timer
var _started := 0.0
var _last_tick := 0.0
# Since when this process has been awake and ticking without a gap; a PC that
# slept resets it, so a woken host never breaks a live holder's lock.
var _awake_since := 0.0
var _settings_mtime := -1
var _status: Dictionary = {}
# A call it said it would come for once it was free or awake: {id, reason, at}.
var _pending: Dictionary = {}
# When this process last handed the buddy over (0: never).
var _handed_over_at := 0.0


func _ready() -> void:
	var now := Time.get_unix_time_from_system()
	_started = now
	_awake_since = now
	# Only one host at a time: a second one (started by the app or by hand while
	# one is running) stops at once and writes nothing.
	var other := Whereabouts.read_status("%s/host.json" % _base)
	var other_pid := int(other.get("pid", 0))
	if Whereabouts.is_alive(other, now) and other_pid != OS.get_process_id() and Whereabouts.is_running(other_pid):
		print("world_host: another host is running (pid %d); this one stops" % other_pid)
		get_tree().quit()
		return
	print("world_host: started (pid %d)" % OS.get_process_id())
	_status = {
		"pid": OS.get_process_id(),
		"started": now,
		"heartbeat": now,
		"state": "waiting",
		"reason": "",
		"answer": {},
		"freshStartBackup": "",
	}
	_write_status()
	_timer = Timer.new()
	_timer.wait_time = HOST_TICK_SECONDS
	_timer.one_shot = false
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	_tick()


func _write_status() -> void:
	Whereabouts.write_status("%s/host.json" % _base, _status)


func _desktop_status() -> Dictionary:
	return Whereabouts.read_status("%s/desktop.json" % _base)


# The desktop app is open and the buddy is not with it. (After it sends the
# buddy home it says "sent_home" until its next visit, so that counts too.)
func _desktop_present(desktop: Dictionary, now: float) -> bool:
	return Whereabouts.is_alive(desktop, now) and ["away", "sent_home"].has(str(desktop.get("state", "")))


func _tick() -> void:
	var now := Time.get_unix_time_from_system()
	# 1. Track being awake.
	if _last_tick > 0.0 and now - _last_tick > 3.0 * HOST_TICK_SECONDS:
		_awake_since = now
	_last_tick = now
	# 2. Settings.
	var mtime := FileAccess.get_modified_time(AppState.SETTINGS_PATH)
	if mtime != _settings_mtime:
		_settings_mtime = mtime
		AppState.reload_settings_read_only()
		if not bool(AppState.settings.get("worldHost", false)):
			_stop()
			return
	# 3. Status and heartbeat.
	_status["pid"] = OS.get_process_id()
	_status["started"] = _started
	_status["heartbeat"] = now
	if AppState.is_holding_buddy():
		Whereabouts.heartbeat(_base, "host", OS.get_process_id(), now)
	var desktop := _desktop_status()
	# 4. Not holding.
	if not AppState.is_holding_buddy():
		var desktop_alive := Whereabouts.is_alive(desktop, now)
		var desktop_state := str(desktop.get("state", ""))
		if desktop_alive and desktop_state == "visiting":
			_status["state"] = "visiting"
			_write_status()
			return
		# Sent home since this process handed it over. For a host that never did,
		# any "sent_home" counts: the app sent it home while no host was running.
		var sent_back := desktop_state == "sent_home" and float(desktop.get("at", 0)) >= _handed_over_at
		# Just handed over: the app may not have picked it up yet. A "sent_home"
		# left over from its last visit must not end this one.
		if str(_status.get("state", "")) == "visiting" and desktop_alive and not sent_back and now - _handed_over_at < HANDOVER_GRACE_SECONDS:
			_write_status()
			return
		if not Whereabouts.try_acquire(_base, "host", OS.get_process_id(), now, now - _awake_since):
			_status["state"] = "waiting"
			_write_status()
			return
		AppState.take_buddy()
		var kept := Whereabouts.read_status("%s/host.json" % _base)
		_status["freshStartBackup"] = str(kept.get("freshStartBackup", _status.get("freshStartBackup", "")))
		var mind_variant = AppState.profile.get("mind", {})
		if typeof(mind_variant) == TYPE_DICTIONARY and str((mind_variant as Dictionary).get("location", "")) == "visiting":
			var reason := "lost"
			if sent_back and DESKTOP_REASONS.has(str(desktop.get("reason", ""))):
				reason = str(desktop["reason"])
			AppState.mind_return_from_visit(int(now), reason)
			print("world_host: took the buddy back (%s)" % reason)
		_status["state"] = "home"
		_status["reason"] = ""
	# 5. Holding.
	var present := _desktop_present(desktop, now)
	# 5.1 Requests.
	for request in Whereabouts.take_requests(_base):
		if str(request.get("kind", "")) != "call_over":
			continue
		if now - float(request.get("t", now)) > REQUEST_MAX_AGE_SECONDS:
			continue
		var answer: Dictionary = AppState.mind_consider_call(int(now))
		var request_reason := str(request.get("reason", "called"))
		_status["answer"] = {
			"id": str(request.get("id", "")),
			"come": str(answer.get("come", "now")),
			"at": int(answer.get("at", now)),
			"why": str(answer.get("why", "")),
		}
		if str(answer.get("come", "now")) == "now":
			if present:
				_hand_over(now, request_reason)
				return
		else:
			_pending = {"id": str(request.get("id", "")), "reason": request_reason, "at": int(answer.get("at", now))}
	# 5.2 A waiting call.
	if not _pending.is_empty():
		if not Whereabouts.is_alive(desktop, now):
			_pending = {}
		elif now >= float(_pending["at"]) and present:
			# Ask again: it may have slept in, or started something new.
			var again: Dictionary = AppState.mind_consider_call(int(now))
			if str(again.get("come", "now")) == "now":
				_pending = {}
				_hand_over(now, "pending")
				return
			_pending["at"] = int(again.get("at", now))
	# 5.3 A lonely visit.
	if present and _pending.is_empty() and AppState.mind_wants_company(int(now)):
		_hand_over(now, "lonely")
		return
	# 5.4 Otherwise it lives its life.
	AppState.tick_mind(int(now))
	_write_status()


# 6. Hand over.
func _hand_over(now: float, reason: String) -> void:
	AppState.mind_leave_for_visit(int(now), reason)
	AppState.release_buddy()
	Whereabouts.release(_base, "host", OS.get_process_id())
	_handed_over_at = now
	_status["state"] = "visiting"
	_status["reason"] = reason
	_write_status()
	print("world_host: handed the buddy to the desktop (%s)" % reason)


func _stop() -> void:
	if AppState.is_holding_buddy():
		AppState.release_buddy()
		Whereabouts.release(_base, "host", OS.get_process_id())
	_status["state"] = "waiting"
	# A heartbeat of 0 says "not running" at once, rather than after the stale time.
	_status["heartbeat"] = 0
	_write_status()
	print("world_host: setting off, stopping")
	get_tree().quit()
