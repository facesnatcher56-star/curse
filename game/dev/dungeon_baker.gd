class_name DungeonBaker
extends TestDungeon
## Builds the dungeon level scene (`game/world/dungeon_level.tscn`) once, from the plan below. Developer tool: the GAME never runs this.
## The scene it writes is the source of the level from then on: open it in the editor, move, add and delete things, save. Run it again only
## to throw the hand edits away and start over from the plan:
##   godot --headless --path . -s res://tools/bake_dungeon_scene.gd
##
## The plan (x, z, metres; north is -z, the hero starts at the south end). Each hall is crossed from one door to the other:
##   entry -> corridor_1 -> hall_1 -> corridor_2 -> hall_2 -> corridor_3 -> hall_3 -> corridor_4 -> hall_4 -> corridor_5 -> hall_5 (final)
## Side spaces hang off the chain (see ROOMS): the entry's alcove and cave, alcoves and treasure rooms in each hall, a cave south of hall_3.

const WALL_HEIGHT := 1.9
const CELL := 0.5

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

var _openings: Array[Vector2] = []     # the middle of every place two spaces meet (doors, and the seams of overlapping pockets)
var _obstacles: Array[Vector2] = []    # pillars and props put down so far: props keep clear of each other
var _category: String = "Props"        # which group of the scene the props being placed go into


## Walls, floor, pillars, props, chests and lights, in memory. `pack_scene` then writes them out. No navigation bake (the game does that).
func build(for_arena: Arena) -> void:
	arena = for_arena
	in_world = false
	_rng.seed = 2525
	_category = "Walls"
	_build_walls()
	_category = "Floor"
	_build_floor()
	_find_openings()
	_category = "Pillars"
	_build_pillars()
	_category = "Props"
	_build_props()
	_build_chests()
	_category = "Torches"
	_build_sconces()


## Every prop gets the facts the game needs to wire it up again when the scene is loaded (see Destructible.adopt and TestDungeon.build).
func _prop(model: String, x: float, z: float, yaw: float, height: float, collides: bool = true, lit: bool = false, clear: float = -1.0) -> Node3D:
	var node: Node3D = super._prop(model, x, z, yaw, height, collides, lit, clear)
	_tag(node, collides, height)
	return node


func _tag(node: Node3D, collides: bool, height: float) -> void:
	node.set_meta("category", _category)
	if collides:
		node.set_meta("obstacle_radius", float((arena.obstacles.back() as Dictionary)["radius"]))
	if node is Destructible:
		node.set_meta("prop_kind", (node as Destructible).prop_name)
		node.set_meta("prop_height", height)


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
				_tag(arena.place_prop("dungeon/floor_flag", Vector3(cx, 0.0, cz), float(_rng.randi() % 4) * PI * 0.5, 0.153, false, false), false, 0.153)   # the GLB is 0.153 m tall: any other height scales the tile and opens gaps
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



# --- Writing the scene -------------------------------------------------------------------------------------------------------------------

## Collects what the build made, sorts it into the scene's groups, and saves it. The groups: Floor, Walls, Pillars, Props, Torches (the
## props), Rock (the invisible solid rock round the rooms), Chests, EnemyGroups (DungeonEnemyGroup markers) and PlayerStart.
## `before` is what the navigation region already held (the arena's own ground), which is not part of the level.
func pack_scene(path: String, before: Array) -> int:
	var root := Node3D.new()
	root.name = "DungeonLevel"
	var holders: Dictionary = {}
	for group_name in ["Floor", "Walls", "Pillars", "Props", "Torches", "Rock", "Chests", "EnemyGroups"]:
		var group := Node3D.new()
		group.name = group_name
		root.add_child(group)
		group.owner = root
		holders[group_name] = group
	var nav: NavigationRegion3D = arena.get("_nav_region")
	var counts: Dictionary = {}
	for child in nav.get_children():
		if before.has(child):
			continue
		var kind: String = String(child.get_meta("category", "Props"))
		nav.remove_child(child)
		var target: Node3D = holders[kind]
		target.add_child(child)
		child.name = _readable_name(child, kind, int(counts.get(kind, 0)))
		_own(child, root)
		counts[kind] = int(counts.get(kind, 0)) + 1
	var rock := _merged_rock()
	(holders["Rock"] as Node3D).add_child(rock)
	_own(rock, root)
	for child in get_children():
		if child is Chest:
			remove_child(child)
			(holders["Chests"] as Node3D).add_child(child)
			child.name = "Chest_%d" % ((holders["Chests"] as Node3D).get_child_count())
			child.owner = root   # only the chest itself: its lid and model are built again when it is ready
			counts["Chests"] = int(counts.get("Chests", 0)) + 1
	for g in GROUPS:
		var group: Dictionary = g
		var marker := DungeonEnemyGroup.new()
		var home: Vector2 = group["home"]
		marker.position = Vector3(home.x, 0.0, home.y)
		marker.area = int(group["area"])
		marker.behaviour = DungeonEnemyGroup.Behaviour.WANDER if String(group["mode"]) == "wander" else DungeonEnemyGroup.Behaviour.STAND
		marker.kinds = (group["kinds"] as Array).duplicate(true)
		marker.name = "Group%02d_area%d" % [(holders["EnemyGroups"] as Node3D).get_child_count() + 1, marker.area]
		(holders["EnemyGroups"] as Node3D).add_child(marker)
		marker.owner = root
	var start := Marker3D.new()
	start.name = "PlayerStart"
	start.position = START_POINT
	root.add_child(start)
	start.owner = root
	var packed := PackedScene.new()
	var error: int = packed.pack(root)
	if error != OK:
		return error
	error = ResourceSaver.save(packed, path)
	print("DUNGEON_BAKE %s: %s, %d enemy groups, %d rock boxes (error %d)" % [path, str(counts), GROUPS.size(), rock.get_child_count(), error])
	return error


