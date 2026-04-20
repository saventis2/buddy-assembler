extends RefCounted

const DEFAULT_STATS := {
    "strength": 1,
    "dexterity": 1,
    "charisma": 1,
    "endurance": 1,
    "wisdom": 1,
    "knowledge": 1,
}


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
    return merged


func apply_interaction(profile: Dictionary, kind: String) -> Dictionary:
    var merged := ensure_profile(profile)
    var stats: Dictionary = merged.get("stats", {}).duplicate(true)
    if kind == "pet":
        stats["charisma"] = int(stats.get("charisma", 1)) + 1
        stats["wisdom"] = int(stats.get("wisdom", 1)) + 1
    elif kind == "toggle_sleep":
        stats["endurance"] = int(stats.get("endurance", 1)) + 1
    merged["stats"] = stats
    _recompute_stage(merged)
    return merged


func apply_behavior(profile: Dictionary, action_id: String) -> Dictionary:
    var merged := ensure_profile(profile)
    var stats: Dictionary = merged.get("stats", {}).duplicate(true)
    if action_id == "wander":
        stats["dexterity"] = int(stats.get("dexterity", 1)) + 1
    elif action_id == "gift":
        stats["charisma"] = int(stats.get("charisma", 1)) + 1
    elif action_id == "sleep":
        stats["endurance"] = int(stats.get("endurance", 1)) + 1
    elif action_id == "happy":
        stats["strength"] = int(stats.get("strength", 1)) + 1
    merged["stats"] = stats
    _recompute_stage(merged)
    return merged


func get_context(profile: Dictionary) -> Dictionary:
    var merged := ensure_profile(profile)
    return {
        "growth_stage": int(merged.get("growth_stage", 1)),
        "stats": merged.get("stats", DEFAULT_STATS.duplicate(true)),
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
