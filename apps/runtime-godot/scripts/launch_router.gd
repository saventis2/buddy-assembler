extends Node

const DEFAULT_SCENE := "res://scenes/BuddyOverlay.tscn"
const VERTICAL_SLICE_SCENE := "res://scenes/vertical_slice/VerticalSliceMain.tscn"


func _ready() -> void:
	var target_scene := _target_scene_from_args(OS.get_cmdline_user_args())
	call_deferred("_switch_to_scene", target_scene)


func _target_scene_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg == "--vertical-slice":
			return VERTICAL_SLICE_SCENE
		if arg == "--default-overlay":
			return DEFAULT_SCENE
	return DEFAULT_SCENE


func _switch_to_scene(path: String) -> void:
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to load launch target scene: %s" % path)
