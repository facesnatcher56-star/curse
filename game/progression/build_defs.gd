class_name BuildDefs
extends RefCounted
## What a hero can BUY with the points his level earns (see HeroProgression), and every tuning number of what those purchases do, in one
## place. Pure data: no state, no saving (TownState keeps what was chosen), no UI (ProgressionPanel only reads this).
##
## Vertical slice: six passives, and three mutually exclusive evolutions of Weapon Throw. Every passive costs 1 Passive Point and every
## evolution 1 Evolution Point. There is no tree, no prerequisites and no respec yet.

const PASSIVE_COST := 1
const EVOLUTION_COST := 1

## Passives in display order. Each is bought once.
const PASSIVE_ORDER: Array[String] = ["unbowed", "mass_transfer", "bloody_recovery", "stubborn_advance", "iron_recovery", "retaliation"]

const PASSIVES := {
	"unbowed": {"name": "Unbowed", "text": "Winding up or charging a heavy skill, the first light stagger is shrugged off. Heavy blows still stop you."},
	"mass_transfer": {"name": "Mass Transfer", "text": "A body you hurl into another carries its force on: one more enemy is bowled aside."},
	"bloody_recovery": {"name": "Bloody Recovery", "text": "A kill by a heavy impact, a collision you caused or a crushing finisher gets your wind back at once."},
	"stubborn_advance": {"name": "Stubborn Advance", "text": "A light blow no longer stops you while you press in on a target. Heavy blows still do."},
	"iron_recovery": {"name": "Iron Recovery", "text": "Shaking off a heavy blow, you shove the lesser enemies around you back with your whole body."},
	"retaliation": {"name": "Retaliation", "text": "After taking a heavy hit, your next basic strike within a few seconds sends its target reeling."},
}

## Skills that can be evolved, each with its mutually exclusive choices. One evolution per skill, permanently (no respec yet).
const EVOLUTION_SKILLS: Array[String] = ["throw"]

const SKILLS := {
	"throw": {
		"name": "Weapon Throw",
		"order": ["wallspike", "reaping_recall", "ricochet"],
		"evolutions": {
			"wallspike": {"name": "Wallspike", "text": "A full-strength throw spears the first ordinary enemy it hits and carries it. Into a wall, it is pinned there until you recall the weapon."},
			"reaping_recall": {"name": "Reaping Recall", "text": "The weapon coming home drags every lesser enemy it strikes in toward you, once each, and leaves them staggered."},
			"ricochet": {"name": "Ricochet", "text": "A strong throw glances off the first wall it meets and flies on, once. Bank it round corners."},
		},
	},
}

# --- Tuning -----------------------------------------------------------------------------------------------------------------------------

## A hit is HEAVY when one blow takes this share of max health, or it is an enemy's heavy attack (strike weight); otherwise it is LIGHT.
## (Nothing classified hits before the build system; this is the one definition.)
const HEAVY_HIT_FRACTION := 0.10
const HEAVY_HIT_WEIGHT := 2.0

# Unbowed
const UNBOWED_COOLDOWN := 2.5          # seconds before another light stagger can be shrugged off
# Stubborn Advance
const STUBBORN_SLOW := 0.3             # the flinch: how much slower, and for how long
const STUBBORN_SLOW_TIME := 0.35
# Mass Transfer
const MASS_TRANSFER_MIN_SPEED := 5.0   # m/s a launch needs to count as a heavy impact
const MASS_TRANSFER_KEEP := 0.9        # share of the speed the bowled body leaves with
const MASS_TRANSFER_FLOOR := 5.5       # and never slower than this (m/s): a real launch, not a nudge
# Bloody Recovery
const BLOODY_RECOVERY_SECONDS := 2.0   # stamina recovers at its normal rate, combat or not, for this long after the kill
const PHYSICAL_FINISHERS: Array[String] = ["impact", "collision", "power", "skewer_kick", "wallspike", "throw"]
# Iron Recovery
const IRON_RADIUS := 3.4
const IRON_KNOCK := 9.0
const IRON_STAGGER := 0.6
# Retaliation
const RETALIATION_SECONDS := 3.0
const RETALIATION_KNOCK := 10.0
const RETALIATION_STAGGER := 1.1

# Weapon Throw evolutions
const WALLSPIKE_MIN_CHARGE := 0.8
const WALLSPIKE_SPEED_KEEP := 0.8      # the weapon slows a little under the weight it carries
const WALLSPIKE_PIN_DAMAGE := 0.7      # of a weapon blow, once, when it is nailed to the wall
const RICOCHET_MIN_CHARGE := 0.5
const RICOCHET_SPEED_KEEP := 0.7
const RICOCHET_RANGE_KEEP := 0.65      # of the range it had left
const REAPING_STOP_DISTANCE := 3.0     # metres from the hero a dragged enemy comes to rest
const REAPING_MAX_PULL := 9.0          # the furthest an enemy is dragged (metres)
const REAPING_STAGGER := 1.1

static func passive(id: String) -> Dictionary:
	return PASSIVES.get(id, {})

static func is_passive(id: String) -> bool:
	return PASSIVES.has(id)

static func is_evolution(skill_id: String, evolution_id: String) -> bool:
	return SKILLS.has(skill_id) and (SKILLS[skill_id]["evolutions"] as Dictionary).has(evolution_id)

static func evolution(skill_id: String, evolution_id: String) -> Dictionary:
	if not is_evolution(skill_id, evolution_id):
		return {}
	return (SKILLS[skill_id]["evolutions"] as Dictionary)[evolution_id]

static func evolution_order(skill_id: String) -> Array:
	return (SKILLS[skill_id]["order"] as Array) if SKILLS.has(skill_id) else []

## Cleans saved choices so they can never create points: unknown or repeated ids go, a skill keeps at most one evolution, and when the
## choices cost more than the level has earned the later ones (in display order) are dropped. Returns {passives: Array[String], evolutions: Dictionary}.
static func sanitize(passives: Variant, evolutions: Variant, earned_passive: int, earned_evolution: int) -> Dictionary:
	var wanted: Dictionary = {}
	if passives is Array:
		for entry in passives:
			if typeof(entry) == TYPE_STRING and is_passive(String(entry)):
				wanted[String(entry)] = true
	var kept_passives: Array[String] = []
	var budget: int = earned_passive
	for id in PASSIVE_ORDER:
		if wanted.has(id) and budget >= PASSIVE_COST:
			kept_passives.append(id)
			budget -= PASSIVE_COST
	var kept_evolutions: Dictionary = {}
	var evo_budget: int = earned_evolution
	if evolutions is Dictionary:
		for skill_id in EVOLUTION_SKILLS:
			var chosen: Variant = (evolutions as Dictionary).get(skill_id)
			if typeof(chosen) == TYPE_STRING and is_evolution(skill_id, String(chosen)) and evo_budget >= EVOLUTION_COST:
				kept_evolutions[skill_id] = String(chosen)
				evo_budget -= EVOLUTION_COST
	return {"passives": kept_passives, "evolutions": kept_evolutions}
