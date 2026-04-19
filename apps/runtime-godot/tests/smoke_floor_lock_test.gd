extends Node

# Smoke test: verifies that BuddyActor._apply_floor_lock_fallback() clamps actor Y
# correctly. Runs headlessly; exits 0 on pass, 1 on any failure.

const BuddyActorScene = preload("res://scenes/vertical_slice/BuddyActor.tscn")

var _all_passed := true


func _ready() -> void:
	var actor: CharacterBody2D = BuddyActorScene.instantiate()
	add_child(actor)

	_run_clamp_below_floor(actor)
	_run_no_push_above_floor(actor)
	_run_inf_lock_is_noop(actor)

	if _all_passed:
		print("smoke_floor_lock: ALL PASS")
		OS.exit(0)
	else:
		print("smoke_floor_lock: FAILED — see errors above")
		OS.exit(1)


func _run_clamp_below_floor(actor: CharacterBody2D) -> void:
	actor.set_floor_lock_y(200.0)
	actor.global_position = Vector2(100.0, 300.0)
	actor._apply_floor_lock_fallback()
	if actor.global_position.y > 200.1:
		push_error("FAIL clamp_below_floor: Y=%.2f expected <= 200.0" % actor.global_position.y)
		_all_passed = false
	else:
		print("PASS clamp_below_floor: Y clamped to %.2f" % actor.global_position.y)


func _run_no_push_above_floor(actor: CharacterBody2D) -> void:
	actor.set_floor_lock_y(200.0)
	actor.global_position = Vector2(100.0, 100.0)
	actor._apply_floor_lock_fallback()
	if actor.global_position.y > 200.1:
		push_error("FAIL no_push_above_floor: Y=%.2f was pushed down unexpectedly" % actor.global_position.y)
		_all_passed = false
	else:
		print("PASS no_push_above_floor: Y=%.2f unaffected" % actor.global_position.y)


func _run_inf_lock_is_noop(actor: CharacterBody2D) -> void:
	actor.set_floor_lock_y(INF)
	actor.global_position = Vector2(100.0, 999.0)
	actor._apply_floor_lock_fallback()
	if actor.global_position.y < 998.0:
		push_error("FAIL inf_lock_is_noop: Y=%.2f changed when lock is INF" % actor.global_position.y)
		_all_passed = false
	else:
		print("PASS inf_lock_is_noop: Y=%.2f unchanged with INF lock" % actor.global_position.y)
