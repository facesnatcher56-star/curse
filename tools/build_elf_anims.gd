extends SceneTree
## Bakes the wood elf's (Cutter's) own clip library, assets/models/elf/anims.res: every barbarian clip adapted to his
## proportions (CharacterModel._borrowed, as before), plus his bow clips keyed in Blender on his own rig
## (tools/art/elf/bow_anims.py -> assets/art_staging/elf/bow_clips.glb): bow_idle (loops), bow_draw, bow_release.
## His rig's twist and joint-helper bones are driven at runtime (JointHelpers), so their tracks are dropped here.
##   godot --headless --path . --script tools/build_elf_anims.gd

const ELF := "res://assets/models/elf"
const BARBARIAN := "res://assets/models/barbarian"
const OUT := "res://assets/models/elf/anims.res"
const BOW_CLIPS := "res://assets/art_staging/elf/bow_clips.glb"
const LOOPING: Array[String] = ["bow_idle"]

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var clips: Array[String] = []
	clips.assign(Player.CLIPS)
	var lib := CharacterModel._borrowed(ELF, BARBARIAN, clips) as AnimationLibrary
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err: int = document.append_from_file(ProjectSettings.globalize_path(BOW_CLIPS), state)
	assert(err == OK, "cannot read " + BOW_CLIPS)
	var scene: Node = document.generate_scene(state)
	var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	for name in player.get_animation_list():
		var animation := player.get_animation(name).duplicate(true) as Animation
		for track in range(animation.get_track_count() - 1, -1, -1):
			var path := String(animation.track_get_path(track))
			if path.ends_with("Twist") or path.ends_with("Help"):
				animation.remove_track(track)
			elif animation.track_get_type(track) != Animation.TYPE_ROTATION_3D and not path.ends_with(":Hips"):
				# bones keep their length: only the hips move; the export's other position (and scale) tracks are dropped,
				# as CharacterModel._borrowed does (they put the shoulders 25 cm off)
				animation.remove_track(track)
		_hold_unkeyed_at_rest(animation)
		animation.loop_mode = Animation.LOOP_LINEAR if String(name) in LOOPING else Animation.LOOP_NONE
		lib.add_animation(name, animation)
		print("BUILD bow clip %s (%.2fs, %d tracks, first track %s)" % [name, animation.length, animation.get_track_count(), animation.track_get_path(0)])
	scene.free()
	print("BUILD saved ", OUT, " clips ", lib.get_animation_list().size(), " err ", ResourceSaver.save(lib, OUT))
	quit()

## Blender's glTF export drops the tracks of bones that stay at rest through a clip (the collarbones, most finger joints). In the
## game such a bone would keep whatever the previous clip left it at (the borrowed sword idle bends the collarbones), throwing
## the arms off, so every bone the clip does not key gets a track holding its rest rotation. Helpers are driven (JointHelpers).
func _hold_unkeyed_at_rest(animation: Animation) -> void:
	var rigged: Node = (load(ELF + "/rigged.glb") as PackedScene).instantiate()
	var sk: Skeleton3D = rigged.find_children("*", "Skeleton3D", true, false)[0]
	var keyed := {}
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			keyed[String(animation.track_get_path(t)).get_slice(":", 1)] = true
	for i in sk.get_bone_count():
		var bone := sk.get_bone_name(i)
		if keyed.has(bone) or bone.ends_with("Twist") or bone.ends_with("Help"):
			continue
		var t := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(t, NodePath("Armature/Skeleton3D:" + bone))
		animation.rotation_track_insert_key(t, 0.0, sk.get_bone_rest(i).basis.get_rotation_quaternion())
	rigged.free()
