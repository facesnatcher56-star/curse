extends SceneTree
## Authors the weighty basic-attack clips (atk_*) on the Knight's own rig by layering body motion on the Meshy swings.
##   godot --headless --path . --script tools/author_attack_anims.gd
##
## The Meshy swings move the arms well but the body barely joins in, which is what makes them look light: the hips stay put, the
## chest does not turn, the knees do not take the weight. This keeps each swing's arm and blade path and adds, per frame, in the
## skeleton's own frame (X = the hero's left, Y = up, Z = forward):
##   - hips and spine twist: coil away from the blow, drive through it hips first, then the chest, then carry on past it;
##   - a lean back while gathering and into the blow as it lands;
##   - the hips sinking onto bent knees at the strike (the knees are solved so the feet stay where they were), then rising;
##   - the head staying on the target while the body turns.
## Each clip is cut out of its source (start..end), so the new clip starts at 0 with the strike at STRIKE[...] seconds.
## Rig units are centimetres. Run it again after changing a number; it replaces the atk_* clips in anims.res and nothing else.

const DIR := "res://assets/models/knight2"
const TRACK := "Armature/Skeleton3D:"
const FPS := 30.0
const HIPS_X := 0.5
const HIPS_Z := -4.0

## name: [source clip, start, strike, end, kind]. `kind` picks the body motion below.
## The same cuts for the two-handed sword (atk2_*): the arms are not the Meshy arms (one hand out at arm's length, the other hanging)
## but solved so both hands stay on the grip. HANDS gives, per phase, where the grip sits in front of the chest (x = the hero's left,
## y = up, z = forward, cm, from the middle of the shoulder line, turning with the chest) and the way the blade points.
const CLIPS2 := {
	"atk2_slash_r": ["slash_r", 0.35, 0.73, 1.1, "slash", 1.0, "diag_down"],
	"atk2_slash_l": ["slash_l", 0.7, 1.37, 1.85, "slash", -1.0, "rising"],
	"atk2_slash": ["slash", 0.5, 1.07, 1.45, "slash", 1.0, "level"],
	"atk2_thrust": ["thrust", 1.0, 1.57, 2.1, "thrust", 1.0, "thrust"],
	"atk2_finisher": ["combo_end", 0.6, 1.37, 2.2, "finisher", 1.0, "overhead"],
}
const PHASES: Array[float] = [0.0, 0.55, 1.0, 1.35, 2.0]
const GUARD := [Vector3(-8, -20, 28), Vector3(-0.15, 0.85, 0.5)]
## name: [[grip position, blade direction] at each of PHASES].
const HANDS := {
	"diag_down": [GUARD, [Vector3(-17, 12, 6), Vector3(-0.35, 0.5, -0.8)], [Vector3(0, -22, 32), Vector3(0.75, -0.15, 0.65)],
		[Vector3(16, -30, 24), Vector3(0.95, -0.2, -0.15)], GUARD],
	"level": [GUARD, [Vector3(-20, -6, 10), Vector3(-0.6, 0.15, -0.78)], [Vector3(2, -18, 34), Vector3(0.8, 0.0, 0.6)],
		[Vector3(18, -20, 22), Vector3(0.97, 0.0, -0.2)], GUARD],
	"rising": [GUARD, [Vector3(14, -32, 18), Vector3(0.8, -0.4, -0.4)], [Vector3(-2, -14, 34), Vector3(-0.7, 0.45, 0.55)],
		[Vector3(-18, 4, 20), Vector3(-0.8, 0.6, -0.1)], GUARD],
	"thrust": [GUARD, [Vector3(-10, -16, 6), Vector3(-0.05, 0.25, 0.97)], [Vector3(-2, -16, 36), Vector3(0, 0.1, 1)],
		[Vector3(0, -18, 34), Vector3(0, 0.1, 1)], GUARD],
	"overhead": [GUARD, [Vector3(-4, 38, -4), Vector3(0.0, 0.75, -0.65)], [Vector3(0, -14, 34), Vector3(0, -0.55, 0.83)],
		[Vector3(0, -32, 30), Vector3(0, -0.85, 0.5)], GUARD],
}
const BLADE_IN_HAND := Vector3(0, 0, 1)         # the blade's direction in the hand bone (Player.GRIPS[3])
const GRIP_IN_HAND := Vector3(-0.8, 15.0, 0.5)   # the fist's middle in the hand bone (Player.HAND_GRIP_POINT)
const HAND_SPACING := 15.0                       # between the hands on the grip
const ELBOW_HINT_R := Vector3(-0.6, -0.8, -0.2)
const ELBOW_HINT_L := Vector3(0.6, -0.8, -0.2)

