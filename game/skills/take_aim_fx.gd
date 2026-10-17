class_name TakeAimFx
extends Node3D
## Take Aim's "Hunter's Focus": thin emerald threads drawn into the bow and the arrow's point, and the sharp launch and impact
## that follow. Green is the ranger accent: it is kept to the weapon, never the body, and fades as the shot is spent.
##
## One TakeAimFx lives on the archer from arming until the shot is loosed (BowAttack.aura). It follows the bow and nocked arrow
## through BowAttack's own holders, so it stays on the right weapon whether the archer walks, turns or draws.

const GROUP := "take_aim_fx"
const EMERALD := Color(0.10, 0.78, 0.42)
const DEEP := Color(0.03, 0.30, 0.16)
const SILVER := Color(0.84, 1.0, 0.92)
const LIME := Color(0.66, 1.0, 0.30)
const FILAMENTS := 8
const WAVES := 2.6   # how many times each thread streams in over one draw
const SEGMENTS := 14

const OVERLAY_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back;
uniform vec3 tip = vec3(0.0);
uniform vec3 axis_a = vec3(0.0);
uniform vec3 axis_b = vec3(0.0, 1.0, 0.0);
uniform vec4 tint : source_color = vec4(0.1, 0.78, 0.42, 1.0);
uniform float rim = 0.0;
uniform float tip_glow = 0.0;
uniform float sweep = -1.0;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.4);
	float near_tip = exp(-distance(world_pos, tip) * 9.0);
	vec3 ab = axis_b - axis_a;
	float s = dot(world_pos - axis_a, ab) / max(dot(ab, ab), 0.0001);
	float band = sweep < 0.0 ? 0.0 : exp(-pow((s - sweep) * 9.0, 2.0)) * step(0.62, fract(s * 31.0));
	float k = fres * rim + near_tip * tip_glow + band * 0.55;
	ALBEDO = mix(tint.rgb, vec3(0.9, 1.0, 0.95), clamp(near_tip * tip_glow, 0.0, 1.0));
	ALPHA = clamp(k, 0.0, 1.0);
}
"""

const DISTORT_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.012;
uniform float ring = 0.0;
varying vec2 uvv;
void vertex() {
	uvv = UV;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 c = uvv - 0.5;
	float d = length(c) * 2.0;
	float shell = exp(-pow((d - ring) * 5.5, 2.0)) * (1.0 - smoothstep(0.7, 1.0, d));
	vec2 off = normalize(c + 0.0001) * shell * strength;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = clamp(shell * 4.0, 0.0, 1.0);
}
"""

static var _overlay_shader: Shader
static var _distort_shader: Shader

var bow: BowAttack
var _elapsed: float = 0.0
var _focus: float = 0.0           # 0 = idle held, 1 = full concentration (activation / draw tighten)
var _threads: MeshInstance3D
var _thread_mesh := ImmediateMesh.new()
var _seeds: Array[Vector3] = []   # filament origins in the bow's frame (metres at world scale)
var _bow_overlays: Array[ShaderMaterial] = []
var _arrow_overlays: Array[ShaderMaterial] = []
var _bow_meshes: Array[MeshInstance3D] = []
var _arrow_meshes: Array[MeshInstance3D] = []
var _tip_glint: MeshInstance3D
var _distort: MeshInstance3D
var _distort_mat: ShaderMaterial
var _motes: CPUParticles3D
var _done := false
var _rv := PackedVector3Array()
var _rc := PackedColorArray()

static func _overlay() -> Shader:
	if _overlay_shader == null:
		_overlay_shader = Shader.new()
		_overlay_shader.code = OVERLAY_SHADER
	return _overlay_shader

static func _distortion() -> Shader:
	if _distort_shader == null:
		_distort_shader = Shader.new()
		_distort_shader.code = DISTORT_SHADER
	return _distort_shader

