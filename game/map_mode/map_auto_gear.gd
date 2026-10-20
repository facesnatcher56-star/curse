class_name MapAutoGear
extends RefCounted
## Dev autoplay helper (`--mapmode-auto`): after each clear's collection, puts on every drop that is an upgrade for the warrior or the Cutter.
## The decision is the game's own shared item comparison and nothing else: Items.hero_can_wear (requirements), LootAppraisal.trend (the loot
## summary's green arrow) and Items.compare (the item card's numbers); the equip is PlayerStats.equip_from_bag. Only the autoplay calls it.

const MAX_SWAPS := 40   # a safety stop: a swap only happens for a strictly better piece, but the card's balance is not a total order

## Every item the run dropped: key -> {name, rarity, slot, def, legendary, reason, who (set when worn)}
static var seen: Dictionary = {}
static var equips: Array[Dictionary] = []

static func reset() -> void:
	seen.clear()
	equips.clear()

static func key_of(item: Dictionary) -> String:
	var c: Dictionary = item.duplicate(true)
	c.erase("bag_cell")
	c.erase("bag_rotated")
	return JSON.stringify(c)

static func rarity_name(item: Dictionary) -> String:
	if MapModeLegendaries.id_of(item) != "":
		return "Legendary"
	return String(Items.RARITY_NAMES[int(item.get("rarity", 0))])

## The worn items of each body before the pickups: member id -> {place -> item key}.
static func snapshot(bodies: Array) -> Dictionary:
	var out: Dictionary = {}
	for body in bodies:
		var b := body as Player
		if b != null and is_instance_valid(b):
			var row: Dictionary = {}
			for place in b.stats.equipment:
				row[place] = key_of(b.stats.equipment[place])
			out[b.member_id] = row
	return out

## The comparison lines that decide `item` against what `body` wears at `place` (the item card's own, the wear warning left out), and their balance.
static func verdict(item: Dictionary, body: Player, place: int) -> Dictionary:
	if not body.stats.equipment.has(place):
		return {"balance": 1, "lines": ["Nothing worn in this slot"], "vs": ""}
	var lines: PackedStringArray = []
	var balance: int = 0
	for line in Items.compare(item, body.stats.equipment[place], body.member_id):
		if String(line.get("key", "")) == Items.WARNING_KEY:
			continue
		lines.append("%s %s" % [line["text"], "(better)" if int(line["sign"]) > 0 else ("(worse)" if int(line["sign"]) < 0 else "")])
		balance += int(line["sign"])
	return {"balance": balance, "lines": lines, "vs": String(body.stats.equipment[place].get("name", "?"))}

## Runs after `MapMode._collect_rewards`: logs what the pickups wore at once, then equips bag upgrades until none is left. `rows` are the loot
## summary rows (HudLootCards.summary_rows) of this clear. Returns the equip records made (also in `equips` and the fight log).
static func process(m: MapMode, before: Dictionary, rows: Array[Dictionary]) -> Array[Dictionary]:
	var bodies: Array = [m.hero, m.companion]
	var made: Array[Dictionary] = []
	for row in rows:
		var it: Dictionary = row["item"]
		var k: String = key_of(it)
		if not seen.has(k):
			seen[k] = _entry(it, "left on the ground (out of reach or bag full)")
	# Pickups that went straight onto an empty slot.
	for body in bodies:
		var b := body as Player
		if b == null or not is_instance_valid(b):
			continue
		for place in b.stats.equipment:
			if (before.get(b.member_id, {}) as Dictionary).get(place, "") != key_of(b.stats.equipment[place]):
				made.append(_record(b.stats.equipment[place], b, place, {"balance": 1, "lines": ["Nothing worn in this slot"], "vs": ""}, "picked up into an empty slot"))
	# Bag upgrades.
	for i in MAX_SWAPS:
		var pick: Dictionary = _best_swap(bodies)
		if pick.is_empty():
			break
		var b: Player = pick["body"]
		var item: Dictionary = b.stats.bag[int(pick["index"])].duplicate(true)
		if not b.stats.equip_from_bag(int(pick["index"]), int(pick["place"])):
			break
		made.append(_record(item, b, int(pick["place"]), pick["verdict"], "upgrade from the bag"))
	_note_leftovers(bodies)
	for rec in made:
		print(line_of(rec))
		m.log.note_equip(rec)
		equips.append(rec)
	return made

