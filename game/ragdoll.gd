class_name Ragdoll
extends RefCounted
## Procedural ragdoll for skinned characters (no physics bodies needed).
##  - Limbs are verlet chains (shoulder->elbow->wrist, hip->knee->ankle, neck->head) simulated in world space, so they
##    swing and drag with the body's motion and gravity; each bone is then re-aimed along its chain segment.
##  - The body is one rigid tumble around the hips (spin, gravity, bounces, friction).
## States: HANG (carried on a blade) -> FLIGHT (thrown) -> LYING (limp on the ground) -> RISING (getting back up).

enum State { OFF, HANG, FLIGHT, LYING, RISING }

const GRAVITY := 20.0
const CHAINS: Array = [
	["LeftArm", "LeftForeArm", "LeftHand"],
	["RightArm", "RightForeArm", "RightHand"],
	["LeftUpLeg", "LeftLeg", "LeftFoot"],
	["RightUpLeg", "RightLeg", "RightFoot"],
	["neck", "Head", "head_end"],
]
const IMPACT_MIN_SPEED := 3.5   # horizontal m/s needed for a collision to count
const IMPACT_DAMAGE := 12.0
const IMPACT_STUN := 3.0        # longer than a normal fall (lie + rise is 2 s)
const BOWL_DAMAGE := 8.0
const LIE_TIME := 1.1
const RISE_TIME := 0.9

var state: int = State.OFF
var permanent: bool = false  # dead actors stay down

var actor: Actor
var skeleton: Skeleton3D
var yaw: float = 0.0
var tilt: float = 0.0  # lean while hanging (radians, positive = head back)

var _tumble: Basis = Basis()
var _omega: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO  # horizontal motion (x, z)
var _vy: float = 0.0
var _height: float = 0.0
var _pivot: Vector3 = Vector3.ZERO
var _hip_y: float = 0.9
var _lie_t: float = 0.0
var _rise_t: float = 0.0
var _lie_from: Basis = Basis()
var _lie_to: Basis = Basis()
var _lie_blend: float = 0.0
var _pin_time: float = 0.0
var _impact_cooldown: float = 0.0
var _bowled: Dictionary = {}   # instance ids already struck by this flight
var _trail_travel: float = 0.0
var _last_hang_pos: Vector3 = Vector3.ZERO
var _hang_velocity: Vector3 = Vector3.ZERO
var _saved_layers: Vector2i = Vector2i.ZERO
var _connected: bool = false
var _tree: SceneTree

var _chains: Array[Dictionary] = []
var _pose_rot: Dictionary = {}   # bone index -> Quaternion last written
var _idle_rot: Dictionary = {}   # bone index -> Quaternion (standing pose to blend back to)

func _init(owner_actor: Actor) -> void:
	actor = owner_actor
	_tree = actor.get_tree()
	skeleton = actor.model.find_children("*", "Skeleton3D", true, false)[0]
	_hip_y = actor.body_height * 0.52
	_pivot = Vector3(0.0, _hip_y, 0.0)

func is_active() -> bool:
	return state != State.OFF

# --- lifecycle -----------------------------------------------------------------

func _begin() -> void:
	if _connected:
		return
	actor.model.anim.pause()
	actor.model.current = ""
	_capture_chains()
	_capture_idle()
	_tree.physics_frame.connect(_on_physics_frame)
	_connected = true

func _finish() -> void:
	state = State.OFF
	if _connected:
		_tree.physics_frame.disconnect(_on_physics_frame)
		_connected = false
	if not is_instance_valid(actor):
		return
	actor.visual.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	actor.collision_layer = _saved_layers.x
	actor.collision_mask = _saved_layers.y
	actor.stun_time = maxf(actor.stun_time, 0.3)  # a moment to find its feet
	actor.model.loop("idle")

