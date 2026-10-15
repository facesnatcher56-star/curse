extends DevSuite
## Focused integration check and real-game capture for the character level-up effect.

func _test_level_up_fx() -> void:
	TownState.persist = false
	TownState.reset()
	# Keep the characters at ordinary, low combat ranks while the level-up cue exercises XP.
	for id in ["hero", "cutter"]:
		PartyManager.current().member(id).class_xp = {"melee": HeroProgression.xp_for_level(2), "ranged": 0, "combat": 0, "nature": 0}
	await get_tree().process_frame
	TownState.add_hero_xp(HeroProgression.xp_for_level(2), false)
	var hero_fx := player.get_node_or_null("CharacterLevelUpFx") as Node3D
	expect("hero XP level event attaches the effect to the earning hero", hero_fx != null and hero_fx.get_parent() == player)
	expect("hero level-up keeps gameplay running and has no duplicate HUD toast", not get_tree().paused and player.is_processing()
		and hud.level_toast_text.is_empty() and hud.level_toast_time == 0.0)
	var previous_position: Vector3 = player.global_position
	player.global_position += Vector3(0.4, 0.0, 0.0)
	expect("effect follows the actor while they move", hero_fx != null and hero_fx.global_position.distance_to(player.global_position) < 0.01)
	player.global_position = previous_position
	TownState.add_member_xp("cutter", HeroProgression.xp_for_level(2), false)
	var cutter_fx := game.companion.get_node_or_null("CharacterLevelUpFx") as Node3D
	expect("Cutter gets an independent effect from their own XP event", cutter_fx != null and cutter_fx.get_parent() == game.companion
		and cutter_fx != hero_fx and is_instance_valid(hero_fx))
	await get_tree().create_timer(Fx.LEVEL_UP_DURATION + 0.15).timeout
	expect("hero and Cutter effects clean themselves up after 2.8 seconds", not is_instance_valid(hero_fx) and not is_instance_valid(cutter_fx))
	TownState.reset()

## --levelupcapture=hero_still|hero_moving|cutter|party; add --crypt for the dark authored road.
## Captures the real main scene at fixed 60 fps as sequential JPEGs for FFmpeg encoding.
func _level_up_capture(case_name: String) -> void:
	TownState.persist = false
	TownState.reset()
	for id in ["hero", "cutter"]:
		PartyManager.current().member(id).class_xp = {"melee": HeroProgression.xp_for_level(2), "ranged": 0, "combat": 0, "nature": 0}
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	var actor: Player = game.companion if case_name == "cutter" else player
	rig.target = actor
	if game.location is TestDungeon:
		rig.zoom_max = TestDungeon.ZOOM_MAX
	rig.set_zoom_now(0.9)
	if case_name == "cutter":
		actor.global_position = player.global_position + Vector3(1.4, 0.0, 0.8)
	elif case_name == "party":
		game.companion.global_position = player.global_position + Vector3(1.3, 0.0, 0.8)
	var out_path := ProjectSettings.globalize_path("res://.dev_output/level-up-frames/" + case_name)
	var err := DirAccess.make_dir_recursive_absolute(out_path)
	if err != OK:
		push_error("Could not create level-up capture folder: " + out_path)
		get_tree().quit(1)
		return
	if game.location != null:
		await game.location.wait_for_navigation()
		game.director.start_location(game.location)
	else:
		await get_tree().physics_frame
		await get_tree().physics_frame
		game.director.start_wave()
	# Let the authored location intro clear before the sample so its text cannot cover the character's level-up title.
	await get_tree().create_timer(4.0).timeout
	print("LEVELUP_CAPTURE_START case=", case_name, " output=", out_path, " actor=", actor.member_id,
		" crypt=", OS.get_cmdline_user_args().has("--crypt"))
	# Half-second pre-roll, the 2.8 s effect, and a short gameplay tail.
	var frame_count := 222
	for frame in frame_count:
		if frame == 30:
			if case_name == "cutter":
				TownState.add_member_xp("cutter", HeroProgression.xp_for_level(2), false)
			else:
				TownState.add_hero_xp(HeroProgression.xp_for_level(2), false)
			if case_name == "party":
				TownState.add_member_xp("cutter", HeroProgression.xp_for_level(2), false)
		if case_name == "hero_moving" and frame == 60:
			# Keep movement underway after the cue, without relying on a user input injection.
			actor.movement.goal = actor.global_position + Vector3(2.2, 0.0, 0.0)
			actor.movement.has_goal = true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image == null:
			push_error("Level-up frame capture returned an empty image at frame " + str(frame))
			get_tree().quit(1)
			return
		var save_err := image.save_jpg(out_path.path_join("frame_%06d.jpg" % frame), 0.92)
		if save_err != OK:
			push_error("Could not save level-up frame " + str(frame) + ": " + str(save_err))
			get_tree().quit(1)
			return
	print("LEVELUP_CAPTURE_DONE case=", case_name, " frames=", frame_count, " fps=60 size=", get_viewport().size)
	get_tree().quit(0)
