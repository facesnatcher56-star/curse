class_name PowerController
extends RefCounted
## The hero's Dungeon Siege II powers that play in Curse (docs/ds2_powers_reference.md): Whirling Strike, Staggering Blow, War Cry and
## Provoke (Melee), Repulse and Silence (Ranged), Flame Nexus and Detonation (Combat Magic). Each opens with passive ranks (PowerDb), costs
## no mana, has no cooldown and recharges from damage dealt (DS2's formula, PowerDef.recharge seconds of combat); its numbers are its rank's.
## Powers never crit. Brutal Attack keeps its own path (SkillController), Take Aim is Cutter's.

const LIVE: Array[String] = ["whirling_strike", "staggering_blow", "war_cry", "provoke", "repulse", "silence", "flame_nexus", "detonation", "thunderous_shot"]
## How far a targeted power (Silence, Detonation) reaches, and War Cry's cone (DS2 gives a cone; Curse's length and width).
const CAST_RANGE := 14.0
const WAR_CRY_LENGTH := 8.0
const WAR_CRY_HALF_ANGLE := 35.0
## How long War Cry's terror lasts (DS2: enemies run in fear; the time is engine-side, CURSE CHOICE).
const WAR_CRY_FEAR := 4.0
## Flame Nexus's radius (DS2's file gives only a dummy radius; CURSE CHOICE) and the burn every DS2 fire power leaves (4 s at 0.1 x INT).
const NEXUS_RADIUS := 4.0
const FIRE_POWER_BURN := 0.1
## The wind-up of a power that strikes on impact (Whirling Strike, War Cry). `start`, `strike` and `end` are clip seconds (the strike is the
## impact frame), `time` the cast's length in seconds. Damage, stun, cost and recharge happen at the impact, never on the key press; a
## wind-up cut short (death, a knockdown, a move, a dodge, another skill) does none of them and is not spent. Curse's own clips for now
## (knight2 library); the free library clips replace them when the owner approves the source.
const CASTS := {
	"whirling_strike": {"clip": "atk_spin", "start": 0.0, "strike": 0.9, "end": 1.5, "time": 0.9, "weight": 2.2},
	"war_cry": {"clip": "cast", "start": 0.0, "strike": 0.9, "end": 1.4, "time": 1.2, "face": true},
}
## Staggering Blow's armed blow: the overhead swing that releases it on impact (the same blow path as a basic attack, with its own clip).
const STAGGER_SWING := {"clip": "atk_finisher", "start": 0.0, "strike": 0.77, "end": 1.6, "time": 1.45, "weight": 1.8, "lunge": 0.6,
	"range": 2.6, "mult": 1.0, "staggering_animation": true}
## Impact feel, bounded: a short hit-pause and a shake when the power hits something, growing with the number hit and capped (seconds
## and shake amount for Fx). CURSE CHOICE; ordinary hits keep their own pause.
const IMPACT_PAUSE := 0.03
const IMPACT_PAUSE_EACH := 0.008
const IMPACT_PAUSE_MAX := 0.06
const IMPACT_SHAKE := 0.12
const IMPACT_SHAKE_EACH := 0.03
const IMPACT_SHAKE_MAX := 0.24
## Metres an enemy is thrown back by a power that stuns it (the knock-back uses the same v^2 / 44 relation as Repulse). CURSE CHOICE.
const WHIRL_KNOCK := 1.6
const STAGGER_KNOCK := 2.6

var p: Player
var reload_required: Dictionary = {}    # power id -> damage its recharge needed
var reload_remaining: Dictionary = {}   # power id -> damage still to deal (0: ready)
var staggering_armed: bool = false
var provoke_time: float = 0.0
var provoke_armor_pct: float = 0.0
var repulse_time: float = 0.0
var _repulse_radius: float = 0.0
var _repulse_push: float = 0.0
var _repulse_stun: float = 0.0
var _repulsed: Dictionary = {}           # instance id -> seconds before it can be thrown back again

func _init(player: Player) -> void:
	p = player

# --- Recharge ----------------------------------------------------------------------------------------------------------------

