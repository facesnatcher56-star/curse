extends Node3D
## Builds the world: arena, hero, camera, HUD and menus, then hands the run to the RunDirector.
## Developer modes (`-- --selftest` and the screenshot tools) are in dev/dev_harness.gd.

var arena: Arena
var player: Player
var hud: Hud
var pause_menu: PauseMenu
var rig: CameraRig
var director: RunDirector

func _ready() -> void:
	# The reward screen pauses the game; this node must keep receiving input while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameSettings.boot()
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
	pause_menu.restart_requested.connect(func() -> void: LoadingScreen.go(get_tree(), "res://game/main.tscn"))
	pause_menu.main_menu_requested.connect(func() -> void: get_tree().change_scene_to_file("res://game/menu.tscn"))
	layer.add_child(pause_menu)

	director = RunDirector.new()
	director.player = player
	director.hud = hud
	director.selftest = OS.get_cmdline_user_args().has("--selftest")
	add_child(director)

	# Developer modes (self-test, screenshot and pose tools) live in DevHarness and take over the run when asked for.
	var dev := DevHarness.new()
	dev.game = self
	add_child(dev)
	if dev.run_from_args():
		return
	# The navigation map only learns about the arena a physics frame or two after it is built (and, coming from the menu,
	# still holds the old scene's data until then); spawn the first wave once it is ready.
	await get_tree().physics_frame
	await get_tree().physics_frame
	director.start_wave()

func _input(event: InputEvent) -> void:
	Gamepad.note_event(event)   # tracks whether the pad or the mouse/keyboard is in use (hints, cursor, aim)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not director.choosing and not pause_menu.is_open():
		pause_menu.open()
		return
	if director.choosing:
		for i in 3:
			if event.is_action_pressed("skill_%d" % (i + 1)):
				director.choose(i)
				return
		if event.is_action_pressed("skill_4"):
			director.choose(-1)
			return
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			for i in hud.card_rects.size():
				if hud.card_rects[i].has_point(click.position):
					director.choose(i)
					return
		return
	if event.is_action_pressed("restart") and player.dead:
		get_tree().reload_current_scene()

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

func _process(_delta: float) -> void:
	hud.wave = director.wave
	hud.kills = director.kills
	hud.alive = get_tree().get_nodes_in_group("enemies").size()
