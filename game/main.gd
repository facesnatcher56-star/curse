extends Node3D
## Arena, camera, wave spawner. Run with `-- --selftest` for a headless combat check.

const ARENA_HALF := 40.0

var arena: Arena
var player: Player
var hud: Hud
var pause_menu: PauseMenu
var rig: CameraRig
var wave: int = 0
var kills: int = 0
var choosing: bool = false
var _choices: Array[Dictionary] = []
var _brute_killed: bool = false
var _reward_pending: bool = false
var _selftest: bool = false

func _ready() -> void:
	# The reward screen pauses the game; this node must keep receiving input while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameSettings.boot()
	_selftest = OS.get_cmdline_user_args().has("--selftest")
	_build_world()

	player = Player.new()
	add_child(player)
	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.72, 0.45)
	torch.light_energy = 1.1
	torch.omni_range = 9.0
	torch.position = Vector3(0, 3.0, 0)
	player.add_child(torch)

	rig = CameraRig.new()
	if OS.get_cmdline_user_args().has("--zoom"):
		rig.offset = Vector3(0.0, 2.6, 4.2)
		rig.pitch_degrees = -22.0
	add_child(rig)
	rig.target = player
	rig.global_position = player.global_position

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.player = player
	hud.arena = arena
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	pause_menu.main_menu_requested.connect(func() -> void: get_tree().change_scene_to_file("res://game/menu.tscn"))
	layer.add_child(pause_menu)

	if OS.get_cmdline_user_args().has("--skillshot=skewer"):
		_skill_shots("skewer")
	elif OS.get_cmdline_user_args().has("--skillshot=fireball"):
		_skill_shots("fireball")
	elif OS.get_cmdline_user_args().has("--skillshot=leap"):
		_leap_shots()
	elif OS.get_cmdline_user_args().has("--skillshot=gibs"):
		_gib_shots()
	elif OS.get_cmdline_user_args().has("--skillshot=power"):
		_melee_shots("power")
	elif OS.get_cmdline_user_args().has("--skillshot=cleave"):
		_melee_shots("cleave")
	elif OS.get_cmdline_user_args().has("--aimshot"):
		_aim_shot()
	elif OS.get_cmdline_user_args().has("--pauseshot"):
		_next_wave()
		await get_tree().create_timer(0.8).timeout
		pause_menu.open()
		await get_tree().create_timer(0.4).timeout
		print("paused=", get_tree().paused, " menu open=", pause_menu.is_open())
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_pause.png")
		pause_menu.close()
		print("paused after resume=", get_tree().paused)
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--hudshot"):
		_hud_shot()
	elif OS.get_cmdline_user_args().has("--rewardshot"):
		_reward_shot()
	elif OS.get_cmdline_user_args().has("--hovershot"):
		_hover_shot()
	elif OS.get_cmdline_user_args().has("--rollshot"):
		_roll_shots()
	elif OS.get_cmdline_user_args().has("--poses"):
		_pose_sheet()
	elif _clip_arg() != "":
		_clip_sheet(_clip_arg())
	elif _selftest:
		_run_selftest()
	else:
		_next_wave()
		if OS.get_cmdline_user_args().has("--shot"):
			_screenshot_demo()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not choosing and not pause_menu.is_open():
		pause_menu.open()
		return
	if choosing:
		for i in 3:
			if event.is_action_pressed("skill_%d" % (i + 1)):
				_choose(i)
				return
		if event.is_action_pressed("skill_4"):
			_choose(-1)
			return
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			for i in hud.card_rects.size():
				if hud.card_rects[i].has_point(click.position):
					_choose(i)
					return
		return
	if event.is_action_pressed("restart") and player.dead:
		get_tree().reload_current_scene()

## Wave over: offer three items, one of which you keep. Brutes make better offers.
func _offer_reward() -> void:
	if _reward_pending:
		return
	_reward_pending = true
	hud.show_banner("Wave cleared", 1.5)
	await get_tree().create_timer(1.3).timeout
	if player.dead:
		return
	var owned: Array[String] = []
	for item in player.equipment.values():
		if item["rarity"] == Items.Rarity.UNIQUE:
			owned.append(item["name"])
	_choices = Items.roll_choices(wave, _brute_killed, owned)
	_brute_killed = false
	hud.choices = _choices
	hud.choosing = true
	choosing = true
	get_tree().paused = true