## A name a person can read in the scene tree: floor tiles by where they lie, props by what they are, the rest by kind and number.
func _readable_name(node: Node3D, category: String, index: int) -> String:
	match category:
		"Floor":
			return "Tile_%d_%d" % [int(round(node.position.x)), int(round(node.position.z))]
		"Walls":
			return "Wall_%03d" % index
		"Pillars":
			return "Pillar_%02d" % index
		"Torches":
			return "Torch_%02d" % index
		"Props":
			var kind: String = String(node.get_meta("prop_kind", "prop"))
			return "%s_%03d" % [kind.capitalize(), index]
	return "%s_%03d" % [category, index]


## Makes `node` and what it is made of belong to the scene, except what an instanced model brings with it (that stays inside the model).
func _own(node: Node, root: Node) -> void:
	node.owner = root
	if node.scene_file_path != "":
		return
	for child in node.get_children():
		_own(child, root)


## The solid rock round the rooms as one body: every cell of the arena that no room covers, merged along rows and then down columns, so the
## scene holds a few hundred boxes instead of thousands. Invisible; it blocks walking and the navigation bake.
func _merged_rock() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "RockBody"
	body.collision_layer = Actor.LAYER_WORLD
	var x0 := -ARENA_HALF_X
	var z0 := -ARENA_HALF_Z
	var cols := int(round(ARENA_HALF_X * 2.0 / CELL))
	var rows := int(round(ARENA_HALF_Z * 2.0 / CELL))
	var open_runs: Dictionary = {}   # "xa:xb" -> [first row, last row]
	var boxes: Array = []            # [xa, xb, first row, last row]
	for iz in rows + 1:
		var runs: Dictionary = {}
		if iz < rows:
			var z: float = z0 + (iz + 0.5) * CELL
			var run_start: int = -1
			for ix in range(cols + 1):
				var void_here: bool = ix < cols and not _walkable(Vector2(x0 + (ix + 0.5) * CELL, z))
				if void_here and run_start < 0:
					run_start = ix
				elif not void_here and run_start >= 0:
					runs["%d:%d" % [run_start, ix]] = true
					run_start = -1
		for key in open_runs.keys():
			if not runs.has(key):
				var span: PackedStringArray = String(key).split(":")
				var rows_open: Array = open_runs[key]
				boxes.append([int(span[0]), int(span[1]), rows_open[0], rows_open[1]])
				open_runs.erase(key)
		for key in runs:
			if open_runs.has(key):
				(open_runs[key] as Array)[1] = iz
			else:
				open_runs[key] = [iz, iz]
	var index: int = 0
	for box in boxes:
		var shape := CollisionShape3D.new()
		var size := BoxShape3D.new()
		var width: float = float(int(box[1]) - int(box[0])) * CELL
		var depth: float = float(int(box[3]) - int(box[2]) + 1) * CELL
		size.size = Vector3(width, 3.0, depth)
		shape.shape = size
		shape.position = Vector3(x0 + float(box[0]) * CELL + width * 0.5, 1.5, z0 + float(box[2]) * CELL + depth * 0.5)
		shape.name = "Rock%03d" % index
		body.add_child(shape)
		index += 1
	return body
