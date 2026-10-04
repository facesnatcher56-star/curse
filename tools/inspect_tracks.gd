extends SceneTree
func _init() -> void:
	var lib: AnimationLibrary = load("res://assets/models/hero/anims.res")
	var anim: Animation = lib.get_animation("slash")
	var types: Dictionary = {}
	for i in anim.get_track_count():
		var ty: int = anim.track_get_type(i)
		var path: String = str(anim.track_get_path(i)).get_slice(":", 1)
		if ty != Animation.TYPE_ROTATION_3D:
			print("non-rotation track: ", path, " type=", ty, " keys=", anim.track_get_key_count(i))
		types[ty] = int(types.get(ty, 0)) + 1
	print("track types: ", types, " total ", anim.get_track_count())
	# Compare animated bone offsets with the rest skeleton.
	var rigged: Node = (load("res://assets/models/hero/rigged.glb") as PackedScene).instantiate()
	root.add_child(rigged)
	var sk: Skeleton3D = rigged.find_children("*", "Skeleton3D", true, false)[0]
	print("skeleton scale: ", sk.global_transform.basis.get_scale(), " armature: ", (sk.get_parent() as Node3D).scale)
	for b in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "LeftUpLeg", "Spine"]:
		var i: int = sk.find_bone(b)
		print(b, " rest pos=", sk.get_bone_rest(i).origin, " rest scale=", sk.get_bone_rest(i).basis.get_scale())
	quit()