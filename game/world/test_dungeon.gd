class_name TestDungeon
extends CryptRoad
## The dungeon test level (`-- --dungeon`, issue #25): enclosed rooms and corridors, built from the environment kit and the dungeon props.
## It reuses CryptRoad's location plumbing (props put on the arena, one navigation bake, groups spawned by the director) with its own
## plan, encounters and look. Without the flag nothing here runs.
##
## The plan (x, z, metres; north is -z, the hero starts at the south end):
##   entry hall -> corridor A (6 wide) -> central pillared chamber -> treasure room (east), collapsed passage (west),
##   corridor B (3 wide, north) -> final hall (larger, a tougher group).

const SITE := "test_dungeon"
const ARENA_HALF_X := 26.0
const ARENA_HALF_Z := 50.0
const START_POINT := Vector3(0.0, 0.0, 39.0)
const WALL_HEIGHT := 1.9
const CELL := 0.5

## Every walkable space as a rectangle: Rect2(x0, z0, width, depth). Two spaces that overlap form a doorway.
const ROOMS := {
	"entry": Rect2(-11, 26, 22, 18),
	"corridor_a": Rect2(-3, 12, 6, 14),
	"central": Rect2(-15, -6, 30, 18),
	"treasure": Rect2(15, -4, 10, 10),
	"collapsed": Rect2(-25, -1, 10, 4),
	"corridor_b": Rect2(-1.5, -14, 3, 8),
	"final": Rect2(-18, -44, 36, 30),
}

## The central chamber's pillars, and the rubble that half-closes the collapsed passage.
const PILLARS: Array[Vector2] = [Vector2(-9, -2), Vector2(-3, -2), Vector2(3, -2), Vector2(9, -2),
		Vector2(-9, 4), Vector2(-3, 4), Vector2(3, 4), Vector2(9, 4)]
const RUBBLE: Array[Vector2] = [Vector2(-19.5, -0.3), Vector2(-22.5, -0.5)]

## Props: [model, x, z, yaw_degrees]. Model names are assets/models/dungeon/<name>/model.glb, except barrels (the arena's own).
const PROPS: Array = [
	["dungeon/crate", -8.5, 41.0, 20.0], ["barrel", 8.5, 31.0, 0.0], ["dungeon/urn", -9.5, 29.0, 0.0],
	["dungeon/urn", -2.4, 20.0, 35.0], ["dungeon/urn", 2.5, 16.0, -20.0], ["dungeon/crate", -2.0, 24.5, 0.0],
	["barrel", 12.0, 9.0, 40.0], ["dungeon/crate", -12.0, 9.0, 0.0], ["dungeon/crate", 12.5, -4.0, 0.0],
	["dungeon/urn", 17.0, -2.0, 10.0], ["dungeon/urn", 24.0, 5.0, -30.0],
	["dungeon/chest", 22.5, 0.5, -90.0],
	["barrel", -22.0, 2.4, 0.0], ["dungeon/urn", -23.0, 0.2, 0.0],
	["dungeon/crate", -14.0, -24.0, 0.0], ["dungeon/crate", 14.0, -24.0, 0.0], ["barrel", -12.0, -40.0, 0.0],
	["barrel", 12.5, -39.0, 0.0], ["dungeon/chest", 0.0, -20.0, 0.0], ["dungeon/urn", -14.5, -33.0, 0.0],
	["dungeon/urn", 15.0, -33.0, 0.0],
]

## Sconces on the wall faces: [x, z, into_room_x, into_room_z]. The torch points into the room.
const SCONCES: Array[Vector4] = [Vector4(-10.2, 44.0, 0, -1), Vector4(10.2, 44.0, 0, -1), Vector4(-15.0, 4.0, 1, 0),
		Vector4(15.0, 8.0, -1, 0), Vector4(-18.0, -40.0, 1, 0), Vector4(18.0, -40.0, -1, 0),
		Vector4(-6.0, -44.0, 0, 1), Vector4(6.0, -44.0, 0, 1)]

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
	_rng.seed = 2525
	_fill_void()
	_build_walls()
	_build_floor()
	for p in PILLARS:
		_prop("dungeon/pillar", p.x, p.y, 0.0, 3.1, true, false, 0.7)
	for r in RUBBLE:
		_prop("dungeon/rubble", r.x, r.y, _rng.randf() * TAU, 0.9, true, false, 0.9)
	_build_props()
	_build_sconces()
	arena.bake_navigation()
	if OS.get_cmdline_user_args().has("--atmosphere"):
		_style_local_lights()


## The enemies: every group stands where the plan puts it. Called by the director once the navigation map is ready.
func spawn_encounters(for_director: RunDirector) -> void:
	director = for_director
	for g in GROUPS:
		_enemy_group_id += 1
		_group(_enemy_group_id, String(g["mode"]), g["members"], g["home"], 4.0)


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
			# No collision on the wall pieces: the rock boxes (_fill_void) are the exact blocker, and a piece that straddles a doorway
			# would otherwise narrow the opening.
			_prop("dungeon/wall", centre.x, centre.y, deg_to_rad(yaw_deg), WALL_HEIGHT, false, false, 0.0)
		s += seg


## Floor tiles over every room, in 2 m steps, each turned by a random quarter turn so the tiles do not repeat.
func _build_floor() -> void:
	for key in ROOMS:
		var r: Rect2 = ROOMS[key]
		var x := r.position.x
		while x < r.position.x + r.size.x - 0.01:
			var z := r.position.y
			while z < r.position.y + r.size.y - 0.01:
				var cx: float = minf(x + 1.0, r.position.x + r.size.x - 1.0)
				var cz: float = minf(z + 1.0, r.position.y + r.size.y - 1.0)
				arena.place_prop("dungeon/floor", Vector3(cx, 0.0, cz), float(_rng.randi() % 4) * PI * 0.5, 0.125, false, false)
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


## A sconce on a wall, its light on the room side. The light is the lit prop's own omni light.
func _build_sconces() -> void:
	for s in SCONCES:
		var wall := Vector2(s.x, s.y)
		var facing := Vector2(s.z, s.w)
		var yaw: float = atan2(-facing.x, -facing.y)   # the sconce's torch points along `facing` (its local -Z)
		_prop("dungeon/torch_sconce", wall.x + facing.x * 0.05, wall.y + facing.y * 0.05, yaw, 1.2, false, true, 0.0)


# --- The look ------------------------------------------------------------------------------------------------------------------------

## The `--atmosphere` look: cool fog with aerial perspective, low ambient so form comes from the sun and the local lights, a stronger
## sun with shadows, moderate SSAO, and an AgX tonemap. The same values as the opt-in profile (game/atmosphere_profile.gd). Only
## environment and light settings change.
static func apply_atmosphere(environment: Environment, sun: DirectionalLight3D) -> void:
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.38, 0.42)
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.9
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_hdr_threshold = 1.2
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.07, 0.08, 0.09)
	environment.fog_density = 0.012
	environment.fog_aerial_perspective = 0.3
	environment.fog_sky_affect = 0.5
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.2
	environment.ssao_power = 1.5
	if sun != null:
		sun.light_energy = 1.4
		sun.shadow_enabled = true


## Warm falloff on the warm local lights (the sconces), and no shadows on the local lights.
func _style_local_lights() -> void:
	for node in find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		light.shadow_enabled = false
		light.omni_attenuation = 1.4
		if light.light_color.r > light.light_color.g:
			light.light_color = light.light_color.lerp(Color(1.0, 0.6, 0.3), 0.3)
			light.light_energy *= 1.8
			light.omni_range *= 1.3
