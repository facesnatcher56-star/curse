class_name Actor
extends CharacterBody3D
## Shared base for the player and enemies: stats, damage intake, hit reactions.

signal died(actor: Actor)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

var max_health: float = 100.0
var health: float = 100.0
## Dungeon Siege II's combat numbers (see Combat): the level (the hero's character level, Cutter's, a monster's from its threat), armour,
## fire resistance as a fraction, the chance to dodge a blow, to block one (a shield's), and to land a critical.
var level: int = 1
var armor: float = 0.0
var fire_resist: float = 0.0
## The other DS2 elements' resistances, fractions like `fire_resist`; each meets only its own element (Combat.element_multiplier).
var ice_resist: float = 0.0
var lightning_resist: float = 0.0
var death_resist: float = 0.0
## Broad DS2-style resistance stats, stored as fractions and refreshed from equipment. Curse-specific overlap is resolved in Combat.
var physical_resist: float = 0.0
var melee_resist: float = 0.0
var ranged_resist: float = 0.0
var magical_resist: float = 0.0
var dodge_chance: float = 0.0
var block_chance: float = 0.0
var crit_chance: float = 0.0
## How much a critical deals (DS2: 200%, Deadly Strike up to 350%), and the share of physical damage this actor shrugs off (Toughness).
var crit_mult: float = 2.0
var toughness: float = 0.0
## Blows that will crit whatever the roll (DS2's War Cry), and a share of armour stripped for a while (War Cry on its victims).
var forced_crits: int = 0
var armor_shred: float = 0.0
var armor_shred_time: float = 0.0

func shred_armor(share: float, seconds: float) -> void:
	armor_shred = maxf(armor_shred, clampf(share, 0.0, 0.95))
	armor_shred_time = maxf(armor_shred_time, seconds)
## Fire added to every physical blow (DS2's added elemental damage, from gear): it meets the target's fire resistance, then armour with the rest.
var added_fire: float = 0.0
var added_fire_max: float = 0.0
## Ice, lightning and death added the same way (min/max of the roll).
var added_ice: float = 0.0
var added_ice_max: float = 0.0
var added_lightning: float = 0.0
var added_lightning_max: float = 0.0
var added_death: float = 0.0
var added_death_max: float = 0.0
var ranged_block_chance: float = 0.0
## The chance to dodge a ranged blow when it differs from `dodge_chance` (the hero: gear can dodge only melee or only ranged). Negative: the same as `dodge_chance`.
var ranged_dodge_chance: float = -1.0
var body_radius: float = 0.4
var dead: bool = false

var stun_time: float = 0.0
var knock: Vector3 = Vector3.ZERO
## Whoever last landed a blow on this actor (for the hero: who to hold responsible for a death, see Monsters.hero_fell).
var last_hit_by: Actor
## KILL CREDIT. The hero gets credit for a death when they were, in the last CREDIT_MS, the cause of any harm to this actor: they hit it
## with a direct attack or a power, or it is burning from fire they lit. Cosmetic body collisions cannot harm or credit anyone.
## Monsters hurting each other, or an enemy dying of nothing
## the hero did, earns nothing. Only XP reads this (quests count kills regardless).
const CREDIT_MS := 15000
var _hero_credit_ms: int = -1000000
var _burn_by_hero: bool = false

func credit_hero() -> void:
	_hero_credit_ms = Time.get_ticks_msec()

## What the hero's party did to this actor, for the XP when it dies (DS2 pays the class skill of the weapon or spell used): the hero's
## damage by class skill ({melee, ranged, combat, nature}) and Cutter's. Only damage that took life counts.
var hero_damage: Dictionary = {}
var cutter_damage: float = 0.0
var member_damage: Dictionary = {} # member ID -> class -> effective damage.
var member_owners: Dictionary = {}
## Summoned actors may inherit a captured origin; ordinary enemies leave it empty.
var combat_origin: Dictionary = {}

func combat_identity() -> Dictionary:
	return combat_origin.duplicate(true)

func _tally_damage(source: Actor, skill_id: String, amount: float, origin: Dictionary = {}) -> void:
	var dealt: float = minf(amount, maxf(health, 0.0))
	if dealt <= 0.0:
		return
	if origin.is_empty() and is_instance_valid(source): origin = source.combat_identity()
	if not String(origin.get("character_id", "")).is_empty():
		var id: String = HeroAttributes.class_of_skill(skill_id)
		var member_id: String = String(origin.character_id)
		member_owners[member_id] = String(origin.get("owner_id", ""))
		if not member_damage.has(member_id): member_damage[member_id] = {}
		member_damage[member_id][id] = float(member_damage[member_id].get(id, 0.0)) + dealt
		if member_id == "hero": hero_damage[id] = float(hero_damage.get(id, 0.0)) + dealt
		elif member_id == "cutter": cutter_damage += dealt
		if self is Enemy: XpShare.pay_hit(self as Enemy, member_id, id, dealt)

