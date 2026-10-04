class_name Enemy
extends Actor
## Melee zombie: shambles toward the player, winds up, strikes. Variants share the same behaviour
## and differ by model and stats (see VARIANTS).

const CLIPS: Array[String] = ["idle", "walk", "attack", "hit", "death"]
# Strike timing measured from the generated clip (see tools/anim_timing.gd); both variants use the same action.
const ATTACK_START := 0.6
const ATTACK_STRIKE := 1.43
const ATTACK_END := 2.0

const VARIANTS := {
	"zombie": {"name": "Zombie", "model": "res://assets/models/zombie", "height": 1.75, "radius": 0.42,
		"health": 60.0, "damage": [6.0, 10.0], "speed": 2.4, "range": 1.6, "attack_time": 1.1,
		"armor": 8.0, "defense": 12.0, "attack_rating": 28.0, "flinch": 0.35, "knock_resist": 0.0, "stun_resist": 0.0},
	"brute": {"name": "Brute", "model": "res://assets/models/zombie_brute", "height": 2.4, "radius": 0.62,
		"health": 220.0, "damage": [14.0, 22.0], "speed": 1.9, "range": 2.2, "attack_time": 1.4,
		"armor": 25.0, "defense": 20.0, "attack_rating": 45.0, "flinch": 0.1, "knock_resist": 0.6, "stun_resist": 0.5,
		"impalable": false},
}

## Set before adding to the tree.
var variant: String = "zombie"
var level_scale: float = 1.0

var target: Actor
var move_speed: float = 2.4
var aggro_range: float = 16.0
var attack_range: float = 1.6
var attack_time: float = 1.1
var attack_cooldown: float = 0.5
var damage_min: float = 6.0
var damage_max: float = 10.0

var _nav_state: Dictionary = {}
var _aggro: bool = false
var _attacking: bool = false
var _attack_t: float = 0.0
var _attack_hit_done: bool = false
var _cool: float = 0.0
var _was_stunned: bool = false

# Crowd behaviour: only a few enemies may swing at once (attack tokens); the rest circle and wait their turn.
static var max_tokens: int = 2
static var _token_holders: Dictionary = {}   # instance id -> [weight, expiry (ms)]

var _attack_heavy: bool = false
var _attack_scale: float = 1.0
var _attack_move: Vector3 = Vector3.ZERO
var _orbit_dir: float = 1.0
var _orbit_flip: float = 2.0
var _ring: float = 2.8

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = LAYER_ENEMY
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY
	var spec: Dictionary = VARIANTS[variant]
	display_name = spec["name"]
	max_health = float(spec["health"]) * level_scale
	health = max_health
	var damage: Array = spec["damage"]
	var damage_scale: float = 1.0 + 0.4 * (level_scale - 1.0)
	damage_min = float(damage[0]) * damage_scale
	damage_max = float(damage[1]) * damage_scale
	move_speed = float(spec["speed"]) * randf_range(0.9, 1.1)
	attack_range = spec["range"]
	attack_time = spec["attack_time"]
	armor = spec["armor"]
	defense = spec["defense"]
	attack_rating = spec["attack_rating"]
	flinch_chance = spec["flinch"]
	knock_resist = spec["knock_resist"]
	stun_resist = spec["stun_resist"]
	impalable = bool(spec.get("impalable", true))
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_orbit_flip = randf_range(1.5, 3.5)
	_ring = attack_range + randf_range(0.9, 1.6)
	aggro_range *= randf_range(0.6, 1.0)   # pack-mates notice the hero at different distances, so a pack trickles in
	_build_model(spec["model"], CLIPS, spec["height"], spec["radius"])
	model.loop("idle")
	# Desynchronise idle poses so a crowd does not move in lockstep.
	model.anim.seek(randf() * 3.0, true)

func _attack_hit_frac() -> float:
	return (ATTACK_STRIKE - ATTACK_START) / (ATTACK_END - ATTACK_START)

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
			_release_token()
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

	_cool = maxf(_cool - delta, 0.0)
	_orbit_flip -= delta
	if _orbit_flip <= 0.0:
		_orbit_flip = randf_range(1.5, 3.5)
		_orbit_dir = -_orbit_dir
	if _attacking:
		_tick_attack(delta, dist)
		move_with(_attack_move)
		return
	var can_swing: bool = _cool <= 0.0 and _tokens_available()
	if dist <= attack_range and can_swing and _take_token():
		_begin_attack()
		return
	if dist > attack_range * 0.9 and (can_swing or dist > _ring + 0.5):
		# Close in. Path around obstacles while far away; go straight in for the last few metres.
		var aim: Vector3 = target.global_position
		if dist > 3.5:
			aim = Nav.next_point(self, target.global_position, _nav_state, delta, 0.5)
		var dir: Vector3 = (aim - global_position)
		dir.y = 0.0
		face(global_position + dir, 0.2)
		var pace: float = move_speed * speed_factor()
		move_with(dir.normalized() * pace + _separation() * pace)
		model.loop("walk", pace / 2.4)
	else:
		_circle(dist)

