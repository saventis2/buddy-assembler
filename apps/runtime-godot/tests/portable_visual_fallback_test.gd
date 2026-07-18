extends Node

const PortableBuddyFallback = preload("res://scripts/visual/portable_buddy_fallback.gd")
const BuddyOverlayScript = preload("res://scripts/buddy_overlay.gd")
const ANIMATION_ROOT := "res://content/core_pack/character/animations"
const ACTIONS := ["idle", "wander", "sit", "sleep", "happy", "gift", "visitor"]
const EXPECTED_FACE_CENTERS_PX := {
    "idle": [Vector2(31.0, 36.0), Vector2(30.0, 35.0), Vector2(29.0, 36.0)],
    "wander": [Vector2(37.0, 36.0), Vector2(37.0, 37.0), Vector2(37.0, 36.0), Vector2(37.0, 35.0)],
    "sit": [Vector2(25.0, 35.0)],
    "sleep": [Vector2(34.0, 35.0)],
    "happy": [Vector2(34.0, 35.0), Vector2(34.0, 35.0), Vector2(34.0, 35.0)],
    "gift": [Vector2(30.0, 36.0), Vector2(26.0, 35.0), Vector2(33.0, 35.0)],
    "visitor": [Vector2(37.0, 36.0), Vector2(37.0, 37.0), Vector2(37.0, 36.0), Vector2(37.0, 35.0)],
}

var _failures: Array[String] = []


func _ready() -> void:
    _check_path_boundary()
    _check_presentation_modes()
    _check_all_shipping_frames()
    _check_process_relative_decoys()
    _check_red_error_box_removed()
    if _failures.is_empty():
        print("portable_visual_fallback_test: PASS (19 shipping frames)")
        get_tree().quit(0)
        return
    for failure in _failures:
        push_error("portable_visual_fallback_test: %s" % failure)
    get_tree().quit(1)


func _check_path_boundary() -> void:
    var rejected := [
        "C:/Users/example/ignored/face.png",
        "C:\\Users\\example\\ignored\\face.png",
        "/home/example/face.png",
        "//server/share/face.png",
        "user://face.png",
        "../face.png",
        "character/../face.png",
    ]
    for path_spec in rejected:
        if PortableBuddyFallback.is_repository_asset_path(path_spec):
            _failures.append("unsafe path accepted: %s" % path_spec)
    for path_spec in ["character/face.png", "res://content/core_pack/character/face.png"]:
        if not PortableBuddyFallback.is_repository_asset_path(path_spec):
            _failures.append("repository path rejected: %s" % path_spec)
    for pack_id in ["../core_pack", "core/pack", "C:pack", "core\\pack", ""]:
        if PortableBuddyFallback.is_pack_id(pack_id):
            _failures.append("unsafe pack id accepted: %s" % pack_id)
    for pack_id in ["core_pack", "night-pack", "pack01"]:
        if not PortableBuddyFallback.is_pack_id(pack_id):
            _failures.append("safe pack id rejected: %s" % pack_id)


func _check_presentation_modes() -> void:
    if PortableBuddyFallback.presentation_mode(Vector2.ZERO, "overlay_or_code", false) != "emergency":
        _failures.append("missing body did not select emergency buddy")
    if PortableBuddyFallback.presentation_mode(Vector2(-1.0, 40.0), "overlay_or_code", false) != "emergency":
        _failures.append("corrupt body dimensions did not select emergency buddy")
    if PortableBuddyFallback.presentation_mode(Vector2(64.0, 80.0), "overlay_or_code", false) != "code_face":
        _failures.append("missing approved face did not select code face")
    if PortableBuddyFallback.presentation_mode(Vector2(64.0, 80.0), "overlay_or_code", true) != "approved_overlay":
        _failures.append("approved repository face did not retain overlay behavior")
    if PortableBuddyFallback.presentation_mode(Vector2(64.0, 80.0), "embedded", false) != "embedded":
        _failures.append("embedded visual behavior was not preserved")


