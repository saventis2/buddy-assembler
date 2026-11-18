extends Node

# The desktop side of the world host (Plan 14 step 2a): this app is the buddy
# visiting. While the buddy is at home the host lives its life and this app only
# shows where it is; while it visits, this app looks after it exactly as before
# and is the only process writing profile.json and world_state.json. It is
# added by the overlay only when AppState.role() == "desktop", and talks to the
# overlay through the signals below. See buddy_whereabouts.gd for the files.

const Whereabouts = preload("res://scripts/persistence/buddy_whereabouts.gd")

signal arrived(reason: String)
signal left(reason: String)
signal answer(come: String, at: int, why: String)
signal health(state: String)

const DESKTOP_POLL_SECONDS := 2
const HOST_START_WAIT_SECONDS := 20
const HOST_RESPAWN_SECONDS := 300
const AWAY_REFRESH_SECONDS := 10
const QUIET_SECONDS := 7200

var _base: String = AppState.HOST_DIR
var _timer: Timer
var _pid := 0
var _started := 0.0
var _awake_since := 0.0
var _last_poll := 0.0
var _last_interaction := 0.0
var _visiting := false
var _closed := false
# "starting" while it waits for the host it just launched; "ready" after.
var _phase := "ready"
var _start_deadline := 0.0
var _next_respawn := 0.0
var _opened_sent := false
var _last_answer_id := ""
var _last_health := ""
var _last_refresh := 0.0
# After sending the buddy home, it does not arrive again until the host has
# taken it back (host.json no longer says "visiting"), or the stale hand-over
# the host has not yet cleared would bring it straight back.
var _host_must_take_back := false
var _state := "away"
var _reason := ""
var _state_at := 0


func is_visiting() -> bool:
	return _visiting


func start() -> void:
	_pid = OS.get_process_id()
	var now := Time.get_unix_time_from_system()
	_started = now
	_awake_since = now
	_last_interaction = now
	_last_poll = now
	var desktop := Whereabouts.read_status("%s/desktop.json" % _base)
	var other_pid := int(desktop.get("pid", 0))
	# A status file left by an app that crashed a moment ago does not count.
	if Whereabouts.is_alive(desktop, now) and other_pid != _pid and Whereabouts.is_running(other_pid):
		print("visit_controller: the buddy app is already open (pid %d)" % int(desktop.get("pid", 0)))
		get_tree().quit()
		return
	_set_state("away", "")
	_write_desktop(now)
	_timer = Timer.new()
	_timer.wait_time = DESKTOP_POLL_SECONDS
	_timer.one_shot = false
	_timer.timeout.connect(_poll)
	add_child(_timer)
	if AppState.is_holding_buddy():
		# After a scene reload it is still with us.
		_visiting = true
		_opened_sent = true
		_set_state("visiting", "")
	else:
		var host := Whereabouts.read_status("%s/host.json" % _base)
		if not Whereabouts.is_alive(host, now):
			# Asked before the host starts, so its first look at the inbox finds
			# the call before it catches up on its day and gets busy.
			Whereabouts.send_request(_base, "call_over", {"reason": "opened"}, now)
			_opened_sent = true
			_spawn_host()
			_phase = "starting"
			_start_deadline = now + HOST_START_WAIT_SECONDS
			_emit_health("starting")
	_timer.start()
	_poll()


# Whether this app finishes a visit itself when the buddy goes home: only when
# no host will take it back and finish it.
static func should_finish_here(setting_on: bool, host_alive: bool) -> bool:
	return not setting_on or not host_alive


func _buddy_is_visiting() -> bool:
	var mind_variant = AppState.profile.get("mind", {})
	return typeof(mind_variant) == TYPE_DICTIONARY and str((mind_variant as Dictionary).get("location", "")) == "visiting"


func call_over() -> void:
	if _visiting or _closed:
		return
	Whereabouts.send_request(_base, "call_over", {"reason": "called"}, Time.get_unix_time_from_system())


func send_home() -> void:
	if _visiting:
		_go_home("sent")


func note_interaction() -> void:
	_last_interaction = Time.get_unix_time_from_system()


# The app is closing: the buddy goes home first, so the host can have it back.
func close_app() -> void:
	if _closed:
		return
	_closed = true
	var now := Time.get_unix_time_from_system()
	var was_visiting := _visiting
	if was_visiting:
		_go_home("closed")
	if _timer != null:
		_timer.stop()
	# A heartbeat of 0 says "closed" at once, rather than after the stale time.
	_write_desktop(0.0)
	if was_visiting:
		print("visit_controller: the buddy went home (closed)")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close_app()


func _set_state(state: String, reason: String) -> void:
	_state = state
	_reason = reason
	_state_at = int(Time.get_unix_time_from_system())


func _write_desktop(heartbeat: float) -> void:
	Whereabouts.write_status("%s/desktop.json" % _base, {
		"pid": _pid,
		"started": _started,
		"heartbeat": heartbeat,
		"state": _state,
		"reason": _reason,
		"at": _state_at,
	})


func _emit_health(state: String) -> void:
	if state == _last_health:
		return
	_last_health = state
	health.emit(state)


func _spawn_host() -> void:
	var args: Array = []
	if not OS.has_feature("template"):
		# A run from the editor's project folder: the host needs the project path.
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append("--headless")
	args.append("--")
	args.append("--world-host")
	var pid := OS.create_process(OS.get_executable_path(), args, false)
	if pid <= 0:
		push_warning("visit_controller: could not start the world host")