## Carried on a blade: limbs dangle, body leans back. The carrier moves `actor`; we keep the pose.
func hang(facing_yaw: float, lean_back: float = 0.45) -> void:
	yaw = facing_yaw
	tilt = lean_back
	_tumble = Basis()
	_height = 0.0
	_last_hang_pos = actor.global_position
	if state == State.OFF:
		# An impaled actor already had its collision switched off; remember what it had before that.
		_saved_layers = actor._saved_collision if actor.impaled else Vector2i(actor.collision_layer, actor.collision_mask)
		_begin()
	state = State.HANG
	_trail_travel = 0.0

## Thrown: ballistic arc with a tumble. `velocity` is the horizontal launch velocity, `lift` the upward speed.
func launch(velocity: Vector3, lift: float, spin: Vector3) -> void:
	if state == State.OFF:
		_saved_layers = Vector2i(actor.collision_layer, actor.collision_mask)
		_begin()
	# Start from the hanging orientation so there is no visual jump.
	_tumble = Basis(actor.visual.basis.orthonormalized()) * Basis(Vector3.UP, -yaw)
	_velocity = Vector3(velocity.x, 0.0, velocity.z)
	_vy = lift
	_omega = spin
	state = State.FLIGHT
	_bowled.clear()
	actor.collision_layer = 0
	actor.collision_mask = Actor.LAYER_WORLD
	_trail_travel = 0.0

## Called when the actor dies mid-ragdoll: it should stay down instead of getting up.
func stay_down() -> void:
	permanent = true
	if state == State.RISING:
		# Killed while getting up (it was knocked down, started to rise, and the blow landed): it must collapse again where it
		# is, not finish standing up and then stand there dead.
		var u: float = clampf(_rise_t / RISE_TIME, 0.0, 1.0)
		var eased: float = u * u * (3.0 - 2.0 * u)
		_lie_from = _lie_from.slerp(Basis(), eased)   # the pose it is in right now
		_lie_blend = 0.0
		_lie_t = LIE_TIME
		state = State.LYING

# --- per-frame -----------------------------------------------------------------

func _on_physics_frame() -> void:
	if not is_instance_valid(actor) or state == State.OFF:
		_finish()
		return
	if _tree.paused:
		return
	update(1.0 / float(Engine.physics_ticks_per_second))

## Holds a downed body on the ground (a boot on the chest): it will not start getting up until this runs out.
func pin(seconds: float) -> void:
	_pin_time = maxf(_pin_time, seconds)

func release_pin() -> void:
	_pin_time = 0.0

func update(delta: float) -> void:
	if _pin_time > 0.0:
		_pin_time -= delta
		if state == State.RISING:
			# Pushed back down: freeze in the current pose as a body lying on the ground.
			_lie_from = _lie_from.slerp(Basis(), clampf(_rise_t / RISE_TIME, 0.0, 1.0))
			_lie_to = _lie_from
			_lie_blend = 1.0
			_lie_t = LIE_TIME * 0.6
			state = State.LYING
		elif state == State.LYING:
			_lie_t = minf(_lie_t, LIE_TIME * 0.6)   # stays down while pinned, then a short beat before it rises
	match state:
		State.HANG:
			_pose_body_hang(delta)
		State.FLIGHT:
			_step_flight(delta)
		State.LYING:
			_step_lying(delta)
		State.RISING:
			_step_rising(delta)
	if state != State.OFF:
		_simulate_chains(delta)
		_apply_chains()
		if state == State.RISING:
			_blend_to_idle()

func _compose(rotation: Basis, extra_height: float) -> void:
	var total: Basis = rotation * Basis(Vector3.UP, yaw)
	actor.visual.transform = Transform3D(total, _pivot - total * _pivot + Vector3(0.0, extra_height, 0.0))

func _pose_body_hang(delta: float) -> void:
	# Track the carrier's motion; if the carrier lets go (or the actor is no longer impaled), fall with that momentum.
	_hang_velocity = (actor.global_position - _last_hang_pos) / maxf(delta, 0.0001)
	_last_hang_pos = actor.global_position
	if not actor.impaled:
		launch(_hang_velocity * 0.7, 0.0, Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))
		return
	# Lean back around the horizontal axis perpendicular to the facing direction.
	var facing: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	var side: Vector3 = facing.cross(Vector3.UP).normalized()
	_compose(Basis(side, -tilt), 0.0)

