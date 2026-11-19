extends Node

# Plan 14 step 3a: the world's rules (WorldRules). The data, the twenty ways of
# working with every reason they give, what tools can do, how a building is
# judged, and the basics check: shelter, warmth and storage are reachable from
# what the starting land provides. Pure data in, pure data out; nothing here
# touches AppState or the disk.

const WorldRules = preload("res://scripts/services/world_rules.gd")
const LandData = preload("res://scripts/services/land_data.gd")

const EXPECTED_WAYS := ["gather", "cut", "dig", "split", "carve", "grind", "shape", "dry", "fire", "twist",
	"weave", "bind", "mix", "stack", "layer", "join", "plant", "grow", "cook", "make_fire"]

var _failed := 0
var _ran := 0
# The first thing that went wrong while a path was being walked.
var _path_err := ""


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("world_rules_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("world_rules_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("data_well_formed", func(): return _test_data())
	_case("every_way_works_and_says_why_not", func(): return _test_every_way())
	_case("the_plans_example", func(): return _test_plans_example())
	_case("tools_come_from_properties", func(): return _test_tools())
	_case("buildings_are_judged", func(): return _test_buildings())
	_case("the_basics_check", func(): return _test_basics())
	_case("nothing_is_changed_in_place", func(): return _test_no_change())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	_path_err = ""
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("world_rules_test[%s]: %s" % [name, err])
	else:
		print("world_rules_test[%s]: ok" % name)


# --- helpers -------------------------------------------------------------

func _r(id: String) -> Dictionary:
	return WorldRules.raw(id)


# One step of a path: it has to work, and its product comes back. The first
# failure is remembered in _path_err.
func _step(label: String, way: String, inputs: Array, tool: Dictionary = {}, cond: Dictionary = {}) -> Dictionary:
	var res: Dictionary = WorldRules.work(way, inputs, tool, cond)
	if str(res["outcome"]) != "worked":
		if _path_err == "":
			_path_err = "%s: %s, %s" % [label, res["outcome"], res["reason"]]
		return {}
	return res["product"]


# A raw material, only if the land gives it.
func _land(id: String) -> Dictionary:
	if not WorldRules.land_materials().has(id):
		if _path_err == "":
			_path_err = "the land does not give %s" % id
		return {}
	return WorldRules.raw(id)


func _state(of: Array, props: Dictionary, form: String = "") -> Dictionary:
	return {"of": of, "props": props, "form": form, "done": [], "parts": [], "layers": 0}


# What one call gives, as {"outcome", "reason"}.
func _call(way: String, inputs: Array, tool: Dictionary = {}, cond: Dictionary = {}) -> Dictionary:
	return WorldRules.work(way, inputs, tool, cond)


# Each row: [label, way, inputs, tool, conditions, outcome, reason].
func _check_rows(rows: Array) -> String:
	for row_variant in rows:
		var row: Array = row_variant
		var res: Dictionary = _call(str(row[1]), row[2], row[3], row[4])
		if str(res["outcome"]) != str(row[5]) or str(res["reason"]) != str(row[6]):
			return "%s: expected %s '%s', got %s '%s'" % [row[0], row[5], row[6], res["outcome"], res["reason"]]
		var product: Dictionary = res["product"]
		if str(res["outcome"]) == "failed" and not product.is_empty():
			return "%s: a failure should have no product" % row[0]
		if str(res["outcome"]) != "failed" and product.is_empty():
			return "%s: a success should have a product" % row[0]
	return ""


# The things the paths and cases build on, made with the rules themselves.
func _kit() -> Dictionary:
	var stone: Dictionary = _r("stone")
	var flake: Dictionary = _step("flake", "split", [_r("flint")], stone)
	var point: Dictionary = _step("point", "carve", [_r("stick")], flake, {"form": "point"})
	var cord: Dictionary = _step("cord", "twist", [_step("bundle", "cut", [_r("nettle")], flake)])
	var handled: Dictionary = _step("handled", "bind", [flake, _r("stick"), cord])
	var drill: Dictionary = _step("drill", "bind", [_r("stick"), _r("stick"), cord], {}, {"form": "drill"})
	var panel: Dictionary = _step("panel", "weave", [_r("stick"), _r("stick")])
	var pole: Dictionary = _step("pole", "cut", [_r("stick")], flake)
	var frame: Dictionary = _step("frame", "bind", [pole, pole, cord], {}, {"form": "frame"})
	return {"stone": stone, "flake": flake, "point": point, "cord": cord, "handled": handled, "drill": drill,
		"panel": panel, "pole": pole, "frame": frame}


# The wattle-and-daub walls and the reed roof of the shelter path.
func _shelter(kit: Dictionary) -> Dictionary:
	var flake: Dictionary = kit["flake"]
	var point: Dictionary = kit["point"]
	var clay: Dictionary = _step("dig clay", "dig", [_land("clay")], point)
	var mix: Dictionary = _step("mix", "mix", [clay, _land("grass")], {}, {"water": true})
	var wall: Dictionary = _step("wall", "layer", [mix, kit["panel"]])
	var reeds: Dictionary = _step("dry reeds", "dry", [_step("cut reeds", "cut", [_land("reed")], flake)],
			{}, {"sun": true, "days": 2})
	var roof: Dictionary = _step("roof", "layer", [reeds, kit["frame"]], {}, {"layers": 4})
	return {"wall": wall, "roof": roof}


func _design(purposes: Array, size: Array, walls: Dictionary, roof: Dictionary, door: Dictionary = {},
		window: bool = false, fittings: Array = []) -> Dictionary:
	return {"purpose": purposes, "size": size, "parts": {"walls": walls, "roof": roof, "door": door,
		"window": {"opening": window}, "fittings": fittings}}


func _with_props(state: Dictionary, changes: Dictionary) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	var props: Dictionary = out["props"]
	for key in changes.keys():
		if int(changes[key]) == 0:
			props.erase(key)
		else:
			props[key] = changes[key]
	return out


# --- cases ---------------------------------------------------------------

func _test_data() -> Variant:
	if WorldRules.PROPERTIES.size() != 13:
		return "expected 13 properties, got %d" % WorldRules.PROPERTIES.size()
	for prop in WorldRules.PROPERTIES:
		if str(WorldRules.PROPERTY_MEANINGS.get(prop, "")).strip_edges() == "":
			return "property %s has no meaning" % prop
	var ways: Array = WorldRules.WAYS.keys()
	if ways != EXPECTED_WAYS:
		return "the ways are %s" % str(ways)
	for way in ways:
		var entry: Dictionary = WorldRules.WAYS[way]
		if str(entry.get("label", "")).strip_edges() == "":
			return "way %s has no label" % way
	var place_ids := {}
	for place_variant in (LandData.LAND as Dictionary).get("places", []):
		var place: Dictionary = place_variant
		place_ids[str(place.get("id", ""))] = true
	for id in WorldRules.RAW.keys():
		var entry: Dictionary = WorldRules.RAW[id]
		var props: Dictionary = entry["props"]
		for prop in props.keys():
			if not WorldRules.PROPERTIES.has(prop):
				return "%s has an unknown property %s" % [id, prop]
			var level: int = int(props[prop])
			if level < 0 or level > 3:
				return "%s.%s is %d, outside 0..3" % [id, prop, level]
		var get_way: String = str(entry["get"])
		if get_way != "draw" and not WorldRules.WAYS.has(get_way):
			return "%s is got by %s, which is not a way" % [id, get_way]
		var places: Array = entry["places"]
		for place_id in places:
			if not place_ids.has(place_id):
				return "%s lies at %s, which is not on the land" % [id, place_id]
	if WorldRules.raw("moonrock") != {}:
		return "an unknown raw should be {}"
	return ""


func _test_every_way() -> Variant:
	var kit: Dictionary = _kit()
	if _path_err != "":
		return "kit: " + _path_err
	var stone: Dictionary = kit["stone"]
	var flake: Dictionary = kit["flake"]
	var point: Dictionary = kit["point"]
	var cord: Dictionary = kit["cord"]
	var handled: Dictionary = kit["handled"]
	var drill: Dictionary = kit["drill"]
	var panel: Dictionary = kit["panel"]
	var frame: Dictionary = kit["frame"]
	var pole: Dictionary = kit["pole"]
	var dry_pot: Dictionary = _step("dry pot", "dry", [_step("pot", "shape", [_step("mix", "mix", [_r("clay"), _r("sand")], {}, {"water": true})], {}, {"water": true, "form": "pot"})], {}, {"sun": true, "days": 2})
	var dug_earth: Dictionary = _step("dug earth", "dig", [_r("earth")], point)
	var crop: Dictionary = _step("crop", "plant", [_r("seed"), dug_earth], {}, {"water": true})
	var food: Dictionary = _step("food", "grow", [crop], {}, {"days": 20, "water": true, "sun": true})
	var dry_grass: Dictionary = _step("dry grass", "dry", [_r("grass")], {}, {"sun": true, "days": 2})
	var brittle_thing: Dictionary = _state(["flint"], {"hard": 1, "brittle": 2})
	var rows: Array = [
		["unknown way", "juggle", [_r("stick")], {}, {}, "failed", "I don't know how to do that"],
		["no inputs", "gather", [], {}, {}, "failed", "there is nothing to work"],
		["gather", "gather", [_r("grass")], {}, {}, "worked", ""],
		["gather, not by hand", "gather", [_r("clay")], {}, {}, "failed", "it won't come away by hand"],
		["cut", "cut", [_r("nettle")], flake, {}, "worked", ""],
		["cut, bare hands", "cut", [_r("nettle")], {}, {}, "failed", "nothing sharp enough to cut it"],
		["cut, a heavy blow", "cut", [_r("log")], flake, {}, "failed", "it needs a heavier blow"],
		["dig", "dig", [_r("clay")], point, {}, "worked", ""],
		["dig, bare hands", "dig", [_r("clay")], {}, {}, "failed", "the ground is too hard for bare hands"],
		["dig, not earth", "dig", [_r("stick")], point, {}, "failed", "there is nothing to dig there"],
		["split", "split", [_r("flint")], stone, {}, "worked", ""],
		["split, rough", "split", [_r("stone")], stone, {}, "badly", "it split, but the edge is rough"],
		["split a log", "split", [_r("log")], handled, {}, "worked", ""],
		["split, bounced", "split", [_r("flint")], {}, {}, "failed", "it just bounced off"],
		["split, no edge", "split", [_r("log")], stone, {}, "failed", "it needs something to drive into it"],
		["split, dented", "split", [_r("clay")], stone, {}, "failed", "it dented but didn't split"],
		["carve", "carve", [_r("stick")], flake, {"form": "bowl"}, "worked", ""],
		["carve, no bite", "carve", [_r("stick")], {}, {}, "failed", "the edge won't bite"],
		["carve, cracked", "carve", [brittle_thing], flake, {}, "failed", "it cracked"],
		["carve, soft", "carve", [_r("clay")], flake, {}, "failed", "it is too soft to carve"],
		["grind", "grind", [_r("flint")], stone, {}, "worked", ""],
		["grind, nothing to rub on", "grind", [_r("flint")], {}, {}, "failed", "there is nothing hard enough to rub it on"],
		["grind, wears away", "grind", [_r("stick")], stone, {}, "failed", "it wears away instead of sharpening"],
		["shape", "shape", [_r("clay")], {}, {"water": true}, "worked", ""],
		["shape, dry", "shape", [_r("clay")], {}, {}, "failed", "it crumbles"],
		["shape, no hold", "shape", [_r("earth")], {}, {"water": true}, "failed", "it won't hold a shape"],
		["dry", "dry", [_r("clay")], {}, {"sun": true, "days": 2}, "worked", ""],
		["dry, wet", "dry", [_r("clay")], {}, {"days": 5}, "failed", "it got wet again"],
		["dry, too soon", "dry", [_r("clay")], {}, {"sun": true, "days": 1}, "failed", "it isn't dry yet"],
		["dry, brick falls apart", "dry", [_step("brick", "shape", [_r("clay")], {}, {"water": true})], {}, {"sun": true, "days": 3}, "failed", "it fell apart while drying"],
		["dry, brick takes three days", "dry", [_step("brick", "shape", [_r("clay")], {}, {"water": true})], {}, {"sun": true, "days": 2}, "failed", "it isn't dry yet"],
		["dry, pot cracks", "dry", [_step("pot", "shape", [_r("clay")], {}, {"water": true, "form": "pot"})], {}, {"sun": true, "days": 2}, "badly", "it cracked while it dried"],
		["dry, by a fire", "dry", [_r("grass")], {}, {"heat": 2, "days": 2}, "worked", ""],
		["fire", "fire", [dry_pot], {}, {"heat": 3}, "worked", ""],
		["fire, burst", "fire", [_r("clay")], {}, {"heat": 3}, "failed", "it burst in the fire"],
		["fire, burned away", "fire", [_r("grass")], {}, {"heat": 3}, "failed", "it burned away"],
		["fire, half hot", "fire", [dry_pot], {}, {"heat": 2}, "badly", "not hot enough"],
		["fire, cold", "fire", [dry_pot], {}, {"heat": 1}, "failed", "not hot enough"],
		["fire, glass", "fire", [_r("sand")], {}, {"heat": 4}, "worked", ""],
		["fire, sand too cool", "fire", [_r("sand")], {}, {"heat": 3}, "failed", "not hot enough"],
		["fire, nothing changed", "fire", [_r("stone")], {}, {"heat": 3}, "failed", "nothing changed"],
		["twist", "twist", [_r("grass")], {}, {}, "worked", ""],
		["twist, too short", "twist", [_r("stick")], {}, {}, "failed", "the threads are too short to twist"],
		["weave", "weave", [_r("grass")], {}, {"form": "basket"}, "worked", ""],
		["weave, snaps", "weave", [_r("stone")], {}, {}, "failed", "it snapped when I bent it"],
		["bind a tool", "bind", [flake, _r("stick"), cord], {}, {}, "worked", ""],
		["bind a frame", "bind", [pole, pole, cord], {}, {"form": "frame"}, "worked", ""],
		["bind a drill", "bind", [_r("stick"), _r("stick"), cord], {}, {"form": "drill"}, "worked", ""],
		["bind, no cord", "bind", [flake, _r("stick")], {}, {}, "failed", "nothing to bind it with"],
		["bind, no handle", "bind", [flake, cord], {}, {}, "failed", "there is no handle to fix it to"],
		["bind, no head", "bind", [_r("stick"), _r("stick"), cord], {}, {}, "failed", "there is nothing sharp or heavy to fix on it"],
		["bind, one pole", "bind", [pole, cord], {}, {"form": "frame"}, "failed", "the pieces won't hold together"],
		["bind, one stick", "bind", [_r("stick"), cord], {}, {"form": "drill"}, "failed", "the pieces won't hold together"],
		["mix", "mix", [_r("clay"), _r("grass")], {}, {"water": true}, "worked", ""],
		["mix, dry", "mix", [_r("clay"), _r("grass")], {}, {}, "failed", "it's too dry to mix"],
		["mix, nothing sticks", "mix", [_r("stick"), _r("grass")], {}, {"water": true}, "failed", "there's nothing in it that sticks"],
		["stack", "stack", [_r("stone")], {}, {}, "worked", ""],
		["stack a kiln", "stack", [_r("stone")], {}, {"around_fire": true}, "worked", ""],
		["stack, soft", "stack", [_r("grass")], {}, {}, "failed", "it's too soft to stack"],
		["stack, won't sit", "stack", [handled], {}, {}, "failed", "it won't sit still"],
		["layer a roof", "layer", [dry_grass, frame], {}, {"layers": 4}, "worked", ""],
		["layer a wall", "layer", [_step("mix", "mix", [_r("clay")], {}, {"water": true}), panel], {}, {}, "worked", ""],
		["layer, nothing under", "layer", [dry_grass], {}, {}, "failed", "it slid off; it needs something under it"],
		["layer, laid wet", "layer", [_r("grass"), frame], {}, {"layers": 4}, "badly", "it was laid wet and will rot"],
		["join", "join", [pole, pole], flake, {}, "worked", ""],
		["join, no edge", "join", [pole, pole], {}, {}, "failed", "the pieces won't hold together"],
		["join, one piece", "join", [pole], flake, {}, "failed", "the pieces won't hold together"],
		["plant", "plant", [_r("seed"), dug_earth], {}, {"water": true}, "worked", ""],
		["plant, no seed", "plant", [dug_earth], {}, {"water": true}, "failed", "there's nothing to plant"],
		["plant, undug", "plant", [_r("seed"), _r("earth")], {}, {"water": true}, "failed", "the ground is too hard"],
		["plant, no water", "plant", [_r("seed"), dug_earth], {}, {}, "failed", "it needs water"],
		["grow", "grow", [crop], {}, {"days": 20, "water": true, "sun": true}, "worked", ""],
		["grow, too soon", "grow", [crop], {}, {"days": 5, "water": true, "sun": true}, "failed", "it isn't ready yet"],
		["grow, dried up", "grow", [crop], {}, {"days": 20, "sun": true}, "failed", "it dried up"],
		["grow, dark", "grow", [crop], {}, {"days": 20, "water": true}, "failed", "it's too dark for it"],
		["cook", "cook", [food], {}, {"heat": 2}, "worked", ""],
		["cook, burned", "cook", [food], {}, {"heat": 3}, "badly", "it burned"],
		["cook, no fire", "cook", [food], {}, {}, "failed", "it needs a fire"],
		["make a fire", "make_fire", [dry_grass, _r("stick"), _r("log")], drill, {}, "worked", ""],
		["fire, never caught", "make_fire", [dry_grass, _r("stick"), _r("log")], {}, {}, "failed", "it smoked but never caught"],
		["fire, damp tinder", "make_fire", [_r("grass"), _r("stick"), _r("log")], drill, {}, "failed", "the tinder was damp"],
		["fire, went out", "make_fire", [dry_grass, _r("stick"), _r("stick")], drill, {}, "failed", "it went out"],
	]
	if _path_err != "":
		return "setup: " + _path_err
	var seen := {}
	for row_variant in rows:
		seen[str((row_variant as Array)[1])] = true
	for way in EXPECTED_WAYS:
		if not seen.has(way):
			return "no row for the way %s" % way
	var err: String = _check_rows(rows)
	if err != "":
		return err
	return ""


func _test_plans_example() -> Variant:
	var mix: Dictionary = _step("mix", "mix", [_r("clay"), _r("sand")], {}, {"water": true})
	var pot: Dictionary = _step("pot", "shape", [mix], {}, {"water": true, "form": "pot"})
	var dried: Dictionary = _step("dried", "dry", [pot], {}, {"sun": true, "days": 2})
	if _path_err != "":
		return _path_err
	if int((dried["props"] as Dictionary).get("hard", 0)) != 2 or int((dried["props"] as Dictionary).get("waterproof", 0)) != 0:
		return "a dried pot should be hard 2, waterproof 0, got %s" % str(dried["props"])
	var fired: Dictionary = _call("fire", [dried], {}, {"heat": 3})
	if str(fired["outcome"]) != "worked":
		return "firing at heat 3: %s" % str(fired)
	var props: Dictionary = fired["product"]["props"]
	if int(props.get("hard", 0)) != 3 or int(props.get("waterproof", 0)) != 2 or int(props.get("brittle", 0)) != 2:
		return "a fired pot should be hard 3, waterproof 2, brittle 2, got %s" % str(props)
	var half: Dictionary = _call("fire", [dried], {}, {"heat": 2})
	if str(half["outcome"]) != "badly" or str(half["reason"]) != "not hot enough":
		return "firing at heat 2: %s" % str(half)
	var brick: Dictionary = _step("brick", "shape", [_r("clay")], {}, {"water": true})
	var bad: Dictionary = _call("dry", [brick], {}, {"sun": true, "days": 3})
	if str(bad["outcome"]) != "failed" or str(bad["reason"]) != "it fell apart while drying":
		return "untempered brick: %s" % str(bad)
	return ""


func _test_tools() -> Variant:
	var kit: Dictionary = _kit()
	if _path_err != "":
		return "kit: " + _path_err
	var hands: Dictionary = WorldRules.abilities({})
	for key in hands.keys():
		if int(hands[key]) != 0:
			return "bare hands should have no %s" % key
	var stone: Dictionary = WorldRules.abilities(_r("stone"))
	if int(stone["striker"]) != 2:
		return "a stone should strike 2, got %s" % str(stone)
	var flake: Dictionary = WorldRules.abilities(kit["flake"])
	if int(flake["edge"]) != 2 or int(flake["digger"]) != 1 or int(flake["striker"]) != 1:
		return "a flake should be edge 2, digger 1, striker 1, got %s" % str(flake)
	var point: Dictionary = WorldRules.abilities(kit["point"])
	if int(point["digger"]) != 1:
		return "a pointed stick should dig 1, got %s" % str(point)
	var tool: Dictionary = WorldRules.abilities(kit["handled"])
	if int(tool["edge"]) != 2 or int(tool["digger"]) != 2 or int(tool["striker"]) != 2:
		return "a flake on a handle should be edge 2, digger 2, striker 2, got %s" % str(tool)
	var drill: Dictionary = WorldRules.abilities(kit["drill"])
	if int(drill["drill"]) != 1:
		return "a drill should drill 1, got %s" % str(drill)
	var fire: Dictionary = _step("fire", "make_fire", [_step("tinder", "dry", [_r("grass")], {}, {"sun": true, "days": 2}), _r("stick"), _r("log")], kit["drill"])
	if int(WorldRules.abilities(fire)["heat"]) != 2:
		return "a fire should give heat 2"
	var kiln: Dictionary = _step("kiln", "stack", [_r("stone")], {}, {"around_fire": true})
	if int(WorldRules.abilities(kiln)["heat"]) != 3:
		return "a kiln should give heat 3"
	if _path_err != "":
		return _path_err
	var bare: Dictionary = _call("cut", [_r("log")], kit["flake"])
	if str(bare["outcome"]) != "failed" or str(bare["reason"]) != "it needs a heavier blow":
		return "a bare flake on a log: %s" % str(bare)
	var swung: Dictionary = _call("cut", [_r("log")], kit["handled"])
	if str(swung["outcome"]) != "worked":
		return "a flake on a handle on a log: %s" % str(swung)
	return ""


func _test_buildings() -> Variant:
	var kit: Dictionary = _kit()
	var built: Dictionary = _shelter(kit)
	var wall: Dictionary = built["wall"]
	var roof: Dictionary = built["roof"]
	var door: Dictionary = kit["panel"]
	var grass: Dictionary = _step("basket", "weave", [_r("grass")], {}, {"form": "basket"})
	var stone_wall: Dictionary = _step("stone wall", "stack", [_r("stone")])
	var fire: Dictionary = _step("fire", "make_fire", [_step("tinder", "dry", [_r("grass")], {}, {"sun": true, "days": 2}), _r("stick"), _r("log")], kit["drill"])
	if _path_err != "":
		return _path_err
	var hearth: Array = [{"kind": "hearth", "item": fire}]
	var basket: Array = [{"kind": "basket", "item": grass}]
	var cases: Array = [
		["all four purposes", _design(["dry", "warm", "storage", "light"], [2, 2], wall, roof, door, true, hearth + basket), "worked", ""],
		["no walls", _design([], [2, 2], {}, roof), "failed", "it has no walls to stand on"],
		["span", _design([], [4, 4], wall, roof), "failed", "too weak for the span"],
		["weak walls", _design([], [3, 3], _with_props(wall, {"strong": 1}), _with_props_parts(roof, 1)), "failed", "the walls are too weak to hold the roof"],
		["no roof for rain", _design(["dry"], [2, 2], wall, {}), "failed", "nothing keeps the rain off"],
		["not waterproof", _design(["dry"], [2, 2], wall, _with_props(roof, {"waterproof": 1})), "failed", "not waterproof"],
		["too thin", _design(["dry"], [2, 2], wall, _with_layers(roof, 2)), "failed", "too thin for its span"],
		["rain blows in", _design(["dry"], [2, 2], stone_wall, roof), "badly", "the rain blows in through the walls"],
		["no fire", _design(["warm"], [2, 2], wall, roof, door), "failed", "no fire"],
		["heat leaks", _design(["warm"], [2, 2], _with_props(wall, {"holds_heat": 0}), roof, door, false, hearth), "failed", "the walls let the heat out"],
		["cold at the door", _design(["warm"], [2, 2], wall, roof, {}, false, hearth), "failed", "the cold comes in at the door"],
		["heat goes up", _design(["warm"], [2, 2], wall, {}, door, false, hearth), "failed", "the heat goes straight up"],
		["nowhere to put things", _design(["storage"], [2, 2], wall, roof), "failed", "nowhere to put things"],
		["no window", _design(["light"], [2, 2], wall, roof), "failed", "no way for light to get in"],
		["a basket is storage", _design(["storage"], [2, 2], wall, roof, {}, false, basket), "worked", ""],
		["warm", _design(["warm"], [2, 2], wall, roof, door, false, hearth), "worked", ""],
	]
	for case_variant in cases:
		var row: Array = case_variant
		var verdict: Dictionary = WorldRules.judge(row[1])
		if str(verdict["outcome"]) != str(row[2]):
			return "%s: expected %s, got %s %s" % [row[0], row[2], verdict["outcome"], str(verdict["reasons"])]
		var reasons: Array = verdict["reasons"]
		if str(row[3]) != "" and not reasons.has(str(row[3])):
			return "%s: expected the reason '%s', got %s" % [row[0], row[3], str(reasons)]
		if str(row[3]) == "" and not reasons.is_empty():
			return "%s: expected no reasons, got %s" % [row[0], str(reasons)]
	# A failure in one purpose leaves the others done.
	var mixed: Dictionary = WorldRules.judge(_design(["storage", "light"], [2, 2], wall, roof, {}, false, basket))
	var does: Dictionary = mixed["does"]
	if not bool(does["storage"]) or bool(does["light"]):
		return "storage should be done and light not, got %s" % str(does)
	var listed: Dictionary = WorldRules.judge(_design(["dry"], [2, 2], wall, roof))["does"]
	if listed.size() != 1 or not listed.has("dry"):
		return "does should have only the listed purposes, got %s" % str(listed)
	return ""


# A copy of a roof whose backing has a different strength.
func _with_props_parts(roof: Dictionary, strong: int) -> Dictionary:
	var out: Dictionary = roof.duplicate(true)
	var parts: Array = out["parts"]
	parts[1] = _with_props(parts[1], {"strong": strong})
	return out


func _with_layers(roof: Dictionary, layers: int) -> Dictionary:
	var out: Dictionary = roof.duplicate(true)
	out["layers"] = layers
	return out


# Shelter, warmth and storage, walked step by step from what the land gives.
func _test_basics() -> Variant:
	if WorldRules.land_materials().is_empty():
		return "the land gives nothing"
	# Shelter.
	var stone: Dictionary = _land("stone")
	var flint: Dictionary = _land("flint")
	var flake: Dictionary = _step("split the flint", "split", [flint], stone)
	var stick: Dictionary = _land("stick")
	var point: Dictionary = _step("carve a digging stick", "carve", [stick], flake, {"form": "point"})
	var nettle_bundle: Dictionary = _step("cut nettles", "cut", [_land("nettle")], flake)
	var cord: Dictionary = _step("twist cord", "twist", [nettle_bundle])
	var pole: Dictionary = _step("cut a pole", "cut", [stick], flake)
	var frame: Dictionary = _step("bind a frame", "bind", [pole, pole, cord], {}, {"form": "frame"})
	var panel: Dictionary = _step("weave a panel", "weave", [stick, stick])
	var earth: Dictionary = _step("dig earth", "dig", [_land("earth")], point)
	var clay: Dictionary = _step("dig clay", "dig", [_land("clay")], point)
	var grass: Dictionary = _land("grass")
	var mix: Dictionary = _step("mix clay and grass", "mix", [clay, _step("gather grass", "gather", [grass])], {}, {"water": true})
	var wall: Dictionary = _step("daub the panel", "layer", [mix, panel])
	var reeds: Dictionary = _step("cut reeds", "cut", [_land("reed")], flake)
	var dry_reeds: Dictionary = _step("dry reeds", "dry", [reeds], {}, {"sun": true, "days": 2})
	var roof: Dictionary = _step("thatch the frame", "layer", [dry_reeds, frame], {}, {"layers": 4})
	if _path_err != "":
		return "shelter: " + _path_err
	if earth.is_empty():
		return "shelter: no earth"
	var shelter: Dictionary = WorldRules.judge(_design(["dry"], [2, 2], wall, roof))
	if str(shelter["outcome"]) != "worked" or not bool((shelter["does"] as Dictionary)["dry"]):
		return "shelter: %s" % str(shelter)
	# Storage, in the same walls.
	var basket: Dictionary = _step("weave a basket", "weave", [_step("gather grass", "gather", [grass])], {}, {"form": "basket"})
	if _path_err != "":
		return "storage: " + _path_err
	var storage: Dictionary = WorldRules.judge(_design(["storage"], [2, 2], wall, roof, {}, false,
			[{"kind": "basket", "item": basket}]))
	if str(storage["outcome"]) != "worked" or not bool((storage["does"] as Dictionary)["storage"]):
		return "storage: %s" % str(storage)
	# Warmth.
	var drill: Dictionary = _step("bind a drill", "bind", [stick, stick, cord], {}, {"form": "drill"})
	var tinder: Dictionary = _step("dry the tinder", "dry", [_step("gather grass", "gather", [grass])], {}, {"sun": true, "days": 2})
	var log: Dictionary = _step("gather a log", "gather", [_land("log")])
	var fire: Dictionary = _step("light a fire", "make_fire", [tinder, stick, log], drill)
	var door: Dictionary = _step("weave a door", "weave", [stick, stick])
	if _path_err != "":
		return "warmth: " + _path_err
	var warm: Dictionary = WorldRules.judge(_design(["warm"], [2, 2], wall, roof, door, false,
			[{"kind": "hearth", "item": fire}]))
	if str(warm["outcome"]) != "worked" or not bool((warm["does"] as Dictionary)["warm"]):
		return "warmth: %s" % str(warm)
	return ""


func _test_no_change() -> Variant:
	var kit: Dictionary = _kit()
	var built: Dictionary = _shelter(kit)
	if _path_err != "":
		return _path_err
	var wall: Dictionary = built["wall"]
	var roof: Dictionary = built["roof"]
	var calls: Array = [
		["split", [_r("flint")], kit["stone"], {}],
		["cut", [_r("nettle")], kit["flake"], {}],
		["bind", [kit["flake"], _r("stick"), kit["cord"]], {}, {}],
		["mix", [_r("clay"), _r("grass")], {}, {"water": true}],
		["layer", [_r("reed"), kit["frame"]], {}, {"layers": 4}],
		["dry", [_r("clay")], {}, {"sun": true, "days": 2, "form": "pot"}],
		["join", [kit["pole"], kit["pole"]], kit["flake"], {"form": "door"}],
	]
	for call_variant in calls:
		var row: Array = call_variant
		var inputs_before: String = var_to_str(row[1])
		var tool_before: String = var_to_str(row[2])
		var cond_before: String = var_to_str(row[3])
		var first: Dictionary = _call(str(row[0]), row[1], row[2], row[3])
		if var_to_str(row[1]) != inputs_before or var_to_str(row[2]) != tool_before or var_to_str(row[3]) != cond_before:
			return "%s changed what it was given" % row[0]
		var second: Dictionary = _call(str(row[0]), row[1], row[2], row[3])
		if var_to_str(first) != var_to_str(second):
			return "%s gave a different answer the second time" % row[0]
		# Changing the product must not reach back into the inputs.
		var product: Dictionary = first["product"]
		if not product.is_empty():
			(product["props"] as Dictionary)["hard"] = 99
			(product["parts"] as Array).append("x")
			if var_to_str(row[1]) != inputs_before:
				return "%s's product shares its inputs" % row[0]
	var design: Dictionary = _design(["dry", "warm"], [2, 2], wall, roof)
	var design_before: String = var_to_str(design)
	var once: Dictionary = WorldRules.judge(design)
	if var_to_str(design) != design_before:
		return "judge changed the design"
	if var_to_str(once) != var_to_str(WorldRules.judge(design)):
		return "judge gave a different answer the second time"
	var raw_a: Dictionary = _r("stone")
	(raw_a["props"] as Dictionary)["hard"] = 0
	if int((_r("stone")["props"] as Dictionary)["hard"]) != 3:
		return "raw() hands out the table itself"
	return ""
