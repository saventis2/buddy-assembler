extends RefCounted

const BASE_ACTIONS := [
    "idle",
    "sit",
    "sleep",
]

const LEVEL_UNLOCKS := [
    {"level": 2, "id": "unlock-wander", "type": "action", "value": "wander"},
    {"level": 2, "id": "unlock-happy", "type": "action", "value": "happy"},
    {"level": 3, "id": "unlock-gift", "type": "action", "value": "gift"},
    {"level": 4, "id": "unlock-visitor", "type": "action", "value": "visitor"},
]


static func all_unlock_rows() -> Array:
    return LEVEL_UNLOCKS.duplicate(true)


static func unlocked_rows_for_level(level: int) -> Array:
    var rows := []
    for row in LEVEL_UNLOCKS:
        if int(row.get("level", 999)) <= level:
            rows.append(row.duplicate(true))
    return rows


static func unlocked_action_ids(level: int) -> Array:
    var ids := []
    for action_id in BASE_ACTIONS:
        ids.append(action_id)
    for row in unlocked_rows_for_level(level):
        if str(row.get("type", "")) == "action":
            ids.append(str(row.get("value", "")))
    return _dedupe(ids)


static func _dedupe(values: Array) -> Array:
    var out := []
    var seen := {}
    for value in values:
        var key := str(value)
        if seen.has(key):
            continue
        seen[key] = true
        out.append(value)
    return out

