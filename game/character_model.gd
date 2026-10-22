class_name CharacterModel
extends Node3D
## A Meshy-rigged GLB plus its separately generated animation clips merged into one AnimationPlayer.
## Folder layout (from tools/meshy.py): rigged.glb and anim_<clip>.glb.

const LOOPING: Array[String] = ["idle", "walk", "run"]

static var _libraries: Dictionary = {}
## Rigs that play another rig's clips: same bone names and rest rotations (every playable character is rigged to the knight2
## skeleton's orientations, docs/art/PIPELINE.md). The barbarian bakes his own library from the knight's
## (tools/build_barbarian_anims.gd); the elf shares the barbarian's, adapted to his proportions.
const ANIM_SOURCE := {"res://assets/models/barbarian": "res://assets/models/knight2",
	"res://assets/models/elf": "res://assets/models/barbarian"}

## Render layer of every character mesh and what it holds, on top of the default layer: AtmosphereProfile.add_actor_lights
## lights only this layer, so characters stand out from the stone without the world getting brighter.
const ACTOR_LAYER := 1 << 9

static func mark_actor(root: Node) -> void:
	for node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).layers |= ACTOR_LAYER

var folder: String = ""   # the rig folder this model was built from (assets/models/<rig>)
## False for a rig whose item models are not built yet (the barbarian, data/appearance/equipment_visuals.json `rigs`):
## held weapons and bows keep their nodes (skill effects anchor to the blade's base and tip) but draw nothing.
var show_items: bool = true
var anim: AnimationPlayer
var current: String = ""
## 0..1: lifts the right leg forward with a bent knee (a boot planted on something in front), applied after the
## animation has been evaluated each frame so it layers over whichever clip is playing.
var leg_raise: float = 0.0
var _leg_skeleton: Skeleton3D
var reaction := BodyRecoil.new()   # how the torso takes a blow (see BodyRecoil); applied after the animation each frame
var _spine: Array[int] = []
var _neck_bone: int = -1
var _head_bone: int = -1
var _thighs: Array[int] = []     # left, right
var _react_skeleton: Skeleton3D
## 0..1: how far the upper body is held in the shield-guard pose (ShieldGuard, map mode). The pose is the `game/block` clip's held frame,
## written over the spine, arms and head after the animation each frame (the legs keep the walk): upper-body layering without an AnimationTree.
var guard_amount: float = 0.0
const GUARD_CLIP := "game/block"
const GUARD_TIME := 0.30   # the clip's held guard (see tools/author_block_anims.gd: 0.30 s "the guard sets again")
const GUARD_ROOT := "Spine"
var _guard_skeleton: Skeleton3D
var _guard_bones: Array = []   # [bone index, rotation track index] for every bone at or under the spine
var _reaction_owner: Node        # Actor that owns this model, for ragdoll/death cleanup

static func build(folder: String, clips: Array[String], fists: bool = true) -> CharacterModel:
	var model := CharacterModel.new()
	model.folder = folder
	model.show_items = bool(ModularAppearance.rig(folder)["equipment_pieces"])
	var rigged: Node = (load(folder + "/rigged.glb") as PackedScene).instantiate()
	mark_actor(rigged)
	model.add_child(rigged)
	var players := rigged.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():   # a rig exported without clips of its own (the barbarian): its tracks are rooted at the rig root
		players.append(AnimationPlayer.new())
		rigged.add_child(players[0])
	model.anim = players[0]
	model.anim.add_animation_library("game", _library(folder, clips))
	model.anim.mixer_applied.connect(model._after_mixer)
	var skeleton: Skeleton3D = rigged.find_children("*", "Skeleton3D", true, false)[0]
	if JointHelpers.has_helpers(skeleton):   # twist and joint-helper bones turn with the joints after every pose (JointHelpers)
		skeleton.add_child(JointHelpers.new())
	if fists:
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
		mark_actor(fist)
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
	if ANIM_SOURCE.has(folder) and not ResourceLoader.exists(folder + "/anims.res"):   # its own baked clips win
		_libraries[folder] = _borrowed(folder, ANIM_SOURCE[folder], clips)
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

