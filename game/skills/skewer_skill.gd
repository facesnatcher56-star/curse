class_name SkewerSkill
extends RefCounted
## Skewer: charge, run up to three enemies onto the blade, skid to a halt, then boot them all off.

var p: Player

func _init(player: Player) -> void:
	p = player

# Aimed skills (Fireball): hold the key to aim, release to cast. The preview shows the blast sphere.
# Skewer state
var skewer_phase: int = 0  # 0 off, 1 wind-up, 2 charge, 3 skid, 4 kick, 5 recover
var skewer_t: float = 0.0
var skewer_dir: Vector3 = Vector3.FORWARD
var skewer_travel: float = 0.0
var skewer_full_at: float = -1.0
var skewer_kicked: bool = false
var skewer_impaled: Array[Actor] = []
var _skewer_tick_clock: float = 0.0
var _skewer_dust: float = 0.0
var big_hit: Dictionary = {}   # enemies already staggered by this charge
# --- Skewer ---------------------------------------------------------------------------

const SKEWER_SPEED := 15.0
const SKEWER_SLOTS: Array[float] = [1.0, 1.4, 1.8]  # distance ahead of the hero along the blade, hilt first
const SKEWER_BIG_BONUS := 45.0   # flat extra damage against enemies too big to impale
const SKEWER_BIG_STUN := 1.6     # they are staggered this long, so they cannot hit back
const RAM_BIG_STUN_MULT := 2.5   # Ramming: the ones too big to move are stunned this much longer
const SKEWER_WINDUP := 0.28
const SKEWER_SKID := 0.24
const SKEWER_KICK_TIME := 0.55
const KICK_START := 0.15
const KICK_STRIKE := 0.6
const KICK_END := 1.1
func start_skewer(cursor: Vector3) -> void:
	var skill: Dictionary = SkillDb.all()["skewer"]
	var dir: Vector3 = cursor - p.global_position
	dir.y = 0.0
	if dir.length() < 0.4:
		dir = Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	skewer_dir = dir.normalized()
	p.stats.mana -= float(skill["mana"])
	p.stats.cooldowns["skewer"] = float(skill["cd"])
	p.skills.clear_aim()
	p.skills.busy = true
	p.skills.busy_skill = "skewer"
	p.skills.busy_def = skill
	p.skills.busy_target = null
	p.skills.busy_t = 0.0
	p.skills.busy_hit_done = false
	p.combat_timer = 5.0
	p.movement.has_goal = false
	p.skills.queued_skill = ""
	p.attack_target = null
	p.click_mode = 0
	skewer_phase = 1
	skewer_t = 0.0
	skewer_travel = 0.0
	skewer_full_at = -1.0
	skewer_kicked = false
	skewer_impaled.clear()
	p.movement.shoved.clear()
	big_hit.clear()
	p.movement.roll_dir = skewer_dir  # lets the roll's shove logic push bystanders out of the lane
	p.collision_mask = Actor.LAYER_WORLD  # run through the crowd; only the blade catches anyone
	p.visual.rotation.y = atan2(skewer_dir.x, skewer_dir.z)
	p.model.loop("charge_run", 0.6)
	p.model.weapon_aim = skewer_dir          # the animation carries the blade diagonally; aim it down the charge instead
	p.model.weapon_length_mult = 1.45        # long enough to carry three
	if p._trail != null:
		p._trail.active = false  # at charge speed the blade ribbon becomes a huge sheet; the impaled enemies sell it instead
	Fx.ring(p, p.global_position, 1.6, Color(0.8, 0.85, 1.0))

