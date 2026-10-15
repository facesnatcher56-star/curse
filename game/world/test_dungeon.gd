class_name TestDungeon
extends CryptRoad
## The dungeon test level (`-- --dungeon`, issue #25; grown for issue #34, Lane J): a chain of halls and corridors that zig-zags north
## from the entry (the critical path, about 330 m to the final hall), with 25 side spaces (alcoves, treasure rooms, cave pockets) off it:
## 36 spaces, 85 enemies in groups, 5 chests, and about 160 barrels, crates and urns. It reuses CryptRoad's location plumbing (props put on the arena, one
## navigation bake, groups spawned by the director). The `--atmosphere` look is the shared AtmosphereProfile, which main applies to every
## location; this file only adds a brighter tune for the rooms. Without the flag nothing here runs.
##
## The plan (x, z, metres; north is -z, the hero starts at the south end). Each hall is crossed from one door to the other:
##   entry -> corridor_1 -> hall_1 -> corridor_2 -> hall_2 -> corridor_3 -> hall_3 -> corridor_4 -> hall_4 -> corridor_5 -> hall_5 (final)
## Side spaces hang off the chain (see ROOMS): the entry's alcove and cave, alcoves and treasure rooms in each hall, a cave south of hall_3.
##
## Enemy levels follow the hero, never higher (see project()): each area's enemies are the level the hero is projected to be when the
## hero reaches that area, counting the XP the dungeon yields along the critical path with HeroProgression's real tables.

const SITE := "test_dungeon"
const ARENA_HALF_X := 50.0
const ARENA_HALF_Z := 124.0
const START_POINT := Vector3(0.0, 0.0, 104.0)
const WALL_HEIGHT := 1.9
const CELL := 0.5
## The camera for this level only: fully zoomed-in is 2.0, and a new run starts at 1.5 (main sets these on the rig).
const ZOOM_MAX := 2.0
const ZOOM_START := 1.5
## Cutter is in the party: his share of every kill (DS2's party bonus, HeroProgression.party_share) is part of the hero's XP.
const PARTY_SIZE := 2
## How far the enemies of one group spread from its home, and how far they may roam from it (see CryptRoad._group).
const GROUP_SPREAD := 1.6
const GROUP_ROAM := 4.0

## Every walkable space as a rectangle: Rect2(x0, z0, width, depth). Two spaces that overlap or touch form an opening.
## The first eleven, in order, are the critical path (the areas); the rest are side spaces.
const ROOMS := {
	"entry": Rect2(-12, 92, 24, 16),
	"corridor_1": Rect2(6, 72, 6, 20),
	"hall_1": Rect2(-28, 56, 56, 16),
	"corridor_2": Rect2(-28, 40, 6, 16),
	"hall_2": Rect2(-36, 22, 66, 18),
	"corridor_3": Rect2(22, 4, 6, 18),
	"hall_3": Rect2(-36, -16, 66, 20),
	"corridor_4": Rect2(-32, -40, 6, 24),
	"hall_4": Rect2(-40, -64, 70, 24),
	"corridor_5": Rect2(18, -88, 6, 24),
	"hall_5": Rect2(-34, -110, 68, 22),
	"alcove_w0": Rect2(-18, 94, 6, 8),         # off the entry's west wall
	"cave_link": Rect2(12, 96, 4, 4),          # the way east out of the entry
	"cave_a": Rect2(16, 90, 8, 10),            # the cave: five overlapping pockets, so the outline is not a rectangle
	"cave_b": Rect2(19, 100, 5, 6),
	"cave_c": Rect2(16, 84, 6, 6),
	"treasure_h1s": Rect2(-24, 72, 10, 10),    # south of hall_1, west end
	"alcove_h1e": Rect2(28, 60, 6, 6),         # off hall_1's east end
	"chamber_h1n": Rect2(0, 46, 14, 10),       # north of hall_1
	"alcove_k1w": Rect2(0, 80, 6, 6),          # off corridor_1
	"alcove_h2w": Rect2(-42, 26, 6, 8),        # off hall_2's west end
	"treasure_h2s": Rect2(-30, 12, 10, 10),    # south of hall_2, west end
	"chamber_h2e": Rect2(30, 26, 8, 14),       # off hall_2's east end
	"alcove_h3n": Rect2(-12, -24, 8, 8),       # north of hall_3
	"cave_h3a": Rect2(-18, 4, 12, 8),          # the cave south of hall_3: three pockets
	"cave_h3b": Rect2(-12, 10, 6, 6),
	"cave_h3c": Rect2(-24, 4, 6, 4),
	"treasure_h3e": Rect2(30, -12, 10, 12),    # off hall_3's east end
	"alcove_h4w": Rect2(-48, -58, 8, 8),       # off hall_4's west end
	"treasure_h4n": Rect2(-36, -72, 10, 8),    # north of hall_4, west end
	"chamber_h4s": Rect2(-18, -40, 14, 10),    # south of hall_4
	"alcove_h4e": Rect2(30, -56, 6, 6),        # off hall_4's east end
	"alcove_h5w": Rect2(-40, -104, 6, 8),      # off the final hall's west end
	"alcove_h5e": Rect2(34, -100, 6, 8),       # off the final hall's east end
	"treasure_vault": Rect2(8, -120, 10, 10),  # north of the final hall
	"chamber_h5s": Rect2(-26, -88, 12, 10),    # south of the final hall, west end
}

