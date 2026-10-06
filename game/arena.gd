class_name Arena
extends Node3D
## Ground plus scattered Meshy props (ruins, graves, dead trees, braziers...).

const HALF := 40.0
const PROP_DIR := "res://assets/models/"

## name -> [count, target height (m), collides, lit]
const PROPS := {
	"ruined_pillar": [7, 4.0, true, false],
	"gravestone": [16, 1.3, true, false],
	"dead_tree": [12, 5.5, true, false],
	"rubble": [9, 1.1, true, false],
	"ruined_wall": [6, 2.6, true, false],
	"barrel": [7, 1.0, true, false],
	"brazier": [7, 1.5, true, true],
	"bones": [14, 0.35, false, false],
	"wrecked_cart": [3, 1.9, true, false],
}

## Centres and radii of solid props, for tests and AI hints.
var obstacles: Array[Dictionary] = []
var _nav_region: NavigationRegion3D
## The town reuses the arena's ground, walls, prop placement and navmesh with its own, smaller size and no random scatter.
var half: float = HALF:
	set(value):
		half = value
		half_x = value
		half_z = value
## The footprint is a rectangle: `half_x` either side of the middle across, `half_z` along. Setting `half` makes it square; an
## authored location (the Crypt Road) sets the two separately for a long, narrow area.
var half_x: float = HALF
var half_z: float = HALF
var scatter: bool = true
## Where this arena's middle is in the world. The Crypt Road is an arena of its own, laid end to end with the town's, so everything
## here (ground, walls, props, obstacles) is placed at `origin_offset` plus the position it is given.
var origin_offset: Vector3 = Vector3.ZERO
## Leave the +z wall out: another arena (the town) joins this one there.
var open_south: bool = false
## One navigation region for several arenas, so a character can path from one into the next. Whoever owns it bakes it once everything
## is placed (`bake_navigation`); each arena just adds its geometry to it.
var shared_region: NavigationRegion3D
## The invisible wall round the edge. The town turns it off and builds its own, with a real opening at the gate.
var build_perimeter_walls: bool = true

var _stage_ms: int = 0

## `-- --timing`: print how long each part of building the arena takes.
func _stage(label: String) -> void:
	if OS.get_cmdline_user_args().has("--timing"):
		var now: int = Time.get_ticks_msec()
		print("[arena] %-14s +%4d ms" % [label, now - _stage_ms])
		_stage_ms = now

## How far the walls are from the middle (x across, z along) of the arena in this scene; the square arena's size when there is none.
static func bounds_of(tree: SceneTree) -> Vector2:
	var arena := tree.get_first_node_in_group("arena") as Arena if tree != null else null
	return Vector2(arena.half_x, arena.half_z) if arena != null else Vector2(HALF, HALF)

## Keeps a ground point inside the walls of whichever arena it is in (or, off the map, the nearest one), `margin` metres short of them.
## With one arena that is just its walls; with the town and the road end to end it is whichever the point belongs to.
static func clamp_point(tree: SceneTree, point: Vector3, margin: float = 0.0) -> Vector3:
	var best: Arena = null
	var best_gap: float = INF
	for node in tree.get_nodes_in_group("arena") if tree != null else []:
		var a := node as Arena
		var local: Vector3 = point - a.origin_offset
		var gap: float = maxf(absf(local.x) - a.half_x, 0.0) + maxf(absf(local.z) - a.half_z, 0.0)
		if gap < best_gap:
			best_gap = gap
			best = a
	var half := Vector2(best.half_x, best.half_z) if best != null else Vector2(HALF, HALF)
	var offset: Vector3 = best.origin_offset if best != null else Vector3.ZERO
	return Vector3(clampf(point.x - offset.x, -half.x + margin, half.x - margin) + offset.x, point.y,
		clampf(point.z - offset.z, -half.y + margin, half.y - margin) + offset.z)

