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
var bounce_length: float = 0.0   # Ricochet: the second segment as drawn (0 when none is predicted)
var bounce_dir: Vector3 = Vector3.ZERO
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

## The first wall in the way (three rays, as `clear_length`): {position, normal, distance}, or {} when the reach is clear.
static func wall_ahead(world: World3D, from: Vector3, dir: Vector3, reach: float, height: float = 1.0) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var start: Vector3 = Vector3(from.x, height, from.z)
	var query := PhysicsRayQueryParameters3D.create(start, start + dir * (reach + WALL_MARGIN), Actor.LAYER_WORLD)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty() or absf((hit["normal"] as Vector3).y) >= 0.6:
		return {}
	return {"position": hit["position"], "normal": hit["normal"], "distance": start.distance_to(hit["position"])}

func show_lane(world: World3D, from: Vector3, dir: Vector3, reach: float, pulse: float, clock: float, bank: bool = false) -> void:
	length = clear_length(world, from, dir, reach)
	blocked = length < reach - 0.01
	bounce_length = 0.0
	bounce_dir = Vector3.ZERO
	var bounce: Dictionary = {}
	if bank:   # Ricochet: the lane runs to the wall and a dimmer one carries on, reflected about the wall's real normal
		bounce = wall_ahead(world, from, dir, reach)
		if not bounce.is_empty():
			length = maxf(float(bounce["distance"]) - 0.1, 0.5)
			blocked = false
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
	if not bounce.is_empty():
		var n: Vector3 = Vector3(bounce["normal"].x, 0.0, bounce["normal"].z).normalized()
		var out: Vector3 = dir.bounce(n)
		out.y = 0.0
		out = out.normalized()
		var wall_point: Vector3 = Vector3(bounce["position"].x, origin.y, bounce["position"].z) + n * 0.3
		var left: float = maxf(reach - float(bounce["distance"]), 1.0) * BuildDefs.RICOCHET_RANGE_KEEP
		var after: float = clear_length(world, wall_point, out, maxf(left, 2.5))
		bounce_dir = out
		bounce_length = after
		var bounce_side: Vector3 = Vector3(-out.z, 0.0, out.x)
		var bend := Color(1.0, 0.82, 0.45, 0.8)
		var tail: Vector3 = wall_point + out * after
		_quad(wall_point - bounce_side * HALF_WIDTH * 0.7, wall_point + bounce_side * HALF_WIDTH * 0.7, tail + bounce_side * HALF_WIDTH * 0.7, tail - bounce_side * HALF_WIDTH * 0.7,
			Color(0.85, 0.78, 0.62, 0.05 + 0.03 * pulse))
		_strip(wall_point + bounce_side * HALF_WIDTH * 0.7, tail + bounce_side * HALF_WIDTH * 0.7, 0.06, Color(1.0, 0.74, 0.34, 0.45))
		_strip(wall_point - bounce_side * HALF_WIDTH * 0.7, tail - bounce_side * HALF_WIDTH * 0.7, 0.06, Color(1.0, 0.74, 0.34, 0.45))
		_strip(end - side * HALF_WIDTH * 1.6, end + side * HALF_WIDTH * 1.6, 0.12, bend)   # the wall mark, where it will glance
		_strip(tail - bounce_side * HALF_WIDTH * 1.2, tail + bounce_side * HALF_WIDTH * 1.2, 0.1, mark)
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
