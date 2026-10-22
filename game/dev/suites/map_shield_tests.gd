extends DevSuite
## Map mode shield guard (issue #88, game/map_mode/shield_guard.gd): the warrior raises his shield while closing on a ranged attacker and
## blocks every single projectile from the front. Driven by hand: the hero's own physics is off, the guard is ticked here with a fixed
## velocity, and the rocks are the real RockProjectile.

const DELTA := 1.0 / 60.0

var _mm: MapMode
var _fwd := Vector3.RIGHT   # the lane runs along +x (the harness arena is full of props)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

## Frames with the guard ticking (as Player._physics_process does in map mode).
func _hold(count: int) -> void:
	for i in count:
		player.shield_guard.tick(DELTA)
		await get_tree().physics_frame

func _plain(body: Actor) -> void:
	body.level = 1
	body.armor = 0.0
	body.toughness = 0.0
	body.block_chance = 0.0
	body.ranged_block_chance = 0.0
	body.dodge_chance = 0.0
	body.ranged_dodge_chance = -1.0
	body.physical_resist = 0.0
	body.ranged_resist = 0.0
	body.melee_resist = 0.0

func _foe(variant: String, at: Vector3) -> Enemy:
	var foe: Enemy = _spawn_enemy(at, variant)
	foe.set_physics_process(false)
	foe.aggro_range = 0.0
	foe.alert_delay = 999.0
	foe.max_health = 1.0e7
	foe.health = foe.max_health
	_plain(foe)
	return foe

## A real rock from `thrower` to the hero's chest.
func _rock(thrower: Enemy, damage: float = 10.0) -> RockProjectile:
	var rock := RockProjectile.new()
	rock.source = thrower
	rock.position = thrower.global_position + Vector3(0, thrower.body_height * 0.75, 0)
	rock.destination = player.global_position + Vector3(0, player.body_height * 0.5, 0)
	rock.damage = damage
	game.add_child(rock)
	return rock

## A hit as the rock delivers it, from a direction: `from_angle` degrees round from the hero's front (0 = straight ahead, 180 = behind).
func _shot(thrower: Enemy, from_angle: float, damage_type: int = Combat.DamageType.PHYSICAL, can_miss: bool = false) -> void:
	var facing := Vector3(sin(player.visual.rotation.y), 0.0, cos(player.visual.rotation.y))
	var from_dir: Vector3 = facing.rotated(Vector3.UP, deg_to_rad(from_angle))
	var result: Dictionary = Combat.resolve(thrower, player, 10.0, damage_type, can_miss, 0.5)
	result["projectile"] = true
	result["shot_dir"] = -from_dir
	player.receive(result, player.global_position + from_dir * 2.0)

func _face(dir: Vector3) -> void:
	player.visual.rotation.y = atan2(dir.x, dir.z)

func _closing(speed: float = 3.0) -> void:
	player.velocity = _fwd * speed

func _clear(list: Array) -> void:
	for n in list:
		if is_instance_valid(n):
			n.queue_free()