func setup(from_bow: BowAttack) -> void:
	bow = from_bow
	add_to_group(GROUP)
	name = "TakeAimFocus"
	top_level = true
	for i in FILAMENTS:
		var a: float = TAU * float(i) / FILAMENTS + 0.4
		_seeds.append(Vector3(cos(a) * (1.0 + 0.2 * (i % 3)), 0.1 + 0.7 * sin(a * 1.7), sin(a) * 0.9))
	_threads = MeshInstance3D.new()
	_threads.mesh = _thread_mesh
	_threads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_threads.material_override = _line_material()
	_threads.top_level = true
	add_child(_threads)
	_build_overlays()
	_tip_glint = _glint_quad(0.07)
	add_child(_tip_glint)
	_distort = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	_distort.mesh = quad
	_distort_mat = ShaderMaterial.new()
	_distort_mat.shader = _distortion()
	_distort.material_override = _distort_mat
	_distort.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_distort)
	_motes = _mote_emitter()
	add_child(_motes)
	_elapsed = 0.0
	# Quiet beginning: a glint on the bow, the arrow takes a silver edge, a few motes at the string.
	_motes.restart()
	_motes.emitting = true

func _build_overlays() -> void:
	if bow == null:
		return
	if is_instance_valid(bow._bow_holder):
		for mesh in bow._bow_holder.find_children("*", "MeshInstance3D", true, false):
			var mat := ShaderMaterial.new()
			mat.shader = _overlay()
			(mesh as MeshInstance3D).material_overlay = mat
			_bow_meshes.append(mesh)
			_bow_overlays.append(mat)
	if is_instance_valid(bow._draw_arrow):
		for mesh in bow._draw_arrow.find_children("*", "MeshInstance3D", true, false):
			var mat := ShaderMaterial.new()
			mat.shader = _overlay()
			(mesh as MeshInstance3D).material_overlay = mat
			_arrow_meshes.append(mesh)
			_arrow_overlays.append(mat)

func _exit_tree() -> void:
	for mesh in _bow_meshes + _arrow_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null

static func _line_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat

static func _glint_quad(size: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = Fx.soft_texture()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.82, 1.0, 0.9, 0.0)
	quad.material = mat
	node.mesh = quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func _mote_emitter() -> CPUParticles3D:
	var motes := CPUParticles3D.new()
	motes.amount = 8
	motes.lifetime = 0.55
	motes.explosiveness = 0.0
	motes.randomness = 0.6
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.10
	motes.direction = Vector3.ZERO
	motes.initial_velocity_min = 0.0
	motes.initial_velocity_max = 0.0
	motes.gravity = Vector3.ZERO
	motes.mesh = BrutalAttackFx._soft_quad(Vector2(0.018, 0.018), Color.WHITE)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.7, 1.0, 0.8, 0.0))
	ramp.add_point(0.25, Color(0.78, 1.0, 0.86, 0.85))
	ramp.set_color(1, Color(0.1, 0.6, 0.3, 0.0))
	motes.color_ramp = ramp
	motes.emitting = false
	return motes

## The point the threads gather on: the nocked arrow's head while it is drawn, otherwise the bow's arrow rest.
func focus_point() -> Vector3:
	if bow == null:
		return global_position
	if is_instance_valid(bow._draw_arrow) and bow._draw_arrow.visible:
		var box: AABB = bow._draw_arrow.get_meta("mesh_bounds")
		return bow._draw_arrow.to_global(Vector3(0.0, box.size.y * 0.5, 0.0))
	if is_instance_valid(bow._bow_holder):
		return bow._bow_holder.to_global(Vector3(-0.02, 0.0, 0.0))
	return global_position

func _bow_axis() -> Array[Vector3]:
	if is_instance_valid(bow._bow_holder):
		var box: AABB = bow._bow_holder.get_meta("mesh_bounds")
		return [bow._bow_holder.to_global(Vector3(0, -box.size.y * 0.5, 0)), bow._bow_holder.to_global(Vector3(0, box.size.y * 0.5, 0))]
	return [global_position, global_position + Vector3.UP]

