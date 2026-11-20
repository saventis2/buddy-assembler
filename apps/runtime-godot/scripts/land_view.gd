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

# --- prototype (land-view spike, 2026-11-20): not for merging --------------
# Two camera modes beside the orbit, and pack models for five places, as
# evidence for two decisions. The orbit and the code-built shapes stay the
# default: nothing changes unless a caller (or the C and P keys) asks.
const CAMERA_MODES := ["orbit", "first_person", "follow"]
const EYE_HEIGHT := 1.6
const EYE_SPEED := 3.0
# How far from the middle the eye may walk; the land is LAND_SIZE across.
const EYE_REACH := 36.0
const LOOK_SPEED := 0.005
# Q and E turn every camera; WASD slides the orbit over the land this fast
# (scaled by how far out it is).
const TURN_SPEED := 1.6
const PAN_SPEED := 9.0
# How quickly the orbit catches the buddy up. It centres on the middle of the
# buddy's body, on whatever ground it stands on.
const ORBIT_FOLLOW_RATE := 6.0
const FOLLOW_BACK := 5.0
const FOLLOW_UP := 1.7
const FOLLOW_LOOK_UP := 1.1
# Close cameras need a nearer near plane, or walls and leaves clip open.
const NEAR_ORBIT := 0.5
const NEAR_CLOSE := 0.05
# KayKit Medieval Hexagon Pack (CC0) models: miniatures for a hex map, where a
# tile is about 2 units across, scaled up for a land with a 2 m buddy.
const PACK_DIR := "res://content/land_pack/kaykit/"
const PACK_MODELS := ["building_home_A_red", "tree_single_A", "tree_single_B", "rock_single_A", "rock_single_C",
	"rock_single_E", "waterplant_A", "waterplant_C", "building_dirt"]
# At 7x the cottage's door suits the 2 m card; it faces its own +Z, as the
# code-built cottage's does.
const PACK_HOUSE_SCALE := 7.0
const PACK_BIG_TREE_SCALE := 6.5
const PACK_PINE_HEIGHT := 1.2
# Looks to compare: "flat" is the view as built; "natural" mutes the colours
# and adds sun shadows, a graded sky and grass over found land; "textured" adds
# surface texture on top. Chosen by the snapshot's "prototype_style" or L.
const STYLES := ["flat", "natural", "textured"]
const GRASS_TUFTS := 6000
# In 4.2's Compatibility renderer a sun that casts shadows draws far brighter:
# measured at noon, open land went from 0.56 to 0.75 mean brightness (flat look
# 0.58). The richer looks turn the sun down to match the flat look.
const SHADOW_SUN_SCALE := 0.48
# Free roaming ("prototype_free"): no paths; the buddy walks straight-ish to
# where it is going, and once there it ambles about now and then.
const AMBLE_PERIOD := 9.0
const AMBLE_SPEED := 0.7
const AMBLE_RADIUS := 3.0
# An upright mist puff is half as tall as the flat sheet is wide.
const MIST_UPRIGHT_HEIGHT := 0.5
# Label size on screen for the close cameras (fixed_size).
const LABEL_CLOSE_PIXEL := 0.0008

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
# Prototype: where the buddy lies when it sleeps at home (on the bed).
var _bed_point := Vector3.ZERO
var _bed_set := false
# Texture instance id -> the row below its lowest drawn pixel (its feet).
var _feet_rows := {}
# Prototype: the land's items, each {"node", "hours", "base", "phase"}.
var _item_nodes: Array = []
# When the current walk ends (free roaming ambles from then on).
var _walk_end := 0.0
# Prototype looks (see STYLES).
var _style_override := ""
var _style_applied := ""
var _ground_plane: MeshInstance3D = null
var _sky_mat: ProceduralSkyMaterial = null
var _grass: MultiMeshInstance3D = null
var _tex_cache := {}
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
# Prototype camera state.
var _camera_mode := "orbit"
var _eye := Vector3.ZERO
var _eye_placed := false
var _look_yaw := 0.0
var _look_pitch := 0.0
var _mouse_look := false
var _follow_side := deg_to_rad(35.0)
var _follow_heading := Vector3.ZERO
var _follow_pos := Vector3.ZERO
var _follow_look := Vector3.ZERO
var _follow_placed := false
var _follow_back := FOLLOW_BACK
# The orbit stops following the buddy once WASD slides it; Space brings it back.
var _free_look := false
# Prototype pack switch: -1 follows the snapshot, 0 off, 1 on.
var _pack_override := -1
# Prototype fixes for the close cameras: upright mist, labels that keep their
# size on screen and hide behind things. On unless the harness turns them off.
var _close_fixes := true
var _mist_sheet: Mesh = null
var _mist_quad: QuadMesh = null
var _mist_dense_up: StandardMaterial3D = null
var _mist_thin_up: StandardMaterial3D = null


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
		"items": _land_items(land),
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


# Prototype: everything the land's text names, for the item models: each
# place's sights, the things it meets (at each of their places, with their
# hours) and the world's raw materials where they lie. A thing's first-meeting
# sight is drawn as the thing itself, so it is not listed twice.
static func _land_items(land: Dictionary) -> Array:
	var items: Array = []
	var thing_sights := {}
	for thing_variant in _arr(land.get("things", [])):
		if typeof(thing_variant) == TYPE_DICTIONARY:
			thing_sights[_str((thing_variant as Dictionary).get("sight", ""))] = true
	for place_variant in _arr(land.get("places", [])):
		if typeof(place_variant) != TYPE_DICTIONARY:
			continue
		var place_id := _str((place_variant as Dictionary).get("id", ""))
		for sight_variant in _arr((place_variant as Dictionary).get("sights", [])):
			if typeof(sight_variant) != TYPE_DICTIONARY:
				continue
			var sight: Dictionary = sight_variant
			var sight_id := _str(sight.get("id", ""))
			if sight_id == "" or thing_sights.has(sight_id):
				continue
			items.append({"id": sight_id, "kind": "sight", "place": place_id, "hours": _hours(sight.get("hours", null)),
				"line": _str(sight.get("line", ""))})
	for thing_variant in _arr(land.get("things", [])):
		if typeof(thing_variant) != TYPE_DICTIONARY:
			continue
		var thing: Dictionary = thing_variant
		for place_variant in _arr(thing.get("places", [])):
			items.append({"id": _str(thing.get("id", "")), "kind": "thing", "place": _str(place_variant),
				"hours": _hours(thing.get("hours", null)), "line": _str(thing.get("describe", ""))})
	for raw_variant in WorldRules.RAW.keys():
		var raw: Dictionary = WorldRules.RAW[raw_variant]
		for place_variant in _arr(raw.get("places", [])):
			items.append({"id": str(raw_variant), "kind": "material", "place": _str(place_variant), "hours": [], "line": ""})
	return items


