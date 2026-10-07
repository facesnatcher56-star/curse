class_name WeaponThrowSkill
extends RefCounted
## Weapon Throw: hold the skill key to wind up and aim, let go to hurl the weapon in his hand along a straight line; it tears through
## whatever stands in that line and buries itself where it lands. Press the same key again and it rips free and comes back to the hero's
## hand along a line of its own (through other enemies if he has moved), and he catches it. One state machine owns the one weapon:
##
##   IN_HAND -> CHARGING -> RELEASING -> FLYING_OUT -> EMBEDDED -> RIPPING -> RETURNING -> CATCHING -> IN_HAND
##
## The weapon in the hero's hand is hidden for as long as the thrown copy (ThrownWeapon) exists, so there is never one in each. Nothing
## here is a hitscan: the weapon moves a little each physics tick and sweeps the ground it covered for enemies, props and walls.
## The numbers are all in DEFAULTS and in each weapon's `throw` profile (data/items, tools/write_item_defs.py).
##
## EVOLUTIONS (BuildDefs, bought with an Evolution Point; one at most, read when the charge starts): all three keep the baseline throw,
## embed and recall, and change what the weapon does on the way:
##   wallspike      a full-strength throw spears the first ordinary enemy it hits and carries it on the blade; into a wall it is pinned there
##                  (a real held state: the victim is impaled and out of the fight) until the recall rips the weapon free and drops it;
##                  in open ground the carried body is thrown on. Big, boss and non-impalable enemies are hit as normal; one victim per throw.
##   reaping_recall on the way back each lesser enemy the weapon strikes is dragged in toward the hero (a skid along the ground that comes
##                  to rest near him, not a teleport), once per return; heavy and boss enemies take the baseline blow.
##   ricochet       a strong throw glances off the first wall it meets (reflected about the wall's real normal), loses some speed and range,
##                  and flies on; it bounces once, then embeds normally. The charge lane shows the predicted bounce.

enum State { IN_HAND, CHARGING, RELEASING, FLYING_OUT, EMBEDDED, RIPPING, RETURNING, CATCHING }

const SKILL_ID := "throw"

## Tunable in one place. A weapon's `throw` profile (ItemDef.profile["throw"]) overrides any of these.
const DEFAULTS := {
	"charge_time": 1.3,        # seconds of holding for the full wind-up
	"min_range": 6.0,          # metres thrown by a tap
	"max_range": 22.0,         # metres thrown by a full charge
	"speed": 28.0,             # m/s outgoing
	"recall_speed": 27.0,      # m/s at the top of the return
	"recall_accel": 55.0,      # m/s^2 as it gathers speed coming back
	"turn_rate": 7.0,          # rad/s the return can curve toward the hero
	"damage": 2.4,             # outgoing weapon-damage multiplier at full charge (a tap does about 40% of it)
	"recall_damage": 0.55,     # of the outgoing damage, per enemy on the way back
	"mass": 1.0,               # how hard it hits: stagger, launch, knockdown, what it loses to heavy targets
	"prop_force": 1.0,         # what it can break
	"spin": 9.0,               # rad/s end over end
	"swing_speed": 1.0,        # how fast the wind-up and release animations play
	"catch_time": 0.34,        # seconds from starting to reach for it to the moment it is in his hand
	"catch_recover": 0.18,     # the short settle after the catch
	"rip_time": 0.4,           # seconds the weapon takes to wrench free of the ground
	"sweep_radius": 0.45,      # how wide the weapon hits (metres, plus the target's own size)
	"cooldown_mult": 1.0,
	"pitch": 1.0,              # how heavy it sounds (lower = heavier)
}
## Seconds of wind-up animation before the weapon leaves the hand at the throw's release, at swing_speed 1.
const RELEASE_STRIKE := 0.2
const RELEASE_LENGTH := 0.95
const CATCH_CLIP_LENGTH := 0.8   # the authored length of wthrow_catch
## The wind-up clip (wthrow) is authored so that time 0 is the guard and its end is the fullest wind-up; the charge scrubs along it.
const WINDUP_CLIP_LENGTH := 1.0
const START_HEIGHT := 1.15      # where the weapon leaves the hand
const END_HEIGHT := 0.25        # where it is when it comes down at the end of its range
const REACH_FAILSAFE := 9.0     # a return that has not arrived after this long is finished at once
const LIGHT_HEFT := 1.6         # targets up to this (a zombie is 1.0) are launched; heavier ones only stagger; from MASSIVE_HEFT they barely move
const MASSIVE_HEFT := 3.0       # (a brute is about 3.2)
const PLANT_FROM := 0.35        # the charge at which the hero starts to plant his feet; at PLANT_FULL he cannot move at all
const PLANT_FULL := 0.9

var p: Player
var state: State = State.IN_HAND
var charge: float = 0.0                 # 0..1 while charging (kept after the release for the throw's strength)
var thrown: ThrownWeapon
var preview: ThrowPreview
var aim_dir: Vector3 = Vector3.FORWARD
# Evolutions (see the header).
var evolution: String = ""               # the evolution in force for the throw being made ("" is the baseline throw)
var bounces: int = 0                     # Ricochet: wall bounces this throw (0 or 1)
var carried: Actor                       # Wallspike: the enemy riding the blade on its way out
var pinned: Actor                        # Wallspike: the enemy nailed to the wall the weapon is embedded in
var _pin_normal: Vector3 = Vector3.ZERO
var pulled_ids: Array[int] = []          # Reaping Recall: who has been dragged on this return

