extends DevSuite
## Self-test: Skewer (aim preview, impaling, the full flow).

## Holding the Skewer key shows the lane and the kick fan, cut short by a wall, and lights up the enemies the blade would take.
func _test_skewer_preview() -> void:
	player.global_position = _free_lane_start(16.0, 6.0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	await get_tree().process_frame
	var cursor: Vector3 = player.global_position + Vector3(12, 0, 0)
	var zs: Array[Enemy] = []
	for i in 4:
		var z: Enemy = _spawn_enemy(player.global_position + Vector3(2.5 + i * 1.4, 0, 0.1))
		z.aggro_range = 0.0
		zs.append(z)
	var side: Enemy = _spawn_enemy(player.global_position + Vector3(4.0, 0, 5.0))
	side.aggro_range = 0.0
	await get_tree().physics_frame
	player.skills.aiming_id = "skewer"
	player.skills.aiming_action = "skill_2"
	player.skills.update_aim(cursor)
	var lane: SkewerPreview = player.skills._lane
	expect("holding Skewer shows its lane", lane != null and lane.node.visible)
	expect("the lane is as long as the charge (range plus the skid) in the open", lane != null and absf(lane.length - (9.0 + SkewerPreview.SKID)) < 0.2)
	var lit: int = 0
	for z in zs:
		lit += 1 if z.highlighted else 0
	expect("the three nearest in the lane are lit, the fourth and the one off to the side are not", lit == 3 and not zs[3].highlighted and not side.highlighted)
	player.skills.clear_aim()
	expect("letting go clears the lane and the lights", not lane.node.visible and not zs[0].highlighted)
	# A wall across the lane shortens it.
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 4.0, 8.0)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = player.global_position + Vector3(5.0, 2.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.skills.aiming_id = "skewer"
	player.skills.update_aim(cursor)
	expect("a wall in the way cuts the lane short", lane.length < 5.0 and lane.length > 3.0)
	player.skills.clear_aim()
	wall.queue_free()
	for e in zs:
		e.queue_free()
	side.queue_free()
	await get_tree().process_frame

func _test_skewer() -> void:
	player.global_position = _free_lane_start(16.0, 6.0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.skills.blade_blood = 0.0
	await get_tree().process_frame
	var brute: Enemy = _spawn_enemy(player.global_position + Vector3(2.4, 0, 0.0), "brute")
	brute.aggro_range = 0.0
	brute.max_health = 800.0
	brute.health = 800.0
	var zombies: Array[Enemy] = []
	for i in 4:
		var z: Enemy = _spawn_enemy(player.global_position + Vector3(4.2 + i * 1.3, 0, 0.1 * i))
		z.aggro_range = 0.0
		z.max_health = 500.0
		z.health = 500.0
		zombies.append(z)
	await get_tree().process_frame
	var stains_before: int = get_tree().get_nodes_in_group("stains").size()
	player.skewer.start_skewer(player.global_position + Vector3(11, 0, 0))
	var max_impaled: int = 0
	var min_blade_dot: float = 1.0
	var phases: Array[int] = []
	var ragdoll_states: Dictionary = {}
	var brute_impaled: bool = false
	var brute_stunned: bool = false
	var killed_mid_carry: Enemy = null
	var corpse_checked: bool = false
	var corpse_ok: bool = false
	var farthest: float = 0.0   # how far from the hero any victim got: they are hit, so they walk back once they are up again
	var elapsed: float = 0.0
	while elapsed < 9.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		max_impaled = maxi(max_impaled, player.skewer.skewer_impaled.size())
		if killed_mid_carry == null and player.skewer.skewer_impaled.size() == 2:
			killed_mid_carry = player.skewer.skewer_impaled[1] as Enemy
			killed_mid_carry._apply_damage(99999.0)  # dies while impaled
		brute_impaled = brute_impaled or brute.impaled
		brute_stunned = brute_stunned or brute.stun_time > 0.5
		if player.skewer.skewer_phase == 2 and player.skewer.skewer_t > 0.25 and player.model.weapon_tip != null:
			var blade: Vector3 = player.model.weapon_tip.global_position - player.model.weapon_base.global_position
			min_blade_dot = minf(min_blade_dot, blade.normalized().dot(player.skewer.skewer_dir))
		if phases.is_empty() or phases[phases.size() - 1] != player.skewer.skewer_phase:
			phases.append(player.skewer.skewer_phase)
			if player.skewer.skewer_phase == 3:
				var lanes: Array[String] = []
				for z in zombies:
					var rel: Vector3 = z.global_position - player.global_position
					lanes.append("(%.1f,%.1f)" % [rel.x, rel.z])
				print("    charge ended: travel=", snappedf(player.skewer.skewer_travel, 0.1), " t=", snappedf(player.skewer.skewer_t, 0.01), " impaled=", player.skewer.skewer_impaled.size(), " zombies rel ", ", ".join(lanes))
		# Snapshot the corpse while it is still lying there (it sinks and is freed a few seconds later).
		if not corpse_checked and is_instance_valid(killed_mid_carry) and killed_mid_carry.ragdoll != null \
				and killed_mid_carry.ragdoll.state == Ragdoll.State.LYING:
			corpse_checked = true
			corpse_ok = killed_mid_carry.dead and killed_mid_carry.global_position.distance_to(player.global_position) > 3.5
		var any_ragdoll: bool = false
		for z in zombies:
			if not is_instance_valid(z):
				continue
			if z.is_ragdolled():
				any_ragdoll = true
				ragdoll_states[z.ragdoll.state] = true
				farthest = maxf(farthest, z.global_position.distance_to(player.global_position))
		if player.skewer.skewer_phase == 0 and not any_ragdoll and elapsed > 1.5:
			break
	await get_tree().create_timer(0.5).timeout
	var recovered: int = 0
	var flung: int = 0
	for z in zombies:
		if not is_instance_valid(z):
			continue
		if not z.is_ragdolled() and not z.impaled and z.collision_layer == Actor.LAYER_ENEMY:
			recovered += 1
		if z.global_position.distance_to(player.global_position) > 4.0:
			flung += 1
	if farthest > 4.0:
		flung = maxi(flung, 1)
	expect("corpse impaled then kicked ends lying on the ground", corpse_ok)
	print("  skewer corpse (died while impaled): kicked away and ended lying on the ground=", corpse_ok)
	var states: Array = ragdoll_states.keys()
	states.sort()
	expect("skewer impales 3", max_impaled == 3)
	expect("skewered enemies recover", recovered >= 2)
	expect("skewered enemies are flung", flung >= 1)
	print("  skewer: impaled=", max_impaled, " phases=", phases, " ragdoll states seen=", states, " (1 hang,2 flight,3 lying,4 rising)",
		" recovered=", recovered, " flung>4m=", flung, " farthest=", snappedf(farthest, 0.1))
	expect("a Brute is not impaled", not brute_impaled)
	expect("a Brute is staggered by the charge", brute_stunned)
	expect("collision mask restored after skewer", player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY))
	print("  skewer vs Brute: impaled=", brute_impaled, " staggered=", brute_stunned, " damage taken=", int(brute.max_health - brute.health),
		"   blood stains added=", get_tree().get_nodes_in_group("stains").size() - stains_before, " blade blood=", snappedf(player.skills.blade_blood, 0.01),
		" blade alignment=", snappedf(min_blade_dot, 0.01), " mask restored=", player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY))
	if is_instance_valid(brute):
		brute.queue_free()
	for z in zombies:
		if is_instance_valid(z):
			z.queue_free()
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	await get_tree().process_frame

