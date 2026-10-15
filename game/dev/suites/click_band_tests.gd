extends DevSuite
## Clicks in the band above the bottom hotbar must reach the world (issue #39, item 3). The HUD's own hit areas (`Hud.covers`) must
## follow what is drawn: the hotbar bar, the round vessels and map by their circles, the open skill picker. Nothing invisible in the
## band above the bar may take the click, and the hotbar, potion dock and utility buttons must still take it.

func _settle() -> void:
	for i in 3: await get_tree().process_frame

func _test_click_band() -> void:
	Gamepad.active = false
	# The dev harness pins its windows to 1280x720; `-- --bandsize=WxH` resizes the window for the check (e.g. the owner's 1080p).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bandsize="):
			var wh := arg.substr(11).split("x")
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
			for i in 30: await get_tree().process_frame
	await _settle()
	var size_px: Vector2 = get_viewport().get_visible_rect().size
	var bar_top: float = hud.hotbar_rect(size_px).position.y
	var orb: Rect2 = Hud.orb_rect(size_px, false)
	var map_rect: Rect2 = Hud.minimap_rect(size_px, true)

	# Ground in the band above the bar, away from the vessels and map: must reach the world.
	for fx in [0.35, 0.5, 0.65]:
		var point := Vector2(size_px.x * fx, bar_top - 40.0)
		expect("ground click above the hotbar at x=%.0f%% reaches the world" % (fx * 100.0), not hud.covers(point) and not player.mouse_over_ui(point))

	# The DS2 HUD hides the vessels and the legacy map: their rectangles must not block. The legacy vessels block only by their circles.
	if hud.use_ds2_ui:
		expect("the hidden legacy map position does not block in the DS2 HUD", not hud.covers(Hud.minimap_rect(size_px, false).get_center()))
		expect("the hidden health vessel does not block in the DS2 HUD", not hud.covers(orb.get_center()))
	else:
		var corner := orb.position + Vector2(6.0, 6.0)
		expect("the corner of the square around a legacy vessel does not block", not hud.covers(corner))
		expect("a legacy vessel itself blocks", hud.covers(orb.get_center()))
	var map_corner := map_rect.position + Vector2(map_rect.size.x - 4.0, 4.0)   # top right: the vessel's disc overlaps the map's top left
	expect("the corner of the square around the map does not block", not hud.covers(map_corner))
	expect("the round map itself blocks", hud.covers(map_rect.get_center()))

	# Interactive things keep their clicks: the hotbar bar, and the potion dock's buttons.
	expect("the hotbar bar still blocks the world", hud.covers(Vector2(size_px.x * 0.5, size_px.y - 8.0)))
	var potion: Control = game.find_child("mana_potion", true, false) as Control
	expect("the mana potion button is still a mouse target", potion != null and potion.mouse_filter == Control.MOUSE_FILTER_STOP)
	# `-- --bandshot=NAME` saves the HUD as docs/screenshots/ui-click-band/NAME.png for inspection.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bandshot=") and DisplayServer.get_name() != "headless":
			var dir := ProjectSettings.globalize_path("res://docs/screenshots/ui-click-band")
			DirAccess.make_dir_recursive_absolute(dir)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir.path_join(arg.substr(11) + ".png"))
			print("CLICKBAND_SHOT ", dir.path_join(arg.substr(11) + ".png"))
