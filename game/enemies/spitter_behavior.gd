class_name SpitterBehavior
extends EnemyBehavior
## The spitter: stays at range and never stands still for long. It keeps its distance (backing off when the hero closes in,
## advancing when they back away), strafes, and every few seconds plants its feet and lobs acid at where the hero is
## heading. The landing spot is marked on the ground first; the puddle it leaves slows and poisons.

enum State { REPOSITION, WINDUP, RECOVER }

var _state: int = State.REPOSITION
var _timer: float = 0.0
var _cooldown: float = 1.5
var _aim: Vector3 = Vector3.ZERO
var _fired: bool = false

func is_attacking() -> bool:
	return _state != State.REPOSITION

func on_interrupted() -> void:
	_state = State.REPOSITION
	_cooldown = maxf(_cooldown, 1.2)

func tick(delta: float, dist: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	match _state:
		State.WINDUP:
			_tick_windup(delta)
			return
		State.RECOVER:
			_timer -= delta
			e.move_with(Vector3.ZERO)
			e.face(e.target.global_position, 0.2)
			if _timer <= 0.0:
				_state = State.REPOSITION
				e._attacking = false
			return
	var preferred: float = float(e.def.param("preferred", 8.0))
	var min_dist: float = float(e.def.param("min_dist", 5.0))
	var fire_range: float = float(e.def.param("fire_range", 13.0))
	if _cooldown <= 0.0 and dist <= fire_range and dist >= 2.0 and e.has_line_to(e.target):
		_begin_windup()
		return
	if dist < min_dist:
		e.back_away_from(e.target.global_position, 1.25)   # kiting: gets out of reach instead of fighting
	elif dist > preferred + 2.5:
		e.walk_to(e.target.global_position, delta, 1.0, true)
	else:
		e.circle_target(dist, preferred, 0.8)

func _begin_windup() -> void:
	_state = State.WINDUP
	_timer = float(e.def.param("windup", 0.75))
	_fired = false
	e._attacking = true
	# Aim where the hero is heading, not where they are.
	var flight: float = float(e.def.param("glob_time", 0.85))
	var lead: Vector3 = e.target.velocity * flight * 0.8
	lead.y = 0.0
	_aim = e.target.global_position + lead
	_aim.y = 0.0

func _tick_windup(delta: float) -> void:
	var total: float = float(e.def.param("windup", 0.75))
	_timer -= delta
	e.move_with(Vector3.ZERO)
	e.face(_aim, 0.35)
	e.telegraph(0.3, "spit")
	if e.has_clip("throw"):
		e.model.manual("throw")
		e.model.scrub(lerpf(0.55, 1.0, clampf(1.0 - _timer / total, 0.0, 1.0)))
	if not _fired and _timer <= 0.0:
		_fired = true
		_spit()
		_state = State.RECOVER
		_timer = 0.5
		_cooldown = randf_range(float(e.def.param("cooldown_min", 2.4)), float(e.def.param("cooldown_max", 3.6)))

func _spit() -> void:
	var glob := AcidGlob.new()
	glob.source = e
	glob.from_pos = e.global_position + Vector3(0, e.body_height * 0.75, 0)
	glob.to_pos = _aim
	glob.flight_time = float(e.def.param("glob_time", 0.85))
	glob.splash_radius = float(e.def.param("splash", 1.3))
	glob.damage = randf_range(e.damage_min, e.damage_max)
	glob.puddle_radius = float(e.def.param("puddle_radius", 1.6))
	glob.puddle_time = float(e.def.param("puddle_time", 3.5))
	glob.puddle_dps = float(e.def.param("puddle_dps", 5.0))
	glob.puddle_slow = float(e.def.param("puddle_slow", 0.3))
	e.get_tree().current_scene.add_child(glob)
	Fx.burst(e, glob.from_pos, (_aim - e.global_position).normalized(), Color(0.5, 0.9, 0.2), 12, 4.0, 0.03, true)
