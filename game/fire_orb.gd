class_name FireOrb
extends Node3D
## The fireball being gathered above the caster's head: a swelling core, a soft glow, a light that
## brightens with size, and embers pulled inward. Released into a Projectile on the throw.

var _size: float = 0.25
var _tween: Tween
var _age: float = 0.0
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _light: OmniLight3D
var _embers: CPUParticles3D
var _fading: bool = false

func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(1.0, 0.6, 0.15)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.45, 0.08)
	core_mat.emission_energy_multiplier = 4.0
	_core = MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.5
	core_mesh.height = 1.0
	_core.mesh = core_mesh
	_core.material_override = core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_color = Color(1.0, 0.4, 0.08, 0.3)
	_glow = MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.85
	glow_mesh.height = 1.7
	_glow.mesh = glow_mesh
	_glow.material_override = glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 7.0
	add_child(_light)

	_embers = CPUParticles3D.new()
	_embers.amount = 36
	_embers.lifetime = 0.45
	_embers.preprocess = 0.2
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_embers.emission_sphere_radius = 1.2
	_embers.initial_velocity_min = 0.0
	_embers.initial_velocity_max = 0.0
	_embers.radial_accel_min = -9.0
	_embers.radial_accel_max = -9.0
	_embers.gravity = Vector3.ZERO
	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.03
	ember_mesh.height = 0.06
	ember_mesh.radial_segments = 6
	ember_mesh.rings = 3
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.albedo_color = Color(1.0, 0.7, 0.25)
	ember_mesh.material = ember_mat
	_embers.mesh = ember_mesh
	add_child(_embers)
	_apply_size()

## Swell (or shrink) to `size` (radius in metres) over `seconds`.
func grow_to(size: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_size", size, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func current_size() -> float:
	return _size

func _process(delta: float) -> void:
	_age += delta
	_apply_size()

func _apply_size() -> void:
	if _core == null:
		return
	var pulse: float = 1.0 + 0.07 * sin(_age * 17.0) + 0.04 * sin(_age * 29.0)
	var s: float = _size * pulse
	_core.scale = Vector3.ONE * s
	_glow.scale = Vector3.ONE * s * (0.75 + 0.15 * sin(_age * 9.0))
	_light.light_energy = 1.0 + 6.0 * _size
	_embers.emission_sphere_radius = 0.7 + _size * 1.4

## Launch point for the projectile; the orb itself goes away with a small burst.
func release() -> Vector3:
	var at: Vector3 = global_position
	Fx.burst(self, at, Vector3.UP, Color(1.0, 0.6, 0.2), 18, 5.0, 0.04, true)
	queue_free()
	return at

func fade_out() -> void:
	if _fading:
		return
	_fading = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_size", 0.0, 0.18)
	_tween.tween_callback(queue_free)
