extends RefCounted
class_name ResolvedFrameCache

# Invalidation policy:
#   - Call invalidate_clip() when a single animation's source textures change.
#   - Call invalidate_all() on a full skin or character swap to flush all cached frames.
#   - The cache is automatically cleared on AnimationController.configure(), so explicit
#     invalidation is only needed for hot-swap scenarios (no full reconfigure).

var _resolved: Dictionary = {}


func clear() -> void:
	_resolved.clear()


func invalidate_all() -> void:
	_resolved.clear()


func invalidate_clip(clip_id: String) -> void:
	var prefix := "%s:" % clip_id
	var keys_to_remove: Array[String] = []
	for key in _resolved.keys():
		if str(key).begins_with(prefix):
			keys_to_remove.append(str(key))
	for key in keys_to_remove:
		_resolved.erase(key)


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
