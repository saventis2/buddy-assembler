extends Node

# The world host and the visit (Plan 14 step 2a-1): who holds the buddy, what a
# visit does to it, and who may write which save file. Everything this test
# writes goes under ROOT. No real process is started; the one real AppState case
# runs in simulation, so nothing is saved.

const SaveStore = preload("res://scripts/persistence/save_store.gd")
const Whereabouts = preload("res://scripts/persistence/buddy_whereabouts.gd")
const MindService = preload("res://scripts/services/mind_service.gd")
const LifeSim = preload("res://tests/life_sim.gd")
const ContentLoader = preload("res://scripts/content/content_loader.gd")
const VisitController = preload("res://scripts/visit_controller.gd")
const BuddyOverlayScript = preload("res://scripts/buddy_overlay.gd")
const WorldHostScript = preload("res://scripts/world_host.gd")


# Stands in for the overlay's visit controller: whether the buddy is here.
class StubVisit extends Node:
	var here := false

	func is_visiting() -> bool:
		return here

const ROOT := "user://world_host_test"
const MINI_LAND := {
	"home_place": "home",
	"paths": [],
	"tails": {"good": ["Good."], "bad": ["Bad."]},
	"places": [
		{"id": "home", "name": "the house", "opens": 0, "closes": 24, "distance": 0, "residents": [],
			"activities": [
				{"id": "sleep", "label": "went to bed", "satisfies": "energy", "until_hour": 6, "hours": [19, 5], "lines": ["I slept."]},
				{"id": "nap", "label": "had a nap", "satisfies": "energy", "minutes": 40, "hours": [5, 19], "lines": ["I napped."]},
				{"id": "tidy", "label": "tidied up", "satisfies": "comfort", "lines": ["I tidied."]},
				{"id": "think", "label": "sat and thought", "satisfies": "reflection", "lines": ["I thought."]},
				{"id": "look", "label": "looked about", "satisfies": "curiosity", "lines": ["I looked about."]},
			],
			"sights": []},
	],
}

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("world_host_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("world_host_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_wipe(ROOT)
	_case("lock_is_held_by_one", func(): return _test_lock_is_held_by_one())
	_case("only_the_owner_releases", func(): return _test_only_the_owner_releases())
	_case("stale_lock_waits_for_an_awake_breaker", func(): return _test_stale_lock())
	_case("dead_owner_is_replaced_at_once", func(): return _test_dead_owner())
	_case("requests_are_taken_once_in_order", func(): return _test_requests())
	_case("call_now_later_asleep", func(): return _test_call_now_later_asleep())
	_case("visit_round_trip", func(): return _test_visit_round_trip())
	_case("return_without_a_visit_is_safe", func(): return _test_return_without_a_visit())
	_case("lonely_when_due", func(): return _test_lonely_when_due())
	_case("bedtime", func(): return _test_bedtime())
	_case("company_fades_on_the_land", func(): return _test_company_fades())
	_case("only_the_holder_writes", func(): return _test_only_the_holder_writes())
	_case("a_lost_lock_stops_writes", func(): return _test_a_lost_lock_stops_writes())
	_case("the_visit_ends_here_without_a_host", func(): return _test_the_visit_ends_here_without_a_host())
	_case("a_host_needs_both_settings", func(): return _test_a_host_needs_both_settings())
	_case("no_host_wanted_keeps_the_visit", func(): return _test_no_host_wanted_keeps_the_visit())
	_case("peek_never_writes", func(): return _test_peek_never_writes())
	_case("solo_is_unchanged", func(): return _test_solo_is_unchanged())
	_case("bedtime_call_waits_for_morning", func(): return _test_bedtime_call_waits_for_morning())
	_case("new_buddy_has_company", func(): return _test_new_buddy_has_company())
	_case("only_a_real_launch_is_the_desktop", func(): return _test_only_a_real_launch_is_the_desktop())
	_case("on_by_default", func(): return _test_on_by_default())
	_case("still_world_after_hours", func(): return _test_still_world_after_hours())
	_case("just_woke_comes_now", func(): return _test_just_woke_comes_now())
	_case("chose_name_line", func(): return _test_chose_name_line())
	# Last: it puts this process into simulation and the desktop role aside.
	_case("a_simulation_is_solo", func(): return _test_a_simulation_is_solo())
	_case("a_visit_that_ends_drops_model_work", func(): return _test_visit_end_drops_model_work())
	_case("a_visit_answers_a_waiting_call", func(): return _test_hand_over_clears_pending())
	Whereabouts.process_check = Callable()
	_wipe(ROOT)


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("world_host_test[%s]: %s" % [name, err])
	else:
		print("world_host_test[%s]: ok" % name)


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


func _fresh_base(name: String) -> String:
	var base := "%s/%s" % [ROOT, name]
	_wipe(base)
	return base


func _processes_running(running: bool) -> void:
	Whereabouts.process_check = func(_pid: int) -> bool: return running


func _service() -> MindService:
	var svc := MindService.new()
	svc.set_time_zone_bias_minutes(0)
	return svc


func _midnight() -> int:
	return LifeSim.DEFAULT_START_UNIX


func _profile(strain: float = 0.2, company: float = 0.0) -> Dictionary:
	return {
		"personality_seed": 1,
		"personality_seed_tag": "curious",
		"mood_modifiers": {"energy_strain": strain, "social_fulfillment": company, "comfort": 0.5, "confidence": 0.5},
	}


func _land() -> Dictionary:
	return MINI_LAND.duplicate(true)


func _journal_texts(profile: Dictionary) -> Array:
	var texts: Array = []
	for entry in (profile["mind"] as Dictionary)["journal"]:
		texts.append(str((entry as Dictionary).get("text", "")))
	return texts


func _test_lock_is_held_by_one() -> Variant:
	var base := _fresh_base("lock")
	_processes_running(true)
	if not Whereabouts.try_acquire(base, "host", 111, 1000.0, 0.0):
		return "the host could not take a free lock"
	if Whereabouts.try_acquire(base, "desktop", 222, 1000.0, 0.0):
		return "the desktop took a lock the host holds"
	if not Whereabouts.holds(base, "host", 111) or Whereabouts.holds(base, "desktop", 222):
		return "holds() disagrees with who acquired"
	if not Whereabouts.release(base, "host", 111):
		return "the host could not release its own lock"
	if not Whereabouts.try_acquire(base, "desktop", 222, 1001.0, 0.0):
		return "the desktop could not take the lock after the host released it"
	if str(Whereabouts.holder(base).get("role", "")) != "desktop":
		return "the holder is not the desktop"
	return null


func _test_only_the_owner_releases() -> Variant:
	var base := _fresh_base("release")
	_processes_running(true)
	Whereabouts.try_acquire(base, "host", 111, 1000.0, 0.0)
	if Whereabouts.release(base, "desktop", 111):
		return "the wrong role released the lock"
	if Whereabouts.release(base, "host", 222):
		return "the wrong pid released the lock"
	if not Whereabouts.holds(base, "host", 111):
		return "the lock was lost to a refused release"
	if not Whereabouts.release(base, "host", 111):
		return "the owner could not release"
	if DirAccess.dir_exists_absolute(Whereabouts.lock_path(base)):
		return "the lock folder is still there after release"
	return null


func _test_stale_lock() -> Variant:
	var base := _fresh_base("stale")
	_processes_running(true)
	Whereabouts.try_acquire(base, "host", 111, 1000.0, 0.0)
	var later := 1000.0 + Whereabouts.STALE_SECONDS + 10.0
	if Whereabouts.try_acquire(base, "desktop", 222, later, Whereabouts.STALE_SECONDS - 1.0):
		return "a breaker that had not been awake long enough broke a stale lock"
	if not Whereabouts.holds(base, "host", 111):
		return "the host lost its lock to a breaker that had to wait"
	if not Whereabouts.try_acquire(base, "desktop", 222, later, float(Whereabouts.STALE_SECONDS)):
		return "an awake breaker could not break a stale lock"
	if not Whereabouts.holds(base, "desktop", 222):
		return "the desktop does not hold the lock it broke"
	# A live holder is never broken.
	Whereabouts.heartbeat(base, "desktop", 222, later)
	if Whereabouts.try_acquire(base, "host", 111, later + 5.0, 1000.0):
		return "a live holder's lock was broken"
	return null


func _test_dead_owner() -> Variant:
	var base := _fresh_base("dead")
	_processes_running(false)
	Whereabouts.try_acquire(base, "host", 111, 1000.0, 0.0)
	if not Whereabouts.try_acquire(base, "desktop", 222, 1001.0, 0.0):
		return "a lock held by a process that is gone was not replaced at once"
	if not Whereabouts.holds(base, "desktop", 222):
		return "the desktop does not hold the replaced lock"
	_processes_running(true)
	return null


func _test_requests() -> Variant:
	var base := _fresh_base("requests")
	var first := Whereabouts.send_request(base, "call_over", {"reason": "opened"}, 1000.0)
	var second := Whereabouts.send_request(base, "call_over", {"reason": "called"}, 1001.0)
	var third := Whereabouts.send_request(base, "call_over", {"reason": "called"}, 1002.0)
	if first == "" or first == second or second == third:
		return "request ids are empty or repeat"
	var taken := Whereabouts.take_requests(base)
	if taken.size() != 3:
		return "took %d requests, expected 3" % taken.size()
	var ids: Array = []
	for row in taken:
		ids.append(str((row as Dictionary).get("id", "")))
	if ids != [first, second, third]:
		return "requests came out of order: %s" % [ids]
	if str((taken[0] as Dictionary).get("reason", "")) != "opened" or str((taken[0] as Dictionary).get("kind", "")) != "call_over":
		return "a request lost its contents"
	if not Whereabouts.take_requests(base).is_empty():
		return "a request was taken twice"
	return null


func _test_call_now_later_asleep() -> Variant:
	var svc := _service()
	var now := _midnight() + 12 * 3600
	var free: Dictionary = svc.consider_call(_profile(), _land(), now)
	if str(free.get("come", "")) != "now":
		return "a free buddy answered %s" % [free]
	var busy_profile := svc.ensure_profile(_profile())
	var mind: Dictionary = busy_profile["mind"]
	mind["journal"] = [{"t": now - 600, "place_id": "home", "activity_id": "nap", "text": "I napped."}]
	mind["busy_until"] = now + 1200
	busy_profile["mind"] = mind
	var busy: Dictionary = svc.consider_call(busy_profile, _land(), now)
	if str(busy.get("come", "")) != "later" or int(busy.get("at", 0)) != now + 1200 or str(busy.get("why", "")) != "had a nap":
		return "a busy buddy answered %s" % [busy]
	var asleep_profile := busy_profile.duplicate(true)
	var sleeping: Dictionary = asleep_profile["mind"]
	sleeping["journal"] = [{"t": now - 600, "place_id": "home", "activity_id": "sleep", "text": "I slept."}]
	sleeping["busy_until"] = now + 5 * 3600
	asleep_profile["mind"] = sleeping
	var asleep: Dictionary = svc.consider_call(asleep_profile, _land(), now)
	if str(asleep.get("come", "")) != "asleep" or int(asleep.get("at", 0)) != now + 5 * 3600:
		return "a sleeping buddy answered %s" % [asleep]
	if svc.consider_call(busy_profile, _land(), now + 1200).get("come", "") != "now":
		return "a buddy whose time is up was still busy"
	return null


# Handing the buddy over, for a newer call or any other reason, also answers an
# older call it told "later": after Send home, that old call must not bring it
# straight back.
func _test_hand_over_clears_pending() -> Variant:
	var start := LifeSim.DEFAULT_START_UNIX
	if not AppState.begin_simulation(2, start):
		return "begin_simulation refused"
	var base := "%s/hand_over" % ROOT
	_wipe(base)
	var host = WorldHostScript.new()
	host._base = base
	host._pending = {"id": "1-aaaaaaaa", "reason": "called", "at": start - 60}
	host._hand_over(float(start), "called")
	var left: Dictionary = host._pending
	host.free()
	_wipe(base)
	if not left.is_empty():
		return "a visit should answer the call that was waiting: %s" % [left]
	return null


# Sent home while the model was thinking: the request is cancelled, and an
# answer that still arrives is not said or used, because the buddy (and its
# profile) is the host's now.
func _test_visit_end_drops_model_work() -> Variant:
	var overlay = BuddyOverlayScript.new()
	var http := HTTPRequest.new()
	var visit := StubVisit.new()
	overlay._chat_http = http
	overlay._visit = visit
	var err := ""
	overlay._chat_pending = {"kind": "chat", "user_text": "hello"}
	overlay._drop_model_work()
	if not (overlay._chat_pending as Dictionary).is_empty():
		err = "the reply on its way was not dropped when the visit ended"
	if err == "":
		overlay._chat_pending = {"kind": "name"}
		var reply := JSON.stringify({"message": {"content": JSON.stringify({"reply": "Hello!", "name": "Pip"})}})
		overlay._on_chat_http_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), reply.to_utf8_buffer())
		if not (overlay._chat_turns as Array).is_empty() or not (overlay._chat_pending as Dictionary).is_empty():
			err = "an answer that came after the buddy went home was used"
	http.free()
	visit.free()
	overlay.free()
	return null if err == "" else err


