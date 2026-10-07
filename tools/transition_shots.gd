extends SceneTree
## Developer check of the hero's combat animation transitions, with contact sheets: ordinary hit and recovery, a swing broken by a hit,
## a swing broken by a knockdown, get-up into walking, and death / revival. It prints how far the sword hand jumps between frames
## (a snap shows as one big step) and which clip is playing.
## Run with a real window: GODOT_HEADLESS= tools/run_godot.sh LOG 120 -- --script res://tools/transition_shots.gd -- --transshots=DIR
## (user arguments make it a developer session: the production save is never touched).

const TILE := 360

var out_dir: String = ""
var player: Player
var skeleton: Skeleton3D
var hand: int = -1
var last_hand: Vector3 = Vector3.ZERO
var worst_step: float = 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--transshots="):
			out_dir = arg.substr(13)
	var main: Node = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_run()

func _hand_pos() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin

## Waits `seconds` of game time one frame at a time, tracking the biggest per-frame jump of the sword hand.
func _watch(seconds: float, label: String, shots: Array[Image] = [], shot_times: Array = []) -> void:
	var t: float = 0.0
	var step_max: float = 0.0
	var next: int = 0
	last_hand = _hand_pos()
	while t < seconds:
		await physics_frame
		await process_frame
		t += 1.0 / 60.0
		var h: Vector3 = _hand_pos()
		step_max = maxf(step_max, h.distance_to(last_hand))
		last_hand = h
		if next < shot_times.size() and t >= float(shot_times[next]):
			shots.append(await _grab())
			next += 1
	worst_step = maxf(worst_step, step_max)
	print("%-28s max hand step %.3f m  clip=%s stun=%.2f kd=%s busy=%s" % [label, step_max, player.model.current, player.stun_time, player.knockdown.phase_name(), player.skills.busy])

func _grab() -> Image:
	var shot: Image = root.get_viewport().get_texture().get_image()
	var c: Vector2i = shot.get_size() / 2
	var tile: Image = shot.get_region(Rect2i(c.x - 300, c.y - 330, 600, 600))
	tile.resize(TILE, TILE)
	return tile

func _sheet(tiles: Array[Image], columns: int, name: String) -> void:
	var rows: int = ceili(float(tiles.size()) / columns)
	var sheet: Image = Image.create(columns * TILE, rows * TILE, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, TILE, TILE), Vector2i((i % columns) * TILE, (i / columns) * TILE))
	sheet.save_png("%s/%s.png" % [out_dir, name])
	print("wrote ", name)

func _reset() -> void:
	if player.dead:
		player.revive_at(Vector3.ZERO)
	player.knockdown.reset()
	player.skills.cancel_action()
	player.stun_time = 0.0
	player.health = player.max_health
	player.invulnerable_time = 0.0
	player.global_position = Vector3.ZERO
	player.model.loop("idle_alert")
	player.visual.rotation.y = PI * 0.62

func _swing() -> void:
	player.skills.start_skill("basic", null, Vector3(3, 0, 1))

func _run() -> void:
	for i in 40:
		await process_frame
	player = get_first_node_in_group("player")
	var rig: CameraRig = get_first_node_in_group("camera_rig")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	for h in current_scene.find_children("*", "Hud", true, false):
		(h as CanvasItem).visible = false
	rig.set_zoom_now(0.75)
	rig.pitch_degrees = -30.0
	skeleton = player.model.find_children("*", "Skeleton3D", true, false)[0]
	hand = skeleton.find_bone("RightHand")
	var light: Dictionary = {"damage": 1.0, "weight": 1.0}
	var heavy: Dictionary = {"damage": 99999.0, "weight": 9.0}
	var tiles: Array[Image] = []

	# 1. an ordinary stagger from standing: flinch, then back to idle
	_reset()
	await create_timer(0.3).timeout
	player._gain_stun(0.5, light)
	await _watch(0.9, "light hit from idle", tiles, [0.08, 0.2, 0.35, 0.55, 0.8])
	var flinch_clip: String = player.model.current
	print("  after recovery clip=", flinch_clip)

	# 2. a swing broken by a stagger: the swing finishes, the flinch then ends with the stun
	_reset()
	await create_timer(0.3).timeout
	_swing()
	await _watch(0.25, "swing start")
	player._gain_stun(0.5, light)
	await _watch(1.2, "light hit during swing", tiles, [0.1, 0.3, 0.5, 0.7, 0.95])

	# 3. a swing broken by a knockdown
	_reset()
	await create_timer(0.3).timeout
	_swing()
	await _watch(0.2, "swing start")
	player._gain_stun(0.9, heavy)
	await _watch(0.9, "knockdown from swing", tiles, [0.03, 0.08, 0.2, 0.4, 0.7])
	# 4. get-up into locomotion
	await _watch(0.9, "get-up")
	var tail: Array[Image] = []
	player.movement.goal = player.global_position + Vector3(4, 0, 0)
	player.movement.has_goal = true
	await _watch(0.7, "walk off after get-up", tail, [0.1, 0.3, 0.6])
	tiles.append_array(tail)
	_sheet(tiles, 5, "transitions_hit_knockdown_getup")

	# 5. death and revival
	tiles = []
	_reset()
	await create_timer(0.3).timeout
	_swing()
	await _watch(0.2, "swing start")
	player._apply_damage(99999.0)
	await _watch(1.6, "death from swing", tiles, [0.05, 0.3, 0.8, 1.5])
	player.revive_at(Vector3.ZERO)
	await _watch(0.9, "revive", tiles, [0.05, 0.4, 0.85])
	_sheet(tiles, 4, "transitions_death_revive")
	print("worst step over all: %.3f m" % worst_step)
	quit(0)
