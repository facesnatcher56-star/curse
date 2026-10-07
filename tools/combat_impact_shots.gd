extends SceneTree
## Developer contact sheet of the impact FX tiers on a bare floor: light hit, critical, crushing, wall slam, each captured shortly after
## the strike and at its peak. Run with a real window:
## GODOT_HEADLESS= tools/run_godot.sh LOG 90 -- --script res://tools/combat_impact_shots.gd -- --impactshots=DIR
## (user arguments make it a developer session: the production save is never touched).

const TILE := 420
var out_dir: String = ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--impactshots="):
			out_dir = arg.substr(14)
	_run()

func _run() -> void:
	await process_frame
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.045, 0.04)
	env.environment.ambient_light_color = Color(0.35, 0.32, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	scene.add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.18, 0.15)
	floor_mesh.material_override = mat
	scene.add_child(floor_mesh)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.global_position = Vector3(0, 3.2, 4.2)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.4
	sun.rotation_degrees = Vector3(-50, 30, 0)
	scene.add_child(sun)
	var body := MeshInstance3D.new()   # stand-in for the target: only sizing the effect against a body
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	body.mesh = capsule
	scene.add_child(body)
	body.global_position = Vector3(0, 0.9, 0)
	var cases: Array = [["light", 0], ["critical", 1], ["crushing", 2], ["wall_slam", -1]]
	var sheet := Image.create(TILE * 3, TILE * cases.size(), false, Image.FORMAT_RGBA8)
	var row: int = 0
	for c in cases:
		Fx.reset_time()
		var at := Vector3(0.45, 1.3, 0)
		var delays: Array = [0.05, 0.12, 0.3]
		if c[1] >= 0:
			Fx.melee_impact(scene, at, Vector3.RIGHT, c[1], row + 1)
		else:
			Fx.body_impact(scene, at, Vector3.LEFT, "wall", 12.0)
		var t: float = 0.0
		for i in 3:
			await create_timer(delays[i] - t).timeout
			t = delays[i]
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(TILE, int(TILE * float(img.get_height()) / img.get_width()))
			sheet.blit_rect(img, Rect2i(0, 0, TILE, img.get_height()), Vector2i(i * TILE, row * TILE))
		row += 1
		await create_timer(0.8).timeout
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		sheet.save_png(out_dir.path_join("combat_impact_sheet.png"))
		print("saved ", out_dir.path_join("combat_impact_sheet.png"))
	quit(0)
