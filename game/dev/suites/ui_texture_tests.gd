extends DevSuite
## `--only=uitexture`: 1080p captures for the texture and text pass (#49). Writes full frames to `--uitex-out=DIR`
## (default: %TEMP%) as {prefix}_hud.png, {prefix}_character.png, {prefix}_tooltip.png. Owner rule: 1080p, monitor 1 (screen 1) only.

func _settle() -> void:
	for i in 8: await get_tree().process_frame

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("UITEX_CAPTURE ", path)

func _test_ui_texture() -> void:
	var out_dir := OS.get_environment("TEMP")
	var prefix := "uitex"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--uitex-out="): out_dir = arg.substr("--uitex-out=".length())
		if arg.begins_with("--uitex-prefix="): prefix = arg.substr("--uitex-prefix=".length())
	if DisplayServer.get_name() == "headless":
		expect("ui texture captures need a display", false)
		return
	var screen := mini(1, DisplayServer.get_screen_count() - 1)
	var window := get_window()
	var size := Vector2i(1920, 1080)
	var ui_size := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--uitex-size="):
			var parts := arg.substr("--uitex-size=".length()).split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		if arg.begins_with("--uitex-ui="): ui_size = float(arg.substr("--uitex-ui=".length()))
	window.borderless = false
	window.current_screen = screen
	window.size = size
	window.position = DisplayServer.screen_get_position(screen)
	print("UITEX_SCREEN index=", screen, " size=", DisplayServer.screen_get_size(screen), " viewport=", get_viewport().get_visible_rect().size)
	GameSettings.ui_size = ui_size
	GameSettings.apply_ui_scale()
	await _settle()
	var hero := player
	hero.stats.add_to_bag(Items.build(ItemDb.get_def("short_bow"), 10, Items.Rarity.RARE, ["ranged_pct_1", "ranged_min_1", "ranged_max_1"]))
	await _settle()
	await _capture(out_dir.path_join("%s_hud.png" % prefix))
	hud._open_character()
	await _settle()
	await _capture(out_dir.path_join("%s_character.png" % prefix))
	hud.open_skills()
	await _settle()
	await _capture(out_dir.path_join("%s_skills.png" % prefix))
	hud._open_character()
	await _settle()
	var grid: Control = hud.character_panel.find_child("BackpackGrid", true, false)
	if grid != null and not grid.tiles.is_empty():
		var point: Vector2 = (grid.tiles[0] as Control).get_global_rect().get_center()
		Input.warp_mouse(point)
		await _settle()
		# Two motion events after the warp: the first can be consumed before the grid's hover state updates.
		for i in 2:
			var motion := InputEventMouseMotion.new()
			motion.position = point
			get_viewport().push_input(motion, true)
			await _settle()
	await _capture(out_dir.path_join("%s_tooltip.png" % prefix))
	get_tree().quit(0)
