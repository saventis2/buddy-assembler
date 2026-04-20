extends Node2D

signal ladder_entered(ladder_data: Dictionary)
signal portal_triggered(portal_data: Dictionary)

const INTERACTION_STUB_RADIUS := 32.0
const SPEECH_BUBBLE_DURATION_STEP := 0.2
const SPEECH_BUBBLE_DURATION_MIN := 0.4
const SPEECH_BUBBLE_DURATION_MAX := 8.0

const BuddyActorScene: PackedScene = preload("res://scenes/vertical_slice/BuddyActor.tscn")
const VisitorControllerScript = preload("res://runtime/buddy/visitor_controller.gd")
const VISITOR_SPAWN_X_OFFSET := 320.0
const VISITOR_ACTOR_DEFINITION_PATH := "res://content/imported/demo/visitor_actor_definition.tres"
const VISITOR_DEBUG_DOT_COLOR := Color(0.25, 1.0, 0.25, 1.0)
const VISITOR_DEBUG_DOT_RADIUS := 5.0
const VISITOR_DEBUG_DOT_Y_OFFSET := -80.0  # float above the visitor's head

@onready var test_map: Node2D = $TestMap
@onready var actor: CharacterBody2D = $BuddyActor
@onready var command_bridge: Node = $BuddyCommandBridge
@onready var hint_label: Label = $CanvasLayer/HintLabel

var _map_ladders: Array = []
var _map_portals: Array = []
var _stub_cooldown: float = 0.0
var _visitor_active: bool = false
var _visitor_ref: Node2D = null


func _ready() -> void:
	var spawn_pos: Vector2 = test_map.get_actor_spawn_position()
	actor.global_position = spawn_pos
	actor.set_floor_lock_y(test_map.get_actor_floor_lock_y())
	command_bridge.play_emote("happy")
	_load_map_interaction_data()
	_update_hint_label()
	var buddy_brain := actor.get_node_or_null("BuddyBrain")
	if buddy_brain != null and buddy_brain.has_signal("visitor_arrival_requested"):
		buddy_brain.visitor_arrival_requested.connect(_on_visitor_arrival_requested)


func _on_visitor_arrival_requested() -> void:
	if _visitor_active:
		return
	_visitor_active = true
	var visitor: CharacterBody2D = BuddyActorScene.instantiate() as CharacterBody2D
	visitor.name = "Visitor"
	visitor.autonomous = true
	visitor.external_axis = 0.0
	# Override the actor definition BEFORE add_child so _ready assembles with
	# the visitor's distinct hair/face/coat sprite set, not the player's.
	var visitor_def := load(VISITOR_ACTOR_DEFINITION_PATH)
	if visitor_def != null:
		visitor.actor_definition = visitor_def
	# Visitor boundary: ignore the map's walls/collision entirely so it can
	# traverse freely in/out of the scene. Floor lock keeps it on the ground.
	visitor.collision_layer = 0
	visitor.collision_mask = 0
	visitor.set_floor_lock_y(test_map.get_actor_floor_lock_y())
	add_child(visitor)
	visitor.global_position = Vector2(
		actor.global_position.x + VISITOR_SPAWN_X_OFFSET,
		actor.global_position.y
	)
	var controller := VisitorControllerScript.new()
	controller.name = "VisitorController"
	controller.target_actor = actor
	controller.depart_threshold_x = visitor.global_position.x + 40.0
	visitor.add_child(controller)
	visitor.tree_exited.connect(_on_visitor_freed)
	_visitor_ref = visitor
	# Arrival sparkle — BasicEff.img/Summoned pop.
	var visitor_renderer: Node = visitor.get_node_or_null("CharacterRenderer2D")
	if visitor_renderer != null and visitor_renderer.has_method("play_overlay"):
		visitor_renderer.call("play_overlay", "visitor_arrival", false)
	queue_redraw()


func _on_visitor_freed() -> void:
	_visitor_active = false
	_visitor_ref = null
	queue_redraw()


func _draw() -> void:
	# Debug marker: green dot tracking the visitor while it's active.
	if not _visitor_active or _visitor_ref == null or not is_instance_valid(_visitor_ref):
		return
	var p := _visitor_ref.global_position + Vector2(0.0, VISITOR_DEBUG_DOT_Y_OFFSET)
	draw_circle(p, VISITOR_DEBUG_DOT_RADIUS, VISITOR_DEBUG_DOT_COLOR)


func _load_map_interaction_data() -> void:
	var map_res: Resource = test_map.get_map_resource()
	if map_res == null:
		return
	if not map_res.has_method("get"):
		return
	var ladders_variant = map_res.get("ladders")
	if typeof(ladders_variant) == TYPE_ARRAY:
		_map_ladders = ladders_variant as Array
	var portals_variant = map_res.get("portals")
	if typeof(portals_variant) == TYPE_ARRAY:
		_map_portals = portals_variant as Array


func _process(delta: float) -> void:
	_stub_cooldown = maxf(0.0, _stub_cooldown - delta)
	_check_interaction_stubs(actor.global_position)
	_update_hint_label()
	if _visitor_active:
		queue_redraw()


