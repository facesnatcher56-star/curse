class_name AtmosphereProfile
extends RefCounted
## Opt-in lighting and atmosphere for the Crypt Road (`-- --atmosphere`, issue #21). Without the flag nothing here runs and the
## default look is unchanged. The values are starting points, tuned by eye from the gameplay camera. Only environment and light
## settings are touched: no gameplay, AI, navigation, collision or UI. Combines with `-- --modular`.
##
## What it does: restrained cool fog with aerial perspective, ambient down to about 0.25 so form comes
## from the sun and the local lights, a stronger sun with shadows, moderate SSAO, warm falloff on the braziers, shrines and fire
## pits, the hero torch as the one shadow-casting local light, and an AgX tonemap with slight desaturation and glow on emissives.

## At most this many local lights cast shadows. Only the hero torch does (see style_hero_torch); everything else is shadowless.
const SHADOW_CASTING_LOCAL_LIGHTS := 1

## The road's full-strength values (the town blends from its own outside values to these by depth, see TownScene._update_world).
const AMBIENT_TARGET := 0.25
const FOG_TARGET := 0.012

## Atmosphere lighting is the default; opt out with `--classic`. `--atmosphere` is accepted as a harmless no-op.
static func enabled() -> bool:
	return not ("--classic" in OS.get_cmdline_user_args())

## Sets the world environment and the sun. Called after the Crypt Road's own multipliers, so these values are the final look.
static func apply_environment(environment: Environment, sun: DirectionalLight3D) -> void:
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.38, 0.42)   # cool and desaturated, without a green cast
	environment.ambient_light_energy = AMBIENT_TARGET
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.9
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_hdr_threshold = 1.2   # only emissives above this glow (fire, magic), not the lit stone
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.07, 0.08, 0.09)
	environment.fog_density = FOG_TARGET
	environment.fog_aerial_perspective = 0.3
	environment.fog_sky_affect = 0.5
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.2
	environment.ssao_power = 1.5
	if sun != null:
		sun.light_energy = 1.4
		sun.shadow_enabled = true

## Warms the Crypt Road's local lights (braziers, shrine, fire pits) and gives them falloff. Green lights (the nests) keep their
## colour, and no local light casts a shadow here.
static func apply_local_lights(root: Node) -> void:
	for node in root.find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		light.shadow_enabled = false
		light.omni_attenuation = 1.4   # faster falloff: pools of light against the cool ambient
		if light.light_color.r > light.light_color.g:   # warm lights only
			light.light_color = light.light_color.lerp(Color(1.0, 0.6, 0.3), 0.3)
			light.light_energy *= 1.8
			light.omni_range *= 1.3

## The hero torch: a warmer, stronger light, and the one shadow-casting local light (SHADOW_CASTING_LOCAL_LIGHTS).
static func style_hero_torch(torch: OmniLight3D) -> void:
	torch.light_color = Color(1.0, 0.66, 0.36)
	torch.light_energy = 1.8
	torch.omni_attenuation = 1.4
	torch.shadow_enabled = SHADOW_CASTING_LOCAL_LIGHTS > 0

## A hero torch for a scene that has none (the town): the same light as main.gd's torch, styled for the atmosphere.
static func make_hero_torch() -> OmniLight3D:
	var torch := OmniLight3D.new()
	torch.omni_range = 9.0
	torch.position = Vector3(0, 3.0, 0)
	style_hero_torch(torch)
	return torch
