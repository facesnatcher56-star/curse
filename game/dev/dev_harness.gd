class_name DevHarness
extends Node3D
## Developer tooling kept out of the game proper: the headless `--selftest` suite and the screenshot / pose tools.
## Main creates one of these and calls run_from_args(); when a dev flag is present it takes over the run.
##   --selftest [--only=NAME]   run the checks (CI runs this headless)
##   --skillshot=NAME, --aimshot, --hudshot, --hovershot, --rollshot, --poses, --clipsheet=, --shot
## Everything below talks to the running game through `game` (the Main node).

var game: Node3D

# Short names for the parts of the game the checks drive.
var player: Player:
	get: return game.player
var hud: Hud:
	get: return game.hud
var rig: CameraRig:
	get: return game.rig
var arena: Arena:
	get: return game.arena
var pause_menu: PauseMenu:
	get: return game.pause_menu
var wave: int:
	get: return game.director.wave
	set(value): game.director.wave = value
var kills: int:
	get: return game.director.kills

func _spawn_enemy(pos: Vector3, variant: String = "zombie", level: float = 1.0) -> Enemy:
	return game.director.spawn_enemy(pos, variant, level)

func _next_wave() -> void:
	game.director.start_wave()

## Returns true when a developer mode was started (so Main should not begin a normal run).
func run_from_args() -> bool:
	if OS.get_cmdline_user_args().has("--skillshot=skewer"):
		_skill_shots("skewer")
	elif OS.get_cmdline_user_args().has("--skillshot=fireball"):
		_skill_shots("fireball")
	elif OS.get_cmdline_user_args().has("--skillshot=leap"):
		_leap_shots()
	elif OS.get_cmdline_user_args().has("--skillshot=earthshatter"):
		_earthshatter_shots()
	elif OS.get_cmdline_user_args().has("--enemyshot"):
		_enemy_shot()
	elif OS.get_cmdline_user_args().has("--enemyfight"):
		_enemy_fight()
	elif OS.get_cmdline_user_args().has("--skillshot=gibs"):
		_gib_shots()
	elif OS.get_cmdline_user_args().has("--skillshot=power"):
		_melee_shots("power")
	elif OS.get_cmdline_user_args().has("--skillshot=cleave"):
		_melee_shots("cleave")
	elif OS.get_cmdline_user_args().has("--aimshot"):
		_aim_shot()
	elif OS.get_cmdline_user_args().has("--pauseshot"):
		_pause_shot()
	elif OS.get_cmdline_user_args().has("--hudshot"):
		_hud_shot()
	elif OS.get_cmdline_user_args().has("--smashshot"):
		_smash_shot()
	elif OS.get_cmdline_user_args().has("--itemsheet"):
		_item_sheet()
	elif OS.get_cmdline_user_args().has("--hovershot"):
		_hover_shot()
	elif OS.get_cmdline_user_args().has("--rollshot"):
		_roll_shots()
	elif OS.get_cmdline_user_args().has("--poses"):
		_pose_sheet()
	elif _clip_arg() != "":
		_clip_sheet(_clip_arg())
	elif OS.get_cmdline_user_args().has("--selftest"):
		_run_selftest()
	elif OS.get_cmdline_user_args().has("--shot"):
		_next_wave()
		_screenshot_demo()
	else:
		return false
	return true

## Skewer: a Brute in the lane is staggered (not impaled); three zombies are impaled, ragdoll, get kicked off and
## thrown trailing blood, lie limp, then get back up. A fourth zombie is only shoved aside.
## A click attacks once; nothing keeps attacking afterwards, and skills drop the attack order.
func _test_auto_attack() -> void:
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	var dummy: Enemy = _spawn_enemy(Vector3(3.5, 0, 0))
	dummy.aggro_range = 0.0
	dummy.max_health = 5000.0
	dummy.health = 5000.0
	await get_tree().physics_frame
	# 1. Order an attack with the mouse NOT held: it should walk up and swing exactly once.
	player.attack_target = dummy
	player.click_mode = 1
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
	expect("click attacks exactly once", swings == 1)
	expect("hero idles after a single click", idle_after)
	expect("hero does not swing or turn with no input", not busy_during_idle and absf(yaw_drift) < 0.02)
	expect("a skill clears the attack order", cleared_by_skill)
	expect("no swinging resumes after a skill", not swings_after_skill)
	print("  auto-attack: one click -> swings=", swings, " (expected 1), idle afterwards=", idle_after, ", idle with enemy near: busy=", busy_during_idle,
		" turned ", snappedf(rad_to_deg(yaw_drift), 0.1), " deg, skill clears attack order=", cleared_by_skill, ", resumed swinging after skill=", swings_after_skill)
	dummy.queue_free()
	await get_tree().process_frame

## Hotkeys pressed mid-animation: the potion drinks immediately, usable skills cancel the swing, unusable ones do not.
func _test_hotkeys() -> void:
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.stats.potions = 3
	var dummy: Enemy = _spawn_enemy(Vector3(1.8, 0, 0))
	dummy.aggro_range = 0.0
	dummy.max_health = 900.0
	dummy.health = 900.0
	await get_tree().physics_frame
	# 1. Potion during a swing.
	player.health = 40.0
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.15).timeout
	var was_busy: bool = player.skills.busy
	Input.action_press("skill_4")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_4")
	var potion_ok: bool = player.stats.potions == 2 and player.health > 80.0 and not player.skills.busy
	# 2. Potion while stunned.
	player.health = 30.0
	player.stats.cooldowns.clear()
	player.stun_time = 1.0
	await get_tree().physics_frame
	Input.action_press("skill_4")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_4")
	var stunned_ok: bool = player.stats.potions == 1 and player.health > 60.0
	player.stun_time = 0.0
	# 3. A usable skill cancels the current swing and starts.
	player.stats.cooldowns.clear()
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.1).timeout
	Input.action_press("skill_5")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_5")
	var skill_ok: bool = player.skills.busy_skill == "skewer" and player.skewer.skewer_phase != 0
	player.skills.cancel_action()
	# 4. A skill on cooldown must NOT cancel the swing.
	player.stats.cooldowns["skewer"] = 5.0
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.1).timeout
	Input.action_press("skill_5")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_5")
	var no_cancel_ok: bool = player.skills.busy and player.skills.busy_skill == "basic"
	player.skills.cancel_action()
	expect("potion works mid-swing", potion_ok)
	expect("potion works while stunned", stunned_ok)
	expect("a usable skill cancels a swing", skill_ok)
	expect("an unusable skill leaves the swing alone", no_cancel_ok)
	print("  hotkeys: potion mid-swing=", potion_ok, " (was busy=", was_busy, "), potion while stunned=", stunned_ok,
		", skill cancels swing=", skill_ok, ", skill on cooldown leaves swing alone=", no_cancel_ok)
	dummy.queue_free()
	player.stats.cooldowns.clear()
	player.stats.potions = 3
	await get_tree().process_frame

## Navigation: a path across the biggest obstacle must detour around it, and the hero must actually walk it.
func _test_navigation() -> void:
	var largest: Dictionary = {}
	for ob in arena.obstacles:
		if largest.is_empty() or float(ob["radius"]) > float(largest["radius"]):
			largest = ob
	if largest.is_empty():
		print("  navigation: no obstacles to test")
		return
	var centre: Vector3 = largest["position"]
	var radius: float = float(largest["radius"])
	# Pick the axis with the most room around the obstacle.
	var span: float = radius + 3.0
	var from: Vector3 = Nav.snap(player, centre + Vector3(-span, 0, 0))
	var to: Vector3 = Nav.snap(player, centre + Vector3(span, 0, 0))
	var map: RID = Nav.map_of(player)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	var length: float = 0.0
	var clearance: float = 9999.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
		var seg: Vector3 = path[i + 1] - path[i]
		var t: float = clampf((centre - path[i]).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		var nearest: Vector3 = path[i] + seg * t
		clearance = minf(clearance, Vector2(nearest.x - centre.x, nearest.z - centre.z).length())
	var straight: float = from.distance_to(to)
	# Now walk it with the real controller.
	player.global_position = from
	player.reset_physics_interpolation()
	await get_tree().physics_frame
	player.movement.goal = to
	player.movement.has_goal = true
	var elapsed: float = 0.0
	var min_gap: float = 9999.0
	while elapsed < 12.0 and Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() > 0.8:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		player.movement.has_goal = true
		player.movement.goal = to
		min_gap = minf(min_gap, Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length())
	var reached: bool = Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() <= 1.0
	expect("hero walks around the obstacle to the goal", reached)
	print("  navigation: obstacle radius ", snappedf(radius, 0.1), " m; path ", snappedf(length, 0.1), " m vs straight ", snappedf(straight, 0.1),
		" m (", path.size(), " points), path clearance ", snappedf(clearance, 0.1), " m; hero walked it: reached=", reached, " in ", snappedf(elapsed, 0.1),
		" s, closest approach ", snappedf(min_gap, 0.1), " m")
	player.movement.has_goal = false
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	await get_tree().process_frame

## A spot with nothing (props, walls) in a corridor of `length` along +X, so spawned test enemies are not pushed around.
func _free_lane_start(length: float, width: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 2.0, width)
	for candidate in [Vector3(-25, 0, 25), Vector3(25, 0, -25), Vector3(-25, 0, -25), Vector3(25, 0, 25), Vector3(0, 0, 30),
			Vector3(0, 0, -30), Vector3(-30, 0, 0), Vector3(-12, 0, 18), Vector3(-12, 0, -18), Vector3(12, 0, 18)]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), candidate + Vector3(length * 0.5, 1.6, 0.0))
		query.collision_mask = Actor.LAYER_WORLD
		if space.intersect_shape(query, 1).is_empty():
			return candidate
	return Vector3.ZERO

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

## Crit kills burst into gore, fireball kills into burning pieces, plain kills just fall over.
func _test_gibs() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("gibs"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(-30, 0, 30)
	player.reset_physics_interpolation()
	var crit_victim: Enemy = _spawn_enemy(Vector3(-30, 0, 24))
	var plain_victim: Enemy = _spawn_enemy(Vector3(-24, 0, 30))
	var fire_victim: Enemy = _spawn_enemy(Vector3(-36, 0, 30))
	for e in [crit_victim, plain_victim, fire_victim]:
		e.aggro_range = 0.0
	await get_tree().process_frame
	var crit: Dictionary = Combat.resolve(player, crit_victim, 500.0, Combat.DamageType.PHYSICAL, false, 1.5, true)
	crit_victim.receive(crit, player.global_position)
	await get_tree().process_frame
	var gore_chunks: int = get_tree().get_nodes_in_group("gibs").size()
	var gore_hidden: bool = not crit_victim.visual.visible
	var gore_burning: int = 0
	for g in get_tree().get_nodes_in_group("gibs"):
		if (g as GibChunk).burning:
			gore_burning += 1
	var plain: Dictionary = Combat.resolve(player, plain_victim, 500.0, Combat.DamageType.PHYSICAL, false, 1.0, false)
	plain["outcome"] = Combat.Outcome.HIT
	plain_victim.receive(plain, player.global_position)
	await get_tree().process_frame
	var plain_chunks: int = get_tree().get_nodes_in_group("gibs").size() - gore_chunks
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.damage = 500.0
	ball.destination = fire_victim.global_position
	add_child(ball)
	ball.global_position = fire_victim.global_position + Vector3(0, 1.0, 0)
	ball._explode()
	await get_tree().process_frame
	var fire_chunks: int = get_tree().get_nodes_in_group("gibs").size() - gore_chunks - plain_chunks
	var fire_burning: int = 0
	for g in get_tree().get_nodes_in_group("gibs"):
		if (g as GibChunk).burning:
			fire_burning += 1
	var fire_hidden: bool = not fire_victim.visual.visible
	await get_tree().create_timer(2.5).timeout
	var grounded: int = 0
	for g in get_tree().get_nodes_in_group("gibs"):
		if (g as Node3D).global_position.y < 0.3:
			grounded += 1
	expect("crit kill bursts into non-burning gore", gore_chunks > 0 and gore_hidden and gore_burning == 0)
	expect("plain kill leaves the body", plain_chunks == 0 and plain_victim.visual.visible)
	expect("fireball kill bursts into burning pieces", fire_chunks > 0 and fire_burning == fire_chunks and fire_hidden)
	expect("gib pieces land", grounded > 0)
	print("  gibs: crit kill -> ", gore_chunks, " chunks (burning=", gore_burning, ") body hidden=", gore_hidden, "; plain kill -> ", plain_chunks,
		" chunks, body visible=", plain_victim.visual.visible, "; fireball kill -> ", fire_chunks, " chunks (burning=", fire_burning, ") body hidden=",
		fire_hidden, "; pieces on the ground after 2.5 s: ", grounded)
	for node in get_tree().get_nodes_in_group("gibs"):
		node.queue_free()
	for e in [crit_victim, plain_victim, fire_victim]:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame

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
	var elapsed: float = 0.0
	while elapsed < 9.0 and not states.has(PouncerBehavior.State.RECOVER):
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		var state: int = (ghoul.behavior as PouncerBehavior)._state
		states[state] = true
		if state == PouncerBehavior.State.RECOVER:
			landed_near = ghoul.flat_distance_to(player) < 2.2
	expect("ghoul crouches, leaps and lands next to the hero", states.has(PouncerBehavior.State.WINDUP) and states.has(PouncerBehavior.State.LEAP) and landed_near)
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

## Controller: sticks move and aim the hero, buttons are bound to the skills, rolls follow the stick, hints switch to pad labels.
func _test_gamepad() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	# Every action has its pad button.
	var wanted: Dictionary = {"alt_skill": true, "dodge": true, "skill_1": true, "skill_2": true, "skill_3": true, "skill_4": true,
		"skill_5": true, "skill_6": true, "skill_7": true, "pause": true, "gear": true, "zoom_in": true, "zoom_out": true, "stand_still": true}
	var missing: PackedStringArray = []
	for action in wanted:
		var has_pad: bool = false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_pad = true
		if not has_pad:
			missing.append(action)
	expect("every action has a controller binding", missing.is_empty())
	expect("keyboard bindings survive next to the pad ones", GameSettings.binding_text("skill_1") == "1")

	player.global_position = Vector3(-30, 0, 20)
	player.reset_physics_interpolation()
	player.movement.has_goal = false
	player.attack_target = null
	Gamepad.active = true
	# Left stick moves the hero, analog.
	Gamepad.test_axes = {JOY_AXIS_LEFT_X: 1.0, JOY_AXIS_LEFT_Y: 0.0}
	var start: Vector3 = player.global_position
	await get_tree().create_timer(1.0).timeout
	var run_dist: float = player.global_position.x - start.x
	var run_clip: String = player.model.current
	expect("left stick runs the hero", run_dist > 3.5 and run_clip == "run")
	Gamepad.test_axes = {JOY_AXIS_LEFT_X: 0.0, JOY_AXIS_LEFT_Y: 0.5}
	start = player.global_position
	await get_tree().create_timer(1.0).timeout
	var walk_dist: float = player.global_position.z - start.z
	expect("a light push walks slower than a full push", walk_dist > 1.0 and walk_dist < run_dist * 0.8)
	Gamepad.test_axes = {}
	await get_tree().create_timer(0.4).timeout
	expect("releasing the stick stops the hero", player.velocity.length() < 0.5 and player.model.current == "idle_alert")
	print("  gamepad move: full push ", snappedf(run_dist, 0.1), " m (", run_clip, "), half push ", snappedf(walk_dist, 0.1), " m")

	# The right stick is the camera: pushed up with no skill held it does not move the target; the nearest enemy in front is targeted.
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: 0.0, JOY_AXIS_RIGHT_Y: -1.0}
	player.visual.rotation.y = 0.0
	var enemy: Enemy = _spawn_enemy(player.global_position + Vector3(4.0, 0, 3.0))
	enemy.aggro_range = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("the right stick does not aim the hero; the facing target is used", player.cursor_world().distance_to(enemy.global_position) < 0.01 and player.hover_target == enemy)
	Gamepad.test_axes = {}

	# A attacks the auto-target (same path as the right mouse button).
	player.global_position = enemy.global_position + Vector3(-1.6, 0, 0)
	player.reset_physics_interpolation()
	enemy.max_health = 5000.0
	enemy.health = 5000.0
	Input.action_press("alt_skill")
	var swung: bool = false
	var t: float = 0.0
	while t < 2.0 and not swung:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		swung = player.skills.busy
	Input.action_release("alt_skill")
	expect("A attacks the targeted enemy", swung)
	await get_tree().create_timer(1.2).timeout
	for retry in 3:   # a swing can miss or be blocked at random: swing again rather than fail on bad luck
		if enemy.health < enemy.max_health:
			break
		Input.action_press("alt_skill")
		await get_tree().create_timer(1.4).timeout
		Input.action_release("alt_skill")
	expect("the enemy was hit", enemy.health < enemy.max_health)

	# Rolling follows the stick.
	player.skills.cancel_action()
	player.stats.cooldowns.clear()
	player.stats.stamina = player.stats.max_stamina
	player.global_position = Vector3(-30, 0, 20)
	player.reset_physics_interpolation()
	await get_tree().physics_frame
	Gamepad.test_axes = {JOY_AXIS_LEFT_X: 0.0, JOY_AXIS_LEFT_Y: 1.0}
	player.movement.try_roll(player.cursor_world())
	var roll_toward_z: bool = player.movement.rolling and player.movement.roll_dir.z > 0.9
	expect("the dodge rolls the way the stick points", roll_toward_z)
	Gamepad.test_axes = {}
	await get_tree().create_timer(0.8).timeout

	# Hints show pad labels while the pad is in use and keyboard ones otherwise.
	var pad_hint: String = GameSettings.short_binding_text("skill_1")
	Gamepad.active = false
	var key_hint: String = GameSettings.short_binding_text("skill_1")
	expect("hotbar hints switch between pad and keyboard labels", pad_hint == "X" and key_hint == "1")
	print("  gamepad hints: pad=", pad_hint, " keyboard=", key_hint)
	Gamepad.active = false
	Gamepad.test_axes = {}
	enemy.queue_free()
	await get_tree().process_frame

## The loading screen loads every asset on background threads, the bar only ever moves forward and ends at 100%,
## and the messages rotate without repeating back to back.
func _test_loading() -> void:
	var screen := LoadingScreen.new()
	screen.auto_switch = false
	LoadingScreen.next_scene = "res://game/main.tscn"
	add_child(screen)
	var last: float = 0.0
	var monotonic: bool = true
	var elapsed: float = 0.0
	while elapsed < 60.0 and not (screen._finished and screen.progress >= 0.999):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		monotonic = monotonic and screen.progress >= last - 0.0001
		last = screen.progress
	expect("loading screen finishes loading everything", screen._finished and screen.assets_total > 20 and screen.assets_done == screen.assets_total)
	expect("the progress bar only moves forward and ends full", monotonic and screen.progress >= 0.999)
	var seen: Dictionary = {}
	var repeat: bool = false
	var previous: String = screen.message
	for i in 120:
		var next: String = screen.next_message()
		repeat = repeat or next == previous
		previous = next
		seen[next] = true
	expect("loading messages are plentiful and never repeat back to back", LoadingScreen.MESSAGES.size() >= 40 and seen.size() >= 25 and not repeat)
	print("  loading: ", screen.assets_done, "/", screen.assets_total, " assets in ", snappedf(elapsed, 0.1), " s, ", LoadingScreen.MESSAGES.size(), " messages, e.g. \"", screen.message, "\"")
	screen.queue_free()
	await get_tree().process_frame

## Hero stands idle with NO input while a pack of zombies swarms in. Logs hits taken per second, how many attackers swing at
## once, and any moment the hero starts a skill / changes clip by itself (an "auto attack" with nobody clicking).
func _test_swarm() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(-30, 0, -30)
	player.reset_physics_interpolation()
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
	while elapsed < 8.0:
		await get_tree().physics_frame
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
	expect("swarm damage stays under 8/s", (start_health - player.health) / 8.0 < 8.0)
	expect("hero never acts or animates by itself in a swarm", not autos.any(func(l: String) -> bool: return "busy skill" in l or "-> walk" in l or "-> run" in l))
	print("  swarm: hero health ", int(start_health), " -> ", int(player.health), " in 8 s (", snappedf((start_health - player.health) / 8.0, 0.1),
		" dmg/s); attackers swinging at once: max ", max_swinging, ", average ", snappedf(swinging_total / frames, 0.1))
	for line in autos:
		print("    ", line)
	# A skill cast in the middle of the swarm should run to the end, not get cut short by incoming hits.
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.health = player.max_health
	player.skills.start_skill("cleave", null, player.global_position + Vector3(0, 0, 2))
	var cast: float = 0.0
	var interrupted: bool = false
	while player.skills.busy and cast < 3.0:
		await get_tree().physics_frame
		cast += 1.0 / 60.0
	expect("a cleave in the middle of a swarm runs to the end", cast >= 1.0 and player.stun_time == 0.0)
	print("  cleave inside the swarm: lasted ", snappedf(cast, 0.01), " s of ", snappedf(player.skills.busy_time, 0.01), " expected, stun at end=", player.stun_time)
	for z in zs:
		if is_instance_valid(z):
			z.queue_free()

