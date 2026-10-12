extends SceneTree
## Visible traversal in the real connected town/road, never a production campaign.
var town: TownScene
var failures := 0
var label := "1080"

func _init() -> void:
	call_deferred("run")

func capture(tag: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join("curse_navigation_%s_%s.png" % [label, tag])
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func route_fixture(area: Arena) -> Dictionary:
	for obstacle in area.obstacles:
		var radius := float(obstacle.radius)
		if radius < 0.7 or radius > 5.0: continue
		var centre: Vector3 = obstacle.position
		for axis in [Vector3.RIGHT, Vector3.FORWARD]:
			var start := Nav.snap(town.player, centre - axis * (radius + 3.0))
			var goal := Nav.snap(town.player, centre + axis * (radius + 3.0))
			if Nav.clearance(town.player, start, goal): continue
			var path := NavigationServer3D.map_get_path(Nav.map_of(town.player), start, goal, true)
			if path.size() < 3 or path[path.size() - 1].distance_to(goal) > 0.5: continue
			var valid := true
			for i in range(1, path.size()): valid = valid and Nav.clearance(town.player, path[i - 1], path[i])
			if valid: return {"start": start, "goal": goal, "points": path.size()}
	return {}

func traverse(area: Arena, tag: String, member: String, supplied: Dictionary = {}) -> void:
	var fixture := route_fixture(area) if supplied.is_empty() else supplied
	if fixture.is_empty():
		print("FAIL: no body-clear detour in ", tag)
		failures += 1
		return
	PartyManager.current().select(member)
	var lead := PartyManager.current().active_body() as Player
	# town.player follows active selection, so resolve the other body by stable ID.
	var follow := PartyManager.current().bodies["cutter" if member == "hero" else "hero"] as Player
	lead.global_position = fixture.start
	follow.global_position = Nav.snap(follow, fixture.start + Vector3(0, 0, 1.8))
	lead.reset_physics_interpolation()
	follow.reset_physics_interpolation()
	Nav.reset(lead, lead.movement._nav_state)
	Nav.reset(follow, follow.movement._nav_state)
	lead.attack_target = null
	follow.attack_target = null
	town.rig.global_position = lead.global_position
	await create_timer(0.4).timeout
	await capture(tag + "_start")
	var arrived := false
	for frame in 1200:
		await physics_frame
		lead.movement.goal = fixture.goal
		lead.movement.has_goal = true
		lead.movement.move(1.0 / 60.0)
		lead.movement.update_locomotion_anim()
		follow.ai.tick(1.0 / 60.0)
		if frame == 90: await capture(tag + "_route")
		if lead.flat_distance_to_point(fixture.goal) < 0.5:
			arrived = true
			break
	for frame in 180:
		await physics_frame
		follow.ai.tick(1.0 / 60.0)
	await capture(tag + "_end")
	var passed := arrived and follow.flat_distance_to(lead) <= 6.0
	print("%s: %s %s points=%d arrived=%s follower_gap=%.2f" % ["PASS" if passed else "FAIL", tag, member, fixture.points, arrived, follow.flat_distance_to(lead)])
	if not passed: failures += 1

func run() -> void:
	TownState.persist = false
	TownState.reset()
	town = TownScene.new()
	root.add_child(town)
	current_scene = town
	for frame in 180:
		await physics_frame
		if Nav.ready(town.player): break
	town.set_process(false)
	town.set_physics_process(false)
	if town.director != null: town.director.set_process(false)
	for node in get_nodes_in_group("enemies"): node.set_physics_process(false)
	for node in town.npcs.values(): node.set_physics_process(false)
	var hero := PartyManager.current().bodies["hero"] as Player
	var cutter := PartyManager.current().bodies["cutter"] as Player
	hero.set_physics_process(false)
	cutter.set_physics_process(false)
	for dimensions in [Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		label = "1080" if dimensions.y == 1080 else "1440"
		root.mode = Window.MODE_WINDOWED
		root.borderless = true
		var screen := 1 if dimensions.y == 1080 and DisplayServer.get_screen_count() > 1 else 0
		root.current_screen = screen
		root.size = dimensions
		root.position = DisplayServer.screen_get_position(screen)
		GameSettings.ui_size = 1.0
		GameSettings.apply_ui_scale()
		await create_timer(0.5).timeout
		await traverse(town.arena, "town", "hero")
		var start := Nav.snap(hero, Vector3(0, 0, 10))
		var goal := Nav.snap(hero, town.crypt.at(town.crypt.road_centre_x(CryptRoad.EXIT_Z - 20), CryptRoad.EXIT_Z - 20))
		var gate_path := NavigationServer3D.map_get_path(Nav.map_of(hero), start, goal, true)
		await traverse(town.arena, "gate", "hero", {"start": start, "goal": goal, "points": gate_path.size()})
		await traverse(town.crypt.arena, "road", "cutter")
		# Isolated earned XP permits ordinary gear checks; identity grants no exceptions.
		TownState.add_member_xp("hero", 300, false, {"ranged": 1.0})
		TownState.add_member_xp("cutter", 300, false, {"melee": 1.0})
		hero.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow"), false)
		cutter.stats.equip(Items.starting_gear()[0], false)
		if not hero.stats.is_ranged() or cutter.stats.is_ranged():
			print("FAIL: swapped equipment requirements")
			failures += 1
		await traverse(town.arena, "town_swapped", "cutter")
		await traverse(town.crypt.arena, "road_swapped", "hero")
		hero.stats.equip(Items.starting_gear()[0], false)
		cutter.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow"), false)
	print("VISIBLE NAVIGATION: %d failure(s)" % failures)
	quit(1 if failures else 0)
