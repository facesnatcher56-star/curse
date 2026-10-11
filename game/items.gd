class_name Items
extends RefCounted
## Items, Dungeon Siege II's way (docs/ds2-combat-and-loot.md 10 and 11). The base items are data (ItemDef in res://data/items/, through
## ItemDb); an item in the world is a Dictionary built from one: {def, level, slot, rarity, mods, unique, name, base, stats}. Only `def`,
## `level`, `rarity`, `mods` (AffixDef ids) and `unique` (a UniqueDef id) are saved (see to_save / from_save): everything else is looked up
## again from the definitions when the item is loaded.
##
## Rarity: Normal (the base alone), Magic (1 or 2 modifiers), Rare (3 or 4), Unique and Set (hand-authored, UniqueDb). Drops follow DS2's
## tables by monster tier, each with its item-level window around the monster's level; magic find multiplies the rare, unique and set odds.

## Where an item is worn. RING2 is the second ring finger: no base has it as its slot, a ring goes on either. ARMOR is the body armour.
enum Slot { WEAPON, ARMOR, RING, SHIELD, HELM, GLOVES, BOOTS, AMULET, RING2 }
enum Rarity { NORMAL, MAGIC, RARE, UNIQUE, SET }

const SLOT_NAMES: Array[String] = ["Weapon", "Body Armor", "Ring", "Shield", "Helm", "Gloves", "Boots", "Amulet", "Ring"]
## The item kind an AffixDef names in its `slots`, per Slot.
const KINDS: Array[String] = ["weapon", "body", "ring", "shield", "helm", "gloves", "boots", "amulet", "ring"]
const RARITY_NAMES: Array[String] = ["Normal", "Magic", "Rare", "Unique", "Set"]
const RARITY_COLORS: Array[Color] = [Color(0.82, 0.82, 0.82), Color(0.42, 0.6, 0.98), Color(0.94, 0.82, 0.34), Color(1.0, 0.58, 0.18),
	Color(0.46, 0.8, 0.38)]

## The modifier-level window around an item's level, by rarity (DS2: a rare's is `-25 ... +5`). CURSE CHOICE: a magic item's, which DS2
## leaves to the engine, is `-20 ... 0`.
const MAGIC_MOD_WINDOW := Vector2i(-20, 0)
const RARE_MOD_WINDOW := Vector2i(-25, 5)
## How many modifiers a rare carries: DS2 leaves it to the engine. CURSE CHOICE: 3 or 4.
const RARE_MODS := Vector2i(3, 4)

## DS2's drop table per monster tier (`pcontent_macros.gas`): the item columns ("item" is any item, "#"), as chances per kill, and the
## item-level window around the monster's level. Gold and potions are Curse's own (gold per kill, health orbs).
const DROPS := {
	"weak": {"item": 0.05, "rare": 0.0045, "unique": 0.0015, "set": 0.0015, "window": Vector2i(-6, 0)},
	"normal": {"item": 0.08, "rare": 0.0075, "unique": 0.0025, "set": 0.0025, "window": Vector2i(-5, 1)},
	"strong": {"item": 0.15, "rare": 0.0135, "unique": 0.0045, "set": 0.0045, "window": Vector2i(-4, 2)},
}
const RARE_WINDOW := Vector2i(-4, 2)
const UNIQUE_WINDOW := Vector2i(-40, 3)
const SET_WINDOW := Vector2i(-50, 3)
## DS2's "#" item: CURSE CHOICE, as the engine decides it there: half are plain, 30% have one modifier and 20% two.
const ANY_ITEM := {"normal": 0.5, "magic1": 0.3, "magic2": 0.2}
## A miniboss always drops one piece: 30% one-modifier magic, 50% two, 12% rare, 4% unique, 4% set (DS2).
const MINIBOSS := {"magic1": 0.3, "magic2": 0.5, "rare": 0.12, "unique": 0.04, "set": 0.04}
## DS2's quest-reward and class-chest macro: 70% rare, 15% unique, 15% set.
const REWARD := {"rare": 0.7, "unique": 0.15, "set": 0.15}