func tick_skewer(delta: float) -> void:
	skewer_t += delta
	var skill: Dictionary = p.skills.busy_def
	match skewer_phase:
		1:
			# Wind-up: sink low behind the blade, then drive off.
			var u: float = clampf(skewer_t / SKEWER_WINDUP, 0.0, 1.0)
			p.visual.rotation.x = lerpf(0.0, -0.12, u)
			p.move_with(Vector3.ZERO)
			if skewer_t >= SKEWER_WINDUP:
				skewer_phase = 2
				skewer_t = 0.0
				p.model.loop("charge_run", 1.5)
				Fx.punch(p, 1.8)
				Fx.shake(p, 0.1)
		2:
			var ramp: float = clampf(0.25 + skewer_t / 0.3, 0.25, 1.0)
			var speed: float = SKEWER_SPEED * ramp
			var before: Vector3 = p.global_position
			p.move_with(skewer_dir * speed)
			var moved: float = before.distance_to(p.global_position)
			skewer_travel += moved
			# Everything breakable in the way is smashed apart and thrown ahead of the charge.
			Destructible.blast(p.get_tree(), p.global_position + skewer_dir * 0.7, 1.3, 999.0, skewer_dir, 2.5)
			p.visual.rotation.y = atan2(skewer_dir.x, skewer_dir.z)
			p.visual.rotation.x = 0.24
			_skewer_dust += delta
			if _skewer_dust > 0.05:
				_skewer_dust = 0.0
				Fx.burst(p, p.global_position + Vector3(0, 0.1, 0), -skewer_dir + Vector3.UP * 0.5, Color(0.5, 0.45, 0.38), 3, 2.5, 0.04)
			Fx.shake(p, 0.02)
			if p.skills.blade_blood > 0.3 and p.model.weapon_tip != null:
				Fx.burst(p, p.model.weapon_tip.global_position, Vector3.DOWN + skewer_dir * -0.5, Color(0.55, 0.04, 0.04), 2, 1.5, 0.025)
			_skewer_catch_enemies(skill)
			p.movement.shove_enemies(delta)
			_carry_impaled(delta)
			var blocked: bool = skewer_t > 0.2 and moved < speed * delta * 0.35
			if skewer_impaled.size() >= 3 and skewer_full_at < 0.0:
				skewer_full_at = skewer_t
			var full_run_done: bool = skewer_full_at >= 0.0 and skewer_t - skewer_full_at > 0.3
			if skewer_travel >= float(skill["range"]) or blocked or full_run_done:
				skewer_phase = 3
				skewer_t = 0.0
				p.model.loop("charge_run", 0.5)
		3:
			# Skid to a stop: plant the feet, carry the momentum.
			var u: float = clampf(skewer_t / SKEWER_SKID, 0.0, 1.0)
			p.move_with(skewer_dir * SKEWER_SPEED * 0.55 * pow(1.0 - u, 2.0))
			p.visual.rotation.x = lerpf(0.24, 0.05, u)
			_carry_impaled(delta)
			if u >= 1.0 or skewer_t >= SKEWER_SKID:
				skewer_t = 0.0
				if skewer_impaled.is_empty():
					skewer_phase = 5
					p.model.loop("idle_alert")
				else:
					skewer_phase = 4
					skewer_kicked = false
					p.model.manual("kick")
					p.model.scrub(KICK_START)
					Fx.ring(p, p.global_position, 2.2, Color(1.0, 0.9, 0.6))
		4:
			var u: float = clampf(skewer_t / SKEWER_KICK_TIME, 0.0, 1.0)
			var hit_frac: float = (KICK_STRIKE - KICK_START) / (KICK_END - KICK_START)
			p.model.scrub(CharacterModel.remap(u, hit_frac, KICK_START, KICK_STRIKE, KICK_END))
			p.move_with(Vector3.ZERO)
			p.visual.rotation.x = -0.12 * sin(clampf(u / hit_frac, 0.0, 1.0) * PI * 0.5) if u < hit_frac else 0.12 * (1.0 - u)
			if u < hit_frac:
				_carry_impaled(delta)
			if not skewer_kicked and u >= hit_frac:
				skewer_kicked = true
				p.model.weapon_aim = null  # blade relaxes once the pile is booted off
				_skewer_kick()
			if u >= 1.0:
				skewer_phase = 5
				skewer_t = 0.0
		5:
			p.move_with(Vector3.ZERO)
			p.visual.rotation.x = lerpf(p.visual.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
			if skewer_t >= 0.22:
				end_skewer()

## Runs the nearest enemies in the lane onto the blade. Returns true if a boss stops the charge.
func _skewer_catch_enemies(skill: Dictionary) -> bool:
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		# Knocked-down enemies (lying or getting up) are still fair game; only ones already on the blade are skipped.
		if e == null or e.dead or e.impaled or (e.is_ragdolled() and e.ragdoll.state == Ragdoll.State.FLIGHT):
			continue
		var rel: Vector3 = e.global_position - p.global_position
		rel.y = 0.0
		var ahead: float = rel.dot(skewer_dir)
		var across: float = absf(rel.cross(skewer_dir).y)
		if ahead < 0.2 or ahead > 1.6 or across > 0.75 + e.body_radius * 0.6:
			continue
		if not e.can_be_impaled():
			# Too big (or a boss): cannot be spitted. It takes a flat chunk of extra damage and is staggered
			# so it cannot hit back, and the charge carries on past it.
			if big_hit.has(e.get_instance_id()):
				continue
			big_hit[e.get_instance_id()] = true
			var damage: float = p.stats.weapon_damage(float(skill["mult"])) * ItemEffects.outgoing_multiplier(p, e) + SKEWER_BIG_BONUS
			var slam: Dictionary = Combat.resolve(p, e, damage, Combat.DamageType.PHYSICAL, false, 3.0)
			slam["skill_id"] = "skewer"
			e.receive(slam, p.global_position)
			var rammed: bool = p.stats.has_affix("charger")
			e.stun_time = maxf(e.stun_time, SKEWER_BIG_STUN * (RAM_BIG_STUN_MULT if rammed else 1.0))  # forced, even for bosses
			Fx.text_at(p, e.global_position + Vector3(0, e.body_height + 0.7, 0), "Stunned" if rammed else "Staggered", Color(1.0, 0.9, 0.5), 46)
			Fx.ring(p, e.global_position, 2.4, Color(1.0, 0.85, 0.5))
			Fx.punch(p, 2.6)
			Fx.shake(p, 0.2)
			p.skills.blade_blood = minf(p.skills.blade_blood + 0.2, 1.0)
			continue
		if skewer_impaled.size() >= 3:
			# The blade is full. With Ramming whoever else is in the lane is knocked down and thrown aside, once, instead of ignored.
			if p.stats.has_affix("charger") and not big_hit.has(e.get_instance_id()):
				big_hit[e.get_instance_id()] = true
				_ram_aside(e, skill)
			continue
		e.set_impaled(true)
		e.ragdoll_hang(atan2(-skewer_dir.x, -skewer_dir.z))
		skewer_impaled.append(e)
		var stab: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(float(skill["mult"])) * ItemEffects.outgoing_multiplier(p, e),
			Combat.DamageType.PHYSICAL, false, 2.0)
		stab["skill_id"] = "skewer"
		stab["damage"] = minf(float(stab["damage"]), maxf(e.health - 1.0, 0.0))  # leave them alive for the kick
		e.receive(stab, p.global_position)
		p.skills.blade_blood = minf(p.skills.blade_blood + 0.4, 1.0)
		Fx.text_at(p, e.global_position + Vector3(0, e.body_height + 0.7, 0), "Impaled", Color(1.0, 0.8, 0.55), 44)
		Fx.burst(p, e.global_position + Vector3(0, 1.1, 0), skewer_dir + Vector3.UP * 0.3, Color(0.6, 0.04, 0.04), 16, 5.0)
		Fx.punch(p, 2.0)
		Fx.shake(p, 0.12)
	return false