## How far the one gathering has got: Cutter's draw of the empowered shot, 0 at the start of the pull and 1 as he looses.
func build() -> float:
	return clampf(bow._draw, 0.0, 1.0) if bow != null and is_instance_valid(bow._draw_arrow) and bow._draw_arrow.visible else 0.0

func _process(delta: float) -> void:
	if bow == null or not is_instance_valid(bow._bow_holder):
		return
	_elapsed += delta
	var tip: Vector3 = focus_point()
	var g: float = build()
	_focus = g
	_update_overlays(tip, g)
	_update_threads(tip, g)
	_update_glint(tip, g)
	_motes.global_position = bow._bow_holder.global_position
	_motes.emitting = _elapsed < 0.4 or g > 0.05
	_motes.amount = 8 if g <= 0.05 else int(8 + 20.0 * g)
	if g > 0.96 and not _done:
		_done = true
		_focus_flash(tip)

## One sharp silver-green point as concentration completes, an instant before the string lets go.
func _focus_flash(tip: Vector3) -> void:
	Fx.burst(self, tip, Vector3.UP, SILVER, 8, 1.8, 0.012, true)
	_pulse_distortion(tip, 0.16, 0.012)

func _pulse_distortion(at: Vector3, duration: float, strength: float) -> void:
	_distort.global_position = at
	_distort_mat.set_shader_parameter("strength", strength)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: _distort_mat.set_shader_parameter("ring", v), 0.0, 0.9, duration)
	tween.tween_callback(func() -> void: _distort_mat.set_shader_parameter("ring", -1.0))

func _update_overlays(tip: Vector3, g: float) -> void:
	var axis: Array[Vector3] = _bow_axis()
	var quiet: float = 1.0 - smoothstep(0.0, 0.5, _elapsed)   # the arming glint: a faint sweep of runes along the bow, then still
	var rim: float = 0.10 + 0.35 * g + 0.15 * quiet
	var sweep: float = -1.0
	if _elapsed > 0.05 and _elapsed < 0.4:
		sweep = (_elapsed - 0.05) / 0.35
	for mat in _bow_overlays:
		mat.set_shader_parameter("axis_a", axis[0])
		mat.set_shader_parameter("axis_b", axis[1])
		mat.set_shader_parameter("tint", Color(0.16, 0.74, 0.46, 1.0))
		mat.set_shader_parameter("rim", rim)
		mat.set_shader_parameter("tip", tip)
		mat.set_shader_parameter("tip_glow", 0.0)
		mat.set_shader_parameter("sweep", sweep)
	for mat in _arrow_overlays:
		mat.set_shader_parameter("tint", Color(0.5, 1.0, 0.75, 1.0))
		mat.set_shader_parameter("tip", tip)
		mat.set_shader_parameter("tip_glow", 0.25 + 1.1 * g)
		mat.set_shader_parameter("rim", 0.1 + 0.4 * g)
		mat.set_shader_parameter("sweep", -1.0)

