class_name EnemyDb
extends RefCounted
## Loads every EnemyDef from res://data/enemies/ once and hands them out by id.

const DIR := "res://data/enemies"

static var _defs: Dictionary = {}

static func all() -> Dictionary:
	if _defs.is_empty():
		for file in DirAccess.get_files_at(DIR):
			# Exported builds list resources as ".tres.remap"; strip it so loading works in both.
			var name: String = file.trim_suffix(".remap")
			if name.ends_with(".tres"):
				var def: EnemyDef = load("%s/%s" % [DIR, name]) as EnemyDef
				if def != null and def.id != "":
					_defs[def.id] = def
	return _defs

static func get_def(id: String) -> EnemyDef:
	var defs: Dictionary = all()
	if not defs.has(id):
		push_error("EnemyDb: no enemy called '%s'" % id)
		return defs.get("zombie")
	return defs[id]

## Definitions that wave spawning may use at this wave, in a stable order.
static func spawnable(wave: int) -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	var ids: Array = all().keys()
	ids.sort()
	for id in ids:
		var def: EnemyDef = _defs[id]
		if def.max_per_wave > 0 and wave >= def.min_wave:
			out.append(def)
	return out

## How many of this enemy a wave calls for.
static func count_for(def: EnemyDef, wave: int) -> int:
	if def.max_per_wave <= 0 or wave < def.min_wave:
		return 0
	return mini(int(def.base_count + def.per_wave * float(wave - def.min_wave)), def.max_per_wave)
