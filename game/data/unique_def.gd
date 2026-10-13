class_name UniqueDef
extends Resource
## A hand-authored item (DS2's uniques and set pieces, docs/ds2-combat-and-loot.md 10.6): a base at a fixed item level with fixed
## modifiers and no random ones. A set piece names its set (SetDef). Written by tools/write_unique_defs.py into res://data/uniques/.

@export var id: String = ""
@export var display_name: String = ""
## The ItemDef it is made on, and its item level.
@export var base: String = ""
@export var level: int = 1
## Its fixed modifiers: stat (AffixDb.STAT_NAMES) -> value.
@export var mods: Dictionary = {}
## The source requirement expression (EquipmentRequirement syntax), when the item's DS2 requirement differs from its base's ("" keeps the base's).
@export var requirements: String = ""
## The SetDef it belongs to ("" for a unique).
@export var set_id: String = ""
## Source-backed passive alterations carried by this unique.
@export var passive_effects: Array[Dictionary] = []
