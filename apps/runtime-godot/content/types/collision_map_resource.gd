extends Resource
class_name CollisionMapResource

@export var map_id: String = ""
@export var spawn_point: Vector2 = Vector2.ZERO
@export var footholds: Array[Dictionary] = []
@export var ladders: Array[Dictionary] = []
@export var portals: Array[Dictionary] = []
@export var interaction_markers: Dictionary = {}
@export var metadata: Dictionary = {}
