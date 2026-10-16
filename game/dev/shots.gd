extends DevSuite
## Screenshot, pose and clip-sheet tools (--skillshot=, --aimshot, --hudshot, --poses, --clipsheet= ...).

## `-- --pauseshot`: open the pause menu over a live wave and capture it.
func _pause_shot() -> void:
	_next_wave()
	await get_tree().create_timer(0.8).timeout
	pause_menu.open()
	await get_tree().create_timer(0.4).timeout
	print("paused=", get_tree().paused, " menu open=", pause_menu.is_open())
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_pause.png")
	pause_menu.close()
	print("paused after resume=", get_tree().paused)
	get_tree().quit()

## `-- --enemyfight`: the new enemy kinds in action against an idle hero; frames in %TEMP%/curse_fight_N.png.
func _enemy_fight() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.max_health = 5000.0
	player.health = 5000.0
	var kinds: Array = [["spitter", Vector3(-6, 0, -8)], ["ghoul", Vector3(7, 0, -6)], ["bloater", Vector3(1.5, 0, -6)],
		["priest", Vector3(0, 0, -11)], ["zombie", Vector3(-1.5, 0, -11.5)], ["zombie", Vector3(1.5, 0, -11.0)]]
	for k in kinds:
		var z: Enemy = _spawn_enemy(k[1], k[0])
		z.aggro_range = 40.0
	for i in 16:
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_fight_%d.png" % i)
	get_tree().quit()

