class_name XpEstimator
extends RefCounted
## Dev tool: how much XP a fresh party earns along the Crypt Road, from the real `RoadEncounterRoster` rows and the real XP rules
## (`HeroProgression.monster_xp_value`, party bonus, level gap), and so when it reaches each level. It does not fight: bodies die in road
## order, the party earns each one's whole pool (no overkill waste) and walks at WALK_SPEED between groups. Used to tune
## `HeroProgression.EARLY_LEVEL_XP` (the Level 5 target) and to keep a test on it.

## Bodies per authored row after the denser packs (lane P2: about +50 % per group). 1.0 is the roster as it stands.
const DENSITY := 1.5
## Seconds the party spends killing one body, on top of walking (assumption: two fighters, 2-3 s a zombie-class body).
const FIGHT_SECONDS_PER_BODY := 3.0
const WALK_SPEED := 4.5
## "The end of the opening road" for the Level 5 target: the intro, graveyard and wooded stretches, before the courtyard
## (the segment bounds in world_tests.gd). Level 5 must come before the party gets here.
const OPENING_ROAD_END_Z := -40.0
const PARTY_SIZE := 2

static func _tier(kind: String, row_tier: String) -> String:
	if row_tier != "":
		return row_tier
	return String(load("res://data/enemies/%s.tres" % kind).tier)

## Every body on the road as {z, level, tier}, nearest the town first (high z). `density` repeats each row's kinds round-robin to
## round(count x density) bodies; the rows' own tier/level are kept.
static func bodies(density: float = DENSITY) -> Array:
	var rows: Array = []
	for beat in RoadEncounterRoster.BEATS:
		rows.append([float(beat[1]), int(beat[2]), String(beat[3]), beat[4]])
	rows.append([58.0, 2, "trivial", ["zombie", "zombie"]])   # the two side groups RoadEncounterRoster.spawn adds
	rows.append([52.0, 2, "trivial", ["zombie", "zombie"]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for row in rows:
		var kinds: Array = row[3]
		var n: int = maxi(int(round(float(kinds.size()) * density)), 1)
		for i in n:
			out.append({"z": row[0], "level": row[1], "tier": _tier(String(kinds[i % kinds.size()]), row[2])})
	return out

## Walks the road. Returns {"levels": {level: {"seconds", "xp", "bodies", "z"}}, "total_xp", "bodies", "seconds"} for the hero.
static func run(density: float = DENSITY) -> Dictionary:
	var xp: float = 0.0
	var level: int = 1
	var seconds: float = 0.0
	var reached: Dictionary = {}
	var list: Array = bodies(density)
	var z: float = float(list[0]["z"]) if not list.is_empty() else 0.0
	var count: int = 0
	for b in list:
		seconds += absf(z - float(b["z"])) / WALK_SPEED + FIGHT_SECONDS_PER_BODY
		z = float(b["z"])
		count += 1
		var pool: float = HeroProgression.monster_xp_value(int(b["level"]), String(b["tier"]))
		var each: float = pool * float(HeroProgression.PARTY_BONUS[PARTY_SIZE]) / float(PARTY_SIZE)
		xp += each * HeroProgression.level_gap_mult(HeroProgression.gap_level(level), int(b["level"]))
		while level < HeroProgression.MAX_LEVEL and int(xp) >= HeroProgression.xp_for_level(level + 1):
			level += 1
			reached[level] = {"seconds": seconds, "xp": int(xp), "bodies": count, "z": z}
	return {"levels": reached, "total_xp": int(xp), "bodies": count, "seconds": seconds, "level": level}