# The throw being made.
var _hold: float = 0.0
var _profile: Dictionary = {}
var _throw_dir: Vector3 = Vector3.FORWARD
var _throw_charge: float = 0.0
var _release_t: float = 0.0
var _range: float = 10.0
var _travelled: float = 0.0
var _speed: float = 0.0
var _start_speed: float = 0.0
var _pos: Vector3 = Vector3.ZERO
var _spin: float = 0.0
var _hit_ids: Dictionary = {}
var _pass_hits: int = 0
# Embedded and coming back.
var _embed_axis: Vector3 = Vector3.DOWN
var _embed_center: Vector3 = Vector3.ZERO
var _embed_t: float = 0.0
var _rip_t: float = 0.0
var _ret_dir: Vector3 = Vector3.UP
var _ret_speed: float = 0.0
var _ret_t: float = 0.0
var _catch_t: float = 0.0
var _catch_from: Vector3 = Vector3.ZERO
var _clock: float = 0.0
var _last_valid: Vector3 = Vector3.ZERO
## Recorded for tests and the report: what the last throw and the last return did.
var last_out_hits: Array[int] = []
var last_return_hits: Array[int] = []
var thrown_at_msec: int = -1
var proc_hits: int = 0                  # hits in the current pass that were allowed to set off on-hit effects (one per pass)

func _init(player: Player) -> void:
	p = player

# --- Queries --------------------------------------------------------------------------------------------------------------------

## The weapon is not in his hand (flying, in the ground, coming back, or reaching for it).
func is_away() -> bool:
	return state >= State.FLYING_OUT

## A sword skill may start: the weapon is in his hand and he is not in the middle of throwing it.
func has_weapon() -> bool:
	return state == State.IN_HAND

func charging() -> bool:
	return state == State.CHARGING

func profile() -> Dictionary:
	var merged: Dictionary = DEFAULTS.duplicate()
	var own: Variant = p.stats.weapon_profile("throw", {})
	if own is Dictionary:
		merged.merge(own, true)
	return merged

func charge_fraction() -> float:
	return clampf(_hold / maxf(float(_profile.get("charge_time", 1.3)), 0.05), 0.0, 1.0) if state == State.CHARGING else charge

## How far a throw made at this charge goes (continuous: min at a tap, max at a full hold).
func range_at(c: float, prof: Dictionary = {}) -> float:
	var use: Dictionary = prof if not prof.is_empty() else profile()
	return lerpf(float(use["min_range"]), float(use["max_range"]), clampf(c, 0.0, 1.0))

## How much of his walking speed he keeps while winding up: some at first, less as it builds, none near the full charge.
func move_factor() -> float:
	if state != State.CHARGING:
		return 1.0
	var c: float = charge_fraction()
	return lerpf(0.55, 0.0, smoothstep(PLANT_FROM, PLANT_FULL, c)) if c > 0.0 else 0.55

## The weapon's world position while it is out (for tests and the HUD).
func weapon_position() -> Vector3:
	return thrown.center() if thrown != null else Vector3.INF

# --- Charging ------------------------------------------------------------------------------------------------------------------

func can_begin() -> bool:
	return state == State.IN_HAND and not p.dead and p.stun_time <= 0.0 and not p.movement.rolling and not p.skills.busy \
		and p.stats.can_use(SKILL_ID)

func begin_charge() -> void:
	_profile = profile()
	evolution = p.evolution_of(SKILL_ID)   # what is bought now is what this throw does
	state = State.CHARGING
	_hold = 0.0
	charge = 0.0
	p.model.manual("wthrow")
	p.model.scrub(0.0)
	Sfx.sample(p, "sword_miss", -12.0, 0.6 * float(_profile["pitch"]))   # the first creak of leather and steel

## Backs out before the release: nothing is spent.
func cancel_charge() -> void:
	if state != State.CHARGING:
		return
	state = State.IN_HAND
	_hold = 0.0
	charge = 0.0
	if preview != null:
		preview.hide_lane()
	p.model.current = ""
	p.model.loop("idle_alert")

## Called every frame while the key is held, with the aim point (the cursor, or the right stick's point).
func update_preview(aim_point: Vector3) -> void:
	if state != State.CHARGING:
		return
	var flat: Vector3 = aim_point - p.global_position
	flat.y = 0.0
	aim_dir = flat.normalized() if flat.length() > 0.4 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	if preview == null:
		preview = ThrowPreview.new(p)
	var bank: bool = evolution == "ricochet" and charge_fraction() >= BuildDefs.RICOCHET_MIN_CHARGE
	preview.show_lane(p.get_world_3d(), p.global_position, aim_dir, range_at(charge_fraction(), _profile), 0.5 + 0.5 * sin(_clock * 8.0), _clock, bank)

## The wind-up pose, scrubbed by how long the key has been held: the planted stance, the twist of the body and the weapon drawn back
## all deepen as the charge builds. Called after the hero's movement each tick, so it is the last word on his pose and facing.
func pose_charge() -> void:
	if state != State.CHARGING:
		return
	var c: float = charge_fraction()
	var turn: float = lerpf(0.4, 0.08, c)   # the heavier the wind-up, the slower he turns his whole body to the aim
	p.face(p.global_position + aim_dir, turn)
	p.model.scrub(c * WINDUP_CLIP_LENGTH)