## Skewer and Leap while running carry the speed in (no stop to wind up), and the end of a Skewer charge deals with what is beside and
## behind the hero: the small are knocked down, the big staggered and slowed.
func _test_skewer_flow() -> void:
	player.global_position = _free_lane_start(16.0, 6.0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	await get_tree().process_frame
	var reach: float = float(SkillDb.all()["skewer"]["range"])   # beside the lane near its end: where the hero will be standing when it stops
	var small: Enemy = _spawn_enemy(player.global_position + Vector3(reach - 1.0, 0, 2.3))
	var big: Enemy = _spawn_enemy(player.global_position + Vector3(reach - 2.0, 0, -2.4), "brute")
	for e in [small, big]:
		e.aggro_range = 0.0
		e.max_health = 900.0
		e.health = 900.0
	await get_tree().process_frame
	player.velocity = Vector3(5.0, 0.0, 0.0)   # running
	player.skewer.start_skewer(player.global_position + Vector3(11, 0, 0))
	expect("a charge started at a run skips the wind-up", player.skewer.skewer_phase == 2 and player.skewer.skewer_t > 0.0)
	var saw_down: bool = false
	var saw_stagger: bool = false
	var elapsed: float = 0.0
	while elapsed < 3.0 and player.skewer.skewer_phase != 0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		saw_down = saw_down or small.is_ragdolled()
		saw_stagger = saw_stagger or (big.stun_time > 0.3 and big.slow_time > 0.0)
	expect("an enemy at the hero's back is knocked down when the charge ends", saw_down)
	expect("a big one there is staggered and slowed instead", saw_stagger)
	await get_tree().create_timer(1.5).timeout
	player.stats.cooldowns.clear()
	player.stats.mana = player.stats.max_mana
	player.velocity = Vector3.ZERO
	player.leap.start_leap(player.global_position + Vector3(0, 0, 5))
	expect("a leap from a standstill still crouches first", player.leap.leap_phase == 1)
	player.leap.end_leap()
	player.velocity = Vector3(0.0, 0.0, 5.0)
	player.stats.cooldowns.clear()
	player.stats.mana = player.stats.max_mana
	player.leap.start_leap(player.global_position + Vector3(0, 0, 5))
	expect("a leap from a run goes straight into the air", player.leap.leap_phase == 2)
	player.leap.end_leap()
	# A crowd never stops the charge: a lane packed with enemies and a full blade, and the hero still runs the whole way.
	player.stats.cooldowns.clear()
	player.stats.mana = player.stats.max_mana
	player.global_position = _free_lane_start(16.0, 6.0)
	player.reset_physics_interpolation()
	var crowd: Array[Enemy] = []
	for i in 9:
		var z: Enemy = _spawn_enemy(player.global_position + Vector3(2.5 + i * 1.2, 0, 0.3 * (i % 3 - 1)))
		z.aggro_range = 0.0
		z.max_health = 900.0
		z.health = 900.0
		crowd.append(z)
	await get_tree().process_frame
	var origin: Vector3 = player.global_position
	player.skewer.start_skewer(origin + Vector3(11, 0, 0))
	var elapsed2: float = 0.0
	var stalled: int = 0
	var last_x: float = player.global_position.x
	while elapsed2 < 4.0 and player.skewer.skewer_phase in [1, 2]:
		await get_tree().physics_frame
		elapsed2 += 1.0 / 60.0
		player.knock = Vector3(-9.0, 0, 0)   # blows landing on him push him back; they must not stop him
		# Once up to speed the hero covers ground every single frame: no hit-pause, no hitch.
		if player.skewer.skewer_phase == 2 and player.skewer.skewer_t > 0.4:
			if player.hitpause > 0.0 or player.global_position.x - last_x < 0.15:
				stalled += 1
		last_x = player.global_position.x
	var ran: float = player.global_position.distance_to(origin)
	expect("a packed lane does not stop the charge short (ran %.1f of %.1f m)" % [ran, reach], ran >= reach - 1.0)
	expect("and it never hitches: no frame at speed without moving (%d stalled)" % stalled, stalled == 0)
	player.skewer.end_skewer()
	player.skills.cancel_action()
	for e in crowd:
		if is_instance_valid(e):
			e.queue_free()
	# Holding the Skewer key to aim does not stop a hero who is running: he keeps going, and releasing charges at once.
	await get_tree().create_timer(1.2).timeout
	player.stats.cooldowns.clear()
	player.stats.mana = player.stats.max_mana
	player.global_position = _free_lane_start(16.0, 6.0)
	player.reset_physics_interpolation()
	player.skills.clear_aim()
	var goal: Vector3 = player.global_position + Vector3(12, 0, 0)
	player.movement.goal = goal
	player.movement.has_goal = true
	var key: String = "skill_%d" % (player.skills.hotbar.find("skewer") + 1)
	Input.action_press(key)
	var start_x: float = player.global_position.x
	for i in 25:
		await get_tree().physics_frame
	var ran_on: bool = player.skills.aiming_id == "skewer" and player.global_position.x > start_x + 1.5
	var speed_held: float = Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release(key)
	for i in 3:
		await get_tree().physics_frame
	expect("aiming Skewer while running keeps the hero running", ran_on and speed_held > SkewerSkill.RUNNING_START)
	expect("and letting go charges straight away, with no stop first", player.skewer.skewer_phase == 2)
	player.skewer.end_skewer()
	player.skills.cancel_action()
	for e in [small, big]:
		if is_instance_valid(e):
			e.queue_free()
