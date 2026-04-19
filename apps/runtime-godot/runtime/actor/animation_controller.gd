extends Node
class_name AnimationController

signal clip_changed(clip_id: String)
signal frame_changed(frame_data: Dictionary)

const ResolvedFrameCacheScript = preload("res://runtime/actor/resolved_frame_cache.gd")

var _clips: Dictionary = {}
var _current_clip: Resource
var _current_clip_id: String = ""
var _frame_index: int = 0
var _elapsed_ms: float = 0.0
var _resolved_frame_cache = ResolvedFrameCacheScript.new()


func configure(clips: Dictionary) -> void:
	_clips = clips.duplicate()
	_current_clip = null
	_current_clip_id = ""
	_frame_index = 0
	_elapsed_ms = 0.0
	_resolved_frame_cache.clear()


func play(clip_id: String, force_restart: bool = false) -> void:
	if not force_restart and _current_clip_id == clip_id:
		return
	var clip_variant = _clips.get(clip_id)
	if not (clip_variant is Resource):
		return
	_current_clip = clip_variant
	_current_clip_id = clip_id
	_frame_index = 0
	_elapsed_ms = 0.0
	clip_changed.emit(_current_clip_id)
	_emit_current_frame()


func update(delta: float) -> void:
	if _current_clip == null:
		return
	if _current_clip.frames.is_empty():
		return

	_elapsed_ms += delta * 1000.0
	var guard := 0
	while guard < 8:
		guard += 1
		var duration_ms := _current_frame_duration_ms()
		if _elapsed_ms < duration_ms:
			break
		_elapsed_ms -= duration_ms
		_advance_frame()
		_emit_current_frame()


func _advance_frame() -> void:
	if _current_clip == null:
		return
	var count: int = _current_clip.frames.size()
	if count <= 1:
		return
	if _frame_index + 1 < count:
		_frame_index += 1
	elif _current_clip.loop:
		_frame_index = 0
	else:
		_frame_index = count - 1


func _current_frame_duration_ms() -> float:
	if _current_clip == null or _current_clip.frames.is_empty():
		return 120.0
	var frame_data: Dictionary = _current_clip.frames[_frame_index]
	var value = frame_data.get("delay_ms", 120.0)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return maxf(20.0, float(value))
	return 120.0


func invalidate_clip(clip_id: String) -> void:
	_resolved_frame_cache.invalidate_clip(clip_id)


func invalidate_all() -> void:
	_resolved_frame_cache.invalidate_all()


func _emit_current_frame() -> void:
	if _current_clip == null or _current_clip.frames.is_empty():
		return
	var frame_data: Dictionary = _current_clip.frames[_frame_index]
	var resolved: Dictionary = _resolved_frame_cache.resolve(_current_clip_id, _frame_index, frame_data)
	frame_changed.emit(resolved)
