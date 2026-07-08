extends RefCounted

const DEFAULT_WALLET := {"meso": 0, "crystals": 0}
const DEFAULT_EQUIPPED_SLOTS := {
    # WZ/Maple-style core equipment slots.
    "weapon": -1,
    "shield": -1,
    "hat": -1,
    "face_accessory": -1,
    "eye_accessory": -1,
    "earrings": -1,
    "overall": -1,
    "top": -1,
    "bottom": -1,
    "shoes": -1,
    "gloves": -1,
    "cape": -1,
    "belt": -1,
    "shoulder": -1,
    "medal": -1,
    "badge": -1,
    "emblem": -1,
    "pocket": -1,
    "pendant1": -1,
    "pendant2": -1,
    "ring1": -1,
    "ring2": -1,
    "ring3": -1,
    "ring4": -1,
    # Legacy compatibility slots used by earlier runtime revisions.
    "gear": -1,
    "charm": -1,
    "relic": -1,
}
const DEFAULT_BOXES := {
    "cozy_box": {
        "theme": "cozy",
        "cost": 15,
        "table": [
            {"id": "cozy-lamp", "category": "decor", "rarity": "uncommon", "weight": 50},
            {"id": "warm-tea", "category": "food", "rarity": "common", "weight": 70},
            {"id": "plush-heart", "category": "gifts", "rarity": "rare", "weight": 25},
        ],
    },
    "heroic_box": {
        "theme": "heroic",
        "cost": 20,
        "table": [
            {"id": "hero-ribbon", "category": "training_items", "rarity": "uncommon", "weight": 55},
            {"id": "focus-badge", "category": "gear", "rarity": "rare", "weight": 35},
            {"id": "victory-banner", "category": "decor", "rarity": "epic", "weight": 10},
        ],
    },
}
const LEGACY_ICON_BY_ITEM_ID := {
    "cozy-lamp": "effects/chair_basic/frames/000.png",
    "plush-heart": "effects/happy_sparkle/frames/000.png",
    "warm-tea": "effects/gift_box/frames/000.png",
    "hero-ribbon": "effects/levelup/frames/000.png",
    "focus-badge": "effects/levelup/frames/001.png",
    "victory-banner": "effects/visitor_arrival/frames/000.png",
}
const LEGACY_ITEM_ID_REMAP := {
    "cozy-lamp": "wz-rocky-mask-doll",
    "warm-tea": "wz-tri-colored-dango",
    "plush-heart": "wz-green-halloween-stick-candy",
}
const CANONICAL_ITEM_KEYS := [
    "name",
    "description",
    "category",
    "rarity",
    "primaryTheme",
    "secondaryThemes",
    "iconAsset",
    "wzIconPath",
    "wzId",
    "wzRoot",
    "wzGroup",
    "price",
    "slotMax",
    "equipSlot",
    "effectProfile",
    "effects",
]
const JOB_MATCH_WEIGHT_MULTIPLIER := 1.45
const PRIMARY_STAT_WEIGHT_MULTIPLIER := 1.35
const DROP_BIAS_WEIGHT_MULTIPLIER := 1.25
const JOB_SLOT_WEIGHT_MULTIPLIER := 1.20
const JOB_SLOT_AFFINITY := {
    "explorer_warrior": ["weapon", "shield", "overall", "top", "bottom", "gloves"],
    "explorer_mage": ["weapon", "hat", "cape", "face_accessory", "eye_accessory"],
    "explorer_bowman": ["weapon", "top", "bottom", "shoes", "gloves"],
    "explorer_thief": ["weapon", "shoes", "gloves", "cape", "ring1", "ring2"],
    "explorer_pirate": ["weapon", "overall", "top", "bottom", "belt", "medal"],
}
const STAT_SLOT_HINTS := {
    "strength": ["weapon", "shield", "overall", "top", "bottom", "gloves"],
    "dexterity": ["weapon", "shoes", "gloves", "cape"],
    "charisma": ["face_accessory", "eye_accessory", "ring1", "ring2", "pendant1", "pendant2"],
    "endurance": ["overall", "top", "bottom", "belt", "medal", "badge"],
    "wisdom": ["hat", "cape", "pendant1", "pendant2"],
    "knowledge": ["weapon", "hat", "face_accessory", "eye_accessory", "cape"],
}


func ensure_world_state(world_state: Dictionary) -> Dictionary:
    var merged := world_state.duplicate(true)
    if typeof(merged.get("wallet", null)) != TYPE_DICTIONARY:
        merged["wallet"] = DEFAULT_WALLET.duplicate(true)
    if typeof(merged.get("inventory", null)) != TYPE_ARRAY:
        merged["inventory"] = []
    if typeof(merged.get("reward_transactions", null)) != TYPE_ARRAY:
        merged["reward_transactions"] = []
    if typeof(merged.get("reward_boxes", null)) != TYPE_DICTIONARY:
        merged["reward_boxes"] = DEFAULT_BOXES.duplicate(true)
    if typeof(merged.get("item_catalog", null)) != TYPE_DICTIONARY:
        merged["item_catalog"] = {}
    if typeof(merged.get("inventory_quarantine", null)) != TYPE_ARRAY:
        merged["inventory_quarantine"] = []
    if typeof(merged.get("duplicate_recycles", null)) != TYPE_ARRAY:
        merged["duplicate_recycles"] = []
    if typeof(merged.get("box_low_value_streaks", null)) != TYPE_DICTIONARY:
        merged["box_low_value_streaks"] = {}
    if typeof(merged.get("box_open_stats", null)) != TYPE_DICTIONARY:
        merged["box_open_stats"] = {}
    if typeof(merged.get("drop_tables", null)) != TYPE_DICTIONARY:
        merged["drop_tables"] = {}
    if typeof(merged.get("equipped_slots", null)) != TYPE_DICTIONARY:
        merged["equipped_slots"] = DEFAULT_EQUIPPED_SLOTS.duplicate(true)
    else:
        var equipped_slots: Dictionary = merged.get("equipped_slots", {}).duplicate(true)
        _normalize_equipped_slots_dict(equipped_slots)
        merged["equipped_slots"] = equipped_slots
    if not merged.has("next_item_instance_id"):
        merged["next_item_instance_id"] = 1
    merged["wallet"] = _normalize_wallet((merged.get("wallet", {}) as Dictionary).duplicate(true))
    _normalize_inventory_instances(merged)
    return merged


