class_name BowAttack
extends RefCounted
## Shared bow attack and the existing procedural archery presentation, for either member.
const BOW_MODEL := "res://assets/models/archer/bow/model.glb"
const QUIVER_MODEL := "res://assets/models/archer/quiver/model.glb"
const ARROW_MODEL := "res://assets/models/archer/arrow/model.glb"
var p: Player
## The empowered shot's draw: one long gathering of focus, then the release (the ordinary draw is 0.62 s).
const TAKE_AIM_DRAW := 1.9
## Thunderous Shot's draw (visuals only for now: `thunder_visual` stands in for the power, which is not built yet).
const THUNDER_DRAW := 1.9
var thunder_visual: bool = false
var thunder_power: bool = false        # the shot was started by the power itself (it deals its damage and is spent at the release)
var _thunder_point: Vector3             # where a Thunderous Shot is aimed: a point (an enemy's chest, or the ground under the cursor)
var _thunder_aimed: bool = false
var thunder_fx: ThunderousShotFx
var _draw: float = 0.0
var _release: float = 0.0
var _recovery: float = 1.05
var armed: bool = false
var reload_required: float = 0.0
var reload_remaining: float = 0.0
var _draw_arrow: Node3D
var _bow_holder: Node3D
var _quiver: Node3D
var _string_upper: MeshInstance3D
var _string_lower: MeshInstance3D
var _skeleton: Skeleton3D
var _pose_bones: Dictionary = {}
var _bow_scale: float
var _arrow_rest: Transform3D
var aura: TakeAimFx
## What the current shot is for: an Actor, or a breakable prop (a nest) the controlled archer was ordered to shoot.
var _target: Actor
var _prop: Destructible
## Firing position for the current target: found on the rings below, with sight over the world geometry.
const SHOT_RANGE := 17.0    # the bow's reach, flat, centre to centre (the hero's basic ranged attack)
const SPOT_RANGE := 12.0    # centre of the candidate rings (SPOT_RINGS); not a distance the archer walks to
const SPOT_MIN := 8.0
const SPOT_ARRIVE := 1.0
const SPOT_TIMEOUT := 6.0   # a position not reached in this long is given up on
const UNREACHABLE_AFTER := 8.0   # an ordered prop with no firing spot for this long is given up (see PartyCharacterAI)
const REPLAN_COOLDOWN := 0.4
const RETRY_COOLDOWN := 1.0 # no viable position: hold, then look again
const MELEE_CLEAR := 4.0    # a firing position this close to an aggro melee enemy is refused
const SPOT_MOVED := 3.0     # the target has moved this far: positions are chosen again
## Rings (metres from the target, on the archer's side) that firing positions are taken from: only far enough to shoot, so the
## nearest sighted ring point wins. The outer ring sits inside the reach limit (SPOT_OUTER) so snapping to the navmesh cannot push it out.
const SPOT_OUTER := SHOT_RANGE - 1.5
const SPOT_RINGS := [SPOT_OUTER, SPOT_RANGE + 2.0, SPOT_RANGE, SPOT_RANGE - 2.0]
const SPOT_ANGLES := [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9, 1.2, -1.2, 1.5, -1.5, 1.8, -1.8, 2.1, -2.1, 2.4, -2.4, 2.7, -2.7]
var _spot: Vector3
var _has_spot: bool = false
var _spot_point: Vector3
var _spot_age: float = 0.0
var _replan_wait: float = 0.0
var _rejected: Array[Vector3] = []
## Counters the selftest reads: entries into hold, failed looks for a firing position, and shots begun.
var holds: int = 0
var retry_attempts: int = 0
## Seconds an ordered prop has gone without a firing spot (reset when one is found or a shot begins).
var blocked_time: float = 0.0
var shots: int = 0
var refusals: int = 0
var _holding: bool = false

func _init(character: Player) -> void:
	p = character

