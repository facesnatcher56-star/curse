class_name ShieldGuard
extends RefCounted
## Map mode only (issue #88): the warrior raises his shield and blocks every single projectile from his front while he closes in on a
## ranged attacker. ONE instance per Player (`Player.shield_guard`); every number lives in the constants below. Nothing here runs unless
## `MapMode.active` (Player ticks and filters behind that flag), so the default game is untouched.
##
## Raised while ALL hold:
##   1. a shield is worn (and the member is not an archer);
##   2. the current or focus target (`MapMode.target_for`) is a ranged attacker;
##   3. he is closing in: walking toward it and not yet in melee range;
##   4. nothing but single projectiles can hit him now: no melee attacker on him, no AoE or explosive coming, no power or swing running.
## Raised, he blocks 100% of the single (non-AoE) projectiles arriving inside ARC_DEG in front of him (no damage, no knock-back, a ring
## and a spark, the shield Opening roll). AoE and explosives (results flagged "aoe", or not flagged "projectile" at all) are never
## auto-blocked; shots from behind or the side keep Combat's normal random block chance. Lowered the same frame a condition fails.

const ARC_DEG := 120.0               # the front arc that is guarded (centred on where he faces)
const UP_TIME := 0.15                # s, shield fully down -> fully up (and back)
const MIN_BLOCK_AMOUNT := 0.5        # the shield counts as up for blocking once this far raised
const MELEE_THREAT_RANGE := 3.2      # m (edge to edge): an awake non-ranged enemy this close counts as a melee attacker on him
const AOE_MARGIN := 1.8              # m: an AoE marker (acid, ground tell, Volatile ring) within radius + this of him counts as incoming
const BLOATER_RANGE := 7.0           # m: a fusing Bloater this close is an explosive about to go off
const CLOSING_SPEED := 0.5           # m/s he must be moving
const CLOSING_DOT := 0.2             # cos of the angle between his velocity and the target direction (about 78 degrees)
const CLOSING_GRACE := 0.25          # s the "closing in" condition may fail (a path corner, a step) before the shield drops
const SPARK_COLOR := Color(1.0, 0.92, 0.6)
const AOE_GROUPS: Array[String] = [GroundTell.GROUP, "aoe_tells"]   # markers with a world position and a "radius" (GroundTell.radius / meta)

var p: Player
var up: bool = false          # the guard is wanted (blocking follows this at once)
var amount: float = 0.0       # 0..1 raise of the pose, ramped over UP_TIME
var blocked: int = 0          # shots this guard has caught
var _grace: float = 0.0
var _target: Actor
var _target_ok: bool = false

func _init(player: Player) -> void:
	p = player

func blocking() -> bool:
	return up and amount >= MIN_BLOCK_AMOUNT

## Per physics frame (map mode only).
func tick(delta: float) -> void:
	_grace = CLOSING_GRACE if wants_up() and _closing_in(_target) else maxf(_grace - delta, 0.0)
	up = _grace > 0.0 and _target_ok
	amount = move_toward(amount, 1.0 if up else 0.0, delta / UP_TIME)
	if p.model != null:
		p.model.guard_amount = amount

## Every condition except "closing in" (which gets a short grace in tick()).
func wants_up() -> bool:
	_target_ok = false
	_target = null
	if p.dead or p.stun_time > 0.0 or p.knockdown.active() or p.is_ragdolled() or p.movement.rolling or p.skills.busy:
		return false
	if not p.stats.equipment.has(Items.Slot.SHIELD) or p.stats.is_ranged():
		return false
	if MapMode.current == null or MapMode.current.state != MapMode.State.FIGHT:
		return false
	_target = MapMode.current.target_for(p)
	if not is_ranged_attacker(_target) or in_melee_range(_target):
		return false
	_target_ok = not melee_attacker_on_me() and not aoe_incoming()
	return _target_ok

# --- the conditions -----------------------------------------------------------------------------------------------------------------

