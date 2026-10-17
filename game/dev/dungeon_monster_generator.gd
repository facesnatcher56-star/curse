class_name DungeonMonsterGenerator
extends RefCounted
## Fills the dungeon level scene's EnemyGroups with a fresh set of monster packs (DungeonEnemyGroup markers), from a plan of where packs
## stand, what they are made of and what they do. Developer tool (see tools/generate_dungeon_monsters.gd): geometry, props and chests in the
## scene are left alone. Packs stand on floor tiles that exist in the scene (so a room you cut is respected), away from props and chests.
## Everything the generator makes is an ordinary marker: tweak any of it in the editor afterwards (level, patrol route, spawn points).
##
## Curse pacing (departs from DS2, see docs/COMBAT_REFERENCE.md): packs of PACK_MIN..PACK_MAX regulars stand along the critical path
## (TestDungeon.CRITICAL_PATH) every PATH_PACK_SPACING metres, so there is never more than a few seconds' walk without a pack in view, plus
## some packs in the side spaces. From ELITE_FROM_AREA on about 1 pack in 5 carries a brute; Champion.roll_pack adds the usual champion chance.

## The walkable spaces of each area (names from DungeonBaker.ROOMS: the area's hall or corridor and the side spaces off it).
const AREA_ROOMS: Array = [
	["entry", "alcove_w0", "cave_link", "cave_a", "cave_b", "cave_c"],
	["corridor_1", "alcove_k1w"],
	["hall_1", "treasure_h1s", "alcove_h1e", "chamber_h1n"],
	["corridor_2"],
	["hall_2", "alcove_h2w", "treasure_h2s", "chamber_h2e"],
	["corridor_3"],
	["hall_3", "alcove_h3n", "cave_h3a", "cave_h3b", "cave_h3c", "treasure_h3e"],
	["corridor_4"],
	["hall_4", "alcove_h4w", "treasure_h4n", "chamber_h4s", "alcove_h4e"],
	["corridor_5"],
	["hall_5", "alcove_h5w", "alcove_h5e", "treasure_vault", "chamber_h5s"],
]

const PACK_MIN := 4
const PACK_MAX := 8
const PATH_PACK_SIZE: Array[int] = [4, 7]   # packs on the way in are a little smaller than the biggest side-space ambush
const SIDE_PACK_SIZE: Array[int] = [4, 6]
const PATH_PACK_SPACING := 26.0   # metres of walking between pack homes along the critical path: about 6 s at the hero's run speed
const FIRST_PACK_DISTANCE := 9.0   # the first pack stands this far (along the path) from the start: in sight on spawn
const FIRST_PACK: Array = [["zombie", 4]]
const ELITE_FROM_AREA := 6        # hall_3 on: earlier areas carry no brute
const ELITE_CHANCE := 0.2
## One row per area (index into TestDungeon.AREAS): `pool` {kind: weight} for each member, `side` how many packs the area's side spaces get,
## `wander` the chance a pack strolls about its home instead of standing guard, `fixed` packs always placed at the path's end
## ([[kind, count], ...] each). `density` (the tool's option) scales the side packs and tightens or loosens the path spacing.
const PLAN: Array = [
	{"side": 1, "pool": {"zombie": 6, "ghoul": 1}, "wander": 0.0},
	{"side": 0, "pool": {"zombie": 2, "ghoul": 1}, "wander": 0.0},
	{"side": 2, "pool": {"zombie": 8, "ghoul": 2, "rock_thrower": 2}, "wander": 0.4},
	{"side": 0, "pool": {"zombie": 1}, "wander": 0.0},
	{"side": 1, "pool": {"zombie": 5, "ghoul": 3, "rock_thrower": 2}, "wander": 0.4},
	{"side": 0, "pool": {"zombie": 1, "ghoul": 1}, "wander": 0.0},
	{"side": 2, "pool": {"zombie": 9, "ghoul": 2, "rock_thrower": 1}, "wander": 0.4},
	{"side": 0, "pool": {"zombie": 1, "rock_thrower": 1}, "wander": 0.0},
	{"side": 1, "pool": {"zombie": 7, "ghoul": 5, "rock_thrower": 2}, "wander": 0.3},
	{"side": 0, "pool": {"zombie": 1, "ghoul": 1}, "wander": 0.0},
	{"side": 1, "pool": {"zombie": 6, "ghoul": 5, "rock_thrower": 4}, "wander": 0.2,
		"fixed": [[["warden", 1], ["zombie", 2], ["rock_thrower", 1], ["ghoul", 1]]]},
]

