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
var sight_refund: float = 0.0   # Executioner's Sight: the share of Take Aim's charge given back by the shot being loosed
var _draw_arrow: Node3D
var _bow_holder: Node3D
var _bow_built: bool = false   # the bow is a model built for this rig: shown and strung where other items are not
var arrow_path: String = ARROW_MODEL   # the arrow this archer nocks and shoots (CompanionArrow flies the same model)
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

## Cutter's own bow clips (tools/art/elf/bow_anims.py, baked into assets/models/elf/anims.res): when the rig's library has them,
## the bow idle, draw, hold and loose are animation, and this code only seats the bow in his fist the way the clips were keyed,
## nocks the arrow between the string fingers and the rest, strings the bow, tilts the chest to the target's height and carries
## the bow while he walks. Archers without them keep the procedural draw (_apply_draw_pose).
const CLIP_DRAW := "bow_draw"
const CLIP_RELEASE := "bow_release"
const CLIP_NOCK_AT := 7.0 / 19.0   # share of bow_draw from which the arrow is on the string (bow_anims.py NOCK_FRAME)
const GRIP_TURN := 0.6             # the bow in the closed fist, as keyed (bow_anims.py TH, GRIP_Z)
const GRIP_UP := 0.035
const CLIP_REST := Vector3(-0.047, 0.085, 0.022)   # the arrow rest on the bow, in the bow's own space (bow_anims.py ArrowRest)
var clip_mode: bool = false

func attach() -> void:
	clip_mode = p.model.has_clip(CLIP_DRAW)
	_attach_gear()
	_skeleton = p.model.find_children("*", "Skeleton3D", true, false)[0]
	for bone_name in ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
			"RightHandThumb1", "RightHandThumb3", "RightHandIndex3", "RightHandMiddle3"]:
		_pose_bones[bone_name] = _skeleton.find_bone(bone_name)
	for side in ["Left", "Right"]:
		var grip: Array = p.model.finger_grip(side)
		_grips[side] = grip if not grip.is_empty() else [Basis.IDENTITY, Vector3.ZERO]
	p.model.anim.mixer_applied.connect(_apply_draw_pose)
	_set_bow_idle(clip_mode)

## While the bow is out (clip mode), wherever the game asks for his idle he stands in the bow idle.
func _set_bow_idle(on: bool) -> void:
	for clip in ["idle_alert", "idle_rest"]:
		if on:
			p.model.aliases[clip] = "bow_idle"
		else:
			p.model.aliases.erase(clip)

func detach() -> void:
	cancel()
	_set_bow_idle(false)
	if p.model.anim.mixer_applied.is_connected(_apply_draw_pose):
		p.model.anim.mixer_applied.disconnect(_apply_draw_pose)
	for node in [_bow_holder, _quiver, _draw_arrow, _string_upper, _string_lower, aura]:
		if is_instance_valid(node): node.queue_free()

## Put the bow away while the archer holds his dagger (see Player.refresh_weapon_model): the object, its counters and reload stay,
## and only the models hide. The shot in progress is the caller's to cancel.
var stowed: bool = false

func set_stowed(on: bool) -> void:
	stowed = on
	_set_bow_idle(clip_mode and not on)
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
	_aim_point = point
	if clip_mode:
		p.model.manual(CLIP_DRAW)   # scrubbed by the draw itself (_scrub_draw): the arrow nocks exactly when the hands meet
	else:
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
		_aim_point = point
		_draw = clampf(p.skills.busy_t / p.skills.busy_time, 0.0, 1.0)
		_scrub_draw()
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
		for bolt in (p.powers.thunderous_directions(aim - from) if thunder_power else [aim - from]):   # the Splitbow draws its three bolts (map mode only)
			ThunderousShotFx.release(p, p, from, bolt, p.powers.thunderous_stun() if thunder_power else 6.0)
		if thunder_power:
			p.powers.thunderous_release(from, aim - from)
		_clear_thunder_fx()
		_clear_thunder_state()
	else:
		var sight: bool = armed and MapModeLegendaries.sight_applies(p, _target)   # Executioner's Sight (map mode only): Take Aim on an Opening
		CompanionArrow.fire(p.get_parent(), p, from, aim, randf_range(damage.x, damage.y) * multiplier, armed, sight)
		if sight:
			sight_refund = MapModeLegendaries.number("executioners_sight", "refund")
	if armed and not thunder_visual:
		TakeAimFx.launch(p, from, aim - from, _draw_arrow.to_global(Vector3(0.0, -box.size.y * 0.5, 0.0)))
		Sfx.power(p, "take_aim_fire")
		reload_required = p.stats.power_recharge_damage(PowerDb.charge_seconds("take_aim"), "ranged")
		reload_remaining = reload_required * (1.0 - sight_refund)
		sight_refund = 0.0
		armed = false
		if is_instance_valid(aura): aura.queue_free()
	p.skills.busy_hit_done = true
	_draw = 0.0
	_release = RELEASE_TIME
	if clip_mode:
		p.model.once(CLIP_RELEASE, 0.0, 1.0, 0.05)
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
	if follow_screen_goal(delta):
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