## Waiting for a turn (or recovering): shuffle around the target at a respectful distance instead of standing in a stack.
func _circle(dist: float) -> void:
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var radial: Vector3 = to_target.normalized() if to_target.length() > 0.01 else Vector3.FORWARD
	var tangent: Vector3 = radial.cross(Vector3.UP) * _orbit_dir
	var hold: float = _ring
	var radial_push: float = clampf((dist - hold) * 0.9, -1.0, 1.0)   # +toward the target, -away
	var pace: float = move_speed * speed_factor() * 0.55
	var desired: Vector3 = (tangent * 0.75 + radial * radial_push).limit_length(1.0) * pace + _separation() * pace
	face(target.global_position, 0.25)
	move_with(desired)
	if desired.length() > 0.25:
		model.loop("walk", 0.7)
	else:
		model.loop("idle")

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

func _token_weight() -> int:
	return 2 if variant == "brute" else 1

func _tokens_available() -> bool:
	return _token_holders.has(get_instance_id()) or _tokens_used() + _token_weight() <= max_tokens

func _take_token() -> bool:
	if _token_holders.has(get_instance_id()):
		return true
	if _tokens_used() + _token_weight() > max_tokens:
		return false
	_token_holders[get_instance_id()] = [_token_weight(), Time.get_ticks_msec() + 4500]
	return true

func _release_token() -> void:
	_token_holders.erase(get_instance_id())

func _exit_tree() -> void:
	_release_token()

## A quick swipe or, now and then, a slow telegraphed heavy blow that lunges and hits much harder.
func _begin_attack() -> void:
	_attacking = true
	_attack_t = 0.0
	_attack_hit_done = false
	_attack_heavy = randf() < (0.5 if variant == "brute" else 0.25)
	_attack_scale = 1.4 if _attack_heavy else randf_range(0.78, 0.95)
	model.manual("attack")
	model.scrub(ATTACK_START)
	if randf() < 0.4:
		Sfx.play(self, "groan", -8.0, randf_range(0.9, 1.15))

## Steers away from nearby zombies so a crowd spreads around the target instead of stacking.
func _separation() -> Vector3:
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

func _tick_attack(delta: float, dist: float) -> void:
	_attack_t += delta
	face(target.global_position, 0.3)
	var duration: float = attack_time * _attack_scale
	var t: float = _attack_t / duration
	var hit_frac: float = _attack_hit_frac()
	model.scrub(CharacterModel.remap(minf(t, 1.0), hit_frac, ATTACK_START, ATTACK_STRIKE, ATTACK_END))
	_attack_move = Vector3.ZERO
	if _attack_heavy:
		if t < hit_frac:
			_flash = maxf(_flash, 0.55)   # red glow while it winds up: the cue to dodge
			model.set_overlay(_flash_mat)
		if t > hit_frac * 0.55 and t < hit_frac:
			# The lunge: it throws itself at the target just before the blow lands.
			var to_target: Vector3 = target.global_position - global_position
			to_target.y = 0.0
			if to_target.length() > attack_range * 0.7:
				_attack_move = to_target.normalized() * 4.2
	if not _attack_hit_done and t >= hit_frac:
		_attack_hit_done = true
		var reach: float = attack_range + (1.0 if _attack_heavy else 0.6)
		if dist <= reach:
			Sfx.play(self, "swing", -8.0, 0.7 if _attack_heavy else 0.8)
			var weight: float = (1.0 if variant == "zombie" else 1.8) * (1.5 if _attack_heavy else 1.0)
			var power: float = 1.6 if _attack_heavy else 0.85
			var result: Dictionary = Combat.resolve(self, target, randf_range(damage_min, damage_max) * power,
				Combat.DamageType.PHYSICAL, true, weight)
			target.receive(result, global_position)
	if t >= 1.0:
		_attacking = false
		_release_token()
		# Heavy blows leave it open for longer. It stays where it is; it does not step back.
		_cool = randf_range(1.3, 2.1) if _attack_heavy else randf_range(0.7, 1.4)

func _on_death() -> void:
	_release_token()
	remove_from_group("enemies")
	Sfx.play(self, "death_groan", -4.0)
	await get_tree().create_timer(5.0).timeout
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(visual, "position:y", -body_height, 2.0)
	await tween.finished
	queue_free()