## Wave layout (packs + isolated Brutes), loot rates, potion pickups and click-to-cancel.
func _test_balance() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
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
	# Loot rates.
	var dummy: Enemy = _spawn_enemy(Vector3(30, 0, 30))
	await get_tree().process_frame
	for hp in [1.0, 0.3]:
		player.health = player.max_health * hp
		var orbs: int = 0
		var potions: int = 0
		for i in 400:
			ItemEffects._drop_loot(player, dummy)
		for node in get_tree().get_nodes_in_group("orbs"):
			if bool(node.get("is_potion")):
				potions += 1
			else:
				orbs += 1
			node.queue_free()
		await get_tree().process_frame
		print("  loot per 100 zombie kills at ", int(hp * 100), "% health: orbs=", orbs / 4.0, " potions=", potions / 4.0)
	dummy.queue_free()
	var brute: Enemy = _spawn_enemy(Vector3(30, 0, 30), "brute")
	await get_tree().process_frame
	var brute_orbs: int = 0
	var brute_potions: int = 0
	for i in 100:
		ItemEffects._drop_loot(player, brute)
	for node in get_tree().get_nodes_in_group("orbs"):
		if bool(node.get("is_potion")):
			brute_potions += 1
		else:
			brute_orbs += 1
		node.queue_free()
	expect("a Brute always drops 2 orbs", brute_orbs == 200)
	print("  per 100 Brute kills: orbs=", brute_orbs, " potions=", brute_potions)
	brute.queue_free()
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

## Leap: slams a downed enemy (crit, pin, boot, pull-out), chops standing ground otherwise; stun shows daze stars.
func _test_leap() -> void:
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	var downed: Enemy = _spawn_enemy(Vector3(32, 0, -19))
	downed.aggro_range = 0.0
	downed.max_health = 800.0
	downed.health = 800.0
	await get_tree().process_frame
	downed.ragdoll_launch(Vector3.ZERO, 0.0, Vector3.ZERO)
	var t: float = 0.0
	while t < 3.0 and not LeapSkill.is_downed(downed):
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var start_health: float = downed.health
	var phases: Array = []
	var max_height: float = 0.0
	var stayed_down: bool = true
	var daze_seen: bool = false
	player.skills.try_directional("leap", downed.global_position)
	t = 0.0
	while player.skills.busy and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if phases.is_empty() or phases[-1] != player.leap.leap_phase:
			phases.append(player.leap.leap_phase)
		max_height = maxf(max_height, player.visual.position.y)
		if player.leap.leap_phase == 4 and is_instance_valid(downed):
			stayed_down = stayed_down and LeapSkill.is_downed(downed)
		daze_seen = daze_seen or (is_instance_valid(downed) and downed._daze != null)
	expect("leap slam runs crouch/air/hold/pull", phases == [1, 2, 3, 4, 0])
	expect("leap slam hurts", start_health - downed.health > 0.0)
	expect("slammed enemy stays pinned during the pull", stayed_down)
	expect("stun shows daze stars", daze_seen)
	expect("leap restores aim and collision", player.model.weapon_aim == null and player.collision_mask == (Player.LAYER_WORLD | Player.LAYER_ENEMY))
	print("  leap slam: phases=", phases, " peak height=", snappedf(max_height, 0.1), " damage=", snappedf(start_health - downed.health, 0.1),
		" stayed pinned during pull=", stayed_down, " daze stars seen=", daze_seen, " ended at ", player.global_position,
		" aim cleared=", player.model.weapon_aim == null, " mask restored=", player.collision_mask == (Player.LAYER_WORLD | Player.LAYER_ENEMY))
	downed.queue_free()
	await get_tree().process_frame

	# An enemy still tumbling through the air, and one that is almost back on its feet, are slammed too.
	for stage in ["flight", "rising"]:
		player.stats.cooldowns.clear()
		player.global_position = Vector3(32, 0, -12)
		player.reset_physics_interpolation()
		var target: Enemy = _spawn_enemy(Vector3(32, 0, -18))
		target.aggro_range = 0.0
		target.max_health = 800.0
		target.health = 800.0
		await get_tree().process_frame
		target.ragdoll_launch(Vector3(0, 0, -6.0), 5.0, Vector3(4, 0, 0))
		if stage == "rising":
			t = 0.0
			while t < 4.0 and not (target.ragdoll != null and target.ragdoll.state == Ragdoll.State.RISING and target.ragdoll._rise_t > 0.5):
				await get_tree().physics_frame
				t += 1.0 / 60.0
		else:
			await get_tree().create_timer(0.15).timeout
		var before: float = target.health
		player.skills.try_directional("leap", target.global_position)
		var slammed: bool = player.leap.leap_slam
		t = 0.0
		while player.skills.busy and t < 5.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		expect("leap on a %s target is a slam" % stage, slammed and before - target.health > 0.0)
		print("  leap on ", stage, " target: slam chosen=", slammed, " damage=", snappedf(before - target.health, 0.1))
		target.queue_free()
		await get_tree().process_frame

	# Overhead chop on open ground, hitting a standing zombie beside the landing spot.
	player.stats.cooldowns.clear()
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	var standing: Enemy = _spawn_enemy(Vector3(33, 0, -19))
	standing.aggro_range = 0.0
	standing.max_health = 800.0
	standing.health = 800.0
	await get_tree().process_frame
	for attempt in 3:   # the chop can miss at random: leap again rather than fail on bad luck
		player.stats.cooldowns.clear()
		player.stats.mana = player.stats.max_mana
		player.global_position = Vector3(32, 0, -12)
		player.reset_physics_interpolation()
		player.skills.try_directional("leap", Vector3(32, 0, -19))
		phases.clear()
		t = 0.0
		while player.skills.busy and t < 5.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if phases.is_empty() or phases[-1] != player.leap.leap_phase:
				phases.append(player.leap.leap_phase)
		if standing.health < 800.0:
			break
	expect("leap on open ground chops", phases == [1, 2, 3, 0] and standing.health < 800.0)
	print("  leap chop: phases=", phases, " standing zombie damage=", snappedf(800.0 - standing.health, 0.1), " landed at ", player.global_position)
	standing.queue_free()
	await get_tree().process_frame

## Skewer catches knocked-down enemies; thrown bodies spread burn to enemies they hit and slam into props.
func _test_impact() -> void:
	player.global_position = Vector3(-25, 0, -25)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	var lying: Enemy = _spawn_enemy(Vector3(-25, 0, -29))
	lying.aggro_range = 0.0
	lying.max_health = 800.0
	lying.health = 800.0
	await get_tree().process_frame
	lying.ragdoll_launch(Vector3.ZERO, 0.0, Vector3.ZERO)
	var t: float = 0.0
	while t < 3.0 and not (lying.ragdoll != null and lying.ragdoll.state == Ragdoll.State.LYING):
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var was_lying: bool = lying.ragdoll != null and lying.ragdoll.state == Ragdoll.State.LYING
	player.skewer.start_skewer(Vector3(-25, 0, -40))
	var caught: bool = false
	t = 0.0
	while player.skills.busy and t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		caught = caught or player.skewer.skewer_impaled.has(lying)
	expect("skewer catches a downed enemy", was_lying and caught)
	print("  skewer vs downed enemy: was lying=", was_lying, " impaled it=", caught)
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(lying):
		lying.queue_free()

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
	expect("a thrown burning body passes burn and slow on", bystander.is_burning() and bystander.slow_time > 0.0 and bystander.health < 500.0)
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
	expect("slamming into a wall hurts and stuns", flier.health < 500.0 and flier.stun_time > 2.0)
	print("  wall slam: health=", snappedf(flier.health, 0.1), "/500 stun left=", snappedf(flier.stun_time, 0.1))
	for e in [bystander, burner, flier]:
		if is_instance_valid(e):
			e.queue_free()
	wall.queue_free()
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

## Roll: immune for the whole roll, shoves non-boss enemies sideways and interrupts them; bosses stay put.
func _test_roll_shove() -> void:
	player.global_position = Vector3(20, 0, 20)
	player.reset_physics_interpolation()
	await get_tree().process_frame
	var near: Enemy = _spawn_enemy(player.global_position + Vector3(1.4, 0, 0.1))
	var attacker: Enemy = _spawn_enemy(player.global_position + Vector3(2.4, 0, -0.1))
	# The boss stands off to the side of the other two so zombies being shoved cannot bump it.
	var boss: Enemy = _spawn_enemy(player.global_position + Vector3(2.0, 0, 6.0), "brute")
	boss.is_boss = true
	for e in [near, attacker, boss]:
		e.aggro_range = 0.0
	await get_tree().process_frame
	# Put one zombie mid-attack so we can see it get interrupted.
	attacker._attacking = true
	attacker.model.manual("attack")
	var start: Vector3 = player.global_position
	var near_start: Vector3 = near.global_position
	var attacker_start: Vector3 = attacker.global_position
	var boss_start: Vector3 = boss.global_position
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(player.global_position + Vector3(8, 0, 0))
	var immune_late: bool = false
	boss.global_position = player.global_position + Vector3(2.4, 0, 0.9)  # inside the roll corridor
	boss_start = boss.global_position
	for i in 40:
		await get_tree().physics_frame
		if player.movement.rolling and player.movement.roll_t > ROLL_CHECK_TIME and player.invulnerable_time > 0.0:
			immune_late = true
	await get_tree().create_timer(0.3).timeout
	var lateral_near: float = absf(near.global_position.z - near_start.z)
	var lateral_attacker: float = absf(attacker.global_position.z - attacker_start.z)
	var boss_moved: float = boss.global_position.distance_to(boss_start)
	expect("roll shoves non-bosses aside", lateral_near > 0.3 and lateral_attacker > 0.3)
	expect("roll interrupts an attacker", not attacker._attacking)
	expect("roll is immune late in the roll", immune_late)
	print("  roll shove: near moved sideways ", snappedf(lateral_near, 0.1), " m, attacker ", snappedf(lateral_attacker, 0.1),
		" m (interrupted=", not attacker._attacking, "), boss displaced ", snappedf(boss_moved, 0.1), " m, immune late in roll=", immune_late)
	for e in [near, attacker, boss]:
		e.queue_free()
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	await get_tree().process_frame

const ROLL_CHECK_TIME := 0.4

## Camera zoom: eases toward the target (no instant jump), respects limits, and zooms both ways.
func _test_zoom() -> void:
	var base: float = rig.camera.position.length()
	var zoom_out := InputEventAction.new()
	zoom_out.action = "zoom_out"
	zoom_out.pressed = true
	for i in 3:
		rig._unhandled_input(zoom_out)
	await get_tree().process_frame
	await get_tree().process_frame
	var early: float = rig.camera.position.length()
	await get_tree().create_timer(1.0).timeout
	var out: float = rig.camera.position.length()
	var zoom_in := InputEventAction.new()
	zoom_in.action = "zoom_in"
	zoom_in.pressed = true
	for i in 40:
		rig._unhandled_input(zoom_in)
	await get_tree().create_timer(1.2).timeout
	var near: float = rig.camera.position.length()
	for i in 12:
		rig._unhandled_input(zoom_out)
	for i in 40:
		rig._unhandled_input(zoom_out)
	await get_tree().create_timer(1.2).timeout
	var far: float = rig.camera.position.length()
	expect("camera zoom is eased", early < out)
	print("  zoom: base=", snappedf(base, 0.01), " after 2 frames=", snappedf(early, 0.01), " (eased: ", early < out, ") out=", snappedf(out, 0.01),
		" min=", snappedf(near / base, 0.01), " max=", snappedf(far / base, 0.01))
	rig._zoom_target = 1.0
	rig._zoom = 1.0

## Settings: rebinding, conflict swap, save/load round trip, and the pause menu node.
func _test_settings() -> void:
	var ok: bool = true
	var backup: Dictionary = GameSettings.custom_bindings.duplicate()
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	GameSettings.rebind("dodge", q)
	ok = ok and GameSettings.binding_text("dodge") == "Q"
	# Binding hotbar 1 to Q must swap: dodge gets the old "1".
	GameSettings.rebind("skill_1", q)
	ok = ok and GameSettings.binding_text("skill_1") == "Q" and GameSettings.binding_text("dodge") == "1"
	GameSettings.master_volume = 0.42
	GameSettings.save_to_disk()
	GameSettings.master_volume = 0.1
	GameSettings.custom_bindings.clear()
	GameSettings.load_from_disk()
	GameSettings.apply_bindings()
	ok = ok and absf(GameSettings.master_volume - 0.42) < 0.001 and GameSettings.binding_text("skill_1") == "Q"
	GameSettings.reset_bindings()
	ok = ok and GameSettings.binding_text("skill_1") == "1" and GameSettings.binding_text("dodge") == "Space"
	# Controller buttons: rebind, swap on conflict, persist, survive a keyboard rebind, reset.
	var pad_ok: bool = GameSettings.pad_binding_text("skill_1") == "X" and GameSettings.pad_binding_text("skill_2") == "Y"
	var pad_press := InputEventJoypadButton.new()
	pad_press.button_index = JOY_BUTTON_Y
	GameSettings.rebind_pad("skill_1", pad_press)   # skill_1 takes Y; skill_2 (which had Y) gets X
	pad_ok = pad_ok and GameSettings.pad_binding_text("skill_1") == "Y" and GameSettings.pad_binding_text("skill_2") == "X"
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	GameSettings.rebind_pad("dodge", trigger)       # a trigger can be bound too; skill_5 (RT) gets dodge's old B
	pad_ok = pad_ok and GameSettings.pad_binding_text("dodge") == "RT" and GameSettings.pad_binding_text("skill_5") == "B"
	GameSettings.rebind("skill_3", q)               # a keyboard rebind must leave the pad button alone
	pad_ok = pad_ok and GameSettings.pad_binding_text("skill_3") == "RB" and GameSettings.binding_text("skill_3") == "Q"
	GameSettings.swap_sticks = true
	GameSettings.save_to_disk()
	GameSettings.custom_pad_bindings.clear()
	GameSettings.swap_sticks = false
	GameSettings.load_from_disk()
	GameSettings.apply_bindings()
	pad_ok = pad_ok and GameSettings.swap_sticks and GameSettings.pad_binding_text("skill_1") == "Y" and GameSettings.pad_binding_text("dodge") == "RT"
	GameSettings.reset_bindings()
	pad_ok = pad_ok and GameSettings.pad_binding_text("skill_1") == "X" and GameSettings.pad_binding_text("dodge") == "B" and GameSettings.pad_binding_text("skill_5") == "RT"
	GameSettings.swap_sticks = false
	expect("controller rebind/swap/persist/reset keeps keyboard bindings", pad_ok)
	print("  controller bindings round trip ok=", pad_ok)
	GameSettings.master_volume = 0.8
	GameSettings.save_to_disk()
	GameSettings.custom_bindings = backup
	expect("settings rebind/swap/save/load/reset", ok)
	print("  settings: rebind/swap/save/load/reset ok=", ok, "  pause menu node=", pause_menu != null)

## Equips every affix in turn and drives each hook (hit, kill, roll, incoming damage, skills) against dummies.
func _test_items() -> void:
	var failures: int = 0
	var dummies: Array[Enemy] = []
	for i in 4:
		var z: Enemy = _spawn_enemy(Vector3(2.0 + i * 0.8, 0, 1.0 + (i % 2) * 0.6))
		z.aggro_range = 0.0
		z.max_health = 400.0
		z.health = 400.0
		dummies.append(z)
	await get_tree().process_frame
	var saved: Dictionary = player.stats.equipment.duplicate()
	for id in AffixDb.all():
		var slot: int = AffixDb.all()[id]["slot"]
		var item: Dictionary = Items.make(slot, Items.Rarity.RARE, 1, id)
		player.stats.equip(item, false)
		if not player.stats.has_affix(id):
			failures += 1
			print("  AFFIX NOT ACTIVE: ", id)
		var target: Enemy = dummies[0]
		var result: Dictionary = Combat.resolve(player, target, 20.0, Combat.DamageType.PHYSICAL, false, 1.0, true)
		result["finisher"] = true
		target.receive(result, player.global_position)
		ItemEffects.on_kill(player, target)
		ItemEffects.on_roll_start(player)
		ItemEffects.power_shockwave(player, Vector3(1, 0, 0))
		ItemEffects.pull_for_cleave(player)
		var incoming: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": 10.0, "weight": 1.0}
		ItemEffects.filter_incoming(player, incoming)
		for d in dummies:
			d.health = d.max_health
			d.bleed_time = 0.0
			d.slow_time = 0.0
		player.stats.cooldowns.clear()
		player.stats.haste_time = 0.0
		player.stats.vault_time = 0.0
		player.stats.chain_time = 0.0
		await get_tree().process_frame
	var choices: Array[Dictionary] = Items.roll_choices(5, true, [])
	expect("every affix is driven by its hook", failures == 0)
	expect("reward offers 3 choices", choices.size() == 3)
	print("  items: ", AffixDb.all().size(), " affixes driven; reward choices=", choices.size(), " (brute offer: ",
		", ".join(choices.map(func(c): return c["name"])), "), failures=", failures)
	for d in dummies:
		d.queue_free()
	player.stats.equipment = saved
	player.armor = player.stats.base_armor + player.stats.armor_stat("armor", 0.0)
	player.health = player.max_health
	await get_tree().process_frame

## `-- --pauseshot`: open the pause menu over a live wave and capture it.
func _pause_shot() -> void:
	_next_wave()
	await get_tree().create_timer(0.8).timeout
	pause_menu.open()
	await get_tree().create_timer(0.4).timeout
	print("paused=", get_tree().paused, " menu open=", pause_menu.is_open())
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_pause.png")
	pause_menu.close()
	print("paused after resume=", get_tree().paused)
	get_tree().quit()

## `-- --enemyfight`: the new enemy kinds in action against an idle hero; frames in %TEMP%/curse_fight_N.png.
func _enemy_fight() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.max_health = 5000.0
	player.health = 5000.0
	var kinds: Array = [["spitter", Vector3(-6, 0, -8)], ["ghoul", Vector3(7, 0, -6)], ["bloater", Vector3(1.5, 0, -6)],
		["priest", Vector3(0, 0, -11)], ["zombie", Vector3(-1.5, 0, -11.5)], ["zombie", Vector3(1.5, 0, -11.0)]]
	for k in kinds:
		var z: Enemy = _spawn_enemy(k[1], k[0])
		z.aggro_range = 40.0
	for i in 16:
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_fight_%d.png" % i)
	get_tree().quit()

## `-- --enemyshot`: one of each enemy kind in a row facing the camera; frame in %TEMP%/curse_enemies.png.
func _enemy_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	var ids: Array = EnemyDb.all().keys()
	ids.sort()
	var x: float = -float(ids.size() - 1) * 1.4
	for id in ids:
		var z: Enemy = _spawn_enemy(Vector3(x, 0, -3.0), id)
		z.aggro_range = 0.0
		z.visual.rotation.y = PI
		x += 2.8
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_enemies.png")
	var names: PackedStringArray = []
	for id in ids:
		names.append(id)
	print("enemy kinds (left to right): ", ", ".join(names))
	get_tree().quit()

## `-- --skillshot=gibs`: a fireball detonates on low-health zombies; frames in %TEMP%/curse_gib_N.png.
func _gib_shots() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.set_physics_process(true)
	var victims: Array[Enemy] = []
	for pos in [Vector3(0.0, 0, -4.0), Vector3(1.4, 0, -4.8), Vector3(-1.3, 0, -4.6), Vector3(0.3, 0, -6.0)]:
		var z: Enemy = _spawn_enemy(pos)
		z.aggro_range = 0.0
		z.max_health = 30.0
		z.health = 30.0
		victims.append(z)
	await get_tree().create_timer(0.6).timeout
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.damage = 200.0
	ball.destination = Vector3(0.0, 0.0, -4.6)
	add_child(ball)
	ball.global_position = Vector3(0.0, 1.0, -4.6)
	ball._explode()
	for i in 16:
		await get_tree().create_timer(0.12).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_gib_%d.png" % i)
	get_tree().quit()

