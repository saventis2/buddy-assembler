extends Node2D

@onready var test_map: Node2D = $TestMap
@onready var actor: CharacterBody2D = $BuddyActor
@onready var command_bridge: Node = $BuddyCommandBridge
@onready var hint_label: Label = $CanvasLayer/HintLabel


func _ready() -> void:
	var spawn_pos: Vector2 = test_map.get_actor_spawn_position()
	actor.global_position = spawn_pos
	actor.set_floor_lock_y(test_map.get_actor_floor_lock_y())
	command_bridge.play_emote("happy")
	hint_label.text = "Arrow keys move, Space jumps, E triggers happy emote"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_E:
			command_bridge.play_emote("happy")
