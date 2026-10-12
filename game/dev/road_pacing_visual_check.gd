extends SceneTree
func _init() -> void: call_deferred("run")

func run() -> void:
	TownState.persist = false
	TownState.reset()
	var town := TownScene.new()
	root.add_child(town)
	current_scene = town
	for frame in 300:
		await physics_frame
		if town.director != null and not get_nodes_in_group("enemies").is_empty() and Nav.ready(town.player): break
	town.set_process(false)
	town.set_physics_process(false)
	for member in PartyManager.current().living(): member.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	town.player.global_position = Nav.snap(town.player, town.crypt.at(0, 160))
	town.rig.global_position = town.player.global_position
	TownState.mana_potions = 12
	town.player.stats.mana = 0
	for dimensions in GameSettings.RESOLUTIONS:
		root.mode = Window.MODE_WINDOWED
		root.borderless = true
		var screen := 1 if dimensions.y <= 1080 and DisplayServer.get_screen_count() > 1 else 0
		root.current_screen = screen
		root.size = dimensions
		root.position = DisplayServer.screen_get_position(screen)
		for scale in [0.5, 1.0, 1.5]:
			GameSettings.ui_size = scale
			GameSettings.apply_ui_scale()
			await create_timer(0.3).timeout
			var button: Button = town.combat_hud.ds2_potion_dock._mana_button
			button.grab_focus()
			var motion := InputEventMouseMotion.new()
			motion.position = button.get_global_rect().get_center()
			motion.global_position = motion.position
			Input.parse_input_event(motion)
			await create_timer(0.8).timeout
			await RenderingServer.frame_post_draw
			var file := OS.get_environment("TEMP").path_join("curse_pace_%dx%d_%.1f.png" % [dimensions.x, dimensions.y, scale])
			root.get_texture().get_image().save_png(file)
			print("CAPTURE ", file)
			print("DOCK ", town.combat_hud.ds2_potion_dock.get_global_rect(), " MANA ", button.get_global_rect())
	quit()