static func _hours(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() == 2:
		return [_to_int(value[0]), _to_int(value[1])]
	return []


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
	# Prototype: the view takes the keyboard (WASD, Q/E, C, P, Space) when it
	# opens and whenever the mouse comes over it, so no click is needed first.
	focus_mode = Control.FOCUS_CLICK
	mouse_entered.connect(grab_focus)
	grab_focus.call_deferred()
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
	_ground_plane = plane_node
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
	_apply_style()
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
	# Prototype: upright puffs for the close cameras, which see the flat sheets
	# edge-on (see _mist_upright).
	_mist_sheet = sheet
	_mist_quad = QuadMesh.new()
	_mist_quad.size = Vector2(1.0, 1.0)
	_mist_dense_up = _mist_material(_fade_texture(), MIST_DENSE_ALPHA, true)
	_mist_thin_up = _mist_material(_fade_texture(), MIST_THIN_ALPHA, true)
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


func _mist_material(texture: Texture2D, alpha: float, upright := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = texture
	mat.albedo_color = Color(0.93, 0.94, 0.96, alpha)
	if upright:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		mat.billboard_keep_scale = true
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
	var style := _style()
	var key := "%s|%s|%s|%s|%s" % [color.to_html(true), alpha, unshaded, emission, style]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	# Prototype looks: lit, solid surfaces take the look's colours and texture;
	# glows, shadows and see-through things keep theirs.
	var lit := not unshaded and emission <= 0.0 and alpha >= 1.0
	var shade := _tone(color) if lit else color
	mat.albedo_color = Color(shade.r, shade.g, shade.b, alpha)
	if lit and style == "textured":
		mat.albedo_texture = _detail_texture()
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3(0.7, 0.7, 0.7)
		mat.albedo_color = Color(minf(1.0, shade.r * 1.12), minf(1.0, shade.g * 1.12), minf(1.0, shade.b * 1.12), alpha)
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
	_bed_set = false
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
	# Prototype: free roaming draws no paths.
	for path_variant in ([] if _free_on() else _arr(_snapshot.get("paths", []))):
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
	_style_labels()
	_build_grass()
	_build_items()


func _build_place(root: Node3D, id: String, kind: String, point: Vector3) -> void:
	if _pack_on() and _build_from_pack(root, id, point):
		return
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

	if _items_on():
		_place_details(root, id, out)


# Added detail belongs to the item prototype; the original view stays unchanged.
func _place_details(root: Node3D, id: String, out: Vector3) -> void:
	var bark := Color("795235")
	var stone := Color("93968b")
	match id:
		"home":
			var house := root.get_node("House") as Node3D
			for x in [-0.54, 0.54]:
				_add(house, _box_mesh(Vector3(0.09, 2.15, 0.12)), bark, Vector3(x, 1.08, 1.73))
			_add(house, _box_mesh(Vector3(1.18, 0.12, 0.14)), bark, Vector3(0, 2.16, 1.73))
			for z in [-0.44, 0.0, 0.44]:
				_add(house, _box_mesh(Vector3(0.08, 0.86, 0.06)), bark, Vector3(2.12, 1.6, z))
			for y in [1.18, 2.02]:
				_add(house, _box_mesh(Vector3(0.09, 0.08, 0.96)), bark, Vector3(2.12, y, 0))
			for x in [-2.2, 2.2]:
				_add(_roof, _box_mesh(Vector3(0.12, 0.14, 3.85)), bark, Vector3(x, -0.72, 0))
			_add(house, _box_mesh(Vector3(0.7, 0.15, 0.7)), stone, Vector3(1.4, 4.15, -0.6))
			for x in [-1.7, -1.1, 1.1, 1.7]:
				_add(house, _box_mesh(Vector3(0.5, 0.18, 0.28)), stone, Vector3(x, 0.09, 1.72))
		"big_tree":
			for k in range(3):
				var direction := Vector3(cos(k * TAU / 3), 0, sin(k * TAU / 3))
				_item_segment(root, out * 1.6 + direction * 0.2 + Vector3(0, 0.35, 0), out * 1.6 + direction * 1.2, 0.12, bark)
				_item_segment(root, out * 1.6 + Vector3(0, 2.8, 0), out * 1.6 + direction * 1.0 + Vector3(0, 3.4, 0), 0.12, bark)
				_add(root, _sphere_mesh(1.1, 9, 5), Color("55783c"), out * 1.6 + direction * 2.2 + Vector3(0, 4.5, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
		"wood_heap":
			var stack := root.get_child(0) as Node3D
			for k in range(4):
				_add(stack, _cyl_mesh(0.19, 0.19, 0.015, 7), Color("c4a577"), Vector3(-0.66 + k * 0.44, 0.22, 1.01), Vector3(90, 0, 0))
				_add(stack, _box_mesh(Vector3(0.018, 0.28, 0.02)), bark, Vector3(-0.66 + k * 0.44, 0.22, 1.025), Vector3(0, 0, 25))
		"patch":
			for k in range(4):
				var at := Vector3(cos(k * 1.7) * 2.8, 0, sin(k * 1.7) * 2.8)
				_add(root, _sphere_mesh(0.45, 7, 4), Color("476737"), at + Vector3(0, 0.55, 0), Vector3.ZERO, Vector3(0.8, 1.5, 1))
				_add(root, _sphere_mesh(0.13, 6, 4), Color("dab0b8"), at + Vector3(0, 1.2, 0), Vector3.ZERO, Vector3(1.3, 0.4, 1.3))
		"gate":
			var fence := root.get_node("Fence") as Node3D
			for x in [-0.8, 0.8, -2.0, 2.0]:
				_add(fence, _prism_mesh(Vector3(0.26, 0.13, 0.26)), Color("a49170"), Vector3(x, 1.25, 0))
			var panel := fence.get_node("GatePanel") as Node3D
			_add(panel, _box_mesh(Vector3(0.22, 0.05, 0.06)), Color("343a39"), Vector3(1.4, 0.85, 0.07))
		"high_ground":
			for k in range(3):
				_add(root, _sphere_mesh(0.65, 6, 4), stone, Vector3(-2 + k * 0.6, 1.85, -1.2), Vector3(0, k * 20, 15), Vector3(0.8, 1.4, 0.7))
		"long_grass":
			for k in range(6):
				_add(root, _cyl_mesh(0, 0.18, 1.8, 4), Color("87924c"), Vector3(cos(k) * 3, 0.9, sin(k) * 3), Vector3(12, k * 60, 10))
		"water":
			for k in range(6):
				_add(root, _sphere_mesh(0.4, 7, 4), stone, out * 4.8 + Vector3(cos(k) * 4.6, 0.13, sin(k) * 4.6), Vector3.ZERO, Vector3(1, 0.5, 0.8))
			for k in range(3):
				_add(root, _cyl_mesh(0.32, 0.32, 0.02, 10), Color("638850"), out * 4.8 + Vector3(1.4 + k * 0.65, 0.08, 1.5))
		"stony_ground":
			for k in range(3):
				_add(root, _prism_mesh(Vector3(0.7, 0.25, 0.5)), Color("a4a394"), Vector3(-1 + k * 0.7, 0.13, -2), Vector3(0, k * 45, 10))
		"grey_bank":
			for k in range(3):
				_add(root, _box_mesh(Vector3(2.5 - k * 0.3, 0.14, 0.3)), Color("928e80") if k != 1 else Color("786955"), out * 2.5 + Vector3(0, 0.1 + k * 0.14, 1.5))
		"sandy_bend":
			for k in range(3):
				_add(root, _sphere_mesh(1, 12, 6), Color("c4b582"), out * 1.5 + Vector3(0, 0.055, k * 0.35), Vector3.ZERO, Vector3(1.4, 0.012, 0.045))
		"tall_reeds":
			for k in range(4):
				var at := Vector3(cos(k * 1.5) * 2.5, 0, sin(k * 1.5) * 2.5)
				_add(root, _sphere_mesh(1, 8, 4), Color("73864c"), at + Vector3(0, 0.65, 0), Vector3(0, k * 70, -25), Vector3(0.08, 0.65, 0.035))
		"dark_trees":
			# Add a smaller, higher tier at each existing tree, keeping its location.
			for k in range(8):
				var crown := root.get_child(k * 2 + 1) as MeshInstance3D
				_add(root, _cyl_mesh(0, 0.9, 2.3, 7), Color("274d35"), crown.position + Vector3(0, 1.0, 0))


func _build_cottage(root: Node3D, id: String) -> void:
	_home_point = root.position
	var house := Node3D.new()
	house.name = "House"
	var front := _neighbour_dir(id)
	house.rotation.y = atan2(front.x, front.z)
	root.add_child(house)
	var wall := Color(0.86, 0.80, 0.66)
	# Four walls round a floor, so the inside can be seen with the roof off.
	# Prototype: the front wall has a real doorway, so the house can be walked
	# into, and the door stands open. The doorway fits the card (CARD_HEIGHT).
	_add(house, _box_mesh(Vector3(4.0, 0.03, 3.2)), Color(0.50, 0.38, 0.26), Vector3(0.0, 0.035, 0.0))
	_add(house, _box_mesh(Vector3(1.6, 2.6, 0.2)), wall, Vector3(-1.3, 1.3, 1.6))
	_add(house, _box_mesh(Vector3(1.6, 2.6, 0.2)), wall, Vector3(1.3, 1.3, 1.6))
	_add(house, _box_mesh(Vector3(1.0, 0.5, 0.2)), wall, Vector3(0.0, 2.35, 1.6))
	_add(house, _box_mesh(Vector3(4.2, 2.6, 0.2)), wall, Vector3(0.0, 1.3, -1.6))
	_add(house, _box_mesh(Vector3(0.2, 2.6, 3.0)), wall, Vector3(2.0, 1.3, 0.0))
	_add(house, _box_mesh(Vector3(0.2, 2.6, 3.0)), wall, Vector3(-2.0, 1.3, 0.0))
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(-0.5, 0.0, 1.72)
	hinge.rotation_degrees = Vector3(0.0, -105.0, 0.0)
	house.add_child(hinge)
	_add(hinge, _box_mesh(Vector3(1.0, 2.1, 0.08)), Color(0.32, 0.20, 0.12), Vector3(0.5, 1.05, 0.0))
	_roof = _add(house, _prism_mesh(Vector3(4.8, 1.5, 3.8)), Color(0.62, 0.30, 0.22), Vector3(0.0, 3.35, 0.0),
		Vector3.ZERO, Vector3.ONE, "Roof")
	_add(house, _box_mesh(Vector3(0.5, 1.2, 0.5)), Color(0.45, 0.36, 0.32), Vector3(1.4, 3.5, -0.6))
	_window_mat = StandardMaterial3D.new()
	_window_mat.albedo_color = Color(1.0, 0.82, 0.45)
	_window_mat.roughness = 1.0
	_window_mat.emission_enabled = true
	_window_mat.emission = Color(1.0, 0.82, 0.45)
	_window_mat.emission_energy_multiplier = 0.0
	# The window shows on both faces of the wall.
	for window_x in [2.08, 1.89]:
		var window := _add(house, _box_mesh(Vector3(0.04, 0.7, 0.8)), Color(1.0, 0.82, 0.45), Vector3(window_x, 1.6, 0.0))
		window.material_override = _window_mat
	_build_furniture(house)
	_window_light = OmniLight3D.new()
	_window_light.name = "WindowLight"
	_window_light.omni_range = 7.0
	_window_light.light_energy = 0.0
	_window_light.light_color = Color(1.0, 0.82, 0.45)
	_window_light.shadow_enabled = false
	_window_light.position = Vector3(1.6, 1.6, 0.0)
	house.add_child(_window_light)


# Prototype: what the buddy's first journal line names (a bed, a table, a
# shelf, a window and a door), the iron box and the glowing box it finds there,
# and a rug and a lamp. House-local: the floor is 4 m by 3.2 m, the door at +Z.
func _build_furniture(house: Node3D) -> void:
	var wood := Color(0.55, 0.40, 0.26)
	var dark_wood := Color(0.40, 0.28, 0.18)
	# The bed along the left wall: frame, headboard, mattress, pillow, blanket.
	_add(house, _box_mesh(Vector3(1.0, 0.35, 2.0)), dark_wood, Vector3(-1.35, 0.175, -0.45))
	_add(house, _box_mesh(Vector3(1.0, 0.75, 0.08)), dark_wood, Vector3(-1.35, 0.375, -1.45))
	_add(house, _box_mesh(Vector3(0.92, 0.14, 1.9)), Color(0.90, 0.88, 0.80), Vector3(-1.35, 0.42, -0.45))
	_add(house, _box_mesh(Vector3(0.7, 0.12, 0.36)), Color(0.96, 0.95, 0.92), Vector3(-1.35, 0.55, -1.18))
	_add(house, _box_mesh(Vector3(0.96, 0.07, 1.2)), Color(0.36, 0.48, 0.62), Vector3(-1.35, 0.52, 0.02))
	_bed_point = _home_point + Vector3(-1.35, 0.5, -0.45).rotated(Vector3.UP, house.rotation.y)
	_bed_set = true
	# The table with four legs, and a stool.
	_add(house, _box_mesh(Vector3(1.0, 0.06, 0.7)), wood, Vector3(0.35, 0.75, -0.75))
	for leg in [Vector3(-0.42, 0.0, -0.29), Vector3(0.42, 0.0, -0.29), Vector3(-0.42, 0.0, 0.29), Vector3(0.42, 0.0, 0.29)]:
		_add(house, _box_mesh(Vector3(0.06, 0.72, 0.06)), dark_wood, Vector3(0.35, 0.36, -0.75) + leg)
	_add(house, _cyl_mesh(0.18, 0.18, 0.45, 8), wood, Vector3(0.35, 0.225, -0.1))
	# The shelf on the back wall, with a few things on it.
	for shelf_y in [1.35, 1.8]:
		_add(house, _box_mesh(Vector3(1.1, 0.05, 0.28)), wood, Vector3(-0.35, shelf_y, -1.36))
	_add(house, _box_mesh(Vector3(0.12, 0.25, 0.2)), Color(0.62, 0.22, 0.20), Vector3(-0.72, 1.5, -1.36))
	_add(house, _box_mesh(Vector3(0.1, 0.22, 0.2)), Color(0.25, 0.40, 0.55), Vector3(-0.58, 1.485, -1.36))
	_add(house, _cyl_mesh(0.08, 0.08, 0.2, 8), Color(0.75, 0.70, 0.55), Vector3(-0.1, 1.475, -1.36))
	_add(house, _cyl_mesh(0.1, 0.07, 0.16, 8), Color(0.55, 0.45, 0.35), Vector3(0.05, 1.905, -1.36))
	# The iron box (a stove) under the chimney, its pipe up through the roof.
	_add(house, _box_mesh(Vector3(0.6, 0.7, 0.55)), Color(0.22, 0.22, 0.24), Vector3(1.4, 0.35, -1.05))
	_add(house, _cyl_mesh(0.08, 0.08, 1.9, 8), Color(0.18, 0.18, 0.20), Vector3(1.4, 1.65, -0.8))
	# The glowing box, on a little desk by the window.
	_add(house, _box_mesh(Vector3(0.5, 0.7, 0.8)), wood, Vector3(1.62, 0.35, 0.65))
	var glow := _add(house, _box_mesh(Vector3(0.4, 0.4, 0.4)), Color(0.55, 0.95, 0.95), Vector3(1.62, 0.9, 0.65),
		Vector3.ZERO, Vector3.ONE, "GlowingBox")
	glow.material_override = _mat(Color(0.55, 0.95, 0.95), 1.0, false, 1.5)
	# A rug inside the door, and a lamp on the table that glows at night.
	_add(house, _box_mesh(Vector3(1.3, 0.01, 0.9)), Color(0.62, 0.30, 0.24), Vector3(0.2, 0.055, 0.75))
	_add(house, _cyl_mesh(0.07, 0.09, 0.12, 8), Color(0.30, 0.25, 0.20), Vector3(0.6, 0.84, -0.85))
	var bulb := _add(house, _sphere_mesh(0.09, 8, 5), Color(1.0, 0.82, 0.45), Vector3(0.6, 0.98, -0.85))
	bulb.material_override = _window_mat


func _build_big_tree(root: Node3D, out: Vector3, rng: RandomNumberGenerator) -> void:
	var trunk_at := out * 1.6
	_add(root, _cyl_mesh(0.35, 0.55, 4.2, 7), Color(0.40, 0.28, 0.18), trunk_at + Vector3(0.0, 2.1, 0.0))
	var leaf := Color(0.22, 0.45, 0.22)
	for i in range(3):
		var r := rng.randf_range(2.2, 2.8)
		var angle := TAU * float(i) / 3.0 + rng.randf() * 0.5
		_add(root, _sphere_mesh(r, 8, 5), leaf.lerp(Color(0.18, 0.38, 0.20), rng.randf()),
			trunk_at + Vector3(cos(angle) * 1.0, 4.8 + rng.randf_range(-0.3, 0.5), sin(angle) * 1.0),
			Vector3.ZERO, Vector3(1, 0.65 if _items_on() else 1.0, 1))


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
	panel.name = "GatePanel"
	panel.position = Vector3(0.8, 0.0, 0.0)
	panel.rotation_degrees = Vector3(0.0, 70.0, 0.0)
	fence.add_child(panel)
	_add(panel, _box_mesh(Vector3(1.6, 0.8, 0.06)), Color(0.58, 0.50, 0.38), Vector3(0.8, 0.6, 0.0))


# --- prototype: free roaming ---------------------------------------------------

func _free_on() -> bool:
	return bool(_snapshot.get("prototype_free", false))


# A walk with no paths: a gentle curve from a to b, bowed to one side.
func _free_walk(a: Vector3, b: Vector3) -> Array:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := flat.length()
	if length < 0.01:
		return [a, b]
	var side := Vector3(-flat.z, 0.0, flat.x) / length
	var bow := length * 0.12 * (1.0 if hash("%s|%s" % [a, b]) % 2 == 0 else -1.0)
	var mid := (a + b) * 0.5 + side * bow
	var points: Array = []
	for i in range(9):
		var t := float(i) / 8.0
		points.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return points


# Where an amble about `stand` has got to: it rests a while after arriving,
# then every AMBLE_PERIOD seconds strolls to another spot near it.
func _amble_at(stand: Vector3, now: float) -> Dictionary:
	var since := now - _walk_end
	if since < 0.0:
		return {"pos": stand, "walking": false, "dir": Vector3.ZERO}
	var k := int(floor(since / AMBLE_PERIOD))
	var a := _amble_point(stand, k - 1)
	var b := _amble_point(stand, k)
	var length := a.distance_to(b)
	var t := since - float(k) * AMBLE_PERIOD
	if length < 0.01 or t >= length / AMBLE_SPEED:
		return {"pos": b, "walking": false, "dir": Vector3.ZERO}
	return {"pos": a.lerp(b, t * AMBLE_SPEED / length), "walking": true, "dir": (b - a) / length}


func _amble_point(stand: Vector3, k: int) -> Vector3:
	if k <= 0:
		return stand
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d" % [str(_snapshot.get("where", "")), _last_t, k])
	var angle := rng.randf() * TAU
	var radius := rng.randf_range(0.8, AMBLE_RADIUS)
	return stand + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


# --- prototype: the land's items -------------------------------------------------

func _items_on() -> bool:
	return bool(_snapshot.get("prototype_items", false))


# Every item (see _land_items) at a found place, as a child of its place node
# (or of the house, for things inside it), shown only in its hours.
func _build_items() -> void:
	_item_nodes = []
	if not _items_on():
		return
	var counts := {}
	for item_variant in _arr(_snapshot.get("items", [])):
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		var place_id := str(item.get("place", ""))
		var place := place_node(place_id)
		if place == null:
			continue
		var index: int = counts.get(place_id, 0)
		counts[place_id] = index + 1
		var node := _item_model(item, place_id)
		if node == null:
			continue
		node.name = "Item_%s_%s" % [str(item.get("id", "")), place_id]
		if not node.has_meta("placed"):
			node.position = _item_ring_spot(item, index, place.position)
		var parent: Node3D = place
		if node.has_meta("in_house") and place.get_node_or_null("House") != null:
			parent = place.get_node("House") as Node3D
		parent.add_child(node)
		_item_nodes.append({"node": node, "hours": item.get("hours", []), "base": node.position,
			"phase": float(_item_nodes.size()) * 1.37})


# A spot for an item with none of its own: spread round the place on a ring,
# out past the place's own props, on the ground (place-local).
func _item_ring_spot(item: Dictionary, index: int, place_at: Vector3) -> Vector3:
	var angle := float(index) * 2.39996 + float(hash(str(item.get("id", ""))) % 100) * 0.01
	var radius := 4.2 + float(index % 3) * 0.9
	var local := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	return Vector3(local.x, ground_height(_points, place_at + local), local.z)


# Shown in their hours ([from, to), wrapping past midnight), hidden outside them.
func _show_items_for(hour: int) -> void:
	for entry in _item_nodes:
		var hours: Array = entry["hours"]
		var shown := true
		if hours.size() == 2:
			var from_h := int(hours[0])
			var to_h := int(hours[1])
			shown = (hour >= from_h and hour < to_h) if from_h <= to_h else (hour >= from_h or hour < to_h)
		(entry["node"] as Node3D).visible = shown


# Motion for creatures, by meta on the item's root: "bob" (metres up and down),
# "fly" (Vector2: circle radius in metres, turn speed in radians a second).
func _animate_items() -> void:
	for entry in _item_nodes:
		var node: Node3D = entry["node"]
		if not node.visible or not (node.has_meta("bob") or node.has_meta("fly")):
			continue
		var at: Vector3 = entry["base"]
		var phase: float = entry["phase"]
		if node.has_meta("fly"):
			var fly: Vector2 = node.get_meta("fly")
			var angle := _clock * fly.y + phase
			at += Vector3(cos(angle) * fly.x, sin(_clock * 1.7 + phase) * 0.2, sin(angle) * fly.x)
			node.rotation.y = -angle - signf(fly.y) * PI * 0.5
		if node.has_meta("bob"):
			at.y += sin(_clock * 2.0 + phase) * float(node.get_meta("bob"))
		node.position = at


# The model for one item, built from the same shapes and look as the rest. A
# model that knows its spot sets node.position (place-local) and the "placed"
# meta; "in_house" puts it in the house's own frame (floor 4 m x 3.2 m, door at
# +Z). Each item has its own silhouette and physical trace.
func _item_model(item: Dictionary, place_id: String) -> Node3D:
	var root := Node3D.new()
	var id := str(item.get("id", ""))
	match id:
		"heron":
			# Tall, grey, on one leg at the edge of the water.
			var grey := Color(0.62, 0.64, 0.68)
			_add(root, _sphere_mesh(0.22, 8, 5), grey, Vector3(0.0, 0.95, 0.0), Vector3.ZERO, Vector3(0.8, 0.9, 1.5))
			_add(root, _cyl_mesh(0.04, 0.05, 0.5, 6), grey, Vector3(0.0, 1.28, 0.22), Vector3(-25.0, 0.0, 0.0))
			_add(root, _sphere_mesh(0.08, 8, 5), Color(0.85, 0.86, 0.88), Vector3(0.0, 1.52, 0.33))
			_add(root, _cyl_mesh(0.0, 0.025, 0.24, 5), Color(0.85, 0.70, 0.30), Vector3(0.0, 1.5, 0.5), Vector3(90.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.012, 0.012, 0.75, 4), Color(0.45, 0.42, 0.30), Vector3(0.0, 0.38, 0.0))
			if place_id == "water" and _points.has("water"):
				var out := _outward(_points["water"])
				root.position = out * 4.8 + Vector3(out.z, 0.0, -out.x) * 4.2
				root.set_meta("placed", true)
		"clay":
			# A dug hollow in the bank with grey-blue lumps beside it.
			_add(root, _cyl_mesh(0.7, 0.55, 0.06, 9), Color(0.42, 0.44, 0.48), Vector3(0.0, 0.03, 0.0))
			for i in range(3):
				_add(root, _sphere_mesh(0.16, 6, 4), Color(0.50, 0.53, 0.58), Vector3(0.9 + 0.25 * i, 0.1, 0.2 * i),
					Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 2.5 + Vector3(-1, 0.03, 2.6)
			root.set_meta("placed", true)
		"log":
			_add(root, _cyl_mesh(0.26, 0.28, 2.4, 8), Color(0.45, 0.31, 0.19), Vector3(0.0, 0.27, 0.0), Vector3(0.0, 0.0, 90.0))
			_add(root, _cyl_mesh(0.22, 0.22, 0.02, 8), Color(0.78, 0.66, 0.48), Vector3(1.21, 0.27, 0.0), Vector3(0.0, 0.0, 90.0))
		"ceiling_stain":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("77513a"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.19, 0.008, 0.34))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("77513a"), Vector3(0.15, 0.0, -0.18), Vector3.ZERO, Vector3(0.16, 0.008, 0.13))
			root.position = Vector3(-0.35, 2.595, -1.25)
			root.set_meta("placed", true)
			root.set_meta("in_house", true)
		"floor_creak":
			_add(root, _box_mesh(Vector3(0.22, 0.035, 0.8)), Color("99754b"), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 3.0))
			_item_segment(root, Vector3(-0.1, 0.02, -0.38), Vector3(-0.1, 0.02, 0.38), 0.008, Color("433524"))
			root.position = Vector3(-0.7, 0.075, 0.0)
			root.set_meta("placed", true)
			root.set_meta("in_house", true)
		"door_draught":
			_add(root, _box_mesh(Vector3(0.72, 0.008, 0.06)), Color("a4b4b5"), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("c8b995"), Vector3(0.2, 0.02, -0.15), Vector3.ZERO, Vector3(0.035, 0.012, 0.13))
			root.position = Vector3(0.0, 0.065, 1.45)
			root.set_meta("placed", true)
			root.set_meta("in_house", true)
		"sun_square":
			_add(root, _box_mesh(Vector3(0.66, 0.004, 0.72)), Color("fff1b5"), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
			root.get_child(0).material_override = _mat(Color("fff1b5"), 1.0, true)
			root.position = Vector3(0.95, 0.058, -0.05)
			root.set_meta("placed", true)
			root.set_meta("in_house", true)
		"roof_tick":
			_add(root, _box_mesh(Vector3(0.5, 0.045, 0.16)), Color("75442c"), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.018, 0.018, 0.09, 8), Color("303033"), Vector3(0.16, -0.04, 0.0), Vector3(0.0, 0.0, 0.0))
			root.position = Vector3(0.3, 2.57, 0.5)
			root.set_meta("placed", true)
			root.set_meta("in_house", true)
		"iron_box_smell":
			_add(root, _box_mesh(Vector3(0.41, 0.36, 0.008)), Color("111416"), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a59e92"), Vector3(0.0, -0.15, 0.02), Vector3.ZERO, Vector3(0.16, 0.025, 0.06))
			_item_segment(root, Vector3(-0.13, -0.1, 0.03), Vector3(0.12, -0.11, 0.03), 0.025, Color("37302a"))
			root.position = Vector3(1.4, 0.36, -0.769)
			root.set_meta("placed", true)
			root.set_meta("in_house", true)
		"grey_feather":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a3abb0"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.065, 0.012, 0.24))
			_item_segment(root, Vector3(0.0, 0.015, -0.29), Vector3(0.0, 0.015, 0.2), 0.008, Color("e0d9c7"))
			root.position = _neighbour_dir("yard") * 2.4 + Vector3(0, 0.27, 0)
			root.set_meta("placed", true)
		"morning_wet":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b8dfdd"), Vector3(-0.4, 0.065, 0.0), Vector3.ZERO, Vector3(0.045, 0.025, 0.045))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b8dfdd"), Vector3(0.0, 0.065, 0.3), Vector3.ZERO, Vector3(0.045, 0.025, 0.045))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b8dfdd"), Vector3(0.3, 0.065, -0.2), Vector3.ZERO, Vector3(0.045, 0.025, 0.045))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b8dfdd"), Vector3(0.6, 0.065, 0.2), Vector3.ZERO, Vector3(0.045, 0.025, 0.045))
			root.position = Vector3(-1.0, 0.0, 1.0)
			root.set_meta("placed", true)
		"upside_shiny":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("191d23"), Vector3(0.0, 0.09, 0.0), Vector3.ZERO, Vector3(0.13, 0.08, 0.2))
			_item_segment(root, Vector3(-0.2, 0.22, -0.12), Vector3(0.2, 0.22, -0.03), 0.012, Color("292b32"))
			_item_segment(root, Vector3(-0.2, 0.22, 0.0), Vector3(0.2, 0.22, 0.09), 0.012, Color("292b32"))
			_item_segment(root, Vector3(-0.2, 0.22, 0.12), Vector3(0.2, 0.22, 0.21), 0.012, Color("292b32"))
			root.position = Vector3(1.0, 0.04, 1.0)
			root.set_meta("placed", true)
		"night_tracks":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("514b3e"), Vector3(0.0, 0.012, 0.0), Vector3.ZERO, Vector3(0.055, 0.009, 0.075))
			_item_segment(root, Vector3(0.0, 0.012, 0.03), Vector3(-0.07, 0.012, 0.17), 0.012, Color("514b3e"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("514b3e"), Vector3(0.25, 0.012, 0.25), Vector3.ZERO, Vector3(0.055, 0.009, 0.075))
			_item_segment(root, Vector3(0.25, 0.012, 0.28), Vector3(0.18, 0.012, 0.42000000000000004), 0.012, Color("514b3e"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("514b3e"), Vector3(0.0, 0.012, 0.5), Vector3.ZERO, Vector3(0.055, 0.009, 0.075))
			_item_segment(root, Vector3(0.0, 0.012, 0.53), Vector3(-0.07, 0.012, 0.67), 0.012, Color("514b3e"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("514b3e"), Vector3(0.25, 0.012, 0.75), Vector3.ZERO, Vector3(0.055, 0.009, 0.075))
			_item_segment(root, Vector3(0.25, 0.012, 0.78), Vector3(0.18, 0.012, 0.92), 0.012, Color("514b3e"))
			root.position = Vector3(0.0, 0.06, 1.0)
			root.set_meta("placed", true)
		"small_hands":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("514b3e"), Vector3(0.0, 0.012, 0.0), Vector3.ZERO, Vector3(0.055, 0.009, 0.075))
			_item_segment(root, Vector3(0.0, 0.012, 0.03), Vector3(-0.07, 0.012, 0.17), 0.012, Color("514b3e"))
			_item_segment(root, Vector3(0.0, 0.012, 0.03), Vector3(0.0, 0.012, 0.17), 0.012, Color("514b3e"))
			_item_segment(root, Vector3(0.0, 0.012, 0.03), Vector3(0.07, 0.012, 0.17), 0.012, Color("514b3e"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("514b3e"), Vector3(0.25, 0.012, 0.25), Vector3.ZERO, Vector3(0.055, 0.009, 0.075))
			_item_segment(root, Vector3(0.25, 0.012, 0.28), Vector3(0.18, 0.012, 0.42000000000000004), 0.012, Color("514b3e"))
			_item_segment(root, Vector3(0.25, 0.012, 0.28), Vector3(0.25, 0.012, 0.42000000000000004), 0.012, Color("514b3e"))
			_item_segment(root, Vector3(0.25, 0.012, 0.28), Vector3(0.32, 0.012, 0.42000000000000004), 0.012, Color("514b3e"))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 2.5 + Vector3(0, 0.05, 2.7)
			root.set_meta("placed", true)
		"three_toes":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("514b3e"), Vector3(0.0, 0.012, 0.0), Vector3.ZERO, Vector3(0.055, 0.009, 0.075))
			_item_segment(root, Vector3(0.0, 0.012, 0.03), Vector3(-0.07, 0.012, 0.17), 0.012, Color("514b3e"))
			_item_segment(root, Vector3(0.0, 0.012, 0.03), Vector3(0.0, 0.012, 0.17), 0.012, Color("514b3e"))
			_item_segment(root, Vector3(0.0, 0.012, 0.03), Vector3(0.07, 0.012, 0.17), 0.012, Color("514b3e"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("514b3e"), Vector3(0.25, 0.012, 0.25), Vector3.ZERO, Vector3(0.055, 0.009, 0.075))
			_item_segment(root, Vector3(0.25, 0.012, 0.28), Vector3(0.18, 0.012, 0.42000000000000004), 0.012, Color("514b3e"))
			_item_segment(root, Vector3(0.25, 0.012, 0.28), Vector3(0.25, 0.012, 0.42000000000000004), 0.012, Color("514b3e"))
			_item_segment(root, Vector3(0.25, 0.012, 0.28), Vector3(0.32, 0.012, 0.42000000000000004), 0.012, Color("514b3e"))
			root.position = Vector3(0.0, 0.06, 1.0)
			root.set_meta("placed", true)
		"roll_ups":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("777d80"), Vector3(0.0, 0.075, 0.0), Vector3.ZERO, Vector3(0.08, 0.06, 0.11))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("777d80"), Vector3(0.16, 0.075, 0.0), Vector3.ZERO, Vector3(0.08, 0.06, 0.11))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("777d80"), Vector3(0.32, 0.075, 0.0), Vector3.ZERO, Vector3(0.08, 0.06, 0.11))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 1.4 + Vector3(0.6, 0.01, 1.15)
			root.set_meta("placed", true)
		"log_ear":
			_add(root, _cyl_mesh(0.2, 0.2, 0.9, 8), Color("795235"), Vector3(0.0, 0.2, 0.0), Vector3(0.0, 0.0, 90.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d1b5a2"), Vector3(0.0, 0.29, 0.2), Vector3.ZERO, Vector3(0.22, 0.07, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("986b55"), Vector3(0.0, 0.33, 0.22), Vector3.ZERO, Vector3(0.15, 0.02, 0.11))
			root.position = Vector3(1.2, 0.0, 1.5)
			root.set_meta("placed", true)
		"sticky_wood":
			_add(root, _cyl_mesh(0.2, 0.2, 0.9, 8), Color("795235"), Vector3(0.0, 0.2, 0.0), Vector3(0.0, 0.0, 90.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d9a13b"), Vector3(0.1, 0.34, 0.12), Vector3.ZERO, Vector3(0.08, 0.13, 0.025))
			root.position = Vector3(-1.0, 0.0, 1.7)
			root.set_meta("placed", true)
		"wood_tunnels":
			_add(root, _cyl_mesh(0.2, 0.2, 0.9, 8), Color("795235"), Vector3(0.0, 0.2, 0.0), Vector3(0.0, 0.0, 90.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("2a241c"), Vector3(-0.25, 0.3, 0.15), Vector3.ZERO, Vector3(0.035, 0.035, 0.015))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("2a241c"), Vector3(0.0, 0.3, 0.15), Vector3.ZERO, Vector3(0.035, 0.035, 0.015))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("2a241c"), Vector3(0.23, 0.3, 0.15), Vector3.ZERO, Vector3(0.035, 0.035, 0.015))
			root.position = Vector3(0.0, 0.0, 2.1)
			root.set_meta("placed", true)
		"red_round":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("bb3829"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.17, 0.18, 0.17))
			_item_segment(root, Vector3(0.0, 0.15, 0.0), Vector3(0.0, 0.32, 0.0), 0.018, Color("795235"))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 1.6 + Vector3(2.6, 3.9, 1.3)
			root.set_meta("placed", true)
		"stick_bundle":
			_item_ring(root, Vector3(0.0, 0.0, 0.0), 0.28, 0.09, Color("795235"), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("34291d"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.21, 0.03, 0.21))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d8d0b2"), Vector3(0.0, 0.06, 0.0), Vector3.ZERO, Vector3(0.06, 0.08, 0.06))
			_item_segment(root, Vector3(-1.1, -0.45, -0.5), Vector3(0.2, -0.08, 0), 0.09, Color("795235"))
			_item_segment(root, Vector3(-0.2, -0.15, 0), Vector3(0.3, 0.2, -0.3), 0.06, Color("795235"))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 1.6 + Vector3(1.3, 2.6, 0.7)
			root.set_meta("placed", true)
		"tree_knock":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("bda076"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.13, 0.22, 0.015))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("352c22"), Vector3(0.0, 0.0, 0.015), Vector3.ZERO, Vector3(0.045, 0.07, 0.01))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 1.6 + Vector3(0.24, 1.9, 0.34)
			root.set_meta("placed", true)
		"trunk_hole":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("392e20"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.21, 0.28, 0.025))
			_item_ring(root, Vector3(0.0, 0.0, 0.01), 0.22, 0.035, Color("795235"), Vector3(90.0, 0.0, 0.0))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 1.6 + Vector3(0.24, 2.2, 0.34)
			root.set_meta("placed", true)
		"hand_leaves":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("ac7739"), Vector3(-0.16, 0.02, 0.08), Vector3.ZERO, Vector3(0.045, 0.01, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("ac7739"), Vector3(-0.08, 0.02, 0.04), Vector3.ZERO, Vector3(0.045, 0.01, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("ac7739"), Vector3(0.0, 0.02, 0.0), Vector3.ZERO, Vector3(0.045, 0.01, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("ac7739"), Vector3(0.08, 0.02, 0.04), Vector3.ZERO, Vector3(0.045, 0.01, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("ac7739"), Vector3(0.16, 0.02, 0.08), Vector3.ZERO, Vector3(0.045, 0.01, 0.17))
			_item_segment(root, Vector3(0.0, 0.02, -0.24), Vector3(0.0, 0.02, 0.1), 0.012, Color("795235"))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"pink_wriggler":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("cc8f86"), Vector3(0.0, 0.04, 0.0), Vector3.ZERO, Vector3(0.1, 0.04, 0.045))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("cc8f86"), Vector3(0.12, 0.04, 0.06), Vector3.ZERO, Vector3(0.1, 0.04, 0.045))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("cc8f86"), Vector3(0.24, 0.04, 0.0), Vector3.ZERO, Vector3(0.1, 0.04, 0.045))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("cc8f86"), Vector3(0.36, 0.04, 0.06), Vector3.ZERO, Vector3(0.1, 0.04, 0.045))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"sleeping_yellow":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("dcaf39"), Vector3(0.0, 0.17, 0.0), Vector3.ZERO, Vector3(0.23, 0.17, 0.55))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("527637"), Vector3(0.0, 0.43, -0.3), Vector3.ZERO, Vector3(0.4, 0.025, 0.35))
			_item_segment(root, Vector3(0.0, 0.1, -0.55), Vector3(0.0, 0.4, -0.3), 0.04, Color("527637"))
			root.position = Vector3(0.0, 0.0, 1.0)
			root.set_meta("placed", true)
		"clean_smell":
			_add(root, _cyl_mesh(0.025, 0.025, 0.6, 8), Color("527637"), Vector3(0.0, 0.3, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("719c66"), Vector3(-0.12, 0.2, 0.0), Vector3.ZERO, Vector3(0.18, 0.025, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("719c66"), Vector3(0.12, 0.3, 0.0), Vector3.ZERO, Vector3(0.18, 0.025, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("719c66"), Vector3(-0.12, 0.4, 0.0), Vector3.ZERO, Vector3(0.18, 0.025, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("719c66"), Vector3(0.12, 0.5, 0.0), Vector3.ZERO, Vector3(0.18, 0.025, 0.09))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"nettle":
			_add(root, _cyl_mesh(0.025, 0.025, 0.6, 8), Color("527637"), Vector3(0.0, 0.3, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("376e35"), Vector3(-0.12, 0.2, 0.0), Vector3.ZERO, Vector3(0.18, 0.025, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("376e35"), Vector3(0.12, 0.3, 0.0), Vector3.ZERO, Vector3(0.18, 0.025, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("376e35"), Vector3(-0.12, 0.4, 0.0), Vector3.ZERO, Vector3(0.18, 0.025, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("376e35"), Vector3(0.12, 0.5, 0.0), Vector3.ZERO, Vector3(0.18, 0.025, 0.09))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"petal_wings":
			for k in range(2):
				var at := Vector3(k * 0.55, k * 0.2, k * 0.15)
				_add(root, _sphere_mesh(1, 8, 4), Color("55523f"), at, Vector3.ZERO, Vector3(0.025, 0.03, 0.14))
				for side in [-1, 1]:
					_add(root, _sphere_mesh(1, 8, 4), Color("f2eed9"), at + Vector3(side * 0.12, 0.04, 0), Vector3(0, 0, side * 25), Vector3(0.14, 0.015, 0.18))
			root.position = Vector3(0, 1.6, 1)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.4, 0.8))
		"clear_wings":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("292b28"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.025, 0.025, 0.35))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("c6e1df"), Vector3(-0.15, 0.0, -0.1), Vector3.ZERO, Vector3(0.24, 0.009, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("c6e1df"), Vector3(-0.15, 0.0, 0.1), Vector3.ZERO, Vector3(0.24, 0.009, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("c6e1df"), Vector3(0.15, 0.0, -0.1), Vector3.ZERO, Vector3(0.24, 0.009, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("c6e1df"), Vector3(0.15, 0.0, 0.1), Vector3.ZERO, Vector3(0.24, 0.009, 0.035))
			root.position = Vector3(0.0, 1.1, 1.6)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.18, 1.2))
		"blue_needle":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("297eae"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.025, 0.025, 0.35))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b5d7e0"), Vector3(-0.15, 0.0, -0.1), Vector3.ZERO, Vector3(0.24, 0.009, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b5d7e0"), Vector3(-0.15, 0.0, 0.1), Vector3.ZERO, Vector3(0.24, 0.009, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b5d7e0"), Vector3(0.15, 0.0, -0.1), Vector3.ZERO, Vector3(0.24, 0.009, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b5d7e0"), Vector3(0.15, 0.0, 0.1), Vector3.ZERO, Vector3(0.24, 0.009, 0.035))
			root.position = Vector3(0.0, 1.1, 1.6)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.18, 1.2))
		"moth":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("292b28"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.055, 0.06, 0.16))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a6a29a"), Vector3(-0.15, 0.0, -0.1), Vector3.ZERO, Vector3(0.18, 0.018, 0.1))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a6a29a"), Vector3(-0.15, 0.0, 0.1), Vector3.ZERO, Vector3(0.18, 0.018, 0.1))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a6a29a"), Vector3(0.15, 0.0, -0.1), Vector3.ZERO, Vector3(0.18, 0.018, 0.1))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a6a29a"), Vector3(0.15, 0.0, 0.1), Vector3.ZERO, Vector3(0.18, 0.018, 0.1))
			root.position = Vector3(2.45, 1.65, 0)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.12, 1.2))
			if place_id == "home":
				root.set_meta("in_house", true)
		"bee":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("292b28"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.095, 0.095, 0.2))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d5e1dd"), Vector3(-0.15, 0.0, -0.1), Vector3.ZERO, Vector3(0.14, 0.009, 0.055))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d5e1dd"), Vector3(-0.15, 0.0, 0.1), Vector3.ZERO, Vector3(0.14, 0.009, 0.055))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d5e1dd"), Vector3(0.15, 0.0, -0.1), Vector3.ZERO, Vector3(0.14, 0.009, 0.055))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d5e1dd"), Vector3(0.15, 0.0, 0.1), Vector3.ZERO, Vector3(0.14, 0.009, 0.055))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("e9b341"), Vector3(0.0, 0.0, 0.04), Vector3.ZERO, Vector3(0.1, 0.1, 0.045))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("e9b341"), Vector3(0.0, 0.0, -0.09), Vector3.ZERO, Vector3(0.095, 0.095, 0.04))
			root.position = Vector3(0.0, 1.1, 1.6)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.18, 1.2))
		"bead_net":
			_item_ring(root, Vector3(0.0, 0.0, 0.0), 0.28, 0.006, Color("b7c7c3"), Vector3(90.0, 0.0, 0.0))
			_item_segment(root, Vector3(-0.3, -0.25, 0.0), Vector3(0.3, 0.25, 0.0), 0.005, Color("b7c7c3"))
			_item_segment(root, Vector3(-0.3, 0.0, 0.0), Vector3(0.3, 0.0, 0.0), 0.005, Color("b7c7c3"))
			_item_segment(root, Vector3(-0.3, 0.25, 0.0), Vector3(0.3, -0.25, 0.0), 0.005, Color("b7c7c3"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d6eceb"), Vector3(-0.2, 0.0, 0.0), Vector3.ZERO, Vector3(0.02, 0.025, 0.02))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d6eceb"), Vector3(0.2, 0.0, 0.0), Vector3.ZERO, Vector3(0.02, 0.025, 0.02))
			root.position = Vector3(-1.4, 0.74, 0.06)
			root.set_meta("placed", true)
		"two_dents":
			_add(root, _box_mesh(Vector3(0.12, 0.018, 2.0)), Color("77674e"), Vector3(-0.45, 0.012, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.12, 0.018, 2.0)), Color("77674e"), Vector3(0.45, 0.012, 0.0), Vector3(0.0, 0.0, 0.0))
			root.position = Vector3(0.0, 0.01, -2.0)
			root.set_meta("placed", true)
		"post_coat":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("537044"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.09, 0.42, 0.02))
			root.position = Vector3(-0.8, 0.6, 0.1)
			root.set_meta("placed", true)
		"far_shut":
			_add(root, _box_mesh(Vector3(1.0, 0.04, 0.45)), Color("aa9474"), Vector3(0.0, 0.12, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.1, 0.16, 0.48)), Color("795235"), Vector3(-0.4, 0.08, 0.0), Vector3(0.0, 0.0, 0.0))
			root.position = Vector3(0.0, 0.0, -4.0)
			root.set_meta("placed", true)
		"far_smoke":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a4adb0"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.12, 0.48, 0.13))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a4adb0"), Vector3(0.0, 0.7, 0.0), Vector3.ZERO, Vector3(0.145, 0.48, 0.13))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a4adb0"), Vector3(0.0, 1.4, 0.0), Vector3.ZERO, Vector3(0.16999999999999998, 0.48, 0.13))
			root.position = Vector3(0.0, 5.0, -7.0)
			root.set_meta("placed", true)
		"cloud_shadow":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("4b6141"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(1.9, 0.005, 1.1))
			root.position = Vector3(-1.0, 1.61, 0.0)
			root.set_meta("placed", true)
		"blue_edge":
			_add(root, _cyl_mesh(0.0, 0.77, 1.1, 8), Color("718ba0"), Vector3(-0.7, 0.55, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.0, 1.1199999999999999, 1.6, 8), Color("718ba0"), Vector3(0.0, 0.8, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.0, 0.7, 1.0, 8), Color("718ba0"), Vector3(0.8, 0.5, 0.0), Vector3(0.0, 0.0, 0.0))
			root.position = Vector3(0, ground_height(_points, _points.get(place_id, Vector3.ZERO) + Vector3(0, 0, -7)), -7)
			root.set_meta("placed", true)
		"first_light":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("fff1c7"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.09, 0.09, 0.09))
			root.get_child(0).material_override = _mat(Color("fff1c7"), 1.0, false, 1.5)
			root.position = Vector3(0.0, 10.0, -6.0)
			root.set_meta("placed", true)
		"wind_line":
			_add(root, _cyl_mesh(0.0, 0.09, 0.6, 8), Color("a0a765"), Vector3(-0.6, 0.2, 0.0), Vector3(0.0, 0.0, -55.0))
			_add(root, _cyl_mesh(0.0, 0.09, 0.6, 8), Color("a0a765"), Vector3(-0.2, 0.2, 0.0), Vector3(0.0, 0.0, -55.0))
			_add(root, _cyl_mesh(0.0, 0.09, 0.6, 8), Color("a0a765"), Vector3(0.2, 0.2, 0.0), Vector3(0.0, 0.0, -55.0))
			_add(root, _cyl_mesh(0.0, 0.09, 0.6, 8), Color("a0a765"), Vector3(0.6, 0.2, 0.0), Vector3(0.0, 0.0, -55.0))
			root.position = Vector3(0.0, 1.62, 2.0)
			root.set_meta("placed", true)
		"green_jumper":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("649041"), Vector3(0.0, 0.16, 0.0), Vector3.ZERO, Vector3(0.1, 0.12, 0.25))
			_item_segment(root, Vector3(-0.12, 0.03, -0.2), Vector3(-0.24, 0.3, 0.12), 0.035, Color("6b8644"))
			_item_segment(root, Vector3(0.12, 0.03, -0.2), Vector3(0.24, 0.3, 0.12), 0.035, Color("6b8644"))
			_item_segment(root, Vector3(0.0, 0.2, 0.2), Vector3(-0.12, 0.36, 0.4), 0.009, Color("527637"))
			_item_segment(root, Vector3(0.0, 0.2, 0.2), Vector3(0.12, 0.36, 0.4), 0.009, Color("527637"))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"grass_ball":
			_add(root, _cyl_mesh(0.018, 0.018, 1.3, 8), Color("527637"), Vector3(-0.25, 0.65, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.018, 0.018, 1.3, 8), Color("527637"), Vector3(0.0, 0.65, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.018, 0.018, 1.3, 8), Color("527637"), Vector3(0.25, 0.65, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b6a16b"), Vector3(0.0, 0.9, 0.0), Vector3.ZERO, Vector3(0.24, 0.25, 0.22))
			_item_ring(root, Vector3(0.0, 0.92, 0.2), 0.065, 0.018, Color("887444"), Vector3(90.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1, 8, 4), Color("443b29"), Vector3(0, 0.92, 0.207), Vector3.ZERO, Vector3(0.052, 0.052, 0.01))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.015)
		"stem_cup":
			_add(root, _cyl_mesh(0.018, 0.018, 1.3, 8), Color("527637"), Vector3(-0.25, 0.65, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.018, 0.018, 1.3, 8), Color("527637"), Vector3(0.0, 0.65, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.018, 0.018, 1.3, 8), Color("527637"), Vector3(0.25, 0.65, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b6a16b"), Vector3(0.0, 0.9, 0.0), Vector3.ZERO, Vector3(0.22, 0.16, 0.2))
			_item_ring(root, Vector3(0.0, 1.02, 0.0), 0.16, 0.045, Color("887444"), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("e1d9b7"), Vector3(0.0, 0.99, 0.0), Vector3.ZERO, Vector3(0.065, 0.08, 0.06))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.015)
		"hook_seeds":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("977743"), Vector3(-0.2, 0.04, 0.0), Vector3.ZERO, Vector3(0.065, 0.045, 0.07))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("977743"), Vector3(0.0, 0.04, 0.0), Vector3.ZERO, Vector3(0.065, 0.045, 0.07))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("977743"), Vector3(0.2, 0.04, 0.0), Vector3.ZERO, Vector3(0.065, 0.045, 0.07))
			_item_ring(root, Vector3(-0.2, 0.04, 0.08), 0.04, 0.009, Color("806333"), Vector3(90.0, 0.0, 0.0))
			_item_ring(root, Vector3(0.0, 0.04, 0.08), 0.04, 0.009, Color("806333"), Vector3(90.0, 0.0, 0.0))
			_item_ring(root, Vector3(0.2, 0.04, 0.08), 0.04, 0.009, Color("806333"), Vector3(90.0, 0.0, 0.0))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"froth_sitter":
			_add(root, _cyl_mesh(0.02, 0.02, 0.8, 8), Color("527637"), Vector3(0.0, 0.4, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("e9ead9"), Vector3(0.0, 0.5, 0.0), Vector3.ZERO, Vector3(0.12, 0.15, 0.12))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("739742"), Vector3(0.0, 0.5, 0.11), Vector3.ZERO, Vector3(0.035, 0.04, 0.04))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"quick_shadows":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("304e58"), Vector3(-0.4, 0.0, 0.0), Vector3.ZERO, Vector3(0.08, 0.025, 0.27))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("304e58"), Vector3(0.0, 0.0, 0.2), Vector3.ZERO, Vector3(0.08, 0.025, 0.27))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("304e58"), Vector3(0.3, 0.0, -0.15), Vector3.ZERO, Vector3(0.08, 0.025, 0.27))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 4.8 + Vector3(0, 0.065, 0)
			root.set_meta("placed", true)
		"water_walkers":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("292b28"), Vector3(0.0, 0.08, 0.0), Vector3.ZERO, Vector3(0.035, 0.025, 0.15))
			_item_segment(root, Vector3(-0.3, 0.0, -0.2), Vector3(0.0, 0.08, 0.0), 0.008, Color("292b28"))
			_item_segment(root, Vector3(-0.3, 0.0, 0.0), Vector3(0.0, 0.08, 0.0), 0.008, Color("292b28"))
			_item_segment(root, Vector3(-0.3, 0.0, 0.2), Vector3(0.0, 0.08, 0.0), 0.008, Color("292b28"))
			_item_segment(root, Vector3(0.3, 0.0, -0.2), Vector3(0.0, 0.08, 0.0), 0.008, Color("292b28"))
			_item_segment(root, Vector3(0.3, 0.0, 0.0), Vector3(0.0, 0.08, 0.0), 0.008, Color("292b28"))
			_item_segment(root, Vector3(0.3, 0.0, 0.2), Vector3(0.0, 0.08, 0.0), 0.008, Color("292b28"))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 4.8 + Vector3(1, 0.07, 0)
			root.set_meta("placed", true)
		"ringed_stone":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("505358"), Vector3(0.0, 0.13, 0.0), Vector3.ZERO, Vector3(0.23, 0.13, 0.18))
			_item_ring(root, Vector3(0.0, 0.13, 0.0), 0.185, 0.018, Color("e5e1cf"), Vector3(0.0, 0.0, 15.0))
			root.position = Vector3(1.0, 0.0, 1.0)
			root.set_meta("placed", true)
		"hanging_colours":
			var colors := [Color("b97c70"), Color("c5a773"), Color("bdba7a"), Color("8eae8c"), Color("829fac"), Color("9992b1")]
			for k in range(6):
				var a := PI * k / 6.0
				var z := PI * (k + 1) / 6.0
				_item_segment(root, Vector3(cos(a) * 0.55, sin(a) * 0.55 + 0.15, 0), Vector3(cos(z) * 0.55, sin(z) * 0.55 + 0.15, 0), 0.025, colors[k])
			_add(root, _sphere_mesh(0.4, 7, 4), Color("7f8785"), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1.5, 0.4, 1))
			_add(root, _box_mesh(Vector3(0.25, 0.2, 0.04)), Color("b2d4d9"), Vector3(0, 0.14, 0.3))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 4.8 + Vector3(0, 0.08, -4.2)
			root.set_meta("placed", true)
		"tail_basker":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("82865b"), Vector3(0.0, 0.12, 0.0), Vector3.ZERO, Vector3(0.1, 0.07, 0.26))
			_item_segment(root, Vector3(0.0, 0.1, -0.2), Vector3(0.15, 0.06, -0.7), 0.035, Color("82865b"))
			_item_segment(root, Vector3(-0.2, 0.04, -0.12), Vector3(0.2, 0.04, -0.12), 0.025, Color("82865b"))
			_item_segment(root, Vector3(-0.2, 0.04, 0.14), Vector3(0.2, 0.04, 0.14), 0.025, Color("82865b"))
			root.position = Vector3(1.0, 0.3, 1.0)
			root.set_meta("placed", true)
		"curled_stone":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("aaa591"), Vector3(0.0, 0.13, 0.0), Vector3.ZERO, Vector3(0.35, 0.13, 0.3))
			_item_ring(root, Vector3(0.0, 0.245, 0.0), 0.17, 0.025, Color("666556"), Vector3(0.0, 0.0, 0.0))
			_item_ring(root, Vector3(0.03, 0.25, 0.0), 0.08, 0.018, Color("666556"), Vector3(0.0, 0.0, 0.0))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"spark_stone":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("737984"), Vector3(0.0, 0.12, 0.0), Vector3.ZERO, Vector3(0.3, 0.12, 0.25))
			_add(root, _cyl_mesh(0.0, 0.055, 0.15, 8), Color("d5dbdf"), Vector3(-0.1, 0.24, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.0, 0.055, 0.15, 8), Color("d5dbdf"), Vector3(0.12, 0.24, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.0, 0.055, 0.15, 8), Color("d5dbdf"), Vector3(0.0, 0.24, 0.1), Vector3(0.0, 0.0, 0.0))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"stone_coats":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("91968e"), Vector3(0.0, 0.15, 0.0), Vector3.ZERO, Vector3(0.35, 0.15, 0.3))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("c1823e"), Vector3(0.15, 0.25, 0.0), Vector3.ZERO, Vector3(0.15, 0.025, 0.14))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("bcc1b0"), Vector3(-0.15, 0.25, 0.0), Vector3.ZERO, Vector3(0.13, 0.025, 0.1))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"pouring_thing":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("6f7652"), Vector3(0.0, 0.055, 0.0), Vector3.ZERO, Vector3(0.15, 0.05, 0.07))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("6f7652"), Vector3(0.19, 0.055, 0.12), Vector3.ZERO, Vector3(0.15, 0.05, 0.07))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("6f7652"), Vector3(0.38, 0.055, 0.0), Vector3.ZERO, Vector3(0.15, 0.05, 0.07))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("6f7652"), Vector3(0.5700000000000001, 0.055, 0.12), Vector3.ZERO, Vector3(0.15, 0.05, 0.07))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("626d4c"), Vector3(0.7, 0.06, 0.0), Vector3.ZERO, Vector3(0.11, 0.065, 0.08))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"bank_holes":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("393a35"), Vector3(-0.4, 0.0, 0.0), Vector3.ZERO, Vector3(0.12, 0.1, 0.018))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("393a35"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.12, 0.1, 0.018))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("393a35"), Vector3(0.4, 0.0, 0.0), Vector3.ZERO, Vector3(0.12, 0.1, 0.018))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 2.5 + Vector3(0, 0.35, 2.18)
			root.set_meta("placed", true)
		"bank_stripes":
			_add(root, _box_mesh(Vector3(1.0, 0.08, 0.12)), Color("898b82"), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(1.0, 0.08, 0.12)), Color("776351"), Vector3(0.0, 0.09, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(1.0, 0.08, 0.12)), Color("aaada5"), Vector3(0.0, 0.18, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(1.0, 0.08, 0.12)), Color("796b59"), Vector3(0.0, 0.27, 0.0), Vector3(0.0, 0.0, 0.0))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 2.5 + Vector3(0, 0.05, 2.1)
			root.set_meta("placed", true)
		"reaching_root":
			_item_segment(root, Vector3(0.0, 0.45, 0.0), Vector3(0.5, 0.35, 0.4), 0.055, Color("795235"))
			_item_segment(root, Vector3(0.5, 0.35, 0.4), Vector3(0.75, 0.1, 0.5), 0.03, Color("795235"))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * 2.5 + Vector3(1, 0, 1.5)
			root.set_meta("placed", true)
		"cupped_shiner":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("414746"), Vector3(0.0, 0.05, 0.0), Vector3.ZERO, Vector3(0.27, 0.08, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a4b9bb"), Vector3(0.0, 0.11, 0.0), Vector3.ZERO, Vector3(0.22, 0.015, 0.13))
			_item_ring(root, Vector3(0.0, 0.105, 0.0), 0.17, 0.025, Color("454d4e"), Vector3(0.0, 0.0, 0.0))
			root.position = Vector3(1.0, 0.06, 0.0)
			root.set_meta("placed", true)
		"smooth_wood":
			_add(root, _cyl_mesh(0.09, 0.09, 0.85, 8), Color("b9aa8c"), Vector3(0.0, 0.08, 0.0), Vector3(0.0, 0.0, 90.0))
			_item_segment(root, Vector3(0.2, 0.08, 0.0), Vector3(0.4, 0.1, 0.22), 0.045, Color("b9aa8c"))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"bubble_holes":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("625d4d"), Vector3(-0.2, 0.005, 0.0), Vector3.ZERO, Vector3(0.05, 0.009, 0.05))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("625d4d"), Vector3(0.0, 0.005, 0.0), Vector3.ZERO, Vector3(0.05, 0.009, 0.05))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("625d4d"), Vector3(0.2, 0.005, 0.0), Vector3.ZERO, Vector3(0.05, 0.009, 0.05))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("bfd7d3"), Vector3(-0.2, 0.045, 0.0), Vector3.ZERO, Vector3(0.035, 0.04, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("bfd7d3"), Vector3(0.2, 0.045, 0.0), Vector3.ZERO, Vector3(0.035, 0.04, 0.035))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"dotted_wobble":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a7c5b5"), Vector3(0.0, 0.08, 0.0), Vector3.ZERO, Vector3(0.35, 0.08, 0.25))
			root.get_child(0).material_override = _mat(Color("bfd8cb"), 0.5)
			_add(root, _sphere_mesh(1.0, 12, 6), Color("242d25"), Vector3(-0.15, 0.1, 0.0), Vector3.ZERO, Vector3(0.035, 0.025, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("242d25"), Vector3(0.0, 0.1, 0.1), Vector3.ZERO, Vector3(0.035, 0.025, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("242d25"), Vector3(0.15, 0.1, -0.05), Vector3.ZERO, Vector3(0.035, 0.025, 0.035))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("242d25"), Vector3(0.0, 0.1, -0.12), Vector3.ZERO, Vector3(0.035, 0.025, 0.035))
			_add(root, _cyl_mesh(0.6, 0.6, 0.02, 12), Color("7b9d9d"), Vector3(0, -0.01, 0))
			root.position = Vector3(0.0, 0.05, -1.0)
			root.set_meta("placed", true)
		"deep_breath":
			_add(root, _cyl_mesh(0.035, 0.035, 1.3, 8), Color("7e8c4b"), Vector3(-0.18, 0.65, 0.0), Vector3(0.0, 0.0, 20.0))
			_add(root, _cyl_mesh(0.035, 0.035, 1.3, 8), Color("7e8c4b"), Vector3(0.0, 0.65, 0.0), Vector3(0.0, 0.0, 20.0))
			_add(root, _cyl_mesh(0.035, 0.035, 1.3, 8), Color("7e8c4b"), Vector3(0.18, 0.65, 0.0), Vector3(0.0, 0.0, 20.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("333e2e"), Vector3(0.0, 0.03, 0.0), Vector3.ZERO, Vector3(0.3, 0.025, 0.25))
			root.position = Vector3(1.0, 0.0, -1.0)
			root.set_meta("placed", true)
		"pale_ring":
			_add(root, _cyl_mesh(0.035, 0.035, 0.24, 8), Color("c5bba1"), Vector3(-0.35, 0.12, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.04, 0.17, 0.13, 8), Color("e4d7b5"), Vector3(-0.35, 0.25, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.035, 0.035, 0.24, 8), Color("c5bba1"), Vector3(0.0, 0.12, 0.35), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.04, 0.17, 0.13, 8), Color("e4d7b5"), Vector3(0.0, 0.25, 0.35), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.035, 0.035, 0.24, 8), Color("c5bba1"), Vector3(0.35, 0.12, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.04, 0.17, 0.13, 8), Color("e4d7b5"), Vector3(0.35, 0.25, 0.0), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.035, 0.035, 0.24, 8), Color("c5bba1"), Vector3(0.0, 0.12, -0.35), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.04, 0.17, 0.13, 8), Color("e4d7b5"), Vector3(0.0, 0.25, -0.35), Vector3(0.0, 0.0, 0.0))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"green_log":
			_add(root, _cyl_mesh(0.25, 0.25, 1.5, 8), Color("795235"), Vector3(0.0, 0.25, 0.0), Vector3(0.0, 0.0, 90.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("617f46"), Vector3(0.0, 0.4, 0.0), Vector3.ZERO, Vector3(0.7, 0.12, 0.23))
			_add(root, _cyl_mesh(0.2, 0.2, 0.02, 8), Color("dcc89e"), Vector3(0.76, 0.25, 0.0), Vector3(0.0, 0.0, 90.0))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"root_door":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("262c21"), Vector3(0.0, 0.04, 0.0), Vector3.ZERO, Vector3(0.24, 0.04, 0.32))
			_item_segment(root, Vector3(-0.3, 0.04, 0.3), Vector3(-0.2, 0.3, -0.3), 0.07, Color("795235"))
			_item_segment(root, Vector3(0.3, 0.04, 0.3), Vector3(0.2, 0.3, -0.3), 0.07, Color("795235"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("87785b"), Vector3(0.0, 0.025, 0.4), Vector3.ZERO, Vector3(0.3, 0.02, 0.2))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"wren":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("8c6545"), Vector3(0.0, 0.18, 0.0), Vector3.ZERO, Vector3(0.16, 0.18, 0.27))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("98724d"), Vector3(0.0, 0.34, 0.2), Vector3.ZERO, Vector3(0.12, 0.12, 0.12))
			_add(root, _cyl_mesh(0.0, 0.035, 0.17, 8), Color("a28c50"), Vector3(0.0, 0.33, 0.36), Vector3(90.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.12, 0.05, 0.25)), Color("8c6545"), Vector3(0.0, 0.18, -0.3), Vector3(-45.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("161e19"), Vector3(0.09, 0.37, 0.26), Vector3.ZERO, Vector3(0.018, 0.018, 0.018))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("e0d3ad"), Vector3(0.0, 0.23, 0.18), Vector3.ZERO, Vector3(0.09, 0.09, 0.08))
			root.position = Vector3(0.0, 1.6, 1.5)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.35, 0.65))
		"woodpecker":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("303933"), Vector3(0.0, 0.18, 0.0), Vector3.ZERO, Vector3(0.16, 0.18, 0.27))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b93e34"), Vector3(0.0, 0.34, 0.2), Vector3.ZERO, Vector3(0.12, 0.12, 0.12))
			_add(root, _cyl_mesh(0.0, 0.035, 0.17, 8), Color("a28c50"), Vector3(0.0, 0.33, 0.36), Vector3(90.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.12, 0.05, 0.25)), Color("303933"), Vector3(0.0, 0.18, -0.3), Vector3(-15.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("161e19"), Vector3(0.09, 0.37, 0.26), Vector3.ZERO, Vector3(0.018, 0.018, 0.018))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("e0d3ad"), Vector3(0.0, 0.23, 0.18), Vector3.ZERO, Vector3(0.1, 0.18, 0.08))
			root.position = Vector3(0.0, 1.6, 1.5)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.35, 0.65))
		"blue_flash":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("287da2"), Vector3(0.0, 0.18, 0.0), Vector3.ZERO, Vector3(0.16, 0.18, 0.27))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("268ac1"), Vector3(0.0, 0.34, 0.2), Vector3.ZERO, Vector3(0.12, 0.12, 0.12))
			_add(root, _cyl_mesh(0.0, 0.035, 0.17, 8), Color("a28c50"), Vector3(0.0, 0.33, 0.36), Vector3(90.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.12, 0.05, 0.25)), Color("287da2"), Vector3(0.0, 0.18, -0.3), Vector3(-15.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("287da2"), Vector3(-0.32, 0.22, 0.0), Vector3.ZERO, Vector3(0.45, 0.035, 0.15))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("287da2"), Vector3(0.32, 0.22, 0.0), Vector3.ZERO, Vector3(0.45, 0.035, 0.15))
			root.position = Vector3(0.0, 1.6, 1.5)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.35, 0.65))
		"two_notes":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("8b7b5c"), Vector3(0.0, 0.18, 0.0), Vector3.ZERO, Vector3(0.16, 0.18, 0.27))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("9f8d6b"), Vector3(0.0, 0.34, 0.2), Vector3.ZERO, Vector3(0.12, 0.12, 0.12))
			_add(root, _cyl_mesh(0.0, 0.035, 0.17, 8), Color("a28c50"), Vector3(0.0, 0.33, 0.36), Vector3(90.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.12, 0.05, 0.25)), Color("8b7b5c"), Vector3(0.0, 0.18, -0.3), Vector3(-15.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("161e19"), Vector3(0.09, 0.37, 0.26), Vector3.ZERO, Vector3(0.018, 0.018, 0.018))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("e0d3ad"), Vector3(0.0, 0.23, 0.18), Vector3.ZERO, Vector3(0.09, 0.09, 0.08))
			root.position = Vector3(0.0, 1.6, 1.5)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.02)
		"wide_wings":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("6d604a"), Vector3(0.0, 0.18, 0.0), Vector3.ZERO, Vector3(0.16, 0.18, 0.27))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("82725a"), Vector3(0.0, 0.34, 0.2), Vector3.ZERO, Vector3(0.12, 0.12, 0.12))
			_add(root, _cyl_mesh(0.0, 0.035, 0.17, 8), Color("a28c50"), Vector3(0.0, 0.33, 0.36), Vector3(90.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.12, 0.05, 0.25)), Color("6d604a"), Vector3(0.0, 0.18, -0.3), Vector3(-15.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("6d604a"), Vector3(-0.32, 0.22, 0.0), Vector3.ZERO, Vector3(0.45, 0.035, 0.15))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("6d604a"), Vector3(0.32, 0.22, 0.0), Vector3.ZERO, Vector3(0.45, 0.035, 0.15))
			root.position = Vector3(0.0, 3.2, 1.5)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.35, 0.65))
		"hanging_bird":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("927958"), Vector3(0.0, 0.18, 0.0), Vector3.ZERO, Vector3(0.16, 0.18, 0.27))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a58c68"), Vector3(0.0, 0.34, 0.2), Vector3.ZERO, Vector3(0.12, 0.12, 0.12))
			_add(root, _cyl_mesh(0.0, 0.035, 0.17, 8), Color("a28c50"), Vector3(0.0, 0.33, 0.36), Vector3(90.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.12, 0.05, 0.25)), Color("927958"), Vector3(0.0, 0.18, -0.3), Vector3(-15.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("927958"), Vector3(-0.32, 0.22, 0.0), Vector3.ZERO, Vector3(0.45, 0.035, 0.15))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("927958"), Vector3(0.32, 0.22, 0.0), Vector3.ZERO, Vector3(0.45, 0.035, 0.15))
			root.position = Vector3(0.0, 3.2, 1.5)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(0.35, 0.65))
		"spider":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("494039"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.09, 0.07, 0.12))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("302e29"), Vector3(0.0, 0.0, 0.13), Vector3.ZERO, Vector3(0.06, 0.05, 0.06))
			_item_segment(root, Vector3(-0.2, 0.0, -0.2), Vector3(0.2, 0.0, 0.2), 0.012, Color("494039"))
			_item_segment(root, Vector3(-0.2, 0.0, -0.07), Vector3(0.2, 0.0, 0.07), 0.012, Color("494039"))
			_item_segment(root, Vector3(-0.2, 0.0, 0.07), Vector3(0.2, 0.0, -0.07), 0.012, Color("494039"))
			_item_segment(root, Vector3(-0.2, 0.0, 0.2), Vector3(0.2, 0.0, -0.2), 0.012, Color("494039"))
			root.position = Vector3(0.65, 2.25, 1.48)
			root.set_meta("placed", true)
			root.set_meta("in_house", true)
			root.rotation_degrees.x = 70
			root.set_meta("bob", 0.01)
		"ant":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("302c25"), Vector3(0.0, 0.06, -0.13), Vector3.ZERO, Vector3(0.045, 0.05, 0.07))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("302c25"), Vector3(0.0, 0.06, 0.0), Vector3.ZERO, Vector3(0.045, 0.05, 0.07))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("302c25"), Vector3(0.0, 0.06, 0.11), Vector3.ZERO, Vector3(0.045, 0.05, 0.07))
			_item_segment(root, Vector3(-0.13, 0.02, -0.1), Vector3(0.13, 0.02, -0.05), 0.009, Color("302c25"))
			_item_segment(root, Vector3(-0.13, 0.02, 0.0), Vector3(0.13, 0.02, 0.05), 0.009, Color("302c25"))
			_item_segment(root, Vector3(-0.13, 0.02, 0.1), Vector3(0.13, 0.02, 0.15000000000000002), 0.009, Color("302c25"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a5a45c"), Vector3(0.0, 0.1, 0.23), Vector3.ZERO, Vector3(0.08, 0.025, 0.1))
			root.position = Vector3(0.5, 0.0, 0.5)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.005)
		"bat":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("3b343c"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.1, 0.12, 0.18))
			_add(root, _prism_mesh(Vector3(0.65, 0.05, 0.38)), Color("463d49"), Vector3(-0.32, 0, 0), Vector3(0, -20, 0))
			_add(root, _prism_mesh(Vector3(0.65, 0.05, 0.38)), Color("463d49"), Vector3(0.32, 0, 0), Vector3(0, 20, 0))
			_add(root, _cyl_mesh(0.0, 0.05, 0.14, 8), Color("3b343c"), Vector3(-0.06, 0.14, 0.1), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.0, 0.05, 0.14, 8), Color("3b343c"), Vector3(0.06, 0.14, 0.1), Vector3(0.0, 0.0, 0.0))
			root.position = Vector3(0.0, 4.0, 0.0)
			root.set_meta("placed", true)
			root.set_meta("fly", Vector2(1.3, 1.3))
		"squirrel":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("87837a"), Vector3(0.0, 0.25, 0.0), Vector3.ZERO, Vector3(0.18, 0.25, 0.16))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("9a9386"), Vector3(0.0, 0.5, 0.12), Vector3.ZERO, Vector3(0.13, 0.13, 0.14))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("969187"), Vector3(0.0, 0.36, -0.27), Vector3.ZERO, Vector3(0.19, 0.35, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("969187"), Vector3(0.0, 0.6, -0.28), Vector3.ZERO, Vector3(0.2, 0.18, 0.2))
			_add(root, _cyl_mesh(0.0, 0.045, 0.14, 8), Color("87837a"), Vector3(-0.08, 0.65, 0.1), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.0, 0.045, 0.14, 8), Color("87837a"), Vector3(0.08, 0.65, 0.1), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("252823"), Vector3(0.1, 0.53, 0.2), Vector3.ZERO, Vector3(0.02, 0.02, 0.02))
			root.position = Vector3(1.0, 0.0, 1.0)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.02)
		"snail":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("999e77"), Vector3(0.0, 0.06, 0.0), Vector3.ZERO, Vector3(0.12, 0.06, 0.32))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("aa8256"), Vector3(0.0, 0.22, -0.08), Vector3.ZERO, Vector3(0.18, 0.2, 0.18))
			_item_ring(root, Vector3(0.16, 0.22, -0.08), 0.1, 0.018, Color("66563d"), Vector3(0.0, 0.0, 90.0))
			_item_segment(root, Vector3(-0.06, 0.1, 0.23), Vector3(-0.06, 0.24, 0.3), 0.014, Color("999e77"))
			_item_segment(root, Vector3(0.06, 0.1, 0.23), Vector3(0.06, 0.24, 0.3), 0.014, Color("999e77"))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.005)
		"hare":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a18462"), Vector3(0.0, 0.25, 0.0), Vector3.ZERO, Vector3(0.23, 0.25, 0.38))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b69873"), Vector3(0.0, 0.47, 0.25), Vector3.ZERO, Vector3(0.15, 0.17, 0.16))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a18462"), Vector3(-0.085, 0.78, 0.23), Vector3.ZERO, Vector3(0.05, 0.25, 0.065))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a18462"), Vector3(0.085, 0.78, 0.23), Vector3.ZERO, Vector3(0.05, 0.25, 0.065))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("806c52"), Vector3(-0.2, 0.1, -0.1), Vector3.ZERO, Vector3(0.12, 0.12, 0.26))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("806c52"), Vector3(0.2, 0.1, -0.1), Vector3.ZERO, Vector3(0.12, 0.12, 0.26))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("242820"), Vector3(0.12, 0.52, 0.33), Vector3.ZERO, Vector3(0.02, 0.02, 0.02))
			root.position = Vector3(0.0, 0.0, 2.0)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.015)
		"frog":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("638044"), Vector3(0.0, 0.12, 0.0), Vector3.ZERO, Vector3(0.2, 0.12, 0.23))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("50713c"), Vector3(-0.2, 0.08, -0.12), Vector3.ZERO, Vector3(0.12, 0.08, 0.22))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("50713c"), Vector3(0.2, 0.08, -0.12), Vector3.ZERO, Vector3(0.12, 0.08, 0.22))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("bbc16f"), Vector3(-0.1, 0.23, 0.12), Vector3.ZERO, Vector3(0.065, 0.06, 0.06))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("bbc16f"), Vector3(0.1, 0.23, 0.12), Vector3.ZERO, Vector3(0.065, 0.06, 0.06))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("202a20"), Vector3(-0.1, 0.25, 0.16), Vector3.ZERO, Vector3(0.028, 0.025, 0.025))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("202a20"), Vector3(0.1, 0.25, 0.16), Vector3.ZERO, Vector3(0.028, 0.025, 0.025))
			root.position = (_outward(_points.get(place_id, Vector3.ZERO)) * 2.5 + Vector3(1.5, 0.06, 2.6)) if place_id == "grey_bank" else Vector3(0, 0.07, 2)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.01)
			if place_id == "tall_reeds":
				_add(root, _cyl_mesh(0.65, 0.65, 0.02, 12), Color("74999b"), Vector3(0, -0.03, -0.25))
		"duck":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("8d6d48"), Vector3(0.0, 0.2, 0.0), Vector3.ZERO, Vector3(0.25, 0.18, 0.38))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("a1855b"), Vector3(0.0, 0.43, 0.28), Vector3.ZERO, Vector3(0.13, 0.14, 0.14))
			_add(root, _box_mesh(Vector3(0.15, 0.05, 0.19)), Color("d6a14a"), Vector3(0.0, 0.42, 0.45), Vector3(0.0, 0.0, 0.0))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d2b55d"), Vector3(-0.2, 0.12, -0.6), Vector3.ZERO, Vector3(0.11, 0.1, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d2b55d"), Vector3(0.1, 0.12, -0.95), Vector3.ZERO, Vector3(0.11, 0.1, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("d2b55d"), Vector3(-0.1, 0.12, -1.3), Vector3.ZERO, Vector3(0.11, 0.1, 0.17))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("252a22"), Vector3(0.1, 0.47, 0.35), Vector3.ZERO, Vector3(0.02, 0.02, 0.02))
			root.position = _outward(_points.get(place_id, Vector3.ZERO)) * (4.8 if place_id == "water" else 0.8) + Vector3(0, 0.07, 0)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.015)
			if place_id == "tall_reeds":
				_add(root, _cyl_mesh(0.65, 0.65, 0.02, 12), Color("74999b"), Vector3(0, -0.03, -0.25))
		"deer":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("9d7955"), Vector3(0.0, 1.0, 0.0), Vector3.ZERO, Vector3(0.28, 0.36, 0.6))
			_item_segment(root, Vector3(0.0, 1.0, 0.4), Vector3(0.0, 1.65, 0.62), 0.13, Color("a5835c"))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("aa8a61"), Vector3(0.0, 1.7, 0.75), Vector3.ZERO, Vector3(0.14, 0.17, 0.26))
			_add(root, _cyl_mesh(0.035, 0.035, 0.8, 8), Color("846445"), Vector3(-0.19, 0.4, -0.37), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.035, 0.035, 0.8, 8), Color("846445"), Vector3(-0.19, 0.4, 0.35), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.035, 0.035, 0.8, 8), Color("846445"), Vector3(0.19, 0.4, -0.37), Vector3(0.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.035, 0.035, 0.8, 8), Color("846445"), Vector3(0.19, 0.4, 0.35), Vector3(0.0, 0.0, 0.0))
			_add(root, _box_mesh(Vector3(0.43, 0.08, 0.13)), Color("a98a64"), Vector3(0.0, 1.91, 0.62), Vector3(0.0, 0.0, 0.0))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
			root.set_meta("bob", 0.015)
		"moon":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("eeecd1"), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(1.5, 1.5, 1.5))
			root.get_child(0).material_override = _mat(Color("eeecd1"), 1.0, false, 1.5)
			root.position = Vector3(0.0, 32.0, 0.0)
			root.set_meta("placed", true)
		"stone":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("969b99"), Vector3(-0.22, 0.12, 0.0), Vector3.ZERO, Vector3(0.24, 0.13, 0.2))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("969b99"), Vector3(0.18, 0.12, 0.15), Vector3.ZERO, Vector3(0.24, 0.13, 0.2))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("969b99"), Vector3(0.0, 0.12, -0.2), Vector3.ZERO, Vector3(0.24, 0.13, 0.2))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"flint":
			_add(root, _sphere_mesh(1.0, 5, 3), Color("343e48"), Vector3(-0.22, 0.12, 0.0), Vector3.ZERO, Vector3(0.24, 0.13, 0.2))
			_add(root, _sphere_mesh(1.0, 5, 3), Color("343e48"), Vector3(0.18, 0.12, 0.15), Vector3.ZERO, Vector3(0.24, 0.13, 0.2))
			_add(root, _sphere_mesh(1.0, 5, 3), Color("343e48"), Vector3(0.0, 0.12, -0.2), Vector3.ZERO, Vector3(0.24, 0.13, 0.2))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"earth":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("68513b"), Vector3(-0.22, 0.12, 0.0), Vector3.ZERO, Vector3(0.3, 0.09, 0.25))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("68513b"), Vector3(0.18, 0.12, 0.15), Vector3.ZERO, Vector3(0.3, 0.09, 0.25))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("68513b"), Vector3(0.0, 0.12, -0.2), Vector3.ZERO, Vector3(0.3, 0.09, 0.25))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"sand":
			_add(root, _cyl_mesh(0.08, 0.38, 0.22, 12), Color("d4bd80"), Vector3(-0.22, 0.12, 0.0), Vector3.ZERO)
			_add(root, _cyl_mesh(0.08, 0.38, 0.22, 12), Color("d4bd80"), Vector3(0.18, 0.12, 0.15), Vector3.ZERO)
			_add(root, _cyl_mesh(0.08, 0.38, 0.22, 12), Color("d4bd80"), Vector3(0.0, 0.12, -0.2), Vector3.ZERO)
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"stick":
			_add(root, _cyl_mesh(0.035, 0.035, 0.9, 8), Color("795235"), Vector3(0.0, 0.06, 0.0), Vector3(80.0, 0.0, 10.0))
			_add(root, _cyl_mesh(0.035, 0.035, 0.9, 8), Color("795235"), Vector3(0.16, 0.06, 0.0), Vector3(80.0, 15.0, 10.0))
			_add(root, _cyl_mesh(0.035, 0.035, 0.9, 8), Color("795235"), Vector3(0.32, 0.06, 0.0), Vector3(80.0, 30.0, 10.0))
			root.position = Vector3(2.0, 0.0, 0.0)
			root.set_meta("placed", true)
		"reed":
			_add(root, _cyl_mesh(0.025, 0.025, 1.1, 8), Color("b4a371"), Vector3(0.0, 0.08, 0.0), Vector3(85.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.025, 0.025, 1.1, 8), Color("b4a371"), Vector3(0.08, 0.08, 0.0), Vector3(85.0, 6.0, 0.0))
			_add(root, _cyl_mesh(0.025, 0.025, 1.1, 8), Color("b4a371"), Vector3(0.16, 0.08, 0.0), Vector3(85.0, 12.0, 0.0))
			_add(root, _cyl_mesh(0.025, 0.025, 1.1, 8), Color("b4a371"), Vector3(0.24, 0.08, 0.0), Vector3(85.0, 18.0, 0.0))
			_item_ring(root, Vector3(0.12, 0.08, 0.0), 0.13, 0.015, Color("795235"), Vector3(90.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.05, 0.05, 0.22, 8), Color("755538"), Vector3(0.08, 0.09, 0.45), Vector3(90, 0, 0))
			root.position = Vector3(-2.0, 0.0, 0.0)
			root.set_meta("placed", true)
		"grass":
			_add(root, _cyl_mesh(0.0, 0.065, 1.1, 4), Color("92a65a"), Vector3(0.0, 0.08, 0.0), Vector3(85.0, 0.0, 0.0))
			_add(root, _cyl_mesh(0.0, 0.065, 1.1, 4), Color("92a65a"), Vector3(0.08, 0.08, 0.0), Vector3(85.0, 6.0, 0.0))
			_add(root, _cyl_mesh(0.0, 0.065, 1.1, 4), Color("92a65a"), Vector3(0.16, 0.08, 0.0), Vector3(85.0, 12.0, 0.0))
			_add(root, _cyl_mesh(0.0, 0.065, 1.1, 4), Color("92a65a"), Vector3(0.24, 0.08, 0.0), Vector3(85.0, 18.0, 0.0))
			_item_ring(root, Vector3(0.12, 0.08, 0.0), 0.13, 0.015, Color("795235"), Vector3(90.0, 0.0, 0.0))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"seed":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b59a5f"), Vector3(-0.2, 0.04, 0.0), Vector3.ZERO, Vector3(0.06, 0.04, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b59a5f"), Vector3(0.0, 0.04, 0.0), Vector3.ZERO, Vector3(0.06, 0.04, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b59a5f"), Vector3(0.2, 0.04, 0.1), Vector3.ZERO, Vector3(0.06, 0.04, 0.09))
			_add(root, _sphere_mesh(1.0, 12, 6), Color("b59a5f"), Vector3(0.0, 0.04, 0.2), Vector3.ZERO, Vector3(0.06, 0.04, 0.09))
			_item_segment(root, Vector3(-0.25, 0.04, -0.2), Vector3(0.1, 0.07, 0.3), 0.012, Color("a18b55"))
			_item_segment(root, Vector3(0.25, 0.04, -0.1), Vector3(-0.15, 0.07, 0.3), 0.012, Color("a18b55"))
			root.position = _item_clear_ground(id, place_id)
			root.set_meta("placed", true)
		"water":
			_add(root, _sphere_mesh(1.0, 12, 6), Color("6a9dba"), Vector3(0.0, 0.015, 0.0), Vector3.ZERO, Vector3(0.65, 0.015, 0.5))
			_item_ring(root, Vector3(0.0, 0.032, 0.0), 0.3, 0.012, Color("a9c8d0"), Vector3(0.0, 0.0, 0.0))
			root.position = Vector3(-1.0, 0.05, 0.0)
			root.set_meta("placed", true)

	_item_detail(root, id)
	if root.has_meta("placed"):
		var low := 0.0
		for child in root.get_children():
			if child is MeshInstance3D:
				var bounds: AABB = child.transform * child.get_aabb()
				low = minf(low, bounds.position.y)
		if low < 0:
			for child in root.get_children():
				child.position.y -= low
			root.position += root.basis * Vector3(0, low, 0)
	_merge_item_parts(root)
	if place_id == "gate" and id in ["post_coat", "bead_net", "two_dents", "far_shut"]:
		var toward := _neighbour_dir("gate")
		var side := Vector3(-toward.z, 0, toward.x)
		var yaw := atan2(-side.z, side.x)
		root.position = root.position.rotated(Vector3.UP, yaw)
		root.rotation.y = yaw
	# Thin traces do not need a second draw in the sun shadow pass.
	if str(item.get("kind", "")) == "sight" or str(item.get("kind", "")) == "material":
		for child in root.get_children():
			if child is MeshInstance3D:
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if root.has_meta("placed") and not root.has_meta("in_house") and place_id == "high_ground" and id not in ["cloud_shadow", "wind_line", "blue_edge", "deer"]:
		root.position.y += ground_height(_points, _points.get(place_id, Vector3.ZERO) + root.position)
	return root


# Opaque primitive parts become one vertex-coloured surface. Special materials
# are grouped separately; the root retains placement and animation metadata.
func _merge_item_parts(root: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var groups := {}
	for child in root.get_children():
		if not child is MeshInstance3D:
			continue
		var mat := child.material_override as StandardMaterial3D
		var special := mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.emission_enabled or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		var key := str(mat.get_instance_id()) if special else "opaque"
		if not groups.has(key):
			groups[key] = []
		groups[key].append(child)
	for key in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in groups[key]:
			var arrays: Array = part.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var normal_basis: Basis = part.transform.basis.inverse().transposed()
			var count: int = indices.size() if indices != null and indices.size() > 0 else vertices.size()
			for i in range(count):
				var index: int = indices[i] if indices != null and indices.size() > 0 else i
				# _mat has applied _tone exactly once, including the texture lift.
				st.set_color(part.material_override.albedo_color if key == "opaque" else Color.WHITE)
				st.set_normal((normal_basis * normals[index]).normalized())
				st.add_vertex(part.transform * vertices[index])
		var merged := MeshInstance3D.new()
		merged.name = "ItemSurface" if key == "opaque" else "ItemSpecial"
		merged.mesh = st.commit()
		if key == "opaque":
			var cache_key := "item_vertices|" + _style()
			if not _mat_cache.has(cache_key):
				var material := StandardMaterial3D.new()
				material.vertex_color_use_as_albedo = true
				material.roughness = 1.0
				if _style() == "textured":
					material.albedo_texture = _detail_texture()
					material.uv1_triplanar = true
					material.uv1_world_triplanar = true
					material.uv1_scale = Vector3.ONE * 0.7
				_mat_cache[cache_key] = material
			merged.material_override = _mat_cache[cache_key]
		else:
			merged.material_override = groups[key][0].material_override
		root.add_child(merged)
		for part in groups[key]:
			root.remove_child(part)
			part.free()


func _item_clear_parts(root: Node3D) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.free()


func _item_form(root: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	return _add(root, _sphere_mesh(1, 16, 8), color, at, Vector3.ZERO, size)


# Details are built in the original local frame, before baking the surfaces.
func _item_detail(root: Node3D, id: String) -> void:
	if id in ["bee", "clear_wings", "blue_needle"]:
		for k in range(1, 5):
			root.get_child(k).material_override = _mat(Color("c6e1df"), 0.65)
	var dark := Color("302d28")
	var bark := Color("795235")
	var cream := Color("d9cbb0")
	match id:
		"deer":
			_item_clear_parts(root)
			_item_form(root, Vector3(0, 1, 0), Vector3(0.25, 0.32, 0.56), Color("9d7955"))
			_item_form(root, Vector3(0, 1.35, 0.43), Vector3(0.16, 0.4, 0.19), Color("a5835c"))
			_item_form(root, Vector3(0, 1.72, 0.62), Vector3(0.13, 0.16, 0.22), Color("b49369"))
			_item_form(root, Vector3(0, 1.66, 0.82), Vector3(0.09, 0.08, 0.16), cream)
			_item_form(root, Vector3(0, 1.69, 0.96), Vector3(0.065, 0.04, 0.035), dark)
			_item_form(root, Vector3(0, 1.08, -0.56), Vector3(0.09, 0.08, 0.16), cream)
			for side in [-1, 1]:
				_item_form(root, Vector3(side * 0.2, 1.87, 0.57), Vector3(0.16, 0.065, 0.08), Color("aa8a61"))
				_item_form(root, Vector3(side * 0.21, 1.9, 0.59), Vector3(0.1, 0.025, 0.045), cream)
				_item_form(root, Vector3(side * 0.12, 1.77, 0.73), Vector3.ONE * 0.022, dark)
				for z in [-0.36, 0.36]:
					_item_segment(root, Vector3(side * 0.18, 0.95, z), Vector3(side * 0.2, 0.46, z - 0.06), 0.055, bark)
					_item_segment(root, Vector3(side * 0.2, 0.46, z - 0.06), Vector3(side * 0.21, 0.06, z + 0.04), 0.027, Color("b08c66"))
					_add(root, _box_mesh(Vector3(0.07, 0.09, 0.12)), dark, Vector3(side * 0.21, 0.045, z + 0.065))
				_item_segment(root, Vector3(side * 0.07, 1.83, 0.53), Vector3(side * 0.16, 2.1, 0.45), 0.022, cream)
				_item_segment(root, Vector3(side * 0.13, 2.02, 0.48), Vector3(side * 0.24, 2.09, 0.56), 0.015, cream)
		"heron":
			_item_clear_parts(root)
			_item_form(root, Vector3(0, 0.94, 0), Vector3(0.19, 0.22, 0.34), Color("929da6"))
			var neck := [Vector3(0, 1.02, 0.18), Vector3(0, 1.18, 0.05), Vector3(0, 1.4, 0.18), Vector3(0, 1.49, 0.32)]
			for i in range(3):
				_item_segment(root, neck[i], neck[i + 1], 0.048, Color("ced0c8"))
			_item_form(root, Vector3(0, 1.51, 0.33), Vector3(0.075, 0.075, 0.12), cream)
			_item_segment(root, Vector3(0, 1.54, 0.28), Vector3(0, 1.48, 0.08), 0.022, dark)
			_add(root, _cyl_mesh(0, 0.028, 0.3, 6), Color("ccaa50"), Vector3(0, 1.5, 0.55), Vector3(90, 0, 0))
			for side in [-1, 1]:
				_item_form(root, Vector3(side * 0.15, 0.97, -0.04), Vector3(0.05, 0.16, 0.28), Color("6f7e8c"))
				_item_form(root, Vector3(side * 0.065, 1.53, 0.38), Vector3.ONE * 0.012, dark)
				_item_segment(root, Vector3(side * 0.065, 0.85, 0), Vector3(side * 0.075, 0.04, 0.025), 0.014, Color("938557"))
				for toe in [-1, 0, 1]:
					_item_segment(root, Vector3(side * 0.075, 0.04, 0.025), Vector3(side * 0.075 + toe * 0.055, 0.025, 0.16), 0.009, Color("938557"))
		"wren", "woodpecker", "blue_flash", "two_notes", "wide_wings", "hanging_bird":
			for side in [-1, 1]:
				_item_form(root, Vector3(side * 0.13, 0.21, -0.025), Vector3(0.055, 0.115, 0.19), Color("166e98") if id == "blue_flash" else Color("4e4234"))
				_item_form(root, Vector3(side * 0.105, 0.385, 0.25), Vector3(0.038, 0.006, 0.035), cream)
				_item_form(root, Vector3(side * 0.113, 0.36, 0.265), Vector3.ONE * 0.018, dark)
				_item_segment(root, Vector3(side * 0.07, 0.12, 0.03), Vector3(side * 0.07, 0.015, 0.1), 0.012, bark)
				for toe in [-1, 0, 1]:
					_item_segment(root, Vector3(side * 0.07, 0.015, 0.1), Vector3(side * 0.07 + toe * 0.035, 0.012, 0.18), 0.008, bark)
				for k in range(4):
					_item_segment(root, Vector3(side * 0.16, 0.25 - k * 0.025, 0.02), Vector3(side * 0.17, 0.23 - k * 0.025, -0.13), 0.008, cream)
				if id in ["wide_wings", "hanging_bird"]:
					for k in range(5):
						_item_form(root, Vector3(side * (0.53 + k * 0.055), 0.22, -0.08 - k * 0.035), Vector3(0.1, 0.022, 0.16), dark)
			if id == "wren":
				_item_segment(root, Vector3(0, 0.19, -0.2), Vector3(0, 0.48, -0.4), 0.045, bark)
			if id == "woodpecker":
				_item_segment(root, Vector3(0, 0.1, -0.1), Vector3(0, -0.06, -0.3), 0.045, dark)
				_item_form(root, Vector3(0, 0.425, 0.18), Vector3(0.08, 0.025, 0.1), Color("c23832"))
		"squirrel", "hare":
			for side in [-1, 1]:
				_item_form(root, Vector3(side * 0.13, 0.055, 0.18), Vector3(0.065, 0.05, 0.14), Color("9c8d78"))
				_item_segment(root, Vector3(side * 0.12, 0.28, 0.11), Vector3(side * 0.09, 0.19, 0.26), 0.04, Color("8f806d"))
				_item_form(root, Vector3(side * 0.105, 0.53, 0.24 if id == "squirrel" else 0.33), Vector3.ONE * 0.022, dark)
				if id == "hare":
					_item_form(root, Vector3(side * 0.085, 0.8, 0.28), Vector3(0.026, 0.18, 0.018), Color("ba9b87"))
					_item_form(root, Vector3(side * 0.085, 0.97, 0.23), Vector3(0.045, 0.045, 0.055), dark)
			_item_form(root, Vector3(0, 0.29, 0.145), Vector3(0.11, 0.15, 0.04), cream)
			_item_form(root, Vector3(0, 0.48, 0.27 if id == "squirrel" else 0.4), Vector3(0.055, 0.045, 0.045), dark)
			if id == "squirrel":
				_item_form(root, Vector3(0, 0.72, -0.17), Vector3(0.18, 0.17, 0.14), Color("a49e91"))
				_item_form(root, Vector3(0, 0.69, -0.04), Vector3(0.11, 0.1, 0.13), Color("a49e91"))
			else:
				_item_form(root, Vector3(0, 0.22, -0.36), Vector3.ONE * 0.09, cream)
		"frog":
			_item_form(root, Vector3(0, 0.15, 0.17), Vector3(0.2, 0.07, 0.11), Color("7d9650"))
			_item_segment(root, Vector3(-0.16, 0.13, 0.24), Vector3(0.16, 0.13, 0.24), 0.008, dark)
			for side in [-1, 1]:
				_item_segment(root, Vector3(side * 0.13, 0.13, 0.13), Vector3(side * 0.23, 0.025, 0.27), 0.025, Color("6b8243"))
				_item_segment(root, Vector3(side * 0.27, 0.08, -0.2), Vector3(side * 0.32, 0.025, 0.03), 0.026, Color("779147"))
				for k in range(3):
					_item_segment(root, Vector3(side * 0.23, 0.025, 0.27), Vector3(side * (0.19 + k * 0.045), 0.018, 0.34), 0.009, cream)
		"duck":
			for side in [-1, 1]:
				_item_form(root, Vector3(side * 0.19, 0.23, -0.03), Vector3(0.08, 0.13, 0.28), bark)
				for k in range(6):
					_item_form(root, Vector3(side * 0.245, 0.2 + (k % 2) * 0.07, -0.2 + (k / 2) * 0.13), Vector3(0.012, 0.026, 0.05), cream)
			_item_form(root, Vector3(0, 0.25, -0.36), Vector3(0.16, 0.045, 0.19), bark)
			for at in [Vector3(-0.2, 0, -0.6), Vector3(0.1, 0, -0.95), Vector3(-0.1, 0, -1.3)]:
				_item_form(root, at + Vector3(0, 0.24, 0.1), Vector3(0.07, 0.07, 0.075), Color("dbc57c"))
				_add(root, _box_mesh(Vector3(0.08, 0.025, 0.09)), Color("b58a45"), at + Vector3(0, 0.23, 0.18))
				for side in [-1, 1]:
					_item_form(root, at + Vector3(side * 0.055, 0.26, 0.13), Vector3.ONE * 0.012, dark)
		"spider", "ant":
			_item_clear_parts(root)
			for n in range(3 if id == "ant" else 1):
				var at := Vector3(n * 0.19, 0, -n * 0.48)
				_item_form(root, at + Vector3(0, 0.07, -0.1), Vector3(0.055, 0.05, 0.09) if id == "ant" else Vector3(0.095, 0.075, 0.13), dark)
				_item_form(root, at + Vector3(0, 0.07, 0.09), Vector3(0.055, 0.05, 0.07), bark)
				if id == "ant":
					_item_form(root, at + Vector3(0, 0.07, 0), Vector3(0.035, 0.035, 0.04), dark)
				for side in [-1, 1]:
					for k in range(3 if id == "ant" else 4):
						var z := -0.12 + k * 0.075
						var knee := at + Vector3(side * 0.16, 0.14, z)
						_item_segment(root, at + Vector3(side * 0.04, 0.07, 0.04), knee, 0.009, dark)
						_item_segment(root, knee, at + Vector3(side * 0.25, 0.01, z * 1.7), 0.007, dark)
					_item_segment(root, at + Vector3(side * 0.025, 0.09, 0.13), at + Vector3(side * 0.065, 0.13, 0.2), 0.006, dark)
		"bat":
			_item_clear_parts(root)
			_item_form(root, Vector3.ZERO, Vector3(0.09, 0.08, 0.2), Color("493a3d"))
			_item_form(root, Vector3(0, 0.025, 0.17), Vector3(0.085, 0.075, 0.075), Color("554047"))
			for side in [-1, 1]:
				for k in range(4):
					var x: float = side * (0.13 + k * 0.13)
					_item_form(root, Vector3(x, -0.005, -0.02 - k * 0.025), Vector3(0.15, 0.012, 0.17 - k * 0.025), Color("68505e"))
				for tip in [Vector3(side * 0.67, 0, 0.05), Vector3(side * 0.48, 0, -0.23), Vector3(side * 0.27, 0, -0.25)]:
					_item_segment(root, Vector3(side * 0.09, 0.02, 0.13), tip, 0.009, Color("b3989f"))
				_add(root, _cyl_mesh(0, 0.04, 0.15, 6), Color("68505e"), Vector3(side * 0.055, 0.12, 0.17))
				_item_form(root, Vector3(side * 0.045, 0.06, 0.225), Vector3.ONE * 0.013, dark)

		"bee", "moth", "blue_needle", "clear_wings":
			_item_form(root, Vector3(0, 0.025, 0.18 if id in ["bee", "moth"] else 0.31), Vector3(0.035, 0.03, 0.04), dark)
			for side in [-1, 1]:
				_item_segment(root, Vector3(side * 0.025, 0.03, 0.18), Vector3(side * 0.075, 0.07, 0.29), 0.007, dark)
				for k in range(3):
					_item_segment(root, Vector3(side * 0.025, -0.02, -0.04 + k * 0.05), Vector3(side * 0.11, -0.07, k * 0.06), 0.007, dark)
				if id == "moth":
					for z in [-0.1, 0.1]:
						_item_form(root, Vector3(side * 0.21, 0.025, z), Vector3(0.055, 0.009, 0.047), bark)
						_item_form(root, Vector3(side * 0.21, 0.033, z), Vector3(0.025, 0.008, 0.025), cream)
			if id in ["blue_needle", "clear_wings"]:
				for k in range(7):
					_item_ring(root, Vector3(0, 0, -0.25 + k * 0.07), 0.025, 0.004, dark, Vector3(90, 0, 0))
		"snail":
			root.get_child(2).free()
			for side in [-1, 1]:
				_item_form(root, Vector3(side * 0.06, 0.24, 0.3), Vector3.ONE * 0.022, dark)
				for k in range(22):
					var a := k * 0.42
					var b := (k + 1) * 0.42
					var r := 0.012 + k * 0.006
					_item_segment(root, Vector3(side * sqrt(maxf(0.001, 0.18 * 0.18 - r * r)), 0.22 + sin(a) * r, -0.08 + cos(a) * r), Vector3(side * sqrt(maxf(0.001, 0.18 * 0.18 - (r + 0.006) * (r + 0.006))), 0.22 + sin(b) * (r + 0.006), -0.08 + cos(b) * (r + 0.006)), 0.009, bark)
		"moon":
			_item_clear_parts(root)
			var disc := _item_form(root, Vector3.ZERO, Vector3(1.5, 1.5, 0.16), cream)
			disc.material_override = _mat(Color("e2dfbd"), 1, false, 0.35)
			for crater in [Vector3(-0.5, 0.5, 0.36), Vector3(0.3, 0.7, 0.25), Vector3(-0.65, -0.3, 0.24), Vector3(0.25, -0.25, 0.42), Vector3(0.65, 0.25, 0.18)]:
				_item_form(root, Vector3(crater.x, crater.y, 0.15), Vector3(crater.z, crater.z * 0.8, 0.025), Color("999e8d"))
				_item_form(root, Vector3(crater.x + crater.z * 0.45, crater.y - crater.z * 0.25, 0.158), Vector3(crater.z * 0.65, crater.z * 0.6, 0.018), Color("a8ab98"))
			for at in [Vector3(0.85, -0.55, 0.12), Vector3(-0.9, 0.1, 0.08), Vector3(0.15, -1.05, 0.1)]:
				_item_ring(root, Vector3(at.x, at.y, 0.14), at.z, 0.012, cream, Vector3(90, 0, 0))

		"iron_box_smell":
			# A shallow soot-black firebox insert fits the existing stove front.
			for side in [-1, 1]:
				_add(root, _box_mesh(Vector3(0.035, 0.38, 0.09)), Color("545354"), Vector3(side * 0.22, 0, 0.03))
			for y in [-0.19, 0.19]:
				_add(root, _box_mesh(Vector3(0.47, 0.035, 0.09)), Color("545354"), Vector3(0, y, 0.03))
			for k in range(5):
				_item_segment(root, Vector3(-0.16 + k * 0.08, -0.13, 0.03), Vector3(-0.16 + k * 0.08, -0.13, 0.09), 0.009, cream)
				_item_form(root, Vector3(-0.13 + k * 0.06, -0.15, 0.055), Vector3(0.035, 0.018, 0.025), Color("77736c"))
			_item_segment(root, Vector3(-0.13, -0.09, 0.045), Vector3(0.1, -0.04, 0.055), 0.023, dark)
			_item_ring(root, Vector3(0.18, 0, 0.09), 0.025, 0.007, cream, Vector3(90, 0, 0))
		"roof_tick":
			for side in [-1, 1]:
				_item_segment(root, Vector3(side * 0.24, 0, 0), Vector3(0, 0.16, 0), 0.028, bark)
				_item_form(root, Vector3(side * 0.16, -0.025, 0.055), Vector3(0.018, 0.012, 0.018), dark)
			for k in range(4):
				_item_segment(root, Vector3(-0.23, 0.025, -0.05 + k * 0.03), Vector3(0.2, 0.025, -0.04 + k * 0.03), 0.003, Color("b58a5b"))
		"log", "green_log", "log_ear", "sticky_wood", "wood_tunnels", "smooth_wood":
			var length := 2.4 if id == "log" else (1.5 if id == "green_log" else 0.9)
			var radius := 0.26 if id == "log" else (0.25 if id == "green_log" else 0.2)
			if id == "smooth_wood":
				radius = 0.08
			for side in [-1, 1]:
				_add(root, _cyl_mesh(radius * 0.87, radius * 0.87, 0.012, 12), cream, Vector3(side * (length / 2 + 0.008), radius, 0), Vector3(0, 0, 90))
				for k in range(3):
					_item_ring(root, Vector3(side * (length / 2 + 0.016), radius, 0), radius * (0.23 + k * 0.23), 0.005, bark, Vector3(0, 0, 90))
			for k in range(7):
				var a := k * PI / 6
				_item_segment(root, Vector3(-length * 0.45, radius + sin(a) * radius, cos(a) * radius), Vector3(length * 0.45, radius + sin(a) * radius, cos(a) * radius), 0.008, Color("a18a65") if id == "smooth_wood" else dark)
			if id == "green_log":
				for k in range(10):
					_item_form(root, Vector3(-0.6 + k * 0.13, 0.46, sin(k * 2) * 0.13), Vector3(0.1, 0.045, 0.09), Color("78914d"))
			if id == "log_ear":
				for k in range(5):
					_item_segment(root, Vector3(0, 0.34, 0.21), Vector3(-0.16 + k * 0.08, 0.32, 0.34), 0.005, bark)
			if id == "sticky_wood":
				_item_form(root, Vector3(0.1, 0.22, 0.19), Vector3(0.04, 0.1, 0.025), Color("c58c27"))
			if id == "wood_tunnels":
				for x in [-0.25, 0, 0.23]:
					_item_ring(root, Vector3(x, 0.3, 0.155), 0.035, 0.008, cream, Vector3(90, 0, 0))
		"stick", "reaching_root", "root_door":
			for k in range(3):
				var at := Vector3(k * 0.14, 0.08, 0.12)
				if id == "reaching_root":
					at = Vector3(0.45 + k * 0.1, 0.36 - k * 0.08, 0.4)
				elif id == "root_door":
					at = Vector3(-0.2 + k * 0.2, 0.22, -0.2)
				_item_segment(root, at, at + Vector3(0.12, 0.02, 0.2), 0.018, bark)
				_item_segment(root, at + Vector3(0.08, 0.015, 0.13), at + Vector3(0.2, 0.01, 0.14), 0.009, bark)
				_item_form(root, at + Vector3(0.12, 0.02, 0.2), Vector3.ONE * 0.016, cream)
		"stone", "flint", "earth", "clay", "sand":
			if id == "earth":
				_item_form(root, Vector3(0, 0.016, 0.38), Vector3(0.23, 0.012, 0.19), Color("332d22"))
			for k in range(9):
				var a := k * 2.4
				var at := Vector3(cos(a) * 0.32, 0.22, sin(a) * 0.22)
				match id:
					"stone":
						_item_form(root, at, Vector3(0.07, 0.035, 0.06), Color("858b81").lerp(cream, k / 12.0))
					"flint":
						_item_form(root, at, Vector3(0.075, 0.018, 0.055), Color("c6c2af"))
					"earth":
						_item_form(root, at, Vector3(0.09, 0.06, 0.075), Color("4e3c2c"))
					"clay":
						_item_form(root, Vector3(0.85 + (k / 3) * 0.25, 0.19, (k / 3) * 0.2 + (k % 3) * 0.045), Vector3(0.06, 0.008, 0.012), Color("626a70"))
					"sand":
						_item_segment(root, Vector3(-0.27, 0.12, -0.3 + k * 0.075), Vector3(0.26, 0.12, -0.27 + k * 0.075), 0.009, Color("b9a16b"))
		"reed", "grass", "seed":
			for k in range(7):
				var x := -0.02 + k * 0.045
				_item_segment(root, Vector3(x, 0.1, -0.45), Vector3(x + 0.05, 0.12, 0.43), 0.012, Color("b3aa6c"))
				if id != "grass":
					_item_form(root, Vector3(x + 0.05, 0.12, 0.4), Vector3(0.025, 0.025, 0.1), bark if id == "reed" else Color("c4ac65"))
				else:
					_item_segment(root, Vector3(x, 0.1, 0), Vector3(x + 0.13, 0.14, 0.55), 0.015, Color("8d9d52"))
			if id != "seed":
				_item_ring(root, Vector3(0.12, 0.09, -0.13), 0.13, 0.012, bark, Vector3(90, 0, 0))
		"nettle", "clean_smell":
			_item_clear_parts(root)
			_item_segment(root, Vector3.ZERO, Vector3(0, 0.65, 0), 0.016, Color("547138"))
			for level in range(4):
				for side in [-1, 1]:
					var y := 0.15 + level * 0.13
					var leaf := Vector3(side * 0.13, y, 0)
					_item_form(root, leaf, Vector3(0.14, 0.018, 0.065), Color("376e35") if id == "nettle" else Color("719c66"))
					_item_segment(root, Vector3(0, y, 0), Vector3(side * 0.25, y + 0.01, 0), 0.005, cream)
					if id == "nettle":
						for tooth in range(4):
							_add(root, _prism_mesh(Vector3(0.05, 0.018, 0.15)), Color("376e35"), leaf + Vector3(side * (-0.07 + tooth * 0.045), 0, 0))
		"water", "bubble_holes", "water_walkers":
			for k in range(6):
				var at := Vector3(cos(k * TAU / 6) * 0.6, 0.02, sin(k * TAU / 6) * 0.47)
				if id == "water":
					_item_form(root, at, Vector3(0.11, 0.06, 0.08), Color("898f83"))
				elif id == "water_walkers":
					_item_ring(root, Vector3(-0.3 if k < 3 else 0.3, 0.002, (k % 3 - 1) * 0.2), 0.045, 0.003, Color("a5c5cc"))
				else:
					_item_ring(root, Vector3(-0.2 + (k % 3) * 0.2, 0.008, 0), 0.045 + (k / 3) * 0.022, 0.003, cream)
			if id == "water":
				_item_ring(root, Vector3(0, 0.035, 0), 0.43, 0.008, Color("c4dde0"))
		"floor_creak", "sun_square", "door_draught":
			for k in range(4):
				var x := -0.08 + k * 0.05
				if id == "floor_creak":
					_item_segment(root, Vector3(x, 0.022, -0.36), Vector3(x + 0.01, 0.025, 0.36), 0.003, bark)
					_item_form(root, Vector3(x, 0.025, 0.32), Vector3.ONE * 0.006, dark)
				elif id == "door_draught":
					_item_form(root, Vector3(-0.2 + k * 0.13, 0.009, -0.07 - k * 0.025), Vector3(0.045, 0.006, 0.012), cream)
				else:
					_item_segment(root, Vector3(-0.3, 0.004, -0.3 + k * 0.2), Vector3(0.3, 0.004, -0.3 + k * 0.2), 0.002, Color("e6ce8d"))
			if id == "sun_square":
				_add(root, _box_mesh(Vector3(0.025, 0.003, 0.72)), Color("ae9c70"), Vector3(0, 0.005, 0))
		"ceiling_stain":
			for k in range(5):
				_item_form(root, Vector3(-0.12 + k * 0.06, -0.003, 0.27 + sin(k) * 0.035), Vector3(0.025, 0.009, 0.05), Color("826047"))
		"grey_feather", "hand_leaves":
			for k in range(9):
				var z := -0.18 + k * 0.04
				for side in [-1, 1]:
					_item_segment(root, Vector3(0, 0.015, z), Vector3(side * (0.055 if id == "grey_feather" else 0.16), 0.015, z + 0.05), 0.003, cream if id == "grey_feather" else bark)
		"morning_wet":
			for at in [Vector3(-0.4, 0, 0), Vector3(0, 0, 0.3), Vector3(0.3, 0, -0.2), Vector3(0.6, 0, 0.2)]:
				_item_form(root, at + Vector3(0, 0.035, 0), Vector3(0.1, 0.012, 0.045), Color("658349"))
				_item_form(root, at + Vector3(-0.012, 0.083, 0.018), Vector3.ONE * 0.009, Color("f0f4df"))
		"night_tracks", "small_hands", "three_toes":
			_item_clear_parts(root)
			for k in range(6):
				var at := Vector3((k % 2) * 0.2, 0.012, k * 0.16)
				var turn := -1.0 if id == "three_toes" and k > 2 else 1.0
				_item_form(root, at, Vector3(0.045, 0.007, 0.05), Color("514b3e"))
				for toe in range(5 if id == "small_hands" else 3):
					var x := (toe - (2 if id == "small_hands" else 1)) * 0.032
					_item_segment(root, at, at + Vector3(x, 0, turn * (0.1 - absf(x) * 0.4)), 0.008, Color("514b3e"))
		"bead_net":
			for k in range(4):
				_item_ring(root, Vector3.ZERO, 0.06 + k * 0.05, 0.003, Color("b7c7c3"), Vector3(90, 0, 0))
			for k in range(12):
				var tip := Vector3(cos(k * TAU / 12), sin(k * TAU / 12), 0) * 0.29
				_item_segment(root, Vector3.ZERO, tip, 0.003, cream)
				_item_form(root, tip * 0.7, Vector3.ONE * 0.009, Color("e3eeec"))
		"roll_ups":
			for n in range(3):
				for k in range(5):
					_item_ring(root, Vector3(n * 0.16, 0.075, -0.065 + k * 0.03), 0.064 - absf(k - 2) * 0.008, 0.004, dark, Vector3(90, 0, 0))
		"tail_basker":
			_item_clear_parts(root)
			_item_form(root, Vector3(0, 0.09, 0), Vector3(0.085, 0.055, 0.22), Color("78815a"))
			_item_form(root, Vector3(0, 0.1, 0.23), Vector3(0.065, 0.045, 0.1), Color("8c9469"))
			for side in [-1, 1]:
				_item_form(root, Vector3(side * 0.05, 0.126, 0.26), Vector3.ONE * 0.012, dark)
				for z in [-0.12, 0.12]:
					_item_segment(root, Vector3(side * 0.065, 0.09, z), Vector3(side * 0.16, 0.04, z - 0.06), 0.018, Color("78815a"))
					_item_segment(root, Vector3(side * 0.16, 0.04, z - 0.06), Vector3(side * 0.19, 0.018, z + 0.035), 0.012, Color("78815a"))
					for toe in range(3):
						_item_segment(root, Vector3(side * 0.19, 0.018, z + 0.035), Vector3(side * (0.18 + toe * 0.025), 0.012, z + 0.09), 0.004, cream)
			for k in range(8):
				_item_segment(root, Vector3(sin(k * 0.3) * 0.12, 0.06 - k * 0.005, -0.18 - k * 0.06), Vector3(sin((k + 1) * 0.3) * 0.12, 0.055 - k * 0.005, -0.24 - k * 0.06), 0.033 - k * 0.0038, Color("78815a"))
			_item_segment(root, Vector3(0, 0.146, -0.17), Vector3(0, 0.146, 0.18), 0.006, cream)
		"upside_shiny", "green_jumper":
			var y := 0.22 if id == "upside_shiny" else 0.15
			_item_form(root, Vector3(0, y, 0.22), Vector3(0.065, 0.05, 0.075), dark if id == "upside_shiny" else Color("6c8544"))
			for side in [-1, 1]:
				_item_form(root, Vector3(side * 0.05, y + 0.025, 0.25), Vector3.ONE * 0.013, dark)
				for k in range(3 if id != "tail_basker" else 2):
					var z := -0.13 + k * 0.13
					_item_segment(root, Vector3(side * 0.08, y, z), Vector3(side * 0.19, y + 0.05, z - 0.06), 0.012, bark)
					_item_segment(root, Vector3(side * 0.19, y + 0.05, z - 0.06), Vector3(side * 0.22, 0.02 if id != "upside_shiny" else 0.32, z + 0.07), 0.009, bark)
		"pink_wriggler", "pouring_thing":
			_item_clear_parts(root)
			for k in range(22):
				var a := Vector3(k * 0.035, 0.045, sin(k * 0.3) * 0.09)
				var b := Vector3((k + 1) * 0.035, 0.045, sin((k + 1) * 0.3) * 0.09)
				_item_segment(root, a, b, 0.027 if id == "pink_wriggler" else 0.04, Color("c28b83") if id == "pink_wriggler" else Color("6f7652"))
				if k % 2 == 0:
					_item_ring(root, a, 0.028 if id == "pink_wriggler" else 0.041, 0.003, Color("9a7068") if id == "pink_wriggler" else Color("4e553e"), Vector3(0, 0, 90))
			if id == "pouring_thing":
				_item_form(root, Vector3(0.8, 0.05, 0.025), Vector3(0.08, 0.04, 0.05), Color("78815a"))
				_item_form(root, Vector3(0.82, 0.075, 0.065), Vector3.ONE * 0.009, dark)
		"stick_bundle", "grass_ball", "stem_cup":
			var centre := Vector3(0, 0.9, 0) if id != "stick_bundle" else Vector3.ZERO
			for k in range(12):
				var a := k * TAU / 12
				var b := a + 1.5
				_item_segment(root, centre + Vector3(cos(a) * 0.23, sin(k * 2) * 0.08, sin(a) * 0.23), centre + Vector3(cos(b) * 0.23, sin(k * 2 + 1) * 0.08, sin(b) * 0.23), 0.009, cream if k % 2 == 0 else bark)
		"red_round":
			_item_form(root, Vector3(0.09, 0.27, 0), Vector3(0.1, 0.015, 0.04), Color("658443"))
			_item_form(root, Vector3(-0.04, 0.07, 0.14), Vector3(0.025, 0.055, 0.012), Color("df7960"))
			_item_form(root, Vector3(0, -0.17, 0), Vector3(0.025, 0.009, 0.025), dark)
		"sleeping_yellow":
			for k in range(7):
				var a := k * TAU / 7
				_item_segment(root, Vector3(cos(a) * 0.18, 0.17 + sin(a) * 0.13, -0.4), Vector3(cos(a) * 0.18, 0.17 + sin(a) * 0.13, 0.4), 0.009, Color("b19436"))
			_item_segment(root, Vector3(-0.3, 0.46, -0.3), Vector3(0.3, 0.46, -0.3), 0.008, cream)
		"petal_wings":
			for n in range(2):
				var at := Vector3(n * 0.55, n * 0.2, n * 0.15)
				for side in [-1, 1]:
					_item_form(root, at + Vector3(side * 0.17, 0.065, 0.06), Vector3(0.022, 0.008, 0.025), dark)
					_item_segment(root, at + Vector3(0, 0.02, 0.12), at + Vector3(side * 0.05, 0.07, 0.23), 0.004, dark)
		"hook_seeds":
			for n in range(3):
				for k in range(8):
					var tip := Vector3(cos(k * TAU / 8) * 0.09, 0.045, sin(k * TAU / 8) * 0.09)
					var at := Vector3(-0.2 + n * 0.2, 0, 0)
					_item_segment(root, at + tip * 0.6, at + tip, 0.004, bark)
					_item_segment(root, at + tip, at + tip + Vector3(0.015, 0.015, -0.01), 0.003, bark)
		"froth_sitter":
			for k in range(14):
				_item_form(root, Vector3(cos(k * 2.4) * 0.08, 0.4 + k * 0.014, 0.08 + sin(k * 2.4) * 0.04), Vector3.ONE * 0.035, Color("f0efe0"))
		"quick_shadows":
			for at in [Vector3(-0.4, 0, 0), Vector3(0, 0, 0.2), Vector3(0.3, 0, -0.15)]:
				for side in [-1, 1]:
					_item_form(root, at + Vector3(side * 0.055, 0, -0.29), Vector3(0.06, 0.012, 0.075), Color("385660"))
				_item_form(root, at + Vector3(0.055, 0.018, 0.17), Vector3.ONE * 0.012, dark)
		"curled_stone":
			root.get_child(2).free()
			root.get_child(1).free()
			for k in range(24):
				var a := k * 0.4
				var b := a + 0.4
				var r := 0.01 + k * 0.006
				_item_segment(root, Vector3(cos(a) * r, 0.26, sin(a) * r), Vector3(cos(b) * (r + 0.006), 0.26, sin(b) * (r + 0.006)), 0.006, bark)
		"ringed_stone", "spark_stone", "stone_coats":
			for k in range(9):
				var at := Vector3(cos(k * 2.4) * 0.2, 0.25, sin(k * 2.4) * 0.13)
				if id == "spark_stone":
					_add(root, _cyl_mesh(0, 0.025, 0.09, 5), cream, at)
				elif id == "stone_coats":
					_item_form(root, at, Vector3(0.055, 0.012, 0.04), Color("ca9650") if k % 2 else Color("c1c4ac"))
				else:
					_item_form(root, at * 0.65, Vector3(0.018, 0.006, 0.016), Color("737b7c"))
		"cupped_shiner":
			_item_clear_parts(root)
			# A mussel half: dark tapered exterior and a pearly concave interior.
			_item_form(root, Vector3(0, 0.038, 0), Vector3(0.23, 0.038, 0.145), Color("404a48"))
			_item_form(root, Vector3(0, 0.062, 0), Vector3(0.205, 0.018, 0.125), Color("afbfc0"))
			for k in range(12):
				var a := k * TAU / 12
				var edge := Vector3(cos(a) * 0.22, 0.085, sin(a) * 0.14)
				_item_segment(root, Vector3(-0.17, 0.015, 0), edge, 0.026, Color("404a48"))
				_item_segment(root, Vector3(-0.16, 0.036, 0), edge + Vector3(0, 0.002, 0), 0.005, Color("afbfc0").lerp(Color("d6c5cf"), (k % 3) * 0.3))
				var b := (k + 1) * TAU / 12
				_item_segment(root, edge, Vector3(cos(b) * 0.22, 0.085, sin(b) * 0.14), 0.012, dark)

		"dotted_wobble":
			for k in range(12):
				var at := Vector3(cos(k * 2.4) * 0.23, 0.13, sin(k * 2.4) * 0.17)
				_item_ring(root, at, 0.035, 0.005, Color("b8d4c7"))
				_item_form(root, at, Vector3.ONE * 0.016, dark)
		"pale_ring":
			for at in [Vector3(-0.35, 0.25, 0), Vector3(0, 0.25, 0.35), Vector3(0.35, 0.25, 0), Vector3(0, 0.25, -0.35)]:
				_item_ring(root, at - Vector3(0, 0.045, 0), 0.13, 0.008, Color("b6a98c"))
				for k in range(4):
					_item_segment(root, at, at + Vector3(cos(k * PI / 2) * 0.12, -0.04, sin(k * PI / 2) * 0.12), 0.004, bark)
		"tree_knock", "trunk_hole", "bank_holes", "bank_stripes", "post_coat":
			if id == "bank_holes":
				_add(root, _box_mesh(Vector3(1.2, 0.38, 0.055)), Color("9b9788"), Vector3(0, 0, -0.05))
			elif id == "post_coat":
				_add(root, _box_mesh(Vector3(0.16, 0.9, 0.035)), bark, Vector3(0, 0, -0.035))
			for k in range(9):
				var x := -0.12 + (k % 3) * 0.12
				var y := -0.15 + (k / 3) * 0.12
				if id == "post_coat":
					_item_form(root, Vector3(x * 0.4, y * 1.7, 0.023), Vector3(0.035, 0.055, 0.012), Color("6e874b"))
				elif id == "bank_holes":
					_item_ring(root, Vector3(-0.4 + (k % 3) * 0.4, 0, -0.005), 0.12 + (k / 3) * 0.01, 0.008, Color("979284"), Vector3(90, 0, 0))
				elif id == "bank_stripes":
					_item_form(root, Vector3(x * 3, y + 0.16, 0.065), Vector3(0.045, 0.018, 0.012), Color("b0a18a"))
				else:
					_item_segment(root, Vector3(x * 0.7, y, -0.02), Vector3(x * 0.7 + 0.012, y + 0.06, -0.015), 0.008, bark)
		"deep_breath", "wind_line":
			for k in range(9):
				var x := -0.35 + k * 0.09
				_item_segment(root, Vector3(x, 0, 0.08), Vector3(x - 0.34, 0.36, 0.08), 0.012, Color("728744"))
				_item_form(root, Vector3(x - 0.34, 0.41, 0.08), Vector3(0.025, 0.08, 0.025), bark if id == "deep_breath" else Color("ada46d"))
		"two_dents", "far_shut":
			for side in [-1, 1]:
				for k in range(5):
					_item_form(root, Vector3(side * 0.45, 0.012, -0.8 + k * 0.4), Vector3(0.08, 0.012, 0.14), Color("9e8a68"))
		"far_smoke":
			for k in range(7):
				_item_form(root, Vector3(sin(k) * 0.06, k * 0.24, 0), Vector3(0.1 + k * 0.015, 0.2, 0.12), Color("bac0bc"))
		"cloud_shadow":
			for k in range(5):
				_item_form(root, Vector3(-0.9 + k * 0.45, 0, sin(k) * 0.6), Vector3(0.65, 0.004, 0.5), Color("4b6141"))
		"blue_edge":
			for k in range(4):
				_add(root, _prism_mesh(Vector3(0.8, 0.6 + (k % 2) * 0.3, 0.6)), Color("829aaa"), Vector3(-1 + k * 0.6, 0.25, 0.4))
		"first_light":
			for k in range(4):
				var ray := _item_form(root, Vector3.ZERO, Vector3(0.012, 0.18, 0.012), cream)
				ray.rotation_degrees.z = k * 45
				ray.material_override = _mat(Color("fff1c7"), 1, false, 1.5)
		"hanging_colours":
			for k in range(12):
				_item_form(root, Vector3(sin(k * 2.4) * 0.25, 0.05 + k * 0.015, 0.32), Vector3.ONE * 0.018, Color("c6e2e4"))


# Spread gathered materials and small ground life outside existing prop bounds.
func _item_clear_ground(id: String, place_id: String) -> Vector3:
	var place := place_node(place_id)
	var point: Vector3 = _points.get(place_id, Vector3.ZERO)
	var angle := float(posmod(hash(id), 628)) * 0.01
	var radius := 3.8 if place_id != "dark_trees" else 6.5
	var centre := Vector3.ZERO
	if place_id == "sandy_bend":
		centre = _outward(point) * 1.5
		radius = 2.0
	for k in range(96):
		var at := Vector3(cos(angle + k * 0.55), 0, sin(angle + k * 0.55)) * (radius + float(k / 24) * (0.15 if place_id == "sandy_bend" else 0.6)) + centre
		at.y = ground_height(_points, point + at)
		var clear := true
		if place != null:
			for child in place.find_children("*", "MeshInstance3D", true, false):
				var bounds: AABB = (place.global_transform.affine_inverse() * child.global_transform) * child.get_aabb()
				if bounds.size.y < 0.15 and bounds.size.x > 2.0:
					continue
				var expanded := bounds.grow(0.7)
				for step in range(5):
					if expanded.has_point(at + Vector3(0.45, 0.6, 0.7) * step):
						clear = false
				if expanded.has_point(at + Vector3(0, 0.1, 0)):
					clear = false
		if clear and _grass != null:
			for tuft in range(_grass.multimesh.instance_count):
				var grass_at := _grass.multimesh.get_instance_transform(tuft).origin
				var distance := Vector2(grass_at.x - point.x - at.x, grass_at.z - point.z - at.z).length()
				if distance < 0.5:
					clear = false
					break
		if clear:
			return at
	return centre + Vector3(cos(angle) * radius, ground_height(_points, point + centre), sin(angle) * radius)


# Primitive strokes shared by roots, legs, stems and traces.
func _item_segment(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var delta := b - a
	var mesh := _add(root, _cyl_mesh(radius, radius, delta.length(), 6), color, (a + b) * 0.5)
	mesh.quaternion = Quaternion(Vector3.UP, delta.normalized())


func _item_ring(root: Node3D, at: Vector3, radius: float, thickness: float, color: Color, rotation := Vector3.ZERO) -> void:
	var key := "ring:%s:%s" % [radius, thickness]
	if not _mesh_cache.has(key):
		var ring := TorusMesh.new()
		ring.inner_radius = radius - thickness
		ring.outer_radius = radius + thickness
		ring.rings = 16
		ring.ring_segments = 6
		_mesh_cache[key] = ring
	_add(root, _mesh_cache[key], color, at, rotation)


# --- prototype: looks --------------------------------------------------------

func set_style(style: String) -> void:
	_style_override = style if STYLES.has(style) else "flat"
	if not _built:
		return
	_apply_style()
	if _have_snapshot:
		_signature = _place_signature()
		_rebuild_places()
		_update_card(0.0)
	_update_sky()


func _style() -> String:
	var style := _style_override if _style_override != "" else str(_snapshot.get("prototype_style", "flat"))
	return style if STYLES.has(style) else "flat"


# Muted: less saturation, a touch darker, pulled toward a warm grey-brown.
func _tone(color: Color) -> Color:
	if _style() == "flat":
		return color
	var muted := Color.from_hsv(color.h, color.s * 0.7, color.v * 0.95, color.a)
	return muted.lerp(Color(0.52, 0.48, 0.40, color.a), 0.15)


# The light, sky and shared materials for the current look.
func _apply_style() -> void:
	var style := _style()
	_style_applied = style
	var rich := style != "flat"
	_sun.shadow_enabled = rich
	if rich:
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_sun.directional_shadow_max_distance = 110.0
		if _sky_mat == null:
			_sky_mat = ProceduralSkyMaterial.new()
			var sky := Sky.new()
			sky.sky_material = _sky_mat
			_env.sky = sky
		_env.background_mode = Environment.BG_SKY
	else:
		_env.background_mode = Environment.BG_COLOR
	_ground_plane.material_override = _mat(Color(0.60, 0.65, 0.62))
	var textured := style == "textured"
	_land_mat.albedo_texture = _grass_texture() if textured else null
	_land_mat.uv1_triplanar = textured
	_land_mat.uv1_world_triplanar = textured
	_land_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)


# A seamless noise picture between two colours, made once in code (no files).
func _noise_texture(key: String, seed_value: int, frequency: float, dark: Color, light: Color) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var grey := noise.get_seamless_image(256, 256)
	var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in range(256):
		for x in range(256):
			image.set_pixel(x, y, dark.lerp(light, grey.get_pixel(x, y).r))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_tex_cache[key] = texture
	return texture


# Grey speckle that roughens every lit surface in the "textured" look.
func _detail_texture() -> Texture2D:
	return _noise_texture("detail", 7, 0.06, Color(0.72, 0.72, 0.72), Color(1.0, 1.0, 1.0))


# Patchy grass for the land in the "textured" look: dry and lush greens.
func _grass_texture() -> Texture2D:
	return _noise_texture("grass", 11, 0.02, _tone(Color(0.33, 0.47, 0.24)), _tone(Color(0.52, 0.62, 0.34)))


# Tufts of grass over found land (not on paths, the yard, the house or the
# water): one multimesh, one draw.
func _build_grass() -> void:
	if _grass != null:
		_grass.queue_free()
		_grass = null
	if _style() == "flat":
		return
	var segments: Array = []
	for path_variant in ([] if _free_on() else _arr(_snapshot.get("paths", []))):
		var path: Array = path_variant
		if _points.has(str(path[0])) and _points.has(str(path[1])):
			segments.append([_points[str(path[0])], _points[str(path[1])]])
	var keep_out := []
	for row in [["home", 3.4], ["yard", 3.6], ["wood_heap", 2.0], ["gate", 1.0]]:
		if _points.has(row[0]):
			keep_out.append([_points[row[0]], float(row[1])])
	if _points.has("water"):
		var water: Vector3 = _points["water"]
		keep_out.append([water + _outward(water) * 4.8, 5.4])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("grass")
	var placed: Array = []
	for i in range(GRASS_TUFTS):
		var p := Vector3(rng.randf_range(-40.0, 40.0), 0.0, rng.randf_range(-40.0, 40.0))
		var yaw := rng.randf() * TAU
		var size := rng.randf_range(0.7, 1.4)
		var shade := rng.randf()
		if p.length() > 40.0 or mist_state(p, _all_points, _known, segments) != "clear":
			continue
		var blocked := false
		for row in keep_out:
			var centre: Vector3 = row[0]
			if Vector2(p.x - centre.x, p.z - centre.z).length() < float(row[1]):
				blocked = true
				break
		if not blocked:
			for segment in segments:
				var a: Vector3 = segment[0]
				var b: Vector3 = segment[1]
				var closest := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
				if Vector2(p.x, p.z).distance_to(closest) < 1.1:
					blocked = true
					break
		if not blocked:
			placed.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size),
				Vector3(p.x, ground_height(_points, p), p.z)), _tone(GRASS * (0.85 + 0.35 * shade))])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _tuft_mesh()
	multimesh.instance_count = placed.size()
	for i in range(placed.size()):
		multimesh.set_instance_transform(i, placed[i][0])
		multimesh.set_instance_color(i, placed[i][1])
	_grass = MultiMeshInstance3D.new()
	_grass.name = "Grass"
	_grass.multimesh = multimesh
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	_grass.material_override = mat
	_world.add_child(_grass)


