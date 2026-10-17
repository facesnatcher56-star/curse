class_name PowerDb
extends RefCounted
## Loads every PowerDef from res://data/powers/ once (tools/write_power_defs.py), and says what rank of a power the hero has.

const DIR := "res://data/powers"

static var _defs: Dictionary = {}   # id -> PowerDef

## Curse pacing (departs from DS2, docs/COMBAT_REFERENCE.md): seconds of combat each charged power takes to come back, in place of
## PowerDef.recharge. Single-target bursts (Brutal Attack, Take Aim) take about 11 s, the crowd powers (Whirling Strike, Thunderous
## Shot) about 7 s. Powers not listed keep DS2's. Tune here.
const CHARGE_SECONDS := {"brutal_attack": 11.0, "take_aim": 11.0, "whirling_strike": 7.0, "thunderous_shot": 7.0}
## A new party's powers: learned at rank 1 without the passive ranks that would normally open them, slotted on the hotbar (see
## HotbarLayout.DEFAULT_SLOTS) and fully charged.
const STARTING_POWERS := {"hero": ["brutal_attack", "whirling_strike"], "cutter": ["take_aim", "thunderous_shot"]}

## Seconds of combat `id` takes to recharge (CHARGE_SECONDS, else the power's DS2 value).
static func charge_seconds(id: String) -> float:
	if CHARGE_SECONDS.has(id):
		return float(CHARGE_SECONDS[id])
	var def: PowerDef = get_def(id)
	return def.recharge if def != null else 21.0

## The rank of `def` for a member with these passive ranks: the passives' rank, or 1 for a starting power.
static func rank_of(def: PowerDef, passive_ranks: Dictionary, member_id: String) -> int:
	var rank: int = def.rank_for(passive_ranks)
	return maxi(rank, 1) if STARTING_POWERS.get(member_id, []).has(def.id) else rank

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
static func hero_rank(id: String, member_id: String = "hero") -> int:
	var def: PowerDef = get_def(id)
	return rank_of(def, PartyManager.current().member(member_id).passive_ranks, member_id) if def != null else 0

## A power's value at the hero's rank and class levels.
static func hero_value(id: String, key: String, member_id: String = "hero") -> float:
	var def: PowerDef = get_def(id)
	if def == null:
		return 0.0
	return def.value(key, hero_rank(id, member_id), HeroAttributes.levels_from_xp(PartyManager.current().member(member_id).class_xp))