func hero_credited() -> bool:
	return Time.get_ticks_msec() - _hero_credit_ms <= CREDIT_MS
## Rooted-ish: a snare slows to a crawl for a while without the ice shell a frost slow shows. Set by apply_snare.
var snare_time: float = 0.0
var snare_amount: float = 0.0
var bleed_time: float = 0.0
var bleed_dps: float = 0.0
var burn_time: float = 0.0
var burn_dps: float = 0.0
var burn_source: Actor
var burn_origin: Dictionary = {}
var burn_skill_id: String = ""
var _flames: Node3D

var display_name: String = "Hero"
var body_height: float = 1.8
var knock_resist: float = 0.0  # 0..1, fraction of knockback ignored
var stun_resist: float = 0.0   # 0..1, fraction of stun time ignored
## Bar feedback for the small bars over bodies (see Hud): `chip_health` is the life the bar still shows trailing behind the real one after a
## blow (held a moment, then it drains, longer for a heavy blow); `hit_pulse` is 1 the instant a blow lands and fades fast, tinted by what
## happened (`hit_pulse_outcome`), its strength following the blow's weight, so a hit is confirmed on the bar and its size is readable.
const CHIP_DRAIN_PER_SECOND := 0.7    # of max life per second, once the hold is over
const HIT_PULSE_SECONDS := 0.2
var chip_health: float = -1.0
var chip_hold: float = 0.0
var hit_pulse: float = 0.0
var hit_pulse_outcome: int = 0
var hit_pulse_weight: float = 1.0
var bar_timer: float = 0.0     # >0 while a floating health bar should be shown (set when hurt)
var flinch_chance: float = 0.0
const SMALL_STUN_RESIST := 0.2   # monsters with no more stun resistance than this flinch from every blow
const MIN_FLINCH := 0.2          # s: the shortest interruption a blow causes
## A blow at least this heavy (strike weight) staggers the hero, which on him is the knockdown: a Brute's heavy swing (2.7), the Warden's
## special (2.0); a zombie's heavy lunge (1.5) is not.
const HEAVY_BLOW_WEIGHT := 2.0
var flinch_serial: int = 0       # counts the blows that landed on a living body, so the hit pose can restart for each one
var hitpause: float = 0.0
var invulnerable_time: float = 0.0
var impalable: bool = true  # false for big enemies and bosses: Skewer staggers them instead
var ragdoll: Ragdoll
var impaled: bool = false   # skewered on the player's sword (Skewer); the player carries it, its AI is paused
var _saved_collision: Vector2i = Vector2i.ZERO
var is_boss: bool = false  # bosses ignore shoves and forced interrupts (see interrupt())

## A big body (a boss; an Enemy also by its DS2 tier, see Enemy.is_big).
func is_big() -> bool:
	return is_boss

var slow_time: float = 0.0
var slow_amount: float = 0.0   # fraction of speed removed while slowed

var visual: Node3D
var model: CharacterModel
var _saved_speed: float = 1.0
var highlighted: bool = false  # lit up as a target (e.g. inside an aimed spell's blast)
var _flash: float = 0.0
var _flash_mat: StandardMaterial3D

func _build_model(folder: String, clips: Array[String], height: float, radius: float, fists: bool = true) -> void:
	body_radius = radius
	body_height = height
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	add_child(shape)

	visual = Node3D.new()
	add_child(visual)
	model = CharacterModel.build(folder, clips, fists)
	visual.add_child(model)

	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1.0, 0.25, 0.2, 0.0)

## Returns true while frozen by a hit-pause; callers should skip their own logic for that frame.
func _actor_tick(delta: float) -> bool:
	_tick_bar_feedback(delta)
	if hitpause > 0.0:
		hitpause -= delta
		if hitpause <= 0.0:
			hitpause = 0.0
			model.anim.speed_scale = _saved_speed
		return true
	stun_time = maxf(stun_time - delta, 0.0)
	if armor_shred_time > 0.0:
		armor_shred_time -= delta
		if armor_shred_time <= 0.0:
			armor_shred = 0.0
	invulnerable_time = maxf(invulnerable_time - delta, 0.0)
	bar_timer = maxf(bar_timer - delta, 0.0)
	slow_time = maxf(slow_time - delta, 0.0)
	snare_time = maxf(snare_time - delta, 0.0)
	knock = knock.move_toward(Vector3.ZERO, 22.0 * delta)
	if bleed_time > 0.0 and not dead:
		bleed_time -= delta
		_apply_damage(bleed_dps * delta)
		if bleed_time <= 0.0:
			bleed_dps = 0.0
	_tick_burn(delta)
	_update_daze(delta)
	_update_frost()
	_update_ward(delta)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		_flash_mat.albedo_color.a = _flash * 0.5
		if _flash <= 0.0:
			_refresh_overlay()
	return false

