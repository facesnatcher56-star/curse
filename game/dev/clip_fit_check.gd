extends SceneTree
## Measured fit of the knight2 clips on the hero rig. For every clip, sampled every 1/30 s, it checks on both rigs:
##   - hands and forearms entering the torso (an ellipse around the chest bones, sized from each rig's own skin),
##   - fists entering the head (a sphere sized from the skin),
##   - feet going through the floor.
## A clip "fits" the hero when he is not worse than the knight it was made for by more than the slack. Prints one line per
## clip and a summary. Headless: godot --headless --path . --script game/dev/clip_fit_check.gd

const KNIGHT := "res://assets/models/knight2"
const SLACK_CM := 3.0
const HAND_R := 4.5   # cm: a fist's half thickness

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var clips: Array[String] = []
	clips.assign(Player.CLIPS)
	var rigs := {}
	for folder in [KNIGHT, CharacterPresentation.folder("hero")]:
		var model := CharacterModel.build(folder, clips, false)
		root.add_child(model)
		rigs[folder] = {"model": model, "sk": model.find_children("*", "Skeleton3D", true, false)[0]}
		rigs[folder].merge(_body_shape(rigs[folder]["sk"]))
	var lib: AnimationLibrary = (rigs[KNIGHT]["model"] as CharacterModel).anim.get_animation_library("game")
	var bad: Array[String] = []
	for clip in lib.get_animation_list():
		var res := {}
		for folder in rigs:
			res[folder] = _measure(rigs[folder], clip)
		var k: Dictionary = res[KNIGHT]
		var h: Dictionary = res[CharacterPresentation.folder("hero")]
		var worse := []
		for key in ["torso", "head", "floor"]:
			if float(h[key]) - float(k[key]) > SLACK_CM and float(h[key]) > SLACK_CM:
				worse.append("%s %.1f vs %.1f cm at %.2fs" % [key, h[key], k[key], h[key + "_t"]])
		print("CLIPFIT %-15s %s" % [clip, "OK" if worse.is_empty() else "BAD " + "; ".join(worse)],
			"   (hero torso %.1f head %.1f floor %.1f | knight %.1f %.1f %.1f)" % [h["torso"], h["head"], h["floor"], k["torso"], k["head"], k["floor"]])
		if not worse.is_empty():
			bad.append(clip)
	print("CLIPFIT DONE bad=", bad)
	quit()

## Chest ellipse half-widths (side, front) in the Spine01 frame and head radius, from the rest skin.
func _body_shape(sk: Skeleton3D) -> Dictionary:
	var chest_ids := [sk.find_bone("Spine01"), sk.find_bone("Spine"), sk.find_bone("Spine02")]
	var head_id := sk.find_bone("Head")
	var frame: Transform3D = sk.get_bone_global_rest(sk.find_bone("Spine01"))
	var head_rest: Vector3 = sk.get_bone_global_rest(head_id).origin
	var xs: Array[float] = []
	var zs: Array[float] = []
	var hr: Array[float] = []
	for mi in sk.find_children("*", "MeshInstance3D", false, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		var skin: Skin = (mi as MeshInstance3D).skin
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty():
				continue
			var per := bones.size() / verts.size()
			for v in range(0, verts.size(), 3):
				var best := 0
				for j in per:
					if weights[v * per + j] > weights[v * per + best]: best = j
				var bind := bones[v * per + best]
				var bone := sk.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != "" else skin.get_bind_bone(bind)
				# rest position of the vertex in skeleton space: bind pose inverse is the skin's bind
				var p: Vector3 = sk.get_bone_global_rest(bone) * (skin.get_bind_pose(bind) * verts[v])
				if bone in chest_ids:
					var q: Vector3 = frame.affine_inverse() * p
					xs.append(absf(q.x)); zs.append(absf(q.z))
				elif bone == head_id:
					hr.append(p.distance_to(head_rest))
	xs.sort(); zs.sort(); hr.sort()
	return {"rx": xs[int(xs.size() * 0.8)], "rz": zs[int(zs.size() * 0.8)], "hr": hr[int(hr.size() * 0.6)],
		"chest_lo": sk.get_bone_global_rest(sk.find_bone("Spine02")).origin.y, "chest_hi": sk.get_bone_global_rest(sk.find_bone("neck")).origin.y,
		"rest_toe": minf(sk.get_bone_global_rest(sk.find_bone("LeftToeBase")).origin.y, sk.get_bone_global_rest(sk.find_bone("RightToeBase")).origin.y)}

## Worst penetrations (cm) over the clip: arm points into the chest ellipse, fists into the head, toes below rest height.
func _measure(rig: Dictionary, clip: String) -> Dictionary:
	var model: CharacterModel = rig["model"]
	var sk: Skeleton3D = rig["sk"]
	var anim: Animation = model.anim.get_animation("game/" + clip)
	model.anim.play("game/" + clip, 0.0)
	var out := {"torso": 0.0, "head": 0.0, "floor": 0.0, "torso_t": 0.0, "head_t": 0.0, "floor_t": 0.0}
	var t := 0.0
	while t <= anim.length:
		model.anim.seek(t, true)
		var frame: Transform3D = sk.get_bone_global_pose(sk.find_bone("Spine01"))
		var lo: float = sk.get_bone_global_pose(sk.find_bone("Spine02")).origin.y - 4.0
		var hi: float = sk.get_bone_global_pose(sk.find_bone("neck")).origin.y
		var head: Vector3 = sk.get_bone_global_pose(sk.find_bone("Head")).origin
		for side in ["Left", "Right"]:
			var hand: Vector3 = sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
			var fore: Vector3 = sk.get_bone_global_pose(sk.find_bone(side + "ForeArm")).origin
			for p in [hand, fore.lerp(hand, 0.5)]:
				var q: Vector3 = frame.affine_inverse() * p
				# radial depth inside the ellipse, in cm along the ray from the axis
				var e: float = sqrt(pow(q.x / float(rig["rx"]), 2) + pow(q.z / float(rig["rz"]), 2))
				if p.y > lo and p.y < hi and e > 0.0001:
					var r_here: float = Vector2(q.x, q.z).length() / e
					var depth: float = r_here + HAND_R - Vector2(q.x, q.z).length()
					if depth > out["torso"]: out["torso"] = depth; out["torso_t"] = t
			var hd: float = float(rig["hr"]) + HAND_R - hand.distance_to(head)
			if hd > out["head"]: out["head"] = hd; out["head_t"] = t
			var toe: float = sk.get_bone_global_pose(sk.find_bone(side + "ToeBase")).origin.y
			var sink: float = float(rig["rest_toe"]) - toe
			if sink > out["floor"]: out["floor"] = sink; out["floor_t"] = t
		t += 1.0 / 30.0
	return out