func configure_from_manifest(world_state: Dictionary, manifest: Dictionary) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var catalog: Dictionary = merged.get("item_catalog", {}).duplicate(true)
    var has_manifest_items := false
    var items_variant = manifest.get("items", [])
    if typeof(items_variant) == TYPE_ARRAY:
        has_manifest_items = true
        catalog.clear()
        for row_variant in items_variant:
            if typeof(row_variant) != TYPE_DICTIONARY:
                continue
            var row: Dictionary = row_variant
            var item_id := str(row.get("id", ""))
            if item_id == "":
                continue
            catalog[item_id] = row.duplicate(true)
    if has_manifest_items:
        merged["item_catalog"] = catalog

    var boxes: Dictionary = merged.get("reward_boxes", DEFAULT_BOXES.duplicate(true))
    boxes = boxes.duplicate(true)
    var has_manifest_boxes := false
    var reward_boxes_variant = manifest.get("rewardBoxes", [])
    if typeof(reward_boxes_variant) == TYPE_ARRAY:
        has_manifest_boxes = true
        boxes = DEFAULT_BOXES.duplicate(true)
        for box_variant in reward_boxes_variant:
            if typeof(box_variant) != TYPE_DICTIONARY:
                continue
            var box: Dictionary = box_variant
            var box_id := str(box.get("id", ""))
            if box_id == "":
                continue
            var normalized := {
                "theme": str(box.get("theme", "cozy")),
                "cost": int(box.get("cost", 15)),
                "possibleItems": box.get("possibleItems", []),
                "categoryBias": box.get("categoryBias", {}),
                "rarityTable": box.get("rarityTable", {}),
            }
            boxes[box_id] = normalized
    if has_manifest_boxes:
        merged["reward_boxes"] = boxes

    var drop_tables: Dictionary = merged.get("drop_tables", {}).duplicate(true)
    var has_manifest_drop_tables := false
    var drop_tables_variant = manifest.get("dropTables", [])
    if typeof(drop_tables_variant) == TYPE_ARRAY:
        has_manifest_drop_tables = true
        drop_tables.clear()
        for table_variant in (drop_tables_variant as Array):
            if typeof(table_variant) != TYPE_DICTIONARY:
                continue
            var table: Dictionary = table_variant
            var table_id := str(table.get("id", ""))
            if table_id == "":
                continue
            var rows: Array = []
            var entries_variant = table.get("entries", [])
            if typeof(entries_variant) == TYPE_ARRAY:
                for entry_variant in (entries_variant as Array):
                    if typeof(entry_variant) != TYPE_DICTIONARY:
                        continue
                    var entry: Dictionary = entry_variant
                    var item_id := str(entry.get("itemId", ""))
                    if item_id == "":
                        continue
                    rows.append(
                        {
                            "itemId": item_id,
                            "weight": maxf(0.0, float(entry.get("weight", 1.0))),
                            "minLevel": int(entry.get("minLevel", 1)),
                            "jobAffinity": str(entry.get("jobAffinity", "")),
                        }
                    )
            drop_tables[table_id] = {"id": table_id, "entries": rows}
    if has_manifest_drop_tables:
        merged["drop_tables"] = drop_tables

    var currencies_variant = manifest.get("currencies", {})
    if typeof(currencies_variant) == TYPE_DICTIONARY:
        var currencies: Dictionary = currencies_variant
        var wallet: Dictionary = merged.get("wallet", {}).duplicate(true)
        if not wallet.has("meso") and not wallet.has("crystals"):
            wallet["meso"] = int(currencies.get("meso", currencies.get("crystals", 0)))
        merged["wallet"] = _normalize_wallet(wallet)
    _normalize_inventory_instances(merged)
    return merged


func backfill_inventory_from_catalog(world_state: Dictionary) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var before_json := JSON.stringify(merged.get("inventory", []))
    var before_quarantine := int((merged.get("inventory_quarantine", []) as Array).size())
    _normalize_inventory_instances(merged)
    var after_json := JSON.stringify(merged.get("inventory", []))
    var after_quarantine := int((merged.get("inventory_quarantine", []) as Array).size())
    return {
        "ok": true,
        "changed": before_json != after_json or before_quarantine != after_quarantine,
        "quarantine_count": after_quarantine,
        "world_state": merged,
    }


