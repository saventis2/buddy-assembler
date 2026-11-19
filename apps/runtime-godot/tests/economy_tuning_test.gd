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
	_case("drop_table_respects_level_and_grants_item", func(): return _test_drop_table_respects_level_and_grants_item())
	_case("drop_table_job_context_bias", func(): return _test_drop_table_job_context_bias())


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
			{
				"id": "rare_c",
				"name": "Rare C",
				"category": "materials",
				"rarity": "rare",
				"primaryTheme": "heroic",
			},
			{
				"id": "mage_focus_item",
				"name": "Mage Focus Item",
				"category": "gifts",
				"rarity": "uncommon",
				"primaryTheme": "magical",
				"equipSlot": "hat",
				"effectProfile": {"knowledge": 2},
			},
			{
				"id": "warrior_focus_item",
				"name": "Warrior Focus Item",
				"category": "decor",
				"rarity": "uncommon",
				"primaryTheme": "heroic",
				"equipSlot": "weapon",
				"effectProfile": {"strength": 2},
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
		"dropTables": [
			{
				"id": "test_drops",
				"entries": [
					{"itemId": "common_a", "weight": 50, "minLevel": 1},
					{"itemId": "rare_c", "weight": 30, "minLevel": 5, "jobAffinity": "explorer_warrior"},
				],
			},
			{
				"id": "job_bias_drops",
				"entries": [
					{"itemId": "mage_focus_item", "weight": 100, "minLevel": 1, "jobAffinity": "explorer_mage"},
					{"itemId": "warrior_focus_item", "weight": 100, "minLevel": 1, "jobAffinity": "explorer_warrior"},
				],
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


func _test_drop_table_respects_level_and_grants_item() -> Variant:
	var svc := EconomyService.new()
	var world := _seed_world()
	var low_level := svc.roll_drop_table(world, "test_drops", {"level": 1, "job_id": "explorer_warrior"}, 1)
	if not bool(low_level.get("ok", false)):
		return "low-level roll should still succeed with eligible entries"
	var low_item_id := str(low_level.get("item", {}).get("id", ""))
	if low_item_id == "rare_c":
		return "rare_c should be gated by minLevel=5"
	world = low_level.get("world_state", {})

	var high_level := svc.roll_drop_table(world, "test_drops", {"level": 7, "job_id": "explorer_warrior"}, 2)
	if not bool(high_level.get("ok", false)):
		return "high-level roll should succeed: %s" % [high_level]
	world = high_level.get("world_state", {})
	var inventory: Array = world.get("inventory", [])
	if inventory.size() < 2:
		return "expected drop rolls to grant inventory items"
	return null


func _test_drop_table_job_context_bias() -> Variant:
	var svc := EconomyService.new()
	var world := _seed_world()
	var mage_hits := 0
	var warrior_hits := 0
	var iterations := 180

	for i in range(iterations):
		var mage_roll := svc.roll_drop_table(
			world,
			"job_bias_drops",
			{
				"level": 25,
				"job_id": "explorer_mage",
				"job_primary_stat": "knowledge",
				"job_drop_bias": ["gifts"],
			},
			9000 + i
		)
		if not bool(mage_roll.get("ok", false)):
			return "mage roll failed at %d: %s" % [i, mage_roll]
		if str(mage_roll.get("item", {}).get("id", "")) == "mage_focus_item":
			mage_hits += 1
		world = mage_roll.get("world_state", {})

	for i in range(iterations):
		var warrior_roll := svc.roll_drop_table(
			world,
			"job_bias_drops",
			{
				"level": 25,
				"job_id": "explorer_warrior",
				"job_primary_stat": "strength",
				"job_drop_bias": ["decor"],
			},
			12000 + i
		)
		if not bool(warrior_roll.get("ok", false)):
			return "warrior roll failed at %d: %s" % [i, warrior_roll]
		if str(warrior_roll.get("item", {}).get("id", "")) == "warrior_focus_item":
			warrior_hits += 1
		world = warrior_roll.get("world_state", {})

	if mage_hits <= iterations / 2:
		return "mage context bias too weak: mage_focus_item hits=%d/%d" % [mage_hits, iterations]
	if warrior_hits <= iterations / 2:
		return "warrior context bias too weak: warrior_focus_item hits=%d/%d" % [warrior_hits, iterations]
	return null
