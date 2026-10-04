class_name SkillDb
extends RefCounted
## Loads every SkillDef from res://data/skills/ once. `all()` gives the dictionary form the combat code reads
## (skill id -> {name, mana, cd, ...}); the definitions themselves are available through `get_def()`.

const DIR := "res://data/skills"

static var _defs: Dictionary = {}
static var _dicts: Dictionary = {}

static func _load() -> void:
	if not _defs.is_empty():
		return
	for file in DirAccess.get_files_at(DIR):
		var name: String = file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var def: SkillDef = load("%s/%s" % [DIR, name]) as SkillDef
			if def != null and def.id != "":
				_defs[def.id] = def
				_dicts[def.id] = def.to_dict()

static func all() -> Dictionary:
	_load()
	return _dicts

static func get_def(id: String) -> SkillDef:
	_load()
	return _defs.get(id)

## id -> tooltip description.
static func description(id: String) -> String:
	_load()
	var def: SkillDef = _defs.get(id)
	return def.description if def != null else ""

## Affix ids that modify a skill.
static func modifier_affixes(id: String) -> Array[String]:
	_load()
	var def: SkillDef = _defs.get(id)
	return def.modifier_affixes if def != null else ([] as Array[String])

## The basic attack's three-step combo table (each step lists the variants it may pick from).
static func basic_combo() -> Array:
	_load()
	return (_defs["basic"] as SkillDef).extra.get("combo", [])