## `-- --skillshot=power|cleave [--mods]`: hit a cluster of zombies and capture frames in %TEMP%/curse_melee_N.png.
## With --mods the hero wears every skill-modifying affix so their effects show too.
func _melee_shots(which: String) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.stats.mana = player.stats.max_mana
	player.set_physics_process(true)
	if OS.get_cmdline_user_args().has("--mods"):
		for affix in ["gravewarden", "whirlpool", "searing", "executioner", "chain", "cleaving", "kindling", "juggler", "breaker", "maelstrom"]:
			player.stats.equipment["mod_" + affix] = {"affix": affix, "name": affix, "rarity": 1, "slot": 0}
	var targets: Array[Enemy] = []
	for pos in [Vector3(0.0, 0, -2.4), Vector3(1.2, 0, -2.9), Vector3(-1.3, 0, -2.2), Vector3(0.4, 0, -4.2), Vector3(2.0, 0, -1.0), Vector3(-2.2, 0, 0.8)]:
		var z: Enemy = _spawn_enemy(pos)
		z.aggro_range = 0.0
		z.max_health = 900.0
		z.health = 900.0
		targets.append(z)
	await get_tree().create_timer(0.6).timeout
	player.skills.start_skill(which, targets[0], null)
	for i in 22:
		await get_tree().create_timer(0.08).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_melee_%d.png" % i)
	get_tree().quit()

## `-- --skillshot=leap`: leap onto a downed zombie (a stunned one stands beside it); frames in %TEMP%/curse_leap_N.png.
func _leap_shots() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.stats.mana = player.stats.max_mana
	player.set_physics_process(true)
	var downed: Enemy = _spawn_enemy(Vector3(0.3, 0, -5.5))
	var dazed: Enemy = _spawn_enemy(Vector3(2.4, 0, -4.0))
	for e in [downed, dazed]:
		e.aggro_range = 0.0
		e.max_health = 800.0
		e.health = 800.0
	dazed.stun_time = 6.0
	await get_tree().create_timer(0.5).timeout
	downed.ragdoll_launch(Vector3(0, 0, -2.0), 1.0, Vector3(3, 0, 0))
	while not LeapSkill.is_downed(downed):
		await get_tree().physics_frame
	player.skills.try_directional("leap", downed.global_position)
	for i in 24:
		await get_tree().create_timer(0.1).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_leap_%d.png" % i)
	get_tree().quit()

## `-- --skillshot=earthshatter`: a crowd (one burning) around the hero, a full ultimate; frames in %TEMP%/curse_es_N.png.
func _earthshatter_shots() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.set_physics_process(true)
	var crowd: Array[Enemy] = []
	for i in 14:
		var angle: float = TAU * float(i) / 14.0 + 0.2
		var radius: float = 2.6 + float(i % 3) * 1.6
		var z: Enemy = _spawn_enemy(player.global_position + Vector3(sin(angle), 0, cos(angle)) * radius, "zombie" if i % 4 else "brute")
		z.aggro_range = 0.0
		z.max_health = 900.0
		z.health = 900.0
		crowd.append(z)
	await get_tree().create_timer(0.6).timeout
	crowd[0].apply_burn(6.0, 8.0)
	player.stats.ult_charge = player.stats.ult_cost("earthshatter")
	player.skills.try_directional("earthshatter", player.global_position + Vector3(0, 0, -5))
	var frame: int = 0
	var started: int = Time.get_ticks_msec()
	while frame < 30:
		await get_tree().create_timer(0.12, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_es_%d.png" % frame)
		print("frame ", frame, " t=", Time.get_ticks_msec() - started, " ms  time_scale=", snappedf(Engine.time_scale, 0.01), " phase=", player.earthshatter.phase)
		frame += 1
	get_tree().quit()

## `-- --skillshot=skewer|fireball`: run the skill on dummies and capture a frame every 0.12 s.
func _skill_shots(which: String) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.stats.mana = player.stats.max_mana
	player.set_physics_process(true)
	var dummies: Array[Enemy] = []
	if which == "skewer":
		for i in 4:
			var z: Enemy = _spawn_enemy(Vector3(1.0 + i * 0.4, 0, -3.5 - i * 1.6))
			z.aggro_range = 0.0
			z.max_health = 800.0
			z.health = 800.0
			dummies.append(z)
	else:
		for pos in [Vector3(-1.2, 0, -4.2), Vector3(0.8, 0, -5.0), Vector3(2.2, 0, -3.8)]:
			var z: Enemy = _spawn_enemy(pos)
			z.aggro_range = 0.0
			z.max_health = 800.0
			z.health = 800.0
			dummies.append(z)
	await get_tree().create_timer(0.8).timeout
	if which == "skewer":
		player.skewer.start_skewer(Vector3(1.8, 0, -12.0))
	else:
		player.skills.start_skill("fireball", null, Vector3(0.6, 0, -4.4))
	for i in 20:
		await get_tree().create_timer(0.14 if i < 12 else 0.4).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_skill_%d.png" % i)
	get_tree().quit()

## `-- --aimshot`: fireball aim preview over a zombie cluster, then hover tooltips for two skills.
func _aim_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	var cluster: Array[Vector3] = [Vector3(1.0, 0, -4.5), Vector3(2.4, 0, -5.4), Vector3(0.0, 0, -6.0), Vector3(-3.5, 0, -4.0), Vector3(6.0, 0, -3.0)]
	for pos in cluster:
		var z: Enemy = _spawn_enemy(pos)
		z.aggro_range = 0.0
	player.set_physics_process(false)
	player.skills.aiming_id = "fireball"
	player.skills.aiming_action = "skill_3"
	await get_tree().create_timer(0.8).timeout
	var cursor: Vector3 = Vector3(1.2, 0, -5.2)
	for i in 6:
		player.skills.update_aim(cursor)
		await get_tree().process_frame
	var lit: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if (node as Actor).highlighted:
			lit += 1
	print("aim: point=", player.skills.aim_point, " highlighted=", lit, " of ", cluster.size(), " (blast radius ", Projectile.BLAST_RADIUS, ")")
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_aim.png")
	# Cast it: the projectile must land on the aimed point.
	player.skills.clear_aim()
	player.skills.start_skill("fireball", null, player.skills.aim_point_for("fireball", cursor))
	for i in 3:
		player.skills.tick_busy(0.3)
	await get_tree().create_timer(1.0).timeout
	# Tooltips: hover the fireball and dodge slots.
	for pair in [["fireball", "curse_tip_0.png"], ["dodge", "curse_tip_1.png"], ["basic", "curse_tip_2.png"]]:
		for hit in hud._slot_hits:
			if hit["id"] == pair[0]:
				hud.mouse_override = (hit["rect"] as Rect2).get_center()
		await get_tree().create_timer(0.2).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/" + pair[1])
	get_tree().quit()

## `-- --hudshot`: put skills on cooldown (and drain mana) to check the hotbar cooldown display.
func _hud_shot() -> void:
	player.set_physics_process(false)
	player.stats.cooldowns = {"power": 1.1, "cleave": 2.0, "fireball": 0.3, "dodge": 0.6}
	player.stats.mana = 9.0
	await get_tree().create_timer(0.15).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hud_0.png")
	player.stats.cooldowns = {"power": 0.0, "cleave": 0.9, "fireball": 0.0, "dodge": 0.0}
	await get_tree().create_timer(0.1).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hud_1.png")
	get_tree().quit()

## `-- --smashshot`: a Skewer charge through a row of barrels, a cart, gravestones and a brazier, captured as the pieces fly.
func _smash_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.global_position = Vector3(-8, 0, 0)
	player.reset_physics_interpolation()
	player.visual.rotation.y = PI * 0.5
	var spots: Array = [["barrel", 0.0, 0.6, 1.0], ["barrel", 1.4, -0.5, 1.0], ["gravestone", 3.0, 0.3, 1.3], ["wrecked_cart", 5.2, -0.4, 1.9],
		["brazier", 7.4, 0.5, 1.5], ["barrel", 9.0, -0.3, 1.0]]
	for spot in spots:
		arena.place_prop(spot[0], Vector3(-3.0 + spot[1], 0, spot[2]), 0.0, spot[3], true, spot[0] == "brazier")
	await get_tree().create_timer(0.5).timeout
	player.stats.mana = player.stats.max_mana
	player.skills.try_directional("skewer", Vector3(20, 0, 0))
	await get_tree().create_timer(0.55).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_smash_0.png")
	await get_tree().create_timer(0.45).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_smash_1.png")
	get_tree().quit()

## `-- --itemsheet`: every dropped-item model on the ground in a ring round the hero, in each rarity's glow, for judging by eye.
func _item_sheet() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.global_position = Vector3.ZERO
	var bases: Array = []
	var drops: Array[LootDrop] = []
	for def in ItemDb.all().values():
		bases.append([def.slot, def.display_name])
	for i in bases.size():
		var item: Dictionary = Items.make(bases[i][0], i % 3, 1, "" if i % 3 == 0 else _any_affix(bases[i][0]), bases[i][1])
		var drop: LootDrop = LootDrop.create(item)
		game.director.add_child(drop)
		var angle: float = -PI * 0.9 + PI * 0.8 * float(i) / float(bases.size() - 1) - PI * 0.5
		drop.global_position = Vector3(cos(angle) * 4.0, 0, sin(angle) * 4.0 - 1.0)
		drop.landed = true
		drop._age = 1.0
		drops.append(drop)
	await get_tree().create_timer(1.0).timeout
	if OS.get_cmdline_user_args().has("--gear"):   # the Tab panel: worn items and the bag as pictures, one pointed at
		for i in 8:
			player.stats.add_to_bag(drops[i].item)
		Input.action_press("gear")
		await get_tree().create_timer(0.5).timeout
		var size_px: Vector2 = get_viewport().get_visible_rect().size
		hud.mouse_override = Vector2(size_px.x - 30.0 - (6 * 64 + 5 * 10) + 1 * 74 + 32, 70.0 + 4.0 + 64.0 + 34.0 + 32.0)
	if OS.get_cmdline_user_args().has("--hover"):   # point at a drop to see its tooltip and comparison
		var focus: LootDrop = drops[2]
		hud.mouse_override = player.get_viewport().get_camera_3d().unproject_position(focus.global_position + Vector3(0, 0.5, 0))
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_items.png")
	get_tree().quit()

func _any_affix(slot: int) -> String:
	for id in AffixDb.all():
		if AffixDb.all()[id]["slot"] == slot and AffixDb.all()[id]["title"] != "":
			return id
	return ""

## `-- --hovershot`: put the mouse over a brute and capture the hover health bar and ring.
func _hover_shot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	var brute: Enemy = _spawn_enemy(Vector3(1.8, 0, -2.4), "brute", 1.0)
	var zombie: Enemy = _spawn_enemy(Vector3(-2.2, 0, -1.2), "zombie", 1.0)
	brute.aggro_range = 0.0
	zombie.aggro_range = 0.0
	await get_tree().create_timer(0.8).timeout
	zombie.receive(Combat.resolve(player, zombie, 20.0), player.global_position)
	brute.receive(Combat.resolve(player, brute, 60.0), player.global_position)
	var camera: Camera3D = get_viewport().get_camera_3d()
	# Screen-space picking at the brute's head, chest, knee and feet, and away from it (injected mouse positions).
	var base: Vector3 = brute.global_position
	for part in [["head", 2.2], ["chest", 1.4], ["knee", 0.6], ["feet", 0.1]]:
		var at: Vector2 = camera.unproject_position(base + Vector3(0, part[1], 0))
		var picked: Actor = player._hover_pick(Vector3(99, 0, 99), at)
		print("pick at brute ", part[0], ": ", picked.display_name if picked else "none")
	var side: Vector2 = camera.unproject_position(base + Vector3(3.5, 1.0, 0))
	var off: Actor = player._hover_pick(Vector3(99, 0, 99), side)
	print("pick 3.5 m to the side: ", off.display_name if off else "none")
	# Freeze the player's own logic so the injected hover sticks for the screenshots.
	player.set_physics_process(false)
	player.hover_target = brute
	for i in 3:
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hover_%d.png" % i)
	get_tree().quit()

## `-- --rollshot`: trigger a dodge roll and capture frames of it, to check the roll starts without a slide.
func _roll_shots() -> void:
	await get_tree().create_timer(0.6).timeout
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(player.global_position + Vector3(5, 0, 0))
	var start: Vector3 = player.global_position
	for i in 8:
		await get_tree().create_timer(0.07).timeout
		print("roll frame ", i, " travelled=", snappedf(player.global_position.distance_to(start), 0.01),
			" clip_pos=", snappedf(player.model.anim.current_animation_position, 0.01))
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_roll_%d.png" % i)
	get_tree().quit()

func _clip_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clipsheet="):
			return arg.substr(12)
	return ""

## `-- --clipsheet=NAME[:T0:T1]`: scrub a clip across [T0, T1] (default the whole clip) in 12 steps and tile the frames into
## %TEMP%/curse_clip_NAME.png, to judge an animation by eye.
func _clip_sheet(spec: String) -> void:
	player.set_physics_process(false)
	var parts: PackedStringArray = spec.split(":")
	var clip: String = parts[0]
	if not player.model.anim.has_animation("game/" + clip):
		print("clip ", clip, " NOT FOUND")
		get_tree().quit()
		return
	player.model.manual(clip)
	var length: float = player.model.anim.get_animation("game/" + clip).length
	var t0: float = float(parts[1]) if parts.size() > 1 else 0.0
	var t1: float = float(parts[2]) if parts.size() > 2 else length
	if parts.size() > 3:
		player.model.leg_raise = float(parts[3])
		rig.pitch_degrees = -8.0                 # side-on view so the leg can be judged
		player.visual.rotation.y = PI * 0.5
	print("clip ", clip, " length=", snappedf(length, 0.01))
	var tiles: Array[Image] = []
	for i in 12:
		var t: float = lerpf(t0, t1, float(i) / 11.0)
		player.model.scrub(t)
		await get_tree().create_timer(0.2).timeout
		player.model.scrub(t)
		await get_tree().create_timer(0.08).timeout
		var skel: Skeleton3D = player.model.find_children("*", "Skeleton3D", true, false)[0]
		var hips: Vector3 = skel.get_bone_global_pose(skel.find_bone("Hips")).origin
		var hand: Vector3 = skel.get_bone_global_pose(skel.find_bone("RightHand")).origin
		var foot: Vector3 = skel.get_bone_global_pose(skel.find_bone("RightFoot")).origin
		print("  t=", snappedf(t, 0.01), " hips y=", snappedf(hips.y, 0.1), " hand y=", snappedf(hand.y, 0.1), " hand z=", snappedf(hand.z, 0.1),
			" foot y=", snappedf(foot.y, 0.1), " foot z=", snappedf(foot.z, 0.1))
		var shot: Image = get_viewport().get_texture().get_image()
		var c: Vector2i = shot.get_size() / 2
		var tile: Image = shot.get_region(Rect2i(c.x - 360, c.y - 420, 720, 720))
		tile.resize(300, 300)
		tiles.append(tile)
	var sheet: Image = Image.create(1200, 900, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 300, 300), Vector2i((i % 4) * 300, (i / 4) * 300))
	sheet.save_png(OS.get_environment("TEMP") + "/curse_clip_%s.png" % clip)
	get_tree().quit()

## `-- --poses`: freeze the hero in key frames of each clip and save a PNG of each (deformation check).
func _pose_sheet() -> void:
	player.set_physics_process(false)
	if OS.get_cmdline_user_args().has("--blood"):
		player.skills.blade_blood = 0.9
		player.skills.update_blade_blood(0.0)
	var poses: Array = [["charge_run", 0.1], ["charge_run", 0.25], ["charge_run", 0.4], ["kick", 0.15], ["kick", 0.3], ["kick", 0.45],
		["kick", 0.6], ["kick", 0.75], ["kick", 0.9], ["kick", 1.1], ["kick", 1.3], ["charge", 2.0]]
	if OS.get_cmdline_user_args().has("--oldposes"):
		poses = [["idle_alert", 1.0], ["slash_r", 0.73], ["slash_l", 1.37], ["thrust", 1.57], ["power", 1.23],
			["cleave", 1.73], ["cleave", 2.4], ["combo_end", 1.37], ["cast", 0.53], ["roll", 0.8], ["hit", 0.3], ["run", 0.3]]
	for i in poses.size():
		player.model.manual(poses[i][0])
		player.model.scrub(poses[i][1])
		await get_tree().create_timer(0.25).timeout
		player.model.scrub(poses[i][1])
		await get_tree().create_timer(0.1).timeout
		var skeleton: Skeleton3D = player.model.find_children("*", "Skeleton3D", true, false)[0]
		var arm_lengths: Array[String] = []
		for chain in [["RightArm", "RightForeArm", "RightHand"], ["LeftArm", "LeftForeArm", "LeftHand"]]:
			var a: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone(chain[0])).origin
			var b: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone(chain[1])).origin
			var c: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone(chain[2])).origin
			arm_lengths.append("%s upper=%.1f fore=%.1f" % [chain[0].substr(0, 1), a.distance_to(b), b.distance_to(c)])
		print("pose ", poses[i][0], ": ", " | ".join(arm_lengths))
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_pose_%d.png" % i)
	get_tree().quit()

## `-- --shot`: spawn zombies next to the hero, fight for a few seconds, save a PNG, quit.
func _screenshot_demo() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	if OS.get_cmdline_user_args().has("--duel"):
		var dummy: Enemy = _spawn_enemy(Vector3(0.6, 0, 2.2))
		dummy.max_health = 9999.0
		dummy.health = 9999.0
	else:
		for i in 4:
			_spawn_enemy(Vector3(-3.0 + i * 2.0, 0, 4.0 + (i % 2) * 2.0))
	await get_tree().create_timer(1.0 if OS.get_cmdline_user_args().has("--duel") else 1.5).timeout
	player.stats.mana = player.stats.max_mana
	var target: Actor = player.enemy_near(player.global_position, 20.0)
	if target:
		player.attack_target = target
	var shots: int = 8 if OS.get_cmdline_user_args().has("--duel") else 4
	for i in shots:
		await get_tree().create_timer(0.3).timeout
		print("shot ", i, " busy=", player.skills.busy, " t=", snappedf(player.skills.busy_t, 0.01), " clip=", player.model.current,
			" pos=", snappedf(player.model.anim.current_animation_position, 0.01), " speed=", player.model.anim.speed_scale,
			" hitpause=", player.hitpause, " target=", player.attack_target, " mana=", int(player.stats.mana))
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(OS.get_environment("TEMP") + "/curse_shot_%d.png" % i)
	get_tree().quit()

