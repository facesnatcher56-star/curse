class_name AffixDb
extends RefCounted
## Loads every AffixDef from res://data/affixes/ once; `all()` is id -> {title, slot, desc}.

const DIR := "res://data/affixes"

static var _dicts: Dictionary = {}

static func all() -> Dictionary:
	if _dicts.is_empty():
		var files: PackedStringArray = DirAccess.get_files_at(DIR)
		files.sort()
		for file in files:
			var name: String = file.trim_suffix(".remap")
			if name.ends_with(".tres"):
				var def: AffixDef = load("%s/%s" % [DIR, name]) as AffixDef
				if def != null and def.id != "":
					_dicts[def.id] = def.to_dict()
	return _dicts
