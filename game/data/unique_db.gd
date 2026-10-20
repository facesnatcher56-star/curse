class_name UniqueDb
extends RefCounted
## Loads every UniqueDef (res://data/uniques/) and SetDef (res://data/sets/) once (tools/write_unique_defs.py).

static var _uniques: Dictionary = {}   # id -> UniqueDef
static var _sets: Dictionary = {}      # id -> SetDef

static func uniques() -> Dictionary:
	if _uniques.is_empty():
		_uniques = _load("res://data/uniques")
	return _uniques

static func sets() -> Dictionary:
	if _sets.is_empty():
		_sets = _load("res://data/sets")
	return _sets

static func get_unique(id: String) -> UniqueDef:
	return (uniques().get(id) as UniqueDef) if uniques().has(id) else MapModeLegendaries.def(id)   # map-mode legendaries are outside the drop pool

static func get_set(id: String) -> SetDef:
	return sets().get(id) as SetDef

## Uniques (`set_pieces` false) or set pieces (true) whose item level is inside [low, high].
static func within(low: int, high: int, set_pieces: bool) -> Array[UniqueDef]:
	var out: Array[UniqueDef] = []
	for def in uniques().values():
		var u := def as UniqueDef
		if (u.set_id != "") == set_pieces and u.level >= low and u.level <= high:
			out.append(u)
	return out

static func _load(dir: String) -> Dictionary:
	var out: Dictionary = {}
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		var name: String = file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var res: Resource = load("%s/%s" % [dir, name])
			if res != null and String(res.get("id")) != "":
				out[String(res.get("id"))] = res
	return out
