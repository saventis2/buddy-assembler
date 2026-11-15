extends RefCounted

const FACE_MODE_EMBEDDED := "embedded"
const VALID_FACE_MODES := [FACE_MODE_EMBEDDED]
const FALLBACK_TEXTURE_PATH := "res://content/core_pack/character/idle.png"
const PRESENTATION_SELECTED_ASSET := "selected_asset"
const PRESENTATION_FALLBACK_ASSET := "fallback_asset"
const PRESENTATION_UNAVAILABLE := "unavailable"


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


static func presentation_mode(selected_size: Vector2, fallback_size: Vector2) -> String:
    if selected_size.x > 0.0 and selected_size.y > 0.0:
        return PRESENTATION_SELECTED_ASSET
    if fallback_size.x > 0.0 and fallback_size.y > 0.0:
        return PRESENTATION_FALLBACK_ASSET
    return PRESENTATION_UNAVAILABLE


static func fitted_asset_rect(
    viewport_size: Vector2,
    texture_size: Vector2,
    requested_scale: float,
    margin: float
) -> Rect2:
    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
        return Rect2()
    if texture_size.x <= 0.0 or texture_size.y <= 0.0:
        return Rect2()

    var safe_margin := maxf(0.0, margin)
    var max_width := maxf(1.0, viewport_size.x - (safe_margin * 2.0))
    var max_height := maxf(1.0, viewport_size.y - (safe_margin * 2.0))
    var scale := minf(
        maxf(0.01, requested_scale),
        minf(max_width / texture_size.x, max_height / texture_size.y)
    )
    var draw_size := texture_size * scale
    var top_left := Vector2(
        (viewport_size.x - draw_size.x) * 0.5,
        viewport_size.y - safe_margin - draw_size.y
    )
    return Rect2(top_left, draw_size)
