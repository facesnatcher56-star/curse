extends DevSuite
## Self-test: hotkeys, hotbar, the skill queue and data integrity, Power Strike, Leap and Earthshatter.

## Hotkeys pressed mid-animation: the potion drinks immediately, usable skills cancel the swing, unusable ones do not.
func _test_hotkeys() -> void:
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.stats.potions = 3
	GameSettings.hotbar_slots[3] = "skewer"
	var dummy: Enemy = _spawn_enemy(Vector3(1.8, 0, 0))
	dummy.aggro_range = 0.0
	dummy.max_health = 900.0
	dummy.health = 900.0
	await get_tree().physics_frame
	# 1. Potion during a swing.
	player.health = 40.0
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.15).timeout
	var was_busy: bool = player.skills.busy
	Input.action_press("use_potion")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("use_potion")
	var potion_ok: bool = player.stats.potions == 2 and player.health > 80.0 and not player.skills.busy
	# 2. Potion while stunned.
	player.health = 30.0
	player.stats.cooldowns.clear()
	player.stun_time = 1.0
	await get_tree().physics_frame
	Input.action_press("use_potion")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("use_potion")
	var stunned_ok: bool = player.stats.potions == 1 and player.health > 60.0
	player.stun_time = 0.0
	# 3. A usable skill cancels the current swing and starts.
	player.stats.cooldowns.clear()
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.1).timeout
	Input.action_press("skill_4")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_4")
	await get_tree().physics_frame   # Skewer is aimed: it charges when the key is let go
	await get_tree().physics_frame
	var skill_ok: bool = player.skills.busy_skill == "skewer" and player.skewer.skewer_phase != 0
	player.skills.cancel_action()
	# 4. A skill on cooldown must NOT cancel the swing.
	player.stats.cooldowns["skewer"] = 5.0
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.1).timeout
	Input.action_press("skill_4")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_4")
	var no_cancel_ok: bool = player.skills.busy and player.skills.busy_skill == "basic"
	player.skills.cancel_action()
	expect("potion works mid-swing", potion_ok)
	expect("potion works while stunned", stunned_ok)
	expect("a usable skill cancels a swing", skill_ok)
	expect("an unusable skill leaves the swing alone", no_cancel_ok)
	print("  hotkeys: potion mid-swing=", potion_ok, " (was busy=", was_busy, "), potion while stunned=", stunned_ok,
		", skill cancels swing=", skill_ok, ", skill on cooldown leaves swing alone=", no_cancel_ok)
	dummy.queue_free()
	player.stats.cooldowns.clear()
	player.stats.potions = 3
	await get_tree().process_frame

