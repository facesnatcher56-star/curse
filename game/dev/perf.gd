extends DevSuite
## Measurements: the --perf frame-time bench and the --roadreturn Crypt Road walk.

## Developer measurement: time the normal click-to-move return from the third nest to the road gate.
## Run with --crypt --roadreturn=clear|skipped; the skipped case leaves three groups on the route.
func _measure_road_return() -> void:
	var scenario: String = "skipped" if OS.get_cmdline_user_args().has("--roadreturn=skipped") else "clear"
	var place: CryptRoad = game.location
	if place == null:
		push_error("Road return measurement needs --crypt")
		get_tree().quit(1)
		return
	await place.wait_for_navigation()
	game.director.start_location(place)
	for i in 2:
		place.nests[i].hit(999.0, Vector3.FORWARD)
	await get_tree().physics_frame
	player.global_position = Nav.snap(player, place.nests[2].global_position + Vector3(4.0, 0.0, 0.0))
	player.reset_physics_interpolation()
	place.nests[2].hit(999.0, Vector3.FORWARD)
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if scenario == "clear" or enemy.group_id not in [1, 9, 11, 103]:
			enemy.queue_free()
	await get_tree().physics_frame
	player.attack_target = null
	player.attack_prop = null
	player.skills.queued_skill = ""
	var waypoints: Array[Vector3] = [Vector3(0.0, 0.0, -98.0), Vector3(0.0, 0.0, -40.0), Vector3(0.0, 0.0, 20.0),
		Vector3(0.0, 0.0, 92.0), Vector3(0.0, 0.0, 150.0), Vector3(0.0, 0.0, CryptRoad.EXIT_Z)]
	var waypoint_index: int = 0
	player.movement.goal = waypoints[waypoint_index]
	player.movement.has_goal = true
	var start: Vector3 = player.global_position
	var elapsed: float = 0.0
	var next_report: float = 15.0
	print("ROAD RETURN %s start=%s exit_z=%.1f speed=%.1f enemies=%d" % [scenario, start, CryptRoad.EXIT_Z,
		player.stats.run_speed, get_tree().get_nodes_in_group("enemies").size()])
	while elapsed < 140.0 and not player.dead and not game.director.is_ending():
		await get_tree().physics_frame
		elapsed += 1.0 / float(Engine.physics_ticks_per_second)
		if player.global_position.distance_to(waypoints[waypoint_index]) < 2.0 and waypoint_index < waypoints.size() - 1:
			waypoint_index += 1
			player.movement.goal = waypoints[waypoint_index]
			player.movement.has_goal = true
			print("ROAD RETURN %s waypoint=%d t=%.1f pos=%s" % [scenario, waypoint_index, elapsed, player.global_position])
		if elapsed >= next_report:
			print("ROAD RETURN %s t=%.1f z=%.1f x=%.1f hp=%.0f stamina=%.0f" % [scenario, elapsed,
				player.global_position.z, player.global_position.x, player.health, player.stats.stamina])
			next_report += 15.0
	print("ROAD RETURN %s RESULT t=%.2f reached=%s dead=%s z=%.1f hp=%.0f stamina=%.0f" % [scenario,
		elapsed, game.director.is_ending(), player.dead, player.global_position.z, player.health, player.stats.stamina])
	get_tree().quit(0 if game.director.is_ending() else 1)

