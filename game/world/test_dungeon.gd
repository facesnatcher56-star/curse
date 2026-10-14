class_name TestDungeon
extends CryptRoad
## The dungeon test level (`-- --dungeon`, issue #25): enclosed rooms, corridors, an alcove, a collapsed wall and a cave-like chamber.
## It reuses CryptRoad's location plumbing (props put on the arena, one navigation bake, groups spawned by the director) with its own
## plan, encounters and look. The `--atmosphere` look is the shared AtmosphereProfile, which main applies to every location; this file
## only adds a brighter tune for the rooms. Without the flag nothing here runs.
##
## The plan (x, z, metres; north is -z, the hero starts at the south end):
##   entry hall (with a west alcove) -> corridor A -> central pillared chamber -> treasure room (east), collapsed passage (west),
##   corridor B (north) -> final hall (with a collapsed wall into an alcove on its west side). A cave opens east off the entry hall.

const SITE := "test_dungeon"
const ARENA_HALF_X := 26.0
const ARENA_HALF_Z := 50.0
const START_POINT := Vector3(0.0, 0.0, 39.0)
const WALL_HEIGHT := 1.9
const CELL := 0.5
## The camera for this level only: fully zoomed-in is 2.0, and a new run starts at 1.5 (main sets these on the rig).
const ZOOM_MAX := 2.0
const ZOOM_START := 1.5

## Every walkable space as a rectangle: Rect2(x0, z0, width, depth). Two spaces that overlap or touch form an opening.
const ROOMS := {
	"entry": Rect2(-11, 26, 22, 18),
	"alcove_west": Rect2(-16, 31, 5, 6),       # off the entry hall's west wall
	"corridor_a": Rect2(-3, 12, 6, 14),
	"central": Rect2(-15, -6, 30, 18),
	"treasure": Rect2(15, -4, 10, 10),
	"collapsed": Rect2(-25, -1, 10, 4),
	"corridor_b": Rect2(-1.5, -14, 3, 8),
	"final": Rect2(-18, -44, 36, 30),
	"alcove_final": Rect2(-22, -31, 4, 6),     # behind the final hall's west wall, where the wall has collapsed
	"cave_link": Rect2(11, 31, 4, 4),          # the way east out of the entry hall
	"cave_a": Rect2(15, 27, 7, 9),             # the cave: three overlapping pockets, so the outline is not a rectangle
	"cave_b": Rect2(18, 29, 5, 6),
	"cave_c": Rect2(15, 35, 6, 4),
}

## The central chamber's pillars, and the rubble that half-closes the collapsed passage.
const PILLARS: Array[Vector2] = [Vector2(-9, -2), Vector2(-3, -2), Vector2(3, -2), Vector2(9, -2),
		Vector2(-9, 4), Vector2(-3, 4), Vector2(3, 4), Vector2(9, 4)]
const RUBBLE: Array[Vector2] = [Vector2(-19.5, -0.3), Vector2(-22.5, -0.5)]
## Fallen stone at the collapsed wall's mouth and in the cave (visual only: they do not block).
const COLLAPSE_RUBBLE: Array[Vector2] = [Vector2(-18.8, -28.0), Vector2(-18.2, -30.4), Vector2(-20.5, -29.2)]
const CAVE_ROCKS: Array[Vector2] = [Vector2(21.8, 30.8), Vector2(20.0, 36.4), Vector2(16.8, 37.5)]

