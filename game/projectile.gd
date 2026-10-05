class_name Projectile
extends Node3D
## Fireball: flies straight, explodes on the first enemy it touches (or at max range).

## Radius of the explosion; the aiming preview uses the same number so what you see is what gets hit.
const BLAST_RADIUS := 2.6

var owner_actor: Actor
var direction: Vector3 = Vector3.FORWARD
var destination: Vector3 = Vector3.ZERO
var speed: float = 18.0
var damage: float = 20.0
var blast_radius: float = BLAST_RADIUS

var _done: bool = false

func _ready() -> void:
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56
	orb.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 3.0
	orb.material_override = mat
	add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 6.0
	light.light_energy = 2.5
	add_child(light)

## Flies straight to the aimed point and explodes exactly there.
func _physics_process(delta: float) -> void:
	if _done:
		return
	var step: float = speed * delta
	var to_target: Vector3 = destination - global_position
	if to_target.length() <= step:
		global_position = destination
		_explode()
		return
	global_position += to_target.normalized() * step
func _explode() -> void:
	_done = true
	var center: Vector3 = global_position
	Destructible.blast(get_tree(), center, blast_radius, 70.0, Vector3.ZERO, 1.6)
	var caught: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.dead:
			continue
		var dist: float = enemy.flat_distance_to(self)
		if dist > blast_radius:
			continue
		var closeness: float = 1.0 - dist / blast_radius   # 1 at the centre, 0 at the rim
		var result: Dictionary = Combat.resolve(owner_actor, enemy, damage * (0.8 + 0.4 * closeness), Combat.DamageType.FIRE, false, 1.4)
		enemy.receive(result, center)
		caught += 1
		if not is_instance_valid(enemy):
			continue
		enemy.apply_burn(maxf(damage * 0.18, 3.0), 4.0 + 2.0 * closeness)
		# Close to the blast: thrown clear by the shockwave, further out only staggered.
		if closeness >= 0.4 and not enemy.is_boss and enemy.impalable:
			var away: Vector3 = enemy.global_position - center
			away.y = 0.0
			away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
			var force: float = 0.4 + closeness
			var spin: Vector3 = away.cross(Vector3.UP) * (3.0 + 5.0 * closeness) + Vector3.UP * randf_range(-1.5, 1.5)
			enemy.ragdoll_launch(away * (4.0 + 6.0 * force), 3.0 + 3.5 * force, spin)
		else:
			enemy.interrupt(0.5)
	if owner_actor is Player:
		ItemEffects.on_fireball_blast(owner_actor as Player, caught)
	Fx.shake(self, 0.22)
	Fx.punch(self, 2.0)
	Fx.hitstop(self, 0.05)
	Sfx.sample(self, "fireball_impact", 1.0, 1.0)
	_explosion_visuals(center)
	queue_free()

