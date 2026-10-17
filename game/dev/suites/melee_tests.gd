extends DevSuite
## Self-test: melee feel (auto-attack, impacts, sword sounds, roll and dodge, fists, weapon styles, recoil, brutal attacks).

## Direct-hit checks miss the delayed damage from a shoved enemy or flying corpse.
func _test_basic_single_target_physics() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().physics_frame
	var origin: Vector3 = _free_lane_start(12.0, 4.0)
	player.set_physics_process(false)
	player.global_position = origin
	player.reset_physics_interpolation()
	if DisplayServer.get_name() != "headless":
		rig.set_process(false)
		rig.camera.global_position = origin + Vector3(4.0, 4.0, 6.0)
		rig.camera.look_at(origin + Vector3(1.8, 0.8, 0.0))
	for lethal in [false, true]:
		player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Greatsword" if not lethal else "Longsword"), false)
		var target: Enemy = _spawn_enemy(origin + Vector3(1.6, 0, 0))
		var bystander: Enemy = _spawn_enemy(origin + Vector3(2.5, 0, 0))
		for e in [target, bystander]:
			e.alert_delay = 999.0
			e.aggro_range = 0.0
			e.max_health = 5000.0
			e.health = 5000.0
			e.dodge_chance = 0.0
			e.block_chance = 0.0
		target.health = 1.0 if lethal else 5000.0
		await get_tree().physics_frame
		player.skills.busy_skill = "basic"
		player.skills.busy_target = target
		player.skills.busy_aim = target.global_position
		player.forced_crits = 0 if lethal else 1
		var old_crit: float = player.crit_chance
		player.crit_chance = 0.0
		player.skills._apply_skill(SkillDb.all()["basic"])
		player.crit_chance = old_crit
		await get_tree().create_timer(1.2).timeout
		print("  basic physics lethal=", lethal, " target health=", target.health, " bystander health=", bystander.health, " result=", bystander.last_result)
		expect("basic %s leaves the adjacent enemy unharmed after physics" % ("kill/corpse" if lethal else "critical knockback"), bystander.health == 5000.0)
		expect("fixture actually lands the requested basic blow", target.dead if lethal else target.health < 5000.0)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_basic_single_%s.png" % ("corpse" if lethal else "critical"))
		for e in [target, bystander]:
			e.queue_free()
		await get_tree().physics_frame
	player.set_physics_process(true)
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Longsword"), false)

## A held click repeats basic attacks, releasing it stops them, and cancellation is obeyed.
func _test_auto_attack() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().physics_frame
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	var dummy: Enemy = _spawn_enemy(Vector3(3.5, 0, 0))
	dummy.aggro_range = 0.0
	dummy.max_health = 5000.0
	dummy.health = 5000.0
	await get_tree().physics_frame
	# 1. Hold the click on the target: approach and repeat; letting go ends the engagement (no auto-attack).
	player.attack_target = dummy
	player.click_mode = 1
	Input.action_press("click")
	var swings: int = 0
	var was_busy: bool = false
	var facing_turns: float = 0.0
	var elapsed: float = 0.0
	while elapsed < 4.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if player.skills.busy and not was_busy and player.skills.busy_skill == "basic":
			swings += 1
		was_busy = player.skills.busy
	var retained_order: bool = player.attack_target == dummy
	Input.action_release("click")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var released_clears: bool = player.attack_target == null and player.click_mode == 0
	player.attack_target = null
	player.skills.cancel_action()
	player.movement.has_goal = false
	var idle_after: bool = not player.skills.busy and player.attack_target == null
	# 2. Standing idle with an enemy nearby must not turn the hero or start anything.
	var yaw_before: float = player.visual.rotation.y
	var busy_during_idle: bool = false
	for i in 90:
		await get_tree().physics_frame
		busy_during_idle = busy_during_idle or player.skills.busy
	var yaw_drift: float = absf(angle_difference(yaw_before, player.visual.rotation.y))
	# 3. A skill clears the attack order so the hero does not resume swinging when it ends.
	player.attack_target = dummy
	player.skills.start_skill("fireball", null, Vector3(0, 0, -6))
	var cleared_by_skill: bool = player.attack_target == null
	await get_tree().create_timer(2.0).timeout
	var swings_after_skill: bool = player.skills.busy and player.skills.busy_skill == "basic"
	expect("holding the click on a target repeats basic attacks", swings >= 2 and retained_order)
	expect("letting go of the click ends the engagement (no auto-attack)", released_clears)
	expect("explicit cancellation clears engagement", idle_after)
	expect("hero does not swing or turn with no input", not busy_during_idle and absf(yaw_drift) < 0.02)
	expect("a skill clears the attack order", cleared_by_skill)
	expect("no swinging resumes after a skill", not swings_after_skill)
	print("  auto-attack: one click -> swings=", swings, " (expected repeated), idle after cancellation=", idle_after, ", idle with enemy near: busy=", busy_during_idle,
		" turned ", snappedf(rad_to_deg(yaw_drift), 0.1), " deg, skill clears attack order=", cleared_by_skill, ", resumed swinging after skill=", swings_after_skill)
	dummy.queue_free()
	await get_tree().process_frame

