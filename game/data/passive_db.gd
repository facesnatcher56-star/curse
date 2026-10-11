class_name PassiveDb
extends RefCounted
## Loads every PassiveDef from res://data/passives/ once (tools/write_passive_defs.py).

const DIR := "res://data/passives"

static var _defs: Dictionary = {}   # id -> PassiveDef

static func all() -> Dictionary:
	if _defs.is_empty():
		var files: PackedStringArray = DirAccess.get_files_at(DIR)
		files.sort()
		for file in files:
			var name: String = file.trim_suffix(".remap")
			if name.ends_with(".tres"):
				var def: PassiveDef = load("%s/%s" % [DIR, name]) as PassiveDef
				if def != null and def.id != "":
					_defs[def.id] = def
	return _defs

static func get_def(id: String) -> PassiveDef:
	return all().get(id) as PassiveDef

## A tree's passives in order.
static func of_tree(tree: String) -> Array[PassiveDef]:
	var out: Array[PassiveDef] = []
	for def in all().values():
		if (def as PassiveDef).tree == tree:
			out.append(def)
	out.sort_custom(func(a: PassiveDef, b: PassiveDef) -> bool: return a.order < b.order)
	return out