func required(id: String) -> float:
	var def: PowerDef = PowerDb.get_def(id)
	return p.stats.power_recharge_damage(PowerDb.charge_seconds(id), def.tree) if def != null else 0.0

func fraction(id: String) -> float:
	var left: float = float(reload_remaining.get(id, 0.0))
	return 1.0 if left <= 0.0 else clampf(1.0 - left / maxf(float(reload_required.get(id, 1.0)), 0.001), 0.0, 1.0)

## Damage the party deals recharges every power but the one that dealt it.
func gain(damage: float, skill_id: String = "") -> void:
	for id in reload_remaining.keys():
		if id != skill_id:
			reload_remaining[id] = maxf(float(reload_remaining[id]) - maxf(damage, 0.0), 0.0)

## Gives back `share` of each charging power's recharge (an Opening's refund).
func refund(share: float) -> void:
	for id in reload_remaining.keys():
		reload_remaining[id] = maxf(float(reload_remaining[id]) - float(reload_required.get(id, 0.0)) * share, 0.0)

func _spend(id: String) -> void:
	reload_required[id] = required(id)
	reload_remaining[id] = reload_required[id]

## A level-up recharges everything (DS2), and a new run starts with nothing armed.
func reset() -> void:
	reload_remaining.clear()
	reload_required.clear()
	staggering_armed = false

# --- Can it be used ---------------------------------------------------------------------------------------------------------

## Why `id` cannot be used now, or "" when it can: not open yet, not in the game yet, the wrong weapon, not recharged.
func blocker(id: String) -> String:
	var def: PowerDef = PowerDb.get_def(id)
	if def == null or not LIVE.has(id):
		return "Not a power"
	if PowerDb.hero_rank(id, p.member_id) <= 0:
		return "%s is not open yet" % def.display_name
	if not stance_ok(def.stance):
		return "%s needs %s" % [def.display_name, {"shield": "a shield", "two_handed": "a two-handed weapon", "melee": "a melee weapon", "bow": "a bow"}.get(def.stance, def.stance)]
	if float(reload_remaining.get(id, 0.0)) > 0.0:
		return "%s is %d%% charged" % [def.display_name, int(fraction(id) * 100.0)]
	return ""

func ready(id: String) -> bool:
	return blocker(id) == ""

func stance_ok(stance: String) -> bool:
	var weapon: Variant = p.stats.equipment.get(Items.Slot.WEAPON)
	match stance:
		"melee":
			return weapon != null and not p.stats.is_ranged()
		"two_handed":
			return weapon != null and not p.stats.is_ranged() and PlayerStats._two_handed(weapon)
		"shield":
			return p.stats.equipment.has(Items.Slot.SHIELD)
		"bow":
			return weapon != null and p.stats.is_ranged()
		"any":
			return true
	return false

func value(id: String, key: String) -> float:
	return PowerDb.hero_value(id, key, p.member_id)

# --- Using them -------------------------------------------------------------------------------------------------------------

