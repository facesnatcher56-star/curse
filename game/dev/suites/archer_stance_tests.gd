extends DevSuite
## The archer's engagement rules: a target in bow reach with a clear sight line is shot from where he stands (no walk, no step back);
## he moves only when the target is out of reach or out of sight, and only as far as it takes to shoot; an enemy in melee contact
## turns him to his dagger, and the bow comes back once the contact is gone. The stance is driven the way the game drives it (the
## party AI and the controlled archer call Player.update_melee_stance), with the archer's own bow ticked as Player's busy loop does.

const DELTA := 1.0 / 60.0
const FIRE_FRAMES := 420   # about seven seconds: several shots at the bow's cadence

func _begin_case(archer: ArcherCompanion, lane: Vector3) -> Enemy:
	archer.testing_disabled = true   # the party AI stays off: these checks drive the archer's decisions directly
	_prepare_archer(archer)
	archer.global_position = lane
	archer.reset_physics_interpolation()
	var enemy: Enemy = _spawn_enemy(lane + Vector3(5.0, 0.0, 0.0))
	enemy.set_physics_process(false)
	enemy.aggro_range = 0.0
	enemy.max_health = 5000.0
	enemy.health = enemy.max_health
	return enemy

## One frame of the game's ranged loop for the archer: the stance decision, the bow's decision, and the busy shot ticking.
func _frame(archer: ArcherCompanion, target: Enemy) -> void:
	archer.update_melee_stance(target)
	if archer.bow != null and archer.stats.is_ranged():
		archer.bow.engage(target, null, DELTA)
		if archer.skills.busy:
			archer.bow.tick(DELTA)
	await get_tree().physics_frame

func _clear_scene() -> void:
	TownState.persist = false
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame

