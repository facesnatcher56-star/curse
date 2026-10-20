extends SceneTree
## Close-up of the five map-mode chest tiers, closed then open, from the game's camera angle (a developer look at the model styling):
##   godot --path . --screen 1 -s res://game/dev/mm_chest_preview.gd --resolution 1920x1080 -- --shots=<abs dir>
var _frames := 0
var _dir := ""
var _chests: Array[Chest] = []
var _step := 0
var _wait := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(_dir)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.12, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.45, 0.42)
	env.environment.ambient_light_energy = 1.1
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.6
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 14)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.24, 0.2)
	floor_mesh.material_override = floor_mat
	root.add_child(floor_mesh)
	var kinds: Array[String] = ["wooden", "iron", "gilded", "cursed", "hoard"]
	for i in kinds.size():
		var chest := Chest.create(kinds[i], 10)
		root.add_child(chest)
		chest.position = Vector3(-6.0 + 3.0 * float(i), 0.0, 0.0)
		if OS.get_cmdline_user_args().has("--zoom"):
			chest.visible = kinds[i] == _kind()
			chest.position = Vector3.ZERO
		_chests.append(chest)
	var cam := Camera3D.new()
	cam.fov = 38.0
	root.add_child(cam)
	var zoom: bool = OS.get_cmdline_user_args().has("--zoom")
	cam.look_at_from_position(Vector3(0.0, 2.0, 2.3) if zoom else Vector3(0.0, 9.0, 9.5), Vector3(0.0, 0.3, 0.0))
	current_scene = root

func _kind() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kind="):
			return arg.substr(7)
	return "wooden"

func _save(shot: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(_dir.path_join(shot + ".png"))
	print("CHESTPREVIEW ", shot)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _frames < 40:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			_save("chests_closed")
			_wait = 10
		1:
			for c in _chests:
				c._lid.rotation.x = -1.9
			_wait = 20
		2:
			_save("chests_open")
			_wait = 10
		3:
			quit(0)
	_step += 1
	return false
