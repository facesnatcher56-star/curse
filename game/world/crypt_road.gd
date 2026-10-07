class_name CryptRoad
extends Node3D
## The first authored location: a long, narrow stretch of ruined road from the town's side gate to a sealed crypt, about 60 m across
## and 360 m long (three and a half times the old arena, and elongated rather than square).
##
##   road gate (town side)  z = +170   the way home; the hero starts a little way in
##   ruined road            z = +150..115   two walkers on the road
##   abandoned wagon        z = +105..95    a pack feeding on the dead
##   graveyard (west)  /  collapsed cottage (east)    z = +95..45   both open onto the road; a nest in each
##   wooded choke           z = +40..8      trees close in to a gap a few metres wide, with a brute
##   old shrine             z = 0           a plague priest among its guard
##   crypt courtyard        z = -45..-155   walled; the third nest, the strongest groups
##   crypt entrance         z = -165        a sealed facade (the way on, for a later job)
##
## Everything is placed by hand (no random scatter of encounters): the monsters exist in the world from the start, doing something
## (strolling, feeding, standing guard) until they notice the hero, and a group wakes together. Filler (trees, graves, bones) is
## scattered from a fixed seed inside named zones so the dressing is the same every visit. Props are the old Meshy set plus the
## Blender models in assets/models/crypt/ (tools/blender/make_crypt_props.py).

const SITE_ID := "crypt_road"
const HALF_X := 30.0
const HALF_Z := 180.0
const START := Vector3(1.0, 0.0, 150.0)
## The road's centre line (x, z), south (town) to north (crypt); it wanders a little so it is a road, not a ruler.
const ROAD: Array[Vector2] = [Vector2(0, 176), Vector2(0, 160), Vector2(4, 138), Vector2(-3, 114), Vector2(2, 92), Vector2(-2, 66),
	Vector2(1, 42), Vector2(0, 16), Vector2(0, -4), Vector2(0, -40), Vector2(0, -90), Vector2(0, -140), Vector2(0, -156)]
const ROAD_HALF_WIDTH := 2.6
const EXIT_Z := 174.0
## The mood of the place: darker and foggier than the arena (see Main._apply_job_mood).
const AMBIENT_MULT := 0.8
const FOG_MULT := 1.7

## The nests: where they are (x, z, yaw). They are placed once at the start and put back by `regrow()` when the quest is handed in.
## Monster density: four times what the hand-placed groups alone held. Every zombie and ghoul in a placed group is `PACK_COPIES`
## strong (the rarer kinds stay single), and `_fill_gaps` puts a smaller group wherever the placed ones leave a stretch of road empty.
const PACK_COPIES := 3
const FILL_CELL := 17.0          # the grid the empty stretches are looked for on
const FILL_COVER := 18.0         # a cell this close to a placed group's home is not empty
const FILL_KEEP_FROM_START := 22.0
const FILL_SEED := 4242          # its own generator, so the dressing (props) is the same as ever
const NEST_SPOTS: Array[Vector3] = [Vector3(-21.0, 58.0, 0.6), Vector3(20.0, 52.0, 2.4), Vector3(14.0, -98.0, 1.4)]

signal nest_destroyed(count: int, total: int)

var arena: Arena
var director: RunDirector
var nests: Array[Destructible] = []
var placed: Array[Dictionary] = []   # {name, pos (Vector3), radius}: every prop put down, for the tests and the minimap
var nests_destroyed: int = 0
var total_nests: int = 3

var _rng := RandomNumberGenerator.new()
var _fill_rng := RandomNumberGenerator.new()
var _homes: Array[Vector2] = []   # (x, z) of every group put out, so the gaps between them can be found
var _keep_clear: Array[Vector3] = []   # (x, z, radius) circles the filler stays out of
var _exit: Area3D
var _exit_time: float = 0.0
var _exit_told: bool = false
## True when the road is the far end of the town's world (see TownScene): its arena is offset past the town gate, there is no exit zone
## of its own (the hero just walks back into town) and its monsters wait out there from the start. False for the standalone run.
var in_world: bool = false

# --- Building the place -------------------------------------------------------------------------------------------------------

## The arena this location needs: the long rectangle, no random scatter, and no navmesh yet (build() adds props first).
static func make_arena() -> Arena:
	var a := Arena.new()
	a.half_x = HALF_X
	a.half_z = HALF_Z
	a.scatter = false
	return a