## Ramming: an enemy the blade could not take is hit by the shoulder of the charge, knocked down and thrown out of the lane.
func _ram_aside(e: Actor, skill: Dictionary) -> void:
	var rel: Vector3 = e.global_position - p.global_position
	rel.y = 0.0
	var lateral: Vector3 = rel - skewer_dir * rel.dot(skewer_dir)
	if lateral.length() < 0.1:
		lateral = skewer_dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	lateral = lateral.normalized()
	var shove: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(float(skill["mult"])) * 0.6 * ItemEffects.outgoing_multiplier(p, e),
		Combat.DamageType.PHYSICAL, false, 2.0)
	shove["skill_id"] = "skewer"
	shove["secondary"] = true
	e.receive(shove, p.global_position)
	if is_instance_valid(e) and not e.dead:
		var away: Vector3 = (skewer_dir * 0.5 + lateral).normalized()
		e.ragdoll_launch(away * 10.0, 4.5, lateral.cross(Vector3.UP) * randf_range(6.0, 10.0))
		e.interrupt(1.0)
	Fx.text_at(p, e.global_position + Vector3(0, e.body_height + 0.7, 0), "Knocked aside", Color(1.0, 0.9, 0.5), 40)
	Fx.punch(p, 1.6)

## Keeps skewered enemies pinned along the blade, hilt first, and bleeds them a little as they ride.
func _carry_impaled(delta: float) -> void:
	_skewer_tick_clock += delta
	var tick: bool = false
	if _skewer_tick_clock >= 0.25:
		_skewer_tick_clock = 0.0
		tick = true
	for i in range(skewer_impaled.size() - 1, -1, -1):
		if not is_instance_valid(skewer_impaled[i]):
			skewer_impaled.remove_at(i)  # a dead enemy stays on the blade and is still kicked off
	for i in skewer_impaled.size():
		var e: Actor = skewer_impaled[i]
		var pos: Vector3 = p.global_position + skewer_dir * SKEWER_SLOTS[i]
		e.global_position = Vector3(pos.x, 0.3, pos.z)
		e.reset_physics_interpolation()
		if e.ragdoll != null:
			e.ragdoll.yaw = atan2(-skewer_dir.x, -skewer_dir.z)  # facing the knight, blade through the chest
		if tick and not e.dead and e.health > 1.0:
			var ride: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(0.25), Combat.DamageType.PHYSICAL, false, 0.4)
			ride["secondary"] = true
			ride["quiet"] = true  # damage only: no popup, flinch or sound for the bleed ticks
			# The bleed alone never finishes them; the kick does.
			ride["damage"] = minf(float(ride["damage"]), maxf(e.health - 1.0, 0.0))
			e.receive(ride, p.global_position)

