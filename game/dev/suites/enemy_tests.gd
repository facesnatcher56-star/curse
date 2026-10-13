extends DevSuite
## Self-test: enemy stats, speeds, waves, swarms, balance and aggro.

## The four new enemy kinds each do what their behaviour promises, against a hero who just stands there.
func _test_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("hazards"):
		node.queue_free()
	await get_tree().process_frame
	var saved_health: float = player.max_health
	player.max_health = 5000.0
	player.health = 5000.0
	player.global_position = Vector3(30, 0, 30)
	player.reset_physics_interpolation()
	player.movement.has_goal = false
	player.attack_target = null

	# Ghoul: stalks round, crouches, springs, lands, is stuck for a moment.
	var ghoul: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -8.0), "ghoul")
	ghoul.aggro_range = 40.0
	var states: Dictionary = {}
	var landed_near: bool = false
	var landing_marker_seen: bool = false
	var elapsed: float = 0.0
	while elapsed < 9.0 and not states.has(PouncerBehavior.State.RECOVER):
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		var state: int = (ghoul.behavior as PouncerBehavior)._state
		states[state] = true
		if state == PouncerBehavior.State.WINDUP and not get_tree().get_nodes_in_group(GroundTell.GROUP).is_empty():
			landing_marker_seen = true
		if state == PouncerBehavior.State.RECOVER:
			landed_near = ghoul.flat_distance_to(player) < 2.2
	expect("ghoul crouches, leaps and lands next to the hero", states.has(PouncerBehavior.State.WINDUP) and states.has(PouncerBehavior.State.LEAP) and landed_near)
	expect("ghoul pounce uses its crouch delay without a ground marker", not landing_marker_seen)
	print("  ghoul: states seen=", states.keys(), " landed near hero=", landed_near, " after ", snappedf(elapsed, 0.1), " s")
	ghoul.queue_free()
	await get_tree().process_frame

	# Spitter: keeps its distance and lobs acid that leaves a puddle.
	player.health = 5000.0
	var spitter: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -10.0), "spitter")
	spitter.aggro_range = 40.0
	var globs_seen: int = 0
	var min_gap: float = 99.0
	var zones: int = 0
	elapsed = 0.0
	var seen_globs: Dictionary = {}
	while elapsed < 10.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		for g in get_tree().get_nodes_in_group("acid_globs"):
			if not seen_globs.has(g.get_instance_id()):
				seen_globs[g.get_instance_id()] = true
				globs_seen += 1
		if elapsed > 3.0:
			min_gap = minf(min_gap, spitter.flat_distance_to(player))
		zones = maxi(zones, get_tree().get_nodes_in_group("hazards").size())
	expect("spitter lobs acid", globs_seen >= 1)
	expect("acid leaves a puddle", zones >= 1)
	expect("spitter keeps its distance", min_gap > 4.0)
	print("  spitter: globs=", globs_seen, " puddles seen=", zones, " closest approach=", snappedf(min_gap, 0.1), " m")
	# The hero walks up to it: it backs off instead of standing and fighting.
	# (A spitter in the middle of a spit stands still by design, so try again if the first attempt caught it mid-attack.)
	var backed_away: bool = false
	for attempt in 4:
		while spitter.behavior.is_attacking():
			await get_tree().physics_frame
		player.global_position = spitter.global_position + Vector3(0, 0, 2.5)
		player.reset_physics_interpolation()
		var before: float = spitter.flat_distance_to(player)
		await get_tree().create_timer(1.2).timeout
		if spitter.flat_distance_to(player) > before + 0.8:
			backed_away = true
			break
	expect("spitter backs away when the hero closes in", backed_away)
	print("  spitter retreat: backed away = ", backed_away)
	# Kiting tires: held at melee range, it must plant its feet for a spell instead of backing off for ever (the owner could not catch ranged monsters).
	var rested: bool = false
	for i in 360:
		player.global_position = spitter.global_position + Vector3(0, 0, 2.0)
		await get_tree().physics_frame
		if spitter._kite_rest > 0.0:
			rested = true
			break
	expect("a kiting monster plants its feet after running backwards for a while", rested)
	spitter.queue_free()
	for node in get_tree().get_nodes_in_group("hazards"):
		node.queue_free()
	player.global_position = Vector3(30, 0, 30)
	await get_tree().process_frame

	# Bloater: walks up and bursts by itself, hurting the hero and leaving a gas cloud.
	player.health = player.max_health
	var bloater: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -7.0), "bloater")
	bloater.aggro_range = 40.0
	var hp_before: float = player.health
	elapsed = 0.0
	while elapsed < 12.0 and not bloater.dead:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
	expect("bloater bursts itself next to the hero", bloater.dead and player.health < hp_before)
	expect("bloater leaves a gas cloud", get_tree().get_nodes_in_group("hazards").size() >= 1)
	print("  bloater: burst after ", snappedf(elapsed, 0.1), " s, hero lost ", snappedf(hp_before - player.health, 0.1), " HP, clouds=", get_tree().get_nodes_in_group("hazards").size())
	for node in get_tree().get_nodes_in_group("hazards"):
		node.queue_free()
	await get_tree().process_frame

	# Bloater shot with a fireball: the gas ignites and burns the zombies around it.
	player.global_position = Vector3(30, 0, 30)
	var bomb: Enemy = _spawn_enemy(Vector3(36, 0, 22), "bloater")
	bomb.aggro_range = 0.0
	var crowd: Array[Enemy] = []
	for off in [Vector3(1.6, 0, 0), Vector3(-1.4, 0.0, 1.0), Vector3(0.2, 0, -1.8)]:
		var z: Enemy = _spawn_enemy(bomb.global_position + off)
		z.aggro_range = 0.0
		z.max_health = 400.0
		z.health = 400.0
		crowd.append(z)
	await get_tree().process_frame
	bomb.health = 20.0   # the fireball kills the Bloater but only singes the zombies
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.damage = 60.0
	ball.destination = bomb.global_position
	add_child(ball)
	ball.global_position = bomb.global_position + Vector3(0, 1.0, 0)
	ball._explode()
	await get_tree().create_timer(0.3).timeout
	var burning: int = 0
	for z in crowd:
		if is_instance_valid(z) and z.is_burning():
			burning += 1
	expect("a fireball-killed bloater ignites the crowd around it", bomb.dead and burning >= 2)
	print("  bloater firebomb: bloater dead=", bomb.dead, ", zombies burning=", burning, "/3")
	for z in crowd:
		if is_instance_valid(z):
			z.queue_free()
	await get_tree().process_frame

	# Priest: wards its allies, raises zombies, and the wards end when it dies.
	for node in get_tree().get_nodes_in_group("hazards"):
		node.queue_free()
	player.global_position = Vector3(-30, 0, -30)
	player.reset_physics_interpolation()
	player.health = player.max_health
	var priest: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, 9.0), "priest")
	priest.aggro_range = 40.0
	var guards: Array[Enemy] = []
	for off in [Vector3(1.5, 0, 1.0), Vector3(-1.5, 0, 1.0)]:
		var g: Enemy = _spawn_enemy(priest.global_position + off)
		g.aggro_range = 0.0
		guards.append(g)
	(priest.behavior as SupportBehavior)._summon_cd = 0.5
	var warded: bool = false
	var summoned: int = 0
	var group_before: int = get_tree().get_nodes_in_group("enemies").size()
	elapsed = 0.0
	while elapsed < 9.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		for g in guards:
			if is_instance_valid(g) and g.ward_time > 0.0:
				warded = true
		summoned = maxi(summoned, get_tree().get_nodes_in_group("enemies").size() - group_before)
	expect("the priest wards its allies", warded)
	expect("the priest raises zombies", summoned >= 1)
	var kept_distance: float = priest.flat_distance_to(player)
	expect("the priest stays well back from the hero", kept_distance > 5.0)
	priest.receive(Combat.resolve(player, priest, 9999.0, Combat.DamageType.PHYSICAL, false, 1.0, false), player.global_position)
	await get_tree().process_frame
	var still_warded: int = 0
	for g in guards:
		if is_instance_valid(g) and g.ward_time > 0.0:
			still_warded += 1
	expect("killing the priest strips its wards", priest.dead and still_warded == 0)
	print("  priest: warded allies=", warded, " zombies raised=", summoned, " distance=", snappedf(kept_distance, 0.1), " m, wards left after its death=", still_warded)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.max_health = saved_health
	player.health = saved_health
	await get_tree().process_frame