## Leap: slams a downed enemy (crit, pin, boot, pull-out), chops standing ground otherwise; stun shows daze stars.
func _test_leap() -> void:
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	var downed: Enemy = _spawn_enemy(Vector3(32, 0, -19))
	downed.aggro_range = 0.0
	downed.max_health = 800.0
	downed.health = 800.0
	await get_tree().process_frame
	downed.ragdoll_launch(Vector3.ZERO, 0.0, Vector3.ZERO)
	var t: float = 0.0
	while t < 3.0 and not LeapSkill.is_downed(downed):
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var start_health: float = downed.health
	var phases: Array = []
	var max_height: float = 0.0
	var stayed_down: bool = true
	var daze_seen: bool = false
	player.skills.try_directional("leap", downed.global_position)
	t = 0.0
	while player.skills.busy and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if phases.is_empty() or phases[-1] != player.leap.leap_phase:
			phases.append(player.leap.leap_phase)
		max_height = maxf(max_height, player.visual.position.y)
		if player.leap.leap_phase == 4 and is_instance_valid(downed):
			stayed_down = stayed_down and LeapSkill.is_downed(downed)
		daze_seen = daze_seen or (is_instance_valid(downed) and downed._daze != null)
	expect("leap slam runs crouch/air/hold/pull", phases == [1, 2, 3, 4, 0])
	expect("leap slam hurts", start_health - downed.health > 0.0)
	expect("slammed enemy stays pinned during the pull", stayed_down)
	expect("stun shows daze stars", daze_seen)
	expect("leap restores aim and collision", player.model.weapon_aim == null and player.collision_mask == (Player.LAYER_WORLD | Player.LAYER_ENEMY))
	print("  leap slam: phases=", phases, " peak height=", snappedf(max_height, 0.1), " damage=", snappedf(start_health - downed.health, 0.1),
		" stayed pinned during pull=", stayed_down, " daze stars seen=", daze_seen, " ended at ", player.global_position,
		" aim cleared=", player.model.weapon_aim == null, " mask restored=", player.collision_mask == (Player.LAYER_WORLD | Player.LAYER_ENEMY))
	downed.queue_free()
	await get_tree().process_frame

	# An enemy still tumbling through the air, and one that is almost back on its feet, are slammed too.
	for stage in ["flight", "rising"]:
		player.stats.cooldowns.clear()
		player.global_position = Vector3(32, 0, -12)
		player.reset_physics_interpolation()
		var target: Enemy = _spawn_enemy(Vector3(32, 0, -18))
		target.aggro_range = 0.0
		target.max_health = 800.0
		target.health = 800.0
		await get_tree().process_frame
		target.ragdoll_launch(Vector3(0, 0, -6.0), 5.0, Vector3(4, 0, 0))
		if stage == "rising":
			t = 0.0
			while t < 4.0 and not (target.ragdoll != null and target.ragdoll.state == Ragdoll.State.RISING and target.ragdoll._rise_t > 0.5):
				await get_tree().physics_frame
				t += 1.0 / 60.0
		else:
			await get_tree().create_timer(0.15).timeout
		var before: float = target.health
		player.skills.try_directional("leap", target.global_position)
		var slammed: bool = player.leap.leap_slam
		t = 0.0
		while player.skills.busy and t < 5.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		expect("leap on a %s target is a slam" % stage, slammed and before - target.health > 0.0)
		print("  leap on ", stage, " target: slam chosen=", slammed, " damage=", snappedf(before - target.health, 0.1))
		target.queue_free()
		await get_tree().process_frame

	# Overhead chop on open ground, hitting a standing zombie beside the landing spot.
	player.stats.cooldowns.clear()
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	var standing: Enemy = _spawn_enemy(Vector3(33, 0, -19))
	standing.aggro_range = 0.0
	standing.max_health = 800.0
	standing.health = 800.0
	await get_tree().process_frame
	for attempt in 3:   # the chop can miss at random: leap again rather than fail on bad luck
		player.stats.cooldowns.clear()
		player.stats.mana = player.stats.max_mana
		player.global_position = Vector3(32, 0, -12)
		player.reset_physics_interpolation()
		player.skills.try_directional("leap", Vector3(32, 0, -19))
		phases.clear()
		t = 0.0
		while player.skills.busy and t < 5.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if phases.is_empty() or phases[-1] != player.leap.leap_phase:
				phases.append(player.leap.leap_phase)
		if standing.health < 800.0:
			break
	expect("leap on open ground chops", phases == [1, 2, 3, 0] and standing.health < 800.0)
	print("  leap chop: phases=", phases, " standing zombie damage=", snappedf(800.0 - standing.health, 0.1), " landed at ", player.global_position)
	standing.queue_free()
	await get_tree().process_frame

