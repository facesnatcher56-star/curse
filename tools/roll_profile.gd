extends SceneTree
## Prints hips height and spine pitch through the roll clip so the visible start of the roll can be found.
func _init() -> void:
	var lib: AnimationLibrary = load("res://assets/models/knight2/anims.res")
	var anim: Animation = lib.get_animation("roll")
	var hips: int = anim.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_POSITION_3D)
	var hips_rot: int = anim.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
	var t: float = 0.0
	while t <= anim.length:
		var y: float = anim.position_track_interpolate(hips, t).y
		var q: Quaternion = anim.rotation_track_interpolate(hips_rot, t)
		print("t=", snappedf(t, 0.01), " hips_y=", snappedf(y, 0.1), " hips_tilt_deg=", snappedf(rad_to_deg(Quaternion.IDENTITY.angle_to(q)), 1))
		t += 0.1
	quit()