func attach() -> void:
	_attach_gear()
	_skeleton = p.model.find_children("*", "Skeleton3D", true, false)[0]
	for bone_name in ["Spine02", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
		_pose_bones[bone_name] = _skeleton.find_bone(bone_name)
	p.model.anim.mixer_applied.connect(_apply_draw_pose)

func detach() -> void:
	cancel()
	if p.model.anim.mixer_applied.is_connected(_apply_draw_pose):
		p.model.anim.mixer_applied.disconnect(_apply_draw_pose)
	for node in [_bow_holder, _quiver, _draw_arrow, _string_upper, _string_lower, aura]:
		if is_instance_valid(node): node.queue_free()

## Put the bow away while the archer holds his dagger (see Player.refresh_weapon_model): the object, its counters and reload stay,
## and only the models hide. The shot in progress is the caller's to cancel.
var stowed: bool = false

func set_stowed(on: bool) -> void:
	stowed = on
	for node in [_bow_holder, _quiver]:
		if is_instance_valid(node): node.visible = not on
	if is_instance_valid(_draw_arrow): _draw_arrow.visible = false
	_set_bow_string_visible(false)

func disarm() -> void:
	armed = false
	if is_instance_valid(aura): aura.queue_free()

func arm() -> void:
	if not p.stats.can_use("take_aim") or armed: return
	armed = true
	aura = TakeAimFx.new()
	p.add_child(aura)
	aura.setup(self)

func start(target: Actor) -> void:
	if not is_instance_valid(target) or target.dead:
		return
	_begin(target, null)

## The controlled archer's order to break a prop (a nest) with the bow. Only hero-breakable props qualify.
## Thunderous Shot: draw toward `point` (no enemy needs to be chosen; the bolt goes where the bow points) and loose the power at the end of
## the draw. False when he cannot draw now (busy, dead, no bow).
func start_thunderous(point: Vector3) -> bool:
	if p.dead or p.skills.busy or not p.stats.is_ranged():
		return false
	_thunder_point = point
	_thunder_aimed = true
	thunder_visual = true
	thunder_power = true
	_begin(null, null)
	if not p.skills.busy:
		_clear_thunder_state()
		return false
	return true

func _clear_thunder_state() -> void:
	if thunder_power:
		thunder_visual = false
	thunder_power = false
	_thunder_aimed = false

func start_prop(prop: Destructible) -> void:
	if prop == null or not prop.is_hero_target():
		return
	_begin(null, prop)

func _begin(target: Actor, prop: Destructible) -> void:
	var point := _shot_point(target, prop)
	if not p.stats.is_ranged() or p.skills.busy:
		return
	if not _thunder_aimed and not Nav.sight_clear(p, p.global_position, point, prop):
		refusals += 1   # a shot asked for without sight is refused here, and counted for the selftest
		return
	p.skills.clear_queue()
	_target = target
	_prop = prop
	p.skills.busy = true
	shots += 1
	blocked_time = 0.0
	_holding = false
	p.skills.busy_skill = "basic"
	p.skills.busy_target = target
	p.skills.busy_def = {"kind": "ranged", "charged": false}
	p.skills.busy_t = 0.0
	p.skills.busy_hit_done = false
	p.skills.busy_time = (THUNDER_DRAW if thunder_visual else (TAKE_AIM_DRAW if armed else 0.62)) / p.stats.attack_speed()
	_recovery = (1.05 + randf_range(0.0, 0.22)) / p.stats.attack_speed()
	p.movement.has_goal = false
	p.combat_timer = 5.0
	p.face(point)
	p.model.loop("idle_alert")
	_draw = 0.0
	if thunder_visual:
		_clear_thunder_fx()
		thunder_fx = ThunderousShotFx.new()
		p.add_child(thunder_fx)
		thunder_fx.setup(self)
	if armed:
		Sfx.power(p, "take_aim_charge")

## Where a shot at an Actor (its chest) or a prop (its centre) is aimed.
func _shot_point(target: Actor, prop: Destructible) -> Vector3:
	if _thunder_aimed:
		return _thunder_point
	if prop != null:
		return prop.global_position + Vector3(0, prop.height * 0.5, 0)
	return target.global_position + Vector3(0, target.body_height * 0.62, 0)

func _target_valid() -> bool:
	if _thunder_aimed:
		return true
	if _prop != null:
		return _prop.is_hero_target()
	return is_instance_valid(_target) and not _target.dead

func tick(delta: float) -> void:
	if not _target_valid():
		cancel()
		return
	p.skills.busy_t += delta
	if not p.skills.busy_hit_done:
		# Sight is re-checked through the whole draw: a target that stepped behind a wall or prop is not loosed at.
		var point := _shot_point(_target, _prop)
		if not _thunder_aimed and not Nav.sight_clear(p, p.global_position, point, _prop):
			cancel()
			return
		p.face(point, 0.28)
		_draw = clampf(p.skills.busy_t / p.skills.busy_time, 0.0, 1.0)
		_draw_arrow.visible = true
		if _draw >= 1.0: loose()
	elif p.skills.busy_t >= p.skills.busy_time + _recovery:
		p.skills.busy = false
	_release = maxf(_release - delta, 0.0)
	_apply_draw_pose()

func loose() -> void:
	_apply_draw_pose()
	var from := p.global_position + Vector3(0, 1.45, 0)
	var box: AABB = _draw_arrow.get_meta("mesh_bounds")
	from = _draw_arrow.to_global(Vector3(0, box.size.y * 0.5, 0))
	var still := _shot_point(_target, _prop)
	var aim := still
	if _target != null:
		aim += _target.velocity * clampf(from.distance_to(aim) / (CompanionArrow.SPEED * (2.0 if armed else 1.0)), 0, 0.45)
	# The lead of a moving target must not put the arrow into scenery: then loose at the point that was checked clear.
	if not _thunder_aimed and not Nav.sight_clear(p, p.global_position, aim, _prop):
		aim = still
	var damage := p.stats.ranged_range()
	var multiplier := PowerDb.hero_value("take_aim", "damage_pct", p.member_id) / 100.0 * p.stats.power_damage_mult() if armed else 1.0
	if thunder_visual:
		# The visuals first (they read who is on the line), then the power's damage and stun.
		ThunderousShotFx.release(p, p, from, aim - from, p.powers.thunderous_stun() if thunder_power else 6.0)
		if thunder_power:
			p.powers.thunderous_release(from, aim - from)
		_clear_thunder_fx()
		_clear_thunder_state()
	else:
		CompanionArrow.fire(p.get_parent(), p, from, aim, randf_range(damage.x, damage.y) * multiplier, armed)
	if armed and not thunder_visual:
		TakeAimFx.launch(p, from, aim - from, _draw_arrow.to_global(Vector3(0.0, -box.size.y * 0.5, 0.0)))
		Sfx.power(p, "take_aim_fire")
		reload_required = p.stats.power_recharge_damage(PowerDb.charge_seconds("take_aim"), "ranged")
		reload_remaining = reload_required
		armed = false
		if is_instance_valid(aura): aura.queue_free()
	p.skills.busy_hit_done = true
	_draw = 0.0
	_release = 0.20
	_draw_arrow.visible = false
	_set_bow_string_visible(false)

func _clear_thunder_fx() -> void:
	if is_instance_valid(thunder_fx): thunder_fx.queue_free()
	thunder_fx = null

func cancel() -> void:
	_clear_thunder_fx()
	_clear_thunder_state()
	_draw = 0.0
	_release = 0.0
	_target = null
	_prop = null
	p.skills.busy = false
	if is_instance_valid(_draw_arrow): _draw_arrow.visible = false
	_set_bow_string_visible(false)

## One ranged decision for an archer, AI or controlled, against an Actor or a prop. A target in reach with a clear sight line is shot
## from where he stands: he holds position while he fires, and does not step back or walk to a preferred distance. Only without a clear
## shot does he take up a reachable firing position with sight of the target (the nearest one, see _pick_spot), and he holds there.
## `hold` (stand still) never walks. Melee engagement is not decided here: see Player.update_melee_stance. The shot itself runs in
## tick(), which re-checks sight through the draw.
func engage(target: Actor, prop: Destructible, delta: float, hold: bool = false) -> void:
	if p.skills.busy:
		return
	_replan_wait = maxf(_replan_wait - delta, 0.0)
	var point := _shot_point(target, prop)
	var sight := p.flat_distance_to_point(point) <= SHOT_RANGE and Nav.sight_clear(p, p.global_position, point, prop)
	if sight and p.stats.can_use("basic"):
		if prop != null:
			start_prop(prop)
		else:
			start(target)
		_stop()
		return
	if hold or sight:
		_stop()
		return
	_take_position(point, prop, delta)

func _stop() -> void:
	p.movement.has_goal = false
	p.move_with(Vector3.ZERO)

## True when an ordered prop has had no reachable firing spot for UNREACHABLE_AFTER seconds: the order cannot be carried out.
func prop_unreachable() -> bool:
	return blocked_time >= UNREACHABLE_AFTER

## Keeps a position that still sees the target; otherwise picks a new one, not more often than REPLAN_COOLDOWN, and never one given up.
func _take_position(point: Vector3, prop: Destructible, delta: float) -> void:
	if _has_spot and _spot_point.distance_to(point) > SPOT_MOVED:
		_has_spot = false
		_rejected.clear()
	if _has_spot and not _spot_good(_spot, point, prop):
		_reject_spot()
	if not _has_spot and _replan_wait <= 0.0:
		var found := _pick_spot(point, prop)
		_replan_wait = REPLAN_COOLDOWN if found else RETRY_COOLDOWN
		if not found:
			retry_attempts += 1   # counted for the selftest: a failed look for a firing position
	if prop != null:
		blocked_time = 0.0 if _has_spot else blocked_time + delta
	if _has_spot:
		_holding = false
	elif not _holding:
		holds += 1   # counted for the selftest: this entry into hold
		_holding = true
	if not _has_spot:
		# No viable firing position. An AI archer holds and retries after the cooldown; a directly controlled one keeps moving freely.
		if p.is_controlled():
			_travel(point, delta)
		else:
			_stop()
		return
	_spot_age += delta
	if p.flat_distance_to_point(_spot) <= SPOT_ARRIVE or _spot_age > SPOT_TIMEOUT:
		# Arrived without sight from where the archer stands (or never got there): give this position up.
		_reject_spot()
		_stop()
		return
	_travel(_spot, delta)

## A position at a shooting range of the point, with a clear sight line to it (through the target prop, if that is the target).
func _spot_good(spot: Vector3, point: Vector3, prop: Destructible) -> bool:
	var reach := Vector2(spot.x - point.x, spot.z - point.z).length()
	return reach >= SPOT_MIN and reach <= SHOT_RANGE - 1.0 and Nav.sight_clear(p, spot, point, prop)

## Priorities, in order: a clear line of sight and a shooting range (required); the nearest such spot to where the archer stands, so he
## moves only as far as it takes to shoot (a straight advance wins when it is clear, and an obstruction forces a lateral spot); and
## separation from melee enemies (a candidate within MELEE_CLEAR of an aggro enemy is refused). Returns false when no candidate qualifies.
func _pick_spot(point: Vector3, prop: Destructible) -> bool:
	var away := Vector3(p.global_position.x - point.x, 0.0, p.global_position.z - point.z)
	away = away.normalized() if away.length() > 0.05 else Vector3.BACK
	var best := Vector3.ZERO
	var best_score := INF
	for ring: float in SPOT_RINGS:
		for angle: float in SPOT_ANGLES:
			var candidate := Nav.snap(p, point + away.rotated(Vector3.UP, angle) * ring)
			if _is_rejected(candidate) or not _spot_good(candidate, point, prop) or _melee_near(candidate):
				continue
			var score := p.flat_distance_to_point(candidate)   # the walk: only as far as it takes to shoot
			if score < best_score:
				best_score = score
				best = candidate
	if best_score == INF:
		return false
	_spot = best
	_spot_point = point
	_has_spot = true
	_spot_age = 0.0
	return true

## Whether an aggro enemy that fights at close range stands within MELEE_CLEAR of a spot.
func _melee_near(spot: Vector3) -> bool:
	for node in p.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		var enemy := node as Enemy
		if enemy == null or enemy.dead or not enemy.is_aggro():
			continue
		if Vector2(enemy.global_position.x - spot.x, enemy.global_position.z - spot.z).length() < MELEE_CLEAR:
			return true
	return false

func _reject_spot() -> void:
	if _has_spot:
		_rejected.append(_spot)
	_has_spot = false
	_spot_age = 0.0
	_replan_wait = REPLAN_COOLDOWN

func _is_rejected(spot: Vector3) -> bool:
	for rejected in _rejected:
		if Vector2(rejected.x - spot.x, rejected.z - spot.z).length() < 1.0:
			return true
	return false

func _travel(goal: Vector3, delta: float) -> void:
	p.movement.goal = Nav.snap(p, goal)
	p.movement.has_goal = true
	p.movement.move(delta)
	p.movement.update_locomotion_anim()

func _attach_gear() -> void:
	# Blender Z exports as Godot Y, so the bow is already upright. Rotating it
	# another quarter-turn made Cutter carry and draw it like a staff.
	var bow_path: String = p.appearance.bow_model if p.appearance != null and p.appearance.bow_model != "" else BOW_MODEL   # the kit bow follows the same prop convention
	_bow_holder = _attach_prop(bow_path, "LeftHand", 1.58, Basis.IDENTITY, Vector3(0.0, 0.02, 0.02))
	# The imported quiver is already upright along +Y. Keep it aligned with the spine and add only a slight shoulder cant.
	var quiver_basis := Basis(Vector3.FORWARD, -0.16)
	_quiver = _attach_prop(QUIVER_MODEL, "Spine02", 0.78, quiver_basis, Vector3(-0.14, -0.08, 0.08))
	_draw_arrow = _attach_prop(ARROW_MODEL, "RightHand", 0.92, Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.02, 0.02))
	_draw_arrow.visible = false
	_bow_scale = _bow_holder.global_basis.get_scale().x
	_arrow_rest = _draw_arrow.transform
	_string_upper = _make_bow_cord()
	_string_lower = _make_bow_cord()
	p.add_child(_string_upper)
	p.add_child(_string_lower)

