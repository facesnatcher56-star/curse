class_name WeaponTrail
extends MeshInstance3D
## Short, dense ribbon that follows a blade through a swing, to sell speed, arc and weight.
## Presentation only: it reads the blade nodes and never feeds anything back into combat.

const DEFAULT_AGE := 0.2
const HEAVY_AGE := 0.28        # at or above this max_age the ribbon is treated as a heavy swing
const MAX_STRENGTH := 0.7      # additive blend: anything brighter reads as a glowing ribbon, not steel
const MAX_POINTS := 24
const MIN_STEP := 0.02         # a blade that has not moved this far adds no sample (no stacked slivers)
const TELEPORT_DIST := 2.5     # a blade jump this big in one frame is a snap/reset, not a swing: drop the ribbon
const IDLE_DRAIN := 3.0        # once the swing ends the ribbon ages this much faster, so it cannot linger

var max_age: float = DEFAULT_AGE
var strength: float = 0.4   # peak alpha of the ribbon

var base_node: Node3D:
	set(value):
		if value != base_node:
			clear()
		base_node = value
var tip_node: Node3D:
	set(value):
		if value != tip_node:
			clear()
		tip_node = value
var active: bool = false
var tint: Color = Color(1.0, 0.92, 0.75)

var _points: Array = []   # [base, tip, age]

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

## Drop every sample at once (cancel, death, revive, weapon swap).
func clear() -> void:
	_points.clear()
	if mesh is ImmediateMesh:
		(mesh as ImmediateMesh).clear_surfaces()

func point_count() -> int:
	return _points.size()

func is_heavy() -> bool:
	return max_age >= HEAVY_AGE

func _process(delta: float) -> void:
	var blade_ok := base_node != null and tip_node != null \
		and is_instance_valid(base_node) and is_instance_valid(tip_node) \
		and base_node.is_inside_tree() and tip_node.is_inside_tree() and tip_node.is_visible_in_tree()
	if not blade_ok:
		clear()
		return
	step(delta, base_node.get_global_transform_interpolated().origin,
		tip_node.get_global_transform_interpolated().origin)

## One frame of the ribbon, given where the blade is now. Separate from _process so it can be driven headless.
func step(delta: float, base_pos: Vector3, tip_pos: Vector3) -> void:
	if not active:
		# swing over (or cancelled): let what is left fade fast rather than trail behind an idle hero
		for point in _points:
			point[2] += delta * (IDLE_DRAIN - 1.0)
	for point in _points:
		point[2] += delta
	while _points.size() > 0 and _points[_points.size() - 1][2] > max_age:
		_points.pop_back()
	if active:
		if _points.size() > 0 and (_points[0][1] as Vector3).distance_to(tip_pos) > TELEPORT_DIST:
			_points.clear()
		if _points.is_empty() or (_points[0][1] as Vector3).distance_to(tip_pos) >= MIN_STEP:
			_points.push_front([base_pos, tip_pos, 0.0])
			if _points.size() > MAX_POINTS:
				_points.resize(MAX_POINTS)
	var im := mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	if _points.size() < 2:
		return
	var peak := minf(strength, MAX_STRENGTH)
	var heavy := is_heavy()
	# heavy swings keep their weight along the arc (gentle falloff); light ones thin out quickly
	var falloff := 1.3 if heavy else 2.0
	var ember := Color(tint.r * 0.75, tint.g * 0.45, tint.b * 0.25)   # the tail cools toward dull ember, not white
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for point in _points:
		var life: float = clampf(1.0 - point[2] / max_age, 0.0, 1.0)
		var col := ember.lerp(tint, life)
		im.surface_set_color(Color(col.r, col.g, col.b, pow(life, falloff) * peak))
		im.surface_add_vertex(point[1])
		# the root edge stays faint: a dense wedge at the tip, not a full-blade sheet
		var root := (point[0] as Vector3).lerp(point[1], 0.25 if heavy else 0.45)
		im.surface_set_color(Color(col.r, col.g, col.b, 0.0))
		im.surface_add_vertex(root)
	im.surface_end()