func _update_glint(tip: Vector3, g: float) -> void:
	var strength: float = g * g if g > 0.0 else clampf(0.2 * (1.0 - smoothstep(0.0, 0.5, _elapsed)), 0.0, 1.0)
	_tip_glint.global_position = tip
	var s: float = 0.03 + 0.09 * strength
	(_tip_glint.mesh as QuadMesh).size = Vector2(s, s)
	((_tip_glint.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = Color(0.78, 1.0, 0.88, 0.1 + 0.8 * strength)

## Threads stream in toward the arrow's head the whole length of the draw, thicker, brighter and straighter as it nears release.
func _update_threads(tip: Vector3, g: float) -> void:
	_thread_mesh.clear_surfaces()
	if g <= 0.02:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var anchor: Vector3 = bow._bow_holder.global_position
	var view: Vector3 = camera.global_position
	_rv.clear()
	_rc.clear()
	var waves: float = g * WAVES
	var intensity: float = smoothstep(0.0, 0.25, g) * (0.45 + 0.55 * g)
	for i in FILAMENTS:
		var travel: float = waves - float(i) / FILAMENTS
		if travel <= 0.0:
			continue
		travel = fposmod(travel, 1.0) if g < 0.97 else 1.0
		var start: Vector3 = anchor + Basis(Vector3.UP, p_yaw() + float(int(waves - float(i) / FILAMENTS)) * 0.9) * _seeds[i]
		var straighten: float = travel * travel
		var mid: Vector3 = start.lerp(tip, 0.5) + Vector3(0, 0.18, 0).rotated(Vector3.FORWARD, float(i)) * (1.0 - straighten)
		var points: Array[Vector3] = []
		var tail_t: float = maxf(travel - 0.7, 0.0)
		for k in SEGMENTS + 1:
			points.append(_quad_bezier(start, mid, tip, lerpf(tail_t, travel, float(k) / SEGMENTS)))
		_emit_ribbon(points, view, (0.0035 + 0.0045 * g) * (0.7 + 0.3 * travel), EMERALD, SILVER, intensity * sin(minf(travel, 1.0) * PI * 0.5))
	if _rv.size() < 4:
		return
	_thread_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _rv.size():
		_thread_mesh.surface_set_color(_rc[i])
		_thread_mesh.surface_add_vertex(_rv[i])
	_thread_mesh.surface_end()

func p_yaw() -> float:
	var player := bow.p
	return player.visual.global_rotation.y if is_instance_valid(player) and player.visual != null else 0.0

static func _quad_bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)

## A camera-facing, tapered strip through the points: wide in the middle of its length, pointed at both ends, tinted from
## `tail_color` at the first point to `head_color` at the last.
func _emit_ribbon(points: Array[Vector3], view: Vector3, width: float, tail_color: Color, head_color: Color, alpha: float) -> void:
	var n: int = points.size()
	if n < 2:
		return
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	for k in n:
		var dir: Vector3 = (points[mini(k + 1, n - 1)] - points[maxi(k - 1, 0)]).normalized()
		var to_cam: Vector3 = (view - points[k]).normalized()
		var side: Vector3 = dir.cross(to_cam).normalized()
		var u: float = float(k) / (n - 1)
		var taper: float = sin(u * PI)
		var col: Color = tail_color.lerp(head_color, u)
		col.a = alpha * taper
		verts.append(points[k] + side * width * taper)
		verts.append(points[k] - side * width * taper)
		cols.append(col)
		cols.append(col)
	# Ribbons share one strip: a degenerate pair at each end keeps them apart.
	if not _rv.is_empty():
		_rv.append(_rv[_rv.size() - 1])
		_rc.append(Color(0, 0, 0, 0))
		_rv.append(verts[0])
		_rc.append(Color(0, 0, 0, 0))
	for i in verts.size():
		_rv.append(verts[i])
		_rc.append(cols[i])

# --- Launch and impact (stateless: they do not need the held-state node) ---------------------------------------------------

## The bowstring lets go: the head flashes, a narrow flash runs along the shot, and a spark leaves the string.
static func launch(from: Node, tip: Vector3, direction: Vector3, string_at: Vector3) -> void:
	var dir: Vector3 = direction.normalized()
	Fx.burst(from, tip, dir, SILVER, 10, 9.0, 0.011, true)
	Fx.burst(from, string_at, dir, LIME.lerp(SILVER, 0.5), 5, 2.8, 0.008, true)
	_flash_line(from, tip, dir, 2.0, 0.09)
	_flash_dot(from, tip, 0.4, 0.12)
	_shock(from, tip, 0.9, 0.18, 0.025)

## A thin bright streak along the direction of travel, fading fast.
static func _flash_line(from: Node, at: Vector3, dir: Vector3, length: float, duration: float) -> void:
	var node := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_texture = Fx.soft_texture()
	mat.albedo_color = Color(0.8, 1.0, 0.9, 0.85)
	mesh.material = mat
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var scene: Node = from.get_tree().current_scene
	scene.add_child(node)
	node.global_position = at + dir * length * 0.5
	# FIXED_Y billboard stands the quad upright; lay it along the shot instead with a flat, camera-turned strip.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	var up: Vector3 = dir
	var cam := from.get_viewport().get_camera_3d()
	var face: Vector3 = (cam.global_position - at).normalized() if cam != null else Vector3.BACK
	var side: Vector3 = up.cross(face).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	node.global_basis = Basis(side, up, side.cross(up).normalized())
	var tween := node.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_callback(node.queue_free)

static func _flash_dot(from: Node, at: Vector3, size: float, duration: float) -> void:
	var node := _glint_quad(size)
	var mat := (node.mesh as QuadMesh).material as StandardMaterial3D
	mat.albedo_color = Color(0.85, 1.0, 0.92, 0.9)
	from.get_tree().current_scene.add_child(node)
	node.global_position = at
	var tween := node.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_callback(node.queue_free)

## A small expanding ripple of bent air at a point.
static func _shock(from: Node, at: Vector3, size: float, duration: float, strength: float) -> void:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = _distortion()
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("ring", 0.0)
	node.mesh = quad
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(node)
	node.global_position = at
	var tween := node.create_tween()
	tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("ring", v), 0.0, 0.95, duration)
	tween.tween_callback(node.queue_free)

