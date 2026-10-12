extends SceneTree
## Inspect every authored rubble approach, not only a preselected clear route.
func _init() -> void:
	call_deferred("run")

func run() -> void:
	TownState.persist = false
	TownState.reset()
	var town := TownScene.new()
	root.add_child(town)
	current_scene = town
	town.set_process(false)
	town.set_physics_process(false)
	for frame in 120:
		await physics_frame
		if Nav.ready(town.player): break
	for member in PartyManager.current().living(): member.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	var checked := 0
	var blocked := 0
	var unreachable := 0
	var rocks: Array[Vector3] = []
	for holder in town._world_nav.get_children():
		if not holder is Node3D or holder.get_child_count() == 0: continue
		var prop := holder.get_child(0)
		if not "rubble" in prop.scene_file_path: continue
		rocks.append(holder.global_position)
		for axis in [Vector3.RIGHT, Vector3.FORWARD, Vector3(1, 0, 1).normalized(), Vector3(1, 0, -1).normalized()]:
			var start := Nav.snap(town.player, holder.global_position - axis * 4.0)
			var goal := Nav.snap(town.player, holder.global_position + axis * 4.0)
			if not Nav.clearance(town.player, start, start) or not Nav.clearance(town.player, goal, goal): continue
			var path := NavigationServer3D.map_get_path(Nav.map_of(town.player), start, goal, true)
			checked += 1
			if path.is_empty() or path[path.size() - 1].distance_to(goal) > 0.5:
				unreachable += 1
				print("UNREACHABLE rubble=", holder.global_position, " start=", start, " goal=", goal)
				var main_path := NavigationServer3D.map_get_path(Nav.map_of(town.player), town.player.global_position, goal, true)
				print("  main component reaches goal=", not main_path.is_empty() and main_path[-1].distance_to(goal) < 0.5)
				for endpoint in [start, goal]:
					var exits := 0
					var bake_exits := 0
					for ray in 32:
						var direction := Vector3(cos(ray * TAU / 32.0), 0, sin(ray * TAU / 32.0))
						var outside := Nav.snap(town.player, endpoint + direction * 4.0)
						var connected := NavigationServer3D.map_get_path(Nav.map_of(town.player), town.player.global_position, outside, true)
						if not connected.is_empty() and connected[-1].distance_to(outside) < 0.5:
							if Nav.clearance(town.player, endpoint, outside): exits += 1
							var original_radius := town.player.body_radius
							town.player.body_radius = 0.75 # Match shared bake radius for diagnosis, no physics step occurs.
							if Nav.clearance(town.player, endpoint, outside): bake_exits += 1
							town.player.body_radius = original_radius
					print("  endpoint=", endpoint, " body-clear exits=", exits, " bake-radius exits=", bake_exits)
				for nearby in town._world_nav.get_children():
					if nearby is Node3D and nearby.get_child_count() > 0 and nearby.global_position.distance_to(goal) < 8:
						print("  nearby=", nearby.global_position, " ", nearby.get_child(0).scene_file_path)
				continue
			for i in range(1, path.size()):
				if not Nav.clearance(town.player, path[i - 1], path[i]):
					blocked += 1
					print("BLOCKED rubble=", holder.global_position, " start=", start, " goal=", goal, " path=", path)
					break
	print("RUBBLE SCAN checked=", checked, " blocked segments=", blocked, " disconnected=", unreachable)
	var hero := PartyManager.current().bodies.hero as Player
	var cutter := PartyManager.current().bodies.cutter as Player
	# Lock the formerly disconnected endpoints even when the author moves a prop;
	# rescanning relative to its new centre alone could silently lose this coverage.
	for pair in [
		[Vector3(16.5, 0, 18), Vector3(18.975, 0, 13.225)],
		[Vector3(16.38582, 0, 17.97145), Vector3(19.5, 0, 14.77157)],
		[Vector3(-14.58409, 0, -108.4989), Vector3(-9.75, 0, -103.75)]]:
		for body in [hero, cutter]:
			var other := cutter if body == hero else hero
			other.global_position = Vector3.ZERO # Don't turn this clearance fixture into a crowd test.
			body.global_position = Nav.snap(body, pair[0])
			body.movement.goal = Nav.snap(body, pair[1])
			body.movement.has_goal = true
			Nav.reset(body, body.movement._nav_state)
			var arrived := false
			for frame in 900:
				await physics_frame
				body.movement.move(1.0 / 60.0)
				if Vector2(body.global_position.x - pair[1].x, body.global_position.z - pair[1].z).length() < 0.5:
					arrived = true
					break
			print("%s FORMER ISLAND member=%s start=%s goal=%s end=%s" % ["PASS" if arrived else "FAIL", body.member_id, pair[0], pair[1], body.global_position])
			if not arrived: blocked += 1
	var road_rocks: Array[Vector3] = []
	for centre in rocks:
		if centre.z < -22: road_rocks.append(centre)
	for centre in road_rocks.slice(0, 2):
		for axis in [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]:
			hero.global_position = Nav.snap(hero, centre + axis * 8.0)
			cutter.global_position = Nav.snap(cutter, centre - axis * 4.0)
			hero.attack_target = null
			cutter.attack_target = null
			Nav.reset(cutter, cutter.movement._nav_state)
			cutter.ai.leash_active = false
			var arrived := false
			for frame in 900:
				await physics_frame
				cutter.ai.tick(1.0 / 60.0)
				if cutter.flat_distance_to(hero) <= 6.0:
					arrived = true
					break
			print("%s FOLLOW rubble=%s axis=%s position=%s gap=%.2f" % ["PASS" if arrived else "FAIL", centre, axis, cutter.global_position, cutter.flat_distance_to(hero)])
			if not arrived: blocked += 1
	quit(1 if blocked or unreachable else 0)