# Five thin blades leaning out, darker at the root (the instance colour tints it).
func _tuft_mesh() -> Mesh:
	if _mesh_cache.has("tuft"):
		return _mesh_cache["tuft"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(5):
		var angle := TAU * float(k) / 5.0
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x) * 0.06
		var root_at := out * 0.05
		var tip := out * 0.18 + Vector3(0.0, 0.34 + 0.1 * float(k % 2), 0.0)
		for vertex in [[root_at - side, 0.8], [root_at + side, 0.8], [tip, 1.1]]:
			st.set_color(Color(vertex[1], vertex[1], vertex[1]))
			st.set_normal(Vector3.UP)
			st.add_vertex(vertex[0])
	var mesh := st.commit()
	_mesh_cache["tuft"] = mesh
	return mesh


# --- prototype: pack models --------------------------------------------------

# Pack models stand in for five places when the snapshot's "prototype_pack" is
# true, or after P in the view. Everything else, and everything the buddy will
# build itself, stays code-built. A missing model falls back to the shapes.
func set_pack(on: bool) -> void:
	_pack_override = 1 if on else 0
	if _built and _have_snapshot:
		_signature = _place_signature()
		_rebuild_places()
		_update_card(0.0)
		_update_sky()


func _pack_on() -> bool:
	if _pack_override >= 0:
		return _pack_override == 1
	return bool(_snapshot.get("prototype_pack", false))


