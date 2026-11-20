extends SubViewportContainer

# The 3D view of the buddy's land (Plan 14 step 4, D-009): a small low-poly
# diorama built from Godot's own shapes in code, with the buddy standing in it
# as its existing 2D character on a card that faces the camera. It shows the
# time of day from the local clock, the world's weather, and mist over every
# place the buddy has not found yet.
#
# It is fed a snapshot Dictionary (see snapshot_from) and a frames Dictionary
# (set_card_frames) and never reads AppState, so the same script can run in a
# web export fed by a published snapshot (step 5). It only exists while its
# window is open: the owner of the window creates it and queue_frees it, and
# the viewport renders at most RENDER_FPS times a second while it lives.

signal place_clicked(place_id: String)

const WorldRules = preload("res://scripts/services/world_rules.gd")

const LAND_SIZE := 64.0
const WALK_SPEED := 1.6
# A little larger than life, so the buddy reads at the starting distance; the
# cottage door is made to fit it.
const CARD_HEIGHT := 2.0
const RENDER_FPS := 30.0
const MIST_STEP := 6.0
const MIST_RADIUS := 38.0
const CLEAR_RADIUS := 7.0
const PATH_CLEAR := 3.0
# Land farther than this from every place is beyond the land: always mist.
const MIST_NEAR := 14.0
const MIST_DENSE_ALPHA := 0.8
const MIST_THIN_ALPHA := 0.4
const EDGE_REACH := 5.0
# Where the camera starts: close enough to see the buddy, and you can zoom out.
const START_DISTANCE := 26.0
const MIN_DISTANCE := 10.0
const MAX_DISTANCE := 80.0
# The view's clock runs on between snapshots and is only put right when it is
# this far out, so a walk never jumps back to the snapshot's whole second.
const CLOCK_SLACK := 2.0
const POSE_BY_INTENT := {"rest": "sleep", "tend_home": "sit", "reflect": "idle", "explore": "happy"}
# The feet rest on top of the path strips (0.05 high), not inside them.
const CARD_LIFT := 0.06
const MIST_FADE_SECONDS := 4.0
const WEATHER_EASE_SECONDS := 6.0
const CLOUD_COUNT := 8

const GRASS := Color(0.40, 0.58, 0.32)
const PATH_TAN := Color(0.62, 0.55, 0.40)

# Set false by tests and the render harness that drive tick() themselves.
var live := true

var _built := false
var _viewport: SubViewport = null
var _world: Node3D = null
var _env: Environment = null
var _sun: DirectionalLight3D = null
var _camera: Camera3D = null
var _places_root: Node3D = null
var _paths_root: Node3D = null
var _labels_root: Node3D = null
var _mist_root: Node3D = null
var _clouds_root: Node3D = null
var _rain: CPUParticles3D = null
var _card: Node3D = null
var _sprite: Sprite3D = null
var _placeholder: MeshInstance3D = null
var _land_mat: StandardMaterial3D = null
var _mist_dense_mat: StandardMaterial3D = null
var _mist_thin_mat: StandardMaterial3D = null
var _fade: GradientTexture2D = null
var _window_mat: StandardMaterial3D = null
var _window_light: OmniLight3D = null
var _roof: MeshInstance3D = null
var _home_point := Vector3.ZERO
var _mat_cache := {}
var _mesh_cache := {}

var _snapshot := {}
var _frames := {}
var _have_snapshot := false
var _clock := 0.0
var _tz_bias := 0
var _known := {}
var _points := {}
var _all_points := {}
var _signature := ""
var _blobs: Array = []
var _cloud_discs: Array = []
var _cover_shown := 0.0
var _rain_shown := 0.0
var _cover_target := 0.0
var _rain_target := 0.0
var _applied := false
var _last_t := 0
var _walk_points: Array = []
var _walk_start := 0.0
var _stand_point := Vector3.ZERO
var _card_pos := Vector3.ZERO
var _card_walking := false
var _card_pose := ""
var _card_dir := Vector3.ZERO
var _flip := false
var _target := Vector3.ZERO
var _yaw := 0.6
var _pitch := deg_to_rad(50.0)
var _dist := START_DISTANCE
var _since_render := 1.0
var _pressing := false
var _drag_travel := 0.0
var _sky := {}


# --- pure helpers -----------------------------------------------------------

static func place_point(pos: Vector2) -> Vector3:
	return Vector3((pos.x - 0.5) * LAND_SIZE, 0.0, (pos.y - 0.5) * LAND_SIZE)


# The ground is flat except for the mound at the high ground; only found
# places are in points (id -> Vector3).
static func ground_height(points: Dictionary, xz: Vector3) -> float:
	if not points.has("high_ground"):
		return 0.0
	var centre: Vector3 = points["high_ground"]
	var d := Vector2(xz.x - centre.x, xz.z - centre.z).length()
	return 1.6 * clampf((9.0 - d) / 5.0, 0.0, 1.0)


# The shortest way between two places by ids, walking only through places in
# open (from_id and to_id are always allowed). Breadth-first; ties go to the
# path listed first. [to_id] for the same place, [] when there is no way.
static func route(paths: Array, from_id: String, to_id: String, open: Dictionary) -> Array:
	if from_id == to_id:
		return [to_id]
	var parent := {from_id: ""}
	var queue: Array = [from_id]
	var head := 0
	while head < queue.size():
		var here: String = queue[head]
		head += 1
		for path_variant in paths:
			if typeof(path_variant) != TYPE_ARRAY or (path_variant as Array).size() != 2:
				continue
			var a := str(path_variant[0])
			var b := str(path_variant[1])
			var next := ""
			if a == here:
				next = b
			elif b == here:
				next = a
			if next == "" or parent.has(next):
				continue
			if next != to_id and not open.has(next):
				continue
			parent[next] = here
			if next == to_id:
				var out: Array = [to_id]
				var back: String = here
				while back != "":
					out.push_front(back)
					back = str(parent[back])
				return out
			queue.append(next)
	return []


# Where a walk along a polyline of points has got to, start_t seconds in.
static func walk_at(points: Array, start_t: float, now: float, speed := WALK_SPEED) -> Dictionary:
	if points.is_empty():
		return {"pos": Vector3.ZERO, "walking": false, "dir": Vector3.ZERO}
	var left := maxf(0.0, now - start_t) * speed
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var length := a.distance_to(b)
		if length < 0.0001:
			continue
		if left <= length:
			return {"pos": a.lerp(b, left / length), "walking": true, "dir": (b - a) / length}
		left -= length
	return {"pos": points[points.size() - 1], "walking": false, "dir": Vector3.ZERO}


