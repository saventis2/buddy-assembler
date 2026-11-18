extends RefCounted

const LandData = preload("res://scripts/services/land_data.gd")

const DEFAULT_TOWN := {
	"home_place": "home",
	# Where each place sits on the town map (0..1 across and down), and the
	# paths drawn between them. A pack's own town may leave these out.
	"paths": [
		["home", "square"], ["home", "garden"], ["garden", "cafe"], ["square", "cafe"], ["square", "market"],
		["square", "library"], ["square", "pond"], ["library", "hill"], ["pond", "hill"],
	],
	"places": [
		{"id": "home", "name": "home", "map": [0.12, 0.55], "kind": "home", "opens": 0, "closes": 24, "distance": 0, "residents": [],
			"activities": [
				{"id": "nap", "label": "had a nap", "satisfies": "energy"},
				{"id": "tidy", "label": "tidied up", "satisfies": "comfort"},
				{"id": "think", "label": "sat and thought", "satisfies": "reflection"},
			]},
		{"id": "square", "name": "the square", "map": [0.45, 0.48], "kind": "square", "opens": 7, "closes": 22, "distance": 1, "residents": ["pip"],
			"activities": [
				{"id": "chat", "label": "stopped to chat", "satisfies": "social"},
				{"id": "people_watch", "label": "watched people go by", "satisfies": "curiosity"},
			]},
		{"id": "cafe", "name": "the cafe", "map": [0.47, 0.14], "kind": "cafe", "opens": 8, "closes": 20, "distance": 1, "residents": ["tala"],
			"activities": [
				{"id": "tea", "label": "had tea", "satisfies": "comfort"},
				{"id": "catch_up", "label": "caught up over a drink", "satisfies": "social"},
			]},
		{"id": "market", "name": "the market lane", "map": [0.80, 0.24], "kind": "shop", "opens": 9, "closes": 18, "distance": 2, "residents": ["rook"],
			"activities": [
				{"id": "browse", "label": "browsed the stalls", "satisfies": "curiosity"},
				{"id": "haggle", "label": "haggled a bit", "satisfies": "social"},
			]},
		{"id": "library", "name": "the old library", "map": [0.80, 0.62], "kind": "library", "opens": 10, "closes": 19, "distance": 2, "residents": ["quill"],
			"activities": [
				{"id": "read", "label": "read for a while", "satisfies": "curiosity"},
				{"id": "quiet_corner", "label": "found a quiet corner", "satisfies": "comfort"},
			]},
		{"id": "pond", "name": "the pond", "map": [0.36, 0.86], "kind": "park", "opens": 0, "closes": 24, "distance": 2, "residents": ["mira"],
			"activities": [
				{"id": "skip_stones", "label": "skipped stones", "satisfies": "curiosity"},
				{"id": "sit_by_water", "label": "sat by the water", "satisfies": "comfort"},
				{"id": "walk_together", "label": "walked the bank", "satisfies": "social"},
			]},
		{"id": "garden", "name": "the garden", "map": [0.22, 0.18], "kind": "park", "opens": 6, "closes": 21, "distance": 1, "residents": [],
			"activities": [
				{"id": "potter", "label": "pottered among the beds", "satisfies": "comfort"},
				{"id": "look_for_bugs", "label": "looked for beetles", "satisfies": "curiosity"},
			]},
		{"id": "hill", "name": "the hill path", "map": [0.84, 0.92], "kind": "park", "opens": 0, "closes": 24, "distance": 3, "residents": ["fenn"],
			"activities": [
				{"id": "climb", "label": "climbed to the top", "satisfies": "curiosity"},
				{"id": "watch_sky", "label": "watched the sky", "satisfies": "comfort"},
			]},
	],
}