# --- Release and throw ----------------------------------------------------------------------------------------------------------

## The point the throw aims at when the key is let go: the cursor, or with no cursor aim the way the preview last pointed.
func aim_point_from(cursor: Vector3) -> Vector3:
	var flat: Vector3 = cursor - p.global_position
	flat.y = 0.0
	if flat.length() < 0.4:
		return p.global_position + aim_dir * 5.0
	return cursor

## Lets go: the release animation starts (from wherever the wind-up had got to) and the weapon leaves his hand at its release frame.
func release(aim_point: Vector3) -> void:
	if state != State.CHARGING:
		return
	_throw_charge = charge_fraction()
	charge = _throw_charge
	var flat: Vector3 = aim_point - p.global_position
	flat.y = 0.0
	_throw_dir = flat.normalized() if flat.length() > 0.4 else aim_dir
	_range = range_at(_throw_charge, _profile)
	if not _can_ricochet():   # a Ricochet throw is not cut short by the wall: it bounces off it and flies on
		_range = minf(_range, ThrowPreview.clear_length(p.get_world_3d(), p.global_position, _throw_dir, _range))
	bounces = 0
	state = State.RELEASING
	_release_t = 0.0
	if preview != null:
		preview.hide_lane()
	p.visual.rotation.y = atan2(_throw_dir.x, _throw_dir.z)
	var swing: float = float(_profile["swing_speed"])
	p.model.once("wthrow_release", 0.0, swing, 0.1)
	p.skills.busy = true
	p.skills.busy_skill = SKILL_ID
	p.skills.busy_def = {"weapon_throw": true, "kind": "throw", "name": "Weapon Throw", "weight": 1.0, "mana": 0.0, "time": RELEASE_LENGTH, "cd": 0.0}
	p.skills.busy_hit_done = false
	p.skills.busy_t = 0.0
	p.skills.busy_time = RELEASE_LENGTH / swing
	p.movement.has_goal = false
	Fx.punch(p, 0.8 + 1.4 * _throw_charge)

func _spawn_weapon() -> void:
	if p.model.weapon == null:
		_finish_release()
		return
	thrown = ThrownWeapon.from_hand(p.model.weapon, p.model.weapon_tip)
	var parent: Node = p.get_parent() if p.get_parent() != null else p.get_tree().current_scene
	parent.add_child(thrown)
	p.model.weapon.visible = false   # the one in his hand goes: there is only ever one
	state = State.FLYING_OUT
	_pos = p.model.weapon.global_position
	_pos.y = START_HEIGHT if _pos.y < 0.4 else _pos.y
	_last_valid = _pos
	_travelled = 0.0
	_start_speed = float(_profile["speed"]) * lerpf(0.82, 1.0, _throw_charge)
	_speed = _start_speed
	_spin = 0.5
	_hit_ids.clear()
	_pass_hits = 0
	last_out_hits.clear()
	proc_hits = 0
	carried = null
	pinned = null
	p.stats.weapon_locked = true   # the weapon is out: the one in the equipment slot may not be swapped for another until it is back
	p.stats.cooldowns[SKILL_ID] = float(SkillDb.all()[SKILL_ID]["cd"]) * float(_profile["cooldown_mult"])   # the cooldown starts when it is thrown
	thrown_at_msec = Time.get_ticks_msec()
	_place_flying()
	Sfx.sample(p, "sword_miss", 1.0 + 3.0 * _throw_charge, 0.62 * float(_profile["pitch"]))
	Fx.shake(p, 0.05 + 0.08 * _throw_charge)

func _finish_release() -> void:
	p.skills.busy = false
	p.skills.busy_hit_done = true
	p.model.loop("idle_alert")

## Called by the skill controller while the release animation runs (the hero is committed: no cancel).
func tick_busy(delta: float) -> void:
	if state == State.RELEASING:
		_release_t += delta
		p.skills.busy_t = _release_t * float(_profile["swing_speed"])
		if thrown == null and _release_t >= RELEASE_STRIKE / float(_profile["swing_speed"]):
			_spawn_weapon()
		if _release_t >= RELEASE_LENGTH / float(_profile["swing_speed"]):
			if state == State.RELEASING:
				state = State.IN_HAND   # (the weapon could not leave his hand: nothing was thrown)
			_finish_release()
	elif state == State.CATCHING:
		_tick_catch(delta)
		if p.skills.busy_t >= p.skills.busy_time:
			_finish_release()
	else:
		_finish_release()

# --- The weapon in the world ------------------------------------------------------------------------------------------------------

## Every physics tick (called by the hero, before anything else).
func tick(delta: float) -> void:
	_clock += delta
	match state:
		State.RELEASING:
			if not p.skills.busy and thrown == null:   # the release was knocked out of him before the weapon left his hand: nothing was thrown
				state = State.IN_HAND
		State.CATCHING:
			if not p.skills.busy:   # something cut the catch short: the weapon is in his hand all the same
				_complete_catch()
		State.CHARGING:
			_hold += delta
			charge = charge_fraction()
			if p.dead or p.stun_time > 0.0 or p.movement.rolling:
				cancel_charge()
		State.FLYING_OUT:
			_tick_flight(delta)
		State.EMBEDDED:
			_tick_embedded(delta)
		State.RIPPING:
			_tick_rip(delta)
		State.RETURNING:
			_tick_return(delta)

