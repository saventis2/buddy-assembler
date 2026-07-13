extends Node

const BondService = preload("res://scripts/services/bond_service.gd")
const GrowthService = preload("res://scripts/services/growth_service.gd")

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
	_case("reconcile_profile_recomputes_level_from_xp_curve", func(): return _test_reconcile_profile_recomputes_level_from_xp_curve())
	_case("reconcile_stat_points_backfills_missing_unspent", func(): return _test_reconcile_stat_points_backfills_missing_unspent())
	_case("reconcile_stat_points_preserves_existing_bonus_points", func(): return _test_reconcile_stat_points_preserves_existing_bonus_points())


func _case(name: String, body: Callable) -> void:
	_ran += 1
	var err: Variant = body.call()
	if err != null and typeof(err) == TYPE_STRING and err != "":
		_failed += 1
		push_error("progression_consistency_test[%s]: %s" % [name, err])
	else:
		print("progression_consistency_test[%s]: ok" % name)


func _test_reconcile_profile_recomputes_level_from_xp_curve() -> Variant:
	var svc := BondService.new()
	var profile := svc.ensure_profile({
		"bond_xp": 595,
		"bond_level": 10,
	})
	var curve := [0, 8, 18, 30, 44, 60, 78, 98, 121, 146, 174, 205, 239, 276, 316, 359, 405, 454, 506, 561]
	profile = svc.reconcile_profile(profile, 10, 20, curve)
	var level := int(profile.get("bond_level", 1))
	if level != 20:
		return "expected bond_level=20 for xp=595 with curve max=20, got %d" % level
	return null


func _test_reconcile_stat_points_backfills_missing_unspent() -> Variant:
	var svc := GrowthService.new()
	var profile := svc.ensure_profile({
		"bond_level": 6,
		"stat_points_spent": 6,
		"stat_points_unspent": 0,
	})
	profile = svc.reconcile_stat_points(profile)
	var unspent := int(profile.get("stat_points_unspent", 0))
	# Earned at level 6 = (6 - 1) * 3 = 15; spent=6 -> minimum unspent=9.
	if unspent != 9:
		return "expected unspent stat points to reconcile to 9, got %d" % unspent
	return null


func _test_reconcile_stat_points_preserves_existing_bonus_points() -> Variant:
	var svc := GrowthService.new()
	var profile := svc.ensure_profile({
		"bond_level": 6,
		"stat_points_spent": 6,
		"stat_points_unspent": 12,
	})
	profile = svc.reconcile_stat_points(profile)
	var unspent := int(profile.get("stat_points_unspent", 0))
	if unspent != 12:
		return "expected existing unspent bonus points preserved at 12, got %d" % unspent
	return null
