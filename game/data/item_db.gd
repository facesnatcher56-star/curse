class_name ItemDb
extends RefCounted
## Loads every ItemDef from res://data/items/ once.

const DIR := "res://data/items"

static var _defs: Dictionary = {}   # id -> ItemDef

static func all() -> Dictionary:
	if _defs.is_empty():
		var files: PackedStringArray = DirAccess.get_files_at(DIR)
		files.sort()
		for file in files:
			var name: String = file.trim_suffix(".remap")
			if name.ends_with(".tres"):
				var def: ItemDef = load("%s/%s" % [DIR, name]) as ItemDef
				if def != null and def.id != "":
					_defs[def.id] = def
	return _defs

static func get_def(id: String) -> ItemDef:
	return all().get(id) as ItemDef

## The base with this display name ("Greatsword"), for content and saves that name bases rather than ids.
static func by_name(display_name: String) -> ItemDef:
	for def in all().values():
		if (def as ItemDef).display_name == display_name:
			return def
	return null

## Every base for a slot, in `order`.
static func of_slot(slot: int) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for def in all().values():
		if (def as ItemDef).slot == slot:
			out.append(def)
	out.sort_custom(func(a: ItemDef, b: ItemDef) -> bool: return a.order < b.order)
	return out
