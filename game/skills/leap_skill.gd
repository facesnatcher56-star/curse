class_name LeapSkill
extends RefCounted
## Leap: spring at the cursor; slam a downed enemy through the ground, or chop on open ground.

var p: Player

func _init(player: Player) -> void:
	p = player

# --- Leap ------------------------------------------------------------------------------
# Spring at the cursor. Onto a downed enemy: land with the blade driven straight down through it into the ground,
# plant a boot on it and wrench the sword free. Onto open ground (or standing enemies): a two-handed overhead chop.

const LEAP_WINDUP := 0.2
const LEAP_SLAM_HOLD := 0.25     # (halved: the recovery after landing on a downed enemy was too long)
const LEAP_PULL_TIME := 0.5
const LEAP_SLAM_MULT := 3.6
const LEAP_CHOP_MULT := 1.3
const LEAP_CHOP_RADIUS := 2.3
const LEAP_PIN_TIME := 1.0
const LEAP_SLAM_REACH := 0.5      # landing spot sits this far short of the victim: the blade comes down in front of the knight
const LEAP_CHOP_RECOVER := 0.6
# Key times in the "leap" clip (Meshy Basic_Jump): crouch, take-off, plunge landing, then the rise that pulls the blade up.
const LEAP_CLIP_CROUCH := 1.4
const LEAP_CLIP_TAKEOFF := 1.68
const LEAP_CLIP_LAND := 2.5
const LEAP_CLIP_PULL_START := 2.95
const LEAP_CLIP_END := 3.9
var leap_phase: int = 0  # 0 off, 1 crouch, 2 airborne, 3 slam hold / chop recovery, 4 boot + pull-out
var leap_t: float = 0.0
var leap_from: Vector3 = Vector3.ZERO
var leap_to: Vector3 = Vector3.ZERO
var leap_air_time: float = 0.5
var leap_victim: Actor = null
var leap_dir: Vector3 = Vector3.FORWARD
var leap_slam: bool = false
var _leap_pulled: bool = false
## A knocked-down enemy (lying or getting up) is the slam target.
static func is_downed(e: Actor) -> bool:
	if e == null or e.dead or e.impaled or not e.is_ragdolled():
		return false
	return e.ragdoll.state != Ragdoll.State.HANG   # thrown, lying or getting up: anything not fully on its feet

func _downed_near(point: Vector3, radius: float) -> Actor:
	var best: Actor = null
	var best_d: float = radius
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if not is_downed(e):
			continue
		var d: float = Vector2(e.global_position.x - point.x, e.global_position.z - point.z).length()
		if d < best_d:
			best_d = d
			best = e
	return best

func start_leap(cursor: Vector3) -> void:
	if p.dead or p.skills.busy or not p.stats.can_use("leap") or not p.skills.weapon_ready("leap"):
		return
	var skill: Dictionary = SkillDb.all()["leap"]
	var running: bool = Vector2(p.velocity.x, p.velocity.z).length() > SkewerSkill.RUNNING_START   # already running: spring straight off, no crouch
	var reach: Vector3 = p.skills.aim_point_for("leap", cursor)
	leap_victim = _downed_near(cursor, 3.2)
	leap_slam = leap_victim != null
	var dest: Vector3 = reach
	if leap_victim != null:
		var away: Vector3 = p.global_position - leap_victim.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.BACK
		dest = leap_victim.global_position + away * LEAP_SLAM_REACH  # the blade comes down in front of the knight
		var offset: Vector3 = dest - p.global_position
		offset.y = 0.0
		if offset.length() > float(skill["range"]):
			dest = p.global_position + offset.normalized() * float(skill["range"])
			leap_victim = null   # too far to land on it; still a decent chop at the spot
			leap_slam = false
	dest = Nav.snap(p, Vector3(dest.x, 0.0, dest.z))
	dest.y = 0.0
	leap_from = p.global_position
	leap_to = dest
	var flat: Vector3 = dest - p.global_position
	flat.y = 0.0
	leap_dir = flat.normalized() if flat.length() > 0.2 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	leap_air_time = clampf(0.36 + flat.length() * 0.035, 0.4, 0.75)
	p.stats.mana -= float(skill["mana"])
	p.stats.cooldowns["leap"] = float(skill["cd"])
	p.skills.clear_aim()
	p.skills.busy = true
	p.skills.busy_skill = "leap"
	p.skills.busy_def = skill
	p.skills.busy_target = null
	p.skills.busy_t = 0.0
	p.skills.busy_hit_done = false
	p.combat_timer = 5.0
	p.movement.has_goal = false
	p.skills.queued_skill = ""
	p.attack_target = null
	p.click_mode = 0
	leap_phase = 1
	leap_t = 0.0
	_leap_pulled = false
	p.collision_mask = Actor.LAYER_WORLD   # sail over the crowd; the landing decides who is hit
	p.visual.rotation.y = atan2(leap_dir.x, leap_dir.z)
	p.model.manual("leap")
	p.model.scrub(LEAP_CLIP_CROUCH)
	if running:
		leap_phase = 2
		p.model.scrub(LEAP_CLIP_TAKEOFF)
		Fx.burst(p, p.global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 12, 3.5, 0.04)
		Fx.punch(p, 1.6)
	if p._trail != null:
		p._trail.active = false
	Fx.ring(p, p.global_position, 1.4, Color(0.9, 0.85, 0.7))