## `-- --archershot`: frozen draw stages and Take Aim flight; frames in %TEMP%/curse_archer_pose_*.png and curse_archer_power_*.png.
func _archer_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0.0, 0.0, 3.0)
	player.visible = false   # leave the frame to Cutter; enemies still hunt this idle target
	player.max_health = 5000.0
	player.health = player.max_health
	rig.target = game.companion
	rig.set_zoom_now(CameraRig.ZOOM_MIN)
	game.companion.testing_disabled = false
	game.companion.global_position = Vector3(0.0, 0.0, -1.0)
	for pos in [Vector3(-4.0, 0, -10.0), Vector3(0.0, 0, -12.0), Vector3(4.0, 0, -10.5)]:
		var enemy: Enemy = _spawn_enemy(pos)
		enemy.set_physics_process(false)
		enemy.target = player
		enemy.aggro_range = 50.0
		enemy.wake()
	var archer: ArcherCompanion = game.companion
	archer.set_physics_process(false)
	archer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	archer.visual.rotation.y = 0.0
	rig.global_position = archer.global_position
	rig.set_process(false)
	rig.camera.position = Vector3(2.4, 2.3, 3.2)
	rig.camera.look_at(archer.global_position + Vector3.UP * 1.1)
	print("ARCHER screens=", DisplayServer.get_screen_count(), " root mode=", get_tree().root.mode)
	for clip in ["walk", "run"]:
		archer.bow._draw = 0.0
		archer.bow._release = 0.0
		archer.model.manual(clip)
		for phase in [0.0, 0.25, 0.50, 0.75]:
			archer.model.scrub(phase)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var carry_image: Image = get_viewport().get_texture().get_image()
			carry_image.resize(1280, 720)
			carry_image.save_png(OS.get_environment("TEMP") + "/curse_archer_carry_%s_%d.png" % [clip, int(phase * 100)])
	for progress in [0.20, 0.50, 0.92]:
		archer.bow._draw = progress
		archer.bow._draw_arrow.visible = true
		archer.model.manual("idle")
		archer.model.scrub(0.0)
		print("ARCHER pose=", progress, " left=", archer.bow._skeleton.to_global(archer.bow._skeleton.get_bone_global_pose(int(archer.bow._pose_bones["LeftHand"])).origin), " right=", archer.bow._skeleton.to_global(archer.bow._skeleton.get_bone_global_pose(int(archer.bow._pose_bones["RightHand"])).origin))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.resize(1280, 720)
		image.save_png(OS.get_environment("TEMP") + "/curse_archer_pose_%d.png" % int(progress * 100))
	# Side view of the bow (a temporary camera on the archer's own right side): the string should sit between the bow and his face,
	# and the belly should face the way he shoots. Carry (walk) and draw poses.
	var side_cam := Camera3D.new()
	add_child(side_cam)
	side_cam.make_current()
	var side_dir: Vector3 = archer.visual.global_basis.x.normalized()
	for mode in ["carry", "draw"]:
		if mode == "carry":
			archer.bow._draw = 0.0
			archer.bow._release = 0.0
			archer.model.manual("walk")
			archer.model.scrub(0.25)
		else:
			archer.bow._draw = 0.92
			archer.bow._draw_arrow.visible = true
			archer.model.manual("idle")
			archer.model.scrub(0.0)
		side_cam.global_position = archer.global_position + side_dir * 1.7 + Vector3.UP * 1.25
		side_cam.look_at(archer.global_position + Vector3.UP * 1.2, Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var side_image: Image = get_viewport().get_texture().get_image()
		side_image.save_png(OS.get_environment("TEMP") + "/curse_archer_side_%s.png" % mode)
	side_cam.current = false
	rig.camera.make_current()
	print("ARCHER SIDESHOT done")
	archer.target = get_tree().get_nodes_in_group("enemies")[0] as Enemy
	archer.target.global_position = archer.global_position + Vector3(0.0, 0.0, 10.0)
	archer.take_aim_armed = true
	archer.bow._draw = 1.0
	archer.model.scrub(0.0)
	archer.bow.loose()
	for i in 5:
		await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.resize(1280, 720)
		image.save_png(OS.get_environment("TEMP") + "/curse_archer_power_%d.png" % i)
	print("ARCHERSHOT done: draw stages and Take Aim flight captured")
	get_tree().quit()

## `-- --takeaimshot`: visual test of Take Aim targeting cursor, hovering an enemy, and firing.
func _take_aim_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(-0.5, 0.0, 1.8)
	player.reset_physics_interpolation()
	var archer: ArcherCompanion = game.companion
	archer.testing_disabled = false
	archer.global_position = Vector3(1.8, 0.0, 3.2)
	archer.reset_physics_interpolation()
	archer.take_aim_reload_remaining = 0.0
	archer.take_aim_armed = false
	var enemy: Enemy = _spawn_enemy(Vector3(0.2, 0.0, -0.6), "zombie")
	enemy.set_physics_process(false)
	enemy.max_health = 1000.0
	enemy.health = 1000.0
	enemy.target = player
	enemy.wake()
	rig.target = player
	rig.global_position = player.global_position
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame

	# Overlay sprite for capturing the custom reticle at the exact mouse hotspot
	var cursor_layer := CanvasLayer.new()
	cursor_layer.layer = 120
	var cursor_rect := TextureRect.new()
	cursor_rect.texture = preload("res://assets/ui/cursors/take_aim_reticle.png")
	cursor_rect.size = Vector2(48, 48)
	cursor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_rect.visible = false
	cursor_layer.add_child(cursor_rect)
	get_tree().root.add_child(cursor_layer)

	# 1. Activate Take Aim -> enters targeting mode
	player.skills.activate_take_aim()
	print("TAKE_AIM_SHOT targeting=", player.skills.take_aim_targeting)

	for res: Vector2i in GameSettings.RESOLUTIONS:
		if DisplayServer.get_name() != "headless":
			var screen: int = 0 if res.y > 1080 else mini(1, DisplayServer.get_screen_count() - 1)
			get_window().current_screen = screen
			get_window().borderless = true
			get_window().size = res
			var physical: Vector2i = DisplayServer.screen_get_size(screen)
			get_window().position = DisplayServer.screen_get_position(screen) + (physical - res).max(Vector2i.ZERO) / 2
		for s in 5:
			await get_tree().process_frame
		var aim_3d: Vector3 = enemy.global_position + Vector3(0.0, enemy.body_height * 0.65, 0.0)
		var screen_pos: Vector2 = rig.camera.unproject_position(aim_3d)
		player.hover_target = enemy
		cursor_rect.position = screen_pos - Vector2(24, 24)
		cursor_rect.visible = true
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var tag: String = "%dx%d" % [res.x, res.y]
		var targeting_img: Image = get_viewport().get_texture().get_image()
		var path: String = OS.get_environment("TEMP") + "/curse_take_aim_targeting_%s.png" % tag
		targeting_img.save_png(path)
		print("TAKE_AIM_SHOT saved ", path)

	# 2. Confirm click on enemy -> Cutter focuses and arms Take Aim
	player.skills.confirm_take_aim(enemy)
	cursor_rect.visible = false
	print("TAKE_AIM_SHOT confirmed: targeting=", player.skills.take_aim_targeting, " cutter_target=", archer.target, " cutter_armed=", archer.take_aim_armed)

	for i in 8:
		await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var shot_img: Image = get_viewport().get_texture().get_image()
		shot_img.save_png(OS.get_environment("TEMP") + "/curse_take_aim_fire_%d.png" % i)

	print("TAKE_AIM_SHOT done")
	cursor_layer.queue_free()
	get_tree().quit()

## `-- --brutalshot`: arms Brutal Attack, whiffs once without spending it, then lands it; frames in %TEMP%/curse_brutal_N.png.
func _brutal_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	game.companion.testing_disabled = true
	player.global_position = Vector3.ZERO
	player.stats.brutal_reload_remaining = 0.0
	TownState.passive_ranks["critical_strike"] = 1   # (Brutal Attack opens with Critical Strike 1)
	player.skills.activate_brutal_attack()
	for i in 10:
		await get_tree().create_timer(0.1).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_brutal_%d.png" % i)
	player.skills.start_skill("basic", null, player.global_position + Vector3(0.0, 0.0, -2.0))
	for i in range(10, 23):
		await get_tree().create_timer(0.1).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_brutal_%d.png" % i)
	var victim: Enemy = _spawn_enemy(player.global_position + Vector3(0.0, 0.0, -1.7))
	victim.max_health = 5000.0
	victim.health = victim.max_health
	player.skills.start_skill("basic", victim)
	for i in range(23, 39):
		await get_tree().create_timer(0.1).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_brutal_%d.png" % i)
	get_tree().quit()

## `-- --enemyshot`: one of each enemy kind in a row facing the camera; frame in %TEMP%/curse_enemies.png.
func _enemy_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	var ids: Array = EnemyDb.all().keys()
	ids.sort()
	var x: float = -float(ids.size() - 1) * 1.4
	for id in ids:
		var z: Enemy = _spawn_enemy(Vector3(x, 0, -3.0), id)
		z.aggro_range = 0.0
		z.visual.rotation.y = PI
		x += 2.8
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_enemies.png")
	var names: PackedStringArray = []
	for id in ids:
		names.append(id)
	print("enemy kinds (left to right): ", ", ".join(names))
	get_tree().quit()

## `-- --championshot`: a plain zombie beside one champion of each affix, facing the camera; frame in %TEMP%/curse_champions.png.
func _champion_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	var plain: Enemy = _spawn_enemy(player.global_position + Vector3(-4.2, 0, -3.0), "zombie")
	plain.aggro_range = 0.0
	plain.visual.rotation.y = PI
	var x: float = -2.8
	var volatile: Enemy = null
	for affix in Champion.AFFIXES.keys():
		var z: Enemy = _spawn_enemy(player.global_position + Vector3(x, 0, -3.0), "zombie")
		z.aggro_range = 0.0
		Champion.attach(z, affix)
		z.visual.rotation.y = PI
		if affix == "explodes":
			volatile = z
		x += 2.8
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_champions.png")
	volatile.champion.on_death(volatile)   # the telegraph: the ring is on the ground, the blast is still to come
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_champions_telegraph.png")
	print("champion shot: plain zombie, then ", ", ".join(Champion.AFFIXES.keys()))
	get_tree().quit()

## `-- --skillshot=gibs`: a fireball detonates on low-health zombies; frames in %TEMP%/curse_gib_N.png.
func _gib_shots() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.set_physics_process(true)
	var victims: Array[Enemy] = []
	for pos in [Vector3(0.0, 0, -4.0), Vector3(1.4, 0, -4.8), Vector3(-1.3, 0, -4.6), Vector3(0.3, 0, -6.0)]:
		var z: Enemy = _spawn_enemy(pos)
		z.aggro_range = 0.0
		z.max_health = 30.0
		z.health = 30.0
		victims.append(z)
	await get_tree().create_timer(0.6).timeout
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.damage = 200.0
	ball.destination = Vector3(0.0, 0.0, -4.6)
	add_child(ball)
	ball.global_position = Vector3(0.0, 1.0, -4.6)
	ball._explode()
	for i in 16:
		await get_tree().create_timer(0.12).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_gib_%d.png" % i)
	get_tree().quit()

## `-- --skillshot=fireball`: cast on dummies and capture a frame every 0.12 s.
func _skill_shots(_which: String) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.stats.mana = player.stats.max_mana
	player.set_physics_process(true)
	for pos in [Vector3(-1.2, 0, -4.2), Vector3(0.8, 0, -5.0), Vector3(2.2, 0, -3.8)]:
		var z: Enemy = _spawn_enemy(pos)
		z.aggro_range = 0.0
		z.max_health = 800.0
		z.health = 800.0
	await get_tree().create_timer(0.8).timeout
	player.skills.start_skill("fireball", null, Vector3(0.6, 0, -4.4))
	for i in 20:
		await get_tree().create_timer(0.14 if i < 12 else 0.4).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_skill_%d.png" % i)
	get_tree().quit()

## `-- --openingshot`: a shield guard frame sequence against a zombie, then an Opening's mark on the zombie beside it. Frames in %TEMP%.
func _opening_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	TownState.passive_ranks["opening"] = 20
	var longsword := Items.build(ItemDb.get_def("longsword"), 10, Items.Rarity.NORMAL, [])
	player.stats.equipment.clear()
	player.stats.equipment[Items.Slot.WEAPON] = longsword
	TownState.persist = false
	TownState.dev_set_hero_level(40)           # the kite shield and longsword are level 10 bases: the hero must meet their class requirement
	TownState.passive_ranks["barricade"] = 1   # a shield needs Barricade 1
	player.stats.equip(Items.build(ItemDb.get_def("kite_shield"), 10, Items.Rarity.NORMAL, []), false)
	player.stats.refresh()
	print("DIAG shield_equipped=", player.stats.equipment.has(Items.Slot.SHIELD), " appearance=", player.appearance != null,
		" worn=", player.appearance.worn if player.appearance != null else [],
		" shd_nodes=", player.model.find_children("*shd_kite*", "Node3D", true, false).size())
	player.max_health = 5000.0
	player.health = 5000.0
	var guard: Enemy = _spawn_enemy(player.global_position + Vector3(1.8, 0, 0))
	guard.alert_delay = 999.0
	guard.set_physics_process(false)
	await get_tree().create_timer(0.5).timeout
	var out := OS.get_environment("TEMP")
	get_viewport().get_texture().get_image().save_png(out + "/curse_block_0_idle.png")
	player._on_blocked()
	for i in 6:
		await get_tree().create_timer(0.07).timeout
		get_viewport().get_texture().get_image().save_png(out + "/curse_block_%d.png" % (i + 1))
	var other: Enemy = _spawn_enemy(player.global_position + Vector3(-1.9, 0, 1.0))
	other.alert_delay = 999.0
	other.set_physics_process(false)
	player.openings._mark(other, "melee")
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(out + "/curse_opening_mark.png")
	print("OPENING_SHOT mark=", player.openings.is_open_on(other), " block_clip=", player.model.current)
	get_tree().quit()

## `-- --skilltipshot`: the skill screen with the Opening passive hovered at rank 5 (its description and current effect). Frame in %TEMP%.
func _skill_tip_shot() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.dev_set_hero_level(40)
	TownState.passive_ranks["opening"] = 5
	hud.open_skills()
	await get_tree().create_timer(0.6).timeout
	var panel = hud.character_panel
	var found: Button = null
	for node in panel.find_children("*", "Button", true, false):
		if node.has_meta("passive_id") and String(node.get_meta("passive_id")) == "opening":
			found = node
	if found == null:
		print("SKILLTIP no opening button")
		get_tree().quit()
		return
	found.mouse_entered.emit()
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_skill_tip.png")
	print("SKILLTIP detail_visible=", panel._detail.visible, " text=", panel._detail_label.text.replace("\n", " | "))
	get_tree().quit()

## Shared setup for the close-up Opening shots: a sword and kite shield at level 40, Opening at rank 20, and a close camera.
func _close_setup() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.dev_set_hero_level(40)
	TownState.passive_ranks["opening"] = 20
	TownState.passive_ranks["barricade"] = 1
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.stats.equipment.clear()
	player.stats.equipment[Items.Slot.WEAPON] = Items.build(ItemDb.get_def("longsword"), 10, Items.Rarity.NORMAL, [])
	player.stats.equip(Items.build(ItemDb.get_def("kite_shield"), 10, Items.Rarity.NORMAL, []), false)
	player.stats.refresh()
	player.max_health = 5000.0
	player.health = 5000.0
	rig.set_zoom_now(0.6)

## `-- --blockclose`: a real zombie attacks the hero; the block chance is forced to 100% (the real block path, not a dodge) so every
## landing blow is blocked. Three frames from the moment the guard clip starts. Frames in %TEMP%.
func _block_close_shot() -> void:
	await _close_setup()
	player.block_chance = 1.0
	player.dodge_chance = 0.0
	var zombie: Enemy = _spawn_enemy(player.global_position + Vector3(1.3, 0, 0.3))
	zombie.aggro_range = 40.0
	zombie.alert_delay = 0.0
	var waited := 0.0
	while player.model.current != "block" and waited < 10.0:
		await get_tree().create_timer(0.02).timeout
		waited += 0.02
	var out := OS.get_environment("TEMP")
	print("BLOCKCLOSE clip=", player.model.current, " waited=", snappedf(waited, 0.01))
	for i in 3:
		get_viewport().get_texture().get_image().save_png(out + "/curse_close_block_%d.png" % i)
		await get_tree().create_timer(0.12).timeout
	get_tree().quit()

## `-- --execclose`: the sword execution on a marked zombie, started through the basic attack (the click and controller path).
## Three frames across the 1.0 s stab. Frames in %TEMP%.
func _exec_close_shot() -> void:
	await _close_setup()
	var victim: Enemy = _spawn_enemy(player.global_position + Vector3(1.5, 0, 0))
	victim.alert_delay = 999.0
	victim.max_health = 50000.0
	victim.health = 50000.0
	victim.set_physics_process(false)
	await get_tree().create_timer(0.3).timeout
	player.openings._mark(victim, "melee")
	player.skills.start_skill("basic", victim)
	var out := OS.get_environment("TEMP")
	print("EXEC busy=", player.skills.busy, " skill=", player.skills.busy_skill, " style=", player.openings.style_id())
	for i in 3:
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png(out + "/curse_close_exec_%d.png" % i)
	print("EXEC hp_left=", victim.health, " outcome=", str(victim.last_result.get("outcome", "")), " skill=", str(victim.last_result.get("skill_id", "")))
	get_tree().quit()

## `-- --aimshot`: fireball aim preview over a zombie cluster, then hover tooltips for two skills.
func _aim_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	var cluster: Array[Vector3] = [Vector3(1.0, 0, -4.5), Vector3(2.4, 0, -5.4), Vector3(0.0, 0, -6.0), Vector3(-3.5, 0, -4.0), Vector3(6.0, 0, -3.0)]
	for pos in cluster:
		var z: Enemy = _spawn_enemy(pos)
		z.aggro_range = 0.0
	player.set_physics_process(false)
	player.skills.aiming_id = "fireball"
	player.skills.aiming_action = "skill_2"
	await get_tree().create_timer(0.8).timeout
	var cursor: Vector3 = Vector3(1.2, 0, -5.2)
	for i in 6:
		player.skills.update_aim(cursor)
		await get_tree().process_frame
	var lit: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if (node as Actor).highlighted:
			lit += 1
	print("aim: point=", player.skills.aim_point, " highlighted=", lit, " of ", cluster.size(), " (blast radius ", Projectile.BLAST_RADIUS, ")")
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_aim.png")
	# Cast it: the projectile must land on the aimed point.
	player.skills.clear_aim()
	player.skills.start_skill("fireball", null, player.skills.aim_point_for("fireball", cursor))
	for i in 3:
		player.skills.tick_busy(0.3)
	await get_tree().create_timer(1.0).timeout
	# Tooltips: hover the fireball and dodge slots.
	for pair in [["fireball", "curse_tip_0.png"], ["dodge", "curse_tip_1.png"], ["basic", "curse_tip_2.png"]]:
		for hit in hud._slot_hits:
			if hit["id"] == pair[0]:
				hud.mouse_override = (hit["rect"] as Rect2).get_center()
		await get_tree().create_timer(0.2).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/" + pair[1])
	get_tree().quit()

## `-- --hudshot`: put skills on cooldown (and drain mana) to check the hotbar cooldown display.
func _hud_shot() -> void:
	player.set_physics_process(false)
	player.stats.cooldowns = {"fireball": 0.3, "dodge": 0.6}
	player.stats.mana = 9.0
	await get_tree().create_timer(0.15).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hud_0.png")
	player.stats.cooldowns = {"fireball": 0.0, "dodge": 0.0}
	await get_tree().create_timer(0.1).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hud_1.png")
	get_tree().quit()

## `-- --powerbarcapture`: record the reusable forged frame with three live power icon textures.
func _powerbar_capture() -> void:
	player.set_physics_process(false)
	for body in PartyManager.current().bodies.values():
		if is_instance_valid(body): body.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	TownState.persist = false
	TownState.reset()
	GameSettings.ui_size = 1.0
	GameSettings.apply_ui_scale()
	# Unlock three actual powers for this non-saving visual capture only.
	TownState.passive_ranks = {"critical_strike": 8, "smite": 1, "devastation": 2, "searing_flames": 8, "ignite": 1}
	for item in Items.starting_gear(): player.stats.equip(item, false)
	player.stats.refresh()
	var powers: Array[String] = ["brutal_attack", "war_cry", "flame_nexus"]
	for i in powers.size():
		player.skills.hotbar[i] = powers[i]
		GameSettings.hotbar_casters[i] = "hero"
		_set_capture_power_charge(powers[i], 0.0)
	await get_tree().create_timer(0.5).timeout
	var view_size := get_viewport().get_visible_rect().size
	var stage := Label.new()
	stage.position = Vector2(0, view_size.y - 200)
	stage.size = Vector2(view_size.x, 40)
	stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_theme_font_size_override("font_size", 24)
	stage.add_theme_color_override("font_color", Color("ffe1a0"))
	stage.add_theme_color_override("font_outline_color", Color.BLACK)
	stage.add_theme_constant_override("outline_size", 10)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(stage)
	var explanation := Label.new()
	explanation.position = Vector2(0, view_size.y - 150)
	explanation.size = Vector2(view_size.x, 48)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explanation.text = "CONTROLLED STATE PLAYBACK | Each icon completes the sequence independently\nStaged gameplay values and release cue; not a recharge-speed or combat test"
	explanation.add_theme_font_size_override("font_size", 16)
	explanation.add_theme_color_override("font_outline_color", Color.BLACK)
	explanation.add_theme_constant_override("outline_size", 8)
	explanation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(explanation)
	var out_dir := ProjectSettings.globalize_path("res://.dev_output/powerbar_forge_v3_frames")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var frame_index := 0
	for active_id in powers:
		for id in powers: _set_capture_power_charge(id, 0.0)
		var title: String = SkillDb.all()[active_id]["name"]
		stage.text = "%s | DARK until it charges" % title
		frame_index = await _save_powerbar_frames(out_dir, frame_index, 40)
		for step in 120:
			var charge: float = float(step + 1) / 120.0
			stage.text = "%s | %d%% CHARGE" % [title, int(charge * 100.0)]
			_set_capture_power_charge(active_id, charge)
			frame_index = await _save_powerbar_frames(out_dir, frame_index, 1)
		stage.text = "%s | FULL: burst, then it pulses" % title
		frame_index = await _save_powerbar_frames(out_dir, frame_index, 220)
		stage.text = "%s | SPENT: back to dark" % title
		player.power_activated.emit(player.member_id, active_id)
		_set_capture_power_charge(active_id, 0.0)
		frame_index = await _save_powerbar_frames(out_dir, frame_index, 40)
	print("POWERBAR_CAPTURE frames=", frame_index, " path=", out_dir)
	get_tree().quit()

func _set_capture_power_charge(id: String, charge: float) -> void:
	if id == "brutal_attack":
		player.stats.brutal_reload_required = player.stats.brutal_recharge_damage()
		player.stats.brutal_reload_remaining = player.stats.brutal_reload_required * (1.0 - charge)
	else:
		var required: float = player.powers.required(id)
		player.powers.reload_required[id] = required
		player.powers.reload_remaining[id] = required * (1.0 - charge)

func _save_powerbar_frames(out_dir: String, start_index: int, count: int) -> int:
	var index := start_index
	for _i in count:
		index = await _save_powerbar_frame(out_dir, index)
	return index

func _save_powerbar_frame(out_dir: String, frame_index: int) -> int:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(out_dir.path_join("frame_%04d.jpg" % frame_index), 0.97)
	return frame_index + 1

## `-- --dropshot`: one of every kind of item lying on the ground next to the hero, and the hotbar's skill picker open on its second slot.
func _drop_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.set_physics_process(false)
	var defs: Array = ItemDb.all().values().slice(0, 9)
	for i in defs.size():
		var def: ItemDef = defs[i]
		var rarity: int = [Items.Rarity.NORMAL, Items.Rarity.MAGIC, Items.Rarity.RARE][i % 3]
		var drop: LootDrop = game.director.drop_item(Vector3(-0.6 + (i % 3) * 0.55, 0, 2.2 + (i / 3) * 0.5), Items.make(def.slot, rarity, 1, def.display_name))
		drop._end = Vector3(-0.6 + (i % 3) * 0.55, 0, 2.2 + (i / 3) * 0.5)
	await get_tree().create_timer(1.6).timeout
	var size_px: Vector2 = hud.get_viewport_rect().size
	for hit in hud._slot_hits:
		if hit["action"] == "skill_2":
			hud.picker.open(1, hit["rect"])
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_drops.png")
	get_tree().quit()

## `-- --smashshot`: a Detonation among a row of barrels, a cart, gravestones and a brazier, captured as the pieces fly.
func _smash_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.global_position = Vector3(-8, 0, 0)
	player.reset_physics_interpolation()
	player.visual.rotation.y = PI * 0.5
	var spots: Array = [["barrel", 0.0, 0.6, 1.0], ["barrel", 1.4, -0.5, 1.0], ["gravestone", 3.0, 0.3, 1.3], ["wrecked_cart", 5.2, -0.4, 1.9],
		["brazier", 7.4, 0.5, 1.5], ["barrel", 9.0, -0.3, 1.0]]
	for spot in spots:
		arena.place_prop(spot[0], Vector3(-3.0 + spot[1], 0, spot[2]), 0.0, spot[3], true, spot[0] == "brazier")
	await get_tree().create_timer(0.5).timeout
	TownState.passive_ranks = {"searing_flames": 8, "ignite": 1, "devastation": 2}
	player.powers.activate("detonation", Vector3(0.5, 0, 0))
	await get_tree().create_timer(0.55).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_smash_0.png")
	await get_tree().create_timer(0.45).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_smash_1.png")
	get_tree().quit()

## `-- --itemsheet`: every dropped-item model on the ground in a ring round the hero, in each rarity's glow, for judging by eye.
func _item_sheet() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.global_position = Vector3.ZERO
	var bases: Array = []
	var drops: Array[LootDrop] = []
	for def in ItemDb.all().values():
		bases.append([def.slot, def.display_name])
	for i in bases.size():
		var item: Dictionary = Items.make(bases[i][0], i % 5, 1, bases[i][1])
		var drop: LootDrop = LootDrop.create(item)
		game.director.add_child(drop)
		var angle: float = -PI * 0.9 + PI * 0.8 * float(i) / float(bases.size() - 1) - PI * 0.5
		drop.global_position = Vector3(cos(angle) * 4.0, 0, sin(angle) * 4.0 - 1.0)
		drop.landed = true
		drop._age = 1.0
		drops.append(drop)
	await get_tree().create_timer(1.0).timeout
	if OS.get_cmdline_user_args().has("--gear"):   # the Tab panel: worn items and the bag as pictures, one pointed at
		for i in 8:
			player.stats.add_to_bag(drops[i].item)
		hud.show_gear = true
		TownState.persist = false   # a picture of a mid-level hero (--maxlevel: the capped one) must not touch the real save
		TownState.dev_set_hero_level(HeroProgression.MAX_LEVEL if OS.get_cmdline_user_args().has("--maxlevel") else 6)
		TownState.add_hero_xp(0 if OS.get_cmdline_user_args().has("--maxlevel") else 420)
		for drop in drops.slice(8):   # the rest are worn, so the paper doll has something in most places
			if not player.stats.equipment.has(player.stats.place_for(drop.item)) and int(drop.item["slot"]) != Items.Slot.WEAPON:
				player.stats.wear(player.stats.place_for(drop.item), drop.item)
		hud._open_character()
		if OS.get_cmdline_user_args().has("--skills"):   # the skill screen instead, a few ranks bought and some chosen
			TownState.passive_ranks = {"fortitude": 3, "critical_strike": 2}
			hud.open_skills()
			await get_tree().process_frame
			hud.character_panel._raise("fortitude")
			hud.character_panel._raise("dodge")
		await get_tree().create_timer(0.5).timeout
		var size_px: Vector2 = get_viewport().get_visible_rect().size
		hud.mouse_override = Vector2(size_px.x - 30.0 - (6 * 64 + 5 * 10) + 1 * 74 + 32, 70.0 + 4.0 + 64.0 + 34.0 + 32.0)
	if OS.get_cmdline_user_args().has("--hover"):   # point at a drop to see its tooltip and comparison
		var focus: LootDrop = drops[2]
		hud.mouse_override = player.get_viewport().get_camera_3d().unproject_position(focus.global_position + Vector3(0, 0.5, 0))
	if OS.get_cmdline_user_args().has("--orbs"):
		player.health = player.max_health * 0.58
		player.stats.mana = player.stats.max_mana * 0.36
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_items.png")
	if OS.get_cmdline_user_args().has("--orb-motion"):
		for i in 16:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_orb_motion_%02d.png" % i)
			await get_tree().create_timer(0.15).timeout
	get_tree().quit()

## `-- --hovershot`: put the mouse over a brute and capture the hover health bar and ring.
func _hover_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	var brute: Enemy = _spawn_enemy(Vector3(1.8, 0, -2.4), "brute", 1.0)
	var zombie: Enemy = _spawn_enemy(Vector3(-2.2, 0, -1.2), "zombie", 1.0)
	brute.aggro_range = 0.0
	zombie.aggro_range = 0.0
	await get_tree().create_timer(0.8).timeout
	zombie.receive(Combat.resolve(player, zombie, 20.0), player.global_position)
	brute.receive(Combat.resolve(player, brute, 60.0), player.global_position)
	var camera: Camera3D = get_viewport().get_camera_3d()
	# Screen-space picking at the brute's head, chest, knee and feet, and away from it (injected mouse positions).
	var base: Vector3 = brute.global_position
	for part in [["head", 2.2], ["chest", 1.4], ["knee", 0.6], ["feet", 0.1]]:
		var at: Vector2 = camera.unproject_position(base + Vector3(0, part[1], 0))
		var picked: Actor = player._hover_pick(Vector3(99, 0, 99), at)
		print("pick at brute ", part[0], ": ", picked.display_name if picked else "none")
	var side: Vector2 = camera.unproject_position(base + Vector3(3.5, 1.0, 0))
	var off: Actor = player._hover_pick(Vector3(99, 0, 99), side)
	print("pick 3.5 m to the side: ", off.display_name if off else "none")
	# Freeze the player's own logic so the injected hover sticks for the screenshots.
	player.set_physics_process(false)
	player.hover_target = brute
	for i in 3:
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hover_%d.png" % i)
	get_tree().quit()

## `-- --rollshot`: trigger a dodge roll and capture frames of it, to check the roll starts without a slide.
func _roll_shots() -> void:
	await get_tree().create_timer(0.6).timeout
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(player.global_position + Vector3(5, 0, 0))
	var start: Vector3 = player.global_position
	for i in 8:
		await get_tree().create_timer(0.07).timeout
		print("roll frame ", i, " travelled=", snappedf(player.global_position.distance_to(start), 0.01),
			" clip_pos=", snappedf(player.model.anim.current_animation_position, 0.01))
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_roll_%d.png" % i)
	get_tree().quit()

## `-- --handshot[=CLIP:T] [--equip=Greatsword]`: a close look at the sword hand, frames in %TEMP%/curse_hand_N.png (front, side, top).
func _hand_shot() -> void:
	player.set_physics_process(false)
	hud.visible = false
	var clip: String = "idle_alert"
	var t: float = 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--handshot="):
			clip = arg.substr(11).get_slice(":", 0)
			t = float(arg.substr(11).get_slice(":", 1)) if ":" in arg else 1.0
		if arg.begins_with("--equip="):
			TownState.passive_ranks["overbear"] = 1   # (a two-handed weapon needs Overbear)
			player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, arg.substr(8)), false)
	await get_tree().process_frame
	player.model.manual(clip)
	player.model.scrub(t)
	await get_tree().create_timer(0.4).timeout
	player.model.scrub(t)
	await get_tree().create_timer(0.2).timeout
	var skel: Skeleton3D = player.model.find_children("*", "Skeleton3D", true, false)[0]
	var hand_xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(skel.find_bone("RightHand"))
	var grip: Vector3 = hand_xf * Vector3(-0.8, 15.0, 0.5)
	var axes: Array = [-hand_xf.basis.x, hand_xf.basis.x, hand_xf.basis.z, -hand_xf.basis.y]   # palm side, back of the hand, blade side, wrist
	var distance: float = 0.8
	if OS.get_cmdline_user_args().has("--body"):   # the whole hero from his right, front, left and back instead
		player.visual.rotation.y = 0.0
		grip = player.global_position + Vector3(0, 1.1, 0)
		axes = [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1)]
		distance = 3.4
	var from_above: bool = OS.get_cmdline_user_args().has("--ground")   # the game's own angle, to judge the floor
	if from_above:
		grip = player.global_position + Vector3(0, 0.4, 0)
		axes = [Vector3(0, 0.8, 0.6), Vector3(0, 1.4, 0.3), Vector3(0.5, 0.6, 0.5), Vector3(0, 0.25, 0.9)]
		distance = 7.0
	var cam := Camera3D.new()
	cam.fov = 28.0
	player.get_tree().root.add_child(cam)
	cam.current = true
	for i in axes.size():
		cam.global_position = grip + (axes[i] as Vector3).normalized() * distance + Vector3(0, 0.12, 0)
		cam.look_at(grip, Vector3.UP)
		await get_tree().create_timer(0.25).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hand_%d.png" % i)
	get_tree().quit()

