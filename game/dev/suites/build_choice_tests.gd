extends DevSuite
## Self-test: build choices.

## The first build choices: what points buy (passives, one Weapon Throw evolution), that the choices save, load, repair and survive death, what
## each evolution and passive does in the world, and that the Progression screen asks before it spends.
func _test_build_choices() -> void:
	TownState.persist = false
	TownState.reset()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var wt: WeaponThrowSkill = player.weapon_throw
	var skills: SkillController = player.skills
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Longsword"), false)
	player.stats.cooldowns.clear()
	# --- Points and spending --------------------------------------------------------------------------------------------------------------
	TownState.dev_set_hero_level(6)   # 3 Passive, 2 Evolution
	expect("a level 6 hero with nothing bought has all of its points (3 and 2)", TownState.passive_points_available() == 3 and TownState.evolution_points_available() == 2
		and TownState.purchased_passives.is_empty() and TownState.skill_evolutions.is_empty())
	expect("a passive costs exactly 1 Passive Point", TownState.buy_passive("unbowed") and TownState.passive_points_available() == 2 and TownState.has_passive("unbowed"))
	expect("it cannot be bought twice", not TownState.can_buy_passive("unbowed") and not TownState.buy_passive("unbowed") and TownState.passive_points_available() == 2)
	expect("an unknown passive is refused", not TownState.buy_passive("not_a_passive") and TownState.passive_points_available() == 2)
	expect("a Weapon Throw evolution costs exactly 1 Evolution Point", TownState.select_evolution("throw", "wallspike") and TownState.evolution_points_available() == 1
		and TownState.selected_evolution("throw") == "wallspike")
	expect("a second evolution of the same skill is refused (one only, no respec)", not TownState.can_select_evolution("throw", "ricochet") and not TownState.select_evolution("throw", "ricochet")
		and not TownState.select_evolution("throw", "wallspike") and TownState.selected_evolution("throw") == "wallspike" and TownState.evolution_points_available() == 1)
	expect("an evolution that does not exist is refused", not TownState.select_evolution("throw", "nonsense") and not TownState.select_evolution("nonsense", "wallspike"))
	TownState.reset()
	expect("without points nothing can be bought (level 1)", not TownState.can_buy_passive("unbowed") and not TownState.buy_passive("unbowed") and not TownState.select_evolution("throw", "ricochet")
		and TownState.passive_points_available() == 0 and TownState.evolution_points_available() == 0)
	# --- Saving: round trip, migration, and bad data never make points ---------------------------------------------------------------------
	TownState.dev_set_hero_level(12)   # 6 Passive, 4 Evolution
	TownState.buy_passive("unbowed")
	TownState.buy_passive("retaliation")
	TownState.select_evolution("throw", "reaping_recall")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	expect("the save holds only the choices, not points", saved["purchased_passives"] == ["unbowed", "retaliation"] and saved["skill_evolutions"] == {"throw": "reaping_recall"}
		and not saved.has("passive_points") and not saved.has("evolution_points") and int(saved["save_version"]) == TownState.SAVE_VERSION)
	TownState.reset()
	TownState.from_dict(TownState.migrate(saved.duplicate(true)))
	expect("a save and load keep the choices and the points left (4, 3)", TownState.has_passive("unbowed") and TownState.has_passive("retaliation") and TownState.selected_evolution("throw") == "reaping_recall"
		and TownState.passive_points_available() == 4 and TownState.evolution_points_available() == 3)
	var old: Dictionary = saved.duplicate(true)
	old["save_version"] = 3
	old.erase("purchased_passives")
	old.erase("skill_evolutions")
	var migrated: Dictionary = TownState.migrate(old)
	TownState.reset()
	TownState.from_dict(migrated)
	expect("a version 3 save migrates with nothing bought and every point it earned free (6, 4)", int(migrated["save_version"]) == TownState.SAVE_VERSION and TownState.purchased_passives.is_empty()
		and TownState.skill_evolutions.is_empty() and TownState.passive_points_available() == 6 and TownState.evolution_points_available() == 4)
	var bad: Dictionary = saved.duplicate(true)
	bad["purchased_passives"] = ["unbowed", "unbowed", "bogus", 7, null, "retaliation", "retaliation", ["x"]]
	bad["skill_evolutions"] = {"throw": "ricochet", "other_skill": "wallspike"}
	TownState.reset()
	TownState.from_dict(TownState.migrate(bad))
	expect("unknown and repeated saved choices are dropped, not paid for twice", TownState.purchased_passives == ["unbowed", "retaliation"] and TownState.skill_evolutions == {"throw": "ricochet"}
		and TownState.passive_points_available() == 4 and TownState.evolution_points_available() == 3)
	var greedy: Dictionary = saved.duplicate(true)
	greedy["hero_xp"] = 0   # level 1: nothing earned
	greedy["purchased_passives"] = ["unbowed", "mass_transfer", "stubborn_advance"]
	greedy["skill_evolutions"] = {"throw": "wallspike"}
	TownState.reset()
	TownState.from_dict(TownState.migrate(greedy))
	expect("choices a level never paid for are dropped (no free points, never negative)", TownState.purchased_passives.is_empty() and TownState.skill_evolutions.is_empty()
		and TownState.passive_points_available() == 0 and TownState.evolution_points_available() == 0)
	for junk in [null, 5, "text", [], {}, [1, 2], {"throw": 3}, {"throw": null}]:
		var weird: Dictionary = saved.duplicate(true)
		weird["purchased_passives"] = junk
		weird["skill_evolutions"] = junk
		TownState.reset()
		TownState.from_dict(TownState.migrate(weird))
		expect("a malformed build (%s) loads without a crash or a negative count" % str(junk), TownState.passive_points_available() >= 0 and TownState.evolution_points_available() >= 0
			and TownState.passive_points_available() <= HeroProgression.passive_points_for_level(TownState.hero_level))
	TownState.reset()
	TownState.dev_set_hero_level(30)
	for id in BuildDefs.PASSIVE_ORDER:
		TownState.buy_passive(id)
	TownState.select_evolution("throw", "ricochet")
	TownState.dev_set_hero_level(4)
	expect("lowering the level drops what it no longer pays for (developer only)", TownState.purchased_passives.size() <= 2 and TownState.skill_evolutions.size() <= 1
		and TownState.passive_points_available() >= 0 and TownState.evolution_points_available() >= 0)
	TownState.reset()
	TownState.dev_set_hero_level(6)
	TownState.buy_passive("mass_transfer")
	TownState.select_evolution("throw", "wallspike")
	player._on_death()
	player.dead = false
	player.health = player.max_health
	expect("dying clears nothing: the build is the hero's, not the run's", TownState.has_passive("mass_transfer") and TownState.selected_evolution("throw") == "wallspike"
		and TownState.passive_points_available() == 2 and TownState.evolution_points_available() == 1)
	var build_events: Array = [0]
	var on_build: Callable = func() -> void: build_events[0] = int(build_events[0]) + 1
	TownState.events.hero_build_changed.connect(on_build)
	TownState.buy_passive("retaliation")
	TownState.buy_passive("retaliation")
	TownState.events.hero_build_changed.disconnect(on_build)
	expect("a purchase announces itself once (and a refused one says nothing)", int(build_events[0]) == 1)

	# --- Weapon Throw: the baseline, then each evolution ---------------------------------------------------------------------------------------
	var throw: Callable = func(aim: Vector3, hold: float) -> void:
		wt._profile = wt.profile()
		wt.evolution = player.evolution_of("throw")
		wt.state = WeaponThrowSkill.State.CHARGING
		wt._hold = hold
		wt.charge = wt.charge_fraction()
		wt.release(aim)
	var make_wall: Callable = func(centre: Vector3, wall_size: Vector3) -> StaticBody3D:
		var wall := StaticBody3D.new()
		wall.collision_layer = Actor.LAYER_WORLD
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall_size
		shape.shape = box
		wall.add_child(shape)
		game.add_child(wall)
		wall.global_position = centre
		return wall
	var clear_field: Callable = func() -> void:
		for node in get_tree().get_nodes_in_group("enemies"):
			node.queue_free()
		wt.reset()
		player.stats.cooldowns.clear()
		await get_tree().process_frame
	var full: float = 10.0   # a hold far past full charge
	# Baseline: no evolution, nothing special happens.
	TownState.reset()
	await clear_field.call()
	var lane: Vector3 = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var base_wall: StaticBody3D = make_wall.call(lane + Vector3(13.5, 2.0, 0.0), Vector3(1.0, 4.0, 5.0))
	var base_victim: Enemy = _throw_dummy(lane + Vector3(5.0, 0, 0))
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), full)
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	expect("baseline throw: nothing is carried or pinned, no bounce, and it sticks in the wall", wt.evolution == "" and wt.carried == null and wt.pinned == null and wt.bounces == 0
		and not base_victim.impaled and wt.thrown.center().x > lane.x + 10.0 and wt.thrown.center().x < lane.x + 13.5)
	base_wall.queue_free()
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)

	# Wallspike.
	TownState.reset()
	TownState.dev_set_hero_level(6)
	TownState.select_evolution("throw", "wallspike")
	await clear_field.call()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var open_line: Array[Enemy] = []
	for d in [5.5, 8.0, 10.5]:
		open_line.append(_throw_dummy(lane + Vector3(d, 0, 0)))
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), full)
	var ever_carried: Dictionary = {}
	var frames: int = 0
	while wt.state != WeaponThrowSkill.State.EMBEDDED and frames < 400:
		await get_tree().physics_frame
		frames += 1
		for e in open_line:
			if is_instance_valid(e) and e.impaled:
				ever_carried[e.get_instance_id()] = true
	expect("Wallspike spears exactly one of three enemies in the line (the first)", ever_carried.size() == 1 and ever_carried.has(open_line[0].get_instance_id()))
	expect("in open ground the carried body is thrown on and nobody stays held", wt.carried == null and wt.pinned == null and open_line.all(func(e: Enemy) -> bool: return not is_instance_valid(e) or not e.impaled))
	expect("the weapon still embeds as normal after throwing the body on", wt.state == WeaponThrowSkill.State.EMBEDDED)
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	await clear_field.call()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var pin_wall: StaticBody3D = make_wall.call(lane + Vector3(13.5, 2.0, 0.0), Vector3(1.0, 4.0, 6.0))
	var pin_victim: Enemy = _throw_dummy(lane + Vector3(5.0, 0, 0))
	var pin_start_hp: float = pin_victim.health
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), full)
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	await get_tree().physics_frame
	expect("Wallspike pins the enemy on the wall: a held state, not a picture", wt.pinned == pin_victim and pin_victim.impaled and pin_victim.health < pin_start_hp
		and pin_victim.global_position.x > lane.x + 11.0 and pin_victim.global_position.x < lane.x + 13.5)
	var pin_spot: Vector3 = pin_victim.global_position
	await get_tree().create_timer(1.0).timeout
	expect("it stays pinned for as long as the weapon is in the wall", wt.pinned == pin_victim and pin_victim.impaled and pin_victim.global_position.distance_to(pin_spot) < 0.2)
	wt.recall()
	await get_tree().physics_frame
	expect("the recall rips the weapon free and drops the victim, knocked down", wt.pinned == null and not pin_victim.impaled and (pin_victim.is_ragdolled() or pin_victim.stun_time > 0.5))
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	expect("and the weapon comes home and is caught", wt.state == WeaponThrowSkill.State.IN_HAND and wt.thrown == null)
	pin_wall.queue_free()
	await clear_field.call()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var big_wall: StaticBody3D = make_wall.call(lane + Vector3(13.5, 2.0, 0.0), Vector3(1.0, 4.0, 6.0))
	var brute: Enemy = _throw_dummy(lane + Vector3(5.0, 0, 0), "brute")
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), full)
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	expect("a Brute is not spiked or pinned: it takes the baseline blow", wt.pinned == null and wt.carried == null and not brute.impaled and brute.health < brute.max_health)
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	await clear_field.call()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var boss: Enemy = _throw_dummy(lane + Vector3(5.0, 0, 0))
	boss.is_boss = true
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), full)
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	expect("a boss-flagged enemy is never spiked", wt.pinned == null and wt.carried == null and not boss.impaled)
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	big_wall.queue_free()
	await clear_field.call()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var weak_victim: Enemy = _throw_dummy(lane + Vector3(5.0, 0, 0))
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), 0.3 * wt.profile()["charge_time"])   # about 30% charge: under the 80% a spear needs
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	expect("a weak throw does not spear anyone", wt.carried == null and wt.pinned == null and not weak_victim.impaled)
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)

	# Reaping Recall.
	TownState.reset()
	TownState.dev_set_hero_level(6)
	TownState.select_evolution("throw", "reaping_recall")
	await clear_field.call()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), full)
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	var rest: Vector3 = wt.thrown.center()
	var hero_spot: Vector3 = Vector3(rest.x - 14.0, 0.0, rest.z + 7.0)
	player.global_position = hero_spot
	player.reset_physics_interpolation()
	var reaped: Array[Enemy] = []
	var before: Array[float] = []
	for fraction in [0.35, 0.6]:
		var spot: Vector3 = Vector3(rest.x, 0.0, rest.z).lerp(hero_spot, fraction)
		var z: Enemy = _throw_dummy(spot)
		reaped.append(z)
		before.append(z.flat_distance_to(player))
	var heavy_on_path: Enemy = _throw_dummy(Vector3(rest.x, 0.0, rest.z).lerp(hero_spot, 0.8), "brute")
	var heavy_before: float = heavy_on_path.flat_distance_to(player)
	await get_tree().create_timer(0.2).timeout
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.RETURNING, 2.0)
	await _wait_state(WeaponThrowSkill.State.CATCHING, 6.0)
	await get_tree().create_timer(1.3).timeout
	var pulled_ok: bool = true
	for i in reaped.size():
		pulled_ok = pulled_ok and is_instance_valid(reaped[i]) and wt.pulled_ids.has(reaped[i].get_instance_id()) and reaped[i].flat_distance_to(player) < before[i] - 1.5
	expect("Reaping Recall drags each lesser enemy the weapon strikes on the way back in toward him", pulled_ok)
	var unique: Dictionary = {}
	for id in wt.pulled_ids:
		unique[id] = true
	expect("each enemy is pulled once per return (no juggling)", unique.size() == wt.pulled_ids.size() and wt.pulled_ids.size() == reaped.size())
	expect("a Brute on the line is hit but not dragged", not wt.pulled_ids.has(heavy_on_path.get_instance_id()) and heavy_on_path.flat_distance_to(player) > heavy_before - 1.0)
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 4.0)
	expect("the weapon is caught as usual", wt.state == WeaponThrowSkill.State.IN_HAND and wt.thrown == null)

	# Ricochet.
	TownState.reset()
	TownState.dev_set_hero_level(6)
	TownState.select_evolution("throw", "ricochet")
	await clear_field.call()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var bank_wall: StaticBody3D = make_wall.call(lane + Vector3(11.5, 2.0, 0.0), Vector3(1.0, 4.0, 30.0))
	var aim_dir: Vector3 = Vector3(1.0, 0.0, 0.5).normalized()
	var hit_t: float = 11.0 / aim_dir.x   # to the wall's face at x + 11
	var hit_point: Vector3 = lane + aim_dir * hit_t
	var expected_out: Vector3 = aim_dir.bounce(Vector3(-1, 0, 0)).normalized()
	var on_return: Enemy = _throw_dummy(hit_point + expected_out * 3.5)
	await get_tree().process_frame
	# The preview shows the bank.
	wt._profile = wt.profile()
	wt.evolution = "ricochet"
	wt.state = WeaponThrowSkill.State.CHARGING
	wt._hold = 10.0
	wt.charge = 1.0
	wt.update_preview(lane + aim_dir * 20.0)
	await get_tree().process_frame
	expect("the throw lane shows the bounce segment, reflected away from the wall", wt.preview != null and wt.preview.bounce_length > 1.0 and wt.preview.bounce_dir.x < -0.5 and wt.preview.bounce_dir.z > 0.0)
	wt.cancel_charge()
	wt.evolution = ""
	wt.update_preview(lane + aim_dir * 20.0)
	wt.state = WeaponThrowSkill.State.IN_HAND
	throw.call(lane + aim_dir * 40.0, full)
	var bounce_frame: int = 0
	while wt.bounces == 0 and bounce_frame < 400:
		await get_tree().physics_frame
		bounce_frame += 1
	var after_dir: Vector3 = wt._throw_dir
	expect("Ricochet bounces off the first wall using its real normal (out %.2f, %.2f)" % [after_dir.x, after_dir.z], wt.bounces == 1 and after_dir.x < -0.5 and absf(after_dir.dot(expected_out) - 1.0) < 0.05)
	expect("it keeps flying: it did not embed in the wall", wt.state == WeaponThrowSkill.State.FLYING_OUT)
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	expect("after the bounce it still strikes what is on its new line", wt.last_out_hits.has(on_return.get_instance_id()))
	expect("it bounced exactly once", wt.bounces == 1)
	wt.recall()
	var homed: bool = await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	expect("the recall brings it home and he catches it, as ever", homed and wt.thrown == null and not player.stats.weapon_locked)
	# A second wall: it cannot bounce twice.
	await clear_field.call()
	bank_wall.queue_free()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var wall_a: StaticBody3D = make_wall.call(lane + Vector3(7.0, 2.0, 0.0), Vector3(1.0, 4.0, 8.0))
	var wall_b: StaticBody3D = make_wall.call(lane + Vector3(-2.0, 2.0, 0.0), Vector3(1.0, 4.0, 8.0))
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), full)
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	expect("a second wall embeds it: no second bounce", wt.bounces == 1 and wt.thrown.center().x < lane.x + 7.0 and wt.thrown.center().x > lane.x - 2.5 and not wt._can_bounce(Vector3(1, 0, 0)))
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	wall_a.queue_free()
	wall_b.queue_free()
	await clear_field.call()
	lane = _clear_lane(26.0, 3.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	var weak_wall: StaticBody3D = make_wall.call(lane + Vector3(9.0, 2.0, 0.0), Vector3(1.0, 4.0, 8.0))
	await get_tree().process_frame
	throw.call(lane + Vector3(40, 0, 0), 0.2 * wt.profile()["charge_time"])
	await _wait_state(WeaponThrowSkill.State.EMBEDDED, 4.0)
	expect("a weak throw does not ricochet", wt.bounces == 0)
	wt.recall()
	await _wait_state(WeaponThrowSkill.State.IN_HAND, 8.0)
	weak_wall.queue_free()

	# --- Passives -------------------------------------------------------------------------------------------------------------------------------
	var hit_hero: Callable = func(damage: float, weight: float) -> void:
		var attacker: Enemy = _throw_dummy(player.global_position + Vector3(2.5, 0, 0))
		var result: Dictionary = Combat.resolve(attacker, player, damage, Combat.DamageType.PHYSICAL, false, weight)
		result["outcome"] = Combat.Outcome.CRUSHING
		result["damage"] = damage
		result["weight"] = weight
		player.invulnerable_time = 0.0
		player.receive(result, attacker.global_position)
		player.knock = Vector3.ZERO   # (the blow's shove would walk him out of the test's geometry)
		attacker.queue_free()
	var calm_hero: Callable = func() -> void:
		player.stun_time = 0.0
		player.slow_time = 0.0
		player.invulnerable_time = 0.0
		player.health = player.max_health
		player.attack_target = null
		player.movement.has_goal = false
		player.click_mode = 0
		skills.aiming_id = ""
		skills.busy = false
		player._unbowed_ready_ms = 0
		player.retaliation_time = 0.0
		player.knockdown.reset()
		player.combat_timer = 0.0
	await clear_field.call()
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	# Unbowed.
	TownState.reset()
	TownState.dev_set_hero_level(10)
	await calm_hero.call()
	skills.aiming_id = "skewer"
	hit_hero.call(4.0, 1.0)
	var baseline_stun: float = player.stun_time
	await calm_hero.call()
	TownState.buy_passive("unbowed")
	skills.aiming_id = "skewer"
	hit_hero.call(4.0, 1.0)
	expect("without Unbowed a light crushing hit stuns him mid-wind-up (%.2f)" % baseline_stun, baseline_stun > 0.3)
	expect("with Unbowed the first light stagger during a committed wind-up is shrugged off, and it was not free damage", player.stun_time == 0.0 and player.unbowed_suppressed == 1 and player.health < player.max_health)
	hit_hero.call(4.0, 1.0)
	expect("a second light hit right after still lands (a short cooldown, not permanent)", player.stun_time > 0.3)
	await calm_hero.call()
	skills.aiming_id = "skewer"
	hit_hero.call(4.0, 2.7)
	expect("a heavy blow still staggers him through Unbowed", player.stun_time > 0.3)
	await calm_hero.call()
	hit_hero.call(4.0, 1.0)
	expect("Unbowed does nothing when he is not committed to a wind-up", player.stun_time > 0.3)
	# Stubborn Advance.
	TownState.reset()
	TownState.dev_set_hero_level(10)
	var target: Enemy = _throw_dummy(Vector3(9, 0, 0))
	await calm_hero.call()
	player.attack_target = target
	hit_hero.call(4.0, 1.0)
	var advance_baseline: float = player.stun_time
	await calm_hero.call()
	TownState.buy_passive("stubborn_advance")
	player.attack_target = target
	hit_hero.call(4.0, 1.0)
	expect("without Stubborn Advance a light crushing hit stops the approach (%.2f)" % advance_baseline, advance_baseline > 0.3)
	expect("with it a light hit only slows him while he presses in", player.stun_time == 0.0 and player.slow_time > 0.0 and player.stubborn_suppressed == 1)
	await calm_hero.call()
	player.attack_target = target
	hit_hero.call(20.0, 1.0)
	expect("a heavy hit (a tenth of his health) still stops him", player.stun_time > 0.3)
	await calm_hero.call()
	hit_hero.call(4.0, 1.0)
	expect("walking about with no target he is stopped as ever", player.stun_time > 0.3)
	target.queue_free()
	# Retaliation.
	TownState.reset()
	TownState.dev_set_hero_level(10)
	TownState.buy_passive("retaliation")
	await calm_hero.call()
	var foe: Enemy = _throw_dummy(Vector3(2.0, 0, 0))
	hit_hero.call(2.0, 1.0)
	expect("a chip hit does not arm Retaliation", player.retaliation_time == 0.0)
	await calm_hero.call()
	hit_hero.call(20.0, 1.0)
	expect("a heavy hit arms it for about 3 seconds", player.retaliation_time > 2.5 and player.retaliation_time <= BuildDefs.RETALIATION_SECONDS)
	var power_hit: Dictionary = Combat.resolve(player, foe, 5.0, Combat.DamageType.PHYSICAL, false, 1.0)
	power_hit["skill_id"] = "power"
	foe.receive(power_hit, player.global_position)
	expect("only a basic strike uses it up: Power Strike does not", player.retaliations_fired == 0 and player.retaliation_time > 0.0)
	foe.stun_time = 0.0
	foe.knock = Vector3.ZERO
	var basic_hit: Dictionary = Combat.resolve(player, foe, 5.0, Combat.DamageType.PHYSICAL, false, 1.0)
	basic_hit["skill_id"] = "basic"
	basic_hit["damage"] = 5.0
	basic_hit["outcome"] = Combat.Outcome.HIT
	basic_hit["outcome"] = Combat.Outcome.HIT
	var foe_health: float = foe.health
	foe.receive(basic_hit, player.global_position)
	expect("the next basic strike sends its target reeling (fired %d, stagger %.2f, knock %.1f, hp lost %.1f), with no extra damage" % [player.retaliations_fired, foe.stun_time, foe.knock.length(), foe_health - foe.health], player.retaliations_fired == 1 and foe.stun_time >= 1.0 and foe.knock.length() > 4.0
		and foe_health - foe.health < 8.0)
	foe.stun_time = 0.0
	foe.knock = Vector3.ZERO
	var again: Dictionary = Combat.resolve(player, foe, 5.0, Combat.DamageType.PHYSICAL, false, 1.0)
	again["skill_id"] = "basic"
	again["damage"] = 5.0
	again["outcome"] = Combat.Outcome.HIT
	foe.receive(again, player.global_position)
	expect("it is used up: the strike after that is an ordinary one", player.retaliations_fired == 1 and player.retaliation_time == 0.0 and foe.stun_time < 0.9)
	await calm_hero.call()
	hit_hero.call(20.0, 1.0)
	player.retaliation_time = 0.05
	await get_tree().create_timer(0.25).timeout
	foe.stun_time = 0.0
	var late: Dictionary = Combat.resolve(player, foe, 5.0, Combat.DamageType.PHYSICAL, false, 1.0)
	late["skill_id"] = "basic"
	late["damage"] = 5.0
	late["outcome"] = Combat.Outcome.HIT
	foe.receive(late, player.global_position)
	expect("it expires: a late basic strike does nothing special", player.retaliations_fired == 1)
	foe.queue_free()
	# Iron Recovery.
	TownState.reset()
	TownState.dev_set_hero_level(10)
	TownState.buy_passive("iron_recovery")
	await clear_field.call()
	await calm_hero.call()
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	var ring: Array[Enemy] = []
	for angle in [0.0, 2.1, 4.2]:
		ring.append(_throw_dummy(Vector3(cos(angle), 0, sin(angle)) * 2.0))
	var iron_brute: Enemy = _throw_dummy(Vector3(cos(1.05), 0, sin(1.05)) * 2.2, "brute")
	hit_hero.call(4.0, 1.0)   # a light stagger: no shove to come
	await get_tree().create_timer(0.9).timeout
	expect("a light stagger does not arm Iron Recovery", player.iron_shoves == 0)
	await calm_hero.call()
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	iron_brute.global_position = Vector3(cos(1.05), 0, sin(1.05)) * 2.2
	iron_brute.knock = Vector3.ZERO
	for i in ring.size():
		ring[i].global_position = Vector3(cos(float(i) * 2.1), 0, sin(float(i) * 2.1)) * 2.0
		ring[i].knock = Vector3.ZERO
		ring[i].stun_time = 0.0
	var ring_before: Array[float] = []
	for e in ring:
		ring_before.append(e.flat_distance_to(player))
	hit_hero.call(20.0, 2.7)
	expect("a heavy hit knocks him down", player.stun_time > 0.3 and player.knockdown.active())
	await get_tree().create_timer(1.7).timeout
	var shoved: bool = true
	for i in ring.size():
		shoved = shoved and ring[i].flat_distance_to(player) > ring_before[i] + 1.0
	expect("when he shakes it off he shoves the lesser enemies round him back, once", player.iron_shoves == 1 and shoved)
	expect("the Brute shrugs the shove off", iron_brute.flat_distance_to(player) < 3.0)
	await get_tree().create_timer(0.6).timeout
	expect("no second shove without a second heavy stagger", player.iron_shoves == 1)
	for e in ring:
		e.queue_free()
	iron_brute.queue_free()
	# Mass Transfer.
	await clear_field.call()
	var transfer_runs: Array[Dictionary] = []
	for with_passive in [false, true]:
		TownState.reset()
		TownState.dev_set_hero_level(10)
		if with_passive:
			TownState.buy_passive("mass_transfer")
		await clear_field.call()
		player.global_position = Vector3(-6, 0, 0)
		player.reset_physics_interpolation()
		var first: Enemy = _throw_dummy(Vector3(0, 0, 0))
		var second: Enemy = _throw_dummy(Vector3(2.0, 0, 0))
		var third: Enemy = _throw_dummy(Vector3(4.2, 0, 0))
		await get_tree().process_frame
		first.knocked_by = player
		first.credit_hero()
		first.ragdoll_launch(Vector3(9.0, 0, 0), 2.0, Vector3(0, 0, 4))
		var second_peak: float = 0.0
		for i in 80:
			await get_tree().physics_frame
			second_peak = maxf(second_peak, second.global_position.x - 2.0)
		transfer_runs.append({"charges": first.ragdoll.transfer_used, "second_charges": second.mass_transfer_charges, "third_used": third.ragdoll.transfer_used if third.ragdoll != null else 0,
			"second_moved": second_peak, "third_moved": third.global_position.x - 4.2, "credited": second.hero_credited(), "second_knocked_down": second.is_ragdolled() or second.stun_time > 0.0})
	expect("without Mass Transfer nothing is passed on", int(transfer_runs[0]["charges"]) == 0)
	expect("with it the launched body passes its force to the one it hits, once (second moved %.1f against %.1f)" % [float(transfer_runs[1]["second_moved"]), float(transfer_runs[0]["second_moved"])],
		int(transfer_runs[1]["charges"]) == 1 and float(transfer_runs[1]["second_moved"]) > float(transfer_runs[0]["second_moved"]) + 1.0 and bool(transfer_runs[1]["second_knocked_down"]))
	expect("the chain is capped: what was bowled carries no transfer on", int(transfer_runs[1]["second_charges"]) == 0 and int(transfer_runs[1]["third_used"]) == 0)
	expect("the hero is credited for what a body he threw bowls over", bool(transfer_runs[1]["credited"]))

	# --- The Progression screen ----------------------------------------------------------------------------------------------------------
	TownState.reset()
	TownState.dev_set_hero_level(6)
	Gamepad.active = true
	hud.show_gear = true
	hud._open_character()
	await get_tree().process_frame
	var character: Control = hud.character_panel
	expect("the character screen has a PROGRESSION button", character.progression_button != null and character.progression_button.text == "PROGRESSION")
	hud.open_progression()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: ProgressionPanel = hud.progression_panel
	expect("it opens two sections, passives first, with the points shown", panel != null and panel.section == "passives" and panel.passive_cards.size() == BuildDefs.PASSIVE_ORDER.size()
		and panel.points_label.text == "Passive Points 3     Evolution Points 2")
	var focus: Control = panel.get_viewport().gui_get_focus_owner()
	expect("controller focus lands inside it (a card)", focus != null and panel.is_ancestor_of(focus) and panel.passive_cards.values().has(focus))
	expect("every control can take focus and the tabs link left and right", panel.passive_tab.focus_mode == Control.FOCUS_ALL and panel.back_button.focus_mode == Control.FOCUS_ALL
		and panel.passive_tab.get_node(panel.passive_tab.focus_neighbor_right) == panel.evolution_tab
		and panel.passive_cards.values().all(func(c: Button) -> bool: return c.focus_mode == Control.FOCUS_ALL))
	(panel.passive_cards["unbowed"] as Button).pressed.emit()
	await get_tree().process_frame
	expect("choosing a passive asks first and spends nothing", panel.confirm_box != null and TownState.passive_points_available() == 3 and not TownState.has_passive("unbowed"))
	panel.back()
	await get_tree().process_frame
	expect("Escape / back dismisses the question, not the screen", panel.confirm_box == null and hud.progression_panel == panel and TownState.passive_points_available() == 3)
	(panel.passive_cards["unbowed"] as Button).pressed.emit()
	await get_tree().process_frame
	panel.confirm_button.pressed.emit()
	await get_tree().process_frame
	expect("confirming buys it and the screen updates at once (2 left, PURCHASED)", TownState.has_passive("unbowed") and TownState.passive_points_available() == 2
		and panel.points_label.text == "Passive Points 2     Evolution Points 2" and (panel.passive_cards["unbowed"] as Button).text.contains("PURCHASED"))
	expect("the character screen's own count follows", character.points_label.text == "Passive Points 2     Evolution Points 2")
	(panel.passive_cards["unbowed"] as Button).pressed.emit()
	await get_tree().process_frame
	expect("a purchased passive asks nothing and cannot be bought again", panel.confirm_box == null and TownState.passive_points_available() == 2)
	panel.evolution_tab.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	expect("the EVOLUTIONS section shows Weapon Throw and its three choices", panel.section == "evolutions" and panel.evolution_cards.size() == 3 and panel.evolution_cards.has("throw/wallspike")
		and panel.evolution_cards.has("throw/reaping_recall") and panel.evolution_cards.has("throw/ricochet"))
	focus = panel.get_viewport().gui_get_focus_owner()
	expect("focus moves into the new section", focus != null and panel.is_ancestor_of(focus) and panel.evolution_cards.values().has(focus))
	(panel.evolution_cards["throw/ricochet"] as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	expect("an evolution asks first, warns it is permanent, spends nothing, and defaults to NO", panel.confirm_box != null and panel.confirm_text.text.contains("permanent") and TownState.selected_evolution("throw") == ""
		and TownState.evolution_points_available() == 2 and panel.cancel_button.has_focus())
	panel.cancel_button.pressed.emit()
	await get_tree().process_frame
	expect("cancelling leaves it unspent", TownState.selected_evolution("throw") == "" and TownState.evolution_points_available() == 2 and panel.confirm_box == null)
	(panel.evolution_cards["throw/ricochet"] as Button).pressed.emit()
	await get_tree().process_frame
	panel.confirm_button.pressed.emit()
	await get_tree().process_frame
	expect("confirming selects it for good: 1 Evolution Point left, Ricochet SELECTED, the others closed", TownState.selected_evolution("throw") == "ricochet" and TownState.evolution_points_available() == 1
		and (panel.evolution_cards["throw/ricochet"] as Button).text.contains("SELECTED") and (panel.evolution_cards["throw/wallspike"] as Button).text.contains("closed")
		and (panel.evolution_cards["throw/reaping_recall"] as Button).text.contains("closed"))
	(panel.evolution_cards["throw/wallspike"] as Button).pressed.emit()
	await get_tree().process_frame
	expect("a closed evolution cannot be chosen", panel.confirm_box == null and TownState.selected_evolution("throw") == "ricochet")
	expect("and the throw uses it at once, with no restart", player.evolution_of("throw") == "ricochet")
	panel.back_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	expect("Back returns to the character screen with focus on PROGRESSION", hud.progression_panel == null and hud.character_panel.visible and hud.character_panel.progression_button.has_focus())
	hud.close_character()
	Gamepad.active = false
	TownState.reset()
