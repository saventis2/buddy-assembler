extends RefCounted
const LEVEL_UP_STAT_POINTS := 3


func ensure_profile(profile: Dictionary) -> Dictionary:
    var merged := profile.duplicate(true)
    if not merged.has("bond_xp"):
        merged["bond_xp"] = 0
    if not merged.has("bond_level"):
        merged["bond_level"] = 1
    if not merged.has("trust_value"):
        merged["trust_value"] = 0.2
    if not merged.has("recent_affection_memory"):
        merged["recent_affection_memory"] = []
    if not merged.has("recent_neglect_summary"):
        merged["recent_neglect_summary"] = []
    return merged


func apply_interaction(
    profile: Dictionary,
    kind: String,
    xp_per_level: int,
    max_level: int,
    xp_curve: Array = []
) -> Dictionary:
    var merged := ensure_profile(profile)
    var xp_gain := 1
    var trust_gain := 0.01
    if kind == "pet":
        xp_gain = 2
        trust_gain = 0.03
    elif kind == "toggle_sleep":
        xp_gain = 1
        trust_gain = 0.015

    merged["bond_xp"] = int(merged.get("bond_xp", 0)) + xp_gain
    merged["trust_value"] = _clamp01(float(merged.get("trust_value", 0.2)) + trust_gain)
    _record_affection(merged, "interaction:%s" % kind)
    _apply_level(merged, xp_per_level, max_level, xp_curve)
    return merged


func apply_behavior(
    profile: Dictionary,
    action_id: String,
    xp_per_level: int,
    max_level: int,
    xp_curve: Array = []
) -> Dictionary:
    var merged := ensure_profile(profile)
    if action_id == "gift":
        merged["bond_xp"] = int(merged.get("bond_xp", 0)) + 3
        merged["trust_value"] = _clamp01(float(merged.get("trust_value", 0.2)) + 0.02)
        _record_affection(merged, "behavior:gift")
    elif action_id == "visitor":
        merged["bond_xp"] = int(merged.get("bond_xp", 0)) + 1
        _record_affection(merged, "behavior:visitor")
    _apply_level(merged, xp_per_level, max_level, xp_curve)
    return merged


func get_status(
    profile: Dictionary,
    xp_per_level: int,
    max_level: int,
    xp_curve: Array = []
) -> Dictionary:
    var merged := ensure_profile(profile)
    _apply_level(merged, xp_per_level, max_level, xp_curve)
    return {
        "bond_level": int(merged.get("bond_level", 1)),
        "bond_xp": int(merged.get("bond_xp", 0)),
        "trust_value": float(merged.get("trust_value", 0.2)),
    }


func reconcile_profile(
    profile: Dictionary,
    xp_per_level: int,
    max_level: int,
    xp_curve: Array = []
) -> Dictionary:
    var merged := ensure_profile(profile)
    _apply_level(merged, xp_per_level, max_level, xp_curve)
    return merged


func _apply_level(profile: Dictionary, xp_per_level: int, max_level: int, xp_curve: Array = []) -> void:
    var safe_xp_per_level: int = max(1, xp_per_level)
    var safe_max: int = max(1, max_level)
    var xp: int = int(profile.get("bond_xp", 0))
    xp = max(0, xp)
    profile["bond_xp"] = xp
    var previous_level := int(profile.get("bond_level", 1))
    var next_level := previous_level
    if not xp_curve.is_empty():
        var level_from_curve := 1
        var cap: int = mini(safe_max, xp_curve.size())
        for i in range(cap):
            if xp >= int(xp_curve[i]):
                level_from_curve = i + 1
        next_level = clamp(level_from_curve, 1, safe_max)
    else:
        var level: int = 1 + int(xp / safe_xp_per_level)
        next_level = clamp(level, 1, safe_max)
    profile["bond_level"] = next_level
    var gained_levels := maxi(0, next_level - previous_level)
    if gained_levels > 0:
        var current_unspent := int(profile.get("stat_points_unspent", 0))
        profile["stat_points_unspent"] = current_unspent + (gained_levels * LEVEL_UP_STAT_POINTS)


func _record_affection(profile: Dictionary, marker: String) -> void:
    var memory: Array = profile.get("recent_affection_memory", [])
    memory.append(marker)
    if memory.size() > 10:
        memory = memory.slice(memory.size() - 10, memory.size())
    profile["recent_affection_memory"] = memory


func _clamp01(value: float) -> float:
    return minf(1.0, maxf(0.0, value))