## The critical path, in order. Area i is AREAS[i]: its enemies are met after the areas before it.
const AREAS: Array[String] = ["entry", "corridor_1", "hall_1", "corridor_2", "hall_2", "corridor_3", "hall_3", "corridor_4", "hall_4",
		"corridor_5", "hall_5"]

## DS2 tier of each kind as spawned here (the same tier its XP and life use: see Enemy.tier_override).
const KIND_TIER := {"zombie": "trivial", "ghoul": "weak", "rock_thrower": "weak", "brute": "strong", "warden": "miniboss"}

## Enemy groups: `area` (an index into AREAS), `mode` ("" stands at home, "wander" strolls about it), `home` (x, z), and `kinds`: [kind, count].
## Each member's level is its area's level from project(), so nothing here names a level.
const GROUPS: Array = [
	{"area": 0, "mode": "", "home": Vector2(0, 93), "kinds": [["zombie", 2]]},
	{"area": 0, "mode": "", "home": Vector2(-15, 98), "kinds": [["zombie", 1]]},
	{"area": 0, "mode": "", "home": Vector2(20, 94), "kinds": [["zombie", 2]]},
	{"area": 0, "mode": "", "home": Vector2(21.5, 103), "kinds": [["ghoul", 1]]},
	{"area": 0, "mode": "", "home": Vector2(19, 87), "kinds": [["zombie", 1]]},
	{"area": 1, "mode": "", "home": Vector2(9, 82), "kinds": [["ghoul", 1], ["zombie", 1]]},
	{"area": 1, "mode": "", "home": Vector2(3, 83), "kinds": [["zombie", 1]]},
	{"area": 2, "mode": "wander", "home": Vector2(-18, 64), "kinds": [["zombie", 2], ["ghoul", 1]]},
	{"area": 2, "mode": "wander", "home": Vector2(10, 64), "kinds": [["rock_thrower", 1], ["zombie", 2]]},
	{"area": 2, "mode": "", "home": Vector2(31, 63), "kinds": [["rock_thrower", 1]]},
	{"area": 2, "mode": "", "home": Vector2(7, 50), "kinds": [["zombie", 2], ["ghoul", 1]]},
	{"area": 2, "mode": "", "home": Vector2(-19, 77), "kinds": [["zombie", 2]]},
	{"area": 3, "mode": "", "home": Vector2(-25, 48), "kinds": [["zombie", 2]]},
	{"area": 4, "mode": "wander", "home": Vector2(-20, 32), "kinds": [["zombie", 2], ["rock_thrower", 1]]},
	{"area": 4, "mode": "wander", "home": Vector2(6, 30), "kinds": [["ghoul", 2], ["zombie", 1]]},
	{"area": 4, "mode": "", "home": Vector2(34, 33), "kinds": [["zombie", 2]]},
	{"area": 4, "mode": "", "home": Vector2(-39, 30), "kinds": [["rock_thrower", 1]]},
	{"area": 4, "mode": "", "home": Vector2(-25, 17), "kinds": [["ghoul", 1]]},
	{"area": 5, "mode": "", "home": Vector2(25, 13), "kinds": [["zombie", 1], ["ghoul", 1]]},
	{"area": 6, "mode": "wander", "home": Vector2(-22, -4), "kinds": [["zombie", 2], ["ghoul", 1]]},
	{"area": 6, "mode": "wander", "home": Vector2(10, -4), "kinds": [["zombie", 2], ["rock_thrower", 1]]},
	{"area": 6, "mode": "", "home": Vector2(-8, -20), "kinds": [["zombie", 1]]},
	{"area": 6, "mode": "", "home": Vector2(-12, 8), "kinds": [["zombie", 2], ["ghoul", 1]]},
	{"area": 6, "mode": "", "home": Vector2(35, -6), "kinds": [["zombie", 2]]},
	{"area": 7, "mode": "", "home": Vector2(-29, -28), "kinds": [["rock_thrower", 1], ["zombie", 1]]},
	{"area": 8, "mode": "wander", "home": Vector2(-28, -52), "kinds": [["zombie", 2], ["ghoul", 1]]},
	{"area": 8, "mode": "wander", "home": Vector2(4, -52), "kinds": [["brute", 1], ["zombie", 2]]},
	{"area": 8, "mode": "", "home": Vector2(16, -46), "kinds": [["ghoul", 2]]},
	{"area": 8, "mode": "", "home": Vector2(-44, -54), "kinds": [["zombie", 1]]},
	{"area": 8, "mode": "", "home": Vector2(-31, -68), "kinds": [["ghoul", 2]]},
	{"area": 8, "mode": "", "home": Vector2(-11, -35), "kinds": [["zombie", 2], ["rock_thrower", 1]]},
	{"area": 8, "mode": "", "home": Vector2(33, -53), "kinds": [["rock_thrower", 1]]},
	{"area": 9, "mode": "", "home": Vector2(21, -76), "kinds": [["zombie", 1], ["ghoul", 1]]},
	{"area": 10, "mode": "wander", "home": Vector2(0, -100), "kinds": [["warden", 1], ["brute", 1], ["rock_thrower", 2]]},
	{"area": 10, "mode": "", "home": Vector2(-18, -96), "kinds": [["brute", 1], ["ghoul", 2]]},
	{"area": 10, "mode": "", "home": Vector2(16, -96), "kinds": [["rock_thrower", 2], ["zombie", 2]]},
	{"area": 10, "mode": "", "home": Vector2(-37, -100), "kinds": [["zombie", 1]]},
	{"area": 10, "mode": "", "home": Vector2(37, -96), "kinds": [["ghoul", 1]]},
	{"area": 10, "mode": "", "home": Vector2(16, -112), "kinds": [["zombie", 2]]},
	{"area": 10, "mode": "", "home": Vector2(-20, -83), "kinds": [["ghoul", 2], ["zombie", 1]]},
]

