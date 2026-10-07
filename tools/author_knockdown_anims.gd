extends SceneTree
## Authors the hero's knockdown clip ("knockdown") on the Knight's own rig and adds it to assets/models/knight2/anims.res (nothing else
## in the library is touched):   godot --headless --path . --script tools/author_knockdown_anims.gd
##
## One continuous 1.30 s clip that the game scrubs by the Knockdown state machine's own clock (Knockdown.clip_time), so the gameplay
## phases keep their exact lengths: 0.00-0.30 thrown off his feet and slammed down, 0.30-0.75 flat on his back and winded, 0.75-1.30
## roll onto a hip and plant the free hand, drag a knee under the body, then drive up on the legs into the idle stance.
##
## Poses are keyed as DIRECTIONS in the skeleton's frame (x = the hero's left, y = up, z = forward; rig units are cm): where each bone
## points (every bone's own +Y runs toward its child), plus the hips' tilt and place and the way the sword points. Each bone is turned by
## the shortest arc from the idle pose onto its direction, after its parent, so the clip never drifts with the idle's own animation.
## A key's height can be given as "ground": [bone, cm] and the hips are lowered until that bone is at that height.

const DIR := "res://assets/models/knight2"
const TRACK := "Armature/Skeleton3D:"
const FPS := 60.0
const LENGTH := 1.30
const CLIP := "knockdown"
const SPINE_FRACTIONS: Array[float] = [0.33, 0.66, 1.0]

# hp/hy/hr: hips pitch (negative = back), yaw, roll in degrees; hips: where they are (cm); torso: where the spine points;
# head; la/lf, ra/rf: upper arm / forearm; lt/ls/lfoot, rt/rs/rfoot: thigh / shin / foot; blade: the sword's direction.
const LYING := {
	"hp": -86.0, "hy": 0.0, "hr": 4.0, "hips": Vector3(0, 13, -16), "torso": Vector3(0.0, 0.10, -1.0), "head": Vector3(0.0, 0.25, -1.0),
	"la": Vector3(0.62, -0.12, -0.78), "lf": Vector3(0.9, -0.1, -0.42),
	"ra": Vector3(-0.66, -0.05, -0.74), "rf": Vector3(-0.9, 0.06, -0.1),
	"lt": Vector3(0.14, 0.02, 1.0), "ls": Vector3(0.12, -0.12, 1.0), "lfoot": Vector3(0.15, 0.85, 0.5),
	"rt": Vector3(-0.2, 0.06, 1.0), "rs": Vector3(-0.2, -0.1, 1.0), "rfoot": Vector3(-0.2, 0.85, 0.5),
	"blade": Vector3(-0.3, 0.0, 0.95),
}

var _sk: Skeleton3D
var _names: Array[String] = []
var _rest_pos: Array[Vector3] = []
var _parent: Array[int] = []
var _idle: Animation
var _idle_hips_global: Quaternion

func _init() -> void:
	var rigged: Node = (load(DIR + "/rigged.glb") as PackedScene).instantiate()
	_sk = rigged.find_children("*", "Skeleton3D", true, false)[0]
	for i in _sk.get_bone_count():
		_names.append(_sk.get_bone_name(i))
		_rest_pos.append(_sk.get_bone_rest(i).origin)
		_parent.append(_sk.get_bone_parent(i))
	var lib: AnimationLibrary = (load(DIR + "/anims.res") as AnimationLibrary).duplicate(true)
	_idle = lib.get_animation("idle_alert")
	var keys: Array = _keys()
	if lib.has_animation(CLIP):
		lib.remove_animation(CLIP)
	lib.add_animation(CLIP, _author(keys))
	print(CLIP, ": ", LENGTH, " s, ", keys.size(), " keys")
	print("saved -> ", ResourceSaver.save(lib, DIR + "/anims.res"))
	quit()