func tick_leap(delta: float) -> void:
	leap_t += delta
	# Committed at take-off: once the knight is committed to a slam, the victim getting up or dying does not change it.
	var slam: bool = leap_slam and leap_victim != null and is_instance_valid(leap_victim)
	match leap_phase:
		1:
			var u: float = clampf(leap_t / LEAP_WINDUP, 0.0, 1.0)
			p.model.scrub(lerpf(LEAP_CLIP_CROUCH, LEAP_CLIP_TAKEOFF, u))
			p.move_with(Vector3.ZERO)
			if leap_t >= LEAP_WINDUP:
				leap_phase = 2
				leap_t = 0.0
				Fx.burst(p, p.global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 12, 3.5, 0.04)
				Fx.punch(p, 1.6)
		2:
			var u: float = clampf(leap_t / leap_air_time, 0.0, 1.0)
			# Anything breakable under the flight path is smashed as the hero sails through.
			Destructible.blast(p.get_tree(), p.global_position, 1.2, 999.0, leap_dir, 2.2)
			if slam:
				# Track the target while airborne (it may still be tumbling or scrambling up).
				var spot: Vector3 = leap_victim.global_position - leap_dir * LEAP_SLAM_REACH
				leap_to = Vector3(spot.x, 0.0, spot.z)
			var ground: Vector3 = leap_from.lerp(leap_to, u)
			p.global_position = Vector3(ground.x, 0.0, ground.z)
			# The clip carries the whole jump: blade raised overhead, then the plunge down in front.
			p.model.scrub(lerpf(LEAP_CLIP_TAKEOFF, LEAP_CLIP_LAND, u))
			if u >= 1.0:
				_leap_land(slam)
		3:
			p.move_with(Vector3.ZERO)
			if slam:
				var u: float = clampf(leap_t / LEAP_SLAM_HOLD, 0.0, 1.0)
				p.model.scrub(lerpf(LEAP_CLIP_LAND, LEAP_CLIP_PULL_START, u))   # crouched over the planted blade
				if leap_victim != null and is_instance_valid(leap_victim) and leap_victim.ragdoll != null:
					leap_victim.ragdoll.pin(0.3)
				if u >= 1.0:
					leap_phase = 4
					leap_t = 0.0
					_leap_pulled = false
			else:
				var u: float = clampf(leap_t / LEAP_CHOP_RECOVER, 0.0, 1.0)
				p.model.scrub(lerpf(LEAP_CLIP_LAND, LEAP_CLIP_END, u))
				if u >= 1.0:
					end_leap()
		4:
			# Boot up onto the body, then rise and wrench the blade out of the ground (the clip's own rise).
			p.move_with(Vector3.ZERO)
			var u: float = clampf(leap_t / LEAP_PULL_TIME, 0.0, 1.0)
			p.model.scrub(lerpf(LEAP_CLIP_PULL_START, LEAP_CLIP_END, smoothstep(0.0, 1.0, u)))
			p.model.leg_raise = smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.8, 1.0, u))
			if leap_victim != null and is_instance_valid(leap_victim) and leap_victim.ragdoll != null:
				leap_victim.ragdoll.pin(0.3)   # held down under the boot
			if not _leap_pulled and u >= 0.5:
				_leap_pulled = true
				if p.model.weapon_tip != null:
					Fx.burst(p, p.model.weapon_tip.global_position, Vector3.UP + leap_dir * -0.3, Color(0.6, 0.04, 0.04), 18, 5.0, 0.03)
				Fx.burst(p, leap_to + leap_dir * LEAP_SLAM_REACH + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 8, 2.5, 0.04)
				Fx.shake(p, 0.1)
				Fx.punch(p, 1.2)
			if u >= 1.0:
				end_leap()

