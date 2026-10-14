class_name RoadEncounterRoster
extends RefCounted
## Authored pacing, not a copy of DS2's map. Shared DS2 level/tier calculations remain unchanged.
## Every row is exactly one body. Gaps are intentional recovery space, never filled procedurally.
## The opening road (z above 110) stays light: trivial and weak fighters only, no brutes, elites, acid or priests.
## Deeper stretches add roaming groups ("wander"), rock throwers, brutes guarding the wooded choke and the third nest's
## approach, and a warden elite before the forecourt. Acid spitters and plague priests are still excluded from the road.
## Row: [id, z, monster level, tier ("" = the kind's own), kinds (one body each), mode ("" guard, "wander" roam)].
const SEGMENT_CAP := 18   # most bodies one stretch of road holds at once (its own spawn budget)
const TOTAL_CAP := 64
const BEATS: Array = [
	[1, 153, 1, "trivial", ["zombie", "zombie"], ""],
	[2, 133, 1, "trivial", ["zombie", "zombie", "zombie"], ""],
	[3, 111, 1, "trivial", ["zombie", "zombie", "zombie"], ""],
	[16, 124, 1, "trivial", ["zombie", "zombie"], "wander"],
	[4, 87, 1, "trivial", ["zombie", "zombie", "zombie"], ""],
	[17, 98, 2, "weak", ["zombie", "ghoul", "zombie"], "wander"],
	[18, 76, 2, "weak", ["rock_thrower", "zombie", "ghoul"], ""],
	[5, 64, 1, "trivial", ["zombie", "zombie", "zombie"], ""],
	[19, 46, 3, "", ["brute", "zombie"], ""],
	[9, 34, 2, "weak", ["zombie", "rock_thrower"], ""],
	[20, 24, 3, "weak", ["ghoul", "zombie", "ghoul"], "wander"],
	[21, 14, 4, "", ["brute", "zombie"], ""],
	[11, 6, 2, "weak", ["zombie", "zombie", "zombie"], ""],
	[12, -23, 2, "trivial", ["zombie", "zombie", "zombie"], ""],
	[22, -36, 3, "weak", ["rock_thrower", "zombie"], ""],
	[13, -53, 2, "weak", ["zombie", "rock_thrower"], ""],
	[23, -68, 4, "weak", ["ghoul", "zombie", "rock_thrower"], "wander"],
	[14, -83, 2, "weak", ["zombie", "zombie", "zombie"], ""],
	[24, -92, 5, "", ["zombie", "brute", "ghoul"], ""],
	[15, -114, 3, "trivial", ["zombie", "zombie", "zombie"], ""],
	[25, -128, 6, "", ["warden", "zombie"], ""],
	[27, -146, 3, "weak", ["zombie", "zombie"], ""],
]

static func spawn(road: CryptRoad, ids: Array = []) -> void:
	for beat in BEATS:
		if not ids.is_empty() and not int(beat[0]) in ids: continue
		var z := float(beat[1])
		var x := road.road_centre_x(z)
		var kinds: Array = beat[4]
		var count: int = kinds.size()
		var members: Array = []
		for i in count:
			members.append([String(kinds[i]), x + (float(i) - float(count - 1) * 0.5) * 2.5, z, beat[2], beat[3]])
		var roaming: bool = String(beat[5]) == "wander"
		road._group(int(beat[0]), String(beat[5]), members, Vector2(x, z), 6.0 if roaming else 0.0)
	# Side objectives have their own small groups, no linked distant reinforcements.
	if ids.is_empty() or 6 in ids: road._group(6, "", [["zombie", -20, 59, 2, "trivial"], ["zombie", -22, 56, 2, "trivial"]], Vector2(-21, 58), 0.0)
	if ids.is_empty() or 8 in ids: road._group(8, "", [["zombie", 19, 54, 2, "trivial"], ["zombie", 21, 51, 2, "trivial"]], Vector2(20, 52), 0.0)
	if not ids.is_empty() and not 27 in ids: return
	if is_instance_valid(road.forecourt_climax): road.forecourt_climax.queue_free()
	var clear := CryptForecourtClimax.new()
	clear.name = "CryptForecourtClimax"
	road.add_child(clear)
	clear.setup(road, road.director)
	road.forecourt_climax = clear
