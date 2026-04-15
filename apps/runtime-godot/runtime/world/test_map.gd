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