func repair_inventory_from_catalog(world_state: Dictionary) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var quarantine_variant = merged.get("inventory_quarantine", [])
    var quarantine: Array = quarantine_variant if typeof(quarantine_variant) == TYPE_ARRAY else []
    if quarantine.is_empty():
        return {
            "ok": true,
            "changed": false,
            "recovered_count": 0,
            "remaining_quarantine_count": 0,
            "world_state": merged,
        }

    var catalog_variant = merged.get("item_catalog", {})
    var catalog: Dictionary = catalog_variant if typeof(catalog_variant) == TYPE_DICTIONARY else {}
    var inventory: Array = merged.get("inventory", [])
    var recovered := 0
    var remaining: Array = []

    for entry_variant in quarantine:
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        var row_variant = entry.get("row", {})
        if typeof(row_variant) != TYPE_DICTIONARY:
            remaining.append(entry.duplicate(true))
            continue
        var row: Dictionary = (row_variant as Dictionary).duplicate(true)
        var item_id := str(row.get("id", ""))
        if item_id == "":
            item_id = str(entry.get("id", ""))
            if item_id != "":
                row["id"] = item_id
        var resolved := _resolve_catalog_item_id(item_id, catalog)
        if resolved == "" or not catalog.has(resolved):
            remaining.append(entry.duplicate(true))
            continue
        if resolved != item_id and item_id != "":
            row["legacyId"] = item_id
            row["id"] = resolved
        inventory.append(row)
        recovered += 1

    merged["inventory"] = inventory
    merged["inventory_quarantine"] = remaining
    _normalize_inventory_instances(merged)
    return {
        "ok": true,
        "changed": recovered > 0,
        "recovered_count": recovered,
        "remaining_quarantine_count": int((merged.get("inventory_quarantine", []) as Array).size()),
        "world_state": merged,
    }


func grant_crystals(world_state: Dictionary, source_type: String, amount: int) -> Dictionary:
    return grant_meso(world_state, source_type, amount)


func grant_meso(world_state: Dictionary, source_type: String, amount: int) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var wallet: Dictionary = merged.get("wallet", {}).duplicate(true)
    var next_amount: int = _wallet_get_meso(wallet) + max(0, amount)
    merged["wallet"] = _wallet_set_meso(wallet, next_amount)
    _record_tx(merged, source_type, [], max(0, amount))
    return merged


func grant_item(world_state: Dictionary, source_type: String, item: Dictionary) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var inventory: Array = merged.get("inventory", [])
    inventory.append(_attach_instance_id(merged, item))
    merged["inventory"] = inventory
    _record_tx(merged, source_type, [item], 0)
    return merged


func get_inventory_snapshot(world_state: Dictionary) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var wallet: Dictionary = merged.get("wallet", {})
    var inventory: Array = merged.get("inventory", [])
    var equipped_slots: Dictionary = merged.get("equipped_slots", {}).duplicate(true)
    var quarantine_count := int((merged.get("inventory_quarantine", []) as Array).size())
    var meso := _wallet_get_meso(wallet)
    return {
        "meso": meso,
        "crystals": meso,
        "inventory": inventory.duplicate(true),
        "equipped_slots": equipped_slots,
        "inventory_count": inventory.size(),
        "quarantine_count": quarantine_count,
    }


func clear_inventory(world_state: Dictionary, clear_quarantine := true) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var inventory_variant = merged.get("inventory", [])
    var inventory: Array = inventory_variant if typeof(inventory_variant) == TYPE_ARRAY else []
    var removed_count := inventory.size()

    var equipped_slots: Dictionary = merged.get("equipped_slots", {}).duplicate(true)
    _normalize_equipped_slots_dict(equipped_slots)
    var unequipped_count := 0
    for slot_variant in equipped_slots.keys():
        var slot := str(slot_variant)
        var equipped_id := int(equipped_slots.get(slot, -1))
        if equipped_id > 0:
            unequipped_count += 1
        equipped_slots[slot] = -1

    merged["inventory"] = []
    merged["equipped_slots"] = equipped_slots

    var cleared_quarantine := false
    if clear_quarantine:
        merged["inventory_quarantine"] = []
        cleared_quarantine = true

    return {
        "ok": true,
        "reason": "",
        "removed_count": removed_count,
        "unequipped_count": unequipped_count,
        "cleared_quarantine": cleared_quarantine,
        "world_state": merged,
    }


func get_item_instance(world_state: Dictionary, instance_id: int) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var idx := _find_inventory_index_by_instance_id(merged.get("inventory", []), instance_id)
    if idx < 0:
        return {"ok": false, "reason": "missing_item", "world_state": merged}
    var inventory: Array = merged.get("inventory", [])
    var row_variant = inventory[idx]
    if typeof(row_variant) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "invalid_item", "world_state": merged}
    return {
        "ok": true,
        "reason": "",
        "item": (row_variant as Dictionary).duplicate(true),
        "world_state": merged,
    }


func consume_item_instance(world_state: Dictionary, instance_id: int) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var inventory: Array = merged.get("inventory", [])
    var idx := _find_inventory_index_by_instance_id(inventory, instance_id)
    if idx < 0:
        return {"ok": false, "reason": "missing_item", "world_state": merged}
    var row_variant = inventory[idx]
    if typeof(row_variant) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "invalid_item", "world_state": merged}
    var item: Dictionary = (row_variant as Dictionary).duplicate(true)
    inventory.remove_at(idx)
    merged["inventory"] = inventory
    _clear_equipped_instance(merged, instance_id)
    return {
        "ok": true,
        "reason": "",
        "item": item,
        "world_state": merged,
    }


