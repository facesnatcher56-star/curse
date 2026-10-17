extends DevSuite
## Take Aim's whole sequence with Cutter, in the live game: activation, the held shot (he walks, nothing fires), a real
## empowered arrow into a living target, and a second one into a lethal target. Run with --movie for a 60 FPS recording:
##   Godot --path . --write-movie out.avi --fixed-fps 60 --resolution 1920x1080 res://game/main.tscn -- --takeaimcapture [--close]

func _take_aim_capture() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.add_member_xp("cutter", HeroProgression.xp_for_level(11), false, {"ranged": 1.0})
	var bought: bool = TownState.buy_passives({"critical_shot": 1}, "cutter")
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	_prepare_archer(archer)
	var lane: Vector3 = await _own_lane(26.0, 8.0)
	var close := OS.get_cmdline_user_args().has("--close")
	archer.testing_disabled = false
	player.global_position = lane + Vector3(-6.0, 0.0, 3.0)
	player.reset_physics_interpolation()
	archer.global_position = lane
	archer.reset_physics_interpolation()
	archer.stats.refresh()
	archer.bow.reload_remaining = 0.0
	archer.bow.armed = false
	rig.target = archer
	rig.global_position = archer.global_position
	rig.set_zoom_now(0.34 if close else 1.0)
	await get_tree().create_timer(3.5).timeout   # the level-up flourish from the fixture's XP is over
	var title := Label.new()
	var view_size := get_viewport().get_visible_rect().size
	title.position = Vector2(0, view_size.y - 120)
	title.size = Vector2(view_size.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	hud.add_child(title)
	print("TAKE_AIM_CAPTURE bought=", bought, " rank=", PowerDb.hero_rank("take_aim", "cutter"), " ranged=", archer.stats.is_ranged(), " can=", archer.stats.can_use("take_aim"))
	var out := ProjectSettings.globalize_path("res://.dev_output/ta_frames" + ("_close" if close else ""))
	DirAccess.make_dir_recursive_absolute(out)
	var foe: Enemy
	var report := {"held_no_shot": true, "arrow_seen": false, "nonlethal": false, "lethal": false, "cleared": false}
	for frame in 720:
		match frame:
			30:
				title.text = "TAKE AIM | Activation: Hunter's Focus"
				archer.activate_take_aim_now()
			170:
				title.text = "EMPOWERED | Cutter walks, the shot is held - no auto fire"
			175:
				pass
			330:
				title.text = "EMPOWERED SHOT | Nonlethal target"
				foe = _victim(lane + Vector3(8.6, 0.0, 0.0), 10000.0)
				archer.bow.start(foe)
			500:
				report["nonlethal"] = is_instance_valid(foe) and not foe.dead and foe.health < foe.max_health
				report["cleared"] = archer.bow.aura == null or not is_instance_valid(archer.bow.aura)
				title.text = "POWER SPENT | Focus gone, ordinary arrows"
				if is_instance_valid(foe): foe.queue_free()
			540:
				title.text = "REARMED | Lethal target, existing gibbing"
				archer.bow.reload_remaining = 0.0
				archer.activate_take_aim_now()
				foe = _victim(lane + Vector3(8.6, 0.0, 0.0), 1.0)
			600:
				archer.bow.start(foe)
		if frame >= 30 and frame < 170:
			report["held_no_shot"] = report["held_no_shot"] and archer.bow.armed
		if frame >= 175 and frame < 215:
			archer.move_with(Vector3.RIGHT * 0.9)
		if frame % 30 == 0 and frame >= 330:
			print("DBG f=", frame, " foe=", foe.global_position if is_instance_valid(foe) else "gone", " archer=", archer.global_position, " shots=", archer.bow.shots, " busy=", archer.skills.busy, " armed=", archer.bow.armed, " tgt=", archer.attack_target, " refusals=", archer.bow.refusals)
		rig.global_position = archer.global_position.lerp(foe.global_position, 0.5) if (is_instance_valid(foe) and frame >= 330 and not close) else archer.global_position
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(out.path_join("frame_%04d.jpg" % frame), 0.95)
	report["lethal"] = is_instance_valid(foe) == false or foe.dead
	print("TAKE_AIM_CAPTURE report=", report, " gibs=", get_tree().get_nodes_in_group("gibs").size())
	get_tree().quit()

func _user_arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return arg.trim_prefix(prefix)
	return ""

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

## Only the lethal shot, framed wide enough to hold Cutter, the arrow's whole flight and the target (see _take_aim_capture for setup).
func _take_aim_lethal_capture() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.add_member_xp("cutter", HeroProgression.xp_for_level(11), false, {"ranged": 1.0})
	TownState.buy_passives({"critical_shot": 1}, "cutter")
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	_prepare_archer(archer)
	var lane: Vector3 = await _own_lane(26.0, 8.0)
	archer.testing_disabled = false
	player.global_position = lane + Vector3(-6.0, 0.0, 3.0)
	player.reset_physics_interpolation()
	archer.global_position = lane
	archer.reset_physics_interpolation()
	archer.stats.refresh()
	archer.bow.reload_remaining = 0.0
	archer.bow.armed = false
	var pivot := Node3D.new()   # the camera looks at the middle of the shot, so Cutter, the whole flight and the target all stay in frame
	game.add_child(pivot)
	rig.target = pivot
	pivot.global_position = lane + Vector3(4.3, 0.0, 0.0)
	rig.set_zoom_now(float(_user_arg_value("--zoom=")) if _user_arg_value("--zoom=") != "" else 1.15)
	await get_tree().create_timer(3.5).timeout   # the level-up flourish from the fixture's XP is over
	var out := ProjectSettings.globalize_path("res://.dev_output/ta_lethal_frames")
	DirAccess.make_dir_recursive_absolute(out)
	var foe := _victim(lane + Vector3(8.6, 0.0, 0.0), 1.0)
	var bystander := _victim(lane + Vector3(21.0, 0.0, 6.0), 100000.0)   # keeps the wave open, so no "Wave cleared" banner covers the kill
	for frame in 520:
		match frame:
			10: archer.activate_take_aim_now()
			60: archer.bow.start(foe)
		pivot.global_position = lane + Vector3(4.3, 0.0, 0.0)
		if frame in [186, 190, 200, 230]:
			for node in get_tree().current_scene.get_children():
				if node.name.begins_with("TakeAim") and node is CPUParticles3D:
					print("DBG f=", frame, " ", node.name, " emitting=", node.emitting, " pos=", (node as Node3D).global_position, " visible=", (node as Node3D).visible)
		if frame >= 170:
			for orb in get_tree().get_nodes_in_group("orbs") + get_tree().get_nodes_in_group("loot"):
				orb.queue_free()
		if frame >= 55 and frame <= 200 and frame % 8 == 0:
			var sk: Skeleton3D = archer.model.find_children("*", "Skeleton3D", true, false)[0]
			var yaws := []
			for bone_name in ["Hips", "Spine", "Spine01", "Spine02", "Head", "LeftArm", "RightArm"]:
				var gb: Basis = sk.global_basis * sk.get_bone_global_pose(sk.find_bone(bone_name)).basis
				yaws.append(snappedf(rad_to_deg(atan2(gb.z.x, gb.z.z)), 1.0))
			print("YAW f=", frame, " H/S/S1/S2/Head/LA/RA=", yaws, " anim=", archer.model.current, " t=", snappedf(archer.model.anim.current_animation_position, 0.01), " spd=", archer.model.anim.speed_scale)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(out.path_join("frame_%04d.jpg" % frame), 0.95)
	print("TAKE_AIM_LETHAL dead=", foe.dead, " gibs=", get_tree().get_nodes_in_group("gibs").size(), " armed=", archer.bow.armed)
	get_tree().quit()

## Thunderous Shot's visuals only (the power is not built): a long draw and a bolt through three enemies in a row, framed wide.
func _thunderous_capture() -> void:
	TownState.persist = false
	TownState.reset()
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	_prepare_archer(archer)
	var lane: Vector3 = await _own_lane(30.0, 8.0)
	archer.testing_disabled = false
	player.global_position = lane + Vector3(-6.0, 0.0, 3.0)
	player.reset_physics_interpolation()
	archer.global_position = lane
	archer.reset_physics_interpolation()
	archer.stats.refresh()
	var pivot := Node3D.new()
	game.add_child(pivot)
	rig.target = pivot
	var close := OS.get_cmdline_user_args().has("--close")
	var real := OS.get_cmdline_user_args().has("--power")   # the real power through the hotbar path, with real damage and stun
	if real:
		TownState.add_member_xp("cutter", HeroProgression.xp_for_level(11), false, {"ranged": 1.0})
		TownState.buy_passives({"critical_shot": 1}, "cutter")
		TownState.buy_passives({"biting_arrow": 1}, "cutter")
		archer.stats.refresh()
		GameSettings.hotbar_slots[2] = "thunderous_shot"
		GameSettings.hotbar_casters[2] = "cutter"
	pivot.global_position = lane + Vector3(7.0, 0.0, 0.0)
	rig.set_zoom_now(0.6 if close else 1.25)
	await get_tree().create_timer(1.0).timeout
	var out := ProjectSettings.globalize_path("res://.dev_output/thunder_frames" + ("_close" if close else ""))
	DirAccess.make_dir_recursive_absolute(out)
	var first := _victim(lane + Vector3(8.0, 0.0, 0.0), 100000.0)
	var second := _victim(lane + Vector3(11.5, 0.0, 0.0), 100000.0)
	var last := _victim(lane + Vector3(15.0, 0.0, 0.0), 1.0 if real else 100000.0)   # one life: dies of the real shot
	var aside := _victim(lane + Vector3(19.0, 0.0, 6.0), 100000.0)   # off the line: untouched
	if real:
		# Let them run their own logic (idle, aggro 0) so the game's own stun shows: they stop, flinch and the daze stars circle.
		for foe in [first, second, last, aside]:
			foe.set_physics_process(true)
	if not real:
		archer.bow.thunder_visual = true
	var aim_demo := OS.get_cmdline_user_args().has("--aim")   # hold the key: the casting area follows the cursor, then let go
	var cursor_at := lane + Vector3(3.0, 0.0, 6.0)
	for frame in 640:
		if aim_demo:
			# The real input path: the mouse is moved over the world point and the hotbar key held. The cursor starts off to the side (nothing
			# on the line), sweeps over the line of enemies, rests on the first, and then the key is let go.
			if frame >= 20 and frame < 230:
				var u: float = clampf(float(frame - 20) / 150.0, 0.0, 1.0)
				cursor_at = (lane + Vector3(3.0, 0.0, 6.0)).lerp(lane + Vector3(17.0, 0.0, 0.2), u)
				if u > 0.85:
					cursor_at = first.global_position
				player.cursor_override = cursor_at   # the controlled hero's cursor: the same value the mouse would give
				player.hover_target = first if u > 0.85 else null
			if frame == 20:
				Input.action_press("skill_3")
			if frame == 230:
				Input.action_release("skill_3")
		match frame:
			20:
				if real and not aim_demo:
					print("THUNDEROUS_POWER activated=", archer.powers.activate("thunderous_shot", first.global_position))
				elif not real:
					archer.bow.start(first)
			232:
				if aim_demo:
					print("THUNDEROUS_AIM released busy=", archer.skills.busy, " thunder_power=", archer.bow.thunder_power, " shots=", archer.bow.shots)
		pivot.global_position = lane + Vector3(7.0, 0.0, 0.0)
		if frame >= 100:
			for orb in get_tree().get_nodes_in_group("orbs") + get_tree().get_nodes_in_group("loot"):
				orb.queue_free()   # the kill's health orb and loot are the game's, not part of the effect: keep them out of the recording
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(out.path_join("frame_%04d.jpg" % frame), 0.95)
	var stunned := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.find_children("ThunderousStun", "Node3D", false, false).size() > 0: stunned += 1
	print("THUNDEROUS_STUN first_stun=", snappedf(first.stun_time, 0.01), " second_stun=", snappedf(second.stun_time, 0.01), " aside_stun=", snappedf(aside.stun_time, 0.01))
	print("THUNDEROUS_CAPTURE stunned_markers=", stunned, " shots=", archer.bow.shots, " real=", real, " last_dead=", last.dead if is_instance_valid(last) else "gone", " ready=", archer.powers.ready("thunderous_shot"), " charge=", snappedf(archer.powers.fraction("thunderous_shot"), 0.01))
	get_tree().quit()
