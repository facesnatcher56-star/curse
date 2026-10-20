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

## The comparison key of the one "cannot wear it yet" warning (not a stat row, so it sits on no line of the card).
const WARNING_KEY := "__warning"

## The comparison key of a modifier's row. Modifiers are prefixed so one named like a base stat (affixes also use "armor") cannot share its row.
static func mod_key(stat: String) -> String:
	return "mod:" + stat

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
## pcontent.skrit calc_modifier_count: 40% plain, 40% one modifier, 20% two at zero MF.
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
	return [make(Slot.WEAPON, Rarity.NORMAL, 2, "Longsword"), make(Slot.ARMOR, Rarity.NORMAL, 2, "Leather Jerkin"), build(ItemDb.get_def("buckler"), 2, Rarity.NORMAL)]

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
static func build(def: ItemDef, level: int, rarity: int, mods: Array = [], unique_id: String = "", saved_values: Dictionary = {}) -> Dictionary:
	if rarity == Rarity.NORMAL and not mods.is_empty():
		rarity = Rarity.MAGIC   # jewellery (see roll_mods)
	var item: Dictionary = {"def": def.id, "level": maxi(level, 1), "slot": def.slot, "rarity": rarity, "mods": mods.duplicate(),
		"unique": unique_id, "base": def.display_name, "stats": def.stats_at(level)}
	var values: Dictionary = {}
	for id in mods:
		var affix: AffixDef = AffixDb.get_def(String(id))
		if affix != null and affix.value_ceiling > affix.value:
			values[id] = clampf(float(saved_values[id]), affix.value, affix.value_ceiling) if saved_values.has(id) else MapDrops.roll_value(affix, rarity)
	item["mod_values"] = values
	item["name"] = _name(def, item)
	return item

## A hand-authored item (a unique or a set piece).
static func unique(u: UniqueDef) -> Dictionary:
	var item: Dictionary = build(ItemDb.get_def(u.base), u.level, Rarity.SET if u.set_id != "" else Rarity.UNIQUE, [], u.id)
	if u.requirements != "":
		item["requirements"] = u.requirements   # rebuilt the same way on load, so a save needs no copy of it
	return item

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
	var window: Vector2i = MapDrops.mod_window(rarity, MAGIC_MOD_WINDOW if rarity == Rarity.MAGIC else RARE_MOD_WINDOW)   # map mode: the top of it
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
		var item_class := _affix_class(def)
		var strength_cap := strength_tier_cap(def)
		var pick: AffixDef = _pick_affix(KINDS[def.slot], level + window.x, level + window.y, position, families, item_class, strength_cap)
		if pick == null:
			pick = _pick_affix(KINDS[def.slot], 0, level + window.y, position, families, item_class, strength_cap)
		if pick == null and position != "":
			pick = _pick_affix(KINDS[def.slot], 0, level + window.y, "", families, item_class, strength_cap)
		if pick != null:
			out.append(pick.id)
			families.append(pick.family)
	return out

## DS2 modifier skill_types follow the weapon discipline, not the presentation model or current wielder.
static func _affix_class(def: ItemDef) -> String:
	if def.slot == Slot.WEAPON:
		return "ranger" if bool(def.profile.get("ranged", false)) else "fighter"
	return def.armor_class

## Highest strength tier (the tier table in AffixDef.tier) a roll may take on this base; 0 means it never rolls Strength, and 99 means
## any tier. DS2's melee and two-handed blows add STR, so those benefit. Owner decision: all ranger gear (bows, crossbows, thrown
## weapons and ranger armour) and mage gear (staffs, robes and similar) never roll Strength. DS2's crossbow bases require only
## ranged and biting_arrow, not Strength. Rings, amulets and fighter gear are unchanged.
static func strength_tier_cap(def: ItemDef) -> int:
	if def.item_type == "staff" or def.armor_class == "mage" or def.armor_class == "ranger":
		return 0
	if def.slot == Slot.WEAPON and bool(def.profile.get("ranged", false)):
		return 0
	return 99

