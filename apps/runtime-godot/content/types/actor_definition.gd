extends Resource
class_name ActorDefinition

@export var actor_id: String = ""
@export var display_name: String = ""
@export var semantic_defaults: Dictionary = {
	"idle": "idle",
	"walk": "walk",
	"jump": "jump",
	"climb": "climb",
	"happy_emote": "happy_emote",
}
@export var skeleton: Resource
@export var skins: Array[Resource] = []
@export var attachment_slots: Resource
@export var behavior_profile: Resource
@export var clips: Dictionary = {}
@export var movement_profile: Dictionary = {
	"walk_speed": 95.0,
	"jump_velocity": -250.0,
	"gravity": 700.0,
	"terminal_velocity": 900.0,
}
@export var metadata: Dictionary = {}