## Props: [model, x, z, yaw_degrees]. Clusters sit in the corners of the rooms. Barrels are the arena's own; the rest are dungeon props.
const PROPS: Array = [
	# Entry hall: a crate and barrel group in the north-west corner, a barrel and urns in the north-east corner.
	["dungeon/crate", -9.5, 42.4, 15.0], ["dungeon/crate", -8.4, 41.3, -10.0], ["barrel", -10.0, 39.8, 0.0],
	["barrel", 9.3, 42.6, 0.0], ["dungeon/urn", 10.3, 41.0, 0.0], ["dungeon/urn", 9.6, 40.1, 30.0],
	["barrel", 8.5, 31.0, 40.0], ["dungeon/urn", -9.5, 29.0, 0.0],
	# Corridor A and the central chamber's corners.
	["dungeon/urn", -2.4, 20.0, 35.0], ["dungeon/urn", 2.5, 16.0, -20.0], ["dungeon/crate", -2.0, 24.5, 0.0],
	["dungeon/crate", -13.3, 9.2, 0.0], ["dungeon/crate", -14.4, 8.0, 20.0], ["barrel", -13.5, 11.3, 0.0],
	["dungeon/urn", -13.2, -4.2, 0.0], ["dungeon/urn", -12.4, -3.6, 0.0], ["dungeon/urn", -13.9, -3.0, 0.0],
	["barrel", 13.3, -4.3, 0.0], ["dungeon/urn", 14.2, -3.0, 0.0],
	["dungeon/crate", 13.2, 9.7, 0.0], ["dungeon/crate", 14.0, 10.5, 30.0],
	# The treasure room: an urn cluster in one corner, crates in the other, and the chest.
	["dungeon/urn", 23.5, -2.8, 0.0], ["dungeon/urn", 24.2, -2.0, 40.0], ["dungeon/urn", 23.2, -1.6, 0.0],
	["dungeon/crate", 16.0, 4.5, 0.0], ["dungeon/crate", 16.8, 5.0, 25.0],
	["dungeon/chest", 22.5, 0.5, -90.0],
	# The collapsed passage and the west alcove.
	["barrel", -22.0, 2.4, 0.0], ["dungeon/urn", -23.0, 0.2, 0.0],
	["barrel", -14.5, 33.5, 0.0], ["barrel", -13.6, 34.6, 30.0], ["dungeon/crate", -14.6, 35.6, 0.0],
	# The cave.
	["barrel", 21.0, 31.0, 0.0], ["dungeon/urn", 22.0, 34.0, 0.0],
	# The final hall: barrel and crate groups in the north corners, urns in the south corners, two chests, and the warden's flank.
	["barrel", -16.0, -42.0, 0.0], ["barrel", -15.2, -41.0, 40.0], ["dungeon/crate", -16.7, -40.0, 0.0],
	["dungeon/crate", 16.0, -42.5, 0.0], ["dungeon/crate", 16.8, -41.2, 25.0], ["dungeon/crate", 15.5, -40.6, 0.0],
	["dungeon/urn", -16.0, -16.0, 0.0], ["dungeon/urn", -15.0, -16.8, 0.0], ["dungeon/urn", -15.5, -15.2, 60.0],
	["dungeon/urn", 16.0, -17.0, 0.0], ["dungeon/urn", 15.2, -16.2, 0.0],
	["dungeon/chest", 0.0, -20.0, 0.0], ["dungeon/chest", -14.8, -29.0, 90.0],
	["dungeon/crate", -14.0, -24.0, 0.0], ["dungeon/crate", 14.0, -24.0, 0.0],
	["dungeon/urn", -14.5, -33.0, 0.0], ["dungeon/urn", 15.0, -33.0, 0.0],
	["barrel", 12.5, -39.0, 0.0],
]

## Sconces on the wall faces: [x, z, into_room_x, into_room_z]. The torch points into the room.
const SCONCES: Array[Vector4] = [Vector4(-10.2, 44.0, 0, -1), Vector4(10.2, 44.0, 0, -1), Vector4(-15.0, 4.0, 1, 0),
		Vector4(15.0, 8.0, -1, 0), Vector4(-18.0, -40.0, 1, 0), Vector4(18.0, -40.0, -1, 0),
		Vector4(-6.0, -44.0, 0, 1), Vector4(6.0, -44.0, 0, 1), Vector4(-16.0, 34.0, 1, 0)]

