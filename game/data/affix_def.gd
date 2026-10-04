class_name AffixDef
extends Resource
## One gear affix as data: what it is called, which slot it rolls on and what it does, in words.
## What it actually *does* is code keyed by `id` in item_effects.gd (the hooks check `has_affix(id)`); this resource is the
## catalogue entry the item generator, the tooltips and the reward screen read. Files live in res://data/affixes/.

@export var id: String = ""
## Prefix for rare items ("Frostbitten Longsword"). Empty = unique-only (never rolled on a rare).
@export var title: String = ""
@export_enum("Weapon", "Armor", "Trinket") var slot: int = 0
@export_multiline var description: String = ""

## The dictionary form the item code reads: {title, slot, desc}.
func to_dict() -> Dictionary:
	return {"title": title, "slot": slot, "desc": description}
