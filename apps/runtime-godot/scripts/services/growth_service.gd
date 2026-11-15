extends RefCounted

const DEFAULT_STATS := {
    "strength": 1,
    "dexterity": 1,
    "charisma": 1,
    "endurance": 1,
    "wisdom": 1,
    "knowledge": 1,
}
const STAT_POINTS_PER_LEVEL := 3
const DEFAULT_UNSPENT_STAT_POINTS := 0
const DEFAULT_SPENT_STAT_POINTS := 0


func ensure_profile(profile: Dictionary) -> Dictionary:
    var merged := profile.duplicate(true)
    if not merged.has("growth_stage"):
        merged["growth_stage"] = 1
    if typeof(merged.get("stats", null)) != TYPE_DICTIONARY:
        merged["stats"] = DEFAULT_STATS.duplicate(true)
    if not merged.has("milestone_flags"):
        merged["milestone_flags"] = []
    if not merged.has("trait_shifts"):
        merged["trait_shifts"] = []
    if not merged.has("unlocked_behaviors"):
        merged["unlocked_behaviors"] = []
    if not merged.has("stat_points_spent"):
        merged["stat_points_spent"] = DEFAULT_SPENT_STAT_POINTS
    if not merged.has("stat_points_unspent"):
        # Backfill for existing saves created before stat points existed.
        # Earned points are tied to achieved bond levels.
        var level := maxi(1, int(merged.get("bond_level", 1)))
        var earned := maxi(0, (level - 1) * STAT_POINTS_PER_LEVEL)
        var spent := maxi(0, int(merged.get("stat_points_spent", 0)))
        merged["stat_points_unspent"] = maxi(0, earned - spent)
    return merged


func apply_interaction(profile: Dictionary, kind: String) -> Dictionary:
    var merged := ensure_profile(profile)
    _maybe_auto_assign_stats(merged)
    _recompute_stage(merged)
    return merged


func apply_behavior(profile: Dictionary, action_id: String) -> Dictionary:
    var merged := ensure_profile(profile)
    _maybe_auto_assign_stats(merged)
    _recompute_stage(merged)
    return merged


func get_context(profile: Dictionary) -> Dictionary:
    var merged := ensure_profile(profile)
    return {
        "growth_stage": int(merged.get("growth_stage", 1)),
        "stats": merged.get("stats", DEFAULT_STATS.duplicate(true)),
        "stat_points_unspent": int(merged.get("stat_points_unspent", DEFAULT_UNSPENT_STAT_POINTS)),
        "stat_points_spent": int(merged.get("stat_points_spent", DEFAULT_SPENT_STAT_POINTS)),
    }


func reconcile_stat_points(profile: Dictionary) -> Dictionary:
    var merged := ensure_profile(profile)
    var level := maxi(1, int(merged.get("bond_level", 1)))
    var earned := maxi(0, (level - 1) * STAT_POINTS_PER_LEVEL)
    var spent := maxi(0, int(merged.get("stat_points_spent", 0)))
    var current_unspent := maxi(0, int(merged.get("stat_points_unspent", 0)))
    var minimum_unspent := maxi(0, earned - spent)
    if current_unspent < minimum_unspent:
        merged["stat_points_unspent"] = minimum_unspent
    return merged


func allocate_stat_point(profile: Dictionary, stat_id: String, count: int = 1) -> Dictionary:
    var merged := ensure_profile(profile)
    var wanted := maxi(1, count)
    var available := int(merged.get("stat_points_unspent", DEFAULT_UNSPENT_STAT_POINTS))
    var spend := mini(available, wanted)
    if spend <= 0:
        return {
            "ok": false,
            "reason": "no_points",
            "profile": merged,
            "spent": 0,
            "stat_id": stat_id,
        }
    var stats: Dictionary = merged.get("stats", {}).duplicate(true)
    var normalized := _normalize_stat_id(stat_id)
    if normalized == "" or not stats.has(normalized):
        return {
            "ok": false,
            "reason": "unknown_stat",
            "profile": merged,
            "spent": 0,
            "stat_id": stat_id,
        }
    stats[normalized] = int(stats.get(normalized, 1)) + spend
    merged["stats"] = stats
    merged["stat_points_unspent"] = available - spend
    merged["stat_points_spent"] = int(merged.get("stat_points_spent", 0)) + spend
    return {
        "ok": true,
        "reason": "",
        "profile": merged,
        "spent": spend,
        "stat_id": normalized,
        "new_value": int(stats.get(normalized, 1)),
    }


func _recompute_stage(profile: Dictionary) -> void:
    var interactions: int = int(profile.get("total_interactions", 0))
    var bond_level: int = int(profile.get("bond_level", 1))
    var derived_stage: int = 1 + int((interactions / 20) + (bond_level / 3))
    var stage: int = int(clamp(derived_stage, 1, 5))
    if stage > int(profile.get("growth_stage", 1)):
        var milestones: Array = profile.get("milestone_flags", [])
        milestones.append("growth_stage_%d" % stage)
        profile["milestone_flags"] = milestones
    profile["growth_stage"] = stage


func _normalize_stat_id(raw: String) -> String:
    var key := raw.to_lower()
    if key in ["str", "strength"]:
        return "strength"
    if key in ["dex", "dexterity"]:
        return "dexterity"
    if key in ["cha", "charisma", "luk", "luck"]:
        return "charisma"
    if key in ["end", "endurance", "hp"]:
        return "endurance"
    if key in ["wis", "wisdom"]:
        return "wisdom"
    if key in ["int", "knowledge", "intelligence"]:
        return "knowledge"
    return ""


func _maybe_auto_assign_stats(profile: Dictionary) -> void:
    if not bool(profile.get("auto_assign_stats", false)):
        return
    var available := int(profile.get("stat_points_unspent", DEFAULT_UNSPENT_STAT_POINTS))
    if available <= 0:
        return
    var target_stat := _preferred_auto_stat(profile)
    var stats: Dictionary = profile.get("stats", DEFAULT_STATS).duplicate(true)
    stats[target_stat] = int(stats.get(target_stat, 1)) + available
    profile["stats"] = stats
    profile["stat_points_unspent"] = 0
    profile["stat_points_spent"] = int(profile.get("stat_points_spent", 0)) + available


func _preferred_auto_stat(profile: Dictionary) -> String:
    var job_primary := _normalize_stat_id(str(profile.get("job_primary_stat", "charisma")))
    if job_primary == "":
        return "charisma"
    return job_primary
