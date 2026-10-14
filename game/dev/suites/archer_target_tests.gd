extends DevSuite
## Archer targets and sight: which props the bow may break, a sight line blocked by scenery, arrows breaking a nest, and the
## controlled archer's order to shoot a nest from a firing position.

## Frames allowed for the ordered nest (140 hp) to break. The starting Short Bow deals 4.9-8.1 per arrow and a shot takes 0.62 s
## to draw plus 1.05-1.27 s to recover, so an unseeded run needs 18-29 shots, about 1800-3300 frames: the old 2400 sat inside that
## spread. With the RNG seeded the run is fixed (measured: 22 shots, 22 hits, 2335 frames); this bound leaves about 25% margin.
const ORDER_FRAME_BOUND := 3000

func _test_archer_targets() -> void:
	TownState.persist = false
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	archer.testing_disabled = true
	_prepare_archer(archer)
	archer.take_aim_armed = false
	var lane: Vector3 = await _own_lane(20.0, 8.0)
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
	var refused0: int = archer.bow.refusals
	archer.bow.start(enemy)
	expect("sight: the bow refuses a blocked shot (no draw starts)", not archer.skills.busy)
	print("REFUSALS: before=", refused0, " after=", archer.bow.refusals, " refused_by_blocked_start=", archer.bow.refusals - refused0)
	expect("sight: the refusal is counted (refusals increased by the blocked start)", archer.bow.refusals > refused0)
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
	# The player's order goes through the hotkey's own code (Player.order_companions_to_prop); the archer's AI then shoots the nest
	# on its own, through the same engagement as any ordered target, until the destructible breaks.
	# Negative: an archer nobody ordered never attacks a nest, however clear the shot. The party AI runs for 600 frames here.
	var idle_nest: Destructible = arena.place_prop("crypt/nest", lane + Vector3(11.0, 0.0, 5.0), 0.0, 1.9) as Destructible
	await get_tree().physics_frame
	await get_tree().physics_frame
	archer.testing_disabled = false
	archer.attack_prop = null
	var idle_hp: float = idle_nest.hp
	var idle_shots: int = archer.bow.shots
	for i in 600:
		await get_tree().physics_frame
	expect("negative: an unordered archer leaves a clear-sight nest untouched over 600 frames (hp unchanged, not broken)",
		is_equal_approx(idle_nest.hp, idle_hp) and not idle_nest.broken)
	expect("negative: an unordered archer begins no shot at the nest (shot count unchanged)", archer.bow.shots == idle_shots)
	idle_nest.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	archer.testing_disabled = false   # this one is the party AI's own shot: it must run
	# Damage per arrow and the recovery after each shot are random draws on the global RNG, which earlier suites leave in any
	# state (enemy_tests calls randomize()), and an earlier suite may leave the archer a different bow. Seed the RNG and give him
	# the starting Short Bow, so the break frame is the same in any run order.
	seed(4242)
	archer.stats.equipment[Items.Slot.WEAPON] = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow")
	archer.stats.refresh()
	var broke: Array[Destructible] = []
	order_nest.destroyed.connect(func(prop: Destructible) -> void: broke.append(prop))
	var ordered: Destructible = player.order_companions_to_prop(order_nest.global_position)
	expect("ordered: the hotkey's prop order marks the nest for the archer", ordered == order_nest and archer.attack_prop == order_nest)
	var shots0: int = archer.bow.shots
	var nest_hp: float = order_nest.hp
	var arrow_hits := 0
	var order_frames := 0
	for i in ORDER_FRAME_BOUND:
		await get_tree().physics_frame
		order_frames += 1
		if order_nest.hp < nest_hp:
			arrow_hits += 1
			nest_hp = order_nest.hp
		if not broke.is_empty():
			break
	var order_shots: int = archer.bow.shots - shots0
	print("NEST ORDER: destroyed_signal=", not broke.is_empty(), " frames=", order_frames, " bound=", ORDER_FRAME_BOUND,
		" shots=", order_shots, " arrow_hits=", arrow_hits, " damage=", archer.stats.ranged_range(), " attack_speed=", archer.stats.attack_speed())
	expect("ordered: every arrow loosed at the nest strikes it (no misses)", arrow_hits == order_shots and arrow_hits > 0)
	expect("ordered: the archer's own shots break the ordered nest (destroyed signal, within %d frames)" % ORDER_FRAME_BOUND,
		not broke.is_empty() and broke[0].broken)
	archer.attack_prop = null
	archer.testing_disabled = true
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
	archer.testing_disabled = true
	_prepare_archer(archer)
	var lane: Vector3 = await _own_lane(24.0, 10.0)
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
	print("RANGE PREFERENCE: measured_reach=", snappedf(reach, 0.01), " preferred=", BowAttack.SPOT_RANGE)
	expect("positioning: range preference - the position is within 2 m of the preferred 12 m", picked and absf(reach - BowAttack.SPOT_RANGE) <= 2.0)
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
	var melee_distance: float = Vector2(melee_spot.x - melee.global_position.x, melee_spot.z - melee.global_position.z).length()
	print("MELEE SEPARATION: picked=", melee_pick, " spot_to_melee=", snappedf(melee_distance, 0.01), " required=", BowAttack.MELEE_CLEAR)
	expect("positioning: melee separation - a firing position is found and is at least MELEE_CLEAR from the aggro enemy",
		melee_pick and melee_distance >= BowAttack.MELEE_CLEAR)
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
	var queries0: int = Nav.requests_total
	for i in 120:
		archer.bow.engage(enemy, null, delta)
		if archer.bow._has_spot and last.distance_to(archer.bow._spot) > 0.5:
			changes += 1
			last = archer.bow._spot
		await get_tree().physics_frame
	var requests: int = Nav.requests_total - queries0
	print("OSCILLATION: spot_changes=", changes, " nav_path_requests=", requests, " spot_reach=", snappedf(reach, 0.01))
	expect("oscillation: a firing position is chosen (it exists at the end of the window)", archer.bow._has_spot)
	expect("oscillation: the firing position changes at most twice in two seconds", changes <= 2)
	expect("navigation: the walk to the firing position makes path requests (bounded, non-zero)", requests >= 1 and requests <= 20)

	# Hold and retry is proven unconditionally, by counter, in archer_hold_tests.gd (the walled scenario).
	barrel.queue_free()
	archer.bow.cancel()
	enemy.queue_free()
	await get_tree().physics_frame