func move_with(desired: Vector3) -> void:
	velocity = desired + knock
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0


func face(pos: Vector3, weight: float = 1.0) -> void:
	var dir: Vector3 = pos - global_position
	dir.y = 0.0
	if dir.length() < 0.01 or visual == null:
		return
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(dir.x, dir.z), weight)

func flat_distance_to_point(point: Vector3) -> float:
	var d: Vector3 = point - global_position
	d.y = 0.0
	return d.length()

func flat_distance_to(other: Node3D) -> float:
	var d: Vector3 = other.global_position - global_position
	d.y = 0.0
	return d.length()

## Skills whose blow is the hero's sword itself.
const SWORD_SKILLS: Array[String] = ["basic", "brutal_attack", "whirling_strike", "staggering_blow", "opening"]
const GIBBING_POWERS: Array[String] = ["brutal_attack", "take_aim", "whirling_strike", "staggering_blow", "flame_nexus", "detonation", "fireball"]

func _tick_bar_feedback(delta: float) -> void:
	if chip_health < 0.0 or health >= chip_health:
		chip_health = health   # healing (and the first frame) never leaves a trail
	elif chip_hold > 0.0:
		chip_hold -= delta
	else:
		chip_health = maxf(health, chip_health - max_health * CHIP_DRAIN_PER_SECOND * delta)
	hit_pulse = maxf(hit_pulse - delta / HIT_PULSE_SECONDS, 0.0)

## A blow has landed or been turned aside: pulse the bar (tinted by `outcome`, sized by `weight`) and keep it on show for a moment.
func _confirm_hit_on_bar(outcome: int, weight: float) -> void:
	hit_pulse = 1.0
	hit_pulse_outcome = outcome
	hit_pulse_weight = weight
	bar_timer = maxf(bar_timer, 1.4)

