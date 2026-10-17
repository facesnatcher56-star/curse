class_name ThunderousShotFx
extends Node3D
## Thunderous Shot's visuals (the power itself, its piercing and its stun, are gameplay that is not built yet: this is presentation only).
##
## A sonic boom, not a spell: cold storm-blue and white, kept on the weapon. While the shot is drawn, jagged blue arcs crawl over the bow and
## string and thin streaks of air are pulled to the arrowhead, building to the release. The release throws a shock ring, a muzzle flash and
## blown dust, and the bolt itself is an instant white-hot line through every enemy on its path, each of which flashes and is left crackling
## for the length of the stun. Blue is this power's accent the way green is Take Aim's.
##
## Presentation entry points, for the power to call when it exists:
##   var fx := ThunderousShotFx.new(); archer.add_child(fx); fx.setup(bow)   # when the draw begins (freed by the caller after the release)
##   ThunderousShotFx.release(scene_node, archer, muzzle, direction, stun_seconds)   # at the moment of release
##   ThunderousShotFx.stun_marker(enemy, seconds)                                     # on anything the bolt stuns

const GROUP := "thunderous_fx"
const BLUE := Color(0.16, 0.40, 1.0)
const DEEP := Color(0.04, 0.10, 0.42)
const WHITE := Color(0.90, 0.95, 1.0)
const VIOLET := Color(0.42, 0.34, 1.0)   # the faint edge of a real discharge
const FLIGHT_SPEED := 95.0    # metres per second the bolt travels as seen: the length of the bow's reach in under two tenths of a second, fast but readable
const BEAM_LIFE := 0.5
const REACH := 17.0   # the bow's reach: how far the bolt goes, and how far the power hits
const WIDTH := 0.9    # how far off the line an enemy can stand and still be on it
const STRIKE_LIFE := 0.26

var bow: BowAttack
var _elapsed: float = 0.0
var _arc_mesh := ImmediateMesh.new()
var _arcs: Array[Dictionary] = []
var _streaks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _reroll: float = 0.0
var _strikes: Array[Dictionary] = []   # lightning bolts coming down onto the bow tip
var _strike_wait: float = 0.6
var _boost: float = 0.0   # how hard the last strike lit the weapon, dying away
var _bow_overlays: Array[ShaderMaterial] = []
var _arrow_overlays: Array[ShaderMaterial] = []
var _overlaid: Array[MeshInstance3D] = []
var _tip_glint: MeshInstance3D
var _dust: CPUParticles3D
var _rv := PackedVector3Array()
var _rc := PackedColorArray()

func setup(from_bow: BowAttack) -> void:
	bow = from_bow
	name = "ThunderousCharge"
	add_to_group(GROUP)
	top_level = true
	_rng.randomize()
	var strip := MeshInstance3D.new()
	strip.mesh = _arc_mesh
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.material_override = TakeAimFx._line_material()
	strip.top_level = true
	add_child(strip)
	for i in 6:
		_streaks.append({"dir": _random_unit(), "radius": _rng.randf_range(0.9, 1.6), "phase": _rng.randf(), "speed": _rng.randf_range(1.6, 2.6)})
	for mesh in bow._bow_holder.find_children("*", "MeshInstance3D", true, false):
		_overlay_mesh(mesh, _bow_overlays)
	for mesh in bow._draw_arrow.find_children("*", "MeshInstance3D", true, false):
		_overlay_mesh(mesh, _arrow_overlays)
	_tip_glint = TakeAimFx._glint_quad(0.07)
	add_child(_tip_glint)
	_dust = _dust_emitter()
	add_child(_dust)

func _overlay_mesh(mesh: Node, into: Array[ShaderMaterial]) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TakeAimFx._overlay()
	(mesh as MeshInstance3D).material_overlay = mat
	_overlaid.append(mesh)
	into.append(mat)

func _exit_tree() -> void:
	for mesh in _overlaid:
		if is_instance_valid(mesh):
			mesh.material_overlay = null

func _random_unit() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.9), _rng.randf_range(-1, 1)).normalized()

## Ground dust lifted at his feet as the shot is drawn: the force of it building, kept low.
func _dust_emitter() -> CPUParticles3D:
	var dust := CPUParticles3D.new()
	dust.amount = 18
	dust.lifetime = 1.3
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.7
	dust.direction = Vector3.UP
	dust.spread = 70.0
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.5
	dust.gravity = Vector3(0, 0.05, 0)
	dust.damping_min = 0.6
	dust.damping_max = 1.2
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.2
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.4))
	growth.add_point(Vector2(1, 1.8))
	dust.scale_amount_curve = growth
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0, 0.2, 1])
	ramp.colors = PackedColorArray([Color(0.55, 0.6, 0.72, 0.0), Color(0.55, 0.6, 0.72, 0.16), Color(0.4, 0.44, 0.55, 0.0)])
	dust.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = BrutalBloodWake.mist_texture()
	quad.material = mat
	dust.mesh = quad
	dust.emitting = false
	return dust

## How far the one gathering has got: the draw, 0 at the start of the pull and 1 as he looses.
func build() -> float:
	return clampf(bow._draw, 0.0, 1.0) if bow != null and is_instance_valid(bow._draw_arrow) and bow._draw_arrow.visible else 0.0