const MIN_FROM_PROP := 2.0
const MIN_FROM_CHEST := 3.0
const MIN_BETWEEN_GROUPS := 4.0
const MAX_FROM_FLOOR := 1.8   # a path pack's home must stand this close to a floor tile


## Replaces the EnemyGroups of `level_root` (an instance of the level scene, not necessarily in the tree) and returns how many groups it made.
static func generate(level_root: Node3D, rng_seed: int, density: float = 1.0) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var holder: Node3D = level_root.get_node("EnemyGroups")
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()
	var start: Vector3 = (level_root.get_node("PlayerStart") as Node3D).position
	var props: Array[Vector2] = _points_under(level_root, ["Props", "Pillars"])
	var chests: Array[Vector2] = _points_under(level_root, ["Chests"])
	var floor_tiles: Array[Vector2] = _points_under(level_root, ["Floor"])
	var taken: Array[Vector2] = []
	var made: int = 0
	# Rows in placement order: the end of the path first (its fixed boss pack), then the way in, then the side spaces.
	var rows: Array = []   # {area, kinds, spot (Vector2.INF = a side space), wanders}
	var last_area: int = PLAN.size() - 1
	for fixed in PLAN[last_area].get("fixed", []):
		rows.append({"area": last_area, "kinds": fixed, "spot": TestDungeon.path_point(TestDungeon.path_length()), "wanders": false})
	var spacing: float = PATH_PACK_SPACING / maxf(density, 0.1)
	var along: float = FIRST_PACK_DISTANCE
	var total: float = TestDungeon.path_length()
	var first: bool = true
	while along < total - spacing * 0.35:
		var here: Vector2 = TestDungeon.path_point(along)
		var area: int = _area_at(here)
		var kinds: Array = FIRST_PACK.duplicate(true) if first else _random_group(PLAN[area], rng, PATH_PACK_SIZE, area)
		first = false
		rows.append({"area": area, "kinds": kinds, "spot": here, "wanders": rng.randf() < float(PLAN[area]["wander"])})
		along += spacing
	for area in PLAN.size():
		for i in maxi(int(round(float(PLAN[area]["side"]) * density)), 0):
			rows.append({"area": area, "kinds": _random_group(PLAN[area], rng, SIDE_PACK_SIZE, area), "spot": Vector2.INF,
				"wanders": rng.randf() < float(PLAN[area]["wander"])})
	for row in rows:
		var area: int = int(row["area"])
		var spot: Vector2 = _place(row, level_root, floor_tiles, props, chests, taken, start, rng)
		if spot == Vector2.INF:
			continue
		taken.append(spot)
		var marker := DungeonEnemyGroup.new()
		made += 1
		marker.name = "Group%02d_area%d" % [made, area]
		marker.position = Vector3(spot.x, 0.0, spot.y)
		marker.area = area
		marker.kinds = row["kinds"]
		var members: int = 0
		for pair in marker.kinds:
			members += int(pair[1])
		marker.spread = clampf(0.9 + 0.3 * float(members), 1.6, 3.0)
		marker.behaviour = DungeonEnemyGroup.Behaviour.WANDER if bool(row["wanders"]) else DungeonEnemyGroup.Behaviour.STAND_GUARD
		holder.add_child(marker)
		marker.owner = level_root
	return made


## Where a pack stands: a path pack on (or beside) its point of the path, a side pack on a random floor tile of the area's side spaces.
static func _place(row: Dictionary, level_root: Node3D, floor_tiles: Array[Vector2], props: Array[Vector2], chests: Array[Vector2],
		taken: Array[Vector2], start: Vector3, rng: RandomNumberGenerator) -> Vector2:
	var centre: Vector2 = row["spot"]
	if centre == Vector2.INF:
		var tiles: Array[Vector2] = _tiles_of_area(level_root, int(row["area"]), true)
		if tiles.is_empty():
			return Vector2.INF
		return _pick_spot(tiles, Vector2(start.x, start.z), props, chests, taken, rng)
	for attempt in 40:
		var jitter: float = 0.0 if attempt == 0 else 0.5 + attempt * 0.1
		var spot: Vector2 = centre + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		if _near_any(spot, floor_tiles, MAX_FROM_FLOOR) and not _near_any(spot, props, MIN_FROM_PROP) \
				and not _near_any(spot, chests, MIN_FROM_CHEST) and not _near_any(spot, taken, MIN_BETWEEN_GROUPS):
			return spot
	return Vector2.INF