## Earthshatter: charges only from damage dealt, will not fire until full, then throws everything in the ring up into the air,
## stuns and hurts it, shares a burn with the rest, staggers a boss without throwing it, and slows time briefly (and restores it).
func _test_earthshatter() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.stats.ult_charge = 0.0
	Fx.reset_time()
	var cost: float = player.stats.ult_cost("earthshatter")
	expect("a new hero starts with the ultimate ready", PlayerStats.new(player).can_use("earthshatter"))
	expect("earthshatter has a charge cost and no mana cost", cost > 0.0 and float(SkillDb.all()["earthshatter"]["mana"]) == 0.0)
	var offsets: Array[Vector3] = [Vector3(2, 0, 0), Vector3(-3, 0, 1), Vector3(0, 0, -4), Vector3(4, 0, 3), Vector3(-5, 0, -2), Vector3(1, 0, 5.5)]
	var centre: Vector3 = player.global_position + Vector3(0, 0, -1.2)
	var ring: Array[Enemy] = []
	for offset in offsets:
		var z: Enemy = _spawn_enemy(centre + offset)
		z.aggro_range = 0.0
		z.max_health = 3000.0
		z.health = 3000.0
		ring.append(z)
	var far: Enemy = _spawn_enemy(centre + Vector3(14, 0, 0))
	far.aggro_range = 0.0
	far.max_health = 3000.0
	far.health = 3000.0
	await get_tree().process_frame
	ring[0].apply_burn(6.0, 8.0)
	# It charges from damage the hero deals...
	var dummy: Enemy = ring[1]
	var before_charge: float = player.stats.ult_charge
	# Force critical setup feedback so this fixture also exercises hitstop isolation.
	dummy.receive(Combat.resolve(player, dummy, 60.0, Combat.DamageType.PHYSICAL, false, 1.0, true), player.global_position)
	expect("dealing damage charges the ultimate", player.stats.ult_charge > before_charge + 30.0)
	# ...and not from damage taken.
	var charge_now: float = player.stats.ult_charge
	player.receive(Combat.resolve(dummy, player, 20.0, Combat.DamageType.PHYSICAL, false, 1.0), dummy.global_position)
	expect("taking damage does not charge it", is_equal_approx(player.stats.ult_charge, charge_now))
	# Not full: pressing it does nothing.
	player.skills.try_directional("earthshatter", centre)
	expect("an uncharged ultimate will not start", not player.skills.busy and not player.stats.can_use("earthshatter"))
	# Setup hits can leave global hitstop active. Measure only the ultimate's time effects.
	Fx.reset_time()
	expect("earthshatter measurement starts at normal speed", is_equal_approx(Engine.time_scale, 1.0))
	# Full: it fires.
	player.stats.ult_charge = cost
	var health_before: Dictionary = {}
	for z in ring:
		health_before[z] = z.health
	var far_before: float = far.health
	player.skills.try_directional("earthshatter", centre)
	expect("a full ultimate starts", player.skills.busy and player.earthshatter.phase == 1)
	var phases: Array = []
	var peak: Dictionary = {}
	var min_scale: float = 1.0
	var slow_before_impact: bool = false
	var impact_seen: bool = false
	var t: float = 0.0
	while player.skills.busy and t < 12.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		min_scale = minf(min_scale, Engine.time_scale)
		if player.earthshatter.phase < 3 and not impact_seen:
			slow_before_impact = slow_before_impact or Engine.time_scale < 0.99
		if player.earthshatter.phase >= 3:
			impact_seen = true
		if phases.is_empty() or phases[-1] != player.earthshatter.phase:
			phases.append(player.earthshatter.phase)
		for z in ring:
			if is_instance_valid(z):
				peak[z] = maxf(float(peak.get(z, 0.0)), z.visual.global_position.y)
	expect("earthshatter runs gather/slam/hold/recover", phases == [1, 2, 3, 4, 0])
	var all_hurt: bool = true
	var all_stunned: bool = true
	for z in ring:
		all_hurt = all_hurt and z.health < float(health_before[z])
		all_stunned = all_stunned and z.stun_time > 0.5
	expect("everything in the ring is hurt", all_hurt)
	expect("everything in the ring is stunned", all_stunned)
	expect("it counts its victims", player.earthshatter.victims == ring.size())
	expect("the enemy outside the ring is untouched", is_equal_approx(far.health, far_before))
	var highest: float = 0.0
	var thrown: int = 0
	for z in ring:
		highest = maxf(highest, float(peak.get(z, 0.0)))
		if float(peak.get(z, 0.0)) > 1.0:
			thrown += 1
	expect("the ring is thrown up into the air", thrown == ring.size() and highest > 2.0)
	expect("the burn on one victim is shared with the rest", ring[2].burn_time > 0.0 and ring[3].burn_time > 0.0)
	expect("the ultimate does not charge itself", player.stats.ult_charge < 1.0)
	expect("time slowed during the impact", min_scale < 0.5)
	expect("time runs at full speed until the blade hits the ground", not slow_before_impact)
	await get_tree().create_timer(1.6, true, false, true).timeout
	expect("time is back to normal afterwards", is_equal_approx(Engine.time_scale, 1.0))
	expect("it restores the hero's state", not player.skills.busy and player.collision_mask == (Player.LAYER_WORLD | Player.LAYER_ENEMY))
	print("  earthshatter: phases=", phases, " thrown=", thrown, "/", ring.size(), " highest=", snappedf(highest, 0.1), " m  slowest time scale=",
		snappedf(min_scale, 0.01), " spread transfers=", player.earthshatter.last_spread)
	# A boss is staggered, not thrown.
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	var boss: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -3.5))
	boss.aggro_range = 0.0
	boss.is_boss = true
	boss.max_health = 3000.0
	boss.health = 3000.0
	await get_tree().process_frame
	player.stats.ult_charge = cost
	player.skills.try_directional("earthshatter", boss.global_position)
	t = 0.0
	while player.skills.busy and t < 12.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a boss takes the blow and is staggered but not thrown", boss.health < 3000.0 and boss.stun_time > 0.5 and not boss.is_ragdolled())
	# Cancelling before the blade lands costs nothing.
	await get_tree().create_timer(1.6, true, false, true).timeout
	player.stats.ult_charge = cost
	player.skills.try_directional("earthshatter", boss.global_position)
	await get_tree().create_timer(0.2).timeout
	player.skills.cancel_action()
	expect("cancelling the wind-up keeps the charge", player.stats.ult_charge >= cost and not player.skills.busy)
	boss.queue_free()
	player.stats.ult_charge = 0.0
	Fx.reset_time()
	await get_tree().process_frame

