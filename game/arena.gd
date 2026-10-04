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

func build(bake_navigation: bool = true) -> void:
	_nav_region = NavigationRegion3D.new()
	add_child(_nav_region)
	_build_ground()
	_build_walls()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed_any: bool = false
	for prop_name in PROPS:
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
	if not placed_any:
		for i in 18:
			var pos := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
			if pos.length() >= 6.0:
				_add_pillar(Vector3(pos.x, 0, pos.y), rng.randf_range(0.7, 1.4), rng.randf_range(2.0, 4.5))
	if bake_navigation:
		_bake_navigation()

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
	box.size = Vector3(HALF * 2.0, 1.0, HALF * 2.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.1, 0.1, 0.09))
	gradient.set_color(1, Color(0.26, 0.24, 0.2))
	var albedo := NoiseTexture2D.new()
	albedo.noise = noise
	albedo.color_ramp = gradient
	albedo.seamless = true
	albedo.width = 1024
	albedo.height = 1024
	var bump := NoiseTexture2D.new()
	bump.noise = noise
	bump.as_normal_map = true
	bump.bump_strength = 2.0
	bump.seamless = true
	bump.width = 1024
	bump.height = 1024
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo
	mat.normal_enabled = true
	mat.normal_texture = bump
	mat.uv1_scale = Vector3(9, 9, 1)
	mat.roughness = 1.0
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF * 2.0, HALF * 2.0)
	mesh_instance.mesh = plane
	mesh_instance.material_override = mat
	ground.add_child(mesh_instance)
	_nav_region.add_child(ground)

func _place(prop_name: String, scene: PackedScene, pos: Vector3, yaw: float, height: float, collides: bool, lit: bool) -> void:
	var prop: Node3D = scene.instantiate()
	var bounds: AABB = CharacterModel._bounds_of(prop)
	var factor: float = height / maxf(bounds.size.y, 0.001)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	prop.scale = Vector3.ONE * factor
	# Centre horizontally and sit the base on the ground.
	prop.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * factor
	holder.add_child(prop)
	if collides:
		var body := StaticBody3D.new()
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
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 2.2
		light.omni_range = 9.0
		light.position = Vector3(0, height * 0.9, 0)
		holder.add_child(light)
		var flicker := FlickerLight.new()
		light.add_child(flicker)
	if collides:
		obstacles.append({"position": pos, "radius": maxf(bounds.size.x, bounds.size.z) * factor * 0.5})
	_nav_region.add_child(holder)

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
		shape.shape = mi.mesh.create_convex_shape(true, true)
		shape.transform = Transform3D(Basis().scaled(Vector3.ONE * factor), prop.position) * rel
		body.add_child(shape)

## Invisible walls so nothing can leave the arena.
func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var along_x: bool = side.x != 0.0
		box.size = Vector3(1.0 if along_x else HALF * 2.0, 8.0, HALF * 2.0 if along_x else 1.0)
		shape.shape = box
		shape.position = side * (HALF + 0.5) + Vector3(0, 4.0, 0)
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
