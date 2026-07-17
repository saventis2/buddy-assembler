extends Node

const PortableBuddyFallback = preload("res://scripts/visual/portable_buddy_fallback.gd")
const ANIMATION_ROOT := "res://content/core_pack/character/animations"
const ACTIONS := ["idle", "wander", "sit", "sleep", "happy", "gift", "visitor"]

var _failures: Array[String] = []


func _ready() -> void:
    _check_path_boundary()
    _check_presentation_modes()
    _check_all_shipping_frames()
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
            var plan := PortableBuddyFallback.face_plan(action, int(frame.get("index", checked)), source_size)
            if not bool(plan.get("complete", false)):
                _failures.append("incomplete code face for %s frame %s" % [action, frame.get("index", "?")])
            checked += 1
    if checked != 19:
        _failures.append("expected 19 shipping frames, checked %d" % checked)


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