# --- the keys ---------------------------------------------------------------------------------------------------------------------
## [time, pose, ease]. ease > 1 starts slowly and ends hard (a fall); < 1 starts hard and settles; 1 is a plain smoothstep.
func _keys() -> Array:
	var stand: Dictionary = _stand_pose()
	var lying: Dictionary = _merge(stand, LYING)
	# Thrown: the blow turns the chest back and the head whips; the knees give.
	var struck: Dictionary = _merge(stand, {
		"hp": -14.0, "hips": Vector3(1, 101, -11), "torso": Vector3(0.0, 0.93, -0.36), "head": Vector3(0.0, 0.8, 0.5),
		"la": Vector3(0.7, 0.2, -0.65), "lf": Vector3(0.45, -0.25, 0.85), "ra": Vector3(-0.75, 0.15, -0.6), "rf": Vector3(-0.55, 0.0, 0.8),
		"lt": Vector3(0.1, -0.88, 0.45), "ls": Vector3(0.05, -0.8, -0.55), "rt": Vector3(-0.1, -0.88, 0.45), "rs": Vector3(-0.05, -0.82, -0.5),
		"blade": Vector3(-0.45, 0.35, 0.82)})
	# Airborne: hips up and back, the body on its way to flat, arms flung wide, the legs trailing in front.
	var flung: Dictionary = _merge(stand, {
		"hp": -52.0, "hr": 5.0, "hips": Vector3(1, 112, -26), "torso": Vector3(0.0, 0.60, -0.8), "head": Vector3(0.0, 0.2, -1.0),
		"la": Vector3(0.75, 0.35, -0.55), "lf": Vector3(0.85, 0.3, -0.4), "ra": Vector3(-0.78, 0.3, -0.5), "rf": Vector3(-0.85, 0.25, -0.35),
		"lt": Vector3(0.12, -0.55, 0.83), "ls": Vector3(0.1, -0.85, 0.5), "rt": Vector3(-0.15, -0.5, 0.85), "rs": Vector3(-0.1, -0.9, 0.4),
		"lfoot": Vector3(0.1, -0.3, 0.9), "rfoot": Vector3(-0.1, -0.3, 0.9),
		"blade": Vector3(-0.5, 0.65, -0.55)})
	# The slam: the back takes it, the arms are thrown out and the head snaps back with the body.
	var slammed: Dictionary = _merge(lying, {"hips": Vector3(0, 12, -16), "head": Vector3(0.05, 0.55, -0.85)})
	var rebound: Dictionary = _merge(lying, {"hp": -80.0, "hips": Vector3(0, 19, -17), "torso": Vector3(0.0, 0.2, -0.98), "head": Vector3(0.0, 0.55, -0.8)})
	# Winded on the ground: the chest heaves, the head rolls to one side.
	var winded_a: Dictionary = _merge(lying, {"torso": Vector3(0.0, 0.16, -1.0), "head": Vector3(0.35, 0.3, -0.9)})
	var winded_b: Dictionary = _merge(lying, {"torso": Vector3(0.0, 0.05, -1.0), "head": Vector3(0.45, 0.2, -0.88)})
	# Gathering: the right knee is drawn up, the free left hand reaches for the ground beside the hip, the head comes round.
	var gather: Dictionary = _merge(lying, {
		"hp": -78.0, "hr": 14.0, "hips": Vector3(0, 14, -16), "torso": Vector3(0.12, 0.2, -0.97), "head": Vector3(0.0, 0.55, -0.8),
		"la": Vector3(0.3, -0.3, -0.9), "lf": Vector3(0.7, -0.25, -0.6),
		"rt": Vector3(-0.2, 0.62, 0.75), "rs": Vector3(-0.15, -0.8, 0.55), "rfoot": Vector3(-0.1, 0.1, 0.99),
		"lt": Vector3(0.16, 0.05, 1.0), "ls": Vector3(0.12, -0.1, 1.0)})
	# Brace: rolled onto the left hip, the chest hauled half upright on the planted left arm, the sword hand dragging.
	var brace: Dictionary = _merge(stand, {
		"hp": -52.0, "hy": 14.0, "hr": 12.0, "hips": Vector3(2, 23, -14), "torso": Vector3(0.18, 0.78, -0.6), "head": Vector3(0.0, 0.5, 0.85),
		"la": Vector3(0.22, -0.8, -0.55), "lf": Vector3(0.12, -0.99, -0.12),
		"ra": Vector3(-0.35, -0.7, 0.5), "rf": Vector3(-0.4, -0.5, 0.78),
		"lt": Vector3(0.3, 0.18, 0.93), "ls": Vector3(0.3, -0.2, 0.9), "lfoot": Vector3(0.1, -0.3, 0.9),
		"rt": Vector3(-0.1, 0.55, 0.8), "rs": Vector3(-0.12, -0.55, 0.8), "rfoot": Vector3(-0.1, -0.2, 0.9),
		"blade": Vector3(-0.1, -0.2, 0.97)})
	# Knee under the body: left foot planted, right knee on the ground, chest hunched forward over it, left hand braced on the thigh,
	# the head low. This is the heaviest moment.
	var kneel: Dictionary = _merge(stand, {
		"hp": 18.0, "hy": 6.0, "hr": 2.0, "hips": Vector3(2, 0, 4), "ground": ["RightLeg", 7.0],
		"torso": Vector3(0.0, 0.82, 0.57), "head": Vector3(0.0, 0.35, 0.94),
		"la": Vector3(0.28, -0.82, 0.5), "lf": Vector3(0.12, -0.8, 0.55),
		"ra": Vector3(-0.3, -0.85, 0.35), "rf": Vector3(-0.15, -0.75, 0.65),
		"lt": Vector3(0.12, 0.02, 1.0), "ls": Vector3(0.03, -1.0, -0.12), "lfoot": Vector3(0.0, -0.3, 0.95),
		"rt": Vector3(-0.1, -0.98, 0.1), "rs": Vector3(-0.08, -0.08, -1.0), "rfoot": Vector3(-0.05, -0.6, -0.8),
		"blade": Vector3(-0.1, -0.45, 0.89)})
	# Driving up: the legs straighten under him, the chest still forward, the free hand coming off the knee.
	var rising: Dictionary = _merge(stand, {
		"hp": 7.0, "hips": Vector3(1, 0, 0), "ground": ["LeftFoot", 12.4],
		"torso": Vector3(0.0, 0.93, 0.36), "head": Vector3(0.0, 0.7, 0.7),
		"la": Vector3(0.3, -0.85, 0.4), "lf": Vector3(0.2, -0.6, 0.78),
		"lt": Vector3(0.08, -0.75, 0.66), "ls": Vector3(0.04, -0.98, -0.2),
		"rt": Vector3(-0.1, -0.7, 0.7), "rs": Vector3(-0.1, -0.92, -0.38), "rfoot": Vector3(-0.05, -0.5, 0.86)})
	return [
		[0.0, stand, 1.0],
		[0.07, struck, 0.7],
		[0.17, flung, 1.0],
		[0.30, slammed, 2.2],
		[0.36, rebound, 0.7],
		[0.46, winded_a, 1.0],
		[0.60, winded_b, 1.0],
		[0.75, gather, 1.0],
		[0.88, brace, 0.8],
		[1.05, kneel, 1.0],
		[1.19, rising, 1.5],
		[1.30, stand, 1.4],
	]