## Map mode (issue #87): the on-screen guard sends him to `goal` for a moment; his firing-position goal is cleared and he walks there first.
var _screen_goal: Vector3 = Vector3.INF
var _screen_goal_left: float = 0.0

func set_screen_goal(goal: Vector3) -> void:
	_screen_goal = goal
	_screen_goal_left = MapModeScreen.GUARD_HOLD
	_has_spot = false
	_spot_age = 0.0
	_replan_wait = 0.0

func has_screen_goal() -> bool:
	return _screen_goal.is_finite()

## True while he is walking to the guard's goal (this frame's engage is then spent on that walk).
func follow_screen_goal(delta: float) -> bool:
	if not _screen_goal.is_finite():
		return false
	_screen_goal_left -= delta
	if _screen_goal_left <= 0.0 or p.flat_distance_to_point(_screen_goal) <= MapModeScreen.GUARD_ARRIVE:
		_screen_goal = Vector3.INF
		return false
	_travel(_screen_goal, delta)
	return true

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
	return reach >= SPOT_MIN and reach <= SHOT_RANGE - 1.0 and MapModeScreen.spot_visible(p, spot) and Nav.sight_clear(p, spot, point, prop)

## Priorities, in order: a clear line of sight and a shooting range (required); the nearest such spot to where the archer stands, so he
## moves only as far as it takes to shoot (a straight advance wins when it is clear, and an obstruction forces a lateral spot); and
## separation from melee enemies (a candidate within MELEE_CLEAR of an aggro enemy is refused). Returns false when no candidate qualifies.
func _pick_spot(point: Vector3, prop: Destructible) -> bool:
	var away := Vector3(p.global_position.x - point.x, 0.0, p.global_position.z - point.z)
	away = away.normalized() if away.length() > 0.05 else Vector3.BACK
	var best := Vector3.ZERO
	var best_score := INF
	for ring: float in (MapModeScreen.FIRE_RINGS if MapMode.active and MapModeScreen.enabled else SPOT_RINGS):
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
	# A bow built for this rig (data/appearance/equipment_visuals.json item_models, e.g. the elf's bow) is shown and strung even
	# where other items are not; it is built to the same convention (upright, 1.58 m, belly -X, string at x +0.065, nocks at +-0.78).
	var worn: Variant = p.stats.wielded_weapon()
	var built: Dictionary = {} if worn == null else ModularAppearance.rig(p.model.folder)["item_models"].get(String((worn as Dictionary)["def"]), {})
	_bow_built = not built.is_empty()
	if _bow_built:
		bow_path = String(built["model"])
	if clip_mode and _bow_built:
		_bow_holder = _seat_bow(bow_path)
	else:
		_bow_holder = _attach_prop(bow_path, "LeftHand", 1.58, Basis.IDENTITY, Vector3(0.0, 0.02, 0.02), _bow_built)
	# The imported quiver is already upright along +Y. Keep it aligned with the spine and add only a slight shoulder cant.
	var quiver_basis := Basis(Vector3.FORWARD, -0.16)
	# the bow's own quiver and arrow when they are built for the rig (same conventions: quiver upright 0.78 m, arrow point up 0.92 m)
	arrow_path = String(built.get("arrow", ARROW_MODEL))
	var quiver_path: String = String(built.get("quiver", QUIVER_MODEL))
	var quiver_offset := Vector3(-0.14, -0.08, 0.08)
	if built.has("quiver"):
		# On the back, in metres: Spine02's bone space is the rig's (centimetres on these rigs), and its +Z points out of the
		# chest. Centred 3 cm below Spine02 and 15 cm behind it (the fletchings below the drawing elbow), its top leaning toward the left shoulder (clear of the drawing elbow), its
		# strap side (the model's -Z) against the body.
		var spine_scale: float = p.model.find_children("*", "Skeleton3D", true, false)[0].global_transform.basis.get_scale().x
		quiver_offset = Vector3(0.0, -0.03, -0.15) / maxf(spine_scale, 0.0001)
		quiver_basis = Basis(Vector3(0, 0, 1), -0.2) * Basis(Vector3.UP, PI)
		# placed against the lower spine as above, then carried by the mid spine so it turns with the back in the archer's stance
		var sk: Skeleton3D = p.model.find_children("*", "Skeleton3D", true, false)[0]
		var to_chest: Transform3D = sk.get_bone_global_rest(sk.find_bone("Spine01")).affine_inverse() * sk.get_bone_global_rest(sk.find_bone("Spine02"))
		quiver_offset = to_chest * quiver_offset
		quiver_basis = to_chest.basis * quiver_basis
	_quiver = _attach_prop(quiver_path, "Spine01" if built.has("quiver") else "Spine02", 0.78, quiver_basis, quiver_offset, built.has("quiver"))
	_draw_arrow = _attach_prop(arrow_path, "RightHand", 0.92, Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.02, 0.02), built.has("arrow"))
	_draw_arrow.visible = false
	_bow_scale = _bow_holder.global_basis.get_scale().x
	_arrow_rest = _draw_arrow.transform
	_string_upper = _make_bow_cord()
	_string_lower = _make_bow_cord()
	p.add_child(_string_upper)
	p.add_child(_string_lower)

