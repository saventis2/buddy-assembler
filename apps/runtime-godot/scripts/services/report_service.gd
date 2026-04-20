extends RefCounted

const ACTION_LINES := {
    "idle": "I kept watch over your workspace.",
    "sleep": "I took a short nap to recharge.",
    "gift": "I picked out a little surprise while you were busy.",
    "visitor": "I chatted with a visitor for a bit.",
    "wander": "I wandered around and stayed curious.",
    "happy": "I practiced cheerful emotes while waiting for you.",
}


func generate_while_away_report(profile: Dictionary, world_state: Dictionary, now_unix: int) -> Dictionary:
    var last_tick := int(world_state.get("last_tick_unix", 0))
    if last_tick <= 0:
        return {"summary": "", "elapsed_minutes": 0}

    var elapsed_minutes := int(max(0, now_unix - last_tick) / 60)
    if elapsed_minutes < 10:
        return {"summary": "", "elapsed_minutes": elapsed_minutes}

    var last_action := str(world_state.get("last_action", "idle"))
    var base_line := str(ACTION_LINES.get(last_action, ACTION_LINES["idle"]))
    var mood := str(profile.get("dominant_mood", "calm"))
    var tone_line := "I feel %s now." % mood
    var summary := "While you were away (%dm), %s %s" % [elapsed_minutes, base_line, tone_line]
    return {
        "summary": summary,
        "elapsed_minutes": elapsed_minutes,
        "last_action": last_action,
    }