## DS2's average movement velocity, by monster role and tier.
func _test_enemy_speed() -> void:
	var expected := {"zombie": 2.5, "brute": 2.3, "spitter": 3.0, "bloater": 2.5, "priest": 3.5, "ghoul": 2.7, "warden": 2.7}
	for id: String in expected:
		var actual: float = EnemyDb.get_def(id).speed
		expect("%s base movement speed is %.2f m/s" % [id, float(expected[id])], is_equal_approx(actual, float(expected[id])))
	expect("hero and archer use DS2's 4.5 movement speed", is_equal_approx(player.stats.run_speed, 4.5) and is_equal_approx(ArcherCompanion.MOVE_SPEED, 4.5))

## The first wave must not put anyone on top of the hero. Runs right at start-up (before the navigation map has caught up),
## once with a navmesh that answers every snap with the origin (the real-game failure), once normally.
func _test_first_wave() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for broken in [true, false]:
		Nav.debug_broken_snap = broken
		game.director.wave = 0
		game.director.start_wave()
		var closest: float = 9999.0
		var count: int = 0
		var alert_ok: bool = true
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e.get_parent() != game.director:
				continue
			count += 1
			closest = minf(closest, e.global_position.distance_to(player.global_position))
			alert_ok = alert_ok and e.alert_delay > 0.0
		expect("wave 1 (navmesh %s) keeps every enemy at least 11 m away" % ("broken" if broken else "ok"), count > 0 and closest >= 11.0)
		expect("wave 1 enemies wait before noticing the hero", alert_ok)
		print("  first wave (broken nav snap=", broken, "): ", count, " enemies, closest ", snappedf(closest, 0.1), " m")
		for node in get_tree().get_nodes_in_group("enemies"):
			node.queue_free()
	Nav.debug_broken_snap = false
	game.director.wave = 0
	await get_tree().process_frame