func _heft(e: Actor) -> float:
	return 1.0 + e.knock_resist * 3.0 + (e.body_radius - 0.42) * 2.0 + (3.0 if e.is_boss else 0.0)

func _place_flying() -> void:
	var axis: Vector3 = (_throw_dir * cos(_spin) + Vector3.UP * sin(_spin)).normalized()
	thrown.set_pose(_pos, axis, 0.0)

func _tick_flight(delta: float) -> void:
	var step: float = _speed * delta
	var f_before: float = clampf(_travelled / maxf(_range, 0.1), 0.0, 1.0)
	_travelled += step
	var f: float = clampf(_travelled / maxf(_range, 0.1), 0.0, 1.0)
	var from: Vector3 = _pos
	var to: Vector3 = from + _throw_dir * step
	to.y = lerpf(START_HEIGHT, END_HEIGHT, pow(f, 2.5))
	_spin += float(_profile["spin"]) * delta
	var stop: Dictionary = _sweep(from, to, true)
	if not _valid(to):
		_failsafe_outbound()
		return
	if not stop.is_empty():
		if _can_bounce(stop["normal"]):
			_bounce(stop["position"], stop["normal"])
		else:
			_embed(stop["position"], stop["normal"], true)
		return
	_pos = to
	_last_valid = to
	_place_flying()
	_carry_victim()
	if f >= 1.0 or f_before >= 1.0:
		_embed(Vector3(_pos.x, 0.0, _pos.z), Vector3.UP, false)
		return
	if _speed < _start_speed * 0.35:   # it has lost its speed to what it hit: it drops where it is
		_embed(Vector3(_pos.x, 0.0, _pos.z), Vector3.UP, false)

## Ricochet: a throw of this strength can glance off a wall (the flag read at the release, before the wall is met).
func _can_ricochet() -> bool:
	return evolution == "ricochet" and _throw_charge >= BuildDefs.RICOCHET_MIN_CHARGE

func _can_bounce(normal: Vector3) -> bool:
	return _can_ricochet() and bounces == 0 and absf(normal.y) < 0.6

## Glances off the wall it struck: the direction is reflected about the wall's actual normal, it loses speed and range, and it flies on.
## Once only (the next wall embeds it).
func _bounce(point: Vector3, normal: Vector3) -> void:
	var n: Vector3 = Vector3(normal.x, 0.0, normal.z).normalized()
	_throw_dir = _throw_dir.bounce(n)
	_throw_dir.y = 0.0
	_throw_dir = _throw_dir.normalized()
	var left: float = maxf(_range - _travelled, 1.0) * BuildDefs.RICOCHET_RANGE_KEEP
	_range = _travelled + maxf(left, 2.5)
	_speed *= BuildDefs.RICOCHET_SPEED_KEEP
	_pos = Vector3(point.x + n.x * 0.35, _pos.y, point.z + n.z * 0.35)
	_last_valid = _pos
	bounces += 1
	_place_flying()
	var spark: Vector3 = Vector3(point.x, _pos.y, point.z)
	Fx.burst(p, spark, n + Vector3.UP * 0.3, Color(1.0, 0.75, 0.4), 14, 5.0, 0.03, true)
	Fx.ring(p, Vector3(point.x, 0.1, point.z), 0.9, Color(0.85, 0.72, 0.5))
	Sfx.sample(p, "sword_hit_2", 1.0, 1.15 * float(_profile["pitch"]))
	Fx.shake(p, 0.05)

# --- Wallspike -------------------------------------------------------------------------------------------------------------------

## Whether the enemy just struck can be spiked: a full-strength outgoing throw, nothing carried yet, an ordinary body (not too big to impale).
func _can_spike(e: Actor, outgoing: bool, heft: float) -> bool:
	return outgoing and evolution == "wallspike" and _throw_charge >= BuildDefs.WALLSPIKE_MIN_CHARGE and carried == null and not e.dead \
		and e.can_be_impaled() and heft <= LIGHT_HEFT

func _spike(e: Actor, flat: Vector3) -> void:
	carried = e
	e.set_impaled(true)
	e.ragdoll_hang(atan2(-flat.x, -flat.z))
	e.credit_hero()
	e.knocked_by = p
	_speed *= BuildDefs.WALLSPIKE_SPEED_KEEP
	Fx.text_at(p, e.global_position + Vector3(0, e.body_height + 0.7, 0), "Spiked", Color(1.0, 0.8, 0.55), 44)
	Fx.burst(p, e.global_position + Vector3(0, 1.0, 0), flat + Vector3.UP * 0.3, Color(0.6, 0.05, 0.04), 16, 5.0)
	Fx.punch(p, 2.0)

## Keeps the spiked enemy on the blade as it flies (just ahead of the weapon, hanging).
func _carry_victim() -> void:
	if carried == null:
		return
	if not is_instance_valid(carried):
		carried = null
		return
	var at: Vector3 = _pos + _throw_dir * 0.55
	carried.global_position = Vector3(at.x, 0.3, at.z)
	carried.reset_physics_interpolation()
	if carried.ragdoll != null:
		carried.ragdoll.yaw = atan2(-_throw_dir.x, -_throw_dir.z)