## The bow in the left fist exactly as the clips were keyed: its handle through the closed fist (CharacterModel.finger_grip), its
## belly turned GRIP_TURN about the handle from the wrist-to-fist direction, the fist GRIP_UP up the bow from its centre.
func _seat_bow(path: String) -> Node3D:
	var prop: Node3D = (load(path) as PackedScene).instantiate()
	LootDrop._use_vertex_colours(prop)
	var skeleton: Skeleton3D = p.model.find_children("*", "Skeleton3D", true, false)[0]
	var rig_scale: float = skeleton.global_transform.basis.get_scale().x
	var grip: Array = p.model.finger_grip("Left")
	var c := cos(GRIP_TURN)
	var s := sin(GRIP_TURN)
	var belly_x := Vector3(-c, 0.0, s)   # the bow's axes in the fist's frame (wrist-to-fist, handle, side)
	var bow := Basis(belly_x, Vector3.UP, Vector3(-s, 0.0, -c))
	var at: Vector3 = belly_x * 0.047 - Vector3.UP * GRIP_UP
	var holder := Node3D.new()
	holder.transform = Transform3D(grip[0], grip[1]) * Transform3D(bow.scaled(Vector3.ONE / rig_scale), at / rig_scale)
	p.model._mount_for("LeftHand").add_child(holder)
	holder.add_child(prop)
	CharacterModel.mark_actor(prop)
	holder.set_meta("mesh_bounds", CharacterModel._bounds_of(prop))
	return holder

func _attach_prop(path: String, bone: String, size: float, prop_basis: Basis, offset: Vector3, built_for_rig: bool = false) -> Node3D:
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
	CharacterModel.mark_actor(prop)
	prop.visible = p.model.show_items or built_for_rig   # a rig without item models keeps the nodes, draws nothing not built for it
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
	if p.model.show_items or _bow_built:
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
	var nock: Vector3 = _draw_arrow.to_global(Vector3(0.0, -box.size.y * 0.5, 0.0)) if _draw > 0.01 and _draw_arrow.visible else (upper + lower) * 0.5
	_set_cord(_string_upper, upper, nock)
	_set_cord(_string_lower, nock, lower)