## Hero stands idle with NO input while a pack of zombies swarms in. Logs hits taken per second, how many attackers swing at
## once, and any moment the hero starts a skill / changes clip by itself (an "auto attack" with nobody clicking).
func _test_swarm() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(-30, 0, -30)
	player.reset_physics_interpolation()
	var saved_max: float = player.max_health
	player.max_health = 10000.0   # (the check is how many swing at once, not whether a level 1 hero survives eight zombies: on DS2's numbers he does not)
	player.health = player.max_health
	player.attack_target = null
	player.skills.queued_skill = ""
	player.movement.has_goal = false
	var zs: Array[Enemy] = []
	for i in 8:
		var angle: float = TAU * float(i) / 8.0
		var z: Enemy = _spawn_enemy(player.global_position + Vector3(sin(angle), 0, cos(angle)) * 5.0)
		z.aggro_range = 40.0
		zs.append(z)
	var hits: int = 0
	var start_health: float = player.health
	var last_clip: String = ""
	var max_swinging: int = 0
	var swinging_total: float = 0.0
	var frames: int = 0
	var autos: Array[String] = []
	var elapsed: float = 0.0
	var taken: float = 0.0   # the blows themselves, frame by frame (his regeneration on 10000 life would hide them)
	while elapsed < 8.0:
		var before_frame: float = player.health
		await get_tree().physics_frame
		taken += maxf(before_frame - player.health, 0.0)
		elapsed += 1.0 / 60.0
		frames += 1
		var swinging: int = 0
		for z in zs:
			if is_instance_valid(z) and z._attacking:
				swinging += 1
		max_swinging = maxi(max_swinging, swinging)
		swinging_total += swinging
		if player.skills.busy or player.model.current != last_clip:
			if player.skills.busy and autos.size() < 6:
				autos.append("t=%.2f busy skill=%s clip=%s" % [elapsed, player.skills.busy_skill, player.model.current])
			if player.model.current != last_clip:
				autos.append("t=%.2f clip %s -> %s" % [elapsed, last_clip, player.model.current])
				last_clip = player.model.current
		if player.stun_time > 0.0 and autos.size() < 12:
			autos.append("t=%.2f player stunned %.2f" % [elapsed, player.stun_time])
	expect("at most max_tokens enemies swing at once", max_swinging <= Enemy.max_tokens)
	var cap: float = Enemy.max_tokens * zs[0].average_hit() / maxf(zs[0].attack_time, 0.1)
	expect("swarm damage is no more than max_tokens attackers' DS2 blows (%.1f/s, cap %.1f/s)" % [taken / 8.0, cap], taken > 0.0 and taken / 8.0 <= cap)
	expect("hero never acts or animates by itself in a swarm", not autos.any(func(l: String) -> bool: return "busy skill" in l or "-> walk" in l or "-> run" in l))
	print("  swarm: hero took ", int(taken), " in 8 s (", snappedf(taken / 8.0, 0.1),
		" dmg/s); attackers swinging at once: max ", max_swinging, ", average ", snappedf(swinging_total / frames, 0.1))
	for line in autos:
		print("    ", line)
	# A cast in the middle of the swarm should run to the end, not get cut short by incoming hits.
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.health = player.max_health
	player.skills.start_skill("fireball", null, zs[0].global_position)
	var cast: float = 0.0
	var interrupted: bool = false
	while player.skills.busy and cast < 3.0:
		await get_tree().physics_frame
		cast += 1.0 / 60.0
	expect("a Fireball cast in the middle of a swarm runs to the end", cast >= 1.0 and player.stun_time == 0.0)
	print("  Fireball inside the swarm: lasted ", snappedf(cast, 0.01), " s of ", snappedf(player.skills.busy_time, 0.01), " expected, stun at end=", player.stun_time)
	player.max_health = saved_max
	player.health = saved_max
	for z in zs:
		if is_instance_valid(z):
			z.queue_free()

