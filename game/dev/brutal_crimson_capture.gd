extends DevSuite
## Real empowered swings, one nonlethal and one lethal, at 1080p/60 FPS.

func _test_crimson_fx() -> void:
	player.set_physics_process(false)
	var crimson := BrutalAttackFx.new()
	player.add_child(crimson)
	crimson.setup(player.model)
	expect("Brutal Attack creates the full crimson gathering effect", crimson.crimson and crimson.get_node_or_null("CrimsonGathering") != null)
	var flow := crimson.get_node("CrimsonGathering") as BrutalCrimsonFx
	var base := player.model.weapon_base
	var tip := player.model.weapon_tip
	expect("crimson energy converges on the held weapon", flow.to_global(flow.weapon_destination(1)).distance_to(base.global_position.lerp(tip.global_position, 0.6)) < 0.001)
	var replacement := Node3D.new()
	player.add_child(replacement)
	replacement.global_position = tip.global_position + Vector3(1, 0.5, 0)
	player.model.weapon_tip = replacement
	expect("gathering follows a replacement weapon marker", flow.to_global(flow.weapon_destination(1)).distance_to(base.global_position.lerp(replacement.global_position, 0.6)) < 0.001)
	player.model.weapon_tip = tip
	replacement.queue_free()
	var orange := BrutalAttackFx.new()
	player.add_child(orange)
	orange.setup(player.model, false)
	expect("Take Aim's shared aura remains orange without crimson ribbons", not orange.crimson and orange.get_node_or_null("CrimsonGathering") == null and orange.get_node_or_null("ChargeGather") == null)
	crimson.queue_free()
	orange.queue_free()
	Fx._recent_impacts.clear()
	var at := player.global_position + Vector3(4, 0, 0)
	SkillFx.brutal_impact(player, at, Vector3.RIGHT, 3)
	var count := get_tree().get_nodes_in_group(BrutalCrimsonFx.GROUP).size()
	SkillFx.brutal_impact(player, at, Vector3.RIGHT, 3)
	expect("a landed hit creates one Meshy rupture and rejects duplicate reports", count == 6 and get_tree().get_nodes_in_group(BrutalCrimsonFx.GROUP).size() == count)
	await get_tree().create_timer(0.6).timeout
	expect("rupture meshes and contact seam clean up", get_tree().get_nodes_in_group(BrutalCrimsonFx.GROUP).is_empty())

func _brutal_crimson_capture() -> void:
	TownState.persist = false
	TownState.reset()
	GameSettings.ui_size = 1.0
	GameSettings.apply_ui_scale()
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	for body in PartyManager.current().bodies.values():
		if is_instance_valid(body): body.set_physics_process(false)
	await get_tree().process_frame
	TownState.passive_ranks = {"critical_strike": 8, "overbear": 1, "barricade": 1}
	for item in Items.starting_gear(): player.stats.equip(item, false)
	player.stats.refresh()
	player.skills.reset()
	player.attack_target = null
	player.hover_target = null
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	if is_instance_valid(game.companion):
		game.companion.global_position = Vector3(-3.5, 0, 1)
		game.companion.reset_physics_interpolation()
	var foe := _victim(Vector3(1.8, 0, 0.6), 10000.0)
	rig.target = player
	rig.set_zoom_now(1.15)
	var title := Label.new()
	var view_size := get_viewport().get_visible_rect().size
	title.position = Vector2(0, view_size.y - 165)
	title.size = Vector2(view_size.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	hud.add_child(title)
	var out := ProjectSettings.globalize_path("res://.dev_output/brutal_crimson_frames")
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(0.3).timeout
	for frame in 480:
		# The actor is held still, but its ordinary attack cooldown must still tick.
		for id in player.stats.cooldowns:
			player.stats.cooldowns[id] = maxf(float(player.stats.cooldowns[id]) - 1.0 / 60.0, 0.0)
		match frame:
			0:
				title.text = "BRUTAL ATTACK | Crimson activation and armed energy"
				player.stats.brutal_reload_remaining = 0.0
				player.skills.activate_brutal_attack()
			60:
				title.text = "EMPOWERED SWING | Real contact, nonlethal target"
				player.skills.start_skill("basic", foe)
			170:
				if foe.dead or foe.health >= foe.max_health or player.skills.brutal_armed:
					push_error("Crimson preview: nonlethal empowered contact did not complete")
					get_tree().quit(1)
					return
				title.text = "POWER SPENT | Body aura and swing wake clear"
			220:
				title.text = "REARMED | Second real strike, lethal target"
				foe.queue_free()
				foe = _victim(Vector3(1.8, 0, 0.6), 1.0)
				player.skills.cancel_action()
				# Completed actions retain their target; this fixture is replacing it.
				player.skills.busy_target = null
				player.attack_target = null
				player.hover_target = null
				player.stats.brutal_reload_remaining = 0.0
				player.skills.activate_brutal_attack()
			270:
				player.skills.start_skill("basic", foe)
			380:
				if not foe.dead or player.skills.brutal_armed or get_tree().get_nodes_in_group("gibs").is_empty():
					push_error("Crimson preview: lethal contact failed dead=%s armed=%s gibs=%d health=%s" % [foe.dead, player.skills.brutal_armed, get_tree().get_nodes_in_group("gibs").size(), foe.health])
					get_tree().quit(1)
					return
				title.text = "LETHAL RUPTURE | Existing lethal-power gibbing preserved"
		if player.skills.busy:
			player.skills.tick_busy(1.0 / 60.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(out.path_join("frame_%04d.jpg" % frame), 0.97)
	print("BRUTAL_CRIMSON_CAPTURE frames=480 path=", out)
	get_tree().quit()

func _victim(at: Vector3, health: float) -> Enemy:
	var foe := _spawn_enemy(at)
	foe.set_physics_process(false)
	foe.aggro_range = 0.0
	foe.max_health = health
	foe.health = health
	foe.armor = 0.0
	foe.dodge_chance = 0.0
	foe.block_chance = 0.0
	return foe