func _choose(index: int) -> void:
	if index >= 0 and index < _choices.size():
		player.equip(_choices[index])
	else:
		player.potions += 1
		player._say("Skipped: +1 potion")
	choosing = false
	_reward_pending = false
	hud.choosing = false
	get_tree().paused = false
	await get_tree().create_timer(1.8).timeout
	if not player.dead:
		_next_wave()

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.05, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.5, 0.62)
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.08, 0.09, 0.12)
	environment.fog_density = 0.01
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_color = Color(0.8, 0.85, 1.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	arena = Arena.new()
	add_child(arena)
	arena.build()
	if hud != null:
		hud.arena = arena

func _next_wave() -> void:
	wave += 1
	var count: int = 8 + wave * 3
	var brutes: int = wave / 2  # none in wave 1, then one more every other wave
	var level: float = 1.0 + 0.12 * (wave - 1)
	var banner: String = "Wave %d" % wave
	if brutes == 1:
		banner += "  -  a Brute approaches"
	elif brutes > 1:
		banner += "  -  %d Brutes approach" % brutes
	hud.show_banner(banner)
	Enemy.max_tokens = 2 + wave / 5   # how many enemies may swing at the hero at once
	# Zombies come in tight packs; Brutes and the odd straggler stand alone, scattered at random.
	var centres: Array[Vector3] = []
	var remaining: int = count
	while remaining > 0:
		var pack: int = mini(remaining, randi_range(2, 5))
		if remaining - pack < 2:
			pack = remaining
		remaining -= pack
		var centre: Vector3 = _spawn_point(14.0, 28.0, centres, 9.0)
		centres.append(centre)
		var placed: Array[Vector3] = []
		for k in pack:
			var pos: Vector3 = centre
			for attempt in 8:
				var offset: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.0, 1.8 + pack * 0.55)
				pos = centre + Vector3(offset.x, 0.0, offset.y)
				var clear: bool = true
				for other in placed:
					if other.distance_to(pos) < 1.5:
						clear = false
						break
				if clear:
					break
			placed.append(pos)
			_spawn_enemy(_clamp_to_arena(pos), "zombie", level)
	for i in brutes:
		_spawn_enemy(_spawn_point(18.0, 34.0, centres, 8.0), "brute", level)
	if wave >= 2:
		for i in randi_range(1, 2):
			_spawn_enemy(_spawn_point(16.0, 34.0, centres, 6.0), "zombie", level)  # stragglers

func _clamp_to_arena(pos: Vector3) -> Vector3:
	return Vector3(clampf(pos.x, -ARENA_HALF + 2, ARENA_HALF - 2), 0.0, clampf(pos.z, -ARENA_HALF + 2, ARENA_HALF - 2))

## A random spot `min_dist`..`max_dist` from the hero, at least `spacing` from every spot already used.
func _spawn_point(min_dist: float, max_dist: float, used: Array[Vector3], spacing: float) -> Vector3:
	# Never closer than 80% of min_dist to the hero (the arena clamp could otherwise pull a spawn onto them);
	# if no spot qualifies, take the farthest one tried.
	var farthest: Vector3 = player.global_position
	var farthest_d: float = -1.0
	for attempt in 30:
		var angle: float = randf() * TAU
		var pos: Vector3 = _clamp_to_arena(player.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(min_dist, max_dist))
		if Nav.ready(self):
			pos = Nav.snap(self, pos)
		var d: float = pos.distance_to(player.global_position)
		if d > farthest_d:
			farthest_d = d
			farthest = pos
		if d < min_dist * 0.8:
			continue
		var ok: bool = true
		for other in used:
			if other.distance_to(pos) < spacing:
				ok = false
				break
		if ok:
			return pos
	return farthest

func _spawn_enemy(pos: Vector3, variant: String = "zombie", level: float = 1.0) -> Enemy:
	var enemy := Enemy.new()
	enemy.variant = variant
	enemy.level_scale = level
	enemy.target = player
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.global_position = pos
	# Teleported bodies would otherwise be drawn sliding in from their previous position.
	enemy.reset_physics_interpolation()
	return enemy

func _on_enemy_died(actor: Actor) -> void:
	kills += 1
	player.on_enemy_killed(actor)
	if actor is Enemy and (actor as Enemy).variant == "brute":
		_brute_killed = true
	await get_tree().process_frame
	if get_tree().get_nodes_in_group("enemies").size() == 0 and not _selftest and not player.dead and not choosing:
		_offer_reward()

