class_name WaystationValidation
extends Node3D
## Isolated visual and programmatic validation for the Hearthward Waystation encounter on Crypt Road.
## Validates navmesh connectivity, enemy placement, and captures 4 required screenshots:
##   1. Approach silhouette from Last Hearth road
##   2. Combat space at the breached road barricade
##   3. Alternate western flank ditch bypass route
##   4. Post-fight readability & tollhouse interior storytelling

var arena: Arena
var location: CryptRoad
var director: RunDirector
var cam: Camera3D
var env: WorldEnvironment

func _ready() -> void:
	print("--- WAYSTATION ENCOUNTER VALIDATION START ---")
	_setup_world()
	await _run_validation()

func _setup_world() -> void:
	# Environment and dark, grim lighting matching Crypt Road tone.
	env = WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.05, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.5, 0.62)
	environment.ambient_light_energy = 0.8 * CryptRoad.AMBIENT_MULT
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.08, 0.09, 0.12)
	environment.fog_density = 0.01 * CryptRoad.FOG_MULT
	NightSky.apply(environment)
	SceneLook.give_reflections(environment)
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_color = Color(0.8, 0.85, 1.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	add_child(sun)

	arena = CryptRoad.make_arena()
	add_child(arena)
	arena.build(false)

	location = CryptRoad.new()
	add_child(location)
	location.build(arena)

	director = RunDirector.new()
	director.world_mode = true
	add_child(director)

	cam = Camera3D.new()
	cam.current = true
	cam.fov = 48.0
	cam.near = 0.2
	cam.far = 120.0
	add_child(cam)

func _run_validation() -> void:
	await location.wait_for_navigation()
	assert(location.navigation_ready(), "Navigation mesh must be ready")
	print("  [PASS] Navigation mesh built and synced")

	var map: RID = get_world_3d().navigation_map

	# 1. Navmesh traversal checks: verify no permanent blockage.
	# Direct road path through the breach.
	var direct_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(1.0, 0.0, 145.0), Vector3(0.0, 0.0, 115.0), true
	)
	assert(not direct_path.is_empty(), "Direct road path through waystation must be traversable")
	var direct_dist: float = direct_path[direct_path.size() - 1].distance_to(Vector3(0.0, 0.0, 115.0))
	assert(direct_dist < 1.5, "Direct path must reach destination (distance: %.2f)" % direct_dist)
	print("  [PASS] Direct road lane traversable through barricade breach (ends %.2f m from target)" % direct_dist)

	# Western flank ditch path.
	var flank_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(1.0, 0.0, 145.0), Vector3(-10.0, 0.0, 127.0), true
	)
	assert(not flank_path.is_empty(), "Western flank ditch path must be traversable")
	var flank_dist: float = flank_path[flank_path.size() - 1].distance_to(Vector3(-10.0, 0.0, 127.0))
	assert(flank_dist < 1.5, "Flank path must reach ditch (distance: %.2f)" % flank_dist)
	print("  [PASS] Western flank ditch traversable (ends %.2f m from target)" % flank_dist)

	# Tollhouse interior access.
	var tollhouse_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(1.0, 0.0, 145.0), Vector3(10.5, 0.0, 127.0), true
	)
	assert(not tollhouse_path.is_empty(), "Tollhouse interior must be accessible")
	var tollhouse_dist: float = tollhouse_path[tollhouse_path.size() - 1].distance_to(Vector3(10.5, 0.0, 127.0))
	assert(tollhouse_dist < 1.8, "Tollhouse path must reach interior (distance: %.2f)" % tollhouse_dist)
	print("  [PASS] Tollhouse interior accessible through doorway (ends %.2f m from target)" % tollhouse_dist)

	# 2. Spawn encounters and verify placement.
	location.spawn_encounters(director)
	await get_tree().process_frame
	await get_tree().physics_frame

	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var waystation_enemies: Array[Enemy] = []
	for node in enemies:
		var e := node as Enemy
		if e != null and e.global_position.z <= 134.0 and e.global_position.z >= 118.0:
			waystation_enemies.append(e)

	print("  [PASS] Waystation encounter spawned: %d enemies in the z=118..134 zone" % waystation_enemies.size())
	assert(waystation_enemies.size() >= 8, "Expected at least 8 waystation enemies across groups 1, 20, 21")

	var groups: Dictionary = {}
	for e in waystation_enemies:
		groups[e.group_id] = groups.get(e.group_id, 0) + 1
		assert(not e._aggro, "Enemies must start unalerted")
		assert(e.global_position.distance_to(CryptRoad.START) >= 12.0, "Enemies must be >= 12m from start")

	print("  [PASS] Group distribution: %s, all unalerted, none near START" % str(groups))

	# 3. Capture screenshots from 4 authored perspectives.
	var dir_path: String = ProjectSettings.globalize_path("res://.agentbridge/screenshots")
	DirAccess.make_dir_absolute(dir_path)

	# View 1: Approach Silhouette (looking North from z = 148 toward tollhouse and barricade).
	cam.global_position = Vector3(1.5, 4.8, 147.0)
	cam.look_at(Vector3(3.0, 1.5, 128.0), Vector3.UP)
	await _capture("waystation_approach.png")

	# View 2: Combat Space (close look at the breached barricade and defenders).
	cam.global_position = Vector3(-1.0, 3.5, 134.5)
	cam.look_at(Vector3(3.5, 1.2, 126.5), Vector3.UP)
	await _capture("waystation_combat_space.png")

	# View 3: Alternate Route (looking down the Western Flank ditch trail).
	cam.global_position = Vector3(-6.5, 3.8, 137.0)
	cam.look_at(Vector3(-10.5, 1.2, 125.0), Vector3.UP)
	await _capture("waystation_alternate_route.png")

	# View 4: Post-fight Readability (elevated view into tollhouse interior & through the breach).
	cam.global_position = Vector3(14.5, 5.5, 136.0)
	cam.look_at(Vector3(5.0, 1.0, 126.5), Vector3.UP)
	await _capture("waystation_post_fight_readability.png")

	print("--- WAYSTATION ENCOUNTER VALIDATION COMPLETED CLEANLY ---")
	get_tree().quit(0)

func _capture(filename: String) -> void:
	await get_tree().create_timer(0.3).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var out_local: String = ProjectSettings.globalize_path("res://.agentbridge/screenshots/" + filename)
	var out_temp: String = OS.get_environment("TEMP") + "/" + filename
	img.save_png(out_local)
	img.save_png(out_temp)
	print("  [RENDER] Saved: %s (and in %%TEMP%%)" % filename)