const CLIPS := {
	"atk_slash_r": ["slash_r", 0.35, 0.73, 1.1, "slash"],
	"atk_thrust": ["thrust", 1.0, 1.57, 2.1, "thrust"],
	"atk_slash_l": ["slash_l", 0.7, 1.37, 1.85, "slash"],
	"atk_slash": ["slash", 0.5, 1.07, 1.45, "slash"],
	"atk_finisher": ["combo_end", 0.6, 1.37, 2.2, "finisher"],
}

## Per kind, key by key over the phase (0 = start, 1 = the strike, 2 = the end): [phase, value]. Yaw values are multiplied by the
## swing's side (+1 when the blade travels toward the hero's left, -1 toward the right). Degrees; drop in cm.
const MOTION := {
	"slash": {
		"hips_yaw": [[0.0, 0.0], [0.55, -16.0], [1.0, 2.0], [1.35, 15.0], [2.0, 0.0]],
		"spine_yaw": [[0.0, 0.0], [0.55, -22.0], [1.0, 6.0], [1.35, 26.0], [2.0, 0.0]],
		"spine_lean": [[0.0, 0.0], [0.55, -10.0], [1.0, 15.0], [1.35, 11.0], [2.0, 0.0]],
		"drop": [[0.0, 0.0], [0.4, 1.5], [0.8, -2.0], [1.0, -6.5], [1.4, -7.5], [2.0, 0.0]],
		"hips_roll": [[0.0, 0.0], [0.55, 4.0], [1.0, -3.0], [1.35, -5.0], [2.0, 0.0]],
	},
	"thrust": {
		"hips_yaw": [[0.0, 0.0], [0.55, -10.0], [1.0, 3.0], [1.35, 6.0], [2.0, 0.0]],
		"spine_yaw": [[0.0, 0.0], [0.55, -14.0], [1.0, 4.0], [1.35, 10.0], [2.0, 0.0]],
		"spine_lean": [[0.0, 0.0], [0.55, -14.0], [1.0, 24.0], [1.35, 18.0], [2.0, 0.0]],
		"drop": [[0.0, 0.0], [0.4, 1.0], [0.8, -3.0], [1.0, -9.0], [1.4, -9.5], [2.0, 0.0]],
		"hips_roll": [[0.0, 0.0], [1.0, 0.0], [2.0, 0.0]],
	},
	"finisher": {
		"hips_yaw": [[0.0, 0.0], [0.6, -20.0], [1.0, 4.0], [1.3, 20.0], [2.0, 0.0]],
		"spine_yaw": [[0.0, 0.0], [0.6, -28.0], [1.0, 8.0], [1.3, 32.0], [2.0, 0.0]],
		"spine_lean": [[0.0, 0.0], [0.6, -18.0], [1.0, 26.0], [1.3, 20.0], [2.0, 0.0]],
		"drop": [[0.0, 0.0], [0.4, 3.0], [0.85, -3.0], [1.0, -9.0], [1.35, -11.0], [2.0, 0.0]],
		"hips_roll": [[0.0, 0.0], [0.6, 5.0], [1.0, -4.0], [1.3, -6.0], [2.0, 0.0]],
	},
}
## How the spine's twist and lean are shared out over Spine02 (low), Spine01 and Spine (high).
const SPINE_SHARE := {"Spine02": 0.25, "Spine01": 0.35, "Spine": 0.4}
const THIGH := 40.0
const SHIN := 38.0

var _sk: Skeleton3D
var _names: Array[String] = []
var _rest_pos: Array[Vector3] = []
var _parent: Array[int] = []