func _tip() -> Vector3:
	var box: AABB = bow._draw_arrow.get_meta("mesh_bounds")
	return bow._draw_arrow.to_global(Vector3(0.0, box.size.y * 0.5, 0.0))

func _nock() -> Vector3:
	var box: AABB = bow._draw_arrow.get_meta("mesh_bounds")
	return bow._draw_arrow.to_global(Vector3(0.0, -box.size.y * 0.5, 0.0))

func _bow_point(s: float) -> Vector3:
	var box: AABB = bow._bow_holder.get_meta("mesh_bounds")
	return bow._bow_holder.to_global(Vector3(0.03, (s - 0.5) * box.size.y, 0.0))

func _process(delta: float) -> void:
	if bow == null or not is_instance_valid(bow._bow_holder):
		return
	_elapsed += delta
	var g: float = build()
	var tip: Vector3 = _tip() if g > 0.0 else _bow_point(0.5)
	_update_overlays(tip, g)
	_update_glint(tip, g)
	_dust.global_position = Vector3(bow.p.global_position.x, 0.12, bow.p.global_position.z)
	_dust.emitting = g > 0.15
	_dust.amount = int(8 + 22.0 * g)
	_run_strikes(delta, g)
	_reroll -= delta
	if _reroll <= 0.0:
		_reroll = 0.05
		_roll_arcs(g)
	_update_arcs(tip, g)

## Lightning strikes the arrowhead at random while the shot is drawn, and more often the longer the draw goes.
func _strike_target() -> Vector3:
	return _tip() if is_instance_valid(bow._draw_arrow) and bow._draw_arrow.visible else _bow_point(1.0)

func _run_strikes(delta: float, g: float) -> void:
	_boost = maxf(_boost - delta * 5.0, 0.0)
	for strike in _strikes:
		strike["age"] = float(strike["age"]) + delta
	_strikes = _strikes.filter(func(strike: Dictionary) -> bool: return float(strike["age"]) < STRIKE_LIFE)
	if g <= 0.03:
		return
	_strike_wait -= delta
	if _strike_wait > 0.0:
		return
	# About one strike a second at the start of the draw, six or seven a second by the end.
	_strike_wait = _rng.randf_range(0.6, 1.4) / (1.0 + 6.0 * g * g)
	var branches: Array[Dictionary] = []
	for k in _rng.randi_range(3, 5):
		branches.append({"at": _rng.randf_range(0.15, 0.85), "dir": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.9, -0.1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.7, 2.0), "disp": _fractal_disp(3, 0.18)})
	var side: Vector3 = Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.8, 2.2)
	_strikes.append({"age": 0.0, "disp": _fractal_disp(5, 0.9), "sky": Vector3(0, _rng.randf_range(9.0, 11.0), 0) + side, "branches": branches})
	var top: Vector3 = _strike_target()
	_boost = 1.0
	ThunderousShotFx._flash(self, top, 0.55 + 0.3 * g, 0.12)
	Fx.burst(self, top, Vector3.UP, WHITE, 10, 5.5, 0.011, true)
	Fx.burst(self, top, Vector3.UP + Vector3(0.5, 0, 0), BLUE, 8, 3.5, 0.01, true)
	ThunderousShotFx._lamp(self, top + Vector3(0, 0.6, 0), 6.0 + 4.0 * g, 9.0, 0.22)
	Fx.shake(self, 0.04 + 0.06 * g)

## Displacement for a jagged channel of 2^depth segments (midpoint displacement: big bends first, then smaller kinks), zero at both ends.
func _fractal_disp(depth: int, amplitude: float) -> Array[Vector3]:
	var n: int = 1 << depth
	var disp: Array[Vector3] = []
	for i in n + 1:
		disp.append(Vector3.ZERO)
	var step: int = n
	var amp: float = amplitude
	while step > 1:
		var half: int = step / 2
		var i: int = half
		while i < n:
			disp[i] = (disp[i - half] + disp[i + half]) * 0.5 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)) * amp
			i += step
		step = half
		amp *= 0.55
	return disp

## Strike brightness over its life: a bright leader, a dim gap, a second return stroke, then a fading glow.
static func _strike_alpha(age: float) -> float:
	if age < 0.04: return 1.0
	if age < 0.07: return 0.25
	if age < 0.12: return 1.0
	if age < 0.17: return 0.4
	return maxf(0.4 * (1.0 - (age - 0.17) / (STRIKE_LIFE - 0.17)), 0.0)

func _update_overlays(tip: Vector3, g: float) -> void:
	var box: AABB = bow._bow_holder.get_meta("mesh_bounds")
	var a: Vector3 = bow._bow_holder.to_global(Vector3(0, -box.size.y * 0.5, 0))
	var b: Vector3 = bow._bow_holder.to_global(Vector3(0, box.size.y * 0.5, 0))
	for mat in _bow_overlays:
		mat.set_shader_parameter("axis_a", a)
		mat.set_shader_parameter("axis_b", b)
		mat.set_shader_parameter("tint", BLUE)
		mat.set_shader_parameter("rim", 0.08 + 0.55 * g + 0.5 * _boost)
		mat.set_shader_parameter("tip", tip)
		mat.set_shader_parameter("tip_glow", 0.0)
		mat.set_shader_parameter("sweep", -1.0)
	for mat in _arrow_overlays:
		mat.set_shader_parameter("tint", WHITE)
		mat.set_shader_parameter("tip", tip)
		mat.set_shader_parameter("tip_glow", 0.2 + 1.3 * g + 2.5 * _boost)
		mat.set_shader_parameter("rim", 0.1 + 0.5 * g + 0.7 * _boost)
		mat.set_shader_parameter("sweep", -1.0)