func _step_flight(delta: float) -> void:
	_vy -= GRAVITY * delta
	_height += _vy * delta
	_velocity *= pow(0.9, delta * 10.0)
	# Rotate about the world axes.
	if _omega.length() > 0.001:
		_tumble = (Basis(_omega.normalized(), _omega.length() * delta) * _tumble).orthonormalized()
	var speed_before: float = _velocity.length()
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	var collision: KinematicCollision3D = actor.move_and_collide(_velocity * delta)
	if collision != null:
		if absf(collision.get_normal().y) < 0.6 and speed_before >= IMPACT_MIN_SPEED and _impact_cooldown <= 0.0:
			_impact_cooldown = 0.4
			_hit_obstacle(speed_before)
		_velocity = _velocity.bounce(collision.get_normal()) * 0.35
		_omega *= 0.7
	if speed_before >= IMPACT_MIN_SPEED:
		_bowl_into_enemies(speed_before)
	actor.global_position.y = 0.0
	# Ground contact depends on how upright the body currently is.
	var upright: float = clampf((_tumble * Basis(Vector3.UP, yaw) * Vector3.UP).y, 0.0, 1.0)
	var clearance: float = 0.2 + (_hip_y - 0.2) * upright * upright
	if _hip_y + _height <= clearance:
		_height = clearance - _hip_y
		if _vy < -2.5:
			_vy = -_vy * 0.35
			_velocity *= 0.7
			_omega *= 0.55
			Fx.burst(actor, actor.global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 8, 3.0, 0.04)
			Fx.shake(actor, 0.05)
		else:
			_vy = 0.0
			_velocity *= pow(0.02, delta)  # sliding friction
			_omega *= pow(0.05, delta)
			if _velocity.length() < 0.6 and _omega.length() < 0.8:
				_begin_lying()
	_leave_blood(delta)
	_compose(_tumble, _height)

## Slammed into a wall, prop or pillar: extra damage and a longer stun than a plain landing.
func _hit_obstacle(speed: float) -> void:
	if actor.dead:
		return
	var result: Dictionary = Combat.resolve(actor, actor, IMPACT_DAMAGE + speed * 1.6, Combat.DamageType.FIRE, false, 1.8)
	result["type"] = Combat.DamageType.PHYSICAL
	result["skill_id"] = "collision"
	actor.receive(result, actor.global_position - _velocity.normalized())
	actor.stun_time = maxf(actor.stun_time, IMPACT_STUN)
	Fx.text_at(actor, actor.global_position + Vector3(0, actor.body_height + 0.5, 0), "Slammed", Color(1.0, 0.85, 0.5), 40)
	Fx.burst(actor, actor.global_position + Vector3(0, 1.0, 0), -_velocity.normalized() + Vector3.UP * 0.3, Color(0.55, 0.5, 0.42), 14, 4.0, 0.05)
	Fx.shake(actor, 0.12)

## A body flying through other enemies knocks them about, hurts them, and passes on its burn, bleed and slow.
func _bowl_into_enemies(speed: float) -> void:
	var here: Vector3 = actor.global_position
	for node in actor.get_tree().get_nodes_in_group("enemies"):
		var other := node as Actor
		if other == null or other == actor or other.dead or other.impaled or other.is_ragdolled():
			continue
		if _bowled.has(other.get_instance_id()):
			continue
		var rel: Vector3 = other.global_position - here
		rel.y = 0.0
		if rel.length() > actor.body_radius + other.body_radius + 0.45 or _height > 1.6:
			continue
		_bowled[other.get_instance_id()] = true
		actor.spread_debuffs_to(other)
		var hit: Dictionary = Combat.resolve(actor, other, BOWL_DAMAGE + speed * 0.8, Combat.DamageType.FIRE, false, 1.5)
		hit["type"] = Combat.DamageType.PHYSICAL
		hit["skill_id"] = "collision"
		other.receive(hit, here)
		if is_instance_valid(other):
			other.interrupt(0.9)
		_velocity *= 0.7
		Fx.burst(actor, other.global_position + Vector3(0, 1.0, 0), _velocity.normalized() + Vector3.UP * 0.3, Color(0.6, 0.05, 0.04), 10, 4.0)
		Fx.shake(actor, 0.08)