func _set_bow_string_visible(on: bool) -> void:
	if _string_upper != null:
		_string_upper.visible = on
	if _string_lower != null:
		_string_lower.visible = on

## The draw, in the order an archer shoots: he turns side-on (left shoulder to the target, head turned back to it), the hands meet in
## front of the chest and the arrow is nocked (NOCK_AT), then the bow arm pushes out straight at shoulder height while the string hand
## pulls back to the anchor at the corner of the mouth. At the loose the string hand follows through past the jaw, the bow arm holds a beat, and both
## blend back into the carry. Every point is placed from the skeleton's own measurements (arm lengths, the closed fist from
## CharacterModel.finger_grip), and the bow and arrow follow the solved fists.
const STANCE_TURN := -1.05    # radians about up: the open archer's stance (about 60 degrees), the bow shoulder toward the target
const NOCK_AT := 0.22         # share of the draw at which the hands meet and the arrow is on the string
const FULL_AT := 0.86         # share of the draw at which the string hand reaches the anchor
const RELEASE_TIME := 0.5
const ANCHOR := Vector3(0.085, -0.035, 0.08)   # the string at full draw, from the Head bone: toward the target, down, to the right (m): the corner of the mouth
const FINGERS := 0.07        # the string hand's fist centre sits this far right of the string (the string lies in the finger ends)
const ARROW_REST := 0.042     # the arrow passes this far above the bow fist's centre (over the index knuckle)
const CANT := 0.17            # radians the bow is canted at the shot
const BRACE := 0.13           # the string's distance behind the grip at rest
var _aim_point: Vector3
var _grips: Dictionary = {}   # "Left"/"Right": [grip basis, fist centre] in hand-bone space