func _test_visit_round_trip() -> Variant:
	var svc := _service()
	var land := _land()
	var left := _midnight() + 9 * 3600
	var back := left + 3 * 3600
	var away: Dictionary = svc.leave_for_visit(_profile(0.2, 0.0), land, left, "lonely")
	var mind: Dictionary = away["mind"]
	if str(mind["location"]) != "visiting" or int(mind["busy_until"]) != 0 or int(mind["visit_left_unix"]) != left or str(mind["visit_reason"]) != "lonely":
		return "leaving did not set the visit: %s" % [mind]
	var leave_entry: Dictionary = (mind["journal"] as Array)[0]
	if str(leave_entry["text"]) != "It was too quiet on my own, so I went to see you." or str(leave_entry["place_id"]) != "visiting" or str(leave_entry["activity_id"]) != "visit_you" or str(leave_entry["intent"]) != "visit":
		return "the leaving entry is wrong: %s" % [leave_entry]
	var home: Dictionary = svc.return_from_visit(away, land, back, "bedtime")
	var home_mind: Dictionary = home["mind"]
	if str(home_mind["location"]) != "home":
		return "it did not come home: %s" % str(home_mind["location"])
	var texts := _journal_texts(home)
	if texts != ["It was too quiet on my own, so I went to see you.", "I walked home from your desk and got ready for bed."]:
		return "journal texts are %s" % [texts]
	var came: Dictionary = (home_mind["journal"] as Array)[1]
	if str(came["intent"]) != "tend_home" or str(came["activity_id"]) != "came_home" or str(came["place_id"]) != "home":
		return "the homecoming entry is wrong: %s" % [came]
	var strain := float(home["mood_modifiers"]["energy_strain"])
	var want_strain := 0.2 + 18.0 * MindService.LAND_TIRE_PER_SLOT
	if not is_equal_approx(strain, want_strain):
		return "tiredness is %s, expected %s (18 slots)" % [str(strain), str(want_strain)]
	if not is_equal_approx(float(home["mood_modifiers"]["social_fulfillment"]), 1.0):
		return "company should have been clamped to 1.0, got %s" % str(home["mood_modifiers"]["social_fulfillment"])
	if int(home_mind["last_decision_unix"]) != back or int(home_mind["last_visit_end_unix"]) != back or int(home_mind["visit_left_unix"]) != 0 or int(home_mind["busy_until"]) != 0:
		return "the visit's bookkeeping is wrong: %s" % [home_mind]
	var context := {"small_beginnings": true, "plans": true, "hour": 12, "is_night": false}
	var ticked: Dictionary = svc.tick(home, [], back, context, land)
	if (ticked["events"] as Array).size() > 1:
		return "it made %d decisions right after coming home" % (ticked["events"] as Array).size()
	# Even much later, the three hours away are not made up.
	var later: Dictionary = svc.tick(home, [], back + 600, context, land)
	if (later["events"] as Array).size() > 1:
		return "it caught up on the visit: %d decisions" % (later["events"] as Array).size()
	return null


