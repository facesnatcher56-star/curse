class_name SkillFx
extends RefCounted
## Heavy-hitting visuals for the sword skills and the gear that modifies them: impacts, sweeping slash discs,
## ground cracks, dust, travelling shockwaves and vortexes. Everything spawns into the current scene and cleans itself up.

const FACING_FORWARD := Vector3(0, 0, 1)

# --- building blocks ------------------------------------------------------------------

## A flat glowing ring-sector (or full disc ring) that sweeps through its arc while it fades: a visible blade arc.
## `arc` is the angular width (TAU for a full circle), `sweep` how far it rotates during `duration`.
static func slash_arc(from: Node, centre: Vector3, facing_yaw: float, inner: float, outer: float, arc: float,
		color: Color, duration: float, sweep: float, height: float = 0.9) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = maxi(int(arc / 0.15), 4)
	for i in segments:
		var a0: float = -arc * 0.5 + arc * float(i) / float(segments)
		var a1: float = -arc * 0.5 + arc * float(i + 1) / float(segments)
		var in0 := Vector3(sin(a0), 0, cos(a0)) * inner
		var in1 := Vector3(sin(a1), 0, cos(a1)) * inner
		var out0 := Vector3(sin(a0), 0, cos(a0)) * outer
		var out1 := Vector3(sin(a1), 0, cos(a1)) * outer
		# Bright leading edge on the outside, fading toward the centre.
		var clear := Color(color.r, color.g, color.b, 0.0)
		for v in [[in0, clear], [out0, color], [out1, color], [in0, clear], [out1, color], [in1, clear]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(mesh_instance)
	mesh_instance.global_position = Vector3(centre.x, height, centre.z)
	mesh_instance.rotation.y = facing_yaw - sweep * 0.5
	mesh_instance.scale = Vector3(0.75, 1.0, 0.75)
	var tween := mesh_instance.create_tween().set_parallel(true)
	tween.tween_property(mesh_instance, "rotation:y", facing_yaw + sweep * 0.5, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mesh_instance, "scale", Vector3(1.08, 1.0, 1.08), duration)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration).set_delay(duration * 0.35)
	tween.chain().tween_callback(mesh_instance.queue_free)

## Ring on the ground that expands from `from_radius` to `to_radius` (shrinks when to < from: a vortex) and fades.
static func ground_ring(from: Node, centre: Vector3, from_radius: float, to_radius: float, color: Color, duration: float,
		delay: float = 0.0, thickness: float = 0.12) -> void:
	var mesh_instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0 - thickness
	torus.outer_radius = 1.0
	mesh_instance.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(mesh_instance)
	mesh_instance.global_position = Vector3(centre.x, 0.07, centre.z)
	mesh_instance.scale = Vector3(from_radius, 1.0, from_radius)
	var tween := mesh_instance.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_callback(func() -> void: mat.albedo_color = Color(color.r, color.g, color.b, color.a))
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3(to_radius, 1.0, to_radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(mesh_instance.queue_free)

## Soft smoke-like puff for dust and debris clouds.
static func dust(from: Node, pos: Vector3, radius: float, amount: int, color: Color = Color(0.42, 0.37, 0.31, 0.42),
		rise: float = 1.2, life: float = 0.9) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.35
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = radius * 0.8
	p.initial_velocity_max = radius * 2.2
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7) * (0.6 + rise * 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(color.r, color.g, color.b, 0.0), color, Color(color.r, color.g, color.b, 0.0)])
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.7))
	p.scale_amount_curve = curve
	from.get_tree().current_scene.add_child(p)
	p.global_position = Vector3(pos.x, 0.15, pos.z)
	p.emitting = true
	from.get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)

## Thin dark fissures radiating from a point; they linger a while and recycle with the blood stains.
static func ground_cracks(from: Node, centre: Vector3, count: int, min_len: float, max_len: float,
		color: Color = Color(0.05, 0.04, 0.03, 0.7), width: float = 0.05, lifetime: float = 12.0) -> void:
	var stains: Array[Node] = from.get_tree().get_nodes_in_group("stains")
	var base_angle: float = randf() * TAU
	for i in count:
		if stains.size() + i > 70 and not stains.is_empty():
			stains[0].queue_free()
			stains.remove_at(0)
		var angle: float = base_angle + TAU * float(i) / float(count) + randf_range(-0.25, 0.25)
		var length: float = randf_range(min_len, max_len)
		var dir := Vector3(sin(angle), 0, cos(angle))
		var quad := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(width * randf_range(0.7, 1.3), length)
		quad.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = color
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.add_to_group("stains")
		from.get_tree().current_scene.add_child(quad)
		quad.global_position = Vector3(centre.x, 0.03, centre.z) + dir * length * 0.5
		quad.rotation.y = angle
		var tween := quad.create_tween()
		tween.tween_interval(lifetime * 0.6)
		tween.tween_property(mat, "albedo_color:a", 0.0, lifetime * 0.4)
		tween.tween_callback(quad.queue_free)