func _init() -> void:
	var rigged: Node = (load(DIR + "/rigged.glb") as PackedScene).instantiate()
	_sk = rigged.find_children("*", "Skeleton3D", true, false)[0]
	for i in _sk.get_bone_count():
		_names.append(_sk.get_bone_name(i))
		_rest_pos.append(_sk.get_bone_rest(i).origin)
		_parent.append(_sk.get_bone_parent(i))
	var lib: AnimationLibrary = (load(DIR + "/anims.res") as AnimationLibrary).duplicate(true)
	for name in CLIPS:
		var spec: Array = CLIPS[name]
		var anim: Animation = _author(lib.get_animation(spec[0]), float(spec[1]), float(spec[2]), float(spec[3]), String(spec[4]))
		if lib.has_animation(name):
			lib.remove_animation(name)
		lib.add_animation(name, anim)
		print(name, ": ", snappedf(anim.length, 0.01), " s, strike at ", snappedf(float(spec[2]) - float(spec[1]), 0.01))
	for name in CLIPS2:
		var spec2: Array = CLIPS2[name]
		var anim2: Animation = _author(lib.get_animation(spec2[0]), float(spec2[1]), float(spec2[2]), float(spec2[3]), String(spec2[4]), float(spec2[5]), String(spec2[6]))
		if lib.has_animation(name):
			lib.remove_animation(name)
		lib.add_animation(name, anim2)
		print(name, ": ", snappedf(anim2.length, 0.01), " s, strike at ", snappedf(float(spec2[2]) - float(spec2[1]), 0.01))
	for name in THROW_CLIPS:
		if lib.has_animation(name):
			lib.remove_animation(name)
		lib.add_animation(name, _author_throw(lib.get_animation("idle_alert"), name))
		print(name, ": ", snappedf(lib.get_animation(name).length, 0.01), " s")
	if lib.has_animation("idle_rest"):
		lib.remove_animation("idle_rest")
	lib.add_animation("idle_rest", _author_rest(lib.get_animation("idle_alert")))
	print("idle_rest: ", snappedf(lib.get_animation("idle_rest").length, 0.01), " s")
	print("saved -> ", ResourceSaver.save(lib, DIR + "/anims.res"))
	quit()

## One bone's local rotation in a source clip at time t (rest rotation when the clip has no track for it).
func _local_rot(src: Animation, bone: int, t: float) -> Quaternion:
	var idx: int = src.find_track(NodePath(TRACK + _names[bone]), Animation.TYPE_ROTATION_3D)
	if idx < 0:
		return _sk.get_bone_rest(bone).basis.get_rotation_quaternion()
	return src.rotation_track_interpolate(idx, t)

func _hips_pos(src: Animation, t: float) -> Vector3:
	var idx: int = src.find_track(NodePath(TRACK + "Hips"), Animation.TYPE_POSITION_3D)
	return src.position_track_interpolate(idx, t) if idx >= 0 else _rest_pos[0]

## Global rotations and positions of every bone for the given local rotations.
func _forward(rots: Array[Quaternion], hips: Vector3) -> Array:
	var gr: Array[Quaternion] = []
	var gp: Array[Vector3] = []
	for i in _names.size():
		var p: int = _parent[i]
		if p < 0:
			gr.append(rots[i])
			gp.append(hips)
		else:
			gr.append(gr[p] * rots[i])
			gp.append(gp[p] + gr[p] * _rest_pos[i])
	return [gr, gp]

## Which way the blade travels around the hero in the blow: +1 toward his left, -1 toward his right, 0 when it goes straight ahead.
func _swing_side(src: Animation, t_strike: float) -> float:
	var angles: Array[float] = []
	for t in [t_strike - 0.18, t_strike + 0.04]:
		var rots: Array[Quaternion] = []
		for i in _names.size():
			rots.append(_local_rot(src, i, t))
		var fk: Array = _forward(rots, _hips_pos(src, t))
		var hand: Vector3 = (fk[1] as Array)[_sk.find_bone("RightHand")] - (fk[1] as Array)[0]
		angles.append(atan2(hand.x, hand.z))
	var d: float = angles[1] - angles[0]
	return 0.0 if absf(d) < 0.15 else signf(d)

func _curve(keys: Array, phase: float) -> float:
	if phase <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if phase <= float(b[0]):
			var u: float = (phase - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), u * u * (3.0 - 2.0 * u))
	return float(keys[keys.size() - 1][1])

## Thigh and knee bends that lower the hips by `drop` cm with the feet staying put (two links, foot under the same spot).
func _leg_bend(drop: float) -> Vector2:
	var lo: float = 0.0
	var hi: float = 80.0
	for _i in 30:
		var alpha: float = deg_to_rad((lo + hi) * 0.5)
		var beta: float = asin(clampf(THIGH * sin(alpha) / SHIN, -1.0, 1.0))   # the shin's lean the other way
		var lowered: float = THIGH + SHIN - THIGH * cos(alpha) - SHIN * cos(beta)
		if lowered < drop:
			lo = (lo + hi) * 0.5
		else:
			hi = (lo + hi) * 0.5
	var a: float = deg_to_rad((lo + hi) * 0.5)
	return Vector2(a, asin(clampf(THIGH * sin(a) / SHIN, -1.0, 1.0)))

