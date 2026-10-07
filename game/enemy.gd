class_name Enemy
extends Actor
## The shared body of every enemy: stats and model from its EnemyDef, aggro and stun handling, movement helpers and the
## attack-slot ("token") system that stops a crowd all swinging at once. What it actually does in a fight is decided by
## its EnemyBehavior (see game/enemies/).

## Set before adding to the tree. `variant` is the EnemyDef id.
var variant: String = "zombie"
var level_scale: float = 1.0
## Whether killing it pays the hero XP. True for everything the world places and for finite spawns (a nest's break-out, an uprising); false
## for anything that can be made over and over (a Plague Priest's summons), so nothing can be farmed. Set it deliberately at the spawn.
var xp_eligible: bool = true

var def: EnemyDef
var behavior: EnemyBehavior
var target: Actor
var move_speed: float = 2.4
var aggro_range: float = 12.0
var attack_range: float = 1.6
var attack_time: float = 1.1
var damage_min: float = 6.0
var damage_max: float = 10.0
## Distance at which it holds position while waiting for its turn to attack.
var ring: float = 2.8
## True while it is committed to an attack (behaviours set and clear this; an interrupt clears it).
var _attacking: bool = false

var _nav_state: Dictionary = {}
var _aggro: bool = false

## What it does before it notices anyone (see _idle_tick): "" stands still, "wander" strolls about `home` (or round `patrol`, a loop
## of points), "feed" hunches over `feed_at`. Monsters placed by hand in a location use these; a wave's arrivals just stand.
## `group_id` ties a placed group together: when one of them notices the hero, all of them do.
var idle_mode: String = ""
var home: Vector3 = Vector3.ZERO
var idle_radius: float = 4.0
var patrol: Array[Vector3] = []
var feed_at: Vector3 = Vector3.ZERO
var group_id: int = -1
var _idle_goal: Vector3 = Vector3.ZERO
var _idle_wait: float = 0.0
var _patrol_index: int = 0
var _idle_clock: float = 0.0
var _notice_timer: float = 0.0
var _retreat_ms: int = -100000   # when it last backed away from the hero (see back_away_from)
## Seconds left before it notices anything (set by the wave director; gives the hero a moment to get their bearings).
var alert_delay: float = 0.0
var _was_stunned: bool = false
var _orbit_dir: float = 1.0
var _orbit_flip: float = 2.0

# Crowd behaviour: only a few enemies may swing at once (attack tokens); the rest circle and wait their turn.
static var max_tokens: int = 2
static var _token_holders: Dictionary = {}   # instance id -> [weight, expiry (ms)]

## Sets how dangerous the body is (a world threat, see WorldThreat: the same scale as `level_scale`) on one that already exists: health and
## damage follow, the share of health left stays. A named monster calls this as it grows; spawning it with its threat does the same job.
func set_threat(threat: float) -> void:
	threat = maxf(threat, 0.1)
	var fraction: float = health / maxf(max_health, 1.0)
	var old_damage: float = 1.0 + 0.4 * (level_scale - 1.0)
	var new_damage: float = 1.0 + 0.4 * (threat - 1.0)
	max_health *= threat / maxf(level_scale, 0.1)
	health = max_health * fraction
	damage_min *= new_damage / old_damage
	damage_max *= new_damage / old_damage
	level_scale = threat

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
	var borrowed: bool = not (ResourceLoader.exists(folder + "/rigged.glb") and ResourceLoader.exists(folder + "/anims.res"))
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

	if alert_delay > 0.0:
		alert_delay -= delta
		move_with(Vector3.ZERO)
		model.loop("idle")
		return
	var dist: float = flat_distance_to(target)
	if not _aggro and dist < aggro_range:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_notice_timer = 0.25
			# Close by it just notices; farther off it needs a clear line (a wall or a tree hides the hero).
			if dist < aggro_range * 0.45 or has_line_to(target):
				wake()
	if not _aggro:
		_idle_tick(delta)
		return
	_orbit_flip -= delta
	if _orbit_flip <= 0.0:
		_orbit_flip = randf_range(1.5, 3.5)
		_orbit_dir = -_orbit_dir
	if dist > FAR_THINK_RANGE:   # a monster that is far from the hero thinks every other tick (nobody can see it do it)
		_far_skip = not _far_skip
		_far_delta += delta
		if _far_skip:
			return
		delta = _far_delta
		_far_delta = 0.0
	behavior.tick(delta, dist)