func build(bake_navigation: bool = true) -> void:
	add_to_group("arena")
	_stage_ms = Time.get_ticks_msec()
	if shared_region != null:
		_nav_region = shared_region
	else:
		_nav_region = NavigationRegion3D.new()
		add_child(_nav_region)
	_build_ground()
	_stage("ground")
	if build_perimeter_walls:
		_build_walls()
	_stage("walls")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed_any: bool = false
	for prop_name in (PROPS if scatter else {}):
		var spec: Array = PROPS[prop_name]
		var path: String = PROP_DIR + prop_name + "/model.glb"
		if not ResourceLoader.exists(path):
			continue
		placed_any = true
		var scene: PackedScene = load(path)
		for i in int(spec[0]):
			var pos := Vector2(rng.randf_range(-HALF + 3, HALF - 3), rng.randf_range(-HALF + 3, HALF - 3))
			if pos.length() < 7.0:
				pos = pos.normalized() * (7.0 + rng.randf() * 4.0)
			_place(prop_name, scene, Vector3(pos.x, 0, pos.y), rng.randf() * TAU,
				float(spec[1]) * rng.randf_range(0.85, 1.2), bool(spec[2]), bool(spec[3]))
	_stage("props")
	if not placed_any and scatter:
		for i in 18:
			var pos := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
			if pos.length() >= 6.0:
				_add_pillar(Vector3(pos.x, 0, pos.y), rng.randf_range(0.7, 1.4), rng.randf_range(2.0, 4.5))
	if bake_navigation:
		_bake_navigation()
		_stage("nav bake")

## Bakes a navigation mesh from the static colliders (ground, walls, props) so characters can path around them.
func _bake_navigation() -> void:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.75       # whole cells (3 x 0.25); comfortably clears the widest regular enemy
	mesh.agent_height = 1.75
	mesh.agent_max_climb = 0.25
	mesh.cell_size = 0.25     # must match the navigation map (default 0.25) to avoid rasterisation warnings
	mesh.cell_height = 0.25
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	_nav_region.navigation_mesh = mesh
	_nav_region.bake_navigation_mesh(false)

func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half_x * 2.0, 1.0, half_z * 2.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)

	var mat: ShaderMaterial = GroundLook.material(Color(0.11, 0.105, 0.092), Color(0.33, 0.30, 0.25), Color(0.065, 0.062, 0.058))
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_x * 2.0, half_z * 2.0)
	mesh_instance.mesh = plane
	mesh_instance.material_override = mat
	ground.add_child(mesh_instance)
	ground.position = origin_offset
	_nav_region.add_child(ground)

## Puts a prop (a res://assets/models/<name>/model.glb) on the ground at `pos`, `height` metres tall, with convex-hull collision.
func place_prop(prop_name: String, pos: Vector3, yaw: float, height: float, collides: bool = true, lit: bool = false) -> Node3D:
	return _place(prop_name, load(PROP_DIR + prop_name + "/model.glb"), pos, yaw, height, collides, lit)

## A prop was smashed: bake the walkable area again (shortly after the last one, on a thread) so nobody keeps walking round a barrel
## that is no longer there.
func request_nav_refresh() -> void:
	if _nav_refresh_pending or _nav_region == null or not is_inside_tree():
		return
	if OS.get_cmdline_user_args().has("--selftest"):
		return   # a re-bake in the middle of a check would change the navigation map under it
	_nav_refresh_pending = true
	await get_tree().create_timer(0.8).timeout
	_nav_refresh_pending = false
	if _nav_region != null and is_instance_valid(_nav_region) and _nav_region.navigation_mesh != null:
		_nav_region.bake_navigation_mesh(true)

var _nav_refresh_pending: bool = false

## Bakes the navigation mesh after props were added by hand.
func bake_navigation() -> void:
	_bake_navigation()

