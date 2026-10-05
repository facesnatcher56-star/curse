class_name Items
extends RefCounted
## Item data and reward generation. Design rule: base items are plain and fixed; the only variation
## is a behaviour (affix) that changes how you play. No random stat lines.
## Items are plain Dictionaries: {slot, rarity, name, base, stats, affix, flavor}.

enum Slot { WEAPON, ARMOR, TRINKET }
enum Rarity { COMMON, RARE, UNIQUE }

const SLOT_NAMES: Array[String] = ["Weapon", "Armor", "Trinket"]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Unique"]
const RARITY_COLORS: Array[Color] = [Color(0.82, 0.82, 0.82), Color(0.45, 0.72, 1.0), Color(1.0, 0.62, 0.18)]

## Affixes (id -> {title, slot, desc}) come from res://data/affixes/*.tres through AffixDb. Every one is a behaviour, not a number.

## Plain base items. Weapons trade speed against damage; armor trades protection against mobility.
const BASES := {
	Slot.WEAPON: [
		{"name": "Falchion", "damage": 0.9, "speed": 1.18},
		{"name": "Longsword", "damage": 1.0, "speed": 1.0},
		{"name": "Greatsword", "damage": 1.35, "speed": 0.82},
	],
	Slot.ARMOR: [
		{"name": "Leather Jerkin", "armor": 15.0, "roll_cost": 0.8, "roll_speed": 1.1},
		{"name": "Mail Hauberk", "armor": 35.0, "roll_cost": 1.0, "roll_speed": 1.0},
		{"name": "Plate Cuirass", "armor": 60.0, "roll_cost": 1.4, "roll_speed": 0.9},
	],
	Slot.TRINKET: [
		{"name": "Charm"}, {"name": "Signet"}, {"name": "Talisman"},
	],
}

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
	var bases: Array = BASES[slot]
	var base: Dictionary = bases[randi() % bases.size()]
	if base_name != "":
		for candidate in bases:
			if candidate["name"] == base_name:
				base = candidate
	var stats: Dictionary = {}
	match slot:
		Slot.WEAPON:
			stats = {"damage": float(base["damage"]) * (1.0 + 0.08 * (tier - 1)), "speed": float(base["speed"])}
		Slot.ARMOR:
			stats = {"armor": float(base["armor"]) + 6.0 * (tier - 1), "roll_cost": float(base["roll_cost"]),
				"roll_speed": float(base["roll_speed"])}
	var name: String = base["name"]
	if affix != "" and rarity == Rarity.RARE:
		name = "%s %s" % [AffixDb.all()[affix]["title"], name]
	return {"slot": slot, "rarity": rarity, "name": name, "base": base["name"], "stats": stats, "affix": affix, "flavor": ""}

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

## The model an item lies on the ground as (made in Blender by tools/blender/make_items.py).
static func model_path(item: Dictionary) -> String:
	return "res://assets/models/items/%s/model.glb" % String(item["base"]).to_lower().replace(" ", "_")

## Text lines for a tooltip/card: stats first, then the behaviour.
static func lines(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var stats: Dictionary = item["stats"]
	match int(item["slot"]):
		Slot.WEAPON:
			out.append("Damage x%.2f    Speed x%.2f" % [stats["damage"], stats["speed"]])
		Slot.ARMOR:
			out.append("Armor %d    Roll cost x%.1f    Roll speed x%.1f" % [stats["armor"], stats["roll_cost"], stats["roll_speed"]])
		Slot.TRINKET:
			out.append("No stats. Only an effect.")
	if item["affix"] != "":
		out.append(AffixDb.all()[item["affix"]]["desc"])
	if item["flavor"] != "":
		out.append("\"%s\"" % item["flavor"])
	return out
