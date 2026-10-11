extends DevSuite
## Weapon Throw: its self-tests (flight, ownership) and the --skillshot=throw screenshots.

## `-- --skillshot=throw [--equip=Greatsword]`: a full-charge throw through a line of zombies, the weapon in the ground, a recall through
## another group and the catch; frames in %TEMP%/curse_throw_N.png.
func _throw_shots() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--equip="):
			player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, arg.substr(8)), false)
	player.set_physics_process(true)
	var origin: Vector3 = _clear_lane(26.0, 3.0)
	player.global_position = origin
	player.reset_physics_interpolation()
	var wt: WeaponThrowSkill = player.weapon_throw
	var line: Array[Enemy] = []
	for d in [5.0, 7.5, 10.0, 12.5]:
		line.append(_throw_dummy(origin + Vector3(d, 0, 0)))
	await get_tree().create_timer(0.6).timeout
	var frame: int = 0
	wt.begin_charge()
	var aim: Vector3 = origin + Vector3(30, 0, 0)
	player.cursor_override = aim
	for i in 14:   # the wind-up, held about a second
		await get_tree().create_timer(0.1).timeout
		wt.update_preview(aim)
		if i == 5 or i == 11:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_throw_%d.png" % frame)
			frame += 1
	wt.release(aim)
	for i in 16:   # the release, the flight, the embedding
		await get_tree().create_timer(0.09).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_throw_%d.png" % frame)
		frame += 1
	# A close look at the weapon where it lies, and as it is wrenched out.
	var look := Camera3D.new()
	look.fov = 40.0
	get_tree().root.add_child(look)
	look.current = true
	var lie: Vector3 = wt.thrown.center() if wt.thrown != null else origin
	look.global_position = lie + Vector3(-2.6, 1.9, 3.2)
	look.look_at(lie + Vector3(0, 0.3, 0))
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_throw_embed.png")
	wt.recall()
	for k in 4:
		await get_tree().create_timer(0.14).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_throw_rip_%d.png" % k)
	await get_tree().create_timer(2.5).timeout
	look.queue_free()
	player.global_position = origin
	var second_spot: Vector3 = origin + Vector3(4.0, 0, 8.0)
	player.global_position = second_spot
	player.reset_physics_interpolation()
	for k in [0.4, 0.7]:
		_throw_dummy(Vector3(origin.x + 12.0, 0, origin.z).lerp(second_spot, k))
	await get_tree().create_timer(0.5).timeout
	wt.state = WeaponThrowSkill.State.IN_HAND
	for i in 2:
		await get_tree().create_timer(0.1).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_throw_%d.png" % frame)
		frame += 1
	print("throw shots done, state ", wt.state)
	get_tree().quit()

