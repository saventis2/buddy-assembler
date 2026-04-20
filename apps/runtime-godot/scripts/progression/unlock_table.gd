extends RefCounted

const TIERS_PATH := "res://content/core_pack/progression/bond_tiers.json"
const BASE_ACTIONS := ["idle", "sit", "sleep"]

const _FALLBACK_XP_PER_LEVEL := 10
const _FALLBACK_MAX_LEVEL := 10
const _FALLBACK_UNLOCKS: Array = [
    {"level": 2, "id": "unlock-wander",  "type": "action", "value": "wander"},
    {"level": 2, "id": "unlock-happy",   "type": "action", "value": "happy"},
    {"level": 3, "id": "unlock-gift",    "type": "action", "value": "gift"},
    {"level": 4, "id": "unlock-visitor", "type": "action", "value": "visitor"},
]
const _FALLBACK_CADENCE: Array = [
    {"from_level": 1, "label": "new", "idle_phrases": ["..."],
     "happy_weight_bias": 1.0, "gift_weight_bias": 1.0},
]

static var _cache: Dictionary = {}
static var _cache_loaded := false


static func _load() -> void:
    if _cache_loaded:
        return
    _cache_loaded = true
    var f := FileAccess.open(TIERS_PATH, FileAccess.READ)
    if f == null:
        push_warning("unlock_table: %s not found — using fallback" % TIERS_PATH)
        return
    var parsed = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("unlock_table: %s not a JSON object — using fallback" % TIERS_PATH)
        return
    _cache = parsed as Dictionary


static func xp_per_level() -> int:
    _load()
    var v: Variant = _cache.get("xp_per_level", _FALLBACK_XP_PER_LEVEL)
    return max(1, int(v) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) else _FALLBACK_XP_PER_LEVEL)


static func max_level() -> int:
    _load()
    var v: Variant = _cache.get("max_level", _FALLBACK_MAX_LEVEL)
    return max(1, int(v) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) else _FALLBACK_MAX_LEVEL)


static func all_unlock_rows() -> Array:
    _load()
    var rows: Variant = _cache.get("unlocks", null)
    if typeof(rows) == TYPE_ARRAY:
        return (rows as Array).duplicate(true)
    return _FALLBACK_UNLOCKS.duplicate(true)


static func unlocked_rows_for_level(level: int) -> Array:
    var out: Array = []
    for row in all_unlock_rows():
        if int(row.get("level", 999)) <= level:
            out.append(row)
    return out


static func unlocked_action_ids(level: int) -> Array:
    var ids: Array = []
    for action_id in BASE_ACTIONS:
        ids.append(action_id)
    for row in unlocked_rows_for_level(level):
        if str(row.get("type", "")) == "action":
            ids.append(str(row.get("value", "")))
    return _dedupe(ids)


static func cadence_for_level(level: int) -> Dictionary:
    _load()
    var tiers: Variant = _cache.get("cadence", null)
    if typeof(tiers) != TYPE_ARRAY or (tiers as Array).is_empty():
        return (_FALLBACK_CADENCE[0] as Dictionary).duplicate(true)
    var best: Dictionary = (_FALLBACK_CADENCE[0] as Dictionary).duplicate(true)
    for tier in (tiers as Array):
        if typeof(tier) != TYPE_DICTIONARY:
            continue
        if int((tier as Dictionary).get("from_level", 999)) <= level:
            best = (tier as Dictionary).duplicate(true)
    return best


static func _dedupe(values: Array) -> Array:
    var out: Array = []
    var seen: Dictionary = {}
    for value in values:
        var key := str(value)
        if seen.has(key):
            continue
        seen[key] = true
        out.append(value)
    return out