const DEFAULT_NPCS := [
	{
		"id": "mira",
		"name": "Mira",
		"role": "mentor",
		"affinity": 0,
		"availability": "always",
		"dialoguePool": [
			"Steady practice builds a steady buddy.",
			"Small routines beat heroic bursts.",
		],
	},
	{
		"id": "pip",
		"name": "Pip",
		"role": "friend",
		"affinity": 0,
		"availability": "always",
		"dialoguePool": [
			"Want to do a cozy errand together?",
			"You and Buddy look synced today.",
		],
	},
	{
		"id": "rook",
		"name": "Rook",
		"role": "rival",
		"affinity": 0,
		"availability": "daytime",
		"dialoguePool": [
			"Try this challenge if you are ready.",
			"No pressure. Skip if you want a quiet loop.",
		],
	},
	{
		"id": "tala",
		"name": "Tala",
		"role": "caretaker",
		"affinity": 0,
		"availability": "always",
		"dialoguePool": [
			"A tidy space helps calm moods.",
			"Let us refresh one corner of home.",
		],
	},
	{
		"id": "quill",
		"name": "Quill",
		"role": "scribe",
		"affinity": 0,
		"availability": "evening",
		"dialoguePool": [
			"Small notes become strong routines.",
			"Want a social errand for the village board?",
		],
	},
	{
		"id": "fenn",
		"name": "Fenn",
		"role": "scout",
		"affinity": 0,
		"availability": "daytime",
		"dialoguePool": [
			"I found a side trail if you want an encounter.",
			"Skip is valid. We can regroup.",
		],
	},
]

const DEFAULT_QUESTS := [
	{
		"id": "quest-cozy-checkin",
		"type": "bond",
		"npcId": "pip",
		"requirements": {"kind": "pet_once"},
		"rewards": {"crystals": 5, "itemId": "wz-tri-colored-dango"},
		"repeatability": "daily",
		"narrativeText": "Pip asks for a cozy check-in with Buddy.",
	},
	{
		"id": "quest-training-nudge",
		"type": "training",
		"npcId": "mira",
		"requirements": {"kind": "happy_or_wander"},
		"rewards": {"crystals": 6, "itemId": "wz-stone-golem-rubble"},
		"repeatability": "daily",
		"narrativeText": "Mira suggests a short training drill.",
	},
	{
		"id": "quest-home-tidy-pass",
		"type": "home_upkeep",
		"npcId": "tala",
		"requirements": {"kind": "home_toggle_or_rest"},
		"rewards": {"crystals": 5, "itemId": "wz-rocky-mask-doll"},
		"repeatability": "daily",
		"narrativeText": "Tala asks for a quick home tidy pass.",
	},
	{
		"id": "quest-village-greeting-run",
		"type": "social",
		"npcId": "quill",
		"requirements": {"kind": "checkin_or_pet"},
		"rewards": {"crystals": 6, "itemId": "wz-fruity-candy"},
		"repeatability": "daily",
		"narrativeText": "Quill posts a social greeting errand.",
	},
]

const DEFAULT_ENCOUNTERS := [
	{
		"id": "encounter-curious-visitor",
		"type": "optional",
		"action": "visitor",
		"npcId": "rook",
		"dropTableId": "rook_challenge_drops",
		"narrativeText": "Rook spots a wild challenge nearby.",
		"rewardsEngage": {"crystals": 7, "itemId": "wz-stone-golem-rubble"},
		"rewardsSkip": {"crystals": 1},
	},
	{
		"id": "encounter-scouted-cache",
		"type": "optional",
		"action": "scout",
		"npcId": "fenn",
		"dropTableId": "fenn_cache_drops",
		"narrativeText": "Fenn points out a hidden cache trail.",
		"rewardsEngage": {"crystals": 5, "itemId": "wz-tri-colored-dango"},
		"rewardsSkip": {"crystals": 2},
	},
	{
		"id": "encounter-late-lantern",
		"type": "optional",
		"action": "support",
		"npcId": "quill",
		"dropTableId": "quill_lantern_drops",
		"narrativeText": "Quill offers a calm late-session challenge.",
		"rewardsEngage": {"crystals": 6, "itemId": "wz-green-halloween-stick-candy"},
		"rewardsSkip": {"crystals": 2},
	}
]