## Apply a resolved attack (see Combat.resolve) to this actor.
func receive(result: Dictionary, source_pos: Vector3) -> void:
	if dead:
		return
	_last_hit_from = source_pos
	_last_hit_ms = Time.get_ticks_msec()
	if result.get("source") is Player or not String(result.get("origin", {}).get("character_id", "")).is_empty():
		credit_hero()
	if result.get("source") is Actor:
		last_hit_by = result["source"]
	if invulnerable_time > 0.0:
		Fx.text_at(self, global_position + Vector3(0, 2.2, 0), "Dodge", Color(0.6, 0.95, 1.0), 40)
		return
	if float(result.get("damage", 0.0)) <= 0.0 and int(result.get("outcome", 0)) >= Combat.Outcome.HIT:
		health = minf(max_health, health - float(result.get("damage", 0.0)))
		return   # Immunity/absorption causes no hit recoil, leech, or recharge.
	result = _filter_incoming(result)
	if result.get("quiet", false):
		# Damage-over-time style tick: apply it, show the health bar, nothing else.
		bar_timer = 4.0
		_tally_damage(result.get("source"), String(result.get("skill_id", "")), float(result["damage"]), result.get("origin", {}))
		_apply_damage(float(result["damage"]))
		return
	var outcome: int = result["outcome"]
	var damage: float = result["damage"]
	if ward_time > 0.0:
		damage *= 1.0 - ward_reduction   # a plague ward soaks part of every blow
	if damage <= 0.0 and outcome >= Combat.Outcome.HIT:
		return
	var weight: float = result.get("weight", 1.0)
	_confirm_hit_on_bar(outcome, weight)
	var source: Actor = result.get("source")
	var chest: Vector3 = global_position + Vector3(0, body_height * 0.65, 0)
	# A "calm" hit (the Earthshatter shockwave striking a whole crowd at once) skips the per-enemy blood, numbers, flashes, shake and
	# hit-pause: ten of those at the same instant would bury the move in noise.
	var calm: bool = bool(result.get("calm", false))
	var away: Vector3 = global_position - source_pos
	away.y = 0.0
	away = away.normalized()

	if not calm:
		Fx.popup(self, outcome, damage, _popup_tint(), String(result.get("skill_id", "")))
	if outcome == Combat.Outcome.MISS:
		if source is Player and String(result.get("skill_id", "")) in SWORD_SKILLS and not result.get("secondary", false):
			Sfx.sword_miss(self)   # the blade cut empty air
		_on_avoided(outcome)
		return
	if outcome == Combat.Outcome.BLOCK:
		Fx.burst(self, chest, away + Vector3.UP * 0.5, Color(1.0, 0.85, 0.5), 10, 6.0, 0.03, true)
		knock += away * 1.5 * weight
		_on_avoided(outcome)
		return

	var fire: bool = result.get("type", 0) == Combat.DamageType.FIRE
	# Only the hero's blade landing makes the sword sound (not a miss or a block, which returned above, and not a fireball,
	# a boot, a shockwave or a splash).
	var sword_contact: bool = source is Player and not result.get("secondary", false) \
		and String(result.get("skill_id", "")) in SWORD_SKILLS
	bar_timer = 4.0
	last_result = result
	# Brutal Attack always bursts a victim it kills. Otherwise a critical killing blow bursts the body, while
	# a direct fire kill (a fireball, not a secondary proc) bursts it into burning pieces.
	if health - damage <= 0.0 and not is_in_group("player"):
		if fire and not result.get("secondary", false):
			_pending_gib = "fire"
		elif String(result.get("skill_id", "")) in GIBBING_POWERS \
				or (not calm and outcome == Combat.Outcome.CRITICAL):
			_pending_gib = "gore"
		_gib_from = source_pos
	_tally_damage(source, String(result.get("skill_id", "")), damage, result.get("origin", {}))
	result["damage"] = minf(damage, maxf(health, 0.0))   # Recharge/leech count actual life removed, not overkill.
	_apply_damage(damage)

	# Layered impact feedback: sound, spray, light, squash, camera, pause, push.
	var killed: bool = dead
	var big: bool = outcome == Combat.Outcome.CRITICAL
	var profile: Dictionary = Fx.impact_profile(outcome, weight)
	var power_sound: String = String(result.get("skill_id", ""))
	if not result.get("secondary", false) and power_sound in ["brutal_attack", "take_aim"]:
		Sfx.power(self, "brutal_hit" if power_sound == "brutal_attack" else "take_aim_hit")
	elif sword_contact:
		Sfx.sword_hit(self, outcome, weight)
	if not calm:
		var amount: int = int(clampf(6.0 + damage * 0.5 + weight * 4.0, 6.0, 40.0)) * (2 if big else 1)
		Fx.burst(self, chest, away + Vector3.UP * 0.6, _blood_color(), amount, 4.0 + weight * 2.5 + (3.0 if big else 0.0))
		if big or randf() < 0.3:
			Fx.blood_decal(self, global_position + away * 0.5, randf_range(0.5, 0.9) * (1.3 if big else 1.0), _blood_color().darkened(0.4))
		# Brutal Attack already supplies its directional DS2 impact. Do not stack
		# the ordinary heavy-hit sparks/ground circle over that presentation.
		if sword_contact and String(result.get("skill_id", "")) != "brutal_attack":
			Fx.melee_impact(self, chest, away, int(profile.tier), get_instance_id())
		elif big:
			Fx.light_flash(self, chest, Color(1.0, 0.85, 0.6), 1.8, 0.07)
	if not dead:
		_flash = 1.0
		model.set_overlay(_flash_mat)
		_squash(away, 0.08 * weight + (0.1 if big else 0.0))
		flinch_serial += 1
		if not is_in_group("player") and not is_ragdolled() and model != null:   # the body takes the blow: chest tips away, shoulders turn, head follows
			var scale_up: float = 1.5 if outcome == Combat.Outcome.CRITICAL else 1.0
			model.react(away, BodyRecoil.peak_for(weight, scale_up, knock_resist))

	if not calm:
		var shake_amount: float = clampf(0.03 + damage * 0.004, 0.03, 0.12) * weight
		Fx.shake(self, shake_amount)
		if source != null and source.is_in_group("player") or is_in_group("player"):
			Fx.kick(self, -away if is_in_group("player") else away, float(profile.kick))

	# Hit-pause on both parties makes the blow land; crits add a brief global slow-down.
	var pause: float = 0.06 * weight + (0.045 if big else 0.0)
	# The hero is never frozen by being hit: a crowd landing blows would otherwise stutter every skill to a halt.
	if not calm:
		if not killed and not is_in_group("player"):
			add_hitpause(pause)
		if source != null and source != self:
			source.add_hitpause(pause)
		if outcome == Combat.Outcome.CRITICAL:
			Fx.hitstop(self, 0.045)

	# Equipment reacts to every landed hit (including the one that killed).
	if source is Player and source != self:
		(source as Player).on_dealt_hit(self, result)
	_on_received_hit(result)
	if killed:
		return
	var push: float = 2.5
	var hero: bool = is_in_group("player")
	if hero and weight >= HEAVY_BLOW_WEIGHT:
		# A heavy blow (a Brute's or the Warden's big swing, a blast) staggers the hero: on him that is the knockdown (Player._gain_stun).
		# DS2 has no such outcome; this keeps Curse's physical knockdown now that the Zombasite "crushing" roll is gone.
		push = 9.0
		_gain_stun(0.5 * (1.0 - stun_resist), result)
	match outcome:
		Combat.Outcome.CRITICAL:
			push = 5.5
			if not hero:
				stun_time = maxf(stun_time, 0.3 * (1.0 - stun_resist))
		_:
			# Ordinary blows only flinch enemies. The hero keeps swinging, casting and moving through them.
			# Every blow interrupts a small monster (the owner: they surround you anyway, so it costs nothing); big ones only sometimes.
			if not hero and (weight >= 1.5 or randf() < flinch_chance or stun_resist <= SMALL_STUN_RESIST):
				stun_time = maxf(stun_time, maxf(0.25 * weight, MIN_FLINCH) * (1.0 - stun_resist))
	var shove: float = push * weight * (1.0 - knock_resist)
	if hero:
		shove *= 0.2 if is_acting() else 0.5   # mid-skill the hero is planted
	knock += away * shove
	_on_hurt(result, source_pos)

