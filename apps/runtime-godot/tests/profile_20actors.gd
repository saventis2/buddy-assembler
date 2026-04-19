extends Node

# Frame-time profiler for 20 concurrent BuddyActor instances.
# Run headlessly via ProfileScene.tscn.
# Collects FRAME_BUDGET frames of delta times, then prints min/max/avg and exits.

const BuddyActorScene = preload("res://scenes/vertical_slice/BuddyActor.tscn")
const ACTOR_COUNT := 20
const FRAME_BUDGET := 300
const WARMUP_FRAMES := 10

var _frame_deltas: Array[float] = []
var _frame_count := 0
var _warmup_remaining := WARMUP_FRAMES


func _ready() -> void:
	print("profile_20actors: spawning %d actors..." % ACTOR_COUNT)
	for i in range(ACTOR_COUNT):
		var actor: CharacterBody2D = BuddyActorScene.instantiate()
		add_child(actor)
		actor.global_position = Vector2(float(i) * 18.0, 100.0)
	print("profile_20actors: actors ready, warming up for %d frames..." % WARMUP_FRAMES)


func _process(delta: float) -> void:
	if _warmup_remaining > 0:
		_warmup_remaining -= 1
		return

	_frame_deltas.append(delta)
	_frame_count += 1

	if _frame_count >= FRAME_BUDGET:
		_report_and_exit()


func _report_and_exit() -> void:
	if _frame_deltas.is_empty():
		push_error("profile_20actors: no frames recorded")
		get_tree().quit(1)
		return

	var total := 0.0
	var min_dt := _frame_deltas[0]
	var max_dt := _frame_deltas[0]
	for dt in _frame_deltas:
		total += dt
		if dt < min_dt:
			min_dt = dt
		if dt > max_dt:
			max_dt = dt
	var avg_dt := total / float(_frame_deltas.size())

	print("")
	print("=== Frame-time profiling report ===")
	print("Actors:  %d" % ACTOR_COUNT)
	print("Frames:  %d" % _frame_deltas.size())
	print("Min dt:  %.2f ms (%.1f fps)" % [min_dt * 1000.0, 1.0 / max(min_dt, 0.0001)])
	print("Max dt:  %.2f ms (%.1f fps)" % [max_dt * 1000.0, 1.0 / max(max_dt, 0.0001)])
	print("Avg dt:  %.2f ms (%.1f fps)" % [avg_dt * 1000.0, 1.0 / max(avg_dt, 0.0001)])
	print("===================================")

	get_tree().quit(0)
