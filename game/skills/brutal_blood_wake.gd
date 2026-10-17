class_name BrutalBloodWake
extends Node3D
## A landed ultimate drives a bloody wake through and beyond the victim.
## Pure presentation: no collision, damage, status or additional hit reports.

const GROUP := "brutal_blood_wake"
const GROUND_GROUP := "brutal_blood_ground"
static var _mist_texture: ImageTexture

static func spawn(from: Node, contact: Vector3, direction: Vector3, rank_scale: float) -> void:
	var wake := BrutalBloodWake.new()
	wake.name = "BrutalBloodWake"
	wake.add_to_group(GROUP)
	from.get_tree().current_scene.add_child(wake)
	wake.global_position = contact
	var dir := direction.normalized()
	var force := lerpf(0.62, 0.8, clampf((rank_scale - 1.0) / 0.8, 0.0, 1.0))   # kept in scale with Take Aim's restrained impact
	wake._mist(dir, force)
	wake._arterial_spray(dir, force)
	wake._ground_splatter(dir, force)
	wake.get_tree().create_timer(1.25).timeout.connect(wake.queue_free)

func _mist(dir: Vector3, force: float) -> void:
	var mist := CPUParticles3D.new()
	mist.name = "DirectionalRedMist"
	mist.amount = 44
	mist.one_shot = true
	mist.explosiveness = 0.75
	mist.lifetime = 0.95
	mist.local_coords = false
	mist.direction = (dir + Vector3.UP * 0.10).normalized()
	mist.spread = 13.0
	mist.initial_velocity_min = 1.8 * force
	mist.initial_velocity_max = 11.0 * force
	mist.damping_min = 5.0
	mist.damping_max = 7.0
	mist.gravity = Vector3(0, -1.6, 0)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.18
	mist.angle_min = -180.0
	mist.angle_max = 180.0
	mist.angular_velocity_min = -55.0
	mist.angular_velocity_max = 55.0
	mist.scale_amount_min = 0.55
	mist.scale_amount_max = 1.15
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.18))
	growth.add_point(Vector2(0.15, 0.65))
	growth.add_point(Vector2(0.65, 1.5))
	growth.add_point(Vector2(1, 2.0))
	mist.scale_amount_curve = growth
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0, 0.12, 0.55, 1])
	ramp.colors = PackedColorArray([Color(0.34, 0.008, 0.022, 0.78), Color(0.26, 0.004, 0.014, 0.65), Color(0.17, 0.003, 0.009, 0.40), Color(0.09, 0.001, 0.004, 0)])
	mist.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.65)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = mist_texture()
	quad.material = material
	mist.mesh = quad
	add_child(mist)

func _arterial_spray(dir: Vector3, force: float) -> void:
	var spray := CPUParticles3D.new()
	spray.name = "ArterialSpray"
	spray.amount = 28
	spray.one_shot = true
	spray.explosiveness = 0.96
	spray.lifetime = 0.70
	spray.local_coords = false
	spray.direction = (dir + Vector3.UP * 0.17).normalized()
	spray.spread = 9.0
	spray.initial_velocity_min = 9.0 * force
	spray.initial_velocity_max = 15.0 * force
	spray.gravity = Vector3(0, -6.0, 0)
	spray.damping_min = 2.0
	spray.damping_max = 4.0
	spray.scale_amount_min = 0.5
	spray.scale_amount_max = 1.3
	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.16
	drop.radial_segments = 5
	drop.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = material
	spray.mesh = drop
	var ramp := Gradient.new()
	ramp.set_color(0, Color("710b18"))
	ramp.add_point(0.4, Color("480711"))
	ramp.set_color(1, Color(0.16, 0.009, 0.018, 0))
	spray.color_ramp = ramp
	add_child(spray)

func _ground_splatter(dir: Vector3, force: float) -> void:
	var scene := get_tree().current_scene
	var existing := get_tree().get_nodes_in_group(GROUND_GROUP)
	if existing.size() >= 8: existing[0].queue_free()
	var ground := Node3D.new()
	ground.name = "BrutalGroundDroplets"
	ground.add_to_group(GROUND_GROUP)
	scene.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var space := get_world_3d().direct_space_state
	for i in 22:
		# The same narrow cone as the airborne arterial spray, extending behind the victim.
		var distance := rng.randf_range(0.4, 5.5) * force
		var along := dir.rotated(Vector3.UP, rng.randf_range(-0.16, 0.16))
		var candidate := global_position + along * distance
		var query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 2.0, candidate - Vector3.UP * 5.0, Actor.LAYER_WORLD)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7: continue
		# Project onto the visible stone, whose raised tile tops differ from its collider.
		var drop := Decal.new()
		drop.name = "GroundBloodDrop"
		var width := rng.randf_range(0.12, 0.30) * (1.0 - 0.25 * distance / (5.5 * force))
		drop.size = Vector3(width, 1.0, width * rng.randf_range(1.3, 2.5))
		drop.modulate = Color(0.24, 0.005, 0.014, 0.95)
		drop.texture_albedo = mist_texture()
		drop.normal_fade = 0.7
		ground.add_child(drop)
		var normal: Vector3 = hit["normal"]
		var z := along.slide(normal).normalized()
		drop.global_transform = Transform3D(Basis(normal.cross(z).normalized(), normal, z), hit["position"] + normal * 0.25)
		drop.visible = false
		var tween := drop.create_tween()
		tween.tween_interval(0.25 + distance * 0.065)
		tween.tween_callback(drop.show)
		tween.tween_interval(6.0)
		tween.tween_property(drop, "modulate:a", 0.0, 1.5)
	ground.get_tree().create_timer(8.5).timeout.connect(ground.queue_free)

static func mist_texture() -> ImageTexture:
	# The dummy renderer cannot initialize an ImageTexture; logic tests need no pixels.
	if DisplayServer.get_name() == "headless": return null
	if _mist_texture == null:
		var noise := FastNoiseLite.new()
		noise.seed = 6722
		noise.frequency = 0.13
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var radius := (Vector2(x, y) / 63.0 - Vector2(0.5, 0.5)).length() * 2.0
				var grain := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var alpha := pow(maxf(1.0 - radius, 0.0), 1.2) * smoothstep(0.15, 0.65, grain) * 1.6
				image.set_pixel(x, y, Color(1, 1, 1, alpha))
		_mist_texture = ImageTexture.create_from_image(image)
	return _mist_texture
