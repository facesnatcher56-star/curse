class_name PowerDb
extends RefCounted
## Loads every PowerDef from res://data/powers/ once (tools/write_power_defs.py), and says what rank of a power the hero has.

const DIR := "res://data/powers"

static var _defs: Dictionary = {}   # id -> PowerDef

static func all() -> Dictionary:
	if _defs.is_empty():
		var files: PackedStringArray = DirAccess.get_files_at(DIR)
		files.sort()
		for file in files:
			var name: String = file.trim_suffix(".remap")
			if name.ends_with(".tres"):
				var def: PowerDef = load("%s/%s" % [DIR, name]) as PowerDef
				if def != null and def.id != "":
					_defs[def.id] = def
	return _defs

static func get_def(id: String) -> PowerDef:
	return all().get(id) as PowerDef

## A tree's powers, in the order the generator lists them.
static func of_tree(tree: String) -> Array[PowerDef]:
	var out: Array[PowerDef] = []
	for def in all().values():
		if (def as PowerDef).tree == tree:
			out.append(def)
	out.sort_custom(func(a: PowerDef, b: PowerDef) -> bool: return a.order < b.order)
	return out

## The hero's rank in a power (0: not open yet), from his passive ranks.
static func hero_rank(id: String) -> int:
	var def: PowerDef = get_def(id)
	return def.rank_for(TownState.passive_ranks) if def != null else 0

## A power's value at the hero's rank and class levels.
static func hero_value(id: String, key: String) -> float:
	var def: PowerDef = get_def(id)
	if def == null:
		return 0.0
	return def.value(key, hero_rank(id), HeroAttributes.levels_from_xp(TownState.class_xp))
