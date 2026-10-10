extends SceneTree
## Real-scene validation of the combat impact presentation in the actual game scene at the normal gameplay camera: a thrown body into
## a wall, a heavy skill (Earthshatter) landing on a pack, and critical vs crushing blows side by side. Records peak concurrent sound
## voices and camera shake, and checks the settings toggles (screen shake, slow motion). Frames are cropped around the action and
## written as contact sheets. Run with a real window:
## GODOT_HEADLESS= tools/run_godot.sh LOG 150 -- --script res://tools/impact_scene_shots.gd -- --impactscene=DIR
## (user arguments make it a developer session: the production save is never touched). Exit code 1 if a check fails.

const TILE := 420

var out_dir: String = ""
var main: Node
var player: Player
var failures: int = 0
var peak_voices: int = 0
var peak_shake: float = 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--impactscene="):
			out_dir = arg.substr(14)
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_run()

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  "), label, "  ", detail)
	if not ok:
		failures += 1

func _spawn(pos: Vector3, hp: float = 5000.0) -> Enemy:
	var e: Enemy = main.director.spawn_enemy(pos, "zombie", 1.0)
	e.aggro_range = 0.0
	e.max_health = hp
	e.health = hp
	return e

func _grab(centre: Vector2 = Vector2(0, -120), tight: int = 0) -> Image:
	var shot: Image = root.get_viewport().get_texture().get_image()
	shot.convert(Image.FORMAT_RGBA8)
	var c: Vector2i = shot.get_size() / 2 + Vector2i(centre)
	var half: int = tight if tight > 0 else mini(shot.get_height() * 2 / 5, 400)
	var r := Rect2i(c.x - half, c.y - half, half * 2, half * 2).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	var tile: Image = shot.get_region(r)
	tile.resize(TILE, TILE)
	return tile

func _region(centre: Vector2) -> Image:
	var shot: Image = root.get_viewport().get_texture().get_image()
	shot.convert(Image.FORMAT_RGBA8)
	var k: float = float(shot.get_width()) / root.get_viewport().get_visible_rect().size.x
	var r := Rect2i(Vector2i(centre * k) - Vector2i(80, 80), Vector2i(160, 160)).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	return shot.get_region(r)

func _changed_pixels(a: Image, b: Image) -> int:
	var n: int = 0
	var w: int = mini(a.get_width(), b.get_width())
	var h: int = mini(a.get_height(), b.get_height())
	for y in h:
		for x in w:
			if absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance()) > 0.06:
				n += 1
	return n

func _sample_state() -> void:
	peak_voices = maxi(peak_voices, get_nodes_in_group("sfx_voice").size())
	var rig: Node = main.rig
	peak_shake = maxf(peak_shake, float(rig._shake))

## Runs `seconds` of real time, taking a frame at each of `times` (real seconds) and tracking voices and shake.
func _film(times: Array, centre: Vector2 = Vector2(0, -120)) -> Array[Image]:
	var tiles: Array[Image] = []
	var start: int = Time.get_ticks_msec()
	var next: int = 0
	while next < times.size():
		await process_frame
		_sample_state()
		if float(Time.get_ticks_msec() - start) / 1000.0 >= float(times[next]):
			await RenderingServer.frame_post_draw
			tiles.append(_grab(centre))
			next += 1
	return tiles

func _sheet(tiles: Array[Image], columns: int, file: String) -> void:
	if out_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rows: int = ceili(float(tiles.size()) / columns)
	var sheet: Image = Image.create(columns * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, TILE, TILE), Vector2i((i % columns) * TILE, (i / columns) * TILE))
	sheet.save_png(out_dir.path_join(file))
	print("saved ", out_dir.path_join(file))

func _reset_hero() -> void:
	player.global_position = Vector3.ZERO
	player.health = player.max_health
	player.skills.cancel_action()
	player.movement.has_goal = false