func _update_glint(tip: Vector3, g: float) -> void:
	var strength: float = g * g
	_tip_glint.global_position = tip
	var size: float = 0.03 + 0.12 * strength
	(_tip_glint.mesh as QuadMesh).size = Vector2(size, size)
	((_tip_glint.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = Color(0.85, 0.93, 1.0, 0.1 + 0.85 * strength)

## New jagged shapes for the arcs, redrawn about twenty times a second like a real discharge.
func _roll_arcs(g: float) -> void:
	_arcs.clear()
	var count: int = int(1.0 + 7.0 * g)
	for i in count:
		var roll: float = _rng.randf()
		var kind: int = 0   # crawls along a limb
		if g > 0.12 and roll < 0.25 + 0.5 * g:
			kind = 2    # from the bow to the arrowhead
		elif g > 0.3 and roll < 0.75:
			kind = 1    # along the string to the head
		var jit: Array[Vector3] = []
		for k in 8:
			jit.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)))
		_arcs.append({"kind": kind, "s": _rng.randf_range(0.05, 0.85), "len": _rng.randf_range(0.12, 0.3), "jit": jit})

func _update_arcs(tip: Vector3, g: float) -> void:
	_arc_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d()
	if camera == null or g <= 0.0 and _elapsed > 0.0 and _arcs.is_empty():
		return
	var view: Vector3 = camera.global_position
	_rv.clear()
	_rc.clear()
	var drawing: bool = g > 0.0
	for arc in _arcs:
		var a: Vector3
		var b: Vector3
		match int(arc["kind"]):
			0:
				a = _bow_point(float(arc["s"]))
				b = _bow_point(minf(float(arc["s"]) + float(arc["len"]), 1.0))
			1:
				if not drawing: continue
				a = _nock()
				b = tip
			_:
				if not drawing: continue
				a = _bow_point(float(arc["s"]))
				b = tip
		var pts: Array[Vector3] = _jag(a, b, 8, 0.045 * (1.0 - 0.5 * g) + 0.01, arc["jit"])
		var strength: float = 0.35 + 0.65 * g
		_ribbon(_rv, _rc, pts, view, 0.011 + 0.006 * g, BLUE, BLUE, 0.28 * strength)     # the glow
		_ribbon(_rv, _rc, pts, view, 0.0035 + 0.002 * g, WHITE, WHITE, 0.95 * strength)  # the hot core
	# The lightning itself: a branching jagged channel from the sky to the arrowhead, a bright core in a blue glow, flickering as it fires.
	var strike_target: Vector3 = _strike_target()
	for strike in _strikes:
		var alpha: float = _strike_alpha(float(strike["age"]))
		if alpha <= 0.0:
			continue
		var sky: Vector3 = strike_target + (strike["sky"] as Vector3)
		var disp: Array = strike["disp"]
		var bolt: Array[Vector3] = []
		for i in disp.size():
			bolt.append(sky.lerp(strike_target, float(i) / (disp.size() - 1)) + (disp[i] as Vector3))
		_ribbon(_rv, _rc, bolt, view, 0.075 * alpha + 0.02, VIOLET, BLUE, 0.35 * alpha)
		_ribbon(_rv, _rc, bolt, view, 0.02, BLUE, WHITE, 0.9 * alpha)
		_ribbon(_rv, _rc, bolt, view, 0.007, WHITE, WHITE, 1.0 * alpha)
		for branch in strike["branches"]:
			var idx: int = clampi(int(float(branch["at"]) * (bolt.size() - 1)), 1, bolt.size() - 2)
			var origin: Vector3 = bolt[idx]
			var bdisp: Array = branch["disp"]
			var limb: Array[Vector3] = []
			for i in bdisp.size():
				limb.append(origin + (branch["dir"] as Vector3) * (float(i) / (bdisp.size() - 1)) + (bdisp[i] as Vector3))
			_ribbon(_rv, _rc, limb, view, 0.022 * alpha, BLUE, BLUE, 0.3 * alpha)
			_ribbon(_rv, _rc, limb, view, 0.005, BLUE, WHITE, 0.85 * alpha)
	# Streaks of air being pulled to the arrowhead.
	if drawing and g > 0.08:
		for streak in _streaks:
			var travel: float = fposmod(_elapsed * float(streak["speed"]) * (0.7 + g) + float(streak["phase"]), 1.0)
			var from_point: Vector3 = tip + (streak["dir"] as Vector3) * float(streak["radius"])
			var head: Vector3 = from_point.lerp(tip, travel)
			var tail: Vector3 = from_point.lerp(tip, maxf(travel - 0.3, 0.0))
			_ribbon(_rv, _rc, [tail, tail.lerp(head, 0.5), head] as Array[Vector3], view, 0.004 + 0.003 * g, BLUE, WHITE, 0.55 * g * sin(travel * PI))
	if _rv.size() < 4:
		return
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _rv.size():
		_arc_mesh.surface_set_color(_rc[i])
		_arc_mesh.surface_add_vertex(_rv[i])
	_arc_mesh.surface_end()

