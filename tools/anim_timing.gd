extends SceneTree
## Debug helper: finds when each baked clip's arm moves fastest (the strike frame), from keyframe data.
## godot --headless --path . --script tools/anim_timing.gd -- res://assets/models/hero RightArm RightForeArm

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var lib: AnimationLibrary = load(args[0] + "/anims.res")
	var bones: PackedStringArray = args.slice(1)
	for clip in lib.get_animation_list():
		var anim: Animation = lib.get_animation(clip)
		var tracks: Array[int] = []
		for bone in bones:
			var idx: int = anim.find_track(NodePath("Armature/Skeleton3D:" + bone), Animation.TYPE_ROTATION_3D)
			if idx >= 0:
				tracks.append(idx)
		var step: float = 1.0 / 30.0
		var speeds: Array[float] = []
		var t: float = step
		while t <= anim.length:
			var total: float = 0.0
			for idx in tracks:
				total += anim.rotation_track_interpolate(idx, t - step).angle_to(anim.rotation_track_interpolate(idx, t)) / step
			speeds.append(total)
			t += step
		var peak: float = 0.0
		var peak_i: int = 0
		for i in speeds.size():
			if speeds[i] > peak:
				peak = speeds[i]
				peak_i = i
		var first: int = -1
		var last: int = -1
		for i in speeds.size():
			if speeds[i] > peak * 0.4:
				if first < 0:
					first = i
				last = i
		print(clip, " len=", snappedf(anim.length, 0.01), " peak@", snappedf((peak_i + 1) * step, 0.01),
			"s active=", snappedf((first + 1) * step, 0.01), "-", snappedf((last + 1) * step, 0.01))
	quit()