## The arena for the road as the far end of the town's world: its south end (the road gate) is flush with the town's north edge at
## z = -town_half, the south wall left out, and it shares the navigation region `region` with the town so everyone can walk between.
static func make_world_arena(town_half: float, region: NavigationRegion3D) -> Arena:
	var a: Arena = make_arena()
	a.origin_offset = Vector3(0.0, 0.0, -town_half - HALF_Z)
	a.open_south = true
	a.shared_region = region
	return a

## A point of the road's own plan (x, z as drawn below) in the world.
func at(x: float, z: float) -> Vector3:
	return arena.origin_offset + Vector3(x, 0.0, z)

## Puts down the road, the landmarks, the filler and the lights, then bakes the navigation mesh once everything is in.
func build(for_arena: Arena) -> void:
	arena = for_arena
	in_world = arena.origin_offset != Vector3.ZERO
	_rng.seed = 1313
	_build_road()
	_landmarks()
	_graveyard()
	_cottage()
	_choke()
	_courtyard()
	_filler()
	if not in_world:
		_exit_gate()
		arena.bake_navigation()   # in the world the town bakes the one shared navigation mesh once everything is placed

## The navigation map takes its new regions on a background thread, and this one is big: true once the road is really in it.
func navigation_ready() -> bool:
	var map: RID = get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:   # a query before the first synchronisation is an error
		return false
	return NavigationServer3D.map_get_closest_point(map, at(START.x, START.z)).distance_to(at(START.x, START.z)) < 3.0

## Waits (a few seconds at most) for navigation_ready(), so monsters are not spawned onto an empty map and snapped to the origin.
func wait_for_navigation() -> void:
	for i in 900:
		if navigation_ready():
			return
		await get_tree().physics_frame

func road_distance(x: float, z: float) -> float:
	var best: float = INF
	for i in ROAD.size() - 1:
		best = minf(best, _segment_distance(Vector2(x, z), ROAD[i], ROAD[i + 1]))
	return best

func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## One prop, remembered. `clear` keeps filler away from it (defaults to its footprint plus a margin).
func _prop(model: String, x: float, z: float, yaw: float, height: float, collides: bool = true, lit: bool = false, clear: float = -1.0) -> Node3D:
	var node: Node3D = arena.place_prop(model, Vector3(x, 0.0, z), yaw, height, collides, lit)
	var radius: float = clear if clear >= 0.0 else height * 0.35
	placed.append({"name": model, "pos": Vector3(x, 0.0, z), "radius": radius})
	if radius > 0.0:
		_keep_clear.append(Vector3(x, z, radius))
	return node

func _clear_spot(x: float, z: float, margin: float = 0.0) -> bool:
	for c in _keep_clear:
		if Vector2(x, z).distance_to(Vector2(c.x, c.y)) < c.z + margin:
			return false
	return true

## `count` of a prop at random inside a rectangle (x0, z0)-(x1, z1), off the road and away from landmarks.
func _scatter(model: String, x0: float, z0: float, x1: float, z1: float, count: int, h0: float, h1: float, collides: bool = true,
		road_margin: float = 1.5) -> void:
	var made: int = 0
	var tries: int = 0
	while made < count and tries < count * 30:
		tries += 1
		var x: float = _rng.randf_range(minf(x0, x1), maxf(x0, x1))
		var z: float = _rng.randf_range(minf(z0, z1), maxf(z0, z1))
		if road_distance(x, z) < ROAD_HALF_WIDTH + road_margin or not _clear_spot(x, z, 0.6):
			continue
		var height: float = _rng.randf_range(h0, h1)
		_prop(model, x, z, _rng.randf() * TAU, height, collides, false, height * 0.18 if collides else 0.0)
		made += 1

## Props in a row from a to b (x, z), `spacing` apart, with a little jitter; `skip` leaves gaps (fraction 0..1 along the line).
func _row(model: String, a: Vector2, b: Vector2, spacing: float, height: float, jitter: float = 0.3, gaps: Array[Vector2] = []) -> void:
	var length: float = a.distance_to(b)
	var steps: int = maxi(int(length / spacing), 1)
	var yaw: float = atan2(b.x - a.x, b.y - a.y) + PI * 0.5
	for i in steps + 1:
		var u: float = float(i) / steps
		var open: bool = false
		for gap in gaps:
			if u >= gap.x and u <= gap.y:
				open = true
		if open:
			continue
		var p: Vector2 = a.lerp(b, u) + Vector2(_rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter, jitter))
		_prop(model, p.x, p.y, yaw + _rng.randf_range(-0.12, 0.12), height * _rng.randf_range(0.9, 1.1), true, false, 0.0)