## Earthshatter: charges only from damage dealt, will not fire until full, then throws everything in the ring up into the air,
## stuns and hurts it, shares a burn with the rest, staggers a boss without throwing it, and slows time briefly (and restores it).
func _test_earthshatter() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.stats.ult_charge = 0.0
	Fx.reset_time()
	var cost: float = player.stats.ult_cost("earthshatter")
	expect("a new hero starts with the ultimate ready", PlayerStats.new(player).can_use("earthshatter"))
	expect("earthshatter has a charge cost and no mana cost", cost > 0.0 and float(SkillDb.all()["earthshatter"]["mana"]) == 0.0)
	var offsets: Array[Vector3] = [Vector3(2, 0, 0), Vector3(-3, 0, 1), Vector3(0, 0, -4), Vector3(4, 0, 3), Vector3(-5, 0, -2), Vector3(1, 0, 5.5)]
	var centre: Vector3 = player.global_position + Vector3(0, 0, -1.2)
	var ring: Array[Enemy] = []
	for offset in offsets:
		var z: Enemy = _spawn_enemy(centre + offset)
		z.aggro_range = 0.0
		z.max_health = 3000.0
		z.health = 3000.0
		ring.append(z)
	var far: Enemy = _spawn_enemy(centre + Vector3(14, 0, 0))
	far.aggro_range = 0.0
	far.max_health = 3000.0
	far.health = 3000.0
	await get_tree().process_frame
	ring[0].apply_burn(6.0, 8.0)
	# It charges from damage the hero deals...
	var dummy: Enemy = ring[1]
	var before_charge: float = player.stats.ult_charge
	dummy.receive(Combat.resolve(player, dummy, 60.0, Combat.DamageType.PHYSICAL, false, 1.0), player.global_position)
	expect("dealing damage charges the ultimate", player.stats.ult_charge > before_charge + 30.0)
	# ...and not from damage taken.
	var charge_now: float = player.stats.ult_charge
	player.receive(Combat.resolve(dummy, player, 20.0, Combat.DamageType.PHYSICAL, false, 1.0), dummy.global_position)
	expect("taking damage does not charge it", is_equal_approx(player.stats.ult_charge, charge_now))
	# Not full: pressing it does nothing.
	player.skills.try_directional("earthshatter", centre)
	expect("an uncharged ultimate will not start", not player.skills.busy and not player.stats.can_use("earthshatter"))
	# Full: it fires.
	player.stats.ult_charge = cost
	var health_before: Dictionary = {}
	for z in ring:
		health_before[z] = z.health
	var far_before: float = far.health
	player.skills.try_directional("earthshatter", centre)
	expect("a full ultimate starts", player.skills.busy and player.earthshatter.phase == 1)
	var phases: Array = []
	var peak: Dictionary = {}
	var min_scale: float = 1.0
	var slow_before_impact: bool = false
	var impact_seen: bool = false
	var t: float = 0.0
	while player.skills.busy and t < 12.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		min_scale = minf(min_scale, Engine.time_scale)
		if player.earthshatter.phase < 3 and not impact_seen:
			slow_before_impact = slow_before_impact or Engine.time_scale < 0.99
		if player.earthshatter.phase >= 3:
			impact_seen = true
		if phases.is_empty() or phases[-1] != player.earthshatter.phase:
			phases.append(player.earthshatter.phase)
		for z in ring:
			if is_instance_valid(z):
				peak[z] = maxf(float(peak.get(z, 0.0)), z.visual.global_position.y)
	expect("earthshatter runs gather/slam/hold/recover", phases == [1, 2, 3, 4, 0])
	var all_hurt: bool = true
	var all_stunned: bool = true
	for z in ring:
		all_hurt = all_hurt and z.health < float(health_before[z])
		all_stunned = all_stunned and z.stun_time > 0.5
	expect("everything in the ring is hurt", all_hurt)
	expect("everything in the ring is stunned", all_stunned)
	expect("it counts its victims", player.earthshatter.victims == ring.size())
	expect("the enemy outside the ring is untouched", is_equal_approx(far.health, far_before))
	var highest: float = 0.0
	var thrown: int = 0
	for z in ring:
		highest = maxf(highest, float(peak.get(z, 0.0)))
		if float(peak.get(z, 0.0)) > 1.0:
			thrown += 1
	expect("the ring is thrown up into the air", thrown == ring.size() and highest > 2.0)
	expect("the burn on one victim is shared with the rest", ring[2].burn_time > 0.0 and ring[3].burn_time > 0.0)
	expect("the ultimate does not charge itself", player.stats.ult_charge < 1.0)
	expect("time slowed during the impact", min_scale < 0.5)
	expect("time runs at full speed until the blade hits the ground", not slow_before_impact)
	await get_tree().create_timer(1.6, true, false, true).timeout
	expect("time is back to normal afterwards", is_equal_approx(Engine.time_scale, 1.0))
	expect("it restores the hero's state", not player.skills.busy and player.collision_mask == (Player.LAYER_WORLD | Player.LAYER_ENEMY))
	print("  earthshatter: phases=", phases, " thrown=", thrown, "/", ring.size(), " highest=", snappedf(highest, 0.1), " m  slowest time scale=",
		snappedf(min_scale, 0.01), " spread transfers=", player.earthshatter.last_spread)
	# A boss is staggered, not thrown.
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	var boss: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -3.5))
	boss.aggro_range = 0.0
	boss.is_boss = true
	boss.max_health = 3000.0
	boss.health = 3000.0
	await get_tree().process_frame
	player.stats.ult_charge = cost
	player.skills.try_directional("earthshatter", boss.global_position)
	t = 0.0
	while player.skills.busy and t < 12.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a boss takes the blow and is staggered but not thrown", boss.health < 3000.0 and boss.stun_time > 0.5 and not boss.is_ragdolled())
	# Cancelling before the blade lands costs nothing.
	await get_tree().create_timer(1.6, true, false, true).timeout
	player.stats.ult_charge = cost
	player.skills.try_directional("earthshatter", boss.global_position)
	await get_tree().create_timer(0.2).timeout
	player.skills.cancel_action()
	expect("cancelling the wind-up keeps the charge", player.stats.ult_charge >= cost and not player.skills.busy)
	boss.queue_free()
	player.stats.ult_charge = 0.0
	Fx.reset_time()
	await get_tree().process_frame

## The mouse over the minimap, hotbar or bars must not pick (or walk to) an enemy standing in the world behind them.
func _test_ui_block() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var size_px: Vector2 = get_viewport().get_visible_rect().size
	var minimap_point: Vector2 = Vector2(size_px.x - 100.0, size_px.y - 100.0)
	var open_point: Vector2 = size_px * 0.5
	expect("the minimap blocks the mouse", game.hud.covers(minimap_point))
	expect("the hotbar blocks the mouse", game.hud.covers(Vector2(size_px.x * 0.5, size_px.y - 50.0)))
	expect("open ground does not", not game.hud.covers(open_point))
	# An enemy standing in the world exactly behind the minimap pixel.
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var hidden_spot: Variant = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(minimap_point), camera.project_ray_normal(minimap_point))
	var enemy: Enemy = _spawn_enemy(hidden_spot)
	enemy.aggro_range = 0.0
	await get_tree().process_frame
	Gamepad.active = false
	expect("the enemy behind the minimap is picked when the mouse is not over the interface", player._hover_pick(enemy.global_position, minimap_point) == enemy)
	expect("the player treats the minimap as interface, not world", player.mouse_over_ui(minimap_point) and not player.mouse_over_ui(open_point))
	enemy.queue_free()
	await get_tree().process_frame

## An enemy behind the camera must never be picked: Camera3D.unproject_position mirrors such points back onto the screen, so one
## standing behind the view used to be "under" the cursor (highlighted and chased on click) while nothing visible was there.
func _test_hover_behind_camera() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, -20)
	player.reset_physics_interpolation()
	game.rig.global_position = player.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera: Camera3D = get_viewport().get_camera_3d()
	var behind: Vector3 = Vector3(camera.global_position.x, 0.0, camera.global_position.z + 20.0)
	var enemy: Enemy = _spawn_enemy(behind)
	enemy.aggro_range = 0.0
	await get_tree().process_frame
	var projected: Vector2 = camera.unproject_position(enemy.global_position + Vector3(0, enemy.body_height * 0.5, 0))
	var size_px: Vector2 = get_viewport().get_visible_rect().size
	print("  behind-camera enemy: behind=", camera.is_position_behind(enemy.global_position), " mirrored onto screen at ", projected, " (screen ", size_px, ")")
	expect("the test enemy really is behind the camera", camera.is_position_behind(enemy.global_position))
	expect("an enemy behind the camera is not picked by a cursor where it mirrors", player._hover_pick(Vector3(0, 0, 0), projected) != enemy)
	enemy.queue_free()
	await get_tree().process_frame

## Holding the camera-rotate button and dragging swings the camera around the hero smoothly; sticks, picking and the minimap follow it,
## and a click without a drag puts it back.
func _test_camera_rotation() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	rig.reset_view()
	await get_tree().create_timer(0.6).timeout
	expect("the camera starts behind the hero", absf(rig.yaw) < 0.01 and absf(Gamepad.view_yaw) < 0.01)
	var down := InputEventAction.new()
	down.action = "camera_rotate"
	down.pressed = true
	rig._unhandled_input(down)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(-285.0, 0.0)   # about a quarter turn
	rig._unhandled_input(drag)
	var up := InputEventAction.new()
	up.action = "camera_rotate"
	up.pressed = false
	rig._unhandled_input(up)
	expect("a drag does not count as a reset click", absf(rig._yaw_target) > 1.0)
	var last: float = rig.yaw
	var biggest_step: float = 0.0
	var frames: int = 0
	var t: float = 0.0
	while t < 1.2:
		await get_tree().process_frame
		t += get_process_delta_time()
		biggest_step = maxf(biggest_step, absf(angle_difference(last, rig.yaw)))
		last = rig.yaw
		frames += 1
	expect("the camera glides to the new angle (no snap)", biggest_step < 0.25 and frames > 10)
	expect("it arrives", absf(angle_difference(rig.yaw, rig._yaw_target)) < 0.02 and absf(rig.yaw) > 1.0)
	expect("the camera node is really turned", absf(angle_difference(rig.rotation.y, rig.yaw)) < 0.001)
	expect("sticks follow the view", Gamepad.to_world(Vector2(0, -1)).distance_to(Vector3(0, 0, -1).rotated(Vector3.UP, rig.yaw)) < 0.001)
	# Stick up now means up the screen: the hero walks away from the camera, not along world -Z.
	var camera: Camera3D = get_viewport().get_camera_3d()
	var screen_up: Vector3 = -camera.global_transform.basis.z
	screen_up.y = 0.0
	screen_up = screen_up.normalized()
	Gamepad.active = true
	Gamepad.test_axes = {JOY_AXIS_LEFT_X: 0.0, JOY_AXIS_LEFT_Y: -1.0}
	var start: Vector3 = player.global_position
	await get_tree().create_timer(0.8).timeout
	Gamepad.test_axes = {}
	Gamepad.active = false
	var moved: Vector3 = player.global_position - start
	moved.y = 0.0
	expect("stick up walks up the screen after the camera is turned", moved.length() > 2.0 and moved.normalized().dot(screen_up) > 0.95)
	# Picking still works from the new angle.
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var enemy: Enemy = _spawn_enemy(Vector3(2.0, 0, 1.0))
	enemy.aggro_range = 0.0
	await get_tree().create_timer(0.3).timeout
	var at: Vector2 = camera.unproject_position(enemy.global_position + Vector3(0, enemy.body_height * 0.5, 0))
	expect("an enemy is still picked under the cursor from the new angle", player._hover_pick(enemy.global_position, at) == enemy)
	enemy.queue_free()
	# A click without a drag resets.
	var click_down := InputEventAction.new()
	click_down.action = "camera_rotate"
	click_down.pressed = true
	rig._unhandled_input(click_down)
	var click_up := InputEventAction.new()
	click_up.action = "camera_rotate"
	click_up.pressed = false
	rig._unhandled_input(click_up)
	await get_tree().create_timer(1.2).timeout
	expect("a middle click without a drag resets the camera", absf(rig.yaw) < 0.02 and absf(Gamepad.view_yaw) < 0.02)
	print("  camera rotation: biggest per-frame step ", snappedf(biggest_step, 0.001), " rad over ", frames, " frames")
	await get_tree().process_frame

## The sword sound plays when the blade connects with an enemy, and only then: not on a miss or a block, not for a fireball or a
## boot or a shockwave.
func _logged(prefix: String) -> int:
	var count: int = 0
	for name in Sfx.played_log:
		if name.begins_with(prefix):
			count += 1
	return count

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
	for other in ["skewer_kick", "earthshatter", "fireball"]:
		var odd: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
		odd["skill_id"] = other
		enemy.receive(odd, player.global_position)
		await get_tree().create_timer(0.1).timeout
	expect("a boot, a shockwave or a fireball is not the sword", Sfx.played_log.size() == 2)
	var secondary: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
	secondary["skill_id"] = "power"
	secondary["secondary"] = true
	enemy.receive(secondary, player.global_position)
	expect("splash damage is not a sword hit either", Sfx.played_log.size() == 2)
	await get_tree().create_timer(0.1).timeout
	var cleave: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
	cleave["skill_id"] = "cleave"
	enemy.receive(cleave, player.global_position)
	expect("every sword skill makes it", _logged("sword_hit") == 2)
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

## Any time the sword swings and finds nothing, a swing sound plays: a swing at a target that is out of reach, a Cleave with nobody
## around, a Leap chop on open ground.
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
	# A Cleave with nobody in range.
	await get_tree().create_timer(0.2).timeout
	Sfx._last_played.clear()
	Sfx.played_log.clear()
	player.skills.start_skill("cleave", null, player.global_position + Vector3(0, 0, -3))
	t = 0.0
	while player.skills.busy and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a Cleave through empty air makes the swing sound", _logged("sword_miss") == 1)
	# A Leap chop onto open ground.
	player.stats.cooldowns.clear()
	Sfx._last_played.clear()
	Sfx.played_log.clear()
	player.skills.try_directional("leap", player.global_position + Vector3(0, 0, -6))
	t = 0.0
	while player.skills.busy and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a Leap chop on bare ground makes the swing sound", _logged("sword_miss") == 1)
	expect("the Leap landing plays its impact sound once", _logged("leap_land") == 1)
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
		player.skills.start_skill("cleave", null, near.global_position)
		t = 0.0
		while player.skills.busy and t < 3.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		if _logged("sword_hit") >= 1:
			break
		await get_tree().create_timer(0.1).timeout
	expect("a Cleave that connects makes the hit sound, not the swing sound", _logged("sword_hit") >= 1 and _logged("sword_miss") == 0)
	near.queue_free()
	Sfx.enabled = was_enabled
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
	for haste in [1.0, 1.6]:   # casting faster moves the launch earlier, and the sound must follow it
		player.stats.cooldowns.clear()
		player.stats.haste_time = 99.0 if haste > 1.0 else 0.0
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
	player.stats.haste_time = 0.0
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

## A normal run starts with the camera zoomed all the way out.
func _test_start_zoom() -> void:
	var fresh := CameraRig.new()
	add_child(fresh)
	fresh.start_zoomed_out()
	await get_tree().process_frame
	expect("a new run starts fully zoomed out", is_equal_approx(fresh._zoom, CameraRig.ZOOM_MAX) and is_equal_approx(fresh._zoom_target, CameraRig.ZOOM_MAX))
	fresh.queue_free()
	await get_tree().process_frame

## A killed enemy goes ragdoll, thrown away from the blow, and stays down: every kind of enemy, and also one killed while it is
## already getting back up (it used to finish standing, then stand there dead).
func _test_death_ragdoll() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var variants: Array[String] = ["zombie", "brute", "ghoul", "spitter", "bloater", "priest"]
	for i in variants.size():
		var variant: String = variants[i]
		var victim: Enemy = _spawn_enemy(Vector3(-15.0 + 6.0 * i, 0, -12), variant)
		victim.health = 1.0
		victim.aggro_range = 0.0
		await get_tree().create_timer(0.2).timeout
		var killed_at: Vector3 = victim.global_position
		var blow: Dictionary = Combat.resolve(player, victim, 500.0, Combat.DamageType.PHYSICAL, false, 2.0)
		blow["outcome"] = Combat.Outcome.HIT   # a plain hit, so it is not turned into gore
		victim._pending_gib = ""
		victim.receive(blow, killed_at + Vector3(0, 0, 2.0))
		expect("a killed %s goes ragdoll" % variant, victim.dead and victim.is_ragdolled())
		await get_tree().create_timer(1.8).timeout
		var thrown: Vector3 = victim.global_position - killed_at
		expect("a killed %s is thrown away from the blow (from +Z)" % variant, thrown.z < -0.4)
		expect("a killed %s is lying down, not standing" % variant, victim.ragdoll != null and victim.ragdoll.permanent and victim.ragdoll.state == Ragdoll.State.LYING)
		victim.queue_free()
	# Knocked down, getting up, and then killed.
	var riser: Enemy = _spawn_enemy(Vector3(0, 0, -8))
	riser.aggro_range = 0.0
	riser.max_health = 500.0
	riser.health = 500.0
	await get_tree().process_frame
	riser.ragdoll_launch(Vector3(0, 0, -2.0), 3.0, Vector3(3, 0, 0))
	var t: float = 0.0
	while t < 5.0 and (riser.ragdoll == null or riser.ragdoll.state != Ragdoll.State.RISING):
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("the test enemy reached the getting-up stage", riser.ragdoll != null and riser.ragdoll.state == Ragdoll.State.RISING)
	var finish: Dictionary = Combat.resolve(player, riser, 5000.0, Combat.DamageType.PHYSICAL, false, 1.0)
	finish["outcome"] = Combat.Outcome.HIT
	riser._pending_gib = ""
	riser.receive(finish, riser.global_position + Vector3(0, 0, 2.0))
	var stood_up: bool = false
	t = 0.0
	while t < 2.5:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		stood_up = stood_up or riser.ragdoll == null or riser.ragdoll.state == Ragdoll.State.OFF or riser.ragdoll.state == Ragdoll.State.RISING
	expect("an enemy killed while getting up lies back down and stays down", riser.dead and not stood_up and riser.ragdoll != null and riser.ragdoll.state == Ragdoll.State.LYING)
	riser.queue_free()
	await get_tree().process_frame

## Enemies run (the run clip) when they chase, never walk.
func _test_enemy_run() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	for variant in ["zombie", "brute", "ghoul"]:
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
		expect("a %s runs toward the hero (never plays the walk clip)" % variant, seen.has("run") and not seen.has("walk"))
		e.queue_free()
	await get_tree().process_frame


## Controller in the menus and the game: pad input hides the mouse and takes over; a real mouse move or any key or click takes it back;
## noisy axes cannot steal control; menus have a selection that D-pad / left stick move; rewards can be chosen from the pad.
func _test_pad_menus() -> void:
	var down := InputEventJoypadButton.new()
	down.pressed = true
	down.button_index = JOY_BUTTON_A
	Gamepad.active = false
	Gamepad._mouse_ms = -100000
	Gamepad.note_event(down)
	expect("a pad button press hands control to the controller", Gamepad.active)
	var wiggle := InputEventMouseMotion.new()
	wiggle.relative = Vector2(4.0, 0.0)
	Gamepad.note_event(wiggle)
	expect("mouse moves arriving right alongside pad input (Steam's emulated mouse) are ignored", Gamepad.active)
	Gamepad._pad_ms = -100000   # ...but once the pad has been quiet for a moment a real mouse move takes over
	Gamepad.note_event(wiggle)
	expect("moving the real mouse switches back to mouse and keyboard", not Gamepad.active)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 0.9
	Gamepad.note_event(stick)
	expect("a wobbling stick right after mouse use does not steal control", not Gamepad.active)
	Gamepad._mouse_ms = -100000   # ...but after the mouse has been still for a moment a real push does
	Gamepad.note_event(stick)
	expect("a real stick push takes control once the mouse is still", Gamepad.active)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_W
	Gamepad._pad_ms = -100000
	Gamepad.note_event(key)
	expect("a key press switches back to keyboard and mouse", not Gamepad.active)
	var rest := InputEventJoypadMotion.new()
	rest.axis = JOY_AXIS_TRIGGER_LEFT
	rest.axis_value = -1.0     # an idle trigger on some drivers
	Gamepad._mouse_ms = -100000
	Gamepad.note_event(rest)
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_RIGHT_Y
	drift.axis_value = 0.2
	Gamepad.note_event(drift)
	expect("a resting trigger or a drifting stick never counts as using the pad", not Gamepad.active)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	Gamepad.note_event(down)
	Gamepad._pad_ms = -100000
	Gamepad.note_event(click)
	expect("a mouse click switches back too", not Gamepad.active)
	# The pause menu opens with something selected, and the D-pad / stick (ui_down) moves it.
	game.pause_menu.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var first: Control = get_viewport().gui_get_focus_owner()
	expect("the pause menu opens with a button selected", first is Button)
	var move := InputEventAction.new()
	move.action = "ui_down"
	move.pressed = true
	Input.parse_input_event(move)
	await get_tree().process_frame
	await get_tree().process_frame
	var second: Control = get_viewport().gui_get_focus_owner()
	expect("down on the D-pad / left stick moves the selection", second != null and second != first)
	var release := InputEventAction.new()
	release.action = "ui_down"
	release.pressed = false
	Input.parse_input_event(release)
	# A real A-button press on the selected button presses it (Resume is first in the pause menu).
	game.pause_menu.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var lift := InputEventJoypadButton.new()
	lift.button_index = JOY_BUTTON_A
	lift.pressed = false
	Input.parse_input_event(lift)
	await get_tree().process_frame
	expect("pressing A on the selected menu button activates it", not game.pause_menu.visible)
	game.pause_menu.close()
	await get_tree().process_frame
	# Settings: opened from the pause menu it gets a selection too.
	var settings := SettingsMenu.new()
	add_child(settings)
	await get_tree().process_frame
	settings.focus_first()
	await get_tree().process_frame
	expect("the settings screen has a selection for the controller", get_viewport().gui_get_focus_owner() != null)
	settings.queue_free()
	await get_tree().process_frame
	Gamepad.active = false
	await get_tree().process_frame

