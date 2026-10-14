extends SceneTree
func _init() -> void:
	var inst: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	root.add_child(inst)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", m.name, " aabb ", (m as MeshInstance3D).get_aabb(), " xf ", (m as Node3D).transform)
	quit()
