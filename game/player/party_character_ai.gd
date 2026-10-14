class_name PartyCharacterAI
extends RefCounted
## AI chooses orders; the common character's existing skills and movement execute them.
var p: Player
var leash_active: bool = false
var _leader_id: int = 0
var _trail: Array[Vector3] = []
var _follow_fallback_at := Vector3(INF, 0, INF)

func _init(character: Player) -> void:
	p = character

func tick(delta: float) -> void:
	var party := PartyManager.current()
	var assignment := party.controller_for(p.member_id)
	var leader := party.active_body(String(assignment.controller_id))
	if leader == null or leader == p or leader.dead:
		p.move_with(Vector3.ZERO)
		return
	var gap := p.flat_distance_to(leader)
	if _leader_id != leader.get_instance_id():
		_leader_id = leader.get_instance_id()
		_trail.clear()
		_follow_fallback_at = Vector3(INF, 0, INF)
	if _trail.is_empty() or _trail.back().distance_to(leader.global_position) > 1.0:
		_trail.append(leader.global_position)
		if _trail.size() > 128: _trail.pop_front()
	var formation := Nav.snap(p, leader.global_position + Vector3(2.4, 0, 3.8).rotated(Vector3.UP, leader.visual.rotation.y))
	if not Nav.clearance(p, formation, formation): formation = leader.global_position
	if try_rescue(leader): return
	# Cast only a live target: an enemy freed at the end of the last frame is still held by attack_target.
	var target: Enemy = (p.attack_target as Enemy) if is_instance_valid(p.attack_target) else null
	if not is_instance_valid(target) or target.dead or target.flat_distance_to(leader) > 16.0:
		target = null
		for node in p.get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Enemy
			if enemy != null and not enemy.dead and enemy.is_aggro() and enemy.flat_distance_to(leader) < 12.0:
				if target == null or enemy.flat_distance_to(p) < target.flat_distance_to(p): target = enemy
	p.attack_target = target
	if gap > 16.0: target = null
	# A prop (a nest) is attacked only when the player ordered it (the companion-attack hotkey). AI companions never choose a prop
	# themselves, and melee companions keep to enemies. The order stays held while an enemy is the target; it is measured from the
	# leader like an enemy is, so Cutter walks to a nest the hero is near rather than ignoring it from 17 m.
	var prop: Destructible = null
	if target == null and p.stats.is_ranged() and p.bow != null:
		var ordered: Destructible = p.attack_prop
		if is_instance_valid(ordered) and ordered.is_hero_target() and leader.flat_distance_to(ordered) <= 16.0:
			prop = ordered
	if target != null or prop != null:
		leash_active = false
		if p.stats.is_ranged() and p.bow != null:
			# The shared bow decides fire, step-back and firing position, with sight checked against the world geometry.
			p.bow.engage(target, prop, delta)
			if prop != null and p.bow.prop_unreachable():
				_give_up_prop()
			return
		if p.flat_distance_to(target) - target.body_radius <= 1.8 and Nav.line_clear(p, target.global_position):
			p.skills.start_skill("basic", target)
			p.move_with(Vector3.ZERO)
			return
		_travel(target.global_position, delta)
		return
	if gap > 6.0: leash_active = true
	if gap <= 3.5: leash_active = false
	if leash_active:
		# A nearest nav point can lie in a disconnected pocket. Use the completed
		# shared query to reject that formation; do not spend an extra reachability query.
		var state := p.movement._nav_state
		var path: PackedVector3Array = state.get("path", PackedVector3Array())
		if state.has("queries") and (state.get("goal", Vector3.INF) as Vector3).distance_to(formation) < 0.5:
			if path.is_empty() or path[path.size() - 1].distance_to(state.get("endpoint", formation)) > 0.5:
				_follow_fallback_at = leader.global_position
		if _follow_fallback_at.distance_to(leader.global_position) <= 1.0: formation = leader.global_position
		_travel(formation, delta, 1.25 if gap > 8.0 else 1.0)
	else:
		p.movement.has_goal = false
		p.move_with(Vector3.ZERO)
		p.movement.update_locomotion_anim()

## No firing spot on the ordered nest for too long: the order is dropped, with a word to the player (the bow counts the time).
func _give_up_prop() -> void:
	p.attack_prop = null
	p.bow.blocked_time = 0.0
	p.say_banner("%s: no firing spot on the nest" % p.display_name)

func _travel(goal: Vector3, delta: float, speed_mult: float = 1.0) -> void:
	p.movement.goal = Nav.snap(p, goal)
	p.movement.has_goal = true
	p.movement.move(delta, speed_mult)
	p.movement.update_locomotion_anim()

func off_camera(point: Vector3) -> bool:
	var camera := p.get_viewport().get_camera_3d()
	if camera == null: return false
	var screen := p.get_viewport().get_visible_rect().grow(48)
	for offset in [Vector3.ZERO, Vector3.UP * p.body_height, Vector3.LEFT * p.body_radius, Vector3.RIGHT * p.body_radius]:
		var sample: Vector3 = point + offset
		if not camera.is_position_behind(sample) and screen.has_point(camera.unproject_position(sample)): return false
	return true

func rescue_eligible(leader: Player) -> bool:
	var state := p.movement._nav_state
	return p.flat_distance_to(leader) > 30.0 and float(state.get("failed_time", 0.0)) >= 5.0 \
		and int(state.get("failed_replans", 0)) >= 2 and not p.dead and not p.skills.busy \
		and p.stun_time <= 0.0 and not p.knockdown.active() and not p.movement.rolling and not p.is_ragdolled() and off_camera(p.global_position)

func try_rescue(leader: Player) -> bool:
	if not rescue_eligible(leader) or not Nav.ready(p): return false
	for i in range(_trail.size() - 1, -1, -1):
		var candidate := Nav.snap(p, _trail[i])
		if candidate.distance_to(_trail[i]) > 1.0 or candidate.distance_to(leader.global_position) > 30.0: continue
		if not off_camera(candidate) or not Nav.clearance(p, candidate, candidate, true): continue
		# A clear segment from the leader proves this breadcrumb is on the reachable side.
		if not Nav.clearance(p, leader.global_position, candidate): continue
		p.global_position = Vector3(candidate.x, 0, candidate.z)
		p.velocity = Vector3.ZERO
		p.reset_physics_interpolation()
		Nav.reset(p, p.movement._nav_state)
		leash_active = false
		return true
	return false