func _author(src: Animation, t0: float, t_strike: float, t1: float, kind: String, forced_side: float = 0.0, hands: String = "") -> Animation:
	var motion: Dictionary = MOTION[kind]
	var side: float = forced_side if forced_side != 0.0 else _swing_side(src, t_strike)
	print("  ", kind, " swing side ", side)
	var out := Animation.new()
	out.length = t1 - t0
	out.loop_mode = Animation.LOOP_NONE
	var rot_tracks: Array[int] = []
	for i in _names.size():
		var tr: int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(TRACK + _names[i]))
		rot_tracks.append(tr)
	var hips_track: int = out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_track, NodePath(TRACK + "Hips"))
	var frames: int = int(ceil((t1 - t0) * FPS))
	for f in frames + 1:
		var t: float = minf(t0 + float(f) / FPS, t1)
		var phase: float = (t - t0) / (t_strike - t0) if t <= t_strike else 1.0 + (t - t_strike) / (t1 - t_strike)
		var rots: Array[Quaternion] = []
		for i in _names.size():
			rots.append(_local_rot(src, i, t))
		var hips: Vector3 = _hips_pos(src, t)
		var yaw_side: float = side if side != 0.0 else 1.0
		# The body's motion in the skeleton's frame.
		var hips_yaw: float = deg_to_rad(_curve(motion["hips_yaw"], phase)) * yaw_side
		var spine_yaw: float = deg_to_rad(_curve(motion["spine_yaw"], phase)) * yaw_side
		var lean: float = deg_to_rad(_curve(motion["spine_lean"], phase))
		var roll: float = deg_to_rad(_curve(motion["hips_roll"], phase)) * yaw_side
		var drop: float = _curve(motion["drop"], phase)
		var bend: Vector2 = _leg_bend(maxf(-drop, 0.0)) if drop < 0.0 else Vector2.ZERO
		var delta: Dictionary = {}   # bone name -> rotation in the skeleton's frame, applied after its parent's
		delta["Hips"] = Quaternion(Vector3.UP, hips_yaw) * Quaternion(Vector3.BACK, roll)
		for bone in SPINE_SHARE:
			var share: float = SPINE_SHARE[bone]
			delta[bone] = Quaternion(Vector3.UP, spine_yaw * share) * Quaternion(Vector3.RIGHT, lean * share)
		# The head keeps looking where the blow goes while the chest turns away from it.
		delta["Head"] = Quaternion(Vector3.UP, -spine_yaw * 0.55) * Quaternion(Vector3.RIGHT, -lean * 0.5)
		# The legs undo what the hips did and sink onto bent knees; the feet undo the bend.
		for side_name in ["Left", "Right"]:
			delta[side_name + "UpLeg"] = (delta["Hips"] as Quaternion).inverse() * Quaternion(Vector3.RIGHT, -bend.x)
			delta[side_name + "Leg"] = Quaternion(Vector3.RIGHT, bend.x + bend.y)
			delta[side_name + "Foot"] = Quaternion(Vector3.RIGHT, -bend.y)
		var gr: Array[Quaternion] = []
		var out_rots: Array[Quaternion] = []
		for i in _names.size():
			var q: Quaternion = rots[i]
			var p: int = _parent[i]
			var gp: Quaternion = gr[p] if p >= 0 else Quaternion.IDENTITY
			if delta.has(_names[i]):
				q = gp.inverse() * (delta[_names[i]] as Quaternion) * gp * q
			out_rots.append(q)
			gr.append(gp * q)
		if hands != "":
			_two_hand_arms(out_rots, rots, hips + Vector3(0, drop, 0), HANDS[hands], phase)
		for i in _names.size():
			out.rotation_track_insert_key(rot_tracks[i], t - t0, out_rots[i])
		out.position_track_insert_key(hips_track, t - t0, Vector3(HIPS_X, hips.y + drop, HIPS_Z))
	return out