func _test_return_without_a_visit() -> Variant:
	var svc := _service()
	var now := _midnight() + 12 * 3600
	var home: Dictionary = svc.return_from_visit(_profile(0.3, 0.1), _land(), now, "lost")
	var mind: Dictionary = home["mind"]
	if str(mind["location"]) != "home" or int(mind["last_decision_unix"]) != now:
		return "it did not come home safely: %s" % [mind]
	if not is_equal_approx(float(home["mood_modifiers"]["energy_strain"]), 0.3) or not is_equal_approx(float(home["mood_modifiers"]["social_fulfillment"]), 0.1):
		return "needs moved with no visit: %s" % [home["mood_modifiers"]]
	if _journal_texts(home) != ["I found my way home from your desk."]:
		return "journal texts are %s" % [_journal_texts(home)]
	return null


func _test_lonely_when_due() -> Variant:
	var svc := _service()
	var land := _land()
	var noon := _midnight() + 12 * 3600
	var lonely := _profile(0.2, 0.1)
	if not svc.wants_company(lonely, land, noon):
		return "a lonely, free buddy by day with no recent visit did not want company"
	var busy := svc.ensure_profile(lonely)
	var busy_mind: Dictionary = busy["mind"]
	busy_mind["busy_until"] = noon + 100
	busy["mind"] = busy_mind
	if svc.wants_company(busy, land, noon):
		return "a busy buddy wanted company"
	if svc.wants_company(lonely, land, _midnight() + 3 * 3600):
		return "it wanted company at night"
	if svc.wants_company(lonely, land, _midnight() + 20 * 3600):
		return "it wanted company at 20:00"
	if svc.wants_company(_profile(0.2, 0.5), land, noon):
		return "a buddy with company wanted more"
	var recent := svc.ensure_profile(lonely)
	var recent_mind: Dictionary = recent["mind"]
	recent_mind["last_visit_end_unix"] = noon - 3600
	recent["mind"] = recent_mind
	if svc.wants_company(recent, land, noon):
		return "it wanted company an hour after a visit"
	recent_mind["last_visit_end_unix"] = noon - MindService.SELF_VISIT_GAP_SECONDS
	recent["mind"] = recent_mind
	if not svc.wants_company(recent, land, noon):
		return "it did not want company once the gap had passed"
	return null


