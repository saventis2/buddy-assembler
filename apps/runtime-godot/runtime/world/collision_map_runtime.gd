extends Node
class_name CollisionMapRuntime

@export var collision_map: Resource


func spawn_point() -> Vector2:
	if collision_map == null:
		return Vector2(64, 120)
	return collision_map.spawn_point


func marker_position(marker_id: String) -> Vector2:
	if collision_map == null:
		return Vector2.ZERO
	var marker = collision_map.interaction_markers.get(marker_id, {})
	if typeof(marker) != TYPE_DICTIONARY:
		return Vector2.ZERO
	return Vector2(float(marker.get("x", 0.0)), float(marker.get("y", 0.0)))
