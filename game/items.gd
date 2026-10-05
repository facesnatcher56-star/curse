class_name Items
extends RefCounted
## Item data and reward generation. Design rule: base items are plain and fixed; the only variation
## is a behaviour (affix) that changes how you play. No random stat lines.
## The base items are data (ItemDef in res://data/items/, through ItemDb). An item in the world is a Dictionary built from one:
## {def, tier, slot, rarity, name, base, stats, affix, flavor}. Only `def`, `tier`, `rarity`, `affix` (and the name of a unique) are
## saved (see to_save / from_save): everything else is looked up again from the definition when the item is loaded.

enum Slot { WEAPON, ARMOR, TRINKET }
enum Rarity { COMMON, RARE, UNIQUE }

const SLOT_NAMES: Array[String] = ["Weapon", "Armor", "Trinket"]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Unique"]
const RARITY_COLORS: Array[Color] = [Color(0.82, 0.82, 0.82), Color(0.45, 0.72, 1.0), Color(1.0, 0.62, 0.18)]

## Affixes (id -> {title, slot, desc}) come from res://data/affixes/*.tres through AffixDb. Every one is a behaviour, not a number.

const UNIQUES := [
	{"name": "Gravewarden", "slot": Slot.WEAPON, "base": "Greatsword", "affix": "gravewarden",
		"flavor": "Pulled from a grave that was not empty."},
	{"name": "Aegis of the Fallen", "slot": Slot.ARMOR, "base": "Plate Cuirass", "affix": "aegis",
		"flavor": "Dented by every blow that missed you."},
	{"name": "Ember Signet", "slot": Slot.TRINKET, "base": "Signet", "affix": "ember",
		"flavor": "Still warm."},
]

static func starting_gear() -> Array[Dictionary]:
	return [make(Slot.WEAPON, Rarity.COMMON, 1, "", "Longsword"), make(Slot.ARMOR, Rarity.COMMON, 1, "", "Leather Jerkin")]

## Builds one item. `tier` scales the fixed numbers slowly with progress (no random variance).
static func make(slot: int, rarity: int, tier: int, affix: String = "", base_name: String = "") -> Dictionary:
	var bases: Array[ItemDef] = ItemDb.of_slot(slot)
	var def: ItemDef = bases[randi() % bases.size()]
	if base_name != "":
		var named: ItemDef = ItemDb.by_name(base_name)
		if named != null and named.slot == slot:
			def = named
	return build(def, tier, rarity, affix)

## An item instance from its definition. Everything but def, tier, rarity and affix is derived.
static func build(def: ItemDef, tier: int, rarity: int, affix: String = "") -> Dictionary:
	var name: String = def.display_name
	if affix != "" and rarity == Rarity.RARE:
		name = "%s %s" % [AffixDb.all()[affix]["title"], name]
	return {"def": def.id, "tier": tier, "slot": def.slot, "rarity": rarity, "name": name, "base": def.display_name,
		"stats": def.stats_at(tier), "affix": affix, "flavor": ""}

## What is written to a save: just enough to build the item again.
static func to_save(item: Dictionary) -> Dictionary:
	var saved: Dictionary = {"def": item["def"], "tier": int(item["tier"]), "rarity": int(item["rarity"]), "affix": String(item["affix"])}
	if int(item["rarity"]) == Rarity.UNIQUE:
		saved["unique"] = item["name"]
	return saved

## Builds an item from a saved one. Takes the current form and the form from before definitions (a whole item dictionary with a base
## name and its stats), so old saves load. Returns {} if the base no longer exists, or the affix no longer exists on a non-common item.
static func from_save(saved: Dictionary) -> Dictionary:
	var def: ItemDef = ItemDb.get_def(String(saved.get("def", "")))
	var tier: int = int(saved.get("tier", 0))
	if def == null:   # before definitions: found by the base name, the tier worked out from the stats
		def = ItemDb.by_name(String(saved.get("base", "")))
		if def != null and tier <= 0:
			tier = def.tier_of(saved.get("stats", {}))
	if def == null:
		return {}
	var rarity: int = int(saved.get("rarity", Rarity.COMMON))
	var affix: String = String(saved.get("affix", ""))
	if affix != "" and not AffixDb.all().has(affix):
		return {}
	var item: Dictionary = build(def, maxi(tier, 1), rarity, affix)
	if rarity == Rarity.UNIQUE:
		var wanted: String = String(saved.get("unique", saved.get("name", "")))
		for entry in UNIQUES:
			if entry["name"] == wanted:
				item["name"] = entry["name"]
				item["flavor"] = entry["flavor"]
	return item

static func make_unique(entry: Dictionary, tier: int) -> Dictionary:
	var item: Dictionary = make(entry["slot"], Rarity.UNIQUE, tier, entry["affix"], entry["base"])
	item["name"] = entry["name"]
	item["flavor"] = entry["flavor"]
	return item

