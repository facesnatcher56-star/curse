extends DevSuite
## Archer targets and sight: which props the bow may break, a sight line blocked by scenery, arrows breaking a nest, and the
## controlled archer's order to shoot a nest from a firing position.

func _test_archer_targets() -> void:
	TownState.persist = false
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	archer.testing_disabled = false
	archer.take_aim_armed = false
	archer.skills.busy = false
	var lane: Vector3 = _clear_lane(20.0, 8.0)
	archer.global_position = lane
	player.global_position = lane + Vector3(0.0, 0.0, -6.0)
	player.reset_physics_interpolation()
	archer.reset_physics_interpolation()
	await get_tree().physics_frame

	# Valid targets: the hero breaks barrels and nests; carts, gravestones and braziers are not hero targets.
	var barrel: Destructible = arena.place_prop("barrel", lane + Vector3(7.0, 0.0, 0.0), 0.0, 1.0) as Destructible
	var nest: Destructible = arena.place_prop("crypt/nest", lane + Vector3(9.0, 0.0, 3.0), 0.0, 1.9) as Destructible
	var stone: Destructible = arena.place_prop("gravestone", lane + Vector3(9.0, 0.0, -3.0), 0.0, 1.3) as Destructible
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("classification: a placed nest and barrel are hero targets", nest != null and barrel != null and nest.is_hero_target() and barrel.is_hero_target())
	expect("classification: a gravestone is not a hero target", stone != null and not stone.is_hero_target())
	var spent: Destructible = arena.place_prop("crypt/nest", lane + Vector3(12.0, 0.0, 7.0), 0.0, 1.9) as Destructible
	await get_tree().physics_frame
	expect("classification: a broken nest stops being a target", spent != null and spent.hit(9999.0, Vector3.RIGHT) and not spent.is_hero_target())

	# Sight: a barrel between the archer and an enemy blocks the shot, and the bow neither fires nor walks it into the scenery.
	var enemy: Enemy = _spawn_enemy(lane + Vector3(15.0, 0.0, 0.0))
	enemy.set_physics_process(false)
	enemy.aggro_range = 0.0
	enemy.max_health = 500.0
	enemy.health = enemy.max_health
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("sight: a barrel between archer and enemy blocks the sight line", not Nav.line_clear(archer, enemy.global_position))
	archer.bow.start(enemy)
	expect("sight: the bow refuses a blocked shot (no draw starts)", not archer.skills.busy)
	archer.bow.engage(enemy, null, 1.0 / 60.0)
	expect("sight: engage with a blocked target does not start a shot", not archer.skills.busy)
	archer.bow._pick_spot(enemy.global_position, null)
	var spot: Vector3 = archer.bow._spot
	expect("sight: a firing position is found with a clear line to the target, in range",
		archer.bow._has_spot and Nav.sight_clear(archer, spot, enemy.global_position)
		and Vector2(spot.x - enemy.global_position.x, spot.z - enemy.global_position.z).length() <= BowAttack.SHOT_RANGE)
	archer.bow._has_spot = false
	barrel.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("sight: with the barrel gone the line is clear and the bow takes the shot", Nav.line_clear(archer, enemy.global_position))
	archer.bow.start(enemy)
	expect("sight: a clear shot starts", archer.skills.busy)
	archer.bow.cancel()
	archer.skills.busy = false

	# Arrows: a nest takes arrow damage, a gravestone only stops the arrow.
	var nest_before: float = nest.hp
	var stone_before: float = stone.hp
	var arrow := CompanionArrow.fire(game, archer, lane + Vector3(0.0, 1.2, 3.0), nest.global_position + Vector3(0.0, 1.0, 0.0), 20.0)
	for i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(arrow) or nest.hp < nest_before:
			break
	expect("arrows: an arrow that strikes a hero-breakable nest damages it", nest.hp < nest_before)
	var stone_arrow := CompanionArrow.fire(game, archer, lane + Vector3(0.0, 1.2, -3.0), stone.global_position + Vector3(0.0, 0.6, 0.0), 20.0)
	for i in 40:
		await get_tree().physics_frame
	expect("arrows: a gravestone is not damaged by an arrow", is_equal_approx(stone.hp, stone_before))

	# The controlled archer's order: a nest in clear sight at range is shot from a firing position until it breaks or is hit.
	# The earlier props stand off the lane's sight line; take them out so the ordered nest is in clear sight.
	for prop in [nest, stone, spent]:
		if is_instance_valid(prop) and not prop.is_queued_for_deletion():
			prop.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var order_nest: Destructible = arena.place_prop("crypt/nest", lane + Vector3(13.0, 0.0, 0.0), 0.0, 1.9) as Destructible
	await get_tree().physics_frame
	await get_tree().physics_frame
	archer.global_position = lane
	archer.reset_physics_interpolation()
	var order_before: float = order_nest.hp
	archer.bow.engage(null, order_nest, 1.0 / 60.0)
	expect("ordered: the archer starts shooting a nest it has clear sight of", archer.skills.busy)
	var hit_nest := false
	for i in 300:
		await get_tree().physics_frame
		if order_nest.hp < order_before:
			hit_nest = true
			break
	expect("ordered: the controlled archer damages the ordered nest", hit_nest)
	archer.bow.cancel()
	archer.skills.busy = false
	for prop in [nest, stone, order_nest]:
		if is_instance_valid(prop) and not prop.broken:
			prop.queue_free()
	enemy.queue_free()
	await get_tree().physics_frame

