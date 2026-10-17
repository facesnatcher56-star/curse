class_name RoadEncounterRoster
extends RefCounted
## Authored pacing, not a copy of DS2's map. Shared DS2 level/tier calculations remain unchanged.
## Every row is exactly one body. Gaps are intentional recovery space, never filled procedurally.
## The opening road (z above 110) stays light: trivial and weak fighters only, no brutes, elites, acid or priests.
## Deeper stretches add roaming groups ("wander"), rock throwers, brutes guarding the wooded choke and the third nest's
## approach, and a warden elite before the forecourt. Acid spitters and plague priests are still excluded from the road.
## Row: [id, z, monster level, tier ("" = the kind's own), kinds (one body each), mode ("" guard, "wander" roam)].
## Curse pacing (departs from DS2, see docs/COMBAT_REFERENCE.md): bigger packs, so fights are denser and there is less walking.
const PACK_MIN := 4   # a regular pack holds at least this many bodies ...
const PACK_MAX := 8   # ... and at most this many
const SEGMENT_CAP := 30   # most bodies one stretch of road holds at once (its own spawn budget)
const TOTAL_CAP := 100
const MAX_WALK_SECONDS_BETWEEN_PACKS := 9.0   # about 8-10 s: the longest walk along the road with no pack in view ...
const HERO_RUN_SPEED := 4.5   # ... at the hero's DS2 run speed (m/s)
const PACK_ROW_SPACING := 2.2   # metres between neighbours in a pack's two staggered rows
const BEATS: Array = [
	[1, 153, 1, "trivial", ["zombie", "zombie", "zombie", "zombie"], ""],
	[2, 133, 1, "trivial", ["zombie", "zombie", "zombie", "zombie"], ""],
	[3, 111, 1, "trivial", ["zombie", "zombie", "zombie", "zombie"], ""],
	[16, 124, 1, "trivial", ["zombie", "zombie", "zombie", "zombie"], "wander"],
	[4, 87, 1, "trivial", ["zombie", "zombie", "zombie", "zombie"], ""],
	[17, 98, 2, "weak", ["zombie", "ghoul", "zombie", "ghoul"], "wander"],
	[18, 76, 2, "weak", ["rock_thrower", "zombie", "ghoul", "zombie"], ""],
	[5, 64, 1, "trivial", ["zombie", "zombie", "zombie", "zombie"], ""],
	[19, 46, 3, "", ["brute", "zombie", "zombie", "zombie"], ""],
	[9, 34, 2, "weak", ["zombie", "rock_thrower", "zombie", "zombie"], ""],
	[20, 24, 3, "weak", ["ghoul", "zombie", "ghoul", "zombie"], "wander"],
	[21, 14, 4, "", ["brute", "zombie", "zombie", "zombie", "zombie"], ""],
	[11, 6, 2, "weak", ["zombie", "zombie", "zombie", "zombie", "zombie"], ""],
	[12, -23, 2, "trivial", ["zombie", "zombie", "zombie", "zombie"], ""],
	[22, -36, 3, "weak", ["rock_thrower", "zombie", "zombie", "zombie"], ""],
	[13, -53, 2, "weak", ["zombie", "rock_thrower", "zombie", "zombie"], ""],
	[23, -68, 4, "weak", ["ghoul", "zombie", "rock_thrower", "zombie"], "wander"],
	[14, -83, 2, "weak", ["zombie", "zombie", "zombie", "zombie"], ""],
	[24, -92, 5, "", ["zombie", "brute", "ghoul", "zombie", "zombie"], ""],
	[15, -114, 3, "trivial", ["zombie", "zombie", "zombie", "zombie"], ""],
	[25, -128, 6, "", ["warden", "zombie", "zombie", "zombie", "zombie"], ""],
	[27, -146, 3, "weak", ["zombie", "zombie", "zombie", "zombie"], ""],
]
## The two groups guarding the side nests (ids 6 and 8): packs like any other.
const NEST_GUARDS: Array = [
	[6, -21.0, 58.0, 2, "trivial", 4],
	[8, 20.0, 52.0, 2, "trivial", 4],
]

## Members of a pack laid out in two staggered rows round (x, z), so a bigger pack stays compact instead of stretching across the road.
static func pack_spots(x: float, z: float, count: int) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var columns: int = ceili(float(count) / 2.0)
	for i in count:
		var row: int = i / columns
		var col: int = i % columns
		var in_row: int = columns if row == 0 else count - columns
		spots.append(Vector2(x + (float(col) - float(in_row - 1) * 0.5) * PACK_ROW_SPACING, z + (float(row) - 0.5) * PACK_ROW_SPACING))
	return spots

static func spawn(road: CryptRoad, ids: Array = []) -> void:
	for beat in BEATS:
		if not ids.is_empty() and not int(beat[0]) in ids: continue
		var z := float(beat[1])
		var x := road.road_centre_x(z)
		var kinds: Array = beat[4]
		var count: int = kinds.size()
		var members: Array = []
		var spots: Array[Vector2] = pack_spots(x, z, count)
		for i in count:
			members.append([String(kinds[i]), spots[i].x, spots[i].y, beat[2], beat[3]])
		var roaming: bool = String(beat[5]) == "wander"
		road._group(int(beat[0]), String(beat[5]), members, Vector2(x, z), 6.0 if roaming else 0.0)
	# Side objectives have their own small groups, no linked distant reinforcements.
	for guard in NEST_GUARDS:
		if not ids.is_empty() and not int(guard[0]) in ids: continue
		var spots: Array[Vector2] = pack_spots(float(guard[1]), float(guard[2]), int(guard[5]))
		var members: Array = []
		for spot in spots:
			members.append(["zombie", spot.x, spot.y, guard[3], guard[4]])
		road._group(int(guard[0]), "", members, Vector2(float(guard[1]), float(guard[2])), 0.0)
	if not ids.is_empty() and not 27 in ids: return
	if is_instance_valid(road.forecourt_climax): road.forecourt_climax.queue_free()
	var clear := CryptForecourtClimax.new()
	clear.name = "CryptForecourtClimax"
	road.add_child(clear)
	clear.setup(road, road.director)
	road.forecourt_climax = clear