## A plain ground click abandons an unlanded swing or its recovery and starts locomotion immediately.
func _test_move_priority() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().physics_frame
	var was_pad: bool = Gamepad.active
	var start: Vector3 = _free_lane_start(14.0, 6.0)
	player.global_position = start
	player.reset_physics_interpolation()
	player.hitpause = 0.0
	player.stun_time = 0.0
	player.movement.has_goal = false
	Gamepad.active = true   # deterministic cursor_override targeting in the headless self-test
	var destination: Vector3 = start + Vector3(0.0, 0.0, 2.2)
	player.cursor_override = destination
	var target: Enemy = _spawn_enemy(start + Vector3(4.5, 0.0, 0.0))
	target.aggro_range = 0.0
	target.max_health = 5000.0
	target.health = target.max_health
	target.dodge_chance = 0.0
	target.block_chance = 0.0
	await get_tree().physics_frame
	# Before the melee hit frame: the click clears engagement and all swing state.
	player.attack_target = target
	player.click_mode = 1
	player.skills.start_skill("basic", target)
	var health_before: float = target.health
	await _click_ground(destination)
	var before_hit_cancelled: bool = not player.skills.busy and player.skills.busy_skill == "" \
		and player.skills.busy_def.is_empty() and player.skills.busy_target == null and not player.skills.busy_hit_done \
		and is_zero_approx(player.skills.busy_t) and player.attack_target == null \
		and player.skills.queued_skill == "" and player.skills.queued_target == null
	expect("ground click cancels a melee wind-up before damage and clears the old target/queue", before_hit_cancelled and target.health == health_before)
	expect("ground click transitions directly into movement animation", ["walk", "run"].has(player.model.current)
		and player.velocity.length() > 0.5 and player.movement.has_goal)
	expect("cancelled melee trail and pose locks are cleared", not player._trail.active and is_zero_approx(player.visual.rotation.x))
	for i in 8:
		await get_tree().physics_frame
	expect("cancelled auto-attack does not reacquire the previous target", player.attack_target == null
		and not player.skills.busy)

	# A legitimately applied hit survives cancellation during the visible recovery window.
	player.set_physics_process(false)
	player.global_position = start
	player.reset_physics_interpolation()
	player.movement.has_goal = false
	target.global_position = start + Vector3(1.5, 0.0, 0.0)
	player.attack_target = target
	player.skills.start_skill("basic", target)
	var hit_at: float = player.skills.busy_time * SkillController.hit_fraction(player.skills.busy_def)
	player.skills.tick_busy(hit_at + 0.01)
	var health_after_hit: float = target.health
	player.hitpause = 0.0
	player.set_physics_process(true)
	player.cursor_override = start + Vector3(0.0, 0.0, -2.2)
	await _click_ground(player.cursor_override)
	expect("movement cancels attack recovery without undoing damage already dealt", health_after_hit < health_before
		and target.health == health_after_hit and not player.skills.busy and ["walk", "run"].has(player.model.current))
	expect("recovery cancellation clears every action lock before locomotion", player.skills.busy_skill == "" and player.skills.busy_def.is_empty()
		and player.skills.busy_target == null and not player.skills.busy_hit_done and not player._trail.active)

	# Repeated ordinary movement clicks replace the current destination.
	var second_destination: Vector3 = start + Vector3(0.0, 0.0, -3.0)
	player.cursor_override = second_destination
	await _click_ground(second_destination)
	expect("repeated movement clicks update the navigation destination", player.movement.has_goal
		and player.movement.goal.distance_to(Nav.snap(player, second_destination)) < 0.05)

	# Stun and knockdown retain the order but keep the body physically locked until they end.
	player.movement.has_goal = false
	player.knock = Vector3.ZERO
	player.stun_time = 0.35
	player.attack_target = target
	var stun_position: Vector3 = player.global_position
	await _click_ground(destination)
	expect("movement click during stun clears combat and records its destination without moving", not player.skills.busy
		and player.attack_target == null and player.movement.has_goal and player.global_position.distance_to(stun_position) < 0.01)
	player.stun_time = 0.0
	await get_tree().physics_frame
	expect("the stored movement order starts as soon as stun clears", ["walk", "run"].has(player.model.current)
		and player.velocity.length() > 0.5)
	player.movement.has_goal = false
	player.knockdown.begin()
	player.attack_target = target
	player.knock = Vector3.ZERO
	var down_position: Vector3 = player.global_position
	await _click_ground(second_destination)
	expect("movement click during knockdown records an order without breaking the fall", player.knockdown.active()
		and player.attack_target == null and player.movement.has_goal and player.global_position.distance_to(down_position) < 0.01)
	player.knockdown.cancel()
	player.movement.has_goal = false

	# The explicit exceptions remain in force while controls are locked, rolling, or held in stand-still mode.
	player.attack_target = target
	player.skills.start_skill("basic", target)
	player.input_locked = true
	await _click_ground(destination)
	expect("control-switch input lock does not consume or cancel the attack", player.skills.busy and player.attack_target == target
		and not player.movement.has_goal)
	player.input_locked = false
	player.skills.cancel_action()
	player.attack_target = target
	player.skills.start_skill("basic", target)
	player.stats.cooldowns["dodge"] = 0.0
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(destination)
	player.cursor_override = destination
	await _click_ground(destination)
	expect("movement clicks do not take over a dodge roll", player.movement.rolling and not player.skills.busy
		and not player.movement.has_goal)
	player.movement.rolling = false
	player.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ENEMY
	player.attack_target = target
	player.skills.start_skill("basic", target)
	Input.action_press("stand_still")
	await _click_ground(destination)
	Input.action_release("stand_still")
	expect("Ctrl plus ground click keeps the swing going and does not move (releasing the click ends the engagement)", player.skills.busy and not player.movement.has_goal)
	player.skills.cancel_action()
	player.attack_target = null

	# A charged spell is canceled before release, while a spell already thrown remains scene-owned.
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns["fireball"] = 0.0
	var aim: Vector3 = start + Vector3(0.0, 0.0, -14.0)
	var projectile_count: int = _scene_projectiles().size()
	player.skills.start_skill("fireball", null, aim)
	await _click_ground(destination)
	expect("movement cancels an unreleased Fireball and refunds its charge", not player.skills.busy
		and is_equal_approx(player.stats.mana, player.stats.max_mana) and float(player.stats.cooldowns.get("fireball", 0.0)) == 0.0
		and _scene_projectiles().size() == projectile_count)
	player.movement.has_goal = false
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns["fireball"] = 0.0
	player.set_physics_process(false)
	player.skills.start_skill("fireball", null, aim)
	for i in 120:
		if player.skills.busy_hit_done:
			break
		player.skills.tick_busy(1.0 / 60.0)
	var released_fireball: Projectile
	for node in _scene_projectiles():
		if node is Projectile:
			released_fireball = node as Projectile
	player.set_physics_process(true)
	await _click_ground(second_destination)
	expect("movement cancels Fireball recovery but the released projectile continues", released_fireball != null
		and is_instance_valid(released_fireball) and not player.skills.busy)
	if is_instance_valid(released_fireball):
		released_fireball.queue_free()

	# The bow follows the same release boundary: no arrow before release, launched arrows persist.
	player.set_physics_process(false)
	player.global_position = start
	player.reset_physics_interpolation()
	var worn_weapon: Dictionary = player.stats.equipment[Items.Slot.WEAPON].duplicate(true)
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow"), false)
	var bow_target: Enemy = _spawn_enemy(start + Vector3(0.0, 0.0, -8.0))
	bow_target.aggro_range = 0.0
	bow_target.max_health = 5000.0
	bow_target.health = bow_target.max_health
	await get_tree().physics_frame
	var arrow_count: int = _scene_projectiles().filter(func(node: Node) -> bool: return node is CompanionArrow).size()
	player.skills.start_skill("basic", bow_target)
	player.set_physics_process(true)
	await _click_ground(destination)
	expect("movement cancels an unreleased bow draw without launching an arrow", player.bow != null and not player.skills.busy
		and _scene_projectiles().filter(func(node: Node) -> bool: return node is CompanionArrow).size() == arrow_count)
	player.set_physics_process(false)
	player.global_position = start
	player.reset_physics_interpolation()
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow"), false)
	player.skills.start_skill("basic", bow_target)
	for i in 120:
		if player.skills.busy_hit_done:
			break
		player.skills.tick_busy(1.0 / 60.0)
	var released_arrow: CompanionArrow
	for node in _scene_projectiles():
		if node is CompanionArrow:
			released_arrow = node as CompanionArrow
	player.set_physics_process(true)
	await _click_ground(second_destination)
	expect("movement cancels bow recovery but the released arrow remains in flight", released_arrow != null
		and is_instance_valid(released_arrow) and not player.skills.busy)
	if is_instance_valid(released_arrow):
		released_arrow.queue_free()
	player.set_physics_process(false)
	player.stats.wear(Items.Slot.WEAPON, worn_weapon)
	player.set_physics_process(true)
	bow_target.queue_free()

	player.skills.cancel_action()
	player.attack_target = null
	player.movement.has_goal = false
	player.cursor_override = Vector3.INF
	Gamepad.active = was_pad
	target.queue_free()
	await get_tree().process_frame