func _test_bedtime() -> Variant:
	var svc := _service()
	var day := _midnight()
	if not svc.is_bedtime(_profile(0.0), day + 22 * 3600):
		return "22:00 was not bedtime"
	if not svc.is_bedtime(_profile(0.0), day + 21 * 3600):
		return "21:00 was not bedtime"
	if not svc.is_bedtime(_profile(0.0), day + 3 * 3600):
		return "03:00 was not bedtime"
	if svc.is_bedtime(_profile(0.0), day + 5 * 3600):
		return "05:00 was bedtime"
	if svc.is_bedtime(_profile(0.95), day + 12 * 3600):
		return "a tired buddy at noon was sent to bed"
	if svc.is_bedtime(_profile(0.44), day + 19 * 3600):
		return "19:00 and not tired enough was bedtime"
	if not svc.is_bedtime(_profile(0.45), day + 19 * 3600):
		return "19:00 and tired enough was not bedtime"
	if svc.is_bedtime(_profile(0.9), day + 18 * 3600):
		return "18:00 was bedtime"
	# Its time on a visit counts: 6 slots on 0.42 is more than 0.45.
	var visiting := svc.leave_for_visit(_profile(0.42), _land(), day + 18 * 3600, "called")
	var at_19 := day + 19 * 3600
	var mind: Dictionary = visiting["mind"]
	mind["visit_left_unix"] = at_19 - 3600
	visiting["mind"] = mind
	if not svc.is_bedtime(visiting, at_19):
		return "the time on a visit did not count toward being tired"
	mind["visit_left_unix"] = 0
	visiting["mind"] = mind
	if svc.is_bedtime(visiting, at_19):
		return "it was bedtime at 0.42 with no visit time"
	return null