## Uses `id` toward `cursor`; says why not when it cannot. Returns whether it went off (or, for Staggering Blow, was armed).
func activate(id: String, cursor: Vector3) -> bool:
	if p.dead:
		return false
	if id == "staggering_blow" and staggering_armed:
		p._say("Staggering Blow is armed")
		return false
	var why: String = blocker(id)
	if why != "":
		p._say(why)
		return false
	if p.skills.busy and String(p.skills.busy_def.get("kind", "")) == "power":
		p._say("%s is already under way" % PowerDb.get_def(p.skills.busy_skill).display_name)
		return false
	p.combat_timer = 5.0
	var immediate_target: Actor = p.skills.busy_target if is_instance_valid(p.skills.busy_target) else p.attack_target
	if not is_instance_valid(immediate_target):
		immediate_target = p.hover_target
	p.skills.cancel_action()   # Powers interrupt an ordinary attack instead of queuing.
	p.skills.clear_queue()
	if id == "thunderous_shot":
		# Cutter draws the shot (BowAttack, one long draw); the bolt, its damage and the stun happen at the release (thunderous_release).
		return p.bow != null and p.bow.start_thunderous(thunderous_aim_point(cursor))
	if CASTS.has(id):
		# The wind-up starts now; the effect lands at its impact (impact()), and only then is the power spent.
		p.skills.start_power_cast(id, cursor, CASTS[id])
		Sfx.power(p, id + "_cast")
		return true
	match id:
		"staggering_blow":
			staggering_armed = true   # the next landed blow releases it, and only then is it spent (DS2: preserved by a miss)
			Sfx.power(p, "staggering_cast")
			p.power_activated.emit(p.member_id, id)
			if is_instance_valid(immediate_target) and not immediate_target.dead:
				p.attack_target = immediate_target
				p.movement.has_goal = false
				p.skills.start_skill("basic", immediate_target)
			return true
		"provoke":
			_provoke()
		"repulse":
			_repulse()
		"silence":
			_silence(_target_point(cursor))
		"flame_nexus":
			_fire_blast(p.global_position, NEXUS_RADIUS, "flame_nexus", false)
		"detonation":
			_fire_blast(_target_point(cursor), value("detonation", "radius"), "detonation", true)
	_spend(id)
	p.power_activated.emit(p.member_id, id)
	return true

## The impact of a wind-up that strikes on impact (SkillController.start_power_cast reaches it at the strike frame). A power that was cut
## short never gets here: nothing is dealt and nothing is spent.
func impact(id: String, aim: Vector3) -> void:
	match id:
		"whirling_strike":
			_whirling_strike()
			p.openings.on_power_use()   # one Opening roll for the whole spin
		"war_cry":
			_war_cry(aim)
	_spend(id)
	p.power_activated.emit(p.member_id, id)

## Whirling Strike: one spin, every enemy within reach hit for the power's share of the weapon, stunned and thrown back a little.
func _whirling_strike() -> void:
	var mult: float = value("whirling_strike", "damage_pct") / 100.0
	var stun: float = value("whirling_strike", "stun")
	var radius: float = value("whirling_strike", "radius")
	MapModeLegendaries.pull_in(p)   # Gravecaller Maul (map mode only): the pull comes before anything is measured or hit
	var hit: Array[Enemy] = enemies_within(p.global_position, radius)
	for e in hit:
		_strike(e, p.stats.weapon_damage(1.0), "whirling_strike", 2.0, p.global_position, mult)
		if is_instance_valid(e) and not e.dead:
			_stagger(e, stun, WHIRL_KNOCK, p.global_position)
			WhirlingStrikeFx.hit(p, e, p.global_position)   # the arc, ring and dust come from the cast's own WhirlingStrikeFx
	Destructible.blast(p.get_tree(), p.global_position, radius, 40.0, Vector3.ZERO, 1.2, Destructible.HERO)
	if not hit.is_empty():
		Sfx.power(p, "whirling_strike_hit")
	_impact_feel(hit.size())

## Thunderous Shot's release (BowAttack.loose): one bolt along `direction` from the arrowhead, as far as the bow reaches or the first wall,
## through every enemy on the line. Each takes the power's share of the bow's damage (it cannot miss and never crits) and is stunned for the
## rank's time. Kills are ordinary deaths: this power does not gib. Returns how many it hit.
func thunderous_release(muzzle: Vector3, direction: Vector3) -> int:
	var dir: Vector3 = direction.normalized()
	var victims: Array[Dictionary] = []
	for bolt in thunderous_directions(dir):   # one bolt, or the Splitbow's fan (map mode only)
		victims.append_array(thunderous_line(muzzle, bolt)["victims"])
	var mult: float = value("thunderous_shot", "damage_pct") / 100.0 * p.stats.power_damage_mult() * MapModeLegendaries.bolt_damage_factor(p)
	var stun: float = value("thunderous_shot", "stun")
	var base: Vector2 = p.stats.ranged_range()
	if not victims.is_empty():
		p.openings.on_power_use()   # one Opening roll for the whole shot, not per enemy
	for victim in victims:
		var e: Enemy = victim["enemy"]
		if not is_instance_valid(e) or e.dead:
			continue   # an earlier bolt of the same shot killed it
		if p is ArcherCompanion:
			e.credit_hero()   # Cutter serves the hero: his kills count as the hero's
		var result: Dictionary = Combat.resolve(p, e, randf_range(base.x, base.y), Combat.DamageType.RANGED, false, 2.0, false, false, mult)
		result["skill_id"] = "thunderous_shot"
		e.receive(result, muzzle)
		if is_instance_valid(e) and not e.dead:
			_stagger(e, stun, 0.0, muzzle)
	_impact_feel(victims.size())
	_spend("thunderous_shot")
	p.power_activated.emit(p.member_id, "thunderous_shot")
	return victims.size()