## Deterministic component interruption checks; the weaponthrow suite covers real input/travel.
func _test_throw_ownership() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var wt: WeaponThrowSkill = player.weapon_throw
	var skills: SkillController = player.skills
	player.set_physics_process(false) # advance the component explicitly, without timing races
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "Longsword"), false)
	player.global_position = _clear_lane(26.0, 3.0)
	player.stun_time = 0.0
	player.movement.rolling = false
	var aim: Vector3 = player.global_position + Vector3(25, 0, 0)
	wt.reset()
	player.stats.cooldowns.clear()
	wt.begin_charge()
	wt.tick(0.5)
	var held: float = wt.charge_fraction()
	wt.begin_charge()
	expect("repeated begin does not restart the charge", is_equal_approx(wt.charge_fraction(), held))
	wt.cancel_charge()
	wt.cancel_charge()
	expect("cancel is repeatable with no spend or hidden blade", wt.has_weapon() and player.model.weapon.visible and not player.stats.weapon_locked and player.stats.cooldowns.is_empty())
	# Death/reset from every state, including the recovery after the catch frame.
	for phase in ["charge", "release", "outbound", "embedded", "rip", "return", "catch", "recovery"]:
		wt.reset()
		skills.busy = false
		player.stats.cooldowns.clear()
		wt.begin_charge()
		wt.tick(0.5)
		if phase == "charge":
			skills.aiming_id = "throw"
			skills.aiming_action = "skill_2"
		if phase != "charge":
			wt.release(aim)
			wt.release(aim) # duplicate release must not spawn twice or reset commitment
		if phase not in ["charge", "release"]:
			wt.tick_busy(0.21)
			var copy: ThrownWeapon = wt.thrown
			wt.begin_charge()
			expect("begin while away preserves ownership (%s)" % phase, wt.state == WeaponThrowSkill.State.FLYING_OUT and wt.thrown == copy)
		if phase in ["embedded", "rip", "return", "catch", "recovery"]:
			wt._embed(player.global_position + Vector3(10, 0, 0), Vector3.UP, false)
			if phase == "embedded":
				await _throw_ownership_png("embedded")
		if phase in ["rip", "return", "catch", "recovery"]:
			expect("embedded recall starts once (%s)" % phase, wt.recall() and not wt.recall())
		if phase in ["return", "catch", "recovery"]:
			wt.tick(float(wt._profile["rip_time"]))
			expect("return recall cannot restart damage history", wt.state == WeaponThrowSkill.State.RETURNING and not wt.recall())
		if phase in ["catch", "recovery"]:
			wt._pos = wt._hand_point() + Vector3(1.5, 0, 0)
			wt.thrown.set_pose(wt._pos, Vector3.UP)
			wt._begin_catch()
		if phase == "recovery":
			await _throw_ownership_png("catch")
			var caught_copy: ThrownWeapon = wt.thrown
			wt.tick_busy(float(wt._profile["catch_time"]))
			expect("catch frame keeps its intended recovery", wt.has_weapon() and skills.busy)
			expect("catch hides the old copy before showing the held blade", not caught_copy.visible and player.model.weapon.visible and wt.thrown == null)
			var effects: int = player.get_parent().get_child_count()
			wt._complete_catch()
			expect("a second catch has no extra effects", player.get_parent().get_child_count() == effects)
		var old_copy: ThrownWeapon = wt.thrown
		player.dead = true
		player._on_death() # existing hook, no player implementation changes
		wt.reset()
		expect("death/reset unlocks weapon AND throw action (%s)" % phase, wt.has_weapon() and wt.thrown == null and player.model.weapon.visible and not player.stats.weapon_locked and not skills.busy and skills.aiming_id != "throw")
		if is_instance_valid(old_copy):
			expect("discarded thrown visual is hidden immediately (%s)" % phase, not old_copy.visible)
		player.revive_at(player.global_position)
		player.set_physics_process(false)
		await get_tree().process_frame
		player.stats.cooldowns.clear()
		expect("revive permits a fresh throw (%s)" % phase, wt.can_begin())
		if phase == "recovery":
			await _throw_ownership_png("recovered")
	# Interrupt release before its strike: no copy, damage, cooldown or lock.
	wt.begin_charge()
	wt.release(aim)
	skills.cancel_action()
	wt.tick(0.01)
	expect("cancelled release leaves nothing spent or stranded", wt.has_weapon() and wt.thrown == null and not player.stats.weapon_locked and player.stats.cooldowns.is_empty())
	# Real sweeps against a stationary enemy: one outgoing and one return hit,
	# even when recall and the same sweep are repeated.
	player.stats.cooldowns.clear()
	wt.begin_charge()
	wt.release(aim)
	wt.tick_busy(0.21)
	var victim: Enemy = _throw_dummy(player.global_position + Vector3(4, 0, 0))
	victim.set_physics_process(false)
	var from: Vector3 = player.global_position + Vector3(2, 1, 0)
	var to: Vector3 = player.global_position + Vector3(6, 1, 0)
	wt._sweep(from, to, true)
	wt._sweep(from, to, true)
	expect("repeated outgoing sweep hits/procs once", wt.last_out_hits.count(victim.get_instance_id()) == 1 and wt.proc_hits == 1)
	expect("outbound forced recall starts once", wt.recall() and not wt.recall())
	wt._sweep(to, from, false)
	var after_return: float = victim.health
	wt.recall()
	wt._sweep(to, from, false)
	expect("repeated recall/sweep does not repeat return damage or procs", wt.last_return_hits.count(victim.get_instance_id()) == 1 and is_equal_approx(victim.health, after_return) and wt.proc_hits == 0)
	victim.free()
	wt.tick(0.01)
	expect("target removed during return does not strand weapon", wt.is_away())
	wt._begin_catch()
	skills.cancel_action()
	wt.tick(0.01)
	expect("interrupted catch restores one blade and unlocked slot", wt.has_weapon() and wt.thrown == null and player.model.weapon.visible and not player.stats.weapon_locked)
	wt.reset()
	# Scene cleanup can remove the visual while the component still owns it.
	player.stats.cooldowns.clear()
	wt.begin_charge()
	wt.release(aim)
	wt.tick_busy(0.21)
	wt.thrown.free()
	wt.tick(0.01)
	expect("lost thrown node recovers equipment/action ownership", wt.has_weapon() and wt.thrown == null and not player.stats.weapon_locked and not skills.busy)
	# A normal sword action must not be cancelled by an idempotent throw reset.
	skills.busy = true
	skills.busy_skill = "basic"
	wt.reset()
	expect("reset leaves another skill's action alone", skills.busy)
	skills.busy = false
	player.set_physics_process(true)

