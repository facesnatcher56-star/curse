class_name Combat
extends RefCounted
## Combat rules, modelled on the layered mitigation described in the Zombasite manual:
## avoid (attack vs defense) -> block -> armor/resist -> health.
## The exact curves are our own tunable approximations, not copied from the original.

enum Outcome { MISS, BLOCK, HIT, CRITICAL, CRUSHING, DEEP_WOUNDS }
enum DamageType { PHYSICAL, FIRE }

## Optional counters used by the self test.
static var tally: Dictionary = {}

static func hit_chance(attack: float, defense: float) -> float:
	return clampf(attack / maxf(attack + defense * 0.6, 1.0), 0.1, 0.95)

static func mitigate(damage: float, armor_or_resist: float) -> float:
	return damage * 100.0 / (100.0 + maxf(armor_or_resist, 0.0))

## `weight` scales knockback, hit-pause and shake: 1.0 for a light swing, higher for heavy blows.
static func resolve(attacker: Actor, defender: Actor, base_damage: float,
		damage_type: int = DamageType.PHYSICAL, can_miss: bool = true, weight: float = 1.0, force_crit: bool = false) -> Dictionary:
	var result: Dictionary = {"outcome": Outcome.HIT, "damage": 0.0, "bleed_dps": 0.0, "bleed_time": 0.0,
		"weight": weight, "source": attacker, "type": damage_type}
	if damage_type == DamageType.PHYSICAL:
		if can_miss and randf() > hit_chance(attacker.attack_rating, defender.defense):
			return _done(result, Outcome.MISS)
		if randf() < defender.block_chance:
			return _done(result, Outcome.BLOCK)

	var dmg: float = base_damage * randf_range(0.85, 1.15)
	var outcome: int = Outcome.HIT
	var roll: float = randf()
	if force_crit:
		outcome = Outcome.CRITICAL
		dmg *= 1.75
	elif damage_type == DamageType.PHYSICAL:
		if roll < attacker.crushing_chance:
			outcome = Outcome.CRUSHING
			dmg *= 1.25
		elif roll < attacker.crushing_chance + attacker.crit_chance:
			outcome = Outcome.CRITICAL
			dmg *= 1.75
		elif roll < attacker.crushing_chance + attacker.crit_chance + attacker.deep_wounds_chance:
			outcome = Outcome.DEEP_WOUNDS
			result["bleed_dps"] = dmg * 0.12
			result["bleed_time"] = 4.0
	elif roll < attacker.crit_chance:
		outcome = Outcome.CRITICAL
		dmg *= 1.5

	var protection: float = defender.armor if damage_type == DamageType.PHYSICAL else defender.fire_resist
	result["damage"] = maxf(mitigate(dmg, protection), 1.0)
	return _done(result, outcome)

static func _done(result: Dictionary, outcome: int) -> Dictionary:
	result["outcome"] = outcome
	tally[outcome] = int(tally.get(outcome, 0)) + 1
	return result
