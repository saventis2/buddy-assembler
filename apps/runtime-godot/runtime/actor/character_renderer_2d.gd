extends Node2D
class_name CharacterRenderer2D

# Renders the character body and face overlay using _draw().
#
# Pivot contract:
#   - pivot_px from the animation JSON anchors the character's floor contact
#     at the renderer's local origin (= actor global_position = floor contact Y).
#   - Face overlay position is read from per-frame JSON draw_order[face] data.
#   - Face variant resolves WZ-source absolute paths for emote expressions.

const EMOTE_MANIFEST_PATH := "res://content/core_pack/character/emotes/manifest.json"
const NO_PIVOT := Vector2(-1.0, -1.0)

# Caches
var _texture_cache: Dictionary = {}      # path -> Texture2D or null
var _anim_pivot_cache: Dictionary = {}   # anim_json_path -> Array of Vector2
var _frame_meta_cache: Dictionary = {}   # texture_path -> Dictionary

# Emote state
var _emote_manifest: Dictionary = {}
var _active_emote_semantic: String = "default"
var _active_face_variant: String = "default"

# Draw state (updated by apply_frame)
var _facing_right: bool = false
var _body_tex: Texture2D = null
var _body_pivot: Vector2 = NO_PIVOT
var _has_face: bool = false
var _face_local: Vector2 = Vector2.ZERO
var _face_default_path: String = ""


func _ready() -> void:
	_load_emote_manifest()


func _load_emote_manifest() -> void:
	var raw := _read_text(EMOTE_MANIFEST_PATH)
	if raw != "":
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			_emote_manifest = parsed as Dictionary


func apply_frame(frame_data: Dictionary) -> void:
	var texture_path := str(frame_data.get("texture_path", ""))
	if texture_path == "":
		_body_tex = null
		_has_face = false
		queue_redraw()
		return

	_body_tex = _load_texture(texture_path)

	var meta := _get_frame_meta(texture_path)
	_body_pivot = meta.get("pivot_px", NO_PIVOT)
	_has_face = meta.has("face_local")
	if _has_face:
		_face_local = meta["face_local"]
		_face_default_path = str(meta.get("face_default_path", ""))
	else:
		_face_default_path = ""

	queue_redraw()


func set_emote(semantic: String) -> void:
	var s := semantic.strip_edges().to_lower()
	if s == "" or s == _active_emote_semantic:
		return
	_active_emote_semantic = s
	_active_face_variant = str(_emote_manifest.get(s, s))
	if _active_face_variant == "":
		_active_face_variant = "default"
	queue_redraw()


func reset_emote() -> void:
	if _active_emote_semantic == "default":
		return
	_active_emote_semantic = "default"
	_active_face_variant = "default"
	queue_redraw()


func set_facing_from_axis(axis: float) -> void:
	if axis > 0.01:
		_facing_right = true
	elif axis < -0.01:
		_facing_right = false
	queue_redraw()


func _draw() -> void:
	if _body_tex == null:
		return
	var tex_size := _body_tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	# Pivot at floor contact (local origin). Fallback: bottom-center.
	var pivot := _body_pivot
	if pivot == NO_PIVOT:
		pivot = Vector2(tex_size.x * 0.5, tex_size.y)

	# Body rect: pivot pixel sits at local origin (actor's floor contact Y).
	var body_rect := Rect2(-pivot, tex_size)

	# Facing: mirror horizontally around X=0 (the floor contact column).
	if _facing_right:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))

	draw_texture_rect(_body_tex, body_rect, false)

	# Face overlay drawn inside the same transform so it flips with the body.
	if _has_face and _face_default_path != "":
		var face_tex := _resolve_face_texture()
		if face_tex != null:
			var face_size := face_tex.get_size()
			var face_rect := Rect2(-pivot + _face_local, face_size)
			draw_texture_rect(face_tex, face_rect, false)

	if _facing_right:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Face resolution ---

func _resolve_face_texture() -> Texture2D:
	var candidates: Array[String] = []
	if _active_face_variant != "default" and _active_face_variant != "":
		var variant_path := _make_variant_path(_face_default_path, _active_face_variant)
		if variant_path != "":
			candidates.append(variant_path)
	candidates.append(_face_default_path)

	for candidate in candidates:
		if candidate == "":
			continue
		if _texture_cache.has(candidate):
			var c = _texture_cache[candidate]
			if c is Texture2D:
				return c as Texture2D
			continue
		var tex := _load_texture(candidate)
		if tex != null:
			return tex
	return null


func _make_variant_path(default_path: String, variant: String) -> String:
	for sep in PackedStringArray(["\\", "/"]):
		var win_default: String = sep + "default" + sep + "face.png"
		if default_path.find(win_default) >= 0:
			return default_path.replace(win_default, sep + variant + sep + "0" + sep + "face.png")
	return ""


