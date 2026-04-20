extends Node

const EconomyService = preload("res://scripts/services/economy_service.gd")

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("economy_tuning_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("economy_tuning_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("duplicate_recycle_capped_by_cost", func(): return _test_duplicate_recycle_capped_by_cost())
	_case("low_value_streak_protection", func(): return _test_low_value_streak_protection())
	_case("theme_open_stats_recorded", func(): return _test_theme_open_stats_recorded())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("economy_tuning_test[%s]: %s" % [name, err])
	else:
		print("economy_tuning_test[%s]: ok" % name)


func _base_manifest() -> Dictionary:
	return {
		"items": [
			{
				"id": "common_a",
				"name": "Common A",
				"category": "food",
				"rarity": "common",
				"primaryTheme": "cozy",
			},
			{
				"id": "uncommon_b",
				"name": "Uncommon B",
				"category": "food",
				"rarity": "uncommon",
				"primaryTheme": "cozy",
			},
		],
		"rewardBoxes": [
			{
				"id": "cheap_box",
				"theme": "cozy",
				"cost": 4,
				"possibleItems": ["common_a"],
				"rarityTable": {"common": 100},
			},
			{
				"id": "streak_box",
				"theme": "cozy",
				"cost": 5,
				"possibleItems": ["common_a", "uncommon_b"],
				"rarityTable": {"common": 1000, "uncommon": 1},
			},
		],
	}


func _seed_world() -> Dictionary:
	var svc := EconomyService.new()
	var world := svc.ensure_world_state({})
	world = svc.configure_from_manifest(world, _base_manifest())
	world = svc.grant_crystals(world, "test:seed", 100)
	return world


func _test_duplicate_recycle_capped_by_cost() -> Variant:
	var svc := EconomyService.new()
	var world := _seed_world()
	var catalog: Dictionary = world.get("item_catalog", {})
	world = svc.grant_item(world, "test:seed_item", (catalog["common_a"] as Dictionary).duplicate(true))

	var before_wallet := int((world.get("wallet", {}) as Dictionary).get("crystals", 0))
	var opened := svc.open_reward_box(world, "cheap_box", 111)
	if not bool(opened.get("ok", false)):
		return "box open failed: %s" % [opened]
	if not bool(opened.get("duplicate", false)):
		return "expected duplicate pull for cheap_box"
	var recycle := int(opened.get("recycleCrystals", 0))
	if recycle > 2:
		return "recycle should be capped at 50% cost (2), got %d" % recycle
	var next_world: Dictionary = opened.get("world_state", {})
	var after_wallet := int((next_world.get("wallet", {}) as Dictionary).get("crystals", 0))
	var expected := before_wallet - 4 + recycle
	if after_wallet != expected:
		return "wallet mismatch; expected %d got %d" % [expected, after_wallet]
	return null


func _test_low_value_streak_protection() -> Variant:
	var svc := EconomyService.new()
	var world := _seed_world()
	var seen_non_common := false
	for i in range(6):
		var opened := svc.open_reward_box(world, "streak_box", 2000 + i)
		if not bool(opened.get("ok", false)):
			return "open failed at iter %d: %s" % [i, opened]
		world = opened.get("world_state", {})
		var rarity := str(opened.get("item", {}).get("rarity", "common")).to_lower()
		if rarity != "common":
			seen_non_common = true
			break
	if not seen_non_common:
		return "expected low-value streak protection to emit non-common within 6 opens"
	return null


func _test_theme_open_stats_recorded() -> Variant:
	var svc := EconomyService.new()
	var world := _seed_world()
	for i in range(3):
		var opened := svc.open_reward_box(world, "cheap_box", 500 + i)
		if not bool(opened.get("ok", false)):
			return "open failed: %s" % [opened]
		world = opened.get("world_state", {})
	var snapshot := svc.get_snapshot(world)
	var stats_variant = snapshot.get("box_open_stats", {})
	if typeof(stats_variant) != TYPE_DICTIONARY:
		return "box_open_stats missing"
	var stats: Dictionary = stats_variant
	if not stats.has("cozy") or typeof(stats["cozy"]) != TYPE_DICTIONARY:
		return "cozy theme stats missing: %s" % [stats]
	var cozy_row: Dictionary = stats["cozy"]
	if int(cozy_row.get("opens", 0)) < 3:
		return "expected cozy open count >= 3"
	var rarity_counts_variant = cozy_row.get("rarity_counts", {})
	if typeof(rarity_counts_variant) != TYPE_DICTIONARY:
		return "rarity_counts missing"
	return null