## Which area (index into AREAS) a ground point is in: the critical-path room that holds it, else the nearest one.
static func _area_at(point: Vector2) -> int:
	var best: int = 0
	var best_distance: float = INF
	for i in TestDungeon.AREAS.size():
		var room: Rect2 = DungeonBaker.ROOMS[TestDungeon.AREAS[i]]
		var distance: float = Vector2(clampf(point.x, room.position.x, room.end.x), clampf(point.y, room.position.y, room.end.y)).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## One pack's [kind, count] pairs: a random size, each member drawn from the area's weighted pool; from ELITE_FROM_AREA on, one pack in
## five swaps a member for a brute.
static func _random_group(plan: Dictionary, rng: RandomNumberGenerator, size_range: Array[int], area: int) -> Array:
	var members: int = rng.randi_range(size_range[0], size_range[1])
	var counts: Dictionary = {}
	var pool: Dictionary = plan["pool"]
	var total: float = 0.0
	for kind in pool:
		total += float(pool[kind])
	for i in members:
		var roll: float = rng.randf() * total
		for kind in pool:
			roll -= float(pool[kind])
			if roll <= 0.0:
				counts[kind] = int(counts.get(kind, 0)) + 1
				break
	if area >= ELITE_FROM_AREA and rng.randf() < ELITE_CHANCE:
		var biggest: String = ""
		for kind in counts:
			if biggest == "" or int(counts[kind]) > int(counts[biggest]):
				biggest = String(kind)
		counts[biggest] = int(counts[biggest]) - 1
		if int(counts[biggest]) <= 0:
			counts.erase(biggest)
		counts["brute"] = 1
	var out: Array = []
	for kind in counts:
		out.append([kind, counts[kind]])
	return out


## The floor tile centres that lie in one of the area's rooms (rooms as drawn in DungeonBaker.ROOMS); `side_only` leaves out the
## area's own hall or corridor (the first room), keeping the side spaces.
static func _tiles_of_area(level_root: Node3D, area: int, side_only: bool = false) -> Array[Vector2]:
	var rects: Array[Rect2] = []
	var keys: Array = AREA_ROOMS[area]
	for key in (keys.slice(1) if side_only else keys):
		rects.append(DungeonBaker.ROOMS[key])
	var tiles: Array[Vector2] = []
	for tile in level_root.get_node("Floor").get_children():
		var spot := Vector2((tile as Node3D).position.x, (tile as Node3D).position.z)
		for rect in rects:
			if rect.grow(-1.5).has_point(spot):
				tiles.append(spot)
				break
	return tiles


static func _points_under(level_root: Node3D, groups: Array) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for group_name in groups:
		for child in level_root.get_node(String(group_name)).get_children():
			points.append(Vector2((child as Node3D).position.x, (child as Node3D).position.z))
	return points


static func _pick_spot(tiles: Array[Vector2], start: Vector2, props: Array[Vector2], chests: Array[Vector2], taken: Array[Vector2],
		rng: RandomNumberGenerator) -> Vector2:
	for attempt in 80:
		var spot: Vector2 = tiles[rng.randi() % tiles.size()] + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if spot.distance_to(start) < PATH_PACK_SPACING * 0.5:
			continue
		if _near_any(spot, props, MIN_FROM_PROP) or _near_any(spot, chests, MIN_FROM_CHEST) or _near_any(spot, taken, MIN_BETWEEN_GROUPS):
			continue
		return spot
	return Vector2.INF


static func _near_any(spot: Vector2, points: Array[Vector2], distance: float) -> bool:
	for p in points:
		if spot.distance_to(p) < distance:
			return true
	return false