## Anything the hero hits turns on them at once, however far away it was and whether or not it had noticed them.
func receive(result: Dictionary, source_pos: Vector3) -> void:
	if not dead and result.get("source") is Player:
		alert_delay = 0.0
		wake()
		# A ranged monster that was running from the hero and got hit is snared for a while instead of being kited around the map.
		var snare: float = float(def.param("snare_on_hit", 0.0))
		if snare > 0.0 and Time.get_ticks_msec() - _retreat_ms < 800:
			apply_snare(snare, float(def.param("snare_amount", 0.6)))
	super.receive(result, source_pos)

## It has noticed the hero (or been hit): stop what it was doing, and call the rest of its group.
func is_aggro() -> bool:
	return _aggro

func wake() -> void:
	if _aggro:
		return
	_aggro = true
	if dormant:
		dormant = false
		visible = true
		set_physics_process(true)
		model.anim.active = true
	if visual != null:
		visual.rotation.x = 0.0   # standing up from a corpse
	if group_id < 0:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var mate := node as Enemy
		if mate != null and mate != self and mate.group_id == group_id and not mate.dead and not mate._aggro:
			mate.alert_delay = randf_range(0.1, 0.7)   # a beat behind the one that saw, so a group does not move as one
			mate.wake()

# --- before it notices anyone --------------------------------------------------------------

func _idle_tick(delta: float) -> void:
	_idle_clock += delta
	match idle_mode:
		"feed":
			move_with(Vector3.ZERO)
			face(feed_at, 0.15)
			model.loop("idle", 0.45)
			if visual != null:   # hunched over the body, rocking a little as it tears
				visual.rotation.x = 0.5 + sin(_idle_clock * 2.6 + float(get_instance_id() % 7)) * 0.07
		"wander":
			_wander(delta)
		_:
			move_with(Vector3.ZERO)
			model.loop("idle")

## A slow stroll: to the next patrol point (or a random spot near home), a pause, and on.
func _wander(delta: float) -> void:
	if _idle_wait > 0.0:
		_idle_wait -= delta
		move_with(Vector3.ZERO)
		model.loop("idle")
		return
	if _idle_goal == Vector3.ZERO:
		if not patrol.is_empty():
			_idle_goal = patrol[_patrol_index % patrol.size()]
			_patrol_index += 1
		else:
			var spot := Vector2.from_angle(randf() * TAU) * randf_range(1.0, idle_radius)
			_idle_goal = Nav.snap(self, home + Vector3(spot.x, 0.0, spot.y))
	var gap: float = Vector2(_idle_goal.x - global_position.x, _idle_goal.z - global_position.z).length()
	if gap < 0.9:
		_idle_goal = Vector3.ZERO
		_idle_wait = randf_range(1.5, 4.5) if patrol.is_empty() else randf_range(0.0, 1.5)
		return
	walk_to(_idle_goal, delta, 0.32, true, "walk" if has_clip("walk") else "")

# --- movement helpers shared by behaviours ------------------------------------------------

## Current walking speed, with slows and buffs applied.
func pace() -> float:
	return move_speed * speed_factor() * (ward_haste if ward_time > 0.0 else 1.0)

## Enemies run everywhere (the run clip, played faster or slower to suit their speed); "walk" is only a fallback.
const RUN_REF_SPEED := 4.0
const WALK_REF_SPEED := 1.3

func locomotion_clip() -> String:
	return "run" if has_clip("run") else "walk"

## Runs toward `point`, pathing around obstacles when it is far away, and drifting away from crowd-mates.
## `clip` is the clip to play while doing it (the strolling idle uses "walk"; asking for it here, not after, keeps the model from being told two
## different clips every frame, which left a strolling monster sliding along in a half-blended pose).
func walk_to(point: Vector3, delta: float, speed_mult: float = 1.0, use_nav: bool = true, clip: String = "") -> void:
	var dist: float = Vector2(point.x - global_position.x, point.z - global_position.z).length()
	var aim: Vector3 = point
	if use_nav and dist > 3.5:
		aim = Nav.next_point(self, point, _nav_state, delta, 0.5)
	var dir: Vector3 = aim - global_position
	dir.y = 0.0
	face(global_position + dir, 0.2)
	var speed: float = pace() * speed_mult
	move_with(dir.normalized() * speed + separation() * speed)
	if clip != "":
		model.loop(clip, clampf(speed / WALK_REF_SPEED, 0.6, 1.4))
	else:
		model.loop(locomotion_clip(), clampf(speed / RUN_REF_SPEED, 0.6, 1.8))

