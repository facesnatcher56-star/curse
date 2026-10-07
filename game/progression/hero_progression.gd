class_name HeroProgression
extends RefCounted
## The rules of the hero's permanent level, and nothing else: no state, no saving, no UI. `TownState` owns the hero's total XP and
## asks this class what level that is; the character screen asks it what to show. The one place the curve lives.

## The level cap. Everything that needs it reads this; nothing else spells the number out.
const MAX_LEVEL := 30

## Total lifetime XP needed to BE each level, level 1 first (index 0). An explicit table, not a formula, so one level that plays too
## slowly can be moved without shifting every later one. Provisional: to be tuned with real playtime. Early levels take 100-300 XP,
## the later ones 900-1400; no level is a wall.
const XP_FOR_LEVEL: Array[int] = [
	0,      # 1
	100,    # 2
	250,    # 3
	450,    # 4
	700,    # 5
	1000,   # 6
	1350,   # 7
	1750,   # 8
	2200,   # 9
	2700,   # 10
	3250,   # 11
	3850,   # 12
	4500,   # 13
	5200,   # 14
	5950,   # 15
	6750,   # 16
	7600,   # 17
	8500,   # 18
	9450,   # 19
	10450,  # 20
	11500,  # 21
	12600,  # 22
	13750,  # 23
	14950,  # 24
	16200,  # 25
	17500,  # 26
	18850,  # 27
	20250,  # 28
	21650,  # 29
	23050,  # 30
]

## The most XP a hero can hold: exactly what level MAX_LEVEL takes. XP earned past it is not kept.
static func max_xp() -> int:
	return XP_FOR_LEVEL[MAX_LEVEL - 1]

## Total XP needed to be this level (the level is clamped to 1..MAX_LEVEL).
static func xp_for_level(level: int) -> int:
	return XP_FOR_LEVEL[clampi(level, 1, MAX_LEVEL) - 1]