## Chests (Chest, the lid-and-loot class): one in each treasure room, in a corner away from the doors.
const CHEST_SPOTS: Array[Vector2] = [Vector2(-17.5, 80.0), Vector2(-28.0, 14.5), Vector2(38.0, -10.0), Vector2(-34.5, -70.5),
		Vector2(13.0, -116.0)]

## The central props of the wide halls: a pillar every 14 m along a strip four metres inside the north wall, clear of the doors.
const PILLAR_HALLS: Array[String] = ["hall_2", "hall_4", "hall_5"]

## Lane G (champions): a group that should gain a champion names it here later. Nothing is spawned from this yet.
const CHAMPION_SLOTS: Array = []

var _enemy_group_id: int = 300
var _openings: Array[Vector2] = []     # the middle of every place two spaces meet (doors, and the seams of overlapping pockets)
var _obstacles: Array[Vector2] = []    # pillars and props put down so far: props keep clear of each other


## The arena for this location: the dungeon's rectangle, no random scatter, and no navigation mesh yet (build() adds props first).
static func make_arena() -> Arena:
	var a := Arena.new()
	a.half_x = ARENA_HALF_X
	a.half_z = ARENA_HALF_Z
	a.scatter = false
	return a


## Where the hero begins: the entry hall's south end.
func start_position() -> Vector3:
	return START_POINT


