extends DevSuite
## Self-test: Fireball, its cancel, frames and sounds, the fire blast and Twin Flame targeting.

## Fireball: sword is put away for the cast, an orb gathers overhead, the ball lands where aimed.
func _test_fireball() -> void:
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	var victim: Enemy = _spawn_enemy(Vector3(0, 0, -6.0))
	victim.aggro_range = 0.0
	victim.max_health = 500.0
	victim.health = 500.0
	await get_tree().process_frame
	player.skills.start_skill("fireball", null, Vector3(0, 0, -6.0))
	var sheathed: bool = false
	var orb_seen: bool = false
	var orb_big: bool = false
	var elapsed: float = 0.0
	while player.skills.busy and elapsed < 4.0:
		await get_tree().physics_frame
		await get_tree().process_frame
		elapsed += 1.0 / 60.0
		if player.model.weapon != null and not player.model.weapon.visible:
			sheathed = true
		if player.skills.fire_orb != null and is_instance_valid(player.skills.fire_orb):
			orb_seen = true
			orb_big = orb_big or player.skills.fire_orb.current_size() > 0.5
	await get_tree().create_timer(1.2).timeout
	expect("fireball: sword sheathed, orb gathered and grown", sheathed and orb_seen and orb_big)
	expect("fireball: sword comes back", player.model.weapon == null or player.model.weapon.visible)
	expect("fireball damages its target", victim.health < victim.max_health)
	print("  fireball: sword sheathed during cast=", sheathed, " orb gathered=", orb_seen, " (grew large=", orb_big, ") sword back=",
		player.model.weapon.visible if player.model.weapon != null else "n/a", " target damaged=", victim.health < victim.max_health)
	victim.queue_free()
	await get_tree().process_frame

## Fireball blast: enemies near the centre are thrown (ragdoll) and everyone hit burns; the rim only staggers.
func _test_fire_blast() -> void:
	player.global_position = Vector3(-20, 0, 20)
	player.reset_physics_interpolation()
	var centre := Vector3(-20, 0, 10)
	var inner: Enemy = _spawn_enemy(centre + Vector3(0.6, 0, 0))
	var rim: Enemy = _spawn_enemy(centre + Vector3(0, 0, 2.2))
	var boss: Enemy = _spawn_enemy(centre + Vector3(-1.0, 0, -0.4), "brute")
	boss.is_boss = true
	for e in [inner, rim, boss]:
		e.aggro_range = 0.0
		e.max_health = 500.0
		e.health = 500.0
	await get_tree().process_frame
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.destination = centre
	add_child(ball)
	ball.global_position = centre + Vector3(0, 1.0, 0)
	ball._explode()
	var start: Vector3 = inner.global_position
	var thrown: bool = false
	var max_away: float = 0.0
	for i in 40:
		await get_tree().physics_frame
		thrown = thrown or inner.is_ragdolled()
		max_away = maxf(max_away, inner.global_position.distance_to(start))
	expect("fireball: close enemy is thrown and burns", thrown and inner.is_burning())
	expect("fireball: rim enemy burns but is not thrown", rim.is_burning() and not rim.is_ragdolled())
	expect("fireball: boss burns but is not thrown", boss.is_burning() and not boss.is_ragdolled())
	print("  fire blast: inner ragdolled=", thrown, " flew ", snappedf(max_away, 0.1), " m, inner burning=", inner.is_burning(),
		" rim burning=", rim.is_burning(), " rim ragdolled=", rim.is_ragdolled(), " boss ragdolled=", boss.is_ragdolled(), " boss burning=", boss.is_burning(),
		" flames=", inner._flames != null)
	await get_tree().create_timer(7.0).timeout
	expect("burn ends, flames go out, enemy gets back up", not inner.is_burning() and inner._flames == null and not inner.is_ragdolled())
	print("  after 7s: inner burning=", inner.is_burning(), " health=", snappedf(inner.health, 0.1), " flames freed=", inner._flames == null,
		" standing again=", not inner.is_ragdolled())
	for e in [inner, rim, boss]:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame

## The fireball's cast sound plays at the moment of launch (whatever the casting speed) and its impact sound plays on the explosion.
func _test_fireball_sounds() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var was_enabled: bool = Sfx.enabled
	Sfx.enabled = true
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	for haste in [1.0]:   # (casting speed: only gear could change it, and none does now)
		player.stats.cooldowns.clear()
		Sfx._last_played.clear()
		Sfx.played_log.clear()
		var target: Vector3 = Vector3(0, 0, -8)
		player.skills.start_skill("fireball", null, target)
		var skill: Dictionary = SkillDb.all()["fireball"]
		var scale_factor: float = player.skills.busy_time / float(skill["time"])
		var throw_at: float = (float(skill["gather"]) + float(skill["release_after"])) * scale_factor
		var cast_at: float = -1.0
		var impact_at: float = -1.0
		var early: bool = false
		var t: float = 0.0
		while t < 5.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if cast_at < 0.0 and _logged("fireball_cast") > 0:
				cast_at = player.skills.busy_t if player.skills.busy else throw_at
			if impact_at < 0.0 and _logged("fireball_impact") > 0:
				impact_at = t
				break
		expect("the cast sound plays once, at launch (casting speed x%.1f)" % haste, _logged("fireball_cast") == 1 and cast_at >= 0.0 and absf(cast_at - throw_at) < 0.1)
		expect("the impact sound plays when the fireball explodes", _logged("fireball_impact") >= 1 and impact_at > throw_at)
		print("  fireball sound x", haste, ": launch at ", snappedf(throw_at, 0.01), " s, cast sound at ", snappedf(cast_at, 0.01), " s, impact sound after ", snappedf(impact_at, 0.01), " s")
		await get_tree().create_timer(0.5).timeout
	# Both cast recordings get used.
	Sfx.played_log.clear()
	for i in 30:
		Sfx._last_played.clear()
		Sfx.sample(self, "fireball_cast")
	var seen: Dictionary = {}
	for name in Sfx.played_log:
		seen[name] = true
	expect("both cast recordings are used", seen.size() == 2)
	Sfx.enabled = was_enabled
	await get_tree().process_frame

