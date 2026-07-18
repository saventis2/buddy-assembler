extends RefCounted

const FACE_MODE_EMBEDDED := "embedded"
const FACE_MODE_OVERLAY_OR_CODE := "overlay_or_code"
const VALID_FACE_MODES := [FACE_MODE_EMBEDDED, FACE_MODE_OVERLAY_OR_CODE]

const FACE_CENTERS_PX := {
    # Face asset origins projected into each tracked shipping frame. Exported
    # builds never need the excluded per-frame workstation metadata.
    "idle": [Vector2(31.0, 36.0), Vector2(30.0, 35.0), Vector2(29.0, 36.0)],
    "wander": [Vector2(37.0, 36.0), Vector2(37.0, 37.0), Vector2(37.0, 36.0), Vector2(37.0, 35.0)],
    "sit": [Vector2(25.0, 35.0)],
    "sleep": [Vector2(34.0, 35.0)],
    "happy": [Vector2(34.0, 35.0), Vector2(34.0, 35.0), Vector2(34.0, 35.0)],
    "gift": [Vector2(30.0, 36.0), Vector2(26.0, 35.0), Vector2(33.0, 35.0)],
    "visitor": [Vector2(37.0, 36.0), Vector2(37.0, 37.0), Vector2(37.0, 36.0), Vector2(37.0, 35.0)],
}

const FRAME_SIZES_PX := {
    "idle": [Vector2(65.0, 89.0), Vector2(65.0, 89.0), Vector2(65.0, 89.0)],
    "wander": [Vector2(73.0, 85.0), Vector2(73.0, 85.0), Vector2(73.0, 85.0), Vector2(73.0, 85.0)],
    "sit": [Vector2(59.0, 77.0)],
    "sleep": [Vector2(87.0, 64.0)],
    "happy": [Vector2(68.0, 83.0), Vector2(68.0, 83.0), Vector2(68.0, 83.0)],
    "gift": [Vector2(67.0, 84.0), Vector2(67.0, 84.0), Vector2(67.0, 84.0)],
    "visitor": [Vector2(73.0, 85.0), Vector2(73.0, 85.0), Vector2(73.0, 85.0), Vector2(73.0, 85.0)],
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


static func is_pack_id(pack_id: String) -> bool:
    var value := pack_id.strip_edges()
    if value == "":
        return false
    for character in value:
        if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character.to_lower()):
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
    var centers_variant = FACE_CENTERS_PX.get(action_id, [])
    var sizes_variant = FRAME_SIZES_PX.get(action_id, [])
    if typeof(centers_variant) != TYPE_ARRAY or typeof(sizes_variant) != TYPE_ARRAY:
        return {}
    var centers: Array = centers_variant
    var sizes: Array = sizes_variant
    if frame_index < 0 or frame_index >= centers.size() or frame_index >= sizes.size():
        return {}
    var expected_size: Vector2 = sizes[frame_index]
    if not source_size.is_equal_approx(expected_size):
        return {}
    var center_px: Vector2 = centers[frame_index]
    return {
        "complete": true,
        "center_px": center_px,
        "center_normalized": Vector2(center_px.x / source_size.x, center_px.y / source_size.y),
        "eye_spacing_normalized": 0.055,
        "eye_radius_normalized": 0.018,
        "mouth_width_normalized": 0.10,
    }


static func emergency_bounds(center: Vector2) -> Rect2:
    return Rect2(center - Vector2(39.0, 51.0), Vector2(78.0, 98.0))