func _leap_land(slam: bool) -> void:
	if slam and leap_victim.dead:
		slam = false         # it died in mid-air; nothing left to pin, so this lands as a plain chop
		leap_slam = false
	p.global_position = Vector3(leap_to.x, 0.0, leap_to.z)
	p.reset_physics_interpolation()
	leap_phase = 3
	leap_t = 0.0
	Sfx.sample(p, "leap_land", -3.0, 1.0)   # the heavy touchdown, slam or chop
	Destructible.blast(p.get_tree(), p.global_position, 3.2, 999.0, leap_dir, 2.0)
	ItemEffects.on_leap_land(p)
	if slam:
		p.model.scrub(LEAP_CLIP_LAND)
		var damage: float = p.stats.weapon_damage(LEAP_SLAM_MULT) * ItemEffects.outgoing_multiplier(p, leap_victim)
		var result: Dictionary = Combat.resolve(p, leap_victim, damage, Combat.DamageType.PHYSICAL, false, 2.4, true)
		result["skill_id"] = "leap"
		leap_victim.receive(result, p.global_position)
		if is_instance_valid(leap_victim) and not leap_victim.dead:
			leap_victim.stun_time = maxf(leap_victim.stun_time, LEAP_PIN_TIME)
			if leap_victim.ragdoll != null:
				leap_victim.ragdoll.pin(LEAP_SLAM_HOLD + LEAP_PULL_TIME)
		var tip: Vector3 = leap_victim.global_position + Vector3(0, 0.2, 0) if is_instance_valid(leap_victim) else leap_to
		Fx.burst(p, tip, Vector3.UP, Color(0.6, 0.04, 0.04), 26, 6.0, 0.03)
		Fx.burst(p, leap_to + leap_dir * 0.5 + Vector3(0, 0.05, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 18, 4.0, 0.05)
		Fx.ring(p, leap_to, 2.4, Color(1.0, 0.85, 0.55))
		Fx.text_at(p, tip + Vector3(0, 1.3, 0), "Impaled!", Color(1.0, 0.8, 0.5), 52)
		p.skills.blade_blood = minf(p.skills.blade_blood + 0.5, 1.0)
		Fx.shake(p, 0.3)
		Fx.punch(p, 3.4)
		Fx.hitstop(p, 0.08)
	else:
		p.model.scrub(LEAP_CLIP_LAND)
		var hit_any: bool = false
		for node in p.get_tree().get_nodes_in_group("enemies"):
			var e := node as Actor
			if e == null or e.dead or e.impaled:
				continue
			if p.flat_distance_to(e) - e.body_radius > LEAP_CHOP_RADIUS:
				continue
			var chop: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(LEAP_CHOP_MULT) * ItemEffects.outgoing_multiplier(p, e),
				Combat.DamageType.PHYSICAL, true, 1.8)
			chop["skill_id"] = "leap"
			e.receive(chop, p.global_position)
			hit_any = true
		Fx.burst(p, p.global_position + leap_dir * 1.0 + Vector3(0, 0.05, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 20, 4.0, 0.05)
		Fx.ring(p, p.global_position + leap_dir * 0.8, 2.6, Color(0.9, 0.85, 0.7))
		Fx.shake(p, 0.22 if hit_any else 0.12)
		Fx.punch(p, 2.6)
		if hit_any:
			Fx.hitstop(p, 0.06)
		else:
			Sfx.sword_miss(p)   # the chop landed on bare ground

func end_leap(restore_pose: bool = true) -> void:
	if leap_victim != null and is_instance_valid(leap_victim) and leap_victim.ragdoll != null:
		leap_victim.ragdoll.release_pin()
	leap_victim = null
	leap_phase = 0
	p.skills.busy = false
	p.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ENEMY
	if not restore_pose:
		return
	p.model.leg_raise = 0.0
	p.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ENEMY
	p.visual.rotation.x = 0.0
	if p._trail != null:
		p._trail.active = false
	p.model.loop("idle_alert")
