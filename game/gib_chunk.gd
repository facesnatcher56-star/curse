class_name GibChunk
extends Node3D
## One flying piece of a burst body: simple ballistic motion with a bounce, a spin, a blood smear where it lands and,
## for fire kills, flames and a char-black body that glows for a few seconds.

const GRAVITY := 22.0

var velocity: Vector3 = Vector3.ZERO
var spin: Vector3 = Vector3.ZERO
var burning: bool = false

var _mesh: MeshInstance3D
var _age: float = 0.0
var _resting: bool = false
var _flames: CPUParticles3D
var _burn_time: float = 0.0

func setup(kind: String, size: Vector3, skin: Color) -> void:
	_mesh = MeshInstance3D.new()
	match kind:
		"sphere":
			var s := SphereMesh.new()
			s.radius = size.x
			s.height = size.x * 2.0
			_mesh.mesh = s
		"capsule":
			var c := CapsuleMesh.new()
			c.radius = size.x
			c.height = maxf(size.y, size.x * 2.2)
			_mesh.mesh = c
		_:
			var b := BoxMesh.new()
			b.size = size
			_mesh.mesh = b
	var mat := StandardMaterial3D.new()
	if burning:
		mat.albedo_color = Color(0.07, 0.055, 0.05)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.35, 0.06)
		mat.emission_energy_multiplier = 1.6
	else:
		mat.albedo_color = skin.lerp(Color(0.5, 0.04, 0.03), randf_range(0.35, 0.7))
	mat.roughness = 0.85
	_mesh.material_override = mat
	add_child(_mesh)

func _ready() -> void:
	add_to_group("gibs")
	if burning:
		_burn_time = randf_range(4.0, 6.0)
		_flames = CPUParticles3D.new()
		_flames.amount = 14
		_flames.lifetime = 0.55
		_flames.local_coords = false
		_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_flames.emission_sphere_radius = 0.12
		_flames.direction = Vector3.UP
		_flames.spread = 25.0
		_flames.initial_velocity_min = 0.4
		_flames.initial_velocity_max = 1.2
		_flames.gravity = Vector3(0, 2.0, 0)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.3, 0.3)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fm.vertex_color_use_as_albedo = true
		fm.albedo_texture = Fx.soft_texture()
		quad.material = fm
		_flames.mesh = quad
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.85, 0.3, 0.9))
		ramp.set_color(1, Color(0.8, 0.1, 0.0, 0.0))
		_flames.color_ramp = ramp
		add_child(_flames)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.15)
		light.light_energy = 0.8
		light.omni_range = 2.5
		add_child(light)

func _physics_process(delta: float) -> void:
	_age += delta
	if burning and _flames != null:
		_burn_time -= delta
		if _burn_time <= 0.0:
			_flames.emitting = false
			_flames.queue_free()
			_flames = null
			var mat := _mesh.material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = 0.0   # cooled, left black
	if _age > 9.0:
		position.y -= 0.5 * delta
		if _age > 11.0:
			queue_free()
		return
	if _resting:
		return
	velocity.y -= GRAVITY * delta
	global_position += velocity * delta
	rotation += spin * delta
	if global_position.y <= 0.08:
		global_position.y = 0.08
		if velocity.y < -2.0:
			velocity.y = -velocity.y * 0.38
			velocity.x *= 0.62
			velocity.z *= 0.62
			spin *= 0.6
			Fx.blood_decal(self, global_position, randf_range(0.3, 0.55), Color(0.3, 0.02, 0.02))
		else:
			velocity.y = 0.0
			velocity.x *= pow(0.02, delta)
			velocity.z *= pow(0.02, delta)
			spin *= pow(0.05, delta)
			if Vector2(velocity.x, velocity.z).length() < 0.3 and spin.length() < 0.6:
				_resting = true