## Staggered by a blow. The hero overrides this (his passives can shrug a light one off, see Player._gain_stun).
func _gain_stun(duration: float, _result: Dictionary = {}) -> void:
	stun_time = maxf(stun_time, duration)

func _blood_color() -> Color:
	return Color(0.55, 0.05, 0.04)

## Quick squash-and-stretch pulse on the visual, pushed along the blow.
func _squash(direction: Vector3, strength: float) -> void:
	if visual == null:
		return
	# Recoil instead of squash: shoving the model back along the blow reads as impact
	# without distorting the mesh (uneven scaling looked rubbery on skinned limbs).
	var tween := create_tween()
	visual.position = direction * strength * 1.5
	tween.tween_property(visual, "position", Vector3.ZERO, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func add_hitpause(duration: float) -> void:
	if duration <= hitpause:
		return
	if hitpause <= 0.0 and model != null:
		_saved_speed = model.anim.speed_scale
		model.anim.speed_scale = 0.0
	hitpause = duration

## True while the procedural ragdoll is driving this actor (carried, flying, lying or getting up).
func is_ragdolled() -> bool:
	return ragdoll != null and ragdoll.is_active()

func can_be_impaled() -> bool:
	return impalable and not is_boss and not dead

func ragdoll_hang(yaw: float) -> void:
	if ragdoll == null:
		ragdoll = Ragdoll.new(self)
	ragdoll.hang(yaw)

func ragdoll_launch(velocity: Vector3, lift: float, spin: Vector3) -> void:
	if ragdoll == null:
		ragdoll = Ragdoll.new(self)
	if not ragdoll.is_active():
		ragdoll.yaw = visual.rotation.y  # keep the current facing; no snap when the tumble starts
	ragdoll.launch(velocity, lift, spin)
	if dead:
		ragdoll.stay_down()

## Pins the actor to the player's blade: no AI, no physics body, until released.
func set_impaled(on: bool) -> void:
	if on == impaled:
		return
	impaled = on
	if on:
		_saved_collision = Vector2i(collision_layer, collision_mask)
		collision_layer = 0
		collision_mask = 0
		velocity = Vector3.ZERO
		knock = Vector3.ZERO
	else:
		collision_layer = _saved_collision.x
		collision_mask = _saved_collision.y

## Breaks whatever the actor is doing (attacks, casts) and staggers it briefly. Bosses are immune.
func interrupt(duration: float) -> bool:
	if is_boss or dead:
		return false
	stun_time = maxf(stun_time, duration)
	return true

## The glow shared by all highlighted enemies; the aiming code pulses its alpha.
static var highlight_material: StandardMaterial3D

static func get_highlight_material() -> StandardMaterial3D:
	if highlight_material == null:
		highlight_material = StandardMaterial3D.new()
		highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Expanded back faces form a clean silhouette outline without washing the
		# enemy's actual materials orange. This is the DS2 hover-target read.
		highlight_material.cull_mode = BaseMaterial3D.CULL_FRONT
		highlight_material.grow_enabled = true
		highlight_material.grow_amount = 0.035
		highlight_material.albedo_color = Color(1.0, 0.34, 0.08, 0.92)
	return highlight_material

func set_highlighted(on: bool) -> void:
	if on == highlighted or model == null:
		return
	highlighted = on
	_refresh_overlay()

## The hit flash always wins; otherwise show the highlight glow, otherwise nothing.
func _refresh_overlay() -> void:
	if _flash > 0.0 or model == null:
		return
	model.set_overlay(get_highlight_material() if highlighted else null)

## Speed multiplier from slows (1.0 when not slowed).
func speed_factor() -> float:
	var factor: float = 1.0 - slow_amount if slow_time > 0.0 else 1.0
	if snare_time > 0.0:
		factor = minf(factor, 1.0 - snare_amount)
	return factor

## Snared: crawling for `seconds` (a ranged monster that tried to run from the hero's blows, so it can be caught).
func apply_snare(seconds: float, amount: float) -> void:
	var fresh: bool = snare_time <= 0.0
	snare_time = maxf(snare_time, seconds)
	snare_amount = maxf(amount, snare_amount if not fresh else 0.0)
	if fresh and not dead:
		Fx.text_at(self, global_position + Vector3(0, body_height + 0.7, 0), "Snared", Color(0.75, 0.85, 0.45), 40)
		Fx.ring(self, global_position + Vector3(0, 0.05, 0), 1.3, Color(0.5, 0.58, 0.28))

func apply_slow(amount: float, seconds: float) -> void:
	slow_amount = maxf(amount, slow_amount if slow_time > 0.0 else 0.0)
	slow_time = maxf(slow_time, seconds)

## A ward (cast by a Plague Priest): takes less damage and moves faster for a few seconds, shown as a green shell.
var ward_time: float = 0.0
var ward_reduction: float = 0.0
var ward_haste: float = 1.0
var ward_source: Actor
var _ward_fx: MeshInstance3D

func apply_ward(seconds: float, reduction: float, haste: float, source: Actor) -> void:
	ward_time = maxf(ward_time, seconds)
	ward_reduction = reduction
	ward_haste = haste
	ward_source = source

func clear_ward() -> void:
	ward_time = 0.0
	ward_source = null

func _update_ward(delta: float) -> void:
	if ward_time > 0.0:
		ward_time -= delta
		if ward_time <= 0.0:
			clear_ward()
	var want: bool = ward_time > 0.0 and not dead and model != null
	if want and _ward_fx == null:
		_ward_fx = MeshInstance3D.new()
		var shell := SphereMesh.new()
		shell.radius = maxf(body_radius * 1.5, 0.6)
		shell.height = body_height * 1.15
		_ward_fx.mesh = shell
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(0.35, 0.9, 0.25, 0.18)
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
		_ward_fx.material_override = mat
		_ward_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ward_fx.position.y = body_height * 0.5
		add_child(_ward_fx)
	elif not want and _ward_fx != null:
		_ward_fx.queue_free()
		_ward_fx = null
	if _ward_fx != null:
		_ward_fx.scale = Vector3.ONE * (1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.008))

