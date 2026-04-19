extends CharacterBody2D
class_name BuddyActor

const CharacterAssemblerScript = preload("res://runtime/actor/character_assembler.gd")

# Body behavior animations need longer hold so the pose is clearly visible.
# Face emotes (happy/sad/angry/love) stay at the shorter EMOTE_FORCE_MS.
const BEHAVIOR_CLIP_IDS := ["sit", "sleep", "gift", "wander", "visitor"]
const BEHAVIOR_FORCE_MS := 2500
# Face emotes held for 1.8s — the old 0.9s cut mid-animation and felt twitchy.
const EMOTE_FORCE_MS := 1800

@export var actor_definition: Resource
# When true, _physics_process reads external_axis instead of Input.
# Used by the visitor controller to drive a second spawned BuddyActor.
@export var autonomous: bool = false
var external_axis: float = 0.0

@onready var state_machine: Node = $StateMachine
@onready var movement_controller: Node = $MovementController
@onready var animation_controller: Node = $AnimationController
@onready var renderer: Node2D = $CharacterRenderer2D
@onready var buddy_brain: Node = $BuddyBrain
@onready var speech_bubble: Node2D = $SpeechBubble

var _assembler = CharacterAssemblerScript.new()
var _runtime_bundle: Dictionary = {}
var _floor_lock_y: float = INF
var speech_bubble_visible_seconds: float = 1.6


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
	var input_axis: float
	var jump_pressed: bool
	if autonomous:
		input_axis = external_axis
		jump_pressed = false
	else:
		input_axis = Input.get_axis("ui_left", "ui_right")
		jump_pressed = Input.is_action_just_pressed("ui_accept")
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
	# Autonomous actors (visitor) are driven externally — don't let their own
	# brain fire random emotes that would interrupt the scripted sequence.
	if not autonomous:
		buddy_brain.tick(delta)


func command_play_emote(emote_name: String) -> void:
	buddy_brain.play_emote(emote_name)


func set_floor_lock_y(world_y: float) -> void:
	_floor_lock_y = world_y


func on_skin_swap() -> void:
	animation_controller.invalidate_all()


func _on_play_emote_requested(emote_id: String) -> void:
	var semantic_defaults: Dictionary = _runtime_bundle.get("semantic_defaults", {})
	var clip_id := str(semantic_defaults.get(emote_id, emote_id))
	var force_ms := BEHAVIOR_FORCE_MS if clip_id in BEHAVIOR_CLIP_IDS else EMOTE_FORCE_MS
	state_machine.force_state(emote_id, force_ms)
	animation_controller.play(clip_id, true)
	var face_semantic := emote_id.trim_suffix("_emote")
	renderer.call("set_emote", face_semantic)
	# Gift reuses the happy_emote body pose (alert / raised arm) plus a
	# gift-box icon overlay at the hand and a speech bubble.
	var is_gift := emote_id == "gift" or emote_id == "gift_emote"
	if is_gift:
		_on_say_requested("For you!")
		renderer.call("play_overlay", "gift_box", true)
	# Chair prop renders behind the body for the duration of the sit pose.
	if clip_id == "sit":
		renderer.call("play_back_overlay", "chair_basic", true)
	# Soft sparkle on happy — IncEXP is a gentle warm glow, appropriate for
	# a positive emote (LevelUp was too ceremonial).
	elif emote_id == "happy" or emote_id == "happy_emote":
		renderer.call("play_overlay", "happy_sparkle", false)
	await get_tree().create_timer(float(force_ms) / 1000.0 + 0.1).timeout
	renderer.call("reset_emote")
	if clip_id == "sit":
		renderer.call("stop_back_overlay")
	if is_gift:
		renderer.call("stop_overlay")


func _on_say_requested(text: String) -> void:
	speech_bubble.visible = true
	speech_bubble.call("show_text", text)
	await get_tree().create_timer(speech_bubble_visible_seconds).timeout
	speech_bubble.call("hide_bubble")
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
