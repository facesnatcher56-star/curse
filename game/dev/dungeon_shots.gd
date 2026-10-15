extends SceneTree
## Windowed gameplay-camera shots of the dungeon test level (issue #25), at the window's own resolution (run at 1920x1080).
## The hero is placed in each space; the live camera rig frames it at the dungeon's start zoom unless a shot sets its own zoom. Run:
##   godot --path . -s res://game/dev/dungeon_shots.gd --resolution 1920x1080 -- --dungeon --atmosphere --shots=<abs dir> [--only=name] [--size=1280x720]
## Omit --atmosphere for the default-lighting shot. --only limits the run to one shot by name. --size sets the window (default 1920x1080).

## name, hero position, frames to wait before the shot, zoom (-1 keeps the start zoom).
const SHOTS := [
	["entry_hall", Vector3(0, 0, 98.0), 40, -1.0],
	["cave_a", Vector3(19.0, 0, 94.0), 40, -1.0],
	["corridor_1", Vector3(9.0, 0, 80.0), 40, -1.0],
	["hall_1", Vector3(-10.0, 0, 64.0), 40, -1.0],
	["treasure_h1s", Vector3(-17.0, 0, 77.0), 40, -1.0],
	["hall_2", Vector3(-4.0, 0, 30.0), 40, -1.0],
	["hall_3", Vector3(0.0, 0, -4.0), 40, -1.0],
	["treasure_h3e", Vector3(33.0, 0, -6.0), 40, -1.0],
	["hall_4", Vector3(-6.0, 0, -52.0), 40, -1.0],
	["final_hall", Vector3(0, 0, -100.0), 40, -1.0],
	["combat_final_hall", Vector3(-2.0, 0, -104.0), 150, -1.0],
	["entry_hall_max_zoom", Vector3(0, 0, 98.0), 40, 2.0],
]

var _main: Node
var _frames := 0
var _shot := -1
var _wait := 0
var _dir := ""
var _only := ""
var _list: Array = []
var _size := Vector2i(1920, 1080)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
		elif arg.begins_with("--only="):
			_only = arg.substr(7)
		elif arg.begins_with("--size="):   # the window size for the shots, e.g. 1280x720 (default 1920x1080)
			var wh: PackedStringArray = arg.substr(7).split("x")
			_size = Vector2i(int(wh[0]), int(wh[1]))
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
		DisplayServer.window_set_size(_size)
	if _frames < 480 or _main.player == null:   # the job banner (4 s) is up for the first seconds, so the shots wait for it to pass
		return false
	if _main.player != null:
		# The HUD's hurt overlay tints the whole frame red while hurt_flash runs down. It is a HUD effect, not lighting, so the shots
		# clear it (the fight itself is unchanged).
		_main.player.hurt_flash = 0.0
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
