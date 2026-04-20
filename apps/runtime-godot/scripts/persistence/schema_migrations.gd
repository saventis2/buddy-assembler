extends RefCounted

# Central registry of persistence schemas and their migrators.
#
# When you bump a schema:
#  1. Increment the *_CURRENT_VERSION constant for that file.
#  2. Add a Callable under *_MIGRATORS keyed by the OLD version.
#     The Callable receives the old-shape Dictionary and returns the
#     dict shaped for (OLD + 1). The loader stamps the new
#     schemaVersion automatically; migrators do not need to.
#  3. Add a test case in tests/save_store_test.gd that writes a
#     fixture at the old version and verifies it loads to the new.
#
# Defaults live with the data owner (AppState) — this module is
# purely about versioning and migration.

const SETTINGS_CURRENT_VERSION := 1
const PROFILE_CURRENT_VERSION := 2
const WORLD_STATE_CURRENT_VERSION := 2

# v1 is initial settings shape; no migrations yet.
static var SETTINGS_MIGRATORS := {}
static var PROFILE_MIGRATORS := {
    1: func(v1: Dictionary) -> Dictionary:
        var next := v1.duplicate(true)
        next["base_type"] = str(next.get("base_type", "sprout"))
        next["personality_seed_tag"] = str(next.get("personality_seed_tag", "curious"))
        next["current_personality_profile"] = next.get(
            "current_personality_profile",
            {
                "curiosity": 0.55,
                "sociability": 0.45,
                "bravery": 0.40,
                "playfulness": 0.50,
                "diligence": 0.45,
                "independence": 0.35,
                "empathy": 0.55,
                "competitiveness": 0.30,
            }
        )
        next["likes"] = next.get("likes", [])
        next["dislikes"] = next.get("dislikes", [])
        next["interests"] = next.get("interests", ["cozy"])
        next["active_goals"] = next.get("active_goals", ["settle-in"])
        next["trait_history_summary"] = next.get("trait_history_summary", [])
        next["interaction_counters"] = next.get("interaction_counters", {})
        next["trust_value"] = float(next.get("trust_value", 0.2))
        next["recent_affection_memory"] = next.get("recent_affection_memory", [])
        next["recent_neglect_summary"] = next.get("recent_neglect_summary", [])
        next["dominant_mood"] = str(next.get("dominant_mood", "calm"))
        next["mood_modifiers"] = next.get(
            "mood_modifiers",
            {
                "energy_strain": 0.0,
                "social_fulfillment": 0.0,
                "comfort": 0.5,
                "confidence": 0.5,
            }
        )
        next["mood_stability"] = float(next.get("mood_stability", 0.7))
        next["last_mood_change_reason"] = str(next.get("last_mood_change_reason", "init"))
        next["growth_stage"] = int(next.get("growth_stage", 1))
        next["stats"] = next.get(
            "stats",
            {
                "strength": 1,
                "dexterity": 1,
                "charisma": 1,
                "endurance": 1,
                "wisdom": 1,
                "knowledge": 1,
            }
        )
        next["milestone_flags"] = next.get("milestone_flags", [])
        next["trait_shifts"] = next.get("trait_shifts", [])
        next["unlocked_behaviors"] = next.get("unlocked_behaviors", [])
        next["last_active_summary"] = str(next.get("last_active_summary", ""))
        return next
}
static var WORLD_STATE_MIGRATORS := {
    1: func(v1: Dictionary) -> Dictionary:
        var next := v1.duplicate(true)
        next["wallet"] = next.get("wallet", {"crystals": 0})
        next["inventory"] = next.get("inventory", [])
        next["reward_transactions"] = next.get("reward_transactions", [])
        next["reward_boxes"] = next.get("reward_boxes", {})
        return next
}
