extends Node

# The buddy writes back (Plan 14 step 2c-2). A letter of yours it has read and not
# answered, and its first letter once it has worked the glowing box out, are
# written here with the larger model from what the buddy remembers, checked
# against its memory like chat (MindThinker.check_reply), and put in the
# mailbox. A letter can take minutes, so this is slow by design.
#
# Only the process that has the buddy at home writes: the world host while it
# holds the buddy, and the app in solo mode (AppState.letters_may_write). The
# world host and the overlay each add one of these; the desktop app while the
# buddy is visiting it never writes. Land world only.
#
# One request at a time. A failed request is tried again after RETRY_SECONDS and
# the work stays due. The handlers are plain functions of the answer, so a test
# can call them without a network.

const MindThinker = preload("res://scripts/services/mind_thinker.gd")
const MemoryService = preload("res://scripts/services/memory_service.gd")

const POLL_SECONDS := 15
# A larger model may have to load first.
const LETTER_TIMEOUT_SECONDS := 240.0
const RETRY_SECONDS := 300
# After an answer that arrived when it may no longer write: the next holder writes it.
const DROPPED_WAIT_SECONDS := 60
const DEFAULT_LETTER_MODEL := "gemma3:12b"

var _timer: Timer
var _http: HTTPRequest = null
var _memory_http: HTTPRequest = null
# The letter request in flight: {"work", "model", "body", "extra", "retried"}. Empty when none.
var _pending: Dictionary = {}
# The memory request in flight: {"body"}. Empty when none.
var _memory_pending: Dictionary = {}
var _next_try := 0.0
# After a 404 (the letter model is not installed) the chat model, for the rest of
# this process.
var _fallback_model := ""


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.one_shot = false
	_timer.timeout.connect(_poll)
	add_child(_timer)
	_timer.start()


# Whether this process may write letters now, and the model is on.
func _can_write() -> bool:
	if not AppState.letters_may_write():
		return false
	if not bool(AppState.settings.get("mindModelEnabled", true)):
		return false
	if str(AppState.settings.get("chatBackend", "ollama")) != "ollama":
		return false
	return _url() != ""


func _url() -> String:
	return MindThinker.endpoint(str(AppState.settings.get("mindModelUrl", MindThinker.DEFAULT_URL)))


func _chat_model() -> String:
	return str(AppState.settings.get("chatModelName", AppState.settings.get("mindModelName", MindThinker.DEFAULT_MODEL)))


func _letter_model() -> String:
	if _fallback_model != "":
		return _fallback_model
	return str(AppState.settings.get("letterModelName", DEFAULT_LETTER_MODEL))


func _poll() -> void:
	if not _pending.is_empty() or not _memory_pending.is_empty():
		return
	if Time.get_unix_time_from_system() < _next_try:
		return
	if not _can_write():
		return
	var work: Dictionary = AppState.letters_next_work()
	if work.is_empty():
		return
	_begin(work, "", false)


# Sets up the request for `work` and sends it on the next idle moment (a request
# started from inside request_completed never completes, so the handlers only
# set the state).
func _begin(work: Dictionary, extra_task: String, retried: bool) -> void:
	var model: String = _letter_model()
	_pending = {"work": work, "model": model, "body": AppState.letters_request_body(model, work, extra_task), "extra": extra_task, "retried": retried}
	_dispatch_letter.call_deferred()


func _dispatch_letter() -> void:
	if _pending.is_empty():
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = LETTER_TIMEOUT_SECONDS
		_http.body_size_limit = MindThinker.MAX_REPLY_BYTES
		_http.max_redirects = 0
		_http.request_completed.connect(_on_letter_completed)
		add_child(_http)
	var error: int = _http.request(_url(), ["Content-Type: application/json"], HTTPClient.METHOD_POST, str(_pending["body"]))
	if error != OK:
		_pending = {}
		_next_try = Time.get_unix_time_from_system() + RETRY_SECONDS


func _on_letter_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var pending: Dictionary = _pending
	_pending = {}
	if pending.is_empty():
		return
	var now: float = Time.get_unix_time_from_system()
	# Handed over, or the setting changed, while it was thinking: the next holder
	# writes it.
	if not AppState.letters_may_write():
		_next_try = now + DROPPED_WAIT_SECONDS
		return
	var work: Dictionary = pending["work"]
	# The letter model is not installed: use the chat model from now on, and ask
	# again at once. (If that was the model already, there is nothing to switch to.)
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 404:
		var chat: String = _chat_model()
		if MindThinker.model_name(chat) != MindThinker.model_name(str(pending.get("model", ""))):
			_fallback_model = chat
			_begin(work, str(pending.get("extra", "")), bool(pending.get("retried", false)))
			return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_next_try = now + RETRY_SECONDS
		return
	var first: bool = str(work.get("kind", "")) != "reply"
	var their: String = "" if first else str((work["letter"] as Dictionary).get("text", ""))
	var known: Dictionary = AppState.memory_known_words()
	# A reply that cannot be read counts as a failed check with nothing named.
	var parsed: Dictionary = MindThinker.parse_letter_reply(body.get_string_from_utf8())
	var written := ""
	var unknown: Array = []
	var premise := false
	var passed := false
	if bool(parsed.get("ok", false)):
		written = str(parsed["letter"])
		var checked: Dictionary = MindThinker.check_reply(written, their, known)
		passed = bool(checked.get("ok", false))
		unknown = checked.get("unknown", [])
		premise = bool(checked.get("premise", false))
	if passed:
		_store(work, written, their)
		return
	if not bool(pending.get("retried", false)):
		_begin(work, MindThinker.honest_retry_note(unknown, premise), true)
		return
	_store(work, MindThinker.letter_fallback(their, unknown, known, first), their)


# Puts the letter in the mailbox, and for a reply sends the talk to memory.
func _store(work: Dictionary, written: String, their: String) -> void:
	AppState.letters_store_written(work, written)
	if str(work.get("kind", "")) != "reply":
		return
	if not AppState.memory_enabled() or MemoryService.looks_like_orders(their):
		return
	var body: String = MindThinker.build_memory_request(_chat_model(), [{"who": "them", "text": their}, {"who": "you", "text": written}])
	_memory_pending = {"body": body}
	_dispatch_memory.call_deferred()


func _dispatch_memory() -> void:
	if _memory_pending.is_empty():
		return
	var url: String = _url()
	if url == "":
		_memory_pending = {}
		return
	if _memory_http == null:
		_memory_http = HTTPRequest.new()
		_memory_http.timeout = LETTER_TIMEOUT_SECONDS
		_memory_http.body_size_limit = MindThinker.MAX_REPLY_BYTES
		_memory_http.max_redirects = 0
		_memory_http.request_completed.connect(_on_memory_completed)
		add_child(_memory_http)
	if _memory_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, str(_memory_pending["body"])) != OK:
		_memory_pending = {}


# What the buddy takes from the letter, kept like what it takes from a talk. A
# failure is dropped, not tried again: the letters themselves stay in the mailbox.
func _on_memory_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_memory_pending = {}
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	if not AppState.letters_may_write() or not AppState.memory_enabled():
		return
	var parsed: Dictionary = MindThinker.parse_memory_reply(body.get_string_from_utf8())
	if not bool(parsed.get("ok", false)):
		return
	# upto 0: no chat turns are dropped (a letter is not a chat turn).
	AppState.memory_apply_consolidation(parsed.get("facts", []), str(parsed.get("summary", "")), 0)
