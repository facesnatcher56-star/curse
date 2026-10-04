extends SceneTree
## `godot --headless --path . --script tools/load_time.gd`: how long each prop model takes to load cold, loaded again (cache hit),
## and instantiated. Used to find what makes starting a run slow.

func _init() -> void:
	for name in ["ruined_pillar", "bones", "barrel", "dead_tree"]:
		var path: String = "res://assets/models/%s/model.glb" % name
		var t: int = Time.get_ticks_msec()
		var scene: PackedScene = load(path)
		var cold: int = Time.get_ticks_msec() - t
		t = Time.get_ticks_msec()
		var again: PackedScene = load(path)
		var warm: int = Time.get_ticks_msec() - t
		t = Time.get_ticks_msec()
		var node: Node = scene.instantiate()
		var inst: int = Time.get_ticks_msec() - t
		var tris: int = 0
		var texs: int = 0
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh != null:
				tris += mesh.get_faces().size() / 3
				texs += mesh.get_surface_count()
		print("%-14s cold %4d ms   again %3d ms   instantiate %3d ms   tris %d surfaces %d" % [name, cold, warm, inst, tris, texs])
		node.free()
	quit()
