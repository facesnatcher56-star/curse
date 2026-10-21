extends DevSuite
## Hotbar "lit" rule (issue #97): a power slot looks ready only when learned, usable and fully charged; a dead caster's slots stay dark;
## a resting mouse never makes a slot look ready. Optional 1080p captures: set HOTBAR_SHOTS to a folder.

func _settle() -> void:
	for i in 4: await get_tree().process_frame

func _shot(name: String) -> void:
	var dir: String = OS.get_environment("HOTBAR_SHOTS")
	if dir == "" or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))

func _test_hotbar_ready() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.dev_set_hero_level(40)
	var cost: float = player.stats.ult_cost("brutal_attack")
	player.stats.brutal_reload_required = cost
	var learned: bool = Hud._power_frame_available(player, "brutal_attack")
	var forge := hud._power_hotkey_vfx[0] as PowerHotkeyVfx
	await _settle()
	print("HOTBAR start state: charge=%.2f lit=%s" % [player.stats.ult_fraction("brutal_attack"), Hud.slot_lit(player, "brutal_attack")])
	await _shot("1_start")
	player.stats.brutal_reload_remaining = cost * 0.5
	await _settle()
	expect("mid-charge: not lit, no ready pulse, icon only half filled", not Hud.slot_lit(player, "brutal_attack") and not forge._ready_now
		and is_equal_approx(float(forge._icon_material.get_shader_parameter("fill")), 0.5))
	await _shot("2_mid_charge")
	player.stats.brutal_reload_remaining = 0.0
	await _settle()
	expect("ready: lit and pulsing exactly when learned", Hud.slot_lit(player, "brutal_attack") == learned and forge._ready_now == learned)
	await get_tree().create_timer(0.3).timeout
	await _shot("3_just_filled")
	await get_tree().create_timer(1.6).timeout
	await _shot("4_ready")
	expect("a dead caster's slot is never lit", not Hud.slot_lit(player, "take_aim", true) and not Hud.slot_lit(null, "take_aim"))
	var cutter := player.stats._cutter()
	if cutter != null:
		cutter.dead = true
		await _settle()
		await _shot("5_cutter_dead")
		cutter.dead = false
	player.stats.brutal_reload_remaining = cost * 0.5
	await _settle()
	var rect: Rect2 = hud._slot_hits[0]["rect"]
	hud.mouse_override = rect.get_center()
	await _settle()
	expect("a resting mouse on a charging slot is not ready", not forge._ready_now and is_equal_approx(float(forge._icon_material.get_shader_parameter("fill")), 0.5))
	await _shot("6_mouse_resting")
	hud.mouse_override = Vector2(-1, -1)
