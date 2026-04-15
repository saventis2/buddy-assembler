extends Node2D
class_name CharacterRenderer2D

@onready var _sprite: Sprite2D = $Sprite2D

var _frame_cache: Dictionary = {}


func apply_frame(frame_data: Dictionary) -> void:
	var texture_path := str(frame_data.get("texture_path", ""))
	if texture_path == "":
		_sprite.texture = null
		return

	if not _frame_cache.has(texture_path):
		var tex = load(texture_path)
		if tex is Texture2D:
			_frame_cache[texture_path] = tex
		else:
			return

	_sprite.texture = _frame_cache[texture_path]
	var anchor = frame_data.get("anchor_px", [0.0, 0.0])
	if typeof(anchor) == TYPE_ARRAY and (anchor as Array).size() >= 2:
		var arr: Array = anchor
		_sprite.offset = Vector2(float(arr[0]), float(arr[1]))

