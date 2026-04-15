extends CharacterBody2D
class_name BuddyActor

const CharacterAssemblerScript = preload("res://runtime/actor/character_assembler.gd")

@export var actor_definition: Resource

@onready var state_machine: Node = $StateMachine
@onready var movement_controller: Node = $MovementController
@onready var animation_controller: Node = $AnimationController
@onready var renderer: Node2D = $CharacterRenderer2D
@onready var buddy_brain: Node = $BuddyBrain
@onready var speech_bubble: Label = $SpeechBubble

var _assembler = CharacterAssemblerScript.new()
var _runtime_bundle: Dictionary = {}
var _floor_lock_y: float = INF


func _ready() -> void:
	if actor_definition == null:
		return
	_runtime_bundle = _assembler.assemble(actor_definition)
	movement_controller.configure(_runtime_bundle.get("movement_profile", {}))
	animation_controller.configure(_runtime_bundle.get("clips", {}))
	animation_controller.frame_changed.connect(renderer.apply_frame)
	buddy_brain.play_emote_requested.connect(_on_play_emote_requested)
	buddy_brain.say_requested.connect(_on_say_requested)
	var defaults: Dictionary = _runtime_bundle.get("semantic_defaults", {})
	var idle_clip := str(defaults.get("idle", "idle"))
	animation_controller.play(idle_clip, true)


func _physics_process(delta: float) -> void:
	var input_axis := Input.get_axis("ui_left", "ui_right")
	var jump_pressed := Input.is_action_just_pressed("ui_accept")
	var floor_lock_grounded := _is_floor_lock_grounded()
	movement_controller.update(self, delta, input_axis, jump_pressed, floor_lock_grounded)
	_apply_floor_lock_fallback()
	renderer.set_facing_from_axis(input_axis)

	var next_state: String = state_machine.evaluate(
		input_axis,
		self,
		_is_floor_lock_grounded(),
		jump_pressed
	)
	var semantic_defaults: Dictionary = _runtime_bundle.get("semantic_defaults", {})
	var clip_id := str(semantic_defaults.get(next_state, next_state))
	animation_controller.play(clip_id)
	animation_controller.update(delta)
	buddy_brain.tick(delta)


func command_play_emote(emote_name: String) -> void:
	buddy_brain.play_emote(emote_name)


func set_floor_lock_y(world_y: float) -> void:
	_floor_lock_y = world_y


func _on_play_emote_requested(emote_id: String) -> void:
	var semantic_defaults: Dictionary = _runtime_bundle.get("semantic_defaults", {})
	var clip_id := str(semantic_defaults.get(emote_id, emote_id))
	state_machine.force_state(emote_id, 900)
	animation_controller.play(clip_id, true)


func _on_say_requested(text: String) -> void:
	speech_bubble.text = text
	speech_bubble.visible = true
	await get_tree().create_timer(1.6).timeout
	speech_bubble.visible = false


func _apply_floor_lock_fallback() -> void:
	if is_inf(_floor_lock_y):
		return
	if global_position.y > _floor_lock_y:
		global_position.y = _floor_lock_y
		velocity.y = 0.0


func _is_floor_lock_grounded() -> bool:
	if is_inf(_floor_lock_y):
		return false
	return absf(global_position.y - _floor_lock_y) <= 1.5 and velocity.y >= 0.0