## Slowed (frostbite, etc.): a cold blue mist drifts off the body and a pale light clings to it until it wears off.
var _frost: Node3D

func _update_frost() -> void:
	var want: bool = slow_time > 0.0 and slow_amount >= 0.2 and not dead and model != null
	if want and _frost == null:
		_frost = _make_frost()
		add_child(_frost)
	elif not want and _frost != null:
		_frost.queue_free()
		_frost = null

func _make_frost() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, body_height * 0.5, 0)
	var mist := CPUParticles3D.new()
	mist.amount = 20
	mist.lifetime = 0.9
	mist.local_coords = false
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.4
	mist.direction = Vector3.UP
	mist.spread = 40.0
	mist.initial_velocity_min = 0.1
	mist.initial_velocity_max = 0.5
	mist.gravity = Vector3(0, -0.3, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	mist.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.85, 1.0, 0.55))
	ramp.set_color(1, Color(0.4, 0.7, 1.0, 0.0))
	mist.color_ramp = ramp
	root.add_child(mist)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.75, 1.0)
	light.light_energy = 0.9
	light.omni_range = 2.5
	root.add_child(light)
	return root

## Stunned or dazed (anything longer than a hit flinch): yellow stars circle the head until it wears off.
const DAZE_MIN := 0.45
var _daze: Node3D
var _daze_clock: float = 0.0