# The card's pose: walking, nothing while it is with you, awake and free, or
# what it is busy with.
static func card_pose(snapshot: Dictionary, now: float, walking: bool) -> String:
	if str(snapshot.get("where", "")) == "visiting":
		return ""
	if walking:
		return "wander"
	if now >= float(_to_int(snapshot.get("busy_until", 0))):
		return "idle"
	var last: Dictionary = _dict(snapshot.get("last", {}))
	return str(POSE_BY_INTENT.get(str(last.get("intent", "")), "idle"))


# Each spot of land belongs to its nearest place (points: every place, id ->
# Vector3), so finding a place clears the land round it. "clear" near a found
# place, on a path between two found places, or nearest a found place; "thin"
# when the nearest place is one it has only a sign of; else "dense". Farther
# than MIST_NEAR from every place is beyond the land, and always "dense".
static func mist_state(point: Vector3, points: Dictionary, known: Dictionary, found_segments: Array) -> String:
	var flat := Vector2(point.x, point.z)
	var nearest := ""
	var nearest_d := INF
	for id_variant in points.keys():
		var id := str(id_variant)
		var place: Vector3 = points[id_variant]
		var d := flat.distance_to(Vector2(place.x, place.z))
		if d <= CLEAR_RADIUS and str(known.get(id, "")) == "found":
			return "clear"
		if d < nearest_d:
			nearest_d = d
			nearest = id
	for segment_variant in found_segments:
		var segment: Array = segment_variant
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var closest := Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if flat.distance_to(closest) <= PATH_CLEAR:
			return "clear"
	if nearest == "" or nearest_d > MIST_NEAR:
		return "dense"
	match str(known.get(nearest, "")):
		"found":
			return "clear"
		"sign":
			return "thin"
	return "dense"


# The light for a local hour (0..24) and the weather ({"cover", "rain"}).
static func sky_at(hour: float, weather: Dictionary) -> Dictionary:
	var day := smoothstep(5.5, 7.0, hour) * (1.0 - smoothstep(19.0, 20.5, hour))
	var golden := clampf(maxf(1.0 - absf(hour - 6.5) / 1.25, 1.0 - absf(hour - 19.5) / 1.25), 0.0, 1.0)
	var night := 1.0 - day
	var elevation := deg_to_rad(55.0)
	var swing := 0.0
	if hour >= 6.0 and hour <= 20.0:
		elevation = maxf(deg_to_rad(8.0), deg_to_rad(70.0) * sin(PI * (hour - 6.0) / 14.0))
		swing = PI * (hour - 6.0) / 14.0
	else:
		swing = PI * clampf(fposmod(hour - 20.0, 24.0) / 10.0, 0.0, 1.0)
	# East (+X) through north (-Z) to west (-X); the light travels the other way.
	var to_sun := Vector3(cos(swing) * cos(elevation), sin(elevation), -sin(swing) * cos(elevation))
	var sun_color := Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.64, 0.40), golden).lerp(Color(0.58, 0.66, 0.90), night)
	var sun_energy := lerpf(lerpf(1.0, 0.7, golden), 0.22, night)
	var sky := Color(0.58, 0.75, 0.92).lerp(Color(0.95, 0.66, 0.48), golden).lerp(Color(0.04, 0.06, 0.13), night)
	var ambient := Color(0.70, 0.74, 0.78).lerp(Color(0.22, 0.27, 0.42), night)
	var ambient_energy := lerpf(0.55, 0.5, night)
	var card_tint := Color(1, 1, 1).lerp(Color(0.50, 0.55, 0.72), night)
	# The mist is drawn unlit (lit sheets would change with the camera), so its
	# colour carries the time of day: white by day, warm at the golden hours,
	# dim blue at night.
	var mist := Color(0.93, 0.94, 0.96).lerp(Color(0.98, 0.84, 0.72), golden * 0.5).lerp(Color(0.28, 0.32, 0.44), night)
	var cover := clampf(float(weather.get("cover", 0.0)), 0.0, 1.0)
	var rain := clampf(float(weather.get("rain", 0.0)), 0.0, 1.0)
	sun_energy *= (1.0 - 0.55 * cover) * (1.0 - 0.3 * rain)
	sky = sky.lerp(Color(0.60, 0.63, 0.67) * (0.15 + 0.85 * day), 0.6 * cover)
	sky.a = 1.0
	mist = mist.lerp(Color(0.74, 0.76, 0.80) * (0.3 + 0.7 * day), 0.4 * cover)
	mist.a = 1.0
	ambient_energy *= 1.0 - 0.1 * rain
	var tint := 1.0 - 0.18 * rain
	return {"sun_dir": -to_sun, "sun_color": sun_color, "sun_energy": sun_energy, "ambient": ambient,
		"ambient_energy": ambient_energy, "sky": sky, "night": night, "card_tint": card_tint,
		"ground_tint": Color(tint, tint, tint), "mist": mist}


# Everything the view shows, from the save. Tolerant of missing or wrongly typed
# fields: the save is data.
static func snapshot_from(profile: Dictionary, land: Dictionary, layout: Dictionary, small: bool, now: int,
		tz_bias_minutes: int, buddy_name: String) -> Dictionary:
	var positions: Dictionary = _dict(layout.get("positions", {}))
	var places: Array = []
	for place_variant in _arr(land.get("places", [])):
		if typeof(place_variant) != TYPE_DICTIONARY:
			continue
		var place: Dictionary = place_variant
		var id := _str(place.get("id", ""))
		if id == "" or not (positions.get(id, null) is Vector2):
			continue
		places.append({"id": id, "name": _str(place.get("name", id)), "kind": _str(place.get("kind", "")),
			"pos": positions[id]})
	var paths: Array = []
	for path_variant in _arr(layout.get("paths", [])):
		if typeof(path_variant) == TYPE_ARRAY and (path_variant as Array).size() == 2:
			paths.append([_str(path_variant[0]), _str(path_variant[1])])
	var home := _str(land.get("home_place", "home"))
	if home == "":
		home = "home"
	var mind: Dictionary = _dict(profile.get("mind", {}))
	var known := {}
	if small:
		for id_variant in _dict(mind.get("known_places", {})).keys():
			var record_variant = (mind["known_places"] as Dictionary)[id_variant]
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var stage := _str((record_variant as Dictionary).get("stage", ""))
			if stage == "found" or stage == "sign":
				known[_str(id_variant)] = stage
		known[home] = "found"
	else:
		for place_row in places:
			known[str((place_row as Dictionary)["id"])] = "found"
	var where := _str(mind.get("location", ""))
	if where == "":
		where = home
	var last := {}
	var came_from := ""
	var seen_last := false
	var journal: Array = _arr(mind.get("journal", []))
	for index in range(journal.size() - 1, -1, -1):
		if typeof(journal[index]) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = journal[index]
		if not seen_last:
			seen_last = true
			var edge := ""
			var toward := ""
			for pair in [["sign", "sign_of"], ["blocked", "blocked_at"], ["found", "found_place"]]:
				if _str(entry.get(pair[1], "")) != "":
					edge = pair[0]
					toward = _str(entry.get(pair[1], ""))
					break
			last = {"t": _to_int(entry.get("t", 0)), "place_id": _str(entry.get("place_id", "")),
				"intent": _str(entry.get("intent", "")), "activity_id": _str(entry.get("activity_id", "")),
				"label": _str(entry.get("activity_label", "")), "edge": edge, "toward": toward}
		else:
			came_from = _str(entry.get("place_id", ""))
			break
	return {
		"name": buddy_name if buddy_name != "" else "Buddy",
		"now": now,
		"tz_bias_minutes": tz_bias_minutes,
		"small": small,
		"home": home,
		"places": places,
		"paths": paths,
		"known": known,
		"where": where,
		"last": last,
		"came_from": came_from,
		"busy_until": _to_int(mind.get("busy_until", 0)),
		"weather": WorldRules.weather(_to_int(profile.get("personality_seed", 0)), now, tz_bias_minutes),
	}