func _begin_lying() -> void:
	state = State.LYING
	_lie_t = 0.0
	_lie_blend = 0.0
	_lie_from = _tumble
	# Settle onto the back or front, with the body laid out along the horizontal part of its head direction.
	var total: Basis = _tumble * Basis(Vector3.UP, yaw)
	var head: Vector3 = total * Vector3.UP
	var flat: Vector3 = Vector3(head.x, 0.0, head.z)
	if flat.length() < 0.2:
		flat = total * Vector3.BACK
		flat.y = 0.0
	flat = flat.normalized()
	# The model faces +Z, so its chest is Vector3.BACK in Godot terms.
	var face_up: float = 1.0 if (total * Vector3.BACK).y > 0.0 else -1.0
	var z_axis: Vector3 = Vector3.UP * face_up
	var x_axis: Vector3 = flat.cross(z_axis).normalized()
	_lie_to = Basis(x_axis, flat, z_axis).orthonormalized() * Basis(Vector3.UP, -yaw)
	Fx.blood_decal(actor, actor.global_position, 0.9, Color(0.3, 0.02, 0.02))

func _step_lying(delta: float) -> void:
	_lie_t += delta
	_lie_blend = minf(_lie_blend + delta / 0.25, 1.0)
	_height = lerpf(_height, 0.2 - _hip_y, 1.0 - exp(-12.0 * delta))
	_compose(_lie_from.slerp(_lie_to, _lie_blend), _height)
	if _lie_t >= LIE_TIME and not permanent:
		state = State.RISING
		_rise_t = 0.0
		_lie_from = _lie_from.slerp(_lie_to, _lie_blend)

func _step_rising(delta: float) -> void:
	_rise_t += delta
	var u: float = clampf(_rise_t / RISE_TIME, 0.0, 1.0)
	var eased: float = u * u * (3.0 - 2.0 * u)
	_height = lerpf(_height, 0.0, eased)
	_compose(_lie_from.slerp(Basis(), eased), _height)
	if u >= 1.0:
		_finish()

# --- blood ----------------------------------------------------------------------

func _leave_blood(delta: float) -> void:
	var speed: float = _velocity.length()
	_trail_travel += speed * delta
	if _trail_travel >= 0.45:
		_trail_travel = 0.0
		var spot: Vector3 = actor.global_position
		Fx.blood_decal(actor, spot, randf_range(0.25, 0.45), Color(0.32, 0.02, 0.02))
		if _height > 0.3:
			Fx.burst(actor, actor.global_position + Vector3(0, _hip_y + _height, 0), Vector3.DOWN, Color(0.55, 0.04, 0.04), 5, 2.0, 0.025)

# --- limb chains ------------------------------------------------------------------

