extends SceneTree
## One real bow draw and release with the kit bow on the modular hero (live BowAttack, live CompanionArrow).
##   godot --path . --script game/dev/modular_bow_check.gd -- --modular --shots=<abs dir>
## Asserts: kit bow in the left hand's holder, arrow shown while drawing, both hands follow bow and nock, arrow leaves the bow.
## Images (Godot renders, close inspection camera) need personal review.
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func settle() -> void:
	await create_timer(0.05, true).timeout
	await RenderingServer.frame_post_draw

func run() -> void:
	TownState.persist = false
	TownState.reset()
	var game := load("res://game/main.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await create_timer(1.0).timeout
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	var hero: Player = PartyManager.current().bodies["hero"]
	hero.stats.wear(Items.Slot.WEAPON, Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow"))
	hero.stats.wear(Items.Slot.ARMOR, Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 2, "Leather Jerkin"))
	hero.stats.wear(Items.Slot.HELM, Items.make(Items.Slot.HELM, Items.Rarity.NORMAL, 2, "Woven Hood"))
	await create_timer(0.3).timeout
	check("hero is ranged and has a BowAttack", hero.stats.is_ranged() and hero.bow != null)
	check("kit bow GLB is the bow model", hero.appearance != null and hero.appearance.bow_model.ends_with("wpn_bow.glb"))
	var holder: Node3D = hero.bow._bow_holder
	var bow_mesh: Node = holder.get_child(0)
	check("bow holder carries the kit bow mesh", bow_mesh.find_children("*", "MeshInstance3D", true, false).size() > 0
		and (bow_mesh.scene_file_path.ends_with("wpn_bow.glb")))
	var target := game.director.spawn_enemy(hero.global_position + hero.visual.global_basis.z * 8.0, "zombie", 1.0) as Enemy
	target.set_physics_process(false)
	target.aggro_range = 0.0
	target.max_health = 5000.0
	target.health = 5000.0
	hero.set_physics_process(true)
	var cam: Camera3D = null
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		root.size = Vector2i(1280, 720)
		cam = Camera3D.new(); game.add_child(cam); cam.fov = 38.0; cam.make_current()
	var skel: Skeleton3D = hero.appearance.skeleton
	var lh := skel.find_bone("LeftHand"); var rh := skel.find_bone("RightHand")
	hero.bow.start(target)
	check("draw began (shot counted, hero busy)", hero.bow.shots == 1 and hero.skills.busy)
	var seen_arrow_visible := false
	var min_left := 99.0; var min_right := 99.0
	var arrow: Node3D = null
	var released_at := -1.0
	var t := 0.0
	var shot_names := ["draw_early", "draw_full", "release", "flight"]
	var next := 0
	var gen_before := hero.get_parent().get_child_count()
	while t < 3.0:
		await physics_frame
		t += 1.0 / 60.0
		if hero.bow._draw_arrow.visible:
			seen_arrow_visible = true
			var left_pos: Vector3 = skel.to_global(skel.get_bone_global_pose(lh).origin)
			var right_pos: Vector3 = skel.to_global(skel.get_bone_global_pose(rh).origin)
			var holder_pos: Vector3 = holder.global_position
			min_left = minf(min_left, left_pos.distance_to(holder_pos))
			var nock: Vector3 = hero.bow._draw_arrow.to_global(Vector3(0, -(hero.bow._draw_arrow.get_meta("mesh_bounds") as AABB).size.y * 0.5, 0))
			min_right = minf(min_right, right_pos.distance_to(nock))
		if cam != null and next < 3 and ((next == 0 and hero.bow._draw > 0.35) or (next == 1 and hero.bow._draw > 0.97) or (next == 2 and hero.skills.busy_hit_done)):
			var c := hero.global_position + Vector3(0, 1.3, 0)
			var side := hero.visual.global_basis.x
			cam.global_position = c + side * 3.4 + hero.visual.global_basis.z * 1.2
			cam.look_at(c + hero.visual.global_basis.z * 0.8)
			await settle()
			root.get_texture().get_image().save_png(shots.path_join("BOW_%s.png" % shot_names[next]))
			print("SHOT BOW_%s.png" % shot_names[next])
			next += 1
		if arrow == null:
			for n in hero.get_parent().get_children():
				if n is CompanionArrow:
					arrow = n
					released_at = t
		if arrow != null and is_instance_valid(arrow):
			if cam != null and next == 3 and t - released_at > 0.06:
				var c2 := hero.global_position + Vector3(0, 1.3, 0)
				cam.global_position = c2 + hero.visual.global_basis.x * 3.4 + hero.visual.global_basis.z * 3.0
				cam.look_at(c2 + hero.visual.global_basis.z * 3.5)
				await settle()
				root.get_texture().get_image().save_png(shots.path_join("BOW_flight.png"))
				print("SHOT BOW_flight.png")
				next += 1
			if t - released_at > 0.25:
				break
	check("arrow was visible on the bow during the draw", seen_arrow_visible)
	check("left hand stays at the bow holder during the draw (min %.2f m)" % min_left, min_left < 0.35)
	check("right (string) hand reaches the nock (min %.2f m)" % min_right, min_right < 0.35)
	check("a CompanionArrow was fired", arrow != null)
	if arrow != null and is_instance_valid(arrow):
		var away: float = arrow.global_position.distance_to(holder.global_position)
		check("arrow left the bow (%.2f m from the bow after %.2f s)" % [away, t - released_at], away > 1.0)
		check("arrow flies toward the target", arrow.global_position.distance_to(target.global_position) < hero.global_position.distance_to(target.global_position))
	check("the draw arrow on the bow is hidden after release", not hero.bow._draw_arrow.visible)
	print("BOW CHECK ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