## A saved or typed XP value made safe: whole, never negative, never past the cap. Anything that is not a number (a malformed save)
## is 0. JSON hands integers back as floats, so floats are accepted.
static func sanitize_xp(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	var number: float = float(value)
	if is_nan(number) or number <= 0.0:
		return 0
	return mini(int(minf(number, float(max_xp()))), max_xp())

## The level that this much total XP is.
static func level_for_xp(total_xp: int) -> int:
	var xp: int = sanitize_xp(total_xp)
	var level: int = 1
	while level < MAX_LEVEL and xp >= XP_FOR_LEVEL[level]:
		level += 1
	return level

static func is_max_level(total_xp: int) -> bool:
	return level_for_xp(total_xp) >= MAX_LEVEL

## How much of the current level has been earned (420 of "420 / 650").
static func xp_into_level(total_xp: int) -> int:
	var xp: int = sanitize_xp(total_xp)
	return xp - xp_for_level(level_for_xp(xp))

## How much XP the current level takes in all (the 650 of "420 / 650"); 0 at the cap, where there is no next level.
static func xp_span_of_level(total_xp: int) -> int:
	var level: int = level_for_xp(total_xp)
	if level >= MAX_LEVEL:
		return 0
	return xp_for_level(level + 1) - xp_for_level(level)

## How much more XP the next level needs; 0 at the cap.
static func xp_to_next_level(total_xp: int) -> int:
	return xp_span_of_level(total_xp) - xp_into_level(total_xp) if not is_max_level(total_xp) else 0

## 0..1 through the current level; 1 at the cap (no division by zero there).
static func level_fraction(total_xp: int) -> float:
	var span: int = xp_span_of_level(total_xp)
	if span <= 0:
		return 1.0
	return clampf(float(xp_into_level(total_xp)) / float(span), 0.0, 1.0)

## What the character screen shows beside the level: "420 / 650 XP", or "MAX LEVEL".
static func progress_text(total_xp: int) -> String:
	if is_max_level(total_xp):
		return "MAX LEVEL"
	return "%d / %d XP" % [xp_into_level(total_xp), xp_span_of_level(total_xp)]

# --- What a level grants ----------------------------------------------------------------------------------------------------------------
# Two build currencies, both DERIVED from the hero's level, never stored or counted up as levels pass: Hero Level is the entitlement, so a
# loaded level 20 hero has exactly what a hero who levelled there has. What is spent will be saved later (available = earned - spent); for
# now nothing can be spent, so everything earned is available.
#   Passive Points: one at every even level (2, 4 ... 30): 15 by the cap. They will buy broad berserker passives.
#   Evolution Points: one every third level (3, 6 ... 30): 10 by the cap. They will evolve individual active skills.
# Only Hero Level grants them. Items, world threat and XP sources are separate systems and stay that way.
const PASSIVE_POINT_EVERY := 2
const EVOLUTION_POINT_EVERY := 3

static func passive_points_for_level(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL) / PASSIVE_POINT_EVERY

static func evolution_points_for_level(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL) / EVOLUTION_POINT_EVERY

## What the levels from `old_level` (exclusive) up to `new_level` (inclusive) granted, every milestone crossed counted:
## {passive, evolution}. Nothing when the level did not rise.
static func points_between(old_level: int, new_level: int) -> Dictionary:
	if new_level <= old_level:
		return {"passive": 0, "evolution": 0}
	return {"passive": passive_points_for_level(new_level) - passive_points_for_level(old_level),
		"evolution": evolution_points_for_level(new_level) - evolution_points_for_level(old_level)}

## "+1 Passive Point  +1 Evolution Point", or "" when a level-up granted neither.
static func points_text(passive: int, evolution: int) -> String:
	var parts: PackedStringArray = []
	if passive > 0:
		parts.append("+%d Passive Point%s" % [passive, "" if passive == 1 else "s"])
	if evolution > 0:
		parts.append("+%d Evolution Point%s" % [evolution, "" if evolution == 1 else "s"])
	return "   ".join(parts)

# --- What the world pays in XP --------------------------------------------------------------------------------------------------------
# One place for every reward rule and number, so the economy can be tuned in one file. None of these read the hero's level: the same source
# is worth the same XP to a level 1 hero and a level 20 one (the rising level requirements are what make early content inefficient).
# Priority: world accomplishments (quests, named monsters, nests) are worth far more than trash.

## A nest destroyed (paid once, when it breaks, not when the quest is handed in).
const NEST_XP := 18
## The standing Crypt Road quest, paid on hand-in (the offer carries it as "xp"; see TownState.crypt_road_offer).
const STANDING_QUEST_XP := 120
## A named monster killed: NAMED_BASE_XP + NAMED_PER_LEVEL x its own level, + NEMESIS_PER_KILL for every time it has killed the hero,
## + PLOT_BONUS_XP if it had a plot under way (the player stopped a live threat).
const NAMED_BASE_XP := 40
const NAMED_PER_LEVEL := 20
const NEMESIS_PER_KILL := 25
const PLOT_BONUS_XP := 25

## `--xplog`: print why XP was paid (developer only).
static var logging: bool = false

## XP for one kill: the enemy's own base value times the threat it was killed at (a stronger version is worth more), at least 1 for any
## enemy that is worth something at all. An enemy worth 0 stays worth 0.
static func kill_xp(base_xp: int, source_threat: float) -> int:
	if base_xp <= 0:
		return 0
	return maxi(int(round(float(base_xp) * maxf(source_threat, 0.0))), 1)

## The extra XP for killing a named monster of this level, which has killed the hero `hero_kills` times, with or without a plot going.
static func named_xp(level: float, hero_kills: int, has_plot: bool) -> int:
	return NAMED_BASE_XP + int(round(NAMED_PER_LEVEL * level)) + NEMESIS_PER_KILL * maxi(hero_kills, 0) + (PLOT_BONUS_XP if has_plot else 0)

static func log_xp(text: String) -> void:
	if logging:
		print("[xp] ", text)