## Where the grip and the blade are at this phase.
func _grip_at(keys: Array, phase: float) -> Array:
	var idx: int = 0
	while idx < PHASES.size() - 2 and phase > PHASES[idx + 1]:
		idx += 1
	var u: float = clampf((phase - PHASES[idx]) / (PHASES[idx + 1] - PHASES[idx]), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var a: Array = keys[idx]
	var b: Array = keys[idx + 1]
	return [(a[0] as Vector3).lerp(b[0], u), ((a[1] as Vector3).lerp(b[1], u)).normalized()]

## Replaces both arms so the hands stay on the sword's grip. `rots` are the source's local rotations, `out_rots` the body's already
## changed ones; the arms start from the source's own twist and only turn as far as they must (so no candy-wrapped sleeves).
func _two_hand_arms(out_rots: Array[Quaternion], rots: Array[Quaternion], hips: Vector3, keys: Array, phase: float) -> void:
	var fk: Array = _forward(out_rots, hips)
	var gr: Array = fk[0]
	var gp: Array = fk[1]
	var left_arm: int = _sk.find_bone("LeftArm")
	var right_arm: int = _sk.find_bone("RightArm")
	# The chest's own turn (twist and lean) carries the grip: express it in the chest's frame, from the middle of the shoulders.
	var chest: Quaternion = _chest_frame(gr)
	var centre: Vector3 = ((gp[left_arm] as Vector3) + (gp[right_arm] as Vector3)) * 0.5
	var grip: Array = _grip_at(keys, phase)
	var grip_pos: Vector3 = centre + chest * (grip[0] as Vector3)
	var blade: Vector3 = chest * (grip[1] as Vector3)
	var left_point: Vector3 = grip_pos - blade * HAND_SPACING
	_solve_arm("Right", out_rots, rots, gr, gp, grip_pos, blade, ELBOW_HINT_R, true)
	_solve_arm("Left", out_rots, rots, gr, gp, left_point, blade, ELBOW_HINT_L, false)

## The chest's turn since the rest pose: the Spine bone's global rotation without the rest orientation (the rest is identity when the
## bones carry their own rest rotation in the animation, which these clips do not change).
func _chest_frame(gr: Array) -> Quaternion:
	var spine: int = _sk.find_bone("Spine")
	var rest_global: Quaternion = Quaternion.IDENTITY
	var chain: Array[int] = []
	var b: int = spine
	while b >= 0:
		chain.push_front(b)
		b = _parent[b]
	for i in chain:
		rest_global = rest_global * _sk.get_bone_rest(i).basis.get_rotation_quaternion()
	return (gr[spine] as Quaternion) * rest_global.inverse()

func _solve_arm(prefix: String, out_rots: Array[Quaternion], src_rots: Array[Quaternion], gr: Array, gp: Array, grip_point: Vector3,
		blade: Vector3, hint: Vector3, is_sword_hand: bool, free_hand: bool = false) -> void:
	var arm: int = _sk.find_bone(prefix + "Arm")
	var fore: int = _sk.find_bone(prefix + "ForeArm")
	var hand: int = _sk.find_bone(prefix + "Hand")
	var shoulder_rot: Quaternion = gr[_parent[arm]]
	var a: float = _rest_pos[fore].length()
	var b: float = _rest_pos[hand].length()
	var s: Vector3 = gp[arm]
	var hand_rot: Quaternion = shoulder_rot * src_rots[arm] * src_rots[fore] * src_rots[hand]
	var palm: Vector3 = GRIP_IN_HAND if is_sword_hand else Vector3(-GRIP_IN_HAND.x, GRIP_IN_HAND.y, GRIP_IN_HAND.z)   # the left hand is the right one mirrored
	var q_arm: Quaternion = src_rots[arm]
	var q_fore: Quaternion = src_rots[fore]
	var q_hand: Quaternion = src_rots[hand]
	for _iter in 3:
		var wrist: Vector3 = grip_point if free_hand else grip_point - hand_rot * palm
		var d: float = clampf(s.distance_to(wrist), absf(a - b) + 0.5, (a + b) * 0.998)
		var dir: Vector3 = (wrist - s).normalized()
		var x: float = (a * a - b * b + d * d) / (2.0 * d)
		var h: float = sqrt(maxf(a * a - x * x, 0.0))
		var perp: Vector3 = hint - dir * hint.dot(dir)
		perp = perp.normalized() if perp.length() > 0.001 else Vector3.DOWN
		var elbow: Vector3 = s + dir * x + perp * h
		var wrist_at: Vector3 = s + dir * d
		var r0: Quaternion = shoulder_rot * src_rots[arm]
		var r_arm: Quaternion = Quaternion(r0 * Vector3.UP, (elbow - s).normalized()) * r0
		var r1: Quaternion = r_arm * src_rots[fore]
		var r_fore: Quaternion = Quaternion(r1 * Vector3.UP, (wrist_at - elbow).normalized()) * r1
		var r2: Quaternion = r_fore * src_rots[hand]
		var r_hand: Quaternion = r2 if free_hand else Quaternion(r2 * BLADE_IN_HAND, blade) * r2   # both fists close round the same grip, thumbs toward the blade
		q_arm = shoulder_rot.inverse() * r_arm
		q_fore = r_arm.inverse() * r_fore
		q_hand = r_fore.inverse() * r_hand
		hand_rot = r_hand
	out_rots[arm] = q_arm
	out_rots[fore] = q_fore
	out_rots[hand] = q_hand

## The sword resting on the shoulder: the idle's own breathing and weight, with the right arm brought up so the fist sits in front of the
## shoulder and the blade lies back over it, and the body a little easier than the alert stance. Loops with the idle.
const REST_GRIP := Vector3(-27.0, -14.0, 26.0)       # out in front of the right shoulder, the forearm held forward
const REST_BLADE := Vector3(0.17, 0.66, -0.73)     # the blade slopes up and back and lies across the top of the shoulder
func _author_rest(src: Animation) -> Animation:
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR
	var rot_tracks: Array[int] = []
	for i in _names.size():
		var tr: int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(TRACK + _names[i]))
		rot_tracks.append(tr)
	var hips_track: int = out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_track, NodePath(TRACK + "Hips"))
	var frames: int = int(ceil(src.length * FPS))
	for f in frames + 1:
		var t: float = minf(float(f) / FPS, src.length)
		var breath: float = sin(TAU * t / src.length)
		var rots: Array[Quaternion] = []
		for i in _names.size():
			rots.append(_local_rot(src, i, t))
		var hips: Vector3 = _hips_pos(src, t)
		var out_rots: Array[Quaternion] = rots.duplicate()
		# easier than the alert stance: the chest a little back and turned off the line, the head level
		var lean: float = deg_to_rad(-3.0)
		var yaw: float = deg_to_rad(-5.0)
		var gr: Array[Quaternion] = []
		for i in _names.size():
			var q: Quaternion = rots[i]
			var p: int = _parent[i]
			var gp: Quaternion = gr[p] if p >= 0 else Quaternion.IDENTITY
			if SPINE_SHARE.has(_names[i]):
				var delta: Quaternion = Quaternion(Vector3.UP, yaw * float(SPINE_SHARE[_names[i]])) * Quaternion(Vector3.RIGHT, lean * float(SPINE_SHARE[_names[i]]))
				q = gp.inverse() * delta * gp * q
			elif _names[i] == "Head":
				q = gp.inverse() * (Quaternion(Vector3.UP, -yaw * 0.7) * Quaternion(Vector3.RIGHT, -lean * 0.8)) * gp * q
			out_rots[i] = q
			gr.append(gp * q)
		var fk: Array = _forward(out_rots, hips)
		var left_arm: int = _sk.find_bone("LeftArm")
		var right_arm: int = _sk.find_bone("RightArm")
		var centre: Vector3 = (((fk[1] as Array)[left_arm] as Vector3) + ((fk[1] as Array)[right_arm] as Vector3)) * 0.5
		var chest: Quaternion = _chest_frame(fk[0])
		var grip_pos: Vector3 = centre + chest * (REST_GRIP + Vector3(0.0, 0.35 * breath, 0.0))
		_solve_arm("Right", out_rots, rots, fk[0], fk[1], grip_pos, chest * REST_BLADE, ELBOW_HINT_R, true)
		for i in _names.size():
			out.rotation_track_insert_key(rot_tracks[i], t, out_rots[i])
		out.position_track_insert_key(hips_track, t, Vector3(HIPS_X, hips.y, HIPS_Z))
	return out

