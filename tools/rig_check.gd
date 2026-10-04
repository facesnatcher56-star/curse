extends SceneTree
## godot --headless --path . --script tools/rig_check.gd -- res://assets/models/knight
## Prints rest bone lengths of both arms and legs so a bad auto-rig (asymmetric joints) is easy to spot.
func _init() -> void:
	var rigged: Node = (load(OS.get_cmdline_user_args()[0] + "/rigged.glb") as PackedScene).instantiate()
	root.add_child(rigged)
	var sk: Skeleton3D = rigged.find_children("*", "Skeleton3D", true, false)[0]
	for chain in [["RightArm", "RightForeArm", "RightHand"], ["LeftArm", "LeftForeArm", "LeftHand"],
			["RightUpLeg", "RightLeg", "RightFoot"], ["LeftUpLeg", "LeftLeg", "LeftFoot"]]:
		var pts: Array[Vector3] = []
		for b in chain:
			var i: int = sk.find_bone(b)
			var xf: Transform3D = Transform3D.IDENTITY
			while i >= 0:
				xf = sk.get_bone_rest(i) * xf
				i = sk.get_bone_parent(i)
			pts.append(xf.origin)
		print(chain[0], ": upper=", snappedf(pts[0].distance_to(pts[1]), 0.1), " lower=", snappedf(pts[1].distance_to(pts[2]), 0.1))
	quit()