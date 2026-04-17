extends Node
class_name BuddyBrain

signal play_emote_requested(emote_id: String)
signal say_requested(text: String)

const BehaviorEngineScript = preload("res://scripts/behavior/behavior_engine.gd")

@export var idle_speech_seconds: float = 8.0

var _elapsed: float = 0.0
var _behavior_engine = null
var _behavior_elapsed: float = 0.0
const BEHAVIOR_INTERVAL_SEC := 6.0


func _ready() -> void:
	_behavior_engine = BehaviorEngineScript.new()
	_behavior_engine.configure(0)


func tick(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= idle_speech_seconds:
		_elapsed = 0.0
		say("Ready when you are.")

	_behavior_elapsed += delta
	if _behavior_elapsed >= BEHAVIOR_INTERVAL_SEC:
		_behavior_elapsed = 0.0
		_fire_behavior()


func _fire_behavior() -> void:
	var now := int(Time.get_unix_time_from_system())
	var context := {
		"unlocked_actions": ["idle", "sit", "sleep", "wander", "happy", "gift", "visitor"]
	}
	var result := _behavior_engine.tick(now, context)
	var action_id := str(result.get("id", "idle"))
	if action_id != "idle":
		play_emote_requested.emit(action_id)


func play_emote(emote_name: String) -> void:
	play_emote_requested.emit("%s_emote" % emote_name)


func say(text: String) -> void:
	say_requested.emit(text)