func _test_company_fades() -> Variant:
	var svc := _service()
	var awake := {"energy_strain": 0.2, "social_fulfillment": 0.8, "comfort": 0.5, "confidence": 0.5}
	svc._apply_land_needs(awake, {"id": "look", "satisfies": "curiosity"}, 10, 0.0, "")
	var want := 0.8 - 10.0 * MindService.LAND_COMPANY_FADE_PER_SLOT
	if not is_equal_approx(float(awake["social_fulfillment"]), want):
		return "company after 10 awake slots is %s, expected %s" % [str(awake["social_fulfillment"]), str(want)]
	var asleep := {"energy_strain": 0.5, "social_fulfillment": 0.8, "comfort": 0.5, "confidence": 0.5}
	svc._apply_land_needs(asleep, {"id": "sleep", "satisfies": "energy", "until_hour": 6}, 30, 0.0, "")
	if not is_equal_approx(float(asleep["social_fulfillment"]), 0.8):
		return "company changed while asleep: %s" % str(asleep["social_fulfillment"])
	var empty := {"energy_strain": 0.2, "social_fulfillment": 0.02, "comfort": 0.5, "confidence": 0.5}
	svc._apply_land_needs(empty, {"id": "look", "satisfies": "curiosity"}, 10, 0.0, "")
	if float(empty["social_fulfillment"]) != 0.0:
		return "company went below zero: %s" % str(empty["social_fulfillment"])
	return null


func _test_only_the_holder_writes() -> Variant:
	var saved_role: String = AppState._role
	var saved_holding: bool = AppState._holding
	var saved_dir: String = AppState._host_dir
	var base := _fresh_base("may_write")
	var pid := OS.get_process_id()
	AppState._host_dir = base
	var paths := [AppState.SETTINGS_PATH, AppState.PROFILE_PATH, AppState.WORLD_STATE_PATH]
	# role, holding -> may write settings, profile, world state
	var table := [
		["solo", false, [true, true, true]],
		["solo", true, [true, true, true]],
		["host", false, [false, false, false]],
		["host", true, [false, true, true]],
		["desktop", false, [true, false, false]],
		["desktop", true, [true, true, true]],
	]
	var problem := ""
	for row in table:
		var role := str(row[0])
		var holding := bool(row[1])
		Whereabouts.release(base, "host", pid)
		Whereabouts.release(base, "desktop", pid)
		# Holding means holding the lock too (AppState._still_holding).
		if holding and role != "solo":
			Whereabouts.try_acquire(base, role, pid, Time.get_unix_time_from_system(), 0.0)
		AppState._role = role
		AppState._holding = holding
		for index in range(paths.size()):
			var got: bool = AppState._may_write(paths[index])
			if got != bool((row[2] as Array)[index]) and problem == "":
				problem = "role %s holding %s: _may_write(%s) is %s" % [role, str(holding), str(paths[index]), str(got)]
	Whereabouts.release(base, "host", pid)
	Whereabouts.release(base, "desktop", pid)
	AppState._role = saved_role
	AppState._holding = saved_holding
	AppState._host_dir = saved_dir
	return problem if problem != "" else null