func equip_item_instance(world_state: Dictionary, instance_id: int) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var inventory: Array = merged.get("inventory", [])
    var idx := _find_inventory_index_by_instance_id(inventory, instance_id)
    if idx < 0:
        return {"ok": false, "reason": "missing_item", "world_state": merged}
    var row_variant = inventory[idx]
    if typeof(row_variant) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "invalid_item", "world_state": merged}
    var item: Dictionary = row_variant
    var slot := _derive_equip_slot(item)
    if slot == "":
        return {"ok": false, "reason": "not_equippable", "world_state": merged}
    var equipped_slots: Dictionary = merged.get("equipped_slots", {}).duplicate(true)
    _normalize_equipped_slots_dict(equipped_slots)
    # Ensure one instance cannot remain bound to multiple slots after slot-map updates.
    for prior_slot_variant in equipped_slots.keys():
        var prior_slot := str(prior_slot_variant)
        if int(equipped_slots.get(prior_slot_variant, -1)) == instance_id:
            equipped_slots[prior_slot] = -1
    if not equipped_slots.has(slot):
        equipped_slots[slot] = -1
    equipped_slots[slot] = instance_id
    merged["equipped_slots"] = equipped_slots
    return {
        "ok": true,
        "reason": "",
        "slot": slot,
        "item": item.duplicate(true),
        "world_state": merged,
    }


func unequip_slot(world_state: Dictionary, slot_id: String) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var slot := _normalize_slot_name(slot_id)
    var equipped_slots: Dictionary = merged.get("equipped_slots", {}).duplicate(true)
    _normalize_equipped_slots_dict(equipped_slots)
    if not equipped_slots.has(slot):
        return {"ok": false, "reason": "unknown_slot", "world_state": merged}
    equipped_slots[slot] = -1
    merged["equipped_slots"] = equipped_slots
    return {"ok": true, "reason": "", "slot": slot, "world_state": merged}


func open_reward_box(world_state: Dictionary, box_id: String, seed: int) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var boxes: Dictionary = merged.get("reward_boxes", {})
    if not boxes.has(box_id):
        return {"ok": false, "reason": "unknown_box", "world_state": merged}

    var box: Dictionary = boxes.get(box_id, {})
    var cost := int(box.get("cost", 9999))
    var wallet: Dictionary = merged.get("wallet", {}).duplicate(true)
    var meso := _wallet_get_meso(wallet)
    if meso < cost:
        return {
            "ok": false,
            "reason": "insufficient_meso",
            "legacy_reason": "insufficient_crystals",
            "world_state": merged
        }

    var table: Array = box.get("table", [])
    if table.is_empty():
        table = _build_table_from_manifest_catalog(merged, box)
    if table.is_empty():
        return {"ok": false, "reason": "empty_box", "world_state": merged}

    var rng := RandomNumberGenerator.new()
    rng.seed = seed if seed != 0 else int(Time.get_unix_time_from_system())
    var selected := _pick_weighted(table, rng)
    selected = _apply_low_value_protection(merged, box_id, selected, table, rng)
    var selected_id := str(selected.get("id", ""))
    var was_duplicate := _inventory_has_item_id(merged.get("inventory", []), selected_id)
    var recycle_meso := 0
    if was_duplicate:
        recycle_meso = _duplicate_recycle_meso_for(selected, cost)

    wallet = _wallet_set_meso(wallet, meso - cost)
    if recycle_meso > 0:
        wallet = _wallet_set_meso(wallet, _wallet_get_meso(wallet) + recycle_meso)
        _record_duplicate_recycle(merged, selected_id, recycle_meso)
    merged["wallet"] = _normalize_wallet(wallet)
    merged = grant_item(merged, "reward_box:%s" % box_id, selected)
    _record_box_open_stats(merged, box_id, str(box.get("theme", "unknown")), selected, was_duplicate, recycle_meso)
    return {
        "ok": true,
        "reason": "",
        "item": selected,
        "duplicate": was_duplicate,
        "recycleMeso": recycle_meso,
        "recycleCrystals": recycle_meso,
        "world_state": merged,
    }


func get_snapshot(world_state: Dictionary) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var wallet: Dictionary = merged.get("wallet", {})
    var inventory: Array = merged.get("inventory", [])
    var recycle_total := 0
    var recycles_variant = merged.get("duplicate_recycles", [])
    if typeof(recycles_variant) == TYPE_ARRAY:
        for row_variant in (recycles_variant as Array):
            if typeof(row_variant) != TYPE_DICTIONARY:
                continue
            recycle_total += int((row_variant as Dictionary).get("meso", (row_variant as Dictionary).get("crystals", 0)))
    var box_open_stats: Dictionary = merged.get("box_open_stats", {})
    var quarantine_count := int((merged.get("inventory_quarantine", []) as Array).size())
    var meso := _wallet_get_meso(wallet)
    return {
        "meso": meso,
        "crystals": meso,
        "inventory_count": inventory.size(),
        "quarantine_count": quarantine_count,
        "duplicate_recycle_total": recycle_total,
        "box_open_stats": box_open_stats,
    }


func list_reward_box_ids(world_state: Dictionary) -> Array:
    var merged := ensure_world_state(world_state)
    var boxes: Dictionary = merged.get("reward_boxes", {})
    return boxes.keys()


