class_name Enemy
extends Actor
## The shared body of every enemy: stats and model from its EnemyDef, aggro and stun handling, movement helpers and the
## attack-slot ("token") system that stops a crowd all swinging at once. What it actually does in a fight is decided by
## its EnemyBehavior (see game/enemies/).

## Set before adding to the tree. `variant` is the EnemyDef id.
var variant: String = "zombie"
var level_scale: float = 1.0

var def: EnemyDef
var behavior: EnemyBehavior
var target: Actor
var move_speed: float = 2.4
var aggro_range: float = 16.0
var attack_range: float = 1.6
var attack_time: float = 1.1
var damage_min: float = 6.0
var damage_max: float = 10.0
## Speed multiplier from buffs (a Plague Priest's ward hastes its allies).
var buff_speed: float = 1.0
## Distance at which it holds position while waiting for its turn to attack.
var ring: float = 2.8
## True while it is committed to an attack (behaviours set and clear this; an interrupt clears it).
var _attacking: bool = false

var _nav_state: Dictionary = {}
var _aggro: bool = false
var _was_stunned: bool = false
var _orbit_dir: float = 1.0
var _orbit_flip: float = 2.0

# Crowd behaviour: only a few enemies may swing at once (attack tokens); the rest circle and wait their turn.
static var max_tokens: int = 2
static var _token_holders: Dictionary = {}   # instance id -> [weight, expiry (ms)]

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = LAYER_ENEMY
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY
	def = EnemyDb.get_def(variant)
	display_name = def.display_name
	max_health = def.health * level_scale
	health = max_health
	var damage_scale: float = 1.0 + 0.4 * (level_scale - 1.0)
	damage_min = def.damage_min * damage_scale
	damage_max = def.damage_max * damage_scale
	move_speed = def.speed * randf_range(0.9, 1.1)
	attack_range = def.attack_range
	attack_time = def.attack_time
	armor = def.armor
	defense = def.defense
	attack_rating = def.attack_rating
	flinch_chance = def.flinch
	knock_resist = def.knock_resist
	stun_resist = def.stun_resist
	impalable = def.impalable
	gib_color = def.gib_color
	aggro_range = def.aggro_range * randf_range(0.6, 1.0)   # pack-mates notice the hero at different distances
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_orbit_flip = randf_range(1.5, 3.5)
	ring = attack_range + randf_range(0.9, 1.6)
	var folder: String = def.model_path
	var borrowed: bool = not ResourceLoader.exists(folder + "/rigged.glb")
	if borrowed:
		folder = def.fallback_model_path
	_build_model(folder, def.clips, def.height, def.radius)
	if borrowed or def.model_scale != Vector3.ONE:
		visual.scale = def.model_scale
	model.loop("idle")
	# Desynchronise idle poses so a crowd does not move in lockstep.
	model.anim.seek(randf() * 3.0, true)
	behavior = EnemyBehaviors.create(def.behavior)
	behavior.setup(self)

func _physics_process(delta: float) -> void:
	var frozen: bool = _actor_tick(delta)
	if is_ragdolled() or impaled:
		return  # the ragdoll (or the skewering player) is driving this actor
	if frozen:
		move_with(Vector3.ZERO)
		return
	if dead or target == null or target.dead:
		move_with(Vector3.ZERO)
		return
	if stun_time > 0.0:
		if not _was_stunned:
			_was_stunned = true
			_attacking = false
			release_token()
			behavior.on_interrupted()
			model.once("hit", 0.0, 1.4)
		move_with(Vector3.ZERO)
		return
	_was_stunned = false

	var dist: float = flat_distance_to(target)
	if not _aggro and dist < aggro_range:
		_aggro = true
	if not _aggro:
		move_with(Vector3.ZERO)
		model.loop("idle")
		return
	_orbit_flip -= delta
	if _orbit_flip <= 0.0:
		_orbit_flip = randf_range(1.5, 3.5)
		_orbit_dir = -_orbit_dir
	behavior.tick(delta, dist)

# --- movement helpers shared by behaviours ------------------------------------------------

## Current walking speed, with slows and buffs applied.
func pace() -> float:
	return move_speed * speed_factor() * buff_speed

