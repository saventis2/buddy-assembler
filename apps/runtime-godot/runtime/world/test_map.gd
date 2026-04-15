extends Node2D

@export var collision_map_resource: Resource

@onready var collision_runtime: Node = $CollisionMapRuntime
@onready var spawn_marker: Marker2D = $SpawnMarker
@onready var interaction_marker: Marker2D = $InteractionMarker


func _ready() -> void:
	collision_runtime.collision_map = collision_map_resource
	spawn_marker.position = collision_runtime.spawn_point()
	var interaction_pos: Vector2 = collision_runtime.marker_position("desk_left")
	if interaction_pos != Vector2.ZERO:
		interaction_marker.position = interaction_pos


func get_actor_spawn_position() -> Vector2:
	return spawn_marker.global_position


func get_actor_floor_lock_y() -> float:
	if collision_map_resource == null:
		return 174.0
	if not collision_map_resource.has_method("get"):
		return 174.0
	var footholds = collision_map_resource.get("footholds")
	if typeof(footholds) == TYPE_ARRAY and (footholds as Array).size() > 0:
		var first = (footholds as Array)[0]
		if typeof(first) == TYPE_DICTIONARY:
			var y0 := float((first as Dictionary).get("y0", 180.0))
			return y0 - 22.0
	return 174.0
