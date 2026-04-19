@tool
extends EditorPlugin

var _import_plugin: EditorImportPlugin


func _enter_tree() -> void:
	_import_plugin = preload("res://addons/buddy_importer/buddy_importer_plugin_import.gd").new()
	add_import_plugin(_import_plugin)


func _exit_tree() -> void:
	if _import_plugin != null:
		remove_import_plugin(_import_plugin)