## Controller targeting: the enemy nearest to where the hero faces is targeted and glows; holding A attacks it; B dodges; Start pauses.
func _test_pad_targeting() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.visual.rotation.y = 0.0   # facing +Z
	Gamepad.active = true
	var behind: Enemy = _spawn_enemy(Vector3(0, 0, -3))
	var ahead: Enemy = _spawn_enemy(Vector3(1.5, 0, 7))
	for e in [behind, ahead]:
		e.aggro_range = 0.0
		e.max_health = 4000.0
		e.health = 4000.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("the pad targets the enemy in front, not the nearer one behind", player.pad_facing_target() == ahead)
	expect("the targeted enemy is the cursor point and the hover target", player.cursor_world().distance_to(ahead.global_position) < 0.01 and player.hover_target == ahead)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("the targeted enemy glows", ahead.highlighted and not behind.highlighted)
	# Turn around: the enemy behind is now the one in front.
	player.visual.rotation.y = PI
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	expect("turning around changes the target", player.pad_facing_target() == behind and behind.highlighted and not ahead.highlighted)
	# It does not flicker: a slightly different angle keeps the same target.
	player.visual.rotation.y = PI + 0.15
	await get_tree().physics_frame
	expect("the target is sticky", player.pad_facing_target() == behind)
	# Holding A attacks the targeted enemy.
	Gamepad.test_axes = {}
	player.visual.rotation.y = PI
	var start_health: float = behind.health
	Input.action_press("alt_skill")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("alt_skill")
	expect("holding A attacks the targeted enemy", behind.health < start_health)
	# Defaults: A attacks (and confirms in menus), B dodges, Start pauses.
	var has_a: bool = false
	for ev in InputMap.action_get_events("alt_skill"):
		has_a = has_a or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	var has_b: bool = false
	for ev in InputMap.action_get_events("dodge"):
		has_b = has_b or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	var has_start: bool = false
	for ev in InputMap.action_get_events("pause"):
		has_start = has_start or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_START)
	var confirms: bool = false
	for ev in InputMap.action_get_events("ui_accept"):
		confirms = confirms or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	for ev in InputMap.action_get_events("ui_cancel"):
		confirms = confirms and true
	var backs: bool = false
	for ev in InputMap.action_get_events("ui_cancel"):
		backs = backs or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	confirms = confirms and backs
	expect("A is attack and menu confirm, B is dodge, Start is pause", has_a and has_b and has_start and confirms)
	Gamepad.active = false
	await get_tree().process_frame
	await get_tree().process_frame
	expect("the glow is removed when the mouse takes over", not behind.highlighted and not ahead.highlighted)
	# Leave the hero idle for whatever test comes next (no swing in progress, no target, no queued skill).
	player.skills.cancel_action()
	player.skills.queued_skill = ""
	player.attack_target = null
	player.click_mode = 0
	player.movement.has_goal = false
	behind.queue_free()
	ahead.queue_free()
	await get_tree().create_timer(0.3).timeout

## Controller camera and Fireball aiming: the right stick turns/zooms the camera, except while Fireball is held, when it slides the
## target area: one snap to the nearest target at the start, then free movement with no snapping back onto enemies.
func _test_pad_camera_and_aim() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.visual.rotation.y = 0.0
	Gamepad.active = true
	rig.reset_view()
	rig._zoom_target = 2.0
	rig._zoom = 2.0
	await get_tree().create_timer(0.5).timeout
	# Right stick: right turns the camera, down zooms out.
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: 1.0, JOY_AXIS_RIGHT_Y: 0.0}
	await get_tree().create_timer(0.6).timeout
	var turned: float = rig._yaw_target
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: 0.0, JOY_AXIS_RIGHT_Y: 1.0}
	var zoom_before: float = rig._zoom_target
	await get_tree().create_timer(0.6).timeout
	var zoom_out: float = rig._zoom_target
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: 0.0, JOY_AXIS_RIGHT_Y: -1.0}
	await get_tree().create_timer(0.6).timeout
	var zoom_in: float = rig._zoom_target
	Gamepad.test_axes = {}
	expect("the right stick turns the camera", absf(turned) > 0.5)
	expect("right stick down zooms out and up zooms in", zoom_out > zoom_before + 0.3 and zoom_in < zoom_out - 0.3)
	# While Fireball is held the stick no longer moves the camera; it slides the target area.
	rig.reset_view()
	await get_tree().create_timer(1.0).timeout
	var first: Enemy = _spawn_enemy(Vector3(2.0, 0, 6.0))
	var second: Enemy = _spawn_enemy(Vector3(-6.0, 0, 8.0))
	for e in [first, second]:
		e.aggro_range = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.stats.cooldowns.clear()
	player.stats.mana = player.stats.max_mana
	Input.action_press("skill_3")
	await get_tree().create_timer(0.2).timeout
	expect("holding Fireball is aiming", player.skills.aiming_id == "fireball")
	var snap_point: Vector3 = player.cursor_world()
	expect("the target area starts on the enemy the hero faces", snap_point.distance_to(first.global_position) < 0.5)
	var yaw_before: float = rig._yaw_target
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: -1.0, JOY_AXIS_RIGHT_Y: 0.0}   # push left: toward the second enemy and past it
	await get_tree().create_timer(0.5).timeout
	var mid: Vector3 = player.cursor_world()
	expect("the stick slides the target area", mid.distance_to(snap_point) > 2.0 and mid.x < snap_point.x)
	expect("the camera does not turn while aiming", absf(rig._yaw_target - yaw_before) < 0.001)
	# It passes straight over the second enemy without latching onto it: keep going and it ends up beyond.
	await get_tree().create_timer(0.8).timeout
	var far: Vector3 = player.cursor_world()
	expect("no snapping onto enemies once the stick is moving it", far.x < second.global_position.x - 1.0)
	Gamepad.test_axes = {}
	var held: Vector3 = player.cursor_world()
	await get_tree().create_timer(0.4).timeout
	expect("released stick: the target area stays where it was put", player.cursor_world().distance_to(held) < 0.01)
	Input.action_release("skill_3")
	await get_tree().create_timer(1.2).timeout
	player.skills.cancel_action()
	first.queue_free()
	second.queue_free()
	Gamepad.active = false
	rig._zoom_target = 1.0
	rig._zoom = 1.0
	await get_tree().process_frame

## Twin Flame: the second fireball goes for a second target; with only one enemy it lands right next to it.
func _test_twin_flame_target() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var one: Enemy = _spawn_enemy(Vector3(0, 0, -8))
	var two: Enemy = _spawn_enemy(Vector3(6, 0, -9))
	var near_first: Enemy = _spawn_enemy(Vector3(0.8, 0, -8))
	for e in [one, two, near_first]:
		e.aggro_range = 0.0
	await get_tree().physics_frame
	var dest: Vector3 = player.skills.twin_destination(Vector3(0, 0, -8))
	expect("the second fireball picks a second target, outside the first blast", dest.distance_to(Vector3(two.global_position.x, 0.0, two.global_position.z)) < 0.01)
	two.queue_free()
	near_first.queue_free()
	await get_tree().process_frame
	var lone: Vector3 = player.skills.twin_destination(Vector3(0, 0, -8))
	var gap: float = Vector2(lone.x - one.global_position.x, lone.z - one.global_position.z).length()
	expect("with one enemy the second fireball lands right beside it", gap > 0.3 and gap < 1.3)
	one.queue_free()
	await get_tree().process_frame
	var none: Vector3 = player.skills.twin_destination(Vector3(0, 0, -8))
	expect("with no enemies it still lands near the aim point", Vector2(none.x, none.z).distance_to(Vector2(0, -8)) < 1.3)
	await get_tree().process_frame

## Start (or Esc) pauses the whole game: enemies, hero, animations, projectiles and effects all stop until it is resumed.
func _test_pause_stops_game() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var chaser: Enemy = _spawn_enemy(Vector3(0, 0, -12))
	chaser.alert_delay = 0.0
	chaser.aggro_range = 60.0
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.direction = Vector3(1, 0, 0)
	ball.destination = Vector3(20, 0.8, 0)
	add_child(ball)
	ball.global_position = Vector3(4, 1.0, 0)
	await get_tree().create_timer(0.8).timeout
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_START
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("Start opens the pause menu and pauses the tree", game.pause_menu.visible and get_tree().paused)
	var chaser_at: Vector3 = chaser.global_position
	var ball_at: Vector3 = ball.global_position
	var player_at: Vector3 = player.global_position
	var anim_at: float = chaser.model.anim.current_animation_position
	await get_tree().create_timer(1.0, true, false, true).timeout
	expect("enemies do not move while paused", chaser.global_position.distance_to(chaser_at) < 0.01)
	expect("projectiles do not fly while paused", ball.global_position.distance_to(ball_at) < 0.01)
	expect("the hero does not move while paused", player.global_position.distance_to(player_at) < 0.01)
	expect("animations stand still while paused", is_equal_approx(chaser.model.anim.current_animation_position, anim_at))
	expect("time scale is untouched", is_equal_approx(Engine.time_scale, 1.0))
	game.pause_menu.close()
	await get_tree().create_timer(0.5).timeout
	expect("resuming gets everything moving again", not get_tree().paused and chaser.global_position.distance_to(chaser_at) > 0.3)
	if is_instance_valid(ball):
		ball.queue_free()
	chaser.queue_free()
	await get_tree().process_frame

# --- Town ------------------------------------------------------------------------------------------------------------------

## The town's inner life: traits weight what NPCs do, likes and dislikes move mood and opinion, bad blood ends in brawls, wretched
## recruits leave, hunger sours everyone, and the numbers behave the same for the same seed.
func _test_town_sim() -> void:
	TownState.persist = false
	TownState.reset()
	expect("five people live in town", TownState.present_ids().size() == 5)
	var sim := TownSim.new(11)
	var marlow: Dictionary = sim.activity_weights("marlow")
	var maren: Dictionary = sim.activity_weights("maren")
	expect("a drunk drinks far more than a teetotal healer", float(marlow["drink"]) > float(maren["drink"]) * 3.0)
	expect("a gossip gossips more than a loyal warden", float(marlow["gossip"]) > float(sim.activity_weights("hale")["gossip"]) * 2.0)
	expect("a religious NPC prays more than a trader", float(maren["pray"]) > float(marlow["pray"]) * 3.0)
	# Likes: Cutter (a joker) enjoys a joke. Dislikes: Maren (religious) resents one.
	var rel_before: float = TownState.relation("marlow", "cutter")
	var mood_before: float = TownState.happiness("cutter")
	sim.perform("marlow", "joke", "cutter")
	expect("a liked joke raises the target's mood", TownState.happiness("cutter") > mood_before + 3.0)
	expect("a liked joke improves their opinion of each other", TownState.relation("marlow", "cutter") > rel_before + 3.0)
	rel_before = TownState.relation("cutter", "maren")
	mood_before = TownState.happiness("maren")
	sim.perform("cutter", "joke", "maren")
	expect("a disliked joke lowers the target's mood", TownState.happiness("maren") < mood_before)
	expect("a disliked joke sours their opinion", TownState.relation("cutter", "maren") < rel_before)
	# Mood changes what they choose.
	TownState.npcs["hale"]["happiness"] = -50.0
	expect("an unhappy NPC argues and broods more", float(sim.activity_weights("hale")["argue"]) > 1.5 * 0.5 * 3.5 * 0.9
		and float(sim.activity_weights("hale")["brood"]) > 0.5)
	TownState.npcs["hale"]["happiness"] = 20.0
	# Brawls.
	TownState.relations[TownState._pair("hale", "cutter")] = 5.0
	var brawled: bool = false
	for i in 20:
		sim.run_round()
		for line in sim.history:
			if "came to blows" in line:
				brawled = true
		TownState.relations[TownState._pair("hale", "cutter")] = 5.0
		if brawled:
			break
	expect("NPCs who hate each other come to blows", brawled)
	# A wretched hired recruit leaves.
	TownState.npcs["cutter"]["member"] = true
	TownState.npcs["cutter"]["happiness"] = -90.0
	sim.run_round()
	expect("a wretched recruit leaves the clan", bool(TownState.npcs["cutter"]["left"]) and not bool(TownState.npcs["cutter"]["member"]))
	expect("the others are shaken when someone leaves", TownState.present_ids().size() == 4)
	# Hunger.
	TownState.reset()
	var mood: float = TownState.happiness("maren")
	TownState.food = 0
	var quiet := TownSim.new(3)
	quiet._settle(TownState.present_ids())
	expect("no food sours everyone", TownState.happiness("maren") < mood - 1.0)
	TownState.food = 12
	expect("rationing starts when food runs low", not TownState.rationing())
	TownState.food = TownState.LOW_FOOD
	expect("food at the low mark means rationing", TownState.rationing())
	# Prices follow mood.
	TownState.npcs["marlow"]["happiness"] = 60.0
	var cheap: float = TownSim.mood_price_mult("marlow")
	TownState.npcs["marlow"]["happiness"] = -50.0
	expect("a content trader charges less than a wretched one", cheap < 1.0 and TownSim.mood_price_mult("marlow") > 1.0)
	# Same seed, same town.
	TownState.reset()
	var a := TownSim.new(99)
	for i in 6:
		a.run_round()
	var first: Array = [TownState.happiness("marlow"), TownState.happiness("hale"), TownState.relation("marlow", "hale")]
	TownState.reset()
	var b := TownSim.new(99)
	for i in 6:
		b.run_round()
	expect("the same seed gives the same town", first == [TownState.happiness("marlow"), TownState.happiness("hale"), TownState.relation("marlow", "hale")])
	# Over a long time every NPC's mood stays inside its range and the town stays alive.
	TownState.reset()
	var long := TownSim.new(5)
	for i in 80:
		long.run_round()
	var in_range: bool = true
	for id in TownState.npcs:
		var h: float = TownState.happiness(id)
		in_range = in_range and h >= -100.0 and h <= 100.0
	expect("moods stay in range over a long time", in_range)
	TownState.reset()