func _apply_draw_pose() -> void:
	if _skeleton == null:
		return
	if clip_mode:
		_apply_clip_pose()
		return
	if _draw <= 0.01 and _release <= 0.0:
		_draw_arrow.top_level = false
		_draw_arrow.transform = _arrow_rest
		_draw_arrow.visible = false
		_hold_bow(0.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO)
		_relax_string_arm()
		_tuck_thumb(Vector3.ZERO, 0.0)
		_update_bow_string()
		return
	_relax_string_arm()   # the string arm comes up from, and goes back down to, the relaxed hang
	var drawing: bool = _release <= 0.0
	var u: float = _draw if drawing else 1.0
	var r: float = 0.0 if drawing else 1.0 - _release / RELEASE_TIME
	var weight: float = smoothstep(0.0, NOCK_AT, u) if drawing else 1.0 - smoothstep(0.35, 1.0, r)
	var pull: float = smoothstep(NOCK_AT, FULL_AT, u)
	var up_s: Vector3 = _skel_dir(Vector3.UP)
	var turn: float = smoothstep(0.5, 1.0, weight)   # the bow comes up first, then he turns, so the front leg stays clear of it
	# the turn is shared down the body: the hips take part of it, so the feet stay apart across the line and out of the bow's way
	_turn("Hips", Quaternion(up_s, STANCE_TURN * 0.45 * turn))
	_turn("Spine02", Quaternion(up_s, STANCE_TURN * 0.2 * turn))
	_turn("Spine01", Quaternion(up_s, STANCE_TURN * 0.2 * turn))
	_turn("Spine", Quaternion(up_s, STANCE_TURN * 0.15 * turn))
	_turn("neck", Quaternion(up_s, -STANCE_TURN * 0.45 * turn))
	_turn("Head", Quaternion(up_s, -STANCE_TURN * 0.55 * turn))
	var face: Vector3 = Vector3(p.visual.global_basis.z.x, 0.0, p.visual.global_basis.z.z).normalized()   # Actor.face turns +Z to the target
	var left: Vector3 = Vector3.UP.cross(face)
	var anchor: Vector3 = _bone_world("Head") + face * ANCHOR.x + Vector3.UP * ANCHOR.y - left * ANCHOR.z
	var to_aim: Vector3 = _aim_point - anchor
	var pitch: float = clampf(atan2(to_aim.y, Vector2(to_aim.x, to_aim.z).length()), -0.4, 0.4)
	var aim: Vector3 = face * cos(pitch) + Vector3.UP * sin(pitch)
	var bow_up: Vector3 = (Vector3.UP - aim * aim.dot(Vector3.UP)).normalized()
	bow_up = bow_up.rotated(aim, -CANT)   # the top canted toward his back: the lower limb and string swing out in front of the chest
	# Full draw: the bow fist where the straight arm reaches along the arrow line from the anchor.
	var shoulder: Vector3 = _bone_world("LeftArm")
	var reach: float = _arm_length("Left") * 0.97
	var q: Vector3 = anchor - bow_up * ARROW_REST - shoulder
	var along: float = q.dot(aim)
	var fist_full: Vector3 = anchor - bow_up * ARROW_REST + aim * (-along + sqrt(maxf(along * along - q.length_squared() + reach * reach, 0.0)))
	# Nocking: the bow fist in front of the chest, the string hand at the string.
	var fist_nock: Vector3 = _bone_world("Spine") + face * 0.4 - left * 0.26 + Vector3.UP * 0.08
	var fist: Vector3 = fist_nock.lerp(fist_full, pull)
	var nock: Vector3 = (fist_nock + bow_up * ARROW_REST - aim * BRACE * _bow_scale).lerp(anchor, pull)
	if not drawing:
		var follow: float = smoothstep(0.0, 0.3, r)
		nock = anchor - aim * 0.1 * follow - left * 0.11 * follow
	_hold_bow(weight, fist, bow_up, aim)
	# The string hand: index above the arrow, the string through the curled fingers, the back of the hand outward.
	var right_shoulder: Vector3 = _bone_world("RightArm")
	var hand_fwd: Vector3 = nock - right_shoulder
	hand_fwd = (hand_fwd - Vector3.UP * hand_fwd.dot(Vector3.UP)).normalized()
	var elbow_up: Vector3 = (-Vector3.UP - left * 0.3).lerp(left - aim * 0.5 - Vector3.UP * 0.3, pull)
	_place_hand("Right", nock - left * FINGERS, hand_fwd, Vector3.UP, elbow_up, weight)
	_tuck_thumb(left, weight)
	var bow_fist: Vector3 = _fist_world("Left")
	var string_fist: Vector3 = _fist_world("Right") + left * FINGERS
	_draw_arrow.top_level = true
	_draw_arrow.visible = drawing and u >= NOCK_AT * 0.9
	var rest: Vector3 = bow_fist + bow_up * ARROW_REST + left * 0.012
	var arrow_dir: Vector3 = (rest - string_fist).normalized()
	var arrow_x: Vector3 = arrow_dir.cross(Vector3.UP).normalized()
	var arrow_scale: float = maxf(_draw_arrow.global_basis.get_scale().x, 0.001)
	var box: AABB = _draw_arrow.get_meta("mesh_bounds")
	_draw_arrow.global_transform = Transform3D(Basis(arrow_x, arrow_dir, arrow_x.cross(arrow_dir)).scaled(Vector3.ONE * arrow_scale),
		string_fist + arrow_dir * box.size.y * arrow_scale * 0.5)
	_update_bow_string()

## The draw clip at the draw's progress: it reaches full in the ordinary draw time (faster with attack speed), and a longer draw
## (Take Aim, Thunderous Shot) holds at full.
func _scrub_draw() -> void:
	if not clip_mode or p.model.current != CLIP_DRAW:
		return
	var full: float = minf(p.skills.busy_time, 0.62 / p.stats.attack_speed())
	var length: float = p.model.anim.get_animation("game/" + CLIP_DRAW).length
	p.model.scrub(minf(p.skills.busy_t / full, 1.0) * length)

