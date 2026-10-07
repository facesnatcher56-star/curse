class_name PilgrimCampValidation
extends Node3D
## Isolated visual and programmatic validation for the Burned Pilgrim Camp encounter on Crypt Road.
## Validates navmesh connectivity, enemy placement, and captures 4 required screenshots:
##   1. Approach silhouette from z = 114 looking North toward the burned camp
##   2. Combat space at the central road and firepit
##   3. Alternate western flank tent/crate cover route
##   4. Post-fight storytelling & wayside shrine view

var arena: Arena
var location: CryptRoad
var director: RunDirector
var cam: Camera3D
var env: WorldEnvironment

func _ready() -> void:
	print("--- PILGRIM CAMP ENCOUNTER VALIDATION START ---")
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
	# Direct road path through the camp.
	var direct_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, 114.0), Vector3(1.5, 0.0, 90.0), true
	)
	assert(not direct_path.is_empty(), "Direct road path through pilgrim camp must be traversable")
	var direct_dist: float = direct_path[direct_path.size() - 1].distance_to(Vector3(1.5, 0.0, 90.0))
	assert(direct_dist < 1.5, "Direct path must reach destination (distance: %.2f)" % direct_dist)
	print("  [PASS] Direct road lane traversable through pilgrim camp (ends %.2f m from target)" % direct_dist)

	# Western flank bypass trail through the tents.
	var flank_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, 114.0), Vector3(-12.0, 0.0, 100.0), true
	)
	assert(not flank_path.is_empty(), "Western flank bypass trail must be traversable")
	var flank_dist: float = flank_path[flank_path.size() - 1].distance_to(Vector3(-12.0, 0.0, 100.0))
	assert(flank_dist < 1.5, "Flank path must reach western bypass (distance: %.2f)" % flank_dist)
	print("  [PASS] Western flank bypass trail traversable (ends %.2f m from target)" % flank_dist)

	# Western flank re-entry to the road past the camp.
	var flank_reentry: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(-12.0, 0.0, 100.0), Vector3(1.5, 0.0, 90.0), true
	)
	assert(not flank_reentry.is_empty(), "Flank re-entry to road must be traversable")
	var reentry_dist: float = flank_reentry[flank_reentry.size() - 1].distance_to(Vector3(1.5, 0.0, 90.0))
	assert(reentry_dist < 1.5, "Flank re-entry must reach road destination (distance: %.2f)" % reentry_dist)
	print("  [PASS] Western flank trail reconnects to road (ends %.2f m from target)" % reentry_dist)

	# Wayside shrine accessibility.
	var shrine_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, 114.0), Vector3(-2.2, 0.0, 95.0), true
	)
	assert(not shrine_path.is_empty(), "Wayside shrine must be accessible")
	var shrine_dist: float = shrine_path[shrine_path.size() - 1].distance_to(Vector3(-2.2, 0.0, 95.0))
	assert(shrine_dist < 1.8, "Shrine path must reach altar (distance: %.2f)" % shrine_dist)
	print("  [PASS] Wayside shrine accessible from road (ends %.2f m from target)" % shrine_dist)

	# 2. Spawn encounters and verify placement.
	location.spawn_encounters(director)
	await get_tree().process_frame
	await get_tree().physics_frame

	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var camp_enemies: Array[Enemy] = []
	for node in enemies:
		var e := node as Enemy
		if e != null and e.global_position.z <= 106.0 and e.global_position.z >= 92.0:
			camp_enemies.append(e)

	print("  [PASS] Pilgrim camp encounter spawned: %d enemies in the z=92..106 zone" % camp_enemies.size())
	assert(camp_enemies.size() >= 10, "Expected at least 10 camp enemies across groups 2, 22, 23")

	var groups: Dictionary = {}
	for e in camp_enemies:
		groups[e.group_id] = groups.get(e.group_id, 0) + 1
		assert(not e._aggro, "Enemies must start unalerted")
		assert(e.global_position.distance_to(CryptRoad.START) >= 40.0, "Enemies must be >= 40m from start")

	print("  [PASS] Group distribution: %s, all unalerted, none near START" % str(groups))

	# 3. Capture screenshots from 4 authored perspectives.
	var dir_path: String = ProjectSettings.globalize_path("res://.agentbridge/screenshots")
	DirAccess.make_dir_absolute(dir_path)

	# View 1: Approach Silhouette (looking North from z = 114 toward burned wagon, ember firepit, and tents).
	cam.global_position = Vector3(0.5, 4.5, 113.5)
	cam.look_at(Vector3(-1.0, 1.2, 100.0), Vector3.UP)
	await _capture("pilgrim_camp_approach.png")

	# View 2: Combat Space (close look at the central road, ember firepit, and feeding pack).
	cam.global_position = Vector3(1.5, 3.6, 106.0)
	cam.look_at(Vector3(-3.5, 1.0, 100.0), Vector3.UP)
	await _capture("pilgrim_camp_combat_space.png")

	# View 3: Alternate Route (looking down the Western Flank trail past tents and crates).
	cam.global_position = Vector3(-8.5, 4.0, 107.0)
	cam.look_at(Vector3(-11.5, 1.2, 97.0), Vector3.UP)
	await _capture("pilgrim_camp_alternate_angle.png")

	# View 4: Post-fight Storytelling & Wayside Shrine (elevated view showing shrine, casualties, and road onward).
	cam.global_position = Vector3(5.5, 5.2, 99.0)
	cam.look_at(Vector3(-2.5, 1.0, 95.0), Vector3.UP)
	await _capture("pilgrim_camp_post_fight_storytelling.png")

	print("--- PILGRIM CAMP ENCOUNTER VALIDATION COMPLETED CLEANLY ---")
	get_tree().quit(0)

func _capture(filename: String) -> void:
	await get_tree().create_timer(0.3).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var out_local: String = ProjectSettings.globalize_path("res://.agentbridge/screenshots/" + filename)
	var out_temp: String = OS.get_environment("TEMP") + "/" + filename
	img.save_png(out_local)
	img.save_png(out_temp)
	print("  [RENDER] Saved: %s (and in %%TEMP%%)" % filename)