## Both the dark verge and the packed road: a soft-edged ribbon laid on the ground along the centre line.
func _build_road() -> void:
	var mat: ShaderMaterial = GroundLook.material(Color(0.19, 0.16, 0.13), Color(0.45, 0.39, 0.31), Color(0.1, 0.085, 0.07), true, 1.15)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var across: Array[float] = [-1.0, -0.62, 0.62, 1.0]   # fractions of the half-width; the outer two fade to nothing
	var alpha: Array[float] = [0.0, 1.0, 1.0, 0.0]
	var rows: Array = []
	var length_so_far: float = 0.0
	var previous: Vector2 = ROAD[0]
	for i in ROAD.size():
		var here: Vector2 = ROAD[i]
		length_so_far += here.distance_to(previous)
		previous = here
		var ahead: Vector2 = ROAD[mini(i + 1, ROAD.size() - 1)] - ROAD[maxi(i - 1, 0)]
		var side := Vector2(-ahead.y, ahead.x).normalized()
		var row: Array = []
		for k in 4:
			var width: float = (ROAD_HALF_WIDTH + 1.2) * across[k]
			var p: Vector2 = here + side * width
			row.append({"p": Vector3(p.x, 0.02, p.y), "uv": Vector2(width * 0.12, length_so_far * 0.12), "a": alpha[k]})
		rows.append(row)
	for i in rows.size() - 1:
		for k in 3:
			var q: Array = [rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]]
			for idx in [0, 2, 1, 0, 3, 2]:
				var v: Dictionary = q[idx]
				st.set_color(Color(1, 1, 1, float(v["a"])))
				st.set_uv(v["uv"])
				st.set_normal(Vector3.UP)
				st.add_vertex(v["p"])
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = arena.origin_offset
	arena.add_child(mesh_instance)

func _light(parent: Node3D, color: Color, energy: float, range_m: float, height: float, flicker: bool = true) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.position = Vector3(0, height, 0)
	parent.add_child(light)
	if flicker:
		light.add_child(FlickerLight.new())
	return light

func _nest(x: float, z: float, yaw: float) -> void:
	var holder: Node3D = _prop("crypt/nest", x, z, yaw, 1.9, true, false, 4.5)
	var nest := holder as Destructible
	_light(holder, Color(0.45, 0.8, 0.2), 1.5, 8.0, 1.6)   # the sacs glow sickly green over the ground round it
	if nest != null:
		nests.append(nest)
		nest.destroyed.connect(_on_nest_destroyed)

func _landmarks() -> void:
	# The road gate, where the hero came from: open in the middle, solid posts at the sides.
	_prop("crypt/road_gate", 0.0, 171.0, 0.0, 5.4, false, false, 0.0)
	for sx in [-1.0, 1.0]:
		var post := StaticBody3D.new()
		post.collision_layer = Actor.LAYER_WORLD
		post.position = at(sx * 4.0, 171.0) + Vector3(0, 1.5, 0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.1, 3.0, 1.1)
		shape.shape = box
		post.add_child(shape)
		arena.add_child(post)
	# Stakes and stones either side of it close the road's mouth to the wilds.
	_row("dead_tree", Vector2(-27, 174), Vector2(-8, 174), 4.5, 5.0, 0.6)
	_row("dead_tree", Vector2(8, 174), Vector2(27, 174), 4.5, 5.0, 0.6)
	# The abandoned wagon: two carts, one on its side, barrels split open, and the dead beside them.
	_prop("wrecked_cart", -5.0, 106.0, 0.5, 1.9)
	_prop("wrecked_cart", 8.0, 97.0, 2.2, 1.7)
	for spot in [Vector2(-2.5, 101), Vector2(-7.5, 100), Vector2(10.5, 101)]:
		_prop("barrel", spot.x, spot.y, _rng.randf() * TAU, 1.0)
	_prop("crypt/corpse", 2.5, 102.0, 0.4, 0.5, false, false, 0.0)
	_prop("crypt/corpse", -8.5, 96.0, 2.0, 0.5, false, false, 0.0)
	# The old shrine in the middle of the road, with its brazier-light of candles.
	var shrine: Node3D = _prop("crypt/shrine", 0.0, -2.0, 0.0, 3.8, true, false, 3.6)
	_light(shrine, Color(1.0, 0.6, 0.25), 1.6, 9.0, 1.4)
	# The crypt: a sealed facade at the north end, with fire either side of its steps.
	var gate: Node3D = _prop("crypt/crypt_gate", 0.0, -166.0, 0.0, 7.6, true, false, 6.0)
	for sx in [-3.7, 3.7]:
		var fire := Node3D.new()
		fire.position = Vector3(sx, 0, 3.95)
		gate.add_child(fire)
		_light(fire, Color(1.0, 0.55, 0.2), 2.0, 10.0, 1.9)

