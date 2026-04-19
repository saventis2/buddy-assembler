extends Resource
class_name BehaviorProfile

@export var profile_id: String = "default"
@export var idle_weights: Dictionary = {"idle": 1.0}
@export var emote_frequency: float = 0.15
@export var curiosity: float = 0.3
@export var follow_distance: float = 64.0
@export var perch_preference: float = 0.1
@export var metadata: Dictionary = {}
