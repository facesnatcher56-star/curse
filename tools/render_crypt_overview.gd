extends SceneTree
## Renders the Crypt scene from straight above into a PNG (a developer look at the whole layout, with the packs marked).
##   godot --path . --screen 1 -s res://tools/render_crypt_overview.gd -- --out=C:/path/crypt_overview.png [--packs]

var _frames := 0
var _viewport: SubViewport
var _out := ""

func _initialize() -> void:
	var packs := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg == "--packs":
			packs = true
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1160, 2048)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var level: Node3D = (load(CryptDungeon.CRYPT_SCENE) as PackedScene).instantiate()
	_viewport.add_child(level)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.03)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.9, 0.95)
	environment.ambient_light_energy = 0.9
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-75, 20, 0)
	sun.light_energy = 0.9
	_viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(CryptLayout.H) * CryptLayout.CELL + 12.0
	camera.position = Vector3(0, 120, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.far = 300.0
	camera.current = true
	_viewport.add_child(camera)
	if packs:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.2, 0.15)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for marker in level.get_node("EnemyGroups").get_children():
			var disc := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 2.0
			cyl.bottom_radius = 2.0
			cyl.height = 0.4
			disc.mesh = cyl
			disc.material_override = mat
			disc.position = Vector3((marker as Node3D).position.x, 6.0, (marker as Node3D).position.z)
			_viewport.add_child(disc)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 120:
		var image: Image = _viewport.get_texture().get_image()
		image.save_png(_out)
		print("OVERVIEW ", _out, " ", image.get_size())
		quit()
	return false
