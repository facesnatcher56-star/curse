class_name PouncerBehavior
extends MeleeBehavior
## The ghoul: fast and fragile. It does not walk straight at the hero; it works around to the side in a curve, then crouches
## (a red glow) and springs. The landing spot is locked at the moment it jumps, so a well-timed roll makes it miss and leaves it
## stuck for a moment. Up close it bites like any shambler.

enum State { STALK, WINDUP, LEAP, RECOVER }

var _state: int = State.STALK
var _timer: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _pounce_cool: float = 1.0
var _saved_mask: int = 0

func is_attacking() -> bool:
	return _state != State.STALK or super.is_attacking()

func on_interrupted() -> void:
	super.on_interrupted()
	if _state == State.LEAP:
		_land(false)
	_state = State.STALK
	_pounce_cool = maxf(_pounce_cool, 1.0)
	e.visual.position.y = 0.0

func tick(delta: float, dist: float) -> void:
	_pounce_cool = maxf(_pounce_cool - delta, 0.0)
	match _state:
		State.WINDUP:
			_tick_windup(delta)
			return
		State.LEAP:
			_tick_leap(delta)
			return
		State.RECOVER:
			_timer -= delta
			e.move_with(Vector3.ZERO)
			e.model.loop("idle")
			if _timer <= 0.0:
				_state = State.STALK
				e._attacking = false
			return
	if super.is_attacking():
		super.tick(delta, dist)
		return
	var leap_min: float = float(e.def.param("leap_min", 2.8))
	var leap_max: float = float(e.def.param("leap_max", 6.5))
	if dist >= leap_min and dist <= leap_max and _pounce_cool <= 0.0 and e.has_line_to(e.target) and e.take_token():
		_state = State.WINDUP
		_timer = float(e.def.param("windup", 0.55))
		e._attacking = true
		if e.has_clip("charge_run"):
			e.model.loop("charge_run", 0.3)
		return
	if dist <= e.attack_range:
		super.tick(delta, dist)
		return
	_stalk(delta, dist)

## Works round toward the hero's flank on a curve instead of a straight line.
func _stalk(delta: float, dist: float) -> void:
	var flank_radius: float = float(e.def.param("flank_radius", 5.5))
	if dist > flank_radius + 1.5:
		e.walk_to(e.target.global_position, delta, 1.0, true)
		return
	var radial: Vector3 = e.global_position - e.target.global_position
	radial.y = 0.0
	radial = radial.normalized()
	var swing: float = e._orbit_dir * 0.6
	var point: Vector3 = e.target.global_position + radial.rotated(Vector3.UP, swing) * maxf(dist - 0.9, float(e.def.param("leap_min", 2.8)) + 0.4)
	e.walk_to(point, delta, 1.15, false)

func _tick_windup(delta: float) -> void:
	_timer -= delta
	e.move_with(Vector3.ZERO)
	e.face(e.target.global_position, 0.4)
	e.telegraph(0.6)
	e.visual.position.y = -0.12   # crouched
	if _timer <= 0.0:
		_begin_leap()

func _begin_leap() -> void:
	_state = State.LEAP
	_timer = 0.0
	_from = e.global_position
	# Lead the hero a little; the spot is locked now, so a roll or a sidestep dodges it.
	var lead: Vector3 = e.target.velocity * 0.18
	lead.y = 0.0
	_to = e.target.global_position + lead
	_to.y = 0.0
	_saved_mask = e.collision_mask
	e.collision_mask = Actor.LAYER_WORLD
	e.visual.position.y = 0.0
	Sfx.play(e, "groan", -4.0, 1.3)

func _tick_leap(delta: float) -> void:
	_timer += delta
	var duration: float = float(e.def.param("leap_time", 0.42))
	var u: float = clampf(_timer / duration, 0.0, 1.0)
	var ground: Vector3 = _from.lerp(_to, u)
	e.global_position = Vector3(ground.x, 0.0, ground.z)
	e.visual.position.y = 4.0 * 0.9 * u * (1.0 - u)
	e.face(_to, 1.0)
	e.move_with(Vector3.ZERO)
	if u >= 1.0:
		_land(true)

func _land(hit: bool) -> void:
	e.collision_mask = _saved_mask if _saved_mask != 0 else (Actor.LAYER_WORLD | Actor.LAYER_PLAYER | Actor.LAYER_ENEMY)
	e.visual.position.y = 0.0
	e.release_token()
	_pounce_cool = randf_range(float(e.def.param("cooldown_min", 2.2)), float(e.def.param("cooldown_max", 3.6)))
	if not hit:
		return
	Fx.burst(e, e.global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 10, 3.0, 0.04)
	var gap: float = e.flat_distance_to(e.target)
	if gap <= e.attack_range + 0.7:
		e.strike_target(float(e.def.param("pounce_mult", 1.5)), 1.4)
	# Whether or not it connected, it is stuck on the ground for a moment: the opening to punish it.
	_state = State.RECOVER
	_timer = float(e.def.param("recover", 1.1))
