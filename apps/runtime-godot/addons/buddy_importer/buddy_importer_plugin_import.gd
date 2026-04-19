@tool
extends EditorImportPlugin

const FORMAT_VERSION := 1

# Preload type scripts directly instead of relying on global class_name lookup.
# Headless CI first-run has an empty global_script_class_cache.cfg, so global
# names like ActorDefinition resolve as "Identifier not declared" during parse.
const ActorDefinitionType = preload("res://content/types/actor_definition.gd")
const AnimationClipType = preload("res://content/types/animation_clip.gd")
const CollisionMapResourceType = preload("res://content/types/collision_map_resource.gd")


func _get_importer_name() -> String:
	return "buddy_importer.bif"


func _get_visible_name() -> String:
	return "Buddy Intermediate Importer"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["bif"])


func _get_save_extension() -> String:
	return "tres"


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_resource_type() -> String:
	return "Resource"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array:
	return [
		{"name": "preserve_source_debug", "default_value": true},
	]


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _get_format_version() -> int:
	return FORMAT_VERSION


func _can_import_threaded() -> bool:
	return true


func _import(
	source_file: String,
	save_path: String,
	_options: Dictionary,
	_platform_variants: Array[String],
	_gen_files: Array[String]
) -> Error:
	var file := FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		return ERR_CANT_OPEN
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR

	var source_data: Dictionary = parsed
	var kind := str(source_data.get("kind", ""))

	var _provenance_meta = source_data.get("metadata", {})
	if typeof(_provenance_meta) == TYPE_DICTIONARY:
		var _source_hash := str((_provenance_meta as Dictionary).get("source_hash", ""))
		if _source_hash == "" or _source_hash == "unknown":
			push_warning(
				"BIF import: missing or unknown provenance hash in '%s'. " +
				"Re-run the converter with --source-hash to include it." % source_file
			)

	if kind == "actor":
		var actor := ActorDefinitionType.new()
		actor.actor_id = str(source_data.get("actor_id", ""))
		actor.display_name = str(source_data.get("display_name", ""))
		actor.semantic_defaults = source_data.get("semantic_defaults", {}).duplicate()
		actor.metadata = source_data.get("metadata", {}).duplicate()
		actor.metadata["import_format_version"] = FORMAT_VERSION
		actor.metadata["source_file"] = source_file
		return ResourceSaver.save(actor, "%s.%s" % [save_path, _get_save_extension()])

	if kind == "anim":
		var clip := AnimationClipType.new()
		clip.clip_id = str(source_data.get("clip_id", ""))
		clip.loop = bool(source_data.get("loop", true))
		clip.frames = _to_dictionary_array(source_data.get("frames", []))
		clip.metadata = source_data.get("metadata", {}).duplicate()
		clip.metadata["import_format_version"] = FORMAT_VERSION
		clip.metadata["source_file"] = source_file
		return ResourceSaver.save(clip, "%s.%s" % [save_path, _get_save_extension()])

	if kind == "map":
		var map_res := CollisionMapResourceType.new()
		map_res.map_id = str(source_data.get("map_id", ""))
		var spawn = source_data.get("spawn_point", {})
		if typeof(spawn) == TYPE_DICTIONARY:
			map_res.spawn_point = Vector2(float(spawn.get("x", 0.0)), float(spawn.get("y", 0.0)))
		map_res.footholds = _to_dictionary_array(source_data.get("footholds", []))
		map_res.ladders = _to_dictionary_array(source_data.get("ladders", []))
		map_res.portals = _to_dictionary_array(source_data.get("portals", []))
		map_res.interaction_markers = source_data.get("interaction_markers", {}).duplicate()
		map_res.metadata = source_data.get("metadata", {}).duplicate()
		map_res.metadata["import_format_version"] = FORMAT_VERSION
		map_res.metadata["source_file"] = source_file
		return ResourceSaver.save(map_res, "%s.%s" % [save_path, _get_save_extension()])

	return ERR_INVALID_DATA


func _to_dictionary_array(value) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return rows
	for item in value:
		if typeof(item) == TYPE_DICTIONARY:
			rows.append((item as Dictionary).duplicate())
	return rows
