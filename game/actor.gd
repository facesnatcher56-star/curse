class_name Actor
extends CharacterBody3D
## Shared base for the player and enemies: stats, damage intake, hit reactions.

signal died(actor: Actor)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

var max_health: float = 100.0
var health: float = 100.0
var attack_rating: float = 20.0
var defense: float = 20.0
var armor: float = 20.0
var fire_resist: float = 0.0
var block_chance: float = 0.0
var crit_chance: float = 0.05
var crushing_chance: float = 0.03
var deep_wounds_chance: float = 0.04
var body_radius: float = 0.4
var dead: bool = false

var stun_time: float = 0.0
var knock: Vector3 = Vector3.ZERO
var bleed_time: float = 0.0
var bleed_dps: float = 0.0
var burn_time: float = 0.0
var burn_dps: float = 0.0
var _flames: Node3D

var display_name: String = "Hero"
var body_height: float = 1.8
var knock_resist: float = 0.0  # 0..1, fraction of knockback ignored
var stun_resist: float = 0.0   # 0..1, fraction of stun time ignored
var bar_timer: float = 0.0     # >0 while a floating health bar should be shown (set when hurt)
var flinch_chance: float = 0.0
var hitpause: float = 0.0
var invulnerable_time: float = 0.0
var impalable: bool = true  # false for big enemies and bosses: Skewer staggers them instead
var ragdoll: Ragdoll
var impaled: bool = false   # skewered on the player's sword (Skewer); the player carries it, its AI is paused
var _saved_collision: Vector2i = Vector2i.ZERO
var is_boss: bool = false  # bosses ignore shoves and forced interrupts (see interrupt())
var slow_time: float = 0.0
var slow_amount: float = 0.0   # fraction of speed removed while slowed

var visual: Node3D
var model: CharacterModel
var _saved_speed: float = 1.0
var highlighted: bool = false  # lit up as a target (e.g. inside an aimed spell's blast)
var _flash: float = 0.0
var _flash_mat: StandardMaterial3D

func _build_model(folder: String, clips: Array[String], height: float, radius: float) -> void:
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
	model = CharacterModel.build(folder, clips)
	visual.add_child(model)

	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1.0, 0.25, 0.2, 0.0)

## Returns true while frozen by a hit-pause; callers should skip their own logic for that frame.
func _actor_tick(delta: float) -> bool:
	if hitpause > 0.0:
		hitpause -= delta
		if hitpause <= 0.0:
			hitpause = 0.0
			model.anim.speed_scale = _saved_speed
		return true
	stun_time = maxf(stun_time - delta, 0.0)
	invulnerable_time = maxf(invulnerable_time - delta, 0.0)
	bar_timer = maxf(bar_timer - delta, 0.0)
	slow_time = maxf(slow_time - delta, 0.0)
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
const SWORD_SKILLS: Array[String] = ["basic", "power", "skewer", "leap"]