# --- Weapon Throw: the wind-up (scrubbed by the charge), the release and the catch ----------------------------------------------------
## Poses are in the chest frame (x = his left, y = up, z = forward, cm). `hy`/`sy` hips and chest twist (degrees, + = toward his left),
## `lean` forward (+) or back (-), `roll` hips tilt, `drop` hips sink in cm, `grip`/`blade` where the right fist is and where the sword
## points, `left`/`lw` where the free left hand goes and how much it goes there (0 leaves it as the idle has it).
const THROW_CLIPS := ["wthrow", "wthrow_release", "wthrow_catch"]
const GUARD_POSE := {"hy": 0.0, "sy": 0.0, "lean": 0.0, "roll": 0.0, "drop": 0.0, "grip": Vector3(-8, -20, 28), "blade": Vector3(-0.15, 0.85, 0.5),
	"left": Vector3(14, -6, 30), "lw": 0.0}
## The fullest wind-up: planted wide and low, the chest turned right away from the target and leaning back, the sword drawn far back behind
## the right shoulder with the arm cocked, the left hand out in front for balance.
const WINDUP_POSE := {"hy": -26.0, "sy": -40.0, "lean": -16.0, "roll": 6.0, "drop": -10.0, "grip": Vector3(-24, 20, -26), "blade": Vector3(-0.1, 0.35, -0.93),
	"left": Vector3(16, -4, 38), "lw": 1.0}
