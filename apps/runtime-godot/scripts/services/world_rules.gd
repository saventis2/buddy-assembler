extends RefCounted

# The world's rules (Plan 14 step 3a): materials with properties, about twenty
# ways of working, what a tool can do, how a building is judged, and the basics
# check that shelter, warmth and storage can be reached from what the starting
# land gives. Pure functions on plain dictionaries, written as static so the
# mind can call them through a preload. No AppState, no randomness, no clock.
# Nothing uses the rules yet (steps 6 to 8 call them).
#
# Properties are whole numbers 0 to 3; a missing property is 0, and every result
# is clamped to 0..3. A material STATE is never changed in place; every function
# hands back new dictionaries:
#   {"of": [raw ids, sorted, unique], "props": {property: level, non-zero only},
#    "form": "" for a raw lump, "done": [ways applied, in order],
#    "parts": [the states a bound or layered thing was made from],
#    "layers": how many layers (roofs)}

const PROPERTIES := ["hard", "strong", "bendable", "brittle", "waterproof", "burns", "holds_heat",
	"see_through", "heavy", "rots", "shapeable", "fibrous", "edge"]

const PROPERTY_MEANINGS := {
	"hard": "does not dent or wear",
	"strong": "carries weight and pulling without breaking",
	"bendable": "bends without breaking",
	"brittle": "breaks when hit or bent",
	"waterproof": "keeps water out",
	"burns": "burns as fuel",
	"holds_heat": "keeps warmth and gives it back",
	"see_through": "lets light through",
	"heavy": "is hard to carry",
	"rots": "goes bad when it stays wet",
	"shapeable": "can be pressed into a shape",
	"fibrous": "is made of long threads",
	"edge": "can cut",
}

# "get" is the way of working that gets it from the land; "places" are land
# place ids. Flags (default false): plant, earthy, temper, sows, liquid.
const RAW := {
	"stick": {"props": {"hard": 1, "strong": 1, "bendable": 2, "burns": 2, "rots": 1},
		"get": "gather", "regrows_days": 3, "places": ["wood_heap", "big_tree", "dark_trees"], "plant": true},
	"log": {"props": {"hard": 2, "strong": 3, "burns": 3, "heavy": 2, "rots": 1},
		"get": "gather", "regrows_days": 0, "places": ["wood_heap", "dark_trees"], "plant": true},
	"stone": {"props": {"hard": 3, "strong": 3, "heavy": 2, "holds_heat": 2, "brittle": 1},
		"get": "gather", "regrows_days": 0, "places": ["stony_ground", "water"]},
	"flint": {"props": {"hard": 3, "heavy": 1, "brittle": 2},
		"get": "gather", "regrows_days": 0, "places": ["stony_ground"], "real_names": ["flint", "flints"]},
	"clay": {"props": {"shapeable": 3, "heavy": 2, "holds_heat": 1},
		"get": "dig", "regrows_days": 0, "places": ["grey_bank"], "earthy": true, "real_names": ["clay"]},
	"earth": {"props": {"shapeable": 1, "heavy": 1},
		"get": "dig", "regrows_days": 0, "places": ["yard", "patch"], "earthy": true},
	"sand": {"props": {"heavy": 1},
		"get": "gather", "regrows_days": 0, "places": ["sandy_bend"], "temper": true},
	"reed": {"props": {"bendable": 2, "strong": 1, "waterproof": 1, "burns": 2, "rots": 1},
		"get": "cut", "regrows_days": 14, "places": ["tall_reeds", "water"], "plant": true, "real_names": ["reed", "reeds"]},
	"grass": {"props": {"bendable": 3, "fibrous": 2, "burns": 2, "rots": 2},
		"get": "gather", "regrows_days": 7, "places": ["long_grass", "patch"], "plant": true, "temper": true},
	"nettle": {"props": {"bendable": 3, "fibrous": 3, "strong": 1, "rots": 1},
		"get": "cut", "regrows_days": 10, "places": ["patch"], "plant": true, "real_names": ["nettle", "nettles"]},
	"seed": {"props": {},
		"get": "gather", "regrows_days": 30, "places": ["patch"], "plant": true, "sows": true},
	"water": {"props": {},
		"get": "draw", "regrows_days": 0, "places": ["water"], "liquid": true},
}