## Streaks of emerald light that travel with the outgoing fragments of a lethal hit, then vanish.
static func _streaks(from: Node, at: Vector3, dir: Vector3, count: int) -> void:
	var streaks := CPUParticles3D.new()
	streaks.one_shot = true
	streaks.amount = count
	streaks.lifetime = 0.34
	streaks.explosiveness = 1.0
	streaks.randomness = 0.4
	streaks.direction = dir
	streaks.spread = 32.0
	streaks.initial_velocity_min = 5.0
	streaks.initial_velocity_max = 11.0
	streaks.gravity = Vector3(0, -3.0, 0)
	streaks.particle_flag_align_y = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.30)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	streaks.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.8, 1.0, 0.9, 0.9))
	ramp.add_point(0.4, Color(0.12, 0.8, 0.42, 0.7))
	ramp.set_color(1, Color(0.03, 0.3, 0.16, 0.0))
	streaks.color_ramp = ramp
	from.get_tree().current_scene.add_child(streaks)
	streaks.global_position = at
	streaks.emitting = true
	streaks.finished.connect(streaks.queue_free)

## Where the empowered arrow lands. Concentrated at the point of contact, but with real force; a lethal blow adds the finish.
static func impact(from: Node, point: Vector3, direction: Vector3, lethal: bool) -> void:
	var dir: Vector3 = direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD
	var big: float = 1.0 if lethal else 0.7
	_flash_dot(from, point, 1.1 * big, 0.14)
	_flash_dot(from, point, 0.45 * big, 0.2)
	Fx.light_flash(from, point, Color(0.6, 1.0, 0.78), 1.6 * big, 0.10)
	Fx.burst(from, point, dir, SILVER, int(20.0 * big), 11.0 * big, 0.013, true)
	Fx.burst(from, point, dir, EMERALD, int(12.0 * big), 6.5, 0.011, true)
	_shock(from, point, 2.6 * big, 0.30, 0.05 * big)
	# Weak reference: a freed `from` must not be captured by the timer's lambda (Godot errors on a freed capture before the body runs).
	var from_ref: WeakRef = weakref(from)
	from.get_tree().create_timer(0.07).timeout.connect(func() -> void:
		var f := from_ref.get_ref() as Node
		if f != null and f.is_inside_tree():
			_shock(f, point, 1.6 * big, 0.26, 0.04 * big))
	_flash_line(from, point - dir * 1.4, dir, 2.4 * big, 0.10)
	if lethal:
		_streaks(from, point, dir, 18)
		_gore(from, point, dir)
		Fx.shake(from, 0.22)
		from.get_tree().create_timer(0.07).timeout.connect(func() -> void:
			var f := from_ref.get_ref() as Node
			if f != null and f.is_inside_tree():
				Fx.shake(f, 0.14))
	else:
		Fx.shake(from, 0.26)

