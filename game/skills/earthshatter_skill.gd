class_name EarthshatterSkill
extends RefCounted
## Earthshatter, the ultimate: raise the blade overhead, drive it into the ground, and the earth bursts outward. Everything in
## the shockwave is hurled into the air (hardest near the centre), stunned, and slams back down in slow motion; anything that
## hits a wall on the way takes the usual wall-slam damage. Debuffs on any victim (burn, bleed, chill) are shared with all
## the others. Bosses are not thrown but are staggered and take the damage.
##
## It has no mana cost or cooldown: it charges from damage the hero deals (PlayerStats.ult_charge).

var p: Player

func _init(player: Player) -> void:
	p = player

const RAISE_TIME := 0.42         # arms swing up (clip 0 -> OVERHEAD_REACHED), brisk and even: it must not read as slow motion
const HOLD_OVERHEAD := 0.22      # blade held up, nearly still
const GATHER_TIME := RAISE_TIME + HOLD_OVERHEAD
const SLAM_TIME := 0.16
const HOLD_TIME := 0.45
const RECOVER_TIME := 0.4
const MULT := 3.2
const RADIUS := 7.5
const MIN_FALLOFF := 0.55          # damage at the very edge relative to the centre
const LAUNCH_LIFT := 11.0          # upward speed at the centre
const LAUNCH_OUT := 8.0            # outward speed at the centre
const STUN_TIME := 2.6
const BOSS_STUN := 1.6
# Key times in the "earthshatter" clip (Meshy Charged_Ground_Slam): arms up, blade overhead and held, the plunge, kneeling, rising.
const CLIP_START := 0.0
const CLIP_OVERHEAD := 1.38
const CLIP_ARMS_UP := 0.55       # the clip has the arms fully raised here and then holds the pose until 1.38
const CLIP_IMPACT := 1.93
const CLIP_HOLD_END := 2.48
const CLIP_END := 3.03

var phase: int = 0   # 0 off, 1 gather, 2 slam, 3 hold, 4 recover
var t: float = 0.0
var dir: Vector3 = Vector3.FORWARD
var centre: Vector3 = Vector3.ZERO
var victims: int = 0           # how many enemies the last shockwave threw
var last_spread: int = 0       # how many debuff transfers the last shockwave made

func start(cursor: Vector3) -> void:
	if p.dead or p.skills.busy or not p.stats.can_use("earthshatter") or not p.skills.weapon_ready("earthshatter"):
		return
	var skill: Dictionary = SkillDb.all()["earthshatter"]
	var flat: Vector3 = cursor - p.global_position
	flat.y = 0.0
	dir = flat.normalized() if flat.length() > 0.4 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	p.skills.clear_aim()
	p.skills.busy = true
	p.skills.busy_skill = "earthshatter"
	p.skills.busy_def = skill
	p.skills.busy_target = null
	p.skills.busy_t = 0.0
	p.skills.busy_hit_done = false
	p.combat_timer = 5.0
	p.movement.has_goal = false
	p.skills.queued_skill = ""
	p.attack_target = null
	p.click_mode = 0
	phase = 1
	t = 0.0
	p.visual.rotation.y = atan2(dir.x, dir.z)
	p.model.manual("earthshatter")
	p.model.scrub(CLIP_START)
	if p._trail != null:
		p._trail.active = false
	# The earth starts pulling in toward the hero as the blade goes up.
	SkillFx.ground_ring(p, p.global_position, RADIUS * 0.9, 0.6, Color(1.0, 0.6, 0.2, 0.7), GATHER_TIME, 0.0, 0.08)
	Fx.light_flash(p, p.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.25), 3.0, 0.4)

func tick(delta: float) -> void:
	t += delta
	p.move_with(Vector3.ZERO)
	match phase:
		1:
			var u: float = clampf(t / GATHER_TIME, 0.0, 1.0)
			if t < RAISE_TIME:
				p.model.scrub(lerpf(CLIP_START, CLIP_ARMS_UP, clampf(t / RAISE_TIME, 0.0, 1.0)))   # constant speed, no easing in or out
			else:
				p.model.scrub(lerpf(CLIP_ARMS_UP, CLIP_OVERHEAD, clampf((t - RAISE_TIME) / HOLD_OVERHEAD, 0.0, 1.0)))
			p.visual.rotation.x = -0.1 * u
			Fx.shake(p, 0.01 + 0.05 * u)   # the ground trembles, harder the longer the blade is held up
			_blade_light(u)
			if randf() < 0.5 * u:
				SkillFx.dust(p, p.global_position + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)), 0.6, 4,
					Color(0.42, 0.37, 0.31, 0.35), 0.8, 0.6)
			if t >= GATHER_TIME:
				phase = 2
				t = 0.0
		2:
			var u: float = clampf(t / SLAM_TIME, 0.0, 1.0)
			p.model.scrub(lerpf(CLIP_OVERHEAD, CLIP_IMPACT, u))
			p.visual.rotation.x = lerpf(-0.1, 0.22, u)
			_blade_light(1.0)
			if t >= SLAM_TIME:
				phase = 3
				t = 0.0
				_impact()
		3:
			var u: float = clampf(t / HOLD_TIME, 0.0, 1.0)
			p.model.scrub(lerpf(CLIP_IMPACT, CLIP_HOLD_END, u))
			_blade_light(1.0 - u)
			if t >= HOLD_TIME:
				phase = 4
				t = 0.0
		4:
			var u: float = clampf(t / RECOVER_TIME, 0.0, 1.0)
			p.model.scrub(lerpf(CLIP_HOLD_END, CLIP_END, u))
			p.visual.rotation.x = lerpf(0.22, 0.0, u)
			if t >= RECOVER_TIME:
				end()