## Right-click or dodge backs out of a Fireball: while aiming (nothing spent, and letting go of the key does not cast) and during the
## wind-up (mana and cooldown come back). The cooldown is long enough that it is not spammed.
func _test_fireball_cancel() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(30, 0, 30)
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns["fireball"] = 0.0
	player.skills.clear_aim()
	player.skills.hotbar[1] = "fireball"   # loadout selection can still place the retained skill
	expect("the fireball cooldown is at least five seconds", float(SkillDb.all()["fireball"]["cd"]) >= 5.0)
	# Cancel while aiming with right-click.
	Input.action_press("skill_2")
	await get_tree().create_timer(0.3).timeout
	expect("holding the key aims", player.skills.aiming_id == "fireball")
	Input.action_press("alt_skill")
	await get_tree().create_timer(0.2).timeout
	Input.action_release("alt_skill")
	expect("right-click cancels the aim", player.skills.aiming_id == "")
	Input.action_release("skill_2")
	await get_tree().create_timer(0.3).timeout
	expect("letting go of the key after cancelling casts nothing", not player.skills.busy and is_equal_approx(player.stats.mana, player.stats.max_mana)
		and float(player.stats.cooldowns.get("fireball", 0.0)) == 0.0)
	# Cancel while aiming with dodge: the hero rolls instead.
	player.stats.stamina = player.stats.max_stamina
	player.stats.cooldowns["dodge"] = 0.0
	Input.action_press("skill_2")
	await get_tree().create_timer(0.3).timeout
	Input.action_press("dodge")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("dodge")
	expect("dodge cancels the aim", player.skills.aiming_id == "")
	Input.action_release("skill_2")
	await get_tree().create_timer(0.8).timeout
	expect("and no fireball was cast", is_equal_approx(player.stats.mana, player.stats.max_mana))
	# Cancel during the wind-up: mana and cooldown come back.
	player.stats.cooldowns["dodge"] = 0.0
	player.stats.stamina = player.stats.max_stamina
	player.skills.start_skill("fireball", null, player.global_position + Vector3(0, 0, -8))
	await get_tree().create_timer(0.25).timeout
	expect("the cast is winding up", player.skills.busy and not player.skills.busy_hit_done and player.stats.mana < player.stats.max_mana)
	Input.action_press("alt_skill")
	await get_tree().create_timer(0.2).timeout
	Input.action_release("alt_skill")
	expect("right-click cancels the wind-up", not player.skills.busy)
	expect("the mana and the cooldown are given back", is_equal_approx(player.stats.mana, player.stats.max_mana)
		and float(player.stats.cooldowns.get("fireball", 0.0)) == 0.0)
	await get_tree().create_timer(0.4).timeout
	player.skills.start_skill("fireball", null, player.global_position + Vector3(0, 0, -8))
	await get_tree().create_timer(0.25).timeout
	player.stats.cooldowns["dodge"] = 0.0
	Input.action_press("dodge")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("dodge")
	expect("dodge cancels the wind-up and rolls", not player.skills.busy and is_equal_approx(player.stats.mana, player.stats.max_mana))
	await get_tree().create_timer(0.8).timeout
	# Once thrown, it is thrown.
	player.stats.cooldowns["dodge"] = 0.0
	player.skills.start_skill("fireball", null, player.global_position + Vector3(0, 0, -8))
	var thrown: bool = false
	var t: float = 0.0
	while t < 2.0 and not thrown:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		thrown = player.skills.busy_hit_done
	Input.action_press("alt_skill")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("alt_skill")
	expect("a fireball that has left the hand keeps its cost", thrown and player.stats.mana < player.stats.max_mana
		and float(player.stats.cooldowns.get("fireball", 0.0)) > 3.0)
	await get_tree().create_timer(1.0).timeout
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns["fireball"] = 0.0
	for node in get_tree().get_nodes_in_group("hazards"):
		node.queue_free()

## How long the longest frame is when a Fireball goes off in the middle of a crowd (nothing may hitch: the blast's work must not land on one frame).
func _test_fireball_frames() -> void:
	player.global_position = _free_lane_start(16.0, 6.0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	await get_tree().process_frame
	var centre: Vector3 = player.global_position + Vector3(8, 0, 0)
	for i in 9:
		var z: Enemy = _spawn_enemy(centre + Vector3(randf_range(-1.8, 1.8), 0, randf_range(-1.8, 1.8)))
		z.aggro_range = 0.0
		z.max_health = 3000.0
		z.health = 3000.0
	await get_tree().create_timer(0.5).timeout
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.direction = Vector3.RIGHT
	ball.damage = 40.0
	ball.destination = centre + Vector3(0, 0.8, 0)
	get_tree().current_scene.add_child(ball)
	ball.global_position = centre + Vector3(0, 0.8, 0)
	var worst: float = 0.0
	var worst_frame: int = 0
	var frames: Array[float] = []
	for i in 60:
		var t0: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		frames.append(ms)
		if ms > worst:
			worst = ms
			worst_frame = i
	print("    fireball frames: worst %.1f ms at frame %d; first ten: %s" % [worst, worst_frame, ", ".join(frames.slice(0, 10).map(func(v: float) -> String: return "%.1f" % v))])
	expect("no frame after a Fireball in a crowd is a hitch (worst %.1f ms)" % worst, worst < 40.0)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
