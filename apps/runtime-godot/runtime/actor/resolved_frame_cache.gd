extends RefCounted
class_name ResolvedFrameCache

var _resolved: Dictionary = {}


func clear() -> void:
	_resolved.clear()


func resolve(clip_id: String, frame_index: int, frame_data: Dictionary) -> Dictionary:
	var key := "%s:%d" % [clip_id, frame_index]
	if _resolved.has(key):
		return _resolved[key]

	var resolved := {
		"texture_path": str(frame_data.get("texture_path", "")),
		"delay_ms": int(frame_data.get("delay_ms", 120)),
		"anchor_px": frame_data.get("anchor_px", [0.0, 0.0]),
	}
	_resolved[key] = resolved
	return resolved