## `-- --clipsheet=NAME[:T0:T1]`: scrub a clip across [T0, T1] (default the whole clip) in 12 steps and tile the frames into
## %TEMP%/curse_clip_NAME.png, to judge an animation by eye.
func _clip_sheet(spec: String) -> void:
	player.set_physics_process(false)
	var parts: PackedStringArray = spec.split(":")
	var clip: String = parts[0]
	if not player.model.anim.has_animation("game/" + clip):
		print("clip ", clip, " NOT FOUND")
		get_tree().quit()
		return
	player.model.manual(clip)
	var length: float = player.model.anim.get_animation("game/" + clip).length
	var t0: float = float(parts[1]) if parts.size() > 1 else 0.0
	var t1: float = float(parts[2]) if parts.size() > 2 else length
	if parts.size() > 3:
		player.model.leg_raise = float(parts[3])
		rig.pitch_degrees = -8.0                 # side-on view so the leg can be judged
		player.visual.rotation.y = PI * 0.5
	for arg in OS.get_cmdline_user_args():   # `--equip=Greatsword`: hold that weapon for the sheet
		if arg.begins_with("--equip="):
			TownState.passive_ranks["overbear"] = 1   # (a two-handed weapon needs Overbear)
			player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, arg.substr(8)), false)
			await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--closeup"):
		hud.visible = false
		rig.set_zoom_now(0.55)
		rig.pitch_degrees = -14.0
		player.visual.rotation.y = PI * 0.62
	print("clip ", clip, " length=", snappedf(length, 0.01))
	var tiles: Array[Image] = []
	for i in 12:
		var t: float = lerpf(t0, t1, float(i) / 11.0)
		player.model.scrub(t)
		await get_tree().create_timer(0.2).timeout
		player.model.scrub(t)
		await get_tree().create_timer(0.08).timeout
		var skel: Skeleton3D = player.model.find_children("*", "Skeleton3D", true, false)[0]
		var hips: Vector3 = skel.get_bone_global_pose(skel.find_bone("Hips")).origin
		var hand: Vector3 = skel.get_bone_global_pose(skel.find_bone("RightHand")).origin
		var foot: Vector3 = skel.get_bone_global_pose(skel.find_bone("RightFoot")).origin
		print("  t=", snappedf(t, 0.01), " hips y=", snappedf(hips.y, 0.1), " hand y=", snappedf(hand.y, 0.1), " hand z=", snappedf(hand.z, 0.1),
			" foot y=", snappedf(foot.y, 0.1), " foot z=", snappedf(foot.z, 0.1))
		var shot: Image = get_viewport().get_texture().get_image()
		var c: Vector2i = shot.get_size() / 2
		var tile: Image = shot.get_region(Rect2i(c.x - 360, c.y - 420, 720, 720))
		if OS.get_cmdline_user_args().has("--closeup"):
			tile = shot.get_region(Rect2i(c.x - 220, c.y - 330, 440, 440))
		tile.resize(300, 300)
		tiles.append(tile)
	var sheet: Image = Image.create(1200, 900, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 300, 300), Vector2i((i % 4) * 300, (i / 4) * 300))
	sheet.save_png(OS.get_environment("TEMP") + "/curse_clip_%s.png" % clip)
	get_tree().quit()

