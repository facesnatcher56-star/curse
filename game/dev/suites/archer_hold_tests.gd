extends DevSuite
## Deterministic hold-and-retry for an AI archer. A closed wall square around the target leaves no firing position with sight of it, so
## the archer must hold, retry on the cooldown, fire nothing, and make no repeated path requests. Removing the walls must end the hold
## and start a shot. Positions and walls are fixed, so the result does not depend on random state.

const DELTA := 1.0 / 60.0
const HOLD_FRAMES := 240          # four seconds: at least three retry cooldowns (RETRY_COOLDOWN is 1.0 s)
const SHOT_FRAMES := 600          # ten seconds: an upper bound on the wait for the first shot after the walls go

func _walls_around(centre: Vector3, half: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.position = centre
	for side in [Vector3(0, 0, half), Vector3(0, 0, -half), Vector3(half, 0, 0), Vector3(-half, 0, 0)]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var along_x: bool = side.z != 0.0
		box.size = Vector3(half * 2.0 + 0.4, height, 0.4) if along_x else Vector3(0.4, height, half * 2.0 + 0.4)
		shape.shape = box
		shape.position = Vector3(side.x, height * 0.5, side.z)
		body.add_child(shape)
	get_tree().current_scene.add_child(body)
	return body

func _test_archer_hold() -> void:
	TownState.persist = false
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	archer.testing_disabled = false
	archer.skills.busy = false
	archer.attack_target = null
	var lane: Vector3 = _clear_lane(24.0, 10.0)
	archer.global_position = lane
	archer.reset_physics_interpolation()
	var enemy: Enemy = _spawn_enemy(lane + Vector3(14.0, 0.0, 0.0))
	enemy.set_physics_process(false)
	enemy.aggro_range = 0.0
	enemy.max_health = 500.0
	enemy.health = enemy.max_health
	var walls: StaticBody3D = _walls_around(enemy.global_position, 2.5, 3.0)
	for i in 3:
		await get_tree().physics_frame
	var bow: BowAttack = archer.bow
	bow.cancel()
	bow._has_spot = false
	bow._replan_wait = 0.0
	bow._rejected.clear()

	# Phase 1: walled in. No firing position can see the target, so the archer must hold.
	var holds0: int = bow.holds
	var shots0: int = bow.shots
	var retries0: int = bow.retry_attempts
	var queries0: int = int(archer.movement._nav_state.get("queries", 0))
	var held_frames: int = 0
	for i in HOLD_FRAMES:
		bow.engage(enemy, null, DELTA)
		if bow._holding:
			held_frames += 1
		await get_tree().physics_frame
	var holds_entered: int = bow.holds - holds0
	var shots_in_hold: int = bow.shots - shots0
	var retries: int = bow.retry_attempts - retries0
	var path_requests: int = int(archer.movement._nav_state.get("queries", 0)) - queries0
	print("HOLD counters: holds_entered=", holds_entered, " held_frames=", held_frames, " shots_in_hold=", shots_in_hold,
		" retry_attempts=", retries, " path_requests=", path_requests, " frames=", HOLD_FRAMES)
	expect("hold: the hold branch was entered (counter > 0)", holds_entered > 0)
	expect("hold: the archer held for most of the window", held_frames >= HOLD_FRAMES / 2)
	expect("hold: zero shots fired into the walls during the hold", shots_in_hold == 0)
	expect("hold: it retried after the cooldown (at least one retry)", retries >= 1)
	expect("hold: it does not retry every frame (bounded by the cooldown)", retries <= HOLD_FRAMES / 60 + 2)
	expect("hold: path requests stay bounded over the run (no repeated requests)", path_requests <= 8)

	# Phase 2: the walls come down. The archer leaves hold and fires once it has sight of the target.
	walls.queue_free()
	for i in 3:
		await get_tree().physics_frame
	var shots1: int = bow.shots
	var fired := false
	for i in SHOT_FRAMES:
		bow.engage(enemy, null, DELTA)
		await get_tree().physics_frame
		if bow.shots > shots1:
			fired = true
			break
	print("LEAVE HOLD: fired=", fired, " holding_now=", bow._holding, " shots=", bow.shots - shots1)
	expect("leave hold: after line of sight is gained the archer fires", fired)
	expect("leave hold: the hold state is cleared", not bow._holding)

	bow.cancel()
	archer.skills.busy = false
	enemy.queue_free()
	await get_tree().physics_frame