## Closes in on the target.
func advance_on_target(delta: float, dist: float) -> void:
	walk_to(target.global_position, delta, 1.0, dist > 3.5)

## Backs straight away from a point (keeping its face to the target) at `speed_mult` of its walking speed.
func back_away_from(point: Vector3, speed_mult: float = 1.0) -> void:
	_retreat_ms = Time.get_ticks_msec()
	var away: Vector3 = global_position - point
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	face(target.global_position, 0.25)
	var speed: float = pace() * speed_mult
	move_with(away * speed + separation() * speed * 0.5)
	model.loop(locomotion_clip(), 0.9)

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
		model.loop(locomotion_clip(), 0.75)
	else:
		model.loop("idle")

## Steers away from nearby enemies so a crowd spreads around the target instead of stacking.
func separation() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	var spacing: float = body_radius * 2.6
	var here: Vector3 = global_position
	var reach: int = int(ceil(spacing / GRID_CELL))
	var cell: Vector2i = Vector2i(floori(here.x / GRID_CELL), floori(here.z / GRID_CELL))
	for gx in range(cell.x - reach, cell.x + reach + 1):
		for gz in range(cell.y - reach, cell.y + reach + 1):
			for other: Enemy in _crowd_cell(get_tree(), Vector2i(gx, gz)):
				if other == self or other.dead:
					continue
				var away: Vector3 = here - other.global_position
				away.y = 0.0
				var d: float = away.length()
				if d > 0.001 and d < spacing:
					push += away / d * (spacing - d)
	return push.limit_length(1.0)

## Who stands where, binned once per physics tick: each monster only has to look at its neighbours, not at all of them (a world with
## two hundred monsters made that the single biggest cost of a fight).
const GRID_CELL := 2.0
static var _crowd: Dictionary = {}
static var _crowd_tick: int = -1
static var _no_one: Array = []

static func _crowd_cell(tree: SceneTree, cell: Vector2i) -> Array:
	var tick: int = Engine.get_physics_frames()
	if tick != _crowd_tick:
		_crowd_tick = tick
		_crowd.clear()
		for node in tree.get_nodes_in_group("enemies"):
			var other := node as Enemy
			if other == null or other.dead or other.dormant:
				continue
			var key := Vector2i(floori(other.global_position.x / GRID_CELL), floori(other.global_position.z / GRID_CELL))
			if not _crowd.has(key):
				_crowd[key] = []
			(_crowd[key] as Array).append(other)
	return _crowd.get(cell, _no_one)

# --- far away and asleep ---------------------------------------------------------------------------

## Asleep monsters this far from the hero (in metres) are not drawn and do nothing at all until he comes back within range: the world
## keeps every monster on the Crypt Road loaded, and running, animating and shadow-casting two hundred of them was most of the cost of
## standing anywhere in it. (The camera never shows anything near that far.)
const SLEEP_RANGE := 60.0
const WAKE_RANGE := 52.0
var dormant: bool = false
const FAR_THINK_RANGE := 28.0
var _far_skip: bool = false
var _far_delta: float = 0.0

func set_dormant(on: bool) -> void:
	if on == dormant or dead or _aggro:
		return
	dormant = on
	visible = not on
	set_physics_process(not on)
	if model != null and model.anim != null:
		model.anim.active = not on
	if on:
		velocity = Vector3.ZERO

## Whether this enemy's model has an animation by that name (new enemies may not have every clip yet).
func has_clip(clip: String) -> bool:
	return model != null and model.anim.has_animation("game/" + clip)

## Clear line (no wall or prop) to another actor, chest height to chest height.
func has_line_to(other: Actor) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), other.global_position + Vector3(0, 1.0, 0), LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

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
	await get_tree().create_timer(5.0).timeout
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(visual, "position:y", -body_height, 2.0)
	await tween.finished
	queue_free()
