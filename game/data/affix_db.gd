class_name AffixDb
extends RefCounted
## Loads every AffixDef from res://data/affixes/ once (tools/write_affix_defs.py).

const DIR := "res://data/affixes"

## How each stat reads on an item card.
const STAT_NAMES := {
	"mana_steal": "Mana stolen per hit", "mana_per_hit": "Mana per hit",
	"str": "Strength", "dex": "Dexterity", "int": "Intelligence", "life": "Life", "mana": "Mana",
	"melee_max": "Maximum melee damage", "melee_min": "Minimum melee damage", "melee_pct": "Melee damage",
	"ranged_max": "Maximum ranged damage", "ranged_min": "Minimum ranged damage", "ranged_pct": "Ranged damage", "spell_pct": "Combat magic damage",
	"fire_added": "Fire damage", "fire_added_max": "Maximum fire damage", "life_steal": "Life stolen per hit", "life_per_hit": "Life per hit", "armor": "Armor", "armor_pct": "Armor",
	"ice_added": "Ice damage", "ice_added_max": "Maximum ice damage", "lightning_added": "Lightning damage", "lightning_added_max": "Maximum lightning damage",
	"death_added": "Death damage", "death_added_max": "Maximum death damage",
	"ice_resist": "Ice resistance", "lightning_resist": "Lightning resistance", "death_resist": "Death resistance",
	"fire_resist": "Fire resistance", "reflect": "Melee damage reflected", "life_regen": "Life recovery", "mana_regen": "Mana recovery",
	"physical_resist": "Melee and ranged resistance", "melee_resist": "Melee resistance", "ranged_resist": "Ranged resistance", "magical_resist": "Magic damage resistance",
	"block": "Chance to block melee", "block_ranged": "Chance to block ranged",
	"power_damage": "Power damage", "dodge": "Chance to dodge melee and ranged", "dodge_melee": "Chance to dodge melee", "dodge_ranged": "Chance to dodge ranged", "recharge": "Power recharge", "magic_find": "Magic find", "gold_find": "Gold found",
}

## The stats that are percentages.
const PERCENT_STATS: Array[String] = ["melee_pct", "ranged_pct", "spell_pct", "life_steal", "mana_steal", "armor_pct", "fire_resist", "ice_resist", "lightning_resist", "death_resist", "reflect", "life_regen", "mana_regen",
	"block", "block_ranged", "dodge", "dodge_melee", "dodge_ranged", "power_damage", "recharge", "magic_find", "gold_find",
	"physical_resist", "melee_resist", "ranged_resist", "magical_resist"]

static func is_percent(stat: String) -> bool:
	return PERCENT_STATS.has(stat)

## "+12 Strength", "+18% Melee damage".
static func describe_stat(stat: String, value: float) -> String:
	return "+%d%s %s" % [int(round(value)), "%" if is_percent(stat) else "", String(STAT_NAMES.get(stat, stat))]

static var _defs: Dictionary = {}   # id -> AffixDef

static func all() -> Dictionary:
	if _defs.is_empty():
		var files: PackedStringArray = DirAccess.get_files_at(DIR)
		files.sort()
		for file in files:
			var name: String = file.trim_suffix(".remap")
			if name.ends_with(".tres"):
				var def: AffixDef = load("%s/%s" % [DIR, name]) as AffixDef
				if def != null and def.id != "":
					_defs[def.id] = def
	return _defs

static func get_def(id: String) -> AffixDef:
	return all().get(id) as AffixDef

## Every affix that may roll on this item kind with a modifier level inside [low, high], optionally only prefixes or suffixes.
static func eligible(kind: String, low: int, high: int, position: String = "") -> Array[AffixDef]:
	var out: Array[AffixDef] = []
	for def in all().values():
		var a := def as AffixDef
		if a.slots.has(kind) and a.level >= low and a.level <= high and (position == "" or a.position == position):
			out.append(a)
	return out