func _test_map_shield() -> void:
	TownState.persist = false
	TownState.reset()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var hero: Player = player
	var cutter: Player = game.companion
	var cutter_was_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = true
	hero.set_physics_process(false)
	TownState.dev_set_hero_level(30)
	hero.stats.equipment.clear()
	for item in Items.starting_gear():
		hero.stats.equip(item, false)
	var shield: Dictionary = Items.build(ItemDb.get_def("buckler"), 6, Items.Rarity.NORMAL, [])
	hero.stats.equipment[Items.Slot.SHIELD] = shield
	hero.stats.refresh()
	hero.level = 30
	_plain(hero)
	var lane: Vector3 = await _own_lane(24.0, 5.0)
	expect("a clear lane for the rocks", lane != Vector3.ZERO)
	hero.global_position = lane + Vector3(2.0, 0, 0)
	hero.reset_physics_interpolation()
	_face(_fwd)
	hero.skills.busy = false
	hero.attack_target = null
	var front: Vector3 = _fwd * 12.0
	var thrower: Enemy = _foe("rock_thrower", hero.global_position + front)
	await _frames(3)

	# --- Flag off: the walking game has the guard too (issue #112), on the target he is going for ---------------------------------------
	expect("flag off at the start", not MapMode.active)
	var idle_zombie: Enemy = _foe("zombie", hero.global_position - _fwd * 1.0 + Vector3(0, 0, 8.0))
	expect("rock_thrower is a ranged attacker for the guard, a zombie is not", ShieldGuard.is_ranged_attacker(thrower) and not ShieldGuard.is_ranged_attacker(idle_zombie))
	_clear([idle_zombie])
	hero.health = hero.max_health
	_closing()
	_rock(thrower)
	await _hold(70)
	expect("flag off, no target: the shield is not raised (amount %.2f)" % hero.shield_guard.amount, not hero.shield_guard.up and hero.shield_guard.amount == 0.0 and hero.shield_guard.blocked == 0)
	expect("flag off, no target: the rock hits him (health %.1f / %.1f)" % [hero.health, hero.max_health], hero.health < hero.max_health)
	expect("flag off, guard down: Player's filter leaves the result alone", hero._filter_incoming({"projectile": true, "shot_dir": -_fwd, "outcome": Combat.Outcome.HIT, "damage": 5.0})["outcome"] == Combat.Outcome.HIT)
	hero.health = hero.max_health
	hero.attack_target = thrower
	_closing()
	_rock(thrower)
	await _hold(70)
	expect("flag off, closing on the thrower he targets: the shield is raised and the rock blocked (blocked %d, health %.1f / %.1f)" % [hero.shield_guard.blocked, hero.health, hero.max_health],
		hero.shield_guard.blocked >= 1 and hero.health >= hero.max_health)
	hero.attack_target = null
	hero.velocity = Vector3.ZERO
	await _hold(30)
	hero.shield_guard.blocked = 0
	hero.health = hero.max_health

	# --- Map mode on ------------------------------------------------------------------------------------------------------------------
	_mm = MapMode.new()
	game.add_child(_mm)
	_mm.set_physics_process(false)
	_mm.hero = hero
	_mm.companion = cutter
	_mm.state = MapMode.State.FIGHT
	_mm.focus = thrower
	_mm.log.begin_fight("shield test", 0.0)
	await _frames(2)
	expect("flag on", MapMode.active)

	# 1. Raised while closing on a lone rock thrower, up in about 0.15 s.
	_closing()
	var g: ShieldGuard = hero.shield_guard
	await _hold(5)
	expect("0.15 s up: after 5 frames (0.083 s) the pose is part way (%.2f)" % g.amount, g.amount > 0.3 and g.amount < 0.9)
	await _hold(6)
	expect("raised vs a lone rock thrower while closing (amount %.2f)" % g.amount, g.up and g.amount >= 0.99 and hero.model.guard_amount >= 0.99 and g.blocking())

	# 2. Blocks 100% of its rocks from the front: no damage, no knock-back.
	hero.health = hero.max_health
	hero.knock = Vector3.ZERO
	var before: int = g.blocked
	var rocks: int = 20
	for i in rocks:
		_rock(thrower)
		await _hold(4)
	await _hold(70)
	expect("blocks all %d rocks from the front (blocked %d)" % [rocks, g.blocked - before], g.blocked - before == rocks)
	expect("no damage taken from them (health %.1f / %.1f)" % [hero.health, hero.max_health], is_equal_approx(hero.health, hero.max_health))
	expect("not shoved by the blocks (knock %s)" % hero.knock, hero.knock.length() < 0.01)
	expect("the fight log counts them (%d)" % _mm.log._guard_blocks, _mm.log._guard_blocks == rocks)

	# 3. The front arc: 50 degrees off the front is caught, 70 is not (half of 120 is 60).
	before = g.blocked
	hero.health = hero.max_health
	_shot(thrower, 50.0)
	_shot(thrower, -55.0)
	expect("shots 50 and -55 degrees off the front are caught", g.blocked - before == 2 and is_equal_approx(hero.health, hero.max_health))
	_shot(thrower, 70.0)
	expect("a shot 70 degrees off the front is not (hit for %.1f)" % (hero.max_health - hero.health), g.blocked - before == 2 and hero.health < hero.max_health)

	# 4. From behind (and the side): the normal random chance - none at 0, all at 1 (a RANGED hit that can be blocked).
	hero.health = hero.max_health
	before = g.blocked
	_shot(thrower, 180.0)
	expect("a rock from behind hits him as ever (health %.1f)" % hero.health, hero.health < hero.max_health and g.blocked == before)
	hero.health = hero.max_health
	_shot(thrower, 90.0)
	expect("a rock from the side hits him as ever", hero.health < hero.max_health and g.blocked == before)
	hero.health = hero.max_health
	hero.ranged_block_chance = 0.0
	_shot(thrower, 180.0, Combat.DamageType.RANGED, true)
	expect("a ranged shot from behind with 0% block chance hits", hero.health < hero.max_health and g.blocked == before)
	hero.health = hero.max_health
	hero.ranged_block_chance = 1.0
	_shot(thrower, 180.0, Combat.DamageType.RANGED, true)
	expect("a ranged shot from behind with 100% block chance is blocked the normal way (not counted as a guard block)", is_equal_approx(hero.health, hero.max_health) and g.blocked == before)
	hero.ranged_block_chance = 0.0

	# 5. AoE and explosives are never auto-blocked.
	hero.health = hero.max_health
	var aoe: Dictionary = Combat.resolve(thrower, hero, 10.0, Combat.DamageType.FIRE, false, 0.8)
	aoe["projectile"] = true
	aoe["aoe"] = true
	aoe["shot_dir"] = -_fwd
	hero.receive(aoe, hero.global_position + _fwd * 2.0)
	expect("a flagged AoE projectile from the front is not blocked (health %.1f)" % hero.health, hero.health < hero.max_health and g.blocked == before)
	hero.health = hero.max_health
	var bloater: Enemy = _foe("bloater", hero.global_position + _fwd * 2.5)
	(bloater.behavior as BloaterBehavior)._burst(false)
	expect("a Bloater blast is not blocked (health %.1f)" % hero.health, hero.health < hero.max_health and g.blocked == before)
	_clear([bloater])
	for child in get_tree().current_scene.get_children():
		if child is HazardZone:
			child.queue_free()   # the Bloater's gas cloud
	hero.stun_time = 0.0   # the blast knocked him about
	hero.knockdown.reset()
	hero.knock = Vector3.ZERO
	var glob := AcidGlob.new()
	glob.source = thrower
	glob.from_pos = thrower.global_position
	glob.to_pos = hero.global_position
	game.add_child(glob)
	await _hold(1)
	expect("an acid glob landing on him drops the guard at once", not g.up and not g.blocking())
	glob.queue_free()
	await _hold(14)
	expect("and it goes up again when the glob is gone", g.up)
	var tell := Node3D.new()
	tell.add_to_group("aoe_tells")
	tell.set_meta("aoe_radius", 3.0)
	game.add_child(tell)
	tell.global_position = hero.global_position + _fwd * 3.0
	await _hold(1)
	expect("a Volatile ring near him drops the guard at once", not g.up)
	tell.queue_free()
	await _hold(14)

	# 6. Lowered on melee contact (a melee enemy engages him), raised again when it is gone.
	expect("up before the melee enemy comes", g.up)
	var zombie: Enemy = _foe("zombie", hero.global_position + Vector3(0, 0, 1.2))
	zombie.wake()
	await _hold(1)
	expect("a melee enemy on him drops the guard the same frame (up %s)" % g.up, not g.up and not g.blocking())
	hero.health = hero.max_health
	_shot(thrower, 0.0)
	expect("and a rock then hits him (no guard)", hero.health < hero.max_health)
	await _hold(12)
	expect("the pose is back down within about 0.15 s (%.2f)" % g.amount, g.amount < 0.01)
	zombie.queue_free()
	await _hold(14)
	expect("raised again once it is gone", g.up)

	# 7. Lowered on arrival (melee range), and when he stops closing in.
	thrower.global_position = hero.global_position + _fwd * 1.4
	await _hold(1)
	expect("in melee range of the thrower: lowered", not g.up)
	thrower.global_position = hero.global_position + front
	await _hold(14)
	expect("raised once more at range", g.up)
	hero.velocity = Vector3.ZERO
	await _hold(int(ShieldGuard.CLOSING_GRACE * 60.0) - 4)
	expect("standing still: the short grace keeps it up", g.up)
	await _hold(10)
	expect("standing still for more than the grace: lowered", not g.up)
	_closing()
	await _hold(14)
	expect("closing in again: raised", g.up)

	# 8. His target changes to a non-ranged enemy / he uses a power.
	var far_zombie: Enemy = _foe("zombie", hero.global_position + _fwd * 14.0)
	_mm.focus = far_zombie
	await _hold(1)
	expect("target switched to a non-ranged enemy: lowered", not g.up)
	_mm.focus = thrower
	await _hold(14)
	expect("target back on the thrower: raised", g.up)
	hero.skills.busy = true
	await _hold(1)
	expect("busy with a power or swing: lowered", not g.up)
	hero.skills.busy = false
	await _hold(14)
	expect("done: raised", g.up)

	# 9. Without a shield he never raises.
	hero.stats.equipment.erase(Items.Slot.SHIELD)
	hero.stats.refresh()
	await _hold(14)
	expect("no shield: not raised, pose down", not g.up and g.amount < 0.01)
	hero.health = hero.max_health
	_rock(thrower)
	await _hold(70)
	expect("no shield: the rock hits him", hero.health < hero.max_health)
	hero.stats.equipment[Items.Slot.SHIELD] = shield
	hero.stats.refresh()

	# 10. The pose: upper body only (spine and above), legs and hips left to the walk.
	hero.model.loop("walk")
	await _hold(14)
	hero.model._find_guard_bones()
	var names: Array[String] = []
	for pair in hero.model._guard_bones:
		names.append(hero.model._guard_skeleton.get_bone_name(pair[0]))
	print("[mmshield] guard bones: ", names)
	expect("the guard layer covers the spine, arms and head", names.has("Spine") and names.has("LeftArm") and names.has("RightArm") and names.has("Head"))
	expect("and not the hips or legs", not names.has("Hips") and not names.any(func(n: String) -> bool: return n.contains("Leg") or n.contains("Foot")))

	# 11. The fight log row.
	var row: Dictionary = _mm.log.end_fight(1.0)
	expect("the fight row counts the shots the shield caught (%d)" % int(row.get("guard_blocks", 0)), int(row.get("guard_blocks", 0)) >= rocks + 2)
	expect("and prints them", _mm.log.row_line(row).contains("shield blocked %d shots" % int(row["guard_blocks"])) and _mm.log.summary_lines()[-1].contains("shield blocked %d shots" % int(row["guard_blocks"])))

	# Put everything back.
	_clear([thrower, far_zombie])
	_mm.queue_free()
	_mm = null
	await get_tree().process_frame
	hero.model.guard_amount = 0.0
	hero.shield_guard.amount = 0.0
	hero.shield_guard.up = false
	hero.velocity = Vector3.ZERO
	hero.health = hero.max_health
	hero.set_physics_process(true)
	cutter.testing_disabled = cutter_was_disabled
