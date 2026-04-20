extends Node

const WorldService = preload("res://scripts/services/world_service.gd")
const EconomyService = preload("res://scripts/services/economy_service.gd")

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("world_variety_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("world_variety_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("anti_repeat_prefers_group_variety", func(): return _test_anti_repeat_prefers_group_variety())
	_case("encounter_skip_remains_non_punitive", func(): return _test_encounter_skip_remains_non_punitive())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("world_variety_test[%s]: %s" % [name, err])
	else:
		print("world_variety_test[%s]: ok" % name)


func _manifest() -> Dictionary:
	return {
		"id": "variety-pack",
		"version": "0.0.1",
		"items": [
			{"id": "item-a", "name": "Item A", "category": "food", "rarity": "common", "primaryTheme": "cozy"},
			{"id": "item-b", "name": "Item B", "category": "materials", "rarity": "common", "primaryTheme": "heroic"},
		],
		"npcs": [
			{"id": "pip", "name": "Pip", "role": "friend", "affinity": 0},
			{"id": "mira", "name": "Mira", "role": "mentor", "affinity": 0},
			{"id": "tala", "name": "Tala", "role": "caretaker", "affinity": 0},
			{"id": "quill", "name": "Quill", "role": "scribe", "affinity": 0},
			{"id": "fenn", "name": "Fenn", "role": "scout", "affinity": 0},
		],
		"quests": [
			{"id": "q-bond-1", "type": "bond", "npcId": "pip", "rewards": {"crystals": 2}, "repeatability": "daily"},
			{"id": "q-bond-2", "type": "bond", "npcId": "pip", "rewards": {"crystals": 2}, "repeatability": "daily"},
			{"id": "q-training-1", "type": "training", "npcId": "mira", "rewards": {"crystals": 2}, "repeatability": "daily"},
			{"id": "q-social-1", "type": "social", "npcId": "quill", "rewards": {"crystals": 2}, "repeatability": "daily"},
		],
		"encounters": [
			{
				"id": "e-visitor-1",
				"type": "optional",
				"action": "visitor",
				"npcId": "pip",
				"rewardsEngage": {"crystals": 4, "itemId": "item-b"},
				"rewardsSkip": {"crystals": 1},
			},
			{
				"id": "e-visitor-2",
				"type": "optional",
				"action": "visitor",
				"npcId": "rook",
				"rewardsEngage": {"crystals": 4, "itemId": "item-b"},
				"rewardsSkip": {"crystals": 1},
			},
			{
				"id": "e-scout-1",
				"type": "optional",
				"action": "scout",
				"npcId": "fenn",
				"rewardsEngage": {"crystals": 5},
				"rewardsSkip": {"crystals": 2},
			},
			{
				"id": "e-support-1",
				"type": "optional",
				"action": "support",
				"npcId": "quill",
				"rewardsEngage": {"crystals": 5},
				"rewardsSkip": {"crystals": 2},
			},
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


func _find_row(rows_variant: Variant, row_id: String) -> Dictionary:
	if typeof(rows_variant) != TYPE_ARRAY:
		return {}
	for row_variant in (rows_variant as Array):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("id", "")) == row_id:
			return row.duplicate(true)
	return {}


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


func _test_anti_repeat_prefers_group_variety() -> Variant:
	var world_service := WorldService.new()
	var world := _seed_world(_manifest())
	var profile := {"dominant_mood": "calm"}
	var now := 1000
	var seen_quest_types: Array = []
	var seen_encounter_actions: Array = []

	for _i in range(4):
		var tick := world_service.tick_world(world, profile, now)
		world = tick.get("world_state", {})
		var world_block: Dictionary = world.get("world", {})
		var pending_quest_id := str(world_block.get("pending_quest_id", ""))
		var pending_encounter_id := str(world_block.get("pending_encounter_id", ""))
		if pending_quest_id == "" or pending_encounter_id == "":
			return "expected both pending quest and encounter in each cycle"

		var quest := _find_row(world_block.get("quests", []), pending_quest_id)
		var encounter := _find_row(world_block.get("encounters", []), pending_encounter_id)
		seen_quest_types.append(str(quest.get("type", "")))
		seen_encounter_actions.append(str(encounter.get("action", "")))

		var quest_done := world_service.complete_pending_quest(world)
		if not bool(quest_done.get("ok", false)):
			return "quest completion failed mid-cycle"
		world = quest_done.get("world_state", {})
		world = _apply_rewards(world, quest_done.get("rewards", {}), "test:variety_quest")

		var encounter_done := world_service.resolve_pending_encounter(world, false)
		if not bool(encounter_done.get("ok", false)):
			return "encounter resolve failed mid-cycle"
		world = encounter_done.get("world_state", {})
		world = _apply_rewards(world, encounter_done.get("rewards", {}), "test:variety_skip")
		now += 2000

	for i in range(1, seen_quest_types.size()):
		if str(seen_quest_types[i]) == str(seen_quest_types[i - 1]):
			return "quest type repeated consecutively: %s" % [seen_quest_types]
	for i in range(1, seen_encounter_actions.size()):
		if str(seen_encounter_actions[i]) == str(seen_encounter_actions[i - 1]):
			return "encounter action repeated consecutively: %s" % [seen_encounter_actions]

	var quest_unique := {}
	for t in seen_quest_types:
		quest_unique[str(t)] = true
	if quest_unique.size() < 3:
		return "expected at least 3 quest categories across repeated sessions: %s" % [seen_quest_types]
	return null


func _test_encounter_skip_remains_non_punitive() -> Variant:
	var world_service := WorldService.new()
	var world := _seed_world(_manifest())
	var world_block: Dictionary = world.get("world", {}).duplicate(true)
	world_block["pending_encounter_id"] = "e-scout-1"
	world["world"] = world_block

	var before_crystals := int((world.get("wallet", {}) as Dictionary).get("crystals", 0))
	var resolved := world_service.resolve_pending_encounter(world, false)
	if not bool(resolved.get("ok", false)):
		return "expected encounter skip resolve to succeed"
	world = resolved.get("world_state", {})
	world = _apply_rewards(world, resolved.get("rewards", {}), "test:skip_non_punitive")
	var after_crystals := int((world.get("wallet", {}) as Dictionary).get("crystals", 0))
	if after_crystals <= before_crystals:
		return "skip path should grant positive value"

	var snapshot := world_service.get_snapshot(world)
	if str(snapshot.get("pending_encounter_id", "")) != "":
		return "skip path should clear pending encounter"
	return null
