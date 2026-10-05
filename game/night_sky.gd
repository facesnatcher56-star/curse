class_name NightSky
extends RefCounted
## The night sky behind every scene (stars, a moon, drifting cloud streaks; see night_sky.gdshader). Call `apply` on a scene's
## Environment. It is painted on every direction, so it shows wherever the ground ends, even though the 3/4 camera looks down.

## `blood_moon`: a deep red moon with a red glow and red-lit clouds.
static func apply(environment: Environment, moon_direction: Vector3 = Vector3(-0.5, -0.6, -0.62), blood_moon: bool = false) -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://game/night_sky.gdshader")
	material.set_shader_parameter("moon_direction", moon_direction.normalized())
	if blood_moon:
		# A total eclipse, not a red planet: a dim copper disc with a darker side and a bright sliver on its edge, a faint maroon glow
		# (not an orange wash), and the stars still showing round it.
		material.set_shader_parameter("moon_tint", Vector3(0.5, 0.09, 0.05))
		material.set_shader_parameter("halo_color", Vector3(0.2, 0.035, 0.03))
		material.set_shader_parameter("halo_wide_color", Vector3(0.1, 0.025, 0.03))
		material.set_shader_parameter("cloud_light", Vector3(0.17, 0.04, 0.04))
		material.set_shader_parameter("moon_radius", 0.056)
		material.set_shader_parameter("eclipse", 1.0)
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_32   # only used for reflections here (ambient light stays the scene's own colour): keep it cheap
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.fog_sky_affect = 0.0           # the fog is the ground's haze; it must not wash the sky out
