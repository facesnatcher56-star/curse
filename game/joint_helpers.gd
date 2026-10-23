class_name JointHelpers
extends SkeletonModifier3D
## Drives a hero rig's twist and joint-helper bones (tools/art/hero/joint_quality.py) after every animation and procedural pose,
## so every clip, borrowed or keyed, bends the skin round instead of folding it into points:
##   - forearm twist bones take the hand's roll against the forearm (the skin turns along the forearm, as the radius does);
##   - upper-arm twist bones take the arm's roll against the collarbone back out at the shoulder;
##   - half-joint helpers (shoulders, elbows, neck) turn half of their child's bend (swing only; the neck helper also half its turn).
## All measured from the rest pose. Bones a rig does not have are skipped, so rigs without helpers are untouched.

# twist bone -> [parent, child, sign]: the child's roll about the parent-to-child limb, measured against the parent, times sign
const TWISTS := {"LeftForeArmTwist": ["LeftForeArm", "LeftHand", 1.0], "RightForeArmTwist": ["RightForeArm", "RightHand", 1.0],
	"LeftArmTwist": ["LeftShoulder", "LeftArm", -1.0], "RightArmTwist": ["RightShoulder", "RightArm", -1.0]}
# helper -> [parent, child, keeps the turn too]
const HALVES := {"LeftShoulderHelp": ["LeftShoulder", "LeftArm", false], "RightShoulderHelp": ["RightShoulder", "RightArm", false],
	"LeftElbowHelp": ["LeftArm", "LeftForeArm", false], "RightElbowHelp": ["RightArm", "RightForeArm", false],
	"NeckHelp": ["Spine", "neck", true]}

var _twists: Array = []   # [bone, parent, child, sign, axis in the child's rest frame, axis in the twist bone's rest frame, rest]
var _halves: Array = []   # [bone, parent, child, keep turn, child's own axis in its rest frame, rest]

static func has_helpers(skeleton: Skeleton3D) -> bool:
	return skeleton.find_bone("LeftElbowHelp") >= 0 or skeleton.find_bone("LeftForeArmTwist") >= 0

func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for name: String in TWISTS:
		var b := sk.find_bone(name)
		var p := sk.find_bone(TWISTS[name][0])
		var c := sk.find_bone(TWISTS[name][1])
		if b < 0 or p < 0 or c < 0:
			continue
		# the limb's direction: for a forearm twist, elbow -> wrist; for an upper-arm twist, shoulder -> elbow
		var fore: bool = name.contains("Fore")
		var elbow: int = sk.find_bone(String(TWISTS[name][1]).replace("Arm", "ForeArm"))
		var limb: Vector3 = (sk.get_bone_global_rest(c if fore else elbow).origin - sk.get_bone_global_rest(p if fore else c).origin).normalized()
		_twists.append([b, p, c, float(TWISTS[name][2]), (sk.get_bone_global_rest(c).basis.orthonormalized().inverse() * limb).normalized(),
			(sk.get_bone_global_rest(b).basis.orthonormalized().inverse() * limb).normalized(), sk.get_bone_rest(b).basis.get_rotation_quaternion()])
	for name: String in HALVES:
		var b := sk.find_bone(name)
		var p := sk.find_bone(HALVES[name][0])
		var c := sk.find_bone(HALVES[name][1])
		if b < 0 or p < 0 or c < 0:
			continue
		var grand: int = -1
		for i in sk.get_bone_count():
			if sk.get_bone_parent(i) == c and not sk.get_bone_name(i).ends_with("Twist") and not sk.get_bone_name(i).ends_with("Help"):
				grand = i
				break
		var axis := Vector3.UP
		if grand >= 0:
			var own: Vector3 = (sk.get_bone_global_rest(grand).origin - sk.get_bone_global_rest(c).origin).normalized()
			axis = (sk.get_bone_global_rest(c).basis.orthonormalized().inverse() * own).normalized()
		_halves.append([b, p, c, bool(HALVES[name][2]), axis, sk.get_bone_rest(b).basis.get_rotation_quaternion()])

## The child's rotation against its parent, compared with the rest pose, in the child's rest frame.
static func _delta(sk: Skeleton3D, p: int, c: int) -> Quaternion:
	var rest: Quaternion = (sk.get_bone_global_rest(p).basis.orthonormalized().inverse() * sk.get_bone_global_rest(c).basis.orthonormalized()).get_rotation_quaternion()
	var now: Quaternion = (sk.get_bone_global_pose(p).basis.orthonormalized().inverse() * sk.get_bone_global_pose(c).basis.orthonormalized()).get_rotation_quaternion()
	return (rest.inverse() * now).normalized()

## The part of q that turns about `axis` (swing-twist), as a signed angle.
static func _twist_angle(q: Quaternion, axis: Vector3) -> float:
	var along: float = Vector3(q.x, q.y, q.z).dot(axis)
	return 2.0 * atan2(along, q.w)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for t in _twists:
		var d := _delta(sk, t[1], t[2])
		var angle: float = _twist_angle(d, t[4]) * float(t[3])
		sk.set_bone_pose_rotation(t[0], (t[6] as Quaternion) * Quaternion(t[5], wrapf(angle, -PI, PI)))
	for h in _halves:
		var d := _delta(sk, h[1], h[2])
		var part: Quaternion = d
		if not h[3]:
			var ang: float = _twist_angle(d, h[4])
			part = d * Quaternion(h[4], ang).inverse()   # the swing: the bend without the roll
		sk.set_bone_pose_rotation(h[0], (h[5] as Quaternion) * Quaternion.IDENTITY.slerp(part.normalized(), 0.5))
