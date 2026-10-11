class_name PowerDef
extends Resource
## One Dungeon Siege II power (docs/ds2_powers_reference.md, ds2-combat-and-loot.md 7): three ranks, each opened by ranks in passives
## (no points are spent on a power), no mana and no cooldown: it recharges from damage dealt (`recharge` seconds of DS2's combat formula,
## PlayerStats.power_recharge_damage). Written by tools/write_power_defs.py into res://data/powers/; read through PowerDb.

@export var id: String = ""
@export var display_name: String = ""
## Its tree: melee, ranged, combat, nature.
@export var tree: String = ""
## Seconds of combat its recharge is worth (DS2: 12, 21, 35 or 60).
@export var recharge: float = 21.0
## What the hero must wield: melee (any melee weapon), shield, two_handed, dual_wield, bow, thrown, or any.
@export var stance: String = "any"
## What each rank needs: three {passive id: rank} (DS2's skill_requirements_0..2).
@export var ranks: Array[Dictionary] = []
## Its numbers per rank: key -> three expressions in melee, ranged, combat and nature (the class levels).
@export var values: Dictionary = {}
## Keys whose ranks 2 and 3 are estimated (the extract did not carry them; ds2_powers_reference.md).
@export var estimated: Array[String] = []
@export var summary: String = ""
## Order within its tree.
@export var order: int = 0
## What Curse is missing for it ("" when it can be used): dual wielding, bows, throwing weapons, ice ... It is data until then.
@export var needs: String = ""

## The rank `passive_ranks` (passive id -> rank) open: the highest whose every requirement is met; 0 for none.
func rank_for(passive_ranks: Dictionary) -> int:
	var best: int = 0
	for i in ranks.size():
		var ok: bool = true
		for passive in ranks[i]:
			ok = ok and int(passive_ranks.get(passive, 0)) >= int(ranks[i][passive])
		if ok:
			best = i + 1
	return best

## `key` at `rank` (1-3) for these class levels ({melee, ranged, combat, nature}).
func value(key: String, rank: int, levels: Dictionary) -> float:
	var list: Array = values.get(key, [])
	if list.is_empty() or rank <= 0:
		return 0.0
	var expression := Expression.new()
	var names := PackedStringArray(["melee", "ranged", "combat", "nature"])
	if expression.parse(String(list[clampi(rank, 1, list.size()) - 1]), names) != OK:
		push_error("PowerDef %s: bad expression for %s" % [id, key])
		return 0.0
	return float(expression.execute([float(levels.get("melee", 0)), float(levels.get("ranged", 0)), float(levels.get("combat", 0)),
		float(levels.get("nature", 0))]))