func _test_archer_stance() -> void:
	await _clear_scene()
	var archer: ArcherCompanion = game.companion
	var lane: Vector3 = await _own_lane(26.0, 10.0)

	# 1. In reach with a clear line, closer than the old step-back distance: he fires from where he stands and does not route.
	var enemy: Enemy = _begin_case(archer, lane)
	enemy.global_position = lane + Vector3(5.0, 0.0, 0.0)
	await get_tree().physics_frame
	var bow: BowAttack = archer.bow
	bow.cancel()
	bow._has_spot = false
	bow._replan_wait = 0.0
	var shots0: int = bow.shots
	var queries0: int = Nav.requests_total
	var moved := false
	for i in FIRE_FRAMES:
		await _frame(archer, enemy)
		if archer.movement.has_goal or bow._has_spot:
			moved = true
	print("HOLD IN REACH: shots=", bow.shots - shots0, " moved=", moved, " path_requests=", Nav.requests_total - queries0,
		" stance=", not archer.stats.stance_weapon.is_empty())
	expect("reach: a target in bow reach and sight at 5 m is shot from where he stands (shots fired)", bow.shots - shots0 >= 3)
	expect("reach: no firing position is taken and no walk is planned while he fires (no step back, no reposition)", not moved)
	expect("reach: no path requests are made while he fires in reach", Nav.requests_total == queries0)
	expect("reach: the bow stays out at 5 m (no melee stance without contact)", archer.bow != null and archer.stats.stance_weapon.is_empty())

	# 2. Out of reach: he moves only as far as it takes to get into shooting range (no walk to a preferred distance).
	archer.skills.busy = false
	bow.cancel()
	bow._has_spot = false
	bow._replan_wait = 0.0
	enemy.global_position = lane + Vector3(20.0, 0.0, 0.0)
	await get_tree().physics_frame
	await _frame(archer, enemy)
	expect("out of reach: a firing position is taken when the target is beyond bow range", bow._has_spot)
	# The least walk is to the straight-back ring point on the navmesh (snapped there, as the bow snaps its own candidates); it can be
	# no nearer than the reach limit, and the spot taken must be that nearest sighted candidate, not a further lateral one.
	var straight: Vector3 = Nav.snap(archer, enemy.global_position + Vector3(-BowAttack.SPOT_OUTER, 0, 0))
	var least_walk: float = archer.flat_distance_to_point(straight)
	var walk: float = archer.flat_distance_to_point(bow._spot)
	print("OUT OF REACH: gap=20 walk=", snappedf(walk, 0.01), " least_walk=", snappedf(least_walk, 0.01),
		" spot_reach=", snappedf(Vector2(bow._spot.x - enemy.global_position.x, bow._spot.z - enemy.global_position.z).length(), 0.01))
	expect("out of reach: the walk is only far enough to shoot (the nearest sighted ring point, not a further one)",
		bow._has_spot and walk <= least_walk + 0.6 and walk >= 20.0 - BowAttack.SHOT_RANGE - 0.5)
	expect("out of reach: the chosen spot is within bow range with clear sight", bow._has_spot
		and Vector2(bow._spot.x - enemy.global_position.x, bow._spot.z - enemy.global_position.z).length() <= BowAttack.SHOT_RANGE - 1.0
		and Nav.sight_clear(archer, bow._spot, enemy.global_position + Vector3(0, 0.8, 0), null))

	# 3. Melee contact: the dagger comes out, the bow is put away, and the melee attack is the one used.
	bow.cancel()
	archer.skills.busy = false
	enemy.global_position = archer.global_position + Vector3(1.2, 0.0, 0.0)
	await get_tree().physics_frame
	archer.update_melee_stance(enemy)
	expect("melee: an enemy in contact draws the dagger (stance held)", not archer.stats.stance_weapon.is_empty())
	expect("melee: the wielded weapon is the dagger", archer.stats.wielded_weapon() != null
		and ItemDb.get_def(String(archer.stats.wielded_weapon().get("def", ""))).id == "dagger")
	expect("melee: the archer is not ranged while the dagger is out, and the bow is stowed (object kept)",
		not archer.stats.is_ranged() and archer.bow != null and archer.bow.stowed)
	expect("melee: the bow is still the worn weapon (only put away, not unequipped)", archer.stats.bow_worn())
	archer.skills.start_skill("basic", enemy)
	expect("melee: the basic melee attack starts on the enemy in contact", archer.skills.busy
		and String(archer.skills.busy_def.get("kind", "")) != "ranged")
	archer.skills.busy = false
	archer.skills.busy_def = {}

	# 4. Hysteresis: an enemy that steps back a little keeps the dagger out; the bow comes back only with room.
	enemy.global_position = archer.global_position + Vector3(3.2, 0.0, 0.0)
	await get_tree().physics_frame
	archer.update_melee_stance(enemy)
	expect("melee: a step back inside the room margin keeps the dagger (no flip-flop)", not archer.stats.stance_weapon.is_empty())
	enemy.global_position = archer.global_position + Vector3(6.0, 0.0, 0.0)
	await get_tree().physics_frame
	archer.update_melee_stance(enemy)
	expect("room: with the enemy out of melee the bow comes back", archer.stats.stance_weapon.is_empty() and archer.bow != null
		and not archer.bow.stowed and archer.stats.is_ranged())

	# 5. A shot being drawn when the enemy closes is given up for the dagger.
	bow = archer.bow
	bow.cancel()
	enemy.global_position = archer.global_position + Vector3(9.0, 0.0, 0.0)
	await get_tree().physics_frame
	bow.start(enemy)
	expect("draw: a shot starts at 9 m", archer.skills.busy and String(archer.skills.busy_def.get("kind", "")) == "ranged")
	enemy.global_position = archer.global_position + Vector3(1.2, 0.0, 0.0)
	await get_tree().physics_frame
	archer.update_melee_stance(enemy)
	expect("draw: an enemy reaching contact mid-draw cancels the shot and draws the dagger", archer.bow != null
		and archer.bow.stowed and not archer.stats.stance_weapon.is_empty() and not archer.skills.busy)

	# 6. The target is gone: the stance ends.
	archer.update_melee_stance(null)
	expect("gone: with no target the dagger is put away and the bow returns", archer.stats.stance_weapon.is_empty()
		and archer.bow != null and not archer.bow.stowed and archer.stats.is_ranged())

	bow = archer.bow
	bow.cancel()
	archer.skills.busy = false
	enemy.queue_free()
	await get_tree().physics_frame
