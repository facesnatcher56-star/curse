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
				continue
			for i in range(1, path.size()):
				if not Nav.clearance(town.player, path[i - 1], path[i]):
					blocked += 1
					print("BLOCKED rubble=", holder.global_position, " start=", start, " goal=", goal, " path=", path)
					break
	print("RUBBLE SCAN checked=", checked, " blocked segments=", blocked, " disconnected=", unreachable)
	var hero := PartyManager.current().bodies.hero as Player
	var cutter := PartyManager.current().bodies.cutter as Player
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
	quit(1 if blocked else 0)
