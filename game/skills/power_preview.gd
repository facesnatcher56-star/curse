class_name PowerPreview
extends RefCounted
## What the Power Strike's wind-up shows on the ground when the weapon sends out a shockwave (Gravewarden): the strip the wave will tear
## along, as wide and as long as it really hits (ItemEffects.power_shockwave), with chevrons running down it toward where it ends, so the
## blow can be placed before it lands. Flat, unlit and ember-coloured, drawn the same way as Skewer's lane.

const FROM := 0.5            # the wave hits from this far out (ItemEffects.power_shockwave: along > 0.5)
const REACH := 8.5           # ... to this far
const HALF_WIDTH := 1.2      # ... and this wide on either side
const HEIGHT := 0.08

var node: MeshInstance3D
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

## `strength` 0..1 fades it in as the blow is gathered; `clock` runs the chevrons.
func show_wave(from: Vector3, dir: Vector3, strength: float, clock: float) -> void:
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var origin: Vector3 = Vector3(from.x, from.y + HEIGHT, from.z)
	var a: Vector3 = origin + dir * FROM
	var b: Vector3 = origin + dir * REACH
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# A faint fill that is strongest at the start and thins out toward the far end.
	var near := Color(1.0, 0.55, 0.2, 0.11 * strength)
	var far := Color(1.0, 0.5, 0.2, 0.02 * strength)
	_vertex(a - side * HALF_WIDTH, near)
	_vertex(a + side * HALF_WIDTH, near)
	_vertex(b + side * HALF_WIDTH, far)
	_vertex(a - side * HALF_WIDTH, near)
	_vertex(b + side * HALF_WIDTH, far)
	_vertex(b - side * HALF_WIDTH, far)
	# The edges, and a bar where it ends.
	var edge := Color(1.0, 0.72, 0.34, 0.7 * strength)
	_strip(a + side * HALF_WIDTH, b + side * HALF_WIDTH, 0.08, edge)
	_strip(a - side * HALF_WIDTH, b - side * HALF_WIDTH, 0.08, edge)
	_strip(b - side * HALF_WIDTH, b + side * HALF_WIDTH, 0.14, edge)
	# Chevrons running down the lane.
	var spacing: float = 1.7
	var shift: float = fmod(clock * 3.0, spacing)
	var d: float = FROM + shift
	while d < REACH - 0.3:
		var fade: float = clampf(1.0 - (d - FROM) / (REACH - FROM), 0.15, 1.0)
		var tip: Vector3 = origin + dir * (d + 0.5)
		var left: Vector3 = origin + dir * d - side * HALF_WIDTH * 0.7
		var right: Vector3 = origin + dir * d + side * HALF_WIDTH * 0.7
		var col := Color(1.0, 0.7, 0.3, 0.55 * strength * fade)
		_strip(left, tip, 0.1, col)
		_strip(right, tip, 0.1, col)
		d += spacing
	_mesh.surface_end()
	node.global_transform = Transform3D.IDENTITY
	node.visible = true

func hide_wave() -> void:
	node.visible = false

func _vertex(point: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(point)

func _strip(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var along: Vector3 = to - from
	if along.length() < 0.001:
		return
	var across: Vector3 = Vector3(-along.z, 0.0, along.x).normalized() * width * 0.5
	var lift := Vector3(0, 0.01, 0)
	for point in [from - across + lift, from + across + lift, to + across + lift, from - across + lift, to + across + lift, to - across + lift]:
		_vertex(point, color)
