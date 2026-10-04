extends SceneTree
func _init() -> void:
	for folder in ["res://assets/models/hero", "res://assets/models/zombie"]:
		var lib: AnimationLibrary = load(folder + "/anims.res")
		print("== ", folder)
		for clip in lib.get_animation_list():
			var anim: Animation = lib.get_animation(clip)
			var idx: int = anim.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_POSITION_3D)
			if idx < 0:
				print(clip, ": no hips position track")
				continue
			var first: Vector3 = anim.position_track_interpolate(idx, 0.0)
			var lo: Vector3 = first
			var hi: Vector3 = first
			var t: float = 0.0
			while t <= anim.length:
				var v: Vector3 = anim.position_track_interpolate(idx, t)
				lo = lo.min(v)
				hi = hi.max(v)
				t += 0.05
			print(clip, ": hips travel x=", snappedf(hi.x - lo.x, 0.1), " y=", snappedf(hi.y - lo.y, 0.1), " z=", snappedf(hi.z - lo.z, 0.1), " (start ", first.snapped(Vector3.ONE * 0.1), ")")
	quit()