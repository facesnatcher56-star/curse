extends DevSuite
## Self-test: knock-downs (monsters and hero), death ragdolls and gibs.

## Crit kills burst into gore, fireball kills into burning pieces, plain kills just fall over.
func _test_gibs() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("gibs"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(-30, 0, 30)
	player.reset_physics_interpolation()
	var crit_victim: Enemy = _spawn_enemy(Vector3(-30, 0, 24))
	var plain_victim: Enemy = _spawn_enemy(Vector3(-24, 0, 30))
	var fire_victim: Enemy = _spawn_enemy(Vector3(-36, 0, 30))
	for e in [crit_victim, plain_victim, fire_victim]:
		e.aggro_range = 0.0
	await get_tree().process_frame
	var crit: Dictionary = Combat.resolve(player, crit_victim, 500.0, Combat.DamageType.PHYSICAL, false, 1.5, true)
	crit_victim.receive(crit, player.global_position)
	await get_tree().process_frame
	var gore_chunks: int = get_tree().get_nodes_in_group("gibs").size()
	var gore_hidden: bool = not crit_victim.visual.visible
	var gore_burning: int = 0
	for g in get_tree().get_nodes_in_group("gibs"):
		if (g as GibChunk).burning:
			gore_burning += 1
	var plain: Dictionary = Combat.resolve(player, plain_victim, 500.0, Combat.DamageType.PHYSICAL, false, 1.0, false)
	plain["outcome"] = Combat.Outcome.HIT
	plain_victim.receive(plain, player.global_position)
	await get_tree().process_frame
	var plain_chunks: int = get_tree().get_nodes_in_group("gibs").size() - gore_chunks
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.damage = 500.0
	ball.destination = fire_victim.global_position
	add_child(ball)
	ball.global_position = fire_victim.global_position + Vector3(0, 1.0, 0)
	ball._explode()
	await get_tree().process_frame
	var fire_chunks: int = get_tree().get_nodes_in_group("gibs").size() - gore_chunks - plain_chunks
	var fire_burning: int = 0
	for g in get_tree().get_nodes_in_group("gibs"):
		if (g as GibChunk).burning:
			fire_burning += 1
	var fire_hidden: bool = not fire_victim.visual.visible
	await get_tree().create_timer(2.5).timeout
	var grounded: int = 0
	for g in get_tree().get_nodes_in_group("gibs"):
		if (g as Node3D).global_position.y < 0.3:
			grounded += 1
	expect("crit kill bursts into non-burning gore", gore_chunks > 0 and gore_hidden and gore_burning == 0)
	expect("plain kill leaves the body", plain_chunks == 0 and plain_victim.visual.visible)
	expect("fireball kill bursts into burning pieces", fire_chunks > 0 and fire_burning == fire_chunks and fire_hidden)
	expect("gib pieces land", grounded > 0)
	print("  gibs: crit kill -> ", gore_chunks, " chunks (burning=", gore_burning, ") body hidden=", gore_hidden, "; plain kill -> ", plain_chunks,
		" chunks, body visible=", plain_victim.visual.visible, "; fireball kill -> ", fire_chunks, " chunks (burning=", fire_burning, ") body hidden=",
		fire_hidden, "; pieces on the ground after 2.5 s: ", grounded)
	for node in get_tree().get_nodes_in_group("gibs"):
		node.queue_free()
	for e in [crit_victim, plain_victim, fire_victim]:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame

## A killed enemy goes ragdoll, thrown away from the blow, and stays down: every kind of enemy, and also one killed while it is
## already getting back up (it used to finish standing, then stand there dead).
func _test_death_ragdoll() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var variants: Array[String] = ["zombie", "brute", "ghoul", "spitter", "bloater", "priest"]
	for i in variants.size():
		var variant: String = variants[i]
		var victim: Enemy = _spawn_enemy(Vector3(-15.0 + 6.0 * i, 0, -12), variant)
		victim.health = 1.0
		victim.aggro_range = 0.0
		await get_tree().create_timer(0.2).timeout
		var killed_at: Vector3 = victim.global_position
		var blow: Dictionary = Combat.resolve(player, victim, 500.0, Combat.DamageType.PHYSICAL, false, 2.0)
		blow["outcome"] = Combat.Outcome.HIT   # a plain hit, so it is not turned into gore
		victim._pending_gib = ""
		victim.receive(blow, killed_at + Vector3(0, 0, 2.0))
		expect("a killed %s goes ragdoll" % variant, victim.dead and victim.is_ragdolled())
		await get_tree().create_timer(1.8).timeout
		var thrown: Vector3 = victim.global_position - killed_at
		expect("a killed %s is thrown away from the blow (from +Z)" % variant, thrown.z < -0.4)
		expect("a killed %s is lying down, not standing" % variant, victim.ragdoll != null and victim.ragdoll.permanent and victim.ragdoll.state == Ragdoll.State.LYING)
		victim.queue_free()
	# Knocked down, getting up, and then killed.
	var riser: Enemy = _spawn_enemy(Vector3(0, 0, -8))
	riser.aggro_range = 0.0
	riser.max_health = 500.0
	riser.health = 500.0
	await get_tree().process_frame
	riser.ragdoll_launch(Vector3(0, 0, -2.0), 3.0, Vector3(3, 0, 0))
	var t: float = 0.0
	while t < 5.0 and (riser.ragdoll == null or riser.ragdoll.state != Ragdoll.State.RISING):
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("the test enemy reached the getting-up stage", riser.ragdoll != null and riser.ragdoll.state == Ragdoll.State.RISING)
	var finish: Dictionary = Combat.resolve(player, riser, 5000.0, Combat.DamageType.PHYSICAL, false, 1.0)
	finish["outcome"] = Combat.Outcome.HIT
	riser._pending_gib = ""
	riser.receive(finish, riser.global_position + Vector3(0, 0, 2.0))
	var stood_up: bool = false
	t = 0.0
	while t < 2.5:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		stood_up = stood_up or riser.ragdoll == null or riser.ragdoll.state == Ragdoll.State.OFF or riser.ragdoll.state == Ragdoll.State.RISING
	expect("an enemy killed while getting up lies back down and stays down", riser.dead and not stood_up and riser.ragdoll != null and riser.ragdoll.state == Ragdoll.State.LYING)
	riser.queue_free()
	await get_tree().process_frame

## The hero's knockdown: a heavy blow (the old heavy-stagger trigger) puts him down -> downed -> getting up -> control; nothing works
## while he is down; Iron Recovery rides on the completed get-up only; death cancels the fall and revival leaves him standing and free.
func _test_hero_knockdown() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.dev_set_hero_level(10)
	TownState.buy_passive("iron_recovery")
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var kd: Knockdown = player.knockdown
	var wt: WeaponThrowSkill = player.weapon_throw
	var hit_hero: Callable = func(damage: float, weight: float) -> void:
		var attacker: Enemy = _throw_dummy(player.global_position + Vector3(2.5, 0, 0))
		var result: Dictionary = Combat.resolve(attacker, player, damage, Combat.DamageType.PHYSICAL, false, weight)
		result["outcome"] = Combat.Outcome.CRUSHING
		result["damage"] = damage
		result["weight"] = weight
		player.invulnerable_time = 0.0
		player.receive(result, attacker.global_position)
		player.knock = Vector3.ZERO
		attacker.queue_free()
	var calm: Callable = func() -> void:
		kd.reset()
		player.stun_time = 0.0
		player.invulnerable_time = 0.0
		player.health = player.max_health
		player.attack_target = null
		player.movement.has_goal = false
		player.skills.busy = false
		player.skills.aiming_id = ""
		player.iron_shoves = 0
		player.global_position = Vector3.ZERO
		player.reset_physics_interpolation()
	await calm.call()
	var ring: Array[Enemy] = []
	for angle in [0.0, 2.1, 4.2]:
		ring.append(_throw_dummy(Vector3(cos(angle), 0, sin(angle)) * 2.0))
	# An ordinary (light) stagger: no knockdown, no Iron Recovery.
	hit_hero.call(4.0, 1.0)
	expect("a light stagger does not knock him down", not kd.active() and kd.knockdowns == 0 and player.stun_time > 0.0)
	await get_tree().create_timer(1.0).timeout
	expect("and Iron Recovery does not fire on an ordinary stagger", player.iron_shoves == 0)
	await calm.call()
	for i in ring.size():
		ring[i].global_position = Vector3(cos(float(i) * 2.1), 0, sin(float(i) * 2.1)) * 2.0
		ring[i].knock = Vector3.ZERO
		ring[i].stun_time = 0.0
	var ring_start: Array[Vector3] = []
	for e in ring:
		ring_start.append(e.global_position)
	# A heavy blow.
	var cooldowns_before: Dictionary = player.stats.cooldowns.duplicate()
	hit_hero.call(20.0, 2.7)
	var health_after_blow: float = player.health
	expect("a heavy blow puts him in the impact phase of a knockdown", kd.active() and kd.phase == Knockdown.Phase.IMPACT and kd.knockdowns == 1)
	expect("the blow cost its damage once (20 of %d)" % int(player.max_health), absf((player.max_health - health_after_blow) - 20.0) < 8.0 and health_after_blow < player.max_health)
	expect("he keeps his weapon through the fall", wt.has_weapon() and not wt.is_away())
	# Walk the phases, trying to act all the way down.
	var foe: Enemy = _throw_dummy(Vector3(2.0, 0, 3.0))
	var seen: Array[String] = []
	var lock_ok: bool = true
	var tried_at_downed: bool = false
	var held_position: Vector3 = player.global_position
	var elapsed: float = 0.0
	player.cursor_override = foe.global_position
	while kd.active() and elapsed < 3.0:
		if seen.is_empty() or seen[-1] != kd.phase_name():
			seen.append(kd.phase_name())
		var pressing: bool = not (kd.phase == Knockdown.Phase.GETTING_UP and kd.phase_time > Knockdown.GET_UP_TIME - 0.05)   # (the very frame he stands, he may act: not tested)
		if pressing:
			player.movement.goal = Vector3(8, 0, 0)
			player.movement.has_goal = true
			Input.action_press("dodge")
			Input.action_press("alt_skill")
			Input.action_press("skill_2")
		await get_tree().physics_frame
		Input.action_release("dodge")
		Input.action_release("alt_skill")
		Input.action_release("skill_2")
		elapsed += get_physics_process_delta_time()
		if kd.is_downed() and not tried_at_downed:
			held_position = player.global_position   # (the blow's own shove has played out by now)
		if kd.active():
			lock_ok = lock_ok and not player.movement.rolling and not player.skills.busy and player.skills.aiming_id == "" and not wt.can_begin() \
				and (not tried_at_downed or player.global_position.distance_to(held_position) < 0.05) and player.stun_time > 0.0
			tried_at_downed = tried_at_downed or kd.is_downed()
	player.movement.has_goal = false
	player.cursor_override = Vector3.INF
	expect("the phases run impact -> downed -> getting_up -> none (saw %s)" % ", ".join(seen), seen == ["impact", "downed", "getting_up"] and not kd.active())
	expect("while he is down he cannot move, attack, dodge or cast (and was tested while downed)", lock_ok and tried_at_downed and kd.get_ups == 1)
	expect("the whole fall is a deliberate %.2f s, not an endless lockout" % Knockdown.TOTAL_TIME, elapsed > Knockdown.TOTAL_TIME - 0.15 and elapsed < Knockdown.TOTAL_TIME + 0.5)
	expect("control is back at the end: no stun, standing upright, the throw can start again", player.stun_time == 0.0 and absf(player.visual.rotation.x) < 0.01 and absf(player.visual.position.y) < 0.01 and wt.can_begin())
	expect("Iron Recovery fired exactly once, on the completed get-up", player.iron_shoves == 1)
	await get_tree().create_timer(0.5).timeout
	var shoved: bool = true
	for i in ring.size():
		shoved = shoved and ring[i].global_position.distance_to(ring_start[i]) > 1.0
	expect("and shoved the lesser enemies round him back", shoved)
	var cooldowns_ok: bool = true
	for id in player.stats.cooldowns.keys():
		cooldowns_ok = cooldowns_ok and float(player.stats.cooldowns[id]) <= float(cooldowns_before.get(id, 0.0)) + 0.001
	expect("the fall took no extra health and spent no cooldown", player.health <= health_after_blow + 2.0 and player.health >= health_after_blow - 0.01 and cooldowns_ok)
	await get_tree().create_timer(0.8).timeout
	expect("no second Iron Recovery afterwards", player.iron_shoves == 1 and wt.has_weapon())
	# A second heavy blow while already down neither restarts nor stretches the fall.
	await calm.call()
	hit_hero.call(20.0, 2.7)
	await get_tree().create_timer(0.5).timeout
	var left: float = player.stun_time
	hit_hero.call(20.0, 2.7)
	expect("a blow while he is down is taken (damage) but does not restart the fall", kd.knockdowns == 1 and player.stun_time <= left + 0.01)
	# Death during a knockdown: the fall is cancelled and nothing fires.
	await calm.call()
	hit_hero.call(20.0, 2.7)
	expect("a fresh knockdown", kd.active())
	player.health = 1.0
	player._apply_damage(500.0)
	expect("dying cancels the knockdown outright", player.dead and not kd.active() and absf(player.visual.rotation.x) < 0.01)
	await get_tree().create_timer(1.6).timeout
	expect("a dead hero never gets up, and no Iron Recovery fires from the fall", player.iron_shoves == 0 and kd.get_ups == 0 and not kd.active())
	expect("his weapon is not lost to the fall", wt.has_weapon())
	# Revive.
	player.revive_at(Vector3.ZERO)
	expect("revive leaves him alive, standing and unlocked", not player.dead and not kd.active() and player.stun_time == 0.0 and player.health > 0.0 and wt.can_begin() and absf(player.visual.rotation.x) < 0.01)
	await get_tree().create_timer(0.3).timeout
	expect("and no stray Iron Recovery arrives after the revive", player.iron_shoves == 0)
	hit_hero.call(20.0, 2.7)
	expect("a revived hero can be knocked down again", kd.active() and kd.knockdowns == 2)
	await get_tree().create_timer(Knockdown.TOTAL_TIME + 0.4).timeout
	expect("and gets up again, once", not kd.active() and kd.get_ups == 1 and player.iron_shoves == 1)
	for e in ring:
		e.queue_free()
	foe.queue_free()
	player.stats.cooldowns.clear()

## Heavy blows have consequences: Power Strike throws what it hits and stuns it; a thrown monster that hits a wall takes a little damage
## and is stunned, and one that hits another monster hurts it and knocks it down; Ramming turns a full Skewer's leftovers into
## knocked-down, thrown-aside monsters (the big ones stunned far longer); and a ranged monster that is hit while backing away is snared.
func _test_knockdown() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var skills: SkillController = player.skills
	var power: Dictionary = SkillDb.all()["power"].duplicate()
	# 1. Power Strike on one zombie in open ground: thrown back several metres and stunned for over a second.
	var z: Enemy = _spawn_enemy(Vector3(0, 0, 1.8))
	z.alert_delay = 999.0
	z.max_health = 5000.0
	z.health = 5000.0
	skills.busy_skill = "power"
	skills.busy_target = z
	skills.busy_aim = z.global_position
	skills._apply_skill(power)
	var stun_at_hit: float = z.stun_time
	var start: Vector3 = z.global_position
	await get_tree().create_timer(0.7).timeout
	var thrown: float = z.global_position.distance_to(start)
	expect("Power Strike stuns for over a second (%.2f)" % stun_at_hit, stun_at_hit >= 1.3)
	# (the blow itself can miss; the throw is the skill's own and happens anyway, a landed hit adds its own knock on top: 4 m and up)
	expect("Power Strike throws it back, even on a miss (%.1f m, was about 0.5 before)" % thrown, thrown >= 1.5)
	z.queue_free()
	# 2. Thrown into a wall: extra damage and a stun.
	# Close enough that even a missed strike's 9 m/s shove reaches the wall
	# above Actor.IMPACT_SPEED; the old 2.8 m gap depended on a random landed hit.
	var wall_victim: Enemy = _spawn_enemy(Vector3(39.2, 0, 0))
	wall_victim.alert_delay = 999.0
	wall_victim.max_health = 5000.0
	wall_victim.health = 5000.0
	player.global_position = Vector3(37.4, 0, 0)
	player.reset_physics_interpolation()
	skills.busy_target = wall_victim
	skills.busy_aim = wall_victim.global_position
	skills._apply_skill(power)
	var hit_only: float = 5000.0 - wall_victim.health
	var hit_only_stun: float = wall_victim.stun_time
	await get_tree().create_timer(0.6).timeout
	expect("thrown into the wall it takes extra damage (%.0f over %.0f) and the impact stuns it" % [5000.0 - wall_victim.health, hit_only],
		5000.0 - wall_victim.health > hit_only + 2.0 and String(wall_victim.last_result.get("skill_id", "")) == "impact" and wall_victim.stun_time > 0.0)
	wall_victim.queue_free()
	await get_tree().process_frame
	# Exercise actual movement/collision without a random combat roll.
	var impact_victim: Enemy = _spawn_enemy(Vector3(39.2, 0, 0))
	impact_victim.alert_delay = 999.0
	impact_victim.max_health = 5000.0
	impact_victim.health = 5000.0
	impact_victim.knock = Vector3(9, 0, 0)
	impact_victim.knocked_by = player
	await get_tree().create_timer(0.6).timeout
	var impact_damage: float = 5000.0 - impact_victim.health
	expect("a qualifying wall collision deals exactly one impact and leaves a living stunned enemy",
		String(impact_victim.last_result.get("skill_id", "")) == "impact" and impact_damage > 0.0
		and is_equal_approx(impact_damage, float(impact_victim.last_result.get("damage", 0.0)))
		and not impact_victim.dead and not impact_victim.is_ragdolled() and impact_victim.stun_time > 0.0)
	await get_tree().create_timer(0.7).timeout
	expect("remaining against the wall does not deal another impact after cooldown", is_equal_approx(5000.0 - impact_victim.health, impact_damage))
	impact_victim.queue_free()
	await get_tree().process_frame
	var no_impact: Enemy = _spawn_enemy(_clear_lane(5.0, 2.0))
	no_impact.alert_delay = 999.0
	no_impact.max_health = 5000.0
	no_impact.health = 5000.0
	no_impact.knock = Vector3(9, 0, 0)
	await get_tree().create_timer(0.6).timeout
	expect("a shove in clear ground causes no false wall impact", is_equal_approx(no_impact.health, 5000.0))
	no_impact.queue_free()
	# 3. Thrown into another monster: both are hurt and the one it hits falls down.
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var front: Enemy = _spawn_enemy(Vector3(0, 0, 1.8))
	var behind: Enemy = _spawn_enemy(Vector3(0, 0, 3.3))
	for e in [front, behind]:
		e.alert_delay = 999.0
		e.max_health = 5000.0
		e.health = 5000.0
	# Power Strike's shove is covered above. Here isolate the actual body contact:
	# its random splash could shove the rear target faster than the front one
	# (9 m/s on a miss versus 10.25 normally, or 20 on a crushing splash).
	# The minimum Power Strike shove closes this 0.66 m capsule gap above IMPACT_SPEED.
	front.knocked_by = player
	front.knock = Vector3(0, 0, SkillController.POWER_KNOCK)
	var saw_down: bool = false
	var t: float = 0.0
	# Observe the first settled body-impact event, before ragdoll follow-up contacts.
	while t < 1.0:
		await get_tree().physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
		saw_down = saw_down or behind.is_ragdolled()
		if saw_down and behind.health < 5000.0 and String(behind.last_result.get("skill_id", "")) == "impact":
			break
	print("  knockdown collision: front_damage=", 5000.0 - front.health,
		" behind_damage=", 5000.0 - behind.health, " down=", saw_down,
		" last=", behind.last_result.get("skill_id", ""))
	expect("the monster that gets hit by the thrown one is hurt and falls down", behind.health < 5000.0 and saw_down
		and String(behind.last_result.get("skill_id", "")) == "impact")
	expect("the thrown monster also takes body-impact damage", front.health < 5000.0
		and String(front.last_result.get("skill_id", "")) == "impact")
	front.queue_free()
	behind.queue_free()
	# 4. A full blade's leftovers are knocked down and thrown aside; with Ramming a big one is stunned far longer.
	var armour: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.RARE, 1, "charger")
	var skewer: SkewerSkill = skills.p.skewer
	var skewer_def: Dictionary = SkillDb.all()["skewer"]
	var run_lane: Callable = func(with_ram: bool) -> Dictionary:
		for node in get_tree().get_nodes_in_group("enemies"):
			node.queue_free()
		await get_tree().process_frame
		player.global_position = Vector3.ZERO
		player.reset_physics_interpolation()
		if with_ram:
			player.stats.equip(armour, false)
		else:
			player.stats.equipment.erase(Items.Slot.ARMOR)
		skewer.skewer_dir = Vector3(0, 0, 1)
		skewer.skewer_impaled.clear()
		skewer.big_hit.clear()
		var lane: Array[Enemy] = []
		for dist in [0.5, 0.8, 1.1, 1.4]:
			var e: Enemy = _spawn_enemy(Vector3(0, 0, dist))
			e.alert_delay = 999.0
			lane.append(e)
		var brute: Enemy = _spawn_enemy(Vector3(1.0, 0, 1.2), "brute")
		brute.alert_delay = 999.0
		skewer._skewer_catch_enemies(skewer_def)
		await get_tree().create_timer(0.3).timeout
		var overflow: Enemy = lane[3]
		var out: Dictionary = {"overflow_down": is_instance_valid(overflow) and (overflow.is_ragdolled() or overflow.stun_time > 0.0),
			"overflow_moved": is_instance_valid(overflow) and absf(overflow.global_position.x) > 0.6, "brute_stun": brute.stun_time}
		for e in skewer.skewer_impaled:
			if is_instance_valid(e):
				e.set_impaled(false)
		skewer.skewer_impaled.clear()
		return out
	var plain: Dictionary = await run_lane.call(false)
	var rammed: Dictionary = await run_lane.call(true)
	expect("the fourth enemy in the lane is knocked down and thrown aside, Ramming or not", plain["overflow_down"] and plain["overflow_moved"]
		and rammed["overflow_down"] and rammed["overflow_moved"])
	expect("with Ramming the big one is stunned much longer (%.1f vs %.1f)" % [rammed["brute_stun"], plain["brute_stun"]],
		float(rammed["brute_stun"]) > float(plain["brute_stun"]) * 2.0)
	player.stats.equipment.erase(Items.Slot.ARMOR)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	# 5. Snare: a spitter that was backing away and is hit gets snared; one that was not, and a zombie, do not.
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	var spitter: Enemy = _spawn_enemy(Vector3(0, 0, 3.0), "spitter")
	var calm_spitter: Enemy = _spawn_enemy(Vector3(5, 0, 3.0), "spitter")
	var zombie: Enemy = _spawn_enemy(Vector3(-5, 0, 3.0))
	for e in [spitter, calm_spitter, zombie]:
		e.alert_delay = 999.0
		e.max_health = 5000.0
		e.health = 5000.0
	var blow: Callable = func() -> Dictionary:
		return {"outcome": Combat.Outcome.HIT, "damage": 5.0, "source": player, "skill_id": "basic", "weight": 1.0, "type": Combat.DamageType.PHYSICAL,
			"bleed_dps": 0.0, "bleed_time": 0.0}
	spitter.back_away_from(player.global_position)
	spitter.receive(blow.call(), player.global_position)
	calm_spitter.receive(blow.call(), player.global_position)
	zombie.receive(blow.call(), player.global_position)
	expect("a spitter hit while running is snared to a crawl for a while (%.1f s, x%.2f)" % [spitter.snare_time, spitter.speed_factor()],
		spitter.snare_time >= 2.5 and spitter.speed_factor() <= 0.45)
	expect("one that was not running is not, and a zombie is not", calm_spitter.snare_time == 0.0 and zombie.snare_time == 0.0)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
