extends SceneTree
## Windowed gameplay-camera shots of the Crypt (`-- --crypt01`) at 1080p, plus the frame rate in each spot. Run:
##   godot --path . --screen 1 -s res://game/dev/crypt_shots.gd --resolution 1920x1080 -- --crypt01 --shots=<abs dir> [--only=name]
## name, hero position as a plan cell (column, row), frames to wait, zoom (-1 keeps the dungeon's start zoom).

const SHOTS := [
	["vestibule", Vector2(26, 56), 60, -1.0],
	["long_hall", Vector2(20, 47), 60, -1.0],
	["pillared_crypt", Vector2(9, 37), 60, -1.0],
	["ossuary", Vector2(22, 36), 60, -1.0],
	["choke", Vector2(14, 31), 60, -1.0],
	["rotunda", Vector2(16, 25), 60, -1.0],
	["vault", Vector2(6, 24), 60, -1.0],
	["guard_hall", Vector2(16, 17), 60, -1.0],
	["antechamber", Vector2(16, 11), 60, -1.0],
	["arena", Vector2(16, 6), 60, -1.0],
	["arena_fight", Vector2(15, 5.5), 200, -1.0],
	["brazier_close", Vector2(14.2, 24.6), 60, 0.55],
	["arena_gate", Vector2(16, 6.8), 60, -1.0],
	["long_hall_wall", Vector2(16, 45.8), 60, -1.0],
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
	if _wait > 0:
		_wait -= 1
		return false
	if _shot >= 0:
		var image := get_root().get_texture().get_image()
		var path := _dir.path_join(String(_list[_shot][0]) + ".png")
		image.save_png(path)
		print("CRYPT_SHOT %s %dx%d fps=%d enemies=%d" % [path, image.get_width(), image.get_height(), Engine.get_frames_per_second(),
			get_nodes_in_group("enemies").size()])
	_shot += 1
	if _shot >= _list.size():
		print("CRYPT_SHOTS DONE")
		quit(0)
		return true
	var cell: Vector2 = _list[_shot][1]
	var p: Vector2 = CryptLayout.world(cell.x, cell.y)
	_main.player.global_position = Vector3(p.x, 0, p.y)
	if float(_list[_shot][3]) >= 0.0:
		_main.rig.set_zoom_now(float(_list[_shot][3]))
	_wait = _wait_override if _wait_override >= 0 else int(_list[_shot][2])
	return false
