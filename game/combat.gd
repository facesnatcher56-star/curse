class_name Combat
extends RefCounted
## Combat rules: Dungeon Siege II's (docs/ds2-combat-and-loot.md section 2). There is no accuracy roll: a blow lands unless it is
## dodged (the defender's dodge chance) or blocked (a shield's chance). Then a critical (a second hit on top), added elemental damage (fire, ice,
## lightning, death), armour as a ratio against the attacker's level, resistance for a directly typed element, the level-gap penalty, and a floor of 1.

enum Outcome { MISS, BLOCK, HIT, CRITICAL }
enum DamageType { PHYSICAL, FIRE, RANGED, ICE, LIGHTNING, DEATH }

## The DS2 elements. Each has independent added damage (`added_<e>`, `added_<e>_max`) and resistance (`<e>_resist`) on an Actor; a resistance
## only ever meets damage of its own element.
const ELEMENTS: Array[String] = ["fire", "ice", "lightning", "death"]
const ELEMENT_OF_TYPE := {DamageType.FIRE: "fire", DamageType.ICE: "ice", DamageType.LIGHTNING: "lightning", DamageType.DEATH: "death"}

## The negative bound of a resistance (a vulnerability): DS2 equipment has death resistance down to -30%, so it must not clamp at 0.
const RESIST_FLOOR := -1.0
## Monsters, unlike heroes, may exceed 100% (the hit then heals them; DS2 section 5 step 5). Curse bounds them at 200%.
const MONSTER_RESIST_CAP := 2.0

## The most a hero's resistance can be (DS2 caps it at 80%).
const RESIST_CAP := 0.8

## Shared eligibility, not inferred from the active character or equipped weapon at impact.
static func weapon_hit_eligible(result: Dictionary) -> bool:
	return not result.get("secondary", false) and not result.get("quiet", false) \
		and int(result.get("type", -1)) in [DamageType.PHYSICAL, DamageType.RANGED] \
		and bool(result.get("weapon_hit", false))

static func restoration_eligible(result: Dictionary) -> bool:
	return weapon_hit_eligible(result) or (not result.get("secondary", false) and not result.get("quiet", false)
		and String(result.get("skill_id", "")) == "fireball")

## Optional counters used by the self test.
static var tally: Dictionary = {}

## The share of a blow that gets through armour: `min(8 + 2 x attacker level, armour) / armour`. Armour at or under `8 + 2L` stops
## nothing; every point above it cuts the blow in proportion.
static func armor_factor(attacker_level: int, armor: float) -> float:
	if armor <= 0.0:
		return 1.0
	return minf(8.0 + 2.0 * float(attacker_level), armor) / armor

## DS2's level gap (attacker level - defender level): more than 4 below x0.75, 6 below x0.5, 8 below x0.25. Both ways: an under-levelled
## hero is nearly toothless, and an over-levelled hero takes little from small fry.
static func level_gap_factor(attacker_level: int, defender_level: int) -> float:
	var gap: int = attacker_level - defender_level
	if gap < -8:
		return 0.25
	if gap < -6:
		return 0.5
	if gap < -4:
		return 0.75
	return 1.0

## `base_damage` is the rolled blow (the attacker's weapon or spell, already times any skill multiplier). `can_miss` false: it cannot be
## dodged (a blast, a collision). `weight` scales knockback, hit-pause and shake: 1.0 for a light swing, higher for heavy blows.
## `allow_crit` false for powers (DS2: powers never crit).
static func resolve(attacker: Actor, defender: Actor, base_damage: float,
		damage_type: int = DamageType.PHYSICAL, can_miss: bool = true, weight: float = 1.0, force_crit: bool = false,
		allow_crit: bool = true, damage_multiplier: float = 1.0) -> Dictionary:
	var result: Dictionary = {"outcome": Outcome.HIT, "damage": 0.0, "weight": weight, "source": attacker, "type": damage_type}
	result["weapon_hit"] = damage_type in [DamageType.PHYSICAL, DamageType.RANGED]
	result["origin"] = attacker.combat_identity() if is_instance_valid(attacker) else {}
	if can_miss and randf() < dodge_chance_against(defender, damage_type):
		return _done(result, Outcome.MISS)
	var physical: bool = damage_type in [DamageType.PHYSICAL, DamageType.RANGED]
	var block: float = defender.ranged_block_chance if damage_type == DamageType.RANGED else defender.block_chance
	if physical and can_miss and randf() < block:
		return _done(result, Outcome.BLOCK)
	var dmg: float = base_damage
	if physical:
		dmg *= 1.0 - clampf(defender.toughness, 0.0, 0.9)
	if physical:
		# One independent roll per element, each against its own resistance only, added before crit and armour (DS2 step 4).
		var added: Dictionary = {}
		for element in ELEMENTS:
			var low: float = added_damage(attacker, element)
			if low > 0.0:
				var rolled: float = maxf(randf_range(low, maxf(low, added_damage_max(attacker, element))) * element_multiplier(defender, element), 0.0)
				added[element] = rolled
				dmg += rolled
		if not added.is_empty():
			result["added_elements"] = added   # per-element amounts, after resistance, before crit/armour/level gap
	var outcome: int = Outcome.HIT
	var forced: bool = allow_crit and attacker.forced_crits > 0
	if forced:
		attacker.forced_crits -= 1   # DS2's War Cry: the next blows crit
	if allow_crit and (force_crit or forced or randf() < attacker.crit_chance):
		# DS2 adds a second, separately rolled hit; CURSE CHOICE: the second roll is taken equal to the first (200%), since the blow
		# arrives here already rolled.
		outcome = Outcome.CRITICAL
		dmg *= attacker.crit_mult
	# DS2 applies armour to spell and power damage too, before final elemental resistance.
	dmg *= armor_factor(attacker.level, defender.armor * (1.0 - defender.armor_shred))
	dmg *= level_gap_factor(attacker.level, defender.level)
	dmg = maxf(dmg, 1.0) * damage_multiplier   # DS2 multiplies the complete resolved blow, including custom damage.
	if ELEMENT_OF_TYPE.has(damage_type):
		# Magical resistance and its matching elemental resistance share one capped effective pool.
		dmg *= resistance_multiplier(defender, magical_resistance_of(defender, ELEMENT_OF_TYPE[damage_type]))
	elif physical:
		# Added weapon elements were cut by element resistance before armor; this final attack-type pool cuts the combined blow once.
		dmg *= resistance_multiplier(defender, physical_attack_resistance(defender, damage_type))
	result["damage"] = dmg
	return _done(result, outcome)