## Another rig's clips for a rig with the same bone names and rest rotations but its own proportions. Rotation tracks carry
## over unchanged. The source keys the hips and the thigh roots by position: the hips track is moved by the difference of
## the two rest poses (so the feet stay on the ground), and the other position tracks are dropped (they would drag the
## joints to the source's proportions; with them gone those bones keep this rig's rest offsets).
static func _borrowed(folder: String, source: String, clips: Array[String]) -> AnimationLibrary:
	var from := _library(source, clips)
	var offset: Vector3 = _rest_origin(folder, "Hips") - _rest_origin(source, "Hips")
	var lib := AnimationLibrary.new()
	for clip in from.get_animation_list():
		var animation := from.get_animation(clip).duplicate(true) as Animation
		for track in range(animation.get_track_count() - 1, -1, -1):
			if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
				continue
			if String(animation.track_get_path(track)).ends_with(":Hips"):
				for key in animation.track_get_key_count(track):
					animation.track_set_key_value(track, key, (animation.track_get_key_value(track, key) as Vector3) + offset)
			else:
				animation.remove_track(track)
		lib.add_animation(clip, animation)
	return lib

static func _rest_origin(folder: String, bone: String) -> Vector3:
	var rigged: Node = (load(folder + "/rigged.glb") as PackedScene).instantiate()
	var skeleton: Skeleton3D = rigged.find_children("*", "Skeleton3D", true, false)[0]
	var origin: Vector3 = skeleton.get_bone_rest(skeleton.find_bone(bone)).origin
	rigged.free()
	return origin

## Clips played in place of others while it is set (e.g. an archer with his bow out stands in "bow_idle" wherever "idle_alert"
## is asked for: BowAttack). Only names the library has.
var aliases: Dictionary = {}

func has_clip(clip: String) -> bool:
	return anim.has_animation("game/" + clip)

## Loop a clip (idle/walk/run); does nothing if it is already playing.
func loop(clip: String, speed: float = 1.0, blend: float = 0.15) -> void:
	clip = aliases.get(clip, clip)
	if current == clip:
		anim.speed_scale = speed
		return
	current = clip
	anim.speed_scale = 1.0
	anim.play("game/" + clip, blend, speed)

## Play a clip once, from `start` seconds, at `speed`.
func once(clip: String, start: float = 0.0, speed: float = 1.0, blend: float = 0.1) -> void:
	clip = aliases.get(clip, clip)
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
	mark_actor(prop)
	prop.visible = show_items
	weapon = holder
	weapon_base = Node3D.new()
	weapon_base.position = Vector3(0, (1.0 - length * 0.0) * bounds.size.y * 0.62 - grip_offset * bounds.size.y, 0)
	holder.add_child(weapon_base)
	weapon_tip = Node3D.new()
	weapon_tip.position = Vector3(0, bounds.size.y * 1.0 - grip_offset * bounds.size.y, 0)
	holder.add_child(weapon_tip)