func roll_drop_table(
    world_state: Dictionary,
    table_id: String,
    context: Dictionary,
    seed: int
) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var drop_tables: Dictionary = merged.get("drop_tables", {})
    if table_id == "" or not drop_tables.has(table_id):
        return {"ok": false, "reason": "unknown_drop_table", "world_state": merged}
    var table_variant = drop_tables.get(table_id, {})
    if typeof(table_variant) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "invalid_drop_table", "world_state": merged}
    var table: Dictionary = table_variant
    var rows_variant = table.get("entries", [])
    if typeof(rows_variant) != TYPE_ARRAY or (rows_variant as Array).is_empty():
        return {"ok": false, "reason": "empty_drop_table", "world_state": merged}

    var level := int(context.get("level", 1))
    var pool := _build_drop_pool(rows_variant as Array, level, context, merged.get("item_catalog", {}))
    if pool.is_empty():
        return {"ok": false, "reason": "no_eligible_drop_rows", "world_state": merged}
    var rng := RandomNumberGenerator.new()
    rng.seed = seed if seed != 0 else int(Time.get_unix_time_from_system())
    var picked := _pick_weighted(pool, rng)
    if typeof(picked) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "drop_roll_failed", "world_state": merged}
    var item := (picked as Dictionary).duplicate(true)
    item.erase("weight")
    item.erase("jobAffinity")
    item.erase("minLevel")
    merged = grant_item(merged, "drop_table:%s" % table_id, item)
    return {"ok": true, "reason": "", "item": item, "world_state": merged}


func _pick_weighted(rows: Array, rng: RandomNumberGenerator) -> Dictionary:
    var total := 0.0
    for row_variant in rows:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        total += maxf(0.0, float((row_variant as Dictionary).get("weight", 0.0)))
    if total <= 0.0:
        return rows[0]

    var roll := rng.randf() * total
    var cumulative := 0.0
    for row_variant in rows:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        cumulative += maxf(0.0, float(row.get("weight", 0.0)))
        if roll <= cumulative:
            return row
    return rows[-1]


func _record_tx(world_state: Dictionary, source_type: String, item_rewards: Array, currency_rewards: int) -> void:
    var txs: Array = world_state.get("reward_transactions", [])
    txs.append(
        {
            "sourceType": source_type,
            "itemRewards": item_rewards,
            "currencyRewards": currency_rewards,
            "timestamp": Time.get_unix_time_from_system(),
        }
    )
    if txs.size() > 50:
        txs = txs.slice(txs.size() - 50, txs.size())
    world_state["reward_transactions"] = txs


func _build_table_from_manifest_catalog(world_state: Dictionary, box: Dictionary) -> Array:
    var table: Array = []
    var catalog: Dictionary = world_state.get("item_catalog", {})
    var item_ids_variant = box.get("possibleItems", [])
    var item_ids: Array = item_ids_variant if typeof(item_ids_variant) == TYPE_ARRAY else []
    var rarity_table_variant = box.get("rarityTable", {})
    var rarity_table: Dictionary = rarity_table_variant if typeof(rarity_table_variant) == TYPE_DICTIONARY else {}
    for item_id_variant in item_ids:
        var item_id := str(item_id_variant)
        if item_id == "" or not catalog.has(item_id):
            continue
        var item: Dictionary = (catalog[item_id] as Dictionary).duplicate(true)
        var rarity := str(item.get("rarity", "common")).to_lower()
        var weight := float(rarity_table.get(rarity, 10.0))
        item["weight"] = maxf(0.1, weight)
        table.append(item)
    return table


func _inventory_has_item_id(inventory_variant: Variant, item_id: String) -> bool:
    if item_id == "" or typeof(inventory_variant) != TYPE_ARRAY:
        return false
    for row_variant in (inventory_variant as Array):
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        if str((row_variant as Dictionary).get("id", "")) == item_id:
            return true
    return false


func _duplicate_recycle_crystals_for(item: Dictionary, box_cost: int) -> int:
    return _duplicate_recycle_meso_for(item, box_cost)


func _duplicate_recycle_meso_for(item: Dictionary, box_cost: int) -> int:
    var rarity := str(item.get("rarity", "common")).to_lower()
    var base := 1
    if rarity == "legendary":
        base = 12
    elif rarity == "epic":
        base = 7
    elif rarity == "rare":
        base = 4
    elif rarity == "uncommon":
        base = 2
    var capped_by_cost := maxi(1, int(floor(float(maxi(1, box_cost)) * 0.5)))
    return mini(base, capped_by_cost)


func _record_duplicate_recycle(world_state: Dictionary, item_id: String, meso: int) -> void:
    if meso <= 0:
        return
    var rows: Array = world_state.get("duplicate_recycles", [])
    rows.append(
        {
            "itemId": item_id,
            "meso": meso,
            "crystals": meso,
            "timestamp": Time.get_unix_time_from_system(),
        }
    )
    if rows.size() > 50:
        rows = rows.slice(rows.size() - 50, rows.size())
    world_state["duplicate_recycles"] = rows


func _apply_low_value_protection(
    world_state: Dictionary,
    box_id: String,
    selected: Dictionary,
    table: Array,
    rng: RandomNumberGenerator
) -> Dictionary:
    var streaks: Dictionary = world_state.get("box_low_value_streaks", {}).duplicate(true)
    var streak := int(streaks.get(box_id, 0))
    var rarity := str(selected.get("rarity", "common")).to_lower()
    var is_low_value := rarity == "common"

    if streak >= 3 and is_low_value:
        var promoted_pool := _filter_non_common(table)
        if not promoted_pool.is_empty():
            selected = _pick_weighted(promoted_pool, rng)
            rarity = str(selected.get("rarity", "common")).to_lower()
            is_low_value = rarity == "common"

    if is_low_value:
        streaks[box_id] = streak + 1
    else:
        streaks[box_id] = 0
    world_state["box_low_value_streaks"] = streaks
    return selected


