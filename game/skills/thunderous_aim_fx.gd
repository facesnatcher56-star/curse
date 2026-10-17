class_name ThunderousAimFx
extends Node3D
## Thunderous Shot's casting area: while the key is held, a lit corridor on the floor from the archer to where the bolt will end, with
## chevrons running down it in the direction of fire, rails along both edges, an end mark where it stops (the bow's reach or the first
## wall), a thin crackle at arrow height down the middle, and a blue ring under every enemy the bolt will go through (the enemies
## themselves get a blue outline from the SkillController). Styled to match the bolt: storm blue and white, with the rails and chevrons
## kept bright so it reads at gameplay distance.

const BLUE := Color(0.22, 0.5, 1.0)
const WHITE := Color(0.9, 0.95, 1.0)

const STRIP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float len = 10.0;
uniform float width = 1.8;
uniform vec4 tint : source_color = vec4(0.12, 0.42, 1.0, 1.0);
uniform float pulse = 0.0;
void fragment() {
	float v = UV.y * len;                                // metres from the archer, along the line of fire
	float x = (UV.x - 0.5) * width;                      // metres from the centre line
	float ax = abs(x) / (width * 0.5);                   // 0 on the line, 1 on the outer edge
	float aa = max(fwidth(ax), 0.002);
	// crisp rails along both edges, with a thin dark line just outside them so they stand out on any floor
	float rail = 1.0 - smoothstep(0.016, 0.016 + aa * 1.5, abs(ax - 0.965));
	float outline = 1.0 - smoothstep(0.012, 0.012 + aa * 1.5, abs(ax - 0.995));
	float fill = (1.0 - ax * ax) * (0.075 + 0.02 * pulse);
	// sharp chevrons running away from the archer: the tip leads, so the pattern moves toward larger v as time passes
	float d = fract((v + abs(x) * 1.1) * 0.3 - TIME * 0.8);
	float chev = smoothstep(0.0, 0.012, d) * (1.0 - smoothstep(0.075, 0.087, d)) * (1.0 - smoothstep(0.55, 0.7, ax));
	// a bright bar across the end of the line
	float bar = smoothstep(len - 0.12, len - 0.1, v) * (1.0 - smoothstep(len - 0.03, len - 0.01, v)) * (1.0 - smoothstep(0.97, 1.0, ax));
	float start = smoothstep(0.3, 1.1, v);
	float tail = 1.0 - smoothstep(len - 0.01, len, v);
	float bright = max(max(rail, chev), bar);
	vec3 col = mix(tint.rgb, vec3(0.85, 0.93, 1.0), bright);
	col = mix(col, vec3(0.02, 0.05, 0.2), outline * (1.0 - bright) * 0.8);
	ALBEDO = col;
	ALPHA = clamp(max(max(fill, bright * 0.72), outline * 0.5), 0.0, 1.0) * start * tail;
}
"""

## How far above the floor the casting area is drawn: clear of the raised tile tops, which stand above the floor's collider.
const LIFT := 0.3

static var _strip_shader: Shader
static var _highlight: StandardMaterial3D
static var _ring_mesh: TorusMesh

var _strip: MeshInstance3D
var _strip_mat: ShaderMaterial
var _crackle: MeshInstance3D
var _crackle_mesh := ImmediateMesh.new()
var _rings: Array[MeshInstance3D] = []
var _end_mark: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _roll: float = 0.0
var _jit: Array = []

## The blue outline given to every enemy the bolt will hit (the orange one is Fireball's blast read). Its alpha is pulsed with the preview.
static func highlight_material() -> StandardMaterial3D:
	if _highlight == null:
		_highlight = StandardMaterial3D.new()
		_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight.cull_mode = BaseMaterial3D.CULL_FRONT
		_highlight.grow = true
		_highlight.grow_amount = 0.035
		_highlight.albedo_color = Color(0.3, 0.6, 1.0, 0.6)
	return _highlight

func _ready() -> void:
	top_level = true
	_rng.randomize()
	if _strip_shader == null:
		_strip_shader = Shader.new()
		_strip_shader.code = STRIP_SHADER
	_strip = MeshInstance3D.new()
	_strip.mesh = PlaneMesh.new()
	_strip_mat = ShaderMaterial.new()
	_strip_mat.shader = _strip_shader
	_strip.material_override = _strip_mat
	_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_strip)
	_crackle = MeshInstance3D.new()
	_crackle.mesh = _crackle_mesh
	_crackle.material_override = TakeAimFx._line_material()
	_crackle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crackle.top_level = true
	add_child(_crackle)
	_end_mark = _make_ring(0.6)
	add_child(_end_mark)

func _make_ring(radius: float) -> MeshInstance3D:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.92
		_ring_mesh.outer_radius = 1.0
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.4, 0.65, 1.0, 0.6)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(radius, 0.6, radius)
	return ring

## Draws the corridor from `origin` (`width` is the full width of the damage path, the same WIDTH the release uses, so it is no wider than what is hit) along the flat direction `dir` for `length` metres, with a ring under each of `victims`.
func show_line(origin: Vector3, dir: Vector3, length: float, width: float, victims: Array[Enemy]) -> void:
	visible = true
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
	var yaw: float = atan2(flat.x, flat.z)
	var mid: Vector3 = Vector3(origin.x, LIFT, origin.z) + flat * length * 0.5
	(_strip.mesh as PlaneMesh).size = Vector2(width, length)
	_strip.global_transform = Transform3D(Basis(Vector3.UP, yaw), mid)
	_strip_mat.set_shader_parameter("len", length)
	_strip_mat.set_shader_parameter("width", width)
	_strip_mat.set_shader_parameter("pulse", pulse)
	# The end mark: a ring where the bolt stops.
	var end: Vector3 = Vector3(origin.x, LIFT + 0.02, origin.z) + flat * length
	_end_mark.global_position = end
	_end_mark.scale = Vector3(0.55 + 0.08 * pulse, 0.6, 0.55 + 0.08 * pulse)
	# Rings under the enemies it will go through.
	while _rings.size() < victims.size():
		var ring := _make_ring(1.0)
		add_child(ring)
		_rings.append(ring)
	for i in _rings.size():
		var ring: MeshInstance3D = _rings[i]
		ring.visible = i < victims.size()
		if ring.visible:
			var foe: Enemy = victims[i]
			var radius: float = maxf(foe.body_radius, 0.35) + 0.35 + 0.06 * pulse
			ring.global_position = Vector3(foe.global_position.x, LIFT + 0.03, foe.global_position.z)
			ring.scale = Vector3(radius, 0.6, radius)
			(ring.material_override as StandardMaterial3D).albedo_color.a = 0.45 + 0.2 * pulse
	highlight_material().albedo_color.a = 0.35 + 0.2 * pulse
	_update_crackle(origin, flat, length)

## A thin flickering line of lightning at arrow height down the middle: where the arrow itself will fly.
func _update_crackle(origin: Vector3, flat: Vector3, length: float) -> void:
	_crackle_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d()
	if camera == null or length < 1.0:
		return
	_roll -= get_process_delta_time()
	if _roll <= 0.0:
		_roll = 0.08
		_jit.clear()
		for i in 40:
			_jit.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0))
	var start: Vector3 = Vector3(origin.x, 1.35, origin.z) + flat * 0.6
	var stop: Vector3 = Vector3(origin.x, 1.35, origin.z) + flat * length
	var pts: Array[Vector3] = ThunderousShotFx._jag(start, stop, maxi(int(length / 0.8), 4), 0.12, _jit)
	var rv := PackedVector3Array()
	var rc := PackedColorArray()
	ThunderousShotFx._ribbon(rv, rc, pts, camera.global_position, 0.01, BLUE, WHITE, 0.3)
	if rv.size() < 4:
		return
	_crackle_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in rv.size():
		_crackle_mesh.surface_set_color(rc[i])
		_crackle_mesh.surface_add_vertex(rv[i])
	_crackle_mesh.surface_end()
