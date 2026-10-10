class_name WardenBehavior
extends MeleeBehavior
## Crypt Warden: close pressure, then a planted overhead cleave. Facing locks at
## commitment; the narrow forward strike can be sidestepped or outranged.

enum State { PRESSURE, WINDUP, STRIKE, RECOVER }
var _state: int = State.PRESSURE
var _timer: float = 0.0
var _special_cool: float = 1.0
var _strike_direction: Vector3 = Vector3.FORWARD
var _special_hit: bool = false

func is_attacking() -> bool:
	return _state != State.PRESSURE or super.is_attacking()

func on_interrupted() -> void:
	super.on_interrupted()
	_state = State.PRESSURE
	_timer = 0.0
	_special_hit = true
	_special_cool = float(e.def.param("special_cooldown", 4.5))
	_cool = maxf(_cool, float(e.def.param("recover", 0.9)))
	_move = Vector3.ZERO
	e._attacking = false
	e.release_token()

func on_death(_killing_blow: Dictionary) -> void:
	on_interrupted()

func tick(delta: float, dist: float) -> void:
	if e.dead or e.stun_time > 0.0 or e.is_ragdolled() or e.impaled or not is_instance_valid(e.target) or e.target.dead:
		on_interrupted()
		return
	_special_cool = maxf(_special_cool - delta, 0.0)
	if _state != State.PRESSURE:
		_tick_special(delta)
		return
	if not super.is_attacking() and _cool <= 0.0 and _special_cool <= 0.0 and dist <= float(e.def.param("special_range", 3.4)) and e.has_line_to(e.target) and e.take_token():
		_state = State.WINDUP
		_timer = 0.0
		_special_hit = false
		e._attacking = true
		e.face(e.target.global_position)
		e.model.manual(e.def.attack_clip)
		e.model.scrub(e.def.attack_start)
		e.move_with(Vector3.ZERO)
		return
	super.tick(delta, dist)

func _tick_special(delta: float) -> void:
	_timer += delta
	e.move_with(Vector3.ZERO)
	var windup: float = float(e.def.param("windup", 0.95))
	var strike: float = float(e.def.param("strike_time", 0.30))
	var recover: float = float(e.def.param("recover", 0.9))
	var held_pose: float = e.def.attack_strike - 0.16
	if _timer < windup:
		e.face(e.target.global_position, 0.15)
		e.telegraph(0.55)
		e.model.scrub(lerpf(e.def.attack_start, held_pose, _timer / windup))
		return
	if _state == State.WINDUP:
		_state = State.STRIKE
		# Lock to the actual visible facing, never to the hero's later position.
		_strike_direction = Vector3(sin(e.visual.rotation.y), 0, cos(e.visual.rotation.y))
	if _timer < windup + strike:
		e.model.scrub(lerpf(held_pose, e.def.attack_strike, (_timer - windup) / strike))
		return
	if not _special_hit:
		_special_hit = true
		if _in_strike_area() and e.has_line_to(e.target):
			e.strike_target(float(e.def.param("special_power", 1.45)), 2.0)
		_state = State.RECOVER
		e.release_token()
		e._attacking = false
	e.model.scrub(lerpf(e.def.attack_strike, e.def.attack_end, clampf((_timer - windup - strike) / recover, 0.0, 1.0)))
	if _timer >= windup + strike + recover:
		_state = State.PRESSURE
		_special_cool = float(e.def.param("special_cooldown", 4.5))
		_cool = 0.4
		e.model.loop("idle")

func _in_strike_area() -> bool:
	var offset: Vector3 = e.target.global_position - e.global_position
	if absf(offset.y) > 2.0:
		return false
	offset.y = 0.0
	var forward: float = offset.dot(_strike_direction)
	var sideways: float = absf(offset.dot(_strike_direction.cross(Vector3.UP)))
	return forward >= 0.0 and forward <= float(e.def.param("special_range", 3.4)) and sideways <= float(e.def.param("strike_half_width", 1.0))
