class_name RoadEncounterRoster
extends RefCounted
## Authored pacing, not a copy of DS2's map. Shared DS2 level/tier calculations remain unchanged.
## Every row is exactly one body. Gaps are intentional recovery space, never filled procedurally.
## No acid, explosive bloaters, summoning priests or heavy-knockdown brutes on the opening road.
const BEATS: Array = [
	[1, 153, 1, "trivial", 2],
	[2, 133, 1, "trivial", 3],
	[3, 111, 1, "trivial", 3],
	[4, 87, 1, "trivial", 3],
	[5, 64, 1, "trivial", 3],
	[9, 34, 2, "weak", 2],
	[11, 6, 2, "weak", 3],
	[12, -23, 2, "trivial", 3],
	[13, -53, 2, "weak", 2],
	[14, -83, 2, "weak", 3],
	[15, -114, 3, "trivial", 3],
	[27, -146, 3, "weak", 2],
]

static func spawn(road: CryptRoad, ids: Array = []) -> void:
	for beat in BEATS:
		if not ids.is_empty() and not int(beat[0]) in ids: continue
		var z := float(beat[1])
		var x := road.road_centre_x(z)
		var members: Array = []
		for i in int(beat[4]):
			var kind := "rock_thrower" if int(beat[0]) in [9, 13] and i == int(beat[4]) - 1 else "zombie"
			members.append([kind, x + (float(i) - float(beat[4] - 1) * 0.5) * 2.0, z, beat[2], beat[3]])
		road._group(int(beat[0]), "", members, Vector2(x, z), 0.0)
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
