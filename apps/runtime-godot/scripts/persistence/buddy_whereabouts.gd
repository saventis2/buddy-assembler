extends RefCounted

# Where the buddy is, for the world host and the desktop app (Plan 14 step 2a).
# The buddy is in one place at a time: whoever holds the lock directory
# "<base>/buddy.lock" is the only process that writes profile.json and
# world_state.json. Each side also writes a status file of its own (host.json,
# desktop.json) and the desktop leaves requests for the host in "<base>/inbox".
# Everything takes the base folder, so tests can use a folder of their own.

const SaveStore = preload("res://scripts/persistence/save_store.gd")

const DEFAULT_BASE := "user://host"
const HEARTBEAT_SECONDS := 15
const STALE_SECONDS := 90
const LOCK_NAME := "buddy.lock"
const OWNER_FILE := "owner.json"
const INBOX_NAME := "inbox"

# Replaceable by a test: returns whether a process with this id is running.
static var process_check: Callable = Callable()


static func lock_path(base: String) -> String:
	return "%s/%s" % [base, LOCK_NAME]


static func _owner_path(base: String) -> String:
	return "%s/%s" % [lock_path(base), OWNER_FILE]


static func holder(base: String = DEFAULT_BASE) -> Dictionary:
	return read_status(_owner_path(base))


static func holds(base: String, role: String, pid: int) -> bool:
	var owner := holder(base)
	return not owner.is_empty() and str(owner.get("role", "")) == role and int(owner.get("pid", -1)) == pid


# Whether a process with this id is running (tests replace the check with
# process_check). Used before breaking a lock, and to tell a second copy of the
# app from a status file left behind by a crash.
static func is_running(pid: int) -> bool:
	return _process_is_running(pid)


static func _process_is_running(pid: int) -> bool:
	if process_check.is_valid():
		return bool(process_check.call(pid))
	if pid <= 0:
		return false
	if OS.get_name() != "Windows":
		# Not checked elsewhere: fall back on the heartbeat alone.
		return true
	var output: Array = []
	var code := OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], output)
	if code != OK:
		return true
	for chunk in output:
		if str(chunk).contains("\"%d\"" % pid):
			return true
	return false


static func _write_owner(base: String, role: String, pid: int, since: float, now: float) -> void:
	SaveStore.write_json(_owner_path(base), {"role": role, "pid": pid, "since": since, "heartbeat": now})


static func try_acquire(base: String, role: String, pid: int, now: float, breaker_awake_seconds: float) -> bool:
	var lock := lock_path(base)
	if not DirAccess.dir_exists_absolute(base):
		DirAccess.make_dir_recursive_absolute(base)
	if DirAccess.make_dir_absolute(lock) == OK:
		_write_owner(base, role, pid, now, now)
		return true
	var owner := holder(base)
	var may_break := false
	if owner.is_empty():
		# A lock with no readable owner may just be mid-creation: only a stale
		# one (by the folder's own age) is broken.
		may_break = breaker_awake_seconds >= STALE_SECONDS and now - float(FileAccess.get_modified_time(lock)) > STALE_SECONDS
	else:
		var heartbeat := float(owner.get("heartbeat", 0.0))
		if now - heartbeat > STALE_SECONDS and breaker_awake_seconds >= STALE_SECONDS:
			may_break = true
		elif not _process_is_running(int(owner.get("pid", 0))):
			may_break = true
	if not may_break:
		return false
	_remove_lock(base)
	if DirAccess.make_dir_absolute(lock) == OK:
		_write_owner(base, role, pid, now, now)
		return true
	return false


static func _remove_lock(base: String) -> void:
	DirAccess.remove_absolute(_owner_path(base))
	DirAccess.remove_absolute(lock_path(base))


static func heartbeat(base: String, role: String, pid: int, now: float) -> void:
	var owner := holder(base)
	if owner.is_empty() or str(owner.get("role", "")) != role or int(owner.get("pid", -1)) != pid:
		return
	_write_owner(base, role, pid, float(owner.get("since", now)), now)


static func release(base: String, role: String, pid: int) -> bool:
	if not holds(base, role, pid):
		return false
	_remove_lock(base)
	return not DirAccess.dir_exists_absolute(lock_path(base))


# Status files. A missing or damaged file reads as {} and is never renamed:
# the process that wrote it may be in the middle of replacing it.
static func write_status(path: String, data: Dictionary) -> bool:
	return SaveStore.write_json(path, data)


static func read_status(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(raw)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func is_alive(status: Dictionary, now: float) -> bool:
	if status.is_empty():
		return false
	return now - float(status.get("heartbeat", 0.0)) <= STALE_SECONDS


# Requests from the desktop to the host: one file each in "<base>/inbox".
static func send_request(base: String, kind: String, data: Dictionary, now: float) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var token := "%08x" % rng.randi()
	var stamp := int(now)
	var id := "%d-%s" % [stamp, token]
	var request := data.duplicate(true)
	request["id"] = id
	request["kind"] = kind
	request["t"] = stamp
	SaveStore.write_json("%s/%s/%s.json" % [base, INBOX_NAME, id], request)
	return id


# Reads, deletes and returns the waiting requests, oldest name first.
static func take_requests(base: String) -> Array:
	var rows: Array = []
	var folder := "%s/%s" % [base, INBOX_NAME]
	if not DirAccess.dir_exists_absolute(folder):
		return rows
	var names: Array = []
	for file_name in DirAccess.get_files_at(folder):
		if file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		var path := "%s/%s" % [folder, file_name]
		var request := read_status(path)
		DirAccess.remove_absolute(path)
		if not request.is_empty():
			rows.append(request)
	return rows
