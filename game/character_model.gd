class_name CharacterModel
extends Node3D
## A Meshy-rigged GLB plus its separately generated animation clips merged into one AnimationPlayer.
## Folder layout (from tools/meshy.py): rigged.glb and anim_<clip>.glb.

const LOOPING: Array[String] = ["idle", "walk", "run"]

static var _libraries: Dictionary = {}

var anim: AnimationPlayer
var current: String = ""
## 0..1: lifts the right leg forward with a bent knee (a boot planted on something in front), applied after the
## animation has been evaluated each frame so it layers over whichever clip is playing.
var leg_raise: float = 0.0
var _leg_skeleton: Skeleton3D

static func build(folder: String, clips: Array[String]) -> CharacterModel:
	var model := CharacterModel.new()
	var rigged: Node = (load(folder + "/rigged.glb") as PackedScene).instantiate()
	model.add_child(rigged)
	model.anim = rigged.find_children("*", "AnimationPlayer", true, false)[0]
	model.anim.add_animation_library("game", _library(folder, clips))
	model.anim.mixer_applied.connect(model._after_mixer)
	model._give_fists(folder)
	return model

## Meshy modelled the Knight's hands flat and open, with no finger bones to close them, so a sword's grip went straight through the
## palm. Where a model comes with gauntlet fists (`fist_r.glb`, `fist_l.glb`, from tools/blender/make_fists.py) the open hands are
## shrunk away inside the wrists (the hand bones are scaled to almost nothing after every animation frame) and a closed fist rides
## each hand instead. The fists and the weapon follow the hand's un-shrunk pose (`_mounts`, moved in `_after_mixer`).
const HAND_BONES: Array[String] = ["RightHand", "LeftHand"]
var _mounts: Dictionary = {}   # hand bone name -> the node that follows it (without the shrinking)
var _mount_skeleton: Skeleton3D

func _give_fists(folder: String) -> void:
	if not ResourceLoader.exists(folder + "/fist_r.glb") or not ResourceLoader.exists(folder + "/fist_l.glb"):
		return
	_mount_skeleton = find_children("*", "Skeleton3D", true, false)[0]
	for side in [["RightHand", "r"], ["LeftHand", "l"]]:
		var mount := Node3D.new()
		_mount_skeleton.add_child(mount)
		_mounts[side[0]] = mount
		var fist: Node3D = (load("%s/fist_%s.glb" % [folder, side[1]]) as PackedScene).instantiate()
		LootDrop._use_vertex_colours(fist)
		mount.add_child(fist)

## What a weapon or prop is attached to: the hand's mount, or a plain bone attachment for any other bone.
func _mount_for(bone_name: String) -> Node3D:
	if _mounts.has(bone_name):
		return _mounts[bone_name]
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	find_children("*", "Skeleton3D", true, false)[0].add_child(attachment)
	return attachment

func _follow_hands() -> void:
	for bone_name in _mounts:
		var idx: int = _mount_skeleton.find_bone(bone_name)
		_mount_skeleton.set_bone_pose_scale(idx, Vector3.ONE)   # no animation track puts it back, so undo last frame's shrinking first
		(_mounts[bone_name] as Node3D).transform = _mount_skeleton.get_bone_global_pose(idx)
		_mount_skeleton.set_bone_pose_scale(idx, Vector3.ONE * 0.01)

static func _library(folder: String, clips: Array[String]) -> AnimationLibrary:
	if _libraries.has(folder):
		return _libraries[folder]
	# Preferred: the baked library from tools/bake_anims.gd (small, animation data only).
	if ResourceLoader.exists(folder + "/anims.res"):
		var baked: AnimationLibrary = load(folder + "/anims.res")
		_libraries[folder] = baked
		return baked
	var lib := AnimationLibrary.new()
	for clip in clips:
		var source: Node = (load("%s/anim_%s.glb" % [folder, clip]) as PackedScene).instantiate()
		var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
		var animation: Animation = player.get_animation(player.get_animation_list()[0]).duplicate()
		animation.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		lib.add_animation(clip, animation)
		source.free()
	_libraries[folder] = lib
	return lib

## Loop a clip (idle/walk/run); does nothing if it is already playing.
func loop(clip: String, speed: float = 1.0, blend: float = 0.15) -> void:
	if current == clip:
		anim.speed_scale = speed
		return
	current = clip
	anim.speed_scale = 1.0
	anim.play("game/" + clip, blend, speed)