func _process(_delta: float) -> void:
	hud.wave = wave
	hud.kills = kills
	hud.alive = get_tree().get_nodes_in_group("enemies").size()

## Skewer: a Brute in the lane is staggered (not impaled); three zombies are impaled, ragdoll, get kicked off and
## thrown trailing blood, lie limp, then get back up. A fourth zombie is only shoved aside.
## A click attacks once; nothing keeps attacking afterwards, and skills drop the attack order.
func _test_auto_attack() -> void:
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.mana = player.max_mana
	player.cooldowns.clear()
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
		if player.busy and not was_busy and player.busy_skill == "basic":
			swings += 1
		was_busy = player.busy
	var idle_after: bool = not player.busy and player.attack_target == null
	# 2. Standing idle with an enemy nearby must not turn the hero or start anything.
	var yaw_before: float = player.visual.rotation.y
	var busy_during_idle: bool = false
	for i in 90:
		await get_tree().physics_frame
		busy_during_idle = busy_during_idle or player.busy
	var yaw_drift: float = absf(angle_difference(yaw_before, player.visual.rotation.y))
	# 3. A skill clears the attack order so the hero does not resume swinging when it ends.
	player.attack_target = dummy
	player._start_skill("fireball", null, Vector3(0, 0, -6))
	var cleared_by_skill: bool = player.attack_target == null
	await get_tree().create_timer(2.0).timeout
	var swings_after_skill: bool = player.busy and player.busy_skill == "basic"
	print("  auto-attack: one click -> swings=", swings, " (expected 1), idle afterwards=", idle_after, ", idle with enemy near: busy=", busy_during_idle,
		" turned ", snappedf(rad_to_deg(yaw_drift), 0.1), " deg, skill clears attack order=", cleared_by_skill, ", resumed swinging after skill=", swings_after_skill)
	dummy.queue_free()
	await get_tree().process_frame