func _attach_prop(path: String, bone: String, size: float, prop_basis: Basis, offset: Vector3) -> Node3D:
	var prop: Node3D = (load(path) as PackedScene).instantiate()
	LootDrop._use_vertex_colours(prop)
	var box: AABB = CharacterModel._bounds_of(prop)
	var extent: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	var skeleton: Skeleton3D = p.model.find_children("*", "Skeleton3D", true, false)[0]
	var rig_scale: float = skeleton.global_transform.basis.get_scale().x
	var holder := Node3D.new()
	holder.position = offset
	holder.basis = prop_basis.scaled(Vector3.ONE * size / maxf(extent * rig_scale, 0.001))
	p.model._mount_for(bone).add_child(holder)
	holder.add_child(prop)
	prop.position = -box.get_center()
	holder.set_meta("mesh_bounds", box)
	return holder

func _make_bow_cord() -> MeshInstance3D:
	var cord := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.006
	mesh.bottom_radius = 0.006
	mesh.height = 1.0
	mesh.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.22, 0.16, 0.09)
	mesh.material = mat
	cord.mesh = mesh
	cord.top_level = true
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cord.visible = false
	return cord

func _set_cord(cord: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta: Vector3 = b - a
	var length: float = delta.length()
	if length <= 0.001:
		cord.visible = false
		return
	var y_axis: Vector3 = delta / length
	var x_axis: Vector3 = y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	cord.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis).scaled(Vector3(1.0, length, 1.0)), (a + b) * 0.5)
	cord.visible = true

