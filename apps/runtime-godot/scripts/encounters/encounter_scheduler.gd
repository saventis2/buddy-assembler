extends RefCounted

var _rng := RandomNumberGenerator.new()
var _rules: Array[Dictionary] = []
var _cooldowns: Dictionary = {}


func configure(event_rules: Array, seed: int) -> void:
    _rules.clear()
    _cooldowns.clear()

    if seed == 0:
        seed = int(Time.get_unix_time_from_system())
    _rng.seed = seed + 113

    for row_variant in event_rules:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant

        var event_id := str(row.get("id", ""))
        if event_id == "":
            continue

        _rules.append(
            {
                "id": event_id,
                "action": str(row.get("action", "gift")),
                "weight": float(row.get("weight", 1.0)),
                "cooldown_seconds": int(row.get("cooldownSeconds", 120)),
                "per_hour": int(row.get("perHour", 1)),
                "per_day": int(row.get("perDay", 4)),
            }
        )


func tick(now_unix: int, context: Dictionary) -> Dictionary:
    if _rules.is_empty():
        return {}
    if bool(context.get("quiet_mode", false)):
        return {}

    var frequency := str(context.get("event_frequency", "normal"))
    var gate_chance := 0.15
    if frequency == "low":
        gate_chance = 0.07
    elif frequency == "high":
        gate_chance = 0.30

    if _rng.randf() > gate_chance:
        return {}

    var weighted: Array[Dictionary] = []
    for rule in _rules:
        var event_id := str(rule.get("id", ""))
        var cooldown_until := int(_cooldowns.get(event_id, 0))
        if cooldown_until > now_unix:
            continue

        var weight := float(rule.get("weight", 1.0))
        if int(context.get("bond_level", 1)) >= 4:
            weight *= 1.2
        if weight <= 0.0:
            continue

        var cloned: Dictionary = rule.duplicate(true)
        cloned["weight"] = weight
        weighted.append(cloned)

    if weighted.is_empty():
        return {}

    var selected: Dictionary = _pick(weighted)
    var picked_id := str(selected.get("id", ""))
    _cooldowns[picked_id] = now_unix + int(selected.get("cooldown_seconds", 120))
    return selected


func _pick(options: Array[Dictionary]) -> Dictionary:
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