## The weapon met a wall with someone on it: nailed to the wall, held there (impaled, out of the fight) until the recall.
func _pin_carried(point: Vector3, normal: Vector3) -> void:
	var e: Actor = carried
	carried = null
	if e == null or not is_instance_valid(e):
		return
	var n: Vector3 = Vector3(normal.x, 0.0, normal.z).normalized()
	pinned = e
	_pin_normal = n
	e.global_position = Vector3(point.x + n.x * 0.5, 0.3, point.z + n.z * 0.5)
	e.reset_physics_interpolation()
	if e.ragdoll != null:
		e.ragdoll.yaw = atan2(-_throw_dir.x, -_throw_dir.z)
	if not e.dead:
		var pin: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(BuildDefs.WALLSPIKE_PIN_DAMAGE), Combat.DamageType.PHYSICAL, false, 2.0)
		pin["skill_id"] = "wallspike"
		pin["secondary"] = true
		e.receive(pin, e.global_position - _throw_dir)
	if is_instance_valid(e):
		Fx.text_at(p, e.global_position + Vector3(0, e.body_height + 0.7, 0), "Pinned", Color(1.0, 0.9, 0.5), 46)
		Fx.burst(p, Vector3(point.x, 1.0, point.z), n + Vector3.UP * 0.2, Color(0.55, 0.5, 0.42), 14, 4.0, 0.05)

## Open ground instead of a wall: the carried body is thrown on, down and forward, and the weapon embeds as it always does.
func _throw_carried(velocity_dir: Vector3) -> void:
	var e: Actor = carried
	carried = null
	if e == null or not is_instance_valid(e):
		return
	e.set_impaled(false)
	e.credit_hero()
	var spin: Vector3 = velocity_dir.cross(Vector3.UP) * randf_range(5.0, 8.0)
	e.ragdoll_launch(velocity_dir * 8.0, 2.0, spin)

## The recall: the weapon rips out of the wall and the pinned enemy drops, knocked down.
func _release_pinned() -> void:
	var e: Actor = pinned
	pinned = null
	if e == null or not is_instance_valid(e):
		return
	e.set_impaled(false)
	e.credit_hero()
	e.knocked_by = p
	e.ragdoll_launch(_pin_normal * 3.0, 2.2, _pin_normal.cross(Vector3.UP) * randf_range(3.0, 6.0))
	if not e.dead:
		e.interrupt(1.5)
	Fx.burst(p, e.global_position + Vector3(0, 1.0, 0), _pin_normal + Vector3.UP * 0.3, Color(0.6, 0.05, 0.04), 12, 4.0)

# --- Reaping Recall --------------------------------------------------------------------------------------------------------------

## A lesser enemy struck on the way home is dragged in toward the hero: a skid along the ground (the knock-back every body already obeys,
## slowing at a steady rate) timed so it comes to rest close to him. Nothing teleports; a wall or another body in the way stops it.
func _reap(e: Actor) -> void:
	pulled_ids.append(e.get_instance_id())
	var to_hero: Vector3 = p.global_position - e.global_position
	to_hero.y = 0.0
	var dist: float = to_hero.length()
	var travel: float = clampf(dist - BuildDefs.REAPING_STOP_DISTANCE, 0.0, BuildDefs.REAPING_MAX_PULL)
	e.knocked_by = p
	e.credit_hero()
	e.interrupt(BuildDefs.REAPING_STAGGER)
	if travel > 0.1:
		e.knock = to_hero.normalized() * sqrt(2.0 * 22.0 * travel)   # knock slows at 22 m/s^2: this speed stops it `travel` metres on
	Fx.burst(p, Vector3(e.global_position.x, 0.15, e.global_position.z), to_hero.normalized() + Vector3.UP * 0.2, Color(0.42, 0.36, 0.28), 10, 3.0, 0.05)

func _valid(point: Vector3) -> bool:
	return point.is_finite() and point.y > -4.0 and point.distance_to(p.global_position) < 220.0

## Sweeps the ground between two ticks: props are smashed, enemies in the way are hit once each, and the first wall stops it.
## Returns {position, normal} when something solid stopped the weapon, else an empty dictionary.
func _sweep(from: Vector3, to: Vector3, outgoing: bool) -> Dictionary:
	var along: Vector3 = to - from
	var length: float = along.length()
	if length < 0.0001:
		return {}
	var dir: Vector3 = along / length
	var prof: Dictionary = _profile
	var c: float = _throw_charge
	# Props first (a broken one no longer blocks the ray below).
	var break_damage: float = (10.0 + 90.0 * c) * float(prof["prop_force"]) * (1.0 if outgoing else 0.5)
	var force: float = clampf(0.9 + 1.6 * c * float(prof["prop_force"]), 0.9, 2.6)
	var samples: int = maxi(int(ceil(length / 0.7)), 1)
	for i in samples + 1:
		var at: Vector3 = from.lerp(to, float(i) / float(samples))
		Destructible.blast(p.get_tree(), Vector3(at.x, 0.0, at.z), 0.55, break_damage, dir, force)
	# Enemies along the segment, nearest first, so what it loses to the first one is felt by the next.
	var found: Array = []
	var radius: float = float(prof["sweep_radius"])
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.impaled or _hit_ids.has(e.get_instance_id()):
			continue
		var rel: Vector3 = e.global_position - from
		rel.y = 0.0
		var flat_dir: Vector3 = Vector3(dir.x, 0.0, dir.z)
		var along_len: float = rel.dot(flat_dir.normalized()) if flat_dir.length() > 0.01 else 0.0
		var t: float = clampf(along_len, 0.0, length)
		var closest: Vector3 = flat_dir.normalized() * t if flat_dir.length() > 0.01 else Vector3.ZERO
		if (rel - closest).length() <= e.body_radius + radius and maxf(to.y, from.y) < e.body_height + 0.4:
			found.append([t, e])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for entry in found:
		var e: Actor = entry[1]
		if is_instance_valid(e) and not e.dead:
			_hit_enemy(e, dir, outgoing)
		if state != State.FLYING_OUT and state != State.RETURNING:
			break
	if not outgoing:
		return {}   # on the way back it only tears through what is in its path: a wall does not catch it
	# Solid world geometry: three rays, centre and the two edges.
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var best: Dictionary = {}
	var best_d: float = INF
	for offset in [0.0, 0.3, -0.3]:
		var query := PhysicsRayQueryParameters3D.create(from + side * offset, to + side * offset + dir * 0.3, Actor.LAYER_WORLD)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty() and from.distance_to(hit["position"]) < best_d:
			best_d = from.distance_to(hit["position"])
			best = hit
	return best