## The arrow's force at the wound: a short spray along the shot, a small cloud of blood that hangs and thins around the impact point,
## the limbs' own trail marking the floor. Kept tight to the contact point; physical colours only, and the existing gibs supply the fragments.
static func _gore(from: Node, point: Vector3, dir: Vector3) -> void:
	var blood := Color(0.30, 0.012, 0.025)
	Fx.burst(from, point, dir + Vector3.UP * 0.12, blood, 12, 5.0, 0.026)
	Fx.burst(from, point, dir + Vector3.UP * 0.2, blood.lightened(0.08), 8, 3.0, 0.022)
	var cloud := CPUParticles3D.new()
	cloud.name = "TakeAimBloodCloud"
	cloud.amount = 26
	cloud.one_shot = true
	cloud.explosiveness = 0.9
	cloud.lifetime = 1.6
	cloud.local_coords = false
	cloud.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cloud.emission_sphere_radius = 0.3
	cloud.direction = (dir + Vector3.UP * 0.1).normalized()
	cloud.spread = 40.0
	cloud.initial_velocity_min = 0.8
	cloud.initial_velocity_max = 4.0
	cloud.damping_min = 3.5
	cloud.damping_max = 5.5
	cloud.gravity = Vector3(0, -0.2, 0)
	cloud.angle_min = -180.0
	cloud.angle_max = 180.0
	cloud.scale_amount_min = 0.6
	cloud.scale_amount_max = 1.0
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.3))
	growth.add_point(Vector2(0.3, 0.9))
	growth.add_point(Vector2(1, 2.4))
	cloud.scale_amount_curve = growth
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0, 0.1, 0.6, 1])
	ramp.colors = PackedColorArray([Color(0.30, 0.01, 0.02, 0.0), Color(0.28, 0.008, 0.02, 0.4), Color(0.18, 0.004, 0.012, 0.22), Color(0.09, 0.002, 0.006, 0.0)])
	cloud.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = BrutalBloodWake.mist_texture()
	quad.material = mat
	cloud.mesh = quad
	from.get_tree().current_scene.add_child(cloud)
	cloud.global_position = point
	cloud.emitting = true
	cloud.finished.connect(cloud.queue_free)
	_torso_mist(from, point, dir)

## The torso and head do not tumble away: they are blown to a fine red mist that streams along the shot and thins as it spreads.
static func _torso_mist(from: Node, point: Vector3, dir: Vector3) -> void:
	var mist := CPUParticles3D.new()
	mist.name = "TakeAimTorsoMist"
	mist.amount = 34
	mist.one_shot = true
	mist.explosiveness = 0.9
	mist.lifetime = 1.8
	mist.local_coords = false
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.45
	mist.direction = (dir + Vector3.UP * 0.12).normalized()
	mist.spread = 48.0
	mist.initial_velocity_min = 0.8
	mist.initial_velocity_max = 5.0
	mist.damping_min = 3.5
	mist.damping_max = 6.0
	mist.gravity = Vector3(0, -0.15, 0)
	mist.angle_min = -180.0
	mist.angle_max = 180.0
	mist.angular_velocity_min = -40.0
	mist.angular_velocity_max = 40.0
	mist.scale_amount_min = 0.5
	mist.scale_amount_max = 1.2
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.25))
	growth.add_point(Vector2(0.25, 1.0))
	growth.add_point(Vector2(1, 2.8))
	mist.scale_amount_curve = growth
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0, 0.08, 0.5, 1])
	ramp.colors = PackedColorArray([Color(0.55, 0.02, 0.035, 0.0), Color(0.5, 0.02, 0.035, 0.22), Color(0.36, 0.012, 0.025, 0.14), Color(0.2, 0.006, 0.014, 0.0)])
	mist.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.47)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = BrutalBloodWake.mist_texture()
	quad.material = mat
	mist.mesh = quad
	from.get_tree().current_scene.add_child(mist)
	mist.global_position = point + dir * 0.15
	mist.emitting = true
	mist.finished.connect(mist.queue_free)