func _update_daze(delta: float) -> void:
	var want: bool = stun_time > DAZE_MIN and not dead and not impaled
	if want and _daze == null and model != null:
		_daze = _make_daze()
		add_child(_daze)
	elif not want and _daze != null:
		_daze.queue_free()
		_daze = null
	if _daze != null:
		_daze_clock += delta
		_daze.rotation.y += 4.5 * delta
		var down: bool = is_ragdolled() and ragdoll.state != Ragdoll.State.HANG
		_daze.position.y = (0.75 if down else body_height + 0.3) + sin(_daze_clock * 5.0) * 0.04

func _make_daze() -> Node3D:
	var root := Node3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.3)
	mat.no_depth_test = true
	mesh.material = mat
	for i in 4:
		var star := MeshInstance3D.new()
		star.mesh = mesh
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a: float = float(i) / 4.0 * TAU
		star.position = Vector3(cos(a), sin(a * 2.0) * 0.06, sin(a)) * 0.34
		root.add_child(star)
		# A short glowing tail so the orbit reads as motion.
		var tail := MeshInstance3D.new()
		var tail_mesh := SphereMesh.new()
		tail_mesh.radius = 0.035
		tail_mesh.height = 0.07
		tail_mesh.radial_segments = 6
		tail_mesh.rings = 3
		tail_mesh.material = mat
		tail.mesh = tail_mesh
		tail.position = Vector3(cos(a - 0.35), sin(a * 2.0) * 0.06, sin(a - 0.35)) * 0.34
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tail)
	return root


## Sets the actor alight: fire damage over time with visible flames until it burns out or dies.
func apply_burn(dps: float, seconds: float, by_hero: bool = false, source: Actor = null, skill_id: String = "", origin: Dictionary = {}) -> void:
	if dead:
		return
	if dps >= burn_dps:
		burn_source = source
		burn_skill_id = skill_id
		burn_origin = origin.duplicate(true) if not origin.is_empty() else source.combat_identity() if is_instance_valid(source) else {}
	if by_hero:
		_burn_by_hero = true
		credit_hero()
	burn_dps = maxf(burn_dps, dps)
	burn_time = maxf(burn_time, seconds)
	if _flames == null and model != null:
		_flames = _make_flames()
		add_child(_flames)

const BURN_TICK := 0.5
var _burn_clock: float = 0.0
var _burn_owed: float = 0.0

func _tick_burn(delta: float) -> void:
	if burn_time <= 0.0:
		return
	burn_time -= delta
	var damage: float = burn_dps * delta * Combat.fire_multiplier(self)
	var dealt: float = minf(maxf(damage, 0.0), maxf(health, 0.0))
	if _burn_by_hero:
		credit_hero()   # fire the hero lit keeps the credit while it burns
		_tally_damage(burn_source if is_instance_valid(burn_source) else null, burn_skill_id, dealt, burn_origin)
		if is_instance_valid(burn_source) and burn_source is Player:
			(burn_source as Player).on_party_damage(dealt, burn_skill_id)
	if damage >= health and burn_skill_id in GIBBING_POWERS and not is_in_group("player"):
		_pending_gib = "fire"
		_gib_from = burn_source.global_position if is_instance_valid(burn_source) else global_position
	if damage > 0.0:
		_apply_damage(damage)
	elif damage < 0.0:
		health = minf(max_health, health - damage)
	# The burning shows in ticks: every half second a fiery number for what it took, a puff of embers and a flare of the flames.
	_burn_owed += dealt
	_burn_clock += delta
	if _burn_clock >= BURN_TICK:
		_burn_clock = 0.0
		if not dead and _burn_owed >= 0.5:
			Fx.damage_tick(self, maxi(roundi(_burn_owed), 1), Color(1.0, 0.55, 0.12))
			Fx.burst(self, global_position + Vector3(0, body_height * 0.6, 0), Vector3.UP, Color(1.0, 0.5, 0.1), 6, 2.8, 0.03)
			if _flames != null:
				_flames.scale = Vector3.ONE * 1.35
		_burn_owed = 0.0
	if _flames != null:
		_flames.scale = _flames.scale.lerp(Vector3.ONE, 1.0 - exp(-10.0 * delta))
	if _flames != null:
		_flames.visible = not is_ragdolled()   # no flame trail across the sky while thrown, and none on a body lying stunned
	if burn_time <= 0.0 or dead:
		stop_burning()

func stop_burning() -> void:
	burn_source = null
	burn_origin = {}
	burn_skill_id = ""
	_burn_by_hero = false
	burn_time = 0.0
	burn_dps = 0.0
	if _flames != null:
		_flames.queue_free()
		_flames = null

