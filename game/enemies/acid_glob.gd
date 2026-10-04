class_name AcidGlob
extends Node3D
## A lobbed glob of acid: arcs to a marked spot (the marker shows where, so the hero can step out), splashes whoever is
## standing there and leaves a HazardZone puddle behind.

var source: Enemy
var from_pos: Vector3 = Vector3.ZERO
var to_pos: Vector3 = Vector3.ZERO
var flight_time: float = 0.85
var splash_radius: float = 1.3
var damage: float = 8.0
var puddle_radius: float = 1.6
var puddle_time: float = 3.5
var puddle_dps: float = 5.0
var puddle_slow: float = 0.3

var _t: float = 0.0
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("acid_globs")
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	orb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.9, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.95, 0.15)
	mat.emission_energy_multiplier = 3.0
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.95, 0.2)
	light.omni_range = 3.0
	add_child(light)
	# Where it will land.
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.88
	torus.outer_radius = 1.0
	_marker.mesh = torus
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = Color(0.6, 1.0, 0.25, 0.8)
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	add_child(_marker)
	_marker.global_position = Vector3(to_pos.x, 0.08, to_pos.z)
	_marker.scale = Vector3(splash_radius, 1.0, splash_radius)
	global_position = from_pos

func _physics_process(delta: float) -> void:
	_t += delta
	var u: float = clampf(_t / flight_time, 0.0, 1.0)
	var ground: Vector3 = from_pos.lerp(to_pos, u)
	var arc: float = 4.0 * (0.8 + from_pos.distance_to(to_pos) * 0.12) * u * (1.0 - u)
	global_position = Vector3(ground.x, lerpf(from_pos.y, 0.2, u) + arc, ground.z)
	_marker_mat.albedo_color.a = 0.45 + 0.4 * sin(_t * 18.0) * sin(_t * 18.0)
	if u >= 1.0:
		_land()

func _land() -> void:
	var scene: Node = get_tree().current_scene
	Fx.burst(scene, Vector3(to_pos.x, 0.2, to_pos.z), Vector3.UP, Color(0.5, 0.9, 0.2), 28, 6.0, 0.04, true)
	Fx.light_flash(scene, Vector3(to_pos.x, 0.6, to_pos.z), Color(0.5, 0.95, 0.2), 3.0, 0.2)
	SkillFx.ground_ring(scene, to_pos, 0.3, splash_radius * 1.2, Color(0.55, 1.0, 0.25, 0.8), 0.3)
	for node in get_tree().get_nodes_in_group("player"):
		var hero := node as Actor
		if hero == null or hero.dead or not is_instance_valid(source):
			continue
		var gap: Vector3 = hero.global_position - to_pos
		gap.y = 0.0
		if gap.length() <= splash_radius + hero.body_radius * 0.5:
			var result: Dictionary = Combat.resolve(source, hero, damage, Combat.DamageType.FIRE, false, 0.8)
			result["secondary"] = true
			hero.receive(result, to_pos)
	var zone := HazardZone.new()
	zone.radius = puddle_radius
	zone.lifetime = puddle_time
	zone.dps = puddle_dps
	zone.slow = puddle_slow
	zone.source = source if is_instance_valid(source) else null
	scene.add_child(zone)
	zone.global_position = Vector3(to_pos.x, 0.0, to_pos.z)
	queue_free()