func _check_interaction_stubs(actor_pos: Vector2) -> void:
	if _stub_cooldown > 0.0:
		return

	for ladder in _map_ladders:
		if typeof(ladder) != TYPE_DICTIONARY:
			continue
		var lx := float((ladder as Dictionary).get("x0", 0.0))
		var ly := float((ladder as Dictionary).get("y0", 0.0))
		if actor_pos.distance_to(Vector2(lx, ly)) <= INTERACTION_STUB_RADIUS:
			print("stub: ladder_enter at (%.0f, %.0f)" % [lx, ly])
			ladder_entered.emit(ladder as Dictionary)
			_stub_cooldown = 1.5
			return

	for portal in _map_portals:
		if typeof(portal) != TYPE_DICTIONARY:
			continue
		var px := float((portal as Dictionary).get("x", 0.0))
		var py := float((portal as Dictionary).get("y", 0.0))
		if actor_pos.distance_to(Vector2(px, py)) <= INTERACTION_STUB_RADIUS:
			print("stub: portal_trigger at (%.0f, %.0f)" % [px, py])
			portal_triggered.emit(portal as Dictionary)
			_stub_cooldown = 1.5
			return


func _update_hint_label() -> void:
	hint_label.text = (
		"Arrow keys: move  Space: jump\n" +
		"E: happy  R: sad  T: angry  Y: love  (face emotes, 1.8s)\n" +
		"U: stunned  I: proud  O: embarrassed  P: sparkle  H: humming  K: kiss  B: bow\n" +
		"S: sit  Z: sleep  G: gift  (body, 2.5s)\n" +
		"F: fly  C: climb  1: swing  2: stab  4: alt_idle  (body, 2.5s)\n" +
		"M: force speech bubble test line\n" +
		"V: visitor (second buddy walks in, waves, leaves)\n" +
		"[/]: speech bubble %.1fs  |  actor.y=%.0f" % [actor.speech_bubble_visible_seconds, actor.global_position.y]
	)


func _input(event: InputEvent) -> void:
	_handle_key_input(event)


func _handle_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_E:
				command_bridge.play_emote("happy")
			elif key_event.keycode == KEY_R:
				command_bridge.play_emote("sad")
			elif key_event.keycode == KEY_T:
				command_bridge.play_emote("angry")
			elif key_event.keycode == KEY_Y:
				command_bridge.play_emote("love")
			elif key_event.keycode == KEY_S:
				command_bridge.play_emote("sit")
			elif key_event.keycode == KEY_Z:
				command_bridge.play_emote("sleep")
			elif key_event.keycode == KEY_G:
				command_bridge.play_emote("gift")
			elif key_event.keycode == KEY_V:
				var buddy_brain := actor.get_node_or_null("BuddyBrain")
				if buddy_brain != null and buddy_brain.has_method("request_visitor_arrival"):
					buddy_brain.request_visitor_arrival()
			elif key_event.keycode == KEY_F:
				command_bridge.play_emote("fly")
			elif key_event.keycode == KEY_C:
				command_bridge.play_emote("climb")
			elif key_event.keycode == KEY_1:
				command_bridge.play_emote("swing")
			elif key_event.keycode == KEY_2:
				command_bridge.play_emote("stab")
			elif key_event.keycode == KEY_4:
				command_bridge.play_emote("alt_idle")
			elif key_event.keycode == KEY_U:
				command_bridge.play_emote("stunned")
			elif key_event.keycode == KEY_I:
				command_bridge.play_emote("proud")
			elif key_event.keycode == KEY_O:
				command_bridge.play_emote("embarrassed")
			elif key_event.keycode == KEY_P:
				command_bridge.play_emote("sparkle")
			elif key_event.keycode == KEY_H:
				command_bridge.play_emote("humming")
			elif key_event.keycode == KEY_K:
				command_bridge.play_emote("kiss")
			elif key_event.keycode == KEY_B:
				command_bridge.play_emote("bow")
			elif key_event.keycode == KEY_M:
				command_bridge.say("Bubble duration %.1fs" % actor.speech_bubble_visible_seconds)
			elif key_event.keycode == KEY_BRACKETLEFT:
				actor.speech_bubble_visible_seconds = maxf(
					SPEECH_BUBBLE_DURATION_MIN,
					actor.speech_bubble_visible_seconds - SPEECH_BUBBLE_DURATION_STEP
				)
				command_bridge.say("Bubble duration %.1fs" % actor.speech_bubble_visible_seconds)
				_update_hint_label()
			elif key_event.keycode == KEY_BRACKETRIGHT:
				actor.speech_bubble_visible_seconds = minf(
					SPEECH_BUBBLE_DURATION_MAX,
					actor.speech_bubble_visible_seconds + SPEECH_BUBBLE_DURATION_STEP
				)
				command_bridge.say("Bubble duration %.1fs" % actor.speech_bubble_visible_seconds)
				_update_hint_label()
