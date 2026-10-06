class_name SceneLook
extends RefCounted
## What the night gives the world to reflect. Steel is metal, and metal only shows what is around it: with nothing to reflect (a flat dark
## background) every blade, helm and plate rendered as the same dull grey-black and the sword could not be told from the ground. A dim
## sky (cold overhead, a muted warm band at the horizon, dark earth below) is used for reflections only: the background stays the
## colour it was, so the mood is the same, but edges and flats of steel now catch a cold light and a warm one, and read.

static func give_reflections(environment: Environment) -> void:
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color(0.17, 0.2, 0.32)
	material.sky_horizon_color = Color(0.62, 0.55, 0.48)
	material.ground_horizon_color = Color(0.34, 0.29, 0.24)
	material.ground_bottom_color = Color(0.09, 0.08, 0.07)
	material.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