func _update_bow_string() -> void:
	if _bow_holder == null or _draw_arrow == null:
		_set_bow_string_visible(false)
		return
	var upper: Vector3 = _bow_holder.to_global(Vector3(0.065, 0.78, 0.0))
	var lower: Vector3 = _bow_holder.to_global(Vector3(0.065, -0.78, 0.0))
	var box: AABB = _draw_arrow.get_meta("mesh_bounds")
	var nock: Vector3 = _draw_arrow.to_global(Vector3(0.0, -box.size.y * 0.5, 0.0)) if _draw > 0.01 else (upper + lower) * 0.5
	_set_cord(_string_upper, upper, nock)
	_set_cord(_string_lower, nock, lower)

func _set_bow_string_visible(on: bool) -> void:
	if _string_upper != null:
		_string_upper.visible = on
	if _string_lower != null:
		_string_lower.visible = on

func _apply_draw_pose() -> void:
	if _skeleton == null:
		return
	if _draw <= 0.01 and _release <= 0.0:
		_draw_arrow.top_level = false
		_draw_arrow.transform = _arrow_rest
		_draw_arrow.visible = false
		_apply_carry_pose()
		_update_bow_string()
		return
	var weight: float = smoothstep(0.0, 0.20, _draw) if _release <= 0.0 else smoothstep(0.0, 0.10, _release)
	_pose("Spine02", Vector3(0.0, -0.12, 0.0), weight)
	var forward: Vector3 = p.visual.global_basis.z.normalized()   # Actor.face uses +Z.
	var side: Vector3 = p.visual.global_basis.x.normalized()
	var chest: Vector3 = p.global_position + Vector3.UP * 1.36
	var pull: float = smoothstep(0.18, 0.92, _draw)
	var bow_hand: Vector3 = chest + Vector3.UP * 0.10 + forward * 0.56 + side * 0.16
	var string_hand: Vector3 = bow_hand.lerp(chest + Vector3.UP * 0.13 + side * 0.16 - forward * 0.06, pull)
	if _release > 0.0:
		string_hand = chest + Vector3.UP * 0.13 + side * 0.28 - forward * 0.14
	_aim_chain(["LeftArm", "LeftForeArm"], "LeftHand", bow_hand, weight)
	_aim_chain(["RightArm", "RightForeArm"], "RightHand", string_hand, weight)
	# Props follow the solved hands, not detached ideal coordinates.
	bow_hand = _skeleton.to_global(_skeleton.get_bone_global_pose(int(_pose_bones["LeftHand"])).origin)
	string_hand = _skeleton.to_global(_skeleton.get_bone_global_pose(int(_pose_bones["RightHand"])).origin)
	_present_draw_props(bow_hand, string_hand, forward)
	_update_bow_string()