func _pack_ready() -> bool:
	for model in PACK_MODELS:
		if not ResourceLoader.exists(PACK_DIR + str(model) + ".gltf"):
			return false
	return true


# One pack model, scaled, with its material made matte like the shapes'.
func _pack_model(model: String, factor: float) -> Node3D:
	var scene := load(PACK_DIR + model + ".gltf") as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	node.scale = Vector3.ONE * factor
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mesh_node as MeshInstance3D).mesh
		for surface in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(surface) as StandardMaterial3D
			if mat != null:
				mat.roughness = 1.0
	return node


func _place_model(parent: Node3D, model: String, factor: float, pos: Vector3, yaw := 0.0) -> Node3D:
	var node := _pack_model(model, factor)
	if node != null:
		node.position = pos
		node.rotation.y = yaw
		parent.add_child(node)
	return node


func _build_from_pack(root: Node3D, id: String, point: Vector3) -> bool:
	if not ["home", "big_tree", "dark_trees", "patch", "high_ground"].has(id) or not _pack_ready():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var out := _outward(point)
	match id:
		"home":
			_pack_cottage(root, id)
		"big_tree":
			# The pack has no broad-leaved tree: its rounder conifer, made big.
			_place_model(root, "tree_single_B", PACK_BIG_TREE_SCALE, out * 1.6, rng.randf() * TAU)
		"dark_trees":
			# The same ring as the shapes, one pack pine for each cone.
			for i in range(8):
				var spot := _ring_point(rng, i, 8, 2.0, 6.0)
				var h := rng.randf_range(3.0, 4.5) + 0.8
				_place_model(root, "tree_single_A", h / PACK_PINE_HEIGHT, spot, rng.randf() * TAU)
		"patch":
			# No bushes or flowers in the pack: bare soil, its leafy water
			# plants for the overgrowth and its reeds among them.
			_place_model(root, "building_dirt", 3.2, Vector3(0.0, 0.0, 0.0), rng.randf() * TAU)
			for i in range(12):
				var spot := _ring_point(rng, i, 12, 0.6, 3.4)
				var model := "waterplant_C" if i % 4 == 0 else "waterplant_A"
				_place_model(root, model, rng.randf_range(5.0, 8.0), spot, rng.randf() * TAU)
		"high_ground":
			# The mound stays code-built: ground_height() and the card's feet
			# follow its shape. The pack's rocks sit on it.
			_add(root, _cyl_mesh(4.0, 9.0, 1.6, 10), Color(0.48, 0.62, 0.36), Vector3(0.0, 0.8, 0.0))
			var rocks := ["rock_single_E", "rock_single_C", "rock_single_A", "rock_single_C", "rock_single_E", "rock_single_A"]
			for i in range(rocks.size()):
				var spot := _ring_point(rng, i, rocks.size(), 1.0, 5.5)
				var y := ground_height({"high_ground": Vector3.ZERO}, spot)
				_place_model(root, str(rocks[i]), rng.randf_range(4.0, 6.5), spot + Vector3(0.0, y - 0.05, 0.0), rng.randf() * TAU)
	return true


