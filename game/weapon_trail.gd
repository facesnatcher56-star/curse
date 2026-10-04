class_name WeaponTrail
extends MeshInstance3D
## Glowing ribbon that follows a blade through a swing, to sell speed and arc.

const DEFAULT_AGE := 0.2

var max_age: float = DEFAULT_AGE
var strength: float = 0.4   # peak alpha of the ribbon

var base_node: Node3D
var tip_node: Node3D
var active: bool = false
var tint: Color = Color(1.0, 0.92, 0.75)

var _points: Array = []

func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat

func _process(delta: float) -> void:
	for point in _points:
		point[2] += delta
	while _points.size() > 0 and _points[_points.size() - 1][2] > max_age:
		_points.pop_back()
	if active and base_node != null and tip_node != null:
		_points.push_front([base_node.get_global_transform_interpolated().origin,
			tip_node.get_global_transform_interpolated().origin, 0.0])
	var im := mesh as ImmediateMesh
	im.clear_surfaces()
	if _points.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for point in _points:
		var fade: float = 1.0 - point[2] / max_age
		im.surface_set_color(Color(tint.r, tint.g, tint.b, fade * strength))
		im.surface_add_vertex(point[1])
		im.surface_set_color(Color(tint.r, tint.g, tint.b, 0.0))
		im.surface_add_vertex(point[0])
	im.surface_end()