## A Power Strike whose weapon throws a shockwave shows the strip it will hit while the blow is gathered, and the effect meshes load.
func _test_power_wave() -> void:
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.stats.equipment["mod_gravewarden"] = {"affix": "gravewarden", "name": "gravewarden", "rarity": 1, "slot": 0}
	var target: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -2.4))
	target.aggro_range = 0.0
	target.max_health = 900.0
	target.health = 900.0
	await get_tree().process_frame
	expect("the shockwave mesh loads", SkillFx._fx_mesh("power_wave") != null)
	player.skills.start_skill("power", target, null)
	await get_tree().create_timer(0.35).timeout
	var shown: bool = player.skills._wave_preview != null and player.skills._wave_preview.node.visible
	expect("the strip the shockwave will hit is shown while the blow is gathered", shown)
	expect("and the enemy in it glows, so you can see who it will hit", target.highlighted)
	await get_tree().create_timer(1.6).timeout
	expect("and it is gone once the blow has landed", player.skills._wave_preview == null or not player.skills._wave_preview.node.visible)
	player.stats.equipment.erase("mod_gravewarden")
	if is_instance_valid(target):
		target.queue_free()

## Power Strike goes where the cursor points: it picks no target for the hero, so an enemy on the other side is left alone, and one in the
## direction of the cursor is hit when the blade comes down.
func _test_power_direction() -> void:
	player.global_position = _free_lane_start(10.0, 6.0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	await get_tree().process_frame
	var ahead: Enemy = _spawn_enemy(player.global_position + Vector3(2.0, 0, 0))
	var aside: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -2.0))
	for e in [ahead, aside]:
		e.aggro_range = 0.0
		e.max_health = 900.0
		e.health = 900.0
	await get_tree().process_frame
	player.skills.try_directional("power", player.global_position + Vector3(8, 0, 0))
	await get_tree().create_timer(0.2).timeout
	var turned: Vector3 = player.global_position + Vector3(0, 0, -8)   # the cursor moves during the wind-up: the blow follows it
	player.cursor_override = turned
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("the blow follows the cursor while it is being gathered", player.skills.busy_aim.is_equal_approx(turned))
	player.cursor_override = player.global_position + Vector3(8, 0, 0)
	expect("a directed Power Strike starts with no target chosen", player.skills.busy and player.skills.busy_skill == "power" and player.skills.busy_target == null)
	await get_tree().create_timer(1.8).timeout
	for attempt in 3:   # a swing can miss: try again, the point is who it goes for
		if ahead.health < ahead.max_health or ahead.dead:
			break
		player.stats.cooldowns.clear()
		player.stats.mana = player.stats.max_mana
		player.global_position = ahead.global_position - Vector3(2.0, 0, 0)
		player.cursor_override = player.global_position + Vector3(8, 0, 0)
		player.skills.try_directional("power", player.cursor_override)
		await get_tree().create_timer(1.8).timeout
	expect("it hits the enemy in the direction of the cursor", ahead.health < ahead.max_health or ahead.dead)
	expect("and leaves the one in another direction alone", aside.health >= aside.max_health - 0.01)
	player.cursor_override = Vector3.INF
	for e in [ahead, aside]:
		if is_instance_valid(e):
			e.queue_free()