## Firing positions: a clear sight line, range near the preferred distance, lateral positions around a blocker, melee separation,
## no oscillation over time, and hold when no position exists.
func _test_archer_positioning() -> void:
	TownState.persist = false
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	archer.testing_disabled = false
	archer.skills.busy = false
	var lane: Vector3 = _clear_lane(24.0, 10.0)
	archer.global_position = lane
	archer.reset_physics_interpolation()
	var enemy: Enemy = _spawn_enemy(lane + Vector3(14.0, 0.0, 0.0))
	enemy.set_physics_process(false)
	enemy.aggro_range = 0.0
	enemy.max_health = 500.0
	enemy.health = enemy.max_health
	var barrel: Destructible = arena.place_prop("barrel", lane + Vector3(7.0, 0.0, 0.0), 0.0, 1.0) as Destructible
	await get_tree().physics_frame
	await get_tree().physics_frame
	var point: Vector3 = enemy.global_position
	archer.bow._rejected.clear()
	var picked: bool = archer.bow._pick_spot(point, null)
	var spot: Vector3 = archer.bow._spot
	var to_spot := Vector3(spot.x - point.x, 0.0, spot.z - point.z)
	var to_archer := Vector3(archer.global_position.x - point.x, 0.0, archer.global_position.z - point.z)
	var reach: float = to_spot.length()
	expect("positioning: a position is found when the direct line is blocked", picked)
	expect("positioning: LOS - the chosen position has a clear sight line to the target", picked and Nav.sight_clear(archer, spot, point, null))
	expect("positioning: range - the chosen position is within the bow's effective range", picked and reach >= BowAttack.SPOT_MIN and reach <= BowAttack.SHOT_RANGE - 1.0)
	expect("positioning: lateral - the position is off the blocked line of advance, not a straight advance",
		picked and to_spot.normalized().angle_to(to_archer.normalized()) > 0.2)

	# Melee separation: an aggro melee enemy on the straight-back ring is never picked against.
	var melee_at: Vector3 = point + to_archer.normalized() * BowAttack.SPOT_RANGE
	var melee: Enemy = _spawn_enemy(melee_at)
	melee.set_physics_process(false)
	melee.aggro_range = 40.0
	melee.wake()
	await get_tree().physics_frame
	expect("positioning: the melee enemy is aggro (precondition)", melee.is_aggro())
	archer.bow._rejected.clear()
	archer.bow._has_spot = false
	var melee_pick: bool = archer.bow._pick_spot(point, null)
	var melee_spot: Vector3 = archer.bow._spot
	expect("positioning: melee separation - no firing position within melee reach of an aggro enemy",
		not melee_pick or Vector2(melee_spot.x - melee.global_position.x, melee_spot.z - melee.global_position.z).length() >= BowAttack.MELEE_CLEAR)
	melee.queue_free()
	archer.attack_target = null
	await get_tree().physics_frame

	# No oscillation: over two seconds the held position changes at most twice, and the archer keeps a valid position throughout.
	archer.bow._rejected.clear()
	archer.bow._has_spot = false
	archer.bow._replan_wait = 0.0
	var changes: int = 0
	var last: Vector3 = Vector3.INF
	var delta: float = get_physics_process_delta_time()
	for i in 120:
		archer.bow.engage(enemy, null, delta)
		if archer.bow._has_spot and last.distance_to(archer.bow._spot) > 0.5:
			changes += 1
			last = archer.bow._spot
		await get_tree().physics_frame
	expect("oscillation: the firing position changes at most twice in two seconds", changes <= 2)

	# Hold and retry: with no position that sees the target, the AI archer does not walk; it waits a cooldown before looking again.
	barrel.queue_free()
	archer.bow.cancel()   # a shot taken during the walk above is over before the hold is judged
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy.global_position = lane + Vector3(60.0, 0.0, 0.0)
	await get_tree().physics_frame
	archer.bow._rejected.clear()
	archer.bow._has_spot = false
	archer.bow._replan_wait = 0.0
	var before: Vector3 = archer.global_position
	archer.bow.engage(enemy, null, delta)
	if not archer.bow._has_spot:
		expect("hold: with no viable position an AI archer does not advance", archer.global_position.distance_to(before) < 0.05)
		expect("hold: it waits a retry cooldown before looking again", archer.bow._replan_wait >= BowAttack.RETRY_COOLDOWN * 0.99)
	enemy.queue_free()
	await get_tree().physics_frame
