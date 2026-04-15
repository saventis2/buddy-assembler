extends Node
class_name BuddyBrain

signal play_emote_requested(emote_id: String)
signal say_requested(text: String)

@export var idle_speech_seconds: float = 8.0

var _elapsed: float = 0.0


func tick(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= idle_speech_seconds:
		_elapsed = 0.0
		say("Ready when you are.")


func play_emote(emote_name: String) -> void:
	play_emote_requested.emit("%s_emote" % emote_name)


func say(text: String) -> void:
	say_requested.emit(text)
