extends RefCounted

const DOMINANT_MOODS := ["calm", "happy", "sleepy", "focused", "curious", "worried", "proud"]


func ensure_profile(profile: Dictionary) -> Dictionary:
    var merged := profile.duplicate(true)
    if not merged.has("dominant_mood"):
        merged["dominant_mood"] = "calm"
    if typeof(merged.get("mood_modifiers", null)) != TYPE_DICTIONARY:
        merged["mood_modifiers"] = {
            "energy_strain": 0.0,
            "social_fulfillment": 0.0,
            "comfort": 0.5,
            "confidence": 0.5,
        }
    if not merged.has("mood_stability"):
        merged["mood_stability"] = 0.7
    if not merged.has("last_mood_change_reason"):
        merged["last_mood_change_reason"] = "init"
    return merged


func apply_interaction(profile: Dictionary, kind: String, quiet_mode: bool) -> Dictionary:
    var merged := ensure_profile(profile)
    var mods: Dictionary = merged.get("mood_modifiers", {}).duplicate(true)
    if kind == "pet":
        mods["social_fulfillment"] = _clamp01(float(mods.get("social_fulfillment", 0.5)) + 0.15)
        mods["confidence"] = _clamp01(float(mods.get("confidence", 0.5)) + 0.05)
        merged["dominant_mood"] = "happy"
    elif kind == "toggle_sleep":
        mods["energy_strain"] = _clamp01(float(mods.get("energy_strain", 0.5)) - 0.2)
        merged["dominant_mood"] = "sleepy"
    elif quiet_mode:
        merged["dominant_mood"] = "focused"
    merged["mood_modifiers"] = mods
    merged["last_mood_change_reason"] = "interaction:%s" % kind
    return merged


func apply_behavior(profile: Dictionary, action_id: String) -> Dictionary:
    var merged := ensure_profile(profile)
    var mods: Dictionary = merged.get("mood_modifiers", {}).duplicate(true)
    if action_id == "sleep":
        mods["energy_strain"] = _clamp01(float(mods.get("energy_strain", 0.5)) - 0.25)
        mods["comfort"] = _clamp01(float(mods.get("comfort", 0.5)) + 0.05)
        merged["dominant_mood"] = "sleepy"
    elif action_id == "happy":
        merged["dominant_mood"] = "happy"
        mods["confidence"] = _clamp01(float(mods.get("confidence", 0.5)) + 0.05)
    elif action_id == "gift":
        merged["dominant_mood"] = "proud"
    elif action_id == "idle":
        _soft_decay(mods)
        if float(mods.get("energy_strain", 0.0)) > 0.72:
            merged["dominant_mood"] = "sleepy"
        elif float(mods.get("social_fulfillment", 0.0)) < 0.25:
            merged["dominant_mood"] = "worried"
        else:
            merged["dominant_mood"] = "calm"
    merged["mood_modifiers"] = mods
    merged["last_mood_change_reason"] = "behavior:%s" % action_id
    return merged


func get_context(profile: Dictionary) -> Dictionary:
    var merged := ensure_profile(profile)
    var mood := str(merged.get("dominant_mood", "calm"))
    if not DOMINANT_MOODS.has(mood):
        mood = "calm"
    return {
        "dominant_mood": mood,
        "mood_modifiers": merged.get("mood_modifiers", {}),
        "mood_stability": float(merged.get("mood_stability", 0.7)),
    }


func _soft_decay(modifiers: Dictionary) -> void:
    modifiers["energy_strain"] = _clamp01(float(modifiers.get("energy_strain", 0.0)) + 0.01)
    modifiers["social_fulfillment"] = _clamp01(float(modifiers.get("social_fulfillment", 0.0)) - 0.015)
    modifiers["confidence"] = _clamp01(float(modifiers.get("confidence", 0.0)) - 0.005)


func _clamp01(value: float) -> float:
    return minf(1.0, maxf(0.0, value))