const WORLD_DEFAULTS := {
	"home_mode": "overlay",
	"home_layout": {
		"sceneId": "cozy_starter_room",
		"decorSlots": {"wall": "", "floor": "", "display": ""},
	},
	"npcs": [],
	"quests": [],
	"encounters": [],
	"npc_affinity": {},
	"completed_quests": [],
	"recent_encounters": [],
	"pending_quest_id": "",
	"pending_encounter_id": "",
	"next_quest_unix": 0,
	"next_encounter_unix": 0,
	"quest_rotation_index": 0,
	"encounter_rotation_index": 0,
	"recent_prompt_ids": [],
	"recent_prompt_groups": [],
	"last_world_event_id": "",
	"last_world_event_unix": 0,
}


func ensure_world_state(world_state: Dictionary) -> Dictionary:
	var merged := world_state.duplicate(true)
	var world_variant = merged.get("world", null)
	if typeof(world_variant) != TYPE_DICTIONARY:
		merged["world"] = WORLD_DEFAULTS.duplicate(true)
	var world: Dictionary = merged.get("world", {}).duplicate(true)

	for key in WORLD_DEFAULTS.keys():
		if not world.has(key):
			world[key] = WORLD_DEFAULTS[key]

	if typeof(world.get("home_layout", null)) != TYPE_DICTIONARY:
		world["home_layout"] = WORLD_DEFAULTS["home_layout"].duplicate(true)
	if typeof(world.get("npcs", null)) != TYPE_ARRAY:
		world["npcs"] = []
	if typeof(world.get("quests", null)) != TYPE_ARRAY:
		world["quests"] = []
	if typeof(world.get("encounters", null)) != TYPE_ARRAY:
		world["encounters"] = []
	if typeof(world.get("npc_affinity", null)) != TYPE_DICTIONARY:
		world["npc_affinity"] = {}
	if typeof(world.get("completed_quests", null)) != TYPE_ARRAY:
		world["completed_quests"] = []
	if typeof(world.get("recent_encounters", null)) != TYPE_ARRAY:
		world["recent_encounters"] = []
	if typeof(world.get("recent_prompt_ids", null)) != TYPE_ARRAY:
		world["recent_prompt_ids"] = []
	if typeof(world.get("recent_prompt_groups", null)) != TYPE_ARRAY:
		world["recent_prompt_groups"] = []

	merged["world"] = world
	return merged


# Where each place sits on the town map (0..1 across and down) and which
# places a path joins. Uses the town's own "map" and "paths" when it has them;
# otherwise places are set in a ring round home by distance, each joined to
# home, so a pack town without map data still gets a map.
func town_map(town: Dictionary) -> Dictionary:
	var places: Array = []
	var places_variant = town.get("places", [])
	if typeof(places_variant) == TYPE_ARRAY:
		for place_variant in places_variant:
			if typeof(place_variant) == TYPE_DICTIONARY and str((place_variant as Dictionary).get("id", "")) != "":
				places.append(place_variant)
	var positions := {}
	var ring: Array = []
	for place in places:
		var place_id := str(place.get("id", ""))
		var map_variant = place.get("map", null)
		if typeof(map_variant) == TYPE_ARRAY and (map_variant as Array).size() == 2:
			positions[place_id] = Vector2(clampf(float(map_variant[0]), 0.0, 1.0), clampf(float(map_variant[1]), 0.0, 1.0))
		else:
			ring.append(place)
	var home_id := str(town.get("home_place", "home"))
	for index in range(ring.size()):
		var place: Dictionary = ring[index]
		var place_id := str(place.get("id", ""))
		if place_id == home_id:
			positions[place_id] = Vector2(0.5, 0.5)
			continue
		var angle := TAU * float(index) / float(maxi(1, ring.size())) - PI / 2.0
		var radius := 0.18 + 0.1 * clampf(float(place.get("distance", 1)), 0.0, 3.0)
		positions[place_id] = Vector2(0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius)
	var paths: Array = []
	var paths_variant = town.get("paths", null)
	if typeof(paths_variant) == TYPE_ARRAY:
		for path_variant in paths_variant:
			if typeof(path_variant) == TYPE_ARRAY and (path_variant as Array).size() == 2:
				var from_id := str(path_variant[0])
				var to_id := str(path_variant[1])
				if positions.has(from_id) and positions.has(to_id) and from_id != to_id:
					paths.append([from_id, to_id])
	if paths.is_empty() and positions.has(home_id):
		for place_id in positions.keys():
			if str(place_id) != home_id:
				paths.append([home_id, str(place_id)])
	return {"positions": positions, "paths": paths}