func _throw_ownership_png(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--throwownershipshots"):
		return
	var camera := Camera3D.new()
	get_tree().root.add_child(camera)
	camera.current = true
	var at: Vector3 = player.weapon_throw.weapon_position() if label == "embedded" else player.global_position + Vector3(0, 1, 0)
	camera.global_position = at + Vector3(-3, 2.5, 4)
	camera.look_at(at)
	await RenderingServer.frame_post_draw
	var path: String = "res://.agentbridge/weaponthrow-%s.png" % label
	expect("PNG saved: %s" % label, get_viewport().get_texture().get_image().save_png(path) == OK)
	camera.queue_free()

func _test_weapon_throw() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var skills: SkillController = player.skills
	var wt: WeaponThrowSkill = player.weapon_throw
	var saved_hotbar: Array[String] = skills.hotbar.duplicate()
	skills.hotbar[1] = "throw"
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "Longsword"), false)
	player.stats.cooldowns.clear()
	player.health = player.max_health
	player.global_position = _clear_lane(26.0, 3.0)
	player.reset_physics_interpolation()
	var start: Vector3 = player.global_position
	player.cursor_override = start + Vector3(30, 0, 0)
	await get_tree().create_timer(0.3).timeout
	# --- Charging: held key, preview grows, range grows -------------------------------------------------------------------------
	expect("Weapon Throw is on the bar and ready", SkillDb.all().has("throw") and wt.can_begin() and wt.has_weapon())
	Input.action_press("skill_2")
	await get_tree().create_timer(0.35).timeout
	expect("holding the key starts the wind-up", wt.charging() and skills.aiming_id == "throw")
	var early_lane: float = wt.preview.length if wt.preview != null else 0.0
	var early_range: float = wt.range_at(wt.charge_fraction())
	var early_speed: float = wt.move_factor()
	await get_tree().create_timer(0.7).timeout
	var later_lane: float = wt.preview.length
	expect("the preview lane is shown and grows the longer it is held", wt.preview.node.visible and later_lane > early_lane + 2.0)
	expect("the projected range is continuous and grows with the charge", wt.range_at(wt.charge_fraction()) > early_range + 3.0 and early_range >= 5.0)
	expect("he gets slower and plants his feet as the wind-up builds", wt.move_factor() < early_speed and wt.move_factor() <= 0.3)
	var full_charge_range: float = wt.range_at(1.0)
	expect("a tap throws about 5-7 m and a full hold 20-25 m", wt.range_at(0.0) >= 5.0 and wt.range_at(0.0) <= 7.0 and full_charge_range >= 20.0 and full_charge_range <= 25.0)
	# --- A line of enemies for the full-charge throw ------------------------------------------------------------------------------
	start = player.global_position   # (he drifts a little while winding up: the line is laid where he stands now)
	player.cursor_override = start + Vector3(30, 0, 0)
	var line: Array[Enemy] = []
	for d in [5.5, 8.0, 10.5]:
		line.append(_throw_dummy(start + Vector3(d, 0, 0)))
	var heavy: Enemy = _throw_dummy(start + Vector3(14.0, 0, 3.0), "brute")
	await get_tree().process_frame
	var line_health: Array[float] = []
	for e in line:
		line_health.append(e.health)
	Input.action_release("skill_2")
	for k in 6:
		await get_tree().physics_frame
		expect("letting go starts the release", await _wait_state(WeaponThrowSkill.State.FLYING_OUT, 1.2))
	expect("the weapon in his hand is gone: only the thrown one is there", not player.model.weapon.visible and wt.thrown != null and wt.thrown.model_count() > 0)
	var visible_copies: int = 0
	for node in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree() and (wt.thrown.is_ancestor_of(mi) or player.model.weapon.is_ancestor_of(mi)):
			visible_copies += 1
	expect("never a second copy of the weapon: every visible blade mesh belongs to the thrown one", visible_copies == wt.thrown.model_count())
	expect("the cooldown starts at the throw", float(player.stats.cooldowns.get("throw", 0.0)) > 13.0)
	expect("sword skills refuse while the weapon is out", wt.is_away() and not skills.weapon_ready("basic") and not skills.weapon_ready("power"))
	expect("the weapon slot is locked while it is out", player.stats.weapon_locked)
	var held: Dictionary = player.stats.equipment[Items.Slot.WEAPON]
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "Falchion"), false)
	expect("the weapon in the slot cannot be swapped while it is away", player.stats.equipment[Items.Slot.WEAPON] == held)
	skills.start_skill("basic", line[0])
	expect("a basic attack does nothing weaponless", not skills.busy or skills.busy_skill == "throw")
	var travelled_first: Vector3 = wt.weapon_position()
	await get_tree().physics_frame
	expect("it travels through the world (it is not placed at the end at once)", wt.weapon_position().distance_to(travelled_first) > 0.2 or wt.state == WeaponThrowSkill.State.EMBEDDED)
	expect("it embeds at the end", await _wait_state(WeaponThrowSkill.State.EMBEDDED, 3.0))
	var rest: Vector3 = wt.thrown.center()
	await get_tree().create_timer(0.8).timeout
	expect("the weapon stays where it landed", wt.state == WeaponThrowSkill.State.EMBEDDED and wt.thrown.center().distance_to(rest) < 0.05)
	expect("the blade is in the ground at a slant, not lying flat or hovering", wt.thrown.tip().y < 0.05 and absf(wt.thrown.axis().y) > 0.5 and wt.thrown.axis().y < 0.0)
	var struck: int = 0
	var launched_zombies: int = 0
	for i in line.size():
		var e: Enemy = line[i]
		if is_instance_valid(e) and (e.health < line_health[i] - 1.0 or e.dead):
			struck += 1
		if is_instance_valid(e) and (e.is_ragdolled() or e.global_position.x > start.x + 3.0 + [5.5, 8.0, 10.5][i] or e.dead):
			launched_zombies += 1
	expect("a full-charge throw hits all three enemies in the line", struck == 3 and wt.last_out_hits.size() >= 3)
	expect("light enemies are knocked flying by it", launched_zombies >= 2)
	expect("it does not impale or carry anyone like Skewer", line.all(func(e: Enemy) -> bool: return not is_instance_valid(e) or not e.impaled))
	expect("only the first hit of a pass can set off on-hit effects (no cascade)", wt.proc_hits == 1)
	expect("the throw went about as far as a full charge", rest.distance_to(Vector3(start.x, 0.0, start.z)) > 15.0)
	expect("the brute off the line is not touched", is_instance_valid(heavy) and heavy.health >= heavy.max_health - 0.5)
	# --- Recall from another spot: a different line, through a second group -----------------------------------------------------
	var second: Array[Enemy] = []
	var hero_spot: Vector3 = Vector3(rest.x - 14.0, 0.0, rest.z + 7.0)
	player.global_position = hero_spot
	player.reset_physics_interpolation()
	player.movement.has_goal = false
	for fraction in [0.4, 0.65]:
		var on_path: Vector3 = Vector3(rest.x, 0.0, rest.z).lerp(hero_spot, fraction)   # on the straight line from where the weapon lies to where he now stands
		second.append(_throw_dummy(on_path))
	await get_tree().create_timer(0.3).timeout
	expect("the throw cooldown is still running", float(player.stats.cooldowns.get("throw", 0.0)) > 5.0)
	var cooldown_before: float = float(player.stats.cooldowns["throw"])
	Input.action_press("skill_2")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("skill_2")
	expect("the same key recalls it, cooldown or not", wt.state == WeaponThrowSkill.State.RIPPING or wt.state == WeaponThrowSkill.State.RETURNING)
	expect("the weapon is wrenched out of the ground and then comes back", await _wait_state(WeaponThrowSkill.State.RETURNING, 2.0))
	var came_back: bool = await _wait_state(WeaponThrowSkill.State.CATCHING, 5.0)
	expect("it flies back to him (it is not teleported)", came_back and wt.thrown != null)
	expect("the return line passed through the second group, a different line from the first", second.any(func(e: Enemy) -> bool: return is_instance_valid(e) and wt.last_return_hits.has(e.get_instance_id())))
	expect("the way back also hit enemies hard enough to hurt them", second.any(func(e: Enemy) -> bool: return is_instance_valid(e) and (e.health < e.max_health - 1.0 or e.dead)))
	expect("he reaches for it (a catch, not a vanishing act)", skills.busy and skills.busy_skill == "throw")
	expect("the catch frame puts it in his hand once", await _wait_state(WeaponThrowSkill.State.IN_HAND, 2.0))
	expect("exactly one weapon: his hand's is back, the thrown copy is gone", player.model.weapon.visible and wt.thrown == null and not player.stats.weapon_locked)
	expect("the cooldown ran on through the whole thing and the catch did not reset it", float(player.stats.cooldowns.get("throw", 0.0)) <= cooldown_before and float(player.stats.cooldowns.get("throw", 0.0)) > 3.0)
	await get_tree().create_timer(0.6).timeout
	expect("sword skills work again at once", skills.weapon_ready("basic"))
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "Falchion"), false)
	expect("and he may change weapons again", player.stats.equipment[Items.Slot.WEAPON]["name"] == "Falchion")
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "Longsword"), false)
	skills.start_skill("basic", second[0] if is_instance_valid(second[0]) else null)
	expect("normal sword combat resumes", skills.busy and skills.busy_skill == "basic")
	skills.cancel_action()
	# --- Tap versus full charge, and light versus heavy -------------------------------------------------------------------------
	player.stats.cooldowns.clear()
	var results: Dictionary = {}
	for label in ["tap", "full"]:
		for node in get_tree().get_nodes_in_group("enemies"):
			node.queue_free()
		await get_tree().process_frame
		player.global_position = _clear_lane(26.0, 3.0)
		player.reset_physics_interpolation()
		var origin: Vector3 = player.global_position
		var light: Enemy = _throw_dummy(origin + Vector3(4.5, 0, 0))
		var big: Enemy = _throw_dummy(origin + Vector3(4.5, 0, 2.4), "brute")
		await get_tree().process_frame
		wt._profile = wt.profile()
		wt.state = WeaponThrowSkill.State.CHARGING
		wt._hold = 0.0 if label == "tap" else 10.0
		wt.charge = wt.charge_fraction()
		wt.release(origin + Vector3(30, 0, 0))
		await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
		results[label] = {"range": wt.thrown.center().distance_to(Vector3(origin.x, 0.0, origin.z)), "light_hp": light.max_health - light.health,
			"light_move": light.global_position.distance_to(origin + Vector3(4.5, 0, 0)), "big_move": big.global_position.distance_to(origin + Vector3(4.5, 0, 2.4)),
			"big_hp": big.max_health - big.health}
		wt.recall()
		await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
		player.stats.cooldowns.clear()
	expect("a tap travels shorter than a full charge", results["tap"]["range"] < results["full"]["range"] - 5.0)
	expect("a full charge hits harder", results["full"]["light_hp"] > results["tap"]["light_hp"] * 1.4)
	expect("a light zombie is thrown further than the brute is moved", results["full"]["light_move"] > results["full"]["big_move"] + 1.0)
	# --- Solid world and props -----------------------------------------------------------------------------------------------------
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var lane: Vector3 = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	arena.place_prop("barrel", lane + Vector3(6.0, 0, 0), 0.0, 1.0)
	var barrel: Destructible = Destructible.near(get_tree(), lane + Vector3(6.0, 0, 0), 0.5)
	var barrel_placed: bool = barrel != null
	var wall := StaticBody3D.new()   # a solid wall across the lane, 13 m out
	wall.collision_layer = Actor.LAYER_WORLD
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1.0, 4.0, 5.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	game.add_child(wall)
	wall.global_position = lane + Vector3(13.5, 2.0, 0.0)
	await get_tree().process_frame
	wt._profile = wt.profile()
	wt.state = WeaponThrowSkill.State.CHARGING
	wt._hold = 10.0
	wt.charge = 1.0
	wt.release(lane + Vector3(40.0, 0, 0))
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	expect("a full-charge throw smashes a barrel in its way", barrel_placed and (not is_instance_valid(barrel) or barrel.broken))
	expect("a wall stops the weapon and it sticks in it", wt.thrown.center().x < lane.x + 13.5 and wt.thrown.center().x > lane.x + 10.0)
	wall.queue_free()
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	# --- Safety ----------------------------------------------------------------------------------------------------------------------
	player.stats.cooldowns.clear()
	player.global_position = _clear_lane(26.0, 3.0)
	player.reset_physics_interpolation()
	wt._profile = wt.profile()
	wt.state = WeaponThrowSkill.State.CHARGING
	wt._hold = 10.0
	wt.charge = 1.0
	wt.release(player.global_position + Vector3(30, 0, 0))
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	wt._embed_center = Vector3(0, -80, 0)   # fell out of the world
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("a weapon that left the world is put back on the ground and can still be recalled", wt.state == WeaponThrowSkill.State.EMBEDDED and wt._valid(wt._embed_center))
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.RETURNING, 2.0)
	player.stats.cooldowns.clear()
	player._on_death()
	expect("dying with the weapon out puts it back in his hand: nothing stranded or duplicated", wt.state == WeaponThrowSkill.State.IN_HAND and player.model.weapon.visible and wt.thrown == null and not player.stats.weapon_locked)
	player.dead = false
	player.health = player.max_health
	# --- Profiles and the controller -----------------------------------------------------------------------------------------------
	var profiles: Dictionary = {}
	for base in ["Falchion", "Longsword", "Greatsword"]:
		player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, base), false)
		profiles[base] = wt.profile()
	expect("the three weapons throw differently", profiles["Falchion"]["charge_time"] < profiles["Longsword"]["charge_time"] and profiles["Longsword"]["charge_time"] < profiles["Greatsword"]["charge_time"]
		and profiles["Falchion"]["speed"] > profiles["Greatsword"]["speed"] and profiles["Greatsword"]["mass"] > profiles["Falchion"]["mass"] and profiles["Greatsword"]["prop_force"] > profiles["Longsword"]["prop_force"])
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "Longsword"), false)
	player.stats.cooldowns.clear()
	Gamepad.active = true
	player.cursor_override = Vector3.INF
	player.global_position = _clear_lane(26.0, 3.0)
	player.reset_physics_interpolation()
	player.visual.rotation.y = PI * 0.5
	Input.action_press("skill_2")
	await get_tree().create_timer(0.5).timeout
	expect("with a controller the same held action winds up, aimed by the pad aim", wt.charging() and wt.aim_dir.dot(Vector3(1, 0, 0)) > 0.5)
	Input.action_release("skill_2")
	expect("and letting go throws", await _wait_state(WeaponThrowSkill.State.FLYING_OUT, 1.5))
	await get_tree().create_timer(0.3).timeout
	Input.action_press("skill_2")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("skill_2")
	expect("pressing it again recalls on a controller too", wt.state == WeaponThrowSkill.State.RETURNING or wt.state == WeaponThrowSkill.State.RIPPING or wt.state == WeaponThrowSkill.State.EMBEDDED)
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	Gamepad.active = false
	player.cursor_override = Vector3.INF
	# --- Cancel ---------------------------------------------------------------------------------------------------------------------
	player.stats.cooldowns.clear()
	player.cursor_override = player.global_position + Vector3(10, 0, 0)
	Input.action_press("skill_2")
	await get_tree().create_timer(0.3).timeout
	expect("winding up again", wt.charging())
	Input.action_press("dodge")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("dodge")
	Input.action_release("skill_2")
	await get_tree().create_timer(0.3).timeout
	expect("a dodge cancels the wind-up and spends no cooldown", wt.has_weapon() and float(player.stats.cooldowns.get("throw", 0.0)) <= 0.01 and player.model.weapon.visible)
	skills.hotbar.assign(saved_hotbar)
	player.cursor_override = Vector3.INF
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
