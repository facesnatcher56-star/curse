extends SceneTree
## Debug helper: godot --headless --path . --script tools/inspect_glb.gd -- res://assets/models/hero

func _init() -> void:
	var folder: String = OS.get_cmdline_user_args()[0]
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".glb"):
			continue
		var scene: PackedScene = load(folder + "/" + file)
		if scene == null:
			print(file, ": failed to load")
			continue
		var root: Node = scene.instantiate()
		print("== ", file, " root=", root.name, " (", root.get_class(), ")")
		_dump(root, 1, file == "rigged.glb" or file == "anim_idle.glb" or file == "model.glb")
		for ap in root.find_children("*", "AnimationPlayer", true, false):
			for anim_name in (ap as AnimationPlayer).get_animation_list():
				var anim: Animation = (ap as AnimationPlayer).get_animation(anim_name)
				var first: String = str(anim.track_get_path(0)) if anim.get_track_count() > 0 else "-"
				print("   anim '", anim_name, "' len=", snappedf(anim.length, 0.01), " tracks=", anim.get_track_count(), " first=", first)
		root.free()
	quit()

func _dump(node: Node, depth: int, show: bool) -> void:
	if show and depth < 5:
		var extra: String = ""
		if node is MeshInstance3D:
			var aabb: AABB = (node as MeshInstance3D).get_aabb()
			extra = " aabb=" + str(aabb.size)
		if node is Skeleton3D:
			extra = " bones=" + str((node as Skeleton3D).get_bone_count())
		print("  ".repeat(depth), node.name, " [", node.get_class(), "]", extra)
	for child in node.get_children():
		_dump(child, depth + 1, show)