## `-- --perf [--count=N,N,..] [--noshadow] [--noground]`: real rendering, the hero standing in a pack of zombies, frame times for each pack size.
## Prints average and worst frame time, the 1% low, draw calls, primitives and the engine's own process/physics time.
func _perf_bench() -> void:
	var counts: Array = [0, 12, 30]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			counts = Array(arg.substr(8).split(",")).map(func(c: String) -> int: return int(c))
	if OS.get_cmdline_user_args().has("--world"):
		await _perf_world()
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	if game.director != null:
		game.director.set_process(false)   # no waves of its own: the pack is the one this bench makes
		game.director.set_physics_process(false)
	if OS.get_cmdline_user_args().has("--noshadow"):
		for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).shadow_enabled = false
	player.global_position = Vector3(-30, 0, -30)
	player.reset_physics_interpolation()
	player.health = 1.0e9
	player.max_health = 1.0e9
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await get_tree().create_timer(1.0).timeout
	for count in counts:
		for node in get_tree().get_nodes_in_group("enemies"):
			node.queue_free()
		await get_tree().create_timer(0.3).timeout
		for i in int(count):
			var angle: float = TAU * float(i) / float(maxi(int(count), 1))
			var z: Enemy = _spawn_enemy(player.global_position + Vector3(sin(angle), 0, cos(angle)) * (3.0 + float(i % 3) * 1.5))
			z.aggro_range = 60.0
		await get_tree().create_timer(1.5).timeout
		for arg in OS.get_cmdline_user_args():
			if arg == "--exp=nophys":
				for node in get_tree().get_nodes_in_group("enemies"):
					node.set_physics_process(false)
			elif arg == "--exp=noanim":
				for node in get_tree().get_nodes_in_group("enemies"):
					(node as Enemy).model.anim.process_mode = Node.PROCESS_MODE_DISABLED
			elif arg == "--exp=nomsaa":
				get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			elif arg == "--exp=lowres":
				get_viewport().scaling_3d_scale = 0.67
			elif arg == "--exp=nocol":
				for node in get_tree().get_nodes_in_group("enemies"):
					(node as Enemy).collision_layer = 0
					(node as Enemy).collision_mask = 0
			elif arg == "--exp=nointerp":
				get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			elif arg == "--exp=noshadow":
				for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
					(light as DirectionalLight3D).shadow_enabled = false
			elif arg == "--exp=noomni":
				for light in get_tree().root.find_children("*", "OmniLight3D", true, false):
					(light as OmniLight3D).visible = false
			elif arg == "--exp=flatground":
				for body in get_tree().root.find_children("*", "MeshInstance3D", true, false):
					var mi := body as MeshInstance3D
					if mi.mesh is PlaneMesh and (mi.mesh as PlaneMesh).size.x > 50.0:
						var flat := StandardMaterial3D.new()
						flat.albedo_color = Color(0.15, 0.14, 0.12)
						mi.material_override = flat
			elif arg == "--exp=noglow" or arg == "--exp=nofog" or arg == "--exp=noenv":
				for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
					var environment: Environment = (node as WorldEnvironment).environment
					if arg != "--exp=nofog":
						environment.glow_enabled = false
					if arg != "--exp=noglow":
						environment.fog_enabled = false
			elif arg == "--exp=hidden":
				for node in get_tree().get_nodes_in_group("enemies"):
					(node as Enemy).visible = false
		var times: Array[float] = []
		var spikes: Array[String] = []
		var draw_calls: float = 0.0
		var gpu_sum: float = 0.0
		var prims: float = 0.0
		var process_ms: float = 0.0
		var physics_ms: float = 0.0
		var nav_ms: float = 0.0
		var pairs: float = 0.0
		var active: float = 0.0
		var phys_start: int = Engine.get_physics_frames()
		var last: int = Time.get_ticks_usec()
		var started: int = last
		while Time.get_ticks_usec() - started < 5000000:
			await get_tree().process_frame
			var now: int = Time.get_ticks_usec()
			times.append(float(now - last) / 1000.0)
			if float(now - last) / 1000.0 > 22.0:
				var vp: RID = get_viewport().get_viewport_rid()
				spikes.append("%.2fs:%.0fms(gpu %.0f cpu-render %.0f proc %.0f phys %.0f)" % [float(now - started) / 1.0e6, float(now - last) / 1000.0, RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
			last = now
			gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
			draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			nav_ms += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
			pairs += Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
			active += Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
		times.sort()
		var n: int = times.size()
		print("physics ticks per rendered frame: %.2f" % (float(Engine.get_physics_frames() - phys_start) / n))
		print("SPIKES ", spikes)
		var total: float = 0.0
		for t in times:
			total += t
		var low: float = 0.0
		var worst_count: int = maxi(n / 100, 1)
		for k in worst_count:
			low += times[n - 1 - k]
		low /= float(worst_count)
		print("GPU avg %.1f ms" % (gpu_sum / n))
		print("PERF enemies=%2d  avg %.1f ms (%.0f fps)  1%%-low %.1f ms (%.0f fps)  worst %.1f ms  draws %d  tris %dk  script process %.1f ms  physics %.1f ms  nav %.1f ms  pairs %d active %d  nodes %d" % [
			count, total / n, 1000.0 * n / total, low, 1000.0 / low, times[n - 1], draw_calls / n, prims / n / 1000.0, process_ms / n, physics_ms / n, nav_ms / n, pairs / n, active / n,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	get_tree().quit()

## `-- --perf --world`: the real connected world (plaza and Crypt Road, every monster loaded): frame times standing in the plaza, out on
## the road with the monsters asleep, and in a fight with everything within 35 m awake.
## One frame-time sample window: average, 1% low, GPU ms.
func _sample_frames(seconds: float) -> String:
	var times: Array[float] = []
	var gpu: float = 0.0
	var last: int = Time.get_ticks_usec()
	var started: int = last
	while float(Time.get_ticks_usec() - started) < seconds * 1.0e6:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	times.sort()
	var n: int = times.size()
	var total: float = 0.0
	for t in times:
		total += t
	var worst: int = maxi(n / 100, 1)
	var low: float = 0.0
	for k in worst:
		low += times[n - 1 - k]
	return "%5.1f ms (%3.0f fps) 1%%low %5.1f  gpu %4.1f" % [total / n, 1000.0 * n / total, low / worst, gpu / n]

func _perf_world() -> void:
	TownState.persist = false
	TownState.reset()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	GameSettings.apply_video()
	var town := TownScene.new()
	game.add_child(town)
	var waited: int = 0
	while (town.director == null or get_tree().get_nodes_in_group("enemies").size() < 40) and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var hero: Player = town.player
	if OS.get_cmdline_user_args().has("--audit"):   # which meshes the world is made of, by triangles
		var by_mesh: Dictionary = {}
		for node in get_tree().root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var tris: int = 0
			for surface in mi.mesh.get_surface_count():
				var arrays: Array = mi.mesh.surface_get_arrays(surface)
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var owner_name: String = String(mi.get_parent().get_parent().name if mi.get_parent() != null and mi.get_parent().get_parent() != null else mi.name)
			var key: String = "%s | %s" % [mi.mesh.resource_path.get_file() if mi.mesh.resource_path != "" else mi.mesh.get_class(), String(mi.mesh.resource_name)]
			var entry: Array = by_mesh.get(key, [0, 0])
			entry[0] = int(entry[0]) + 1
			entry[1] = tris
			by_mesh[key] = entry
		var keys: Array = by_mesh.keys()
		keys.sort_custom(func(a, b): return int(by_mesh[a][0]) * int(by_mesh[a][1]) > int(by_mesh[b][0]) * int(by_mesh[b][1]))
		for k in keys.slice(0, 25):
			print("AUDIT %-60s x%-4d %7d tris each  = %dk" % [k, by_mesh[k][0], by_mesh[k][1], int(by_mesh[k][0]) * int(by_mesh[k][1]) / 1000])
	hero.health = 1.0e9
	hero.max_health = 1.0e9
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if OS.get_cmdline_user_args().has("--cpu"):
		await _perf_cpu(town, hero)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--matrix"):
		await _perf_matrix(town, hero)
		get_tree().quit()
		return
	for phase in ["plaza", "road", "fight"]:
		if phase == "road":
			hero.global_position = town.crypt.at(0.0, -40.0) if town.crypt != null else Vector3(0, 0, -60)
			hero.reset_physics_interpolation()
		elif phase == "fight":
			for node in get_tree().get_nodes_in_group("enemies"):
				var e := node as Enemy
				if e != null and not e.dead and e.global_position.distance_to(hero.global_position) < 35.0:
					e.wake()
		await get_tree().create_timer(2.0).timeout
		var times: Array[float] = []
		var gpu: float = 0.0
		var last: int = Time.get_ticks_usec()
		var started: int = last
		while Time.get_ticks_usec() - started < 6000000:
			await get_tree().process_frame
			var now: int = Time.get_ticks_usec()
			times.append(float(now - last) / 1000.0)
			last = now
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		times.sort()
		var n: int = times.size()
		var total: float = 0.0
		for t in times:
			total += t
		var low: float = 0.0
		for k in maxi(n / 100, 1):
			low += times[n - 1 - k]
		low /= float(maxi(n / 100, 1))
		var awake: int = 0
		for node in get_tree().get_nodes_in_group("enemies"):
			awake += 1 if (node as Enemy)._aggro else 0
		print("WORLD %-6s avg %.1f ms (%.0f fps)  1%%-low %.1f ms  worst %.1f ms  gpu %.1f ms  enemies %d (awake %d)  nodes %d  draws %d  tris %dk" % [
			phase, total / n, 1000.0 * n / total, low, times[n - 1], gpu / n, get_tree().get_nodes_in_group("enemies").size(), awake,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])
	get_tree().quit()

## Where the plaza's frame time goes: each step switches one more thing off and samples again.
func _perf_cpu(town: TownScene, hero: Player) -> void:
	hero.global_position = Vector3(0, 0, 10)
	hero.reset_physics_interpolation()
	await get_tree().create_timer(2.0).timeout
	var dormant_count: int = 0
	var nearest: float = 1.0e9
	var farthest: float = 0.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		dormant_count += 1 if e.dormant else 0
		var d: float = Vector2(e.global_position.x - hero.global_position.x, e.global_position.z - hero.global_position.z).length()
		nearest = minf(nearest, d)
		farthest = maxf(farthest, d)
	print("DORMANT %d of %d; hero at %s; nearest %.0f m, farthest %.0f m; hero processing %s" % [dormant_count, get_tree().get_nodes_in_group("enemies").size(), hero.global_position, nearest, farthest, hero.is_physics_processing()])
	var by_script: Dictionary = {}
	for node in get_tree().root.find_children("*", "Node", true, false):
		if node.is_processing() or node.is_physics_processing():
			var script: Script = node.get_script()
			var key: String = script.resource_path.get_file() if script != null else node.get_class()
			by_script[key] = int(by_script.get(key, 0)) + 1
	print("PROCESSING ", by_script)
	var steps: Array = [["base", func() -> void: pass]]
	for script_name in ["hud.gd", "town_hud.gd", "town_scene.gd", "run_director.gd", "crypt_road.gd", "flicker_light.gd", "town_npc.gd", "character_model.gd", "enemy.gd", "weapon_trail.gd", "camera_rig.gd", "main.gd", "player.gd"]:
		steps.append(["+ " + script_name + " off", func() -> void:
			for node in get_tree().root.find_children("*", "Node", true, false):
				var script: Script = node.get_script()
				if script != null and script.resource_path.get_file() == script_name:
					node.set_process(false)
					node.set_physics_process(false)])
	for step in steps:
		(step[1] as Callable).call()
		await get_tree().create_timer(2.0).timeout
		print("CPU %-44s %s  nodes %d" % [step[0], await _sample_frames(3.0), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])

func _perf_matrix(town: TownScene, hero: Player) -> void:
	var sun: DirectionalLight3D = null
	for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		sun = light as DirectionalLight3D
	var viewport: Viewport = get_viewport()
	var configs: Array = [
		["base", func() -> void: pass],
		["no shadows", func() -> void: sun.shadow_enabled = false],
		["sun 2 splits, 30 m", func() -> void:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 30.0],
		["+ msaa off", func() -> void: viewport.msaa_3d = Viewport.MSAA_DISABLED],
		["+ render scale 0.77 (FSR)", func() -> void:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			viewport.scaling_3d_scale = 0.77],
	]
	for config in configs:
		(config[1] as Callable).call()
		hero.global_position = Vector3(0, 0, 10)
		hero.reset_physics_interpolation()
		await get_tree().create_timer(2.5).timeout
		var plaza: String = await _sample_frames(3.0)
		hero.global_position = town.crypt.at(0.0, -40.0)
		hero.reset_physics_interpolation()
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e != null and not e.dead and e.global_position.distance_to(hero.global_position) < 35.0:
				e.wake()
		await get_tree().create_timer(2.5).timeout
		var fight: String = await _sample_frames(3.0)
		print("MATRIX %-28s plaza %s | fight %s" % [config[0], plaza, fight])