## Wave layout (packs + isolated Brutes), loot rates, potion pickups and click-to-cancel.
func _test_balance() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	# This test measures the shape of random pack placements. Keep the sampled layouts
	# stable so earlier tests consuming the global RNG cannot make the assertion flaky.
	seed(2026)
	for w in [1, 4]:
		wave = w - 1
		_next_wave()
		await get_tree().process_frame
		var zombies: Array[Node3D] = []
		var brutes: Array[Node3D] = []
		for node in get_tree().get_nodes_in_group("enemies"):
			if (node as Enemy).variant == "brute":
				brutes.append(node)
			else:
				zombies.append(node)
		var in_pack: int = 0
		var nearest_sum: float = 0.0
		for z in zombies:
			var nearest: float = 999.0
			for o in zombies:
				if o != z:
					nearest = minf(nearest, z.global_position.distance_to(o.global_position))
			nearest_sum += nearest
			if nearest < 3.0:
				in_pack += 1
		var lone_brutes: int = 0
		for b in brutes:
			var near: bool = false
			for z in zombies:
				if z.global_position.distance_to(b.global_position) < 3.0:
					near = true
			if not near:
				lone_brutes += 1
		expect("wave %d zombies come in packs" % w, in_pack >= int(zombies.size() * 0.5))
		expect("wave %d brutes stand alone" % w, lone_brutes == brutes.size())
		print("  wave ", w, ": ", zombies.size(), " zombies, ", brutes.size(), " brutes; zombies within 3 m of another: ", in_pack,
			" (mean nearest neighbour ", snappedf(nearest_sum / maxf(zombies.size(), 1), 0.1), " m); brutes standing alone: ", lone_brutes)
		for node in get_tree().get_nodes_in_group("enemies"):
			node.queue_free()
		await get_tree().process_frame
	# DS2 loot is independent of missing health and body size (road_pacing_check verifies rates).
	var loot := MonsterLoot.roll(2, "weak")
	expect("shared monster loot has health, mana, gold and equipment results", loot.has("health") and loot.has("mana") and loot.has("gold") and loot.has("item"))
	# Potion pickup.
	player.stats.potions = 2
	var pickup := HealthOrb.new()
	pickup.is_potion = true
	add_child(pickup)
	pickup.global_position = player.global_position + Vector3(0, 0.6, 0)
	await get_tree().process_frame
	player.stats.collect_orbs()
	expect("potion pickup gives +1 potion", player.stats.potions == 3)
	print("  potion pickup: potions 2 -> ", player.stats.potions)
	# Click-away cancels a basic swing.
	player.global_position = Vector3(-30, 0, 30)
	player.reset_physics_interpolation()
	var target: Enemy = _spawn_enemy(Vector3(-28.5, 0, 30))
	target.aggro_range = 0.0
	target.max_health = 5000.0
	target.health = 5000.0
	await get_tree().process_frame
	player.attack_target = target
	var t: float = 0.0
	while not player.skills.busy and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a basic swing can be cancelled by clicking away", player.skills.busy and player.skills.swing_cancellable_by_move())
	print("  swing started=", player.skills.busy, " cancellable by click-away=", player.skills.swing_cancellable_by_move())
	player.skills.cancel_action()
	player.attack_target = null
	expect("cancelling stops the swing", not player.skills.busy)
	print("  after cancel: busy=", player.skills.busy)
	target.queue_free()
	await get_tree().process_frame
	randomize()

