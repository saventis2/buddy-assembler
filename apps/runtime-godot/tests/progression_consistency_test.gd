extends Node

const BondService = preload("res://scripts/services/bond_service.gd")
const UnlockTable = preload("res://scripts/progression/unlock_table.gd")
const CORE_MANIFEST_PATH := "res://content/core_pack/manifest.json"
const TIERS_PATH := "res://content/core_pack/progression/bond_tiers.json"

var _failed := 0
var _ran := 0


func _ready() -> void:
	_run_all()
	if _failed == 0:
		print("progression_consistency_test: PASS (%d cases)" % _ran)
		get_tree().quit(0)
	else:
		push_error("progression_consistency_test: FAIL (%d/%d failed)" % [_failed, _ran])
		get_tree().quit(1)


func _run_all() -> void:
	_case("tracked_config_matches_runtime", _test_tracked_config_matches_runtime)
	_case("unlock_rows_resolve_to_shipping_actions", _test_unlock_rows_resolve_to_shipping_actions)
	_case("xp_thresholds_match_bond_service", _test_xp_thresholds_match_bond_service)
	_case("bond_level_is_clamped", _test_bond_level_is_clamped)


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var error: Variant = body.call()
	if error != null and str(error) != "":
		_failed += 1
		push_error("progression_consistency_test[%s]: %s" % [name, error])
	else:
		print("progression_consistency_test[%s]: ok" % name)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return "missing tracked JSON: %s" % path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return "expected JSON object: %s" % path
	return parsed


func _validate_tracked_unlock_contract(
	tiers: Dictionary, runtime_rows: Array, runtime_actions: Array
) -> Variant:
	if not tiers.has("unlocks"):
		return "tracked tiers must define unlocks"
	var tracked_value: Variant = tiers["unlocks"]
	if typeof(tracked_value) != TYPE_ARRAY:
		return "tracked tiers unlocks must be an array"
	var tracked_rows := tracked_value as Array
	if tracked_rows.is_empty():
		return "tracked tiers unlocks must not be empty"
	for row_value in tracked_rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			return "tracked unlock row is not an object"
	if tracked_rows != runtime_rows:
		return "tracked unlock rows do not exactly match runtime unlock rows"

	var tracked_action_ids: Array = []
	for row_value in tracked_rows:
		var row := row_value as Dictionary
		if str(row.get("type", "")) == "action":
			tracked_action_ids.append(str(row.get("value", "")))
	var runtime_unlock_action_ids: Array = []
	for action_id_value in runtime_actions:
		var action_id := str(action_id_value)
		if not UnlockTable.BASE_ACTIONS.has(action_id):
			runtime_unlock_action_ids.append(action_id)
	if tracked_action_ids != runtime_unlock_action_ids:
		return "tracked unlock actions do not exactly match runtime unlock actions"
	return null


