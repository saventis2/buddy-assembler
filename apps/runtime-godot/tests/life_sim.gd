extends RefCounted

# Fast-forward harness: lives a brand-new buddy through N days in seconds by
# driving the real AppState.tick_mind with a supplied clock, then reports what
# the life was like (journal, per-day stats, "firsts", repetition). It uses
# AppState's simulation seam, so nothing it does can be saved.

const ContentLoader = preload("res://scripts/content/content_loader.gd")
const MindService = preload("res://scripts/services/mind_service.gd")
const MemoryService = preload("res://scripts/services/memory_service.gd")

# 2027-01-01 00:00, read as local time (the simulation has no time zone).
const DEFAULT_START_UNIX := 1798761600
const SECONDS_PER_DAY := 86400
const NOT_SIMULATED := [
	"ambient desktop animation ticks",
	"quests and encounters",
	"talking to the buddy",
	"the language model",
]
const MOOD_KEYS := ["energy_strain", "social_fulfillment", "comfort", "confidence"]
const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]


static func run(app_state: Node, config: Dictionary) -> Dictionary:
	var state = app_state
	var days: int = int(config.get("days", 0))
	if days < 1:
		return {"error": "days must be at least 1"}
	var seed_value: int = int(config.get("seed", 1))
	var start: int = int(config.get("start_unix", DEFAULT_START_UNIX))
	var pack_id: String = str(config.get("pack_id", "core_pack"))
	var small: bool = bool(config.get("small_beginnings", false))

	if not state.begin_simulation(seed_value, start):
		return {"error": "begin_simulation refused (needs a headless process and a start time above 0)"}
	var loaded: Dictionary = ContentLoader.load_with_fallback(pack_id, "", false)
	state.apply_loaded_pack(str(loaded.get("pack_id", pack_id)), loaded.get("manifest", {}))
	state.trim_catalog_for_simulation()
	state.settings["smallBeginnings"] = small

	var home_place: String = str(state.get_town().get("home_place", "home"))
	var interval: int = MindService.DECISION_INTERVAL_SECONDS
	var slots_per_day: int = int(SECONDS_PER_DAY / interval)

	var rows: Array = []
	var day_rows: Array = []
	var seen_firsts := {}
	var seen_texts := {}
	var places_seen := {}
	var companions_seen := {}
	var intents_total := {}
	var wants_noticed := 0
	var purchases_total := 0
	var decisions_total := 0
	var flat_days := 0
	var flat_streak := 0
	var longest_flat_streak := 0

	var day_decisions := 0
	var day_intents := {}
	var day_places := {}
	var day_companions := {}
	var day_firsts: Array = []
	var day_new_texts := 0
	var day_purchases := 0
	var text_counts := {}
	var signs_total := 0
	var sights_total := 0
	var blocked_total := 0
	var night_rows := 0
	var need_stats := {}
	for need_key in MOOD_KEYS:
		need_stats[need_key] = {"min": 1.0, "max": 0.0, "samples": 0, "at_limit": 0}
	var memory_service = MemoryService.new()
	var memory_max_edges := 0
	# Letters from the person (config "letters"): each goes in the mailbox at its
	# time, as the world host would on taking the request.
	var letter_plan: Array = []
	for letter_variant in config.get("letters", []):
		var spec: Dictionary = letter_variant
		var target: int = start + (int(spec.get("day", 1)) - 1) * SECONDS_PER_DAY + int(spec.get("hour", 0)) * 3600 + int(spec.get("minute", 0)) * 60
		letter_plan.append({"target": maxi(target, start), "text": str(spec.get("text", "")), "sent": false})
	var letter_timeline: Array = []

	for i in range(days * slots_per_day):
		var t: int = start + i * interval
		var day: int = int(i / slots_per_day) + 1
		for plan_variant in letter_plan:
			var plan: Dictionary = plan_variant
			if not bool(plan["sent"]) and int(plan["target"]) <= t:
				plan["sent"] = true
				state.set_sim_clock(int(plan["target"]))
				var sent: Dictionary = state.letters_send(str(plan["text"]))
				if not bool(sent.get("ok", false)):
					letter_timeline.append({"t": int(plan["target"]), "text": "a letter was refused (%s)" % str(sent.get("reason", ""))})
		state.set_sim_clock(t)
		var events: Array = state.tick_mind(t)
		if not events.is_empty():
			var journal: Array = state.get_mind_journal(40)
			for entry_variant in journal:
				if typeof(entry_variant) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = entry_variant
				var entry_t: int = int(entry.get("t", 0))
				# A plan line is stamped a second before its decision, a purchase
				# line a second after it.
				if entry_t < t - 1 or entry_t > t + 1:
					continue
				var kind: String = str(entry.get("kind", "decision"))
				var found: Array = []
				if kind == "decision":
					var place_id: String = str(entry.get("place_id", ""))
					if place_id != "" and place_id != home_place:
						found.append({"kind": "place", "id": place_id, "name": str(entry.get("place_name", place_id))})
					var activity_id: String = str(entry.get("activity_id", ""))
					if activity_id != "":
						found.append({"kind": "activity", "id": activity_id, "name": str(entry.get("activity_label", activity_id))})
					var companion: String = str(entry.get("companion_name", ""))
					if companion != "":
						found.append({"kind": "companion", "id": companion, "name": companion})
					var want_id: String = str(entry.get("noticed_want", ""))
					if want_id != "":
						found.append({"kind": "want", "id": want_id, "name": str(entry.get("noticed_item", ""))})
						wants_noticed += 1
					var sign_id: String = str(entry.get("sign_of", ""))
					if sign_id != "":
						found.append({"kind": "sign", "id": sign_id, "name": sign_id})
					var sight_id: String = str(entry.get("sight", ""))
					if sight_id != "":
						found.append({"kind": "sight", "id": sight_id, "name": sight_id})
				elif kind == "purchase" and float(entry.get("valence", 0.0)) > 0.0:
					# The same kind also carries "I didn't have enough saved" lines.
					found.append({"kind": "purchase", "id": str(entry.get("subject_id", "")), "name": str(entry.get("subject_name", ""))})
					purchases_total += 1
					day_purchases += 1
				var first_tags: Array = []
				for first_row in found:
					var key: String = str(first_row["kind"]) + ":" + str(first_row["id"])
					if seen_firsts.has(key):
						continue
					seen_firsts[key] = true
					first_tags.append(key)
					day_firsts.append({"t": entry_t, "kind": first_row["kind"], "id": first_row["id"], "name": first_row["name"]})
					if first_row["kind"] == "place":
						places_seen[first_row["id"]] = true
					elif first_row["kind"] == "companion":
						companions_seen[first_row["id"]] = true
					elif first_row["kind"] == "sign":
						signs_total += 1
					elif first_row["kind"] == "sight":
						sights_total += 1
				var text: String = str(entry.get("text", ""))
				if not seen_texts.has(text):
					seen_texts[text] = true
					day_new_texts += 1
				text_counts[text] = int(text_counts.get(text, 0)) + 1
				var stamp: Dictionary = Time.get_datetime_dict_from_unix_time(entry_t)
				if kind == "decision" and int(stamp.get("hour", 0)) < 5:
					night_rows += 1
				if str(entry.get("blocked_at", "")) != "":
					blocked_total += 1
				var row := {
					"t": entry_t,
					"day": day,
					"hour": int(stamp.get("hour", 0)),
					"minute": int(stamp.get("minute", 0)),
					"kind": kind,
					"intent": str(entry.get("intent", "")),
					"place_id": str(entry.get("place_id", "")),
					"place_name": str(entry.get("place_name", "")),
					"activity_id": str(entry.get("activity_id", "")),
					"companion_name": str(entry.get("companion_name", "")),
					"sign_of": str(entry.get("sign_of", "")),
					"blocked_at": str(entry.get("blocked_at", "")),
					"found_place": str(entry.get("found_place", "")),
					"sight": str(entry.get("sight", "")),
					"valence": _snap(float(entry.get("valence", 0.0))),
					"text": text,
					"firsts": first_tags,
				}
				rows.append(row)

			for event_variant in events:
				var event: Dictionary = event_variant
				if str(event.get("learned", "")) == "console":
					letter_timeline.append({"t": int(event.get("t", t)), "text": "it worked out the glowing box"})
				var read_variant = event.get("read_letters", [])
				if typeof(read_variant) == TYPE_ARRAY and not (read_variant as Array).is_empty():
					letter_timeline.append({"t": int(event.get("t", t)), "text": "it read %d letter%s" % [(read_variant as Array).size(), "" if (read_variant as Array).size() == 1 else "s"]})
				var intent: String = str(event.get("intent", ""))
				day_decisions += 1
				day_intents[intent] = int(day_intents.get(intent, 0)) + 1
				intents_total[intent] = int(intents_total.get(intent, 0)) + 1
				var event_place: String = str(event.get("place_id", ""))
				if event_place != "":
					day_places[event_place] = int(day_places.get(event_place, 0)) + 1
				var event_companion: String = str(event.get("companion_name", ""))
				if event_companion != "":
					day_companions[event_companion] = int(day_companions.get(event_companion, 0)) + 1
				state.apply_behavior(str(event.get("action", "idle")))
			# How its needs are doing, once for every slot where it decided something.
			var sampled: Dictionary = state.profile.get("mood_modifiers", {})
			for need_key in MOOD_KEYS:
				var level: float = float(sampled.get(need_key, 0.0))
				var stats: Dictionary = need_stats[need_key]
				stats["min"] = minf(float(stats["min"]), level)
				stats["max"] = maxf(float(stats["max"]), level)
				stats["samples"] = int(stats["samples"]) + 1
				if level <= 0.02 or level >= 0.98:
					stats["at_limit"] = int(stats["at_limit"]) + 1
			var slot_memory: Dictionary = memory_service.land_memory_report(state.profile, {"home_place": home_place})
			memory_max_edges = maxi(memory_max_edges, int(slot_memory.get("total_edges", 0)))
		decisions_total += events.size()

		if i % slots_per_day == slots_per_day - 1:
			var mods: Dictionary = state.profile.get("mood_modifiers", {})
			var mood := {}
			for mood_key in MOOD_KEYS:
				mood[mood_key] = _snap(float(mods.get(mood_key, 0.0)))
			day_rows.append({
				"day": day,
				"decisions": day_decisions,
				"intents": day_intents,
				"places": day_places,
				"companions": day_companions,
				"firsts": day_firsts,
				"new_texts": day_new_texts,
				"meso": int(state.get_inventory_snapshot().get("meso", 0)),
				"mood": mood,
				"open_wants": _open_wants(state.mind_wants()),
				"purchases": day_purchases,
			})
			if day_firsts.is_empty() and day_new_texts == 0:
				flat_days += 1
				flat_streak += 1
				longest_flat_streak = maxi(longest_flat_streak, flat_streak)
			else:
				flat_streak = 0
			day_decisions = 0
			day_intents = {}
			day_places = {}
			day_companions = {}
			day_firsts = []
			day_new_texts = 0
			day_purchases = 0

	var ratio: float = 0.0
	if not rows.is_empty():
		ratio = float(seen_texts.size()) / float(rows.size())
	var preferences: Dictionary = state.get_mind_preferences()
	var feelings_raw: Dictionary = state.profile.get("mind", {}).get("feelings", {})
	var feelings := {}
	for feeling_key in feelings_raw.keys():
		feelings[str(feeling_key)] = _snap(float(feelings_raw[feeling_key]))
	var tail: Array = []
	var recent: Array = state.get_mind_journal(5)
	for recent_entry in recent:
		tail.append(str((recent_entry as Dictionary).get("text", "")))
	var counts: Array = text_counts.values()
	counts.sort()
	counts.reverse()
	var top_ten := 0
	for count_index in range(mini(10, counts.size())):
		top_ten += int(counts[count_index])
	var top10_share: float = 0.0
	if not rows.is_empty():
		top10_share = float(top_ten) / float(rows.size())
	var needs_report := {}
	for need_key in MOOD_KEYS:
		var stats: Dictionary = need_stats[need_key]
		var samples: int = int(stats["samples"])
		needs_report[need_key] = {
			"min": _snap(float(stats["min"]) if samples > 0 else 0.0),
			"max": _snap(float(stats["max"])),
			"at_limit_share": _snap(float(int(stats["at_limit"])) / float(samples) if samples > 0 else 0.0),
		}
	var known_variant = state.profile.get("mind", {}).get("known_places", {})
	var known_found: Array = []
	var known_signs: Array = []
	if typeof(known_variant) == TYPE_DICTIONARY:
		for known_id in (known_variant as Dictionary).keys():
			var known_record = (known_variant as Dictionary)[known_id]
			if typeof(known_record) != TYPE_DICTIONARY:
				continue
			var known_stage: String = str((known_record as Dictionary).get("stage", ""))
			if known_stage == "found":
				known_found.append(str(known_id))
			elif known_stage == "sign":
				known_signs.append(str(known_id))
	known_found.sort()
	known_signs.sort()
	var final_wants: Array = []
	for want_variant in state.mind_wants():
		var want: Dictionary = want_variant
		final_wants.append({
			"name": str(want.get("name", "")),
			"price": int(want.get("price", 0)),
			"status": str(want.get("status", "")),
		})

	var console_record: Dictionary = {}
	var console_variant = state.profile.get("mind", {}).get("console", null)
	if typeof(console_variant) == TYPE_DICTIONARY:
		console_record = console_variant
	var final_letters: Array = []
	for letter_row_variant in state.letters_items():
		var letter_row: Dictionary = letter_row_variant
		if str(letter_row.get("from", "")) == "you":
			final_letters.append({"text": str(letter_row.get("text", "")), "sent_t": int(letter_row.get("t", 0)), "read_t": int(letter_row.get("read_t", 0))})
	for timeline_row_variant in letter_timeline:
		var timeline_row: Dictionary = timeline_row_variant
		var timeline_stamp: Dictionary = Time.get_datetime_dict_from_unix_time(int(timeline_row["t"]))
		timeline_row["day"] = int((int(timeline_row["t"]) - start) / SECONDS_PER_DAY) + 1
		timeline_row["hour"] = int(timeline_stamp.get("hour", 0))
		timeline_row["minute"] = int(timeline_stamp.get("minute", 0))

	return {
		"schema": 1,
		"config": {"days": days, "seed": seed_value, "start_unix": start, "pack_id": pack_id, "small_beginnings": small},
		"not_simulated": NOT_SIMULATED.duplicate(),
		"rows": rows,
		"days": day_rows,
		"totals": {
			"decisions": decisions_total,
			"rows": rows.size(),
			"distinct_texts": seen_texts.size(),
			"distinct_text_ratio": _snap(ratio),
			"flat_days": flat_days,
			"longest_flat_streak": longest_flat_streak,
			"places_visited": places_seen.size(),
			"companions_met": companions_seen.size(),
			"wants_noticed": wants_noticed,
			"purchases": purchases_total,
			"intents": intents_total,
			"signs": signs_total,
			"sights": sights_total,
			"blocked_tries": blocked_total,
			"night_rows": night_rows,
			"top10_share": _snap(top10_share),
			"needs": needs_report,
			"memory_max_edges": memory_max_edges,
		},
		"final": {
			"location": str(state.profile.get("mind", {}).get("location", "")),
			"favourite": str(preferences.get("favourite", "")),
			"least": str(preferences.get("least", "")),
			"feelings": feelings,
			"wants": final_wants,
			"bond_level": int(state.profile.get("bond_level", 1)),
			"top_trait": str(state.get_behavior_context().get("top_trait", "")),
			"meso": int(state.get_inventory_snapshot().get("meso", 0)),
			"journal_tail": tail,
			"memory": memory_service.land_memory_report(state.profile, {"home_place": home_place}),
			"known_places": {"found": known_found, "signs": known_signs},
			"letters": {
				"console_goes": int(console_record.get("goes", 0)),
				"console_known_t": int(console_record.get("known_t", 0)),
				"letters": final_letters,
			},
		},
		"letter_timeline": letter_timeline,
	}