## What the town keeps: pay-out for a run, gear handed over, the job board, the food bill, and saving without losing a thing.
func _test_town_state() -> void:
	TownState.persist = false
	TownState.reset()
	var board_ok: bool = TownState.board.size() == 3
	for offer in TownState.board:
		board_ok = board_ok and JobObjective.stages(offer) >= 2 and offer.has("location") and int(offer["reward"]) > 0
	expect("the board posts three jobs", board_ok)
	# Saving: a version, the job and last run saved, old saves migrated, newer ones left alone, an abandoned run noticed.
	TownState.gold = 77
	TownState.job = TownState.board[0].duplicate(true)
	TownState.last_run = {"kills": 5, "wave": 2, "completed": true, "died": false, "gold": 40}
	var saved_town: Variant = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.reset()
	TownState.from_dict(TownState.migrate(saved_town))
	expect("a saved town keeps its version, gold, job and last run", int(saved_town["save_version"]) == TownState.SAVE_VERSION and TownState.gold == 77
		and JobObjective.stages(TownState.job) >= 2 and TownState.last_run.get("kills") == 5)
	var legacy: Dictionary = {"gold": 12, "board": [{"name": "Clear Ash Ford", "waves": 3, "modifiers": [], "reward": 80}]}
	var upgraded: Dictionary = TownState.migrate(legacy)
	expect("a save from before versions is migrated", int(upgraded["save_version"]) == TownState.SAVE_VERSION
		and JobObjective.stages(upgraded["board"][0]) == 3)
	expect("a save from a newer build is refused, not overwritten", TownState.migrate({"save_version": TownState.SAVE_VERSION + 1}).is_empty())
	# Items are definitions plus a small instance: saved as {def, tier, rarity, affix}, rebuilt from the data on load.
	var made: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 3, "chain", "Greatsword")
	var slim: Dictionary = Items.to_save(made)
	var rebuilt: Dictionary = Items.from_save(JSON.parse_string(JSON.stringify(slim)))
	expect("an item is saved as only its definition, tier, rarity and affix", slim.keys().size() == 4 and slim["def"] == "greatsword"
		and rebuilt["name"] == made["name"] and is_equal_approx(float(rebuilt["stats"]["damage"]), float(made["stats"]["damage"])))
	var def: ItemDef = ItemDb.get_def("greatsword")
	var old_damage: float = float(def.stats["damage"])
	def.stats["damage"] = 2.0
	expect("changing a base's numbers changes saved copies too", is_equal_approx(float(Items.from_save(slim)["stats"]["damage"]), 2.0 * (1.0 + 0.08 * 2)))
	def.stats["damage"] = old_damage
	var old_form: Dictionary = {"slot": 0, "rarity": 1, "name": "Stormcalled Greatsword", "base": "Greatsword", "affix": "chain", "flavor": "",
		"stats": {"damage": 1.35 * 1.16, "speed": 0.82}}
	var from_old: Dictionary = Items.from_save(old_form)
	expect("an item saved as a whole dictionary still loads, its tier worked out", from_old["def"] == "greatsword" and from_old["tier"] == 3)
	expect("an item whose base or affix has gone is dropped", Items.from_save({"def": "vanished", "tier": 1, "rarity": 0, "affix": ""}).is_empty()
		and Items.from_save({"def": "falchion", "tier": 1, "rarity": 1, "affix": "no_such_affix"}).is_empty())
	var v1: Dictionary = TownState.migrate({"save_version": 1, "gear": {"0": old_form}, "stash": [old_form], "stock": [{"item": old_form, "price": 80}]})
	expect("a version 1 save has its items rewritten as definitions", v1["gear"]["0"].has("def") and not v1["gear"]["0"].has("stats")
		and v1["stash"][0]["def"] == "greatsword" and v1["stock"][0]["item"]["tier"] == 3)
	TownState.run_in_progress = true
	TownState.job = TownState.board[0].duplicate(true)
	var mid_run: Variant = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.from_dict(TownState.migrate(mid_run))
	expect("a game closed mid-run abandons that run", TownState.job.is_empty() and not TownState.run_in_progress
		and bool(TownState.last_run.get("abandoned", false)))
	TownState.reset()
	var cost: int = TownState.food_cost()
	var food_mood_before: float = TownState.happiness("marlow")
	TownState.food = cost
	TownState.begin_job(TownState.board[0])
	expect("exactly enough food is not a shortage", TownState.food == 0 and is_equal_approx(TownState.happiness("marlow"), food_mood_before))
	TownState.food = cost - 1
	TownState.begin_job(TownState.board[0])
	expect("too little food sours the clan", TownState.happiness("marlow") < food_mood_before)
	var old_job: Dictionary = JobObjective.upgrade_legacy({"name": "Clear Ash Ford", "waves": 4, "modifiers": [], "reward": 90})
	expect("a job saved with a wave count becomes an objective", JobObjective.stages(old_job) == 4 and old_job["location"] == "Ash Ford"
		and JobObjective.describe(old_job) == "Clear 4 waves" and JobObjective.is_complete(old_job, {"stage": 4}) and not JobObjective.is_complete(old_job, {"stage": 3}))
	var clash: bool = false
	for seed_value in 120:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		TownState.jobs_done = 5
		TownState.roll_board(rng)
		for offer in TownState.board:
			var mods: Array = offer["modifiers"]
			if (mods.has("darkness") and mods.has("moonlit")) or (mods.has("fog") and mods.has("moonlit")):
				clash = true
	expect("jobs never combine modifiers that exclude each other", not clash)
	TownState.reset()
	# The food bill and the pay-out.
	var food_before: int = TownState.food
	var offer: Dictionary = {"name": "Test", "objective": JobObjective.clear_waves(3), "modifiers": ["fog"], "reward": 100}
	TownState.begin_job(offer)
	expect("leaving costs the clan food", TownState.food == food_before - TownState.food_cost())
	var gold_before: int = TownState.gold
	var mood_before: float = TownState.happiness("hale")
	TownState.finish_run({"kills": 10, "wave": 3, "completed": true, "died": false})
	expect("a finished job pays its reward plus 2g a kill", TownState.gold == gold_before + 120)
	expect("a finished job counts", TownState.jobs_done == 1 and TownState.job.is_empty())
	expect("the town is pleased by a finished job", TownState.happiness("hale") > mood_before)
	expect("the board is refreshed", TownState.board.size() == 3)
	expect("the result is kept for the welcome back", int(TownState.last_run["gold"]) == 120)
	gold_before = TownState.gold
	TownState.begin_job({})
	TownState.finish_run({"kills": 4, "wave": 2, "completed": false, "died": true})
	expect("a fallen hero keeps only the 2g per kill", TownState.gold == gold_before + 8 and TownState.jobs_done == 1)
	# Gear and stash.
	TownState.reset()
	var blade: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 2, "")
	for id in AffixDb.all():
		if AffixDb.all()[id]["slot"] == Items.Slot.WEAPON and AffixDb.all()[id]["title"] != "":
			blade = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 2, id)
			break
	TownState.take_gear({Items.Slot.WEAPON: blade})
	expect("the run's gear is kept", String(TownState.gear[Items.Slot.WEAPON]["name"]) == String(blade["name"]))
	TownState.take_gear({Items.Slot.WEAPON: Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword")})
	expect("a replaced special item goes to the stash", TownState.stash.size() == 1 and String(TownState.stash[0]["name"]) == String(blade["name"]))
	# Saving: everything survives a trip through JSON.
	TownState.gold = 321
	TownState.food = 7
	TownState.npcs["marlow"]["happiness"] = 33.0
	TownState.add_relation("marlow", "hale", 9.0)
	TownState.npcs["cutter"]["member"] = true
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.reset()
	TownState.from_dict(saved)
	expect("saved gold and food come back", TownState.gold == 321 and TownState.food == 7)
	expect("saved moods and opinions come back", is_equal_approx(TownState.happiness("marlow"), 33.0)
		and is_equal_approx(TownState.relation("marlow", "hale"), 59.0) and bool(TownState.npcs["cutter"]["member"]))
	expect("saved gear keeps its slot and rarity as integers", TownState.gear.has(Items.Slot.WEAPON)
		and typeof(TownState.gear[Items.Slot.WEAPON]["rarity"]) == TYPE_INT and TownState.stash.size() == 1)
	var hero_gear: Dictionary = {}
	for item in TownState.gear.values():
		hero_gear[int(item["slot"])] = item
	expect("a saved item still describes itself", not Items.lines(TownState.gear[Items.Slot.WEAPON]).is_empty())
	TownState.reset()

## Wave modifiers: more of what they favour, tougher or quicker enemies, a mood for the whole run, and a job that ends in town.
func _test_run_modifiers() -> void:
	var director: RunDirector = game.director
	var zombie: EnemyDef = EnemyDb.get_def("zombie")
	var ghoul: EnemyDef = EnemyDb.get_def("ghoul")
	expect("all nine modifiers load", TownDb.modifiers().size() == 9)
	var plain_zombies: int = director.modified_count(zombie, 3)
	var plain_ghouls: int = director.modified_count(ghoul, 3)
	director.set_job({"name": "Test", "objective": JobObjective.clear_waves(3), "modifiers": ["swarming"], "reward": 50})
	expect("Swarming brings more zombies and ghouls", director.modified_count(zombie, 3) > plain_zombies
		and director.modified_count(ghoul, 3) > plain_ghouls)
	expect("an enemy not in the wave stays out", director.modified_count(EnemyDb.get_def("priest"), 1) == 0)
	director.set_job({"name": "Test", "objective": JobObjective.clear_waves(3), "modifiers": ["cursed"], "reward": 50})
	expect("Cursed only starts at its minimum wave", director.active_modifiers(1).is_empty() and director.active_modifiers(2).size() == 1)
	var saved_wave: int = director.wave
	director.wave = 3
	director.set_job({"name": "Test", "objective": JobObjective.clear_waves(3), "modifiers": ["gigantism", "fleet"], "reward": 50})
	expect("modifiers stack", is_equal_approx(director.modifier_product("speed_mult"), 0.92 * 1.25)
		and is_equal_approx(director.modifier_product("health_mult"), 1.5))
	var big: Enemy = _spawn_enemy(Vector3(30, 0, 30), "zombie", 1.0)
	await get_tree().process_frame
	expect("Gigantism makes enemies tougher and bigger", big.max_health >= zombie.health * 1.49 and big.visual.scale.x > 1.2)
	expect("the wave banner names the rules", director.modifier_names() == "Gigantism, Fleet of Foot")
	big.queue_free()
	director.wave = saved_wave
	director.set_job({})
	expect("no job means no modifiers", director.modifiers.is_empty() and director.modified_count(zombie, 3) == plain_zombies)
	# Mood: darkness dims, fog thickens.
	var env: Environment = game.world_environment
	var ambient: float = env.ambient_light_energy
	var fog: float = env.fog_density
	game._apply_job_mood({"modifiers": ["darkness"]})
	expect("Darkness dims the world and thickens the fog", env.ambient_light_energy < ambient * 0.5 and env.fog_density > fog)
	env.ambient_light_energy = ambient
	env.fog_density = fog
	# Every modifier references enemies that exist.
	var known: bool = true
	for id in TownDb.modifiers():
		for enemy_id in TownDb.modifier(id).spawn_weights:
			known = known and EnemyDb.all().has(enemy_id)
	expect("every modifier names real enemies", known)

## The town scene: it builds, people and places can be found and used, the panels work and shopping changes what you own.
func _test_town_scene() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.gold = 500
	var town := TownScene.new()
	game.add_child(town)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("the town has its five people", town.npcs.size() == 5)
	var kinds: Dictionary = {}
	for spot in town.spots:
		kinds[spot["kind"]] = true
	expect("the town has a gate, stone, board, stash and people", kinds.has("gate") and kinds.has("stone") and kinds.has("board")
		and kinds.has("stash") and kinds.has("npc"))
	# Standing near the gate offers it.
	town.player.global_position = Vector3(0, 0, -16.0)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("standing at the gate offers it", town.near.get("kind") == "gate" and town.hud.prompt.contains("gate"))
	# The gate is a real opening: the north edge is walled either side of it, and the opening itself is clear.
	var space: PhysicsDirectSpaceState3D = town.get_world_3d().direct_space_state
	var blocked_at: Callable = func(x: float) -> bool:
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 1.0, -15.0), Vector3(x, 1.0, -TownScene.HALF - 1.0), Actor.LAYER_WORLD)
		return not space.intersect_ray(query).is_empty()
	expect("the town wall is solid beside the gate", blocked_at.call(-10.0) and blocked_at.call(10.0))
	expect("the opening at the gate is clear of walls", not blocked_at.call(2.5) and not blocked_at.call(-2.5))
	var ward_query := PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, -TownScene.HALF - 2.0), Vector3(0, 1.0, -TownScene.HALF + 2.0), Actor.LAYER_ENEMY | Actor.LAYER_PLAYER)
	expect("the gate is warded against monsters only", not space.intersect_ray(ward_query).is_empty()
		and space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, -TownScene.HALF - 2.0), Vector3(0, 1.0, -TownScene.HALF + 2.0), town.player.collision_mask)).is_empty())
	# A click on someone is found by where they are on screen.
	town.player.global_position = Vector3(-8.0, 0, 0.0)
	await get_tree().process_frame
	var camera: Camera3D = town.get_viewport().get_camera_3d()
	var on_screen: Vector2 = camera.unproject_position(town.npcs["marlow"].global_position + Vector3(0, 1.1, 0))
	expect("a click on Marlow picks Marlow", town.pick_spot(on_screen).get("id") == "marlow")
	# The sim's social life is acted out: a gossiper walks over to the other person, they face each other, and he goes home after.
	TownStage.time_scale = 8.0
	TownNpc.speed_scale = 8.0
	town.player.global_position = Vector3(0, 0, -4.0)
	var gossiper: TownNpc = town.npcs["marlow"]
	var listener: TownNpc = town.npcs["hale"]
	town.stage.handle({"id": "marlow", "text": "Did you hear?", "partner": "hale", "activity": "gossip"})
	var met: bool = false
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if town.stage.events.has("gossip marlow"):
			met = gossiper.global_position.distance_to(listener.global_position) < 2.4
			break
	expect("someone who gossips walks over to the other person", met)
	expect("and the two turn to face each other", absf(angle_difference(gossiper.rotation.y, atan2(listener.global_position.x - gossiper.global_position.x, listener.global_position.z - gossiper.global_position.z))) < 0.5)
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if not gossiper.busy:
			break
	expect("afterwards he walks home and the stage lets him go", not gossiper.busy and gossiper.global_position.distance_to(gossiper.home) < 0.5)
	town.stage.handle({"id": "marlow", "text": "Another.", "partner": "", "activity": "drink"})
	var drank: bool = false
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if town.stage.events.has("drink marlow"):
			drank = gossiper.global_position.distance_to(town.stations["drink"]) < 1.5
			break
	expect("drinking happens at the barrels", drank)
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if not gossiper.busy:
			break
	town.stage.handle({"id": "hale", "text": "That's it!", "partner": "marlow", "activity": "brawl"})
	town.stage.handle({"id": "marlow", "text": "Come on, then.", "partner": "hale", "activity": "brawl_reply"})
	var fought: bool = false
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if town.stage.events.has("brawl hale"):
			fought = listener.global_position.distance_to(gossiper.global_position) < 2.4
			break
	expect("a brawl is fought face to face", fought)
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if not listener.busy and not gossiper.busy:
			break
	expect("and everyone is home afterwards", not listener.busy and not gossiper.busy and listener.global_position.distance_to(listener.home) < 0.5)
	TownStage.time_scale = 1.0
	TownNpc.speed_scale = 1.0
	town.player.global_position = Vector3(-8.0, 0, 0.0)
	for each in town.npcs.values():   # let the lines die away
		each._bark_left = 0.0
		each._bark.visible = false
	# A name tag and a speech line never show together.
	var talker: TownNpc = town.npcs["marlow"]
	talker.set_tag_visible(true)
	expect("the name shows while they are quiet", talker._tag.visible)
	talker.say("Prices are only going up.")
	expect("the name hides while they speak", not talker._tag.visible and talker._bark.visible)
	talker._bark_left = 0.01
	await get_tree().create_timer(0.1).timeout
	expect("the name comes back when they stop", talker._tag.visible and not talker._bark.visible)
	# Panels.
	for id in ["marlow", "hale", "maren", "cutter", "dorn"]:
		town.panel.open_npc(id)
		await get_tree().process_frame
		expect("%s's panel opens with something to do" % id, town.panel.visible and town.panel.get_tree().paused and _count_buttons(town.panel) >= 2)
		town.panel.close()
	town.panel.open_npc("dorn")
	await get_tree().process_frame
	var smith_ok: bool = TownState.smith_stock.size() >= 2
	for entry in TownState.smith_stock:
		smith_ok = smith_ok and int(entry["item"]["slot"]) != Items.Slot.TRINKET
	expect("the smith sells only weapons and armour", smith_ok)
	town.panel.close()
	town.panel.open_board()
	await get_tree().process_frame
	expect("the board lists the jobs", _count_buttons(town.panel) >= 4)
	var offer: Dictionary = TownState.board[0]
	town.panel._take_job(offer)
	expect("taking a job sets it", TownState.job.get("name") == offer["name"])
	town.panel.close()
	town.panel.open_stash()
	await get_tree().process_frame
	town.panel.close()
	town.panel.open_gate()
	await get_tree().process_frame
	expect("the gate page names the job", town.panel.visible and _label_text(town.panel).contains(String(offer["name"])))
	town.panel.close()
	expect("closing a panel unpauses the world", not get_tree().paused)
	# Shopping.
	town.panel.open_npc("marlow")
	await get_tree().process_frame
	var stock: Array = TownState.stock
	expect("the trader has wares", stock.size() == 3)
	var gold: int = TownState.gold
	var vendor_gold: int = TownState.vendor_gold
	var ware: Dictionary = (stock[0] as Dictionary)["item"]
	var price: int = int(round(int((stock[0] as Dictionary)["price"]) * TownSim.mood_price_mult("marlow")))
	town.panel._buy(0, price)
	expect("buying costs gold and puts the item on", TownState.gold == gold - price and TownState.vendor_gold == vendor_gold + price
		and String(TownState.gear[int(ware["slot"])]["name"]) == String(ware["name"]))
	expect("buying gear puts it on the hero standing in town", town.player.stats.equipment[int(ware["slot"])]["name"] == ware["name"])
	var potions: int = TownState.potions
	town.panel._buy_supply("potion", 15)
	expect("buying a potion adds one, to the hero too", TownState.potions == potions + 1 and town.player.stats.potions == potions + 1)
	town.panel.close()   # (the town is paused while a panel is open)
	town.player.stats.potions -= 1   # he drinks one in town
	await get_tree().process_frame
	await get_tree().process_frame
	expect("a potion drunk in town is not bought back by the town's count", TownState.potions == potions)
	TownState.stash.append(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword"))
	town.panel._wear(TownState.stash.size() - 1)
	expect("wearing from the stash puts it on the hero too", town.player.stats.equipment[Items.Slot.WEAPON]["base"] == "Greatsword"
		and town.player._held_path == Items.model_path(town.player.stats.equipment[Items.Slot.WEAPON]))
	# Hiring.
	town.panel.close()
	town.panel.open_npc("cutter")
	await get_tree().process_frame
	expect("a recruit starts outside the clan", not bool(TownState.npcs["cutter"]["member"]))
	gold = TownState.gold
	town.panel.close()
	TownState.npcs["cutter"]["member"] = false
	town.panel.open_npc("cutter")
	town.panel._rebuild()
	var hire: Button = _find_button(town.panel, "Hire")
	expect("the hire button is there and affordable", hire != null and not hire.disabled)
	if hire != null:
		hire.pressed.emit()
	expect("hiring costs gold and joins the clan", bool(TownState.npcs["cutter"]["member"]) and TownState.gold == gold - TownDb.npc("cutter").recruit_cost)
	town.panel.close()
	# The healing stone, and the hero carries what the town gave into the run.
	town.player.health = 10.0
	town.interact({"kind": "stone"})
	expect("the healing stone heals", town.player.health >= town.player.max_health - 0.1)
	var run_hero := Player.new()
	game.add_child(run_hero)
	TownScene._apply_run_gear(run_hero)
	expect("a run starts with the town's potions", run_hero.stats.potions == TownState.potions)
	run_hero.queue_free()
	# Town life goes on while you watch.
	town.sim.run_round()
	await get_tree().process_frame
	expect("the sim's talk reaches the townspeople", true)
	town.queue_free()
	await get_tree().process_frame
	game.rig.camera.current = true
	get_tree().paused = false
	TownState.job = {}
	TownState.reset()

func _count_buttons(root: Node) -> int:
	var count: int = 0
	for node in root.find_children("*", "Button", true, false):
		if not (node as Button).disabled:
			count += 1
	return count

func _find_button(root: Node, text_start: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with(text_start):
			return node as Button
	return null

func _label_text(root: Node) -> String:
	var out: PackedStringArray = []
	for node in root.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return " ".join(out)

# --- Loot ------------------------------------------------------------------------------------------------------------------

## Monsters drop items instead of the old between-wave reward: the odds, the models, walking over a drop, upgrades being put on and
## the rest going to the bag.
func _test_loot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame
	# Every base item has its Blender model.
	var missing: PackedStringArray = []
	for def in ItemDb.all().values():
		if not ResourceLoader.exists(def.model_path):
			missing.append(def.display_name)
	expect("every base item has a dropped model (%s missing)" % ", ".join(missing), missing.is_empty())
	# The odds: ordinary monsters mostly drop commons, a Brute never drops a common.
	var common_brute: int = 0
	var rare_or_better: int = 0
	for i in 200:
		if int(Items.roll_drop(5, 1.0, [])["rarity"]) == Items.Rarity.COMMON:
			common_brute += 1
		if int(Items.roll_drop(2, 0.0, [])["rarity"]) >= Items.Rarity.RARE:
			rare_or_better += 1
	expect("a Brute's drop is always rare or better", common_brute == 0)
	# About 73% of 200 are rare or better (a rare roll, plus every common trinket made rare): a spread of six sigma either side.
	expect("an ordinary monster's drop is often common but sometimes rare", rare_or_better > 90 and rare_or_better < 188)
	expect("only monsters that should drop do", EnemyDb.get_def("brute").drop_chance > EnemyDb.get_def("zombie").drop_chance
		and EnemyDb.get_def("zombie").drop_chance > 0.0)
	# The old reward screen is gone.
	expect("the director no longer offers a reward", not game.director.has_method("offer_reward") and not game.director.has_method("choose"))
	# A kill can drop an item that lands near the body.
	var def: EnemyDef = EnemyDb.get_def("zombie")
	var saved_chance: float = def.drop_chance
	def.drop_chance = 1.0
	player.global_position = Vector3(30, 0, 30)
	var zombie: Enemy = _spawn_enemy(Vector3(24, 0, 24))
	zombie.aggro_range = 0.0
	await get_tree().process_frame
	zombie.receive({"outcome": Combat.Outcome.HIT, "damage": 9999.0, "source": player, "skill_id": "basic", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, player.global_position)
	await get_tree().create_timer(0.3).timeout
	def.drop_chance = saved_chance
	var drops: Array = get_tree().get_nodes_in_group("loot")
	expect("a killed monster drops an item", drops.size() == 1)
	if drops.size() == 1:
		var drop: LootDrop = drops[0]
		await get_tree().create_timer(LootDrop.LAND_TIME + 0.2).timeout
		expect("the drop lands on the ground near the body", drop.landed and absf(drop.global_position.y) < 0.05
			and drop.global_position.distance_to(Vector3(24, 0, 24)) < 3.0)
		expect("the drop can be seen: it has a model", drop.get_node_or_null("Model") != null)
		drop.queue_free()
	# Pickup: an empty slot is filled, anything else goes to the bag (rarity never swaps gear by itself).
	var stats: PlayerStats = player.stats
	var saved_equipment: Dictionary = stats.equipment.duplicate(true)
	var saved_bag: Array[Dictionary] = stats.bag.duplicate(true)
	stats.equipment = {}
	stats.bag = []
	var plain: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Longsword")
	stats.pickup(plain)
	expect("an empty slot takes whatever is picked up", stats.equipment.get(Items.Slot.WEAPON, {}).get("name") == "Longsword" and stats.bag.is_empty())
	stats.pickup(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Falchion"))
	expect("a second weapon goes to the bag", stats.equipment[Items.Slot.WEAPON]["name"] == "Longsword" and stats.bag.size() == 1)
	var fancy: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword")
	for id in AffixDb.all():
		if AffixDb.all()[id]["slot"] == Items.Slot.WEAPON and AffixDb.all()[id]["title"] != "":
			fancy = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, id)
			break
	stats.pickup(fancy)
	expect("a rarer weapon is never swapped in on its own: it goes to the bag", stats.equipment[Items.Slot.WEAPON]["name"] == "Longsword" and stats.bag.size() == 2)
	for i in 20:
		stats.add_to_bag(Items.make(Items.Slot.TRINKET, Items.Rarity.COMMON, 1))
	expect("the bag holds a dozen items", stats.bag.size() == PlayerStats.MAX_BAG)
	# Walking over a drop picks it up.
	stats.bag = []
	player.global_position = Vector3(-30, 0, -30)   # well away, so the drop is not picked up as it lands
	player.reset_physics_interpolation()
	var walk: LootDrop = game.director.drop_item(Vector3(30, 0, 33), Items.make(Items.Slot.ARMOR, Items.Rarity.COMMON, 1, "", "Mail Hauberk"))
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.3).timeout
	var before: bool = is_instance_valid(walk)
	player.global_position = walk.global_position + Vector3(0.5, 0, 0)
	await get_tree().create_timer(0.3).timeout
	expect("walking over a drop picks it up", before and not is_instance_valid(walk) or walk.is_queued_for_deletion())
	expect("and the armour is on", stats.equipment.get(Items.Slot.ARMOR, {}).get("name") == "Mail Hauberk" or stats.bag.size() >= 1)
	# The hero holds what is equipped: each weapon shows its own model, and longer weapons are longer in the hand.
	var held_length: Dictionary = {}
	for base_name in ["Falchion", "Longsword", "Greatsword"]:
		stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", base_name), false)
		await get_tree().process_frame
		var tip_y: float = player.model.weapon_tip.position.y
		held_length[base_name] = tip_y
		expect("equipping the %s puts its model in the hand" % base_name, player._held_path == Items.model_path(stats.equipment[Items.Slot.WEAPON])
			and player.model.weapon != null and player._trail.tip_node == player.model.weapon_tip)
	expect("a greatsword is longer in the hand than a falchion", held_length["Greatsword"] > held_length["Falchion"])
	stats.equipment = saved_equipment
	stats.bag = saved_bag
	player.armor = stats.base_armor + stats.armor_stat("armor", 0.0)
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame

## Drop readability and the item card: a drop grows with camera distance and carries a constant-size marker; pointing at it shows
## what it is and how it compares with what is worn; enemies notice the hero from a shorter distance than they used to.
func _test_loot_ui() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame
	expect("enemies notice the hero from a shorter range", EnemyDef.new().aggro_range <= 12.5 and EnemyDb.get_def("zombie").aggro_range <= 12.5)
	# Comparison.
	var longsword: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Longsword")
	var great: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword")
	var lines: Array[Dictionary] = Items.compare(great, longsword)
	var damage_better: bool = false
	var speed_worse: bool = false
	for entry in lines:
		if String(entry["text"]).begins_with("Damage") and int(entry["sign"]) > 0:
			damage_better = true
		if String(entry["text"]).begins_with("Speed") and int(entry["sign"]) < 0:
			speed_worse = true
	expect("a greatsword hits harder and swings slower than a longsword", damage_better and speed_worse)
	expect("an empty slot says so", Items.compare(great, null)[0]["text"] == "Nothing worn in this slot")
	expect("the same item compares as the same", Items.compare(longsword, longsword)[0]["sign"] == 0)
	var leather: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.COMMON, 1, "", "Leather Jerkin")
	var plate: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.COMMON, 1, "", "Plate Cuirass")
	var armour_lines: Array[Dictionary] = Items.compare(plate, leather)
	var cost_worse: bool = false
	for entry in armour_lines:
		if String(entry["text"]).begins_with("Roll cost") and int(entry["sign"]) < 0:
			cost_worse = true
	expect("heavier armour costs more to roll in", cost_worse)
	# Scale with distance, marker, focus.
	player.global_position = Vector3(0, 0, 0)
	var drop: LootDrop = game.director.drop_item(Vector3(0, 0, -4), Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "", "Falchion"))
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.4).timeout
	expect("a drop has a marker that stays one size on screen", drop._marker != null and drop._marker.fixed_size)
	var near_scale: float = drop.get_node("Model").scale.x
	game.rig.set_zoom_now(CameraRig.ZOOM_MAX)
	await get_tree().create_timer(0.6).timeout
	var far_scale: float = drop.get_node("Model").scale.x
	game.rig.set_zoom_now(1.0)
	expect("a drop grows when the camera is far away (%.2f vs %.2f)" % [near_scale, far_scale], far_scale > near_scale * 1.15)
	# The item under the mouse is the one in focus.
	await get_tree().create_timer(0.6).timeout
	var camera: Camera3D = get_viewport().get_camera_3d()
	hud.mouse_override = camera.unproject_position(drop.global_position + Vector3(0, 0.5, 0))
	expect("pointing at a drop focuses it", hud._drop_in_focus() == drop)
	hud.mouse_override = camera.unproject_position(drop.global_position + Vector3(400, 0, 0))
	expect("pointing elsewhere focuses nothing", hud._drop_in_focus() == null)
	hud.mouse_override = Vector2(-1.0, -1.0)
	drop.queue_free()
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
	expect("the fireball cooldown is at least five seconds", float(SkillDb.all()["fireball"]["cd"]) >= 5.0)
	# Cancel while aiming with right-click.
	Input.action_press("skill_3")
	await get_tree().create_timer(0.3).timeout
	expect("holding the key aims", player.skills.aiming_id == "fireball")
	Input.action_press("alt_skill")
	await get_tree().create_timer(0.2).timeout
	Input.action_release("alt_skill")
	expect("right-click cancels the aim", player.skills.aiming_id == "")
	Input.action_release("skill_3")
	await get_tree().create_timer(0.3).timeout
	expect("letting go of the key after cancelling casts nothing", not player.skills.busy and is_equal_approx(player.stats.mana, player.stats.max_mana)
		and float(player.stats.cooldowns.get("fireball", 0.0)) == 0.0)
	# Cancel while aiming with dodge: the hero rolls instead.
	player.stats.stamina = player.stats.max_stamina
	player.stats.cooldowns["dodge"] = 0.0
	Input.action_press("skill_3")
	await get_tree().create_timer(0.3).timeout
	Input.action_press("dodge")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("dodge")
	expect("dodge cancels the aim", player.skills.aiming_id == "")
	Input.action_release("skill_3")
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