## Skills on keys can be changed freely: the layout is always the same seven skills (a change is a swap), it is shared by the hero, the
## settings and the save, and clicking a hotbar slot opens a picker whose icons put a skill on that key.
func _test_hotbar() -> void:
	GameSettings.reset_hotbar()
	var full_layout: Array[String] = ["power", "fireball", "throw", "skewer", "leap", "earthshatter"]
	var slots: Array[String] = full_layout.duplicate()
	var alt: String = HotbarLayout.assign(slots, HotbarLayout.DEFAULT_ALT, 0, "fireball")
	expect("putting a skill that is elsewhere on a key swaps the two", slots[0] == "fireball" and slots[1] == "power" and alt == "basic")
	alt = HotbarLayout.assign(slots, alt, HotbarLayout.ALT, "throw")
	expect("the mouse button swaps like any other slot", alt == "throw" and slots[2] == "basic" and HotbarLayout.is_valid(slots, alt))
	var benched: Array[String] = full_layout.duplicate()
	var bench_alt: String = HotbarLayout.assign(benched, HotbarLayout.DEFAULT_ALT, 3, "throw")
	expect("a skill from the bench takes a key and the one it replaces goes to the bench", benched[3] == "throw" and not benched.has("skewer") and bench_alt == "basic" and HotbarLayout.is_valid(benched, bench_alt))
	expect("a layout has six slots, permits empty keys, excludes potions, and never duplicates assigned skills", not HotbarLayout.is_valid(["power", "power", "throw", "skewer", "leap", "earthshatter"], "basic")
		and not HotbarLayout.is_valid(["power", "fireball", "potion", "skewer", "leap", "earthshatter"], "basic")
		and not HotbarLayout.is_valid(["power", "fireball", "throw", "skewer", "leap"], "basic") and HotbarLayout.is_valid(HotbarLayout.DEFAULT_SLOTS, "basic"))
	expect("the dodge cannot be put on a key", HotbarLayout.assign(slots, alt, 3, "dodge") == alt and slots[3] == "skewer")
	# The hero's bar IS the settings' layout, so one change shows everywhere.
	GameSettings.reset_hotbar()
	var skills: SkillController = player.skills
	expect("the hero's hotbar is the settings' layout", is_same(skills.hotbar, GameSettings.hotbar_slots) and skills.right_click_skill == "basic")
	# The real click path: open the picker on slot 2, choose Leap.
	await get_tree().process_frame
	await get_tree().process_frame
	var size_px: Vector2 = hud.get_viewport_rect().size
	var second: Dictionary = {}
	var mouse_slot: Dictionary = {}
	for hit in hud._slot_hits:
		if hit["action"] == "skill_2":
			second = {"slot": 1, "rect": hit["rect"]}
		if hit["action"] == "alt_skill":
			mouse_slot = {"slot": HotbarLayout.ALT, "rect": hit["rect"]}
	expect("the hotbar slots are known to the HUD", not second.is_empty() and not mouse_slot.is_empty())
	var press := func(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> bool:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = true
		e.position = at
		return hud.picker.handle_click(e)
	expect("clicking a slot opens the picker for it", press.call((second["rect"] as Rect2).get_center()) and hud.picker.is_open() and hud.picker.open_slot == 1)
	expect("the open picker keeps the world from taking clicks", hud.covers(hud.picker.panel_rect(size_px).get_center()))
	var leap_at: Vector2 = Vector2.ZERO
	for cell in hud.picker.cells(size_px):
		if cell["id"] == "leap":
			leap_at = (cell["rect"] as Rect2).get_center()
	press.call(leap_at)
	expect("choosing Leap puts it on the empty key 2", skills.hotbar[1] == "leap" and not hud.picker.is_open()
		and HotbarLayout.is_valid(skills.hotbar, skills.right_click_skill))
	# The mouse button, and closing without choosing.
	await get_tree().process_frame
	press.call((mouse_slot["rect"] as Rect2).get_center())
	expect("the mouse button's slot opens a picker too", hud.picker.is_open() and hud.picker.open_slot == HotbarLayout.ALT)
	press.call(Vector2(5, 5), MOUSE_BUTTON_RIGHT)
	expect("a right click closes it with nothing changed", not hud.picker.is_open() and skills.right_click_skill == "basic")
	press.call((mouse_slot["rect"] as Rect2).get_center())
	expect("the dedicated potion is absent from the skill picker", not HotbarLayout.ASSIGNABLE.has("potion"))
	var dodge_rect: Rect2 = Rect2()
	for hit in hud._slot_hits:
		if hit["action"] == "dodge":
			dodge_rect = hit["rect"]
	expect("the dodge slot cannot be changed", not press.call(dodge_rect.get_center()) and not hud.picker.is_open())
	# Take Aim can be assigned from the bench, shows in the picker, and commands Cutter.
	press.call((second["rect"] as Rect2).get_center())
	var take_aim_at: Vector2 = Vector2.ZERO
	for cell in hud.picker.cells(size_px):
		if cell["id"] == "take_aim":
			take_aim_at = (cell["rect"] as Rect2).get_center()
	expect("the picker presents Take Aim as an assignable power", take_aim_at != Vector2.ZERO)
	press.call(take_aim_at)
	expect("Take Aim can be assigned to hotbar slot 2", skills.hotbar[1] == "take_aim" and HotbarLayout.is_valid(skills.hotbar, skills.right_click_skill))
	var cutter: ArcherCompanion = game.companion
	if cutter != null:
		cutter.take_aim_armed = false
		cutter.take_aim_reload_remaining = 0.0
		expect("Take Aim is usable when Cutter is ready", player.stats.can_use("take_aim") and is_equal_approx(player.stats.ult_fraction("take_aim"), 1.0))
		skills.activate_take_aim()
		expect("activating Take Aim hotkey arms Cutter", cutter.take_aim_armed)
	GameSettings.reset_hotbar()

## Drive cancellation synchronously so regeneration and input timing cannot mask a spend or refund.
func _test_action_queue() -> void:
	player.set_physics_process(false)
	var s: SkillController = player.skills
	var aim: Vector3 = player.global_position + Vector3(0, 0, -2)
	var target: Enemy = _spawn_enemy(aim)
	target.set_physics_process(false)
	s.reset()
	player.stats.cooldowns.clear()
	player.stats.mana = player.stats.max_mana
	s.queue_skill("basic", aim)
	s.cancel_action()
	expect("idle cancellation drops queued order", s.queued_skill == "" and s.queued_target == null)
	s.reset()
	s.queue_skill("basic", aim)
	s.start_skill("fireball", null, aim)
	expect("immediate skill supersedes queued order", s.queued_skill == "" and s.queued_target == null)
	s.cancel_action()
	s.reset()
	s.queue_skill("basic", aim)
	s.start_skill("basic", target)
	expect("consuming queue clears target ownership", s.queued_skill == "" and s.queued_target == null)
	s.cancel_action()
	s.queue_skill("basic", aim)
	expect("fixture queued target before deletion", s.queued_target == target)
	target.free()
	player._act(0.0, aim)
	expect("freed queue target is dropped", s.queued_skill == "" and s.queued_target == null)
	var next: Enemy = _spawn_enemy(aim)
	next.set_physics_process(false)
	s.queue_skill("basic", aim)
	player.stats.cooldowns.clear()
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(aim)
	expect("idle dodge clears queued target ownership", s.queued_skill == "" and s.queued_target == null)
	player.movement.tick_roll(2.0)
	# Presses on either side of completion retain only the latest intended order.
	for elapsed in [0.0, 0.25, 0.8]:
		s.reset()
		player.stats.cooldowns.clear()
		player.stats.mana = player.stats.max_mana
		s.start_skill("fireball", null, aim)
		s.tick_busy(elapsed)
		s.queue_skill("basic", aim)
		s.queue_skill("basic", aim)
		expect("repeated queue holds one next order", s.queued_skill == "basic" and s.queued_target == next)
		s.tick_busy(s.busy_time)
		var mana: float = player.stats.mana
		var children: int = get_tree().current_scene.get_child_count()
		s.tick_busy(10.0)
		expect("completion cannot replay or spend", is_equal_approx(player.stats.mana, mana) and get_tree().current_scene.get_child_count() == children)
		player._act(0.0, aim)
		expect("completion consumes queued action once", s.busy and s.busy_skill == "basic" and s.queued_skill == "" and s.queued_target == null)
		s.cancel_action()
	# Directional starts and aimed Skewer share queue supersession semantics.
	for id in ["power", "skewer", "leap", "earthshatter"]:
		s.reset()
		player.stats.cooldowns.clear()
		player.stats.mana = player.stats.max_mana
		player.stats.ult_charge = player.stats.ult_cost("earthshatter")
		s.queue_skill("basic", aim)
		s.try_directional(id, aim)
		expect("directional action supersedes queue: " + id, s.busy and s.queued_skill == "" and s.queued_target == null)
		s.cancel_action()
	s.queue_skill("basic", aim)
	player.stats.cooldowns.clear()
	player.stats.potions = 1
	player.health = player.max_health * 0.5
	s.drink_potion()
	expect("idle potion cancels queued action", s.queued_skill == "" and s.queued_target == null and player.stats.potions == 0)
	# Unusable replacement preserves the intended next action without spending.
	s.queue_skill("basic", aim)
	player.stats.cooldowns["fireball"] = 5.0
	s.start_skill("fireball", null, aim)
	expect("rejected replacement preserves queue", s.queued_skill == "basic" and not s.busy)
	player.stats.cooldowns["basic"] = 5.0
	player._act(0.0, aim)
	expect("unusable queued action is dropped without blocking", not s.busy and s.queued_skill == "" and s.queued_target == null)
	player.stats.cooldowns.clear()
	s.queue_skill("basic", aim)
	player.dead = true
	player._on_death()
	s.queue_skill("basic", aim)
	expect("dead input cannot acquire queue ownership", s.queued_skill == "" and s.queued_target == null)
	player.revive_at(player.global_position)
	player.set_physics_process(false)
	player.stats.cooldowns.clear()
	s.start_skill("basic", next)
	expect("revive accepts immediate action", s.busy and s.busy_skill == "basic")
	s.cancel_action()
	# Public throw hooks: sword actions cannot acquire ownership while away/returning.
	player.stats.cooldowns.clear()
	s.queue_skill("basic", aim)
	Input.action_press("skill_6")
	s.handle_aimed_key("skill_6", WeaponThrowSkill.SKILL_ID, aim)
	expect("throw charge supersedes queue", s.queued_skill == "" and s.queued_target == null)
	Input.action_release("skill_6")
	s.handle_aimed_key("skill_6", WeaponThrowSkill.SKILL_ID, aim)
	s.tick_busy(2.0)
	expect("throw fixture reaches away state", player.weapon_throw.is_away())
	for returning in [false, true]:
		if returning:
			Input.action_press("skill_6")
			s.handle_aimed_key("skill_6", WeaponThrowSkill.SKILL_ID, aim)
			Input.action_release("skill_6")
		s.queue_skill("basic", aim)
		s.try_directional("power", aim)
		expect("away/returning weapon rejects sword input", not s.busy and s.queued_skill == "")
	player.weapon_throw.reset()
	next.free()
	s.reset()
	player.set_physics_process(true)

func _test_skill_integrity() -> void:
	player.set_physics_process(false)
	var s: SkillController = player.skills
	var aim: Vector3 = player.global_position + Vector3(0, 0, -6)
	for elapsed in [0.0, 0.25, 0.8]:
		player.stats.mana = player.stats.max_mana
		player.stats.cooldowns.clear()
		s.start_skill("fireball", null, aim)
		s.tick_busy(elapsed)
		var spent: float = player.stats.mana
		s.start_skill("fireball", null, aim)
		expect("repeated start does not spend again", is_equal_approx(player.stats.mana, spent))
		s.cancel_action()
		expect("generic pre-release cancellation refunds Fireball", is_equal_approx(player.stats.mana, player.stats.max_mana) and float(player.stats.cooldowns.get("fireball", 0.0)) == 0.0)
		s.cancel_action()
		expect("repeat cancellation cannot mint mana", is_equal_approx(player.stats.mana, player.stats.max_mana))
	player.stats.cooldowns.clear()
	s.start_skill("fireball", null, aim)
	s.tick_busy(s.busy_time)
	var committed_mana: float = player.stats.mana
	var balls: int = get_tree().current_scene.get_child_count()
	s.tick_busy(10.0)
	expect("finished tick cannot replay Fireball", get_tree().current_scene.get_child_count() == balls)
	s.cancel_action()
	expect("released Fireball keeps its cost", is_equal_approx(player.stats.mana, committed_mana) and float(player.stats.cooldowns.get("fireball", 0.0)) > 0.0)
	for id in ["power", "skewer", "leap", "earthshatter"]:
		player.stats.mana = player.stats.max_mana
		player.stats.cooldowns.clear()
		player.stats.ult_charge = player.stats.ult_cost("earthshatter")
		s.try_directional(id, aim)
		var mana: float = player.stats.mana
		var charge: float = player.stats.ult_charge
		s.try_directional(id, aim)
		expect("repeated directional start spends once: " + id, is_equal_approx(mana, player.stats.mana) and is_equal_approx(charge, player.stats.ult_charge))
		s.cancel_action()
		s.tick_busy(10.0)
		expect("cancel stops component and delayed effects: " + id, not s.busy and player.skewer.skewer_phase == 0 and player.leap.leap_phase == 0 and player.earthshatter.phase == 0)
	# Reset every real phase, including active/recovery, without replacing the death clip.
	for id in ["skewer", "leap", "earthshatter"]:
		for phase in range(1, 6 if id == "skewer" else 5):
			player.stats.mana = player.stats.max_mana
			player.stats.cooldowns.clear()
			player.stats.ult_charge = player.stats.ult_cost("earthshatter")
			s.try_directional(id, aim)
			match id:
				"skewer": player.skewer.skewer_phase = phase
				"leap": player.leap.leap_phase = phase
				"earthshatter": player.earthshatter.phase = phase
			player.model.once("death", 0.0, 1.0, 0.1)
			var clip: String = player.model.current
			player._on_death()
			expect("death cleans phase %d of %s without replacing clip" % [phase, id], not s.busy and player.skewer.skewer_phase == 0 and player.leap.leap_phase == 0 and player.earthshatter.phase == 0 and player.model.current == clip)
	# The potion and legal switch both use the generic cancellation path.
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.stats.potions = 1
	player.health = player.max_health * 0.5
	s.start_skill("fireball", null, aim)
	s.drink_potion()
	expect("potion abort refunds unreleased cast", not s.busy and player.stats.potions == 0 and is_equal_approx(player.stats.mana, player.stats.max_mana))
	player.stats.cooldowns.clear()
	s.start_skill("fireball", null, aim)
	s.cancel_action()
	s.try_directional("power", aim)
	expect("legal switch spends only the replacement skill", s.busy and s.busy_skill == "power" and is_equal_approx(player.stats.mana, player.stats.max_mana - float(SkillDb.all()["power"]["mana"])))
	s.cancel_action()
	var captive: Enemy = _spawn_enemy(aim)
	captive.set_impaled(true)
	player.skewer.skewer_impaled.append(captive)
	player.skewer.skewer_phase = 2
	s.reset()
	expect("reset releases the Skewer captive", not captive.impaled and player.skewer.skewer_impaled.is_empty() and player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY))
	captive.queue_free()
	player.stats.cooldowns.clear()
	s.aiming_id = "fireball"
	s.aiming_action = "skill_2"
	s.aim_blocked = "skill_1"
	s.swallow_alt = true
	s.queued_skill = "power"
	s.start_skill("fireball", null, aim)
	player._on_death()
	expect("death clears action and aim state", not s.busy and s.aiming_id == "" and s.aiming_action == "" and s.queued_skill == "" and s.fire_orb == null)
	player.dead = true
	s.start_skill("fireball", null, aim)
	s.try_directional("earthshatter", aim)
	expect("dead actor cannot restart a skill", not s.busy)
	player.revive_at(player.global_position)
	expect("revive clears blocked input state", s.aim_blocked == "" and not s.swallow_alt and s.busy_def.is_empty() and s.busy_target == null and s.queued_target == null)
	player.set_physics_process(true)