## Keep the bow upright beside the hip, rather than rotating it with the generic
## unarmed walk/run palm. Legs, torso and the free arm retain their locomotion.
func _apply_carry_pose() -> void:
	var forward: Vector3 = p.visual.global_basis.z.normalized()
	var side: Vector3 = p.visual.global_basis.x.normalized()
	var carry_hand: Vector3 = p.global_position + Vector3.UP * 1.0 + side * 0.42 + forward * 0.12
	_aim_chain(["LeftArm", "LeftForeArm"], "LeftHand", carry_hand, 1.0)
	var hand: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(int(_pose_bones["LeftHand"])).origin)
	var bow_y: Vector3 = Vector3.UP   # limbs vertical in carry and walk (no lean): the limb tips sit behind the grip, level
	# The mesh's belly is its local -X and its string its local +X (measured on archer/bow and modular/wpn_bow): local -X points forward,
	# so the string faces the archer and the belly the target. The limbs stay vertical (local Y is up).
	var bow_x: Vector3 = -side.cross(bow_y).normalized()
	var bow_z: Vector3 = bow_x.cross(bow_y).normalized()
	_bow_holder.top_level = true
	_bow_holder.global_transform = Transform3D(Basis(bow_x, bow_y, bow_z).scaled(Vector3.ONE * _bow_scale), hand + bow_x * 0.065 * _bow_scale)