## The chance `defender` has to dodge a blow of `damage_type`: arrows meet the ranged chance, everything else the melee one (DS2: the Dodge skill and
## `alter_chance_to_dodge_hit` gear apply to both; `_melee` and `_ranged` gear to one).
static func dodge_chance_against(defender: Actor, damage_type: int) -> float:
	var chance: float = defender.ranged_dodge_chance if damage_type == DamageType.RANGED and defender.ranged_dodge_chance >= 0.0 else defender.dodge_chance
	return clampf(chance, 0.0, 1.0)

static func fire_multiplier(defender: Actor) -> float:
	return element_multiplier(defender, "fire")

## The share of an element's damage that gets through `defender`: `1 - resistance`, resistance held to [-100%, 80%] for heroes and
## companions, [-100%, 200%] for monsters. Zero resistance is x1.0, -30% is x1.3.
static func element_multiplier(defender: Actor, element: String) -> float:
	return resistance_multiplier(defender, resistance_of(defender, element))

## Effective weapon resistance: physical plus the matching attack-type resistance. Additive overlap is a Curse-specific design choice,
## not verified original DS2 engine behavior. Enemy resistance cap remains Curse's existing 200% element cap pending source-specific data.
static func physical_attack_resistance(actor: Actor, damage_type: int) -> float:
	return actor.physical_resist + (actor.ranged_resist if damage_type == DamageType.RANGED else actor.melee_resist)

static func magical_resistance_of(actor: Actor, element: String) -> float:
	return actor.magical_resist + resistance_of(actor, element)

static func effective_resistance(actor: Actor, damage_type: int) -> float:
	if damage_type in [DamageType.PHYSICAL, DamageType.RANGED]:
		return clamp_resistance(actor, physical_attack_resistance(actor, damage_type))
	if ELEMENT_OF_TYPE.has(damage_type):
		return clamp_resistance(actor, magical_resistance_of(actor, ELEMENT_OF_TYPE[damage_type]))
	return clamp_resistance(actor, actor.magical_resist)

static func clamp_resistance(actor: Actor, resistance: float) -> float:
	var cap: float = RESIST_CAP if actor.is_in_group("player") or actor.is_in_group("companions") else MONSTER_RESIST_CAP
	return clampf(resistance, RESIST_FLOOR, cap)

static func resistance_multiplier(defender: Actor, resistance: float) -> float:
	return 1.0 - clamp_resistance(defender, resistance)

static func resistance_of(actor: Actor, element: String) -> float:
	match element:
		"fire": return actor.fire_resist
		"ice": return actor.ice_resist
		"lightning": return actor.lightning_resist
		"death": return actor.death_resist
	return 0.0

static func added_damage(actor: Actor, element: String) -> float:
	match element:
		"fire": return actor.added_fire
		"ice": return actor.added_ice
		"lightning": return actor.added_lightning
		"death": return actor.added_death
	return 0.0

static func added_damage_max(actor: Actor, element: String) -> float:
	match element:
		"fire": return actor.added_fire_max
		"ice": return actor.added_ice_max
		"lightning": return actor.added_lightning_max
		"death": return actor.added_death_max
	return 0.0

static func _done(result: Dictionary, outcome: int) -> Dictionary:
	result["outcome"] = outcome
	tally[outcome] = int(tally.get(outcome, 0)) + 1
	return result