func _hit_enemy(e: Actor, dir: Vector3, outgoing: bool) -> void:
	_hit_ids[e.get_instance_id()] = true
	var prof: Dictionary = _profile
	var mass: float = float(prof["mass"])
	var c: float = _throw_charge
	var heft: float = _heft(e)
	var strength: float = (0.4 + 0.6 * c) * float(prof["damage"]) * (1.0 if outgoing else float(prof["recall_damage"]))
	var damage: float = p.stats.weapon_damage(strength) * ItemEffects.outgoing_multiplier(p, e)
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
	var result: Dictionary = Combat.resolve(p, e, damage, Combat.DamageType.PHYSICAL, false, 1.0 + 1.2 * c * mass)
	result["skill_id"] = SKILL_ID
	# Only the first thing the outgoing weapon strikes can set off the weapon's on-hit effects; everything after it, and the whole way
	# back, is a secondary hit, so a weapon that goes through ten enemies does not chain, burn and juggle ten times over.
	result["secondary"] = not (outgoing and _pass_hits == 0)
	if not result["secondary"]:
		proc_hits += 1
	_pass_hits += 1
	(last_out_hits if outgoing else last_return_hits).append(e.get_instance_id())
	e.receive(result, e.global_position - flat)
	var strike: float = 0.55 if outgoing else 0.4
	Sfx.sample(p, "sword_hit", 1.0 + 3.0 * c, (0.85 / maxf(mass, 0.7) ** 0.35) * float(prof["pitch"]))
	Fx.shake(p, 0.03 + 0.05 * c * mass)
	if not is_instance_valid(e):
		return
	if _can_spike(e, outgoing, heft):
		_spike(e, flat)
		return
	if not outgoing and evolution == "reaping_recall" and not e.dead and heft <= LIGHT_HEFT and not e.is_boss and not pulled_ids.has(e.get_instance_id()):
		_reap(e)
		_speed *= 1.0 - minf(0.03 * heft * mass, 0.2)
		return
	var impulse: float = (5.0 + 11.0 * c) * mass * (1.0 if outgoing else 0.8)
	if heft >= MASSIVE_HEFT:
		# Something this size takes the blow and barely moves; the weapon loses most of its speed to it.
		if not e.dead:
			e.interrupt(0.3 + 0.3 * c)
			e.knock += flat * impulse * 0.07 / heft
		_speed *= 0.55
		Fx.punch(p, 1.4)
	elif heft > LIGHT_HEFT:
		if not e.dead:
			e.interrupt(strike + 0.7 * c * mass)
			e.knock += flat * impulse * 0.28 / heft
		_speed *= 1.0 - minf(0.07 * heft * mass, 0.4)
	else:
		var launch: bool = c >= 0.35 or not outgoing or e.dead
		if launch:
			var side: Vector3 = flat.cross(Vector3.UP)
			e.ragdoll_launch(flat * impulse / heft + Vector3.UP * 0.0, 2.0 + 2.5 * c * mass, side * randf_range(-5.0, 5.0))
			e.interrupt(1.0 + 0.8 * c)
		else:
			e.interrupt(0.7)
			e.knock += flat * impulse * 0.6
		_speed *= 1.0 - minf(0.03 * heft * mass, 0.2)

# --- Landing ---------------------------------------------------------------------------------------------------------------------