# The pack's cottage is one mesh, so its roof cannot come off when the buddy is
# home (it is hidden inside instead); the window light stays for the night.
func _pack_cottage(root: Node3D, id: String) -> void:
	_home_point = root.position
	var house := Node3D.new()
	house.name = "House"
	var front := _neighbour_dir(id)
	house.rotation.y = atan2(front.x, front.z)
	root.add_child(house)
	_place_model(house, "building_home_A_red", PACK_HOUSE_SCALE, Vector3.ZERO)
	_window_light = OmniLight3D.new()
	_window_light.name = "WindowLight"
	_window_light.omni_range = 7.0
	_window_light.light_energy = 0.0
	_window_light.light_color = Color(1.0, 0.82, 0.45)
	_window_light.shadow_enabled = false
	_window_light.position = Vector3(0.0, 1.6, 3.4)
	house.add_child(_window_light)


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


# Prototype: "orbit" (the default), "first_person" or "follow".
func set_camera_mode(mode: String) -> void:
	_camera_mode = mode if CAMERA_MODES.has(mode) else "orbit"
	_follow_placed = false
	_free_look = false
	_set_mouse_look(false)
	if _built:
		_camera.near = NEAR_ORBIT if _camera_mode == "orbit" else NEAR_CLOSE
		if _camera_mode == "first_person" and not _eye_placed:
			_place_eye_by_card()
		_restyle_close()
		_apply_camera()