func _filter_non_common(table: Array) -> Array:
    var filtered: Array = []
    for row_variant in table:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var rarity := str(row.get("rarity", "common")).to_lower()
        if rarity == "common":
            continue
        filtered.append(row)
    return filtered


func _record_box_open_stats(
    world_state: Dictionary,
    box_id: String,
    theme: String,
    item: Dictionary,
    duplicate: bool,
    recycle_meso: int
) -> void:
    var stats: Dictionary = world_state.get("box_open_stats", {}).duplicate(true)
    var theme_key := theme if theme != "" else "unknown"
    var row: Dictionary = stats.get(theme_key, {}).duplicate(true)
    row["opens"] = int(row.get("opens", 0)) + 1
    if duplicate:
        row["duplicates"] = int(row.get("duplicates", 0)) + 1
        row["recycle_meso"] = int(row.get("recycle_meso", row.get("recycle_crystals", 0))) + recycle_meso
        row["recycle_crystals"] = int(row.get("recycle_meso", 0))

    var rarity := str(item.get("rarity", "common")).to_lower()
    var rarity_counts: Dictionary = row.get("rarity_counts", {}).duplicate(true)
    rarity_counts[rarity] = int(rarity_counts.get(rarity, 0)) + 1
    row["rarity_counts"] = rarity_counts
    row["last_box_id"] = box_id
    row["last_item_id"] = str(item.get("id", ""))
    row["last_timestamp"] = Time.get_unix_time_from_system()
    stats[theme_key] = row
    world_state["box_open_stats"] = stats


func _wallet_get_meso(wallet: Dictionary) -> int:
    return int(wallet.get("meso", wallet.get("crystals", 0)))


func _wallet_set_meso(wallet: Dictionary, amount: int) -> Dictionary:
    var next: Dictionary = wallet.duplicate(true)
    var safe: int = max(0, amount)
    next["meso"] = safe
    next["crystals"] = safe
    return next


func _normalize_wallet(wallet: Dictionary) -> Dictionary:
    var normalized := wallet.duplicate(true)
    var meso := _wallet_get_meso(normalized)
    normalized["meso"] = meso
    normalized["crystals"] = meso
    return normalized


func _normalize_inventory_instances(world_state: Dictionary) -> void:
    var inventory: Array = world_state.get("inventory", [])
    var catalog_variant = world_state.get("item_catalog", {})
    var catalog: Dictionary = catalog_variant if typeof(catalog_variant) == TYPE_DICTIONARY else {}
    var quarantine_variant = world_state.get("inventory_quarantine", [])
    var quarantine: Array = quarantine_variant if typeof(quarantine_variant) == TYPE_ARRAY else []
    var normalized: Array = []
    var next_id := maxi(1, int(world_state.get("next_item_instance_id", 1)))
    for row_variant in inventory:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = (row_variant as Dictionary).duplicate(true)
        var item_id := str(row.get("id", ""))
        var resolved_item_id := _resolve_catalog_item_id(item_id, catalog)
        if resolved_item_id == "" or not catalog.has(resolved_item_id):
            quarantine = _append_inventory_quarantine(quarantine, row, "missing_catalog_item", resolved_item_id)
            continue
        row = _merge_item_row_from_catalog(row, catalog)
        var instance_id := int(row.get("instance_id", 0))
        if instance_id <= 0:
            instance_id = next_id
            next_id += 1
            row["instance_id"] = instance_id
        else:
            next_id = maxi(next_id, instance_id + 1)
        normalized.append(row)
    world_state["inventory"] = normalized
    world_state["inventory_quarantine"] = quarantine
    world_state["next_item_instance_id"] = next_id

    var valid_ids := {}
    for row_variant in normalized:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        valid_ids[int(row.get("instance_id", 0))] = true
    var equipped_slots: Dictionary = world_state.get("equipped_slots", DEFAULT_EQUIPPED_SLOTS).duplicate(true)
    _normalize_equipped_slots_dict(equipped_slots)
    for slot_variant in equipped_slots.keys():
        var slot := str(slot_variant)
        var equipped_id := int(equipped_slots.get(slot, -1))
        if equipped_id <= 0 or not valid_ids.has(equipped_id):
            equipped_slots[slot] = -1
    world_state["equipped_slots"] = equipped_slots


func _merge_item_row_from_catalog(row: Dictionary, catalog: Dictionary) -> Dictionary:
    var item_id := str(row.get("id", ""))
    if item_id == "":
        return row
    var merged := row.duplicate(true)
    var resolved_item_id := _resolve_catalog_item_id(item_id, catalog)
    if resolved_item_id != item_id:
        merged["legacyId"] = item_id
        merged["id"] = resolved_item_id
    if not catalog.has(resolved_item_id):
        return merged
    var source_variant = catalog.get(resolved_item_id, {})
    if typeof(source_variant) != TYPE_DICTIONARY:
        return merged
    var source: Dictionary = source_variant
    for key_variant in source.keys():
        var key := str(key_variant)
        if key == "" or key == "instance_id" or key == "id":
            continue
        if CANONICAL_ITEM_KEYS.has(key):
            merged[key] = source.get(key_variant)
            continue
        var existing = merged.get(key, null)
        var should_fill := false
        if existing == null:
            should_fill = true
        elif typeof(existing) == TYPE_STRING and str(existing).strip_edges() == "":
            should_fill = true
        elif typeof(existing) == TYPE_ARRAY and (existing as Array).is_empty():
            should_fill = true
        elif typeof(existing) == TYPE_DICTIONARY and (existing as Dictionary).is_empty():
            should_fill = true
        elif (key == "name" or key == "description") and str(existing).strip_edges() == item_id:
            should_fill = true
        if should_fill:
            merged[key] = source.get(key_variant)
    return merged


