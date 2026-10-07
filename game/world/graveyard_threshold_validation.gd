class_name GraveyardThresholdValidation
extends Node3D
## Isolated visual and programmatic validation for the Broken Funeral Procession / Graveyard Threshold beat.
## Validates navmesh connectivity, enemy placement, full road continuity, and captures 4 required screenshots:
##   1. Approach silhouette from z = 93 looking North toward the broken hearse and threshold markers
##   2. Combat space at the central road, tipped hearse, and disturbed graves
##   3. Alternate western cemetery detour trail and tactical cover route
##   4. Post-fight graveyard foreshadowing view looking past the threshold into the ancient cemetery

var arena: Arena
var location: CryptRoad
var director: RunDirector
var cam: Camera3D
var env: WorldEnvironment

func _ready() -> void:
	print("--- GRAVEYARD THRESHOLD ENCOUNTER VALIDATION START ---")
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

	# 1. Full Road Continuity Check:
	# Start (z=150) -> Waystation (z=127) -> Pilgrim Camp (z=100) -> Threshold (z=81) -> Graveyard (z=60) -> Crypt Entrance (z=-155)
	var full_road_waypoints: Array[Vector3] = [
		Vector3(1.0, 0.0, 150.0),    # START
		Vector3(2.0, 0.0, 127.0),    # Hearthward Waystation
		Vector3(0.0, 0.0, 100.0),    # Burned Pilgrim Camp
		Vector3(0.5, 0.0, 81.0),     # Graveyard Threshold Beat
		Vector3(-1.0, 0.0, 60.0),    # Ancient Graveyard Road Passage
		Vector3(0.0, 0.0, 0.0),      # Old Roadside Shrine
		Vector3(0.0, 0.0, -155.0)    # Crypt Gate Approach
	]

	for i in full_road_waypoints.size() - 1:
		var p0: Vector3 = full_road_waypoints[i]
		var p1: Vector3 = full_road_waypoints[i + 1]
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, p0, p1, true)
		assert(not path.is_empty(), "Full road segment %d -> %d must be traversable" % [i, i + 1])
		var dist: float = path[path.size() - 1].distance_to(p1)
		assert(dist < 2.0, "Path segment %d -> %d must reach destination (distance: %.2f)" % [i, i + 1, dist])

	print("  [PASS] Full road continuity verified: START (z=150) -> Waystation -> Pilgrim Camp -> Graveyard Threshold -> Crypt Gate (z=-155)")

	# 2. Local Beat Traversal Checks:
	# Direct road path through the graveyard threshold.
	var direct_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(1.5, 0.0, 92.0), Vector3(-0.5, 0.0, 71.0), true
	)
	assert(not direct_path.is_empty(), "Direct road path through graveyard threshold must be traversable")
	var direct_dist: float = direct_path[direct_path.size() - 1].distance_to(Vector3(-0.5, 0.0, 71.0))
	assert(direct_dist < 1.5, "Direct path must reach destination (distance: %.2f)" % direct_dist)
	print("  [PASS] Direct road lane traversable through threshold (ends %.2f m from target)" % direct_dist)

	# Western cemetery detour trail through toppled markers and gatepost.
	var detour_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(1.5, 0.0, 92.0), Vector3(-7.5, 0.0, 82.0), true
	)
	assert(not detour_path.is_empty(), "Western cemetery detour trail must be traversable")
	var detour_dist: float = detour_path[detour_path.size() - 1].distance_to(Vector3(-7.5, 0.0, 82.0))
	assert(detour_dist < 1.5, "Detour path must reach western cover trail (distance: %.2f)" % detour_dist)
	print("  [PASS] Western cemetery detour trail traversable (ends %.2f m from target)" % detour_dist)

	# Western detour re-entry to the road past the mourning shrine.
	var detour_reentry: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(-7.5, 0.0, 82.0), Vector3(-0.5, 0.0, 71.0), true
	)
	assert(not detour_reentry.is_empty(), "Western detour trail must reconnect to road")
	var reentry_dist: float = detour_reentry[detour_reentry.size() - 1].distance_to(Vector3(-0.5, 0.0, 71.0))
	assert(reentry_dist < 1.5, "Detour re-entry must reach road (distance: %.2f)" % reentry_dist)
	print("  [PASS] Western detour trail reconnects to road (ends %.2f m from target)" % reentry_dist)

	# Mourning shrine accessibility.
	var shrine_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, 81.0), Vector3(-2.4, 0.0, 76.0), true
	)
	assert(not shrine_path.is_empty(), "Mourning shrine must be accessible")
	var shrine_dist: float = shrine_path[shrine_path.size() - 1].distance_to(Vector3(-2.4, 0.0, 76.0))
	assert(shrine_dist < 1.8, "Shrine path must reach altar (distance: %.2f)" % shrine_dist)
	print("  [PASS] Mourning shrine accessible from road (ends %.2f m from target)" % shrine_dist)

	# Broken hearse casket investigation accessibility.
	var hearse_dest := Vector3(4.5, 0.0, 82.2)
	var hearse_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, 81.0), hearse_dest, true
	)
	assert(not hearse_path.is_empty(), "Broken hearse casket must be accessible")
	var hearse_dist: float = hearse_path[hearse_path.size() - 1].distance_to(hearse_dest)
	assert(hearse_dist < 1.8, "Hearse path must reach casket (distance: %.2f)" % hearse_dist)
	print("  [PASS] Broken hearse casket accessible from road (ends %.2f m from target)" % hearse_dist)

	# 3. Spawn encounters and verify placement.
	location.spawn_encounters(director)
	await get_tree().process_frame
	await get_tree().physics_frame

	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var threshold_enemies: Array[Enemy] = []
	for node in enemies:
		var e := node as Enemy
		if e != null and e.global_position.z <= 88.0 and e.global_position.z >= 73.0:
			threshold_enemies.append(e)

	print("  [PASS] Graveyard threshold encounter spawned: %d enemies in the z=73..88 zone" % threshold_enemies.size())
	assert(threshold_enemies.size() >= 10, "Expected at least 10 threshold enemies across groups 24, 25, 26")

	var groups: Dictionary = {}
	for e in threshold_enemies:
		groups[e.group_id] = groups.get(e.group_id, 0) + 1
		assert(not e._aggro, "Enemies must start unalerted")
		assert(e.global_position.distance_to(CryptRoad.START) >= 60.0, "Enemies must be >= 60m from start")

	print("  [PASS] Group distribution: %s, all unalerted, safe initial distance" % str(groups))

	# 4. Capture screenshots from 4 authored perspectives.
	var dir_path: String = ProjectSettings.globalize_path("res://.agentbridge/screenshots")
	DirAccess.make_dir_absolute(dir_path)

	# View 1: Approach Silhouette (looking North from z = 92 toward broken hearse, brazier glow, toppled grave markers).
	cam.global_position = Vector3(1.2, 4.2, 92.0)
	cam.look_at(Vector3(0.0, 1.2, 81.0), Vector3.UP)
	await _capture("graveyard_threshold_approach.png")

	# View 2: Combat Space (close look at the central road, broken funeral hearse, casket, and fallen pallbearers).
	cam.global_position = Vector3(0.0, 3.5, 87.0)
	cam.look_at(Vector3(3.2, 1.0, 82.5), Vector3.UP)
	await _capture("graveyard_threshold_combat_space.png")

	# View 3: Alternate Route (looking down the Western Cemetery Detour trail past toppled headstones and gatepost).
	cam.global_position = Vector3(-4.0, 3.8, 87.5)
	cam.look_at(Vector3(-7.5, 1.2, 79.0), Vector3.UP)
	await _capture("graveyard_threshold_alternate_angle.png")

	# View 4: Post-fight Graveyard Foreshadowing (elevated view looking past the mourning shrine and threshold gates into the ancient cemetery).
	cam.global_position = Vector3(3.5, 5.0, 81.0)
	cam.look_at(Vector3(-6.0, 1.0, 68.0), Vector3.UP)
	await _capture("graveyard_threshold_foreshadowing.png")

	print("--- GRAVEYARD THRESHOLD ENCOUNTER VALIDATION COMPLETED CLEANLY ---")
	get_tree().quit(0)

func _capture(filename: String) -> void:
	await get_tree().create_timer(0.3).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var out_local: String = ProjectSettings.globalize_path("res://.agentbridge/screenshots/" + filename)
	var out_temp: String = OS.get_environment("TEMP") + "/" + filename
	img.save_png(out_local)
	img.save_png(out_temp)
	print("  [RENDER] Saved: %s (and in %%TEMP%%)" % filename)