## The grip of a hand with finger bones (the detailed skeleton, hands resting closed): [grip basis, centre] in the hand
## bone's space, for attach_weapon. The handle runs through the closed fist from the little finger towards the index
## finger (the blade's +Y), centred between the knuckles and the curled finger ends; the edge faces the way the knuckles
## point. Empty for a hand without finger bones.
func finger_grip(side: String) -> Array:
	var skeleton: Skeleton3D = find_children("*", "Skeleton3D", true, false)[0]
	var hand := skeleton.find_bone(side + "Hand")
	if hand < 0 or skeleton.find_bone(side + "HandIndex1") < 0:
		return []
	var to_hand: Transform3D = skeleton.get_bone_global_rest(hand).affine_inverse()
	var joint := func(bone: String) -> Vector3: return to_hand * skeleton.get_bone_global_rest(skeleton.find_bone(side + "Hand" + bone)).origin
	var ring := Vector3.ZERO
	for finger in ["Index", "Middle", "Ring", "Pinky"]:
		ring += (joint.call(finger + "1") as Vector3) + (joint.call(finger + "3") as Vector3)
	var centre: Vector3 = ring / 8.0
	var up: Vector3 = ((joint.call("Index1") as Vector3) - (joint.call("Pinky1") as Vector3)).normalized()
	var forward: Vector3 = centre - up * centre.dot(up)   # from the wrist towards the fist, across the handle
	forward = forward.normalized()
	return [Basis(forward, up, forward.cross(up)), centre]

## Shows or hides the held weapon's model (its nodes stay either way).
func show_weapon(on: bool) -> void:
	if weapon != null and weapon.get_child_count() > 0:
		(weapon.get_child(0) as Node3D).visible = on

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
	if reaction.active():
		if is_instance_valid(_reaction_owner) and (bool(_reaction_owner.get("dead")) or bool(_reaction_owner.call("is_ragdolled"))):
			reaction.clear()
		else:
			reaction.step(delta)
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
	if guard_amount > 0.001:
		_apply_guard()
	if reaction.active():
		_apply_hit_reaction()
	_follow_hands()
	if leg_raise <= 0.001:
		return
	if _leg_skeleton == null:
		_leg_skeleton = find_children("*", "Skeleton3D", true, false)[0]
	_rotate_bone_about_x("RightUpLeg", -1.8 * leg_raise)   # thigh forward and up
	_rotate_bone_about_x("RightLeg", 0.5 * leg_raise)      # knee bends the shin back down
	_rotate_bone_about_x("RightFoot", -0.25 * leg_raise)

func _find_guard_bones() -> void:
	_guard_bones = []
	var skeletons: Array[Node] = find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or anim == null or not anim.has_animation(GUARD_CLIP):
		return
	_guard_skeleton = skeletons[0] as Skeleton3D
	var root: int = _guard_skeleton.find_bone(GUARD_ROOT)
	var clip: Animation = anim.get_animation(GUARD_CLIP)
	for t in clip.get_track_count():
		if clip.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone: int = _guard_skeleton.find_bone(String(clip.track_get_path(t)).get_slice(":", 1))
		var walker: int = bone
		while walker >= 0 and walker != root:
			walker = _guard_skeleton.get_bone_parent(walker)
		if bone >= 0 and walker == root and root >= 0:
			_guard_bones.append([bone, t])

## Blends the spine and everything above it toward the held guard pose; the hips and legs keep whatever clip is playing.
func _apply_guard() -> void:
	if _guard_skeleton == null:
		_find_guard_bones()
	if _guard_bones.is_empty():
		return
	var clip: Animation = anim.get_animation(GUARD_CLIP)
	for pair in _guard_bones:
		var bone: int = pair[0]
		var target: Quaternion = clip.rotation_track_interpolate(pair[1], GUARD_TIME)
		_guard_skeleton.set_bone_pose_rotation(bone, _guard_skeleton.get_bone_pose_rotation(bone).slerp(target, guard_amount))

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


## A blow lands: `away` is the horizontal world direction it pushes the body, `peak` how far (rad) the chest should tip (BodyRecoil.peak_for).
func react(away: Vector3, peak: float) -> void:
	if _reaction_owner == null:
		var visual_parent: Node = get_parent()
		var actor_candidate: Node = visual_parent.get_parent() if visual_parent != null else null
		if actor_candidate != null and actor_candidate.has_method("is_ragdolled"):
			_reaction_owner = actor_candidate
	var facing: Vector3 = global_transform.basis.z   # models face +Z (Actor.face)
	reaction.hit(away, facing, peak)