func _apply_clip_pose() -> void:
	if stowed:
		return
	var drawing: bool = _release <= 0.0 and _draw > 0.01
	var face: Vector3 = Vector3(p.visual.global_basis.z.x, 0.0, p.visual.global_basis.z.z).normalized()
	# the chest tilts to the target's height while the bow is up (the clips aim level)
	var up_weight: float = smoothstep(0.2, 0.8, _draw) if _release <= 0.0 else smoothstep(0.0, RELEASE_TIME * 0.6, _release)
	if up_weight > 0.0:
		var to_aim: Vector3 = _aim_point - _bone_world("Head")
		var pitch: float = clampf(atan2(to_aim.y, Vector2(to_aim.x, to_aim.z).length()), -0.35, 0.35)
		_turn("Spine", Quaternion(_skel_dir(Vector3.UP.cross(face)), -pitch * up_weight))
	elif p.model.current in ["walk", "run"]:
		# the borrowed walk and run swing a free arm: the bow arm holds the bow as the bow idle does instead
		var left: Vector3 = Vector3.UP.cross(face)
		_place_hand("Left", p.global_position + Vector3.UP * 0.93 + left * 0.27 + face * 0.06, -Vector3.UP + left * 0.05,
			face * 0.94 - Vector3.UP * 0.34, -face + left * 0.3, 1.0)
	# the arrow, from between the string fingers to the rest on the bow, once it is on the string
	_draw_arrow.top_level = true
	_draw_arrow.visible = drawing and p.model.current == CLIP_DRAW and 		p.model.anim.current_animation_position >= CLIP_NOCK_AT * p.model.anim.get_animation("game/" + CLIP_DRAW).length
	if _draw_arrow.visible:
		var nock: Vector3 = _skeleton.to_global((_skeleton.get_bone_global_pose(int(_pose_bones["RightHandIndex3"])).origin
			+ _skeleton.get_bone_global_pose(int(_pose_bones["RightHandMiddle3"])).origin) * 0.5)
		var dir: Vector3 = (_bow_holder.to_global(CLIP_REST) - nock).normalized()
		var side: Vector3 = dir.cross(Vector3.UP).normalized()
		var arrow_scale: float = maxf(_draw_arrow.global_basis.get_scale().x, 0.001)
		var box: AABB = _draw_arrow.get_meta("mesh_bounds")
		_draw_arrow.global_transform = Transform3D(Basis(side, dir, side.cross(dir)).scaled(Vector3.ONE * arrow_scale),
			nock + dir * box.size.y * arrow_scale * 0.5)
	_update_bow_string()

## The bow fist and the bow. `weight` 0 is the carry (the arm hanging beside the hip, the bow on a slant, top forward); 1 is the
## shot (the fist at `fist`, the bow upright across `aim`, its belly to the target, elbow turned out and down).
func _hold_bow(weight: float, fist: Vector3, bow_up: Vector3, aim: Vector3) -> void:
	var face: Vector3 = Vector3(p.visual.global_basis.z.x, 0.0, p.visual.global_basis.z.z).normalized()
	var left: Vector3 = Vector3.UP.cross(face)
	var carry: Vector3 = p.global_position + Vector3.UP * 0.97 + left * 0.36 + face * 0.08
	var carry_up: Vector3 = (Vector3.UP * 0.9 + face * 0.42).normalized()
	var at: Vector3 = carry.lerp(fist, weight) + (face * 0.45 + left * 0.2) * sin(PI * weight)   # raised and lowered out in front and to the side, clear of the hip and the front leg
	var up: Vector3 = carry_up.lerp(bow_up, smoothstep(0.3, 0.8, weight)).normalized()   # upright only once the fist is up, clear of the knee
	# carried, the belly faces his leg and the string faces out, clear of the leg; shooting, the belly faces the target
	var facing: Vector3 = -left if weight <= 0.0 else (-left).lerp(aim, smoothstep(0.0, 0.6, weight))
	facing = (facing - up * facing.dot(up)).normalized()
	var shoulder: Vector3 = _bone_world("LeftArm")
	# The wrist-to-fist direction: carried, along the hanging arm; shooting, turned across the line (knuckles toward the string
	# side), so the handle sits in the web of the thumb and the forearm runs off to the side of the string.
	var fwd: Vector3 = (at - shoulder).normalized().lerp((aim - left * 0.7).normalized(), weight)
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var elbow: Vector3 = (-face + left * 0.3).lerp(left - Vector3.UP * 0.4, smoothstep(0.0, 0.4, weight))   # turned out early, so the forearm stays off the string
	_place_hand("Left", at, fwd, up, elbow, 1.0)
	var bow_x: Vector3 = -facing
	_bow_holder.top_level = true
	_bow_holder.global_transform = Transform3D(Basis(bow_x, up, bow_x.cross(up)).scaled(Vector3.ONE * _bow_scale), _fist_world("Left") - facing * 0.065 * _bow_scale)