# --- Shared drawing ------------------------------------------------------------------------------------------------------

## A jagged line from a to b. `jit` holds one random offset per interior point (the shape of one flicker of the discharge).
static func _jag(a: Vector3, b: Vector3, segments: int, amplitude: float, jit: Array) -> Array[Vector3]:
	var axis: Vector3 = b - a
	var side: Vector3 = axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up: Vector3 = axis.cross(side).normalized()
	var pts: Array[Vector3] = []
	for i in segments + 1:
		var t: float = float(i) / segments
		var point: Vector3 = a.lerp(b, t)
		if i > 0 and i < segments:
			var j: Vector3 = jit[(i - 1) % jit.size()]
			point += (side * j.x + up * j.y) * amplitude * sin(t * PI)
		pts.append(point)
	return pts

## Appends a camera-facing tapered strip through `pts` to the strip arrays (a degenerate pair keeps strips apart).
static func _ribbon(rv: PackedVector3Array, rc: PackedColorArray, pts: Array[Vector3], view: Vector3, width: float, c0: Color, c1: Color, alpha: float, ramp: bool = false) -> void:
	var n: int = pts.size()
	if n < 2 or alpha <= 0.0:
		return
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	for k in n:
		var dir: Vector3 = (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var to_cam: Vector3 = (view - pts[k]).normalized()
		var side: Vector3 = dir.cross(to_cam).normalized()
		var u: float = float(k) / (n - 1)
		var taper: float = pow(u, 1.3) if ramp else sin(u * PI) * 0.85 + 0.15
		var col: Color = c0.lerp(c1, u)
		col.a = alpha * taper
		verts.append(pts[k] + side * width * taper)
		verts.append(pts[k] - side * width * taper)
		cols.append(col)
		cols.append(col)
	if not rv.is_empty():
		rv.append(rv[rv.size() - 1])
		rc.append(Color(0, 0, 0, 0))
		rv.append(verts[0])
		rc.append(Color(0, 0, 0, 0))
	for i in verts.size():
		rv.append(verts[i])
		rc.append(cols[i])

# --- Release ---------------------------------------------------------------------------------------------------------------

## The shot is loosed. `from` is any node in the scene, `muzzle` the arrowhead and `direction` the line of fire.
static func release(from: Node, archer: Node3D, muzzle: Vector3, direction: Vector3, stun_seconds: float = 6.0) -> void:
	var dir: Vector3 = direction.normalized()
	var space: PhysicsDirectSpaceState3D = archer.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * REACH, Actor.LAYER_WORLD)
	var hit: Dictionary = space.intersect_ray(query)
	var end: Vector3 = hit["position"] if not hit.is_empty() else muzzle + dir * REACH
	var length: float = muzzle.distance_to(end)
	# Everything on the line, in the order the bolt reaches it.
	var victims: Array[Dictionary] = []
	for node in from.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.dead:
			continue
		var chest: Vector3 = enemy.global_position + Vector3(0, enemy.body_height * 0.6, 0)
		var along: float = (chest - muzzle).dot(dir)
		if along > 0.0 and along < length and (chest - (muzzle + dir * along)).length() < WIDTH:
			victims.append({"enemy": enemy, "along": along})
	victims.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["along"]) < float(y["along"]))
	var beam := Beam.new()
	from.get_tree().current_scene.add_child(beam)
	beam.setup(muzzle, end)
	_muzzle(from, archer, muzzle, dir)
	_floor_scorch(from, muzzle, end)
	_floor_glow(from, muzzle, end)
	_path_debris(from, muzzle, dir, length)
	for victim in victims:
		var enemy: Enemy = victim["enemy"]
		var delay: float = float(victim["along"]) / FLIGHT_SPEED
		from.get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(enemy) and enemy.is_inside_tree():
				_pass_through(from, enemy, dir, stun_seconds))
	from.get_tree().create_timer(length / FLIGHT_SPEED).timeout.connect(func() -> void:
		if is_instance_valid(from) and from.is_inside_tree():
			_end_of_line(from, end, dir))

## Where the arrow is loosed: a flat shock ring on the ground, a flash, a thin horizontal flare, dust blown back, and the camera takes it.
static func _muzzle(from: Node, archer: Node3D, muzzle: Vector3, dir: Vector3) -> void:
	Fx.ring(from, archer.global_position, 4.5, BLUE.lerp(WHITE, 0.3))
	_flash(from, muzzle, 0.9, 0.16)
	_flash(from, muzzle, 0.35, 0.28)
	_flare(from, muzzle, 2.6, 0.14)
	_air_ring(from, muzzle, 3.4, 0.32)
	Fx.burst(from, muzzle, dir + Vector3.UP * 0.1, WHITE, 16, 12.0, 0.012, true)
	Fx.burst(from, muzzle, dir + Vector3.UP * 0.2, BLUE, 12, 7.0, 0.011, true)
	SkillFx.dust(from, archer.global_position - dir * 0.6, 1.5, 18, Color(0.5, 0.55, 0.66, 0.34), 1.0, 0.9)
	_lamp(from, muzzle, 5.0, 10.0, 0.3)
	Fx.shake(from, 0.34)
	Fx.punch(from, 2.0)