# --- pose handling ----------------------------------------------------------------------------------------------------------------
## A pose that is `base` with `changes` on top. Giving new hips without a "ground" cancels the base's ground request.
func _merge(base: Dictionary, changes: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate()
	for k in changes:
		out[k] = changes[k]
	if changes.has("hips") and not changes.has("ground"):
		out.erase("ground")
	if changes.has("torso") or changes.has("head"):
		out.erase("sp")   # the spine was the base's; work it out again from the new torso and head
	return out

func _idle_local(bone: int) -> Quaternion:
	var idx: int = _idle.find_track(NodePath(TRACK + _names[bone]), Animation.TYPE_ROTATION_3D)
	if idx < 0:
		return _sk.get_bone_rest(bone).basis.get_rotation_quaternion()
	return _idle.rotation_track_interpolate(idx, 0.0)

func _idle_hips() -> Vector3:
	return _idle.position_track_interpolate(_idle.find_track(NodePath(TRACK + "Hips"), Animation.TYPE_POSITION_3D), 0.0)

## Global rotations of the idle pose.
func _idle_globals() -> Array[Quaternion]:
	var gr: Array[Quaternion] = []
	for i in _names.size():
		var p: int = _parent[i]
		gr.append(_idle_local(i) if p < 0 else gr[p] * _idle_local(i))
	return gr

func _bone_dir(gr: Array[Quaternion], bone: String) -> Vector3:
	return gr[_sk.find_bone(bone)] * Vector3.UP

## The idle stance as a pose: every direction the way the idle has it, the hips where it has them.
func _stand_pose() -> Dictionary:
	var gr: Array[Quaternion] = _idle_globals()
	_idle_hips_global = gr[0]
	var hand: Quaternion = gr[_sk.find_bone("RightHand")]
	return {
		"hp": 0.0, "hy": 0.0, "hr": 0.0, "hips": _idle_hips(),
		"sp": [_bone_dir(gr, "Spine02"), _bone_dir(gr, "Spine01"), _bone_dir(gr, "Spine")],
		"torso": _bone_dir(gr, "Spine"),
		"neck": _bone_dir(gr, "neck"), "head": _bone_dir(gr, "Head"),
		"la": _bone_dir(gr, "LeftArm"), "lf": _bone_dir(gr, "LeftForeArm"), "ra": _bone_dir(gr, "RightArm"), "rf": _bone_dir(gr, "RightForeArm"),
		"lt": _bone_dir(gr, "LeftUpLeg"), "ls": _bone_dir(gr, "LeftLeg"), "lfoot": _bone_dir(gr, "LeftFoot"),
		"rt": _bone_dir(gr, "RightUpLeg"), "rs": _bone_dir(gr, "RightLeg"), "rfoot": _bone_dir(gr, "RightFoot"),
		"blade": hand * Vector3(0, 0, 1),
	}

func _hips_rotation(pose: Dictionary) -> Quaternion:
	return Quaternion(Vector3.RIGHT, deg_to_rad(float(pose["hp"]))) * Quaternion(Vector3.UP, deg_to_rad(float(pose["hy"]))) \
		* Quaternion(Vector3.BACK, deg_to_rad(float(pose["hr"]))) * _idle_hips_global

## Fills in what a key leaves to be worked out: the three spine bones and the neck (spread from the hips' own axis to the torso and head
## directions), and the hips' height from a "ground" request.
func _resolve(pose: Dictionary) -> Dictionary:
	var out: Dictionary = pose.duplicate()
	if not out.has("sp"):
		var up: Vector3 = _hips_rotation(out) * Vector3.UP
		var torso: Vector3 = (out["torso"] as Vector3).normalized()
		var sp: Array[Vector3] = []
		for f in SPINE_FRACTIONS:
			sp.append(up.slerp(torso, f).normalized())
		out["sp"] = sp
		out["neck"] = torso.slerp((out["head"] as Vector3).normalized(), 0.45).normalized()
	for k in ["la", "lf", "ra", "rf", "lt", "ls", "lfoot", "rt", "rs", "rfoot", "head", "blade", "neck"]:
		out[k] = (out[k] as Vector3).normalized()
	if out.has("ground"):
		var hips: Vector3 = out["hips"]
		hips.y = 0.0
		out["hips"] = hips
		var gp: Array[Vector3] = _fk(out)[1]
		var spec: Array = out["ground"]
		hips.y = float(spec[1]) - gp[_sk.find_bone(String(spec[0]))].y
		out["hips"] = hips
		out.erase("ground")
	return out

## Local rotations for a (resolved) pose.
func _rotations(pose: Dictionary) -> Array[Quaternion]:
	var sp: Array = pose["sp"]
	var aim: Dictionary = {
		"Spine02": sp[0], "Spine01": sp[1], "Spine": sp[2],
		"neck": pose["neck"], "Head": pose["head"], "LeftArm": pose["la"], "LeftForeArm": pose["lf"], "RightArm": pose["ra"],
		"RightForeArm": pose["rf"], "LeftUpLeg": pose["lt"], "LeftLeg": pose["ls"], "LeftFoot": pose["lfoot"],
		"RightUpLeg": pose["rt"], "RightLeg": pose["rs"], "RightFoot": pose["rfoot"]}
	var locals: Array[Quaternion] = []
	var gr: Array[Quaternion] = []
	for i in _names.size():
		var p: int = _parent[i]
		var parent_global: Quaternion = gr[p] if p >= 0 else Quaternion.IDENTITY
		var g: Quaternion = parent_global * _idle_local(i)
		if p < 0:
			g = _hips_rotation(pose)
		elif aim.has(_names[i]):
			g = Quaternion(g * Vector3.UP, aim[_names[i]] as Vector3) * g
		elif _names[i] == "RightHand":
			g = Quaternion(g * Vector3(0, 0, 1), pose["blade"] as Vector3) * g
		locals.append(parent_global.inverse() * g)
		gr.append(g)
	return locals

## [global rotations, global positions] of a pose.
func _fk(pose: Dictionary) -> Array:
	var locals: Array[Quaternion] = _rotations(pose)
	var gr: Array[Quaternion] = []
	var gp: Array[Vector3] = []
	for i in _names.size():
		var p: int = _parent[i]
		if p < 0:
			gr.append(locals[i])
			gp.append(pose["hips"])
		else:
			gr.append(gr[p] * locals[i])
			gp.append(gp[p] + gr[p] * _rest_pos[i])
	return [gr, gp]

func _blend(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out: Dictionary = {}
	for k in a:
		var av: Variant = a[k]
		if av is Vector3:
			out[k] = (av as Vector3).lerp(b[k], u) if k == "hips" else (av as Vector3).slerp(b[k], u)
		elif av is Array:
			var arr: Array[Vector3] = []
			for i in (av as Array).size():
				arr.append(((av as Array)[i] as Vector3).slerp((b[k] as Array)[i], u))
			out[k] = arr
		else:
			out[k] = lerpf(float(av), float(b[k]), u)
	return out

func _eased(u: float, ease_power: float) -> float:
	if ease_power == 1.0:
		return u * u * (3.0 - 2.0 * u)
	if ease_power > 1.0:
		return pow(u, ease_power)
	return 1.0 - pow(1.0 - u, 1.0 / ease_power)

func _author(keys: Array) -> Animation:
	var resolved: Array = []
	for key in keys:
		var pose: Dictionary = _resolve(key[1])
		resolved.append([float(key[0]), pose, float(key[2])])
		var gp: Array[Vector3] = _fk(pose)[1]
		print("t=%.2f hips=%s  Lhand y=%.1f Rhand y=%.1f Lfoot y=%.1f Rfoot y=%.1f Rknee y=%.1f Lknee y=%.1f head y=%.1f" % [float(key[0]), pose["hips"],
			gp[_sk.find_bone("LeftHand")].y, gp[_sk.find_bone("RightHand")].y, gp[_sk.find_bone("LeftFoot")].y,
			gp[_sk.find_bone("RightFoot")].y, gp[_sk.find_bone("RightLeg")].y, gp[_sk.find_bone("LeftLeg")].y,
			gp[_sk.find_bone("head_end")].y])
	var out := Animation.new()
	out.length = LENGTH
	out.loop_mode = Animation.LOOP_NONE
	var rot_tracks: Array[int] = []
	for i in _names.size():
		var tr: int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(TRACK + _names[i]))
		rot_tracks.append(tr)
	var hips_track: int = out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_track, NodePath(TRACK + "Hips"))
	var frames: int = int(ceil(LENGTH * FPS))
	for f in frames + 1:
		var t: float = minf(float(f) / FPS, LENGTH)
		var pose: Dictionary = resolved[0][1]
		for i in range(1, resolved.size()):
			if t <= float(resolved[i][0]):
				var t0: float = float(resolved[i - 1][0])
				var u: float = clampf((t - t0) / (float(resolved[i][0]) - t0), 0.0, 1.0)
				pose = _blend(resolved[i - 1][1], resolved[i][1], _eased(u, float(resolved[i][2])))
				break
			pose = resolved[i][1]
		var locals: Array[Quaternion] = _rotations(pose)
		for i in _names.size():
			out.rotation_track_insert_key(rot_tracks[i], t, locals[i])
		out.position_track_insert_key(hips_track, t, pose["hips"])
	return out