func _graveyard() -> void:
	# West of the road, z 95..45: rows of stones in a fenced yard open to the road at two gaps, one nest at the back.
	_row("crypt/iron_fence", Vector2(-27, 94), Vector2(-9, 94), 3.0, 1.8, 0.05, [Vector2(0.55, 0.7)])
	_row("crypt/iron_fence", Vector2(-27, 44), Vector2(-9, 44), 3.0, 1.8, 0.05, [Vector2(0.3, 0.46)])
	_row("crypt/iron_fence", Vector2(-27, 94), Vector2(-27, 44), 3.0, 1.8, 0.05)
	_row("crypt/iron_fence", Vector2(-9, 94), Vector2(-9, 44), 3.0, 1.8, 0.05, [Vector2(0.18, 0.3), Vector2(0.62, 0.78)])
	# Grave slabs are flat 1.9 m models (height 0.3 makes one about 2.4 m long): rows of them, a lane left open down the middle
	# and a clearing round the nest.
	for row in 7:
		for col in 4:
			var x: float = -24.0 + col * 4.4 + _rng.randf_range(-0.4, 0.4)
			var z: float = 90.0 - row * 6.0 + _rng.randf_range(-0.6, 0.6)
			if Vector2(x, z).distance_to(Vector2(-21.0, 58.0)) < 5.5 or absf(x + 14.5) < 1.6:
				continue
			_prop("gravestone", x, z, _rng.randf_range(-0.2, 0.2) + PI, _rng.randf_range(0.28, 0.34), true, false, 0.0)
	_nest(NEST_SPOTS[0].x, NEST_SPOTS[0].y, NEST_SPOTS[0].z)
	_prop("rubble", -16.0, 74.0, 1.0, 1.0)
	_prop("dead_tree", -24.0, 80.0, 0.0, 6.0)

func _cottage() -> void:
	# East of the road, z 95..45: the collapsed cottage, a broken wall line, and a nest behind it.
	_prop("crypt/cottage_ruin", 17.0, 68.0, -0.3, 3.4, true, false, 4.5)
	_row("ruined_wall", Vector2(8, 94), Vector2(27, 94), 5.0, 2.4, 0.2, [Vector2(0.0, 0.2), Vector2(0.55, 0.7)])
	_row("ruined_wall", Vector2(8, 44), Vector2(27, 44), 5.0, 2.4, 0.2, [Vector2(0.0, 0.3)])
	_row("ruined_wall", Vector2(27, 94), Vector2(27, 44), 5.0, 2.4, 0.2)
	_nest(NEST_SPOTS[1].x, NEST_SPOTS[1].y, NEST_SPOTS[1].z)
	_prop("barrel", 11.0, 78.0, 0.3, 1.0)
	_prop("wrecked_cart", 23.0, 80.0, 1.1, 1.8)
	_prop("brazier", 12.0, 56.0, 0.0, 1.5, true, true, 0.8)

func _choke() -> void:
	# The wood closes in: dead trees both sides leave a gap a few metres wide, with ruined walls to channel it.
	_scatter("dead_tree", 4.0, 38.0, 17.0, 8.0, 12, 5.0, 6.8, true, 1.4)
	_scatter("dead_tree", -4.0, 38.0, -17.0, 8.0, 12, 5.0, 6.8, true, 1.4)
	_prop("ruined_wall", -5.0, 28.0, 1.2, 2.6)
	_prop("ruined_wall", 5.5, 12.0, -1.3, 2.6)
	_prop("rubble", 3.8, 20.0, 0.5, 1.0)
	_prop("rubble", -4.2, 34.0, 2.0, 1.0)
	_prop("brazier", -3.6, 22.0, 0.0, 1.5, true, true, 0.8)

