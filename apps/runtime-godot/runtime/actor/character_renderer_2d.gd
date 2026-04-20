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
const FACE_VARIANTS_PATH := "res://content/core_pack/character/emotes/face_variants.json"
const NO_PIVOT := Vector2(-1.0, -1.0)

# MapleStory composites have ~15 px of empty space between the shoes and the
# pivot_world floor reference (pivot_world.y = floor_world_ref). Without this
# shift, every pose hovers by that amount. Lowering the render by this offset
# preserves each animation's RELATIVE vertical intent (idle vs walk vs jumping
# emotes) while landing the shoes on the floor in standing poses.
const CHARACTER_FLOOR_OFFSET_PX := 10.0

# Per-action extra floor offset. Some WZ actions (prone/sleep) are authored
# with a pivot that leaves the body hovering at our standard offset — add
# more pixels so the character lies flat on the floor.
const ACTION_EXTRA_FLOOR_OFFSET := {
	"sleep": 15.0,
}

# Caches
var _texture_cache: Dictionary = {}        # path -> Texture2D or null
var _anim_pivot_cache: Dictionary = {}     # anim_json_path -> Array of Vector2
var _frame_meta_cache: Dictionary = {}     # texture_path -> Dictionary

# Emote state
var _emote_manifest: Dictionary = {}
var _face_variant_brow_px: Dictionary = {}  # variant name -> Vector2 brow pixel within image (origin + map/brow)
var _active_emote_semantic: String = "default"
var _active_face_variant: String = "default"

# Draw state (updated by apply_frame)
var _facing_right: bool = false
var _body_tex: Texture2D = null
var _body_pivot: Vector2 = NO_PIVOT
var _has_face: bool = false
var _face_local: Vector2 = Vector2.ZERO
var _face_default_path: String = ""
var _face_default_brow_px: Vector2 = Vector2.ZERO  # default face's brow pixel within image
var _last_resolved_variant: String = "default"
var _current_action: String = ""  # parsed from texture_path (e.g. "sleep")

# Overlay effect state (Effect.wz sprites — LevelUp etc.)
# Anchored at the actor's floor contact (= renderer local origin).
# Each frame has its own origin_px (foot-contact pivot within the PNG) and delay.
var _overlay_frames: Array = []       # [{tex, origin_px, delay_ms}]
var _overlay_frame_idx: int = -1
var _overlay_elapsed_ms: float = 0.0
var _overlay_loop: bool = false
var _overlay_anchor: String = ""       # "" = floor contact; "hand" = follow body hand
var _body_hand_world: Vector2 = Vector2.ZERO  # current body frame's hand anchor (world-rel)
var _has_hand_world: bool = false
var _body_pivot_world: Vector2 = Vector2.ZERO  # floor-contact point in world coords

# Back-layer overlay (chair/prop sprites). Drawn BEFORE body so the character
# sits in front of the chair.
var _back_overlay_frames: Array = []
var _back_overlay_frame_idx: int = -1
var _back_overlay_elapsed_ms: float = 0.0
var _back_overlay_loop: bool = false


func _ready() -> void:
	_load_emote_manifest()
	_load_face_variants()
	set_process(true)


func _process(delta: float) -> void:
	_tick_overlay(delta, false)
	_tick_overlay(delta, true)


func _tick_overlay(delta: float, back: bool) -> void:
	var frames: Array = _back_overlay_frames if back else _overlay_frames
	var idx: int = _back_overlay_frame_idx if back else _overlay_frame_idx
	if idx < 0 or frames.is_empty():
		return
	var elapsed: float = _back_overlay_elapsed_ms if back else _overlay_elapsed_ms
	elapsed += delta * 1000.0
	var frame: Dictionary = frames[idx]
	var frame_delay: float = float(frame.get("delay_ms", 90))
	if elapsed >= frame_delay:
		elapsed -= frame_delay
		idx += 1
		var loop: bool = _back_overlay_loop if back else _overlay_loop
		if idx >= frames.size():
			if loop:
				idx = 0
			else:
				idx = -1
				frames = []
		queue_redraw()
	if back:
		_back_overlay_frames = frames
		_back_overlay_frame_idx = idx
		_back_overlay_elapsed_ms = elapsed
	else:
		_overlay_frames = frames
		_overlay_frame_idx = idx
		_overlay_elapsed_ms = elapsed


