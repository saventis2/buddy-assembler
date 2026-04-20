extends RefCounted

var _rng := RandomNumberGenerator.new()
var _cooldowns := {}
var _last_action := "idle"
var _recent_actions: Array = []


func configure(seed_val: int) -> void:
	if seed_val == 0:
		seed_val = int(Time.get_unix_time_from_system())
	_rng.seed = seed_val
	_recent_actions.clear()


func tick(now_unix: int, context: Dictionary) -> Dictionary:
	var forced_action := str(context.get("forced_action", ""))
	if forced_action != "":
		_last_action = forced_action
		_push_recent_action(forced_action)
		_cooldowns[forced_action] = now_unix + 3
		return {"id": forced_action, "weight": 1000.0, "cooldown": 3}

	# wander deliberately NOT in rotation: it's a walk1 alias, nothing new.
	# visitor spawns a second BuddyActor via BuddyBrain (Phase D).
	# sit: chair_basic overlay (Item.wz/Install/03010000).
	# gift: happy_emote body pose + gift_box icon overlay + bubble.
	var base_options := [
		{"id": "idle", "weight": 7.0, "cooldown": 1},
		{"id": "happy", "weight": 1.2, "cooldown": 8},
		{"id": "stunned", "weight": 0.5, "cooldown": 20},
		{"id": "proud", "weight": 0.5, "cooldown": 20},
		{"id": "embarrassed", "weight": 0.5, "cooldown": 20},
		{"id": "sparkle", "weight": 0.5, "cooldown": 25},
		{"id": "humming", "weight": 0.5, "cooldown": 20},
		{"id": "kiss", "weight": 0.4, "cooldown": 25},
		{"id": "bow", "weight": 0.4, "cooldown": 25},
		{"id": "sit", "weight": 1.5, "cooldown": 8},
		{"id": "sleep", "weight": 1.5, "cooldown": 8},
		{"id": "gift", "weight": 0.8, "cooldown": 20},
		{"id": "visitor", "weight": 0.6, "cooldown": 30},
	]

	var allowed_map := _index_map(context.get("allowed_actions", []))
	var unlocked_map := _index_map(context.get("unlocked_actions", []))

	var weighted := []
	for option in base_options:
		var action_id := str(option["id"])
		if not allowed_map.is_empty() and not allowed_map.has(action_id):
			continue
		if not unlocked_map.is_empty() and not unlocked_map.has(action_id):
			continue

		var cooldown_until := int(_cooldowns.get(action_id, 0))
		if cooldown_until > now_unix:
			continue

		var weight := float(option["weight"])
		if action_id == _last_action:
			weight *= 0.45
		if _recent_actions.has(action_id):
			weight *= 0.35 if action_id != "idle" else 0.7
		if context.get("is_night", false) and action_id == "sleep":
			weight *= 2.6
		if int(context.get("bond_level", 1)) > 3 and action_id == "happy":
			weight *= 1.5
		var mood := str(context.get("dominant_mood", "calm"))
		if mood == "sleepy" and action_id == "sleep":
			weight *= 1.6
		elif mood == "proud" and action_id == "gift":
			weight *= 1.4
		elif mood == "worried" and action_id == "visitor":
			weight *= 1.2
		var top_trait := str(context.get("top_trait", ""))
		if top_trait == "curiosity" and action_id == "wander":
			weight *= 1.35
		elif top_trait == "empathy" and action_id in ["happy", "gift"]:
			weight *= 1.2
		var growth_stage := int(context.get("growth_stage", 1))
		if growth_stage >= 3 and action_id == "visitor":
			weight *= 1.2
		if context.get("quiet_mode", false):
			if action_id in ["wander", "happy", "gift"]:
				weight *= 0.15
			if action_id == "sleep":
				weight *= 2.0

		var event_frequency := str(context.get("event_frequency", "normal"))
		if action_id == "gift":
			if event_frequency == "low":
				weight *= 0.4
			elif event_frequency == "high":
				weight *= 1.6
		if action_id == "visitor" and context.get("quiet_mode", false):
			weight *= 0.05
		if action_id == "visitor" and int(context.get("bond_level", 1)) >= 4:
			weight *= 1.8

		var activity_state := str(context.get("activity_state", "steady"))
		if activity_state == "focused":
			if action_id in ["idle", "sit", "sleep"]:
				weight *= 1.25
			elif action_id in ["gift", "visitor"]:
				weight *= 0.65
		elif activity_state == "idle":
			if action_id in ["wander", "happy"]:
				weight *= 1.25
		elif activity_state == "late_session":
			if action_id == "sleep":
				weight *= 1.6
			if action_id == "visitor":
				weight *= 0.45

		var interaction_intensity := str(context.get("interaction_intensity", "balanced"))
		if interaction_intensity == "cozy":
			if action_id in ["visitor", "gift"]:
				weight *= 0.75
		elif interaction_intensity == "deep":
			if action_id in ["visitor", "gift", "happy"]:
				weight *= 1.2

		var quiet_strictness := str(context.get("quiet_strictness", "balanced"))
		if context.get("quiet_mode", false) and quiet_strictness == "strict":
			if action_id in ["visitor", "gift", "happy", "wander"]:
				weight *= 0.05

		if weight > 0.0:
			weighted.append(
				{
					"id": action_id,
					"weight": weight,
					"cooldown": int(option["cooldown"]),
				}
			)

	var picked := _pick(weighted)
	var picked_id := str(picked.get("id", "idle"))
	_cooldowns[picked_id] = now_unix + int(picked.get("cooldown", 3))
	_last_action = picked_id
	_push_recent_action(picked_id)
	return picked


func _pick(options: Array) -> Dictionary:
	if options.is_empty():
		return {"id": "idle", "cooldown": 1, "weight": 1.0}

	var total := 0.0
	for row in options:
		total += float(row.get("weight", 0.0))
	if total <= 0.0:
		return options[0]

	var roll := _rng.randf() * total
	var cumulative := 0.0
	for row in options:
		cumulative += float(row.get("weight", 0.0))
		if roll <= cumulative:
			return row
	return options[-1]


func _index_map(values: Variant) -> Dictionary:
	var map := {}
	if typeof(values) != TYPE_ARRAY:
		return map
	for value in values:
		var key := str(value)
		if key == "":
			continue
		map[key] = true
	return map


func _push_recent_action(action_id: String) -> void:
	if action_id == "":
		return
	_recent_actions.append(action_id)
	if _recent_actions.size() > 4:
		_recent_actions = _recent_actions.slice(_recent_actions.size() - 4, _recent_actions.size())