## Play a clip once, from `start` seconds, at `speed`.
func once(clip: String, start: float = 0.0, speed: float = 1.0, blend: float = 0.1) -> void:
	current = clip
	anim.speed_scale = 1.0
	anim.play("game/" + clip, blend, speed)
	anim.seek(start, false)

## Start a clip that the caller scrubs by hand with scrub(), so wind-up and strike can use their own pacing.
func manual(clip: String, blend: float = 0.0) -> void:
	current = clip
	anim.speed_scale = 0.0
	anim.play("game/" + clip, blend, 1.0)

func scrub(position: float) -> void:
	anim.seek(position, true)

## Maps gameplay progress u (0..1) onto clip time: slow anticipation, fast strike at `hit`, easing recovery.
static func remap(u: float, hit: float, start: float, strike: float, end: float) -> float:
	if u < hit:
		# Long, slow gather (the weapon feels heavy to lift), then it accelerates hard into the strike.
		return start + (strike - start) * pow(u / hit, 2.4)
	var v: float = (u - hit) / (1.0 - hit)
	# Follow-through: the blade barely moves just after impact, as if the mass carries it, then recovers.
	const HOLD := 0.2
	const HOLD_PROGRESS := 0.05
	if v < HOLD:
		return strike + (end - strike) * HOLD_PROGRESS * (v / HOLD)
	var w: float = (v - HOLD) / (1.0 - HOLD)
	return strike + (end - strike) * (HOLD_PROGRESS + (1.0 - HOLD_PROGRESS) * (1.0 - pow(1.0 - w, 2.0)))

var weapon: Node3D
var weapon_base: Node3D
var weapon_tip: Node3D

## Set to a world-space direction to make the blade point that way regardless of the animation (blended in
## and out); null returns it to the grip the animation gives. `weapon_length_mult` stretches the blade while aiming.
var weapon_aim: Variant = null
var weapon_length_mult: float = 1.0
var weapon_blade_range: Vector2 = Vector2(0.0, 1.0)  # blade extent along the sword mesh's own Y axis
var _weapon_grip: Basis = Basis()
var _weapon_scale_vec: Vector3 = Vector3.ONE
var _aim_blend: float = 0.0
var _last_aim: Vector3 = Vector3.FORWARD

func _init() -> void:
	process_priority = 100  # after the AnimationPlayer, so our override wins the frame

## Parents a separately generated prop (upright, blade along +Y) to a hand bone.
## `grip` rotates the prop into the fist; `length` is the blade length in metres.
func attach_weapon(scene_path: String, bone_name: String, grip: Basis, length: float, grip_offset: float,
		hand_offset: Vector3 = Vector3.ZERO, thickness: float = 1.0, prop_basis: Basis = Basis(), tint_by_vertex: bool = false) -> void:
	var skeleton: Skeleton3D = find_children("*", "Skeleton3D", true, false)[0]
	var attachment: Node3D = _mount_for(bone_name)
	var prop: Node3D = (load(scene_path) as PackedScene).instantiate()
	if tint_by_vertex:
		LootDrop._use_vertex_colours(prop)
	# prop_basis stands a model that was built lying down (long axis X) up along Y, the way the grip expects.
	var bounds: AABB = Transform3D(prop_basis, Vector3.ZERO) * _bounds_of(prop)
	var scale_factor: float = length / maxf(bounds.size.y, 0.001)
	# The skeleton is scaled (cm rig); counter it so the prop keeps its real size.
	var rig_scale: float = skeleton.global_transform.basis.get_scale().x
	var holder := Node3D.new()
	_weapon_grip = grip
	# The guard sits about 36% up the sword mesh; everything above that is blade.
	var mesh_aabb: AABB = bounds
	weapon_blade_range = Vector2(mesh_aabb.position.y + 0.36 * mesh_aabb.size.y, mesh_aabb.end.y)
	_weapon_scale_vec = Vector3.ONE * scale_factor / maxf(rig_scale, 0.0001)
	holder.basis = grip.scaled(_weapon_scale_vec)
	# Bone origin is the wrist; hand_offset (bone space, rig units) moves the grip into the palm.
	holder.position = hand_offset
	attachment.add_child(holder)
	# Pommel at the origin, grip_offset (fraction of length) up the blade sits in the hand.
	# Thickness widens the blade (not its length) so the sword reads as a heavy piece of steel.
	prop.basis = Basis.from_scale(Vector3(thickness, 1.0, thickness)) * prop_basis
	prop.position = Vector3(-bounds.get_center().x * thickness, -bounds.position.y - grip_offset * bounds.size.y,
		-bounds.get_center().z * thickness)
	holder.add_child(prop)
	weapon = holder
	weapon_base = Node3D.new()
	weapon_base.position = Vector3(0, (1.0 - length * 0.0) * bounds.size.y * 0.62 - grip_offset * bounds.size.y, 0)
	holder.add_child(weapon_base)
	weapon_tip = Node3D.new()
	weapon_tip.position = Vector3(0, bounds.size.y * 1.0 - grip_offset * bounds.size.y, 0)
	holder.add_child(weapon_tip)