func is_burning() -> bool:
	return burn_time > 0.0

func _make_flames() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, body_height * 0.45, 0)
	var fire := CPUParticles3D.new()
	fire.amount = 28
	fire.lifetime = 0.7
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.35
	fire.direction = Vector3.UP
	fire.spread = 20.0
	fire.gravity = Vector3(0, 2.5, 0)
	fire.initial_velocity_min = 0.6
	fire.initial_velocity_max = 1.6
	fire.scale_amount_min = 0.6
	fire.scale_amount_max = 1.2
	fire.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	fire.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3, 0.9))
	ramp.set_color(1, Color(0.8, 0.1, 0.0, 0.0))
	fire.color_ramp = ramp
	root.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 1.4
	light.omni_range = 4.0
	root.add_child(light)
	return root

## Overridable: lets equipment change an incoming hit (block it, reduce it) before it is applied.
func _filter_incoming(result: Dictionary) -> Dictionary:
	return result

## Post-mitigation, overkill-clamped damage, including lethal hits. Not called for avoided/quiet ticks.
func _on_received_hit(_result: Dictionary) -> void:
	pass

func _popup_tint() -> Color:
	return Color(0, 0, 0, 0)

func _apply_damage(amount: float) -> void:
	if dead:
		return
	if amount > 0.0:
		if chip_health < 0.0 or chip_health < health:
			chip_health = health   # the trail starts from the life the blow found
		chip_hold = 0.28 + 0.14 * hit_pulse_weight   # a heavy blow's loss lingers a little longer
	health -= amount
	if health <= 0.0:
		health = 0.0
		_die()

## How a killing blow bursts the body: "" (it just falls), "gore" or "fire". Set by receive() just before the lethal damage.
var _pending_gib: String = ""
var _last_hit_from: Vector3 = Vector3.ZERO   # where the latest blow came from, and when: a death is thrown away from it
var _last_hit_ms: int = -100000
var _gib_from: Vector3 = Vector3.ZERO

## True while the actor is committed to a skill or attack (the hero overrides this); committed actors are shoved less.
func is_acting() -> bool:
	return false

## Colour of the pieces when this body bursts (set from the enemy's definition).
var gib_color: Color = Color(0.42, 0.48, 0.37)

## The most recent resolved hit this actor took (read by death hooks, e.g. "was it killed by fire?").
var last_result: Dictionary = {}

func _gib_color() -> Color:
	return gib_color

func _die() -> void:
	dead = true
	died.emit(self)
	set_physics_process(false)
	hitpause = 0.0
	stop_burning()
	if _frost != null:
		_frost.queue_free()
		_frost = null
	model.set_overlay(null)
	if _pending_gib != "":
		Gibs.explode(self, _pending_gib, _gib_from)
		visual.visible = false   # nothing left to lie there
		if is_ragdolled():
			ragdoll.stay_down()
	elif is_ragdolled():
		ragdoll.stay_down()  # dies where it lies instead of playing the death animation
	elif is_in_group("player"):
		model.once("death", 0.0, 1.0, 0.1)   # the hero keeps the death animation
	else:
		_collapse_as_ragdoll()
	Fx.blood_decal(self, global_position, 1.3, _blood_color().darkened(0.5))
	for shape in find_children("*", "CollisionShape3D", false, false):
		(shape as CollisionShape3D).set_deferred("disabled", true)
	_on_death()

## A killed enemy goes limp and is thrown by the blow that killed it: further for heavy hits, away from where it came from; a
## death from burning or bleeding just crumples. It stays where it lands.
func _collapse_as_ragdoll() -> void:
	var recent: bool = Time.get_ticks_msec() - _last_hit_ms < 400
	var away: Vector3 = global_position - _last_hit_from
	away.y = 0.0
	if not recent or away.length() < 0.05:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized()
	var weight: float = clampf(float(last_result.get("weight", 1.0)), 0.4, 3.5) if recent else 0.4
	var speed: float = 1.5 + weight * 2.6
	var spin: Vector3 = away.cross(Vector3.UP) * (3.0 + weight * 2.0) + Vector3(randf_range(-1.0, 1.0), randf_range(-1.5, 1.5), randf_range(-1.0, 1.0))
	ragdoll_launch(away * speed, 2.0 + weight * 1.4, spin)

func _on_hurt(_result: Dictionary, _source_pos: Vector3) -> void:
	pass

func _on_avoided(_outcome: int) -> void:
	pass

func _on_death() -> void:
	pass