func _courtyard() -> void:
	# z -45..-155, 44 m wide: a wall with one wide opening at the south, columns down a central avenue, braziers, graves, a nest.
	_row("ruined_wall", Vector2(-23, -44), Vector2(-5, -44), 6.3, 3.0, 0.1)
	_row("ruined_wall", Vector2(5, -44), Vector2(23, -44), 6.3, 3.0, 0.1)
	_row("ruined_wall", Vector2(-23, -44), Vector2(-23, -158), 6.3, 3.0, 0.1, [Vector2(0.38, 0.46), Vector2(0.7, 0.76)])
	_row("ruined_wall", Vector2(23, -44), Vector2(23, -158), 6.3, 3.0, 0.1, [Vector2(0.3, 0.37), Vector2(0.62, 0.7)])
	_row("ruined_wall", Vector2(-23, -158), Vector2(-6, -158), 6.7, 3.2, 0.1)
	_row("ruined_wall", Vector2(6, -158), Vector2(23, -158), 6.7, 3.2, 0.1)
	for z in [-62.0, -84.0, -106.0, -128.0]:   # the avenue's columns
		_prop("ruined_pillar", -8.0, z, 0.0, 4.2, true, false, 1.0)
		_prop("ruined_pillar", 8.0, z, 0.0, _rng.randf_range(3.0, 4.2), true, false, 1.0)
	for corner in [Vector2(-18, -52), Vector2(18, -52), Vector2(-18, -150), Vector2(18, -150), Vector2(-17, -100), Vector2(17, -78)]:
		_prop("brazier", corner.x, corner.y, 0.0, 1.5, true, true, 0.8)
	for row in 7:
		for col in 2:
			for side in [-1.0, 1.0]:
				var x: float = side * (14.0 + col * 4.8) + _rng.randf_range(-0.4, 0.4)
				var z: float = -56.0 - row * 13.0 + _rng.randf_range(-1.5, 1.5)
				if Vector2(x, z).distance_to(Vector2(14.0, -98.0)) < 6.0:
					continue
				_prop("gravestone", x, z, PI + _rng.randf_range(-0.2, 0.2), _rng.randf_range(0.28, 0.34), true, false, 0.0)
	_nest(NEST_SPOTS[2].x, NEST_SPOTS[2].y, NEST_SPOTS[2].z)
	_prop("rubble", -14.0, -90.0, 0.4, 1.1)
	_prop("rubble", 12.0, -140.0, 1.4, 1.2)

## Trees, bones and rubble everywhere that was not placed by hand; the same every time (fixed seed).
func _filler() -> void:
	_scatter("dead_tree", -29.0, 170.0, -23.0, -150.0, 46, 5.0, 7.0, true, 0.0)   # the wood either side of the road
	_scatter("dead_tree", 23.0, 170.0, 29.0, -150.0, 46, 5.0, 7.0, true, 0.0)
	_scatter("dead_tree", -22.0, 168.0, 22.0, 120.0, 16, 5.0, 6.5)
	_scatter("rubble", -22.0, 168.0, 22.0, 120.0, 8, 0.8, 1.3)
	_scatter("bones", -12.0, 168.0, 12.0, 100.0, 24, 0.3, 0.45, false, 0.0)
	_scatter("bones", -20.0, 90.0, 22.0, -150.0, 40, 0.3, 0.45, false, 0.0)
	_scatter("rubble", -20.0, -44.0, 20.0, -150.0, 10, 0.8, 1.3)
	_scatter("wrecked_cart", -20.0, 168.0, 20.0, 110.0, 2, 1.6, 1.9)

func _exit_gate() -> void:
	_exit = Area3D.new()
	_exit.collision_layer = 0
	_exit.collision_mask = Actor.LAYER_PLAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7.0, 4.0, 4.0)
	shape.shape = box
	_exit.add_child(shape)
	_exit.position = Vector3(0.0, 2.0, EXIT_Z)
	add_child(_exit)

# --- The monsters -------------------------------------------------------------------------------------------------------------

## A hand-placed group. `mode` is what they do until they notice the hero: "" stands guard, "wander" strolls about `home` (or round
## `patrol`), "feed" hunches over `feed_at`. `members` is [kind, x, z] triples.
func _group(id: int, mode: String, members: Array, home: Vector2, radius: float = 4.0, feed_at: Vector2 = Vector2.ZERO,
		patrol: Array[Vector2] = []) -> void:
	_homes.append(home)
	var threat: float = WorldThreat.for_distance(EXIT_Z - home.y)   # the stretch the group lives in
	for m in members:
		var copies: int = PACK_COPIES if String(m[0]) in ["zombie", "ghoul"] else 1
		for c in copies:
			var spot: Vector2 = Vector2(float(m[1]), float(m[2]))
			if c > 0:   # the extra bodies stand round the one that was placed
				spot += Vector2.from_angle(float(c) * 2.4 + float(m[1])) * (1.3 + 0.4 * c)
			var e: Enemy = director.spawn_enemy(Nav.snap(self, at(spot.x, spot.y)), String(m[0]), threat)
			e.group_id = id
			e.idle_mode = mode
			e.home = at(home.x, home.y)
			e.idle_radius = radius
			if mode == "feed":
				e.feed_at = at(feed_at.x, feed_at.y)
			for p in patrol:
				e.patrol.append(at(p.x, p.y))
			e.alert_delay = 0.0

