class_name Items
extends RefCounted
## Item data and reward generation. The base items are data (ItemDef in res://data/items/, through ItemDb). An item in the world is a
## Dictionary built from one: {def, tier, slot, rarity, name, base, stats}. Only `def`, `tier` and `rarity` are saved (see to_save /
## from_save): everything else is looked up again from the definition when the item is loaded.
## (The behaviour affixes and the three uniques are gone; Dungeon Siege II's item levels, rarities and numeric affixes replace them.)

enum Slot { WEAPON, ARMOR, TRINKET }
enum Rarity { COMMON, RARE, UNIQUE }

const SLOT_NAMES: Array[String] = ["Weapon", "Armor", "Trinket"]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Unique"]
const RARITY_COLORS: Array[Color] = [Color(0.82, 0.82, 0.82), Color(0.45, 0.72, 1.0), Color(1.0, 0.62, 0.18)]

static func starting_gear() -> Array[Dictionary]:
	return [make(Slot.WEAPON, Rarity.COMMON, 1, "Longsword"), make(Slot.ARMOR, Rarity.COMMON, 1, "Leather Jerkin")]

## Builds one item. `tier` scales the fixed numbers slowly with progress (no random variance).
static func make(slot: int, rarity: int, tier: int, base_name: String = "") -> Dictionary:
	var bases: Array[ItemDef] = ItemDb.of_slot(slot)
	var def: ItemDef = bases[randi() % bases.size()]
	if base_name != "":
		var named: ItemDef = ItemDb.by_name(base_name)
		if named != null and named.slot == slot:
			def = named
	return build(def, tier, rarity)

## An item instance from its definition. Everything but def, tier and rarity is derived.
static func build(def: ItemDef, tier: int, rarity: int) -> Dictionary:
	return {"def": def.id, "tier": tier, "slot": def.slot, "rarity": rarity, "name": def.display_name, "base": def.display_name,
		"stats": def.stats_at(tier)}

## What is written to a save: just enough to build the item again.
static func to_save(item: Dictionary) -> Dictionary:
	return {"def": item["def"], "tier": int(item["tier"]), "rarity": int(item["rarity"])}

## Builds an item from a saved one. Takes the current form and the form from before definitions (a whole item dictionary with a base
## name and its stats), so old saves load. Returns {} if the base no longer exists. An old affix or unique name is ignored (a unique comes
## back as a plain rare of its base).
static func from_save(saved: Dictionary) -> Dictionary:
	var def: ItemDef = ItemDb.get_def(String(saved.get("def", "")))
	var tier: int = int(saved.get("tier", 0))
	if def == null:   # before definitions: found by the base name, the tier worked out from the stats
		def = ItemDb.by_name(String(saved.get("base", "")))
		if def != null and tier <= 0:
			tier = def.tier_of(saved.get("stats", {}))
	if def == null:
		return {}
	var rarity: int = mini(int(saved.get("rarity", Rarity.COMMON)), Rarity.RARE)
	return build(def, maxi(tier, 1), rarity)

## The item tier a source of this threat drops (see WorldThreat). Item tier and threat are DIFFERENT SCALES and their numbers are not meant
## to match: this is a loot-progression mapping, provisional, and it deliberately keeps the early road's loot as it was before the world
## had a threat (the first stretch, 1.25, is tier 2). Today it is one tier per whole point of threat on top of tier 1, coarse on purpose
## (0.1 of threat is nothing). Never assume tier == monster level or tier == threat; ask this. It and `tier_for_wave` are the only
## places a tier is worked out; the hero's level plays no part.
static func tier_for_source(source_threat: float) -> int:
	return 1 + maxi(int(floor(source_threat)), 0)

## The wave arena's own tier (a development mode: its waves are not the connected world's progression, see RunDirector).
static func tier_for_wave(wave: int) -> int:
	return 1 + wave / 3

## One random item of the given numerical `tier` (1 and up), a weapon or an armour; `rare_chance` is the odds of a rare (otherwise common).
## The tier says how strong the numbers are; the chance says how special the item is: separate things.
static func roll_one(tier: int, rare_chance: float) -> Dictionary:
	var slot: int = randi() % 2   # (trinkets had nothing but an affix: none drop until DS2 jewellery replaces them)
	return make(slot, Rarity.RARE if randf() < rare_chance else Rarity.COMMON, maxi(tier, 1))

## What a dead monster drops, as an item of `tier` (from its source: `tier_for_source`). `luck` 0 is an ordinary monster; 1 is a Brute
## (a guaranteed rare): luck changes the rarity, never the tier.
static func roll_drop(tier: int, luck: float) -> Dictionary:
	return roll_one(tier, 1.0 if luck >= 1.0 else 0.55)

## Three different items (the trader's stock). Brutes guarantee rares.
static func roll_choices(tier: int, brute_killed: bool) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var attempts: int = 0
	while choices.size() < 3 and attempts < 40:
		attempts += 1
		var item: Dictionary = roll_drop(tier, 1.0 if brute_killed else 0.0)
		var duplicate: bool = false
		for existing in choices:
			if existing["name"] == item["name"] and existing["rarity"] == item["rarity"]:
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

## Text lines for a tooltip/card.
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
	return out
