class_name SupportBehavior
extends MeleeBehavior
## The plague priest: stays behind its pack and makes the pack harder to kill. Every few seconds it casts a ward on nearby
## allies (damage taken down, move speed up) and every so often it raises fresh zombies from the ground. It backs away from
## the hero, so it has to be hunted down; killing it strips every ward it gave out. A staff swat is its only fight.

enum State { POSITION, CAST }

var _state: int = State.POSITION
var _cast_t: float = 0.0
var _cast_kind: String = "ward"
var _ward_cd: float = 3.0
var _summon_cd: float = 8.0
var _summoned: Array[Enemy] = []

func is_attacking() -> bool:
	return _state == State.CAST or super.is_attacking()

func on_interrupted() -> void:
	super.on_interrupted()
	if _state == State.CAST:
		_state = State.POSITION
		_ward_cd = maxf(_ward_cd, 2.0)
		e.model.loop("idle")

func on_death(_blow: Dictionary) -> void:
	# Its wards die with it.
	for node in e.get_tree().get_nodes_in_group("enemies"):
		var ally := node as Actor
		if ally != null and ally.ward_source == e:
			ally.clear_ward()

func tick(delta: float, dist: float) -> void:
	_ward_cd = maxf(_ward_cd - delta, 0.0)
	_summon_cd = maxf(_summon_cd - delta, 0.0)
	if _state == State.CAST:
		_tick_cast(delta)
		return
	if super.is_attacking():
		super.tick(delta, dist)
		return
	var flee: float = float(e.def.param("flee_dist", 4.5))
	var allies: Array[Enemy] = _allies_near(10.0)
	if dist <= e.attack_range and e.tokens_available():
		super.tick(delta, dist)   # cornered: swat with the staff
		return
	if _ward_cd <= 0.0 and not allies.is_empty() and dist > flee * 0.7:
		_begin_cast("ward")
		return
	_summoned = _summoned.filter(func(z: Enemy) -> bool: return is_instance_valid(z) and not z.dead)
	if _summon_cd <= 0.0 and _summoned.size() < int(e.def.param("summon_max", 4)) and dist > flee:
		_begin_cast("summon")
		return
	var keep_min: float = float(e.def.param("keep_min", 6.5))
	var keep_max: float = float(e.def.param("keep_max", 11.0))
	if dist < flee:
		e.back_away_from(e.target.global_position, 1.3)
	elif dist < keep_min:
		e.back_away_from(e.target.global_position, 0.8)
	elif dist > keep_max:
		e.walk_to(e.target.global_position, delta, 0.9, true)
	else:
		e.circle_target(dist, (keep_min + keep_max) * 0.5, 0.6)

func _allies_near(radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in e.get_tree().get_nodes_in_group("enemies"):
		var ally := node as Enemy
		if ally != null and ally != e and not ally.dead and ally.def.behavior != "support" \
				and ally.flat_distance_to(e) <= radius:
			out.append(ally)
	return out

func _begin_cast(kind: String) -> void:
	_state = State.CAST
	_cast_kind = kind
	_cast_t = 0.0
	e._attacking = true
	if e.has_clip("cast"):
		e.model.manual("cast")
		e.model.scrub(0.4)
	Fx.ring(e, e.global_position, 2.0, Color(0.55, 1.0, 0.3))

func _tick_cast(delta: float) -> void:
	_cast_t += delta
	var total: float = 1.1
	e.move_with(Vector3.ZERO)
	e.face(e.target.global_position, 0.2)
	e.telegraph(0.3, "cast")
	if e.has_clip("cast"):
		e.model.scrub(lerpf(0.4, 1.6, clampf(_cast_t / total, 0.0, 1.0)))
	if _cast_t >= total:
		if _cast_kind == "ward":
			_apply_ward()
		else:
			_summon()
		_state = State.POSITION
		e._attacking = false
		e.model.loop("idle")

func _apply_ward() -> void:
	_ward_cd = float(e.def.param("ward_interval", 7.0))
	var warded: int = 0
	for ally in _allies_near(10.0):
		ally.apply_ward(float(e.def.param("ward_time", 5.0)), float(e.def.param("ward_reduction", 0.4)),
			float(e.def.param("ward_haste", 1.25)), e)
		Fx.beam(e, e.global_position + Vector3(0, 1.4, 0), ally.global_position + Vector3(0, 1.0, 0), Color(0.55, 1.0, 0.3, 0.8))
		warded += 1
		if warded >= 5:
			break
	Fx.light_flash(e, e.global_position + Vector3(0, 1.4, 0), Color(0.55, 1.0, 0.3), 3.0, 0.3)

func _summon() -> void:
	_summon_cd = float(e.def.param("summon_interval", 15.0))
	var director: Node = e.get_tree().get_first_node_in_group("director")
	if director == null:
		return
	for i in int(e.def.param("summon_count", 2)):
		var angle: float = randf() * TAU
		var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.8, 3.0)
		var spot: Vector3 = e.global_position + offset
		var zombie: Enemy = director.spawn_enemy(spot, "zombie", e.level_scale)
		zombie.xp_eligible = false   # renewable: a priest can make these forever, so they pay nothing
		zombie.stun_time = 0.9   # clawing its way out of the ground
		zombie._aggro = true
		var tween: Tween = zombie.create_tween()
		zombie.visual.position.y = -1.2
		tween.tween_property(zombie.visual, "position:y", 0.0, 0.9)
		SkillFx.ground_ring(e, spot, 0.3, 1.4, Color(0.5, 1.0, 0.3, 0.8), 0.5)
		SkillFx.dust(e, spot, 0.8, 10)
		_summoned.append(zombie)