## The release: the whole body thrown forward through the throw, the arm out and high, the left hand dragged back.
const RELEASE_POSE := {"hy": 10.0, "sy": 26.0, "lean": 22.0, "roll": -4.0, "drop": -13.0, "grip": Vector3(-6, 16, 38), "blade": Vector3(0.05, 0.25, 0.97),
	"left": Vector3(24, -4, -8), "lw": 1.0}
const FOLLOW_POSE := {"hy": 18.0, "sy": 38.0, "lean": 27.0, "roll": -6.0, "drop": -8.0, "grip": Vector3(14, -14, 36), "blade": Vector3(0.6, -0.4, 0.7),
	"left": Vector3(26, -2, -12), "lw": 1.0}
const REACH_POSE := {"hy": 4.0, "sy": 8.0, "lean": 6.0, "roll": 0.0, "drop": -4.0, "grip": Vector3(-14, 6, 46), "blade": Vector3(0.0, 0.9, 0.4),
	"left": Vector3(14, -6, 30), "lw": 0.0}
const CATCH_POSE := {"hy": -2.0, "sy": -4.0, "lean": -10.0, "roll": 0.0, "drop": -6.0, "grip": Vector3(-8, -4, 34), "blade": Vector3(0.0, 0.8, 0.6),
	"left": Vector3(14, -6, 30), "lw": 0.0}
const RECOIL_POSE := {"hy": -4.0, "sy": -6.0, "lean": -18.0, "roll": 0.0, "drop": -8.0, "grip": Vector3(-8, -10, 30), "blade": Vector3(0.0, 0.85, 0.5),
	"left": Vector3(14, -6, 30), "lw": 0.0}

func _lerp_pose(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out: Dictionary = {}
	for key in a:
		if a[key] is Vector3:
			out[key] = (a[key] as Vector3).lerp(b[key], u)
		else:
			out[key] = lerpf(float(a[key]), float(b[key]), u)
	return out

## Eases between keyframed poses: keys = [[time, pose], ...].
func _pose_at(keys: Array, t: float) -> Dictionary:
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var u: float = (t - float(keys[i - 1][0])) / (float(keys[i][0]) - float(keys[i - 1][0]))
			return _lerp_pose(keys[i - 1][1], keys[i][1], u * u * (3.0 - 2.0 * u))
	return keys[keys.size() - 1][1]

func _author_throw(idle: Animation, clip: String) -> Animation:
	var length: float = 1.0
	var keys: Array = []
	match clip:
		"wthrow":
			length = 1.0   # time = the charge: 0 the guard, 1 the fullest wind-up
		"wthrow_release":
			length = 0.95
			keys = [[0.0, WINDUP_POSE], [0.2, RELEASE_POSE], [0.5, FOLLOW_POSE], [0.95, GUARD_POSE]]
		"wthrow_catch":
			length = 0.8   # the catch frame is at 0.64 of it (WeaponThrowSkill plays it at the speed that puts the weapon in his hand then)
			keys = [[0.0, GUARD_POSE], [0.3, REACH_POSE], [0.51, CATCH_POSE], [0.62, RECOIL_POSE], [0.8, GUARD_POSE]]
	var out := Animation.new()
	out.length = length
	out.loop_mode = Animation.LOOP_NONE
	var rot_tracks: Array[int] = []
	for i in _names.size():
		var tr: int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(TRACK + _names[i]))
		rot_tracks.append(tr)
	var hips_track: int = out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_track, NodePath(TRACK + "Hips"))
	var frames: int = int(ceil(length * FPS))
	for f in frames + 1:
		var t: float = minf(float(f) / FPS, length)
		var pose: Dictionary
		if clip == "wthrow":
			pose = _lerp_pose(GUARD_POSE, WINDUP_POSE, pow(t, 0.85))
		else:
			pose = _pose_at(keys, t)
		var rots: Array[Quaternion] = []
		for i in _names.size():
			rots.append(_local_rot(idle, i, 1.0))   # the idle held still: the throw's own motion is the point
		var hips: Vector3 = _hips_pos(idle, 1.0)
		var out_rots: Array[Quaternion] = _body_for_pose(rots, pose)
		hips.y += float(pose["drop"])
		_arms_for_pose(out_rots, rots, hips, pose)
		for i in _names.size():
			out.rotation_track_insert_key(rot_tracks[i], t, out_rots[i])
		out.position_track_insert_key(hips_track, t, Vector3(HIPS_X, hips.y, HIPS_Z))
	return out