## Takes the held weapon off (its model and the bone attachment holding it).
func clear_weapon() -> void:
	if weapon != null and is_instance_valid(weapon):
		if weapon.get_parent() is BoneAttachment3D:
			weapon.get_parent().queue_free()
		else:
			weapon.queue_free()
	weapon = null
	weapon_base = null
	weapon_tip = null

## Combined bounds of all meshes under `node`, in the node's own space (nested transforms included).
func _process(delta: float) -> void:
	if weapon == null:
		return
	if weapon_aim != null:
		_last_aim = (weapon_aim as Vector3).normalized()
	_aim_blend = move_toward(_aim_blend, 1.0 if weapon_aim != null else 0.0, delta * 7.0)
	if _aim_blend <= 0.0:
		return
	var parent: Node3D = weapon.get_parent() as Node3D
	var parent_basis: Basis = parent.global_transform.basis.orthonormalized()
	var y: Vector3 = _last_aim
	var x: Vector3 = y.cross(Vector3.UP)
	x = x.normalized() if x.length() > 0.01 else Vector3.RIGHT
	var z: Vector3 = x.cross(y)
	var desired: Basis = parent_basis.inverse() * Basis(x, y, z)
	var stretch := Vector3(1.0, lerpf(1.0, weapon_length_mult, _aim_blend), 1.0)
	weapon.basis = _weapon_grip.slerp(desired, _aim_blend) * Basis.from_scale(_weapon_scale_vec * stretch)

static func _bounds_of(node: Node) -> AABB:
	var result := AABB()
	var first: bool = true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var xf: Transform3D = Transform3D.IDENTITY
		var walker: Node = mi
		while walker != null and walker != node:
			xf = (walker as Node3D).transform * xf
			walker = walker.get_parent()
		var box: AABB = xf * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
## A material that draws blood on the blade only (see blood_blade.gdshader).
func make_blade_blood_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://game/blood_blade.gdshader")
	material.set_shader_parameter("blade_start", weapon_blade_range.x)
	material.set_shader_parameter("blade_end", weapon_blade_range.y)
	material.set_shader_parameter("amount", 0.0)
	return material

## Tints just the weapon (blood on the blade). Pass null to clear.
func set_weapon_overlay(material: Material) -> void:
	if weapon == null:
		return
	for node in weapon.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = material

func set_overlay(material: Material) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = material

func _after_mixer() -> void:
	_follow_hands()
	if leg_raise <= 0.001:
		return
	if _leg_skeleton == null:
		_leg_skeleton = find_children("*", "Skeleton3D", true, false)[0]
	_rotate_bone_about_x("RightUpLeg", -1.8 * leg_raise)   # thigh forward and up
	_rotate_bone_about_x("RightLeg", 0.5 * leg_raise)      # knee bends the shin back down
	_rotate_bone_about_x("RightFoot", -0.25 * leg_raise)

## Rotates a bone about the skeleton's X axis (the character's left-right axis), on top of its animated pose.
func _rotate_bone_about_x(bone_name: String, angle: float) -> void:
	var idx: int = _leg_skeleton.find_bone(bone_name)
	if idx < 0:
		return
	var parent: int = _leg_skeleton.get_bone_parent(idx)
	var parent_basis: Basis = _leg_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var global_basis: Basis = _leg_skeleton.get_bone_global_pose(idx).basis
	var turned: Basis = Basis(Vector3.RIGHT, angle) * global_basis
	_leg_skeleton.set_bone_pose_rotation(idx, (parent_basis.inverse() * turned).get_rotation_quaternion())
