class_name DungeonMonsterGenerator
extends RefCounted
## Fills the dungeon level scene's EnemyGroups with a fresh set of monster groups (DungeonEnemyGroup markers), from a plan of how many
## groups each area gets, what they are made of and what they do. Developer tool (see tools/generate_dungeon_monsters.gd): geometry, props
## and chests in the scene are left alone. Groups stand on floor tiles that exist in the scene (so a room you cut is respected), away
## from props, chests and the start. Everything the generator makes is an ordinary marker: tweak any of it in the editor afterwards
## (level, patrol route, spawn points).

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

## One row per area (index into TestDungeon.AREAS): `groups` how many groups, `pool` {kind: weight} for each member, `size` [min, max]
## members per group, `wander` the chance a group strolls about its home instead of standing guard, `fixed` groups always placed
## ([[kind, count], ...] each). `density` (the tool's option) scales `groups`. The default plan is close to what the level shipped with (about 75 monsters; the shipped level has 85).
const PLAN: Array = [
	{"groups": 5, "pool": {"zombie": 6, "ghoul": 1}, "size": [1, 2], "wander": 0.0},
	{"groups": 2, "pool": {"zombie": 2, "ghoul": 1}, "size": [1, 2], "wander": 0.0},
	{"groups": 5, "pool": {"zombie": 8, "ghoul": 2, "rock_thrower": 2}, "size": [1, 3], "wander": 0.4},
	{"groups": 1, "pool": {"zombie": 1}, "size": [2, 2], "wander": 0.0},
	{"groups": 5, "pool": {"zombie": 5, "ghoul": 3, "rock_thrower": 2}, "size": [1, 3], "wander": 0.4},
	{"groups": 1, "pool": {"zombie": 1, "ghoul": 1}, "size": [2, 2], "wander": 0.0},
	{"groups": 5, "pool": {"zombie": 9, "ghoul": 2, "rock_thrower": 1}, "size": [1, 3], "wander": 0.4},
	{"groups": 1, "pool": {"zombie": 1, "rock_thrower": 1}, "size": [2, 2], "wander": 0.0},
	{"groups": 7, "pool": {"zombie": 7, "ghoul": 5, "rock_thrower": 2, "brute": 1}, "size": [1, 3], "wander": 0.3},
	{"groups": 1, "pool": {"zombie": 1, "ghoul": 1}, "size": [2, 2], "wander": 0.0},
	{"groups": 6, "pool": {"zombie": 6, "ghoul": 5, "rock_thrower": 4, "brute": 2}, "size": [1, 3], "wander": 0.2,
		"fixed": [[["warden", 1]]]},
]

const MIN_FROM_START := 14.0
const MIN_FROM_PROP := 2.0
const MIN_FROM_CHEST := 3.0
const MIN_BETWEEN_GROUPS := 4.0


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
	var taken: Array[Vector2] = []
	var made: int = 0
	for area in PLAN.size():
		var plan: Dictionary = PLAN[area]
		var tiles: Array[Vector2] = _tiles_of_area(level_root, area)
		if tiles.is_empty():
			continue
		var wanted: int = maxi(int(round(float(plan["groups"]) * density)), 0)
		var rows: Array = []
		for i in wanted:
			rows.append(_random_group(plan, rng))
		for fixed in plan.get("fixed", []):
			rows.append(fixed)
		for kinds in rows:
			var spot: Vector2 = _pick_spot(tiles, Vector2(start.x, start.z), props, chests, taken, rng)
			if spot == Vector2.INF:
				continue
			taken.append(spot)
			var marker := DungeonEnemyGroup.new()
			made += 1
			marker.name = "Group%02d_area%d" % [made, area]
			marker.position = Vector3(spot.x, 0.0, spot.y)
			marker.area = area
			marker.kinds = kinds
			var mode_roll: float = rng.randf()
			marker.behaviour = DungeonEnemyGroup.Behaviour.WANDER if mode_roll < float(plan["wander"]) else DungeonEnemyGroup.Behaviour.STAND_GUARD
			holder.add_child(marker)
			marker.owner = level_root
	return made


## One group's [kind, count] pairs: a random size, each member drawn from the area's weighted pool.
static func _random_group(plan: Dictionary, rng: RandomNumberGenerator) -> Array:
	var size_range: Array = plan["size"]
	var members: int = rng.randi_range(int(size_range[0]), int(size_range[1]))
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
	var out: Array = []
	for kind in counts:
		out.append([kind, counts[kind]])
	return out


## The floor tile centres that lie in one of the area's rooms (rooms as drawn in DungeonBaker.ROOMS).
static func _tiles_of_area(level_root: Node3D, area: int) -> Array[Vector2]:
	var rects: Array[Rect2] = []
	for key in AREA_ROOMS[area]:
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
		if spot.distance_to(start) < MIN_FROM_START:
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
