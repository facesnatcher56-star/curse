class_name AffixDef
extends Resource
## One tier of a Dungeon Siege II item modifier family (docs/ds2-combat-and-loot.md 10.5): "of the Wolf" is +N life at modifier level L.
## Written by tools/write_affix_defs.py into res://data/affixes/; read through AffixDb. What a stat does is PlayerStats' (gear_stat).

@export var id: String = ""
## The family (its exclusion group: an item carries at most one tier of each) and the stat it raises.
@export var family: String = ""
@export var stat: String = ""
## The name it gives an item: a prefix ("Cruel Longsword") or a suffix ("Longsword of the Wolf").
@export var title: String = ""
@export_enum("prefix", "suffix") var position: String = "suffix"
@export var tier: int = 1
## Its modifier level: it rolls only on an item whose drop allows that level.
@export var level: int = 1
@export var value: float = 0.0
## True when `value` is a percentage.
@export var percent: bool = false
## The item kinds it may roll on (weapon, body, helm, gloves, boots, shield, ring, amulet).
@export var slots: Array[String] = []

## "+12 Strength", "+18% Melee damage": the line on an item card.
func describe() -> String:
	return "+%d%s %s" % [int(value), "%" if percent else "", String(AffixDb.STAT_NAMES.get(stat, stat))]
