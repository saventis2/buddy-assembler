extends Node2D

signal ladder_entered(ladder_data: Dictionary)
signal portal_triggered(portal_data: Dictionary)

const INTERACTION_STUB_RADIUS := 32.0
const SPEECH_BUBBLE_DURATION_STEP := 0.2
const SPEECH_BUBBLE_DURATION_MIN := 0.4
const SPEECH_BUBBLE_DURATION_MAX := 8.0

@onready var test_map: Node2D = $TestMap
@onready var actor: CharacterBody2D = $BuddyActor
@onready var command_bridge: Node = $BuddyCommandBridge
@onready var hint_label: Label = $CanvasLayer/HintLabel

var _map_ladders: Array = []
var _map_portals: Array = []
var _stub_cooldown: float = 0.0


func _ready() -> void:
	var spawn_pos: Vector2 = test_map.get_actor_spawn_position()
	actor.global_position = spawn_pos
	actor.set_floor_lock_y(test_map.get_actor_floor_lock_y())
	command_bridge.play_emote("happy")
	_load_map_interaction_data()
	_update_hint_label()


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
		"E: happy  R: sad  T: angry  Y: love\n" +
		"S: sit  Z: sleep  G: gift  V: visitor  W: wander\n" +
		"[/]: speech bubble %.1fs  |  actor.y=%.0f" % [actor.speech_bubble_visible_seconds, actor.global_position.y]
	)


func _unhandled_input(event: InputEvent) -> void:
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
				command_bridge.play_emote("visitor")
			elif key_event.keycode == KEY_W:
				command_bridge.play_emote("wander")
			elif key_event.keycode == KEY_BRACKETLEFT:
				actor.speech_bubble_visible_seconds = maxf(
					SPEECH_BUBBLE_DURATION_MIN,
					actor.speech_bubble_visible_seconds - SPEECH_BUBBLE_DURATION_STEP
				)
				_update_hint_label()
			elif key_event.keycode == KEY_BRACKETRIGHT:
				actor.speech_bubble_visible_seconds = minf(
					SPEECH_BUBBLE_DURATION_MAX,
					actor.speech_bubble_visible_seconds + SPEECH_BUBBLE_DURATION_STEP
				)
				_update_hint_label()
