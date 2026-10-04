extends SceneTree
## godot --headless --path . --script tools/sword_profile.gd
## Prints the sword mesh's width along its length so the blade/guard boundary can be found.
func _init() -> void:
	var scene: Node = (load("res://assets/models/sword/model.glb") as PackedScene).instantiate()
	root.add_child(scene)
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var aabb: AABB = mi.get_aabb()
	print("mesh aabb pos=", aabb.position, " size=", aabb.size, " node xform=", mi.transform)
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bins: int = 24
	var width: Array[float] = []
	for i in bins:
		width.append(0.0)
	for v in verts:
		var t: float = clampf((v.y - aabb.position.y) / aabb.size.y, 0.0, 0.9999)
		var b: int = int(t * bins)
		width[b] = maxf(width[b], maxf(absf(v.x - aabb.get_center().x), absf(v.z - aabb.get_center().z)))
	for i in bins:
		print("%2d  y=%.2f  half-width=%.3f %s" % [i, float(i) / bins, width[i], "#".repeat(int(width[i] / aabb.size.y * 200.0))])
	quit()