## `-- --poses`: freeze the hero in key frames of each clip and save a PNG of each (deformation check).
func _pose_sheet() -> void:
	player.set_physics_process(false)
	if OS.get_cmdline_user_args().has("--blood"):
		player.skills.blade_blood = 0.9
		player.skills.update_blade_blood(0.0)
	var poses: Array = [["charge_run", 0.1], ["charge_run", 0.25], ["charge_run", 0.4], ["kick", 0.15], ["kick", 0.3], ["kick", 0.45],
		["kick", 0.6], ["kick", 0.75], ["kick", 0.9], ["kick", 1.1], ["kick", 1.3], ["charge", 2.0]]
	if OS.get_cmdline_user_args().has("--oldposes"):
		poses = [["idle_alert", 1.0], ["slash_r", 0.73], ["slash_l", 1.37], ["thrust", 1.57], ["power", 1.23],
			["combo_end", 1.37], ["cast", 0.53], ["roll", 0.8], ["hit", 0.3], ["run", 0.3]]
	for i in poses.size():
		player.model.manual(poses[i][0])
		player.model.scrub(poses[i][1])
		await get_tree().create_timer(0.25).timeout
		player.model.scrub(poses[i][1])
		await get_tree().create_timer(0.1).timeout
		var skeleton: Skeleton3D = player.model.find_children("*", "Skeleton3D", true, false)[0]
		var arm_lengths: Array[String] = []
		for chain in [["RightArm", "RightForeArm", "RightHand"], ["LeftArm", "LeftForeArm", "LeftHand"]]:
			var a: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone(chain[0])).origin
			var b: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone(chain[1])).origin
			var c: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone(chain[2])).origin
			arm_lengths.append("%s upper=%.1f fore=%.1f" % [chain[0].substr(0, 1), a.distance_to(b), b.distance_to(c)])
		print("pose ", poses[i][0], ": ", " | ".join(arm_lengths))
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_pose_%d.png" % i)
	get_tree().quit()

