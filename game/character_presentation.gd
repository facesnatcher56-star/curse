class_name CharacterPresentation
extends RefCounted
## Identity chooses artwork and rig only. Every rig receives the same supported combat clips.
const MEMBERS := {
	"hero": {"model": "res://assets/models/barbarian", "portrait": "res://assets/ui/busts/knight.png", "name": "Hero"},
	"cutter": {"model": "res://assets/models/elf", "portrait": "res://assets/ui/busts/priest.png", "name": "Cutter"},
}

static func folder(member_id: String) -> String:
	return MEMBERS.get(member_id, MEMBERS["hero"])["model"]

static func share_combat_clips(model: CharacterModel) -> void:
	var library := model.anim.get_animation_library("game")
	var source := CharacterModel._library("res://assets/models/knight2", Player.CLIPS)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var root: Node = model.anim.get_node(model.anim.root_node)
	var skeleton_path := str(root.get_path_to(skeleton))
	for clip in source.get_animation_list():
		if library.has_animation(clip): continue
		var animation := source.get_animation(clip).duplicate(true) as Animation
		for track in range(animation.get_track_count() - 1, -1, -1):
			var path := str(animation.track_get_path(track))
			var parts := path.split(":")
			if parts.size() > 1 and skeleton.find_bone(parts[1]) >= 0:
				animation.track_set_path(track, NodePath(skeleton_path + ":" + parts[1]))
			else:
				animation.remove_track(track)
		library.add_animation(clip, animation)