## The places an item of `slot` can be worn (a ring: either hand).
static func places(slot: int) -> Array[int]:
	if slot == Slot.RING or slot == Slot.RING2:
		return [Slot.RING, Slot.RING2]
	return [slot]

static func starting_gear() -> Array[Dictionary]:
	return [make(Slot.WEAPON, Rarity.NORMAL, 2, "Longsword"), make(Slot.ARMOR, Rarity.NORMAL, 2, "Leather Jerkin")]

## Builds one item of `slot` at item level `level`: a random base of the slot (or the one named), with random modifiers for its rarity. A
## unique or set rarity takes an authored piece of that slot when there is one (otherwise the item is a rare).
static func make(slot: int, rarity: int, level: int, base_name: String = "") -> Dictionary:
	if rarity >= Rarity.UNIQUE:
		var authored: Array[UniqueDef] = []
		for u in UniqueDb.within(-1000, 1000, rarity == Rarity.SET):
			if ItemDb.get_def(u.base) != null and ItemDb.get_def(u.base).slot == slot:
				authored.append(u)
		if not authored.is_empty():
			return unique(authored[randi() % authored.size()])
		rarity = Rarity.RARE
	var bases: Array[ItemDef] = ItemDb.of_slot(slot)
	var def: ItemDef = bases[randi() % bases.size()]
	if base_name != "":
		var named: ItemDef = ItemDb.by_name(base_name)
		if named != null and named.slot == slot:
			def = named
	return build(def, level, rarity, roll_mods(def, level, rarity))

## An item instance from its definition. Everything but def, level, rarity, mods and unique is derived.
static func build(def: ItemDef, level: int, rarity: int, mods: Array = [], unique_id: String = "") -> Dictionary:
	if rarity == Rarity.NORMAL and not mods.is_empty():
		rarity = Rarity.MAGIC   # jewellery (see roll_mods)
	var item: Dictionary = {"def": def.id, "level": maxi(level, 1), "slot": def.slot, "rarity": rarity, "mods": mods.duplicate(),
		"unique": unique_id, "base": def.display_name, "stats": def.stats_at(level)}
	item["name"] = _name(def, item)
	return item

## A hand-authored item (a unique or a set piece).
static func unique(u: UniqueDef) -> Dictionary:
	return build(ItemDb.get_def(u.base), u.level, Rarity.SET if u.set_id != "" else Rarity.UNIQUE, [], u.id)

## "Cruel Longsword of the Wolf": a magic or rare item takes its first prefix and suffix; a unique has its own name.
static func _name(def: ItemDef, item: Dictionary) -> String:
	var u: UniqueDef = UniqueDb.get_unique(String(item.get("unique", "")))
	if u != null:
		return u.display_name
	var prefix: String = ""
	var suffix: String = ""
	for id in item["mods"]:
		var a: AffixDef = AffixDb.get_def(String(id))
		if a == null:
			continue
		if a.position == "prefix" and prefix == "":
			prefix = a.title + " "
		elif a.position == "suffix" and suffix == "":
			suffix = " " + a.title
	return prefix + def.display_name + suffix

