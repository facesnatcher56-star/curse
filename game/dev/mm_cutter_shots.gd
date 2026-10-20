extends SceneTree
## 1080p shots of the Cutter at the start of three map-mode fights on the full HUD (`-- --mapmode`, issue #87). Run (second monitor, hard time cap):
##   godot --path . --screen 1 -s res://game/dev/mm_cutter_shots.gd --resolution 1920x1080 -- --mapmode --shots=<abs dir> --prefix=after_ [--before]
## `--before` turns the on-screen clamp off (MapModeScreen.enabled), for the old behaviour.

const ROOMS := [1, 2, 4]
var _main: Node
var _frames := 0
var _dir := ""
var _prefix := ""
var _room_index := 0
var _phase := 0
var _wait := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
		if arg.begins_with("--prefix="):
			_prefix = arg.substr(9)
		if arg == "--before":
			MapModeScreen.enabled = false
	DirAccess.make_dir_recursive_absolute(_dir)
	TownState.persist = false
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main

func _save(shot: String) -> void:
	var image := get_root().get_texture().get_image()
	var path := _dir.path_join(_prefix + shot + ".png")
	image.save_png(path)
	print("MMCUTTER_SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])

func _path(graph: MapGraph, from_id: int, to_id: int) -> Array:
	var came: Dictionary = {from_id: -1}
	var queue: Array = [from_id]
	while not queue.is_empty():
		var id: int = int(queue.pop_front())
		if id == to_id:
			break
		for n in graph.neighbours(id):
			if not came.has(int(n)):
				came[int(n)] = id
				queue.append(int(n))
	var out: Array = []
	var at: int = to_id
	while came.has(at) and at != -1:
		out.push_front(at)
		at = int(came[at])
	return out

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _frames < 300 or _main.player == null or MapMode.current == null:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	var m: MapMode = MapMode.current
	var player: Player = _main.player
	var cutter: Player = _main.companion
	match _phase:
		0:
			player.invulnerable_time = 1.0e9
			cutter.invulnerable_time = 1.0e9
			GameSettings.screen_shake = 0.0
			_phase = 1
			_wait = 30
		1:
			if _room_index >= ROOMS.size():
				print("MMCUTTER_SHOTS DONE")
				quit(0)
				return true
			if m.overlay != null and m.overlay.is_open():
				m.overlay.close()
			var room: int = ROOMS[_room_index]
			var route: Array = _path(m.graph, 0, room)
			for id in route:
				if int(id) != room:
					m.graph.mark_cleared(int(id))
			var before_id: int = int(route[route.size() - 2])
			var at: Vector2 = m.graph.pos_of(before_id)
			player.global_position = Nav.snap(player, Vector3(at.x, 0.0, at.y))
			cutter.global_position = Nav.snap(cutter, player.global_position + Vector3(1.5, 0.0, 0.0))
			m.current_node = before_id
			m.state = MapMode.State.MAP
			_phase = 2
			_wait = 90
		2:
			m.select_marker(ROOMS[_room_index])
			_phase = 3
		3:
			if m.state == MapMode.State.FIGHT:
				for e in m.fight_enemies():
					e.max_health = 100000.0
					e.health = e.max_health
				_phase = 4
				_wait = 100
		4:
			_save("fight_%d_room%d" % [_room_index + 1, ROOMS[_room_index]])
			var f: Vector2 = get_root().get_camera_3d().unproject_position(cutter.global_position)
			print("MMCUTTER_POS room %d cutter feet %s warrior %s" % [ROOMS[_room_index], f, get_root().get_camera_3d().unproject_position(player.global_position)])
			for e in m.fight_enemies():
				e.max_health = 10.0
				e.credit_hero()
				e._apply_damage(1000.0)
			_phase = 5
		5:
			for e in m.fight_enemies():
				e.health = 1.0
				e.credit_hero()
				e._apply_damage(1000.0)
			if m.state == MapMode.State.MAP:
				_room_index += 1
				_phase = 1
	return false