## The directions Thunderous Shot's bolts fly in along `dir`: one, or three in a cone with the Splitbow (map mode only).
func thunderous_directions(dir: Vector3) -> Array[Vector3]:
	return MapModeLegendaries.bolt_directions(p, dir.normalized())

## Where Thunderous Shot is aimed for a cursor: the enemy under the cursor (its chest) if there is one, else the point on the ground.
func thunderous_aim_point(cursor: Vector3) -> Vector3:
	var target: Actor = p.hover_target
	if not is_instance_valid(target):
		# A hotbar key sends the command to its member whoever is controlled: the enemy under the mouse is the controlled body's.
		var party := PartyManager.current()
		var driver := party.bodies.get(party.active_id) as Player
		target = driver.hover_target if is_instance_valid(driver) else null
	if is_instance_valid(target) and not target.dead:
		return target.global_position + Vector3(0, target.body_height * 0.62, 0)
	return Vector3(cursor.x, p.global_position.y + 1.2, cursor.z)

## The bolt's line from `muzzle` along `dir`: how far it goes (the bow's reach, or the first wall) and the enemies on it nearest first, as
## [{enemy, along}]. The release and the casting-area preview both read this, so the highlight is exactly who is hit.
func thunderous_line(muzzle: Vector3, dir: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * ThunderousShotFx.REACH, Actor.LAYER_WORLD)
	var wall: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(query)
	var length: float = muzzle.distance_to(wall["position"]) if not wall.is_empty() else ThunderousShotFx.REACH
	var victims: Array[Dictionary] = []
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead:
			continue
		var chest: Vector3 = e.global_position + Vector3(0, e.body_height * 0.6, 0)
		var along: float = (chest - muzzle).dot(dir)
		if along > 0.0 and along < length and (chest - (muzzle + dir * along)).length() < ThunderousShotFx.WIDTH:
			victims.append({"enemy": e, "along": along})
	victims.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["along"]) < float(b["along"]))
	return {"length": length, "victims": victims}

## The stun, in seconds, Thunderous Shot leaves at this member's rank (for its visuals).
func thunderous_stun() -> float:
	return value("thunderous_shot", "stun")

## Staggering Blow, released by the blow that landed on `target`: a shockwave from it stuns everything around and deals the power's damage.
func release_staggering(target: Actor) -> void:
	if not staggering_armed or target == null:
		return
	staggering_armed = false
	p.openings.on_power_use()   # one Opening roll for the whole Staggering Blow, not per enemy it stuns
	var centre: Vector3 = target.global_position
	var mult: float = value("staggering_blow", "damage_pct") / 100.0
	var stun: float = value("staggering_blow", "stun")
	var radius: float = value("staggering_blow", "radius")
	var hit: Array[Enemy] = enemies_within(centre, radius)
	for e in hit:
		_strike(e, p.stats.weapon_damage(1.0), "staggering_blow", 3.0, centre, mult)
		if is_instance_valid(e) and not e.dead:
			_stagger(e, stun, STAGGER_KNOCK, centre)
	Fx.ring(p, centre, radius, Color(0.75, 0.6, 0.4))
	Fx.burst(p, centre + Vector3(0, 0.2, 0), Vector3.UP, Color(0.4, 0.33, 0.25), 24, 6.0, 0.06)
	Sfx.power(p, "staggering_hit")
	_impact_feel(hit.size())
	_spend("staggering_blow")

