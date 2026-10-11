class_name SetDef
extends Resource
## An item set (DS2, docs/ds2-combat-and-loot.md 10.6): bonuses that grow with the number of its pieces worn, cumulatively (two pieces give
## the "2" bonus, three the "2" and the "3" ...). Written by tools/write_unique_defs.py into res://data/sets/.

@export var id: String = ""
@export var display_name: String = ""
## Pieces worn (as a string key) -> {stat: value}.
@export var bonuses: Dictionary = {}

## Everything `worn` pieces give, summed.
func bonus_for(worn: int) -> Dictionary:
	var out: Dictionary = {}
	for key in bonuses:
		if int(key) <= worn:
			for stat in bonuses[key]:
				out[stat] = float(out.get(stat, 0.0)) + float(bonuses[key][stat])
	return out