# --- Per-frame metadata ---

func _get_frame_meta(texture_path: String) -> Dictionary:
	if _frame_meta_cache.has(texture_path):
		return _frame_meta_cache[texture_path]

	var meta: Dictionary = {}

	# pivot_px from animation JSON (one level up from frames/)
	var anim_json_path := _anim_json_path_for(texture_path)
	var frame_idx := _frame_idx_from_path(texture_path)
	if anim_json_path != "" and frame_idx >= 0:
		var pivots := _get_anim_pivots(anim_json_path)
		if frame_idx < pivots.size():
			meta["pivot_px"] = pivots[frame_idx]

	# Face overlay from per-frame JSON
	var frame_json_path := texture_path.get_basename() + ".json"
	var raw := _read_text(frame_json_path)
	if raw == "":
		raw = _read_file(ProjectSettings.globalize_path(frame_json_path))

	if raw != "":
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			var d := parsed as Dictionary
			var bounds_v = d.get("frame_bounds_world", {})
			var bl := 0.0
			var bt := 0.0
			if typeof(bounds_v) == TYPE_DICTIONARY:
				bl = float((bounds_v as Dictionary).get("left", 0.0))
				bt = float((bounds_v as Dictionary).get("top", 0.0))
			var draw_order_v = d.get("draw_order", [])
			if typeof(draw_order_v) == TYPE_ARRAY:
				for ev in draw_order_v as Array:
					if typeof(ev) != TYPE_DICTIONARY:
						continue
					var e := ev as Dictionary
					if str(e.get("asset_kind", "")) != "face":
						continue
					var tl_v = e.get("top_left", [])
					if typeof(tl_v) == TYPE_ARRAY and (tl_v as Array).size() >= 2:
						var tl := tl_v as Array
						meta["face_local"] = Vector2(float(tl[0]) - bl, float(tl[1]) - bt)
					meta["face_default_path"] = str(e.get("png", ""))
					break

	_frame_meta_cache[texture_path] = meta
	return meta


func _anim_json_path_for(texture_path: String) -> String:
	# .../animations/idle/frames/000.png -> .../animations/idle.json
	var frames_dir := texture_path.get_base_dir()   # .../idle/frames
	var anim_dir := frames_dir.get_base_dir()        # .../idle
	var anim_name := anim_dir.get_file()             # idle
	var base_dir := anim_dir.get_base_dir()          # .../animations
	return base_dir + "/" + anim_name + ".json"


func _frame_idx_from_path(texture_path: String) -> int:
	var stem := texture_path.get_file().get_basename()  # "000"
	if stem.is_valid_int():
		return stem.to_int()
	return -1


func _get_anim_pivots(anim_json_path: String) -> Array:
	if _anim_pivot_cache.has(anim_json_path):
		return _anim_pivot_cache[anim_json_path]

	var raw := _read_text(anim_json_path)
	if raw == "":
		raw = _read_file(ProjectSettings.globalize_path(anim_json_path))

	var pivots: Array = []
	if raw != "":
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			var frames_v = (parsed as Dictionary).get("frames", [])
			if typeof(frames_v) == TYPE_ARRAY:
				for fv in frames_v as Array:
					if typeof(fv) != TYPE_DICTIONARY:
						pivots.append(NO_PIVOT)
						continue
					var f := fv as Dictionary
					var pv = f.get("pivot_px", [])
					if typeof(pv) == TYPE_ARRAY and (pv as Array).size() >= 2:
						var pa := pv as Array
						pivots.append(Vector2(float(pa[0]), float(pa[1])))
					else:
						pivots.append(NO_PIVOT)

	_anim_pivot_cache[anim_json_path] = pivots
	return pivots


# --- Texture and file loading ---

func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		var c = _texture_cache[path]
		if c is Texture2D:
			return c as Texture2D
		return null

	var tex: Texture2D = null

	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			var r = load(path)
			if r is Texture2D:
				tex = r as Texture2D
		if tex == null:
			tex = _image_from_file(ProjectSettings.globalize_path(path))
	else:
		# Absolute filesystem path (WZ source assets — face PNGs)
		tex = _image_from_file(path)

	_texture_cache[path] = tex
	return tex


func _image_from_file(fs_path: String) -> Texture2D:
	if not FileAccess.file_exists(fs_path):
		return null
	var img := Image.new()
	if img.load(fs_path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _read_text(res_path: String) -> String:
	if not FileAccess.file_exists(res_path):
		return ""
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _read_file(fs_path: String) -> String:
	if not FileAccess.file_exists(fs_path):
		return ""
	var f := FileAccess.open(fs_path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t