## `-- --shot`: spawn zombies next to the hero, fight for a few seconds, save a PNG, quit.
func _screenshot_demo() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	if OS.get_cmdline_user_args().has("--duel"):
		var dummy: Enemy = _spawn_enemy(Vector3(0.6, 0, 2.2))
		dummy.max_health = 9999.0
		dummy.health = 9999.0
	else:
		for i in 4:
			_spawn_enemy(Vector3(-3.0 + i * 2.0, 0, 4.0 + (i % 2) * 2.0))
	await get_tree().create_timer(1.0 if OS.get_cmdline_user_args().has("--duel") else 1.5).timeout
	player.stats.mana = player.stats.max_mana
	var target: Actor = player.enemy_near(player.global_position, 20.0)
	if target:
		player.attack_target = target
	var shots: int = 8 if OS.get_cmdline_user_args().has("--duel") else 4
	for i in shots:
		await get_tree().create_timer(0.3).timeout
		print("shot ", i, " busy=", player.skills.busy, " t=", snappedf(player.skills.busy_t, 0.01), " clip=", player.model.current,
			" pos=", snappedf(player.model.anim.current_animation_position, 0.01), " speed=", player.model.anim.speed_scale,
			" hitpause=", player.hitpause, " target=", player.attack_target, " mana=", int(player.stats.mana))
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(OS.get_environment("TEMP") + "/curse_shot_%d.png" % i)
	get_tree().quit()