## The body of a pose: hips and chest twist, lean, the head holding the target, the legs sinking onto bent knees with the feet kept put.
func _body_for_pose(rots: Array[Quaternion], pose: Dictionary) -> Array[Quaternion]:
	var hips_yaw: float = deg_to_rad(float(pose["hy"]))
	var spine_yaw: float = deg_to_rad(float(pose["sy"]))
	var lean: float = deg_to_rad(float(pose["lean"]))
	var roll: float = deg_to_rad(float(pose["roll"]))
	var drop: float = float(pose["drop"])
	var bend: Vector2 = _leg_bend(-drop) if drop < 0.0 else Vector2.ZERO
	var delta: Dictionary = {}
	delta["Hips"] = Quaternion(Vector3.UP, hips_yaw) * Quaternion(Vector3.BACK, roll)
	for bone in SPINE_SHARE:
		var share: float = SPINE_SHARE[bone]
		delta[bone] = Quaternion(Vector3.UP, spine_yaw * share) * Quaternion(Vector3.RIGHT, lean * share)
	delta["Head"] = Quaternion(Vector3.UP, -(hips_yaw + spine_yaw) * 0.45) * Quaternion(Vector3.RIGHT, -lean * 0.4)
	for side_name in ["Left", "Right"]:
		delta[side_name + "UpLeg"] = (delta["Hips"] as Quaternion).inverse() * Quaternion(Vector3.RIGHT, -bend.x)
		delta[side_name + "Leg"] = Quaternion(Vector3.RIGHT, bend.x + bend.y)
		delta[side_name + "Foot"] = Quaternion(Vector3.RIGHT, -bend.y)
	var gr: Array[Quaternion] = []
	var out_rots: Array[Quaternion] = []
	for i in _names.size():
		var q: Quaternion = rots[i]
		var parent: int = _parent[i]
		var gp: Quaternion = gr[parent] if parent >= 0 else Quaternion.IDENTITY
		if delta.has(_names[i]):
			q = gp.inverse() * (delta[_names[i]] as Quaternion) * gp * q
		out_rots.append(q)
		gr.append(gp * q)
	return out_rots

## Both arms of a pose: the right fist at its grip, the left hand where the pose puts it (blended in by `lw`).
func _arms_for_pose(out_rots: Array[Quaternion], rots: Array[Quaternion], hips: Vector3, pose: Dictionary) -> void:
	var fk: Array = _forward(out_rots, hips)
	var gr: Array = fk[0]
	var gp: Array = fk[1]
	var left_arm: int = _sk.find_bone("LeftArm")
	var right_arm: int = _sk.find_bone("RightArm")
	var chest: Quaternion = _chest_frame(gr)
	var centre: Vector3 = ((gp[left_arm] as Vector3) + (gp[right_arm] as Vector3)) * 0.5
	var before: Array[Quaternion] = out_rots.duplicate()
	var blade: Vector3 = chest * (pose["blade"] as Vector3).normalized()
	_solve_arm("Right", out_rots, rots, gr, gp, centre + chest * (pose["grip"] as Vector3), blade, ELBOW_HINT_R, true)
	var lw: float = float(pose["lw"])
	if lw > 0.001:
		var solved: Array[Quaternion] = out_rots.duplicate()
		_solve_arm("Left", solved, rots, gr, gp, centre + chest * (pose["left"] as Vector3), blade, ELBOW_HINT_L, false, true)
		for bone in ["LeftArm", "LeftForeArm", "LeftHand"]:
			var idx: int = _sk.find_bone(bone)
			out_rots[idx] = before[idx].slerp(solved[idx], lw)
