class_name HeroAttributes
extends RefCounted
## Dungeon Siege II's character model as pure rules (docs/ds2-combat-and-loot.md section 1): no state, no saving, no UI.
## Four class skills (Melee, Ranged, Combat Magic, Nature Magic) rise with use; they decide STR / DEX / INT, which decide life and mana.
## TownState holds the XP; this turns XP into levels, attributes and the numbers the hero (and Cutter) fight with.

const CLASSES: Array[String] = ["melee", "ranged", "combat", "nature"]
const CLASS_NAMES := {"melee": "Melee", "ranged": "Ranged", "combat": "Combat Magic", "nature": "Nature Magic"}

## DS2 `skill_influences`: how much each class skill feeds STR, DEX and INT.
const INFLUENCE := {
	"melee": Vector3(3, 1, 1),
	"ranged": Vector3(1, 3, 1),
	"combat": Vector3(1, 1, 3),
	"nature": Vector3(1, 1, 3),
}

## DS2's human start (STR, DEX, INT).
const START := Vector3(12, 11, 11)
## heroes_ds2.gas: human magic_find_chance = 0.1 (percent units used by our loot rules).
const HUMAN_MAGIC_FIND := 10.0

## The skill each hit is counted under. Anything not listed (collisions, impacts, splash) is Melee: the hero's own body and blade.
const SKILL_CLASS := {
	"basic": "melee", "brutal_attack": "melee", "whirling_strike": "melee", "staggering_blow": "melee", "rebuke": "melee", "reflect": "melee",
	"collision": "melee", "impact": "melee",
	"take_aim": "ranged", "companion_arrow": "ranged",
	"flame_nexus": "combat", "detonation": "combat",
	"fireball": "combat", "burn": "combat",
}

## Class skill level from its XP: DS2 reads it straight off the same table as character level, counting from 0 (confirmed in the real game:
## a fresh hero is Level 0 with every class skill 0, and a pure fighter shows character level 3 and Melee 3 together). Curse numbers the
## character from 1, so its level is always one above DS2's while the class skill equals it: Melee 0 untrained, 1 at the XP of character level 2.
static func class_level(xp: int) -> int:
	return HeroProgression.level_for_xp(xp) - 1

static func class_of_skill(skill_id: String) -> String:
	return String(SKILL_CLASS.get(skill_id, "melee"))

## STR, DEX, INT for these class levels ({class id: level}). CURSE CHOICE (DS2 does this inside its engine): each class level adds its
## influence weights, so a pure Melee 29 hero has 12 + 3x29 = 99 STR, 40 DEX, 40 INT, matching DS2's design note (STR = 3 x level + 10,
## about 100 / 40 / 40 at level 30).
static func attributes(levels: Dictionary) -> Vector3:
	var out: Vector3 = START
	for id in CLASSES:
		out += INFLUENCE[id] * float(levels.get(id, 0))
	return out

## DS2 max life: (0.50 STR + 0.39 DEX + 0.23 INT) x 5 x (1 + Fortitude).
static func max_life(attr: Vector3, fortitude: float = 0.0) -> float:
	return (0.50 * attr.x + 0.39 * attr.y + 0.23 * attr.z) * 5.0 * (1.0 + fortitude)

## DS2 max mana: (0.01 STR + 0.12 DEX + 0.87 INT) x 5 x (1 + Brilliance).
static func max_mana(attr: Vector3, brilliance: float = 0.0) -> float:
	return (0.01 * attr.x + 0.12 * attr.y + 0.87 * attr.z) * 5.0 * (1.0 + brilliance)

## DS2 regeneration: about 1% of the maximum per second.
const REGEN_PER_SECOND := 0.01

## Levels from class XP ({class id: xp}).
static func levels_from_xp(class_xp: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in CLASSES:
		out[id] = class_level(int(class_xp.get(id, 0)))
	return out

## Splits `amount` XP over the class skills by the damage each did ({class id: damage}). With no damage recorded it all goes to
## `fallback` (CURSE CHOICE for XP that is not from a hit: quests, nests, a kill made entirely by Cutter).
static func split(amount: int, damage_by_class: Dictionary, fallback: String) -> Dictionary:
	var total: float = 0.0
	for id in damage_by_class:
		total += maxf(float(damage_by_class[id]), 0.0)
	if amount <= 0:
		return {}
	if total <= 0.0:
		return {fallback: amount}
	var out: Dictionary = {}
	var given: int = 0
	var biggest: String = fallback
	var biggest_damage: float = -1.0
	for id in damage_by_class:
		var d: float = maxf(float(damage_by_class[id]), 0.0)
		var share: int = int(floor(float(amount) * d / total))
		if share > 0:
			out[id] = share
			given += share
		if d > biggest_damage:
			biggest_damage = d
			biggest = id
	if given < amount:   # rounding: what is left goes to the class that did the most
		out[biggest] = int(out.get(biggest, 0)) + amount - given
	return out