func _resolve_catalog_item_id(item_id: String, catalog: Dictionary) -> String:
    if catalog.has(item_id):
        return item_id
    var mapped_id := str(LEGACY_ITEM_ID_REMAP.get(item_id, "")).strip_edges()
    if mapped_id != "" and catalog.has(mapped_id):
        return mapped_id
    return item_id


func _apply_legacy_icon_backfill(row: Dictionary) -> Dictionary:
    var item_id := str(row.get("id", ""))
    if item_id == "":
        return row
    if not LEGACY_ICON_BY_ITEM_ID.has(item_id):
        return row
    var merged := row.duplicate(true)
    if str(merged.get("iconAsset", "")).strip_edges() == "":
        merged["iconAsset"] = str(LEGACY_ICON_BY_ITEM_ID[item_id])
    if str(merged.get("description", "")).strip_edges() == "":
        merged["description"] = "Legacy inventory item (auto-mapped icon)."
    if str(merged.get("sourceType", "")).strip_edges() == "":
        merged["sourceType"] = "legacy_backfill"
    if str(merged.get("name", "")).strip_edges() == "":
        merged["name"] = "Unknown Legacy Item"
    return merged


func _append_inventory_quarantine(
    quarantine: Array,
    row: Dictionary,
    reason: String,
    resolved_item_id: String
) -> Array:
    var next := quarantine.duplicate(true)
    var entry := {
        "id": str(row.get("id", "")),
        "resolvedId": resolved_item_id,
        "reason": reason,
        "timestamp": Time.get_unix_time_from_system(),
        "row": row.duplicate(true),
    }
    next.append(entry)
    if next.size() > 200:
        next = next.slice(next.size() - 200, next.size())
    return next


func _attach_instance_id(world_state: Dictionary, item: Dictionary) -> Dictionary:
    var with_id := item.duplicate(true)
    var instance_id := maxi(1, int(world_state.get("next_item_instance_id", 1)))
    with_id["instance_id"] = instance_id
    world_state["next_item_instance_id"] = instance_id + 1
    return with_id


func _find_inventory_index_by_instance_id(inventory_variant: Variant, instance_id: int) -> int:
    if instance_id <= 0 or typeof(inventory_variant) != TYPE_ARRAY:
        return -1
    var inventory: Array = inventory_variant
    for i in range(inventory.size()):
        var row_variant = inventory[i]
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        if int(row.get("instance_id", 0)) == instance_id:
            return i
    return -1


func _derive_equip_slot(item: Dictionary) -> String:
    var wz_group := str(item.get("wzGroup", "")).to_lower().strip_edges()
    var wz_id := str(item.get("wzId", "")).strip_edges()
    if wz_group == "accessory":
        var accessory_slot := _derive_accessory_slot_from_wz_id(wz_id)
        if accessory_slot != "":
            return accessory_slot

    var slot_hint := _normalize_slot_name(str(item.get("equipSlot", "")))
    if slot_hint != "":
        return slot_hint
    var category := str(item.get("category", "")).to_lower().strip_edges()
    var name_blob := ("%s %s %s" % [
        str(item.get("id", "")),
        str(item.get("name", "")),
        str(item.get("description", "")),
    ]).to_lower()
    if category == "gear":
        if "weapon" in name_blob or "sword" in name_blob or "staff" in name_blob or "wand" in name_blob or "dagger" in name_blob or "bow" in name_blob:
            return "weapon"
        if "hat" in name_blob or "cap" in name_blob or "helm" in name_blob:
            return "hat"
        if "overall" in name_blob:
            return "overall"
        if "top" in name_blob:
            return "top"
        if "bottom" in name_blob or "pants" in name_blob:
            return "bottom"
        if "shoe" in name_blob or "boot" in name_blob:
            return "shoes"
        if "glove" in name_blob:
            return "gloves"
        if "cape" in name_blob:
            return "cape"
        if "ring" in name_blob:
            return "ring1"
        if "pendant" in name_blob or "necklace" in name_blob:
            return "pendant1"
        return "weapon"
    if category == "training_items":
        return "pocket"
    if category == "evolution_items":
        return "medal"
    return ""


func _derive_accessory_slot_from_wz_id(wz_id: String) -> String:
    if wz_id.length() < 3:
        return ""
    var prefix := wz_id.substr(0, 3)
    if prefix == "101":
        return "face_accessory"
    if prefix == "102":
        return "eye_accessory"
    if prefix == "103":
        return "earrings"
    if prefix == "111":
        return "ring1"
    if prefix == "112":
        return "pendant1"
    if prefix == "113":
        return "belt"
    if prefix == "114":
        return "medal"
    if prefix == "115":
        return "shoulder"
    if prefix == "116":
        return "pocket"
    if prefix == "118":
        return "badge"
    if prefix == "119":
        return "emblem"
    return ""


func _normalize_slot_name(slot_id: String) -> String:
    var slot := slot_id.to_lower().strip_edges().replace(" ", "_")
    if slot == "":
        return ""
    var alias := {
        "face": "face_accessory",
        "eye": "eye_accessory",
        "ear": "earrings",
        "earring": "earrings",
        "glove": "gloves",
        "shoe": "shoes",
        "boots": "shoes",
        "necklace": "pendant1",
        "pendant": "pendant1",
        "ring": "ring1",
        "acc": "face_accessory",
    }
    if alias.has(slot):
        return str(alias.get(slot))
    return slot


