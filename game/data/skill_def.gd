class_name SkillDef
extends Resource
## One hero skill as data: costs, timing, which animation clip and its strike window, and its tooltip text.
## Instances are .tres files in res://data/skills/ (loaded by SkillDb). `extra` carries the numbers only one kind of skill
## uses (the fireball's gather/release timing, the basic attack's combo table, ...).

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Cost")
@export var mana: float = 0.0
@export var cooldown: float = 0.0

@export_group("Timing")
## Gameplay duration of the whole skill in seconds (the clip window below is stretched to fit it).
@export var time: float = 1.0
@export var clip: String = ""
## Clip seconds where the swing starts, lands and ends (measure with tools/anim_timing.gd).
@export var clip_start: float = 0.0
@export var clip_strike: float = 0.0
@export var clip_end: float = 0.0

@export_group("Effect")
## "melee", "cleave", "projectile", "charge", "leap", "potion" or "dodge": which code path runs it.
@export var kind: String = "melee"
@export var range: float = 2.4
@export var mult: float = 1.0
@export var weight: float = 1.0
@export var lunge: float = 0.0

@export_group("Input")
## Triggers on key press, toward the cursor (Skewer, Leap).
@export var directional: bool = false
## Hold the key to aim a ground target, release to cast (Fireball).
@export var aimed: bool = false

@export_group("Gear")
## Affixes that change how this skill behaves; a gold pip shows on its hotbar slot while one is worn.
@export var modifier_affixes: Array[String] = []

## Anything else a particular skill needs (flags like "charged", "skewer", "leap", fireball timing, the combo table).
@export var extra: Dictionary = {}

## The dictionary form the combat code reads (the shape the old SKILLS constant had).
func to_dict() -> Dictionary:
	var d: Dictionary = {"name": display_name, "mana": mana, "time": time, "range": range, "mult": mult, "cd": cooldown,
		"kind": kind, "clip": clip, "start": clip_start, "strike": clip_strike, "end": clip_end, "weight": weight, "lunge": lunge}
	if directional:
		d["directional"] = true
	if aimed:
		d["aimed"] = true
	d.merge(extra, true)
	return d