## The string arm while he carries the bow: standing, it eases down to hang relaxed at his side (the shared idle is a sword guard);
## walking and running keep their own arm swing.
var _relaxed: float = 0.0

func _relax_string_arm() -> void:
	var standing: bool = Vector2(p.velocity.x, p.velocity.z).length() < 0.3
	_relaxed = move_toward(_relaxed, 1.0 if standing else 0.0, p.get_process_delta_time() * 4.0)
	if _relaxed <= 0.0:
		return
	var face: Vector3 = Vector3(p.visual.global_basis.z.x, 0.0, p.visual.global_basis.z.z).normalized()
	var left: Vector3 = Vector3.UP.cross(face)
	var fist: Vector3 = p.global_position + Vector3.UP * 0.95 - left * 0.34 + face * 0.05
	var fwd: Vector3 = fist - _bone_world("RightArm")
	_place_hand("Right", fist, fwd - face * fwd.dot(face), face, -face + Vector3.UP * 0.2, smoothstep(0.0, 1.0, _relaxed))

## Puts a closed fist's centre at `fist` (world), its handle axis along `up` and the wrist-to-fist direction along `fwd`, by turning the
## arm (two-bone, the elbow bent toward `elbow`) and then the hand; `weight` blends from the animated arm.
func _place_hand(side: String, fist: Vector3, fwd: Vector3, up: Vector3, elbow: Vector3, weight: float) -> void:
	if weight <= 0.0:
		return
	var hand: int = int(_pose_bones[side + "Hand"])
	var grip: Array = _grips[side]
	var f: Vector3 = _skel_dir(fwd)
	var v: Vector3 = _skel_dir(up)
	f = (f - v * f.dot(v)).normalized()
	var wanted: Basis = Basis(f, v, f.cross(v)) * (grip[0] as Basis).inverse()
	var now: Basis = _skeleton.get_bone_global_pose(hand).basis.orthonormalized()
	var hand_basis: Basis = Basis(now.get_rotation_quaternion().slerp(wanted.get_rotation_quaternion(), weight))
	var wrist_now: Vector3 = _skeleton.get_bone_global_pose(hand).origin
	var wrist: Vector3 = wrist_now.lerp(_skeleton.to_local(fist) - hand_basis * (grip[1] as Vector3), weight)
	_reach(side, wrist, _skel_dir(elbow))
	var parent: int = _skeleton.get_bone_parent(hand)
	_skeleton.set_bone_pose_rotation(hand, (_skeleton.get_bone_global_pose(parent).basis.orthonormalized().inverse() * hand_basis).get_rotation_quaternion())

## Two-bone reach in skeleton space: the upper arm and forearm turn so the wrist lands on `wrist` (clamped to the arm's length), the
## elbow bending toward `pole`.
func _reach(side: String, wrist: Vector3, pole: Vector3) -> void:
	var upper: int = int(_pose_bones[side + "Arm"])
	var lower: int = int(_pose_bones[side + "ForeArm"])
	var hand: int = int(_pose_bones[side + "Hand"])
	var s: Vector3 = _skeleton.get_bone_global_pose(upper).origin
	var e: Vector3 = _skeleton.get_bone_global_pose(lower).origin
	var a: float = s.distance_to(e)
	var b: float = e.distance_to(_skeleton.get_bone_global_pose(hand).origin)
	var to: Vector3 = wrist - s
	if to.length_squared() < 0.0001:
		return
	var dir: Vector3 = to.normalized()
	var d: float = clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var bend: Vector3 = pole - dir * pole.dot(dir)
	if bend.length_squared() < 0.000001:
		bend = (e - s) - dir * (e - s).dot(dir)
	bend = bend.normalized()
	var cos_a: float = clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow: Vector3 = s + (dir * cos_a + bend * sqrt(1.0 - cos_a * cos_a)) * a
	_swing(upper, e - s, elbow - s)
	e = _skeleton.get_bone_global_pose(lower).origin
	_swing(lower, _skeleton.get_bone_global_pose(hand).origin - e, s + dir * d - e)