# A holder whose lock was taken over (it froze for longer than the stale time,
# so the other side broke the lock) stops writing the buddy's files at once.
func _test_a_lost_lock_stops_writes() -> Variant:
	var saved_role: String = AppState._role
	var saved_holding: bool = AppState._holding
	var saved_dir: String = AppState._host_dir
	var base := _fresh_base("lost_lock")
	var pid := OS.get_process_id()
	var now := Time.get_unix_time_from_system()
	var problem := ""
	if not Whereabouts.try_acquire(base, "desktop", pid, now, 0.0):
		problem = "could not take the test lock"
	AppState._host_dir = base
	AppState._role = "desktop"
	AppState._holding = true
	if problem == "" and not AppState._may_write(AppState.PROFILE_PATH):
		problem = "the holder may not write its own buddy"
	if problem == "":
		# The host takes the lock over.
		SaveStore.write_json(Whereabouts.lock_path(base) + "/owner.json", {"role": "host", "pid": pid + 1, "since": now, "heartbeat": now})
		if AppState._may_write(AppState.PROFILE_PATH) or AppState._may_write(AppState.WORLD_STATE_PATH):
			problem = "a process whose lock was taken over still writes the buddy"
		elif AppState.is_holding_buddy():
			problem = "a process whose lock was taken over still says it holds the buddy"
		elif not AppState._may_write(AppState.SETTINGS_PATH):
			problem = "the app lost its own settings along with the lock"
	_wipe(base)
	AppState._role = saved_role
	AppState._holding = saved_holding
	AppState._host_dir = saved_dir
	return problem if problem != "" else null


# When the buddy goes home and no host will take it back (the setting is off,
# or no host is running), the app finishes the visit itself.
# The app wants a host only when both settings the host checks are on, so with
# small beginnings off it keeps the buddy instead of restarting hosts that stop.
func _test_a_host_needs_both_settings() -> Variant:
	if not VisitController.host_wanted({}):
		return "with the defaults a host should be wanted"
	if VisitController.host_wanted({"worldHost": false, "smallBeginnings": true}):
		return "with World host off no host should be wanted"
	if VisitController.host_wanted({"worldHost": true, "smallBeginnings": false}):
		return "with small beginnings off no host should be wanted"
	if not VisitController.host_wanted({"worldHost": true, "smallBeginnings": true}):
		return "with both on a host should be wanted"
	return null


# With no host wanted (the setting went off while the app is open) the buddy
# stays with you: bedtime and a long quiet do not end the visit, or the next
# poll would bring it straight back, every two seconds.
func _test_no_host_wanted_keeps_the_visit() -> Variant:
	if VisitController.visit_end_reason(false, true, VisitController.QUIET_SECONDS * 2.0) != "":
		return "with no host wanted, neither bedtime nor a long quiet should end the visit"
	if VisitController.visit_end_reason(true, true, 0.0) != "bedtime":
		return "with a host wanted, bedtime should end the visit"
	if VisitController.visit_end_reason(true, false, float(VisitController.QUIET_SECONDS)) != "quiet":
		return "with a host wanted, a long quiet should end the visit"
	if VisitController.visit_end_reason(true, false, VisitController.QUIET_SECONDS - 1.0) != "":
		return "otherwise the visit should go on"
	return null


func _test_the_visit_ends_here_without_a_host() -> Variant:
	if not VisitController.should_finish_here(false, true):
		return "with the setting off, the app must finish the visit itself"
	if not VisitController.should_finish_here(true, false):
		return "with no host running, the app must finish the visit itself"
	if VisitController.should_finish_here(true, true):
		return "with a host running, the host finishes the visit"
	return null


func _test_peek_never_writes() -> Variant:
	var base := _fresh_base("peek")
	DirAccess.make_dir_recursive_absolute(base)
	var damaged := base + "/damaged.json"
	var newer := base + "/newer.json"
	var good := base + "/good.json"
	_write(damaged, "{ this is not json")
	_write(newer, "{\"schemaVersion\": 99}")
	_write(good, "{\"schemaVersion\": 1, \"a\": 5}")
	var before := [FileAccess.get_md5(damaged), FileAccess.get_md5(newer), FileAccess.get_md5(good)]
	var factory := func() -> Dictionary: return {"schemaVersion": 1, "a": 0, "b": 7}
	if not SaveStore.peek_versioned(damaged, factory, 1, {}).is_empty():
		return "a damaged file did not read as {}"
	if not SaveStore.peek_versioned(newer, factory, 1, {}).is_empty():
		return "a newer file did not read as {}"
	if not SaveStore.peek_versioned(base + "/missing.json", factory, 1, {}).is_empty():
		return "a missing file did not read as {}"
	var read := SaveStore.peek_versioned(good, factory, 1, {})
	if int(read.get("a", 0)) != 5 or int(read.get("b", 0)) != 7:
		return "a good file was not read and merged: %s" % [read]
	var after := [FileAccess.get_md5(damaged), FileAccess.get_md5(newer), FileAccess.get_md5(good)]
	if before != after:
		return "a file changed after being peeked"
	for file_name in DirAccess.get_files_at(base):
		if file_name.contains(".corrupt-"):
			return "peeking quarantined a file: %s" % file_name
	if DirAccess.get_files_at(base).size() != 3:
		return "the folder has %d files, expected 3" % DirAccess.get_files_at(base).size()
	return null


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("world_host_test: cannot write %s" % path)
		return
	file.store_string(text)
	file.close()


