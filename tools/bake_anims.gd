extends SceneTree
## Bakes the animation data from Meshy's anim_*.glb downloads into one small AnimationLibrary resource.
## Raw downloads live outside the project (~/.meshy/cache/<asset>) because each one embeds the full mesh.
##   godot --headless --path . --script tools/bake_anims.gd -- res://assets/models/hero C:/Users/me/.meshy/cache/hero
## Optional third argument "hips_first_frame" (staged metre rigs only): hips X and Z are pinned to each clip's
## own first-frame values instead of the cm constants below, and hips Y is left free, so a clip can drop
## the hips through the ground. The default (no argument) output is unchanged.

const LOOPING: Array[String] = ["idle", "walk", "run"]

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var res_folder: String = args[0]
	var cache: String = args[1]
	var hips_mode: String = args[2] if args.size() > 2 else "cm"
	var lib := AnimationLibrary.new()
	for file in DirAccess.get_files_at(cache):
		if not file.begins_with("anim_") or not file.ends_with(".glb"):
			continue
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var err: int = document.append_from_file(cache + "/" + file, state)
		if err != OK:
			push_error("failed to read " + file)
			continue
		var scene: Node = document.generate_scene(state)
		var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var animation: Animation = player.get_animation(player.get_animation_list()[0]).duplicate()
		var clip: String = file.trim_prefix("anim_").trim_suffix(".glb")
		animation.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		if hips_mode == "hips_first_frame":
			_pin_hips_to_first_frame(animation)
		else:
			_strip_root_motion(animation)
		lib.add_animation(clip, animation)
		print("baked ", clip, " (", snappedf(animation.length, 0.01), "s, ", animation.get_track_count(), " tracks)")
		scene.free()
	var save_err: int = ResourceSaver.save(lib, res_folder + "/anims.res")
	print("saved ", res_folder, "/anims.res -> ", save_err)
	quit()

## Meshy clips carry real root motion (swings drift the hips forward by up to 1-2.6 m, idles wander).
## The game moves characters with physics, so pin the hips' horizontal position (rig units are cm)
## and keep only the vertical motion (crouching, falling, rolling).
const HIPS_X := 0.5
const HIPS_Z := -4.0

## Staged metre rigs: keep the hips' vertical motion, hold horizontal position at the clip's own start.
func _pin_hips_to_first_frame(animation: Animation) -> void:
	var idx: int = animation.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_POSITION_3D)
	if idx < 0 or animation.track_get_key_count(idx) == 0:
		return
	var first: Vector3 = animation.track_get_key_value(idx, 0)
	for key in animation.track_get_key_count(idx):
		var value: Vector3 = animation.track_get_key_value(idx, key)
		animation.track_set_key_value(idx, key, Vector3(first.x, value.y, first.z))

func _strip_root_motion(animation: Animation) -> void:
	var idx: int = animation.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_POSITION_3D)
	if idx < 0:
		return
	for key in animation.track_get_key_count(idx):
		var value: Vector3 = animation.track_get_key_value(idx, key)
		animation.track_set_key_value(idx, key, Vector3(HIPS_X, value.y, HIPS_Z))
