class_name BrutalBloodWake
extends Node3D
## A landed ultimate drives a bloody wake through and beyond the victim.
## Pure presentation: no collision, damage, status or additional hit reports.

const GROUP := "brutal_blood_wake"
static var _mist_texture: ImageTexture

static func spawn(from: Node, contact: Vector3, direction: Vector3, rank_scale: float) -> void:
	var wake := BrutalBloodWake.new()
	wake.name = "BrutalBloodWake"
	wake.add_to_group(GROUP)
	from.get_tree().current_scene.add_child(wake)
	wake.global_position = contact
	var dir := direction.normalized()
	var force := lerpf(1.0, 1.3, clampf((rank_scale - 1.0) / 0.8, 0.0, 1.0))
	wake._mist(dir, force)
	wake._arterial_spray(dir, force)
	wake.get_tree().create_timer(1.25).timeout.connect(wake.queue_free)

func _mist(dir: Vector3, force: float) -> void:
	var mist := CPUParticles3D.new()
	mist.name = "DirectionalRedMist"
	mist.amount = 84
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
	ramp.colors = PackedColorArray([Color(0.88, 0.025, 0.09, 0.85), Color(0.66, 0.012, 0.055, 0.72), Color(0.43, 0.008, 0.035, 0.45), Color(0.26, 0.003, 0.018, 0)])
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
	spray.amount = 48
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
	ramp.set_color(0, Color("e52136"))
	ramp.add_point(0.4, Color("a10c22"))
	ramp.set_color(1, Color(0.30, 0.03, 0.08, 0))
	spray.color_ramp = ramp
	add_child(spray)

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