func _run() -> void:
	await create_timer(1.0).timeout
	player = main.player
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	player.invulnerable_time = 999.0
	_reset_hero()

	# 1. A thrown body into a wall, in the real arena at the real camera.
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 3, 0.6)
	shape.shape = box
	wall.add_child(shape)
	var wall_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	wall_mesh.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.32, 0.29, 0.25)
	wall_mesh.material_override = wm
	wall.add_child(wall_mesh)
	main.add_child(wall)
	wall.global_position = Vector3(0, 1.5, -6)
	var thrown: Enemy = _spawn(Vector3(0, 0, -2.5))
	await create_timer(0.3).timeout
	var seen_before: int = Fx._recent_impacts.size()
	thrown.ragdoll_launch(Vector3(0, 0, -11), 3.0, Vector3(4, 0, 2))
	peak_voices = 0
	peak_shake = 0.0
	var tiles: Array[Image] = await _film([0.12, 0.3, 0.5, 0.65, 0.8, 1.0], Vector2(0, -230))
	_sheet(tiles, 3, "thrown_body_wall.png")
	check("thrown body registered a wall impact", Fx._recent_impacts.has("body_wall"), "recent=%s" % [Fx._recent_impacts.keys()])
	check("thrown body: voices stay capped", peak_voices <= Sfx.MAX_VOICES, "peak voices %d (cap %d)" % [peak_voices, Sfx.MAX_VOICES])
	check("thrown body: camera shake bounded", peak_shake <= 0.35, "peak shake %.3f" % peak_shake)
	await create_timer(2.5).timeout
	wall.queue_free()
	thrown.queue_free()

	# 2. Earthshatter landing on a pack.
	_reset_hero()
	var pack: Array[Enemy] = []
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		pack.append(_spawn(Vector3(0, 0, -3.2) + Vector3(sin(a), 0, cos(a)) * 1.6))
	await create_timer(0.3).timeout
	player.stats.ult_charge = player.stats.ult_cost("earthshatter")
	peak_voices = 0
	peak_shake = 0.0
	player.skills.try_directional("earthshatter", Vector3(0, 0, -6))
	check("earthshatter started in the real scene", player.earthshatter.phase != 0)
	tiles = await _film([0.4, 0.9, 1.3, 1.5, 1.7, 2.0, 2.4, 3.0, 3.6], Vector2(0, -120))
	_sheet(tiles, 3, "heavy_skill_landing.png")
	check("earthshatter: voices stay capped", peak_voices <= Sfx.MAX_VOICES, "peak voices %d (cap %d)" % [peak_voices, Sfx.MAX_VOICES])
	check("earthshatter: camera shake bounded", peak_shake <= 0.35, "peak shake %.3f" % peak_shake)
	var airborne: int = 0
	for e in pack:
		if is_instance_valid(e) and (e.dead or e.health < e.max_health):
			airborne += 1
	check("earthshatter hit the pack", airborne >= 3, "%d of 6 hurt" % airborne)
	await create_timer(2.5).timeout
	for e in pack:
		if is_instance_valid(e):
			e.queue_free()

	# 3. Critical vs crushing at the normal camera: the same enemy and spot, one tier then the other.
	_reset_hero()
	var dummy: Enemy = _spawn(Vector3(2.2, 0, 0))
	await create_timer(0.3).timeout
	var chest: Vector3 = dummy.global_position + Vector3(0, 1.1, 0)
	var away: Vector3 = Vector3.RIGHT
	var rows: Array[Image] = []
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var screen_pt: Vector2 = cam.unproject_position(chest)
	var footprints: Array = []
	for tier in [1, 2]:
		Fx._recent_impacts.clear()
		await RenderingServer.frame_post_draw
		var base: Image = _region(screen_pt)
		Fx.melee_impact(dummy, chest, away, tier, tier)
		var peak: int = 0
		var start: int = Time.get_ticks_msec()
		var shots: Array[float] = [0.03, 0.07, 0.14]
		var next: int = 0
		while next < shots.size():
			await process_frame
			if float(Time.get_ticks_msec() - start) / 1000.0 >= shots[next]:
				await RenderingServer.frame_post_draw
				var now: Image = _region(screen_pt)
				peak = maxi(peak, _changed_pixels(base, now))
				rows.append(_grab((screen_pt - Vector2(root.get_viewport().get_visible_rect().size) / 2.0) * (float(root.get_viewport().get_texture().get_width()) / root.get_viewport().get_visible_rect().size.x), 160))
				next += 1
		footprints.append(peak)
		await create_timer(0.8).timeout
	_sheet(rows, 3, "critical_vs_crushing.png")
	check("critical and crushing profiles differ", Fx.impact_profile(Combat.Outcome.CRITICAL, 1.0).tier != Fx.impact_profile(Combat.Outcome.CRUSHING, 1.0).tier)
	print("changed-pixel footprint at normal camera (160px window around the chest): critical %d, crushing %d" % [footprints[0], footprints[1]])

	# 4. Settings toggles.
	var rig: Node = main.rig
	GameSettings.screen_shake = 0.0
	rig._shake = 0.0
	Fx.shake(dummy, 0.3)
	Fx.kick(dummy, Vector3.RIGHT, 0.5)
	await process_frame
	check("screen shake setting zero suppresses shake", float(rig._shake) == 0.0, "shake %.3f" % rig._shake)
	GameSettings.screen_shake = 1.0
	GameSettings.slow_motion = false
	Fx.slowmo(dummy, 0.12, 0.3, 0.3)
	await process_frame
	check("slow motion off keeps time scale 1", is_equal_approx(Engine.time_scale, 1.0), "time_scale %.3f" % Engine.time_scale)
	GameSettings.slow_motion = true
	GameSettings.show_damage_numbers = false
	var labels_before: int = 0
	for n in main.get_children():
		if n is Label3D:
			labels_before += 1
	Fx.popup(dummy, Combat.Outcome.CRUSHING, 99.0)
	var labels_after: int = 0
	for n in main.get_children():
		if n is Label3D:
			labels_after += 1
	check("damage numbers off draws no popup", labels_after == labels_before)
	GameSettings.show_damage_numbers = true
	quit(1 if failures > 0 else 0)