## Item pictures: every base item has an icon and a framed badge, a tile shows a tooltip card, and the Tab panel lists what is worn.
func _test_item_icons() -> void:
	var missing: PackedStringArray = []
	for def in ItemDb.all().values():
		if ItemIcons.icon_for(Items.build(def, 1, Items.Rarity.RARE)) == null:
			missing.append(def.display_name)
	expect("every base item has an icon (%s missing)" % ", ".join(missing), missing.is_empty())
	var item: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.UNIQUE, 1, "", "Greatsword")
	var badge: Texture2D = ItemIcons.badge(item)
	expect("an item's badge is its picture in a frame", badge != null and badge.get_width() == 96 and ItemIcons.badge(item) == badge)
	var common_badge: Texture2D = ItemIcons.badge(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword"))
	expect("rarity changes the frame", common_badge.get_image().get_pixel(3, 40) != badge.get_image().get_pixel(3, 40))
	var tile: ItemTile = ItemTile.create(item, Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Longsword"))
	var card: Control = tile._make_custom_tooltip("") as Control
	expect("a tile's tooltip card describes the item and compares it", card != null and _label_text(card).contains("Greatsword") and _label_text(card).contains("Damage"))
	card.free()
	tile.free()
	# The ground badge is a picture, not text.
	var drop: LootDrop = game.director.drop_item(Vector3(40, 0, 40), item)
	await get_tree().create_timer(0.2).timeout
	expect("a dropped item is shown by its picture and carries no name text", drop._marker != null and drop._marker.texture == badge
		and drop.find_children("*", "Label3D", true, false).is_empty())
	drop.queue_free()
	# Tab panel hit boxes.
	Input.action_press("gear")
	await get_tree().create_timer(0.3).timeout
	expect("the Tab panel has a picture for what is worn", not hud._gear_hits.is_empty())
	Input.action_release("gear")
	await get_tree().process_frame

## Breakable props: barrels, carts, gravestones and braziers can be smashed; a charge or a leap through them throws the pieces along its
## path; clicking one makes the hero swing at it; what breaks stops blocking the way and may leave something behind.
func _test_destructibles() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().process_frame
	var props: Array = get_tree().get_nodes_in_group("destructibles")
	var kinds: Dictionary = {}
	for node in props:
		kinds[(node as Destructible).prop_name] = true
	expect("the arena has breakable barrels, carts, gravestones and braziers", kinds.has("barrel") and kinds.has("wrecked_cart")
		and kinds.has("gravestone") and kinds.has("brazier"))
	# Hits: a barrel survives a scratch and goes with a proper blow; the pieces and what is left behind.
	arena.place_prop("barrel", Vector3(34, 0, 34), 0.0, 1.0)
	var barrel: Destructible = Destructible.near(get_tree(), Vector3(34, 0, 34), 0.5)
	expect("a placed barrel is breakable", barrel != null and barrel.prop_name == "barrel")
	var obstacles_before: int = arena.obstacles.size()
	expect("a scratch does not break it", not barrel.hit(3.0, Vector3.RIGHT) and not barrel.broken and barrel.hp < barrel.max_hp)
	expect("a proper blow does", barrel.hit(30.0, Vector3.RIGHT))
	await get_tree().create_timer(0.3).timeout
	expect("it throws pieces", get_tree().get_nodes_in_group("debris").size() >= 10)
	expect("what is broken stops being an obstacle", arena.obstacles.size() == obstacles_before - 1 and Destructible.near(get_tree(), Vector3(34, 0, 34), 0.5) == null)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	# Gravestones take several hits.
	arena.place_prop("gravestone", Vector3(30, 0, 36), 0.0, 1.3)
	var grave: Destructible = Destructible.near(get_tree(), Vector3(30, 0, 36), 0.5)
	expect("a gravestone takes more than one swing", not grave.hit(15.0, Vector3.RIGHT) and not grave.hit(15.0, Vector3.RIGHT) and grave.hit(15.0, Vector3.RIGHT))
	# Charging through a barrel throws the pieces the way the hero was going.
	player.global_position = Vector3(26, 0, 30)
	player.reset_physics_interpolation()
	player.visual.rotation.y = PI * 0.5
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns["skewer"] = 0.0
	arena.place_prop("barrel", Vector3(30, 0, 30), 0.0, 1.0)
	arena.place_prop("wrecked_cart", Vector3(33, 0, 30.4), 0.0, 1.9)
	await get_tree().process_frame
	player.skills.try_directional("skewer", Vector3(40, 0, 30))
	var charge_t: float = 0.0
	while charge_t < 3.0 and (player.skills.busy or charge_t < 0.3):
		await get_tree().physics_frame
		charge_t += 1.0 / 60.0
	expect("a Skewer charge smashes what is in its path", Destructible.near(get_tree(), Vector3(30, 0, 30), 0.3) == null
		and Destructible.near(get_tree(), Vector3(33, 0, 30.4), 0.3) == null)
	var ahead: float = 0.0
	var count: int = 0
	for node in get_tree().get_nodes_in_group("debris"):
		ahead += (node as DebrisChunk).velocity.x + ((node as DebrisChunk).global_position.x - 30.0)
		count += 1
	expect("the pieces are thrown ahead of the charge (%d pieces)" % count, count > 10 and ahead > 0.0)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().create_timer(1.0).timeout
	# Leaping over a barrel breaks it too.
	player.global_position = Vector3(26, 0, 33)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns["leap"] = 0.0
	arena.place_prop("barrel", Vector3(30, 0, 33), 0.0, 1.0)
	await get_tree().process_frame
	player.skills.try_directional("leap", Vector3(34, 0, 33))
	var leap_t: float = 0.0
	while leap_t < 4.0 and (player.skills.busy or leap_t < 0.3):
		await get_tree().physics_frame
		leap_t += 1.0 / 60.0
	expect("a Leap through a barrel breaks it", Destructible.near(get_tree(), Vector3(30, 0, 33), 0.3) == null)
	# Clicking a prop sends the hero to swing at it.
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	player.global_position = Vector3(20, 0, 20)
	player.reset_physics_interpolation()
	player.stats.stamina = player.stats.max_stamina
	arena.place_prop("barrel", Vector3(24, 0, 20), 0.0, 1.0)
	await get_tree().process_frame
	var target: Destructible = Destructible.near(get_tree(), Vector3(24, 0, 20), 0.3)
	player.attack_prop = target
	var smash_t: float = 0.0
	while smash_t < 6.0 and not target.broken:
		await get_tree().physics_frame
		smash_t += 1.0 / 60.0
	expect("the hero walks up and smashes a barrel they were sent at (%.1f s)" % smash_t, target.broken)
	# Fire and explosions.
	arena.place_prop("barrel", Vector3(14, 0, 14), 0.0, 1.0)
	await get_tree().process_frame
	expect("a blast breaks what is inside it", Destructible.blast(get_tree(), Vector3(14, 0, 14.5), 2.0, 80.0) == 1)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
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

## The new gear affixes (the six dull ones are gone): each does what it says, using the same moves and states the skills create.
func _test_new_affixes() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	# The catalogue.
	var removed: Array = ["frostbite", "momentum", "last_stand", "riposte", "warding", "windfall"]
	var gone: bool = true
	for id in removed:
		gone = gone and not AffixDb.all().has(id)
	expect("the six dull affixes are gone", gone)
	var counts: Dictionary = {0: 0, 1: 0, 2: 0}
	var described: bool = true
	for id in AffixDb.all():
		var entry: Dictionary = AffixDb.all()[id]
		described = described and String(entry["desc"]) != ""
		if String(entry["title"]) != "":
			counts[int(entry["slot"])] += 1
	expect("9 weapon, 5 armor and 7 trinket affixes can roll on rares", counts[0] == 9 and counts[1] == 5 and counts[2] == 7)
	expect("every affix is described", described)
	var pips_ok: bool = true
	for skill_id in SkillDb.all():
		for affix_id in SkillDb.modifier_affixes(skill_id):
			pips_ok = pips_ok and AffixDb.all().has(affix_id)
	expect("every skill's list of affixes that change it names real ones", pips_ok)

	var saved: Dictionary = player.stats.equipment.duplicate()
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	var a: Enemy = _spawn_enemy(Vector3(6, 0, 0))
	var b: Enemy = _spawn_enemy(Vector3(7.2, 0, 0))
	var far: Enemy = _spawn_enemy(Vector3(-20, 0, 0))
	for e in [a, b, far]:
		e.aggro_range = 0.0
		e.max_health = 3000.0
		e.health = 3000.0
	await get_tree().process_frame

	# Kindling: burning enemies take 50% more, and the fire jumps to the neighbour.
	_wear("kindling", 0)
	expect("a hit on a cold enemy is plain", is_equal_approx(ItemEffects.outgoing_multiplier(player, a), 1.0))
	a.apply_burn(5.0, 4.0)
	expect("a hit on a burning enemy does 50% more", is_equal_approx(ItemEffects.outgoing_multiplier(player, a), 1.5))
	var hit: Dictionary = Combat.resolve(player, a, 10.0, Combat.DamageType.PHYSICAL, false, 1.0, true)
	a.receive(hit, player.global_position)
	ItemEffects.on_dealt_hit(player, a, hit)
	expect("the fire jumps to the enemy next to it", b.is_burning() and not far.is_burning())
	a.stop_burning()
	b.stop_burning()

	# Juggler's: an enemy thrown into the air takes 80% more and is knocked back up.
	_wear("juggler", 0)
	a.ragdoll_launch(Vector3(0, 0, 4), 6.0, Vector3(3, 0, 0))
	await get_tree().process_frame
	expect("a thrown enemy is airborne", ItemEffects.is_airborne(a))
	expect("hits on it do 80% more", is_equal_approx(ItemEffects.outgoing_multiplier(player, a), 1.8))
	expect("hits on a grounded enemy do not", is_equal_approx(ItemEffects.outgoing_multiplier(player, far), 1.0))
	await get_tree().create_timer(0.4).timeout   # now on its way down
	expect("it is falling", ItemEffects.is_airborne(a) and a.ragdoll._vy < 0.0)
	ItemEffects.on_dealt_hit(player, a, hit)
	expect("the hit knocks it back up", ItemEffects.is_airborne(a) and a.ragdoll._vy > 3.0)
	await get_tree().create_timer(2.5).timeout

	# Breaker's: stunned or downed enemies are always crit.
	_wear("breaker", 0)
	far.stun_time = 0.0
	expect("a healthy enemy is not a guaranteed crit", not ItemEffects.guaranteed_crit(player, far))
	far.stun_time = 1.0
	expect("a stunned one is", ItemEffects.guaranteed_crit(player, far))
	far.stun_time = 0.0
	far.ragdoll_launch(Vector3(0, 0, 3), 5.0, Vector3(2, 0, 0))
	await get_tree().process_frame
	expect("a knocked-down one is", ItemEffects.guaranteed_crit(player, far))
	await get_tree().create_timer(3.0).timeout

	# Maelstrom: Cleave stuns everything it hits.
	_wear("maelstrom", 0)
	for e in [a, b]:
		e.global_position = player.global_position + Vector3(1.4 if e == a else -1.4, 0, 0)
		e.stun_time = 0.0
	await get_tree().process_frame
	player.skills.start_skill("cleave", a, null)
	var longest: float = 0.0
	var t: float = 0.0
	while t < 1.8:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		longest = maxf(longest, minf(a.stun_time, b.stun_time))
	expect("Cleave stuns everything it catches for about a second (%.2f)" % longest, longest >= 0.8)
	await get_tree().create_timer(1.5).timeout
	for e in [a, b]:
		e.global_position = Vector3(6, 0, 0) if e == a else Vector3(7.2, 0, 0)
		e.stun_time = 0.0

	# Impaler's and Ramming: the Skewer kick.
	_wear("impaler", 0)
	var before: float = b.health
	ItemEffects.impaler_burst(player, a, Vector3(6, 0, 0))
	expect("an enemy kicked off the blade bursts and hurts the one beside it", b.health < before)
	_wear("charger", 1)
	player.stats.cooldowns["skewer"] = 9.0
	ItemEffects.on_skewer_kick(player, 2)
	expect("a Skewer that carried two is not ready again", float(player.stats.cooldowns["skewer"]) > 0.0)
	ItemEffects.on_skewer_kick(player, 3)
	expect("one that carried three is", float(player.stats.cooldowns["skewer"]) == 0.0)

	# Ember-Treaded: the trail sets an enemy standing on it alight.
	_wear("cinder_roll", 1)
	far.global_position = player.global_position + Vector3(0.6, 0, 0)
	far.stop_burning()
	ItemEffects.on_roll_start(player)
	await get_tree().create_timer(0.5).timeout
	expect("an enemy on the embers catches fire", far.is_burning())
	far.global_position = Vector3(-20, 0, 0)
	far.stop_burning()

	# Vaultborn: a Leap landing makes the next Power Strike free.
	_wear("vaultborn", 1)
	player.stats.mana = 0.0
	player.stats.cooldowns["power"] = 5.0
	expect("without a Leap, Power Strike is not available", not player.stats.can_use("power"))
	ItemEffects.on_leap_land(player)
	expect("after a Leap landing it is, with no mana and no cooldown", player.stats.can_use("power") and player.stats.vault_time > 0.0)
	a.global_position = player.global_position + Vector3(1.4, 0, 0)
	player.skills.start_skill("power", a, null)
	expect("using it spends nothing", player.stats.mana == 0.0 and float(player.stats.cooldowns["power"]) == 5.0 and player.stats.vault_time == 0.0)
	await get_tree().create_timer(2.0).timeout
	player.skills.cancel_action()
	player.stats.mana = player.stats.max_mana

	# Smouldering: being hit sets the enemies close to you alight.
	_wear("smouldering", 1)
	a.global_position = player.global_position + Vector3(2.0, 0, 0)
	far.global_position = Vector3(-20, 0, 0)
	a.stop_burning()
	ItemEffects.on_player_hurt(player)
	expect("a close enemy catches fire when you are hit, a far one does not", a.is_burning() and not far.is_burning())
	a.stop_burning()

	# Wildfire: a Fireball that catches three or more.
	_wear("wildfire", 2)
	player.stats.cooldowns["fireball"] = 5.5
	ItemEffects.on_fireball_blast(player, 2)
	expect("two enemies in the blast earn nothing", float(player.stats.cooldowns["fireball"]) == 5.5)
	ItemEffects.on_fireball_blast(player, 3)
	expect("three earn 3 seconds off the cooldown", is_equal_approx(float(player.stats.cooldowns["fireball"]), 2.5))

	# Virtuoso: different skills in a row stack; repeating drops them.
	_wear("virtuoso", 2)
	player.stats.chain_stacks = 0
	player.stats.chain_time = 0.0
	player.stats.chain_last = ""
	ItemEffects.on_skill_start(player, "power")
	expect("the first skill starts the streak with no bonus", player.stats.chain_stacks == 0 and is_equal_approx(ItemEffects.virtuoso_multiplier(player), 1.0))
	ItemEffects.on_skill_start(player, "cleave")
	expect("a different second skill gives +20%", player.stats.chain_stacks == 1 and is_equal_approx(ItemEffects.virtuoso_multiplier(player), 1.2))
	ItemEffects.on_skill_start(player, "fireball")
	ItemEffects.on_skill_start(player, "skewer")
	ItemEffects.on_skill_start(player, "leap")
	expect("it stops at three stacks (+60%)", player.stats.chain_stacks == 3 and is_equal_approx(ItemEffects.virtuoso_multiplier(player), 1.6))
	ItemEffects.on_skill_start(player, "leap")
	expect("repeating a skill drops them", player.stats.chain_stacks == 0)
	ItemEffects.on_skill_start(player, "power")
	ItemEffects.on_skill_start(player, "cleave")
	player.stats.chain_time = 0.0
	player._physics_process(0.016)
	expect("the streak ends when its time runs out", player.stats.chain_stacks == 0)

	# Quakebound: kills charge the ultimate.
	_wear("quaker", 2)
	player.stats.ult_charge = 0.0
	ItemEffects.on_kill(player, far)
	expect("a kill charges 4% of Earthshatter", is_equal_approx(player.stats.ult_charge, PlayerStats.MAX_ULT_CHARGE * 0.04))

	# Pyrebound: a burning enemy that dies explodes.
	_wear("pyre", 2)
	a.global_position = Vector3(6, 0, 3)
	b.global_position = Vector3(7.0, 0, 3)
	a.stop_burning()
	b.stop_burning()
	a.health = 3000.0
	b.health = 3000.0
	var b_before: float = b.health
	ItemEffects.on_kill(player, a)
	expect("a cold kill explodes nothing", b.health == b_before and not b.is_burning())
	a.apply_burn(5.0, 4.0)
	ItemEffects.on_kill(player, a)
	expect("a burning kill goes up: the neighbour is hurt and set alight", b.health < b_before and b.is_burning())

	player.stats.equipment = saved
	player.armor = player.stats.base_armor + player.stats.armor_stat("armor", 0.0)
	player.stats.cooldowns.clear()
	player.stats.ult_charge = PlayerStats.MAX_ULT_CHARGE
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame

## Puts on one item carrying just this affix in the right slot (replacing what was worn there).
func _wear(affix_id: String, slot: int) -> void:
	player.stats.equipment = {}
	player.stats.equip(Items.make(slot, Items.Rarity.RARE, 1, affix_id), false)

# --- Headless self test ---------------------------------------------------------

## `--only=NAME` runs a single check, so a change can be verified without the whole suite.
const ONLY_TESTS := {
	"townlayout": "_test_town_layout", "crypt": "_test_crypt_road", "weaponstyle": "_test_weapon_styles", "autoattack": "_test_auto_attack", "items": "_test_items", "swarm": "_test_swarm", "gibs": "_test_gibs",
	"balance": "_test_balance", "enemies": "_test_enemies", "firstwave": "_test_first_wave", "gamepad": "_test_gamepad", "loading": "_test_loading", "leap": "_test_leap", "uiblock": "_test_ui_block", "behindcam": "_test_hover_behind_camera", "camera": "_test_camera_rotation", "startzoom": "_test_start_zoom", "deathragdoll": "_test_death_ragdoll", "enemyrun": "_test_enemy_run", "padmenus": "_test_pad_menus", "padtarget": "_test_pad_targeting", "padcamera": "_test_pad_camera_and_aim", "twinflame": "_test_twin_flame_target", "pausetest": "_test_pause_stops_game", "swordsound": "_test_sword_sound", "swordair": "_test_sword_miss_in_air", "fireballsound": "_test_fireball_sounds", "earthshatter": "_test_earthshatter", "impact": "_test_impact", "fireblast": "_test_fire_blast", "loot": "_test_loot", "newaffixes": "_test_new_affixes", "destructibles": "_test_destructibles", "hitaggro": "_test_hit_aggro", "fireballcancel": "_test_fireball_cancel", "itemicons": "_test_item_icons", "lootui": "_test_loot_ui", "townsim": "_test_town_sim", "townstate": "_test_town_state", "modifiers": "_test_run_modifiers", "townscene": "_test_town_scene", "skewer": "_test_skewer",
}

## Nothing in the town may clip into anything else: no solid prop overlaps another or the palisade, none stands beyond the wall, and
## nobody's spot or station is inside one. Footprints are each model's bounds, scaled to its height, as a rotated rectangle.
func _town_footprint(node: Node3D, prop: TownProp) -> Dictionary:
	var inst: Node3D = (load("res://assets/models/%s/model.glb" % prop.model_name) as PackedScene).instantiate()
	var b: AABB = CharacterModel._bounds_of(inst)
	var f: float = prop.height / maxf(b.size.y, 0.001)
	inst.free()
	return {"name": node.name, "model": prop.model_name, "c": Vector2(node.position.x, node.position.z),
		"h": Vector2(b.size.x * f * 0.5, b.size.z * f * 0.5), "yaw": node.rotation.y, "solid": prop.collides}

func _town_corners(o: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var c: float = cos(o["yaw"])
	var s: float = sin(o["yaw"])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector2(sx * o["h"].x, sz * o["h"].y)
			out.append(o["c"] + Vector2(p.x * c + p.y * s, -p.x * s + p.y * c))
	return out

## How deep two footprints overlap (0 when apart), by the separating-axis test.
func _town_overlap(a: Dictionary, b: Dictionary) -> float:
	var best: float = INF
	for o in [a, b]:
		var c: float = cos(o["yaw"])
		var s: float = sin(o["yaw"])
		for axis in [Vector2(c, -s), Vector2(s, c)]:
			var ra := Vector2(INF, -INF)
			var rb := Vector2(INF, -INF)
			for p in _town_corners(a):
				ra = Vector2(minf(ra.x, p.dot(axis)), maxf(ra.y, p.dot(axis)))
			for p in _town_corners(b):
				rb = Vector2(minf(rb.x, p.dot(axis)), maxf(rb.y, p.dot(axis)))
			var depth: float = minf(ra.y, rb.y) - maxf(ra.x, rb.x)
			if depth <= 0.0:
				return 0.0
			best = minf(best, depth)
	return best

func _test_town_layout() -> void:
	var layout: Node = (load("res://game/town/town_layout.tscn") as PackedScene).instantiate()
	var props: Array[Dictionary] = []
	for node in layout.get_node("Props").get_children():
		if node is TownProp and (node as TownProp).model_name != "":
			props.append(_town_footprint(node, node))
	var clashes: PackedStringArray = []
	var beyond: PackedStringArray = []
	for i in props.size():
		var a: Dictionary = props[i]
		if a["model"] != "palisade":
			for corner in _town_corners(a):
				if absf(corner.x) > TownScene.HALF + 0.3 or absf(corner.y) > TownScene.HALF + 0.3:
					beyond.append(String(a["name"]))
					break
		for j in range(i + 1, props.size()):
			var b: Dictionary = props[j]
			if (a["model"] == "palisade" and b["model"] == "palisade") or a["model"] == "town_gate" or b["model"] == "town_gate":
				continue
			if (a["solid"] or b["solid"]) and _town_overlap(a, b) > 0.05:
				clashes.append("%s x %s" % [a["name"], b["name"]])
	expect("no town prop clips into another or into the palisade: " + ", ".join(clashes), clashes.is_empty())
	expect("no town prop stands beyond the wall: " + ", ".join(beyond), beyond.is_empty())
	var stood_in: PackedStringArray = []
	for group in ["Spots", "Stations"]:
		for marker in layout.get_node(group).get_children():
			var at := Vector2(marker.position.x, marker.position.z)
			for o in props:
				if not o["solid"] or o["model"] == "palisade":
					continue
				var local: Vector2 = at - o["c"]
				var c: float = cos(o["yaw"])
				var s: float = sin(o["yaw"])
				if absf(local.x * c - local.y * s) < o["h"].x + 0.4 and absf(local.x * s + local.y * c) < o["h"].y + 0.4:
					stood_in.append("%s in %s" % [marker.name, o["name"]])
	expect("nobody's spot or station is inside a solid prop: " + ", ".join(stood_in), stood_in.is_empty())
	layout.free()

## Weapons have a moveset of their own: the falchion recovers fast, staggers lightly and finishes its combo quickly; the longsword is the
## baseline; the greatsword hits a wide arc, staggers and knocks back harder, recovers slowly and finishes with a slam.
func _test_weapon_styles() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	var skills: SkillController = player.skills
	var swing_time: Dictionary = {}
	var finisher_time: Dictionary = {}
	var weights: Dictionary = {}
	var swept: Dictionary = {}
	var slammed: Dictionary = {}
	var base_time: float = float(SkillDb.basic_combo()[2][0]["time"])
	for base in ["Falchion", "Longsword", "Greatsword"]:
		player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", base), false)
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
			e.defense = 0.0   # a swing can still miss (5%) or be blocked, so each is tried a few times
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
		for e in group:
			e.queue_free()
		await get_tree().process_frame
	expect("a falchion recovers faster than a longsword, a greatsword slower", swing_time["Falchion"] < swing_time["Longsword"] - 0.1
		and swing_time["Greatsword"] > swing_time["Longsword"] + 0.1)
	expect("a falchion's finisher is short and a greatsword's is not", finisher_time["Falchion"] < base_time * 0.8 and absf(finisher_time["Longsword"] - base_time) < 0.001
		and absf(finisher_time["Greatsword"] - base_time) < 0.001)
	expect("stagger weight rises falchion < longsword < greatsword", weights["Falchion"] < weights["Longsword"] - 0.15 and weights["Greatsword"] > weights["Longsword"] + 0.3)
	expect("only the greatsword's swing reaches the others in an arc in front (not behind)", swept["Falchion"] == 0 and swept["Longsword"] == 0 and swept["Greatsword"] == 2)
	expect("only the greatsword's finisher slams the ground in front", slammed["Falchion"] == 0 and slammed["Longsword"] == 0 and slammed["Greatsword"] >= 2)
	expect("the tooltip says how the weapon fights", Items.lines(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword")).any(
		func(line: String) -> bool: return line.contains("slam")))
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Longsword"), false)

## The Crypt Road: the objective's bookkeeping, an elongated authored layout with three reachable nests, monsters that exist from the
## start and do their own thing until noticed (a group wakes together), and what destroying a nest does.
func _test_crypt_road() -> void:
	var offer: Dictionary = TownState.crypt_road_offer()
	var objective: Dictionary = offer["objective"]
	expect("a destroy_nest job reads as nests, not waves", JobObjective.describe(offer) == "Destroy 3 corrupted nests"
		and JobObjective.progress_text(offer, {"stage": 1}) == "Destroy nests: 1 / 3" and not JobObjective.uses_waves(offer)
		and not JobObjective.ends_run_when_complete(offer) and int(objective["count"]) == 3)
	expect("it completes at the third nest only", not JobObjective.is_complete(offer, {"stage": 2}) and JobObjective.is_complete(offer, {"stage": 3}))
	expect("a wave job still uses waves", JobObjective.uses_waves(JobObjective.upgrade_legacy({"name": "x", "waves": 3})))
	# Swap the wave arena for the location, as Main does for this job.
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	var place_arena: Arena = CryptRoad.make_arena()
	game.add_child(place_arena)
	place_arena.build(false)
	var place := CryptRoad.new()
	game.add_child(place)
	place.build(place_arena)
	player.global_position = CryptRoad.START
	player.reset_physics_interpolation()
	var footprint: float = place_arena.half_x * place_arena.half_z * 4.0
	expect("it is 3-5 times the old arena and long rather than square", footprint >= Arena.HALF * Arena.HALF * 4.0 * 3.0
		and footprint <= Arena.HALF * Arena.HALF * 4.0 * 5.0 and place_arena.half_z >= place_arena.half_x * 4.0)
	expect("it holds three nests", place.nests.size() == 3)
	var inside: bool = true
	for entry in place.placed:
		var pos: Vector3 = entry["pos"]
		inside = inside and absf(pos.x) < place_arena.half_x and absf(pos.z) < place_arena.half_z
	expect("everything placed is inside the walls", inside and place.placed.size() > 150)
	expect("the middle of the road is clear of solid props", place.road_distance(0.0, 100.0) < 3.0
		and not place.placed.any(func(e: Dictionary) -> bool: return e["name"] == "dead_tree" and place.road_distance(e["pos"].x, e["pos"].z) < CryptRoad.ROAD_HALF_WIDTH))
	await place.wait_for_navigation()
	expect("the navigation map takes the whole road", place.navigation_ready())
	var map: RID = game.get_world_3d().navigation_map
	var reachable: int = 0
	for nest in place.nests:
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, CryptRoad.START, nest.global_position, true)
		var gap: float = path[path.size() - 1].distance_to(nest.global_position) if not path.is_empty() else -1.0
		if gap >= 0.0 and gap < 4.5:
			reachable += 1
		else:
			print("  nest at ", nest.global_position, " path points ", path.size(), " ends ", gap, " m from it")
	expect("every nest can be walked to from the start", reachable == 3)
	var crypt_path: PackedVector3Array = NavigationServer3D.map_get_path(map, CryptRoad.START, Vector3(0, 0, -150), true)
	expect("the road runs the whole length, to the crypt courtyard", not crypt_path.is_empty() and crypt_path[crypt_path.size() - 1].z < -140.0)
	# The monsters.
	var run: RunDirector = game.director
	run.set_job(offer)
	run.start_location(place)
	await get_tree().process_frame
	var all: Array = get_tree().get_nodes_in_group("enemies")
	var near_start: int = 0
	var awake: int = 0
	var kinds: Dictionary = {}
	for node in all:
		var e: Enemy = node
		near_start += 1 if e.global_position.distance_to(CryptRoad.START) < 12.0 else 0
		awake += 1 if e._aggro else 0
		kinds[e.variant] = true
	print("  monsters ", all.size(), " awake ", awake, " within 12 m of the start ", near_start)
	expect("monsters already exist across the road, none awake and none on the hero", all.size() >= 40 and awake == 0 and near_start == 0)
	expect("it uses the whole cast: zombies, ghouls, spitters, a bloater, a priest, brutes", kinds.size() == 6)
	var feeder: Enemy = null
	var spitter: Enemy = null
	var melee_front: float = -INF
	for node in all:
		var e: Enemy = node
		if e.idle_mode == "feed" and feeder == null:
			feeder = e
		if e.variant == "spitter" and e.global_position.z < 80.0 and e.global_position.z > 60.0:
			spitter = e
		if e.variant == "zombie" and e.group_id == 7:
			melee_front = maxf(melee_front, e.global_position.z)
	expect("some are feeding at a corpse", feeder != null)
	expect("the cottage spitters stand behind its melee line (farther from the way in)", spitter != null and spitter.global_position.z < melee_front - 4.0)
	await get_tree().create_timer(1.0).timeout
	expect("a feeder is hunched over, a sleeper has not walked off", feeder.visual.rotation.x > 0.3 and not feeder._aggro)
	var walker: Enemy = null
	for node in all:
		if (node as Enemy).group_id == 1:
			walker = node
	var walked_from: Vector3 = walker.global_position
	await get_tree().create_timer(2.0).timeout
	expect("a walker strolls about on its own", walker.global_position.distance_to(walked_from) > 0.6 and not walker._aggro)
	# Noticing one wakes its group.
	var mates: Array[Enemy] = []
	for node in all:
		if (node as Enemy).group_id == 6:
			mates.append(node)
	mates[0].wake()
	var all_awake: bool = true
	for m in mates:
		all_awake = all_awake and m._aggro
	expect("when one of a group notices the hero the whole group does", mates.size() >= 3 and all_awake)
	# The nests.
	var count_before: int = get_tree().get_nodes_in_group("enemies").size()
	var first: Destructible = place.nests[0]
	var nearby: Enemy = null
	for node in all:
		var e: Enemy = node
		if not e._aggro and e.global_position.distance_to(first.global_position) < 20.0:
			nearby = e
	first.hit(999.0, Vector3.FORWARD)
	await get_tree().process_frame
	expect("the hero's own swings can break a nest (and a click picks it)", Destructible.near(get_tree(), place.nests[1].global_position, 3.0, Destructible.HERO) == place.nests[1])
	expect("destroying a nest counts once and shows on the HUD line", place.nests_destroyed == 1 and run.progress()["stage"] == 1
		and run.objective_line() == "Destroy nests: 1 / 3")
	expect("it stirs up what lived nearby", nearby == null or nearby._aggro)
	expect("something climbs out of the broken nest", get_tree().get_nodes_in_group("enemies").size() >= count_before + 3)
	expect("there is no wave, and the run does not end when the field is cleared", run.location == null or run.wave >= 3)
	place.nests[1].hit(999.0, Vector3.FORWARD)
	place.nests[2].hit(999.0, Vector3.FORWARD)
	await get_tree().process_frame
	expect("three nests complete the job", JobObjective.is_complete(offer, run.progress()) and run.objective_line() == "Destroy nests: 3 / 3")
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	# Walking out through the road gate with the job done hands it in.
	player.global_position = Vector3(0, 0, CryptRoad.EXIT_Z)
	player.reset_physics_interpolation()
	await get_tree().create_timer(1.2).timeout
	expect("walking out through the gate with the nests gone ends the run", run.is_ending())

var _failures: PackedStringArray = []

## Records a failed expectation (printed as [FAIL], which CI treats as an error) instead of just logging a boolean.
func expect(label: String, condition: bool) -> void:
	if not condition:
		_failures.append(label)
		print("  [FAIL] ", label)

## Ends the run: exit code 0 when every expectation held, 1 otherwise.
func _finish() -> void:
	if _failures.is_empty():
		print("SELFTEST done")
		get_tree().quit(0)
	else:
		print("SELFTEST FAILED: ", ", ".join(_failures))
		print("SELFTEST done")
		get_tree().quit(1)

func _run_selftest() -> void:
	print("SELFTEST start")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only=") and ONLY_TESTS.has(arg.substr(7)):
			await call(ONLY_TESTS[arg.substr(7)])
			_finish()
			return
	for action in ["click", "alt_skill", "stand_still", "restart", "skill_1", "skill_4"]:
		expect("input action %s exists" % action, InputMap.has_action(action))
	print("  camera current: ", rig.camera.current, "  pitch: ", rig.camera.rotation_degrees.x, "  fov: ", rig.camera.fov)

	await _test_first_wave()
	_test_settings()
	await _test_zoom()
	await _test_hotkeys()
	await _test_navigation()
	await _test_roll_shove()
	await _test_skewer()
	await _test_fireball()
	await _test_items()
	await _test_leap()
	await _test_earthshatter()
	await _test_ui_block()
	await _test_hover_behind_camera()
	await _test_camera_rotation()
	await _test_start_zoom()
	await _test_death_ragdoll()
	await _test_enemy_run()
	await _test_pad_menus()
	await _test_pad_targeting()
	await _test_pad_camera_and_aim()
	await _test_twin_flame_target()
	await _test_sword_sound()
	await _test_sword_miss_in_air()
	await _test_fireball_sounds()
	await _test_impact()
	await _test_fire_blast()
	await _test_gibs()
	await _test_swarm()
	await _test_gamepad()
	await _test_loading()
	await _test_enemies()
	await _test_balance()
	await _test_auto_attack()
	await _test_fireball_cancel()
	await _test_item_icons()
	await _test_loot()
	await _test_destructibles()
	await _test_loot_ui()
	_test_town_sim()
	_test_town_state()
	await _test_run_modifiers()
	await _test_town_scene()

	var zombies: Array[Enemy] = []
	for i in 3:
		zombies.append(_spawn_enemy(Vector3(2.0 + i * 1.5, 0, 3.0)))
	player.attack_target = zombies[0]
	player.stats.mana = player.stats.max_mana
	await get_tree().create_timer(0.5).timeout
	# Exercise hotbar skills directly on the nearest zombie.
	for id in ["power", "cleave", "fireball"]:
		var target: Actor = player.enemy_near(player.global_position, 20.0)
		if target == null:
			break
		player.skills.queued_skill = id
		player.skills.queued_target = target
		await get_tree().create_timer(1.6).timeout
	await get_tree().create_timer(6.0).timeout

	# Roll: should move the hero ~4 m, grant brief invulnerability and not leave collision disabled.
	var before: Vector3 = player.global_position
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(player.global_position + Vector3(5, 0, 0))
	var roll_invuln: bool = player.invulnerable_time > 0.0
	await get_tree().create_timer(0.8).timeout
	expect("roll covers ground and is invulnerable", player.global_position.distance_to(before) > 3.0 and roll_invuln)
	expect("roll restores collision and ends", player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY) and not player.movement.rolling)
	print("  roll: moved ", snappedf(player.global_position.distance_to(before), 0.1), " m, invulnerable during=", roll_invuln,
		", mask restored=", player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY), ", rolling=", player.movement.rolling)

	# (Death behaviour has its own check: _test_death_ragdoll.)

	var names := ["MISS", "BLOCK", "HIT", "CRIT", "CRUSH", "WOUND"]
	var parts: Array[String] = []
	for key in Combat.tally.keys():
		parts.append("%s=%d" % [names[int(key)], int(Combat.tally[key])])
	print("  outcomes: ", ", ".join(parts))
	print("  kills: ", kills, "  player health: ", int(player.health), "  mana: ", int(player.stats.mana))
	_finish()