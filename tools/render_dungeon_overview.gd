extends SceneTree
## Renders the dungeon level scene from straight above into %TEMP%/dungeon_overview.png (a developer look at the whole level).
##   godot --path . -s res://tools/render_dungeon_overview.gd --resolution 640x1600

var _frames := 0
var _viewport: SubViewport

func _initialize() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(800, 1984)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var level: Node3D = (load("res://game/world/dungeon_level.tscn") as PackedScene).instantiate()
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
	sun.rotation_degrees = Vector3(-80, 20, 0)
	sun.light_energy = 0.8
	_viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 248.0
	camera.position = Vector3(0, 120, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.far = 300.0
	camera.current = true
	_viewport.add_child(camera)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 60:
		var image: Image = _viewport.get_texture().get_image()
		var path: String = OS.get_environment("TEMP") + "/dungeon_overview.png"
		image.save_png(path)
		print("OVERVIEW ", path, " ", image.get_size())
		quit()
	return false
