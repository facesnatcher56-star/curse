extends SceneTree
## Builds the GridMap MeshLibrary from the KayKit Dungeon Remastered structural pieces.
##   godot --headless --path . -s res://tools/build_dungeon_meshlib.gd
## Cell is 4 x 4 x 4 m (the kit's wall/floor module), cell_center_y off so floors sit at the cell bottom. Wall-like pieces are
## shifted half a cell so they sit on the cell's -Z edge; rotate them in 90 degree steps to reach the other edges.

const DIR := "res://assets/third_party/kaykit_dungeon/models/"
const OUT := "res://assets/third_party/kaykit_dungeon/dungeon_meshlib.tres"
const PREFIXES := ["floor_", "wall", "stairs", "pillar", "column", "barrier", "rubble"]
const EDGE_PREFIXES := ["wall", "stairs", "barrier"]

func _initialize() -> void:
	var names: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".gltf.glb"):
			var n := f.trim_suffix(".gltf.glb")
			for p in PREFIXES:
				if n.begins_with(p):
					names.append(n)
					break
	names.sort()
	var lib := MeshLibrary.new()
	var id := 0
	for n in names:
		var inst: Node = (load(DIR + n + ".gltf.glb") as PackedScene).instantiate()
		var mesh := ArrayMesh.new()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := Transform3D()
			var n3: Node = m
			while n3 != null and n3 != inst:
				xf = (n3 as Node3D).transform * xf
				n3 = n3.get_parent()
			for s in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in verts.size():
					verts[i] = xf * verts[i]
				for i in norms.size():
					norms[i] = (xf.basis * norms[i]).normalized()
				arr[Mesh.ARRAY_VERTEX] = verts
				arr[Mesh.ARRAY_NORMAL] = norms
				arr[Mesh.ARRAY_TANGENT] = null
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				mesh.surface_set_material(mesh.get_surface_count() - 1, m.mesh.surface_get_material(s))
		inst.free()
		if mesh.get_surface_count() == 0:
			continue
		lib.create_item(id)
		lib.set_item_name(id, n)
		lib.set_item_mesh(id, mesh)
		for p in EDGE_PREFIXES:
			if n.begins_with(p):
				lib.set_item_mesh_transform(id, Transform3D(Basis(), Vector3(0, 0, -2)))
				break
		lib.set_item_shapes(id, [mesh.create_convex_shape(true, true), Transform3D()])
		id += 1
	var err := ResourceSaver.save(lib, OUT)
	print("meshlib items=", id, " save_err=", err)
	quit()
