extends SceneTree
## Windowed gameplay-camera shots of the dungeon test level (issue #25), at the window's own resolution (run at 1920x1080).
## The hero is placed in each space; the live camera rig frames it at the dungeon's start zoom unless a shot sets its own zoom. Run:
##   godot --path . -s res://game/dev/dungeon_shots.gd --resolution 1920x1080 -- --dungeon --atmosphere --shots=<abs dir> [--only=name]
## Omit --atmosphere for the default-lighting shot. --only limits the run to one shot by name.

## name, hero position, frames to wait before the shot, zoom (-1 keeps the start zoom).
const SHOTS := [
	["entry_hall", Vector3(0, 0, 34.0), 40, -1.0],
	["corridor_a", Vector3(0, 0, 22.0), 40, -1.0],
	["central_chamber", Vector3(-1.0, 0, 3.0), 40, -1.0],
	["treasure_room", Vector3(19.0, 0, -0.5), 40, -1.0],
	["final_hall", Vector3(0, 0, -20.0), 40, -1.0],
	["combat_final_hall", Vector3(-2.0, 0, -27.0), 150, -1.0],
	["entry_hall_max_zoom", Vector3(0, 0, 34.0), 40, 2.0],
]

var _main: Node
var _frames := 0
var _shot := -1
var _wait := 0
var _dir := ""
var _only := ""
var _list: Array = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
		elif arg.begins_with("--only="):
			_only = arg.substr(7)
	for shot in SHOTS:
		if _only.is_empty() or String(shot[0]) == _only:
			_list.append(shot)
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main   # the game sets this when it loads main; effects attach to it
	# The dev harness opens a 720p window on the second monitor; these shots are 1080p, so the window is resized after it.



func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _frames < 240 or _main.player == null:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _shot >= 0:
		var image := get_root().get_texture().get_image()
		var path := _dir.path_join(String(_list[_shot][0]) + ".png")
		image.save_png(path)
		print("DUNGEON_SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])
	_shot += 1
	if _shot >= _list.size():
		print("DUNGEON_SHOTS DONE")
		quit(0)
		return true
	var shot: Array = _list[_shot]
	_main.player.global_position = shot[1]
	if float(shot[3]) >= 0.0:
		_main.rig.set_zoom_now(float(shot[3]))
	_wait = int(shot[2])
	return false
