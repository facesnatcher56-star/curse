class_name HeroProgression
extends RefCounted
## The rules of the hero's permanent level, and nothing else: no state, no saving, no UI. `TownState` owns the hero's total XP and
## asks this class what level that is; the character screen asks it what to show. The one place the curve lives.

## The level cap (DS2's `Uber`, max 100). Everything that needs it reads this; nothing else spells the number out.
## The stored level cap: DS2's Uber is capped at level 100, counted from 0, so the table has 101 rows and Curse stores 1-based, 101.
const MAX_LEVEL := 101
## The old interpolated curve (saves of versions 7-9) stopped at 100 rows.
const LEGACY_MAX_LEVEL := 100

## Previous interpolated curve, retained ONLY to preserve progress while migrating version 7-9 saves.
const DS2_SAMPLES := {1: 0, 2: 300, 5: 4000, 10: 34200, 20: 196000, 30: 663000, 40: 1990000, 50: 5740000, 60: 16400000,
	70: 46700000, 80: 133000000, 90: 377000000, 100: 1070000000}

static var _table: PackedInt64Array = PackedInt64Array()
static var _legacy_table: PackedInt64Array = PackedInt64Array()

## Total lifetime XP needed to BE each level, level 1 first (index 0).
static func table() -> PackedInt64Array:
	if _table.is_empty():
		_table = PackedInt64Array(JSON.parse_string(FileAccess.get_file_as_string("res://data/reference/ds2_xp.json")))
	return _table

static func legacy_table() -> PackedInt64Array:
	if _legacy_table.is_empty():
		var points: Array = DS2_SAMPLES.keys()
		points.sort()
		_legacy_table.resize(LEGACY_MAX_LEVEL)
		for level in range(1, LEGACY_MAX_LEVEL + 1):
			if DS2_SAMPLES.has(level):
				_legacy_table[level - 1] = int(DS2_SAMPLES[level])
				continue
			var below: int = 1
			var above: int = LEGACY_MAX_LEVEL
			for p in points:
				if int(p) < level:
					below = int(p)
				elif int(p) > level:
					above = int(p)
					break
			var lo: float = float(DS2_SAMPLES[below])
			var hi: float = float(DS2_SAMPLES[above])
			var t: float = float(level - below) / float(above - below)
			_legacy_table[level - 1] = int(round(lo * pow(hi / lo, t)))
	return _legacy_table

## Keep the level and fraction earned when replacing the approximate curve with the extracted table.
static func migrate_interpolated_xp(xp: int) -> int:
	var old: PackedInt64Array = legacy_table()
	var index: int = 0
	while index < LEGACY_MAX_LEVEL - 1 and xp >= old[index + 1]:
		index += 1
	if index == LEGACY_MAX_LEVEL - 1:
		return max_xp()
	var fraction: float = clampf(float(xp - old[index]) / float(old[index + 1] - old[index]), 0.0, 1.0)
	return table()[index] + int(fraction * float(table()[index + 1] - table()[index]))

## The most XP a hero can hold: exactly what level MAX_LEVEL takes. XP earned past it is not kept.
static func max_xp() -> int:
	return table()[MAX_LEVEL - 1]

## Total XP needed to be this level (the level is clamped to 1..MAX_LEVEL).
static func xp_for_level(level: int) -> int:
	return table()[clampi(level, 1, MAX_LEVEL) - 1]

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
	var t: PackedInt64Array = table()
	while level < MAX_LEVEL and xp >= t[level]:
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

# --- What the world pays in XP (DS2, section 5) ------------------------------------------------------------------------------------
# Hits pay the monster's DS2 XP pool hit by hit (XpShare), times the level-gap multiplier, split over the party (the hero and Cutter)
# with DS2's group bonus.

## DS2 monster tiers and what their XP is multiplied by.
const TIER_XP := {"trivial": 0.42, "weak": 0.80, "normal": 1.0, "strong": 1.25, "miniboss": 3.33}

