extends RefCounted

const DEFAULT_PROFILE := {
    "base_type": "sprout",
    "personality_seed_tag": "curious",
    "current_personality_profile": {
        "curiosity": 0.55,
        "sociability": 0.45,
        "bravery": 0.40,
        "playfulness": 0.50,
        "diligence": 0.45,
        "independence": 0.35,
        "empathy": 0.55,
        "competitiveness": 0.30,
    },
    "likes": [],
    "dislikes": [],
    "interests": ["cozy"],
    "active_goals": ["settle-in"],
    "trait_history_summary": [],
    "interaction_counters": {},
    "job_id": "explorer_buddy",
    "job_name": "Explorer Buddy",
    "job_primary_stat": "charisma",
    "job_drop_bias": [],
}


func ensure_profile(profile: Dictionary) -> Dictionary:
    var merged := profile.duplicate(true)
    for key in DEFAULT_PROFILE.keys():
        if not merged.has(key):
            merged[key] = DEFAULT_PROFILE[key]
    if typeof(merged.get("current_personality_profile", null)) != TYPE_DICTIONARY:
        merged["current_personality_profile"] = DEFAULT_PROFILE["current_personality_profile"].duplicate(true)
    if typeof(merged.get("interaction_counters", null)) != TYPE_DICTIONARY:
        merged["interaction_counters"] = {}
    return merged


func record_interaction(profile: Dictionary, kind: String) -> Dictionary:
    var merged := ensure_profile(profile)
    var counters: Dictionary = merged.get("interaction_counters", {})
    counters[kind] = int(counters.get(kind, 0)) + 1
    merged["interaction_counters"] = counters

    var personality: Dictionary = merged.get("current_personality_profile", {}).duplicate(true)
    if kind == "pet":
        personality["empathy"] = _clamp01(float(personality.get("empathy", 0.5)) + 0.01)
        personality["sociability"] = _clamp01(float(personality.get("sociability", 0.5)) + 0.01)
    elif kind == "toggle_sleep":
        personality["diligence"] = _clamp01(float(personality.get("diligence", 0.5)) + 0.005)
    merged["current_personality_profile"] = personality

    _refresh_interests(merged)
    return merged


func record_behavior(profile: Dictionary, action_id: String) -> Dictionary:
    var merged := ensure_profile(profile)
    var history: Array = merged.get("trait_history_summary", [])
    if action_id in ["gift", "visitor", "happy"]:
        history.append("showed_%s" % action_id)
    if history.size() > 20:
        history = history.slice(history.size() - 20, history.size())
    merged["trait_history_summary"] = history
    return merged


func configure_from_manifest(profile: Dictionary, manifest: Dictionary) -> Dictionary:
    var merged := ensure_profile(profile)
    var progression_variant = manifest.get("progression", null)
    if typeof(progression_variant) != TYPE_DICTIONARY:
        return merged
    var progression: Dictionary = progression_variant
    var jobs_variant = progression.get("jobs", null)
    if typeof(jobs_variant) != TYPE_ARRAY:
        return merged
    var jobs: Array = jobs_variant
    if jobs.is_empty():
        return merged

    var active_job_id := str(progression.get("activeJobId", ""))
    var picked: Dictionary = {}
    for row_variant in jobs:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        if active_job_id != "" and str(row.get("id", "")) == active_job_id:
            picked = row
            break
        if picked.is_empty():
            picked = row
    if picked.is_empty():
        return merged
    merged["job_id"] = str(picked.get("id", merged.get("job_id", "explorer_buddy")))
    merged["job_name"] = str(picked.get("name", merged.get("job_name", "Explorer Buddy")))
    merged["job_primary_stat"] = _normalize_primary_stat(str(picked.get("primaryStat", merged.get("job_primary_stat", "charisma"))))
    var drop_bias_variant = picked.get("dropBias", [])
    if typeof(drop_bias_variant) == TYPE_ARRAY:
        merged["job_drop_bias"] = (drop_bias_variant as Array).duplicate(true)
    elif typeof(merged.get("job_drop_bias", null)) != TYPE_ARRAY:
        merged["job_drop_bias"] = []
    return merged


func get_context(profile: Dictionary) -> Dictionary:
    var merged := ensure_profile(profile)
    var personality: Dictionary = merged.get("current_personality_profile", {})
    var top_trait := "curiosity"
    var top_value := -1.0
    for key in personality.keys():
        var value := float(personality.get(key, 0.0))
        if value > top_value:
            top_trait = str(key)
            top_value = value
    return {
        "base_type": str(merged.get("base_type", "sprout")),
        "personality_seed_tag": str(merged.get("personality_seed_tag", "curious")),
        "top_trait": top_trait,
        "top_trait_weight": top_value,
        "interests": merged.get("interests", []),
    }


func _refresh_interests(profile: Dictionary) -> void:
    var counters: Dictionary = profile.get("interaction_counters", {})
    var interests: Array = profile.get("interests", [])
    if int(counters.get("pet", 0)) >= 6 and not interests.has("companionship"):
        interests.append("companionship")
    if int(counters.get("toggle_sleep", 0)) >= 4 and not interests.has("rest"):
        interests.append("rest")
    profile["interests"] = interests


func _clamp01(value: float) -> float:
    return minf(1.0, maxf(0.0, value))


func _normalize_primary_stat(raw: String) -> String:
    var key := raw.to_lower()
    if key in ["str", "strength"]:
        return "strength"
    if key in ["dex", "dexterity"]:
        return "dexterity"
    if key in ["int", "knowledge", "wisdom", "intelligence"]:
        return "knowledge"
    if key in ["luk", "charisma", "luck"]:
        return "charisma"
    if key in ["endurance", "hp", "vitality"]:
        return "endurance"
    return "charisma"