func _normalize_equipped_slots_dict(equipped_slots: Dictionary) -> void:
    var normalized := DEFAULT_EQUIPPED_SLOTS.duplicate(true)
    for slot_variant in equipped_slots.keys():
        var slot := _normalize_slot_name(str(slot_variant))
        if slot == "":
            continue
        normalized[slot] = int(equipped_slots.get(slot_variant, -1))
    equipped_slots.clear()
    for slot_variant in normalized.keys():
        equipped_slots[str(slot_variant)] = int(normalized.get(slot_variant, -1))


func _clear_equipped_instance(world_state: Dictionary, instance_id: int) -> void:
    var equipped_slots: Dictionary = world_state.get("equipped_slots", {}).duplicate(true)
    for slot_variant in equipped_slots.keys():
        var slot := str(slot_variant)
        if int(equipped_slots.get(slot, -1)) == instance_id:
            equipped_slots[slot] = -1
    world_state["equipped_slots"] = equipped_slots


func _build_drop_pool(rows: Array, level: int, context: Dictionary, catalog_variant: Variant) -> Array:
    var pool: Array = []
    if typeof(catalog_variant) != TYPE_DICTIONARY:
        return pool
    var job_id := str(context.get("job_id", ""))
    var primary_stat := _normalize_primary_stat_id(str(context.get("job_primary_stat", "")))
    var category_bias := _normalize_drop_bias_list(context.get("job_drop_bias", []))
    var catalog: Dictionary = catalog_variant
    for row_variant in rows:
        if typeof(row_variant) != TYPE_DICTIONARY:
            continue
        var row: Dictionary = row_variant
        var item_id := str(row.get("itemId", ""))
        if item_id == "" or not catalog.has(item_id):
            continue
        var min_level := int(row.get("minLevel", 1))
        if level < min_level:
            continue
        var entry_job := str(row.get("jobAffinity", ""))
        var weight := maxf(0.0, float(row.get("weight", 1.0)))
        var item := (catalog[item_id] as Dictionary).duplicate(true)
        if entry_job != "" and job_id != "" and entry_job == job_id:
            weight *= JOB_MATCH_WEIGHT_MULTIPLIER
        var category := str(item.get("category", "")).to_lower().strip_edges()
        if category != "" and category_bias.has(category):
            weight *= DROP_BIAS_WEIGHT_MULTIPLIER
        if _item_supports_primary_stat(item, primary_stat):
            weight *= PRIMARY_STAT_WEIGHT_MULTIPLIER
        var slot := _normalize_slot_name(str(item.get("equipSlot", "")))
        if slot != "":
            var job_slots: Array = JOB_SLOT_AFFINITY.get(job_id, [])
            if job_slots.has(slot):
                weight *= JOB_SLOT_WEIGHT_MULTIPLIER
        if weight <= 0.0:
            continue
        item["weight"] = weight
        item["minLevel"] = min_level
        item["jobAffinity"] = entry_job
        pool.append(item)
    return pool


func _normalize_drop_bias_list(value: Variant) -> Array:
    if typeof(value) != TYPE_ARRAY:
        return []
    var out: Array = []
    for row in (value as Array):
        var key := str(row).to_lower().strip_edges()
        if key == "":
            continue
        if not out.has(key):
            out.append(key)
    return out


func _item_supports_primary_stat(item: Dictionary, primary_stat: String) -> bool:
    if primary_stat == "":
        return false
    var effects := _item_effect_profile(item)
    if effects.has(primary_stat) and float(effects.get(primary_stat, 0.0)) > 0.0:
        return true
    if primary_stat == "knowledge":
        if effects.has("int") and float(effects.get("int", 0.0)) > 0.0:
            return true
        if effects.has("intelligence") and float(effects.get("intelligence", 0.0)) > 0.0:
            return true
    if primary_stat == "charisma":
        if effects.has("luk") and float(effects.get("luk", 0.0)) > 0.0:
            return true
        if effects.has("luck") and float(effects.get("luck", 0.0)) > 0.0:
            return true
    var slot := _normalize_slot_name(str(item.get("equipSlot", "")))
    if slot == "":
        return false
    var hinted_slots: Array = STAT_SLOT_HINTS.get(primary_stat, [])
    return hinted_slots.has(slot)


func _item_effect_profile(item: Dictionary) -> Dictionary:
    var profile := {}
    var effect_profile_variant = item.get("effectProfile", {})
    if typeof(effect_profile_variant) == TYPE_DICTIONARY:
        for key_variant in (effect_profile_variant as Dictionary).keys():
            var key := str(key_variant).to_lower().strip_edges()
            profile[key] = float((effect_profile_variant as Dictionary).get(key_variant, 0.0))
    var effects_variant = item.get("effects", {})
    if typeof(effects_variant) == TYPE_DICTIONARY:
        var effects: Dictionary = effects_variant
        for key_variant in effects.keys():
            var key := str(key_variant).to_lower().strip_edges()
            var value := float(effects.get(key_variant, 0.0))
            profile[key] = value
    return profile


func _normalize_primary_stat_id(raw: String) -> String:
    var key := raw.to_lower().strip_edges()
    if key in ["str", "strength"]:
        return "strength"
    if key in ["dex", "dexterity"]:
        return "dexterity"
    if key in ["int", "knowledge", "wisdom", "intelligence"]:
        return "knowledge"
    if key in ["luk", "charisma", "luck"]:
        return "charisma"
    if key in ["endurance", "hp", "vitality"]:
        return "endurance"
    return key
