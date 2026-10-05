extends Node3D
## Builds the world: arena, hero, camera, HUD and menus, then hands the run to the RunDirector.
## Developer modes (`-- --selftest` and the screenshot tools) are in dev/dev_harness.gd.

var arena: Arena
var player: Player
var hud: Hud
var pause_menu: PauseMenu
var rig: CameraRig
var director: RunDirector
var location: CryptRoad   # set when the job is played in an authored location instead of the wave arena
var world_environment: Environment

var _boot_ms: int = 0

## `-- --timing` prints how long each stage of starting a run takes (and quits once the first wave is up).
func _mark(label: String) -> void:
	if OS.get_cmdline_user_args().has("--timing"):
		var now: int = Time.get_ticks_msec()
		print("[boot] %-22s +%4d ms  (total %d ms since engine start)" % [label, now - _boot_ms, now])
		_boot_ms = now

func _ready() -> void:
	_boot_ms = Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("--crypt") and TownState.job.is_empty():   # developer shortcut: straight into the Crypt Road
		TownState.job = TownState.crypt_road_offer()
	# Pausing (the pause menu) must freeze the whole world, so this node and everything under it is pausable. The
	# menus and HUD (the CanvasLayer below) and the input relay keep running while paused.
	get_tree().paused = false
	var relay := Node.new()
	relay.set_script(preload("res://game/pause_relay.gd"))
	add_child(relay)
	relay.connect("unhandled", _unhandled_input)
	Fx.reset_time()
	GameSettings.boot()
	_mark("settings")
	_build_world()
	_apply_job_mood(TownState.job)
	_mark("world + nav bake")

	player = Player.new()
	add_child(player)
	TownScene._apply_run_gear(player)   # what the town holds (nothing, for a run that did not come from town)
	if location != null:
		player.global_position = CryptRoad.START
		for arg in OS.get_cmdline_user_args():   # `-- --crypt --at=x,z`: start somewhere along the road (developer tool)
			if arg.begins_with("--at="):
				var xz: PackedStringArray = arg.substr(5).split(",")
				player.global_position = Vector3(float(xz[0]), 0.0, float(xz[1]))
	_mark("hero model")
	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.72, 0.45)
	torch.light_energy = 1.1
	torch.omni_range = 9.0
	torch.position = Vector3(0, 3.0, 0)
	player.add_child(torch)

	rig = CameraRig.new()
	rig.fog_env = world_environment
	if OS.get_cmdline_user_args().has("--zoom"):
		rig.offset = Vector3(0.0, 2.6, 4.2)
		rig.pitch_degrees = -22.0
	add_child(rig)
	rig.target = player
	rig.global_position = player.global_position

	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
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

	_mark("camera + hud + menus")
	director = RunDirector.new()
	director.player = player
	director.hud = hud
	director.selftest = OS.get_cmdline_user_args().has("--selftest")
	add_child(director)
	if not TownState.job.is_empty() and not director.selftest:
		director.set_job(TownState.job)

	# Developer modes (self-test, screenshot and pose tools) live in DevHarness and take over the run when asked for.
	var dev := DevHarness.new()
	dev.game = self
	add_child(dev)
	if dev.run_from_args():
		return
	rig.start_zoomed_out()
	# The navigation map only learns about the arena a physics frame or two after it is built (and, coming from the menu,
	# still holds the old scene's data until then); spawn the first wave once it is ready.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_mark("2 physics frames")
	if location != null:
		await location.wait_for_navigation()
		director.start_location(location)
		_mark("location populated")
	else:
		director.start_wave()
		_mark("first wave spawned")
	if OS.get_cmdline_user_args().has("--startshot"):   # a normal run's opening view, for judging the start zoom by eye
		await get_tree().create_timer(2.5).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_start.png")
		get_tree().quit()
	if OS.get_cmdline_user_args().has("--timing"):
		await get_tree().create_timer(1.0).timeout
		_mark("1 s of play")
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not pause_menu.is_open():
		pause_menu.open()
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
	NightSky.apply(environment)
	env.environment = environment
	world_environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_color = Color(0.8, 0.85, 1.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	if String(TownState.job.get("site", "")) == CryptRoad.SITE_ID:
		arena = CryptRoad.make_arena()
		add_child(arena)
		arena.build(false)   # the location puts its props down first, then bakes the navigation mesh itself
		location = CryptRoad.new()
		add_child(location)
		location.build(arena)
		environment.ambient_light_energy *= CryptRoad.AMBIENT_MULT
		environment.fog_density *= CryptRoad.FOG_MULT
	else:
		arena = Arena.new()
		add_child(arena)
		arena.build()
	if hud != null:
		hud.arena = arena

## A job's modifiers set the mood of the whole run: darker, brighter, foggier.
func _apply_job_mood(offer: Dictionary) -> void:
	for id in offer.get("modifiers", []):
		var def: RunModifierDef = TownDb.modifier(String(id))
		if def != null:
			world_environment.ambient_light_energy *= def.ambient_mult
			world_environment.fog_density *= def.fog_mult

func _process(_delta: float) -> void:
	hud.wave = director.wave
	hud.kills = director.kills
	hud.objective = director.objective_line()
	hud.alive = get_tree().get_nodes_in_group("enemies").size()