func get_town(world_state: Dictionary) -> Dictionary:
	var world: Dictionary = ensure_world_state(world_state)["world"]
	var town = world.get("town", null)
	if typeof(town) == TYPE_DICTIONARY:
		var places = (town as Dictionary).get("places", null)
		if typeof(places) == TYPE_ARRAY and not (places as Array).is_empty():
			return town
	return DEFAULT_TOWN.duplicate(true)


# The whole land of a buddy that starts small (Plan 14). The mind decides how
# much of it the buddy knows; see mind_service.known_town.
func get_land() -> Dictionary:
	return LandData.LAND.duplicate(true)


func configure_from_manifest(world_state: Dictionary, manifest: Dictionary) -> Dictionary:
	var merged := ensure_world_state(world_state)
	var world: Dictionary = merged.get("world", {}).duplicate(true)

	var npcs := _normalize_npcs(manifest.get("npcs", []))
	if npcs.is_empty():
		npcs = DEFAULT_NPCS.duplicate(true)
	world["npcs"] = npcs

	var manifest_town = manifest.get("town", null)
	if typeof(manifest_town) == TYPE_DICTIONARY and typeof((manifest_town as Dictionary).get("places", null)) == TYPE_ARRAY and not ((manifest_town as Dictionary)["places"] as Array).is_empty():
		world["town"] = (manifest_town as Dictionary).duplicate(true)
	else:
		world["town"] = DEFAULT_TOWN.duplicate(true)

	var quests := _normalize_quests(manifest.get("quests", []))
	if quests.is_empty():
		quests = DEFAULT_QUESTS.duplicate(true)
	world["quests"] = quests

	var encounters := _normalize_encounters(manifest.get("encounters", []))
	if encounters.is_empty():
		encounters = DEFAULT_ENCOUNTERS.duplicate(true)
	world["encounters"] = encounters

	var home_variant = manifest.get("home", null)
	if typeof(home_variant) == TYPE_DICTIONARY:
		var home: Dictionary = home_variant
		var next_home: Dictionary = (world.get("home_layout", {}) as Dictionary).duplicate(true)
		next_home["sceneId"] = str(home.get("sceneId", next_home.get("sceneId", "cozy_starter_room")))
		var slots_variant = home.get("decorSlots", null)
		if typeof(slots_variant) == TYPE_DICTIONARY:
			next_home["decorSlots"] = (slots_variant as Dictionary).duplicate(true)
		world["home_layout"] = next_home

	var affinity: Dictionary = world.get("npc_affinity", {}).duplicate(true)
	for npc_variant in npcs:
		if typeof(npc_variant) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_variant
		var npc_id := str(npc.get("id", ""))
		if npc_id == "":
			continue
		if not affinity.has(npc_id):
			affinity[npc_id] = int(npc.get("affinity", 0))
	world["npc_affinity"] = affinity

	if not _id_in_rows(world.get("pending_quest_id", ""), quests):
		world["pending_quest_id"] = ""
	if not _id_in_rows(world.get("pending_encounter_id", ""), encounters):
		world["pending_encounter_id"] = ""

	merged["world"] = world
	return merged