# Prototype: the harness turns the close-camera fixes off to show the view as
# the orbit draws it.
func set_close_fixes(on: bool) -> void:
	_close_fixes = on
	if _built:
		_restyle_close()


func _restyle_close() -> void:
	for blob in _blobs:
		_style_blob(blob)
	_update_mist(0.0)
	_style_labels()


# The flat sheets lie edge-on to an eye 1.6 m up, and a sheet above the eye is
# seen from below, where it is not drawn: the close cameras get upright puffs
# instead, each a billboard turned about its upright axis.
func _mist_upright() -> bool:
	return _close_fixes and _camera_mode != "orbit"


func _blob_scale(blob: Dictionary) -> Vector3:
	var flat: Vector3 = blob["scale"]
	if not _mist_upright():
		return flat
	return Vector3(flat.x, flat.x * MIST_UPRIGHT_HEIGHT, 1.0)


func _blob_lift(blob: Dictionary) -> float:
	if not _mist_upright():
		return float(blob["lift"])
	# The middle a little under halfway up, so the faded rim meets the ground.
	return (blob["scale"] as Vector3).x * MIST_UPRIGHT_HEIGHT * 0.4


func _style_blob(blob: Dictionary) -> void:
	var node: MeshInstance3D = blob["node"]
	var upright := _mist_upright()
	var dense := str(blob["state"]) != "thin"
	node.mesh = _mist_quad if upright else _mist_sheet
	if upright:
		node.material_override = _mist_dense_up if dense else _mist_thin_up
	else:
		node.material_override = _mist_dense_mat if dense else _mist_thin_mat
	if float(blob["shrink"]) < 0.0:
		node.scale = _blob_scale(blob)