func play_overlay(effect_id: String, loop: bool = false) -> void:
	_play_overlay_internal(effect_id, loop, false)


func stop_overlay() -> void:
	if _overlay_frame_idx < 0:
		return
	_overlay_frame_idx = -1
	_overlay_frames = []
	queue_redraw()


func play_back_overlay(effect_id: String, loop: bool = true) -> void:
	_play_overlay_internal(effect_id, loop, true)


func stop_back_overlay() -> void:
	if _back_overlay_frame_idx < 0:
		return
	_back_overlay_frame_idx = -1
	_back_overlay_frames = []
	queue_redraw()


func _play_overlay_internal(effect_id: String, loop: bool, back: bool) -> void:
	var manifest_path := "res://content/core_pack/effects/%s/effect.json" % effect_id
	var raw := _read_text(manifest_path)
	if raw == "":
		return
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var frames_v = (parsed as Dictionary).get("frames", [])
	if typeof(frames_v) != TYPE_ARRAY:
		return
	var frames_dir := "res://content/core_pack/effects/%s/frames/" % effect_id
	var out: Array = []
	var idx := 0
	for fv in frames_v as Array:
		if typeof(fv) != TYPE_DICTIONARY:
			continue
		var fd := fv as Dictionary
		var tex := _load_texture(frames_dir + "%03d.png" % idx)
		idx += 1
		if tex == null:
			continue
		var origin_v = fd.get("origin_px", [0, 0])
		var origin := Vector2.ZERO
		if typeof(origin_v) == TYPE_ARRAY and (origin_v as Array).size() >= 2:
			var oa := origin_v as Array
			origin = Vector2(float(oa[0]), float(oa[1]))
		out.append({
			"tex": tex,
			"origin_px": origin,
			"delay_ms": float(fd.get("delay_ms", 90)),
		})
	if out.is_empty():
		return
	if back:
		_back_overlay_frames = out
		_back_overlay_frame_idx = 0
		_back_overlay_elapsed_ms = 0.0
		_back_overlay_loop = loop
	else:
		_overlay_frames = out
		_overlay_frame_idx = 0
		_overlay_elapsed_ms = 0.0
		_overlay_loop = loop
		_overlay_anchor = str((parsed as Dictionary).get("anchor_to", ""))
	queue_redraw()


func _load_emote_manifest() -> void:
	var raw := _read_text(EMOTE_MANIFEST_PATH)
	if raw != "":
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			_emote_manifest = parsed as Dictionary


func _load_face_variants() -> void:
	var raw := _read_text(FACE_VARIANTS_PATH)
	if raw == "":
		return
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for key in (parsed as Dictionary).keys():
		var v = (parsed as Dictionary)[key]
		if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
			var a := v as Array
			_face_variant_brow_px[str(key)] = Vector2(float(a[0]), float(a[1]))


