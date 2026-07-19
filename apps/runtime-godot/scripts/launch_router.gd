extends Node

const DEFAULT_SCENE := "res://scenes/BuddyOverlay.tscn"
const VERTICAL_SLICE_SCENE := "res://scenes/vertical_slice/VerticalSliceMain.tscn"
const ContentLoader = preload("res://scripts/content/content_loader.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--verify-export-closure"):
		call_deferred("_verify_export_closure")
		return
	if args.has("--ci-startup-smoke"):
		call_deferred("_run_ci_startup_smoke")
		return
	var target_scene := _target_scene_from_args(args)
	call_deferred("_switch_to_scene", target_scene)


func _target_scene_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg == "--vertical-slice":
			if ResourceLoader.exists(VERTICAL_SLICE_SCENE):
				return VERTICAL_SLICE_SCENE
			push_warning("Vertical-slice resources are not part of the shipping payload.")
			return DEFAULT_SCENE
		if arg == "--default-overlay":
			return DEFAULT_SCENE
	return DEFAULT_SCENE


func _switch_to_scene(path: String) -> void:
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to load launch target scene: %s" % path)


func _run_ci_startup_smoke() -> void:
	var resource := load(DEFAULT_SCENE)
	if not resource is PackedScene:
		push_error("project_startup_smoke: default scene did not load as PackedScene")
		get_tree().quit(1)
		return
	var instance := (resource as PackedScene).instantiate()
	if instance == null:
		push_error("project_startup_smoke: default scene did not instantiate")
		get_tree().quit(1)
		return
	add_child(instance)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(instance) or not instance.is_inside_tree():
		push_error("project_startup_smoke: default scene did not enter the scene tree")
		get_tree().quit(1)
		return
	print("project_startup_smoke: PASS")
	instance.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _verify_export_closure() -> void:
	var failures: Array[String] = []
	var required_files := [
		"res://content/core_pack/manifest.json",
		"res://content/night_pack/manifest.json",
		"res://content/core_pack/character/animations/idle.json",
		"res://content/core_pack/character/animations/wander.json",
		"res://content/core_pack/character/animations/sit.json",
		"res://content/core_pack/character/animations/sleep.json",
		"res://content/core_pack/character/animations/happy.json",
		"res://content/core_pack/character/animations/gift.json",
		"res://content/core_pack/character/animations/visitor.json",
		"res://content/core_pack/character/emotes/manifest.json",
		"res://content/core_pack/effects/chair_basic/effect.json",
		"res://content/core_pack/progression/bond_tiers.json",
	]
	for path in required_files:
		if not FileAccess.file_exists(path):
			failures.append("missing required file: %s" % path)

	var required_resources := [
		"res://scenes/BuddyOverlay.tscn",
		"res://content/core_pack/effects/chair_basic/frames/000.png",
	]
	for action in ["idle", "wander", "sit", "sleep", "happy", "gift", "visitor"]:
		required_resources.append("res://content/core_pack/character/%s.png" % action)
		required_resources.append("res://content/core_pack/character/animations/%s_sheet.png" % action)
	for path in required_resources:
		if not ResourceLoader.exists(path):
			failures.append("missing required resource: %s" % path)

	var forbidden_files := [
		"res://content/sample_pack/manifest.json",
		"res://content/core_pack/character/animations/idle/frames/000.json",
		"res://addons/buddy_importer/plugin.cfg",
	]
	for path in forbidden_files:
		if FileAccess.file_exists(path):
			failures.append("development file leaked into export: %s" % path)

	var forbidden_resources := [
		"res://scenes/vertical_slice/VerticalSliceMain.tscn",
		"res://tests/PortableVisualFallbackTest.tscn",
		"res://runtime/actor/character_renderer_2d.gd",
		"res://content/core_pack/character_visitor/idle.png",
		"res://content/core_pack/character/animations/alt_idle_sheet.png",
	]
	for path in forbidden_resources:
		if ResourceLoader.exists(path):
			failures.append("development resource leaked into export: %s" % path)

	for pack_id in ["core_pack", "night_pack"]:
		var loaded := ContentLoader.load_pack(pack_id)
		if not bool(loaded.get("ok", false)):
			failures.append("shipping pack failed exported load: %s -> %s" % [pack_id, loaded.get("errors", [])])
	var cycleable := ContentLoader.list_cycleable_pack_ids()
	if cycleable != ["core_pack", "night_pack"]:
		failures.append("unexpected exported user pack cycle: %s" % [cycleable])

	if not failures.is_empty():
		for failure in failures:
			push_error("export_closure_check: %s" % failure)
		get_tree().quit(1)
		return
	print("export_closure_check: PASS")
	get_tree().quit(0)
