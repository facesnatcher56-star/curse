class_name AffixDb
extends RefCounted
## Loads every AffixDef from res://data/affixes/ once (tools/write_affix_defs.py).

const DIR := "res://data/affixes"

## How each stat reads on an item card.
const STAT_NAMES := {
	"str": "Strength", "dex": "Dexterity", "int": "Intelligence", "life": "Life", "mana": "Mana",
	"melee_max": "Maximum melee damage", "melee_min": "Minimum melee damage", "melee_pct": "Melee damage", "spell_pct": "Combat magic damage",
	"fire_added": "Fire damage", "life_steal": "Life stolen per hit", "life_per_hit": "Life per hit", "armor": "Armor", "armor_pct": "Armor",
	"fire_resist": "Fire resistance", "reflect": "Melee damage reflected", "life_regen": "Life recovery", "mana_regen": "Mana recovery",
	"block": "Chance to block", "recharge": "Power recharge", "magic_find": "Magic find", "gold_find": "Gold found",
}

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
