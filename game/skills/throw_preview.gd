class_name ThrowPreview
extends RefCounted
## What holding Weapon Throw shows on the ground: a narrow lane from the hero to where the weapon will land, as long as the charge so far
## (it grows while the button is held) and cut short where a wall or a prop would stop it, with chevrons running down it and a mark where
## the blade will bite. Flat, unlit, dull steel, drawn the way Skewer's lane and Power Strike's strip are: no laser.

const HALF_WIDTH := 0.3
const HEIGHT := 0.07
const WALL_MARGIN := 0.45

var node: MeshInstance3D
var length: float = 0.0          # the lane as drawn, for tests
var blocked: bool = false        # true when a wall or a prop cut it short
var _mesh := ImmediateMesh.new()

func _init(owner_node: Node3D) -> void:
	node = MeshInstance3D.new()
	node.mesh = _mesh
	node.top_level = true
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.visible = false
	owner_node.add_child(node)

## How far a weapon launched along `dir` from `from` really gets (at the height it flies) before something solid stops it: three rays, one
## down the middle and one along each edge, so a post at the side shortens it too. `reach` when nothing is in the way.
static func clear_length(world: World3D, from: Vector3, dir: Vector3, reach: float, height: float = 1.0) -> float:
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var shortest: float = reach
	for offset in [0.0, HALF_WIDTH, -HALF_WIDTH]:
		var start: Vector3 = Vector3(from.x, height, from.z) + side * offset
		var query := PhysicsRayQueryParameters3D.create(start, start + dir * (reach + WALL_MARGIN), Actor.LAYER_WORLD)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			shortest = minf(shortest, maxf(start.distance_to(hit["position"]) - WALL_MARGIN, 0.5))
	return shortest

func show_lane(world: World3D, from: Vector3, dir: Vector3, reach: float, pulse: float, clock: float) -> void:
	length = clear_length(world, from, dir, reach)
	blocked = length < reach - 0.01
	var origin := Vector3(from.x, from.y + HEIGHT, from.z)
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var end: Vector3 = origin + dir * length
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(origin - side * HALF_WIDTH, origin + side * HALF_WIDTH, end + side * HALF_WIDTH, end - side * HALF_WIDTH,
		Color(0.85, 0.78, 0.62, 0.07 + 0.04 * pulse))
	var edge := Color(1.0, 0.74, 0.34, 0.6)
	_strip(origin + side * HALF_WIDTH, end + side * HALF_WIDTH, 0.07, edge)
	_strip(origin - side * HALF_WIDTH, end - side * HALF_WIDTH, 0.07, edge)
	# Chevrons running out along it, toward where the blade will land.
	var spacing: float = 1.6
	var d: float = fmod(clock * 4.0, spacing)
	while d < length - 0.3:
		var tip: Vector3 = origin + dir * (d + 0.4)
		var fade: float = clampf(1.0 - d / maxf(length, 1.0), 0.25, 1.0)
		var col := Color(1.0, 0.7, 0.3, 0.5 * fade)
		_strip(origin + dir * d - side * HALF_WIDTH * 0.8, tip, 0.08, col)
		_strip(origin + dir * d + side * HALF_WIDTH * 0.8, tip, 0.08, col)
		d += spacing
	# Where it lands: a bar across the end and a small X of the blade biting the ground (red when a wall or a prop cuts it short).
	var mark := Color(0.95, 0.45, 0.22, 0.85) if blocked else Color(1.0, 0.8, 0.4, 0.85)
	_strip(end - side * HALF_WIDTH * 1.5, end + side * HALF_WIDTH * 1.5, 0.12, mark)
	_strip(end - side * 0.22 - dir * 0.22, end + side * 0.22 + dir * 0.22, 0.07, mark)
	_strip(end + side * 0.22 - dir * 0.22, end - side * 0.22 + dir * 0.22, 0.07, mark)
	_mesh.surface_end()
	node.global_transform = Transform3D.IDENTITY
	node.visible = true

func hide_lane() -> void:
	node.visible = false

func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for v in [a, b, c]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(a, b, c, color)
	_tri(a, c, d, color)

func _strip(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var along: Vector3 = to - from
	if along.length() < 0.001:
		return
	var across: Vector3 = Vector3(-along.z, 0.0, along.x).normalized() * width * 0.5
	var lift := Vector3(0, 0.01, 0)
	_quad(from - across + lift, from + across + lift, to + across + lift, to - across + lift, color)