## `-- --powerfeel=<power id> [--classic]`: the hero uses one of the three impact powers on a group, in the live dungeon, shown full screen
## on screen 1 at 1920x1080. Frames run from the key press past the impact into %TEMP%/curse_powerfeel_<id>_N.png; the frame just after the
## impact is also written to docs/screenshots/power-feel/<id>_<modular|classic>.png.
func _power_feel_shot(id: String) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	if DisplayServer.get_screen_count() > 1:
		DisplayServer.window_set_current_screen(1)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await get_tree().create_timer(0.6).timeout
	game.companion.testing_disabled = true
	player.global_position = Vector3(40, 0, 40)
	player.reset_physics_interpolation()
	player.powers.reset()
	player.skills.reset()
	for item in Items.starting_gear():
		player.stats.equip(item, false)
	TownState.passive_ranks = {"critical_strike": 8, "fortitude": 8, "smite": 1, "overbear": 1, "barricade": 1, "dodge": 5, "survival": 3,
		"devastation": 2, "searing_flames": 8, "ignite": 1}
	if id == "staggering_blow":
		player.stats.wear(Items.Slot.WEAPON, Items.build(ItemDb.get_def("greatsword"), 6, Items.Rarity.NORMAL))
	player.stats.refresh()
	player.visual.rotation.y = 0.0
	var at: Vector3 = player.global_position
	var offsets: Array[Vector3] = []
	if id == "war_cry":
		offsets = [Vector3(-1.6, 0, 3.4), Vector3(0.9, 0, 4.6), Vector3(-0.4, 0, 6.4), Vector3(2.8, 0, 3.0), Vector3(-3.0, 0, 5.2), Vector3(1.5, 0, -2.5)]
	elif id == "staggering_blow":
		offsets = [Vector3(0, 0, 2.6), Vector3(-1.2, 0, 3.3), Vector3(1.4, 0, 3.4), Vector3(0.2, 0, 4.4), Vector3(-2.0, 0, 2.2)]
	else:
		offsets = [Vector3(1.6, 0, 0), Vector3(-1.6, 0, 0), Vector3(0, 0, 1.7), Vector3(0, 0, -1.7), Vector3(2.6, 0, 2.2), Vector3(-2.4, 0, -2.0)]
	var group: Array[Enemy] = []
	for off in offsets:
		var e: Enemy = _spawn_enemy(at + off)
		e.aggro_range = 0.0
		e.max_health = 5000.0
		e.health = e.max_health
		e.dodge_chance = 0.0
		e.block_chance = 0.0
		group.append(e)
	await get_tree().create_timer(0.8).timeout
	var cursor: Vector3 = at + Vector3(0, 0, 5)
	if id == "staggering_blow":
		player.attack_target = group[0]
	var mode: String = "classic" if "--classic" in OS.get_cmdline_user_args() else "modular"
	var out_dir: String = ProjectSettings.globalize_path("res://docs/screenshots/power-feel")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var went: bool = player.powers.activate(id, cursor)
	print("POWERFEEL ", id, " ", mode, " activated=", went)
	for i in 12:
		await get_tree().create_timer(0.1).timeout
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(OS.get_environment("TEMP") + "/curse_powerfeel_%s_%d.png" % [id, i])
		if i == 6:
			image.save_png(out_dir + "/%s_%s.png" % [id, mode])
	var hit: int = 0
	for e in group:
		if is_instance_valid(e) and e.health < e.max_health:
			hit += 1
	print("POWERFEEL enemies struck=", hit, " of ", group.size(), " spent=", player.powers.reload_remaining.has(id))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_tree().quit()