## The weapon comes to rest: into the ground at a slant, or into the wall that stopped it.
func _embed(point: Vector3, normal: Vector3, wall_ok: bool) -> void:
	var c: float = _throw_charge
	var mass: float = float(_profile["mass"])
	var axis: Vector3
	var tip_point: Vector3
	if wall_ok and absf(normal.y) < 0.6:
		axis = (-normal * 0.85 + _throw_dir * 0.2 + Vector3.DOWN * 0.1).normalized()
		tip_point = point - normal * 0.14
	else:
		axis = (_throw_dir * 0.48 + Vector3.DOWN * 0.88).normalized()
		tip_point = Vector3(point.x, -0.12, point.z)
	_embed_axis = axis
	_embed_center = tip_point - axis * (thrown.length_m * (1.0 - ThrownWeapon.BALANCE))
	state = State.EMBEDDED
	_embed_t = 0.0
	thrown.set_pose(_embed_center, _embed_axis, 0.0)
	if carried != null:
		if wall_ok and absf(normal.y) < 0.6:
			_pin_carried(point, normal)
		else:
			_throw_carried(_throw_dir)
	var dust: Vector3 = Vector3(point.x, 0.1, point.z)
	Fx.burst(p, dust, Vector3.UP + _throw_dir * 0.3, Color(0.42, 0.36, 0.28), int(10 + 22 * c * mass), 3.0 + 3.0 * c * mass, 0.05)
	Fx.ring(p, dust, 0.8 + 1.6 * c * mass, Color(0.7, 0.62, 0.5))
	Sfx.sample(p, "leap_land", 2.0 + 3.0 * c, 0.9 * float(_profile["pitch"]))
	Fx.shake(p, 0.05 + 0.1 * c * mass)
	Fx.punch(p, 0.8 + 2.0 * c * mass)
	# A full-charge heavy weapon hitting the ground shakes the nearest small enemies for a moment: a flinch, not damage.
	if c * mass >= 1.1:
		for node in p.get_tree().get_nodes_in_group("enemies"):
			var e := node as Actor
			if e != null and not e.dead and e.global_position.distance_to(dust) < 4.5 and _heft(e) <= LIGHT_HEFT:
				e.interrupt(0.45)

func _tick_embedded(delta: float) -> void:
	_embed_t += delta
	if pinned != null:   # held on the wall for as long as the weapon is: nothing shoves it free
		if is_instance_valid(pinned):
			pinned.knock = Vector3.ZERO
			pinned.velocity = Vector3.ZERO
		else:
			pinned = null
	if _embed_t < 0.7 and thrown != null:   # it hums in the ground for a moment after the blow
		var lateral: Vector3 = _embed_axis.cross(Vector3.UP).normalized()
		var wobble: float = sin(_embed_t * 46.0) * 0.07 * exp(-_embed_t * 5.5)
		thrown.set_pose(_embed_center, (_embed_axis + lateral * wobble).normalized(), 0.0)
	if not _valid(_embed_center):
		_failsafe_outbound()

func _failsafe_outbound() -> void:
	if carried != null:
		_throw_carried(_throw_dir)
	# It left the world (fell through, or ended up somewhere that is not valid): put it back on the nearest good ground so a recall works.
	var safe: Vector3 = _last_valid if _valid(_last_valid) else p.global_position + Vector3(0, 0, 1.5)
	_pos = Vector3(safe.x, 0.5, safe.z)
	_embed_axis = (_throw_dir * 0.48 + Vector3.DOWN * 0.88).normalized()
	_embed_center = Vector3(safe.x, -0.12, safe.z) - _embed_axis * (thrown.length_m * (1.0 - ThrownWeapon.BALANCE))
	state = State.EMBEDDED
	thrown.set_pose(_embed_center, _embed_axis, 0.0)

# --- Recall ----------------------------------------------------------------------------------------------------------------------

## The same key again: always works while the weapon is out, whatever the cooldown says.
func recall() -> bool:
	match state:
		State.EMBEDDED:
			state = State.RIPPING
			_rip_t = 0.0
			_release_pinned()
			Fx.burst(p, Vector3(_embed_center.x, 0.1, _embed_center.z), Vector3.UP, Color(0.42, 0.36, 0.28), 24, 4.5, 0.05)
			Sfx.sample(p, "sword_miss", 0.0, 0.7 * float(_profile.get("pitch", 1.0)))
			return true
		State.FLYING_OUT:
			if carried != null:
				_throw_carried(_throw_dir)   # called back with someone on the blade: it comes off and is thrown on
			_begin_return(_pos)   # turned round in the air
			return true
	return false

func _tick_rip(delta: float) -> void:
	_rip_t += delta
	var total: float = float(_profile["rip_time"])
	var u: float = clampf(_rip_t / total, 0.0, 1.0)
	# It strains against the ground, then wrenches free along its own blade and swings up.
	var out_axis: Vector3 = -_embed_axis
	var lateral: Vector3 = _embed_axis.cross(Vector3.UP).normalized()
	var shake: float = sin(_rip_t * 60.0) * 0.1 * (1.0 - u)
	var lift: float = smoothstep(0.35, 1.0, u)
	var center: Vector3 = _embed_center + out_axis * (lift * 1.1) + Vector3.UP * (lift * 0.5)
	var axis: Vector3 = (_embed_axis + lateral * shake).normalized().slerp(Vector3.UP, lift * 0.5).normalized()
	thrown.set_pose(center, axis, 0.0)
	if u >= 0.55 and int(_rip_t * 60.0) % 5 == 0:
		Fx.burst(p, Vector3(_embed_center.x, 0.1, _embed_center.z), Vector3.UP, Color(0.42, 0.36, 0.28), 4, 2.5, 0.04)
	if u >= 1.0:
		_begin_return(center)

func _begin_return(from: Vector3) -> void:
	state = State.RETURNING
	_pos = from
	_pos.y = maxf(_pos.y, 0.45)
	_ret_dir = (Vector3.UP * 0.5 + (p.global_position - _pos).normalized()).normalized()
	_ret_speed = 6.0
	_ret_t = 0.0
	_hit_ids.clear()
	_pass_hits = 0
	last_return_hits.clear()
	pulled_ids.clear()
	proc_hits = 0
	_spin = 0.0
	Sfx.sample(p, "sword_miss", 1.0, 0.8 * float(_profile.get("pitch", 1.0)))