func apply_frame(frame_data: Dictionary) -> void:
	var texture_path := str(frame_data.get("texture_path", ""))
	if texture_path == "":
		_body_tex = null
		_has_face = false
		queue_redraw()
		return

	_body_tex = _load_texture(texture_path)
	_current_action = _action_from_texture_path(texture_path)

	var meta := _get_frame_meta(texture_path)
	_body_pivot = meta.get("pivot_px", NO_PIVOT)
	_body_pivot_world = meta.get("pivot_world", Vector2.ZERO)
	_has_hand_world = meta.has("hand_world")
	if _has_hand_world:
		_body_hand_world = meta["hand_world"]
	_has_face = meta.has("face_local")
	if _has_face:
		_face_local = meta["face_local"]
		_face_default_path = str(meta.get("face_default_path", ""))
		_face_default_brow_px = meta.get("face_default_brow_px", Vector2.ZERO)
	else:
		_face_default_path = ""
		_face_default_brow_px = Vector2.ZERO

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
	# Flip the whole renderer node around its local origin (= floor-contact column).
	# This keeps body, face, and any future overlays aligned to the same pivot.
	scale.x = -1.0 if _facing_right else 1.0
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

	# Apply the character-level floor offset uniformly so every animation keeps
	# its intended relative vertical position (idle's weapon tail stays below
	# the shoes, emotes stay raised). Per-frame visible-pixel scanning was
	# rejected because it locks onto incidental artifacts like the weapon tip
	# and flattens emotes against the floor.
	var extra_offset := float(ACTION_EXTRA_FLOOR_OFFSET.get(_current_action, 0.0))
	var eff_pivot := Vector2(
		pivot.x,
		clamp(pivot.y - CHARACTER_FLOOR_OFFSET_PX - extra_offset, 0.0, tex_size.y)
	)

	# Back-layer overlay (chair, props) — drawn BEFORE body so the character
	# sits in front. No counter-flip: chairs/props follow the character's
	# facing (the sit pose is asymmetric, and the chair should face the same
	# way the character does).
	if _back_overlay_frame_idx >= 0 and _back_overlay_frame_idx < _back_overlay_frames.size():
		var bo_data: Dictionary = _back_overlay_frames[_back_overlay_frame_idx]
		var bo_tex: Texture2D = bo_data["tex"]
		if bo_tex != null:
			var bo_origin: Vector2 = bo_data["origin_px"]
			var bo_size := bo_tex.get_size()
			draw_texture_rect(bo_tex, Rect2(-bo_origin, bo_size), false)

	# Facing flip is applied via the node's scale.x (see set_facing_from_axis),
	# which mirrors body, face, and any future overlay around x=0 uniformly.
	var body_rect := Rect2(-eff_pivot, tex_size)
	draw_texture_rect(_body_tex, body_rect, false)

	if _has_face and _face_default_path != "":
		var face_tex := _resolve_face_texture()
		if face_tex != null:
			var face_size := face_tex.get_size()
			# Re-anchor the face so the brow point stays where the default face
			# would have placed it. The default's top_left was computed for the
			# default origin; a variant canvas may be taller (angry) or shifted
			# (love), so we offset by (default_origin - variant_origin).
			var face_offset := _face_variant_origin_delta()
			var face_rect := Rect2(-eff_pivot + _face_local + face_offset, face_size)
			draw_texture_rect(face_tex, face_rect, false)

	# Overlay effect (LevelUp sparkle, etc.) drawn LAST so it sits on top of
	# both body and face. Counter-flip via draw_set_transform so the effect
	# stays world-oriented even when the character is mirrored by scale.x —
	# overlays are world-space events, not part of the character's silhouette.
	if _overlay_frame_idx >= 0 and _overlay_frame_idx < _overlay_frames.size():
		var of_data: Dictionary = _overlay_frames[_overlay_frame_idx]
		var of_tex: Texture2D = of_data["tex"]
		if of_tex != null:
			var of_origin: Vector2 = of_data["origin_px"]
			var of_size := of_tex.get_size()
			if _overlay_anchor == "hand" and _has_hand_world:
				# Held prop: track the body's per-frame hand anchor and flip with
				# the character (no counter-flip), like an equipped weapon.
				# world_anchors are relative to navel (world origin); pivot_world
				# is the floor-contact point in that same world frame. Convert
				# hand -> local by subtracting pivot_world, then apply the same
				# floor offset the body renders with.
				var extra := float(ACTION_EXTRA_FLOOR_OFFSET.get(_current_action, 0.0))
				var hand_local := (_body_hand_world - _body_pivot_world) + Vector2(0.0, CHARACTER_FLOOR_OFFSET_PX + extra)
				draw_texture_rect(of_tex, Rect2(hand_local - of_origin, of_size), false)
			else:
				# World-space effect: counter-flip so it stays world-oriented
				# even when the character is mirrored.
				var facing_scale := Vector2(-1.0, 1.0) if scale.x < 0.0 else Vector2.ONE
				draw_set_transform(Vector2.ZERO, 0.0, facing_scale)
				draw_texture_rect(of_tex, Rect2(-of_origin, of_size), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _face_variant_origin_delta() -> Vector2:
	# Only shift when the actually-rendered texture is a variant; otherwise
	# (fallback to default) we want the original top_left.
	if _last_resolved_variant == "" or _last_resolved_variant == "default":
		return Vector2.ZERO
	if not _face_variant_brow_px.has(_last_resolved_variant):
		return Vector2.ZERO
	var variant_brow: Vector2 = _face_variant_brow_px[_last_resolved_variant]
	return _face_default_brow_px - variant_brow


# --- Face resolution ---

func _resolve_face_texture() -> Texture2D:
	_last_resolved_variant = "default"
	var candidates: Array = []  # [{ "path": String, "variant": String }]
	if _active_face_variant != "default" and _active_face_variant != "":
		var variant_path := _make_variant_path(_face_default_path, _active_face_variant)
		if variant_path != "":
			candidates.append({"path": variant_path, "variant": _active_face_variant})
	candidates.append({"path": _face_default_path, "variant": "default"})

	for entry in candidates:
		var candidate := str(entry["path"])
		if candidate == "":
			continue
		if _texture_cache.has(candidate):
			var c = _texture_cache[candidate]
			if c is Texture2D:
				_last_resolved_variant = str(entry["variant"])
				return c as Texture2D
			continue
		var tex := _load_texture(candidate)
		if tex != null:
			_last_resolved_variant = str(entry["variant"])
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

	# pivot_px / pivot_world from animation JSON (one level up from frames/)
	var anim_json_path := _anim_json_path_for(texture_path)
	var frame_idx := _frame_idx_from_path(texture_path)
	if anim_json_path != "" and frame_idx >= 0:
		var pivots := _get_anim_pivots(anim_json_path)
		if frame_idx < pivots.size():
			var pe: Dictionary = pivots[frame_idx]
			if pe.has("pivot_px"):
				meta["pivot_px"] = pe["pivot_px"]
			if pe.has("pivot_world"):
				meta["pivot_world"] = pe["pivot_world"]

	# Face overlay from per-frame JSON
	var frame_json_path := texture_path.get_basename() + ".json"
	var raw := _read_text(frame_json_path)
	if raw == "":
		raw = _read_file(ProjectSettings.globalize_path(frame_json_path))

	if raw != "":
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			var d := parsed as Dictionary
			var wa_v = d.get("world_anchors", {})
			if typeof(wa_v) == TYPE_DICTIONARY:
				var hand_v = (wa_v as Dictionary).get("hand", null)
				if typeof(hand_v) == TYPE_ARRAY and (hand_v as Array).size() >= 2:
					var ha := hand_v as Array
					meta["hand_world"] = Vector2(float(ha[0]), float(ha[1]))
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
					# Combine origin + anchors_local.brow to get the brow pixel
					# within the default face image (what variant entries align to).
					var origin_px := Vector2.ZERO
					var origin_v = e.get("origin", [])
					if typeof(origin_v) == TYPE_ARRAY and (origin_v as Array).size() >= 2:
						var oa := origin_v as Array
						origin_px = Vector2(float(oa[0]), float(oa[1]))
					var brow_local := Vector2.ZERO
					var anchors_local_v = e.get("anchors_local", {})
					if typeof(anchors_local_v) == TYPE_DICTIONARY:
						var brow_v = (anchors_local_v as Dictionary).get("brow", [])
						if typeof(brow_v) == TYPE_ARRAY and (brow_v as Array).size() >= 2:
							var ba := brow_v as Array
							brow_local = Vector2(float(ba[0]), float(ba[1]))
					meta["face_default_brow_px"] = origin_px + brow_local
					break

	_frame_meta_cache[texture_path] = meta
	return meta


func _action_from_texture_path(texture_path: String) -> String:
	# .../animations/<action>/frames/000.png -> <action>
	var frames_dir := texture_path.get_base_dir()
	var anim_dir := frames_dir.get_base_dir()
	return anim_dir.get_file()


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
					var entry: Dictionary = {}
					if typeof(fv) == TYPE_DICTIONARY:
						var f := fv as Dictionary
						var pv = f.get("pivot_px", [])
						if typeof(pv) == TYPE_ARRAY and (pv as Array).size() >= 2:
							var pa := pv as Array
							entry["pivot_px"] = Vector2(float(pa[0]), float(pa[1]))
						var pw = f.get("pivot_world", [])
						if typeof(pw) == TYPE_ARRAY and (pw as Array).size() >= 2:
							var wa := pw as Array
							entry["pivot_world"] = Vector2(float(wa[0]), float(wa[1]))
					pivots.append(entry)

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
