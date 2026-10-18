class_name CryptLook
extends RefCounted
## The Crypt's mood (`-- --crypt01`): a dark environment so the light comes from the torches, braziers and candles, in pools with real falloff,
## and stone that is darkened and grimed by a shader instead of repainted. Environment and light settings plus material swaps only: no
## gameplay, navigation or collision. Called by CryptDungeon (materials when it builds, environment and lights from tune_look).

const STONE_SHADER := "res://game/world/crypt_stone.gdshader"
## Groups of the scene whose meshes get the stone material (set pieces too: their pedestals, pillars and arches are the same stone).
const STONE_GROUPS := ["Pillars", "Liners", "SetPieces"]

## Per light role (the baker marks each light with `crypt_role`): energy, range, attenuation, whether it casts shadows (only up close).
const ROLES := {
	"torch": {"energy": 4.6, "range": 9.5, "attenuation": 1.5, "shadow": false},
	"brazier": {"energy": 6.5, "range": 13.0, "attenuation": 1.4, "shadow": true},
	"candle": {"energy": 1.6, "range": 5.0, "attenuation": 1.6, "shadow": false},
}
const SHADOW_FADE := 20.0
const HERO_TORCH_RANGE := 12.0
const HERO_TORCH_ENERGY := 2.4


static func tune_environment(environment: Environment, sun: DirectionalLight3D) -> void:
	environment.ambient_light_color = Color(0.5, 0.44, 0.5)   # a dim warm grey-violet, nudged toward the torch colour: a crypt, not a night outdoors
	environment.ambient_light_energy = 0.42
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0)
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.1, 0.08, 0.07)   # a dusty haze that eats the far end of a room
	environment.fog_density = 0.014
	environment.fog_aerial_perspective = 0.2
	environment.tonemap_exposure = 1.05
	if sun != null:
		sun.light_energy = 0.25
		sun.light_color = Color(0.72, 0.72, 0.95)
		sun.shadow_enabled = false


## The hero's own torch in the Crypt reaches a little further and brighter, so enemies in the darkest rooms stand out against the floor.
static func tune_hero_torch(torch: OmniLight3D) -> void:
	torch.omni_range = HERO_TORCH_RANGE
	torch.light_energy = HERO_TORCH_ENERGY


static func style_lights(root: Node) -> void:
	for node in root.find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		if not light.has_meta("crypt_role"):
			continue
		var role: Dictionary = ROLES[String(light.get_meta("crypt_role"))]
		light.light_color = Color(1.0, 0.55, 0.24)
		light.light_energy = float(role["energy"])
		light.omni_range = float(role["range"])
		light.omni_attenuation = float(role["attenuation"])
		light.shadow_enabled = bool(role["shadow"])
		if light.shadow_enabled:
			light.distance_fade_shadow = SHADOW_FADE
		for child in light.get_children():
			if child is FlickerLight:
				(child as FlickerLight)._base = light.light_energy


## Swaps the kit's stone materials for the grimed shader. The GridMap library is copied first: it is shared with other scenes.
static func apply_materials(level: Node3D) -> void:
	var shader: Shader = load(STONE_SHADER)
	var cache: Dictionary = {}
	for node in level.find_children("*", "GridMap", true, false):
		var grid := node as GridMap
		if grid.mesh_library == null:
			continue
		grid.mesh_library = grid.mesh_library.duplicate(true)
		for item in grid.mesh_library.get_item_list():
			var mesh: Mesh = grid.mesh_library.get_item_mesh(item)
			if mesh == null:
				continue
			for surface in mesh.get_surface_count():
				var swapped: Material = _stone(mesh.surface_get_material(surface), shader, cache)
				if swapped != null and mesh is ArrayMesh:
					(mesh as ArrayMesh).surface_set_material(surface, swapped)
	for group_name in STONE_GROUPS:
		if not level.has_node(group_name):
			continue
		for node in level.get_node(group_name).find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			for surface in mi.mesh.get_surface_count():
				var swapped: Material = _stone(mi.get_active_material(surface), shader, cache)
				if swapped != null:
					mi.set_surface_override_material(surface, swapped)


static func _stone(source: Material, shader: Shader, cache: Dictionary) -> Material:
	var std := source as StandardMaterial3D
	if std == null or std.albedo_texture == null or std.emission_enabled or std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	var key: int = std.get_instance_id()
	if not cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_tex", std.albedo_texture)
		mat.set_shader_parameter("base_color", std.albedo_color)
		cache[key] = mat
	return cache[key]