## Walls, floor, pillars, props, chests and lights, then the one navigation bake. Called once the arena is built without navigation.
func build(for_arena: Arena) -> void:
	arena = for_arena
	in_world = false
	add_to_group("test_dungeon")   # the HUD names the zone from it
	_rng.seed = 2525
	_black_out_ground()
	_fill_void()
	_build_walls()
	_build_floor()
	_find_openings()
	_build_pillars()
	_build_props()
	_build_chests()
	_build_sconces()
	arena.bake_navigation()


## The rooms are lit and the rest is dark: the arena's grey ground plane becomes black, so anything outside the walls reads as void.
func _black_out_ground() -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.01, 0.01, 0.012)
	black.roughness = 1.0
	var nav: NavigationRegion3D = arena.get("_nav_region")
	for child in nav.get_children():
		if child is StaticBody3D:
			for mesh in child.get_children():
				if mesh is MeshInstance3D:
					(mesh as MeshInstance3D).material_override = black


## The enemies: every group stands where the plan puts it, at the level its area is projected to meet (see project()). Called by the
## director once the navigation map is ready. The levels are read from the hero's XP at this moment, so they follow the hero who loads.
func spawn_encounters(for_director: RunDirector) -> void:
	director = for_director
	var levels: PackedInt32Array = area_levels(TownState.hero_xp)
	for g in GROUPS:
		var group: Dictionary = g
		var home: Vector2 = group["home"]
		var level: int = levels[int(group["area"])]
		var members: Array = []
		for pair in group["kinds"]:
			var kind: String = String(pair[0])
			for i in int(pair[1]):
				var spot: Vector2 = home + Vector2(_rng.randf_range(-GROUP_SPREAD, GROUP_SPREAD), _rng.randf_range(-GROUP_SPREAD, GROUP_SPREAD))
				members.append([kind, spot.x, spot.y, level, String(KIND_TIER[kind])])
		_enemy_group_id += 1
		_group(_enemy_group_id, String(group["mode"]), members, home, GROUP_ROAM)


# --- What the hero is projected to meet ------------------------------------------------------------------------------------------------

## Walks the critical path with the hero's XP `entry_xp` and returns one row per area: {area, level (the enemies' level there: the
## hero's projected level on arrival), xp (what the area's kills pay), xp_total, hero_level (after the area)}. Each kill pays
## HeroProgression.monster_xp for its level and tier, times the level-gap multiplier, shared over the party as the game does
## (RunDirector._pay_kill_xp). Every enemy of an area is counted as killed, and side spaces are counted with their area.
## The enemies of an area are at the level the hero has on arriving there, so the gap is never a penalty here.
static func project(entry_xp: int) -> Array:
	var rows: Array = []
	var xp: int = HeroProgression.sanitize_xp(entry_xp)
	for area in AREAS.size():
		var level: int = HeroProgression.level_for_xp(xp)
		var gained: int = 0
		for g in GROUPS:
			var group: Dictionary = g
			if int(group["area"]) != area:
				continue
			for pair in group["kinds"]:
				var tier: String = String(KIND_TIER[String(pair[0])])
				for i in int(pair[1]):
					var kill: int = HeroProgression.monster_xp(level, tier)
					var gap: float = HeroProgression.level_gap_mult(HeroProgression.level_for_xp(xp), level)
					var share: int = HeroProgression.party_share(int(round(float(kill) * gap)), PARTY_SIZE)
					var before: int = xp
					xp = mini(xp + share, HeroProgression.max_xp())
					gained += xp - before
		rows.append({"area": AREAS[area], "level": level, "xp": gained, "xp_total": xp, "hero_level": HeroProgression.level_for_xp(xp)})
	return rows