static func _snap(value: float) -> float:
	return snappedf(value, 0.001)


# Wants it is still saving or shopping for (bought and faded ones stay in the
# list as history).
static func _open_wants(wants: Array) -> int:
	var open := 0
	for want_variant in wants:
		if typeof(want_variant) != TYPE_DICTIONARY:
			continue
		if str((want_variant as Dictionary).get("status", "")) in ["saving", "buying"]:
			open += 1
	return open


# journal: "all" prints every row, "firsts" only rows that carry a first or a
# never-seen text, "none" no rows.
static func format_text(report: Dictionary, journal: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var config: Dictionary = report.get("config", {})
	var start: int = int(config.get("start_unix", DEFAULT_START_UNIX))
	var world_name: String = "land" if bool(config.get("small_beginnings", false)) else "town"
	lines.append("== Buddy life: %s days, seed %s, pack %s, world %s ==" % [str(config.get("days", 0)), str(config.get("seed", 0)), str(config.get("pack_id", "")), world_name])
	lines.append("Not simulated: " + ", ".join(PackedStringArray(report.get("not_simulated", []))))
	lines.append("")

	var rows_by_day := {}
	var seen_texts := {}
	for row_variant in report.get("rows", []):
		var row: Dictionary = row_variant
		var shown: bool = journal == "all"
		if journal == "firsts":
			if not (row.get("firsts", []) as Array).is_empty() or not seen_texts.has(str(row.get("text", ""))):
				shown = true
		seen_texts[str(row.get("text", ""))] = true
		if shown:
			var day_key: int = int(row.get("day", 0))
			if not rows_by_day.has(day_key):
				rows_by_day[day_key] = []
			(rows_by_day[day_key] as Array).append(row)

	for day_variant in report.get("days", []):
		var day_row: Dictionary = day_variant
		var day_number: int = int(day_row.get("day", 0))
		var day_start: int = start + (day_number - 1) * SECONDS_PER_DAY
		var stamp: Dictionary = Time.get_datetime_dict_from_unix_time(day_start)
		var weekday: String = str(WEEKDAYS[int(stamp.get("weekday", 0))])
		lines.append("--- Day %d (%s) %d decisions, meso %d ---" % [day_number, weekday, int(day_row.get("decisions", 0)), int(day_row.get("meso", 0))])
		lines.append("intents: " + _counts_text(day_row.get("intents", {})))
		var mood: Dictionary = day_row.get("mood", {})
		lines.append("mood: " + _counts_text(mood) + "; open wants " + str(day_row.get("open_wants", 0)) + "; purchases " + str(day_row.get("purchases", 0)))
		var first_names: PackedStringArray = PackedStringArray()
		for first_variant in day_row.get("firsts", []):
			var first_row: Dictionary = first_variant
			first_names.append(str(first_row.get("kind", "")) + " " + str(first_row.get("name", first_row.get("id", ""))))
		lines.append("firsts: " + (", ".join(first_names) if not first_names.is_empty() else "none") + "; new texts " + str(day_row.get("new_texts", 0)))
		for shown_variant in rows_by_day.get(day_number, []):
			var shown_row: Dictionary = shown_variant
			lines.append("%02d:%02d [%s] %s" % [int(shown_row.get("hour", 0)), int(shown_row.get("minute", 0)), str(shown_row.get("intent", "")), str(shown_row.get("text", ""))])
		lines.append("")

	var totals: Dictionary = report.get("totals", {})
	lines.append("== Totals ==")
	lines.append("decisions %d, journal rows %d, distinct texts %d (ratio %s)" % [int(totals.get("decisions", 0)), int(totals.get("rows", 0)), int(totals.get("distinct_texts", 0)), str(totals.get("distinct_text_ratio", 0))])
	lines.append("flat days %d, longest flat streak %d" % [int(totals.get("flat_days", 0)), int(totals.get("longest_flat_streak", 0))])
	lines.append("places visited %d, companions met %d, wants noticed %d, purchases %d" % [int(totals.get("places_visited", 0)), int(totals.get("companions_met", 0)), int(totals.get("wants_noticed", 0)), int(totals.get("purchases", 0))])
	lines.append("intents: " + _counts_text(totals.get("intents", {})))
	lines.append("signs %d, sights %d, failed tries %d, night rows %d, top-10 lines cover %s of the journal" % [int(totals.get("signs", 0)), int(totals.get("sights", 0)), int(totals.get("blocked_tries", 0)), int(totals.get("night_rows", 0)), str(totals.get("top10_share", 0))])
	var needs_totals: Dictionary = totals.get("needs", {})
	for need_name in MOOD_KEYS:
		var need_row: Dictionary = needs_totals.get(need_name, {})
		lines.append("need %s: %s..%s, at a limit %s" % [need_name, str(need_row.get("min", 0)), str(need_row.get("max", 0)), str(need_row.get("at_limit_share", 0))])
	lines.append("Firsts:")
	for day_variant in report.get("days", []):
		var firsts_day: Dictionary = day_variant
		for first_variant in firsts_day.get("firsts", []):
			var first_entry: Dictionary = first_variant
			var first_stamp: Dictionary = Time.get_datetime_dict_from_unix_time(int(first_entry.get("t", 0)))
			lines.append("  day %d %02d:%02d  %s %s" % [int(firsts_day.get("day", 0)), int(first_stamp.get("hour", 0)), int(first_stamp.get("minute", 0)), str(first_entry.get("kind", "")), str(first_entry.get("name", first_entry.get("id", "")))])
	var memory: Dictionary = (report.get("final", {}) as Dictionary).get("memory", {})
	var alone_t: int = int(memory.get("alone_belief_t", 0))
	var alone_text := "never" if alone_t <= 0 else "day %d" % (int((alone_t - start) / SECONDS_PER_DAY) + 1)
	lines.append("memory: edges %s, total %d, max %d, alone belief %s, untraceable %d, today %d" % [_counts_text(memory.get("edges", {})), int(memory.get("total_edges", 0)), int(totals.get("memory_max_edges", 0)), alone_text, int(memory.get("untraceable", 0)), int(memory.get("today", 0))])
	if bool(config.get("small_beginnings", false)):
		var letters_final: Dictionary = (report.get("final", {}) as Dictionary).get("letters", {})
		var known_t: int = int(letters_final.get("console_known_t", 0))
		lines.append("console worked out: %s (%d goes to the glowing box so far)" % ["not yet" if known_t <= 0 else _day_clock(known_t, start), int(letters_final.get("console_goes", 0))])
		var letter_number := 0
		for letter_variant in letters_final.get("letters", []):
			var letter: Dictionary = letter_variant
			letter_number += 1
			var sent_t: int = int(letter.get("sent_t", 0))
			var read_t: int = int(letter.get("read_t", 0))
			if read_t <= 0:
				lines.append("letter %d: sent %s, not read" % [letter_number, _day_clock(sent_t, start)])
			else:
				var minutes_after: int = int((read_t - sent_t) / 60)
				lines.append("letter %d: sent %s, read %s (after %d h %d min)" % [letter_number, _day_clock(sent_t, start), _day_clock(read_t, start), int(minutes_after / 60), minutes_after % 60])
		var timeline: Array = report.get("letter_timeline", [])
		if not timeline.is_empty():
			lines.append("Letter timeline:")
			for timeline_variant in timeline:
				var timeline_row: Dictionary = timeline_variant
				lines.append("  day %d %02d:%02d  %s" % [int(timeline_row.get("day", 0)), int(timeline_row.get("hour", 0)), int(timeline_row.get("minute", 0)), str(timeline_row.get("text", ""))])
	var final: Dictionary = report.get("final", {})
	lines.append("Final: at %s, favourite %s, least %s, bond level %d, top trait %s, meso %d" % [str(final.get("location", "")), str(final.get("favourite", "")), str(final.get("least", "")), int(final.get("bond_level", 1)), str(final.get("top_trait", "")), int(final.get("meso", 0))])
	for tail_text in final.get("journal_tail", []):
		lines.append("  > " + str(tail_text))
	return "\n".join(lines)


# "day D HH:MM" for a simulated time.
static func _day_clock(unix_time: int, start: int) -> String:
	var stamp: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return "day %d %02d:%02d" % [int((unix_time - start) / SECONDS_PER_DAY) + 1, int(stamp.get("hour", 0)), int(stamp.get("minute", 0))]


static func _counts_text(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for key in keys:
		parts.append(str(key) + " " + str(counts[key]))
	return ", ".join(parts) if not parts.is_empty() else "none"