# The twenty ways, in order. "label" is plain words for the Mind view; the other
# numbers are the ones work() reads (no magic numbers elsewhere).
const WAYS := {
	"gather": {"label": "picked up by hand"},
	"cut": {"label": "cut", "min_edge": 1, "blow_hard": 2, "blow_striker": 2},
	"dig": {"label": "dug", "digger": 1},
	"split": {"label": "split", "striker": 2, "rough_brittle": 1, "flake_brittle": 2, "flake_edge": 2,
		"rough_edge": 1, "plank_hard": 2, "plank_edge": 1},
	"carve": {"label": "carved", "split_brittle": 2},
	"grind": {"label": "ground on a stone", "rub_hard": 3, "edge_gain": 1},
	"shape": {"label": "shaped", "shapeable": 2},
	"dry": {"label": "dried", "days": 2, "brick_days": 3, "heat": 1, "dried_hard": 2, "dried_strong": 1,
		"dried_brittle": 1},
	"fire": {"label": "fired", "heat": 3, "half_heat": 2, "glass_heat": 4, "fired_hard": 3, "fired_strong": 2,
		"fired_waterproof": 2, "fired_brittle": 2, "fired_holds_heat": 2, "half_hard": 2, "half_waterproof": 1,
		"half_brittle": 1, "glass_see_through": 3, "glass_hard": 3, "glass_brittle": 3},
	"twist": {"label": "twisted", "fibrous": 2, "strong_gain": 2, "bendable": 3},
	"weave": {"label": "woven", "bendable": 2, "brittle_max": 2, "strong_gain": 1},
	"bind": {"label": "tied together", "head_edge": 1, "head_striker": 2, "handle_hard": 1, "frame_pieces": 2,
		"drill_pieces": 2, "binder_gain": 1},
	"mix": {"label": "mixed", "clay_shapeable": 3, "other_shapeable": 2, "grass_strong": 1},
	"stack": {"label": "stacked", "hard": 2, "kiln_holds_heat": 2, "wall_heavy": 3},
	"layer": {"label": "laid in layers", "waterproof_max_roof": 3, "waterproof_max_wall": 2, "wall_holds_heat": 1},
	"join": {"label": "joined", "edge": 2, "pieces": 2},
	"plant": {"label": "planted"},
	"grow": {"label": "grown", "days": 20, "food_rots": 2},
	"cook": {"label": "cooked", "heat": 2, "burn_heat": 3, "meal_rots": 1},
	"make_fire": {"label": "lit a fire", "burns": 3},
}

# What a fire and a kiln give, and what a tool form adds.
const FIRE_HEAT := 2
const KILN_HEAT := 3
const MAX_LEVEL := 3

const WORKED := "worked"
const BADLY := "badly"
const FAILED := "failed"


# --- states -----------------------------------------------------------------

# The starting state of a raw material, or {} for an unknown id.
static func raw(id: String) -> Dictionary:
	if not RAW.has(id):
		return {}
	var entry: Dictionary = RAW[id]
	var props: Dictionary = entry["props"]
	return {"of": [id], "props": props.duplicate(true), "form": "", "done": [], "parts": [], "layers": 0}


# Every raw id the land gives somewhere, sorted.
static func land_materials() -> Array:
	var out: Array = []
	for id in RAW.keys():
		var entry: Dictionary = RAW[id]
		var places: Array = entry["places"]
		if not places.is_empty():
			out.append(str(id))
	out.sort()
	return out


static func _lv(state: Dictionary, prop: String) -> int:
	var props: Dictionary = state.get("props", {})
	return int(props.get(prop, 0))


static func _form(state: Dictionary) -> String:
	return str(state.get("form", ""))


static func _has_of(state: Dictionary, id: String) -> bool:
	var of: Array = state.get("of", [])
	return of.has(id)


static func _done_has(state: Dictionary, way: String) -> bool:
	var done: Array = state.get("done", [])
	return done.has(way)


static func _flag(state: Dictionary, flag: String) -> bool:
	var of: Array = state.get("of", [])
	for id in of:
		if RAW.has(id):
			var entry: Dictionary = RAW[id]
			if bool(entry.get(flag, false)):
				return true
	return false


static func _is_earthy(state: Dictionary) -> bool:
	return _flag(state, "earthy")


static func _is_plant(state: Dictionary) -> bool:
	return _flag(state, "plant") and not _is_earthy(state)


static func _clean(props: Dictionary) -> Dictionary:
	var out := {}
	for key in props.keys():
		var level: int = clampi(int(props[key]), 0, MAX_LEVEL)
		if level > 0:
			out[key] = level
	return out