## A short-lived point light that is not held to the shared flash-light cap: the bolt lights the room as it goes.
static func _lamp(from: Node, at: Vector3, energy: float, light_range: float, duration: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.72, 1.0)
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	from.get_tree().current_scene.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)

## A wide soft glow laid on the floor under the whole line, brightest where the bolt has just been.
static func _floor_glow(from: Node, a: Vector3, b: Vector3) -> void:
	var flat: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length() < 0.5:
		return
	var node := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var side: Vector3 = flat.cross(Vector3.UP).normalized() * 1.1
	for half in [1.0, -1.0]:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in 13:
			var t: float = float(i) / 12.0
			var point: Vector3 = Vector3(a.x, 0.05, a.z).lerp(Vector3(b.x, 0.05, b.z), t)
			mesh.surface_set_color(Color(0.5, 0.7, 1.0, 0.55))
			mesh.surface_add_vertex(point)
			mesh.surface_set_color(Color(0.3, 0.5, 1.0, 0.0))
			mesh.surface_add_vertex(point + side * half)
		mesh.surface_end()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(node)
	var tween := node.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_callback(node.queue_free)

static func _flash(from: Node, at: Vector3, size: float, duration: float) -> void:
	var node := TakeAimFx._glint_quad(size)
	var mat := (node.mesh as QuadMesh).material as StandardMaterial3D
	mat.albedo_color = Color(0.85, 0.93, 1.0, 0.95)
	from.get_tree().current_scene.add_child(node)
	node.global_position = at
	var tween := node.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_callback(node.queue_free)

## A thin anamorphic streak: a wide, hairline flare across the flash.
static func _flare(from: Node, at: Vector3, width: float, duration: float) -> void:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = Fx.soft_texture()
	mat.albedo_color = Color(0.7, 0.85, 1.0, 0.85)
	quad.material = mat
	node.mesh = quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(node)
	node.global_position = at
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_property(node, "scale", Vector3(1.4, 1.0, 1.0), duration)
	tween.chain().tween_callback(node.queue_free)

static var _ring_texture: GradientTexture2D

## A soft expanding ring of compressed air: a camera-facing additive ring that opens and fades. It does not sample the screen, so it
## leaves no outline.
static func _air_ring(from: Node, at: Vector3, size: float, duration: float) -> void:
	if _ring_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.6, 0.78, 0.9, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
		_ring_texture = GradientTexture2D.new()
		_ring_texture.gradient = gradient
		_ring_texture.fill = GradientTexture2D.FILL_RADIAL
		_ring_texture.fill_from = Vector2(0.5, 0.5)
		_ring_texture.fill_to = Vector2(1.0, 0.5)
		_ring_texture.width = 128
		_ring_texture.height = 128
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _ring_texture
	mat.albedo_color = Color(0.62, 0.78, 1.0, 0.55)
	quad.material = mat
	node.mesh = quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(node)
	node.global_position = at
	node.scale = Vector3(0.15, 0.15, 0.15)
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "scale", Vector3.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(node.queue_free)

## A ring standing across the line of fire, opening outward as the bolt passes through it.
static func _line_ring(from: Node, at: Vector3, dir: Vector3, radius: float, duration: float) -> void:
	var node := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.93
	torus.outer_radius = 1.0
	node.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.55, 0.75, 1.0, 0.8)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(node)
	node.global_position = at
	node.global_basis = Basis(Quaternion(Vector3.UP, dir))
	node.scale = Vector3(0.2, 1.0, 0.2)
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "scale", Vector3(radius, 1.0, radius), duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(node.queue_free)

## The bolt goes through an enemy: a flash, a ring across the line, a spray of sparks along it, and it is left crackling.
static func _pass_through(from: Node, enemy: Enemy, dir: Vector3, stun_seconds: float) -> void:
	var chest: Vector3 = enemy.global_position + Vector3(0, enemy.body_height * 0.6, 0)
	_flash(from, chest, 0.5, 0.12)
	_line_ring(from, chest, dir, 0.9, 0.2)
	_air_ring(from, chest, 1.5, 0.2)
	Fx.burst(from, chest, dir, WHITE, 12, 9.0, 0.012, true)
	Fx.burst(from, chest, dir + Vector3.UP * 0.4, BLUE, 10, 6.0, 0.011, true)
	_lamp(from, chest, 2.5, 6.0, 0.2)
	Fx.shake(from, 0.06)
	stun_marker(enemy, stun_seconds)

## Dust and chips thrown up along the floor under the line, in step with the bolt.
static func _path_debris(from: Node, muzzle: Vector3, dir: Vector3, length: float) -> void:
	var d: float = 2.5
	while d < length:
		var at := Vector3(muzzle.x + dir.x * d, 0.05, muzzle.z + dir.z * d)
		from.get_tree().create_timer(d / FLIGHT_SPEED).timeout.connect(func() -> void:
			if is_instance_valid(from) and from.is_inside_tree():
				Fx.burst(from, at, Vector3.UP, Color(0.62, 0.66, 0.74), 5, 3.5, 0.022))
		d += 3.0

