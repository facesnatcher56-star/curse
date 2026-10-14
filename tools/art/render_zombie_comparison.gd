extends SceneTree

const LIVE := "res://assets/models/zombie"
const CONVERTED := "res://assets/art_staging/enemies/zombie_converted"
const OUT := "res://assets/art_staging/enemies/previews"
var world: Node3D
var camera: Camera3D
var live: CharacterModel
var converted: CharacterModel
var label: Label

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.content_scale_size = Vector2i(1920, 1080)
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.60)
	e.ambient_light_energy = 0.65
	env.environment = e
	world.add_child(env)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	floor.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.24)
	mat.roughness = 1.0
	floor.material_override = mat
	world.add_child(floor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	world.add_child(sun)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 38.0
	camera.rotation_degrees = Vector3(-54, 0, 0)
	world.add_child(camera)
	live = CharacterModel.build(LIVE, ["walk", "attack", "death"])
	converted = CharacterModel.build(CONVERTED, ["walk", "attack", "death"])
	world.add_child(live)
	world.add_child(converted)
	_check_models()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var header := ColorRect.new()
	header.color = Color(0.05, 0.05, 0.06, 0.88)
	header.position = Vector2.ZERO
	header.size = Vector2(1920, 96)
	layer.add_child(header)
	label = Label.new()
	label.position = Vector2(30, 23)
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(label)
	for view in ["close", "wide"]:
		camera.position = Vector3(0, 9.0, 6.5) * (0.6 if view == "close" else 4.2)
		for pose in ["walk", "attack", "death"]:
			for source in ["live", "converted"]:
				var model: CharacterModel = live if source == "live" else converted
				live.visible = source == "live"
				converted.visible = source == "converted"
				var clip: Animation = model.anim.get_animation("game/" + pose)
				var fraction := 0.95 if pose == "death" else 0.5
				model.anim.play("game/" + pose)
				model.anim.seek(clip.length * fraction, true)
				model.anim.pause()
				label.text = "ZOMBIE %s | %s | %s @ %d%% | Godot gameplay camera" % [source.to_upper(), view.to_upper(), pose.to_upper(), int(fraction * 100.0)]
				for i in range(5):
					await process_frame
				var path := "%s/zombie_compare_%s_%s_%s.png" % [OUT, view, pose, source]
				var err := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
				print("SHOT ", path, " result=", err)
	quit(0)

func _check_models() -> void:
	var a: Skeleton3D = live.find_children("*", "Skeleton3D", true, false)[0]
	var b: Skeleton3D = converted.find_children("*", "Skeleton3D", true, false)[0]
	var names_a: Array[String] = []
	var names_b: Array[String] = []
	for i in a.get_bone_count():
		names_a.append(String(a.get_bone_name(i)))
	for i in b.get_bone_count():
		names_b.append(String(b.get_bone_name(i)))
	print("BONES live=", names_a, " converted=", names_b, " match=", names_a == names_b)
	print("BOUNDS live=", CharacterModel._bounds_of(live), " converted=", CharacterModel._bounds_of(converted))
	for model in [live, converted]:
		var source := "live" if model == live else "converted"
		print("PLAYER ", source, " root=", model.anim.root_node, " path=", model.anim.get_path())
		for clip in ["walk", "attack", "death"]:
			var anim: Animation = model.anim.get_animation("game/" + clip)
			var paths: Array[String] = []
			for i in anim.get_track_count():
				paths.append(String(anim.track_get_path(i)))
			print("TRACKS ", source, " ", clip, " count=", paths.size(), " first=", paths.slice(0, 5))
			var missing: Array[String] = []
			var track_root: Node = model.anim.get_node(model.anim.root_node)
			for track_path in paths:
				var parts: PackedStringArray = track_path.split(":")
				var node: Node = track_root.get_node_or_null(NodePath(parts[0]))
				if node == null or (parts.size() > 1 and node is Skeleton3D and (node as Skeleton3D).find_bone(parts[1]) < 0):
					missing.append(track_path)
			print("TRACK_RESOLVE ", source, " ", clip, " missing=", missing)