func tick_world(world_state: Dictionary, profile: Dictionary, now_unix: int) -> Dictionary:
	var merged := ensure_world_state(world_state)
	var world: Dictionary = merged.get("world", {}).duplicate(true)
	var changed := false
	var prompt := {}
	var mood := str(profile.get("dominant_mood", "calm"))
	var recent_prompt_ids: Array = world.get("recent_prompt_ids", [])
	var recent_prompt_groups: Array = world.get("recent_prompt_groups", [])

	if str(world.get("pending_quest_id", "")) == "":
		var next_quest_unix := int(world.get("next_quest_unix", 0))
		if now_unix >= next_quest_unix:
			var quests: Array = world.get("quests", [])
			if not quests.is_empty():
				var quest := _rotating_pick_non_recent_group(
					quests,
					int(world.get("quest_rotation_index", 0)),
					recent_prompt_ids,
					recent_prompt_groups,
					"type"
				)
				world["quest_rotation_index"] = int(world.get("quest_rotation_index", 0)) + 1
				world["pending_quest_id"] = str(quest.get("id", ""))
				world["next_quest_unix"] = now_unix + 900
				world["last_world_event_id"] = str(quest.get("id", ""))
				world["last_world_event_unix"] = now_unix
				_push_recent_prompt(world, str(quest.get("id", "")), _row_group(quest, "type"))
				changed = true
				prompt = {
					"type": "quest",
					"id": str(quest.get("id", "")),
					"npcName": _npc_name(world, str(quest.get("npcId", ""))),
					"text": str(quest.get("narrativeText", "A village quest is available.")),
				}

	if str(world.get("pending_encounter_id", "")) == "":
		var next_encounter_unix := int(world.get("next_encounter_unix", 0))
		if now_unix >= next_encounter_unix and mood != "sleepy":
			var encounters: Array = world.get("encounters", [])
			if not encounters.is_empty():
				var encounter := _rotating_pick_non_recent_group(
					encounters,
					int(world.get("encounter_rotation_index", 0)),
					recent_prompt_ids,
					recent_prompt_groups,
					"action"
				)
				world["encounter_rotation_index"] = int(world.get("encounter_rotation_index", 0)) + 1
				world["pending_encounter_id"] = str(encounter.get("id", ""))
				world["next_encounter_unix"] = now_unix + 1200
				world["last_world_event_id"] = str(encounter.get("id", ""))
				world["last_world_event_unix"] = now_unix
				_push_recent_prompt(world, str(encounter.get("id", "")), _row_group(encounter, "action"))
				changed = true
				if prompt.is_empty():
					prompt = {
						"type": "encounter",
						"id": str(encounter.get("id", "")),
						"npcName": _npc_name(world, str(encounter.get("npcId", ""))),
						"text": str(encounter.get("narrativeText", "An optional encounter appears.")),
					}

	merged["world"] = world
	return {
		"changed": changed,
		"prompt": prompt,
		"world_state": merged,
	}


func complete_pending_quest(world_state: Dictionary) -> Dictionary:
	var merged := ensure_world_state(world_state)
	var world: Dictionary = merged.get("world", {}).duplicate(true)
	var quest_id := str(world.get("pending_quest_id", ""))
	if quest_id == "":
		return {"ok": false, "reason": "no_pending_quest", "world_state": merged}

	var quest := _find_row(world.get("quests", []), quest_id)
	if quest.is_empty():
		world["pending_quest_id"] = ""
		merged["world"] = world
		return {"ok": false, "reason": "unknown_quest", "world_state": merged}

	var completed: Array = world.get("completed_quests", [])
	completed.append(quest_id)
	if completed.size() > 40:
		completed = completed.slice(completed.size() - 40, completed.size())
	world["completed_quests"] = completed
	world["pending_quest_id"] = ""
	var npc_id := str(quest.get("npcId", ""))
	if npc_id != "":
		var affinity: Dictionary = world.get("npc_affinity", {}).duplicate(true)
		affinity[npc_id] = int(affinity.get(npc_id, 0)) + 1
		world["npc_affinity"] = affinity

	merged["world"] = world
	return {
		"ok": true,
		"reason": "",
		"quest": quest,
		"npcName": _npc_name(world, npc_id),
		"rewards": quest.get("rewards", {}),
		"world_state": merged,
	}


