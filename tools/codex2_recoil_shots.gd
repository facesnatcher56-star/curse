extends SceneTree
## Codex 2 visual review of monster body recoil across the supported resolution and UI-scale matrix.
## Run visibly with: --script res://tools/codex2_recoil_shots.gd -- --codex2shots=ABSOLUTE_OUTPUT_DIR

const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const SCALES: Array[float] = [0.5, 1.0, 1.5]

var output_dir := ""
var game: Node3D
var target: Enemy

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--codex2shots="):
			output_dir = arg.substr(14)
	if output_dir.is_empty():
		push_error("Pass --codex2shots=ABSOLUTE_OUTPUT_DIR")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	game = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	_run()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = output_dir.path_join(name + ".png")
	var error: Error = image.save_png(path)
	print("CODEX2_RECOIL_CAPTURE ", path, " size=", image.get_size(), " error=", error)

func _source_on(side: String) -> Vector3:
	var forward := Vector3(sin(target.visual.rotation.y), 0.0, cos(target.visual.rotation.y))
	var left := forward.rotated(Vector3.UP, PI * 0.5)
	match side:
		"front": return target.global_position + forward * 2.0
		"rear": return target.global_position - forward * 2.0
		"left": return target.global_position + left * 2.0
		_: return target.global_position - left * 2.0

func _run() -> void:
	await _frames(45)
	var player: Player = game.player
	var rig: CameraRig = game.rig
	game.director.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await process_frame
	target = game.director.spawn_enemy(player.global_position + Vector3(0.0, 0.0, 3.5), "zombie", 1.0)
	target.aggro_range = 0.0
	target.alert_delay = 999.0
	target.max_health = 5000.0
	target.health = 5000.0
	target.set_physics_process(false)
	rig.set_process(false)
	var focus: Vector3 = target.global_position + Vector3.UP * 0.9
	rig.camera.global_position = focus + Vector3(3.0, 2.5, 4.0)
	rig.camera.look_at(focus)
	var window: Window = root
	var old_size: Vector2i = window.size
	var old_screen: int = window.current_screen
	var old_borderless: bool = window.borderless
	var old_ui_scale: float = GameSettings.ui_size
	for resolution in RESOLUTIONS:
		var screen: int = 0 if resolution.y > 1080 else mini(1, DisplayServer.get_screen_count() - 1)
		window.current_screen = screen
		window.borderless = true
		window.size = resolution
		var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
		window.position = DisplayServer.screen_get_position(screen) + (screen_size - resolution).max(Vector2i.ZERO) / 2
		print("CODEX2_RECOIL_CASE screen=", screen, " monitor_size=", screen_size, " resolution=", resolution)
		for scale in SCALES:
			GameSettings.ui_size = scale
			GameSettings.apply_ui_scale()
			await _frames(12)
			var cases: Array[Array] = [["crushing", "front"]]
			if resolution == Vector2i(1280, 720) and is_equal_approx(scale, 1.0):
				cases.clear()
				for tier in ["light", "heavy", "crushing"]:
					for side in ["front", "rear", "left", "right"]:
						cases.append([tier, side])
			for test_case in cases:
				var tier: String = test_case[0]
				var side: String = test_case[1]
				target.stun_time = 0.0
				target.hitpause = 0.0
				target.health = target.max_health
				target.model.reaction.clear()
				target.model.loop("idle")
				var weight: float = 0.4 if tier == "light" else 1.5 if tier == "heavy" else 2.2
				var hit_from: Vector3 = _source_on(side)
				var away: Vector3 = target.global_position - hit_from
				away.y = 0.0
				var outcome_scale: float = 1.5 if tier == "crushing" else 1.0
				target.model.react(away.normalized(), BodyRecoil.peak_for(weight, outcome_scale, target.knock_resist))
				var tag: String = "%dx%d_scale%s_%s_%s" % [resolution.x, resolution.y, str(scale), tier, side]
				await create_timer(0.12).timeout
				await _capture(tag + "_impact")
				await create_timer(0.3).timeout
				await _capture(tag + "_recovery")
				if resolution == Vector2i(1280, 720) and tier == "crushing" and side == "front":
					await create_timer(0.55).timeout
					await _capture(tag + "_settled")
	GameSettings.ui_size = old_ui_scale
	GameSettings.apply_ui_scale()
	window.borderless = old_borderless
	window.size = old_size
	window.current_screen = old_screen
	print("CODEX2_RECOIL_SHOTS_DONE")
	quit(0)