func _find_reaction_bones() -> void:
	var skeletons: Array[Node] = find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_react_skeleton = skeletons[0] as Skeleton3D
	var found: Array[int] = []
	for i in _react_skeleton.get_bone_count():
		var lowered: String = _react_skeleton.get_bone_name(i).to_lower()
		if lowered.contains("spine"):
			found.append(i)
		elif lowered == "leftupleg" or lowered.ends_with(":leftupleg"):
			_thighs.resize(2)
			_thighs[0] = i
		elif lowered == "rightupleg" or lowered.ends_with(":rightupleg"):
			_thighs.resize(2)
			_thighs[1] = i
		elif lowered == "neck" or lowered.ends_with(":neck"):
			_neck_bone = i
		elif lowered == "head" or lowered.ends_with(":head"):
			_head_bone = i
	# lowest in the hierarchy first: a bone's depth is how many parents it has
	var depths: Dictionary = {}
	for bone in found:
		var n: int = 0
		var p: int = _react_skeleton.get_bone_parent(bone)
		while p >= 0:
			n += 1
			p = _react_skeleton.get_bone_parent(p)
		depths[bone] = n
	found.sort_custom(func(a: int, b: int) -> bool: return depths[a] < depths[b])
	_spine = found

## Tips the spine, neck and head by the reaction's springs, on top of whatever the clip is playing.
func _apply_hit_reaction() -> void:
	if _react_skeleton == null:
		_find_reaction_bones()
	if _react_skeleton == null or _spine.is_empty():
		reaction.step(10.0)   # no usable skeleton: let it finish at once
		return
	var inverse: Basis = _react_skeleton.global_transform.basis.orthonormalized().inverse()
	var count: int = _spine.size()
	for i in count:
		var share: float = (0.7 + 0.6 * float(i) / maxf(count - 1, 1)) / float(count)   # the upper spine bends more than the lower
		_turn_bone(_spine[i], reaction.lean * share, reaction.twist * share, inverse)
	if reaction.step_t > 0.0 and _thighs.size() == 2 and _thighs[0] > 0 and _thighs[1] > 0:
		# the recovery step: the thigh swings the foot out the way the body is being pushed, then plants it
		var recovery_reach: float = lerpf(0.75, 1.1, clampf((reaction.step_peak - BodyRecoil.STEP_PEAK) / (BodyRecoil.MAX_LEAN - BodyRecoil.STEP_PEAK), 0.0, 1.0))
		_turn_bone(_thighs[reaction.step_leg], -reaction.step_dir * (recovery_reach * reaction.step_swing()), 0.0, inverse)
	if _neck_bone >= 0:
		_turn_bone(_neck_bone, reaction.head * 0.25, 0.0, inverse)
	if _head_bone >= 0:
		_turn_bone(_head_bone, reaction.head * 0.45 - reaction.lean * 0.15, reaction.twist * -0.4, inverse)

## Rotates one bone: tips it toward the horizontal world vector `tilt` (magnitude = angle) and turns it about the vertical by `yaw`, in addition to its pose.
func _turn_bone(bone: int, tilt: Vector2, yaw: float, inverse_skeleton: Basis) -> void:
	var angle: float = tilt.length()
	var turn := Basis()
	if angle > 0.0005:
		var axis_world: Vector3 = Vector3.UP.cross(Vector3(tilt.x, 0.0, tilt.y)).normalized()
		turn = Basis((inverse_skeleton * axis_world).normalized(), angle)
	if absf(yaw) > 0.0005:
		turn = Basis((inverse_skeleton * Vector3.UP).normalized(), yaw) * turn
	var parent: int = _react_skeleton.get_bone_parent(bone)
	var parent_basis: Basis = _react_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var global_basis: Basis = _react_skeleton.get_bone_global_pose(bone).basis
	_react_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * (turn * global_basis)).get_rotation_quaternion())
