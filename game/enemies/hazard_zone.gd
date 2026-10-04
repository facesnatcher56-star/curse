class_name HazardZone
extends Node3D
## A patch of ground that poisons and slows whatever stands in it for a few seconds (acid puddles, bloater gas).
## Only the hero is hurt; enemies shrug it off.

var radius: float = 1.5
var lifetime: float = 3.5
var dps: float = 5.0
var slow: float = 0.3
var color: Color = Color(0.45, 0.85, 0.2)
var source: Actor

var _age: float = 0.0
var _tick: float = 0.0
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _bubbles: CPUParticles3D

func _ready() -> void:
	add_to_group("hazards")
	# Glowing pool on the ground.
	var pool := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.2
	pool.mesh = plane
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_texture = Fx.soft_texture()
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	pool.material_override = _mat
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position.y = 0.05
	add_child(pool)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 0.9
	_light.omni_range = radius * 2.2
	_light.position.y = 0.5
	add_child(_light)
	# Bubbles rising off it.
	_bubbles = CPUParticles3D.new()
	_bubbles.amount = int(10 + radius * 6.0)
	_bubbles.lifetime = 1.1
	_bubbles.local_coords = false
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = radius * 0.8
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 15.0
	_bubbles.initial_velocity_min = 0.3
	_bubbles.initial_velocity_max = 0.9
	_bubbles.gravity = Vector3(0, 0.3, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	bm.vertex_color_use_as_albedo = true
	bm.albedo_texture = Fx.soft_texture()
	quad.material = bm
	_bubbles.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 0.7))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	_bubbles.color_ramp = ramp
	add_child(_bubbles)

func _physics_process(delta: float) -> void:
	_age += delta
	var fade_in: float = clampf(_age / 0.25, 0.0, 1.0)
	var fade_out: float = clampf((lifetime - _age) / 0.8, 0.0, 1.0)
	var strength: float = minf(fade_in, fade_out)
	_mat.albedo_color.a = 0.55 * strength
	_light.light_energy = 0.9 * strength
	if _age >= lifetime:
		queue_free()
		return
	_tick += delta
	if _tick < 0.4:
		return
	_tick = 0.0
	for node in get_tree().get_nodes_in_group("player"):
		var hero := node as Actor
		if hero == null or hero.dead:
			continue
		var gap: Vector3 = hero.global_position - global_position
		gap.y = 0.0
		if gap.length() > radius + hero.body_radius * 0.5:
			continue
		hero.apply_slow(slow, 0.8)
		if hero.invulnerable_time > 0.0:
			continue
		var amount: float = dps * 0.4
		var result: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": amount, "quiet": true, "source": source,
			"type": Combat.DamageType.FIRE, "secondary": true}
		hero.receive(result, global_position)
		Fx.text_at(hero, hero.global_position + Vector3(randf_range(-0.3, 0.3), 2.0, 0), str(int(round(amount))), Color(0.55, 0.9, 0.25), 32)
