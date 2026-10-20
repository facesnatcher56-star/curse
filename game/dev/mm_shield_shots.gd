extends SceneTree
## 1080p shots of the map-mode shield guard (issue #88) on the real HUD (`-- --mapmode`): the warrior walking toward two rock throwers with the
## shield raised, and a rock hitting it. Run:
##   godot --path . --screen 1 -s res://game/dev/mm_shield_shots.gd --resolution 1920x1080 -- --mapmode --shots=<abs dir>

var _main: Node
var _frames := 0
var _dir := ""
var _started := false
var _sent := 0
var _blocked_seen := 0
var _seq := 0
var _hit_shots := 0
var _t0 := 0
var _last_ms := 0
var _last_throw := 0
var _throwers: Array[Enemy] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(_dir)
	TownState.persist = false
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main

func _save(shot: String) -> void:
	var image := get_root().get_texture().get_image()
	var path := _dir.path_join(shot + ".png")
	image.save_png(path)
	print("MMSHIELD_SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _frames < 300 or _main.player == null or MapMode.current == null:
		return false
	var mm: MapMode = MapMode.current
	var hero: Player = _main.player
	if mm.overlay != null and mm.overlay.is_open():
		mm.overlay.close()
	if not _started:
		_started = true
		TownState.dev_set_hero_level(30)
		hero.stats.equipment[Items.Slot.SHIELD] = Items.build(ItemDb.get_def("buckler"), 6, Items.Rarity.NORMAL, [])
		hero.stats.refresh()
		hero.health = hero.max_health
		for node in get_nodes_in_group("enemies"):
			node.queue_free()   # only the throwers: a stray awake monster would be a melee attacker on him
		var camera: Camera3D = get_root().get_camera_3d()
		var spot := Vector3.ZERO
		var best_y := -1.0e9
		var space: PhysicsDirectSpaceState3D = hero.get_world_3d().direct_space_state
		for dist in [15.0, 17.0, 13.0, 19.0]:
			for i in 24:
				var dir := Vector3(0, 0, 1).rotated(Vector3.UP, TAU * float(i) / 24.0)
				var want: Vector3 = hero.global_position + dir * dist
				var snapped: Vector3 = Nav.snap(hero, want)
				if snapped.distance_to(want) > 0.8 or not Nav.line_clear(hero, snapped):
					continue
				var ray := PhysicsRayQueryParameters3D.create(hero.global_position + Vector3(0, 1.2, 0), snapped + Vector3(0, 1.2, 0), Actor.LAYER_WORLD)
				if not space.intersect_ray(ray).is_empty():
					continue   # the throwers must see him (no wall, no prop in between)
				var sy: float = camera.unproject_position(snapped).y   # prefer the throwers on the screen's lower half: the shield faces the camera
				if sy > best_y:
					best_y = sy
					spot = snapped
			if spot != Vector3.ZERO:
				break
		hero.face(spot, 1.0)
		print("MMSHIELD spot ", spot, " hero ", hero.global_position)
		for k in 2:
			var at: Vector3 = Nav.snap(hero, spot + (spot - hero.global_position).normalized() * (float(k) * 2.0))
			var e: Enemy = _main.director.spawn_enemy(at, "rock_thrower", 1.0)
			e.group_id = 990
			e.max_health = 1.0e6
			e.health = e.max_health
			_throwers.append(e)
		mm.group_id = 990
		mm.state = MapMode.State.FIGHT
		mm._fight_started = MapMode.now()
		mm.log.begin_fight("rock throwers", MapMode.now())
		for e in _throwers:
			e.alert_delay = 0.0
			e.wake()
		_t0 = _frames
		return false
	var blocked: int = hero.shield_guard.blocked
	if Time.get_ticks_msec() - _last_throw >= 900:   # the throwers' own cadence is slow and they can walk off; force a rock every 0.9 s so each approach shows hits
		_last_throw = Time.get_ticks_msec()
		for e in _throwers:
			if is_instance_valid(e) and not e.dead and e.flat_distance_to(hero) <= 14.0 and e.flat_distance_to(hero) > 2.0:
				e.target = hero
				(e.behavior as RockThrowerBehavior)._spit()
				break
	var n: int = _frames - _t0
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_ms >= 150 and _seq < 70:
		_last_ms = now_ms
		_save("seq_%02d_up%s_amount%d" % [_seq, "1" if hero.shield_guard.up else "0", int(hero.shield_guard.amount * 100)])
		_seq += 1
	if blocked > _blocked_seen:
		_blocked_seen = blocked
		if _hit_shots < 3:
			_hit_shots += 1
			_save("block_hit_%d" % _hit_shots)
	if n > 2400 or hero.dead:
		for line in mm.log.summary_lines():
			print(line)
		print("MMSHIELD blocked %d, health %.0f/%.0f, up %s" % [blocked, hero.health, hero.max_health, hero.shield_guard.up])
		quit(0)
		return true
	return false
