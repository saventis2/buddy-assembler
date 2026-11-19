extends Node

const WorldService = preload("res://scripts/services/world_service.gd")
const EconomyService = preload("res://scripts/services/economy_service.gd")

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("world_economy_flow_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("world_economy_flow_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("quest_and_encounter_engage_flow", func(): return _test_quest_and_encounter_engage_flow())
	_case("encounter_skip_flow", func(): return _test_encounter_skip_flow())
	_case("duplicate_recycle_flow", func(): return _test_duplicate_recycle_flow())
	_case("legacy_inventory_ids_remap_to_catalog", func(): return _test_legacy_inventory_ids_remap_to_catalog())
	_case("strict_catalog_quarantine_and_repair", func(): return _test_strict_catalog_quarantine_and_repair())
	_case("items_survive_load_before_catalog", func(): return _test_items_survive_load_before_catalog())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("world_economy_flow_test[%s]: %s" % [name, err])
	else:
		print("world_economy_flow_test[%s]: ok" % name)


func _new_manifest() -> Dictionary:
	return {
		"id": "test-pack",
		"version": "0.0.1",
		"items": [
			{
				"id": "wz-tri-colored-dango",
				"name": "Tri-colored Dango",
				"category": "food",
				"rarity": "common",
				"primaryTheme": "cozy",
			},
			{
				"id": "wz-stone-golem-rubble",
				"name": "Stone Golem Rubble",
				"category": "materials",
				"rarity": "common",
				"primaryTheme": "heroic",
			},
		],
		"npcs": [
			{"id": "pip", "name": "Pip", "role": "friend", "affinity": 0, "dialoguePool": ["hello"]},
			{"id": "rook", "name": "Rook", "role": "rival", "affinity": 0, "dialoguePool": ["ready?"]},
		],
		"quests": [
			{
				"id": "quest-cozy-checkin",
				"type": "bond",
				"npcId": "pip",
				"rewards": {"crystals": 5, "itemId": "wz-tri-colored-dango"},
				"repeatability": "daily",
				"narrativeText": "Cozy check-in.",
			}
		],
		"encounters": [
			{
				"id": "encounter-curious-visitor",
				"type": "optional",
				"action": "visitor",
				"npcId": "rook",
				"rewardsEngage": {"crystals": 7, "itemId": "wz-stone-golem-rubble"},
				"rewardsSkip": {"crystals": 1},
				"narrativeText": "A challenge appears.",
			}
		],
		"rewardBoxes": [
			{
				"id": "dupe_box",
				"theme": "cozy",
				"cost": 10,
				"possibleItems": ["wz-tri-colored-dango"],
				"rarityTable": {"common": 100},
			}
		],
	}


func _seed_world(manifest: Dictionary) -> Dictionary:
	var world_service := WorldService.new()
	var economy_service := EconomyService.new()
	var world := {}
	world = world_service.ensure_world_state(world)
	world = economy_service.ensure_world_state(world)
	world = world_service.configure_from_manifest(world, manifest)
	world = economy_service.configure_from_manifest(world, manifest)
	return world


func _apply_rewards(world: Dictionary, rewards_variant: Variant, source: String) -> Dictionary:
	var economy_service := EconomyService.new()
	if typeof(rewards_variant) != TYPE_DICTIONARY:
		return world
	var rewards: Dictionary = rewards_variant
	var next_world := world
	var crystals := int(rewards.get("crystals", 0))
	if crystals > 0:
		next_world = economy_service.grant_crystals(next_world, source, crystals)
	var item_id := str(rewards.get("itemId", ""))
	if item_id != "":
		var catalog: Dictionary = next_world.get("item_catalog", {})
		if catalog.has(item_id) and typeof(catalog[item_id]) == TYPE_DICTIONARY:
			next_world = economy_service.grant_item(next_world, source, (catalog[item_id] as Dictionary).duplicate(true))
	return next_world


func _test_quest_and_encounter_engage_flow() -> Variant:
	var manifest := _new_manifest()
	var world_service := WorldService.new()
	var economy_service := EconomyService.new()
	var world := _seed_world(manifest)
	var profile := {"dominant_mood": "calm"}

	var tick := world_service.tick_world(world, profile, 1000)
	world = tick.get("world_state", {})
	var snapshot := world_service.get_snapshot(world)
	if str(snapshot.get("pending_quest_id", "")) == "":
		return "expected pending quest after tick"
	if str(snapshot.get("pending_encounter_id", "")) == "":
		return "expected pending encounter after tick"

	var quest_result := world_service.complete_pending_quest(world)
	if not bool(quest_result.get("ok", false)):
		return "quest completion failed: %s" % [quest_result]
	world = quest_result.get("world_state", {})
	world = _apply_rewards(world, quest_result.get("rewards", {}), "test:quest")

	var wallet_after_quest: Dictionary = world.get("wallet", {})
	if int(wallet_after_quest.get("crystals", 0)) < 5:
		return "expected quest crystals applied"
	var inv_after_quest: Array = world.get("inventory", [])
	if inv_after_quest.is_empty():
		return "expected quest reward item in inventory"

	var encounter_result := world_service.resolve_pending_encounter(world, true)
	if not bool(encounter_result.get("ok", false)):
		return "encounter engage failed: %s" % [encounter_result]
	world = encounter_result.get("world_state", {})
	world = _apply_rewards(world, encounter_result.get("rewards", {}), "test:encounter_engage")

	var final_snapshot := world_service.get_snapshot(world)
	if str(final_snapshot.get("pending_encounter_id", "")) != "":
		return "expected pending encounter cleared after resolve"
	var econ_snapshot := economy_service.get_snapshot(world)
	if int(econ_snapshot.get("crystals", 0)) < 12:
		return "expected combined quest+engage crystals"
	return null


func _test_encounter_skip_flow() -> Variant:
	var manifest := _new_manifest()
	var world_service := WorldService.new()
	var economy_service := EconomyService.new()
	var world := _seed_world(manifest)
	var world_block: Dictionary = world.get("world", {}).duplicate(true)
	world_block["pending_encounter_id"] = "encounter-curious-visitor"
	world["world"] = world_block

	var before := int((world.get("wallet", {}) as Dictionary).get("crystals", 0))
	var result := world_service.resolve_pending_encounter(world, false)
	if not bool(result.get("ok", false)):
		return "encounter skip failed: %s" % [result]
	world = result.get("world_state", {})
	world = _apply_rewards(world, result.get("rewards", {}), "test:encounter_skip")
	var after := int((world.get("wallet", {}) as Dictionary).get("crystals", 0))
	if after <= before:
		return "expected skip rewards to grant crystals"
	return null


func _test_duplicate_recycle_flow() -> Variant:
	var manifest := _new_manifest()
	var economy_service := EconomyService.new()
	var world := _seed_world(manifest)

	var catalog: Dictionary = world.get("item_catalog", {})
	if not catalog.has("wz-tri-colored-dango"):
		return "missing item catalog seed for duplicate test"
	world = economy_service.grant_item(world, "seed:item", (catalog["wz-tri-colored-dango"] as Dictionary).duplicate(true))
	world = economy_service.grant_crystals(world, "seed:crystals", 25)

	var before_wallet := int((world.get("wallet", {}) as Dictionary).get("crystals", 0))
	var open := economy_service.open_reward_box(world, "dupe_box", 1234)
	if not bool(open.get("ok", false)):
		return "expected reward box open success: %s" % [open]
	if not bool(open.get("duplicate", false)):
		return "expected duplicate flag on repeat pull"
	var recycle := int(open.get("recycleCrystals", 0))
	if recycle <= 0:
		return "expected recycle crystals on duplicate"
	world = open.get("world_state", {})
	var after_wallet := int((world.get("wallet", {}) as Dictionary).get("crystals", 0))
	var expected_wallet := before_wallet - 10 + recycle
	if after_wallet != expected_wallet:
		return "wallet mismatch after duplicate recycle: expected %d got %d" % [expected_wallet, after_wallet]
	var recycles: Array = world.get("duplicate_recycles", [])
	if recycles.is_empty():
		return "expected duplicate recycle history row"
	return null


func _test_legacy_inventory_ids_remap_to_catalog() -> Variant:
	var manifest := _new_manifest()
	manifest["items"] = (manifest.get("items", []) as Array).duplicate(true)
	manifest["items"].append(
		{
			"id": "wz-green-halloween-stick-candy",
			"name": "Green Halloween Stick Candy",
			"description": "A green Halloween candy.",
			"category": "gifts",
			"rarity": "common",
			"iconAsset": "icons/items/wz-green-halloween-stick-candy.png",
		}
	)
	manifest["items"].append(
		{
			"id": "wz-rocky-mask-doll",
			"name": "Rocky Mask Doll",
			"description": "A doll modeled after Stone Mask.",
			"category": "decor",
			"rarity": "common",
			"iconAsset": "icons/items/wz-rocky-mask-doll.png",
		}
	)
	var economy_service := EconomyService.new()
	var world := _seed_world(manifest)
	world["inventory"] = [
		{"id": "cozy-lamp", "iconAsset": "effects/chair_basic/frames/000.png"},
		{"id": "plush-heart", "iconAsset": "effects/happy_sparkle/frames/000.png"},
	]
	world = economy_service.ensure_world_state(world)
	var inventory: Array = world.get("inventory", [])
	if inventory.size() != 2:
		return "expected 2 inventory rows after normalization"
	var first: Dictionary = inventory[0]
	var second: Dictionary = inventory[1]
	if str(first.get("id", "")) != "wz-rocky-mask-doll":
		return "expected cozy-lamp remap to wz-rocky-mask-doll, got %s" % [first.get("id", "")]
	if str(second.get("id", "")) != "wz-green-halloween-stick-candy":
		return "expected plush-heart remap to wz-green-halloween-stick-candy, got %s" % [second.get("id", "")]
	if str(first.get("iconAsset", "")) == "effects/chair_basic/frames/000.png":
		return "expected remapped catalog icon for rocky-mask-doll"
	if str(second.get("iconAsset", "")) == "effects/happy_sparkle/frames/000.png":
		return "expected remapped catalog icon for halloween-stick-candy"
	return null


func _test_strict_catalog_quarantine_and_repair() -> Variant:
	var manifest := _new_manifest()
	var economy_service := EconomyService.new()
	var world := _seed_world(manifest)
	world["inventory"] = [
		{"id": "unknown-item-x", "iconAsset": "effects/gift_box/frames/000.png"},
	]
	world = economy_service.ensure_world_state(world)
	var snapshot_before := economy_service.get_inventory_snapshot(world)
	if int(snapshot_before.get("inventory_count", 0)) != 0:
		return "expected unresolved item to be removed from active inventory"
	if int(snapshot_before.get("quarantine_count", 0)) <= 0:
		return "expected unresolved item to be quarantined"

	# Add the formerly unknown item to catalog and repair.
	var catalog: Dictionary = world.get("item_catalog", {}).duplicate(true)
	catalog["unknown-item-x"] = {
		"id": "unknown-item-x",
		"name": "Recovered Item",
		"description": "Recovered from quarantine.",
		"category": "materials",
		"rarity": "common",
		"iconAsset": "icons/items/wz-stone-golem-rubble.png",
	}
	world["item_catalog"] = catalog
	var repaired := economy_service.repair_inventory_from_catalog(world)
	if not bool(repaired.get("ok", false)):
		return "expected repair_inventory_from_catalog to succeed"
	world = repaired.get("world_state", {})
	var snapshot_after := economy_service.get_inventory_snapshot(world)
	if int(snapshot_after.get("inventory_count", 0)) != 1:
		return "expected repaired item to return to inventory"
	if int(snapshot_after.get("quarantine_count", 0)) != 0:
		return "expected quarantine to be empty after successful repair"
	return null

# A save holds the inventory but not the item catalogue, which is rebuilt
# from the content pack afterwards. Loading must not treat every item as
# unknown in between, and the real check must still run once it is there.
func _test_items_survive_load_before_catalog() -> Variant:
	var economy := EconomyService.new()
	var saved := {"inventory": [{"id": "item-a", "instance_id": 7, "name": "Item A"}], "next_item_instance_id": 8}
	var loaded := economy.ensure_world_state(saved)
	if (loaded.get("inventory", []) as Array).size() != 1:
		return "item was dropped when the save was loaded before the catalogue"
	if not (loaded.get("inventory_quarantine", []) as Array).is_empty():
		return "item was quarantined before any catalogue was loaded"
	loaded["item_catalog"] = {"item-b": {"id": "item-b", "name": "Item B", "category": "food", "rarity": "common"}}
	var checked := economy.ensure_world_state(loaded)
	if (checked.get("inventory_quarantine", []) as Array).size() != 1:
		return "an item missing from a loaded catalogue should still be quarantined"
	return null