## A thin scorch left on the floor under the whole line, fading over a few seconds.
static func _floor_scorch(from: Node, a: Vector3, b: Vector3) -> void:
	var node := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var flat: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length() < 0.5:
		return
	var side: Vector3 = flat.cross(Vector3.UP).normalized() * 0.2
	var start := Vector3(a.x, 0.03, a.z)
	var stop := Vector3(b.x, 0.03, b.z)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 9:
		var t: float = float(i) / 8.0
		var point: Vector3 = start.lerp(stop, t)
		var fade: float = (1.0 - t * 0.7) * sin(minf(t * 8.0, 1.0) * PI * 0.5)
		mesh.surface_set_color(Color(0.02, 0.03, 0.07, 0.55 * fade))
		mesh.surface_add_vertex(point + side)
		mesh.surface_set_color(Color(0.02, 0.03, 0.07, 0.55 * fade))
		mesh.surface_add_vertex(point - side)
	mesh.surface_end()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(node)
	var tween := node.create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(mat, "albedo_color:a", 0.0, 2.5)
	tween.tween_callback(node.queue_free)

static func _end_of_line(from: Node, end: Vector3, dir: Vector3) -> void:
	_flash(from, end, 0.6, 0.16)
	_line_ring(from, end, dir, 1.6, 0.3)
	Fx.burst(from, end, -dir + Vector3.UP * 0.5, BLUE, 12, 6.0, 0.011, true)
	SkillFx.dust(from, Vector3(end.x, 0.05, end.z), 1.0, 12, Color(0.5, 0.55, 0.66, 0.3), 1.0, 0.8)

## Marks an enemy as stunned: small arcs jump around its head and shoulders for `seconds`, then die away.
static func stun_marker(enemy: Enemy, seconds: float) -> void:
	for old in enemy.find_children("ThunderousStun", "Node3D", false, false):
		old.queue_free()
	var marker := Stun.new()
	marker.name = "ThunderousStun"
	enemy.add_child(marker)
	marker.setup(enemy, seconds)

