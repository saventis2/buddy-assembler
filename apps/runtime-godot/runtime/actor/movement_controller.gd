extends Node
class_name MovementController

var walk_speed: float = 95.0
var jump_velocity: float = -250.0
var gravity: float = 700.0
var terminal_velocity: float = 900.0


func configure(profile: Dictionary) -> void:
	walk_speed = float(profile.get("walk_speed", walk_speed))
	jump_velocity = float(profile.get("jump_velocity", jump_velocity))
	gravity = float(profile.get("gravity", gravity))
	terminal_velocity = float(profile.get("terminal_velocity", terminal_velocity))


func update(
	body: CharacterBody2D,
	delta: float,
	input_axis: float,
	jump_pressed: bool,
	grounded_override: bool = false
) -> void:
	body.velocity.x = input_axis * walk_speed
	body.velocity.y = minf(body.velocity.y + gravity * delta, terminal_velocity)
	if jump_pressed and (body.is_on_floor() or grounded_override):
		body.velocity.y = jump_velocity
	body.move_and_slide()
