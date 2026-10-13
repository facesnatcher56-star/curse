extends SceneTree
## Isolated actual-world presentation regression and native-resolution captures.
var failures := 0
func _init() -> void: call_deferred("run")
func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	TownState.persist = false
	TownState.reset()
	var town := TownScene.new()
	root.add_child(town)
	current_scene = town
	for frame in 300:
		await physics_frame
		if town.director != null and Nav.ready(town.player): break
	town.set_process(false)
	town.set_physics_process(false)
	for body in PartyManager.current().living(): body.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	var target := get_nodes_in_group("enemies")[0] as Enemy
	target.def = target.def.duplicate()
	target.def.tier = "normal"
	target.health = 7.56
	target.max_health = 7.56
	check("fractional full HP is 8 / 8, never 8 / 7", Ds2TargetBanner.health_text(7.56, 7.56) == "8 / 8")
	check("tiny positive HP stays visible", Ds2TargetBanner.health_text(0.01, 7.56) == "1 / 8")
	check("over-cap display clamps", Ds2TargetBanner.health_text(9, 7.56) == "8 / 8")
	target.max_health = 9999
	check("high HP alone is not elite", Ds2TargetBanner.status_of(target).is_empty())
	target.level = 99
	check("high level alone is not elite", Ds2TargetBanner.status_of(target).is_empty())
	target.def.tier = "miniboss"
	check("miniboss has gold status", Ds2TargetBanner.status_of(target) == "MINIBOSS")
	target.def.tier = "strong"
	target.set_meta("monster_uid", -1)
	check("named status overrides strong tier", Ds2TargetBanner.status_of(target) == "UNIQUE")
	target.remove_meta("monster_uid")
	target.def.tier = "normal"
	target.level = 1
	target.max_health = 7.56
	town.player.global_position = Nav.snap(town.player, target.global_position + Vector3(0, 0, 6))
	town.rig.global_position = town.player.global_position
	town.companion.global_position = town.player.global_position + Vector3(2, 0, 1)
	town.player.hover_target = target
	var banner: Ds2TargetBanner = town.combat_hud.ds2_target_banner
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.borderless = true
		root.current_screen = mini(1, DisplayServer.get_screen_count() - 1)
		root.size = Vector2i(1280, 720)
		root.position = DisplayServer.screen_get_position(root.current_screen)
		GameSettings.ui_size = 1.5
		GameSettings.apply_ui_scale()
		for frame in 2: await process_frame
	target.health = target.max_health * 0.5
	banner.update_target(target, 0.016)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var damage_capture := OS.get_environment("TEMP").path_join("curse_target_damage_trail.png")
		root.get_texture().get_image().save_png(damage_capture)
		print("CAPTURE ", damage_capture)
	target.health = target.max_health
	banner.update_target(target, 0.016)
	town.player.attack_target = target
	var ground_drop := LootDrop.create(Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "Falchion"))
	town.add_child(ground_drop)
	ground_drop.toss_from(target.global_position + Vector3(1.5, 0.0, 1.5))
	var level_toast: ProgressionHud = town.combat_hud.progression_hud
	level_toast.toast_text = "LEVEL 2"
	level_toast.toast_time = ProgressionHud.TOAST_SECONDS
	level_toast.toast_levels = 1
	for frame in 45: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var target_rect := banner.get_global_rect()
	var toast_rect := level_toast.toast_rect(banner.get_viewport_rect().size)
	check("level-up toast clears the target banner", not toast_rect.intersects(target_rect))
	var party_rect := town.combat_hud.ds2_party_frame.get_global_rect()
	var loot_plates_clear := true
	for entry in town.combat_hud.loot_cards.names:
		var plate: Rect2 = entry["rect"]
		if plate.grow(6.0).intersects(target_rect) or plate.grow(6.0).intersects(party_rect) or plate.intersects(toast_rect):
			loot_plates_clear = false
	check("loot name plates clear target, party frames, and level-up toast", not town.combat_hud.loot_cards.names.is_empty() and loot_plates_clear)
	if DisplayServer.get_name() != "headless":
		var overlay_capture := OS.get_environment("TEMP").path_join("curse_target_hud_overlays.png")
		root.get_texture().get_image().save_png(overlay_capture)
		print("CAPTURE ", overlay_capture)
	ground_drop.queue_free()
	town.player.attack_target = null
	level_toast.toast_time = 0.0
	for dimensions in GameSettings.RESOLUTIONS:
		if DisplayServer.get_name() != "headless":
			root.mode = Window.MODE_WINDOWED
			root.borderless = true
			root.current_screen = 0 if dimensions.y > 1080 else mini(1, DisplayServer.get_screen_count() - 1)
			root.size = dimensions
			root.position = DisplayServer.screen_get_position(root.current_screen)
		for multiplier in [0.5, 1.0, 1.5]:
			GameSettings.ui_size = multiplier
			GameSettings.apply_ui_scale()
			for kind in ["normal", "strong", "unique", "boss"]:
				target.def.tier = "strong" if kind == "strong" else "normal"
				target.is_boss = kind == "boss"
				if target.has_meta("quest_uid"): target.remove_meta("quest_uid")
				if kind == "unique": target.set_meta("quest_uid", -1)
				target.display_name = "Gorran the Hollow, Slayer of 2" if kind == "unique" else ("Graveyard Warden" if kind == "boss" else "Restless Dead")
				for frame in 8: await process_frame
				banner.update_target(target, 1.0)
				check("status " + kind, Ds2TargetBanner.status_of(target) == {"normal": "", "strong": "STRONG", "unique": "UNIQUE", "boss": "BOSS"}[kind])
				check("name color " + kind, banner._name_label.get_theme_color("font_color") == Ds2TargetBanner.status_color(target))
				check("banner fits viewport", root.get_visible_rect().encloses(banner.get_global_rect()))
				check("HP text fits", banner._health_label.get_minimum_size().x <= banner._health_label.size.x)
				check("name fits", banner._name_label.get_theme_font("font").get_string_size(banner._name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, banner._name_label.get_theme_font_size("font_size")).x <= banner._name_label.size.x)
				check("HP has at least 16 physical pixels", banner._health_label.get_theme_font_size("font_size") * banner.scale.x * root.size.x / root.get_visible_rect().size.x >= 16.0)
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					var path := OS.get_environment("TEMP").path_join("curse_target_%dx%d_%.1f_%s.png" % [dimensions.x, dimensions.y, multiplier, kind])
					root.get_texture().get_image().save_png(path)
					print("CAPTURE ", path)
			# Check real menu layering with a committed target still selected.
			town.player.attack_target = target
			town.combat_hud._open_character()
			for frame in 8: await process_frame
			check("inventory above target decoration", town.combat_hud.character_panel.z_index > banner.z_index)
			check("target decoration never intercepts menu input", banner.mouse_filter == Control.MOUSE_FILTER_IGNORE)
			check("target banner hidden beneath paused menus", not banner.visible)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("curse_target_%dx%d_%.1f_inventory.png" % [dimensions.x, dimensions.y, multiplier]))
			town.combat_hud.close_character()
			town.player.attack_target = null
	print("TARGET HUD failures=", failures)
	quit(1 if failures else 0)