func resolve_pending_encounter(world_state: Dictionary, engage: bool) -> Dictionary:
	var merged := ensure_world_state(world_state)
	var world: Dictionary = merged.get("world", {}).duplicate(true)
	var encounter_id := str(world.get("pending_encounter_id", ""))
	if encounter_id == "":
		return {"ok": false, "reason": "no_pending_encounter", "world_state": merged}

	var encounter := _find_row(world.get("encounters", []), encounter_id)
	if encounter.is_empty():
		world["pending_encounter_id"] = ""
		merged["world"] = world
		return {"ok": false, "reason": "unknown_encounter", "world_state": merged}

	var history: Array = world.get("recent_encounters", [])
	history.append({"id": encounter_id, "engage": engage, "ts": Time.get_unix_time_from_system()})
	if history.size() > 30:
		history = history.slice(history.size() - 30, history.size())
	world["recent_encounters"] = history
	world["pending_encounter_id"] = ""

	merged["world"] = world
	var reward_key := "rewardsEngage" if engage else "rewardsSkip"
	return {
		"ok": true,
		"reason": "",
		"encounter": encounter,
		"engaged": engage,
		"npcName": _npc_name(world, str(encounter.get("npcId", ""))),
		"dropTableId": str(encounter.get("dropTableId", "")),
		"rewards": encounter.get(reward_key, {}),
		"world_state": merged,
	}


func get_snapshot(world_state: Dictionary) -> Dictionary:
	var merged := ensure_world_state(world_state)
	var world: Dictionary = merged.get("world", {})
	var home_layout: Dictionary = world.get("home_layout", {})
	var decor_slots: Dictionary = home_layout.get("decorSlots", {})
	return {
		"home_mode": str(world.get("home_mode", "overlay")),
		"home_scene_id": str(world.get("home_layout", {}).get("sceneId", "cozy_starter_room")),
		"home_wall_decor": str(decor_slots.get("wall", "")),
		"pending_quest_id": str(world.get("pending_quest_id", "")),
		"pending_encounter_id": str(world.get("pending_encounter_id", "")),
		"npc_count": (world.get("npcs", []) as Array).size(),
		"quest_count": (world.get("quests", []) as Array).size(),
		"encounter_count": (world.get("encounters", []) as Array).size(),
		"last_world_event_id": str(world.get("last_world_event_id", "")),
	}


func set_home_mode(world_state: Dictionary, mode: String) -> Dictionary:
	var merged := ensure_world_state(world_state)
	var world: Dictionary = merged.get("world", {}).duplicate(true)
	var normalized := "home" if mode == "home" else "overlay"
	world["home_mode"] = normalized
	merged["world"] = world
	return merged


