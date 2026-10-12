extends DevSuite
## Actual town screens at supported window sizes and interface-scale boundaries.
func _settle() -> void:
	for i in 8: await get_tree().process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join("curse_theme_" + name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("THEME_CAPTURE ", path)

func _test_ornate_theme() -> void:
	for id in ["metal", "parchment", "button", "icon", "compass", "crest"]:
		expect("generated art is present: " + id, UiTheme.art(id) != null)
	expect("panels use textured reusable styles", UiTheme.panel_box() is StyleBoxTexture)
	for id in UiTheme.ART_LOGICAL_SIZE:
		expect("high-DPI pixels preserved: " + id, UiTheme.art(id).get_image().get_width() >= UiTheme.ART_LOGICAL_SIZE[id].x * 4)
		expect("nine-slice logical geometry preserved: " + id, Vector2i(UiTheme.art(id).get_size()) == UiTheme.ART_LOGICAL_SIZE[id])
	expect("parchment uses dark readable ink", UiTheme.PAPER_INK.get_luminance() < 0.2)
	expect("native tooltips share the compact ornate frame", UiTheme.get_theme().get_stylebox("panel", "TooltipPanel").texture == UiTheme.tooltip_box().texture)
	var icon_button := Button.new()
	UiTheme.style_button(icon_button, Color.WHITE, true)
	expect("white icon buttons visibly brighten on hover", icon_button.get_theme_stylebox("hover").modulate_color.r > icon_button.get_theme_stylebox("normal").modulate_color.r)
	icon_button.free()
	TownState.persist = false
	TownState.reset()
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	await _settle()
	var town := TownScene.new()
	town.with_road = false
	game.add_child(town)
	hud.hide()
	await _settle()
	var ui := town.combat_hud
	# Keep the matrix's real hover card representative of the longest generated weapon modifier stack.
	town.player.stats.add_to_bag(Items.build(ItemDb.get_def("short_bow"), 10, Items.Rarity.RARE,
		["ranged_pct_1", "ranged_min_1", "ranged_max_1"]))
	var old_scale := GameSettings.ui_size
	var old_size := get_window().size
	var old_screen := get_window().current_screen
	var old_borderless := get_window().borderless
	var resolutions := GameSettings.RESOLUTIONS
	if DisplayServer.get_name() == "headless": resolutions = [old_size]
	for resolution in resolutions:
		for multiplier in [0.5, 1.0, 1.5]:
			if DisplayServer.get_name() != "headless":
				# Owner permits the native 1440p check on monitor 1; monitor 2 is 1080p.
				var screen: int = 0 if resolution.y > 1080 else mini(1, DisplayServer.get_screen_count() - 1)
				get_window().current_screen = screen
				get_window().borderless = true
				get_window().size = resolution
				var physical := DisplayServer.screen_get_size(screen)
				get_window().position = DisplayServer.screen_get_position(screen) + (physical - resolution).max(Vector2i.ZERO) / 2
				expect("test window fits physical monitor", physical.x >= resolution.x and physical.y >= resolution.y)
				GameSettings.ui_size = multiplier
				GameSettings.apply_ui_scale()
			await _settle()
			var tag := "%dx%d_scale%s" % [resolution.x, resolution.y, str(multiplier)]
			print("THEME_CASE ", tag, " viewport=", get_viewport().get_visible_rect().size,
				" monitor=", DisplayServer.window_get_current_screen())
			await _capture("hud_" + tag)
			# Art preview only: never persist or change the player's default layout.
			var prior_icon: String = town.player.skills.hotbar[2]
			town.player.skills.hotbar[2] = "provoke"
			await _settle()
			await _capture("provoke_preview_" + tag)
			town.player.skills.hotbar[2] = prior_icon
			await _settle()
			ui._open_character()
			await _settle()
			print("THEME_INVENTORY ", tag, " size=", ui.character_panel.size, " scale=", ui.character_panel.scale,
				" min=", ui.character_panel.get_combined_minimum_size(), " grid=", ui.character_panel.find_child("BackpackGrid", true, false).size)
			expect("inventory fits: " + tag, get_viewport().get_visible_rect().encloses(ui.character_panel.get_global_rect()))
			expect("inventory keeps readable proportions: " + tag, ui.character_panel.size.y < ui.character_panel.size.x * 1.2)
			expect("town overlays do not cover inventory: " + tag, town.hud.overlay_rects.is_empty())
			await _capture("inventory_" + tag)
			var portrait: TextureRect = ui.character_panel.find_child("CharacterPortrait", true, false)
			if portrait != null:
				var physical := portrait.get_screen_transform()
				var pixels := portrait.size * Vector2(physical.x.length(), physical.y.length())
				expect("portrait renders at displayed pixels: " + tag, portrait.texture.get_size().x >= pixels.x and portrait.texture.get_size().y >= pixels.y)
			var grid: Control = ui.character_panel.find_child("BackpackGrid", true, false)
			var tile: Control = grid.tiles[0]
			var motion := InputEventMouseMotion.new()
			motion.position = tile.get_global_rect().get_center()
			get_viewport().push_input(motion, true)
			await _settle()
			expect("inventory item highlights on actual hover: " + tag, tile.hovered)
			var details: Control = tile.get_node("ItemDetails")
			expect("item tooltip is visible and inside viewport: " + tag, details.visible and get_viewport().get_visible_rect().encloses(details.get_child(0).get_global_rect()))
			await _capture("item_tooltip_" + tag)
			ui.open_skills()
			await _settle()
			expect("skills fit: " + tag, get_viewport().get_visible_rect().encloses(ui.character_panel.get_global_rect()))
			ui.character_panel._hide_detail()
			await _capture("skills_" + tag)
			var skill: Button = ui.character_panel.find_child("fortitude_plus", true, false)
			motion.position = Vector2(get_viewport().get_visible_rect().size.x - 2, 2)
			get_viewport().push_input(motion, true)
			await _settle()
			motion.position = skill.get_global_rect().get_center()
			get_viewport().push_input(motion, true)
			await _settle()
			expect("skill hover opens themed details: " + tag, ui.character_panel._detail.visible)
			expect("skill tooltip fits viewport: " + tag, get_viewport().get_visible_rect().encloses(ui.character_panel._detail.get_global_rect()))
			await _capture("skill_tooltip_" + tag)
			ui.character_panel._switch_tree("ranged")
			await _settle()
			ui.character_panel._hide_detail()
			expect("Thunderous Shot uses its own artwork", ui.character_panel.find_child("power_thunderous_shot", true, false).icon.resource_path == "res://assets/icons/thunderous_shot.png")
			await _capture("ranged_skills_" + tag)
			var thunder: Button = ui.character_panel.find_child("power_thunderous_shot", true, false)
			motion.position = thunder.get_global_rect().get_center()
			get_viewport().push_input(motion, true)
			await _settle()
			expect("Thunderous Shot hover details fit", ui.character_panel._detail.visible and get_viewport().get_visible_rect().encloses(ui.character_panel._detail.get_global_rect()))
			await _capture("thunderous_tooltip_" + tag)
			ui.close_character()
			await _settle()
			for hit in ui._slot_hits:
				if hit.id == "": continue
				ui.mouse_override = hit.rect.get_center()
				await _settle()
				await _capture("hotbar_tooltip_" + tag)
				break
			ui.mouse_override = Vector2(-1, -1)
			for page in ["stash", "board", "chronicle", "marlow"]:
				match page:
					"stash": town.panel.open_stash()
					"board": town.panel.open_board()
					"chronicle": town.panel.open_chronicle()
					_: town.panel.open_npc(page)
				await _settle()
				var service: Control = town.panel._box.get_parent().get_parent().get_parent()
				expect("town service fits: " + page + tag, get_viewport().get_visible_rect().encloses(service.get_global_rect()))
				await _capture(page + "_" + tag)
				town.panel.close()
			town.pause_menu.open()
			await _settle()
			await _capture("pause_" + tag)
			town.pause_menu._open_settings()
			await _settle()
			var settings := town.pause_menu._settings
			for tab in 4:
				settings.select_tab(tab)
				await _settle()
				print("THEME_SETTINGS ", tag, " tab=", tab, " rect=", settings.get_global_rect(), " scale=", settings.scale)
				expect("settings fit %d: %s" % [tab, tag], get_viewport().get_visible_rect().encloses(settings.get_global_rect()))
				await _capture("settings%d_" % tab + tag)
			town.pause_menu.close()
			town.player.dead = true
			await _settle()
			await _capture("death_" + tag)
			town.player.dead = false
			await _settle()
	GameSettings.ui_size = old_scale
	get_window().borderless = old_borderless
	get_window().current_screen = old_screen
	get_window().size = old_size
	GameSettings.apply_ui_scale()
	await _settle()
	town.player.dead = true
	await _settle()
	await _capture("death")
	town.player.dead = false
	town.pause_menu.open()
	await _settle()
	await _capture("pause")
	town.pause_menu.close()
	town.combat_hud.hide()
	town.hud.hide() # A production scene transition removes these before loading.
	var loading := LoadingScreen.new()
	loading.auto_switch = false
	town.add_child(loading)
	await _settle()
	await _capture("loading")
	# Finish the asynchronous preload before shutting down the test process.
	var preload_started := Time.get_ticks_msec()
	while not loading._finished and Time.get_ticks_msec() - preload_started < 20000:
		await get_tree().process_frame
	loading.queue_free()
	get_tree().paused = false
	town.queue_free()
	await _settle()
	hud.show()
	TownState.reset()