# Called at its bedtime it does not come for a visit that would end at once:
# it says it will come at 07:00.
func _test_bedtime_call_waits_for_morning() -> Variant:
	var svc := _service()
	var night: Dictionary = svc.consider_call(_profile(), _land(), _midnight() + 22 * 3600)
	var next_morning := _midnight() + (24 + MindService.VISIT_MORNING_HOUR) * 3600
	if str(night.get("come", "")) != "asleep" or int(night.get("at", 0)) != next_morning:
		return "a free buddy called at 22:00 answered %s, not asleep until %d" % [night, next_morning]
	var early: Dictionary = svc.consider_call(_profile(), _land(), _midnight() + 3 * 3600)
	if int(early.get("at", 0)) != _midnight() + MindService.VISIT_MORNING_HOUR * 3600:
		return "called at 03:00 it should come at 07:00 the same morning: %s" % [early]
	if str(svc.consider_call(_profile(), _land(), _midnight() + 10 * 3600).get("come", "")) != "now":
		return "a free buddy called at 10:00 did not come now"
	return null


# A buddy that has just woken on the land is not lonely yet.
func _test_new_buddy_has_company() -> Variant:
	if not AppState.begin_simulation(3, LifeSim.DEFAULT_START_UNIX):
		return "begin_simulation refused"
	var result: Dictionary = AppState._fresh_start(false, [], ROOT + "/fresh/backups")
	if str(result.get("status", "")) != "started":
		return "the fresh start did not run: %s" % [result]
	var mods_variant = AppState.profile.get("mood_modifiers", {})
	var company := float((mods_variant as Dictionary).get("social_fulfillment", -1.0)) if typeof(mods_variant) == TYPE_DICTIONARY else -1.0
	if not is_equal_approx(company, MindService.LAND_START_COMPANY):
		return "a new buddy starts with company %s, not %s" % [company, MindService.LAND_START_COMPANY]
	if _service().wants_company(AppState.profile, _land(), _midnight() + 12 * 3600):
		return "a new buddy is lonely at once"
	return null


func _test_solo_is_unchanged() -> Variant:
	if AppState.role() != "solo":
		return "role is %s in a test process with the setting off and no host" % AppState.role()
	if AppState.is_holding_buddy():
		return "a solo process says it holds the buddy"
	# The test process ran a test scene, so it is solo although the setting is on
	# by default. (The default, not this machine's saved settings, which an
	# earlier run may have written either way.)
	if not bool(AppState._default_settings().get("worldHost", false)):
		return "worldHost is off by default"
	var start: int = LifeSim.DEFAULT_START_UNIX
	if not AppState.begin_simulation(2, start):
		return "begin_simulation refused"
	var loaded: Dictionary = ContentLoader.load_with_fallback("core_pack", "", false)
	AppState.apply_loaded_pack(str(loaded.get("pack_id", "core_pack")), loaded.get("manifest", {}))
	AppState.settings["smallBeginnings"] = true
	AppState.set_sim_clock(start + 9 * 3600)
	var events: Array = AppState.tick_mind(start + 9 * 3600)
	if events.is_empty():
		return "tick_mind made no decision in role solo"
	if AppState.role() != "solo":
		return "the role changed"
	return null


func _test_only_a_real_launch_is_the_desktop() -> Variant:
	var no := [
		[["--headless", "--quit"], []],
		[["--headless", "--quit-after", "2"], []],
		[["--path", "x", "res://tests/LifeSimTest.tscn"], []],
		[["-s", "res://x.gd"], []],
		[["--check-only"], []],
		[["--import"], []],
		[["--editor"], []],
		[["-e"], []],
		[["--path", "x"], ["--ci-startup-smoke"]],
		[["--path", "x"], ["--verify-export-closure"]],
	]
	for row in no:
		if AppState._is_real_launch_args(PackedStringArray(row[0]), PackedStringArray(row[1])):
			return "%s with user args %s counted as a real launch" % [row[0], row[1]]
	var yes := [
		[["--path", "x"], []],
		[["--path", "x", "res://scenes/LaunchRouter.tscn"], []],
		[["--path", "x"], ["--vertical-slice"]],
	]
	for row in yes:
		if not AppState._is_real_launch_args(PackedStringArray(row[0]), PackedStringArray(row[1])):
			return "%s with user args %s did not count as a real launch" % [row[0], row[1]]
	return null


func _test_on_by_default() -> Variant:
	if not bool(AppState._default_settings().get("worldHost", false)):
		return "worldHost is not on in the default settings"
	return null