static func _pick_affix(kind: String, low: int, high: int, position: String, taken: Array[String], item_class: String = "", strength_cap: int = 99) -> AffixDef:
	var pool: Array[AffixDef] = []
	for a in AffixDb.eligible(kind, low, high, position):
		if a.stat == "str" and (strength_cap <= 0 or a.tier > strength_cap):
			continue
		if item_class != "" and not a.classes.is_empty() and not a.classes.has(item_class) and not (item_class == "mage" and (a.classes.has("cmage") or a.classes.has("nmage"))):
			continue
		if not taken.has(a.family):
			pool.append(a)
	return pool[randi() % pool.size()] if not pool.is_empty() else null

## Everything an item's modifiers add: stat -> value (its affixes, or a unique's fixed modifiers).
static func mods_of(item: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in item.get("mods", []):
		var a: AffixDef = AffixDb.get_def(String(id))
		if a != null:
			if a.stat == "":
				continue
			out[a.stat] = float(out.get(a.stat, 0.0)) + float((item.get("mod_values", {}) as Dictionary).get(id, a.value))
			if a.stat.ends_with("_added"):   # an element's damage range: the maximum travels as "<stat>_max"
				out[a.stat + "_max"] = float(out.get(a.stat + "_max", 0.0)) + maxf(a.max_value, a.value)
	var u: UniqueDef = UniqueDb.get_unique(String(item.get("unique", "")))
	if u != null:
		for stat in u.mods:
			out[stat] = float(out.get(stat, 0.0)) + float(u.mods[stat])
	return out

## Passive alterations supplied by this item instance's inline payload, affixes, and unique definition. Set-tier payloads are aggregated by
## TownState from SetDef so that each active tier is counted once for the worn set.
static func passive_effects_of(item: Dictionary) -> Array:
	var out: Array = []
	for effect in item.get("effects", []):
		if effect is Dictionary:
			out.append(effect)
	for id in item.get("mods", []):
		var affix: AffixDef = AffixDb.get_def(String(id))
		if affix != null:
			out.append_array(affix.passive_effects)
	var unique: UniqueDef = UniqueDb.get_unique(String(item.get("unique", "")))
	if unique != null:
		out.append_array(unique.passive_effects)
	return out

# --- Requirements (DS2: class skill >= item level - 2) ---------------------------------------------------------------------------------

## Which class skill an armour class's pieces ask for (DS2's `equip_requirements`).
const ARMOR_CLASS_SKILL := {"fighter": "melee", "ranger": "ranged", "mage": "combat"}

## Legacy compatibility summary for the current small live item set. Full decisions use requirement_expression/evaluate_requirement below.
static func requirement(item: Dictionary) -> Dictionary:
	var def: ItemDef = ItemDb.get_def(String(item["def"]))
	var skill: String = "melee"
	if def != null and def.is_jewelry():
		skill = "uber"
	elif def != null and def.is_armor():
		skill = String(ARMOR_CLASS_SKILL.get(def.armor_class, "melee"))
	elif def != null and def.item_type == "bow":
		skill = "ranged"
	var stance: String = ""
	if def != null and def.item_type == "shield":
		stance = "barricade"
	elif def != null and bool(def.profile.get("two_handed", false)) and not bool(def.profile.get("ranged", false)):
		stance = "overbear"
	return {"class": skill, "level": maxi(int(item["level"]) - 2, 0), "passive": stance}

## Exact DS2 source text is used when present. Legacy live bases use the already documented class/item-level mapping,
## expressed through the same parser and with their DS2 stance passive requirement.
static func requirement_expression(item: Dictionary) -> String:
	if not item.has("def") or ItemDb.get_def(String(item.get("def", ""))) == null:
		return "unknown_item_definition:0"
	if item.has("requirements"):
		return String(item["requirements"])
	var def: ItemDef = ItemDb.get_def(String(item["def"]))
	if def.requirements_from_source:
		return def.requirements
	var legacy: Dictionary = requirement(item)
	var source := "%s:#item_level - 2.0" % String(legacy["class"])
	if String(legacy["passive"]) == "barricade":
		source += ",aegis:1"
	elif String(legacy["passive"]) != "":
		source += ",%s:1" % String(legacy["passive"])
	return source

## `context` contains class levels, effective STR/DEX/INT and actual learned passive ranks.
static func evaluate_requirement(source: String, item_level: float, context: Dictionary) -> Dictionary:
	return EquipmentRequirement.evaluate(source, item_level, context)

## Whether `levels` and acquired `ranks` satisfy the source-backed or legacy requirement.
static func meets_requirement(item: Dictionary, levels: Dictionary, ranks: Dictionary = {}, attributes: Dictionary = {}) -> bool:
	var context := {"levels": levels, "passive_ranks": ranks, "attributes": attributes}
	return bool(evaluate_requirement(requirement_expression(item), float(item.get("level", 0)), context).get("satisfied", false))

## Whether the hero (TownState's level, class XP and passives) may wear `item`.
static func hero_can_wear(item: Dictionary, member_id: String = "hero") -> bool:
	var member := PartyManager.current().member(member_id)
	return bool(evaluate_requirement(requirement_expression(item), float(item.get("level", 0)), _member_requirement_context(member)).get("satisfied", false))

## The requirement as the item card says it: only what the hero lacks when he cannot wear it, else the whole requirement (see EquipmentRequirement.describe_terms).
static func requirement_card_text(item: Dictionary, member_id: String = "hero") -> String:
	return EquipmentRequirement.describe_terms(requirement_expression(item), float(item.get("level", 0)), _member_requirement_context(PartyManager.current().member(member_id)),
		not hero_can_wear(item, member_id))

static func requirement_text(item: Dictionary, member_id: String = "hero") -> String:
	return EquipmentRequirement.describe(requirement_expression(item), float(item.get("level", 0)), _member_requirement_context(PartyManager.current().member(member_id)))

static func _member_requirement_context(member: CharacterState) -> Dictionary:
	var levels: Dictionary = HeroAttributes.levels_from_xp(member.class_xp)
	levels["uber"] = member.level
	var attributes: Dictionary = _member_effective_attributes(member)
	return {"levels": levels, "attributes": attributes, "passive_ranks": TownState.effective_passive_ranks(member.id)}

static func _member_effective_attributes(member: CharacterState) -> Dictionary:
	var body: Variant = PartyManager.current().bodies.get(member.id)
	var attr: Vector3
	if body is Player and is_instance_valid(body) and body.stats != null:
		attr = body.stats.attributes
	else:
		attr = HeroAttributes.attributes(HeroAttributes.levels_from_xp(member.class_xp))
		var gear := _equipment_attribute_totals(member.equipment)
		attr += Vector3(float(gear.get("str", 0.0)), float(gear.get("dex", 0.0)), float(gear.get("int", 0.0)))
	return {"strength": attr.x, "dexterity": attr.y, "intelligence": attr.z}

static func _equipment_attribute_totals(equipment: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	var set_pieces: Dictionary = {}
	for place in equipment:
		var item: Dictionary = equipment[place]
		var item_mods: Dictionary = mods_of(item)
		for stat in item_mods:
			totals[stat] = float(totals.get(stat, 0.0)) + float(item_mods[stat])
		var unique: UniqueDef = UniqueDb.get_unique(String(item.get("unique", "")))
		if unique != null and unique.set_id != "":
			set_pieces[unique.set_id] = int(set_pieces.get(unique.set_id, 0)) + 1
	for set_id in set_pieces:
		var set_def: SetDef = UniqueDb.get_set(String(set_id))
		if set_def != null:
			var bonus: Dictionary = set_def.bonus_for(int(set_pieces[set_id]))
			for stat in bonus:
				totals[stat] = float(totals.get(stat, 0.0)) + float(bonus[stat])
	return totals

# --- Saving ---------------------------------------------------------------------------------------------------------------------------

## What is written to a save: just enough to build the item again.
static func to_save(item: Dictionary) -> Dictionary:
	return {"def": item["def"], "level": int(item["level"]), "rarity": int(item["rarity"]), "mods": (item.get("mods", []) as Array).duplicate(),
		"unique": String(item.get("unique", "")), "mod_values": (item.get("mod_values", {}) as Dictionary).duplicate()}

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
	var values: Dictionary = saved.get("mod_values", {})
	# Older items had fixed values: keep those, rather than rerolling on each load.
	for id in mods:
		if not values.has(id):
			values[id] = AffixDb.get_def(String(id)).value
	return build(def, int(saved["level"]), rarity, mods, "", values)

# --- Loot (DS2 section 11) --------------------------------------------------------------------------------------------------------------

## What a dead monster of `tier` (MonsterScaling.TIERS) and `level` drops, or {} for nothing (most kills drop nothing). `magic_find` is the
## supplied percent: it multiplies rare, unique and set weights (DS2: `x (1 + MF/100)`, so "nothing" is diluted, not removed).
## `chance_mult` scales every item chance (a world event's drop multiplier).
static func rarity_weights(table: Dictionary, magic_find: float, chance_mult: float = 1.0) -> Dictionary:
	var weights: Dictionary = {}
	for kind in table:
		weights[kind] = float(table[kind]) * chance_mult * (1.0 + maxf(magic_find, 0.0) / 100.0 if kind in ["rare", "unique", "set"] else 1.0)
	return weights

## Installed pcontent.skrit calc_modifier_count, ordered thresholds (not normalized weights).
static func ordinary_mod_count(roll: float, magic_find: float) -> int:
	var multiplier := 1.0 + maxf(magic_find, 0.0) / 100.0
	if roll <= 0.4 * multiplier: return 1
	if roll <= 0.6 * multiplier: return 2
	return 0

## Existing Curse container distribution is explicitly outside Task 2's economy changes.
static func container_item_kind(roll: float) -> String:
	return "normal" if roll < 0.5 else ("magic1" if roll < 0.8 else "magic2")

static func roll_drop(level: int, tier: String, magic_find: float = 0.0, chance_mult: float = 1.0) -> Dictionary:
	if tier == "miniboss":
		return roll_reward(level, MINIBOSS, magic_find)
	var table: Dictionary = DROPS.get(tier, DROPS["weak"] if tier == "trivial" else DROPS["normal"])
	var nothing: float = 1.0 - float(table["item"]) - float(table["rare"]) - float(table["unique"]) - float(table["set"])
	var weights := rarity_weights({"item": table.item, "rare": table.rare, "unique": table.unique, "set": table.set}, magic_find, chance_mult)
	var total: float = nothing
	for kind in weights:
		total += float(weights[kind])
	var roll: float = randf() * total
	for kind in weights:
		roll -= float(weights[kind])
		if roll < 0.0:
			return item_of_kind(kind, level, table["window"], Vector2i.ZERO, magic_find)
	return {}

## A guaranteed piece by a weighted table of kinds (magic1, magic2, rare, unique, set): a miniboss, a quest reward, a named monster.
static func roll_reward(level: int, table: Dictionary = REWARD, magic_find: float = 0.0) -> Dictionary:
	var weights := rarity_weights(table, magic_find)
	var total: float = 0.0
	for kind in table:
		total += float(weights[kind])
	var roll: float = randf() * total
	for kind in weights:
		roll -= float(weights[kind])
		if roll < 0.0:
			return item_of_kind(kind, level, DROPS["strong"]["window"], Vector2i.ZERO, magic_find)
	return item_of_kind("rare", level, RARE_WINDOW)

## One item of a drop kind: "item" (DS2's "#"), "magic1", "magic2", "normal", "rare", "unique" or "set". A unique or set
## piece comes from its own wide window; when none is authored inside it, a rare drops instead.
static func item_of_kind(kind: String, level: int, window: Vector2i, rarity_window: Vector2i = Vector2i.ZERO, magic_find: float = 0.0) -> Dictionary:
	if kind == "item":
		var count := ordinary_mod_count(randf(), magic_find)
		kind = ["normal", "magic1", "magic2"][count]
	if kind == "unique" or kind == "set":
		var w: Vector2i = UNIQUE_WINDOW if kind == "unique" else SET_WINDOW
		if rarity_window != Vector2i.ZERO: w = rarity_window
		var authored: Array[UniqueDef] = UniqueDb.within(level + w.x, level + w.y, kind == "set")
		if not authored.is_empty():
			return unique(authored[randi() % authored.size()])
		kind = "rare"
		rarity_window = RARE_WINDOW # Catalogue fallback must not reuse a unique/set's much wider window.
	if kind == "rare":
		window = rarity_window if rarity_window != Vector2i.ZERO else RARE_WINDOW
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
		for lvl in (MapModeTraits.drop_levels(d) if MapMode.active else d.levels):   # map mode also offers Battle Axe and Buckler from level 3
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
## The single "cannot wear it yet" warning for an item, shown once on any card (empty when the hero may wear it).
static func wear_warning(item: Dictionary, member_id: String = "hero") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not hero_can_wear(item, member_id):
		out.append({"text": "You cannot wear this yet", "sign": -1, "key": WARNING_KEY, "delta": ""})
	return out

## How `item` compares with what is worn in its place. Each entry: {text, sign, key, delta}: `key` is the stat row it belongs beside (see
## rows()), `delta` is the signed change alone, e.g. "(-1)", and `text` is the whole thing, e.g. "Armor 8 (-1)". sign is +1 better,
## -1 worse, 0 neutral. The unmet-requirement warning comes first (key WARNING_KEY); an empty slot is one line of its own.
const VS_KEY := "__vs"
const UP := "▲"
const DOWN := "▼"

static func compare(item: Dictionary, current: Variant, member_id: String = "hero") -> Array[Dictionary]:
	var out: Array[Dictionary] = wear_warning(item, member_id)
	if current == null:
		out.append({"text": "Nothing worn in this slot", "sign": 1, "key": VS_KEY, "delta": ""})
		return out
	var worn: Dictionary = current
	var a: Dictionary = item["stats"]
	var b: Dictionary = worn["stats"]
	var diffs: Array[Dictionary] = []
	if a.has("max") and b.has("max"):
		# The same terms as the stat line: its average damage (shown there as "avg"), and its speed word.
		_diff(diffs, "damage", "Damage", (float(a["min"]) + float(a["max"])) * 0.5, (float(b["min"]) + float(b["max"])) * 0.5, "%.1f", "%.1f")
		if not is_equal_approx(float(a["speed"]), float(b["speed"])):
			var faster: bool = float(a["speed"]) > float(b["speed"])
			diffs.append({"text": "Speed: %s %s" % [speed_word(float(a["speed"])), (UP + " faster") if faster else (DOWN + " slower")], "stat_text": "Speed: %s" % speed_word(float(a["speed"])),
				"sign": 1 if faster else -1, "key": "speed", "delta": (UP + " faster") if faster else (DOWN + " slower")})
	if a.has("armor") or b.has("armor"):
		_diff(diffs, "armor", "Armor", float(a.get("armor", 0.0)), float(b.get("armor", 0.0)), "%d", "%d")
	var mine: Dictionary = mods_of(item)
	var theirs: Dictionary = mods_of(worn)
	var stats: Array = mine.keys()
	for stat in theirs:
		if not stats.has(stat):
			stats.append(stat)
	for stat in stats:   # an element's maximum ("<stat>_added_max", named in STAT_NAMES) gets its own row when it differs, even if the minimum does not
		var fmt: String = "%d%%" if AffixDb.is_percent(String(stat)) else "%d"
		_diff(diffs, mod_key(String(stat)), String(AffixDb.STAT_NAMES.get(stat, stat)), float(mine.get(stat, 0.0)), float(theirs.get(stat, 0.0)), fmt, fmt)
	out.append({"text": "vs %s (equipped)" % String(worn["name"]), "sign": 0, "key": VS_KEY, "delta": ""})
	if diffs.is_empty():
		out.append({"text": "Same as what you wear", "sign": 0, "key": "", "delta": ""})
	out.append_array(diffs)
	return out

## Records one stat's change when it differs: `value_fmt` shows the item's own number, `delta_fmt` the size of the change (higher is better).
## The change is one indicator: ▲ for better, ▼ for worse, then the amount (no second sign, no brackets).
static func _diff(out: Array[Dictionary], key: String, label: String, value: float, other: float, value_fmt: String, delta_fmt: String) -> void:
	if is_equal_approx(value, other):
		return
	var delta: float = value - other
	var delta_text: String = "%s %s" % [UP if delta > 0.0 else DOWN, delta_fmt % absf(delta)]
	out.append({"text": "%s %s %s" % [label, value_fmt % value, delta_text], "stat_text": "%s %s" % [label, value_fmt % value], "sign": 1 if delta > 0.0 else -1, "key": key, "delta": delta_text})

## The model an item lies on the ground as (from its definition; made in Blender by tools/blender/make_items.py).
static func model_path(item: Dictionary) -> String:
	return ItemDb.get_def(String(item["def"])).model_path

## Text lines for a tooltip/card: its numbers, its modifiers, its set, its level and what it needs.
## The text lines of an item's card (see rows()).
static func lines(item: Dictionary, member_id: String = "hero") -> Array[String]:
	var out: Array[String] = []
	for row in rows(item, member_id):
		out.append(String(row["text"]))
	return out

## Every line of an item's card as {text, key, section}: base stats, modifiers, the map-mode trait, the map-mode legendary effect, set bonuses,
## then what it needs, in that order (SECTIONS). A stat line's `key` is the stat it shows ("damage", "speed", "armor" or a modifier id), which
## is where its comparison with the worn piece is drawn; other lines have key "". Item level is not a line: the card's header shows it.
const SECTIONS: Array[String] = ["base", "mods", "trait", "legendary", "set", "req"]
const REQ_KEY := "__requirement"
const SPEED_WORDS: Array[String] = ["Slow", "Normal", "Fast", "Very fast"]

## The plain word for a weapon's speed multiplier (0.82 slow, 1.0 normal, 1.18 fast, 1.5 very fast).
static func speed_word(speed: float) -> String:
	if speed < 0.92:
		return SPEED_WORDS[0]
	if speed < 1.08:
		return SPEED_WORDS[1]
	if speed < 1.3:
		return SPEED_WORDS[2]
	return SPEED_WORDS[3]

static func rows(item: Dictionary, member_id: String = "hero") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stats: Dictionary = item["stats"]
	var def: ItemDef = ItemDb.get_def(String(item["def"]))
	if stats.has("max"):
		out.append({"text": "Damage %d-%d (avg %.1f)" % [int(stats["min"]), int(stats["max"]), (float(stats["min"]) + float(stats["max"])) * 0.5], "key": "damage", "section": "base"})
		out.append({"text": "Speed: %s" % speed_word(float(stats["speed"])), "key": "speed", "section": "base"})
		if bool(def.profile.get("two_handed", false)):
			out.append({"text": "Two-handed", "key": "", "section": "base"})
		var style: String = String(def.profile.get("style", ""))
		if style != "":
			out.append({"text": style, "key": "", "section": "base"})
	if stats.has("armor"):
		out.append({"text": "Armor %d" % int(stats["armor"]), "key": "armor", "section": "base"})
	var mods: Dictionary = mods_of(item)
	for stat in mods:
		if String(stat).ends_with("_added_max"):
			continue
		if String(stat).ends_with("_added") and float(mods.get(stat + "_max", 0.0)) > float(mods[stat]):
			out.append({"text": "+%d–%d %s" % [int(mods[stat]), int(mods[stat + "_max"]), String(AffixDb.STAT_NAMES.get(stat, stat))], "key": mod_key(String(stat)), "section": "mods"})
			continue
		out.append({"text": AffixDb.describe_stat(String(stat), float(mods[stat])), "key": mod_key(String(stat)), "section": "mods"})
	for effect in passive_effects_of(item):
		var line := passive_effect_line(effect)
		if line != "":
			out.append({"text": line, "key": "", "section": "mods"})
	for row in MapModeTraits.rows_for(item):   # map mode only: the base's trait line
		row["section"] = "trait"
		out.append(row)
	var legendary: String = MapModeLegendaries.tooltip_line(item)   # map mode only
	if legendary != "":
		out.append({"text": legendary, "key": "", "section": "legendary"})
	var u: UniqueDef = UniqueDb.get_unique(String(item.get("unique", "")))
	if u != null and u.set_id != "":
		var set_def: SetDef = UniqueDb.get_set(u.set_id)
		if set_def != null:
			out.append({"text": "Part of %s" % set_def.display_name, "key": "", "section": "set"})
			for count in set_def.bonuses:
				var parts: PackedStringArray = []
				for stat in set_def.bonuses[count]:
					parts.append(AffixDb.describe_stat(String(stat), float(set_def.bonuses[count][stat])))
				out.append({"text": "  %s worn: %s" % [count, ", ".join(parts)], "key": "", "section": "set"})
			for count in set_def.passive_effect_tiers:
				var parts: PackedStringArray = []
				for effect in set_def.passive_effect_tiers[count]:
					if effect is Dictionary:
						var line := passive_effect_line(effect)
						if line != "": parts.append(line)
				if not parts.is_empty():
					out.append({"text": "  %s worn: %s" % [count, ", ".join(parts)], "key": "", "section": "set"})
	var need: String = requirement_card_text(item, member_id)
	if need != "":
		out.append({"text": need, "key": REQ_KEY, "section": "req"})
	return out

## The "Item level N" shown in the card's header (it is not a row of its own).
## What the card calls the item's rarity: a map-mode power legendary is "Legendary", whatever its rarity colour.
static func rarity_label(item: Dictionary) -> String:
	return "Legendary" if MapModeLegendaries.id_of(item) != "" else String(RARITY_NAMES[int(item["rarity"])])

static func level_text(item: Dictionary) -> String:
	return "Item level %d" % int(item["level"])

static func passive_effect_line(effect: Dictionary) -> String:
	var raw_value: Variant = effect.get("value", 0)
	var amount: int = int(String(raw_value).to_float()) if raw_value is String else int(raw_value)
	var description := String(effect.get("description", ""))
	if description != "":
		return description.replace("<value>", str(amount))
	var alteration := String(effect.get("alteration", "")).strip_edges().to_lower()
	if alteration == "alter_passive_rank":
		var passive_def: PassiveDef = PassiveDb.get_def(String(effect.get("passive", "")).strip_edges().to_lower())
		return "+%d to %s" % [amount, passive_def.display_name] if passive_def != null else ""
	if alteration == "alter_skill_suite":
		var suite := String(effect.get("suite", "")).strip_edges().to_lower()
		return "+%d to %s" % [amount, _supported_passive_names(TownState.GEAR_SUITE_PASSIVES.get(suite, []))] \
			if not TownState.GEAR_SUITE_PASSIVES.get(suite, []).is_empty() else ""
	var discipline := String(TownState.GEAR_DISCIPLINE_ALTERATIONS.get(alteration, ""))
	if discipline == "": return ""
	var discipline_name := String(HeroAttributes.CLASS_NAMES.get(discipline, ""))
	return "+%d to %s Skills" % [amount, discipline_name] if discipline_name != "" else ""

static func _supported_passive_names(ids: Array) -> String:
	var names: Array[String] = []
	for id in ids:
		var def: PassiveDef = PassiveDb.get_def(String(id))
		if def != null:
			names.append(def.display_name)
	if names.size() < 2:
		return ", ".join(names)
	var final_name: String = names.pop_back()
	if names.size() == 1:
		return "%s and %s" % [names[0], final_name]
	return "%s, and %s" % [", ".join(names), final_name]