func _click_ground(point: Vector3) -> void:
	player.cursor_override = point
	Input.action_press("click")
	await get_tree().physics_frame
	Input.action_release("click")
	await get_tree().physics_frame

func _scene_projectiles() -> Array[Node]:
	var out: Array[Node] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return out
	for node in scene.get_children():
		if node is Projectile or node is CompanionArrow:
			out.append(node)
	return out

## Thrown bodies and wall bounces are presentation, never an extra attack.
func _test_impact() -> void:
	player.global_position = Vector3(-25, 0, -25)
	player.reset_physics_interpolation()
	# Burning body bowled into a bystander.
	var bystander: Enemy = _spawn_enemy(Vector3(32, 0, -13))
	var burner: Enemy = _spawn_enemy(Vector3(32, 0, -19))
	for e in [bystander, burner]:
		e.aggro_range = 0.0
		e.max_health = 500.0
		e.health = 500.0
	await get_tree().process_frame
	burner.apply_burn(5.0, 6.0)
	burner.apply_slow(0.4, 5.0)
	burner.ragdoll_launch(Vector3(0, 0, 12), 6.5, Vector3(4, 0, 0))   # same throw as the Skewer kick
	await get_tree().create_timer(1.0).timeout
	expect("a thrown body cannot damage, spread statuses or knock down a bystander", not bystander.is_burning() and bystander.slow_time == 0.0
		and bystander.health == 500.0 and not bystander.is_ragdolled() and bystander.stun_time == 0.0)
	print("  bowled: bystander burning=", bystander.is_burning(), " slowed=", bystander.slow_time > 0.0, " health=", snappedf(bystander.health, 0.1), "/500")
	bystander.queue_free()
	burner.queue_free()
	await get_tree().process_frame

	# Thrown into a wall.
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 3, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = Vector3(32, 1.5, -10)
	var flier: Enemy = _spawn_enemy(Vector3(32, 0, -16))
	flier.aggro_range = 0.0
	flier.max_health = 500.0
	flier.health = 500.0
	await get_tree().process_frame
	flier.ragdoll_launch(Vector3(0, 0, 13), 2.0, Vector3(5, 0, 0))
	await get_tree().create_timer(1.0).timeout
	expect("a ragdoll wall bounce adds no damage or stun", flier.health == 500.0 and flier.stun_time == 0.0)
	print("  wall slam: health=", snappedf(flier.health, 0.1), "/500 stun left=", snappedf(flier.stun_time, 0.1))
	for e in [bystander, burner, flier]:
		if is_instance_valid(e):
			e.queue_free()
	wall.queue_free()
	await get_tree().process_frame

## Roll: immune for the whole roll, shoves non-boss enemies sideways and interrupts them; bosses stay put.
func _test_roll_shove() -> void:
	# The old (20,20) fixture put BOTH zombies inside arena scenery. Recovery
	# moved them before the roll and could pin the attacker during its shove.
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().physics_frame
	var old_rate := Engine.physics_ticks_per_second
	for rate in [30, 60, 120]:
		Engine.physics_ticks_per_second = rate
		await _roll_shove_case(rate)
	Engine.physics_ticks_per_second = old_rate

