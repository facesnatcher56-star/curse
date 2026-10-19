extends SceneTree
## Windowed gameplay-camera shots of the map-mode dungeon (`-- --mapmode`) at 1080p, plus the frame rate in each spot. Run:
##   godot --path . --screen 1 -s res://game/dev/map_mode_shots.gd --resolution 1920x1080 -- --mapmode --shots=<abs dir> [--only=name]
## name, hero position as a plan cell (column, row), frames to wait, zoom (-1 keeps the dungeon's start zoom).

const SHOTS := [
	["start", Vector2(31, 96), 60, -1.0],
	["corridor_0_1", Vector2(31, 88), 60, -1.0],
	["fallen_guard", Vector2(31, 82), 60, -1.0],
	["corridor_1_3", Vector2(19, 75), 60, -1.0],
	["swarm", Vector2(48, 79), 120, -1.0],
	["vestry", Vector2(35, 63), 60, -1.0],
	["shrine", Vector2(15, 58.5), 60, -1.0],
	["chest_room", Vector2(6, 67), 60, -1.0],
	["boss", Vector2(28, 6.5), 60, -1.0],
]

var _main: Node
var _frames := 0
var _shot := -1
var _wait := 0
var _dir := ""
var _only := ""
var _wait_override := -1
var _list: Array = []
var _fps: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
		elif arg.begins_with("--wait="):
			_wait_override = int(arg.substr(7))   # frames to settle before the shot and its frame rate (default: per shot)
		elif arg.begins_with("--only="):
			_only = arg.substr(7)
	for shot in SHOTS:
		if _only.is_empty() or String(shot[0]) == _only:
			_list.append(shot)
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _frames < 300 or _main.player == null:
		return false
	_main.player.hurt_flash = 0.0
	if MapMode.current != null and MapMode.current.overlay != null and MapMode.current.overlay.is_open():
		MapMode.current.overlay.close()   # the map opens by itself; the shots want the world
	if _wait > 0:
		_wait -= 1
		return false
	if _shot >= 0:
		var image := get_root().get_texture().get_image()
		var path := _dir.path_join(String(_list[_shot][0]) + ".png")
		image.save_png(path)
		print("MAPMODE_SHOT %s %dx%d fps=%d enemies=%d" % [path, image.get_width(), image.get_height(), Engine.get_frames_per_second(),
			get_nodes_in_group("enemies").size()])
	_shot += 1
	if _shot >= _list.size():
		print("MAPMODE_SHOTS DONE")
		quit(0)
		return true
	var cell: Vector2 = _list[_shot][1]
	var p: Vector2 = MapModeLayout.world(cell.x, cell.y)
	_main.player.global_position = Vector3(p.x, 0, p.y)
	if float(_list[_shot][3]) >= 0.0:
		_main.rig.set_zoom_now(float(_list[_shot][3]))
	_wait = _wait_override if _wait_override >= 0 else int(_list[_shot][2])
	return false
