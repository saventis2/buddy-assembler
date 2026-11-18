extends RefCounted

# The mailbox (Plan 14 step 2c-1): the letters between the person and the buddy,
# kept in profile["letters"]. Pure functions on the profile, written as static
# so the mind can call them through a preload too. Land world only; nothing
# here is used in the old town.
#
# profile["letters"] = {"items": [letter, ...]}, oldest first. A letter is:
#   {"id", "from": "you" | "buddy", "text", "t",
#    "read_t": yours: when the buddy read it (0 = waiting); the buddy's: 0,
#    "reply_due": yours: read and not yet answered (step 2c-2 answers it),
#    "reply_to": the buddy's: the id it answers ("" for its first letter)}

const MemoryService = preload("res://scripts/services/memory_service.gd")

const MAX_LETTER_CHARS := 1500
const MAX_LETTERS := 60
# At most this many of your letters wait unread at the glowing box; another has
# to wait until it reads some. The mailbox is in the save, so it cannot grow
# without end, and letters waiting to be read are never dropped for the cap.
const MAX_WAITING := 20
# A letter left in the inbox that has not turned up in the mailbox after this
# long, with its file gone, was dropped (an old host does not know letters).
const LOST_AFTER_SECONDS := 120
const FROM_YOU := "you"
const FROM_BUDDY := "buddy"


# The profile with profile["letters"]["items"] holding well-formed letters only.
static func ensure_letters(profile: Dictionary) -> Dictionary:
	var out: Dictionary = profile.duplicate(false)
	out["letters"] = {"items": _items(profile)}
	return out


# What may be sent: {"ok", "text" (cleaned), "reason": "" | "empty" | "too_long" | "sensitive"}.
static func check_text(text: String) -> Dictionary:
	var cleaned: String = _clean(text)
	var reason := ""
	if cleaned == "":
		reason = "empty"
	elif cleaned.length() > MAX_LETTER_CHARS:
		reason = "too_long"
	elif MemoryService.looks_sensitive(cleaned):
		reason = "sensitive"
	return {"ok": reason == "", "text": cleaned, "reason": reason}


# Puts a letter from the person in the mailbox. A request can arrive twice: an
# id that is already there is ok and changes nothing.
static func add_from_you(profile: Dictionary, id: String, text: String, now: int) -> Dictionary:
	var items: Array = _items(profile)
	for item in items:
		if str((item as Dictionary)["id"]) == id and id != "":
			return {"profile": profile, "ok": true, "id": id, "reason": ""}
	var checked: Dictionary = check_text(text)
	if not bool(checked["ok"]):
		return {"profile": profile, "ok": false, "id": "", "reason": str(checked["reason"])}
	if unread_count(profile) >= MAX_WAITING:
		return {"profile": profile, "ok": false, "id": "", "reason": "too_many_waiting"}
	var letter_id: String = id if id != "" else new_id(now)
	items.append({"id": letter_id, "from": FROM_YOU, "text": str(checked["text"]), "t": now, "read_t": 0, "reply_due": false, "reply_to": ""})
	var out: Dictionary = profile.duplicate(false)
	out["letters"] = {"items": _trim(items)}
	return {"profile": out, "ok": true, "id": letter_id, "reason": ""}


# Letters from the person that the buddy has not read yet, oldest first.
static func unread_from_you(profile: Dictionary) -> Array:
	var rows: Array = []
	for item in _items(profile):
		if _waiting(item):
			rows.append(item)
	return rows


static func unread_count(profile: Dictionary) -> int:
	var count := 0
	for item in _items(profile):
		if _waiting(item):
			count += 1
	return count


static func has_unread(profile: Dictionary) -> bool:
	for item in _items(profile):
		if _waiting(item):
			return true
	return false


# The buddy reads these: each gets its read time and now waits for an answer.
static func mark_read(profile: Dictionary, ids: Array, now: int) -> Dictionary:
	var items: Array = _items(profile)
	for item in items:
		var row: Dictionary = item
		if _waiting(row) and ids.has(str(row["id"])):
			row["read_t"] = maxi(1, now)
			row["reply_due"] = true
	var out: Dictionary = profile.duplicate(false)
	out["letters"] = {"items": items}
	return out


# For the desktop, about a letter of yours: "read", "waiting" (in the mailbox,
# not read), "on_its_way" (still in the inbox, or only just sent) or "lost".
static func delivery_state(profile: Dictionary, id: String, inbox_file_exists: bool, sent_at: int, now: int) -> String:
	for item in _items(profile):
		if str((item as Dictionary)["id"]) == id:
			return "read" if int((item as Dictionary)["read_t"]) > 0 else "waiting"
	if inbox_file_exists or now - sent_at < LOST_AFTER_SECONDS:
		return "on_its_way"
	return "lost"


# How many letters from the buddy are newer than `seen_t`.
static func count_from_buddy_after(profile: Dictionary, seen_t: int) -> int:
	var count := 0
	for item in _items(profile):
		if str((item as Dictionary)["from"]) == FROM_BUDDY and int((item as Dictionary)["t"]) > seen_t:
			count += 1
	return count


# Same shape as an inbox request id (buddy_whereabouts.send_request).
static func new_id(now: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%d-%08x" % [now, rng.randi()]


static func _waiting(item: Variant) -> bool:
	return str((item as Dictionary)["from"]) == FROM_YOU and int((item as Dictionary)["read_t"]) <= 0


# A copy of the well-formed letters; anything else in the save is dropped.
static func _items(profile: Dictionary) -> Array:
	var rows: Array = []
	var letters_variant = profile.get("letters", null)
	if typeof(letters_variant) != TYPE_DICTIONARY:
		return rows
	var items_variant = (letters_variant as Dictionary).get("items", null)
	if typeof(items_variant) != TYPE_ARRAY:
		return rows
	for item_variant in items_variant:
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		var from: String = str(item.get("from", ""))
		if str(item.get("id", "")) == "" or (from != FROM_YOU and from != FROM_BUDDY):
			continue
		if typeof(item.get("text", null)) != TYPE_STRING or str(item["text"]) == "":
			continue
		var t_variant = item.get("t", null)
		if typeof(t_variant) != TYPE_INT and typeof(t_variant) != TYPE_FLOAT:
			continue
		rows.append({
			"id": str(item["id"]),
			"from": from,
			"text": str(item["text"]),
			"t": int(t_variant),
			"read_t": int(item.get("read_t", 0)),
			"reply_due": bool(item.get("reply_due", false)),
			"reply_to": str(item.get("reply_to", "")),
		})
	return rows


# Over the cap, the oldest letters go: first those read and answered (and the
# buddy's own), then, if that is not enough, the oldest still waiting for an
# answer. Letters waiting to be read are never dropped; MAX_WAITING keeps them
# few, so the mailbox stays at MAX_LETTERS.
static func _trim(items: Array) -> Array:
	var rows: Array = items
	while rows.size() > MAX_LETTERS:
		var drop := -1
		for index in range(rows.size()):
			var row: Dictionary = rows[index]
			if not _waiting(row) and not bool(row["reply_due"]):
				drop = index
				break
		if drop < 0:
			for index in range(rows.size()):
				if not _waiting(rows[index]):
					drop = index
					break
		if drop < 0:
			break
		rows.remove_at(drop)
	return rows


# Ends stripped, line breaks kept, runs of spaces made one.
static func _clean(text: String) -> String:
	var lines: PackedStringArray = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var kept: PackedStringArray = PackedStringArray()
	for line in lines:
		var one: String = line
		while one.contains("  "):
			one = one.replace("  ", " ")
		kept.append(one)
	return "\n".join(kept).strip_edges()
