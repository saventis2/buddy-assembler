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
