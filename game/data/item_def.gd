class_name ItemDef
extends Resource
## One base item as data: what it is, which slot it fills, how it looks on the ground and in the inventory, and the item levels it comes in.
## A particular item in the world is an *instance* (see Items): this definition's id, an item level, a rarity and its modifiers.
## Its numbers are Dungeon Siege II's curves at that level (docs/ds2-combat-and-loot.md 10.1 and 3), so changing a base changes every copy,
## saved ones included. Files live in res://data/items/, written by tools/write_item_defs.py.

## DS2's damage per hit at item level L, `a + b L`, by weapon type (`wpn_bases.gas`); the low roll is 0.75 of it and the high 1.25.
const WEAPON_CURVES := {"1h": Vector2(3.4, 0.74), "2h": Vector2(5.2, 1.2), "thrown": Vector2(3.84, 0.86), "bow": Vector2(3.0, 0.65)}
## DS2's armour: `class x slot x (16 + 4L)` (`amr_bases.gas`).
const ARMOR_CLASS := {"fighter": 1.0, "ranger": 0.8, "mage": 0.6}
const ARMOR_SLOT := {"body": 0.5, "helm": 0.2, "shield": 0.2, "gloves": 0.15, "boots": 0.15}

@export var id: String = ""
@export var display_name: String = ""
@export_enum("Weapon", "Body armour", "Ring", "Shield", "Helm", "Gloves", "Boots", "Amulet") var slot: int = 0
## Order within its slot (which base is "first"; also the order tests and menus go through them).
@export var order: int = 0
## The model it lies on the ground as, and the held model for weapons (Blender, tools/blender/make_items.py).
@export var model_path: String = ""
@export var icon_path: String = ""
## What it is to DS2: 1h, 2h (weapons), body, helm, gloves, boots, shield (armour), ring, amulet (jewellery).
@export var item_type: String = ""
## An armour piece's class: fighter, ranger or mage (its share of the armour budget).
@export var armor_class: String = ""
## The item levels this base comes in (DS2's base and var1-var4), lowest first.
@export var levels: Array[int] = []
## What is not a curve: a weapon's {damage (its share of its type's damage per hit), speed}.
@export var stats: Dictionary = {}
## How a weapon fights beyond its damage and speed (read through PlayerStats.weapon_profile; empty means the baseline longsword style):
## (swing speed itself is the weapon's "speed" stat) "recovery" speeds (or slows) the tail after each blow, "weight" scales the stagger and
## knockback of the basic combo; "finisher_time" scales the combo finisher's length, "style" is the tooltip line.
## Basic attacks always resolve against one engaged enemy (DS2); area damage belongs to explicit powers.
## "two_handed" true: it needs both hands (no shield).
@export var profile: Dictionary = {}

func is_weapon() -> bool:
	return WEAPON_CURVES.has(item_type)

func is_armor() -> bool:
	return ARMOR_SLOT.has(item_type)

func is_jewelry() -> bool:
	return item_type == "ring" or item_type == "amulet"

## Its numbers at item level `level`: a weapon {min, max, speed}, an armour piece {armor}, jewellery {}.
func stats_at(level: int) -> Dictionary:
	var out: Dictionary = {}
	for key in stats:
		out[key] = float(stats[key])
	var l: float = float(maxi(level, 1))
	if is_weapon():
		var curve: Vector2 = WEAPON_CURVES[item_type]
		var average: float = (curve.x + curve.y * l) * float(stats.get("damage", 1.0))
		out.erase("damage")
		out["min"] = average * 0.75
		out["max"] = average * 1.25
		out["speed"] = float(stats.get("speed", 1.0))
	elif is_armor():
		out["armor"] = float(ARMOR_CLASS.get(armor_class, 1.0)) * float(ARMOR_SLOT[item_type]) * (16.0 + 4.0 * l)
	return out

## The level of this base nearest `level` (for an item whose level came from elsewhere, such as an old save).
func nearest_level(level: int) -> int:
	var best: int = levels[0] if not levels.is_empty() else maxi(level, 1)
	for candidate in levels:
		if absi(candidate - level) < absi(best - level):
			best = candidate
	return best