func _explosion_visuals(center: Vector3) -> void:
	var scene: Node = get_parent()
	var ground := Vector3(center.x, 0.0, center.z)
	# Blinding flash, shockwave and flying sparks.
	Fx.light_flash(scene, center + Vector3(0, 0.8, 0), Color(1.0, 0.65, 0.3), 9.0, 0.3)
	Fx.ring(scene, ground + Vector3(0, 0.1, 0), blast_radius * 1.3, Color(1.0, 0.7, 0.35))
	Fx.burst(scene, center, Vector3.UP, Color(1.0, 0.7, 0.25), 60, 11.0, 0.035, true)
	# Fireball: a hot white core that balloons and cools to dark orange, then fades.
	var core := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	core.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.95, 0.7, 0.9)
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(core)
	core.global_position = ground + Vector3(0, 0.7, 0)
	core.scale = Vector3.ONE * 0.6
	var tween := core.create_tween().set_parallel(true)
	tween.tween_property(core, "scale", Vector3(1.9, 1.5, 1.9) * blast_radius, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color", Color(0.9, 0.25, 0.04, 0.0), 0.45).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(core.queue_free)
	# Rolling flame, then smoke drifting up from the blast.
	_puff(scene, ground, 46, 0.75, blast_radius * 0.5, Vector2(0.9, 0.9), 3.0, 5.0,
		[Color(1.0, 0.8, 0.3, 0.9), Color(0.9, 0.25, 0.05, 0.5), Color(0.1, 0.05, 0.03, 0.0)], true, 0.0)
	_puff(scene, ground + Vector3(0, 0.5, 0), 30, 2.2, blast_radius * 0.45, Vector2(1.3, 1.3), 1.4, 2.2,
		[Color(0.18, 0.16, 0.15, 0.0), Color(0.16, 0.14, 0.13, 0.65), Color(0.1, 0.09, 0.09, 0.0)], false, 0.12)
	# Scorched earth: a dark charred patch with a glowing ember bed that cools off.
	Fx.blood_decal(scene, ground, blast_radius * 1.15, Color(0.02, 0.015, 0.012, 0.9))
	Fx.blood_decal(scene, ground, blast_radius * 0.8, Color(0.0, 0.0, 0.0, 0.5))
	_ember_bed(scene, ground)
	# Smouldering afterwards: thin smoke and drifting embers for several seconds.
	var smoulder := Node3D.new()
	scene.add_child(smoulder)
	smoulder.global_position = ground
	_puff(smoulder, ground, 14, 3.0, blast_radius * 0.5, Vector2(0.7, 0.7), 0.5, 1.0,
		[Color(0.3, 0.28, 0.26, 0.0), Color(0.25, 0.23, 0.22, 0.35), Color(0.15, 0.14, 0.14, 0.0)], false, 0.0, true)
	_puff(smoulder, ground, 8, 1.4, blast_radius * 0.45, Vector2(0.09, 0.09), 0.4, 1.1,
		[Color(1.0, 0.6, 0.15, 1.0), Color(0.9, 0.2, 0.03, 0.6), Color(0.3, 0.05, 0.0, 0.0)], true, 0.0, true)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.4, 0.1)
	glow.omni_range = 5.0
	glow.light_energy = 1.2
	glow.position = Vector3(0, 0.3, 0)
	smoulder.add_child(glow)
	var out := smoulder.create_tween()
	out.tween_property(glow, "light_energy", 0.0, 6.0)
	out.tween_interval(1.0)
	out.tween_callback(smoulder.queue_free)

## Billboarded particle puff. `loop` keeps it emitting (for smouldering); otherwise it fires once.
func _puff(parent: Node, at: Vector3, amount: int, life: float, radius: float, size: Vector2, speed_min: float,
		speed_max: float, ramp_colors: Array, additive: bool, rise: float, loop: bool = false) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = not loop
	p.explosiveness = 0.0 if loop else 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 70.0 if not loop else 25.0
	p.gravity = Vector3(0, 1.2 + rise * 4.0, 0)
	p.initial_velocity_min = speed_min * (0.3 if loop else 1.0)
	p.initial_velocity_max = speed_max * (0.5 if loop else 1.0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray(ramp_colors)
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0]) if ramp_colors.size() == 3 else PackedFloat32Array([0.0, 1.0])
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	if not loop:
		get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)

## Glowing red-hot patch on the ground that cools over a few seconds.
func _ember_bed(scene: Node, ground: Vector3) -> void:
	var quad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * blast_radius * 1.5
	quad.mesh = plane
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 0.35, 0.06, 0.8)
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(quad)
	quad.global_position = ground + Vector3(0, 0.035, 0)
	var tween := quad.create_tween()
	tween.tween_property(mat, "albedo_color", Color(0.7, 0.12, 0.02, 0.35), 2.5)
	tween.tween_property(mat, "albedo_color:a", 0.0, 4.0)
	tween.tween_callback(quad.queue_free)