## DS2 party bonus by the number of members who level; each gets bonus / members of what a lone hero would.
const PARTY_BONUS := [1.0, 1.0, 1.80, 2.43, 2.92]

## A nest destroyed pays a miniboss of its level; the standing quest a fixed sum. Named monsters pay a miniboss of their level, plus
## NEMESIS_PER_KILL for every time one has killed the hero and PLOT_BONUS_XP if it had a plot under way. (Curse choices, DS2 scale.)
const STANDING_QUEST_XP := 3000
const NEMESIS_PER_KILL := 400
const PLOT_BONUS_XP := 400

## `--xplog`: print why XP was paid (developer only).
static var logging: bool = false

## DS2's XP value of a monster, unrounded (its template's `experience_value`, actor_evil_*.gas): below level 12 `base + slope x L`, from
## level 12 `curve x 1.11^L / (5.4 (L + 10))`, with each tier's own constants as the templates give them (weak is 0.75 of normal below
## level 12 but 0.8 of it above; trivial and miniboss are 0.42 and 3.33 of normal). This is the pool its hits drain (see XpShare).
const TIER_VALUE := {
	"trivial": [20.0, 5.0, 2722.0], "weak": [36.0, 9.0, 5184.0], "normal": [48.0, 12.0, 6480.0],
	"strong": [60.0, 15.0, 8100.0], "miniboss": [160.0, 40.0, 21600.0],
}

static func monster_xp_value(level: int, tier: String = "normal") -> float:
	var l: int = maxi(level, 0)
	var t: Array = TIER_VALUE.get(tier, TIER_VALUE["normal"])
	return float(t[0]) + float(t[1]) * l if l < 12 else float(t[2]) * pow(1.11, l) / (5.4 * (l + 10))

static func monster_xp(level: int, tier: String = "normal") -> int:
	return maxi(int(round(monster_xp_value(level, tier))), 1)

## DS2 counts character level from 0 (a fresh hero is "Level 0", the first level-up at 300 XP makes it 1). Curse's stored level counts
## from 1, so everything the player reads (`display_level`) and the level gap (`gap_level`) goes through here to show DS2's number.
static func gap_level(character_level: int) -> int:
	return maxi(character_level - 1, 0)

## The character level as the player sees it: DS2's, from 0.
static func display_level(character_level: int) -> int:
	return gap_level(character_level)

## DS2's level-gap multiplier (hero level - monster level): more than 4 above, -20% a level; more than 4 below, -20% a level too
## (DS2 penalises both, so neither farming nor carrying pays); never under 5%.
static func level_gap_mult(hero_level: int, monster_level: int) -> float:
	var gap: int = hero_level - monster_level
	var mult: float = 1.0
	if gap > 4:
		mult = 1.0 - 0.2 * (gap - 4)
	elif gap < -4:
		mult = 1.0 + 0.2 * (gap + 4)
	return maxf(mult, 0.05)

## What each member of a party of `members` gets of a kill worth `xp` to a lone hero.
static func party_share(xp: int, members: int) -> int:
	var n: int = clampi(members, 1, PARTY_BONUS.size() - 1)
	return int(round(float(xp) * float(PARTY_BONUS[n]) / float(n)))

## What a nest of this monster level is worth: the two trivial zombies that claw out of it (DS2: a breakable generator pays its
## children's `experience_value`; Curse's nest releases them as it breaks and they pay when killed, so breaking the nest pays nothing itself).
static func nest_xp(level: int) -> int:
	return 2 * monster_xp(level, "trivial")

## A named monster of this monster level, which has killed the hero `hero_kills` times, with or without a plot going.
static func named_xp(level: int, hero_kills: int, has_plot: bool) -> int:
	return monster_xp(level, "miniboss") + NEMESIS_PER_KILL * maxi(hero_kills, 0) + (PLOT_BONUS_XP if has_plot else 0)

static func log_xp(text: String) -> void:
	if logging:
		print("[xp] ", text)