func _roll_shove_case(rate: int) -> void:
	var origin := _clear_lane(9.0, 7.0)
	expect("roll fixture has a world-clear corridor", origin != Vector3.ZERO)
	var review := OS.get_cmdline_user_args().has("--rollreview") and DisplayServer.get_name() != "headless" and rate == 60
	if review:
		rig.set_process(false)
		rig.camera.global_position = origin + Vector3(4, 5, 8)
		rig.camera.look_at(origin + Vector3(2, 0, 0))
	player.skills.cancel_action()
	player.skills.clear_queue()
	player.attack_target = null
	player.movement.has_goal = false
	player.knock = Vector3.ZERO
	player.stats.cooldowns.erase("dodge")
	player.global_position = origin
	player.reset_physics_interpolation()
	await get_tree().physics_frame
	# In shove range, but outside physical contact: immunity is not immunity to
	# ordinary collision recovery. Do not teleport an oversized body into others.
	var boss: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, 2.0), "brute")
	boss.is_boss = true
	boss.global_position.z = player.global_position.z + player.body_radius + boss.body_radius + 0.35
	boss.aggro_range = 0.0
	boss.idle_mode = ""
	await get_tree().physics_frame
	await get_tree().process_frame
	var boss_start := boss.global_position
	player.movement.roll_dir = Vector3.RIGHT
	player.movement.shoved.clear()
	player.movement.shove_enemies(1.0 / rate)
	expect("boss in shove range ignores displacement and interruption", boss.global_position == boss_start and boss.stun_time == 0.0 and not player.movement.shoved.has(boss.get_instance_id()))
	var near: Enemy = _spawn_enemy(player.global_position + Vector3(1.4, 0, 0.1))
	var attacker: Enemy = _spawn_enemy(player.global_position + Vector3(2.4, 0, -0.1))
	for e in [near, attacker]:
		e.aggro_range = 0.0
		e.idle_mode = ""
	await get_tree().physics_frame
	await get_tree().process_frame
	expect("roll fixture bodies do not recover from initial overlaps", near.global_position.distance_to(origin + Vector3(1.4, 0, 0.1)) < 0.01 and attacker.global_position.distance_to(origin + Vector3(2.4, 0, -0.1)) < 0.01)
	# Put one zombie mid-attack so we can see it get interrupted.
	attacker._attacking = true
	attacker.model.manual("attack")
	if review: await _roll_review_capture("before")
	var near_start: Vector3 = near.global_position
	var attacker_start: Vector3 = attacker.global_position
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(player.global_position + Vector3(8, 0, 0))
	expect("roll starts immediately and only collides with world", player.movement.rolling and player.collision_mask == Actor.LAYER_WORLD)
	var immune_late: bool = false
	var interrupted_during_roll := false
	for i in ceili(rate * (PlayerMovement.ROLL_TIME + 0.4)):
		await get_tree().physics_frame
		if review and i == 12: await _roll_review_capture("during")
		interrupted_during_roll = interrupted_during_roll or (player.movement.rolling and not attacker._attacking and attacker.stun_time > 0.0)
		if player.movement.rolling and player.movement.roll_t > ROLL_CHECK_TIME and player.invulnerable_time > 0.0:
			immune_late = true
	await get_tree().process_frame
	var lateral_near: float = absf(near.global_position.z - near_start.z)
	var lateral_attacker: float = absf(attacker.global_position.z - attacker_start.z)
	var boss_moved: float = boss.global_position.distance_to(boss_start)
	expect("roll shoves non-bosses aside", lateral_near > 0.3 and lateral_attacker > 0.3)
	expect("roll actually contacts both eligible enemies", player.movement.shoved.has(near.get_instance_id()) and player.movement.shoved.has(attacker.get_instance_id()))
	expect("roll interrupts an attacker during the roll", interrupted_during_roll)
	expect("roll leaves boss stationary and unstunned", boss_moved < 0.01 and boss.stun_time == 0.0)
	expect("roll restores normal collision", not player.movement.rolling and player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY))
	expect("roll is immune late in the roll", immune_late)
	if review:
		await _roll_review_capture("after")
		rig.set_process(true)
	print("  roll shove at ", rate, " Hz: near moved sideways ", lateral_near, " m, attacker ", lateral_attacker,
		" m (interrupted=", not attacker._attacking, "), boss displaced ", snappedf(boss_moved, 0.1), " m, immune late in roll=", immune_late)
	for e in [near, attacker, boss]:
		e.queue_free()
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	await get_tree().process_frame

func _roll_review_capture(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join("curse_roll_" + stage + ".png")
	expect("roll review screenshot saved", get_viewport().get_texture().get_image().save_png(path) == OK)
	print("ROLL_REVIEW ", path)

const ROLL_CHECK_TIME := 0.4

func _test_sword_sound() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in game.get_children():
		if node is Projectile:   # a fireball left flying by an earlier check would land mid-test and play its impact sound
			node.queue_free()
	await get_tree().process_frame
	var was_enabled: bool = Sfx.enabled
	Sfx.enabled = true
	expect("both sword sound files are in the project", ResourceLoader.exists("res://assets/audio/sword_hit.ogg") and ResourceLoader.exists("res://assets/audio/sword_hit_2.wav"))
	# The sounds are randomised, never the same recording twice in a row, and both get used.
	var used: Dictionary = {}
	var repeated: bool = false
	var previous: String = ""
	for i in 40:
		Sfx._last_played.clear()
		Sfx.sample(self, "sword_hit")
		used[Sfx.last_name] = true
		repeated = repeated or Sfx.last_name == previous
		previous = Sfx.last_name
	expect("the sword hit sound is randomised between both recordings", used.size() == 2 and not repeated)
	Sfx._last_played.clear()
	var enemy: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -3))
	enemy.aggro_range = 0.0
	enemy.max_health = 5000.0
	enemy.health = 5000.0
	await get_tree().process_frame
	Sfx.played_log.clear()
	var hit: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
	hit["skill_id"] = "basic"
	enemy.receive(hit, player.global_position)
	expect("a sword hit plays the sound", _logged("sword_hit") == 1 and _logged("sword_miss") == 0)
	await get_tree().create_timer(0.1).timeout
	var miss: Dictionary = {"outcome": Combat.Outcome.MISS, "damage": 0.0, "source": player, "skill_id": "basic"}
	enemy.receive(miss, player.global_position)
	expect("a missed swing plays a swing sound, not the hit sound", _logged("sword_hit") == 1 and _logged("sword_miss") == 1)
	await get_tree().create_timer(0.1).timeout
	var block: Dictionary = {"outcome": Combat.Outcome.BLOCK, "damage": 0.0, "source": player, "skill_id": "basic", "weight": 1.0}
	enemy.receive(block, player.global_position)
	expect("a block plays neither", Sfx.played_log.size() == 2)
	await get_tree().create_timer(0.1).timeout
	for other in ["flame_nexus", "detonation", "fireball"]:
		var odd: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
		odd["skill_id"] = other
		enemy.receive(odd, player.global_position)
		await get_tree().create_timer(0.1).timeout
	expect("a fire power or a fireball is not the sword", Sfx.played_log.size() == 2)
	var secondary: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
	secondary["skill_id"] = "basic"
	secondary["secondary"] = true
	enemy.receive(secondary, player.global_position)
	expect("splash damage is not a sword hit either", Sfx.played_log.size() == 2)
	await get_tree().create_timer(0.1).timeout
	# The four swing recordings are all used, never the same twice running.
	Sfx.played_log.clear()
	var repeats: bool = false
	for i in 60:
		Sfx._last_played.clear()
		Sfx.sample(self, "sword_miss")
		if Sfx.played_log.size() >= 2 and Sfx.played_log[-1] == Sfx.played_log[-2]:
			repeats = true
	var distinct: Dictionary = {}
	for name in Sfx.played_log:
		distinct[name] = true
	expect("all four swing sounds are used and none repeats back to back", distinct.size() == 4 and not repeats)
	Sfx.enabled = was_enabled
	enemy.queue_free()
	await get_tree().process_frame