static func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _arr(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


static func _str(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME, TYPE_INT, TYPE_FLOAT:
			return str(value)
	return ""


static func _to_int(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			return (value as String).to_int()
	return 0


# --- the scene --------------------------------------------------------------

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if size.x > 1.0 and size.y > 1.0:
		_viewport.size = Vector2i(int(size.x), int(size.y))
	add_child(_viewport)
	_world = Node3D.new()
	_world.name = "World"
	_viewport.add_child(_world)

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	env_node.environment = _env
	_world.add_child(env_node)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = false
	_world.add_child(_sun)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 45.0
	_camera.near = 0.5
	_camera.far = 400.0
	_world.add_child(_camera)

	var ground := Node3D.new()
	ground.name = "Ground"
	_world.add_child(ground)
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	var plane_node := MeshInstance3D.new()
	plane_node.mesh = plane
	# Pale, so the world beyond the land reads as more mist.
	plane_node.material_override = _mat(Color(0.60, 0.65, 0.62))
	ground.add_child(plane_node)
	_land_mat = StandardMaterial3D.new()
	_land_mat.albedo_color = GRASS
	_land_mat.roughness = 1.0
	_land_mat.metallic = 0.0
	var disc := CylinderMesh.new()
	disc.top_radius = 44.0
	disc.bottom_radius = 44.0
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	var disc_node := MeshInstance3D.new()
	disc_node.mesh = disc
	disc_node.material_override = _land_mat
	disc_node.position = Vector3(0.0, 0.01, 0.0)
	ground.add_child(disc_node)

	_places_root = _node3d("Places")
	_paths_root = _node3d("Paths")
	_labels_root = _node3d("Labels")
	_mist_root = _node3d("Mist")
	_clouds_root = _node3d("CloudShadows")
	_build_mist()
	_build_clouds()
	_build_rain()
	_build_card()
	_built = true
	_apply_camera()
	if _have_snapshot:
		_apply_snapshot()
	_apply_card_frames()


func _node3d(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	_world.add_child(node)
	return node


# Soft sheets of mist lying over the land, two to a spot: each fades from its
# middle to nothing at its rim, so they melt into each other with no edges. They
# lie flat, so they never cut into the ground the way an upright sprite would.
func _build_mist() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("mist")
	_mist_dense_mat = _mist_material(_fade_texture(), MIST_DENSE_ALPHA)
	_mist_thin_mat = _mist_material(_fade_texture(), MIST_THIN_ALPHA)
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(1.0, 1.0)
	var spots: Array = []
	var steps := int(MIST_RADIUS / MIST_STEP) + 1
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			var p := Vector3(ix * MIST_STEP + rng.randf_range(-1.5, 1.5), 0.0, iz * MIST_STEP + rng.randf_range(-1.5, 1.5))
			if p.length() <= MIST_RADIUS:
				spots.append({"p": p, "edge": false})
	for i in range(28):
		var angle := TAU * float(i) / 28.0
		var radius := rng.randf_range(42.0, 48.0)
		spots.append({"p": Vector3(cos(angle) * radius, 0.0, sin(angle) * radius), "edge": true})
	var n := 0
	for spot_variant in spots:
		var spot: Dictionary = spot_variant
		var at: Vector3 = spot["p"]
		var edge := bool(spot["edge"])
		for layer in range(2):
			var node := MeshInstance3D.new()
			node.name = "Mist_%d" % n
			node.mesh = sheet
			node.material_override = _mist_dense_mat
			var width := (15.0 if edge else 10.5) * (1.0 if layer == 0 else 0.8) * rng.randf_range(0.9, 1.15)
			var base_scale := Vector3(width, 1.0, width)
			var base := at
			if layer == 1:
				base += Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
			var lift := 0.5 + 1.1 * float(layer) + (0.6 if edge else 0.0)
			node.scale = base_scale
			node.position = base + Vector3(0.0, lift, 0.0)
			_mist_root.add_child(node)
			_blobs.append({"node": node, "spot": at, "base": base, "lift": lift, "phase": float(n) * 1.7,
				"scale": base_scale, "edge": edge, "state": "dense", "shrink": -1.0})
			n += 1


# A round fade from solid in the middle to nothing at the rim, shared by the mist
# and the cloud shadows. Built in code: no image files.
func _fade_texture() -> GradientTexture2D:
	if _fade != null:
		return _fade
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	_fade = GradientTexture2D.new()
	_fade.gradient = gradient
	_fade.fill = GradientTexture2D.FILL_RADIAL
	_fade.fill_from = Vector2(0.5, 0.5)
	_fade.fill_to = Vector2(0.5, 0.0)
	_fade.width = 64
	_fade.height = 64
	return _fade


func _mist_material(texture: Texture2D, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = texture
	mat.albedo_color = Color(0.93, 0.94, 0.96, alpha)
	return mat


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("clouds")
	# Soft-edged like the mist, so a cloud's shadow has no hard rim.
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_texture = _fade_texture()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.3)
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(1.0, 1.0)
	for i in range(CLOUD_COUNT):
		var width := rng.randf_range(14.0, 22.0)
		var node := MeshInstance3D.new()
		node.name = "Cloud_%d" % i
		node.mesh = sheet
		node.material_override = shadow_mat
		node.scale = Vector3(width, 1.0, width * rng.randf_range(0.6, 0.9))
		node.position = Vector3(-50.0 + 12.5 * i, 0.1 + 0.004 * i, rng.randf_range(-30.0, 30.0))
		node.visible = false
		_clouds_root.add_child(node)
		_cloud_discs.append(node)


func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 500
	_rain.lifetime = 1.1
	_rain.preprocess = 1.1
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(30.0, 0.5, 30.0)
	_rain.direction = Vector3(0.0, -1.0, 0.0)
	_rain.spread = 0.0
	_rain.initial_velocity_min = 18.0
	_rain.initial_velocity_max = 22.0
	_rain.gravity = Vector3(0.0, -2.0, 0.0)
	var streak := BoxMesh.new()
	streak.size = Vector3(0.02, 0.6, 0.02)
	streak.material = _mat(Color(0.72, 0.78, 0.86), 0.45, true)
	_rain.mesh = streak
	_rain.position = Vector3(0.0, 22.0, 0.0)
	_rain.emitting = false
	_world.add_child(_rain)


func _build_card() -> void:
	_card = Node3D.new()
	_card.name = "Card"
	_world.add_child(_card)
	_sprite = Sprite3D.new()
	_sprite.name = "Sprite"
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.centered = true
	_sprite.pixel_size = 0.02
	_card.add_child(_sprite)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	_placeholder = MeshInstance3D.new()
	_placeholder.name = "Placeholder"
	_placeholder.mesh = capsule
	_placeholder.material_override = _mat(Color(0.95, 0.80, 0.35), 1.0, true)
	_placeholder.position = Vector3(0.0, 0.8, 0.0)
	_card.add_child(_placeholder)
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.45
	shadow_mesh.bottom_radius = 0.45
	shadow_mesh.height = 0.01
	shadow_mesh.radial_segments = 12
	shadow_mesh.rings = 1
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = shadow_mesh
	shadow.material_override = _mat(Color(0, 0, 0), 0.35, true)
	shadow.position = Vector3(0.0, 0.02, 0.0)
	_card.add_child(shadow)


# --- shapes and materials ---------------------------------------------------

func _mat(color: Color, alpha := 1.0, unshaded := false, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(true), alpha, unshaded, emission]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.roughness = 1.0
	mat.metallic = 0.0
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	_mat_cache[key] = mat
	return mat


# The flat-shaded low-poly look: every triangle gets its own vertices and one
# face normal, instead of the smooth normals a primitive mesh comes with.
func _faceted(mesh: PrimitiveMesh, key: String) -> Mesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	# The headless renderer keeps no mesh data to read back (asking prints an
	# error per shape), and nothing is drawn there anyway: the plain shape does.
	if DisplayServer.get_name() == "headless":
		_mesh_cache[key] = mesh
		return mesh
	var arrays: Array = mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i in range(verts.size()):
			indices.append(i)
	var out_verts := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var tri := 0
	while tri + 2 < indices.size():
		var ia := indices[tri]
		var ib := indices[tri + 1]
		var ic := indices[tri + 2]
		tri += 3
		var average: Vector3 = normals[ia] + normals[ib] + normals[ic]
		var face: Vector3 = (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		if face.length_squared() < 0.0000001:
			face = average
		elif face.dot(average) < 0.0:
			face = -face
		face = face.normalized()
		out_verts.append(verts[ia])
		out_verts.append(verts[ib])
		out_verts.append(verts[ic])
		for k in range(3):
			out_normals.append(face)
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = out_verts
	out_arrays[Mesh.ARRAY_NORMAL] = out_normals
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	_mesh_cache[key] = out
	return out


func _box_mesh(size: Vector3) -> Mesh:
	var key := "box|%s" % size
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	return _faceted(mesh, key)


func _cyl_mesh(top: float, bottom: float, height: float, sides: int) -> Mesh:
	var key := "cyl|%s|%s|%s|%d" % [top, bottom, height, sides]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return _faceted(mesh, key)


func _sphere_mesh(radius: float, segments: int, rings: int) -> Mesh:
	var key := "sphere|%s|%d|%d" % [radius, segments, rings]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return _faceted(mesh, key)


func _prism_mesh(size: Vector3) -> Mesh:
	var key := "prism|%s" % size
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := PrismMesh.new()
	mesh.size = size
	return _faceted(mesh, key)


func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot_deg := Vector3.ZERO,
		scl := Vector3.ONE, node_name := "") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color)
	node.position = pos
	node.rotation_degrees = rot_deg
	node.scale = scl
	if node_name != "":
		node.name = node_name
	parent.add_child(node)
	return node


# A point on a ring round the place, spread evenly with a little jitter.
func _ring_point(rng: RandomNumberGenerator, index: int, count: int, r_min: float, r_max: float) -> Vector3:
	var angle := TAU * (float(index) + rng.randf() * 0.6) / float(maxi(1, count))
	var radius := rng.randf_range(r_min, r_max)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


# --- places -----------------------------------------------------------------

# Direction from a place toward the other end of its first path.
func _neighbour_dir(id: String) -> Vector3:
	for path_variant in _arr(_snapshot.get("paths", [])):
		var path: Array = path_variant
		var other := ""
		if str(path[0]) == id:
			other = str(path[1])
		elif str(path[1]) == id:
			other = str(path[0])
		if other != "" and _all_points.has(other) and _all_points.has(id):
			var d: Vector3 = _all_points[other] - _all_points[id]
			d.y = 0.0
			if d.length() > 0.01:
				return d.normalized()
	return Vector3(0.0, 0.0, 1.0)


func _outward(point: Vector3) -> Vector3:
	var flat := Vector3(point.x, 0.0, point.z)
	if flat.length() < 0.01:
		return Vector3(0.0, 0.0, -1.0)
	return flat.normalized()


func _label_height(id: String, kind: String, point: Vector3) -> float:
	match id:
		"big_tree":
			return 7.5
		"dark_trees":
			return 6.0
		"home":
			return 4.6
		"high_ground":
			return ground_height(_points, point) + 2.6
	if kind == "home":
		return 4.6
	if kind == "park" and id != "patch" and id != "long_grass":
		return 7.5
	if ["square", "cafe", "shop", "library"].has(kind):
		return 4.2
	return 2.6


func _rebuild_places() -> void:
	for root in [_places_root, _paths_root, _labels_root]:
		for child in (root as Node3D).get_children():
			(root as Node3D).remove_child(child)
			child.queue_free()
	_roof = null
	_window_light = null
	_window_mat = null
	for place_variant in _arr(_snapshot.get("places", [])):
		var place: Dictionary = place_variant
		var id := str(place["id"])
		if str(_known.get(id, "")) != "found":
			continue
		var point: Vector3 = _all_points[id]
		var node := Node3D.new()
		node.name = "Place_%s" % id
		node.position = point
		_places_root.add_child(node)
		_build_place(node, id, str(place.get("kind", "")), point)
		var label := Label3D.new()
		label.name = "Label_%s" % id
		label.text = str(place.get("name", id))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.02
		label.font_size = 32
		label.outline_size = 10
		label.modulate = Color(1, 1, 1)
		label.outline_modulate = Color(0.08, 0.08, 0.1)
		label.position = point + Vector3(0.0, _label_height(id, str(place.get("kind", "")), point), 0.0)
		_labels_root.add_child(label)
	for path_variant in _arr(_snapshot.get("paths", [])):
		var path: Array = path_variant
		var from_id := str(path[0])
		var to_id := str(path[1])
		if str(_known.get(from_id, "")) != "found" or str(_known.get(to_id, "")) != "found":
			continue
		if not _all_points.has(from_id) or not _all_points.has(to_id):
			continue
		var a: Vector3 = _all_points[from_id]
		var b: Vector3 = _all_points[to_id]
		var length := a.distance_to(b)
		if length < 0.1:
			continue
		var strip := _add(_paths_root, _box_mesh(Vector3(1.4, 0.04, length)), PATH_TAN,
			(a + b) * 0.5 + Vector3(0.0, 0.03, 0.0), Vector3.ZERO, Vector3.ONE, "Path_%s_%s" % [from_id, to_id])
		strip.rotation.y = atan2(b.x - a.x, b.z - a.z)


func _build_place(root: Node3D, id: String, kind: String, point: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var out := _outward(point)
	match id:
		"home":
			_build_cottage(root, id)
		"yard":
			_add(root, _box_mesh(Vector3(6.0, 0.04, 5.0)), Color(0.66, 0.58, 0.42), Vector3(0.0, 0.02, 0.0))
			_add(root, _box_mesh(Vector3(1.2, 0.25, 0.6)), Color(0.55, 0.52, 0.48),
				_neighbour_dir(id) * 2.4 + Vector3(0.0, 0.125, 0.0))
		"wood_heap":
			var stack := Node3D.new()
			stack.position = out * 1.4
			stack.rotation.y = atan2(out.x, out.z)
			root.add_child(stack)
			var bark := Color(0.45, 0.30, 0.18)
			var log_mesh := _cyl_mesh(0.22, 0.22, 2.0, 7)
			for i in range(4):
				_add(stack, log_mesh, bark, Vector3(-0.66 + 0.44 * i, 0.22, 0.0), Vector3(90, 0, 0))
			for i in range(3):
				_add(stack, log_mesh, bark, Vector3(-0.44 + 0.44 * i, 0.6, 0.0), Vector3(90, 0, 0))
		"big_tree":
			_build_big_tree(root, out, rng)
		"patch":
			var green := Color(0.34, 0.52, 0.26)
			for i in range(10):
				var spot := _ring_point(rng, i, 10, 1.2, 3.5)
				var r := rng.randf_range(0.5, 0.9)
				_add(root, _sphere_mesh(r, 7, 4), green.lerp(Color(0.28, 0.46, 0.22), rng.randf()),
					spot + Vector3(0.0, r * 0.3, 0.0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
			for i in range(8):
				var spot := _ring_point(rng, i, 8, 1.0, 3.8)
				_add(root, _box_mesh(Vector3(0.12, 0.12, 0.12)), Color(0.95, 0.85, 0.25), spot + Vector3(0.0, 0.12, 0.0),
					Vector3(0.0, rng.randf_range(0.0, 90.0), 0.0))
		"gate":
			_build_gate(root, id)
		"high_ground":
			_add(root, _cyl_mesh(4.0, 9.0, 1.6, 10), Color(0.48, 0.62, 0.36), Vector3(0.0, 0.8, 0.0))
		"long_grass":
			for i in range(26):
				var h := rng.randf_range(0.9, 1.4)
				_add(root, _cyl_mesh(0.0, 0.12, h, 4), Color(0.62, 0.66, 0.32).lerp(Color(0.50, 0.58, 0.28), rng.randf()),
					_ring_point(rng, i, 26, 1.0, 5.0) + Vector3(0.0, h * 0.5, 0.0))
		"water":
			_add(root, _cyl_mesh(4.9, 4.9, 0.05, 14), Color(0.20, 0.34, 0.50), out * 4.8 + Vector3(0.0, 0.025, 0.0))
			_add(root, _cyl_mesh(4.5, 4.5, 0.06, 14), Color(0.25, 0.45, 0.65), out * 4.8 + Vector3(0.0, 0.03, 0.0))
		"stony_ground":
			for i in range(9):
				var r := rng.randf_range(0.4, 0.9)
				_add(root, _sphere_mesh(r, 6, 3), Color(0.55, 0.55, 0.53).lerp(Color(0.45, 0.45, 0.44), rng.randf()),
					_ring_point(rng, i, 9, 1.0, 4.0) + Vector3(0.0, r * 0.3, 0.0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		"grey_bank":
			_add(root, _sphere_mesh(2.4, 8, 5), Color(0.50, 0.46, 0.40), out * 2.5, Vector3.ZERO, Vector3(1.0, 0.25, 1.0))
		"sandy_bend":
			_add(root, _cyl_mesh(3.2, 3.2, 0.04, 12), Color(0.82, 0.74, 0.52), out * 1.5 + Vector3(0.0, 0.03, 0.0))
		"tall_reeds":
			for i in range(24):
				var h := rng.randf_range(1.4, 2.2)
				var spot := _ring_point(rng, i, 24, 1.2, 3.5)
				_add(root, _cyl_mesh(0.04, 0.04, h, 4), Color(0.45, 0.50, 0.25), spot + Vector3(0.0, h * 0.5, 0.0))
				if i % 3 == 0:
					_add(root, _cyl_mesh(0.08, 0.08, 0.3, 5), Color(0.40, 0.28, 0.16), spot + Vector3(0.0, h, 0.0))
		"dark_trees":
			for i in range(8):
				var spot := _ring_point(rng, i, 8, 2.0, 6.0)
				var h := rng.randf_range(3.0, 4.5)
				_add(root, _cyl_mesh(0.2, 0.25, 1.0, 6), Color(0.30, 0.20, 0.14), spot + Vector3(0.0, 0.5, 0.0))
				_add(root, _cyl_mesh(0.0, rng.randf_range(1.2, 1.6), h, 7), Color(0.14, 0.30, 0.18),
					spot + Vector3(0.0, 0.8 + h * 0.5, 0.0))
		_:
			match kind:
				"home":
					_build_cottage(root, id)
				"park":
					_build_big_tree(root, out, rng)
				"water":
					_add(root, _cyl_mesh(4.5, 4.5, 0.06, 14), Color(0.25, 0.45, 0.65), out * 4.8 + Vector3(0.0, 0.03, 0.0))
				_:
					_build_small_building(root, kind, out)


func _build_cottage(root: Node3D, id: String) -> void:
	_home_point = root.position
	var house := Node3D.new()
	house.name = "House"
	var front := _neighbour_dir(id)
	house.rotation.y = atan2(front.x, front.z)
	root.add_child(house)
	var wall := Color(0.86, 0.80, 0.66)
	# Four wall slabs round a floor, so the inside can be seen with the roof off.
	# The door fits the card (CARD_HEIGHT).
	_add(house, _box_mesh(Vector3(4.0, 0.03, 3.2)), Color(0.50, 0.38, 0.26), Vector3(0.0, 0.035, 0.0))
	_add(house, _box_mesh(Vector3(4.2, 2.6, 0.2)), wall, Vector3(0.0, 1.3, 1.6))
	_add(house, _box_mesh(Vector3(4.2, 2.6, 0.2)), wall, Vector3(0.0, 1.3, -1.6))
	_add(house, _box_mesh(Vector3(0.2, 2.6, 3.0)), wall, Vector3(2.0, 1.3, 0.0))
	_add(house, _box_mesh(Vector3(0.2, 2.6, 3.0)), wall, Vector3(-2.0, 1.3, 0.0))
	_add(house, _box_mesh(Vector3(1.0, 2.1, 0.1)), Color(0.32, 0.20, 0.12), Vector3(0.0, 1.05, 1.72))
	_roof = _add(house, _prism_mesh(Vector3(4.8, 1.5, 3.8)), Color(0.62, 0.30, 0.22), Vector3(0.0, 3.35, 0.0),
		Vector3.ZERO, Vector3.ONE, "Roof")
	_add(house, _box_mesh(Vector3(0.5, 1.2, 0.5)), Color(0.45, 0.36, 0.32), Vector3(1.4, 3.5, -0.6))
	_window_mat = StandardMaterial3D.new()
	_window_mat.albedo_color = Color(1.0, 0.82, 0.45)
	_window_mat.roughness = 1.0
	_window_mat.emission_enabled = true
	_window_mat.emission = Color(1.0, 0.82, 0.45)
	_window_mat.emission_energy_multiplier = 0.0
	var window := _add(house, _box_mesh(Vector3(0.1, 0.7, 0.8)), Color(1.0, 0.82, 0.45), Vector3(2.08, 1.6, 0.0))
	window.material_override = _window_mat
	var glow := _add(house, _box_mesh(Vector3(0.5, 0.5, 0.5)), Color(0.55, 0.95, 0.95), Vector3(-1.5, 0.3, -1.1),
		Vector3.ZERO, Vector3.ONE, "GlowingBox")
	glow.material_override = _mat(Color(0.55, 0.95, 0.95), 1.0, false, 1.5)
	_window_light = OmniLight3D.new()
	_window_light.name = "WindowLight"
	_window_light.omni_range = 7.0
	_window_light.light_energy = 0.0
	_window_light.light_color = Color(1.0, 0.82, 0.45)
	_window_light.shadow_enabled = false
	_window_light.position = Vector3(1.6, 1.6, 0.0)
	house.add_child(_window_light)


func _build_big_tree(root: Node3D, out: Vector3, rng: RandomNumberGenerator) -> void:
	var trunk_at := out * 1.6
	_add(root, _cyl_mesh(0.35, 0.55, 4.2, 7), Color(0.40, 0.28, 0.18), trunk_at + Vector3(0.0, 2.1, 0.0))
	var leaf := Color(0.22, 0.45, 0.22)
	for i in range(3):
		var r := rng.randf_range(2.2, 2.8)
		var angle := TAU * float(i) / 3.0 + rng.randf() * 0.5
		_add(root, _sphere_mesh(r, 8, 5), leaf.lerp(Color(0.18, 0.38, 0.20), rng.randf()),
			trunk_at + Vector3(cos(angle) * 1.0, 4.8 + rng.randf_range(-0.3, 0.5), sin(angle) * 1.0))


func _build_gate(root: Node3D, id: String) -> void:
	var toward := _neighbour_dir(id)
	var side := Vector3(-toward.z, 0.0, toward.x)
	var fence := Node3D.new()
	fence.name = "Fence"
	fence.rotation.y = atan2(-side.z, side.x)
	root.add_child(fence)
	var wood := Color(0.50, 0.44, 0.36)
	for x in [-6.0, -4.0, -2.0, -0.8, 0.8, 2.0, 4.0, 6.0]:
		_add(fence, _box_mesh(Vector3(0.18, 1.2, 0.18)), wood, Vector3(x, 0.6, 0.0))
	for sign_x in [-1.0, 1.0]:
		var from_x := 0.8 if sign_x > 0.0 else -6.0
		var to_x := 6.0 if sign_x > 0.0 else -0.8
		for rail_y in [0.5, 0.95]:
			_add(fence, _box_mesh(Vector3(to_x - from_x, 0.1, 0.08)), wood, Vector3((from_x + to_x) * 0.5, rail_y, 0.0))
	# The gate panel, swung open on its hinge at one post.
	var panel := Node3D.new()
	panel.position = Vector3(0.8, 0.0, 0.0)
	panel.rotation_degrees = Vector3(0.0, 70.0, 0.0)
	fence.add_child(panel)
	_add(panel, _box_mesh(Vector3(1.6, 0.8, 0.06)), Color(0.58, 0.50, 0.38), Vector3(0.8, 0.6, 0.0))


func _build_small_building(root: Node3D, kind: String, out: Vector3) -> void:
	var colors := {"square": Color(0.55, 0.55, 0.62), "cafe": Color(0.70, 0.45, 0.35),
		"shop": Color(0.68, 0.56, 0.30), "library": Color(0.45, 0.40, 0.66)}
	var tone: Color = colors.get(kind, Color(0.60, 0.55, 0.50))
	var building := Node3D.new()
	building.rotation.y = atan2(out.x, out.z)
	root.add_child(building)
	_add(building, _box_mesh(Vector3(3.0, 2.4, 3.0)), tone, Vector3(0.0, 1.2, 0.0))
	_add(building, _prism_mesh(Vector3(3.6, 1.2, 3.4)), tone.darkened(0.35), Vector3(0.0, 3.0, 0.0))


# --- feeding the view -------------------------------------------------------

func set_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_have_snapshot = true
	if _built:
		_apply_snapshot()


func set_card_frames(frames: Dictionary) -> void:
	_frames = frames
	if _built:
		_apply_card_frames()


func set_camera(yaw: float, pitch_deg: float, distance: float) -> void:
	_yaw = yaw
	_pitch = clampf(deg_to_rad(pitch_deg), deg_to_rad(22.0), deg_to_rad(78.0))
	_dist = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	if _built:
		_apply_camera()


func _apply_card_frames() -> void:
	var idle: Dictionary = _dict(_frames.get("idle", {}))
	var frames: Array = _arr(idle.get("frames", []))
	var has_art := not frames.is_empty() and frames[0] is Texture2D
	_sprite.visible = has_art
	_placeholder.visible = not has_art
	if has_art:
		# Scaled by the character itself, not its frame: a frame can carry empty
		# space round the character. (No image headless; then the frame's height.)
		var texture: Texture2D = frames[0]
		var height := float(texture.get_height())
		var image := texture.get_image()
		if image != null and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			var used := image.get_used_rect()
			if used.size.y > 0:
				height = float(used.size.y)
		_sprite.pixel_size = CARD_HEIGHT / maxf(1.0, height)
	else:
		_sprite.pixel_size = 0.02


func _apply_snapshot() -> void:
	var first := not _applied
	_applied = true
	_tz_bias = _to_int(_snapshot.get("tz_bias_minutes", 0))
	var snapshot_now := float(_to_int(_snapshot.get("now", 0)))
	if first or absf(snapshot_now - _clock) > CLOCK_SLACK:
		_clock = snapshot_now
	_known = _dict(_snapshot.get("known", {}))
	_all_points.clear()
	_points.clear()
	for place_variant in _arr(_snapshot.get("places", [])):
		var place: Dictionary = place_variant
		var id := str(place["id"])
		var pos: Vector2 = place["pos"]
		_all_points[id] = place_point(pos)
		if str(_known.get(id, "")) == "found":
			_points[id] = _all_points[id]
	var found_ids: Array = _points.keys()
	found_ids.sort()
	var signature := "%s|%s|%s" % [",".join(PackedStringArray(found_ids)), str(_snapshot.get("paths", [])), str(_snapshot.get("home", ""))]
	if signature != _signature:
		_signature = signature
		_rebuild_places()
	_update_mist_states(first)
	_plan_movement(first)
	var weather: Dictionary = _dict(_snapshot.get("weather", {}))
	_cover_target = clampf(float(weather.get("cover", 0.0)), 0.0, 1.0)
	_rain_target = clampf(float(weather.get("rain", 0.0)), 0.0, 1.0)
	if first:
		_cover_shown = _cover_target
		_rain_shown = _rain_target
	_update_card(0.0)
	if first:
		_target = _card_pos if _card.visible else _home_or_zero()
		_apply_camera()
	_update_sky()


func _home_or_zero() -> Vector3:
	var home := str(_snapshot.get("home", "home"))
	return _all_points.get(home, Vector3.ZERO)


# Where the card stands, and the walk it is on if it has just come from
# somewhere else.
func _plan_movement(first: bool) -> void:
	var home := str(_snapshot.get("home", "home"))
	var where := str(_snapshot.get("where", home))
	if where == "":
		where = home
	var last: Dictionary = _dict(_snapshot.get("last", {}))
	var came_from := str(_snapshot.get("came_from", ""))
	var origin: Vector3 = _all_points.get(where, _all_points.get(home, Vector3.ZERO))
	var edge_point := origin
	var edge_try := false
	var edge := str(last.get("edge", ""))
	var toward := str(last.get("toward", ""))
	if (edge == "sign" or edge == "blocked") and _all_points.has(toward):
		var d: Vector3 = _all_points[toward] - origin
		d.y = 0.0
		if d.length() > 0.01:
			edge_point = origin + d.normalized() * EDGE_REACH
			edge_try = true
	_stand_point = edge_point
	_walk_points = []
	if str(last.get("place_id", "")) == where and came_from != "" and came_from != where and _all_points.has(came_from):
		var open := {}
		for id in _known.keys():
			if str(_known[id]) == "found":
				open[id] = true
		var ids := route(_arr(_snapshot.get("paths", [])), came_from, where, open)
		if not ids.is_empty():
			var points: Array = []
			for id in ids:
				points.append(_all_points[str(id)])
			if edge_try:
				points.append(edge_point)
			_walk_points = points
	if _walk_points.is_empty() and edge_try and (came_from == where or came_from == ""):
		# A try from where it already was: it walks out to the edge and looks.
		_walk_points = [origin, edge_point]
	var seen_t := _to_int(last.get("t", 0))
	if first:
		_walk_start = float(seen_t)
	elif seen_t != _last_t:
		_walk_start = _clock
	_last_t = seen_t


func _update_mist_states(first: bool) -> void:
	var found_segments: Array = []
	for path_variant in _arr(_snapshot.get("paths", [])):
		var path: Array = path_variant
		if _points.has(str(path[0])) and _points.has(str(path[1])):
			found_segments.append([_points[str(path[0])], _points[str(path[1])]])
	for blob in _blobs:
		var state := "dense"
		if not bool(blob["edge"]):
			state = mist_state(blob["spot"], _all_points, _known, found_segments)
		var was: String = blob["state"]
		var node: MeshInstance3D = blob["node"]
		if state == was and not first:
			continue
		blob["state"] = state
		if state == "clear":
			if first:
				node.visible = false
				blob["shrink"] = -1.0
			elif was != "clear":
				blob["shrink"] = MIST_FADE_SECONDS
			continue
		blob["shrink"] = -1.0
		node.visible = true
		node.scale = blob["scale"]
		node.material_override = _mist_dense_mat if state == "dense" else _mist_thin_mat


# --- per frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if live:
		tick(delta)


func tick(delta: float) -> void:
	if not _built:
		return
	_clock += delta
	var mix := 1.0 - exp(-delta / WEATHER_EASE_SECONDS)
	_cover_shown = lerpf(_cover_shown, _cover_target, mix)
	_rain_shown = lerpf(_rain_shown, _rain_target, mix)
	_update_card(delta)
	_update_camera(delta)
	_update_sky()
	_update_mist(delta)
	_update_clouds(delta)
	_since_render += delta
	if _since_render >= 1.0 / RENDER_FPS:
		_since_render = 0.0
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _update_card(_delta: float) -> void:
	if not _have_snapshot:
		return
	var visiting := str(_snapshot.get("where", "")) == "visiting"
	_card.visible = not visiting
	var pos := _stand_point
	var walking := false
	_card_dir = Vector3.ZERO
	if not _walk_points.is_empty():
		var walk := walk_at(_walk_points, _walk_start, _clock)
		pos = walk["pos"]
		walking = bool(walk["walking"])
		_card_dir = walk["dir"]
	_card_pos = pos
	_card_walking = walking
	_card_pose = card_pose(_snapshot, _clock, walking)
	_card.position = Vector3(pos.x, ground_height(_points, pos) + CARD_LIFT, pos.z)
	if walking and _card_dir.length() > 0.001:
		_flip = _card_dir.dot(_camera.transform.basis.x) > 0.0
	_update_sprite()
	if _roof != null:
		var indoors := not visiting and not walking and Vector2(pos.x - _home_point.x, pos.z - _home_point.z).length() < 2.0
		_roof.visible = not indoors


func _update_sprite() -> void:
	if not _sprite.visible:
		return
	var entry: Dictionary = _dict(_frames.get(_card_pose, _frames.get("idle", {})))
	var frames: Array = _arr(entry.get("frames", []))
	if frames.is_empty() or not (frames[0] is Texture2D):
		return
	var count := frames.size()
	var step := int(_clock / maxf(0.05, float(entry.get("seconds", 0.5))))
	var index := step % count
	if count > 2 and bool(entry.get("ping_pong", false)):
		var cycle := (count * 2) - 2
		index = step % cycle
		if index >= count:
			index = cycle - index
	var texture: Texture2D = frames[index]
	var pivots: Array = _arr(entry.get("pivots", []))
	var pivot := Vector2(-1.0, -1.0)
	if index < pivots.size() and pivots[index] is Vector2:
		pivot = pivots[index]
	var w := float(texture.get_width())
	var h := float(texture.get_height())
	var offset := Vector2(0.0, h * 0.5)
	if pivot.x >= 0.0 and pivot.y >= 0.0:
		offset = Vector2(w * 0.5 - pivot.x, pivot.y - h * 0.5)
	# The sprite mirrors inside its rectangle, so the feet mirror with it.
	if _flip:
		offset.x = -offset.x
	_sprite.texture = texture
	_sprite.flip_h = _flip
	_sprite.offset = offset


func _update_camera(delta: float) -> void:
	var goal := _card_pos if _card.visible else _home_or_zero()
	_target = _target.lerp(goal, 1.0 - exp(-3.0 * delta))
	_apply_camera()


func _apply_camera() -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_camera.transform = Transform3D(Basis.IDENTITY, _target + offset).looking_at(_target, Vector3.UP)
	if _rain != null:
		_rain.position = Vector3(_target.x, 22.0, _target.z)


func _update_sky() -> void:
	var hour := fposmod(_clock + float(_tz_bias) * 60.0, 86400.0) / 3600.0
	_sky = sky_at(hour, {"cover": _cover_shown, "rain": _rain_shown})
	var night: float = _sky["night"]
	_env.background_color = _sky["sky"]
	_env.ambient_light_color = _sky["ambient"]
	_env.ambient_light_energy = _sky["ambient_energy"]
	_sun.light_color = _sky["sun_color"]
	_sun.light_energy = _sky["sun_energy"]
	var travel: Vector3 = _sky["sun_dir"]
	_sun.transform = Transform3D(Basis.looking_at(travel, Vector3.UP), Vector3.ZERO)
	_sprite.modulate = _sky["card_tint"]
	_land_mat.albedo_color = GRASS * (_sky["ground_tint"] as Color)
	var mist: Color = _sky["mist"]
	_mist_dense_mat.albedo_color = Color(mist.r, mist.g, mist.b, MIST_DENSE_ALPHA)
	_mist_thin_mat.albedo_color = Color(mist.r, mist.g, mist.b, MIST_THIN_ALPHA)
	if _window_mat != null:
		_window_mat.emission_energy_multiplier = 1.2 * night
	if _window_light != null:
		_window_light.light_energy = 0.9 * night
		_window_light.visible = night > 0.02
	_rain.emitting = _rain_shown > 0.15


func _update_mist(delta: float) -> void:
	for blob in _blobs:
		var node: MeshInstance3D = blob["node"]
		if not node.visible:
			continue
		var base: Vector3 = blob["base"]
		var phase: float = blob["phase"]
		node.position = base + Vector3(sin(_clock * 0.05 + phase) * 0.8, float(blob["lift"]), cos(_clock * 0.04 + phase) * 0.8)
		var left: float = blob["shrink"]
		if left >= 0.0:
			left -= delta
			if left <= 0.0:
				node.visible = false
				blob["shrink"] = -1.0
			else:
				blob["shrink"] = left
				node.scale = (blob["scale"] as Vector3) * (left / MIST_FADE_SECONDS)


func _update_clouds(delta: float) -> void:
	var shown := int(round(float(CLOUD_COUNT) * _cover_shown))
	for i in range(_cloud_discs.size()):
		var node: MeshInstance3D = _cloud_discs[i]
		node.visible = i < shown
		var x := node.position.x + 0.8 * delta
		if x > 50.0:
			x -= 100.0
		node.position.x = x


# --- clicks -----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pressing = true
				_drag_travel = 0.0
			else:
				if _pressing and _drag_travel < 5.0:
					_pick(button.position)
				_pressing = false
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist * 0.9, MIN_DISTANCE, MAX_DISTANCE)
			_apply_camera()
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist * 1.1, MIN_DISTANCE, MAX_DISTANCE)
			_apply_camera()
			accept_event()
	elif event is InputEventMouseMotion and _pressing:
		var motion := event as InputEventMouseMotion
		_drag_travel += motion.relative.length()
		_yaw -= motion.relative.x * 0.006
		_pitch = clampf(_pitch + motion.relative.y * 0.004, deg_to_rad(22.0), deg_to_rad(78.0))
		_apply_camera()
		accept_event()


# The found place whose point projects nearest the click, within 48 pixels.
func _pick(at: Vector2) -> void:
	var best := ""
	var best_d := 48.0
	for id in _points.keys():
		var point: Vector3 = (_points[id] as Vector3) + Vector3(0.0, 1.0, 0.0)
		if _camera.is_position_behind(point):
			continue
		var d := _camera.unproject_position(point).distance_to(at)
		if d < best_d:
			best_d = d
			best = str(id)
	if best != "":
		emit_signal("place_clicked", best)


# --- for tests and the render harness ---------------------------------------

func card_node() -> Node3D:
	return _card


func card_pose_now() -> String:
	return _card_pose


func card_walking() -> bool:
	return _card_walking


func place_node(id: String) -> Node3D:
	return _places_root.get_node_or_null("Place_%s" % id) as Node3D


func path_count() -> int:
	return _paths_root.get_child_count()


func label_count() -> int:
	return _labels_root.get_child_count()


# State -> how many visible blobs are in it ("clear" ones are still shrinking away).
func mist_states() -> Dictionary:
	var out := {}
	for blob in _blobs:
		if (blob["node"] as MeshInstance3D).visible:
			var state: String = blob["state"]
			out[state] = int(out.get(state, 0)) + 1
	return out


func mist_blob_near(point: Vector3) -> String:
	var best := ""
	var best_d := 4.0
	for blob in _blobs:
		var node: MeshInstance3D = blob["node"]
		if not node.visible:
			continue
		var base: Vector3 = blob["base"]
		var d := Vector2(base.x - point.x, base.z - point.z).length()
		if d <= best_d:
			best_d = d
			best = str(blob["state"])
	return best


func rain_emitting() -> bool:
	return _rain.emitting


func sky_now() -> Dictionary:
	return _sky


func viewport() -> SubViewport:
	return _viewport


func roof_visible() -> bool:
	return _roof == null or _roof.visible


func mesh_count() -> int:
	return _count_meshes(_world)


func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total