## Apply a resolved attack (see Combat.resolve) to this actor.
func receive(result: Dictionary, source_pos: Vector3) -> void:
	if dead:
		return
	_last_hit_from = source_pos
	_last_hit_ms = Time.get_ticks_msec()
	if invulnerable_time > 0.0:
		Fx.text_at(self, global_position + Vector3(0, 2.2, 0), "Dodge", Color(0.6, 0.95, 1.0), 40)
		return
	result = _filter_incoming(result)
	if result.get("quiet", false):
		# Damage-over-time style tick: apply it, show the health bar, nothing else.
		bar_timer = 4.0
		_apply_damage(float(result["damage"]))
		return
	var outcome: int = result["outcome"]
	var damage: float = result["damage"]
	if ward_time > 0.0:
		damage *= 1.0 - ward_reduction   # a plague ward soaks part of every blow
	var weight: float = result.get("weight", 1.0)
	var source: Actor = result.get("source")
	var chest: Vector3 = global_position + Vector3(0, body_height * 0.65, 0)
	# A "calm" hit (the Earthshatter shockwave striking a whole crowd at once) skips the per-enemy blood, numbers, flashes, shake and
	# hit-pause: ten of those at the same instant would bury the move in noise.
	var calm: bool = bool(result.get("calm", false))
	var away: Vector3 = global_position - source_pos
	away.y = 0.0
	away = away.normalized()

	if not calm:
		Fx.popup(self, outcome, damage, _popup_tint())
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
	# A killing blow that is a crit (or a crushing blow) bursts the body; a direct fire kill (a fireball, not a
	# secondary proc) bursts it into burning pieces.
	if health - damage <= 0.0 and not is_in_group("player"):
		if fire and not result.get("secondary", false):
			_pending_gib = "fire"
		elif not calm and (outcome == Combat.Outcome.CRITICAL or outcome == Combat.Outcome.CRUSHING):
			_pending_gib = "gore"
		_gib_from = source_pos
	_apply_damage(damage)

	# Layered impact feedback: sound, spray, light, squash, camera, pause, push.
	var killed: bool = dead
	var big: bool = outcome == Combat.Outcome.CRUSHING or outcome == Combat.Outcome.CRITICAL
	if sword_contact:
		Sfx.sword_hit(self, outcome, weight)
	if not calm:
		var amount: int = int(clampf(6.0 + damage * 0.5 + weight * 4.0, 6.0, 40.0)) * (2 if big else 1)
		Fx.burst(self, chest, away + Vector3.UP * 0.6, _blood_color(), amount, 4.0 + weight * 2.5 + (3.0 if big else 0.0))
		if big or randf() < 0.3:
			Fx.blood_decal(self, global_position + away * 0.5, randf_range(0.5, 0.9) * (1.3 if big else 1.0), _blood_color().darkened(0.4))
		if big:
			Fx.light_flash(self, chest, Color(1.0, 0.85, 0.6), 2.5, 0.08)
	if not dead:
		_flash = 1.0
		model.set_overlay(_flash_mat)
		_squash(away, 0.08 * weight + (0.1 if big else 0.0))

	if not calm:
		var shake_amount: float = clampf(0.03 + damage * 0.004, 0.03, 0.12) * weight
		Fx.shake(self, shake_amount)
		if source != null and source.is_in_group("player") or is_in_group("player"):
			Fx.kick(self, -away if is_in_group("player") else away, 0.5 * weight)

	# Hit-pause on both parties makes the blow land; crits add a brief global slow-down.
	var pause: float = 0.06 * weight + (0.045 if big else 0.0)
	# The hero is never frozen by being hit: a crowd landing blows would otherwise stutter every skill to a halt.
	if not calm:
		if not killed and not is_in_group("player"):
			add_hitpause(pause)
		if source != null and source != self:
			source.add_hitpause(pause)
		if outcome == Combat.Outcome.CRUSHING:
			Fx.hitstop(self, 0.07)
		elif outcome == Combat.Outcome.CRITICAL:
			Fx.hitstop(self, 0.045)

	# Equipment reacts to every landed hit (including the one that killed).
	if source is Player and source != self:
		(source as Player).on_dealt_hit(self, result)
	if killed:
		return
	var push: float = 2.5
	var hero: bool = is_in_group("player")
	match outcome:
		Combat.Outcome.CRUSHING:
			push = 9.0
			stun_time = maxf(stun_time, (0.5 if hero else 0.8) * (1.0 - stun_resist))
		Combat.Outcome.CRITICAL:
			push = 5.5
			if not hero:
				stun_time = maxf(stun_time, 0.3 * (1.0 - stun_resist))
		_:
			# Ordinary blows only flinch enemies. The hero keeps swinging, casting and moving through them.
			if not hero and (weight >= 1.5 or randf() < flinch_chance):
				stun_time = maxf(stun_time, 0.25 * weight * (1.0 - stun_resist))
	var shove: float = push * weight * (1.0 - knock_resist)
	if hero:
		shove *= 0.2 if is_acting() else 0.5   # mid-skill the hero is planted
	knock += away * shove
	if outcome == Combat.Outcome.DEEP_WOUNDS:
		bleed_dps = result["bleed_dps"]
		bleed_time = result["bleed_time"]
	_on_hurt(result, source_pos)

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
		highlight_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		highlight_material.albedo_color = Color(1.0, 0.42, 0.08, 0.35)
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
	return 1.0 - slow_amount if slow_time > 0.0 else 1.0

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

## Passes burn, bleed and slow on to another actor (e.g. a burning body thrown into a crowd).
func spread_debuffs_to(other: Actor) -> void:
	if burn_time > 0.0:
		other.apply_burn(burn_dps, burn_time)
	if bleed_time > 0.0:
		other.bleed_dps = maxf(other.bleed_dps, bleed_dps)
		other.bleed_time = maxf(other.bleed_time, bleed_time)
	if slow_time > 0.0:
		other.apply_slow(slow_amount, slow_time)

## Sets the actor alight: fire damage over time with visible flames until it burns out or dies.
func apply_burn(dps: float, seconds: float) -> void:
	if dead:
		return
	burn_dps = maxf(burn_dps, dps)
	burn_time = maxf(burn_time, seconds)
	if _flames == null and model != null:
		_flames = _make_flames()
		add_child(_flames)

func _tick_burn(delta: float) -> void:
	if burn_time <= 0.0:
		return
	burn_time -= delta
	_apply_damage(burn_dps * delta)
	if _flames != null:
		_flames.visible = not is_ragdolled()   # no flame trail across the sky while thrown, and none on a body lying stunned
	if burn_time <= 0.0 or dead:
		stop_burning()

func stop_burning() -> void:
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

func _popup_tint() -> Color:
	return Color(0, 0, 0, 0)

func _apply_damage(amount: float) -> void:
	if dead:
		return
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