## The recruit rig has no authored bow clip, and its idle hand transforms do not
## carry props in an archery pose. During the draw, place the equipment from the
## same three physical points an archer uses: bow hand, string hand, arrow tip.
func _present_draw_props(bow_hand: Vector3, nock: Vector3, forward: Vector3) -> void:
	if _bow_holder == null or _draw_arrow == null:
		return
	var bow_scale: float = maxf(_bow_holder.global_basis.get_scale().x, 0.001)
	var arrow_scale: float = maxf(_draw_arrow.global_basis.get_scale().x, 0.001)
	# BoneAttachment updates later in the skeleton pass. World-space presentation
	# must not inherit that second transform after already following solved hands.
	_bow_holder.top_level = true
	_draw_arrow.top_level = true
	# The grip sits 0.067 along the belly from the mesh centre, which is now toward forward: the centre lies behind the hand.
	var bow_centre: Vector3 = bow_hand - forward * 0.065 * bow_scale
	var arrow_dir: Vector3 = (bow_hand + forward * 0.38 - nock).normalized()
	# Local -X is the belly (measured): it points at the target, the string faces the archer. Arrow was exported with its shaft along +Y.
	var bow_x: Vector3 = -forward
	var bow_y: Vector3 = Vector3.UP
	var bow_z: Vector3 = bow_x.cross(bow_y).normalized()
	_bow_holder.global_transform = Transform3D(Basis(bow_x, bow_y, bow_z).scaled(Vector3.ONE * bow_scale), bow_centre)
	var arrow_x: Vector3 = arrow_dir.cross(Vector3.UP).normalized()
	var arrow_z: Vector3 = arrow_x.cross(arrow_dir).normalized()
	var box: AABB = _draw_arrow.get_meta("mesh_bounds")
	_draw_arrow.global_transform = Transform3D(Basis(arrow_x, arrow_dir, arrow_z).scaled(Vector3.ONE * arrow_scale), nock + arrow_dir * box.size.y * arrow_scale * 0.5)

