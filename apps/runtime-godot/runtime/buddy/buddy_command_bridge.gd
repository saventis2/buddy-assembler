extends Node
class_name BuddyCommandBridge

@export var target_actor_path: NodePath


func play_emote(emote_name: String) -> void:
	var actor := get_node_or_null(target_actor_path)
	if actor == null:
		return
	if actor.has_method("command_play_emote"):
		actor.command_play_emote(emote_name)


func say(text: String) -> void:
	var actor := get_node_or_null(target_actor_path)
	if actor == null:
		return
	if actor.has_method("command_say"):
		actor.command_say(text)