## Walks toward `point`, pathing around obstacles when it is far away, and drifting away from crowd-mates.
func walk_to(point: Vector3, delta: float, speed_mult: float = 1.0, use_nav: bool = true) -> void:
	var dist: float = Vector2(point.x - global_position.x, point.z - global_position.z).length()
	var aim: Vector3 = point
	if use_nav and dist > 3.5:
		aim = Nav.next_point(self, point, _nav_state, delta, 0.5)
	var dir: Vector3 = aim - global_position
	dir.y = 0.0
	face(global_position + dir, 0.2)
	var speed: float = pace() * speed_mult
	move_with(dir.normalized() * speed + separation() * speed)
	model.loop("walk", speed / 2.4)

## Closes in on the target.
func advance_on_target(delta: float, dist: float) -> void:
	walk_to(target.global_position, delta, 1.0, dist > 3.5)

## Backs straight away from a point (keeping its face to the target) at `speed_mult` of its walking speed.
func back_away_from(point: Vector3, speed_mult: float = 1.0) -> void:
	var away: Vector3 = global_position - point
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	face(target.global_position, 0.25)
	var speed: float = pace() * speed_mult
	move_with(away * speed + separation() * speed * 0.5)
	model.loop("walk", 0.9)

## Waiting for a turn: shuffle around the target at a respectful distance instead of standing in a stack.
func circle_target(dist: float, hold: float = -1.0, pace_mult: float = 0.55) -> void:
	if hold < 0.0:
		hold = ring
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var radial: Vector3 = to_target.normalized() if to_target.length() > 0.01 else Vector3.FORWARD
	var tangent: Vector3 = radial.cross(Vector3.UP) * _orbit_dir
	var radial_push: float = clampf((dist - hold) * 0.9, -1.0, 1.0)   # +toward the target, -away
	var speed: float = pace() * pace_mult
	var desired: Vector3 = (tangent * 0.75 + radial * radial_push).limit_length(1.0) * speed + separation() * speed
	face(target.global_position, 0.25)
	move_with(desired)
	if desired.length() > 0.25:
		model.loop("walk", 0.7)
	else:
		model.loop("idle")

## Steers away from nearby enemies so a crowd spreads around the target instead of stacking.
func separation() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	var spacing: float = body_radius * 2.6
	for node in get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other == null or other == self or other.dead:
			continue
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		var d: float = away.length()
		if d > 0.001 and d < spacing:
			push += away / d * (spacing - d)
	return push.limit_length(1.0)

## Red glow: the wind-up cue that tells the hero a heavy attack is coming.
func telegraph(strength: float = 0.55) -> void:
	_flash = maxf(_flash, strength)
	model.set_overlay(_flash_mat)

## One melee blow at the target. `power` scales the damage roll, `weight` the knock-back and stagger.
func strike_target(power: float, weight: float) -> void:
	var result: Dictionary = Combat.resolve(self, target, randf_range(damage_min, damage_max) * power,
		Combat.DamageType.PHYSICAL, true, weight)
	target.receive(result, global_position)

# --- attack slots -------------------------------------------------------------------------

func _tokens_used() -> int:
	var now: int = Time.get_ticks_msec()
	var used: int = 0
	for id in _token_holders.keys():
		var entry: Array = _token_holders[id]
		if not is_instance_id_valid(id) or now > int(entry[1]):
			_token_holders.erase(id)
			continue
		used += int(entry[0])
	return used

func tokens_available() -> bool:
	return _token_holders.has(get_instance_id()) or _tokens_used() + def.token_weight <= max_tokens

func take_token() -> bool:
	if _token_holders.has(get_instance_id()):
		return true
	if _tokens_used() + def.token_weight > max_tokens:
		return false
	_token_holders[get_instance_id()] = [def.token_weight, Time.get_ticks_msec() + 4500]
	return true

func release_token() -> void:
	_token_holders.erase(get_instance_id())

func _exit_tree() -> void:
	release_token()

func _on_death() -> void:
	release_token()
	behavior.on_death(last_result)
	remove_from_group("enemies")
	Sfx.play(self, "death_groan", -4.0)
	await get_tree().create_timer(5.0).timeout
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(visual, "position:y", -body_height, 2.0)
	await tween.finished
	queue_free()
