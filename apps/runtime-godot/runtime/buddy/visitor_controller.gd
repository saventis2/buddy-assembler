extends Node
class_name VisitorController

# Drives a spawned (autonomous) BuddyActor through a scripted
# walk-in → wave → walk-out sequence, then frees the actor.
#
# Expects its parent to be a BuddyActor with autonomous = true.

const APPROACH_DISTANCE_PX := 90.0
const WAVE_DURATION_SEC := 1.8
const APPROACH_TIMEOUT_SEC := 10.0
const DEPART_TIMEOUT_SEC := 8.0
const OFFSCREEN_MARGIN_PX := 140.0

enum Phase { APPROACH, WAVE, DEPART, DONE }

var target_actor: Node2D = null
var depart_threshold_x: float = 1_000_000.0

var _phase: int = Phase.APPROACH
var _phase_elapsed: float = 0.0
var _wave_elapsed: float = 0.0
var _actor: CharacterBody2D = null


func _ready() -> void:
	_actor = get_parent() as CharacterBody2D


func _physics_process(delta: float) -> void:
	if _actor == null:
		return
	_phase_elapsed += delta
	match _phase:
		Phase.APPROACH:
			_actor.external_axis = -1.0
			var target_x := _target_x()
			var reached := _actor.global_position.x <= target_x + APPROACH_DISTANCE_PX
			if reached or _phase_elapsed >= APPROACH_TIMEOUT_SEC:
				_actor.external_axis = 0.0
				_phase = Phase.WAVE
				_phase_elapsed = 0.0
				_actor.command_play_emote("happy")
		Phase.WAVE:
			_wave_elapsed += delta
			if _wave_elapsed >= WAVE_DURATION_SEC:
				_phase = Phase.DEPART
				_phase_elapsed = 0.0
		Phase.DEPART:
			_actor.external_axis = 1.0
			if _actor.global_position.x >= depart_threshold_x or _phase_elapsed >= DEPART_TIMEOUT_SEC:
				_phase = Phase.DONE
				# Farewell sparkle, then free once it's had time to play.
				_actor.external_axis = 0.0
				var renderer: Node = _actor.get_node_or_null("CharacterRenderer2D")
				if renderer != null and renderer.has_method("play_overlay"):
					renderer.call("play_overlay", "visitor_depart", false)
				await get_tree().create_timer(0.6).timeout
				if is_instance_valid(_actor):
					_actor.queue_free()


func _target_x() -> float:
	if target_actor != null and is_instance_valid(target_actor):
		return target_actor.global_position.x
	return 0.0