func _hand_point() -> Vector3:
	var hand: Vector3 = p.model.weapon.global_position if p.model.weapon != null else p.global_position + Vector3(0, START_HEIGHT, 0)
	return hand

func _tick_return(delta: float) -> void:
	_ret_t += delta
	var target: Vector3 = _hand_point()
	var to_hand: Vector3 = target - _pos
	_ret_speed = minf(_ret_speed + float(_profile["recall_accel"]) * delta, float(_profile["recall_speed"]))
	# Steering: it curves toward him at a limited rate (so its path is visibly a path), strongly enough that it always arrives.
	var desired: Vector3 = to_hand.normalized() if to_hand.length() > 0.01 else _ret_dir
	var turn: float = clampf(float(_profile["turn_rate"]) * delta * (1.0 + 2.0 * clampf(1.0 - to_hand.length() / 6.0, 0.0, 1.0)), 0.0, 1.0)
	_ret_dir = _ret_dir.slerp(desired, turn).normalized()
	var step: float = _ret_speed * delta
	var from: Vector3 = _pos
	var to: Vector3 = from + _ret_dir * step
	to.y = maxf(to.y, 0.3)
	_sweep(from, to, false)
	if not _valid(to) or _ret_t > REACH_FAILSAFE:
		_complete_catch()   # failsafe: never stranded
		return
	_pos = to
	_spin += float(_profile["spin"]) * 0.8 * delta
	var axis: Vector3 = (_ret_dir * cos(_spin) + Vector3.UP * sin(_spin)).normalized()
	thrown.set_pose(_pos, axis, 0.0)
	# Close enough to reach for it: the catch starts, timed so the weapon arrives in his hand at the catch frame.
	var reach: float = _ret_speed * float(_profile["catch_time"]) * 0.6 + 1.0
	if to_hand.length() <= reach and not p.dead:
		_begin_catch()

func _begin_catch() -> void:
	state = State.CATCHING
	_catch_t = 0.0
	_catch_from = _pos
	var catch_time: float = float(_profile["catch_time"])
	p.skills.busy = true
	p.skills.busy_skill = SKILL_ID
	p.skills.busy_def = {"weapon_throw": true, "kind": "throw", "name": "Weapon Throw", "weight": 1.0, "mana": 0.0, "time": catch_time, "cd": 0.0}
	p.skills.busy_hit_done = true
	p.skills.busy_t = 0.0
	p.skills.busy_time = catch_time + float(_profile["catch_recover"])
	p.movement.has_goal = false
	var to_weapon: Vector3 = _pos - p.global_position
	to_weapon.y = 0.0
	if to_weapon.length() > 0.3:
		p.visual.rotation.y = lerp_angle(p.visual.rotation.y, atan2(to_weapon.x, to_weapon.z), 0.8)
	# The clip is authored with the catch frame 64% of the way through; it is played at the speed that puts it on the weapon's arrival.
	p.model.once("wthrow_catch", 0.0, CATCH_CLIP_LENGTH * 0.64 / maxf(catch_time, 0.1), 0.08)

func _tick_catch(delta: float) -> void:
	if thrown == null:
		return
	_catch_t += delta
	p.skills.busy_t = _catch_t
	var catch_time: float = float(_profile["catch_time"])
	var u: float = clampf(_catch_t / catch_time, 0.0, 1.0)
	var hand: Vector3 = _hand_point()
	var here: Vector3 = _catch_from.lerp(hand, smoothstep(0.0, 1.0, u))
	var axis: Vector3 = thrown.axis().slerp(Vector3.UP, 0.0)
	thrown.set_pose(here, axis, 0.0)
	if u >= 1.0:
		_complete_catch()

## The catch frame: the thrown weapon is gone and the one in his hand is back, once.
func _complete_catch() -> void:
	var mass: float = float(_profile.get("mass", 1.0))
	if thrown != null:
		thrown.queue_free()
		thrown = null
	if p.model.weapon != null:
		p.model.weapon.visible = true
	state = State.IN_HAND
	charge = 0.0
	p.stats.weapon_locked = false
	Sfx.sample(p, "sword_hit_2", -1.0, 0.75 * float(_profile.get("pitch", 1.0)))
	Fx.shake(p, 0.04 + 0.05 * mass)
	Fx.punch(p, 0.6 + 0.8 * mass)
	Fx.burst(p, p.global_position + Vector3(0, 1.0, 0), Vector3.UP, Color(0.7, 0.7, 0.72), 6, 2.0, 0.03)

# --- Safety ----------------------------------------------------------------------------------------------------------------------

## Puts everything back: the weapon in his hand, no thrown copy, nothing locked. Called when he dies, is revived, or leaves the world.
func reset() -> void:
	if carried != null:
		_throw_carried(_throw_dir)
	if pinned != null:
		_release_pinned()
	if thrown != null and is_instance_valid(thrown):
		thrown.queue_free()
	thrown = null
	if p.model != null and p.model.weapon != null and is_instance_valid(p.model.weapon):
		p.model.weapon.visible = true
	if preview != null:
		preview.hide_lane()
	if state != State.IN_HAND and p.skills.busy_skill == SKILL_ID:
		p.skills.busy = false
	state = State.IN_HAND
	charge = 0.0
	_hold = 0.0
	p.stats.weapon_locked = false
