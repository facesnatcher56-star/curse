extends SceneTree
func _init() -> void:
	var inst: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	root.add_child(inst)
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		print("SKEL ", s.name, " bones ", s.get_bone_count(), " global_scale ", s.global_transform.basis.get_scale(), " parent ", s.get_parent().name, " parent xf ", (s.get_parent() as Node3D).transform)
		for i in s.get_bone_count():
			var g := s.get_bone_global_rest(i)
			print(i, " ", s.get_bone_name(i), " parent ", s.get_bone_parent(i), " pos ", g.origin)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", m.name, " aabb ", (m as MeshInstance3D).get_aabb())
	print("ANIMS ", (inst.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer).get_animation_list())
	quit()
