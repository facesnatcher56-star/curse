extends DevSuite
## Reproducible six-second gameplay-context preview. Staged presentation events;
## uses the live popup entry point without changing damage, XP, or save data.

func _test_damage_number_presentation() -> void:
	var was_shown := GameSettings.show_damage_numbers
	var before := get_tree().get_nodes_in_group(DamageNumber.GROUP).size()
	GameSettings.show_damage_numbers = false
	Fx.popup(player, Combat.Outcome.CRITICAL, 248.0)
	Fx.damage_tick(player, 12.0, Color.ORANGE)
	Fx.popup(player, Combat.Outcome.HIT, 900.0, Color.TRANSPARENT, "brutal_attack")
	expect("damage-number setting suppresses direct hits and ticks", get_tree().get_nodes_in_group(DamageNumber.GROUP).size() == before)
	GameSettings.show_damage_numbers = true
	Fx.popup(player, Combat.Outcome.HIT, 37.4)
	Fx.popup(player, Combat.Outcome.CRITICAL, 248.0)
	Fx.damage_tick(player, 12.2, Color.ORANGE)
	Fx.popup(player, Combat.Outcome.MISS, 0.0)
	Fx.popup(player, Combat.Outcome.BLOCK, 0.0)
	var numbers := get_tree().get_nodes_in_group(DamageNumber.GROUP).slice(before)
	expect("each staged outcome creates independent feedback", numbers.size() == 5)
	if numbers.size() == 5:
		var normal := numbers[0].get_child(1) as Label3D
		var critical := numbers[1].get_child(1) as Label3D
		var tick := numbers[2].get_child(1) as Label3D
		expect("number styling preserves rounded resolved values and tick tint", normal.text == "37" and critical.text == "248" and tick.text == "12" and tick.modulate == Color.ORANGE)
		expect("critical remains identified and more prominent", critical.font_size > normal.font_size and (numbers[1].get_child(2) as Label3D).text == "CRITICAL")
		expect("avoided attacks show their outcome without damage values", (numbers[3].get_child(1) as Label3D).text == "Dodge" and (numbers[4].get_child(1) as Label3D).text == "Block")
	for id in ["brutal_attack", "take_aim", "flame_nexus"]:
		Fx.popup(player, Combat.Outcome.HIT, 1250.4, Color.TRANSPARENT, id)
	var powers := get_tree().get_nodes_in_group(DamageNumber.GROUP).slice(before + 5)
	expect("melee, ranged and spell ultimates share dramatic resolved damage numbers", powers.size() == 3 and powers.all(func(number) -> bool: return (number.get_child(1) as Label3D).text == "1250" and (number.get_child(1) as Label3D).font_size == 86 and (number.get_child(2) as Label3D).text == "ULTIMATE"))
	Fx.popup(player, Combat.Outcome.CRITICAL, 2750, Color.TRANSPARENT, "take_aim")
	var power_crit: Node = get_tree().get_nodes_in_group(DamageNumber.GROUP).back()
	expect("ultimate criticals retain critical identity", (power_crit.get_child(2) as Label3D).text == "ULTIMATE CRITICAL" and (power_crit.get_child(1) as Label3D).font_size == 100)
	Fx.popup(player, Combat.Outcome.BLOCK, 0, Color.TRANSPARENT, "brutal_attack")
	var avoided: Node = get_tree().get_nodes_in_group(DamageNumber.GROUP).back()
	expect("an avoided ultimate keeps the ordinary Block feedback", avoided.get_child_count() == 2 and (avoided.get_child(1) as Label3D).text == "Block")
	await get_tree().create_timer(1.5).timeout
	expect("combat feedback cleans itself up after its hold and fade", numbers.all(func(number) -> bool: return not is_instance_valid(number)))
	expect("ultimate damage numbers clean up after their longer hold", powers.all(func(number) -> bool: return not is_instance_valid(number)) and not is_instance_valid(power_crit))
	GameSettings.show_damage_numbers = was_shown

func _damage_number_capture() -> void:
	TownState.persist = false
	GameSettings.show_damage_numbers = true
	GameSettings.ui_size = 1.0
	GameSettings.apply_ui_scale()
	for node in get_tree().get_nodes_in_group("enemies"): node.queue_free()
	for body in PartyManager.current().bodies.values():
		if is_instance_valid(body): body.set_physics_process(false)
	await get_tree().process_frame
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	var foe := _spawn_enemy(Vector3(1.7, 0, 0.5))
	foe.set_physics_process(false)
	foe.aggro_range = 0.0
	foe.max_health = 1000.0
	foe.health = 1000.0
	if is_instance_valid(game.companion):
		game.companion.global_position = Vector3(-2.2, 0, 1.2)
		game.companion.reset_physics_interpolation()
	rig.target = player
	rig.set_zoom_now(0.9)
	var title := Label.new()
	var view_size := get_viewport().get_visible_rect().size
	title.position = Vector2(0, view_size.y - 165)
	title.size = Vector2(view_size.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(title)
	var out_dir := ProjectSettings.globalize_path("res://.dev_output/damage_number_styled_frames")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(0.3).timeout
	for frame in 360:
		match frame:
			0:
				title.text = "DAMAGE NUMBERS | Staged feedback in gameplay"
			20, 48:
				title.text = "Normal hits"
				Fx.popup(foe, Combat.Outcome.HIT, 37.0 if frame == 20 else 124.0)
			90:
				title.text = "Critical hit"
				Fx.popup(foe, Combat.Outcome.CRITICAL, 248.0)
			150, 174:
				title.text = "Elemental damage"
				Fx.damage_tick(foe, 12.0, Color(1.0, 0.55, 0.12))
			210:
				title.text = "Avoided attacks"
				Fx.popup(foe, Combat.Outcome.MISS, 0.0)
			234:
				Fx.popup(foe, Combat.Outcome.BLOCK, 0.0)
			270:
				title.text = "Damage received"
				Fx.popup(player, Combat.Outcome.HIT, 19.0, player._popup_tint())
			300, 312, 324:
				title.text = "Rapid hits"
				Fx.popup(foe, Combat.Outcome.CRITICAL if frame == 324 else Combat.Outcome.HIT, 86.0 if frame == 324 else 43.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(out_dir.path_join("frame_%04d.jpg" % frame), 0.97)
	print("DAMAGE_NUMBER_CAPTURE frames=360 path=", out_dir)
	get_tree().quit()