func _test_tracked_config_matches_runtime() -> Variant:
	var parsed: Variant = _read_json(TIERS_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		return parsed
	var tiers := parsed as Dictionary
	var configured_xp := int(tiers.get("xp_per_level", 0))
	var configured_max := int(tiers.get("max_level", 0))
	if configured_xp <= 0 or configured_max <= 0:
		return "xp_per_level and max_level must both be positive"
	if UnlockTable.xp_per_level() != configured_xp:
		return "UnlockTable xp_per_level does not match tracked tiers"
	if UnlockTable.max_level() != configured_max:
		return "UnlockTable max_level does not match tracked tiers"

	var runtime_rows := UnlockTable.all_unlock_rows()
	var runtime_actions := UnlockTable.unlocked_action_ids(UnlockTable.max_level())
	var unlock_error: Variant = _validate_tracked_unlock_contract(tiers, runtime_rows, runtime_actions)
	if unlock_error != null:
		return unlock_error

	var missing_unlocks := tiers.duplicate(true)
	missing_unlocks.erase("unlocks")
	var wrong_type_unlocks := tiers.duplicate(true)
	wrong_type_unlocks["unlocks"] = {}
	var empty_unlocks := tiers.duplicate(true)
	empty_unlocks["unlocks"] = []
	var incomplete_unlocks := tiers.duplicate(true)
	var incomplete_rows := runtime_rows.duplicate(true)
	incomplete_rows.pop_back()
	incomplete_unlocks["unlocks"] = incomplete_rows
	var negative_cases: Array = [
		{"name": "missing", "config": missing_unlocks},
		{"name": "wrong-type", "config": wrong_type_unlocks},
		{"name": "empty", "config": empty_unlocks},
		{"name": "incomplete", "config": incomplete_unlocks},
	]
	for negative_value in negative_cases:
		var negative := negative_value as Dictionary
		var candidate := negative["config"] as Dictionary
		if _validate_tracked_unlock_contract(candidate, runtime_rows, runtime_actions) == null:
			return "unlock validator accepted %s tracked unlocks" % str(negative["name"])
	return null


func _test_unlock_rows_resolve_to_shipping_actions() -> Variant:
	var manifest_value: Variant = _read_json(CORE_MANIFEST_PATH)
	if typeof(manifest_value) != TYPE_DICTIONARY:
		return manifest_value
	var manifest := manifest_value as Dictionary
	var visual: Variant = manifest.get("visual", {})
	var animations: Variant = (visual as Dictionary).get("animations", {}) if typeof(visual) == TYPE_DICTIONARY else {}
	if typeof(animations) != TYPE_DICTIONARY:
		return "core manifest visual.animations is not an object"

	var seen_ids: Dictionary = {}
	var seen_actions: Dictionary = {}
	var previous_level := 0
	for row_value in UnlockTable.all_unlock_rows():
		if typeof(row_value) != TYPE_DICTIONARY:
			return "unlock row is not an object"
		var row := row_value as Dictionary
		var level := int(row.get("level", 0))
		var row_id := str(row.get("id", ""))
		var action_id := str(row.get("value", ""))
		if level < 1 or level > UnlockTable.max_level():
			return "unlock %s has out-of-range level %d" % [row_id, level]
		if level < previous_level:
			return "unlock rows are not ordered by level"
		previous_level = level
		if row_id == "" or seen_ids.has(row_id):
			return "unlock ids must be non-empty and unique: %s" % row_id
		seen_ids[row_id] = true
		if str(row.get("type", "")) == "action":
			if action_id == "" or not (animations as Dictionary).has(action_id):
				return "unlock action is absent from shipping animations: %s" % action_id
			if seen_actions.has(action_id):
				return "duplicate unlock action: %s" % action_id
			seen_actions[action_id] = true
			if UnlockTable.unlocked_action_ids(level - 1).has(action_id):
				return "action %s unlocks before configured level %d" % [action_id, level]
			if not UnlockTable.unlocked_action_ids(level).has(action_id):
				return "action %s is missing at configured level %d" % [action_id, level]

	var expected_unlock_actions: Array = []
	for animation_id_value in (animations as Dictionary).keys():
		var animation_id := str(animation_id_value)
		if not UnlockTable.BASE_ACTIONS.has(animation_id):
			expected_unlock_actions.append(animation_id)
	expected_unlock_actions.sort()
	var configured_unlock_actions := seen_actions.keys()
	configured_unlock_actions.sort()
	if configured_unlock_actions != expected_unlock_actions:
		return (
			"configured action unlocks are incomplete: expected %s, got %s"
			% [expected_unlock_actions, configured_unlock_actions]
		)
	return null


func _test_xp_thresholds_match_bond_service() -> Variant:
	var service := BondService.new()
	var xp_per_level := UnlockTable.xp_per_level()
	var max_level := UnlockTable.max_level()
	for expected_level in range(1, max_level + 1):
		var threshold := (expected_level - 1) * xp_per_level
		var status := service.get_status({"bond_xp": threshold}, xp_per_level, max_level)
		if int(status.get("bond_level", 0)) != expected_level:
			return "xp %d expected level %d, got %s" % [threshold, expected_level, status]
		if expected_level < max_level:
			var before_next := service.get_status(
				{"bond_xp": (expected_level * xp_per_level) - 1}, xp_per_level, max_level
			)
			if int(before_next.get("bond_level", 0)) != expected_level:
				return "level advanced before threshold %d" % (expected_level * xp_per_level)
	return null


func _test_bond_level_is_clamped() -> Variant:
	var service := BondService.new()
	var xp_per_level := UnlockTable.xp_per_level()
	var max_level := UnlockTable.max_level()
	var below_zero := service.get_status({"bond_xp": -100}, xp_per_level, max_level)
	if int(below_zero.get("bond_xp", -1)) != 0 or int(below_zero.get("bond_level", 0)) != 1:
		return "negative xp was not clamped to level 1: %s" % below_zero
	var above_cap := service.get_status({"bond_xp": 999999}, xp_per_level, max_level)
	if int(above_cap.get("bond_level", 0)) != max_level:
		return "large xp was not clamped to max level %d: %s" % [max_level, above_cap]
	return null