## A power's stun and throw-back on one enemy: it reels for `stun` (scaled by its resistance) and is pushed away from `from`.
func _stagger(e: Enemy, stun: float, throw_back: float, from: Vector3) -> void:
	var out: Vector3 = e.global_position - from
	out.y = 0.0
	# knock decays at 22 m/s2 (Actor), so a push of v travels v^2 / 44 m: v = sqrt(44 d) throws it `throw_back` metres.
	e.knock += (out.normalized() if out.length() > 0.1 else Vector3.FORWARD) * sqrt(44.0 * throw_back) * (1.0 - e.knock_resist)
	e._gain_stun(stun * (1.0 - e.stun_resist))

## The hit-pause and shake of a power's impact: bounded, and only when it struck something (see IMPACT_*).
func _impact_feel(hits: int) -> void:
	if hits <= 0:
		return
	var more: int = mini(hits - 1, 4)
	Fx.hitstop(p, minf(IMPACT_PAUSE + IMPACT_PAUSE_EACH * more, IMPACT_PAUSE_MAX))
	Fx.shake(p, minf(IMPACT_SHAKE + IMPACT_SHAKE_EACH * more, IMPACT_SHAKE_MAX))

## War Cry: a cone in front; the enemies in it run in fear with their armour stripped, and the hero's next blows are critical.
## `cursor` is where the hero faced when he began the shout (the cone's direction).
func _war_cry(cursor: Vector3) -> void:
	var facing: Vector3 = cursor - p.global_position
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.1 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	var shred: float = value("war_cry", "armor_reduction_pct") / 100.0
	var seconds: float = value("war_cry", "duration")
	var hit: Array[Enemy] = []
	for e in enemies_within(p.global_position, WAR_CRY_LENGTH):
		var to: Vector3 = e.global_position - p.global_position
		to.y = 0.0
		if to.length() < 0.5 or rad_to_deg(facing.angle_to(to.normalized())) <= WAR_CRY_HALF_ANGLE:
			e.shred_armor(shred, seconds)
			e.frighten(WAR_CRY_FEAR)
			hit.append(e)
	p.forced_crits = int(value("war_cry", "critical_hits"))
	Fx.sector(p, p.global_position, facing, WAR_CRY_HALF_ANGLE, WAR_CRY_LENGTH, Color(0.9, 0.6, 0.35), 0.45)
	Fx.burst(p, p.global_position + Vector3(0, 1.6, 0) + facing, facing, Color(0.6, 0.5, 0.4), 20, 7.0, 0.04)
	if not hit.is_empty():
		Sfx.power(p, "war_cry_hit")
	_impact_feel(hit.size())

## Provoke: every enemy around turns on the hero, and his armour rises while he holds them.
func _provoke() -> void:
	for e in enemies_within(p.global_position, value("provoke", "radius")):
		e.target = p
		e.wake()
	provoke_armor_pct = value("provoke", "armor_pct")
	provoke_time = value("provoke", "duration")
	p.stats.refresh()
	Fx.ring(p, p.global_position, value("provoke", "radius"), Color(0.7, 0.65, 0.55))
	Fx.text_at(p, p.global_position + Vector3(0, 2.4, 0), "Provoke", Color(0.85, 0.75, 0.55), 36)

## Repulse: for a while, anything that comes within reach is thrown back and stunned.
func _repulse() -> void:
	repulse_time = value("repulse", "duration")
	_repulse_radius = value("repulse", "radius")
	_repulse_push = value("repulse", "knockback")
	_repulse_stun = value("repulse", "stun")
	_repulsed.clear()
	Fx.ring(p, p.global_position, _repulse_radius, Color(0.6, 0.7, 0.75))

## Silence: monsters inside the area cannot cast (a plague priest's wards and raisings) for a while.
func _silence(point: Vector3) -> void:
	var seconds: float = value("silence", "duration")
	for e in enemies_within(point, value("silence", "radius")):
		e.silence_time = maxf(e.silence_time, seconds)
	Fx.ring(p, point, value("silence", "radius"), Color(0.55, 0.6, 0.7))
	Fx.text_at(p, point + Vector3(0, 1.8, 0), "Silence", Color(0.7, 0.75, 0.85), 32)

