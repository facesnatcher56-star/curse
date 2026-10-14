extends SceneTree
func _init() -> void:
	var inst: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	root.add_child(inst)
	var s: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in s.get_bone_count():
		var g := s.get_bone_global_rest(i)
		var loc := s.get_bone_rest(i)
		var e := g.basis.orthonormalized().get_euler() * 180.0 / PI
		print("BONE|%s|parent=%s|gpos=%s|gx_axis=%s|gy_axis=%s|local_euler=%s" % [s.get_bone_name(i), s.get_bone_name(s.get_bone_parent(i)) if s.get_bone_parent(i) >= 0 else "-", g.origin.snappedf(0.01), g.basis.x.snappedf(0.01), g.basis.y.snappedf(0.01), (loc.basis.get_euler() * 180.0 / PI).snappedf(1.0)])
	quit()
