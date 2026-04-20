extends RefCounted

const DEFAULT_WALLET := {"crystals": 0}
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
    if typeof(merged.get("duplicate_recycles", null)) != TYPE_ARRAY:
        merged["duplicate_recycles"] = []
    if typeof(merged.get("box_low_value_streaks", null)) != TYPE_DICTIONARY:
        merged["box_low_value_streaks"] = {}
    if typeof(merged.get("box_open_stats", null)) != TYPE_DICTIONARY:
        merged["box_open_stats"] = {}
    return merged


func configure_from_manifest(world_state: Dictionary, manifest: Dictionary) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var catalog: Dictionary = {}
    var items_variant = manifest.get("items", [])
    if typeof(items_variant) == TYPE_ARRAY:
        for row_variant in items_variant:
            if typeof(row_variant) != TYPE_DICTIONARY:
                continue
            var row: Dictionary = row_variant
            var item_id := str(row.get("id", ""))
            if item_id == "":
                continue
            catalog[item_id] = row.duplicate(true)
    merged["item_catalog"] = catalog

    var boxes := DEFAULT_BOXES.duplicate(true)
    var reward_boxes_variant = manifest.get("rewardBoxes", [])
    if typeof(reward_boxes_variant) == TYPE_ARRAY:
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
    merged["reward_boxes"] = boxes

    var currencies_variant = manifest.get("currencies", {})
    if typeof(currencies_variant) == TYPE_DICTIONARY:
        var currencies: Dictionary = currencies_variant
        var wallet: Dictionary = merged.get("wallet", {}).duplicate(true)
        if not wallet.has("crystals"):
            wallet["crystals"] = int(currencies.get("crystals", 0))
        merged["wallet"] = wallet
    return merged


func grant_crystals(world_state: Dictionary, source_type: String, amount: int) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var wallet: Dictionary = merged.get("wallet", {}).duplicate(true)
    wallet["crystals"] = int(wallet.get("crystals", 0)) + max(0, amount)
    merged["wallet"] = wallet
    _record_tx(merged, source_type, [], max(0, amount))
    return merged


func grant_item(world_state: Dictionary, source_type: String, item: Dictionary) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var inventory: Array = merged.get("inventory", [])
    inventory.append(item)
    merged["inventory"] = inventory
    _record_tx(merged, source_type, [item], 0)
    return merged


func open_reward_box(world_state: Dictionary, box_id: String, seed: int) -> Dictionary:
    var merged := ensure_world_state(world_state)
    var boxes: Dictionary = merged.get("reward_boxes", {})
    if not boxes.has(box_id):
        return {"ok": false, "reason": "unknown_box", "world_state": merged}

    var box: Dictionary = boxes.get(box_id, {})
    var cost := int(box.get("cost", 9999))
    var wallet: Dictionary = merged.get("wallet", {}).duplicate(true)
    var crystals := int(wallet.get("crystals", 0))
    if crystals < cost:
        return {"ok": false, "reason": "insufficient_crystals", "world_state": merged}

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
    var recycle_crystals := 0
    if was_duplicate:
        recycle_crystals = _duplicate_recycle_crystals_for(selected, cost)

    wallet["crystals"] = crystals - cost
    if recycle_crystals > 0:
        wallet["crystals"] = int(wallet.get("crystals", 0)) + recycle_crystals
        _record_duplicate_recycle(merged, selected_id, recycle_crystals)
    merged["wallet"] = wallet
    merged = grant_item(merged, "reward_box:%s" % box_id, selected)
    _record_box_open_stats(merged, box_id, str(box.get("theme", "unknown")), selected, was_duplicate, recycle_crystals)
    return {
        "ok": true,
        "reason": "",
        "item": selected,
        "duplicate": was_duplicate,
        "recycleCrystals": recycle_crystals,
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
            recycle_total += int((row_variant as Dictionary).get("crystals", 0))
    var box_open_stats: Dictionary = merged.get("box_open_stats", {})
    return {
        "crystals": int(wallet.get("crystals", 0)),
        "inventory_count": inventory.size(),
        "duplicate_recycle_total": recycle_total,
        "box_open_stats": box_open_stats,
    }


func list_reward_box_ids(world_state: Dictionary) -> Array:
    var merged := ensure_world_state(world_state)
    var boxes: Dictionary = merged.get("reward_boxes", {})
    return boxes.keys()


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


func _record_duplicate_recycle(world_state: Dictionary, item_id: String, crystals: int) -> void:
    if crystals <= 0:
        return
    var rows: Array = world_state.get("duplicate_recycles", [])
    rows.append(
        {
            "itemId": item_id,
            "crystals": crystals,
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
    recycle_crystals: int
) -> void:
    var stats: Dictionary = world_state.get("box_open_stats", {}).duplicate(true)
    var theme_key := theme if theme != "" else "unknown"
    var row: Dictionary = stats.get(theme_key, {}).duplicate(true)
    row["opens"] = int(row.get("opens", 0)) + 1
    if duplicate:
        row["duplicates"] = int(row.get("duplicates", 0)) + 1
        row["recycle_crystals"] = int(row.get("recycle_crystals", 0)) + recycle_crystals

    var rarity := str(item.get("rarity", "common")).to_lower()
    var rarity_counts: Dictionary = row.get("rarity_counts", {}).duplicate(true)
    rarity_counts[rarity] = int(rarity_counts.get(rarity, 0)) + 1
    row["rarity_counts"] = rarity_counts
    row["last_box_id"] = box_id
    row["last_item_id"] = str(item.get("id", ""))
    row["last_timestamp"] = Time.get_unix_time_from_system()
    stats[theme_key] = row
    world_state["box_open_stats"] = stats
