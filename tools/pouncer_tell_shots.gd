extends SceneTree
## Screenshots of the pouncer landing marker mid-windup, at normal and far zoom, one ghoul and a pack of four.
## GODOT_HEADLESS= tools/run_godot.sh LOG 120 -- --script res://tools/pouncer_tell_shots.gd -- --tellshots=DIR

var out_dir: String = ""
var main: Node

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tellshots="):
			out_dir = arg.substr(12)
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_run()

func _shoot(name: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])

func _wait_windup(gs: Array) -> void:
	var t: float = 0.0
	while t < 8.0:
		await physics_frame
		t += 1.0 / 60.0
		for g in gs:
			if is_instance_valid(g) and (g.behavior as PouncerBehavior)._state == PouncerBehavior.State.WINDUP:
				return

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	for i in 10:
		await process_frame
	var p: Player = main.player
	p.max_health = 5000.0
	p.health = 5000.0
	p.global_position = Vector3(30, 0, 30)
	p.reset_physics_interpolation()
	main.rig.global_position = p.global_position
	for count in [1, 4]:
		for n in get_nodes_in_group("enemies"):
			n.queue_free()
		await process_frame
		var gs: Array = []
		for i in count:
			var g: Enemy = main.director.spawn_enemy(Vector3(30 - 6 + i * 4.0, 0, 24.0), "ghoul", 1.0)
			g.aggro_range = 40.0
			g.wake()
			gs.append(g)
		await _wait_windup(gs)
		for zoom in [1.0, 4.2]:
			main.rig.set_zoom_now(zoom)
			await _shoot("tell_%d_zoom%d" % [count, int(zoom)])
		main.rig.set_zoom_now(1.0)
		await create_timer(2.0).timeout
	quit(0)
