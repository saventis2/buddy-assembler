extends Node

const PortableBuddyFallback = preload("res://scripts/visual/portable_buddy_fallback.gd")
const BuddyOverlayScript = preload("res://scripts/buddy_overlay.gd")
const USER_PACK_MANIFESTS := [
    "res://content/core_pack/manifest.json",
    "res://content/night_pack/manifest.json",
]
const VIEWPORT_SIZE := Vector2(340.0, 340.0)
const VIEW_MARGIN := 4.0

var _failures: Array[String] = []


func _ready() -> void:
    _check_path_boundary()
    _check_asset_only_presentation()
    _check_fallback_viewport()
    _check_process_relative_decoys()
    _check_shipping_source_policy()
    if _failures.is_empty():
        print("portable_visual_fallback_test: PASS (existing assets only)")
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


func _check_asset_only_presentation() -> void:
    if PortableBuddyFallback.presentation_mode(Vector2(64.0, 80.0), Vector2(65.0, 88.0)) != PortableBuddyFallback.PRESENTATION_SELECTED_ASSET:
        _failures.append("usable selected asset was not preferred")
    if PortableBuddyFallback.presentation_mode(Vector2.ZERO, Vector2(65.0, 88.0)) != PortableBuddyFallback.PRESENTATION_FALLBACK_ASSET:
        _failures.append("missing selected asset did not choose the tracked fallback asset")
    if PortableBuddyFallback.presentation_mode(Vector2(-1.0, 40.0), Vector2(65.0, 88.0)) != PortableBuddyFallback.PRESENTATION_FALLBACK_ASSET:
        _failures.append("invalid selected asset dimensions did not choose the tracked fallback asset")
    if PortableBuddyFallback.presentation_mode(Vector2.ZERO, Vector2.ZERO) != PortableBuddyFallback.PRESENTATION_UNAVAILABLE:
        _failures.append("missing selected and fallback assets did not fail honestly")

    if PortableBuddyFallback.VALID_FACE_MODES != [PortableBuddyFallback.FACE_MODE_EMBEDDED]:
        _failures.append("face policy permits a non-embedded drawing mode")
    for manifest_path in USER_PACK_MANIFESTS:
        var file := FileAccess.open(manifest_path, FileAccess.READ)
        if file == null:
            _failures.append("missing user pack manifest: %s" % manifest_path)
            continue
        var parsed = JSON.parse_string(file.get_as_text())
        file.close()
        if typeof(parsed) != TYPE_DICTIONARY:
            _failures.append("invalid user pack manifest: %s" % manifest_path)
            continue
        var visual = (parsed as Dictionary).get("visual", {})
        if typeof(visual) != TYPE_DICTIONARY or str((visual as Dictionary).get("faceMode", "")) != PortableBuddyFallback.FACE_MODE_EMBEDDED:
            _failures.append("user pack does not use embedded repository artwork: %s" % manifest_path)


func _check_fallback_viewport() -> void:
    if PortableBuddyFallback.FALLBACK_TEXTURE_PATH != "res://content/core_pack/character/idle.png":
        _failures.append("fallback does not identify the approved tracked idle asset")
        return
    if not ResourceLoader.exists(PortableBuddyFallback.FALLBACK_TEXTURE_PATH, "Texture2D"):
        _failures.append("tracked fallback texture is unavailable")
        return
    var texture := load(PortableBuddyFallback.FALLBACK_TEXTURE_PATH) as Texture2D
    if texture == null:
        _failures.append("tracked fallback texture did not load")
        return
    var rect := PortableBuddyFallback.fitted_asset_rect(
        VIEWPORT_SIZE,
        texture.get_size(),
        2.35,
        VIEW_MARGIN
    )
    if rect.size.x <= 0.0 or rect.size.y <= 0.0:
        _failures.append("fallback asset produced an empty draw rectangle")
    if rect.position.x < VIEW_MARGIN or rect.position.y < VIEW_MARGIN:
        _failures.append("fallback asset starts outside the safe viewport: %s" % rect)
    if rect.end.x > VIEWPORT_SIZE.x - VIEW_MARGIN or rect.end.y > VIEWPORT_SIZE.y - VIEW_MARGIN:
        _failures.append("fallback asset ends outside the safe viewport: %s" % rect)


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


func _check_shipping_source_policy() -> void:
    var file := FileAccess.open("res://scripts/buddy_overlay.gd", FileAccess.READ)
    if file == null:
        _failures.append("could not inspect shipping overlay source")
        return
    var source := file.get_as_text()
    file.close()
    if source.contains("missing_rect"):
        _failures.append("red missing-asset box remains in shipping draw path")
    if source.contains("_draw_code_face") or source.contains("code_face_geometry"):
        _failures.append("shipping runtime still contains a code-drawn face path")
    if source.contains("_draw_emergency_buddy"):
        _failures.append("shipping runtime still contains a code-drawn emergency buddy")
    if source.contains("draw_circle(") or source.contains("draw_arc("):
        _failures.append("shipping overlay still draws replacement facial or character graphics")
    if not source.contains("PORTABLE_FALLBACK_TEXTURE") or not source.contains(PortableBuddyFallback.FALLBACK_TEXTURE_PATH):
        _failures.append("shipping runtime does not preload the approved fallback asset")
    if source.contains("_load_face_overlay_for_frame") or source.contains("/frames/%03d.json"):
        _failures.append("shipping runtime still loads excluded per-frame metadata")
    if source.contains("_load_texture_from_file(path_spec)") or source.contains("_read_text_file(path_spec)"):
        _failures.append("process-relative resource fallback remains in shipping runtime")
