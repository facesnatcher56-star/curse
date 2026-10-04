extends SceneTree
## Debug helper: locates the sword tip (in the hand bone's local space) from skinning weights.
## godot --headless --path . --script tools/find_weapon_tip.gd -- res://assets/models/hero RightHand

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var rigged: Node = (load(args[0] + "/rigged.glb") as PackedScene).instantiate()
	root.add_child(rigged)
	var skeleton: Skeleton3D = rigged.find_children("*", "Skeleton3D", true, false)[0]
	var mesh_instance: MeshInstance3D = skeleton.find_children("*", "MeshInstance3D", true, false)[0]
	var bone: int = skeleton.find_bone(args[1])
	print("mesh xform: ", mesh_instance.transform, " skin binds: ", mesh_instance.skin.get_bind_count() if mesh_instance.skin else -1)
	var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride: int = bones.size() / verts.size()
	print("verts=", verts.size(), " stride=", stride)

	var skin: Skin = mesh_instance.skin
	var hand_bind: int = -1
	for b in skin.get_bind_count():
		var bi: int = skin.get_bind_bone(b)
		if bi < 0:
			bi = skeleton.find_bone(skin.get_bind_name(b))
		if bi == bone:
			hand_bind = b
	print("hand bind index: ", hand_bind)
	# Bone-local position of every vertex mostly weighted to the hand.
	var local_points: Array[Vector3] = []
	for i in verts.size():
		var w: float = 0.0
		for k in stride:
			if bones[i * stride + k] == hand_bind:
				w += weights[i * stride + k]
		if w > 0.6:
			local_points.append(skin.get_bind_pose(hand_bind) * verts[i])
	print("hand-weighted verts: ", local_points.size())
	var centroid: Vector3 = Vector3.ZERO
	for p in local_points:
		centroid += p
	centroid /= local_points.size()
	var best: Vector3 = centroid
	var best_d: float = 0.0
	for p in local_points:
		if (p - Vector3.ZERO).length() > best_d:
			best_d = (p - Vector3.ZERO).length()
			best = p
	print("centroid(local)=", centroid, " farthest from bone origin=", best, " dist=", best_d)
	var min_p: Vector3 = local_points[0]
	var max_p: Vector3 = local_points[0]
	for p in local_points:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	print("local aabb min=", min_p, " max=", max_p)
	quit()
