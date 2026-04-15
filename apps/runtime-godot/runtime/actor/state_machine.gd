extends Node
class_name ActorStateMachine

var current_state: String = "idle"
var forced_state_until_ms: int = 0


func force_state(state_id: String, duration_ms: int) -> void:
	current_state = state_id
	forced_state_until_ms = Time.get_ticks_msec() + max(0, duration_ms)


func evaluate(input_axis: float, body: CharacterBody2D) -> String:
	var now_ms := Time.get_ticks_msec()
	if now_ms < forced_state_until_ms:
		return current_state

	if not body.is_on_floor():
		current_state = "jump"
	elif absf(input_axis) > 0.01:
		current_state = "walk"
	else:
		current_state = "idle"
	return current_state
