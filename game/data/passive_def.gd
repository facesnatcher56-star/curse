class_name PassiveDef
extends Resource
## One Dungeon Siege II passive skill (docs/ds2-combat-and-loot.md 6): bought with skill points, one rank at a time, up to 20. Its effect
## runs from `first` at rank 1 to `last` at rank 20. It opens at a class skill level and may need ranks in another passive first.
## Written by tools/write_passive_defs.py into res://data/passives/; read through PassiveDb. What an effect does is PlayerStats' (passive).

const MAX_RANK := 20

@export var id: String = ""
@export var display_name: String = ""
## Its tree: melee, ranged, combat (HeroAttributes.CLASSES).
@export var tree: String = ""
## The class skill level that opens it (DS2's tiers: 1, 5, 12, 24, 36).
@export var class_level: int = 1
## Ranks needed in other passives first: id -> rank.
@export var prereqs: Dictionary = {}
## The effect at rank 1 and at rank 20, and how it reads: "Max life +%s%%".
@export var first: float = 0.0
@export var last: float = 0.0
@export var text: String = ""
## What Curse is missing for its effect ("" when it works): it can still be bought, as DS2's path to what comes after it.
@export var needs: String = ""
## Order within its tree.
@export var order: int = 0

## Its effect at `rank` (0 at rank 0; straight from rank 1 to rank 20).
func value(rank: int) -> float:
	if rank <= 0:
		return 0.0
	return first + (last - first) * float(mini(rank, MAX_RANK) - 1) / float(MAX_RANK - 1)

func describe(rank: int) -> String:
	var v: float = value(maxi(rank, 1))
	return text % (("%d" % int(round(v))) if absf(v - round(v)) < 0.05 or absf(v) >= 10.0 else ("%.1f" % v))