static func _n(way: String, key: String) -> int:
	var entry: Dictionary = WAYS[way]
	return int(entry[key])


static func _union(inputs: Array) -> Array:
	var seen := {}
	for state_variant in inputs:
		var state: Dictionary = state_variant
		var of: Array = state.get("of", [])
		for id in of:
			seen[str(id)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


# The new state: of from every input, done from the first input plus the way.
static func _make(inputs: Array, way: String, props: Dictionary, form: String,
		parts: Array = [], layers: int = 0) -> Dictionary:
	var first: Dictionary = inputs[0]
	var done: Array = (first.get("done", []) as Array).duplicate(true)
	done.append(way)
	return {"of": _union(inputs), "props": _clean(props), "form": form, "done": done,
		"parts": parts, "layers": layers}


static func _res(outcome: String, reason: String, product: Dictionary) -> Dictionary:
	return {"outcome": outcome, "reason": reason, "product": product}


static func _fail(reason: String) -> Dictionary:
	return _res(FAILED, reason, {})


static func _props_of(state: Dictionary) -> Dictionary:
	return (state.get("props", {}) as Dictionary).duplicate(true)


# The form asked for in conditions, if it is one of the allowed; else the default.
static func _asked_form(cond: Dictionary, allowed: Array, default_form: String) -> String:
	var asked: String = str(cond.get("form", default_form))
	if allowed.has(asked):
		return asked
	return default_form


# --- tools ------------------------------------------------------------------

# Index of the part that works as the head of a tool: the highest edge, ties the
# highest striker, cords never. -1 when there is none.
static func _head_index(parts: Array) -> int:
	var best := -1
	var best_edge := -1
	var best_striker := -1
	for i in range(parts.size()):
		var part: Dictionary = parts[i]
		if _form(part) == "cord":
			continue
		var ab: Dictionary = abilities(part)
		var edge: int = int(ab["edge"])
		var striker: int = int(ab["striker"])
		if edge > best_edge or (edge == best_edge and striker > best_striker):
			best = i
			best_edge = edge
			best_striker = striker
	return best


# What a state can do as a tool: {"edge", "striker", "digger", "drill", "heat"}.
static func abilities(state: Dictionary) -> Dictionary:
	var out := {"edge": 0, "striker": 0, "digger": 0, "drill": 0, "heat": 0}
	if state.is_empty():
		return out
	var form: String = _form(state)
	var src: Dictionary = state
	var head_form := ""
	if form == "tool":
		var parts: Array = state.get("parts", [])
		var index: int = _head_index(parts)
		if index >= 0:
			src = parts[index]
			head_form = _form(src)
	var edge: int = _lv(src, "edge")
	var hard: int = _lv(src, "hard")
	var heavy: int = _lv(src, "heavy")
	var striker := 0
	if hard >= 2 and heavy >= 1:
		striker = mini(hard, heavy)
	var digger := 0
	if form == "tool":
		striker += 1
		if head_form == "flake" and edge >= 1:
			digger = 2
	elif form == "point" or (form == "flake" and edge >= 1):
		digger = 1
	out["edge"] = clampi(edge, 0, MAX_LEVEL)
	out["striker"] = clampi(striker, 0, MAX_LEVEL)
	out["digger"] = clampi(digger, 0, MAX_LEVEL)
	out["drill"] = 1 if form == "drill" else 0
	if form == "fire":
		out["heat"] = FIRE_HEAT
	elif form == "kiln":
		out["heat"] = KILN_HEAT
	return out


# --- the engine -------------------------------------------------------------

# Work inputs with a way. Returns {"outcome": "worked" | "badly" | "failed",
# "reason": "" when worked, "product": the new state, {} when failed}.
# conditions (all optional): water, sun (bools), heat, days, layers, count
# (ints), form (the shape asked for).
static func work(way: String, inputs: Array, tool: Dictionary = {}, conditions: Dictionary = {}) -> Dictionary:
	if not WAYS.has(way):
		return _fail("I don't know how to do that")
	if inputs.is_empty():
		return _fail("there is nothing to work")
	var ins: Array = []
	for state_variant in inputs:
		var state: Dictionary = state_variant
		ins.append(state.duplicate(true))
	var held: Dictionary = tool.duplicate(true)
	var cond: Dictionary = conditions.duplicate(true)
	var heat: int = maxi(int(cond.get("heat", 0)), int(abilities(held)["heat"]))
	match way:
		"gather":
			return _gather(ins)
		"cut":
			return _cut(ins, held)
		"dig":
			return _dig(ins, held)
		"split":
			return _split(ins, held)
		"carve":
			return _carve(ins, held, cond)
		"grind":
			return _grind(ins, held)
		"shape":
			return _shape(ins, cond)
		"dry":
			return _dry(ins, cond, heat)
		"fire":
			return _fire(ins, heat)
		"twist":
			return _twist(ins)
		"weave":
			return _weave(ins, cond)
		"bind":
			return _bind(ins, cond)
		"mix":
			return _mix(ins, cond)
		"stack":
			return _stack(ins, cond)
		"layer":
			return _layer(ins, cond)
		"join":
			return _join(ins, held, cond)
		"plant":
			return _plant(ins, cond)
		"grow":
			return _grow(ins, cond)
		"cook":
			return _cook(ins, heat)
		"make_fire":
			return _make_fire(ins, held)
	return _fail("I don't know how to do that")


static func _gather(ins: Array) -> Dictionary:
	var s: Dictionary = ins[0]
	var of: Array = s.get("of", [])
	if of.size() != 1 or not RAW.has(of[0]):
		return _fail("it won't come away by hand")
	var entry: Dictionary = RAW[of[0]]
	if str(entry["get"]) != "gather":
		return _fail("it won't come away by hand")
	return _res(WORKED, "", _make(ins, "gather", _props_of(s), _form(s), (s.get("parts", []) as Array).duplicate(true), int(s.get("layers", 0))))


static func _cut(ins: Array, tool: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	var ab: Dictionary = abilities(tool)
	var hard: int = _lv(s, "hard")
	if int(ab["edge"]) < maxi(_n("cut", "min_edge"), hard):
		return _fail("nothing sharp enough to cut it")
	if hard >= _n("cut", "blow_hard") and int(ab["striker"]) < _n("cut", "blow_striker"):
		return _fail("it needs a heavier blow")
	var form: String = _form(s)
	if _is_plant(s):
		form = "bundle" if hard == 0 else "pole"
	return _res(WORKED, "", _make(ins, "cut", _props_of(s), form))


static func _dig(ins: Array, tool: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	if not _is_earthy(s):
		return _fail("there is nothing to dig there")
	if int(abilities(tool)["digger"]) < _n("dig", "digger"):
		return _fail("the ground is too hard for bare hands")
	return _res(WORKED, "", _make(ins, "dig", _props_of(s), _form(s)))


static func _split(ins: Array, tool: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	var ab: Dictionary = abilities(tool)
	if int(ab["striker"]) < _n("split", "striker"):
		return _fail("it just bounced off")
	var props: Dictionary = _props_of(s)
	var brittle: int = _lv(s, "brittle")
	if brittle >= _n("split", "flake_brittle"):
		props["edge"] = _n("split", "flake_edge")
		return _res(WORKED, "", _make(ins, "split", props, "flake"))
	if brittle == _n("split", "rough_brittle"):
		props["edge"] = _n("split", "rough_edge")
		return _res(BADLY, "it split, but the edge is rough", _make(ins, "split", props, "flake"))
	if _is_plant(s) and _lv(s, "hard") >= _n("split", "plank_hard"):
		if int(ab["edge"]) < _n("split", "plank_edge"):
			return _fail("it needs something to drive into it")
		props["heavy"] = _lv(s, "heavy") - 1
		return _res(WORKED, "", _make(ins, "split", props, "plank"))
	return _fail("it dented but didn't split")


static func _carve(ins: Array, tool: Dictionary, cond: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	if int(abilities(tool)["edge"]) < _lv(s, "hard"):
		return _fail("the edge won't bite")
	if _lv(s, "brittle") >= _n("carve", "split_brittle"):
		return _fail("it cracked")
	if _lv(s, "shapeable") >= 1:
		return _fail("it is too soft to carve")
	var form: String = _asked_form(cond, ["point", "peg", "bowl", "handle"], "point")
	return _res(WORKED, "", _make(ins, "carve", _props_of(s), form))


static func _grind(ins: Array, tool: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	var rub: int = _n("grind", "rub_hard")
	if _lv(tool, "hard") < rub:
		return _fail("there is nothing hard enough to rub it on")
	if _lv(s, "hard") < rub:
		return _fail("it wears away instead of sharpening")
	var props: Dictionary = _props_of(s)
	props["edge"] = _lv(s, "edge") + _n("grind", "edge_gain")
	return _res(WORKED, "", _make(ins, "grind", props, _form(s)))


static func _shape(ins: Array, cond: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	if not bool(cond.get("water", false)):
		return _fail("it crumbles")
	if _lv(s, "shapeable") < _n("shape", "shapeable"):
		return _fail("it won't hold a shape")
	var form: String = _asked_form(cond, ["brick", "pot", "tile"], "brick")
	return _res(WORKED, "", _make(ins, "shape", _props_of(s), form))


static func _dry(ins: Array, cond: Dictionary, heat: int) -> Dictionary:
	var s: Dictionary = ins[0]
	if not bool(cond.get("sun", false)) and heat < _n("dry", "heat"):
		return _fail("it got wet again")
	var form: String = _form(s)
	var need_days: int = _n("dry", "brick_days") if form == "brick" else _n("dry", "days")
	if int(cond.get("days", 0)) < need_days:
		return _fail("it isn't dry yet")
	var props: Dictionary = _props_of(s)
	var outcome := WORKED
	var reason := ""
	if _is_earthy(s):
		if _lv(s, "shapeable") >= 1:
			var tempered: bool = _has_of(s, "sand") or _has_of(s, "grass")
			if not tempered and form == "brick":
				return _fail("it fell apart while drying")
			props["shapeable"] = 0
			props["hard"] = _n("dry", "dried_hard")
			props["strong"] = _n("dry", "dried_strong") + (1 if _has_of(s, "grass") else 0)
			props["brittle"] = _n("dry", "dried_brittle")
			props["waterproof"] = 0
			if not tempered and (form == "pot" or form == "tile"):
				props["strong"] = int(props["strong"]) - 1
				outcome = BADLY
				reason = "it cracked while it dried"
	elif _is_plant(s):
		props["rots"] = _lv(s, "rots") - 1
		props["burns"] = _lv(s, "burns") + 1
		props["bendable"] = _lv(s, "bendable") - 1
	return _res(outcome, reason, _make(ins, "dry", props, form, (s.get("parts", []) as Array).duplicate(true), int(s.get("layers", 0))))


static func _fire(ins: Array, heat: int) -> Dictionary:
	var s: Dictionary = ins[0]
	var props: Dictionary = _props_of(s)
	var earthy: bool = _is_earthy(s)
	var dried: bool = _done_has(s, "dry")
	if earthy and not dried:
		return _fail("it burst in the fire")
	if _lv(s, "burns") >= 1:
		return _fail("it burned away")
	if earthy:
		if heat >= _n("fire", "heat"):
			props["hard"] = _n("fire", "fired_hard")
			props["strong"] = _n("fire", "fired_strong")
			props["waterproof"] = _n("fire", "fired_waterproof")
			props["brittle"] = _n("fire", "fired_brittle")
			props["holds_heat"] = _n("fire", "fired_holds_heat")
			props["shapeable"] = 0
			return _res(WORKED, "", _make(ins, "fire", props, _form(s)))
		if heat == _n("fire", "half_heat"):
			props["hard"] = _n("fire", "half_hard")
			props["waterproof"] = _n("fire", "half_waterproof")
			props["brittle"] = _n("fire", "half_brittle")
			return _res(BADLY, "not hot enough", _make(ins, "fire", props, _form(s)))
		return _fail("not hot enough")
	var of: Array = s.get("of", [])
	if of == ["sand"]:
		if heat >= _n("fire", "glass_heat"):
			props["see_through"] = _n("fire", "glass_see_through")
			props["hard"] = _n("fire", "glass_hard")
			props["brittle"] = _n("fire", "glass_brittle")
			return _res(WORKED, "", _make(ins, "fire", props, "glass"))
		return _fail("not hot enough")
	if heat < _n("fire", "half_heat"):
		return _fail("not hot enough")
	return _fail("nothing changed")


static func _twist(ins: Array) -> Dictionary:
	var s: Dictionary = ins[0]
	if _lv(s, "fibrous") < _n("twist", "fibrous"):
		return _fail("the threads are too short to twist")
	var props: Dictionary = _props_of(s)
	props["strong"] = _lv(s, "strong") + _n("twist", "strong_gain")
	props["bendable"] = _n("twist", "bendable")
	props["fibrous"] = 0
	return _res(WORKED, "", _make(ins, "twist", props, "cord"))


static func _weave(ins: Array, cond: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	if _lv(s, "bendable") < _n("weave", "bendable") or _lv(s, "brittle") >= _n("weave", "brittle_max"):
		return _fail("it snapped when I bent it")
	var props: Dictionary = _props_of(s)
	props["strong"] = _lv(s, "strong") + _n("weave", "strong_gain")
	var form: String = _asked_form(cond, ["panel", "basket", "mat"], "panel")
	return _res(WORKED, "", _make(ins, "weave", props, form))


static func _bind(ins: Array, cond: Dictionary) -> Dictionary:
	var binder := -1
	for i in range(ins.size()):
		if _form(ins[i]) == "cord":
			binder = i
			break
	if binder < 0:
		return _fail("nothing to bind it with")
	var binder_state: Dictionary = ins[binder]
	var others: Array = []
	for i in range(ins.size()):
		if i != binder:
			others.append(ins[i])
	var parts: Array = ins.duplicate(true)
	var asked: String = _asked_form(cond, ["tool", "frame", "drill"], "tool")
	if asked == "tool":
		var head_i: int = _head_index(others)
		if head_i < 0:
			return _fail("there is nothing sharp or heavy to fix on it")
		var head: Dictionary = others[head_i]
		var ab: Dictionary = abilities(head)
		if int(ab["edge"]) < _n("bind", "head_edge") and int(ab["striker"]) < _n("bind", "head_striker"):
			return _fail("there is nothing sharp or heavy to fix on it")
		var has_handle := false
		for i in range(others.size()):
			if i == head_i:
				continue
			var piece: Dictionary = others[i]
			if _is_plant(piece) and _lv(piece, "hard") >= _n("bind", "handle_hard") \
					and ["", "pole", "handle"].has(_form(piece)):
				has_handle = true
		if not has_handle:
			return _fail("there is no handle to fix it to")
		return _res(WORKED, "", _make(ins, "bind", _props_of(head), "tool", parts))
	if asked == "frame":
		var strong: int = MAX_LEVEL
		var count := 0
		var first_props: Dictionary = {}
		for piece_variant in others:
			var piece: Dictionary = piece_variant
			if _is_plant(piece) and ["pole", "plank", ""].has(_form(piece)) and _lv(piece, "hard") >= 1:
				if count == 0:
					first_props = _props_of(piece)
				count += 1
				strong = mini(strong, _lv(piece, "strong"))
		if count < _n("bind", "frame_pieces"):
			return _fail("the pieces won't hold together")
		first_props["strong"] = mini(strong, _lv(binder_state, "strong") + _n("bind", "binder_gain"))
		return _res(WORKED, "", _make(ins, "bind", first_props, "frame", parts))
	var sticks: Array = []
	for piece_variant in others:
		var piece: Dictionary = piece_variant
		if piece.get("of", []) == ["stick"]:
			sticks.append(piece)
	if sticks.size() < _n("bind", "drill_pieces"):
		return _fail("the pieces won't hold together")
	var stick: Dictionary = sticks[0]
	return _res(WORKED, "", _make(ins, "bind", _props_of(stick), "drill", parts))


static func _mix(ins: Array, cond: Dictionary) -> Dictionary:
	if not bool(cond.get("water", false)):
		return _fail("it's too dry to mix")
	var base: Dictionary = {}
	for state_variant in ins:
		var state: Dictionary = state_variant
		if _is_earthy(state):
			base = state
			break
	if base.is_empty():
		return _fail("there's nothing in it that sticks")
	var of: Array = _union(ins)
	var props: Dictionary = _props_of(base)
	props["shapeable"] = _n("mix", "clay_shapeable") if of.has("clay") else _n("mix", "other_shapeable")
	if of.has("grass"):
		props["strong"] = _lv(base, "strong") + _n("mix", "grass_strong")
	return _res(WORKED, "", _make(ins, "mix", props, "mix"))


static func _stack(ins: Array, cond: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	if _lv(s, "hard") < _n("stack", "hard"):
		return _fail("it's too soft to stack")
	if not ["", "brick", "flake", "plank"].has(_form(s)):
		return _fail("it won't sit still")
	var props: Dictionary = _props_of(s)
	if bool(cond.get("around_fire", false)) and _lv(s, "holds_heat") >= _n("stack", "kiln_holds_heat"):
		return _res(WORKED, "", _make(ins, "stack", props, "kiln"))
	props["waterproof"] = 0
	props["heavy"] = _n("stack", "wall_heavy")
	return _res(WORKED, "", _make(ins, "stack", props, "wall"))


static func _layer(ins: Array, cond: Dictionary) -> Dictionary:
	if ins.size() < 2 or not ["frame", "panel", "wall"].has(_form(ins[1])):
		return _fail("it slid off; it needs something under it")
	var covering: Dictionary = ins[0]
	var backing: Dictionary = ins[1]
	var layers: int = int(cond.get("layers", 1))
	if layers < 1:
		return _fail("there is nothing to lay")
	var parts: Array = [covering.duplicate(true), backing.duplicate(true)]
	var backing_form: String = _form(backing)
	if _is_plant(covering) and (backing_form == "frame" or backing_form == "panel"):
		var props: Dictionary = _props_of(covering)
		props["waterproof"] = mini(_n("layer", "waterproof_max_roof"),
			_lv(covering, "waterproof") + int((layers - 1) / 2.0))
		if not _done_has(covering, "dry"):
			props["rots"] = maxi(_lv(covering, "rots"), 1)
			return _res(BADLY, "it was laid wet and will rot", _make(ins, "layer", props, "roof", parts, layers))
		return _res(WORKED, "", _make(ins, "layer", props, "roof", parts, layers))
	if _is_earthy(covering) and _form(covering) == "mix" and (backing_form == "panel" or backing_form == "wall"):
		var wall_props: Dictionary = _props_of(backing)
		wall_props["strong"] = _lv(backing, "strong")
		wall_props["waterproof"] = mini(_n("layer", "waterproof_max_wall"), _lv(backing, "waterproof") + 1)
		wall_props["holds_heat"] = maxi(_lv(backing, "holds_heat"), _n("layer", "wall_holds_heat"))
		return _res(WORKED, "", _make(ins, "layer", wall_props, "wall", parts))
	return _fail("it won't stay in layers")


static func _join(ins: Array, tool: Dictionary, cond: Dictionary) -> Dictionary:
	var pieces: Array = []
	for state_variant in ins:
		var state: Dictionary = state_variant
		if _form(state) == "plank" or _form(state) == "pole":
			pieces.append(state)
	if pieces.size() < _n("join", "pieces") or int(abilities(tool)["edge"]) < _n("join", "edge"):
		return _fail("the pieces won't hold together")
	var props: Dictionary = _props_of(pieces[0])
	var strong: int = MAX_LEVEL
	for piece_variant in pieces:
		var piece: Dictionary = piece_variant
		strong = mini(strong, _lv(piece, "strong"))
	props["strong"] = strong
	var form: String = _asked_form(cond, ["shelf", "frame", "door"], "shelf")
	return _res(WORKED, "", _make(ins, "join", props, form, ins.duplicate(true)))


static func _plant(ins: Array, cond: Dictionary) -> Dictionary:
	var has_seed := false
	var ground: Dictionary = {}
	for state_variant in ins:
		var state: Dictionary = state_variant
		if _flag(state, "sows"):
			has_seed = true
		elif _is_earthy(state) and ground.is_empty():
			ground = state
	if not has_seed:
		return _fail("there's nothing to plant")
	if ground.is_empty() or not _done_has(ground, "dig"):
		return _fail("the ground is too hard")
	if not bool(cond.get("water", false)):
		return _fail("it needs water")
	return _res(WORKED, "", _make(ins, "plant", {}, "crop"))


static func _grow(ins: Array, cond: Dictionary) -> Dictionary:
	var s: Dictionary = ins[0]
	if _form(s) != "crop":
		return _fail("there is nothing to grow")
	if int(cond.get("days", 0)) < _n("grow", "days"):
		return _fail("it isn't ready yet")
	if not bool(cond.get("water", false)):
		return _fail("it dried up")
	if not bool(cond.get("sun", false)):
		return _fail("it's too dark for it")
	return _res(WORKED, "", _make(ins, "grow", {"rots": _n("grow", "food_rots")}, "food"))


static func _cook(ins: Array, heat: int) -> Dictionary:
	var s: Dictionary = ins[0]
	if _form(s) != "food":
		return _fail("there is nothing to cook")
	if heat < _n("cook", "heat"):
		return _fail("it needs a fire")
	var made: Dictionary = _make(ins, "cook", {"rots": _n("cook", "meal_rots")}, "meal")
	if heat >= _n("cook", "burn_heat"):
		return _res(BADLY, "it burned", made)
	return _res(WORKED, "", made)


static func _make_fire(ins: Array, tool: Dictionary) -> Dictionary:
	if int(abilities(tool)["drill"]) < 1:
		return _fail("it smoked but never caught")
	var burns: int = _n("make_fire", "burns")
	var tinder: Dictionary = ins[0]
	if _lv(tinder, "burns") < burns:
		return _fail("the tinder was damp")
	var fuel: Dictionary = {}
	if ins.size() >= 3:
		fuel = ins[2]
	if _lv(fuel, "burns") < burns:
		return _fail("it went out")
	return _res(WORKED, "", _make(ins, "make_fire", {}, "fire"))


# --- buildings --------------------------------------------------------------

# How a building is judged. design = {"purpose": [String], "size": [w, d],
# "parts": {"walls": state, "roof": state, "door": state or {},
# "window": {"opening": bool}, "fittings": [{"kind", "item"}]}}.
# Returns {"outcome", "reasons": [String], "does": {purpose: bool}}.
static func judge(design: Dictionary) -> Dictionary:
	var purposes: Array = design.get("purpose", [])
	var size: Array = design.get("size", [0, 0])
	var span: int = mini(int(size[0]), int(size[1]))
	var parts: Dictionary = design.get("parts", {})
	var walls: Dictionary = parts.get("walls", {})
	var roof: Dictionary = parts.get("roof", {})
	var door: Dictionary = parts.get("door", {})
	var window: Dictionary = parts.get("window", {})
	var fittings: Array = parts.get("fittings", [])
	var reasons: Array = []
	var badly := false

	var stands := true
	if walls.is_empty() or _form(walls) != "wall" or _lv(walls, "strong") < 1:
		stands = false
		_add_reason(reasons, "it has no walls to stand on")
	if not roof.is_empty():
		var roof_parts: Array = roof.get("parts", [])
		var backing: Dictionary = {}
		if roof_parts.size() >= 2:
			backing = roof_parts[1]
		if _lv(backing, "strong") < span - 1:
			stands = false
			_add_reason(reasons, "too weak for the span")
		if not walls.is_empty() and span >= 3 and _lv(walls, "strong") < 2:
			stands = false
			_add_reason(reasons, "the walls are too weak to hold the roof")

	var does := {}
	if purposes.has("dry"):
		var ok := stands
		if roof.is_empty() or _form(roof) != "roof":
			ok = false
			_add_reason(reasons, "nothing keeps the rain off")
		else:
			if _lv(roof, "waterproof") < 2:
				ok = false
				_add_reason(reasons, "not waterproof")
			if int(roof.get("layers", 0)) < span + 2:
				ok = false
				_add_reason(reasons, "too thin for its span")
		if _lv(walls, "waterproof") < 1:
			badly = true
			_add_reason(reasons, "the rain blows in through the walls")
		does["dry"] = ok
	if purposes.has("warm"):
		var ok := stands
		var has_fire := false
		for fitting_variant in fittings:
			var fitting: Dictionary = fitting_variant
			if str(fitting.get("kind", "")) == "hearth":
				var item: Dictionary = fitting.get("item", {})
				if int(abilities(item)["heat"]) >= 2:
					has_fire = true
		if not has_fire:
			ok = false
			_add_reason(reasons, "no fire")
		if _lv(walls, "holds_heat") < 1:
			ok = false
			_add_reason(reasons, "the walls let the heat out")
		if door.is_empty():
			ok = false
			_add_reason(reasons, "the cold comes in at the door")
		if roof.is_empty():
			ok = false
			_add_reason(reasons, "the heat goes straight up")
		does["warm"] = ok
	if purposes.has("storage"):
		var ok := stands
		var has_place := false
		for fitting_variant in fittings:
			var fitting: Dictionary = fitting_variant
			var kind: String = str(fitting.get("kind", ""))
			var item: Dictionary = fitting.get("item", {})
			if ["shelf", "basket", "pot"].has(kind) and _form(item) == kind:
				has_place = true
		if not has_place:
			ok = false
			_add_reason(reasons, "nowhere to put things")
		does["storage"] = ok
	if purposes.has("light"):
		var ok := stands
		if not bool(window.get("opening", false)):
			ok = false
			_add_reason(reasons, "no way for light to get in")
		does["light"] = ok

	var failed: bool = not stands
	for purpose in does.keys():
		if not bool(does[purpose]):
			failed = true
	var outcome := WORKED
	if failed:
		outcome = FAILED
	elif badly:
		outcome = BADLY
	return {"outcome": outcome, "reasons": reasons, "does": does}


static func _add_reason(reasons: Array, reason: String) -> void:
	if not reasons.has(reason):
		reasons.append(reason)