func _aim_chain(chain: Array[String], hand_name: String, target_world: Vector3, weight: float) -> void:
	var hand: int = int(_pose_bones.get(hand_name, -1))
	if hand < 0:
		return
	var start: Vector3 = _skeleton.get_bone_global_pose(hand).origin
	var target_local: Vector3 = start.lerp(_skeleton.to_local(target_world), weight)
	for iteration in 8:
		for name in chain:
			var bone: int = int(_pose_bones.get(name, -1))
			if bone < 0:
				continue
			var pivot: Vector3 = _skeleton.get_bone_global_pose(bone).origin
			var hand_pos: Vector3 = _skeleton.get_bone_global_pose(hand).origin
			var current: Vector3 = hand_pos - pivot
			var wanted: Vector3 = target_local - pivot
			if current.length_squared() < 0.0001 or wanted.length_squared() < 0.0001:
				continue
			var world_delta := Basis(Quaternion(current.normalized(), wanted.normalized()))
			var parent: int = _skeleton.get_bone_parent(bone)
			var parent_basis: Basis = _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
			var local_delta: Quaternion = Quaternion(parent_basis.inverse() * world_delta * parent_basis)
			_skeleton.set_bone_pose_rotation(bone, local_delta * _skeleton.get_bone_pose_rotation(bone))

## Layers a rotation over the animated pose of a bone. Idempotent: when the animation has not rewritten the bone since the last layer
## (a long hold, or called twice in a frame) the layer is applied to the animated pose it was first applied to, not stacked on itself.
var _layer_base: Dictionary = {}
var _layer_out: Dictionary = {}

func _pose(name: String, euler: Vector3, weight: float) -> void:
	var index: int = int(_pose_bones.get(name, -1))
	if index < 0:
		return
	var base: Quaternion = _skeleton.get_bone_pose_rotation(index)
	if _layer_out.has(name) and base.is_equal_approx(_layer_out[name]):
		base = _layer_base[name]   # still our own output: the animation has not refreshed this bone
	else:
		_layer_base[name] = base
	var layer := Quaternion.from_euler(euler)
	var result: Quaternion = base * Quaternion.IDENTITY.slerp(layer, weight)
	_layer_out[name] = result
	_skeleton.set_bone_pose_rotation(index, result)