## The enemy level of each area (index into AREAS) for a hero with `entry_xp` XP at the start: see project().
static func area_levels(entry_xp: int) -> PackedInt32Array:
	var levels := PackedInt32Array()
	for row in project(entry_xp):
		levels.append(int(row["level"]))
	return levels


# --- The plan ---------------------------------------------------------------------------------------------------------------------

## True where a point of the plan is inside one of the rooms (anything else is solid rock, see _fill_void).
func _walkable(p: Vector2) -> bool:
	for key in ROOMS:
		if (ROOMS[key] as Rect2).has_point(p):
			return true
	return false


## The rock around the rooms: every cell of the arena that no room covers is a solid box, merged along each row. Invisible, but it
## blocks the hero, the enemies and the navigation mesh, so only the rooms can be walked.
func _fill_void() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	var nav: NavigationRegion3D = arena.get("_nav_region")
	var x0 := -ARENA_HALF_X
	var z0 := -ARENA_HALF_Z
	var cols := int(round(ARENA_HALF_X * 2.0 / CELL))
	var rows := int(round(ARENA_HALF_Z * 2.0 / CELL))
	for iz in rows:
		var z: float = z0 + (iz + 0.5) * CELL
		var run_start: int = -1
		for ix in range(cols + 1):
			var void_here: bool = ix < cols and not _walkable(Vector2(x0 + (ix + 0.5) * CELL, z))
			if void_here and run_start < 0:
				run_start = ix
			elif not void_here and run_start >= 0:
				_add_rock_box(body, x0 + run_start * CELL, x0 + ix * CELL, z0 + iz * CELL)
				run_start = -1
	nav.add_child(body)