## An enemy whose attacks are projectiles (the spitter family: rock thrower, spitter).
static func is_ranged_attacker(a: Actor) -> bool:
	var e := a as Enemy
	return e != null and not e.dead and e.behavior is SpitterBehavior

func in_melee_range(target: Actor) -> bool:
	return p.flat_distance_to(target) - target.body_radius <= float(SkillDb.all()["basic"]["range"])

func _closing_in(target: Actor) -> bool:
	if target == null:
		return false
	var v := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var to_target: Vector3 = target.global_position - p.global_position
	to_target.y = 0.0
	if v.length() < CLOSING_SPEED or to_target.length() < 0.01:
		return false
	return v.normalized().dot(to_target.normalized()) >= CLOSING_DOT

## Any awake enemy that is not a ranged attacker and is close enough to be hitting him.
func melee_attacker_on_me() -> bool:
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead or not e.is_aggro() or is_ranged_attacker(e):
			continue
		if p.flat_distance_to(e) - e.body_radius <= MELEE_THREAT_RANGE:
			return true
	return false

## An acid glob landing near him, a ground tell or a Volatile ring over him, a Bloater about to burst.
func aoe_incoming() -> bool:
	var here := Vector2(p.global_position.x, p.global_position.z)
	for node in p.get_tree().get_nodes_in_group("acid_globs"):
		var glob := node as AcidGlob
		if glob != null and here.distance_to(Vector2(glob.to_pos.x, glob.to_pos.z)) <= glob.splash_radius + AOE_MARGIN:
			return true
	for group in AOE_GROUPS:
		for node in p.get_tree().get_nodes_in_group(group):
			var n3 := node as Node3D
			if n3 == null:
				continue
			var radius: float = float(n3.get_meta("aoe_radius")) if n3.has_meta("aoe_radius") else float(n3.get("radius"))
			if here.distance_to(Vector2(n3.global_position.x, n3.global_position.z)) <= radius + AOE_MARGIN:
				return true
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and not e.dead and e.behavior is BloaterBehavior and e.behavior.is_attacking() \
				and p.flat_distance_to(e) <= BLOATER_RANGE:
			return true
	return false

# --- the block ----------------------------------------------------------------------------------------------------------------------

## Player._filter_incoming: turns a single projectile from the front into a block (damage 0, flagged "guard" so nobody is shoved).
func filter(result: Dictionary) -> Dictionary:
	if not blocking() or not bool(result.get("projectile", false)) or bool(result.get("aoe", false)):
		return result
	if int(result.get("outcome", Combat.Outcome.HIT)) < Combat.Outcome.HIT:
		return result   # already dodged or blocked the normal way
	if not from_front(result):
		return result   # behind or beside him: the normal random chance already rolled in Combat.resolve
	result["outcome"] = Combat.Outcome.BLOCK
	result["damage"] = 0.0
	result["guard"] = true
	blocked += 1
	if MapMode.current != null:
		MapMode.current.log.note_guard_block()
	_spark(result)
	return result

## True when the shot's flight direction runs into the face of the guard (within half of ARC_DEG of where he faces).
func from_front(result: Dictionary) -> bool:
	var dir: Vector3 = result.get("shot_dir", Vector3.ZERO)
	dir.y = 0.0
	if dir.length() < 0.001:
		return false
	var facing := Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	return facing.angle_to(-dir.normalized()) <= deg_to_rad(ARC_DEG) * 0.5

func _spark(result: Dictionary) -> void:
	var dir: Vector3 = result.get("shot_dir", Vector3.FORWARD)
	var facing := Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	var at: Vector3 = p.global_position + facing * (p.body_radius + 0.25) + Vector3(0, p.body_height * 0.6, 0)
	Fx.burst(p, at, -dir.normalized() + Vector3.UP * 0.3, SPARK_COLOR, 8, 5.0, 0.025, true)
	Fx.light_flash(p, at, SPARK_COLOR, 1.6, 0.1)
