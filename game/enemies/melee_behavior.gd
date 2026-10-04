class_name MeleeBehavior
extends EnemyBehavior
## The shambler: closes in, waits its turn (only a few enemies may swing at once; the rest circle), then throws either a
## quick swipe or, now and then, a slow telegraphed heavy blow that lunges and hits much harder.

var _t: float = 0.0
var _hit_done: bool = false
var _heavy: bool = false
var _scale: float = 1.0
var _cool: float = 0.0
var _move: Vector3 = Vector3.ZERO
var _active: bool = false

func is_attacking() -> bool:
	return _active

func on_interrupted() -> void:
	_active = false

func tick(delta: float, dist: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	if _active:
		_tick_attack(delta, dist)
		e.move_with(_move)
		return
	var can_swing: bool = _cool <= 0.0 and e.tokens_available()
	if dist <= e.attack_range and can_swing and e.take_token():
		_begin()
		return
	if dist > e.attack_range * 0.9 and (can_swing or dist > e.ring + 0.5):
		e.advance_on_target(delta, dist)
	else:
		e.circle_target(dist)

func _begin() -> void:
	_active = true
	e._attacking = true
	_t = 0.0
	_hit_done = false
	_heavy = randf() < float(e.def.param("heavy_chance", 0.25))
	_scale = 1.4 if _heavy else randf_range(0.78, 0.95)
	e.model.manual(e.def.attack_clip)
	e.model.scrub(e.def.attack_start)

func _hit_frac() -> float:
	return (e.def.attack_strike - e.def.attack_start) / (e.def.attack_end - e.def.attack_start)

func _tick_attack(delta: float, dist: float) -> void:
	_t += delta
	e.face(e.target.global_position, 0.3)
	var duration: float = e.attack_time * _scale
	var t: float = _t / duration
	var hit_frac: float = _hit_frac()
	e.model.scrub(CharacterModel.remap(minf(t, 1.0), hit_frac, e.def.attack_start, e.def.attack_strike, e.def.attack_end))
	_move = Vector3.ZERO
	if _heavy:
		if t < hit_frac:
			e.telegraph()   # red glow while it winds up: the cue to dodge
		if t > hit_frac * 0.55 and t < hit_frac:
			# The lunge: it throws itself at the target just before the blow lands.
			var to_target: Vector3 = e.target.global_position - e.global_position
			to_target.y = 0.0
			if to_target.length() > e.attack_range * 0.7:
				_move = to_target.normalized() * 4.2
	if not _hit_done and t >= hit_frac:
		_hit_done = true
		var reach: float = e.attack_range + (1.0 if _heavy else 0.6)
		if dist <= reach:
			var weight: float = (1.0 if e.def.token_weight <= 1 else 1.8) * (1.5 if _heavy else 1.0)
			e.strike_target((1.6 if _heavy else 0.85), weight)
	if t >= 1.0:
		_active = false
		e._attacking = false
		e.release_token()
		# Heavy blows leave it open for longer. It stays where it is; it does not step back.
		_cool = randf_range(1.3, 2.1) if _heavy else randf_range(0.7, 1.4)