func _bone_world_origin(bone: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin

func _capture_chains() -> void:
	_chains.clear()
	var skeleton_basis: Basis = skeleton.global_transform.basis.orthonormalized()
	for names in CHAINS:
		var bones: Array[int] = []
		for n in names:
			var idx: int = skeleton.find_bone(n)
			if idx < 0:
				bones.clear()
				break
			bones.append(idx)
		if bones.is_empty():
			continue
		var points: Array[Vector3] = []
		var lengths: Array[float] = []
		var ref_dirs: Array[Vector3] = []
		var ref_basis: Array[Basis] = []
		for b in bones:
			points.append(_bone_world_origin(b))
		for i in bones.size() - 1:
			lengths.append(maxf(points[i].distance_to(points[i + 1]), 0.02))
		for i in bones.size():
			var pose_basis: Basis = skeleton.get_bone_global_pose(bones[i]).basis.orthonormalized()
			ref_basis.append(pose_basis)
			ref_dirs.append(pose_basis * Vector3.UP)  # bone +Y runs toward its child in this rig
		_chains.append({"bones": bones, "points": points, "prev": points.duplicate(), "lengths": lengths,
			"ref_dirs": ref_dirs, "ref_basis": ref_basis})
	for i in skeleton.get_bone_count():
		_pose_rot[i] = skeleton.get_bone_pose_rotation(i)

func _capture_idle() -> void:
	_idle_rot.clear()
	var anim: Animation = actor.model.anim.get_animation("game/idle")
	if anim == null:
		return
	for i in skeleton.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:" + skeleton.get_bone_name(i))
		var track: int = anim.find_track(path, Animation.TYPE_ROTATION_3D)
		if track >= 0:
			_idle_rot[i] = anim.rotation_track_interpolate(track, 0.0)

func _simulate_chains(delta: float) -> void:
	var gravity: Vector3 = Vector3(0.0, -GRAVITY, 0.0)
	var damping: float = 0.97 if state != State.HANG else 0.94
	for chain in _chains:
		var points: Array = chain["points"]
		var prev: Array = chain["prev"]
		var lengths: Array = chain["lengths"]
		var bones: Array = chain["bones"]
		points[0] = _bone_world_origin(bones[0])  # anchored to the body
		prev[0] = points[0]
		for i in range(1, points.size()):
			var velocity: Vector3 = (points[i] - prev[i]) * damping
			prev[i] = points[i]
			points[i] = points[i] + velocity + gravity * delta * delta
		for _iteration in 4:
			for i in points.size() - 1:
				var offset: Vector3 = points[i + 1] - points[i]
				var length: float = offset.length()
				if length < 0.0001:
					continue
				var correction: Vector3 = offset * ((length - lengths[i]) / length)
				if i == 0:
					points[i + 1] = points[i + 1] - correction
				else:
					points[i] = points[i] + correction * 0.5
					points[i + 1] = points[i + 1] - correction * 0.5
			for i in range(1, points.size()):
				var p: Vector3 = points[i]
				p.y = maxf(p.y, 0.04)
				points[i] = p

func _apply_chains() -> void:
	var inverse_skeleton: Basis = skeleton.global_transform.basis.orthonormalized().inverse()
	for chain in _chains:
		var points: Array = chain["points"]
		var bones: Array = chain["bones"]
		var ref_dirs: Array = chain["ref_dirs"]
		var ref_basis: Array = chain["ref_basis"]
		for j in bones.size():
			var segment: Vector3 = Vector3.ZERO
			if j < points.size() - 1:
				segment = points[j + 1] - points[j]
			else:
				segment = points[j] - points[j - 1]
			if segment.length() < 0.0001:
				continue
			var direction: Vector3 = inverse_skeleton * segment.normalized()
			var reference: Vector3 = ref_dirs[j]
			if reference.dot(direction) < -0.999:
				continue
			var rotation: Quaternion = Quaternion(reference, direction)
			var global_basis: Basis = Basis(rotation) * (ref_basis[j] as Basis)
			var parent: int = skeleton.get_bone_parent(bones[j])
			var parent_basis: Basis = skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
			var local: Quaternion = (parent_basis.orthonormalized().inverse() * global_basis).orthonormalized().get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(bones[j], local)
			_pose_rot[bones[j]] = local

## While getting up, ease every bone from the limp pose back to the standing pose.
func _blend_to_idle() -> void:
	var u: float = clampf(_rise_t / RISE_TIME, 0.0, 1.0)
	var weight: float = clampf((u - 0.25) / 0.75, 0.0, 1.0)
	weight = weight * weight * (3.0 - 2.0 * weight)
	for bone in _idle_rot:
		var limp: Quaternion = skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, limp.slerp(_idle_rot[bone], weight))