func _test_a_simulation_is_solo() -> Variant:
	AppState._role = "desktop"
	AppState._holding = true
	var start: int = LifeSim.DEFAULT_START_UNIX
	if not AppState.begin_simulation(2, start):
		return "begin_simulation refused"
	if AppState.role() != "solo" or AppState._holding:
		return "a simulation is role %s, holding %s" % [AppState.role(), AppState._holding]
	var loaded: Dictionary = ContentLoader.load_with_fallback("core_pack", "", false)
	AppState.apply_loaded_pack(str(loaded.get("pack_id", "core_pack")), loaded.get("manifest", {}))
	AppState.settings["smallBeginnings"] = true
	AppState.set_sim_clock(start + 9 * 3600)
	if AppState.tick_mind(start + 9 * 3600).is_empty():
		return "tick_mind was short-circuited in a simulation"
	return null


# A buddy that has just woken for the first time comes when called, though its
# waking takes a little while; at bedtime it still waits for the morning.
func _test_just_woke_comes_now() -> Variant:
	var svc := _service()
	var noon := _midnight() + 12 * 3600
	var profile := svc.ensure_profile(_profile())
	var mind: Dictionary = profile["mind"]
	mind["journal"] = [{"t": noon, "place_id": "home", "activity_id": "wake", "activity_label": "woke up", "text": "I woke up."}]
	mind["busy_until"] = noon + 1200
	profile["mind"] = mind
	var answer: Dictionary = svc.consider_call(profile, _land(), noon + 60)
	if str(answer.get("come", "")) != "now":
		return "a buddy that has just woken answered %s" % [answer]
	var night_profile := profile.duplicate(true)
	(night_profile["mind"] as Dictionary)["busy_until"] = _midnight() + 22 * 3600 + 1200
	var night: Dictionary = svc.consider_call(night_profile, _land(), _midnight() + 22 * 3600)
	if str(night.get("come", "")) != "asleep":
		return "a buddy that has just woken at 22:00 answered %s" % [night]
	return null


func _test_still_world_after_hours() -> Variant:
	var svc := _service()
	var now: int = _midnight() + 12 * 3600
	var base := _profile()
	base["mind"] = {"last_decision_unix": now - 5 * 3600, "location": "home", "journal": []}
	var long_gap: Dictionary = svc.note_still_world(base, _land(), now)
	var journal: Array = long_gap["mind"]["journal"]
	if journal.size() != 1:
		return "a 5-hour gap made %d entries" % journal.size()
	var entry: Dictionary = journal[0]
	if str(entry.get("text", "")) != "There was a long stretch I don't remember. When I noticed again, everything was just where I left it.":
		return "wrong text: %s" % [entry.get("text", "")]
	if str(entry.get("activity_id", "")) != "still_world" or str(entry.get("place_id", "")) != "home":
		return "wrong activity or place: %s" % [entry]
	if int(entry.get("t", 0)) >= now - 8 * 600:
		return "the line is dated %d, not before the catch-up decisions" % int(entry.get("t", 0))
	for case_name in ["short", "visiting", "never", "asleep"]:
		var other := _profile()
		var mind := {"last_decision_unix": now - 2 * 3600, "location": "home", "journal": []}
		if case_name == "visiting":
			mind["last_decision_unix"] = now - 5 * 3600
			mind["location"] = "visiting"
		elif case_name == "never":
			mind["last_decision_unix"] = 0
		elif case_name == "asleep":
			# Went to bed ten hours ago and sleeps on for another hour: no lost time.
			mind["last_decision_unix"] = now - 10 * 3600
			mind["busy_until"] = now + 3600
		other["mind"] = mind
		var after: Dictionary = svc.note_still_world(other, _land(), now)
		if not (after["mind"]["journal"] as Array).is_empty():
			return "a %s gap still got a line" % case_name
	# Woke up four hours ago after a long sleep, and nothing happened since: the
	# lost time runs from waking, and the line is dated after it.
	var woke := _profile()
	woke["mind"] = {"last_decision_unix": now - 14 * 3600, "busy_until": now - 4 * 3600, "location": "home", "journal": []}
	var woke_after: Dictionary = svc.note_still_world(woke, _land(), now)
	var woke_journal: Array = woke_after["mind"]["journal"]
	if woke_journal.size() != 1 or int((woke_journal[0] as Dictionary).get("t", 0)) <= now - 4 * 3600:
		return "after waking four hours ago it should get one line dated after it woke: %s" % [woke_journal]
	return null


func _test_chose_name_line() -> Variant:
	var base := _profile()
	base["mind"] = {"location": "home", "journal": []}
	var named: Dictionary = _service().note_name(base, _midnight(), "Pip", _land())
	var journal: Array = named["mind"]["journal"]
	if journal.size() != 1:
		return "%d entries" % journal.size()
	var entry: Dictionary = journal[0]
	if str(entry.get("text", "")) != "I thought about what to call myself. I'm Pip.":
		return "wrong text: %s" % [entry.get("text", "")]
	if str(entry.get("activity_id", "")) != "chose_name" or str(entry.get("place_id", "")) != "home" or str(entry.get("place_name", "")) != "the house":
		return "wrong place or activity: %s" % [entry]
	return null
