extends SceneTree
## Developer contact sheets for the hero knockdown, close enough to judge limbs and weight: the fall, the downed hold, the brace, the knee
## under the body, the rise and the stand (each from a three-quarter and a side view), and a death triggered in each phase.
## Run with a real window: GODOT_HEADLESS= tools/run_godot.sh LOG 120 -- --script res://tools/knockdown_shots.gd -- --knockshots=DIR
## (user arguments make it a developer session: the production save is never touched).

const FRAMES := [["impact_early", Knockdown.Phase.IMPACT, 0.08], ["impact_late", Knockdown.Phase.IMPACT, 0.28],
	["downed", Knockdown.Phase.DOWNED, 0.2], ["brace", Knockdown.Phase.GETTING_UP, 0.12], ["knee_under", Knockdown.Phase.GETTING_UP, 0.3],
	["rising", Knockdown.Phase.GETTING_UP, 0.43], ["standing", Knockdown.Phase.NONE, 0.0]]
const VIEWS := [PI * 0.62, PI * 0.5]
const TILE := 400

var out_dir: String = ""
var player: Player
var kd: Knockdown
var rig: CameraRig

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--knockshots="):
			out_dir = arg.substr(13)
	var main: Node = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_run()

func _grab() -> Image:
	await process_frame
	await process_frame
	await process_frame
	var shot: Image = root.get_viewport().get_texture().get_image()
	var c: Vector2i = shot.get_size() / 2
	var tile: Image = shot.get_region(Rect2i(c.x - 330, c.y - 380, 660, 660))
	tile.resize(TILE, TILE)
	return tile

func _stand() -> void:
	player.set_physics_process(true)
	if player.dead:
		player.revive_at(Vector3.ZERO)
	kd.reset()
	player.stun_time = 0.0
	player.health = player.max_health
	player.invulnerable_time = 0.0
	player.global_position = Vector3.ZERO
	player.model.loop("idle_alert")
	player.set_physics_process(false)

func _pose_at(phase: int, t: float) -> void:
	kd.phase = phase
	kd.phase_time = t
	kd._pose()

func _sheet(tiles: Array[Image], columns: int, name: String) -> void:
	var rows: int = ceili(float(tiles.size()) / columns)
	var sheet: Image = Image.create(columns * TILE, rows * TILE, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, TILE, TILE), Vector2i((i % columns) * TILE, (i / columns) * TILE))
	sheet.save_png("%s/%s.png" % [out_dir, name])
	print("wrote ", name)

func _run() -> void:
	for i in 40:
		await process_frame
	player = get_first_node_in_group("player")
	rig = get_first_node_in_group("camera_rig")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	for h in current_scene.find_children("*", "Hud", true, false):
		(h as CanvasItem).visible = false
	kd = player.knockdown
	rig.set_zoom_now(0.75)
	rig.pitch_degrees = -30.0
	# the fall, frame by frame (the state machine is posed by hand so every frame is exactly where it says)
	var tiles: Array[Image] = []
	for view in VIEWS:
		for frame in FRAMES:
			_stand()
			await create_timer(0.3).timeout
			player.visual.rotation.y = view
			if frame[1] != Knockdown.Phase.NONE:
				var began: bool = kd.begin()
				_pose_at(frame[1], frame[2])
				print(frame[0], " began=", began, " authored=", kd._authored(), " clip=", player.model.current, " t=", player.model.anim.current_animation_position)
			tiles.append(await _grab())
	_sheet(tiles, FRAMES.size(), "knockdown_sheet")
	# death from each phase, shortly after, midway and settled
	tiles = []
	for pair in [["impact", Knockdown.Phase.IMPACT, 0.12], ["impact_late", Knockdown.Phase.IMPACT, 0.27], ["downed", Knockdown.Phase.DOWNED, 0.2],
			["brace", Knockdown.Phase.GETTING_UP, 0.15], ["knee", Knockdown.Phase.GETTING_UP, 0.33]]:
		_stand()
		await create_timer(0.3).timeout
		player.visual.rotation.y = VIEWS[0]
		kd.begin()
		_pose_at(pair[1], pair[2])
		await process_frame
		player.set_physics_process(true)
		player._apply_damage(99999.0)
		for wait in [0.05, 0.4, 1.6]:
			await create_timer(wait).timeout
			tiles.append(await _grab())
	_sheet(tiles, 3, "knockdown_deaths")
	# revive: a valid neutral stand
	_stand()
	kd.begin()
	_pose_at(Knockdown.Phase.DOWNED, 0.2)
	player.set_physics_process(true)
	player._apply_damage(99999.0)
	await create_timer(1.2).timeout
	player.revive_at(Vector3.ZERO)
	await create_timer(0.8).timeout
	tiles = [await _grab()]
	_sheet(tiles, 1, "knockdown_revive")
	quit(0)