func _normalize_npcs(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var rows: Array = []
	for row_variant in (value as Array):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var npc_id := str(row.get("id", ""))
		var name := str(row.get("name", ""))
		if npc_id == "" or name == "":
			continue
		rows.append(
			{
				"id": npc_id,
				"name": name,
				"role": str(row.get("role", "villager")),
				"affinity": int(row.get("affinity", 0)),
				"availability": str(row.get("availability", "always")),
				"dialoguePool": row.get("dialoguePool", []),
			}
		)
	return rows


func _normalize_quests(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var rows: Array = []
	for row_variant in (value as Array):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var quest_id := str(row.get("id", ""))
		if quest_id == "":
			continue
		rows.append(
			{
				"id": quest_id,
				"type": str(row.get("type", "daily")),
				"npcId": str(row.get("npcId", "")),
				"requirements": row.get("requirements", {}),
				"rewards": row.get("rewards", {}),
				"repeatability": str(row.get("repeatability", "daily")),
				"narrativeText": str(row.get("narrativeText", "A buddy quest is available.")),
			}
		)
	return rows


func _normalize_encounters(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var rows: Array = []
	for row_variant in (value as Array):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var encounter_id := str(row.get("id", ""))
		if encounter_id == "":
			continue
		rows.append(
			{
				"id": encounter_id,
				"type": str(row.get("type", "optional")),
				"action": str(row.get("action", "visitor")),
				"npcId": str(row.get("npcId", "")),
				"dropTableId": str(row.get("dropTableId", "")),
				"narrativeText": str(row.get("narrativeText", "An encounter appears.")),
				"rewardsEngage": row.get("rewardsEngage", {}),
				"rewardsSkip": row.get("rewardsSkip", {}),
			}
		)
	return rows


func _rotating_pick(rows: Array, index: int) -> Dictionary:
	if rows.is_empty():
		return {}
	var i := posmod(index, rows.size())
	var candidate = rows[i]
	if typeof(candidate) != TYPE_DICTIONARY:
		return {}
	return (candidate as Dictionary).duplicate(true)


func _rotating_pick_non_recent_group(
	rows: Array,
	index: int,
	recent_prompt_ids: Array,
	recent_prompt_groups: Array,
	group_key: String
) -> Dictionary:
	if rows.is_empty():
		return {}
	if rows.size() == 1:
		return _rotating_pick(rows, index)
	var candidate := _rotating_pick(rows, index)
	var candidate_id := str(candidate.get("id", ""))
	var candidate_group := _row_group(candidate, group_key)
	var recent_group_is_used := candidate_group != "" and recent_prompt_groups.has(candidate_group)
	var candidate_is_fresh := candidate_id == "" or not recent_prompt_ids.has(candidate_id)
	var group_is_fresh := candidate_group == "" or not recent_group_is_used
	if candidate_is_fresh and group_is_fresh:
		return candidate

	var fallback_non_repeat_id := {}
	for offset in range(1, rows.size()):
		var alt = _rotating_pick(rows, index + offset)
		var alt_id := str(alt.get("id", ""))
		var alt_group := _row_group(alt, group_key)
		var alt_group_fresh := alt_group == "" or not recent_prompt_groups.has(alt_group)
		if alt_id != "" and not recent_prompt_ids.has(alt_id):
			if alt_group_fresh:
				return alt
			if fallback_non_repeat_id.is_empty():
				fallback_non_repeat_id = alt
	if not fallback_non_repeat_id.is_empty():
		return fallback_non_repeat_id
	for offset in range(1, rows.size()):
		var alt = _rotating_pick(rows, index + offset)
		var alt_group := _row_group(alt, group_key)
		if alt_group != "" and not recent_prompt_groups.has(alt_group):
			return alt
	return candidate


func _push_recent_prompt(world: Dictionary, prompt_id: String, prompt_group: String = "") -> void:
	if prompt_id == "":
		return
	var recent_ids: Array = world.get("recent_prompt_ids", [])
	recent_ids.append(prompt_id)
	if recent_ids.size() > 6:
		recent_ids = recent_ids.slice(recent_ids.size() - 6, recent_ids.size())
	world["recent_prompt_ids"] = recent_ids
	if prompt_group != "":
		var groups: Array = world.get("recent_prompt_groups", [])
		groups.append(prompt_group)
		if groups.size() > 4:
			groups = groups.slice(groups.size() - 4, groups.size())
		world["recent_prompt_groups"] = groups


func _row_group(row: Dictionary, group_key: String) -> String:
	if group_key == "":
		return ""
	return str(row.get(group_key, ""))


func _find_row(rows_variant: Variant, wanted_id: String) -> Dictionary:
	if typeof(rows_variant) != TYPE_ARRAY:
		return {}
	for row_variant in (rows_variant as Array):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("id", "")) == wanted_id:
			return row.duplicate(true)
	return {}


func _id_in_rows(wanted_id: String, rows_variant: Variant) -> bool:
	if wanted_id == "" or typeof(rows_variant) != TYPE_ARRAY:
		return false
	for row_variant in (rows_variant as Array):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		if str((row_variant as Dictionary).get("id", "")) == wanted_id:
			return true
	return false


func _npc_name(world: Dictionary, npc_id: String) -> String:
	if npc_id == "":
		return "Villager"
	var rows_variant = world.get("npcs", [])
	if typeof(rows_variant) != TYPE_ARRAY:
		return "Villager"
	for row_variant in (rows_variant as Array):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("id", "")) == npc_id:
			return str(row.get("name", "Villager"))
	return "Villager"