# Close up, a label the size of a sign in the world fills the screen and shows
# through walls: the close cameras keep labels one size on screen, behind things.
func _style_labels() -> void:
	var close := _close_fixes and _camera_mode != "orbit"
	for label_node in _labels_root.get_children():
		var label := label_node as Label3D
		label.fixed_size = close
		label.no_depth_test = not close
		label.pixel_size = LABEL_CLOSE_PIXEL if close else 0.02


func camera_mode() -> String:
	return _camera_mode


# Prototype: where the eye stands (x and z; it stays EYE_HEIGHT over the
# ground) and which way it looks.
func set_eye(at: Vector3, yaw: float, pitch_deg: float) -> void:
	_eye = Vector3(at.x, 0.0, at.z)
	_look_yaw = yaw
	_look_pitch = clampf(deg_to_rad(pitch_deg), deg_to_rad(-80.0), deg_to_rad(80.0))
	_eye_placed = true
	if _built:
		_apply_camera()


# Prototype: the eye stands at `at` looking at `point`.
func look_from(at: Vector3, point: Vector3) -> void:
	var eye := Vector3(at.x, ground_height(_points, at) + EYE_HEIGHT, at.z)
	var d := point - eye
	set_eye(at, atan2(-d.x, -d.z), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


# Prototype: how far round from straight behind the follow camera sits.
func set_follow_side(degrees: float) -> void:
	_follow_side = deg_to_rad(degrees)
	_follow_placed = false


# Entering first person from the orbit: stand a few metres from the buddy, on
# the side the orbit camera was looking from, and look at it.
func _place_eye_by_card() -> void:
	var at := _card_pos if _card.visible else _home_or_zero()
	var from := Vector3(sin(_yaw), 0.0, cos(_yaw))
	look_from(at + from * 5.0, at + Vector3(0.0, ground_height(_points, at) + 1.0, 0.0))


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
	# Prototype fix: the assembled frames carry a clear margin (10 px) round the
	# character, and their pivots sit at the canvas bottom, so the card floated
	# 0.3 m (standing) to 0.45 m (walking) over its shadow. Feet go on the
	# lowest drawn pixel instead. (No image headless: the pivots stand.)
	_feet_rows.clear()
	for entry_variant in _frames.values():
		for frame_variant in _arr(_dict(entry_variant).get("frames", [])):
			if not (frame_variant is Texture2D):
				continue
			var frame_image := (frame_variant as Texture2D).get_image()
			if frame_image == null or frame_image.is_empty():
				continue
			if frame_image.is_compressed():
				frame_image.decompress()
			var drawn := frame_image.get_used_rect()
			if drawn.size.y > 0:
				_feet_rows[(frame_variant as Texture2D).get_instance_id()] = float(drawn.end.y)


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
	if _style() != _style_applied:
		_apply_style()
	var signature := _place_signature()
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
		_target = _orbit_goal()
		_apply_camera()
	_update_sky()


func _place_signature() -> String:
	var found_ids: Array = _points.keys()
	found_ids.sort()
	return "%s|%s|%s|%s|%s|%s|%s" % [",".join(PackedStringArray(found_ids)), str(_snapshot.get("paths", [])),
		str(_snapshot.get("home", "")), _pack_on(), _style(), _items_on(), _free_on()]


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
		if _free_on():
			# Prototype: no paths, so it heads straight there, on a gentle curve.
			ids = []
			var points: Array = _free_walk(_all_points[came_from], origin)
			if edge_try:
				points.append(edge_point)
			_walk_points = points
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
	var length := 0.0
	for i in range(_walk_points.size() - 1):
		length += (_walk_points[i] as Vector3).distance_to(_walk_points[i + 1])
	_walk_end = _walk_start + length / WALK_SPEED


func _update_mist_states(first: bool) -> void:
	var found_segments: Array = []
	for path_variant in ([] if _free_on() else _arr(_snapshot.get("paths", []))):
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
		_style_blob(blob)


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
	_animate_items()
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
	# Prototype: free roaming ambles about the place once a walk is over, while
	# it is idle or exploring (not sitting, sleeping or at home).
	if _free_on() and not walking and not visiting:
		var still_pose := card_pose(_snapshot, _clock, false)
		var at_home := Vector2(_stand_point.x - _home_point.x, _stand_point.z - _home_point.z).length() < 2.5
		if (still_pose == "idle" or still_pose == "happy") and not at_home:
			var amble := _amble_at(_stand_point, _clock)
			pos = amble["pos"]
			walking = bool(amble["walking"])
			_card_dir = amble["dir"]
	_card_pos = pos
	_card_walking = walking
	_card_pose = card_pose(_snapshot, _clock, walking)
	_card.position = Vector3(pos.x, ground_height(_points, pos) + CARD_LIFT, pos.z)
	# Prototype: asleep at home, it lies on the bed rather than the floor.
	if _bed_set and not walking and _card_pose == "sleep" \
			and Vector2(pos.x - _home_point.x, pos.z - _home_point.z).length() < 2.0:
		_card.position = _bed_point + Vector3(0.0, CARD_LIFT, 0.0)
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
	var feet := float(_feet_rows.get(texture.get_instance_id(), -1.0))
	if feet > 0.0:
		if pivot.x < 0.0:
			pivot.x = w * 0.5
		pivot.y = feet
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
	if has_focus():
		_keys_move_camera(delta)
	if not _free_look:
		_target = _target.lerp(_orbit_goal(), 1.0 - exp(-ORBIT_FOLLOW_RATE * delta))
	if _camera_mode == "follow":
		_follow_step(delta)
	_apply_camera()


# The middle of the buddy's body, on whatever ground it stands on (the house
# while it is away), so the orbit centres on the buddy and turns round it.
func _orbit_goal() -> Vector3:
	if _card.visible:
		return _card.position + Vector3(0.0, CARD_HEIGHT * 0.5, 0.0)
	return _home_or_zero()


func _apply_camera() -> void:
	var rain_at := _target
	match _camera_mode:
		"first_person":
			var eye := Vector3(_eye.x, ground_height(_points, _eye) + EYE_HEIGHT, _eye.z)
			_camera.transform = Transform3D(Basis(Vector3.UP, _look_yaw) * Basis(Vector3.RIGHT, _look_pitch), eye)
			rain_at = eye
		"follow":
			if not _follow_placed:
				_follow_step(0.0)
			_camera.transform = Transform3D(Basis.IDENTITY, _follow_pos).looking_at(_follow_look, Vector3.UP)
			rain_at = _follow_look
		_:
			var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
			_camera.transform = Transform3D(Basis.IDENTITY, _target + offset).looking_at(_target, Vector3.UP)
	if _rain != null:
		_rain.position = Vector3(rain_at.x, 22.0, rain_at.z)


# Prototype: WASD (or the arrows) move whichever camera is in use and Q/E turn
# it: the orbit slides over the land (Space comes back to the buddy), first
# person walks, and the follow camera swings round the buddy and in or out.
func _keys_move_camera(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_E):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		turn -= 1.0
	if move.length() > 1.0:
		move = move.normalized()
	if move == Vector2.ZERO and turn == 0.0:
		return
	match _camera_mode:
		"first_person":
			_look_yaw -= turn * TURN_SPEED * delta
			var forward := Vector3(-sin(_look_yaw), 0.0, -cos(_look_yaw))
			var right := Vector3(cos(_look_yaw), 0.0, -sin(_look_yaw))
			_eye = _within_land(_eye + (forward * move.y + right * move.x) * EYE_SPEED * delta)
		"follow":
			_follow_side += (move.x + turn) * TURN_SPEED * delta
			_follow_back = clampf(_follow_back - move.y * 4.0 * delta, 2.5, 14.0)
		_:
			_yaw -= turn * TURN_SPEED * delta
			if move != Vector2.ZERO:
				var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
				var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
				_free_look = true
				var flat := _within_land(Vector3(_target.x, 0.0, _target.z)
					+ (forward * move.y + right * move.x) * PAN_SPEED * (_dist / START_DISTANCE) * delta)
				_target = Vector3(flat.x, ground_height(_points, flat) + CARD_HEIGHT * 0.5, flat.z)


func _within_land(at: Vector3) -> Vector3:
	var flat := Vector2(at.x, at.z)
	if flat.length() > EYE_REACH:
		flat = flat.normalized() * EYE_REACH
	return Vector3(flat.x, 0.0, flat.y)


# Prototype: low behind the buddy, turning with it as it walks. Standing, it
# keeps the last heading; one that has not walked looks in across the land.
func _follow_step(delta: float) -> void:
	var at := _card.position if _card.visible else _home_or_zero()
	if _card_walking and _card_dir.length() > 0.001:
		if _follow_heading.length() < 0.5:
			_follow_heading = _card_dir
		else:
			var turned := _follow_heading.lerp(_card_dir, 1.0 - exp(-1.5 * delta))
			if turned.length() > 0.01:
				_follow_heading = turned.normalized()
	if _follow_heading.length() < 0.5:
		var inward := Vector3(-at.x, 0.0, -at.z)
		_follow_heading = inward.normalized() if inward.length() > 1.0 else Vector3(0.0, 0.0, -1.0)
	var back := _follow_heading.rotated(Vector3.UP, _follow_side)
	var goal := at - back * _follow_back + Vector3(0.0, FOLLOW_UP, 0.0)
	goal.y = maxf(goal.y, ground_height(_points, goal) + 0.6)
	var look := at + Vector3(0.0, FOLLOW_LOOK_UP, 0.0)
	if not _follow_placed:
		_follow_pos = goal
		_follow_look = look
		_follow_placed = true
	else:
		_follow_pos = _follow_pos.lerp(goal, 1.0 - exp(-2.5 * delta))
		_follow_look = _follow_look.lerp(look, 1.0 - exp(-6.0 * delta))


func _set_mouse_look(on: bool) -> void:
	if on == _mouse_look:
		return
	_mouse_look = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_set_mouse_look(false)


func _update_sky() -> void:
	var hour := fposmod(_clock + float(_tz_bias) * 60.0, 86400.0) / 3600.0
	_show_items_for(int(hour))
	_sky = sky_at(hour, {"cover": _cover_shown, "rain": _rain_shown})
	var night: float = _sky["night"]
	_env.background_color = _sky["sky"]
	_env.ambient_light_color = _sky["ambient"]
	_env.ambient_light_energy = _sky["ambient_energy"]
	_sun.light_color = _sky["sun_color"]
	_sun.light_energy = float(_sky["sun_energy"]) * (SHADOW_SUN_SCALE if _sun.shadow_enabled else 1.0)
	var travel: Vector3 = _sky["sun_dir"]
	_sun.transform = Transform3D(Basis.looking_at(travel, Vector3.UP), Vector3.ZERO)
	_sprite.modulate = _sky["card_tint"]
	# Prototype looks: the land's own green, or white under the grass texture.
	var land := Color(1, 1, 1) if _style() == "textured" else _tone(GRASS)
	_land_mat.albedo_color = land * (_sky["ground_tint"] as Color)
	if _sky_mat != null and _style() != "flat":
		var sky_color: Color = _sky["sky"]
		_sky_mat.sky_top_color = sky_color.darkened(0.3)
		_sky_mat.sky_horizon_color = sky_color.lerp(Color(0.90, 0.88, 0.84), 0.4 * (1.0 - night))
		_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
		_sky_mat.ground_bottom_color = _tone(Color(0.60, 0.65, 0.62)) * (0.25 + 0.75 * (1.0 - night))
	var mist: Color = _sky["mist"]
	_mist_dense_mat.albedo_color = Color(mist.r, mist.g, mist.b, MIST_DENSE_ALPHA)
	_mist_thin_mat.albedo_color = Color(mist.r, mist.g, mist.b, MIST_THIN_ALPHA)
	_mist_dense_up.albedo_color = _mist_dense_mat.albedo_color
	_mist_thin_up.albedo_color = _mist_thin_mat.albedo_color
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
		node.position = base + Vector3(sin(_clock * 0.05 + phase) * 0.8, _blob_lift(blob), cos(_clock * 0.04 + phase) * 0.8)
		var left: float = blob["shrink"]
		if left >= 0.0:
			left -= delta
			if left <= 0.0:
				node.visible = false
				blob["shrink"] = -1.0
			else:
				blob["shrink"] = left
				node.scale = _blob_scale(blob) * (left / MIST_FADE_SECONDS)


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
		elif button.button_index == MOUSE_BUTTON_RIGHT and _camera_mode == "first_person":
			# Prototype: hold the right button for mouse-look with the cursor held.
			_set_mouse_look(button.pressed)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist * 0.9, MIN_DISTANCE, MAX_DISTANCE)
			_apply_camera()
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist * 1.1, MIN_DISTANCE, MAX_DISTANCE)
			_apply_camera()
			accept_event()
	elif event is InputEventMouseMotion and (_pressing or _mouse_look):
		var motion := event as InputEventMouseMotion
		_drag_travel += motion.relative.length()
		match _camera_mode:
			"first_person":
				_look_yaw -= motion.relative.x * LOOK_SPEED
				_look_pitch = clampf(_look_pitch - motion.relative.y * LOOK_SPEED, deg_to_rad(-80.0), deg_to_rad(80.0))
			"follow":
				_follow_side -= motion.relative.x * LOOK_SPEED
			_:
				_yaw -= motion.relative.x * 0.006
				_pitch = clampf(_pitch + motion.relative.y * 0.004, deg_to_rad(22.0), deg_to_rad(78.0))
		_apply_camera()
		accept_event()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		# Prototype keys: C cycles the camera, P swaps code shapes for the pack.
		var key := event as InputEventKey
		if key.physical_keycode == KEY_C:
			set_camera_mode(str(CAMERA_MODES[(CAMERA_MODES.find(_camera_mode) + 1) % CAMERA_MODES.size()]))
			accept_event()
		elif key.physical_keycode == KEY_P:
			set_pack(not _pack_on())
			accept_event()
		elif key.physical_keycode == KEY_L:
			set_style(str(STYLES[(STYLES.find(_style()) + 1) % STYLES.size()]))
			accept_event()
		elif key.physical_keycode == KEY_SPACE:
			# Back to the buddy: the orbit follows it again, the follow camera
			# comes back to its usual distance.
			_free_look = false
			_follow_back = FOLLOW_BACK
			accept_event()
		elif key.physical_keycode == KEY_ESCAPE and _mouse_look:
			_set_mouse_look(false)
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