func _add_rock_box(body: StaticBody3D, xa: float, xb: float, za: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(xb - xa, 3.0, CELL)
	shape.shape = box
	shape.position = Vector3((xa + xb) * 0.5, 1.5, za + CELL * 0.5)
	body.add_child(shape)


## Wall segments along every room edge that faces the rock. An edge that opens onto another room (a doorway) gets no wall there.
func _build_walls() -> void:
	for key in ROOMS:
		var r: Rect2 = ROOMS[key]
		var x0: float = r.position.x
		var z0: float = r.position.y
		var x1: float = x0 + r.size.x
		var z1: float = z0 + r.size.y
		_wall_edge(Vector2(x0, z0), Vector2(x1, z0), Vector2(0, -1), 0.0)   # the edge at the room's low z
		_wall_edge(Vector2(x0, z1), Vector2(x1, z1), Vector2(0, 1), 0.0)    # the edge at the room's high z
		_wall_edge(Vector2(x0, z0), Vector2(x0, z1), Vector2(-1, 0), 90.0)  # the low x edge
		_wall_edge(Vector2(x1, z0), Vector2(x1, z1), Vector2(1, 0), 90.0)   # the high x edge


func _wall_edge(a: Vector2, b: Vector2, normal: Vector2, yaw_deg: float) -> void:
	var length: float = a.distance_to(b)
	var dir: Vector2 = (b - a) / maxf(length, 0.001)
	var s := 0.0
	while s < length - 0.01:
		var seg: float = minf(3.0, length - s)
		var mid: Vector2 = a + dir * (s + seg * 0.5)
		var samples: Array[Vector2] = [a + dir * s, mid, a + dir * (s + seg)]
		var rock: bool = false
		for p in samples:
			if not _walkable(p + normal * 0.5):
				rock = true
		if rock:
			var centre: Vector2 = mid + normal * 0.3
			var model: String = "dungeon/wall_large_a" if _rng.randf() < 0.5 else "dungeon/wall_large_b"
			# No collision on the wall pieces: the rock boxes (_fill_void) are the exact blocker, and a piece that straddles a doorway
			# would otherwise narrow the opening.
			_prop(model, centre.x, centre.y, deg_to_rad(yaw_deg), WALL_HEIGHT, false, false, 0.0)
			if _rng.randf() < 0.45:   # a buttress on the room side, every few metres along a long wall
				var inside: Vector2 = mid - normal * 0.4
				_prop("dungeon/pillar", inside.x, inside.y, 0.0, 2.3, false, false, 0.0)
		s += seg


## Floor tiles over every room: 2 m calm flagstone tiles, each turned by a random quarter turn so the tiles do not repeat.
func _build_floor() -> void:
	for key in ROOMS:
		var r: Rect2 = ROOMS[key]
		var x := r.position.x
		while x < r.position.x + r.size.x - 0.01:
			var z := r.position.y
			while z < r.position.y + r.size.y - 0.01:
				var cx: float = minf(x + 1.0, r.position.x + r.size.x - 1.0)
				var cz: float = minf(z + 1.0, r.position.y + r.size.y - 1.0)
				arena.place_prop("dungeon/floor_flag", Vector3(cx, 0.0, cz), float(_rng.randi() % 4) * PI * 0.5, 0.153, false, false)   # the GLB is 0.153 m tall: any other height scales the tile and opens gaps
				z += 2.0
			x += 2.0


## Every place two spaces meet: where their rectangles overlap or share an edge (a doorway, or the seam between two cave pockets).
func _find_openings() -> void:
	_openings.clear()
	var keys: Array = ROOMS.keys()
	for i in keys.size():
		var a: Rect2 = ROOMS[keys[i]]
		for j in range(i + 1, keys.size()):
			var b: Rect2 = ROOMS[keys[j]]
			var ix0: float = maxf(a.position.x, b.position.x)
			var ix1: float = minf(a.end.x, b.end.x)
			var iz0: float = maxf(a.position.y, b.position.y)
			var iz1: float = minf(a.end.y, b.end.y)
			if ix1 < ix0 or iz1 < iz0 or (ix1 - ix0) + (iz1 - iz0) <= 0.0:
				continue   # the rectangles only touch at a corner, or not at all
			_openings.append(Vector2((ix0 + ix1) * 0.5, (iz0 + iz1) * 0.5))


## True when a point is within `margin` metres of a doorway (or a seam).
func _near_opening(p: Vector2, margin: float) -> bool:
	for o in _openings:
		if o.distance_to(p) < margin:
			return true
	return false


## Pillars along the strip four metres inside each wide hall's north wall, every 14 m, none by a doorway.
func _build_pillars() -> void:
	for key in PILLAR_HALLS:
		var r: Rect2 = ROOMS[key]
		var x := r.position.x + 9.0
		while x < r.end.x - 8.0:
			var p := Vector2(x, r.position.y + 4.0)
			if not _near_opening(p, 4.0):
				_prop("dungeon/pillar", p.x, p.y, 0.0, 3.1, true, false, 0.7)
				_obstacles.append(p)
			x += 14.0


## Barrels, crates and urns, about one for every 55 square metres of each space (at least one), seeded so the room is the same every
## visit. Corridors stay clear. A prop keeps off the doorways, the other props, the chests and the hero's start.
func _build_props() -> void:
	for key in ROOMS:
		if String(key).begins_with("corridor"):
			continue
		var r: Rect2 = ROOMS[key]
		var count: int = maxi(1, int(round(r.get_area() / 55.0)))
		var made: int = 0
		var tries: int = 0
		while made < count and tries < count * 40:
			tries += 1
			var p := Vector2(_rng.randf_range(r.position.x + 1.6, r.end.x - 1.6), _rng.randf_range(r.position.y + 1.6, r.end.y - 1.6))
			if not _prop_spot_ok(p):
				continue
			var roll: float = _rng.randf()
			if roll < 0.4:
				_prop("barrel", p.x, p.y, _rng.randf() * TAU, 1.1, true, false, 0.6)
			elif roll < 0.7:
				_prop("dungeon/crate", p.x, p.y, _rng.randf() * TAU, 0.9, true, false, 0.7)
			else:
				_prop("dungeon/urn", p.x, p.y, _rng.randf() * TAU, 0.75, true, false, 0.45)
			_obstacles.append(p)
			made += 1


func _prop_spot_ok(p: Vector2) -> bool:
	if _near_opening(p, 3.2) or p.distance_to(Vector2(START_POINT.x, START_POINT.z)) < 4.0:
		return false
	for c in CHEST_SPOTS:
		if p.distance_to(c) < 3.0:
			return false
	for o in _obstacles:
		if p.distance_to(o) < 2.2:
			return false
	return true


## The treasure chests: a Chest each (click it to open; it drops its loot once).
func _build_chests() -> void:
	for spot in CHEST_SPOTS:
		var chest := Chest.new()
		chest.position = at(spot.x, spot.y)
		add_child(chest)


## One sconce on a wall of each space of 60 square metres or more: on the first wall (in the order north, south, west, east, from a
## different start for each space) that no doorway opens onto. The torch points into the room. The light is the sconce's own, which the
## shared profile warms.
func _build_sconces() -> void:
	var index: int = 0
	for key in ROOMS:
		var r: Rect2 = ROOMS[key]
		index += 1
		if r.get_area() < 60.0:
			continue
		var mid_x: float = r.position.x + r.size.x * 0.5
		var mid_z: float = r.position.y + r.size.y * 0.5
		var walls: Array = [
			[Vector2(mid_x, r.position.y), Vector2(0, 1)],   # the low-z wall, its torch points south (+z)
			[Vector2(mid_x, r.end.y), Vector2(0, -1)],
			[Vector2(r.position.x, mid_z), Vector2(1, 0)],
			[Vector2(r.end.x, mid_z), Vector2(-1, 0)],
		]
		for k in walls.size():
			var wall: Array = walls[(index + k) % walls.size()]
			var spot: Vector2 = wall[0]
			var facing: Vector2 = wall[1]
			if _near_opening(spot, 3.5):
				continue
			var yaw: float = atan2(-facing.x, -facing.y)   # the sconce's torch points along `facing` (its local -Z)
			_prop("dungeon/torch_sconce", spot.x + facing.x * 0.05, spot.y + facing.y * 0.05, yaw, 1.2, false, true, 0.0)
			break


## Brighter than the shared profile alone, so the rooms stay readable: enemies, props and loot must be easy to see. Called by main
## after the profile is applied, and only under --atmosphere.
func tune_look(environment: Environment) -> void:
	# Neutral enough that the warm sconces read as warm: the room stays bright, and the warmth comes from the torch pools.
	environment.ambient_light_color = Color(0.5, 0.51, 0.54)
	environment.ambient_light_energy = 0.55
	environment.fog_density = 0.008
	environment.background_mode = Environment.BG_COLOR   # no sky: beyond the walls is void
	environment.background_color = Color(0.0, 0.0, 0.0)
	# The warm lights (sconces, hearth) get a stronger pool of warm light. Their flicker keeps its own base energy, so the base is
	# set too, or the flicker would hand the old value back every frame.
	for node in arena.find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		if light.light_color.r <= light.light_color.g:
			continue
		light.light_color = Color(1.0, 0.56, 0.24)
		light.light_energy *= 1.5
		for child in light.get_children():
			if child is FlickerLight:
				(child as FlickerLight)._base = light.light_energy