func _place(prop_name: String, scene: PackedScene, pos: Vector3, yaw: float, height: float, collides: bool, lit: bool) -> Node3D:
	var prop: Node3D = scene.instantiate()
	if prop_name.begins_with("town/") or prop_name.begins_with("crypt/"):   # Blender-made, painted on the vertices (tools/blender/)
		LootDrop._use_vertex_colours(prop)
	var kind: String = prop_name.get_file()   # "crypt/nest" is a "nest" to Destructible
	var bounds: AABB = CharacterModel._bounds_of(prop)
	var factor: float = height / maxf(bounds.size.y, 0.001)
	var breakable: bool = collides and Destructible.STATS.has(kind)
	var holder: Node3D = Destructible.new() if breakable else Node3D.new()
	var body: StaticBody3D = null
	var light: OmniLight3D = null
	holder.position = pos + origin_offset
	holder.rotation.y = yaw
	prop.scale = Vector3.ONE * factor
	# Centre horizontally and sit the base on the ground.
	prop.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * factor
	holder.add_child(prop)
	if collides:
		body = StaticBody3D.new()
		body.collision_layer = Actor.LAYER_WORLD
		if prop_name == "dead_tree":
			# Only the trunk blocks; a hull around the whole tree would wall off its branches.
			var trunk := CollisionShape3D.new()
			var cylinder := CylinderShape3D.new()
			cylinder.radius = maxf(bounds.size.x, bounds.size.z) * factor * 0.09
			cylinder.height = height
			trunk.shape = cylinder
			trunk.position.y = height * 0.5
			body.add_child(trunk)
		else:
			_add_hull_shapes(body, prop, factor)
		holder.add_child(body)
	if lit:
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 2.2
		light.omni_range = 9.0
		light.distance_fade_enabled = true   # a brazier far from the camera is not worth a light
		light.distance_fade_begin = 30.0
		light.distance_fade_length = 10.0
		light.position = Vector3(0, height * 0.9, 0)
		holder.add_child(light)
		var flicker := FlickerLight.new()
		light.add_child(flicker)
	var footprint: float = maxf(bounds.size.x, bounds.size.z) * factor * 0.5
	var obstacle: Dictionary = {"position": pos + origin_offset, "radius": footprint}
	if collides:
		obstacles.append(obstacle)
	_nav_region.add_child(holder)
	if breakable:
		(holder as Destructible).configure(self, kind, prop, body, light, obstacle, footprint, height)
	return holder

var _hulls: Dictionary = {}   # mesh -> its convex hull: every copy of a prop shares one hull instead of recomputing it

func _hull_for(mesh: Mesh) -> Shape3D:
	if not _hulls.has(mesh):
		_hulls[mesh] = mesh.create_convex_shape(true, true)
	return _hulls[mesh]

## One convex hull per mesh, so collision follows the real silhouette instead of a box.
func _add_hull_shapes(body: StaticBody3D, prop: Node3D, factor: float) -> void:
	for child in prop.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var rel: Transform3D = Transform3D.IDENTITY
		var walker: Node = mi
		while walker != null and walker != prop:
			rel = (walker as Node3D).transform * rel
			walker = walker.get_parent()
		var shape := CollisionShape3D.new()
		shape.shape = _hull_for(mi.mesh)
		shape.transform = Transform3D(Basis().scaled(Vector3.ONE * factor), prop.position) * rel
		body.add_child(shape)

## Invisible walls so nothing can leave the arena.
func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.position = origin_offset
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		if open_south and side.z > 0.0:
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var along_x: bool = side.x != 0.0
		box.size = Vector3(1.0 if along_x else half_x * 2.0, 8.0, half_z * 2.0 if along_x else 1.0)
		shape.shape = box
		shape.position = Vector3(side.x * (half_x + 0.5), 4.0, side.z * (half_z + 0.5))
		body.add_child(shape)
	_nav_region.add_child(body)

func _add_pillar(pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.position = pos
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position.y = height * 0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = radius * 0.9
	cyl_mesh.bottom_radius = radius
	cyl_mesh.height = height
	mesh.mesh = cyl_mesh
	mesh.position.y = height * 0.5
	body.add_child(mesh)
	_nav_region.add_child(body)