## Any time the sword swings and finds nothing, a swing sound plays: a swing at a target that is out of reach.
func _test_sword_miss_in_air() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var was_enabled: bool = Sfx.enabled
	Sfx.enabled = true
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	# A swing at an enemy that is out of reach by the time the blow lands.
	var far: Enemy = _spawn_enemy(Vector3(0, 0, -9))
	far.aggro_range = 0.0
	await get_tree().process_frame
	Sfx._last_played.clear()
	Sfx.played_log.clear()
	player.skills.start_skill("basic", far, far.global_position)
	var t: float = 0.0
	while player.skills.busy and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a swing that cannot reach its target makes the swing sound", _logged("sword_miss") == 1 and _logged("sword_hit") == 0)
	far.queue_free()
	await get_tree().process_frame
	# And when it does connect there is no swing sound.
	var near: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -1.6))
	near.aggro_range = 0.0
	near.max_health = 3000.0
	near.health = 3000.0
	await get_tree().process_frame
	for attempt in 8:   # a swing can also be dodged (that is a miss): swing until one connects
		player.stats.cooldowns.clear()
		Sfx._last_played.clear()
		Sfx.played_log.clear()
		player.skills.start_skill("basic", near, near.global_position)
		t = 0.0
		while player.skills.busy and t < 3.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		if _logged("sword_hit") >= 1 and _logged("sword_miss") == 0:   # (a swing that also whiffed on someone else is not the case under test)
			break
		await get_tree().create_timer(0.1).timeout
	expect("a swing that connects makes the hit sound, not the swing sound", _logged("sword_hit") >= 1 and _logged("sword_miss") == 0)
	near.queue_free()
	Sfx.enabled = was_enabled
	await get_tree().process_frame

## A dodge always wins over an auto attack: it is dropped mid-swing, and a still-held attack button does not start another one afterwards.
func _test_dodge_cancels_attack() -> void:
	player.global_position = _free_lane_start(8.0, 6.0)
	player.reset_physics_interpolation()
	player.stats.cooldowns.clear()
	player.stats.stamina = player.stats.max_stamina
	var foe: Enemy = _spawn_enemy(player.global_position + Vector3(1.4, 0, 0))
	foe.aggro_range = 0.0
	foe.max_health = 900.0
	foe.health = 900.0
	await get_tree().process_frame
	player.attack_target = foe
	player.skills.start_skill("basic", foe)
	await get_tree().create_timer(0.1).timeout   # still gathering the swing: the blade has not come down
	expect("the swing is under way and has not landed", player.skills.busy and not player.skills.busy_hit_done)
	Input.action_press("alt_skill")   # the attack button is still held
	player.movement.try_roll(player.global_position + Vector3(-5, 0, 0))
	expect("a dodge pressed in the middle of an auto attack goes through", player.movement.rolling)
	expect("and the attack is dropped", not player.skills.busy and player.attack_target == null and player.skills.queued_skill == "")
	await get_tree().create_timer(1.0).timeout
	var swung: bool = player.skills.busy
	Input.action_release("alt_skill")
	expect("the held attack button does not start another swing after the roll", not swung)
	foe.queue_free()