## Enemy groups, [kind, x, z, level, tier]: one group per space, a tougher group in the final hall. The roster and AI are the existing ones.
const GROUPS: Array = [
	{"mode": "", "home": Vector2(0, 22), "members": [["zombie", -1.0, 19.0, 5, "trivial"], ["zombie", 1.0, 20.5, 5, "trivial"]]},
	{"mode": "wander", "home": Vector2(0, 2), "members": [["ghoul", -9.0, 0.0, 6, "weak"], ["zombie", -5.0, 5.0, 5, "trivial"],
		["zombie", 5.0, 7.0, 5, "trivial"], ["rock_thrower", 8.0, -1.0, 6, "weak"]]},
	{"mode": "", "home": Vector2(20, 1), "members": [["brute", 20.0, 2.5, 7, ""], ["zombie", 18.0, -2.0, 5, "trivial"]]},
	{"mode": "", "home": Vector2(-21, 1.5), "members": [["zombie", -19.0, 2.4, 5, "trivial"], ["ghoul", -17.8, 1.0, 6, "weak"]]},
	{"mode": "wander", "home": Vector2(0, -28), "members": [["warden", 0.0, -32.0, 8, ""], ["brute", -6.0, -36.0, 8, ""],
		["brute", 6.0, -36.0, 8, ""], ["ghoul", -9.0, -26.0, 8, "weak"], ["ghoul", 9.0, -26.0, 8, "weak"],
		["rock_thrower", -3.5, -40.5, 8, "weak"], ["rock_thrower", 3.5, -40.5, 8, "weak"]]},
]

var _enemy_group_id: int = 300


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


## Walls, floor, pillars, props and lights, then the one navigation bake. Called once the arena is built without navigation.
func build(for_arena: Arena) -> void:
	arena = for_arena
	in_world = false
	add_to_group("test_dungeon")   # the HUD names the zone from it
	_rng.seed = 2525
	_black_out_ground()
	_fill_void()
	_build_walls()
	_build_floor()
	for p in PILLARS:
		_prop("dungeon/pillar", p.x, p.y, 0.0, 3.1, true, false, 0.7)
	for r in RUBBLE:
		_prop("dungeon/rubble", r.x, r.y, _rng.randf() * TAU, 0.9, true, false, 0.9)
	for r in COLLAPSE_RUBBLE:
		_prop("dungeon/rubble", r.x, r.y, _rng.randf() * TAU, 0.7, false, false, 0.0)
	for r in CAVE_ROCKS:
		_prop("dungeon/rubble", r.x, r.y, _rng.randf() * TAU, 1.1, true, false, 0.9)
	_build_props()
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


## The enemies: every group stands where the plan puts it. Called by the director once the navigation map is ready.
func spawn_encounters(for_director: RunDirector) -> void:
	director = for_director
	for g in GROUPS:
		_enemy_group_id += 1
		_group(_enemy_group_id, String(g["mode"]), g["members"], g["home"], 4.0)


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


func _build_props() -> void:
	for p in PROPS:
		var model: String = p[0]
		var x: float = p[1]
		var z: float = p[2]
		var yaw: float = deg_to_rad(float(p[3]))
		if model == "barrel":
			_prop("barrel", x, z, yaw, 1.1, true, false, 0.6)
		elif model == "dungeon/crate":
			_prop(model, x, z, yaw, 0.9, true, false, 0.7)
		elif model == "dungeon/urn":
			_prop(model, x, z, yaw, 0.75, true, false, 0.45)
		elif model == "dungeon/chest":
			_prop(model, x, z, yaw, 0.8, true, false, 0.7)


## A sconce on a wall, its light on the room side. The light is the lit prop's own omni light, which the shared profile warms.
func _build_sconces() -> void:
	for s in SCONCES:
		var wall := Vector2(s.x, s.y)
		var facing := Vector2(s.z, s.w)
		var yaw: float = atan2(-facing.x, -facing.y)   # the sconce's torch points along `facing` (its local -Z)
		_prop("dungeon/torch_sconce", wall.x + facing.x * 0.05, wall.y + facing.y * 0.05, yaw, 1.2, false, true, 0.0)