## The glow on the sword tip builds through the gather and peaks as it comes down.
func _blade_light(strength: float) -> void:
	if p.model == null or p.model.weapon_tip == null:
		return
	var light: OmniLight3D = p.skills._glow_light
	if light == null:
		light = OmniLight3D.new()
		light.omni_range = 5.0
		p.model.weapon_tip.add_child(light)
		p.skills._glow_light = light
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0 * strength

func _impact() -> void:
	var skill: Dictionary = p.skills.busy_def
	p.skills.busy_hit_done = true
	p.stats.ult_charge = maxf(p.stats.ult_charge - float(skill.get("charge", 0.0)), 0.0)
	centre = p.global_position + dir * 1.2
	centre.y = 0.0
	SkillFx.earthshatter_impact(p, centre, RADIUS)
	Destructible.blast(p.get_tree(), centre, RADIUS, 999.0, Vector3.ZERO, 2.6)
	Fx.text_at(p, p.global_position + Vector3(0, 2.8, 0), "Earthshatter!", Color(1.0, 0.7, 0.3), 56)
	Gamepad.rumble(0.9, 1.0, 0.55)
	var in_range: Array[Actor] = []
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.impaled:
			continue
		if _flat(e.global_position - centre).length() - e.body_radius <= RADIUS:
			in_range.append(e)
	_share_debuffs(in_range)
	victims = 0
	for e in in_range:
		_hit(e)
	# The moment of impact, and the bodies in the air, play out in slow motion.
	Fx.slowmo(p, 0.12, 0.55, 0.55)

## Burn, bleed and chill on any victim are passed to every other victim.
func _share_debuffs(group: Array[Actor]) -> void:
	last_spread = 0
	var carriers: Array[Actor] = []
	for e in group:
		if e.burn_time > 0.0 or e.bleed_time > 0.0 or e.slow_time > 0.0:
			carriers.append(e)
	for src in carriers:
		for other in group:
			if other != src:
				src.spread_debuffs_to(other)
				last_spread += 1

func _hit(e: Actor) -> void:
	var offset: Vector3 = _flat(e.global_position - centre)
	var near: float = 1.0 - clampf(offset.length() / RADIUS, 0.0, 1.0)   # 1 at the centre, 0 at the edge
	var away: Vector3 = offset.normalized() if offset.length() > 0.15 else dir
	var damage: float = p.stats.weapon_damage(MULT) * ItemEffects.outgoing_multiplier(p, e) * lerpf(MIN_FALLOFF, 1.0, near)
	var result: Dictionary = Combat.resolve(p, e, damage, Combat.DamageType.PHYSICAL, false, 3.0)
	result["skill_id"] = "earthshatter"
	result["calm"] = true   # one big shockwave, not a separate splash of effects on every victim
	e.receive(result, centre)
	if not is_instance_valid(e):
		return
	victims += 1
	if e.is_boss:
		e.stun_time = maxf(e.stun_time, BOSS_STUN)
		Fx.text_at(p, e.global_position + Vector3(0, e.body_height + 0.7, 0), "Staggered", Color(1.0, 0.9, 0.5), 46)
		return
	e.stun_time = maxf(e.stun_time, STUN_TIME)
	# Thrown up and outward; the ones nearest the blade go highest, spinning end over end.
	var spin: Vector3 = away.cross(Vector3.UP) * randf_range(5.0, 9.0) + Vector3.UP * randf_range(-2.0, 2.0)
	e.ragdoll_launch(away * (LAUNCH_OUT * lerpf(0.45, 1.0, near)), LAUNCH_LIFT * lerpf(0.7, 1.0, near) + randf_range(-0.8, 1.2), spin)
	if e.ragdoll != null:
		e.ragdoll.calm = true

static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v

func end(restore_pose: bool = true) -> void:
	phase = 0
	p.skills.busy = false
	if not restore_pose:
		return
	p.visual.rotation.x = 0.0
	if p.skills._glow_light != null:
		p.skills._glow_light.light_energy = 0.0
	if p._trail != null:
		p._trail.active = false
	p.model.loop("idle_alert")