## Every group, standing where the layout says. Called once the navigation map is ready (see Main).
func spawn_encounters(for_director: RunDirector) -> void:
	director = for_director
	_homes.clear()
	# Walkers on the road, the first thing the hero sees (far enough down it that they do not notice him at the start).
	_group(1, "wander", [["zombie", 2, 129], ["zombie", -2, 123]], Vector2(0, 121), 5.0, Vector2.ZERO,
		[Vector2(3, 133), Vector2(-2, 113), Vector2(2, 123)])
	# The wagon: a pack at the dead (they hunch over the corpses until the hero is close), one stray.
	_group(2, "feed", [["zombie", 1.6, 103.4], ["zombie", 3.6, 101.2], ["zombie", 2.6, 100.4]], Vector2(2.5, 102), 2.0, Vector2(2.5, 102))
	_group(2, "feed", [["zombie", -9.6, 96.8], ["zombie", -7.8, 95.2]], Vector2(-8.5, 96), 2.0, Vector2(-8.5, 96))
	_group(3, "wander", [["zombie", 12, 110]], Vector2(12, 110), 4.0)
	# The graveyard: strollers among the stones, a bloater lying in wait among the graves, and the nest's keepers.
	_group(4, "wander", [["zombie", -14, 80], ["zombie", -18, 74], ["zombie", -12, 70]], Vector2(-15, 76), 8.0)
	_group(5, "", [["bloater", -16.5, 64]], Vector2(-16.5, 64))
	_group(6, "wander", [["zombie", -23, 55], ["zombie", -19, 51], ["zombie", -24, 61], ["ghoul", -17, 56]], Vector2(-21, 57), 5.0)
	# The cottage: a line of fighters across the way in, spitters standing back behind them, the nest's keepers behind the house.
	_group(7, "", [["zombie", 13, 84], ["zombie", 17.5, 85], ["zombie", 22, 83.5]], Vector2(17, 84))
	_group(7, "", [["spitter", 16, 75], ["spitter", 22, 74]], Vector2(19, 74))
	_group(8, "wander", [["zombie", 23, 57], ["zombie", 17, 49]], Vector2(20, 53), 4.0)
	# The choke: a brute that has been standing in the road a long while, and a pair of ghouls working the trees.
	_group(9, "wander", [["brute", 3, 22]], Vector2(2, 22), 3.0)
	_group(10, "wander", [["ghoul", -7, 31], ["ghoul", -9, 27]], Vector2(-8, 29), 4.0)
	# The shrine: a plague priest among its guard, a spitter at its back.
	_group(11, "", [["priest", 0, -9.5], ["zombie", 4, -5], ["zombie", -4, -5.5], ["zombie", 5.5, -1.5], ["zombie", -5.5, -2],
		["spitter", 1, -15]], Vector2(0, -8))
	# The courtyard: patrols on the avenue, a bloater at the wall, the third nest's pack, a priest with spitters behind, brutes at the door.
	_group(12, "wander", [["zombie", -7, -62], ["zombie", 7, -66], ["zombie", -6, -74], ["zombie", 8, -72]], Vector2(0, -68), 4.0, Vector2.ZERO,
		[Vector2(-8, -68), Vector2(8, -68), Vector2(8, -118), Vector2(-8, -118)])
	_group(13, "", [["bloater", -15, -84]], Vector2(-15, -84))
	_group(14, "wander", [["ghoul", 12, -95], ["ghoul", 16, -101], ["zombie", 11, -102], ["zombie", 17, -94]], Vector2(14, -98), 5.0)
	_group(15, "", [["priest", -14, -112], ["spitter", -14, -121], ["spitter", -9, -124], ["zombie", -11, -108], ["zombie", -17, -108]], Vector2(-13, -114))
	_group(16, "", [["brute", -9, -138], ["brute", 9, -138], ["zombie", 0, -142]], Vector2(0, -139))
	_fill_gaps()