## Flame Nexus (around the hero) and Detonation (at the target): DS2 fire powers, their damage grown by Searing Flames, cannot be dodged,
## and set what they hit alight (DS2: fire powers always ignite).
func _fire_blast(centre: Vector3, radius: float, id: String, knock: bool) -> void:
	var damage: float = value(id, "damage") * (1.0 + p.stats.passive("searing_flames") / 100.0) * (1.0 + p.stats.passive("arcane_fury") / 100.0) * p.stats.power_damage_mult()
	for e in enemies_within(centre, radius):
		var result: Dictionary = Combat.resolve(p, e, damage * randf_range(0.75, 1.25), Combat.DamageType.FIRE, false, 2.0, false, false)
		result["skill_id"] = id
		e.receive(result, centre)
		if is_instance_valid(e) and not e.dead:
			e.apply_burn(FIRE_POWER_BURN * p.stats.intelligence, 4.0, true, p, id)
			if knock:
				var out: Vector3 = e.global_position - centre
				out.y = 0.0
				e.knock += (out.normalized() if out.length() > 0.1 else Vector3.FORWARD) * 7.0 * (1.0 - e.knock_resist)
	Fx.ring(p, centre, radius, Color(1.0, 0.5, 0.15))
	Fx.burst(p, centre + Vector3(0, 0.4, 0), Vector3.UP, Color(1.0, 0.45, 0.1), 28, 6.0, 0.05, true)
	Fx.light_flash(p, centre + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.2), 3.0, 0.35)
	Destructible.blast(p.get_tree(), centre, radius, 50.0, Vector3.ZERO, 1.4, Destructible.HERO)

# --- Each frame -------------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if provoke_time > 0.0:
		provoke_time -= delta
		if provoke_time <= 0.0:
			provoke_armor_pct = 0.0
			p.stats.refresh()
	if repulse_time > 0.0:
		repulse_time -= delta
		for id in _repulsed.keys():
			_repulsed[id] = float(_repulsed[id]) - delta
			if float(_repulsed[id]) <= 0.0:
				_repulsed.erase(id)
		for e in enemies_within(p.global_position, _repulse_radius):
			if _repulsed.has(e.get_instance_id()) or e.is_boss:
				continue
			_repulsed[e.get_instance_id()] = _repulse_stun
			var out: Vector3 = e.global_position - p.global_position
			out.y = 0.0
			# knock decays at 22 m/s2 (Actor), so a push of v travels v^2 / 44 m: v = sqrt(44 d) throws it `knockback` metres.
			e.knock += (out.normalized() if out.length() > 0.1 else Vector3.FORWARD) * sqrt(44.0 * _repulse_push) * (1.0 - e.knock_resist)
			e._gain_stun(_repulse_stun * (1.0 - e.stun_resist))
			Fx.burst(p, e.global_position + Vector3(0, 1.0, 0), out.normalized(), Color(0.6, 0.7, 0.75), 6, 4.0, 0.03)

# --- Helpers ----------------------------------------------------------------------------------------------------------------

func enemies_within(centre: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead:
			continue
		var gap: Vector3 = e.global_position - centre
		gap.y = 0.0
		if gap.length() <= radius + e.body_radius:
			out.append(e)
	return out

func _target_point(cursor: Vector3) -> Vector3:
	var to: Vector3 = cursor - p.global_position
	to.y = 0.0
	return p.global_position + to.limit_length(CAST_RANGE)

## A physical power blow: it can be dodged and blocked, never crits (DS2: powers never crit).
func _strike(e: Enemy, damage: float, id: String, weight: float, from: Vector3, mult: float = 1.0) -> void:
	var result: Dictionary = Combat.resolve(p, e, damage, Combat.DamageType.PHYSICAL, true, weight, false, false, mult * p.stats.power_damage_mult())
	result["skill_id"] = id
	e.receive(result, from)