## Walk/run selection follows the DS2 movement band without slow-motion running.
func _test_enemy_run() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	for variant in ["zombie", "brute", "spitter", "bloater", "priest", "warden", "ghoul"]:
		var e: Enemy = _spawn_enemy(Vector3(0, 0, -14), variant)
		e.alert_delay = 0.0
		e.aggro_range = 60.0
		await get_tree().create_timer(0.3).timeout
		var seen: Dictionary = {}
		var t: float = 0.0
		while t < 1.5:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			seen[e.model.current] = true
		print("  ", variant, " clips seen while chasing: ", seen.keys())
		if e.def.speed <= Enemy.SHAMBLE_MAX_SPEED:
			expect("a slowed %s shambles instead of running in slow motion" % variant,
				seen.has("walk") and not seen.has("run") and e.locomotion_rate(e.pace()) >= 0.78)
		else:
			expect("a fast %s still runs toward the hero" % variant, seen.has("run") and not seen.has("walk"))
		e.queue_free()
	await get_tree().process_frame

## An enemy the hero hits comes for them whatever the distance; the hero's own swings only break barrels.
func _test_hit_aggro() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var far: Enemy = _spawn_enemy(Vector3(0, 0, -35))
	far.aggro_range = 0.0
	far.max_health = 5000.0
	far.health = 5000.0
	var quiet: Enemy = _spawn_enemy(Vector3(35, 0, 0))
	quiet.aggro_range = 0.0
	await get_tree().create_timer(0.5).timeout
	var start_far: float = far.global_position.distance_to(player.global_position)
	var start_quiet: float = quiet.global_position.distance_to(player.global_position)
	far.receive({"outcome": Combat.Outcome.HIT, "damage": 3.0, "source": player, "skill_id": "fireball", "weight": 1.0,
		"type": Combat.DamageType.FIRE}, player.global_position)
	await get_tree().create_timer(1.5).timeout
	expect("an enemy hit from far away comes for the hero", far.global_position.distance_to(player.global_position) < start_far - 3.0)
	expect("an enemy that was not hit stays where it was", quiet.global_position.distance_to(player.global_position) > start_quiet - 0.5)
	# Hits that are not the hero's (another enemy's blast, say) do not provoke.
	var other: Enemy = _spawn_enemy(Vector3(-35, 0, 0))
	other.aggro_range = 0.0
	other.max_health = 5000.0
	other.health = 5000.0
	await get_tree().create_timer(0.3).timeout
	var before: float = other.global_position.distance_to(player.global_position)
	other.receive({"outcome": Combat.Outcome.HIT, "damage": 3.0, "source": quiet, "skill_id": "x", "weight": 1.0,
		"type": Combat.DamageType.PHYSICAL}, quiet.global_position)
	await get_tree().create_timer(1.0).timeout
	expect("a hit from another enemy does not provoke", other.global_position.distance_to(player.global_position) > before - 0.5)
	# Swings only break barrels.
	arena.place_prop("gravestone", Vector3(10, 0, 10), 0.0, 1.3)
	arena.place_prop("barrel", Vector3(14, 0, 10), 0.0, 1.0)
	expect("a swing breaks the barrel and not the gravestone", Destructible.blast(get_tree(), Vector3(12, 0, 10), 6.0, 99.0, Vector3.RIGHT, 1.0, "barrel") == 1
		and Destructible.near(get_tree(), Vector3(10, 0, 10), 0.4) != null)
	expect("a click only picks barrels", Destructible.near(get_tree(), Vector3(10, 0, 10), 0.4, "barrel") == null)
	Destructible.near(get_tree(), Vector3(10, 0, 10), 0.4).hit(999.0, Vector3.RIGHT)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().process_frame