## Wherever the placed groups leave the road empty (no group's home within FILL_COVER), a small group of whatever lives in that stretch:
## zombies near the town, ghouls and the odd spitter in the middle, bloaters in the wood, spitters, brutes and priests towards the crypt.
## Every cell of a grid across the whole strip is checked, and the same seed gives the same monsters each time.
func _fill_gaps() -> void:
	_fill_rng.seed = FILL_SEED + TownState.road_seed * 977   # every reset of the road (TownState.road_seed) stocks the empty stretches differently
	var group: int = 200
	var z: float = HALF_Z - 12.0
	while z > -HALF_Z + 14.0:
		var x: float = -HALF_X + 9.0
		while x < HALF_X - 6.0:
			var spot := Vector2(x + _fill_rng.randf_range(-3.0, 3.0), z + _fill_rng.randf_range(-3.0, 3.0))
			x += FILL_CELL
			if spot.distance_to(Vector2(START.x, START.z)) < FILL_KEEP_FROM_START or absf(spot.y) > HALF_Z - 10.0:
				continue
			var covered: bool = false
			for h in _homes:
				covered = covered or h.distance_to(spot) < FILL_COVER
			if covered:
				continue
			var snapped: Vector3 = Nav.snap(self, at(spot.x, spot.y))
			if snapped.distance_to(at(spot.x, spot.y)) > 4.0:   # inside a tree stand or a wall: nothing lives there
				continue
			_homes.append(spot)
			group += 1
			var zone: ZoneDef = TownDb.zone_at(EXIT_Z - spot.y)
			if zone == null or _fill_rng.randf() >= zone.density:
				continue
			var members: Array = []
			for kind in _fill_kinds(zone):
				var offset: Vector2 = Vector2.from_angle(_fill_rng.randf() * TAU) * _fill_rng.randf_range(0.6, 2.8)
				members.append([kind, spot.x + offset.x, spot.y + offset.y])
			_group(group, "wander" if _fill_rng.randf() < 0.6 else "", members, spot, 5.0, Vector2.ZERO, [])
		z -= FILL_CELL

## What a gap-filling group is made of in this stretch: one of the zone's group templates, picked by weight (the run's modifiers make some
## likelier: a Spitters' Nest favours the groups with spitters in them), and made bigger or smaller by the modifiers' count multiplier.
func _fill_kinds(zone: ZoneDef) -> Array[String]:
	var total: float = 0.0
	var weights: Array[float] = []
	for template in zone.groups:
		var w: float = float(template["weight"]) * director.group_weight(template["members"])
		weights.append(w)
		total += w
	var roll: float = _fill_rng.randf() * total
	var chosen: Array = zone.groups[0]["members"]
	for i in zone.groups.size():
		roll -= weights[i]
		if roll <= 0.0:
			chosen = zone.groups[i]["members"]
			break
	var out: Array[String] = []
	for kind in chosen:
		out.append(String(kind))
	var mult: float = director.group_count_mult()
	var wanted: int = maxi(int(round(float(out.size()) * mult)), 1)
	while out.size() < wanted:
		out.append(out[_fill_rng.randi() % out.size()])
	while out.size() > wanted:
		out.pop_back()
	return out

# --- The nests ------------------------------------------------------------------------------------------------------------------

func _on_nest_destroyed(prop: Destructible) -> void:
	nests_destroyed += 1
	TownState.add_hero_xp(HeroProgression.NEST_XP)   # when it breaks (a prop breaks once), not when the quest is handed in
	HeroProgression.log_xp("nest %d of %d: %d" % [nests_destroyed, total_nests, HeroProgression.NEST_XP])
	nest_destroyed.emit(nests_destroyed, total_nests)
	if director == null:
		return
	var at: Vector3 = prop.global_position
	# What lived nearby is stirred up: every monster within a good throw of the nest turns on the hero (and so does its group).
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy != null and not enemy.dead and enemy.global_position.distance_to(at) < 26.0:
			enemy.wake()
	# And what was inside comes out: a few things claw up out of the broken mound (not a wave; it happens once, here).
	var kinds: Array[String] = []
	kinds.assign(["zombie", "zombie", "ghoul"] if nests_destroyed < total_nests else ["zombie", "ghoul", "ghoul", "brute"])
	for i in kinds.size():
		var angle: float = TAU * float(i) / kinds.size()
		var spot: Vector3 = Nav.snap(self, at + Vector3(cos(angle), 0.0, sin(angle)) * 2.4)
		var e: Enemy = director.spawn_enemy(spot, kinds[i], threat_at(at))
		e.group_id = 100 + nests_destroyed
		e.alert_delay = 0.0
		e.wake()

## The quest was handed in: the road is corrupted again. Whatever is left of the monsters goes, the nests grow back where they were and
## every group is put out again.
## Where the road runs at a given z (its centre line), for putting something on it.
func road_centre_x(z: float) -> float:
	for i in range(ROAD.size() - 1):
		var a: Vector2 = ROAD[i]
		var b: Vector2 = ROAD[i + 1]
		if (z <= a.y and z >= b.y) or (z >= a.y and z <= b.y):
			var t: float = 0.0 if is_equal_approx(a.y, b.y) else (z - a.y) / (b.y - a.y)
			return lerpf(a.x, b.x, t)
	return ROAD[ROAD.size() - 1].x

