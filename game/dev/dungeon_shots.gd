extends SceneTree
## Windowed gameplay-camera shots of the dungeon test level (issue #25), at the window's own resolution (run at 1920x1080).
## The hero is placed in each space; the live camera rig frames it. Run:
##   godot --path . -s res://game/dev/dungeon_shots.gd --resolution 1920x1080 -- --dungeon --atmosphere --shots=<abs dir>

## name, hero position, frames to wait before the shot.
const SHOTS := [
	["entry_hall", Vector3(0, 0, 34.0), 40],
	["corridor_a", Vector3(0, 0, 22.0), 40],
	["central_chamber", Vector3(-1.0, 0, 3.0), 40],
	["treasure_room", Vector3(19.0, 0, -0.5), 40],
	["final_hall", Vector3(0, 0, -20.0), 40],
	["combat_final_hall", Vector3(-2.0, 0, -27.0), 150],
]

var _main: Node
var _frames := 0
var _shot := -1
var _wait := 0
var _dir := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main   # the game sets this when it loads main; effects attach to it


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 240 or _main.player == null:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _shot >= 0:
		var image := get_root().get_texture().get_image()
		var path := _dir.path_join(String(SHOTS[_shot][0]) + ".png")
		image.save_png(path)
		print("DUNGEON_SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])
	_shot += 1
	if _shot >= SHOTS.size():
		print("DUNGEON_SHOTS DONE")
		quit(0)
		return true
	var shot: Array = SHOTS[_shot]
	_main.player.global_position = shot[1]
	_wait = int(shot[2])
	return false
