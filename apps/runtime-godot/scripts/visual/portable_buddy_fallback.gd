extends RefCounted

const FACE_MODE_EMBEDDED := "embedded"
const FACE_MODE_OVERLAY_OR_CODE := "overlay_or_code"
const VALID_FACE_MODES := [FACE_MODE_EMBEDDED, FACE_MODE_OVERLAY_OR_CODE]

const FACE_ANCHORS := {
    "idle": Vector2(0.50, 0.38),
    "wander": Vector2(0.50, 0.38),
    "sit": Vector2(0.50, 0.36),
    "sleep": Vector2(0.62, 0.43),
    "happy": Vector2(0.50, 0.38),
    "gift": Vector2(0.50, 0.38),
    "visitor": Vector2(0.50, 0.38),
}


static func is_repository_asset_path(path_spec: String) -> bool:
    var path := path_spec.strip_edges()
    if path == "" or path.contains("\\"):
        return false
    if path.begins_with("/") or path.begins_with("user://") or path.begins_with("file://"):
        return false
    if path.length() >= 2 and path.substr(1, 1) == ":":
        return false
    if path.contains("://") and not path.begins_with("res://"):
        return false

    var relative := path.trim_prefix("res://")
    if relative == "" or relative.contains(":"):
        return false
    for segment in relative.split("/"):
        if segment == "..":
            return false
    return true


static func presentation_mode(
    body_size: Vector2,
    face_mode: String,
    approved_face_available: bool
) -> String:
    if body_size.x <= 0.0 or body_size.y <= 0.0:
        return "emergency"
    if face_mode == FACE_MODE_EMBEDDED:
        return "embedded"
    if face_mode == FACE_MODE_OVERLAY_OR_CODE and approved_face_available:
        return "approved_overlay"
    return "code_face"


static func face_plan(action_id: String, frame_index: int, source_size: Vector2) -> Dictionary:
    if source_size.x <= 0.0 or source_size.y <= 0.0:
        return {}
    var anchor: Vector2 = FACE_ANCHORS.get(action_id, FACE_ANCHORS["idle"])
    var frame_nudge := float((frame_index % 3) - 1) * 0.006
    anchor.x = clampf(anchor.x + frame_nudge, 0.30, 0.70)
    return {
        "complete": true,
        "center_normalized": anchor,
        "eye_spacing_normalized": 0.055,
        "eye_radius_normalized": 0.018,
        "mouth_width_normalized": 0.10,
    }


static func emergency_bounds(center: Vector2) -> Rect2:
    return Rect2(center - Vector2(39.0, 51.0), Vector2(78.0, 98.0))