func _poll() -> void:
	if _closed:
		return
	var now := Time.get_unix_time_from_system()
	# A PC that slept: this process has not been ticking, so it may not break locks yet.
	if now - _last_poll > 3.0 * DESKTOP_POLL_SECONDS:
		_awake_since = now
	_last_poll = now
	# Heartbeats. is_holding_buddy() checks the lock is still ours.
	if AppState.is_holding_buddy():
		Whereabouts.heartbeat(AppState.HOST_DIR, "desktop", _pid, now)
	elif _visiting:
		# This app froze for longer than the stale time and the host took the
		# buddy back: it is at home now, and nothing here writes it any more.
		_visiting = false
		_host_must_take_back = false
		_set_state("away", "")
		left.emit("lost")
	_write_desktop(now)
	var host := Whereabouts.read_status("%s/host.json" % _base)
	var host_alive := Whereabouts.is_alive(host, now)
	# Waiting for the host it launched.
	if _phase == "starting":
		if host_alive:
			_phase = "ready"
		elif now >= _start_deadline:
			_phase = "ready"
			_emit_health("not_running")
			_stay_with_you(now)
			_next_respawn = now + HOST_RESPAWN_SECONDS
	if _phase == "starting":
		_emit_health("starting")
		return
	_emit_health("running" if host_alive else "not_running")
	if not host_alive:
		if not bool(AppState.settings.get("worldHost", false)):
			# The setting is off (a host was running at start and stopped because
			# of it): no host will come, so the buddy stays with you.
			_stay_with_you(now)
		elif now >= _next_respawn and now - _awake_since >= Whereabouts.STALE_SECONDS:
			# The host stopped while this app is open: start it again, at most once
			# every HOST_RESPAWN_SECONDS. A new host replaces a dead one's lock.
			# Not straight after the PC wakes up: the old host gets time to tick
			# again first, so there are never two.
			_spawn_host()
			_next_respawn = now + HOST_RESPAWN_SECONDS
	if _visiting:
		_poll_visiting(now)
	else:
		_poll_away(now, host, host_alive)


# No host to hand the buddy over: it stays with you for now. Its land life is
# paused (tick_mind does nothing for the desktop).
func _stay_with_you(now: float) -> void:
	if _visiting:
		return
	if Whereabouts.try_acquire(_base, "desktop", _pid, now, now - _awake_since):
		AppState.take_buddy()
		# It is visiting you like any other time, so the visit can be finished
		# properly when it ends (see _go_home).
		if not _buddy_is_visiting():
			AppState.mind_leave_for_visit(int(now), "opened")
		_visiting = true
		_opened_sent = true
		_set_state("visiting", "")
		_write_desktop(now)
		arrived.emit("opened")


func _poll_away(now: float, host: Dictionary, host_alive: bool) -> void:
	if host_alive and not _opened_sent:
		_opened_sent = true
		Whereabouts.send_request(_base, "call_over", {"reason": "opened"}, now)
	var host_state := str(host.get("state", ""))
	if _host_must_take_back and host_state != "visiting":
		_host_must_take_back = false
	if host_alive:
		var host_answer_variant = host.get("answer", {})
		if typeof(host_answer_variant) == TYPE_DICTIONARY:
			var host_answer: Dictionary = host_answer_variant
			var answer_id := str(host_answer.get("id", ""))
			if answer_id != "" and answer_id != _last_answer_id:
				_last_answer_id = answer_id
				answer.emit(str(host_answer.get("come", "")), int(host_answer.get("at", 0)), str(host_answer.get("why", "")))
	if host_alive and host_state == "visiting" and not _host_must_take_back:
		if Whereabouts.try_acquire(_base, "desktop", _pid, now, now - _awake_since):
			AppState.take_buddy()
			_visiting = true
			_last_interaction = now
			_set_state("visiting", "")
			_write_desktop(now)
			# arrived is the overlay's cue to re-apply the content pack: the item
			# catalogue is rebuilt from the pack and is not in the save.
			arrived.emit(str(host.get("reason", "called")))
			return
	if now - _last_refresh >= AWAY_REFRESH_SECONDS:
		_last_refresh = now
		AppState.reload_buddy_read_only()


func _poll_visiting(now: float) -> void:
	if AppState.mind_is_bedtime(int(now)):
		_go_home("bedtime")
	elif now - _last_interaction >= QUIET_SECONDS:
		_go_home("quiet")


func _go_home(reason: String) -> void:
	left.emit(reason)
	var now := Time.get_unix_time_from_system()
	var host := Whereabouts.read_status("%s/host.json" % _base)
	# With no host to take it back (the setting is off, so the host stops, or no
	# host is running), the visit ends here. Otherwise the save would say
	# "visiting" with nobody to finish it, and the next run would count the
	# visit as time on its land.
	if should_finish_here(bool(AppState.settings.get("worldHost", false)), Whereabouts.is_alive(host, now)) and _buddy_is_visiting():
		AppState.mind_return_from_visit(int(now), reason)
	AppState.release_buddy()
	Whereabouts.release(_base, "desktop", _pid)
	_visiting = false
	_host_must_take_back = true
	_last_refresh = 0.0
	_set_state("sent_home", reason)
	_write_desktop(Time.get_unix_time_from_system())