func _test_brutal_attack() -> void:
	TownState.passive_ranks["critical_strike"] = 1   # (DS2: Brutal Attack opens with Critical Strike 1)
	GameSettings.reset_hotbar()
	expect("the default loadout contains the two party powers and the basic attack",
		GameSettings.hotbar_slots == ["brutal_attack", "take_aim", "", "", "", ""] and GameSettings.hotbar_alt == "basic")
	var skills: SkillController = player.skills
	skills.cancel_action()
	player.stats.brutal_reload_remaining = 0.0
	var priority_target: Enemy = _spawn_enemy(player.global_position + Vector3(0.0, 0.0, -1.7))
	priority_target.aggro_range = 0.0
	player.attack_target = priority_target
	skills.start_skill("basic", priority_target)
	await get_tree().create_timer(0.08).timeout
	skills.activate_brutal_attack()
	expect("Brutal Attack interrupts the ordinary swing and begins its powered blow immediately",
		skills.brutal_armed and skills._brutal_aura != null and skills.busy and skills.busy_skill == "basic"
		and bool(skills.busy_def.get("brutal_animation", false)) and skills.busy_t < 0.08)
	var aura := skills._brutal_aura as BrutalAttackFx
	expect("Brutal Attack wisps track the animated skeleton instead of fixed body offsets", aura != null and aura.emitters.size() >= 12)
	var bone: int = aura.skeleton.find_bone("RightForeArm")
	player.model.manual("power")
	player.model.scrub(0.78)
	var before_wisp: Vector3 = (aura.emitters[bone] as CPUParticles3D).global_position
	player.model.scrub(1.23)
	var after_wisp: Vector3 = (aura.emitters[bone] as CPUParticles3D).global_position
	var after_bone: Vector3 = aura.skeleton.to_global(aura.skeleton.get_bone_global_pose(bone).origin)
	expect("the arm's steam moves with the attack pose and stays just outside the bone", before_wisp.distance_to(after_wisp) > 0.05
		and after_wisp.distance_to(after_bone) < 0.07)
	expect("arming keeps the red aura without an inward body-particle burst or attack delay", aura.get_node_or_null("ChargeGather") == null and aura.get_node_or_null("CrimsonGathering") != null and skills.busy_t < 0.08)
	expect("Brutal Attack uses the approved crimson palette while preserving DS2 rank scaling", BrutalAttackFx.rank_color(1) == Color("d61036")
		and BrutalAttackFx.rank_color(2) == Color("ef2546") and BrutalAttackFx.rank_color(3) == Color("ff5367")
		and is_equal_approx(BrutalAttackFx.rank_scale(1), 1.0) and is_equal_approx(BrutalAttackFx.rank_scale(3), 1.8))
	var infusion := aura.get_node("CrimsonGathering") as BrutalCrimsonFx
	skills.tick_busy(0.14)
	expect("visible particle infusion is still underway during the draw-back", infusion.infusion_fraction() > 0.0 and infusion.infusion_fraction() < 1.0 and not skills.busy_hit_done)
	expect("infusion uses most of the actual pre-contact animation", is_equal_approx(infusion.infusion_duration(), skills.busy_time * SkillController.hit_fraction(skills.busy_def) * 0.9))
	var destination := infusion.to_local(player.model.weapon_base.global_position.lerp(player.model.weapon_tip.global_position, 0.35))
	expect("the red particles travel from the body into the weapon itself", infusion.mote_position(0, 0).distance_to(destination) > 0.2 and infusion.mote_position(0, 1).distance_to(destination) < 0.001)
	skills.cancel_action()
	expect("cancelling the windup restores the armed body energy", skills.brutal_armed and infusion.infusion_fraction() == 0.0)
	priority_target.queue_free()
	player.attack_target = null
	skills.combo_step = 2
	var brutal_animation: Dictionary = skills._next_basic()
	expect("an armed Brutal Attack replaces the basic combo with its own short heavy windup",
		bool(brutal_animation.get("brutal_animation", false)) and brutal_animation["clip"] == "power"
		and float(brutal_animation["time"]) > 1.0 and float(brutal_animation["weight"]) > 2.0 and skills.combo_step == 0)
	# A complete basic swing into empty space must leave the stored power untouched.
	skills.busy_skill = "basic"
	skills.busy_target = null
	skills.busy_aim = player.global_position + Vector3(0.0, 0.0, -2.0)
	skills._apply_skill(SkillDb.all()["basic"])
	expect("a missed Brutal Attack is not consumed", skills.brutal_armed and player.stats.brutal_reload_remaining == 0.0)
	var victim: Enemy = _spawn_enemy(player.global_position + Vector3(0.0, 0.0, -1.7))
	victim.max_health = 10000.0
	victim.health = victim.max_health
	victim.armor = 0.0
	var before: float = victim.health
	skills.busy_target = victim
	Fx._recent_impacts.clear()
	skills._apply_skill(SkillDb.all()["basic"])
	# Use the production helper so the test observes the same minimum level guard as a fresh new-game save.
	var expected_reload: float = player.stats.brutal_recharge_damage()
	expect("the next successful basic hit spends Brutal Attack and deals its amplified weapon damage",
		not skills.brutal_armed and is_equal_approx(player.stats.brutal_reload_remaining, expected_reload)
		and is_equal_approx(player.stats.brutal_reload_required, expected_reload) and before - victim.health > player.stats.weapon_range(1.0).y * 5.0)
	expect("spending Brutal Attack removes its persistent aura", skills._brutal_aura == null)
	expect("Brutal Attack's directional impact does not also spawn the generic heavy-hit ground ring", not Fx._recent_impacts.has("crush_ring"))
	player.on_dealt_hit(victim, {"outcome": Combat.Outcome.HIT, "damage": 90.0, "skill_id": "basic"})
	expect("ordinary combat damage subtracts from DS2's reload-damage budget",
		is_equal_approx(player.stats.brutal_reload_remaining, expected_reload - 90.0))
	player.on_dealt_hit(victim, {"outcome": Combat.Outcome.HIT, "damage": 999.0, "skill_id": "brutal_attack"})
	expect("Brutal Attack does not recharge itself", is_equal_approx(player.stats.brutal_reload_remaining, expected_reload - 90.0))
	var gibs_before: int = get_tree().get_nodes_in_group("gibs").size()
	victim.health = 1.0
	var brutal_kill: Dictionary = Combat.resolve(player, victim, 10.0, Combat.DamageType.PHYSICAL, false, 1.0, false)
	brutal_kill["outcome"] = Combat.Outcome.HIT   # prove the skill, not a crit/crushing roll, causes the gib
	brutal_kill["damage"] = 10.0
	brutal_kill["skill_id"] = "brutal_attack"
	victim.receive(brutal_kill, player.global_position)
	expect("a lethal Brutal Attack gibs the enemy",
		victim.dead and not victim.visual.visible and get_tree().get_nodes_in_group("gibs").size() > gibs_before)
	victim.queue_free()
	for node in get_tree().get_nodes_in_group("gibs"):
		node.queue_free()
	skills.cancel_action()

## Weapons have a moveset of their own: the falchion recovers fast, staggers lightly and finishes its combo quickly; the longsword is the
## baseline; the greatsword hits a wide arc, staggers and knocks back harder, recovers slowly and finishes with a slam.
## Both hands are closed gauntlets round the grip (the open Meshy hands are shrunk away), and standing about long enough rests the sword on his shoulder.
func _test_fists() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var model: CharacterModel = player.model
	await get_tree().create_timer(0.3).timeout
	expect("each hand has its own closed fist", model._mounts.size() == 2 and model._mounts["RightHand"].get_child_count() >= 1
		and model._mounts["LeftHand"].get_child_count() == 1)
	expect("the sword is held by the right fist's mount", model.weapon != null and model.weapon.get_parent() == model._mounts["RightHand"])
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	expect("the open hand meshes are shrunk away inside the wrists", skeleton.get_bone_pose_scale(skeleton.find_bone("RightHand")).x < 0.1
		and skeleton.get_bone_pose_scale(skeleton.find_bone("LeftHand")).x < 0.1)
	expect("the fist is not shrunk with them", (model._mounts["RightHand"] as Node3D).transform.basis.get_scale().x > 0.5)
	player.combat_timer = 0.0
	player.movement.idle_time = 0.0
	player.movement.update_locomotion_anim()
	expect("standing about he is alert at first", model.current == "idle_alert")
	player.movement.idle_time = PlayerMovement.REST_AFTER + 1.0
	player.movement.update_locomotion_anim()
	expect("after a while he rests the sword on his shoulder", model.current == "idle_rest")
	player.combat_timer = 3.0
	player.movement.update_locomotion_anim()
	expect("in a fight he is alert again", model.current == "idle_alert")
	player.movement.idle_time = 0.0

## A two-hander swings its own clips (both hands on the grip); the one-handers swing theirs, and no basic swing leaves a blade ribbon.
func _test_two_hand() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	var skills: SkillController = player.skills
	var seen: Dictionary = {}
	for base in ["Falchion", "Greatsword"]:
		TownState.passive_ranks["overbear"] = 1   # (a two-handed weapon needs Overbear)
		player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, base), false)
		var clips: Array[String] = []
		for step in 3:
			var far: Enemy = _spawn_enemy(Vector3(0, 0, 14))
			far.alert_delay = 999.0
			skills.combo_step = step
			skills.start_skill("basic", far)
			clips.append(player.model.current)
			expect("%s swing %d has a blade ribbon only when it is not a basic swing" % [base, step], not player._trail.active)
			skills.cancel_action()
			far.queue_free()
		seen[base] = clips
	var one: Array = seen["Falchion"]
	var two: Array = seen["Greatsword"]
	expect("a falchion swings the one-handed clips", one.all(func(c: String) -> bool: return c.begins_with("atk_")))
	expect("a greatsword swings the two-handed clips", two.all(func(c: String) -> bool: return c.begins_with("atk2_")))
	expect("a greatsword recovers slower than it did", float(player.stats.weapon_profile("recovery", 1.0)) <= 0.6)

