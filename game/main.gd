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

	# Developer modes (self-test, screenshot and pose tools) live in DevHarness and take over the run when asked for.
	var dev := DevHarness.new()
	dev.game = self
	add_child(dev)
	if dev.run_from_args():
		return
	_next_wave()

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