## Rock chips and clods thrown up by a crushing blow.
static func debris(from: Node, pos: Vector3, amount: int, speed: float) -> void:
	Fx.burst(from, pos + Vector3(0, 0.2, 0), Vector3.UP, Color(0.34, 0.31, 0.28), amount, speed, 0.07)
	Fx.burst(from, pos + Vector3(0, 0.2, 0), Vector3.UP, Color(0.2, 0.17, 0.14), int(amount * 0.6), speed * 0.8, 0.045)

# --- Stored powers ---------------------------------------------------------------------

## Brutal Attack's owner-approved crimson rupture follows a landed empowered hit.
## Meshy shards and a narrow contact tear carry the weight of the empowered blow.
static func brutal_impact(from: Node, point: Vector3, direction: Vector3, rank: int = 1) -> void:
	BrutalAttackFx.impact(from, point, direction, rank)

## efct_take_aim_charge: white motes converge on the bow hand over ~0.4 s.
## The separate orange body pre-launch aura lasts until the stored shot is spent.
static func take_aim_charge(bow: Node3D) -> void:
	var gather := CPUParticles3D.new()
	gather.name = "TakeAimCharge"
	gather.amount = 30
	gather.one_shot = true
	gather.explosiveness = 1.0
	gather.lifetime = 0.4
	gather.local_coords = true
	gather.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	gather.emission_sphere_radius = 1.3
	gather.radial_accel_min = -20.0
	gather.radial_accel_max = -20.0
	gather.initial_velocity_min = 0.0
	gather.initial_velocity_max = 0.0
	gather.gravity = Vector3.ZERO
	gather.mesh = BrutalAttackFx._soft_quad(Vector2(0.045, 0.045), Color.WHITE)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.96, 0.8, 0.0))
	ramp.add_point(0.2, Color(1.0, 0.96, 0.8, 0.65))
	ramp.set_color(1, Color(1.0, 0.96, 0.8, 0.0))
	gather.color_ramp = ramp
	bow.add_child(gather)
	gather.scale = Vector3.ONE / maxf(bow.global_basis.get_scale().x, 0.001)
	gather.finished.connect(gather.queue_free)
	Fx.light_flash(bow, bow.global_position, Color(1.0, 0.96, 0.78), 1.1, 0.4)

## The empowered arrow keeps a narrow dirty-white wake. It is intentionally much thinner than a spell projectile.
static func take_aim_trail(arrow: Node3D) -> void:
	# A narrow, warm pressure streak reads at gameplay zoom without becoming a fireball.
	var core := MeshInstance3D.new()
	core.name = "TakeAimCore"
	var streak := CylinderMesh.new()
	streak.top_radius = 0.018
	streak.bottom_radius = 0.002
	streak.height = 1.4
	streak.radial_segments = 8
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.95, 0.72, 0.38)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.56, 0.18)
	core_mat.emission_energy_multiplier = 1.8
	streak.material = core_mat
	core.mesh = streak
	core.position.y = -0.7
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(core)
	var trail := CPUParticles3D.new()
	trail.amount = 28
	trail.lifetime = 0.12
	trail.randomness = 0.25
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.025
	trail.direction = Vector3.ZERO
	trail.spread = 8.0
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.12
	trail.gravity = Vector3(0, -0.25, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.065, 0.20)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	trail.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.95, 0.80, 0.55, 0.72))
	ramp.add_point(0.45, Color(0.72, 0.52, 0.28, 0.34))
	ramp.set_color(1, Color(0.18, 0.12, 0.08, 0.0))
	trail.color_ramp = ramp
	arrow.add_child(trail)

static func take_aim_hit(from: Node, point: Vector3, direction: Vector3) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD
	Fx.light_flash(from, point + Vector3(0, 0.65, 0), Color(0.90, 0.63, 0.28), 2.2, 0.10)
	Fx.burst(from, point + Vector3(0, 0.65, 0), dir, Color(0.88, 0.67, 0.38), 18, 8.5, 0.022, true)
	Fx.burst(from, point + Vector3(0, 0.55, 0), dir, Color(0.22, 0.15, 0.10), 10, 5.0, 0.035)
	Fx.shake(from, 0.14)