func _test_weapon_styles() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	var skills: SkillController = player.skills
	var swing_time: Dictionary = {}
	var finisher_time: Dictionary = {}
	var actual_finisher: Dictionary = {}   # how long the finisher really takes, swing speed and recovery included
	var weights: Dictionary = {}
	var swept: Dictionary = {}
	var slammed: Dictionary = {}
	var base_time: float = float(SkillDb.basic_combo()[2][0]["time"])
	for base in ["Falchion", "Longsword", "Greatsword"]:
		TownState.passive_ranks["overbear"] = 1   # (a two-handed weapon needs Overbear)
		player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, base), false)
		# How long a first swing takes from start to recovered (stepped by hand so engine time cannot blur it).
		var far: Enemy = _spawn_enemy(Vector3(0, 0, 14))
		far.alert_delay = 999.0
		skills.combo_step = 0
		skills.start_skill("basic", far)
		var steps: int = 0
		while skills.busy and steps < 900:
			skills.tick_busy(1.0 / 60.0)
			steps += 1
		swing_time[base] = steps / 60.0
		far.queue_free()
		skills.combo_step = 2
		finisher_time[base] = float(skills._next_basic()["time"])
		skills.combo_step = 2
		skills.start_skill("basic", _spawn_enemy(Vector3(0, 0, 14)))
		var fsteps: int = 0
		while skills.busy and fsteps < 900:
			skills.tick_busy(1.0 / 60.0)
			fsteps += 1
		actual_finisher[base] = fsteps / 60.0
		# What one swing does to enemies around the target (the timed swing above lunged the hero forward: back to the origin).
		player.global_position = Vector3.ZERO
		player.reset_physics_interpolation()
		var target: Enemy = _spawn_enemy(Vector3(0, 0, 1.6))
		var left: Enemy = _spawn_enemy(Vector3(1.4, 0, 1.2))
		var right: Enemy = _spawn_enemy(Vector3(-1.3, 0, 1.3))
		var behind: Enemy = _spawn_enemy(Vector3(0, 0, -1.5))
		var group: Array[Enemy] = [target, left, right, behind]
		for e in group:
			e.alert_delay = 999.0
			e.max_health = 5000.0
			e.health = 5000.0
			e.dodge_chance = 0.0   # (DS2: a blow lands unless dodged or blocked)
			e.block_chance = 0.0
		skills.busy_skill = "basic"
		skills.busy_target = target
		skills.busy_aim = target.global_position
		var plain: Dictionary = SkillDb.all()["basic"].duplicate()
		plain.merge(SkillDb.basic_combo()[0][0], true)
		weights[base] = 0.0
		for attempt in 8:
			skills._apply_skill(plain)
			if not target.last_result.is_empty():
				weights[base] = float(target.last_result.get("weight", 0.0))
		swept[base] = int(left.health < 5000.0) + int(right.health < 5000.0) + int(behind.health < 5000.0)
		for e in group:
			e.health = 5000.0
			e.stun_time = 0.0
		var finisher: Dictionary = SkillDb.all()["basic"].duplicate()
		finisher.merge(SkillDb.basic_combo()[2][0], true)
		skills._apply_skill(finisher)
		slammed[base] = int(left.stun_time > 0.0) + int(right.stun_time > 0.0) + int(behind.stun_time > 0.0)
		skills.brutal_armed = true
		skills._apply_skill(plain)
		expect("%s Brutal Attack never cleaves adjacent enemies" % base, left.health == 5000.0 and right.health == 5000.0 and behind.health == 5000.0)
		target.global_position = Vector3(0, 0, 14)
		skills.brutal_armed = true
		skills._apply_skill(finisher)
		expect("%s out-of-reach swing cannot hit bystanders or spend Brutal Attack" % base,
			skills.brutal_armed and left.health == 5000.0 and right.health == 5000.0 and behind.health == 5000.0)
		skills.brutal_armed = false
		for e in group:
			e.queue_free()
		await get_tree().process_frame
	expect("a falchion recovers faster than a longsword, a greatsword slower", swing_time["Falchion"] < swing_time["Longsword"] - 0.1
		and swing_time["Greatsword"] > swing_time["Longsword"] + 0.1)
	expect("a falchion's finisher is short and a greatsword's is not", absf(finisher_time["Falchion"] - base_time * 0.9) < 0.001 and absf(finisher_time["Longsword"] - base_time) < 0.001
		and absf(finisher_time["Greatsword"] - base_time) < 0.001)
	expect("a falchion's finisher really takes about 0.8 s (longsword 1.3 s), readable from wind-up to finish", actual_finisher["Falchion"] > 0.7
		and actual_finisher["Falchion"] < 0.9 and absf(actual_finisher["Longsword"] - base_time) < 0.05 and actual_finisher["Greatsword"] > actual_finisher["Longsword"])
	expect("stagger weight rises falchion < longsword < greatsword", weights["Falchion"] < weights["Longsword"] - 0.15 and weights["Greatsword"] > weights["Longsword"] + 0.3)
	expect("DS2 basic swings hit only the engaged target with every weapon", swept["Falchion"] == 0 and swept["Longsword"] == 0 and swept["Greatsword"] == 0)
	expect("basic finishers never add a free area slam", slammed["Falchion"] == 0 and slammed["Longsword"] == 0 and slammed["Greatsword"] == 0)
	expect("the tooltip says how the weapon fights", Items.lines(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Greatsword")).any(
		func(line: String) -> bool: return line.contains("Single target")))
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Longsword"), false)