## The bolt itself: an arrow made of lightning. The real arrow flies down the line inside a blue sheath with small arcs crawling over it,
## a jagged strand trails behind it (thick and bright at the arrow, thinning into the dark), and forks flick off the trail and strike the
## floor as it passes. What it has crossed stays faintly alight for a moment, and lights come up down the line as the arrow reaches them.
class Beam extends Node3D:
	const ARROW_MODEL := "res://assets/models/archer/arrow/model.glb"
	const TRAIL := 9.0       # metres of strand behind the arrow
	const FORK_LIFE := 0.18
	const ARROW_SCALE := 1.6   # the arrow is drawn larger than life so it reads from the camera
	var a: Vector3
	var b: Vector3
	var _age: float = 0.0
	var _mesh := ImmediateMesh.new()
	var _head: MeshInstance3D
	var _arrow: Node3D
	var _arrow_overlays: Array[ShaderMaterial] = []
	var _rng := RandomNumberGenerator.new()
	var _jit: Array = []
	var _roll: float = 0.0
	var _lights: Array[OmniLight3D] = []
	var _light_at: Array[float] = []
	var _forks: Array[Dictionary] = []

	func setup(from_point: Vector3, to_point: Vector3) -> void:
		a = from_point
		b = to_point
		name = "ThunderousBeam"
		add_to_group(ThunderousShotFx.GROUP)
		top_level = true
		_rng.randomize()
		var strip := MeshInstance3D.new()
		strip.mesh = _mesh
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.material_override = TakeAimFx._line_material()
		strip.top_level = true
		add_child(strip)
		_head = TakeAimFx._glint_quad(0.6)
		add_child(_head)
		_make_arrow()
		var length: float = a.distance_to(b)
		# Forks that will strike the floor beside the trail, about every two metres down the line.
		var d: float = 1.5
		while d < length - 0.5:
			var side: Vector3 = Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.5, 1.2)
			var jit: Array = []
			for k in 6:
				jit.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0))
			_forks.append({"t": d / length, "side": side, "jit": jit, "born": -1.0})
			d += _rng.randf_range(1.6, 2.6)
		# Lights spaced down the line come up as the arrow reaches them and die away behind it, with a flicker.
		var count: int = clampi(int(length / 5.0), 3, 7)
		for i in count:
			var light := OmniLight3D.new()
			light.light_color = Color(0.55, 0.72, 1.0)
			light.light_energy = 0.0
			light.omni_range = 8.0
			light.shadow_enabled = false
			add_child(light)
			_lights.append(light)
			_light_at.append((float(i) + 0.5) / count)

	## The real arrow, in a blue sheath: a rim of light over the whole shaft and a white-hot head.
	func _make_arrow() -> void:
		var scene := load(ARROW_MODEL) as PackedScene
		if scene == null:
			return
		_arrow = Node3D.new()
		_arrow.top_level = true
		add_child(_arrow)
		var model: Node3D = scene.instantiate()
		LootDrop._use_vertex_colours(model)
		_arrow.add_child(model)
		var bounds: AABB = CharacterModel._bounds_of(model)
		model.position.y -= bounds.end.y   # the tip is the arrow's origin
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var mat := ShaderMaterial.new()
			mat.shader = TakeAimFx._overlay()
			(mesh as MeshInstance3D).material_overlay = mat
			_arrow_overlays.append(mat)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= ThunderousShotFx.BEAM_LIFE:
			queue_free()
			return
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var view: Vector3 = camera.global_position
		var length: float = a.distance_to(b)
		var dir: Vector3 = (b - a).normalized()
		var reach: float = clampf(_age * ThunderousShotFx.FLIGHT_SPEED / maxf(length, 0.01), 0.0, 1.0)
		var fade: float = 1.0 - _age / ThunderousShotFx.BEAM_LIFE
		var head: Vector3 = a.lerp(b, reach)
		_roll -= delta
		if _roll <= 0.0:
			_roll = 0.03
			_jit.clear()
			for i in 24:
				_jit.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0))
		var rv := PackedVector3Array()
		var rc := PackedColorArray()
		var in_flight: bool = reach < 1.0
		# The arrow itself, drawn larger than life, with the sheath brightest at its head.
		if _arrow != null:
			_arrow.visible = in_flight
			_arrow.global_position = head
			_arrow.global_basis = Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3.ONE * ARROW_SCALE)
			for mat in _arrow_overlays:
				mat.set_shader_parameter("tint", ThunderousShotFx.BLUE.lerp(ThunderousShotFx.WHITE, 0.4))
				mat.set_shader_parameter("tip", head)
				mat.set_shader_parameter("tip_glow", 2.2)
				mat.set_shader_parameter("rim", 1.2)
				mat.set_shader_parameter("sweep", -1.0)
		# The trail: three jagged strands from the dark behind up to the arrow, thin at the tail and bright at the head.
		var trail_len: float = minf(head.distance_to(a), TRAIL)
		if trail_len > 0.3:
			var tail: Vector3 = head - dir * trail_len
			var segments: int = maxi(int(trail_len / 0.5), 3)
			for strand in 3:
				var offset: int = strand * 7
				var shifted: Array = _jit.slice(offset) + _jit.slice(0, offset)
				var pts: Array[Vector3] = ThunderousShotFx._jag(tail, head, segments, 0.34 if strand > 0 else 0.15, shifted)
				var live: float = 1.0 if in_flight else fade
				ThunderousShotFx._ribbon(rv, rc, pts, view, 0.05 if strand == 0 else 0.03, ThunderousShotFx.DEEP, ThunderousShotFx.BLUE, 0.4 * live, true)
				ThunderousShotFx._ribbon(rv, rc, pts, view, 0.013 if strand == 0 else 0.007, ThunderousShotFx.BLUE, ThunderousShotFx.WHITE, 0.95 * live, true)
		# Where it has already been stays faintly alight, flickering, and dies away behind it.
		if head.distance_to(a) > 1.0:
			var after: Array[Vector3] = ThunderousShotFx._jag(a, head, maxi(int(head.distance_to(a) / 0.7), 3), 0.2, _jit)
			ThunderousShotFx._ribbon(rv, rc, after, view, 0.016, ThunderousShotFx.BLUE, ThunderousShotFx.BLUE, 0.45 * fade * fade)
		# Small arcs crawling over the arrow's own shaft.
		if in_flight:
			var side: Vector3 = dir.cross(Vector3.UP).normalized()
			for i in 3:
				var back: float = _rng.randf_range(0.15, 1.0)
				var start: Vector3 = head - dir * back + side * _rng.randf_range(-0.12, 0.12) + Vector3.UP * _rng.randf_range(-0.1, 0.12)
				var stop: Vector3 = start - dir * _rng.randf_range(0.25, 0.5) + side * _rng.randf_range(-0.2, 0.2) + Vector3.UP * _rng.randf_range(-0.2, 0.2)
				var arc: Array[Vector3] = ThunderousShotFx._jag(start, stop, 4, 0.06, _jit)
				ThunderousShotFx._ribbon(rv, rc, arc, view, 0.007, ThunderousShotFx.WHITE, ThunderousShotFx.BLUE, 0.9)
		# Forks: as the arrow passes a mark, a bolt flicks from the trail down to the floor beside it, with a spark spray and a flash.
		for fork in _forks:
			var at: Vector3 = a.lerp(b, float(fork["t"]))
			if float(fork["born"]) < 0.0:
				if reach >= float(fork["t"]):
					fork["born"] = _age
					var ground: Vector3 = Vector3(at.x, 0.05, at.z) + (fork["side"] as Vector3)
					Fx.burst(self, ground, Vector3.UP, ThunderousShotFx.WHITE, 8, 5.0, 0.011, true)
					Fx.burst(self, ground, Vector3.UP, ThunderousShotFx.BLUE, 6, 3.0, 0.01, true)
					ThunderousShotFx._lamp(self, ground + Vector3(0, 0.4, 0), 3.0, 5.0, 0.15)
				continue
			var life: float = 1.0 - (_age - float(fork["born"])) / FORK_LIFE
			if life <= 0.0:
				continue
			var from_trail: Vector3 = at + Vector3(0, 1.1, 0)
			var to_ground: Vector3 = Vector3(at.x, 0.05, at.z) + (fork["side"] as Vector3)
			var bolt: Array[Vector3] = ThunderousShotFx._jag(from_trail, to_ground, 7, 0.22, fork["jit"])
			ThunderousShotFx._ribbon(rv, rc, bolt, view, 0.035 * life, ThunderousShotFx.VIOLET, ThunderousShotFx.BLUE, 0.4 * life)
			ThunderousShotFx._ribbon(rv, rc, bolt, view, 0.008, ThunderousShotFx.BLUE, ThunderousShotFx.WHITE, 1.0 * life)
		_mesh.clear_surfaces()
		if rv.size() >= 4:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in rv.size():
				_mesh.surface_set_color(rc[i])
				_mesh.surface_add_vertex(rv[i])
			_mesh.surface_end()
		for i in _lights.size():
			var at_t: float = _light_at[i]
			var lit: float = clampf((reach - at_t) * 6.0 + 1.0, 0.0, 1.0) if reach >= at_t else 0.0   # arrives with the arrow
			_lights[i].global_position = a.lerp(b, at_t) + Vector3(0, 0.6, 0)
			_lights[i].light_energy = 4.5 * lit * fade * fade * _rng.randf_range(0.65, 1.0)
		# A white-hot flare at the arrow's head while it flies.
		_head.global_position = head
		(_head.mesh as QuadMesh).size = Vector2(0.7, 0.7)
		((_head.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = Color(0.85, 0.93, 1.0, 0.9 if in_flight else 0.0)

## A stunned enemy's crackle: a few small bolts jumping between points around the head and shoulders, redrawn about twenty times a second.
class Stun extends Node3D:
	const VISIBLE := 2.0
	var enemy: Enemy
	var _left: float = 0.0
	var _age: float = 0.0
	var _mesh := ImmediateMesh.new()
	var _rng := RandomNumberGenerator.new()
	var _roll: float = 0.0
	var _bolts: Array[Dictionary] = []
	var _aura: MeshInstance3D

	func setup(target: Enemy, seconds: float) -> void:
		enemy = target
		_left = minf(seconds, VISIBLE)   # the crackle shows the hit, it does not run for the whole stun
		_rng.randomize()
		_aura = TakeAimFx._glint_quad(1.0)
		_aura.top_level = true
		add_child(_aura)
		var strip := MeshInstance3D.new()
		strip.mesh = _mesh
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.material_override = TakeAimFx._line_material()
		strip.top_level = true
		add_child(strip)

	func _process(delta: float) -> void:
		_left -= delta
		_age += delta
		if _left <= 0.0 or not is_instance_valid(enemy) or enemy.dead:
			queue_free()
			return
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		# A burst of crackle as it is hit, then a few small arcs now and then as it fades.
		var strong: bool = _age < 0.5
		var intensity: float = 1.0 if strong else maxf(0.45 * (1.0 - (_age - 0.5) / (VISIBLE - 0.5)), 0.0)
		_roll -= delta
		if _roll <= 0.0:
			_roll = 0.05 if strong else 0.22
			_bolts.clear()
			for i in (_rng.randi_range(2, 3) if strong else 1):
				var jit: Array[Vector3] = []
				for k in 5:
					jit.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0))
				_bolts.append({"a": _rng.randf_range(0.0, TAU), "b": _rng.randf_range(0.0, TAU), "ha": _rng.randf_range(0.25, 0.95), "hb": _rng.randf_range(0.2, 1.0), "jit": jit})
		var fade: float = clampf(_left / 0.5, 0.0, 1.0)
		var centre: Vector3 = enemy.global_position
		var h: float = enemy.body_height
		var view: Vector3 = camera.global_position
		var rv := PackedVector3Array()
		var rc := PackedColorArray()
		for bolt in _bolts:
			var p0: Vector3 = centre + Vector3(cos(float(bolt["a"])) * 0.22, h * float(bolt["ha"]), sin(float(bolt["a"])) * 0.22)
			var p1: Vector3 = centre + Vector3(cos(float(bolt["b"])) * 0.6, h * float(bolt["hb"]), sin(float(bolt["b"])) * 0.6)
			var pts: Array[Vector3] = ThunderousShotFx._jag(p0, p1, 7, 0.1, bolt["jit"])
			ThunderousShotFx._ribbon(rv, rc, pts, view, 0.022, ThunderousShotFx.BLUE, ThunderousShotFx.BLUE, 0.35 * fade * intensity)
			ThunderousShotFx._ribbon(rv, rc, pts, view, 0.006, ThunderousShotFx.WHITE, ThunderousShotFx.WHITE, 0.95 * fade * intensity)
		_aura.global_position = centre + Vector3(0, h * 0.6, 0)
		(_aura.mesh as QuadMesh).size = Vector2(h * 0.7, h * 0.7)
		((_aura.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = Color(0.4, 0.6, 1.0, fade * intensity * _rng.randf_range(0.06, 0.14))
		_mesh.clear_surfaces()
		if rv.size() >= 4:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in rv.size():
				_mesh.surface_set_color(rc[i])
				_mesh.surface_add_vertex(rv[i])
			_mesh.surface_end()