## Turns a bone (skeleton space) so the direction `from` (its child, measured now) becomes `to`.
func _swing(bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 0.0000001 or to.length_squared() < 0.0000001:
		return
	var turn := Basis(Quaternion(from.normalized(), to.normalized()))
	var parent: int = _skeleton.get_bone_parent(bone)
	var parent_basis: Basis = _skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var local_turn: Quaternion = Quaternion(parent_basis.inverse() * turn * parent_basis)
	_skeleton.set_bone_pose_rotation(bone, (local_turn * _skeleton.get_bone_pose_rotation(bone)).normalized())

func _skel_dir(world: Vector3) -> Vector3:
	return (_skeleton.global_basis.inverse() * world).normalized()

func _bone_world(name: String) -> Vector3:
	return _skeleton.to_global(_skeleton.get_bone_global_pose(int(_pose_bones[name])).origin)

func _fist_world(side: String) -> Vector3:
	var pose: Transform3D = _skeleton.get_bone_global_pose(int(_pose_bones[side + "Hand"]))
	return _skeleton.to_global(pose.origin + pose.basis.orthonormalized() * (_grips[side][1] as Vector3))

## The string hand's thumb, folded down out of the jaw: the sword grip the hand rests in wraps it round toward the face. The fingers
## are keyed by no clip, so the thumb is set from its rest every time (weight 0 puts it back).
func _tuck_thumb(face_side: Vector3, weight: float) -> void:
	var root: int = int(_pose_bones.get("RightHandThumb1", -1))
	var tip: int = int(_pose_bones.get("RightHandThumb3", -1))
	if root < 0 or tip < 0:
		return
	_skeleton.set_bone_pose_rotation(root, _skeleton.get_bone_rest(root).basis.get_rotation_quaternion())   # no clip keys the fingers: start from rest
	if weight <= 0.0:
		return
	var now: Vector3 = _skeleton.get_bone_global_pose(tip).origin - _skeleton.get_bone_global_pose(root).origin
	var toward_face: Vector3 = _skel_dir(face_side)
	var wanted: Vector3 = now - toward_face * maxf(now.dot(toward_face), 0.0) * 1.5 - _skel_dir(Vector3.UP) * now.length() * 0.4
	_swing(root, now, now.lerp(wanted, weight))

## Shoulder to wrist, in metres.
func _arm_length(side: String) -> float:
	var s: Vector3 = _bone_world(side + "Arm")
	var e: Vector3 = _bone_world(side + "ForeArm")
	return s.distance_to(e) + e.distance_to(_bone_world(side + "Hand"))

## Layers a turn (skeleton space, about the bone's own joint) over the animated pose of a bone. Idempotent: when the animation has not
## rewritten the bone since the last layer (a long hold, or called twice in a frame) the turn is applied to the animated pose it was first
## applied to, not stacked on itself.
var _layer_base: Dictionary = {}
var _layer_out: Dictionary = {}

func _turn(name: String, turn: Quaternion) -> void:
	var index: int = int(_pose_bones.get(name, -1))
	if index < 0:
		return
	var base: Quaternion = _skeleton.get_bone_pose_rotation(index)
	if _layer_out.has(name) and base.is_equal_approx(_layer_out[name]):
		base = _layer_base[name]   # still our own output: the animation has not refreshed this bone
	else:
		_layer_base[name] = base
	var parent: int = _skeleton.get_bone_parent(index)
	var parent_turn: Quaternion = _skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	var result: Quaternion = (parent_turn.inverse() * turn * parent_turn * base).normalized()
	_layer_out[name] = result
	_skeleton.set_bone_pose_rotation(index, result)
