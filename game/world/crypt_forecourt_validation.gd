class_name CryptForecourtValidation
extends Node3D
## Isolated visual and programmatic validation for the Ruined Mortuary / Ossuary Forecourt beat.
## Validates navmesh connectivity, enemy placement, full road continuity from Last Hearth to the crypt gate,
## and captures 4 required screenshots:
##   1. Approach silhouette from z = -144 looking North toward the monumental pillars and crypt portal
##   2. Combat space at the forecourt plaza, broken bier, and portal vanguard line
##   3. Alternate western mortuary shelter angle with embalming slab and flank cover
##   4. Post-fight crypt destination view looking up the steps into the sealed crypt gate facade

var arena: Arena
var location: CryptRoad
var director: RunDirector
var cam: Camera3D
var env: WorldEnvironment

func _ready() -> void:
	print("--- CRYPT FORECOURT ENCOUNTER VALIDATION START ---")
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
	# Start (z=150) -> Waystation (z=127) -> Pilgrim Camp (z=100) -> Threshold (z=81) -> Graveyard (z=60)
	# -> Shrine (z=0) -> Courtyard (z=-100) -> Forecourt Approach (z=-146) -> Crypt Gate Steps (z=-162)
	var full_road_waypoints: Array[Vector3] = [
		Vector3(1.0, 0.0, 150.0),    # START (Last Hearth Gate)
		Vector3(2.0, 0.0, 127.0),    # Hearthward Waystation
		Vector3(0.0, 0.0, 100.0),    # Burned Pilgrim Camp
		Vector3(0.5, 0.0, 81.0),     # Graveyard Threshold Beat
		Vector3(-1.0, 0.0, 60.0),    # Ancient Graveyard Road Passage
		Vector3(0.0, 0.0, 0.0),      # Old Roadside Shrine
		Vector3(0.0, 0.0, -100.0),   # Crypt Courtyard Avenue
		Vector3(0.0, 0.0, -146.0),   # Forecourt Approach
		Vector3(0.0, 0.0, -162.0)    # Crypt Gate Steps
	]

	for i in full_road_waypoints.size() - 1:
		var p0: Vector3 = full_road_waypoints[i]
		var p1: Vector3 = full_road_waypoints[i + 1]
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, p0, p1, true)
		assert(not path.is_empty(), "Full road segment %d -> %d must be traversable" % [i, i + 1])
		var dist: float = path[path.size() - 1].distance_to(p1)
		assert(dist < 2.0, "Path segment %d -> %d must reach destination (distance: %.2f)" % [i, i + 1, dist])

	print("  [PASS] Full road continuity verified: START (z=150) -> Waystation -> Pilgrim Camp -> Graveyard Threshold -> Shrine -> Courtyard -> Forecourt -> Crypt Gate (z=-162)")

	# 2. Local Beat Traversal Checks:
	# Direct central road lane through forecourt to crypt gate steps.
	var direct_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, -145.0), Vector3(0.0, 0.0, -162.0), true
	)
	assert(not direct_path.is_empty(), "Direct approach lane to crypt gate must be traversable")
	var direct_dist: float = direct_path[direct_path.size() - 1].distance_to(Vector3(0.0, 0.0, -162.0))
	assert(direct_dist < 1.5, "Direct path must reach crypt steps (distance: %.2f)" % direct_dist)
	print("  [PASS] Direct approach lane traversable to crypt steps (ends %.2f m from target)" % direct_dist)

	# Western mortuary shelter flank path.
	var west_flank_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, -145.0), Vector3(-9.0, 0.0, -154.0), true
	)
	assert(not west_flank_path.is_empty(), "Western mortuary shelter flank path must be traversable")
	var west_dist: float = west_flank_path[west_flank_path.size() - 1].distance_to(Vector3(-9.0, 0.0, -154.0))
	assert(west_dist < 1.5, "West flank path must reach mortuary shelter (distance: %.2f)" % west_dist)
	print("  [PASS] Western mortuary shelter flank path traversable (ends %.2f m from target)" % west_dist)

	# West flank reconnection to the crypt steps.
	var west_reentry: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(-9.0, 0.0, -154.0), Vector3(0.0, 0.0, -162.0), true
	)
	assert(not west_reentry.is_empty(), "West flank must reconnect to crypt steps")
	var west_reentry_dist: float = west_reentry[west_reentry.size() - 1].distance_to(Vector3(0.0, 0.0, -162.0))
	assert(west_reentry_dist < 1.5, "West flank re-entry must reach crypt steps (distance: %.2f)" % west_reentry_dist)
	print("  [PASS] Western mortuary shelter flank reconnects to crypt steps (ends %.2f m from target)" % west_reentry_dist)

	# Eastern ossuary colonnade flank path.
	var east_flank_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, -145.0), Vector3(8.0, 0.0, -154.0), true
	)
	assert(not east_flank_path.is_empty(), "Eastern ossuary colonnade flank path must be traversable")
	var east_dist: float = east_flank_path[east_flank_path.size() - 1].distance_to(Vector3(8.0, 0.0, -154.0))
	assert(east_dist < 1.5, "East flank path must reach ossuary colonnade (distance: %.2f)" % east_dist)
	print("  [PASS] Eastern ossuary colonnade flank path traversable (ends %.2f m from target)" % east_dist)

	# East flank reconnection to the crypt steps.
	var east_reentry: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(8.0, 0.0, -154.0), Vector3(0.0, 0.0, -162.0), true
	)
	assert(not east_reentry.is_empty(), "East flank must reconnect to crypt steps")
	var east_reentry_dist: float = east_reentry[east_reentry.size() - 1].distance_to(Vector3(0.0, 0.0, -162.0))
	assert(east_reentry_dist < 1.5, "East flank re-entry must reach crypt steps (distance: %.2f)" % east_reentry_dist)
	print("  [PASS] Eastern ossuary colonnade reconnects to crypt steps (ends %.2f m from target)" % east_reentry_dist)

	# Mortuary bier investigation accessibility.
	var bier_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, -154.0), Vector3(-10.2, 0.0, -154.0), true
	)
	assert(not bier_path.is_empty(), "Mortuary embalming bier must be accessible")
	var bier_dist: float = bier_path[bier_path.size() - 1].distance_to(Vector3(-10.2, 0.0, -154.0))
	assert(bier_dist < 1.8, "Path must reach mortuary bier (distance: %.2f)" % bier_dist)
	print("  [PASS] Mortuary embalming bier accessible (ends %.2f m from target)" % bier_dist)

	# Ossuary niches investigation accessibility.
	var ossuary_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(0.0, 0.0, -154.0), Vector3(10.5, 0.0, -153.5), true
	)
	assert(not ossuary_path.is_empty(), "Ossuary bone niches must be accessible")
	var ossuary_dist: float = ossuary_path[ossuary_path.size() - 1].distance_to(Vector3(10.5, 0.0, -153.5))
	assert(ossuary_dist < 1.8, "Path must reach ossuary niches (distance: %.2f)" % ossuary_dist)
	print("  [PASS] Ossuary bone niches accessible (ends %.2f m from target)" % ossuary_dist)

	# 3. Spawn encounters and verify placement.
	location.spawn_encounters(director)
	await get_tree().process_frame
	await get_tree().physics_frame

	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var forecourt_enemies: Array[Enemy] = []
	for node in enemies:
		var e := node as Enemy
		if e != null and e.global_position.z <= -146.0 and e.global_position.z >= -165.0:
			forecourt_enemies.append(e)

	print("  [PASS] Forecourt encounter spawned: %d enemies in the z = -146..-165 zone" % forecourt_enemies.size())
	assert(forecourt_enemies.size() >= 12, "Expected at least 12 forecourt enemies across groups 27, 28, 29")

	var groups: Dictionary = {}
	for e in forecourt_enemies:
		groups[e.group_id] = groups.get(e.group_id, 0) + 1
		assert(not e._aggro, "Enemies must start unalerted")
		assert(e.global_position.distance_to(CryptRoad.START) >= 280.0, "Enemies must be >= 280m from start")

	print("  [PASS] Group distribution: %s, all unalerted, safe initial distance" % str(groups))

	# 4. Capture screenshots from 4 authored perspectives.
	var dir_path: String = ProjectSettings.globalize_path("res://.agentbridge/screenshots")
	DirAccess.make_dir_absolute(dir_path)

	# View 1: Approach Silhouette (looking North from z = -143 toward monumental pillars, forecourt plaza, and crypt portal).
	cam.global_position = Vector3(0.0, 4.2, -143.0)
	cam.look_at(Vector3(0.0, 2.0, -162.0), Vector3.UP)
	await _capture("crypt_forecourt_approach.png")

	# View 2: Combat Space (elevated view of the forecourt plaza, broken bier, braziers, and vanguard before the steps).
	cam.global_position = Vector3(2.5, 4.8, -151.0)
	cam.look_at(Vector3(0.0, 1.2, -159.5), Vector3.UP)
	await _capture("crypt_forecourt_combat_space.png")

	# View 3: Alternate Angle (western mortuary shelter view, showing the stone embalming bier, shelter walls, and flank cover line).
	cam.global_position = Vector3(-6.0, 3.8, -148.0)
	cam.look_at(Vector3(-10.5, 1.2, -155.0), Vector3.UP)
	await _capture("crypt_forecourt_alternate_angle.png")

	# View 4: Post-fight Crypt Destination View (looking up the grand stone steps into the sealed facade of the crypt portal).
	cam.global_position = Vector3(0.0, 2.8, -157.0)
	cam.look_at(Vector3(0.0, 3.2, -166.0), Vector3.UP)
	await _capture("crypt_forecourt_destination_view.png")

	print("--- CRYPT FORECOURT ENCOUNTER VALIDATION COMPLETED CLEANLY ---")
	get_tree().quit(0)

func _capture(filename: String) -> void:
	await get_tree().create_timer(0.3).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var out_local: String = ProjectSettings.globalize_path("res://.agentbridge/screenshots/" + filename)
	var out_temp: String = OS.get_environment("TEMP") + "/" + filename
	img.save_png(out_local)
	img.save_png(out_temp)
	print("  [RENDER] Saved: %s (and in %%TEMP%%)" % filename)