## Standing monsters take a blow in the body: the chest tips away from it, overshoots and settles (BodyRecoil + CharacterModel._apply_hit_reaction).
func _test_body_recoil() -> void:
	await get_tree().process_frame
	# The spring on its own: heavier blows lean further, big monsters lean less, it overshoots once, and comes to rest.
	var light: float = BodyRecoil.peak_for(0.4, 1.0, 0.0)
	var heavy: float = BodyRecoil.peak_for(1.5, 1.0, 0.0)
	var crushing: float = BodyRecoil.peak_for(2.2, 1.5, 0.0)
	var heavy_big: float = BodyRecoil.peak_for(1.5, 1.0, 0.8)
	expect("light, heavy and crushing hits have distinct body-recoil peaks", light < heavy and heavy < crushing and crushing <= BodyRecoil.MAX_LEAN)
	expect("a monster that resists knock-back leans less", heavy_big < heavy * 0.7)
	var front := BodyRecoil.new()
	front.hit(Vector3(0, 0, 1), Vector3(0, 0, 1), heavy, 0.0)
	front.step(1.0 / 60.0)
	var rear := BodyRecoil.new()
	rear.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), heavy, 0.0)
	rear.step(1.0 / 60.0)
	expect("front and rear blows move the torso in opposite directions", front.lean.y > 0.0 and rear.lean.y < 0.0)
	var spring := BodyRecoil.new()
	spring.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.3, 0.0)
	var peak: float = 0.0
	var crossed: bool = false
	for i in 120:
		spring.step(1.0 / 60.0)
		peak = maxf(peak, spring.lean.length())
		if spring.lean.y > 0.01:
			crossed = true   # it rocked back past upright (the blow pushed toward -z)
	expect("the lean reaches about the asked-for peak, in the direction of the blow", peak > 0.2 and peak < 0.45)
	expect("it overshoots upright once (momentum recovery)", crossed)
	for i in 120:
		spring.step(1.0 / 60.0)
	expect("and it comes to rest", not spring.active())
	var stepper := BodyRecoil.new()
	stepper.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.32, 0.0)
	var first_leg: int = stepper.step_leg
	var mild := BodyRecoil.new()
	mild.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.1, 0.0)
	expect("a heavy blow costs a recovery step, a light one does not", stepper.step_t > 0.0 and mild.step_t <= 0.0 and stepper.step_swing() >= 0.0)
	var crusher := BodyRecoil.new()
	crusher.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), crushing, 0.0)
	expect("crushing hits request a deeper directional recovery than heavy hits", crusher.step_peak > stepper.step_peak and crusher.step_t > stepper.step_t)
	for i in 90:
		stepper.step(1.0 / 60.0)
	stepper.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.32, 0.0)
	expect("the next step uses the other leg", stepper.step_leg != first_leg)
	var sideways := BodyRecoil.new()
	sideways.hit(Vector3(1, 0, 0), Vector3(0, 0, 1), 0.3, 0.0)
	var straight := BodyRecoil.new()
	straight.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.3, 0.0)
	expect("a blow from the side turns the shoulders, one from the front does not", absf(sideways.twist_vel) > 0.5 and absf(straight.twist_vel) < 0.01)
	var rapid := BodyRecoil.new()
	var controlled: bool = true
	for i in 80:
		var impact_dir: Vector3 = Vector3(1, 0, 0) if i % 4 == 0 else Vector3(0, 0, -1)
		rapid.hit(impact_dir, Vector3(0, 0, 1), crushing, 0.0)
		rapid.step(1.0 / 60.0)
		controlled = controlled and rapid.lean.length() <= BodyRecoil.MAX_LEAN + 0.001 \
			and absf(rapid.twist) <= BodyRecoil.MAX_TWIST + 0.001 \
			and rapid.lean_vel.length() <= BodyRecoil.MAX_LEAN_SPEED + 0.001 \
			and absf(rapid.twist_vel) <= BodyRecoil.MAX_TWIST_SPEED + 0.001
	for i in 240:
		rapid.step(1.0 / 60.0)
	expect("rapid crushing impacts stay bounded and the body settles afterward", controlled and not rapid.active())
	# On real monsters: every body has a spine to bend, and a landed blow moves it and then settles.
	for variant in ["zombie", "ghoul", "spitter", "bloater", "brute", "priest"]:
		var body: Enemy = _spawn_enemy(Vector3(-30, 0, -30), variant)
		body.aggro_range = 0.0
		body.max_health = 5000.0
		body.health = 5000.0
		await get_tree().process_frame
		body.model._find_reaction_bones()
		expect("%s has a spine to bend" % variant, body.model._spine.size() >= 1)
		body.queue_free()
	var target: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -6.0), "zombie")
	target.aggro_range = 0.0
	target.max_health = 5000.0
	target.health = 5000.0
	await get_tree().create_timer(0.4).timeout
	var blow: Dictionary = {"outcome": Combat.Outcome.CRITICAL, "damage": 5.0, "weight": 2.2, "source": player,
		"type": Combat.DamageType.PHYSICAL, "skill_id": "basic"}
	target.receive(blow, target.global_position + Vector3(0, 0, 3.0))
	var seen: float = 0.0
	for i in 40:
		await get_tree().physics_frame
		seen = maxf(seen, target.model.reaction.lean.length())
	expect("a heavy critical blow on a standing zombie tips its spine (peak %.2f rad)" % seen, seen > 0.15)
	expect("and the zombie has thighs to step with", target.model._thighs.size() == 2 and target.model._thighs[0] > 0 and target.model._thighs[1] > 0)
	await get_tree().create_timer(1.8).timeout
	expect("and it recovers", not target.model.reaction.active())
	# Every blow interrupts a small monster, even a light one, and a blow while it is still reeling restarts the reaction.
	target.stun_time = 0.0
	var light_blow: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": 1.0, "weight": 0.5, "source": player,
		"type": Combat.DamageType.PHYSICAL, "skill_id": "basic"}
	var every_time: bool = true
	for i in 4:
		target.stun_time = 0.0
		target.receive(light_blow, target.global_position + Vector3(0, 0, 3.0))
		every_time = every_time and target.stun_time >= 0.1
	expect("a light blow interrupts a small monster every time", every_time)
	var serial: int = target.flinch_serial
	target.receive(light_blow, target.global_position + Vector3(0, 0, 3.0))
	expect("each blow counts, so the hit pose can restart", target.flinch_serial == serial + 1)
	target.health = 1.0
	var lethal_blow: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": 1.0, "weight": 1.0, "source": player,
		"type": Combat.DamageType.PHYSICAL, "skill_id": "basic"}
	target.receive(lethal_blow, target.global_position + Vector3(0, 0, 3.0))
	await get_tree().process_frame
	await get_tree().process_frame
	expect("death and ragdoll handoff clear the standing-body reaction", target.dead and target.is_ragdolled() and not target.model.reaction.active())
	target.queue_free()