func _check_all_shipping_frames() -> void:
    var checked := 0
    for action in ACTIONS:
        var file := FileAccess.open("%s/%s.json" % [ANIMATION_ROOT, action], FileAccess.READ)
        if file == null:
            _failures.append("missing animation manifest: %s" % action)
            continue
        var parsed = JSON.parse_string(file.get_as_text())
        file.close()
        if typeof(parsed) != TYPE_DICTIONARY:
            _failures.append("invalid animation manifest: %s" % action)
            continue
        for frame_variant in (parsed as Dictionary).get("frames", []):
            if typeof(frame_variant) != TYPE_DICTIONARY:
                _failures.append("non-object frame in %s" % action)
                continue
            var frame: Dictionary = frame_variant
            var rect: Array = frame.get("rect", [])
            if rect.size() < 4:
                _failures.append("frame without rect in %s" % action)
                continue
            var source_size := Vector2(float(rect[2]), float(rect[3]))
            var frame_index := int(frame.get("index", -1))
            var plan := PortableBuddyFallback.face_plan(action, frame_index, source_size)
            if not bool(plan.get("complete", false)):
                _failures.append("incomplete code face for %s frame %s" % [action, frame.get("index", "?")])
                continue
            var expected: Vector2 = EXPECTED_FACE_CENTERS_PX[action][frame_index]
            var center_px: Vector2 = plan.get("center_px", Vector2(-1.0, -1.0))
            if not center_px.is_equal_approx(expected):
                _failures.append("wrong face center for %s[%d]: expected %s, got %s" % [action, frame_index, expected, center_px])
            var normalized: Vector2 = plan.get("center_normalized", Vector2(-1.0, -1.0))
            var reconstructed := Vector2(normalized.x * source_size.x, normalized.y * source_size.y)
            if not reconstructed.is_equal_approx(expected):
                _failures.append("normalized face center drift for %s[%d]: expected %s, got %s" % [action, frame_index, expected, reconstructed])
            if expected.x <= 0.0 or expected.y <= 0.0 or expected.x >= source_size.x or expected.y >= source_size.y:
                _failures.append("face center outside tracked frame for %s[%d]: %s in %s" % [action, frame_index, expected, source_size])

            var sprite_rect := Rect2(Vector2(100.0, 50.0), source_size * 2.0)
            var geometry := BuddyOverlayScript.code_face_geometry(action, frame_index, source_size, sprite_rect)
            var expected_screen := sprite_rect.position + (expected * 2.0)
            var actual_screen: Vector2 = geometry.get("center", Vector2(-1.0, -1.0))
            if not actual_screen.is_equal_approx(expected_screen):
                _failures.append("BuddyOverlay face integration drift for %s[%d]: expected %s, got %s" % [action, frame_index, expected_screen, actual_screen])
            if action == "sleep" and actual_screen.x >= sprite_rect.get_center().x:
                _failures.append("sleep face landed on the prone body: %s" % actual_screen)
            checked += 1
    if checked != 19:
        _failures.append("expected 19 shipping frames, checked %d" % checked)


func _check_process_relative_decoys() -> void:
    # Godot resolves bare process-relative paths from the project working
    # directory. These tracked files exist there but not beneath the requested
    # pack root, so a confined resolver must refuse them.
    var text_decoy := "project.godot"
    var texture_decoy := "content/core_pack/character/animations/idle_sheet.png"
    if not FileAccess.file_exists(text_decoy) or not FileAccess.file_exists(texture_decoy):
        _failures.append("process-relative decoy fixtures are unavailable")
        return
    var overlay = BuddyOverlayScript.new()
    if overlay._resolve_text(text_decoy, "missing-decoy-pack") != "":
        _failures.append("process-relative text decoy was loaded")
    if overlay._resolve_texture(texture_decoy, "missing-decoy-pack") != null:
        _failures.append("process-relative texture decoy was loaded")
    if overlay._resolve_text("manifest.json", "../core_pack") != "":
        _failures.append("relative text escaped an unvalidated pack root")
    if overlay._resolve_texture("character/idle.png", "../core_pack") != null:
        _failures.append("relative texture escaped an unvalidated pack root")
    overlay.free()


func _check_red_error_box_removed() -> void:
    var file := FileAccess.open("res://scripts/buddy_overlay.gd", FileAccess.READ)
    if file == null:
        _failures.append("could not inspect shipping overlay source")
        return
    var source := file.get_as_text()
    file.close()
    if source.contains("missing_rect"):
        _failures.append("red missing-asset box remains in shipping draw path")
    if not source.contains("_draw_emergency_buddy"):
        _failures.append("emergency buddy draw path is absent")
    if source.contains("_load_face_overlay_for_frame") or source.contains("/frames/%03d.json"):
        _failures.append("shipping runtime still loads excluded per-frame metadata")
    if source.contains("_load_texture_from_file(path_spec)") or source.contains("_read_text_file(path_spec)"):
        _failures.append("process-relative resource fallback remains in shipping runtime")