## One random item. `unique_chance` and `rare_chance` are the odds of each (otherwise common); trinkets are never common.
static func roll_one(wave: int, unique_chance: float, rare_chance: float, owned_uniques: Array[String]) -> Dictionary:
	var tier: int = 1 + wave / 3
	var slot: int = randi() % 3
	var roll: float = randf()
	var rarity: int = Rarity.COMMON
	if roll < unique_chance:
		rarity = Rarity.UNIQUE
	elif roll < unique_chance + rare_chance:
		rarity = Rarity.RARE
	if slot == Slot.TRINKET and rarity == Rarity.COMMON:
		rarity = Rarity.RARE
	var item: Dictionary = {}
	if rarity == Rarity.UNIQUE:
		var pool: Array[Dictionary] = []
		for entry in UNIQUES:
			if entry["slot"] == slot and not (entry["name"] in owned_uniques):
				pool.append(entry)
		if pool.is_empty():
			rarity = Rarity.RARE
		else:
			item = make_unique(pool[randi() % pool.size()], tier)
	if rarity == Rarity.RARE:
		var ids: Array[String] = []
		for id in AffixDb.all():
			if AffixDb.all()[id]["slot"] == slot and AffixDb.all()[id]["title"] != "":
				ids.append(id)
		item = make(slot, Rarity.RARE, tier, ids[randi() % ids.size()])
	elif rarity == Rarity.COMMON:
		item = make(slot, Rarity.COMMON, tier)
	return item

## What a dead monster drops. `luck` 0 is an ordinary monster; 1 is a Brute (guaranteed rare or better, a fair chance of a unique).
static func roll_drop(wave: int, luck: float, owned_uniques: Array[String]) -> Dictionary:
	var unique_chance: float = (0.20 if luck >= 1.0 else (0.08 if wave >= 4 else 0.04))
	var rare_chance: float = 1.0 if luck >= 1.0 else 0.55
	return roll_one(wave, unique_chance, rare_chance, owned_uniques)

## Three different items (the trader's stock). Brutes guarantee at least rare; trinkets are always rare or better.
static func roll_choices(wave: int, brute_killed: bool, owned_uniques: Array[String]) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var attempts: int = 0
	while choices.size() < 3 and attempts < 40:
		attempts += 1
		var item: Dictionary = roll_drop(wave, 1.0 if brute_killed else 0.0, owned_uniques)
		var duplicate: bool = false
		for existing in choices:
			if existing["name"] == item["name"]:
				duplicate = true
		if not duplicate:
			choices.append(item)
	return choices

## How `item` compares with what is worn in its slot: lines of {text, sign} (sign +1 better, -1 worse, 0 neutral) for the tooltip.
static func compare(item: Dictionary, current: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if current == null:
		out.append({"text": "Nothing worn in this slot", "sign": 1})
		return out
	var worn: Dictionary = current
	var a: Dictionary = item["stats"]
	var b: Dictionary = worn["stats"]
	match int(item["slot"]):
		Slot.WEAPON:
			_diff(out, "Damage", float(a["damage"]), float(b["damage"]), true, "x%.2f")
			_diff(out, "Speed", float(a["speed"]), float(b["speed"]), true, "x%.2f")
		Slot.ARMOR:
			_diff(out, "Armor", float(a["armor"]), float(b["armor"]), true, "%d")
			_diff(out, "Roll cost", float(a["roll_cost"]), float(b["roll_cost"]), false, "x%.1f")
			_diff(out, "Roll speed", float(a["roll_speed"]), float(b["roll_speed"]), true, "x%.1f")
	var new_affix: String = String(item["affix"])
	var old_affix: String = String(worn["affix"])
	if new_affix != old_affix:
		if new_affix != "":
			out.append({"text": "Gains: %s" % AffixDb.all()[new_affix]["title"], "sign": 1})
		if old_affix != "":
			out.append({"text": "Loses: %s" % AffixDb.all()[old_affix]["title"], "sign": -1})
	if out.is_empty():
		out.append({"text": "Same as what you wear", "sign": 0})
	return out

static func _diff(out: Array[Dictionary], label: String, value: float, other: float, higher_is_better: bool, fmt: String) -> void:
	if is_equal_approx(value, other):
		return
	var delta: float = value - other
	var better: bool = (delta > 0.0) == higher_is_better
	var shown: String = (fmt % value) + "   (%s%s)" % ["+" if delta > 0.0 else "-", (fmt % absf(delta)).trim_prefix("x")]
	out.append({"text": "%s  %s" % [label, shown], "sign": 1 if better else -1})

## The model an item lies on the ground as (from its definition; made in Blender by tools/blender/make_items.py).
static func model_path(item: Dictionary) -> String:
	return ItemDb.get_def(String(item["def"])).model_path

## Text lines for a tooltip/card: stats first, then the behaviour.
static func lines(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var stats: Dictionary = item["stats"]
	match int(item["slot"]):
		Slot.WEAPON:
			out.append("Damage x%.2f    Speed x%.2f" % [stats["damage"], stats["speed"]])
			var style: String = String(ItemDb.get_def(String(item["def"])).profile.get("style", ""))
			if style != "":
				out.append(style)
		Slot.ARMOR:
			out.append("Armor %d    Roll cost x%.1f    Roll speed x%.1f" % [stats["armor"], stats["roll_cost"], stats["roll_speed"]])
		Slot.TRINKET:
			out.append("No stats. Only an effect.")
	if item["affix"] != "":
		out.append(AffixDb.all()[item["affix"]]["desc"])
	if item["flavor"] != "":
		out.append("\"%s\"" % item["flavor"])
	return out