## The finish: a boot to the pile throws every impaled enemy off the sword and away, in a fan.
func _skewer_kick() -> void:
	var count: int = skewer_impaled.size()
	var angles: Array[float] = [0.0]
	if count == 2:
		angles = [-0.3, 0.3]
	elif count >= 3:
		angles = [-0.5, 0.0, 0.5]
	var skill: Dictionary = p.skills.busy_def
	for i in count:
		var e: Actor = skewer_impaled[i]
		if not is_instance_valid(e):
			continue
		e.set_impaled(false)
		var away: Vector3 = skewer_dir.rotated(Vector3.UP, angles[i])
		if not e.dead:
			var boot: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(float(skill["mult"]) * 1.2), Combat.DamageType.PHYSICAL, false, 3.2)
			boot["skill_id"] = "skewer_kick"
			e.receive(boot, p.global_position)
		if is_instance_valid(e):
			# Thrown like a sack (alive or not): fast over the ground, lofted, end-over-end.
			var spin: Vector3 = away.cross(Vector3.UP) * randf_range(7.0, 11.0) + Vector3.UP * randf_range(-3.0, 3.0)
			e.ragdoll_launch(away * 12.0, 6.5, spin)
		Fx.burst(p, e.global_position + Vector3(0, 1.0, 0), away + Vector3.UP * 0.4, Color(0.6, 0.05, 0.04), 20, 7.0)
		if p.stats.has_affix("impaler"):
			var fallback: Vector3 = p.global_position + away * 8.0
			var victim: Actor = e
			p.get_tree().create_timer(0.85).timeout.connect(func() -> void: ItemEffects.impaler_burst(p, victim, fallback))
	p.skills.blade_blood = minf(p.skills.blade_blood + 0.3, 1.0)
	skewer_impaled.clear()
	Fx.ring(p, p.global_position + skewer_dir * 1.3, 3.0, Color(1.0, 0.85, 0.5))
	Fx.shake(p, 0.3)
	Fx.punch(p, 3.8)
	Fx.hitstop(p, 0.09)
	Fx.slowmo(p, 0.2, 0.4, 0.5)   # the boot lands and the pile flies off the blade in slow motion
func end_skewer() -> void:
	for e in skewer_impaled:
		if is_instance_valid(e):
			e.set_impaled(false)
			e.ragdoll_launch(skewer_dir * 3.0, 2.0, skewer_dir.cross(Vector3.UP) * 4.0)
	skewer_impaled.clear()
	skewer_phase = 0
	p.skills.busy = false
	p.model.weapon_aim = null
	p.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ENEMY
	p.visual.rotation.x = 0.0
	if p._trail != null:
		p._trail.active = false
	p.model.loop("idle_alert")
