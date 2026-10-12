extends SceneTree
## Captures real common-character HUD/menu contexts; images require personal review.
func _init() -> void:
	call_deferred("run")

func settle() -> void:
	await create_timer(0.25, true).timeout
	await RenderingServer.frame_post_draw

func capture(tag: String) -> void:
	await settle()
	var path := OS.get_environment("TEMP").path_join("curse_party_" + tag + ".png")
	root.get_texture().get_image().save_png(path)
	print("PARTY_CAPTURE ", path)

func run() -> void:
	TownState.persist = false
	TownState.reset()
	var game := load("res://game/main.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await create_timer(1.0).timeout
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	for body in PartyManager.current().bodies.values(): body.set_physics_process(false)
	for resolution in GameSettings.RESOLUTIONS:
		var screen: int = 0 if resolution.y > 1080 else mini(1, DisplayServer.get_screen_count() - 1)
		root.current_screen = screen
		root.borderless = true
		root.size = resolution
		root.position = DisplayServer.screen_get_position(screen) + (DisplayServer.screen_get_size(screen) - resolution).max(Vector2i.ZERO) / 2
		for multiplier in [0.5, 1.0, 1.5]:
			GameSettings.ui_size = multiplier
			GameSettings.apply_ui_scale()
			var tag := "%dx%d_scale%s" % [resolution.x, resolution.y, str(multiplier)]
			await capture("hud_" + tag)
			for member_id in ["hero", "cutter"]:
				PartyManager.current().select(member_id)
				game.hud._open_character()
				await capture(member_id + "_inventory_" + tag)
				game.hud.open_skills()
				await settle()
				game.hud.character_panel._switch_tree("ranged")
				await settle()
				var button := game.hud.character_panel.find_child("power_take_aim", true, false) as Button
				if button != null:
					button.grab_focus()
					Input.warp_mouse(button.get_global_rect().get_center() * root.content_scale_factor)
				await capture(member_id + "_skills_" + tag)
				game.hud.close_character()
	print("PARTY VISUAL CAPTURES COMPLETE (review required)")
	quit()