## The best upgrade over the bag, the two members and the places: {body, index, place, verdict}, or {} when there is none.
static func _best_swap(bodies: Array) -> Dictionary:
	var best: Dictionary = {}
	for body in bodies:
		var b := body as Player
		if b == null or not is_instance_valid(b) or b.stats == null:
			continue
		for i in b.stats.bag.size():
			var item: Dictionary = b.stats.bag[i]
			if not Items.hero_can_wear(item, b.member_id):
				continue
			if LootAppraisal.trend(item, b.stats) <= 0:   # the loot summary's own arrow: only a green one is worn
				continue
			var hc: int = b.stats._hand_conflict(item)
			if hc >= 0 and b.stats.equipment.has(hc):
				continue   # a two-handed weapon would take the shield off (or the reverse): not a plain upgrade
			for place in Items.places(int(item["slot"])):
				var v: Dictionary = verdict(item, b, place)
				if int(v["balance"]) > 0 and (best.is_empty() or int(v["balance"]) > int((best["verdict"] as Dictionary)["balance"])):
					best = {"body": b, "index": i, "place": place, "verdict": v}
	return best

## Why each dropped piece that was never worn stayed in the bag, kept for the end-of-run report.
static func _note_leftovers(bodies: Array) -> void:
	for body in bodies:
		var b := body as Player
		if b == null or not is_instance_valid(b):
			continue
		for item in b.stats.bag:
			var k: String = key_of(item)
			if not seen.has(k):
				seen[k] = _entry(item, "")
			if String(seen[k]["who"]) != "":
				continue
			var why: PackedStringArray = []
			for other in bodies:
				var o := other as Player
				if o == null or not is_instance_valid(o):
					continue
				if not Items.hero_can_wear(item, o.member_id):
					why.append("%s cannot wear it (%s)" % [o.display_name, Items.requirement_text(item, o.member_id)])
					continue
				var hc: int = o.stats._hand_conflict(item)
				if hc >= 0 and o.stats.equipment.has(hc):
					why.append("%s: would displace a %s" % [o.display_name, Items.SLOT_NAMES[hc]])
					continue
				var parts: PackedStringArray = []
				for place in Items.places(int(item["slot"])):
					var v: Dictionary = verdict(item, o, place)
					parts.append("vs %s: %s" % [v["vs"], ", ".join(v["lines"])])
				why.append("%s: not better (%s)" % [o.display_name, " | ".join(parts)])
			seen[k]["reason"] = "in the bag; " + "; ".join(why)

static func _entry(item: Dictionary, reason: String) -> Dictionary:
	return {"name": String(item.get("name", "?")), "rarity": rarity_name(item), "slot": String(Items.SLOT_NAMES[int(item["slot"])]), "def": String(item.get("def", "")),
		"legendary": MapModeLegendaries.id_of(item), "trait": String(MapModeTraits.trait_of(item).get("id", "")), "reason": reason, "who": ""}

static func _record(item: Dictionary, body: Player, place: int, v: Dictionary, how: String) -> Dictionary:
	var k: String = key_of(item)
	if not seen.has(k):
		seen[k] = _entry(item, "")
	seen[k]["who"] = body.display_name
	seen[k]["reason"] = "worn"
	var rec: Dictionary = _entry(item, how)
	rec.merge({"who": body.display_name, "member": body.member_id, "place": place, "how": how, "replaces": String(v.get("vs", "")),
		"lines": v.get("lines", []), "balance": int(v.get("balance", 0)), "hero_level": body.character.level}, true)
	return rec

static func line_of(rec: Dictionary) -> String:
	var replaces: String = String(rec.get("replaces", ""))
	return "[mapmode] EQUIP %s (%s, %s) on %s: %s%s; why: %s (balance %+d)" % [rec["name"], rec["rarity"], rec["slot"], rec["who"], rec["how"],
		(", replaces " + replaces) if replaces != "" else "", ", ".join(rec["lines"]), int(rec["balance"])]