## Hotkeys pressed mid-animation: the potion drinks immediately, usable skills cancel the swing, unusable ones do not.
func _test_hotkeys() -> void:
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.mana = player.max_mana
	player.cooldowns.clear()
	player.potions = 3
	var dummy: Enemy = _spawn_enemy(Vector3(1.8, 0, 0))
	dummy.aggro_range = 0.0
	dummy.max_health = 900.0
	dummy.health = 900.0
	await get_tree().physics_frame
	# 1. Potion during a swing.
	player.health = 40.0
	player._start_skill("basic", dummy)
	await get_tree().create_timer(0.15).timeout
	var was_busy: bool = player.busy
	Input.action_press("skill_4")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_4")
	var potion_ok: bool = player.potions == 2 and player.health > 80.0 and not player.busy
	# 2. Potion while stunned.
	player.health = 30.0
	player.cooldowns.clear()
	player.stun_time = 1.0
	await get_tree().physics_frame
	Input.action_press("skill_4")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_4")
	var stunned_ok: bool = player.potions == 1 and player.health > 60.0
	player.stun_time = 0.0
	# 3. A usable skill cancels the current swing and starts.
	player.cooldowns.clear()
	player._start_skill("basic", dummy)
	await get_tree().create_timer(0.1).timeout
	Input.action_press("skill_5")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_5")
	var skill_ok: bool = player.busy_skill == "skewer" and player.skewer_phase != 0
	player._cancel_action()
	# 4. A skill on cooldown must NOT cancel the swing.
	player.cooldowns["skewer"] = 5.0
	player._start_skill("basic", dummy)
	await get_tree().create_timer(0.1).timeout
	Input.action_press("skill_5")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_5")
	var no_cancel_ok: bool = player.busy and player.busy_skill == "basic"
	player._cancel_action()
	print("  hotkeys: potion mid-swing=", potion_ok, " (was busy=", was_busy, "), potion while stunned=", stunned_ok,
		", skill cancels swing=", skill_ok, ", skill on cooldown leaves swing alone=", no_cancel_ok)
	dummy.queue_free()
	player.cooldowns.clear()
	player.potions = 3
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
	player.goal = to
	player.has_goal = true
	var elapsed: float = 0.0
	var min_gap: float = 9999.0
	while elapsed < 12.0 and Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() > 0.8:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		player.has_goal = true
		player.goal = to
		min_gap = minf(min_gap, Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length())
	var reached: bool = Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() <= 1.0
	print("  navigation: obstacle radius ", snappedf(radius, 0.1), " m; path ", snappedf(length, 0.1), " m vs straight ", snappedf(straight, 0.1),
		" m (", path.size(), " points), path clearance ", snappedf(clearance, 0.1), " m; hero walked it: reached=", reached, " in ", snappedf(elapsed, 0.1),
		" s, closest approach ", snappedf(min_gap, 0.1), " m")
	player.has_goal = false
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
	player.mana = player.max_mana
	player.cooldowns.clear()
	player.blade_blood = 0.0
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
	player._start_skewer(player.global_position + Vector3(11, 0, 0))
	var max_impaled: int = 0
	var min_blade_dot: float = 1.0
	var phases: Array[int] = []
	var ragdoll_states: Dictionary = {}
	var brute_impaled: bool = false
	var brute_stunned: bool = false
	var killed_mid_carry: Enemy = null
	var corpse_checked: bool = false
	var corpse_ok: bool = false
	var elapsed: float = 0.0
	while elapsed < 9.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		max_impaled = maxi(max_impaled, player.skewer_impaled.size())
		if killed_mid_carry == null and player.skewer_impaled.size() == 2:
			killed_mid_carry = player.skewer_impaled[1] as Enemy
			killed_mid_carry._apply_damage(99999.0)  # dies while impaled
		brute_impaled = brute_impaled or brute.impaled
		brute_stunned = brute_stunned or brute.stun_time > 0.5
		if player.skewer_phase == 2 and player.skewer_t > 0.25 and player.model.weapon_tip != null:
			var blade: Vector3 = player.model.weapon_tip.global_position - player.model.weapon_base.global_position
			min_blade_dot = minf(min_blade_dot, blade.normalized().dot(player.skewer_dir))
		if phases.is_empty() or phases[phases.size() - 1] != player.skewer_phase:
			phases.append(player.skewer_phase)
			if player.skewer_phase == 3:
				var lanes: Array[String] = []
				for z in zombies:
					var rel: Vector3 = z.global_position - player.global_position
					lanes.append("(%.1f,%.1f)" % [rel.x, rel.z])
				print("    charge ended: travel=", snappedf(player.skewer_travel, 0.1), " t=", snappedf(player.skewer_t, 0.01), " impaled=", player.skewer_impaled.size(), " zombies rel ", ", ".join(lanes))
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
		if player.skewer_phase == 0 and not any_ragdoll and elapsed > 1.5:
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
	print("  skewer corpse (died while impaled): kicked away and ended lying on the ground=", corpse_ok)
	var states: Array = ragdoll_states.keys()
	states.sort()
	print("  skewer: impaled=", max_impaled, " phases=", phases, " ragdoll states seen=", states, " (1 hang,2 flight,3 lying,4 rising)",
		" recovered=", recovered, " flung>4m=", flung)
	print("  skewer vs Brute: impaled=", brute_impaled, " staggered=", brute_stunned, " damage taken=", int(brute.max_health - brute.health),
		"   blood stains added=", get_tree().get_nodes_in_group("stains").size() - stains_before, " blade blood=", snappedf(player.blade_blood, 0.01),
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
	player.mana = player.max_mana
	player.cooldowns.clear()
	var victim: Enemy = _spawn_enemy(Vector3(0, 0, -6.0))
	victim.aggro_range = 0.0
	victim.max_health = 500.0
	victim.health = 500.0
	await get_tree().process_frame
	player._start_skill("fireball", null, Vector3(0, 0, -6.0))
	var sheathed: bool = false
	var orb_seen: bool = false
	var orb_big: bool = false
	var elapsed: float = 0.0
	while player.busy and elapsed < 4.0:
		await get_tree().physics_frame
		await get_tree().process_frame
		elapsed += 1.0 / 60.0
		if player.model.weapon != null and not player.model.weapon.visible:
			sheathed = true
		if player._fire_orb != null and is_instance_valid(player._fire_orb):
			orb_seen = true
			orb_big = orb_big or player._fire_orb.current_size() > 0.5
	await get_tree().create_timer(1.2).timeout
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
	print("  gibs: crit kill -> ", gore_chunks, " chunks (burning=", gore_burning, ") body hidden=", gore_hidden, "; plain kill -> ", plain_chunks,
		" chunks, body visible=", plain_victim.visual.visible, "; fireball kill -> ", fire_chunks, " chunks (burning=", fire_burning, ") body hidden=",
		fire_hidden, "; pieces on the ground after 2.5 s: ", grounded)
	for node in get_tree().get_nodes_in_group("gibs"):
		node.queue_free()
	for e in [crit_victim, plain_victim, fire_victim]:
		if is_instance_valid(e):
			e.queue_free()
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
	player.queued_skill = ""
	player.has_goal = false
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
		if player.busy or player.model.current != last_clip:
			if player.busy and autos.size() < 6:
				autos.append("t=%.2f busy skill=%s clip=%s" % [elapsed, player.busy_skill, player.model.current])
			if player.model.current != last_clip:
				autos.append("t=%.2f clip %s -> %s" % [elapsed, last_clip, player.model.current])
				last_clip = player.model.current
		if player.stun_time > 0.0 and autos.size() < 12:
			autos.append("t=%.2f player stunned %.2f" % [elapsed, player.stun_time])
	print("  swarm: hero health ", int(start_health), " -> ", int(player.health), " in 8 s (", snappedf((start_health - player.health) / 8.0, 0.1),
		" dmg/s); attackers swinging at once: max ", max_swinging, ", average ", snappedf(swinging_total / frames, 0.1))
	for line in autos:
		print("    ", line)
	# A skill cast in the middle of the swarm should run to the end, not get cut short by incoming hits.
	player.mana = player.max_mana
	player.cooldowns.clear()
	player.health = player.max_health
	player._start_skill("cleave", null, player.global_position + Vector3(0, 0, 2))
	var cast: float = 0.0
	var interrupted: bool = false
	while player.busy and cast < 3.0:
		await get_tree().physics_frame
		cast += 1.0 / 60.0
	print("  cleave inside the swarm: lasted ", snappedf(cast, 0.01), " s of ", snappedf(player.busy_time, 0.01), " expected, stun at end=", player.stun_time)
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
				if z.global_position.distance_to(b.global_position) < 5.0:
					near = true
			if not near:
				lone_brutes += 1
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
	print("  per 100 Brute kills: orbs=", brute_orbs, " potions=", brute_potions)
	brute.queue_free()
	# Potion pickup.
	player.potions = 2
	var pickup := HealthOrb.new()
	pickup.is_potion = true
	add_child(pickup)
	pickup.global_position = player.global_position + Vector3(0, 0.6, 0)
	await get_tree().process_frame
	player._collect_orbs()
	print("  potion pickup: potions 2 -> ", player.potions)
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
	while not player.busy and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	print("  swing started=", player.busy, " cancellable by click-away=", player._swing_cancellable_by_move())
	player._cancel_action()
	player.attack_target = null
	print("  after cancel: busy=", player.busy)
	target.queue_free()
	await get_tree().process_frame

## Leap: slams a downed enemy (crit, pin, boot, pull-out), chops standing ground otherwise; stun shows daze stars.
func _test_leap() -> void:
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	player.mana = player.max_mana
	player.cooldowns.clear()
	var downed: Enemy = _spawn_enemy(Vector3(32, 0, -19))
	downed.aggro_range = 0.0
	downed.max_health = 800.0
	downed.health = 800.0
	await get_tree().process_frame
	downed.ragdoll_launch(Vector3.ZERO, 0.0, Vector3.ZERO)
	var t: float = 0.0
	while t < 3.0 and not Player.is_downed(downed):
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var start_health: float = downed.health
	var phases: Array = []
	var max_height: float = 0.0
	var stayed_down: bool = true
	var daze_seen: bool = false
	player._try_directional("leap", downed.global_position)
	t = 0.0
	while player.busy and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if phases.is_empty() or phases[-1] != player.leap_phase:
			phases.append(player.leap_phase)
		max_height = maxf(max_height, player.visual.position.y)
		if player.leap_phase == 4 and is_instance_valid(downed):
			stayed_down = stayed_down and Player.is_downed(downed)
		daze_seen = daze_seen or (is_instance_valid(downed) and downed._daze != null)
	print("  leap slam: phases=", phases, " peak height=", snappedf(max_height, 0.1), " damage=", snappedf(start_health - downed.health, 0.1),
		" stayed pinned during pull=", stayed_down, " daze stars seen=", daze_seen, " ended at ", player.global_position,
		" aim cleared=", player.model.weapon_aim == null, " mask restored=", player.collision_mask == (Player.LAYER_WORLD | Player.LAYER_ENEMY))
	downed.queue_free()
	await get_tree().process_frame

	# An enemy still tumbling through the air, and one that is almost back on its feet, are slammed too.
	for stage in ["flight", "rising"]:
		player.cooldowns.clear()
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
		player._try_directional("leap", target.global_position)
		var slammed: bool = player.leap_slam
		t = 0.0
		while player.busy and t < 5.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		print("  leap on ", stage, " target: slam chosen=", slammed, " damage=", snappedf(before - target.health, 0.1))
		target.queue_free()
		await get_tree().process_frame

	# Overhead chop on open ground, hitting a standing zombie beside the landing spot.
	player.cooldowns.clear()
	player.global_position = Vector3(32, 0, -12)
	player.reset_physics_interpolation()
	var standing: Enemy = _spawn_enemy(Vector3(33, 0, -19))
	standing.aggro_range = 0.0
	standing.max_health = 800.0
	standing.health = 800.0
	await get_tree().process_frame
	player._try_directional("leap", Vector3(32, 0, -19))
	phases.clear()
	t = 0.0
	while player.busy and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if phases.is_empty() or phases[-1] != player.leap_phase:
			phases.append(player.leap_phase)
	print("  leap chop: phases=", phases, " standing zombie damage=", snappedf(800.0 - standing.health, 0.1), " landed at ", player.global_position)
	standing.queue_free()
	await get_tree().process_frame

## Skewer catches knocked-down enemies; thrown bodies spread burn to enemies they hit and slam into props.
func _test_impact() -> void:
	player.global_position = Vector3(-25, 0, -25)
	player.reset_physics_interpolation()
	player.mana = player.max_mana
	player.cooldowns.clear()
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
	player._start_skewer(Vector3(-25, 0, -40))
	var caught: bool = false
	t = 0.0
	while player.busy and t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		caught = caught or player.skewer_impaled.has(lying)
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
	print("  fire blast: inner ragdolled=", thrown, " flew ", snappedf(max_away, 0.1), " m, inner burning=", inner.is_burning(),
		" rim burning=", rim.is_burning(), " rim ragdolled=", rim.is_ragdolled(), " boss ragdolled=", boss.is_ragdolled(), " boss burning=", boss.is_burning(),
		" flames=", inner._flames != null)
	await get_tree().create_timer(7.0).timeout
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
	player.stamina = player.max_stamina
	player._try_roll(player.global_position + Vector3(8, 0, 0))
	var immune_late: bool = false
	boss.global_position = player.global_position + Vector3(2.4, 0, 0.9)  # inside the roll corridor
	boss_start = boss.global_position
	for i in 40:
		await get_tree().physics_frame
		if player.rolling and player.roll_t > ROLL_CHECK_TIME and player.invulnerable_time > 0.0:
			immune_late = true
	await get_tree().create_timer(0.3).timeout
	var lateral_near: float = absf(near.global_position.z - near_start.z)
	var lateral_attacker: float = absf(attacker.global_position.z - attacker_start.z)
	var boss_moved: float = boss.global_position.distance_to(boss_start)
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
	GameSettings.master_volume = 0.8
	GameSettings.save_to_disk()
	GameSettings.custom_bindings = backup
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
	var saved: Dictionary = player.equipment.duplicate()
	for id in Items.AFFIXES:
		var slot: int = Items.AFFIXES[id]["slot"]
		var item: Dictionary = Items.make(slot, Items.Rarity.RARE, 1, id)
		player.equip(item, false)
		if not player.has_affix(id):
			failures += 1
			print("  AFFIX NOT ACTIVE: ", id)
		var target: Enemy = dummies[0]
		var result: Dictionary = Combat.resolve(player, target, 20.0, Combat.DamageType.PHYSICAL, false, 1.0, true)
		result["finisher"] = true
		target.receive(result, player.global_position)
		ItemEffects.on_kill(player, target)
		ItemEffects.on_roll_start(player)
		ItemEffects.on_roll_end(player)
		ItemEffects.power_shockwave(player, Vector3(1, 0, 0))
		ItemEffects.pull_for_cleave(player)
		var incoming: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": 10.0, "weight": 1.0}
		ItemEffects.filter_incoming(player, incoming)
		for d in dummies:
			d.health = d.max_health
			d.bleed_time = 0.0
			d.slow_time = 0.0
		player.cooldowns.clear()
		player.haste_time = 0.0
		player.riposte_time = 0.0
		player.ward_timer = 0.0
		await get_tree().process_frame
	var choices: Array[Dictionary] = Items.roll_choices(5, true, [])
	print("  items: ", Items.AFFIXES.size(), " affixes driven; reward choices=", choices.size(), " (brute offer: ",
		", ".join(choices.map(func(c): return c["name"])), "), failures=", failures)
	for d in dummies:
		d.queue_free()
	player.equipment = saved
	player.armor = player.base_armor + player.armor_stat("armor", 0.0)
	player.health = player.max_health
	await get_tree().process_frame

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
	player.mana = player.max_mana
	player.set_physics_process(true)
	if OS.get_cmdline_user_args().has("--mods"):
		for affix in ["gravewarden", "whirlpool", "frostbite", "searing", "executioner", "chain", "cleaving"]:
			player.equipment["mod_" + affix] = {"affix": affix, "name": affix, "rarity": 1, "slot": 0}
	var targets: Array[Enemy] = []
	for pos in [Vector3(0.0, 0, -2.4), Vector3(1.2, 0, -2.9), Vector3(-1.3, 0, -2.2), Vector3(0.4, 0, -4.2), Vector3(2.0, 0, -1.0), Vector3(-2.2, 0, 0.8)]:
		var z: Enemy = _spawn_enemy(pos)
		z.aggro_range = 0.0
		z.max_health = 900.0
		z.health = 900.0
		targets.append(z)
	await get_tree().create_timer(0.6).timeout
	player._start_skill(which, targets[0], null)
	for i in 22:
		await get_tree().create_timer(0.08).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_melee_%d.png" % i)
	get_tree().quit()

## `-- --skillshot=leap`: leap onto a downed zombie (a stunned one stands beside it); frames in %TEMP%/curse_leap_N.png.
func _leap_shots() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.mana = player.max_mana
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
	while not Player.is_downed(downed):
		await get_tree().physics_frame
	player._try_directional("leap", downed.global_position)
	for i in 24:
		await get_tree().create_timer(0.1).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_leap_%d.png" % i)
	get_tree().quit()

## `-- --skillshot=skewer|fireball`: run the skill on dummies and capture a frame every 0.12 s.
func _skill_shots(which: String) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	player.mana = player.max_mana
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
		player._start_skewer(Vector3(1.8, 0, -12.0))
	else:
		player._start_skill("fireball", null, Vector3(0.6, 0, -4.4))
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
	player.aiming_id = "fireball"
	player.aiming_action = "skill_3"
	await get_tree().create_timer(0.8).timeout
	var cursor: Vector3 = Vector3(1.2, 0, -5.2)
	for i in 6:
		player._update_aim(cursor)
		await get_tree().process_frame
	var lit: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if (node as Actor).highlighted:
			lit += 1
	print("aim: point=", player.aim_point, " highlighted=", lit, " of ", cluster.size(), " (blast radius ", Projectile.BLAST_RADIUS, ")")
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_aim.png")
	# Cast it: the projectile must land on the aimed point.
	player._clear_aim()
	player._start_skill("fireball", null, player.aim_point_for("fireball", cursor))
	for i in 3:
		player._tick_busy(0.3)
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
	player.cooldowns = {"power": 1.1, "cleave": 2.0, "fireball": 0.3, "dodge": 0.6}
	player.mana = 9.0
	await get_tree().create_timer(0.15).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hud_0.png")
	player.cooldowns = {"power": 0.0, "cleave": 0.9, "fireball": 0.0, "dodge": 0.0}
	await get_tree().create_timer(0.1).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_hud_1.png")
	get_tree().quit()

## `-- --rewardshot`: show the reward screen as it would appear after killing a Brute on wave 5.
func _reward_shot() -> void:
	wave = 5
	_brute_killed = true
	_offer_reward()
	await get_tree().create_timer(2.2).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_reward.png")
	get_tree().quit()

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
	player.stamina = player.max_stamina
	player._try_roll(player.global_position + Vector3(5, 0, 0))
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
		player.blade_blood = 0.9
		player._update_blade_blood(0.0)
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
	player.mana = player.max_mana
	var target: Actor = player.enemy_near(player.global_position, 20.0)
	if target:
		player.attack_target = target
	var shots: int = 8 if OS.get_cmdline_user_args().has("--duel") else 4
	for i in shots:
		await get_tree().create_timer(0.3).timeout
		print("shot ", i, " busy=", player.busy, " t=", snappedf(player.busy_t, 0.01), " clip=", player.model.current,
			" pos=", snappedf(player.model.anim.current_animation_position, 0.01), " speed=", player.model.anim.speed_scale,
			" hitpause=", player.hitpause, " target=", player.attack_target, " mana=", int(player.mana))
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(OS.get_environment("TEMP") + "/curse_shot_%d.png" % i)
	get_tree().quit()

# --- Headless self test ---------------------------------------------------------

func _run_selftest() -> void:
	print("SELFTEST start")
	# `--only=NAME` runs a single test, so changes can be checked without the whole suite.
	for arg in OS.get_cmdline_user_args():
		if arg == "--only=gibs":
			await _test_gibs()
			print("SELFTEST done")
			get_tree().quit()
			return
		if arg == "--only=swarm":
			await _test_swarm()
			print("SELFTEST done")
			get_tree().quit()
			return
		if arg == "--only=items":
			await _test_items()
			print("SELFTEST done")
			get_tree().quit()
			return
		if arg == "--only=balance":
			await _test_balance()
			print("SELFTEST done")
			get_tree().quit()
			return
		if arg == "--only=leap":
			await _test_leap()
			print("SELFTEST done")
			get_tree().quit()
			return
		if arg == "--only=impact":
			await _test_impact()
			print("SELFTEST done")
			get_tree().quit()
			return
		if arg == "--only=fireblast":
			await _test_fire_blast()
			print("SELFTEST done")
			get_tree().quit()
			return
		if arg == "--only=autoattack":
			await _test_auto_attack()
			print("SELFTEST done")
			get_tree().quit()
			return
	for action in ["click", "alt_skill", "stand_still", "restart", "skill_1", "skill_4"]:
		print("  input action ", action, ": ", InputMap.has_action(action))
	print("  camera current: ", rig.camera.current, "  pitch: ", rig.camera.rotation_degrees.x, "  fov: ", rig.camera.fov)

	_test_settings()
	await _test_zoom()
	await _test_hotkeys()
	await _test_navigation()
	await _test_roll_shove()
	await _test_skewer()
	await _test_fireball()
	await _test_items()

	var zombies: Array[Enemy] = []
	for i in 3:
		zombies.append(_spawn_enemy(Vector3(2.0 + i * 1.5, 0, 3.0)))
	player.attack_target = zombies[0]
	player.mana = player.max_mana
	await get_tree().create_timer(0.5).timeout
	# Exercise hotbar skills directly on the nearest zombie.
	for id in ["power", "cleave", "fireball"]:
		var target: Actor = player.enemy_near(player.global_position, 20.0)
		if target == null:
			break
		player.queued_skill = id
		player.queued_target = target
		await get_tree().create_timer(1.6).timeout
	await get_tree().create_timer(6.0).timeout

	# Roll: should move the hero ~4 m, grant brief invulnerability and not leave collision disabled.
	var before: Vector3 = player.global_position
	player.stamina = player.max_stamina
	player._try_roll(player.global_position + Vector3(5, 0, 0))
	var roll_invuln: bool = player.invulnerable_time > 0.0
	await get_tree().create_timer(0.8).timeout
	print("  roll: moved ", snappedf(player.global_position.distance_to(before), 0.1), " m, invulnerable during=", roll_invuln,
		", mask restored=", player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY), ", rolling=", player.rolling)

	# Death: a killed zombie must play its death clip and keep playing it (not freeze on frame 0).
	var victim: Enemy = _spawn_enemy(Vector3(1.5, 0, -3.0))
	victim.health = 1.0
	await get_tree().create_timer(0.2).timeout
	victim.receive(Combat.resolve(player, victim, 50.0, Combat.DamageType.PHYSICAL, false), player.global_position)
	await get_tree().create_timer(0.1).timeout
	var pos_a: float = victim.model.anim.current_animation_position
	await get_tree().create_timer(0.6).timeout
	var pos_b: float = victim.model.anim.current_animation_position
	print("  zombie death: clip=", victim.model.current, " dead=", victim.dead, " pos ", snappedf(pos_a, 0.01), " -> ", snappedf(pos_b, 0.01))

	var names := ["MISS", "BLOCK", "HIT", "CRIT", "CRUSH", "WOUND"]
	var parts: Array[String] = []
	for key in Combat.tally.keys():
		parts.append("%s=%d" % [names[int(key)], int(Combat.tally[key])])
	print("  outcomes: ", ", ".join(parts))
	print("  kills: ", kills, "  player health: ", int(player.health), "  mana: ", int(player.mana))
	print("SELFTEST done")
	get_tree().quit()