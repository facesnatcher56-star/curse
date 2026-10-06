class_name SkewerPreview
extends RefCounted
## What holding the Skewer key shows on the ground: the whole lane the charge will run (as wide as the blade catches, as long as the
## charge goes before a wall or tree stops it), and at its end the fan the kicked enemies are thrown across. Drawn flat and unlit in
## dull steel and blood red, so it reads from the far zoom without looking like a UI sticker.

const LANE_HALF_WIDTH := 1.1     # the catch width: SkewerSkill._skewer_catch_enemies (0.75 plus a zombie's reach)
const SKID := 0.7                # about how far the planted-feet skid carries on after the charge
const KICK_FAN_ANGLE := 1.2      # the kicked enemies leave at random angles within this fan (SkewerSkill._skewer_kick throws each one differently)
const KICK_FAN_RANGE := 9.0      # and fly about this far (measured by the self-test: the farthest victim reached 9.1 m)
const WALL_MARGIN := 0.55        # the hero's body: the charge stops this far short of what blocks it
const HEIGHT := 0.07             # just above the ground

var node: MeshInstance3D
var length: float = 0.0          # the lane as drawn, for tests
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

## How far the charge can really run along `dir` from `from`: the skill's range plus the skid, cut short where the lane meets a wall,
## a tree or a prop (three rays, one down the middle and one along each edge, so a post at the side shortens it too).
func lane_length(world: World3D, from: Vector3, dir: Vector3, reach: float) -> float:
	var full: float = reach + SKID
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var shortest: float = full
	for offset in [0.0, LANE_HALF_WIDTH * 0.85, -LANE_HALF_WIDTH * 0.85]:
		var start: Vector3 = from + Vector3(0, 0.9, 0) + side * offset
		var query := PhysicsRayQueryParameters3D.create(start, start + dir * (full + WALL_MARGIN), Actor.LAYER_WORLD)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			shortest = minf(shortest, maxf(start.distance_to(hit["position"]) - WALL_MARGIN, 1.0))
	return shortest

func show_lane(world: World3D, from: Vector3, dir: Vector3, reach: float, pulse: float) -> void:
	length = lane_length(world, from, dir, reach)
	var origin := Vector3(from.x, from.y + HEIGHT, from.z)
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var end: Vector3 = origin + dir * length
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# The kick fan first (underneath): where the pile is thrown, at the end of the lane.
	var fan := Color(0.62, 0.08, 0.05, 0.07 + 0.04 * pulse)
	var steps: int = 8
	for i in steps:
		var a0: float = -KICK_FAN_ANGLE + 2.0 * KICK_FAN_ANGLE * float(i) / steps
		var a1: float = -KICK_FAN_ANGLE + 2.0 * KICK_FAN_ANGLE * float(i + 1) / steps
		_tri(end, end + dir.rotated(Vector3.UP, a0) * KICK_FAN_RANGE, end + dir.rotated(Vector3.UP, a1) * KICK_FAN_RANGE, fan)
	# The lane itself: a faint steel fill, bright edges and a bar across the end.
	_quad(origin - side * LANE_HALF_WIDTH, origin + side * LANE_HALF_WIDTH, end + side * LANE_HALF_WIDTH, end - side * LANE_HALF_WIDTH,
		Color(0.85, 0.78, 0.62, 0.08 + 0.04 * pulse))
	var edge := Color(1.0, 0.74, 0.34, 0.75)
	_strip(origin + side * LANE_HALF_WIDTH, end + side * LANE_HALF_WIDTH, 0.09, edge)
	_strip(origin - side * LANE_HALF_WIDTH, end - side * LANE_HALF_WIDTH, 0.09, edge)
	_strip(end - side * LANE_HALF_WIDTH, end + side * LANE_HALF_WIDTH, 0.14, edge)
	_mesh.surface_end()
	node.global_transform = Transform3D.IDENTITY
	node.visible = true

func hide_lane() -> void:
	node.visible = false

# --- Triangles ----------------------------------------------------------------------------------------------------------------

func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for v in [a, b, c]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(a, b, c, color)
	_tri(a, c, d, color)

## A thin flat strip between two points.
func _strip(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var along: Vector3 = to - from
	if along.length() < 0.001:
		return
	var across: Vector3 = Vector3(-along.z, 0.0, along.x).normalized() * width * 0.5
	var lift := Vector3(0, 0.01, 0)
	_quad(from - across + lift, from + across + lift, to + across + lift, to - across + lift, color)