## Random modifiers for an item of this rarity: a magic item 1 or 2 (one prefix and one suffix when two), a rare 3 or 4. At most one of a
## family; the modifier level within the rarity's window around the item level (lower tiers when nothing fits). Jewellery is never plain.
static func roll_mods(def: ItemDef, level: int, rarity: int, count: int = -1) -> Array:
	if rarity == Rarity.NORMAL and def.is_jewelry():
		rarity = Rarity.MAGIC   # CURSE CHOICE: a plain ring does nothing, so jewellery always has at least one modifier
	if rarity != Rarity.MAGIC and rarity != Rarity.RARE:
		return []
	if count < 0:
		count = randi_range(1, 2) if rarity == Rarity.MAGIC else randi_range(RARE_MODS.x, RARE_MODS.y)
	var window: Vector2i = MAGIC_MOD_WINDOW if rarity == Rarity.MAGIC else RARE_MOD_WINDOW
	var positions: Array[String] = []
	if rarity == Rarity.MAGIC and count == 2:
		positions.append_array(["prefix", "suffix"])
	elif rarity == Rarity.MAGIC:
		positions.append("prefix" if randi() % 2 == 0 else "suffix")
	else:
		for i in count:
			positions.append("")
	var out: Array = []
	var families: Array[String] = []
	for position in positions:
		var pick: AffixDef = _pick_affix(KINDS[def.slot], level + window.x, level + window.y, position, families)
		if pick == null:
			pick = _pick_affix(KINDS[def.slot], 0, level + window.y, position, families)
		if pick == null and position != "":
			pick = _pick_affix(KINDS[def.slot], 0, level + window.y, "", families)
		if pick != null:
			out.append(pick.id)
			families.append(pick.family)
	return out

static func _pick_affix(kind: String, low: int, high: int, position: String, taken: Array[String]) -> AffixDef:
	var pool: Array[AffixDef] = []
	for a in AffixDb.eligible(kind, low, high, position):
		if not taken.has(a.family):
			pool.append(a)
	return pool[randi() % pool.size()] if not pool.is_empty() else null