## A named monster for a quest (see Quests, kind "slay_unique"): a tougher one of its kind, somewhere in the stretch of road the quest
## names (distances from the town gate), wandering about its spot. It drops a good item when it dies.
func spawn_unique(inst: Dictionary) -> Enemy:
	var def: QuestDef = Quests.def_of(inst)
	if director == null or def == null:
		return null
	var z: float = clampf(EXIT_Z - randf_range(def.zone.x, def.zone.y), -140.0, 130.0)
	var spot: Vector3 = Nav.snap(self, at(road_centre_x(z) + randf_range(-4.0, 4.0), z))
	var e: Enemy = director.spawn_enemy(spot, def.target, def.unique_level)   # unique_level is an absolute threat, on the zones' scale
	e.display_name = def.unique_name
	e.max_health *= def.unique_hp
	e.health = e.max_health
	if e.visual != null:
		e.visual.scale *= 1.2
	e.idle_mode = "wander"
	e.home = spot
	e.idle_radius = 8.0
	e.group_id = 300 + int(inst["uid"])
	e.alert_delay = 0.0
	e.set_meta("quest_uid", int(inst["uid"]))
	QuestMarker.attach(e)
	inst["data"]["spawned"] = true
	return e

## The threat of ordinary monsters where a point on the road is (see WorldThreat): the stretch's own, whatever the hero has become.
func threat_at(point: Vector3) -> float:
	return WorldThreat.for_distance(distance_of(point))

## How far out from the town gate a point on the road is (metres), the measure a named monster's place is kept in.
func distance_of(point: Vector3) -> float:
	return EXIT_Z - (point.z - arena.origin_offset.z)

## Where a named monster (see Monsters) lives on the road, from its distance out from the gate and its side of the road.
func monster_spot(mon: Dictionary) -> Vector3:
	var z: float = clampf(EXIT_Z - float(mon["dist"]), -140.0, 130.0)
	return Nav.snap(self, at(road_centre_x(z) + float(mon["lane"]), z))

## A named monster, put on the road at its place: a body of its kind with its level's strength, marked so it can be found.
func spawn_named(mon: Dictionary) -> Enemy:
	if director == null:
		return null
	var spot: Vector3 = monster_spot(mon)
	var e: Enemy = director.spawn_enemy(spot, String(mon["kind"]), float(mon["level"]))   # its threat is its own level, not the stretch's
	e.display_name = String(mon["name"])
	e.idle_mode = "wander"
	e.home = spot
	e.idle_radius = 8.0
	e.group_id = 500 + int(mon["uid"])
	e.alert_delay = 0.0
	MonsterMark.apply_look(e, mon)
	MonsterMark.attach(e, mon)
	mon["spawned"] = true
	return e

## A horde climbs out of the ground around a named monster (its uprising).
func spawn_horde(mon: Dictionary, count: int = 8) -> void:
	if director == null:
		return
	var centre: Vector3 = monster_spot(mon)
	for i in count:
		var angle: float = TAU * float(i) / count
		var spot: Vector3 = Nav.snap(self, centre + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(3.0, 6.0))
		var e: Enemy = director.spawn_enemy(spot, "ghoul" if i % 3 == 0 else "zombie", threat_at(centre))
		e.group_id = 600 + int(mon["uid"])
		e.alert_delay = 0.0
		e.idle_mode = "wander"
		e.home = centre
		e.idle_radius = 9.0

func regrow() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	var alive: Array[Destructible] = []
	for nest in nests:
		if is_instance_valid(nest) and not nest.broken:
			alive.append(nest)
	nests = alive
	var have: Array[Vector3] = []
	for nest in nests:
		have.append(nest.global_position)
	for spot in NEST_SPOTS:
		var wanted: Vector3 = at(spot.x, spot.y)
		var present: bool = false
		for h in have:
			present = present or h.distance_to(wanted) < 1.0
		if not present:
			_nest(spot.x, spot.y, spot.z)
	nests_destroyed = 0
	arena.request_nav_refresh()
	await get_tree().process_frame
	spawn_encounters(director)

# --- Leaving ----------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if in_world or _exit == null or director == null or director.player == null or director.is_ending():
		return
	var inside: bool = _exit.overlaps_body(director.player)
	if not inside:
		_exit_time = 0.0
		_exit_told = false
		return
	_exit_time += delta
	if nests_destroyed >= total_nests:
		if _exit_time > 0.4:
			director.request_exit()
		return
	# Walking back out before the nests are gone abandons the job; stay a moment in the gate to mean it.
	if not _exit_told:
		_exit_told = true
		director.hud.show_banner("The road home\nStay in the gate to abandon the job", 2.4)
	if _exit_time > 2.6:
		director.request_exit()
