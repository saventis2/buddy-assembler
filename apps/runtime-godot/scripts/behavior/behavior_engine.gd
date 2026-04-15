extends RefCounted

var _rng := RandomNumberGenerator.new()
var _cooldowns := {}
var _last_action := "idle"


func configure(seed: int) -> void:
    if seed == 0:
        seed = int(Time.get_unix_time_from_system())
    _rng.seed = seed


func tick(now_unix: int, context: Dictionary) -> Dictionary:
    var forced_action := str(context.get("forced_action", ""))
    if forced_action != "":
        _last_action = forced_action
        _cooldowns[forced_action] = now_unix + 3
        return {"id": forced_action, "weight": 1000.0, "cooldown": 3}

    var base_options := [
        {"id": "idle", "weight": 7.0, "cooldown": 1},
        {"id": "wander", "weight": 4.0, "cooldown": 4},
        {"id": "sit", "weight": 3.0, "cooldown": 5},
        {"id": "happy", "weight": 2.0, "cooldown": 6},
        {"id": "gift", "weight": 1.0, "cooldown": 12},
        {"id": "sleep", "weight": 1.5, "cooldown": 8},
        {"id": "visitor", "weight": 0.8, "cooldown": 14},
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
        if context.get("is_night", false) and action_id == "sleep":
            weight *= 2.6
        if int(context.get("bond_level", 1)) > 3 and action_id == "happy":
            weight *= 1.5
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
