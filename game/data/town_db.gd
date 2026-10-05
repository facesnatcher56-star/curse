class_name TownDb
extends RefCounted
## Loads the town's data once: NPCs (res://data/npcs), personality traits (res://data/traits) and wave modifiers
## (res://data/modifiers). All are .tres Resources written by tools/write_town_defs.py.

static var _npcs: Dictionary = {}
static var _traits: Dictionary = {}
static var _modifiers: Dictionary = {}

static func npcs() -> Dictionary:
	if _npcs.is_empty():
		_load("res://data/npcs", _npcs)
	return _npcs

static func traits() -> Dictionary:
	if _traits.is_empty():
		_load("res://data/traits", _traits)
	return _traits

static func modifiers() -> Dictionary:
	if _modifiers.is_empty():
		_load("res://data/modifiers", _modifiers)
	return _modifiers

static func npc(id: String) -> NpcDef:
	return npcs().get(id) as NpcDef

static func trait_def(id: String) -> TraitDef:
	return traits().get(id) as TraitDef

static func modifier(id: String) -> RunModifierDef:
	return modifiers().get(id) as RunModifierDef

## Ids in a stable order (directory listings are not).
static func sorted_ids(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids

static func _load(dir: String, into: Dictionary) -> void:
	for file in DirAccess.get_files_at(dir):
		var name: String = file.trim_suffix(".remap")   # exported builds list resources as ".tres.remap"
		if not name.ends_with(".tres"):
			continue
		var res: Resource = load("%s/%s" % [dir, name])
		if res != null and res.get("id") != null and String(res.get("id")) != "":
			into[String(res.get("id"))] = res