## Everything an item's modifiers add: stat -> value (its affixes, or a unique's fixed modifiers).
static func mods_of(item: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in item.get("mods", []):
		var a: AffixDef = AffixDb.get_def(String(id))
		if a != null:
			out[a.stat] = float(out.get(a.stat, 0.0)) + a.value
	var u: UniqueDef = UniqueDb.get_unique(String(item.get("unique", "")))
	if u != null:
		for stat in u.mods:
			out[stat] = float(out.get(stat, 0.0)) + float(u.mods[stat])
	return out

# --- Requirements (DS2: class skill >= item level - 2) ---------------------------------------------------------------------------------

## Which class skill an armour class's pieces ask for (DS2's `equip_requirements`).
const ARMOR_CLASS_SKILL := {"fighter": "melee", "ranger": "ranged", "mage": "combat"}

## What wearing `item` needs: {class, level}, DS2's `equip_requirements` (item level - 2): a weapon Melee (the hero's blades), an armour
## piece its own class's skill (fighter Melee, ranger Ranged, mage Combat Magic), jewellery the character level ("uber"). The stance
## passives DS2 also asks for (Barricade for a shield, Overbear for a two-handed weapon) come with the passive trees.
static func requirement(item: Dictionary) -> Dictionary:
	var def: ItemDef = ItemDb.get_def(String(item["def"]))
	var skill: String = "melee"
	if def != null and def.is_jewelry():
		skill = "uber"
	elif def != null and def.is_armor():
		skill = String(ARMOR_CLASS_SKILL.get(def.armor_class, "melee"))
	var stance: String = ""
	if def != null and def.item_type == "shield":
		stance = "barricade"
	elif def != null and bool(def.profile.get("two_handed", false)):
		stance = "overbear"
	return {"class": skill, "level": maxi(int(item["level"]) - 2, 0), "passive": stance}

## Whether `levels` meet the requirement: class skill levels (HeroAttributes.levels_from_xp) and "uber", the character level; `ranks`
## the passive ranks (a shield needs Barricade, a two-handed weapon Overbear).
static func meets_requirement(item: Dictionary, levels: Dictionary, ranks: Dictionary = {}) -> bool:
	var need: Dictionary = requirement(item)
	return int(levels.get(need["class"], 0)) >= int(need["level"]) and (String(need["passive"]) == "" or int(ranks.get(need["passive"], 0)) >= 1)

## Whether the hero (TownState's level, class XP and passives) may wear `item`.
static func hero_can_wear(item: Dictionary) -> bool:
	var levels: Dictionary = HeroAttributes.levels_from_xp(TownState.class_xp)
	levels["uber"] = TownState.hero_level
	return meets_requirement(item, levels, TownState.passive_ranks)

static func requirement_text(item: Dictionary) -> String:
	var need: Dictionary = requirement(item)
	var parts: PackedStringArray = []
	if int(need["level"]) > 0:
		if String(need["class"]) == "uber":
			parts.append("level %d" % int(need["level"]))
		else:
			parts.append("%s %d" % [String(HeroAttributes.CLASS_NAMES.get(need["class"], need["class"])), int(need["level"])])
	if String(need["passive"]) != "":
		parts.append(PassiveDb.get_def(String(need["passive"])).display_name)
	return ("Requires " + " and ".join(parts)) if not parts.is_empty() else ""

# --- Saving ---------------------------------------------------------------------------------------------------------------------------

## What is written to a save: just enough to build the item again.
static func to_save(item: Dictionary) -> Dictionary:
	return {"def": item["def"], "level": int(item["level"]), "rarity": int(item["rarity"]), "mods": (item.get("mods", []) as Array).duplicate(),
		"unique": String(item.get("unique", ""))}

## Builds an item from a saved one. Reads the current form and the older ones: {def, tier, rarity} from before DS2 items (its tier becomes
## its item level, as a Normal item: whatever made it rare is gone) and the whole dictionary from before definitions (found by base name).
## Returns {} if the base no longer exists. Modifiers or a unique that no longer exist are dropped.
static func from_save(saved: Dictionary) -> Dictionary:
	var def: ItemDef = ItemDb.get_def(String(saved.get("def", "")))
	if def == null:
		def = ItemDb.by_name(String(saved.get("base", "")))
	if def == null:
		return {}
	if not saved.has("level"):   # before DS2 items
		return build(def, maxi(int(saved.get("tier", 1)), 1), Rarity.NORMAL, roll_mods(def, maxi(int(saved.get("tier", 1)), 1), Rarity.NORMAL))
	var u: UniqueDef = UniqueDb.get_unique(String(saved.get("unique", "")))
	if u != null:
		return unique(u)
	var mods: Array = []
	for id in saved.get("mods", []):
		if AffixDb.get_def(String(id)) != null:
			mods.append(String(id))
	var rarity: int = clampi(int(saved.get("rarity", Rarity.NORMAL)), Rarity.NORMAL, Rarity.RARE)
	return build(def, int(saved["level"]), rarity, mods)

# --- Loot (DS2 section 11) --------------------------------------------------------------------------------------------------------------

## What a dead monster of `tier` (MonsterScaling.TIERS) and `level` drops, or {} for nothing (most kills drop nothing). `magic_find` is the
## hero's (percent): it multiplies the rare, unique and set chances (DS2: `x (1 + MF/100)`, so "nothing" is diluted, not removed).
## `chance_mult` scales every item chance (a world event's drop multiplier).
static func roll_drop(level: int, tier: String, magic_find: float = 0.0, chance_mult: float = 1.0) -> Dictionary:
	if tier == "miniboss":
		return roll_reward(level, MINIBOSS, magic_find)
	var table: Dictionary = DROPS.get(tier, DROPS["weak"] if tier == "trivial" else DROPS["normal"])
	var mf: float = 1.0 + maxf(magic_find, 0.0) / 100.0
	var nothing: float = 1.0 - float(table["item"]) - float(table["rare"]) - float(table["unique"]) - float(table["set"])
	var weights: Dictionary = {"item": float(table["item"]) * chance_mult, "rare": float(table["rare"]) * mf * chance_mult,
		"unique": float(table["unique"]) * mf * chance_mult, "set": float(table["set"]) * mf * chance_mult}
	var total: float = nothing
	for kind in weights:
		total += float(weights[kind])
	var roll: float = randf() * total
	for kind in weights:
		roll -= float(weights[kind])
		if roll < 0.0:
			return item_of_kind(kind, level, table["window"])
	return {}

## A guaranteed piece by a weighted table of kinds (magic1, magic2, rare, unique, set): a miniboss, a quest reward, a named monster.
static func roll_reward(level: int, table: Dictionary = REWARD, magic_find: float = 0.0) -> Dictionary:
	var mf: float = 1.0 + maxf(magic_find, 0.0) / 100.0
	var weights: Dictionary = {}
	var total: float = 0.0
	for kind in table:
		weights[kind] = float(table[kind]) * (mf if kind in ["rare", "unique", "set"] else 1.0)
		total += float(weights[kind])
	var roll: float = randf() * total
	for kind in weights:
		roll -= float(weights[kind])
		if roll < 0.0:
			return item_of_kind(kind, level, DROPS["strong"]["window"])
	return item_of_kind("rare", level, RARE_WINDOW)

## One item of a drop kind: "item" (DS2's "#", see ANY_ITEM), "magic1", "magic2", "normal", "rare", "unique" or "set". A unique or set
## piece comes from its own wide window; when none is authored inside it, a rare drops instead.
static func item_of_kind(kind: String, level: int, window: Vector2i) -> Dictionary:
	if kind == "item":
		var r: float = randf()
		kind = "normal" if r < ANY_ITEM["normal"] else ("magic1" if r < ANY_ITEM["normal"] + ANY_ITEM["magic1"] else "magic2")
	if kind == "unique" or kind == "set":
		var w: Vector2i = UNIQUE_WINDOW if kind == "unique" else SET_WINDOW
		var authored: Array[UniqueDef] = UniqueDb.within(level + w.x, level + w.y, kind == "set")
		if not authored.is_empty():
			return unique(authored[randi() % authored.size()])
		kind = "rare"
	if kind == "rare":
		window = RARE_WINDOW
	var picked: Dictionary = pick_base(level + window.x, level + window.y)
	var def: ItemDef = picked["def"]
	var lvl: int = int(picked["level"])
	match kind:
		"magic1":
			return build(def, lvl, Rarity.MAGIC, roll_mods(def, lvl, Rarity.MAGIC, 1))
		"magic2":
			return build(def, lvl, Rarity.MAGIC, roll_mods(def, lvl, Rarity.MAGIC, 2))
		"rare":
			return build(def, lvl, Rarity.RARE, roll_mods(def, lvl, Rarity.RARE))
	return build(def, lvl, Rarity.NORMAL, roll_mods(def, lvl, Rarity.NORMAL))

## A base and one of its item levels inside [low, high] (DS2: a drop is a base's variant whose level fits the window). The slot is picked
## first, evenly; when no variant of any base fits, each slot offers its variant nearest the window (CURSE CHOICE: with few bases there are
## gaps). `slot` -1 means any slot.
static func pick_base(low: int, high: int, slot: int = -1) -> Dictionary:
	var by_slot: Dictionary = {}   # slot -> Array of [def, level]
	for def in ItemDb.all().values():
		var d := def as ItemDef
		if slot >= 0 and d.slot != slot:
			continue
		for lvl in d.levels:
			if lvl >= low and lvl <= high:
				if not by_slot.has(d.slot):
					by_slot[d.slot] = []
				by_slot[d.slot].append([d, lvl])
	if by_slot.is_empty():
		var middle: float = (low + high) * 0.5
		for def in ItemDb.all().values():
			var d := def as ItemDef
			if slot >= 0 and d.slot != slot:
				continue
			var best: int = d.levels[0]
			for lvl in d.levels:
				if absf(lvl - middle) < absf(best - middle):
					best = lvl
			if not by_slot.has(d.slot) or absf(best - middle) < absf(int(by_slot[d.slot][0][1]) - middle):
				by_slot[d.slot] = [[d, best]]
	var slots: Array = by_slot.keys()
	var options: Array = by_slot[slots[randi() % slots.size()]]
	var chosen: Array = options[randi() % options.size()]
	return {"def": chosen[0], "level": chosen[1]}

## One item for sale around `level` (a merchant's stock): magic, rare with `rare_chance`. `slots` limits the kinds (the smith: weapons and
## armour).
static func shop_item(level: int, rare_chance: float, slots: Array = []) -> Dictionary:
	var slot: int = int(slots[randi() % slots.size()]) if not slots.is_empty() else -1
	var picked: Dictionary = pick_base(level - 4, level + 1, slot)
	var def: ItemDef = picked["def"]
	var rarity: int = Rarity.RARE if randf() < rare_chance else Rarity.MAGIC
	return build(def, int(picked["level"]), rarity, roll_mods(def, int(picked["level"]), rarity))

## Three different items (the trader's stock) around `level`.
static func roll_choices(level: int, rare_chance: float = 0.15) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var attempts: int = 0
	while choices.size() < 3 and attempts < 40:
		attempts += 1
		var item: Dictionary = shop_item(level, rare_chance)
		var duplicate: bool = false
		for existing in choices:
			if existing["name"] == item["name"]:
				duplicate = true
		if not duplicate:
			choices.append(item)
	return choices

# --- Cards ------------------------------------------------------------------------------------------------------------------------------

## How `item` compares with what is worn in its place: lines of {text, sign} (sign +1 better, -1 worse, 0 neutral) for the tooltip. An
## unmet requirement comes first, as a worse line.
static func compare(item: Dictionary, current: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not hero_can_wear(item):
		out.append({"text": "%s (you cannot wear it yet)" % requirement_text(item), "sign": -1})
	if current == null:
		out.append({"text": "Nothing worn in this slot", "sign": 1})
		return out
	var worn: Dictionary = current
	var a: Dictionary = item["stats"]
	var b: Dictionary = worn["stats"]
	if a.has("max") and b.has("max"):
		_diff(out, "Damage", (float(a["min"]) + float(a["max"])) * 0.5, (float(b["min"]) + float(b["max"])) * 0.5, true, "%.1f")
		_diff(out, "Speed", float(a["speed"]), float(b["speed"]), true, "x%.2f")
	if a.has("armor") or b.has("armor"):
		_diff(out, "Armor", float(a.get("armor", 0.0)), float(b.get("armor", 0.0)), true, "%d")
	var mine: Dictionary = mods_of(item)
	var theirs: Dictionary = mods_of(worn)
	var stats: Array = mine.keys()
	for stat in theirs:
		if not stats.has(stat):
			stats.append(stat)
	for stat in stats:
		_diff(out, String(AffixDb.STAT_NAMES.get(stat, stat)), float(mine.get(stat, 0.0)), float(theirs.get(stat, 0.0)), true,
			"%d%%" if AffixDb.is_percent(String(stat)) else "%d")
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

## Text lines for a tooltip/card: its numbers, its modifiers, its set, its level and what it needs.
static func lines(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var stats: Dictionary = item["stats"]
	var def: ItemDef = ItemDb.get_def(String(item["def"]))
	if stats.has("max"):
		out.append("Damage %d-%d    Speed x%.2f%s" % [int(stats["min"]), int(stats["max"]), stats["speed"],
			"    Two-handed" if bool(def.profile.get("two_handed", false)) else ""])
		var style: String = String(def.profile.get("style", ""))
		if style != "":
			out.append(style)
	if stats.has("armor"):
		out.append("Armor %d" % int(stats["armor"]))
	var mods: Dictionary = mods_of(item)
	for stat in mods:
		out.append(AffixDb.describe_stat(String(stat), float(mods[stat])))
	var u: UniqueDef = UniqueDb.get_unique(String(item.get("unique", "")))
	if u != null and u.set_id != "":
		var set_def: SetDef = UniqueDb.get_set(u.set_id)
		if set_def != null:
			out.append("Part of %s" % set_def.display_name)
			for count in set_def.bonuses:
				var parts: PackedStringArray = []
				for stat in set_def.bonuses[count]:
					parts.append(AffixDb.describe_stat(String(stat), float(set_def.bonuses[count][stat])))
				out.append("  %s worn: %s" % [count, ", ".join(parts)])
	var need: String = requirement_text(item)
	out.append("Item level %d%s" % [int(item["level"]), ("    " + need) if need != "" else ""])
	return out
