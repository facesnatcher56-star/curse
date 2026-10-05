class_name ItemDef
extends Resource
## One base item as data: what it is, which slot it fills, how it looks on the ground and in the inventory, and its fixed numbers.
## A particular item in the world is an *instance* (see Items): this definition's id, a tier, a rarity and an affix, nothing else.
## Everything else is read from here, so changing a base's numbers or model changes every copy, saved ones included.
## Files live in res://data/items/, written by tools/write_item_defs.py.

@export var id: String = ""
@export var display_name: String = ""
@export_enum("Weapon", "Armor", "Trinket") var slot: int = 0
## Order within its slot (which base is "first"; also the order tests and menus go through them).
@export var order: int = 0
## The model it lies on the ground as, and the held model for weapons (Blender, tools/blender/make_items.py).
@export var model_path: String = ""
@export var icon_path: String = ""
## Base numbers at tier 1: weapons {damage, speed}, armour {armor, roll_cost, roll_speed}, trinkets {}.
@export var stats: Dictionary = {}
## How a stat grows with tier: `tier_mult` {key: fraction per tier above 1} multiplies, `tier_add` {key: amount per tier above 1} adds.
@export var tier_mult: Dictionary = {}
@export var tier_add: Dictionary = {}
## How a weapon fights beyond its damage and speed (read through PlayerStats.weapon_profile; empty means the baseline longsword style):
## "swing" speeds the basic combo, "recovery" speeds (or slows) the tail after each blow, "weight" scales the stagger and knockback of
## the basic combo, "arc" is the width in degrees in which a basic swing also hits other enemies (for "arc_damage" of the damage),
## "finisher_time" scales the combo finisher's length, "finisher" = "slam" makes it shake the ground, "style" is the tooltip line.
@export var profile: Dictionary = {}

func stats_at(tier: int) -> Dictionary:
	var out: Dictionary = {}
	var steps: int = maxi(tier, 1) - 1
	for key in stats:
		var value: float = float(stats[key])
		value *= 1.0 + float(tier_mult.get(key, 0.0)) * steps
		value += float(tier_add.get(key, 0.0)) * steps
		out[key] = value
	return out

## The tier a stat line was made at (for saves from before items kept their tier): -1 when the stats do not fit this base.
func tier_of(saved_stats: Dictionary) -> int:
	for key in tier_mult:
		if saved_stats.has(key) and float(stats.get(key, 0.0)) > 0.0:
			return maxi(1 + int(round((float(saved_stats[key]) / float(stats[key]) - 1.0) / float(tier_mult[key]))), 1)
	for key in tier_add:
		if saved_stats.has(key):
			return maxi(1 + int(round((float(saved_stats[key]) - float(stats.get(key, 0.0))) / float(tier_add[key]))), 1)
	return 1
