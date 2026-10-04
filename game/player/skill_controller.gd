class_name SkillController
extends RefCounted
## Skill use: hotkeys and the aim preview, starting and ticking a skill, the basic combo, strike effects and blade blood.

var p: Player

func _init(player: Player) -> void:
	p = player

const COMBO_WINDOW := 0.9
var hotbar: Array[String] = ["power", "cleave", "fireball", "potion", "skewer", "leap"]
var right_click_skill: String = "basic"
var _glow_light: OmniLight3D
var _haste_fx: CPUParticles3D
var _riposte_light: OmniLight3D
var queued_skill: String = ""
var queued_target: Actor
var busy: bool = false
var busy_skill: String = ""
var busy_target: Actor
var busy_t: float = 0.0
var busy_hit_done: bool = false
var busy_aim: Vector3 = Vector3.ZERO
var busy_def: Dictionary = {}
var combo_step: int = 0
var combo_timer: float = 0.0
var busy_time: float = 0.8
var blade_blood: float = 0.0    # 0..1 how bloody the sword is; fades slowly
var _blood_mat: ShaderMaterial
var _fire_orb: FireOrb
var _release_started: bool = false
var aiming_id: String = ""
var aiming_action: String = ""
var aim_point: Vector3 = Vector3.ZERO
var _aim_root: Node3D
var _aim_sphere_mat: StandardMaterial3D
var _aim_line: MeshInstance3D
var _highlighted: Array[Actor] = []
var _swing_sound_played: bool = false
## A basic swing can always be abandoned by clicking away; heavier melee skills only once the blow has landed.
func _swing_cancellable_by_move() -> bool:
	var kind: String = String(busy_def.get("kind", ""))
	if kind != "melee" and kind != "cleave":
		return false
	return busy_skill == "basic" or busy_hit_done

## Hotkeys are read every frame, whatever the hero is doing, and cancel the current animation:
##  - the potion drinks at once (even while stunned);
##  - any other usable skill interrupts a swing/cast/charge and then starts through the normal path;
##  - a skill that cannot be used (cooldown, no mana, nothing to hit) tells you why and does NOT cancel anything.
func _handle_hotkeys(cursor: Vector3) -> void:
	if p.dead:
		return
	for i in hotbar.size():
		var action: String = "skill_%d" % (i + 1)
		if not Input.is_action_just_pressed(action):
			continue
		var id: String = hotbar[i]
		if id == "potion":
			if p.stats._use_potion() and busy and not p.movement.rolling:
				_cancel_action()
		elif busy and not p.movement.rolling and p.stun_time <= 0.0:
			if not p.stats._can_use(id):
				if p.stats.mana < float(SkillDb.all()[id]["mana"]):
					p._say("Not enough mana")
				else:
					p._say("%s is on cooldown" % SkillDb.all()[id]["name"])
			elif _hotkey_would_start(id, cursor):
				_cancel_action()

## Whether pressing this skill's key right now would actually start it (targeted skills need an enemy near the cursor).
func _hotkey_would_start(id: String, cursor: Vector3) -> bool:
	var skill: Dictionary = SkillDb.all()[id]
	if skill.get("directional", false) or skill.get("aimed", false):
		return true
	return p.enemy_near(cursor, 12.0) != null

## Aborts the current swing, cast or charge immediately.
func _cancel_action() -> void:
	if not busy:
		return
	if bool(busy_def.get("skewer", false)):
		p.skewer._end_skewer()  # releases anyone on the blade and restores collision
	if bool(busy_def.get("leap", false)):
		p.leap._end_leap()
	if bool(busy_def.get("charged", false)):
		_drop_orb()
	busy = false
	busy_hit_done = true
	queued_skill = ""
	if p._trail != null:
		p._trail.active = false
	if p.visual != null:
		p.visual.rotation.x = 0.0
	p.model.loop("idle_alert")

## Skills that launch in a direction (Skewer) trigger on press, toward the cursor.
func _try_directional(id: String, cursor: Vector3) -> void:
	if not p.stats._can_use(id):
		if p.stats.mana < float(SkillDb.all()[id]["mana"]):
			p._say("Not enough mana")
		return
	if bool(SkillDb.all()[id].get("leap", false)):
		p.leap._start_leap(cursor)
	else:
		p.skewer._start_skewer(cursor)

## Holding the key aims; letting go casts at the point under the cursor.
func _handle_aimed_key(action: String, id: String, cursor: Vector3) -> void:
	if Input.is_action_pressed(action):
		aiming_id = id
		aiming_action = action
		p.movement.has_goal = false
	elif aiming_id == id and aiming_action == action:
		_release_aim(cursor)

func _release_aim(cursor: Vector3) -> void:
	var id: String = aiming_id
	var point: Vector3 = aim_point_for(id, cursor)
	if not p.stats._can_use(id):
		_clear_aim()
		if p.stats.mana < float(SkillDb.all()[id]["mana"]):
			p._say("Not enough mana")
		return
	_clear_aim(true)
	_start_skill(id, null, point)

func _clear_aim(keep_orb: bool = false) -> void:
	if not keep_orb:
		_drop_orb()
	aiming_id = ""
	aiming_action = ""
	for e in _highlighted:
		if is_instance_valid(e):
			e.set_highlighted(false)
	_highlighted.clear()
	if _aim_root != null:
		_aim_root.visible = false
	if _aim_line != null:
		_aim_line.visible = false

## The cursor point on the ground, pulled in to the skill's range if it is too far.
func aim_point_for(id: String, cursor: Vector3) -> Vector3:
	var reach: float = float(SkillDb.all()[id]["range"])
	var flat: Vector3 = cursor - p.global_position
	flat.y = 0.0
	if flat.length() > reach:
		flat = flat.normalized() * reach
	return p.global_position + flat

## Per-frame preview while aiming: sphere at the impact point, ring on the ground, a line from the hero,
## and every enemy inside the blast lit up.
func _update_aim(cursor: Vector3) -> void:
	if aiming_id == "":
		return
	aim_point = aim_point_for(aiming_id, cursor)
	if bool(SkillDb.all()[aiming_id].get("charged", false)) and not busy:
		_ensure_orb(0.28)
	_ensure_aim_nodes()
	_aim_root.visible = true
	var radius: float = Projectile.BLAST_RADIUS
	var centre: Vector3 = aim_point + Vector3(0, 0.8, 0)
	_aim_root.global_transform = Transform3D(Basis(), Vector3(aim_point.x, 0.0, aim_point.z))
	(_aim_root.get_node("Sphere") as Node3D).position = Vector3(0, 0.8, 0)
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
	_aim_sphere_mat.albedo_color.a = 0.16 + 0.1 * pulse
	Actor.get_highlight_material().albedo_color.a = 0.3 + 0.2 * pulse
	# Line from the hero to the target.
	var from: Vector3 = p.global_position + Vector3(0, 1.1, 0)
	var length: float = from.distance_to(centre)
	_aim_line.visible = length > 0.2
	if _aim_line.visible:
		var up: Vector3 = (centre - from).normalized()
		var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
		(_aim_line.mesh as CylinderMesh).height = length
		_aim_line.global_transform = Transform3D(Basis(side.cross(up).normalized(), up, side), (from + centre) * 0.5)
	# Highlight everything the blast would hit.
	var now_hit: Array[Actor] = []
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead:
			continue
		var gap: Vector3 = e.global_position - aim_point
		gap.y = 0.0
		if gap.length() <= radius + e.body_radius * 0.5:
			now_hit.append(e)
	for e in _highlighted:
		if is_instance_valid(e) and not (e in now_hit):
			e.set_highlighted(false)
	for e in now_hit:
		e.set_highlighted(true)
	_highlighted = now_hit

func _ensure_orb(size: float) -> void:
	if _fire_orb == null or not is_instance_valid(_fire_orb):
		_fire_orb = FireOrb.new()
		p.add_child(_fire_orb)
		_fire_orb.global_position = _orb_home()
		_fire_orb.grow_to(size, 0.3)

func _drop_orb() -> void:
	if _fire_orb != null and is_instance_valid(_fire_orb):
		_fire_orb.fade_out()
	_fire_orb = null

## Over the head, where the raised hands end up at the top of the gather.
func _orb_home() -> Vector3:
	return p.get_global_transform_interpolated().origin + Vector3(0, p.body_height + 0.8, 0)

func _ensure_aim_nodes() -> void:
	if _aim_root != null:
		return
	_aim_root = Node3D.new()
	_aim_root.top_level = true
	_aim_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.add_child(_aim_root)
	_aim_sphere_mat = StandardMaterial3D.new()
	_aim_sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_sphere_mat.albedo_color = Color(1.0, 0.42, 0.08, 0.22)
	_aim_sphere_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sphere := MeshInstance3D.new()
	sphere.name = "Sphere"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = Projectile.BLAST_RADIUS
	sphere_mesh.height = Projectile.BLAST_RADIUS * 2.0
	sphere.mesh = sphere_mesh
	sphere.material_override = _aim_sphere_mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_root.add_child(sphere)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.95)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = Projectile.BLAST_RADIUS - 0.07
	torus.outer_radius = Projectile.BLAST_RADIUS
	ring.mesh = torus
	ring.material_override = ring_mat
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_root.add_child(ring)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.16
	core_mesh.height = 0.32
	core.mesh = core_mesh
	core.material_override = ring_mat
	core.position.y = 0.8
	_aim_root.add_child(core)
	_aim_line = MeshInstance3D.new()
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = 0.025
	line_mesh.bottom_radius = 0.025
	_aim_line.mesh = line_mesh
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.45)
	_aim_line.material_override = line_mat
	_aim_line.top_level = true
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(_aim_line)

func _queue_skill(id: String, cursor: Vector3) -> void:
	var target: Actor = p.enemy_near(cursor, 12.0)
	if target == null:
		return
	queued_skill = id
	queued_target = target
	p.movement.has_goal = false

func _start_skill(id: String, target: Actor, aim: Variant = null) -> void:
	var skill: Dictionary = SkillDb.all()[id]
	if id == "basic":
		skill = _next_basic()
	busy_def = skill
	busy_time = float(skill["time"]) / p.stats.attack_speed()
	if String(skill["kind"]) == "cleave":
		ItemEffects.pull_for_cleave(p)
	p.stats.mana -= float(skill["mana"])
	p.stats.cooldowns[id] = float(skill["cd"])
	busy = true
	busy_skill = id
	busy_target = target
	busy_t = 0.0
	busy_hit_done = false
	busy_aim = aim if aim != null else target.global_position
	p.combat_timer = 5.0
	p.movement.has_goal = false
	p.face(busy_aim)
	if id == queued_skill:
		queued_skill = ""
	# A click attacks once; the hero only keeps swinging while the attack button is held. Any other skill
	# replaces the attack order, so the hero never starts auto-attacking again once the skill ends.
	if id != "basic" or not (Input.is_action_pressed("click") or Input.is_action_pressed("alt_skill")):
		p.attack_target = null
	_swing_sound_played = false
	_release_started = false
	_style_trail(id)
	p.model.manual(skill["clip"])
	p.model.scrub(float(skill["start"]))
	if bool(skill.get("charged", false)):
		_ensure_orb(0.28)
		_fire_orb.grow_to(0.55, float(skill["gather"]) * busy_time / float(skill["time"]))
		Fx.ring(p, p.global_position, 1.8, Color(1.0, 0.55, 0.15))
		Fx.light_flash(p, p.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 2.0, 0.3)

## Blade ribbon colour and length per skill: plain steel for the combo, hot orange for Power Strike, icy white for Cleave.
func _style_trail(id: String) -> void:
	if p._trail == null:
		return
	match id:
		"power":
			p._trail.tint = Color(1.0, 0.62, 0.25)
			p._trail.max_age = 0.34
			p._trail.strength = 0.85
		"cleave":
			p._trail.tint = Color(0.75, 0.92, 1.0)
			p._trail.max_age = 0.4
			p._trail.strength = 0.8
		_:
			p._trail.tint = Color(1.0, 0.92, 0.75)
			p._trail.max_age = WeaponTrail.DEFAULT_AGE
			p._trail.strength = 0.4

## The blade glows as a heavy skill is wound up (a light on the tip that peaks at the strike, then fades).
func _blade_glow(u: float, hit_frac: float) -> void:
	if p.model == null or p.model.weapon_tip == null:
		return
	if _glow_light == null:
		_glow_light = OmniLight3D.new()
		_glow_light.omni_range = 4.0
		p.model.weapon_tip.add_child(_glow_light)
	_glow_light.light_color = Color(1.0, 0.6, 0.25) if busy_skill == "power" else Color(0.7, 0.9, 1.0)
	if u < hit_frac:
		_glow_light.light_energy = 3.5 * pow(u / hit_frac, 2.0)
	else:
		_glow_light.light_energy = 3.5 * clampf(1.0 - (u - hit_frac) / 0.3, 0.0, 1.0)

## Gear buffs you can see: a haste wake behind you, and a gold glow on the blade while a riposte is ready.
func _update_buff_visuals() -> void:
	if _glow_light != null and not (busy and (busy_skill == "power" or busy_skill == "cleave")):
		_glow_light.light_energy = 0.0
	if _haste_fx == null and p.stats.haste_time > 0.0:
		_haste_fx = _make_haste_fx()
		p.add_child(_haste_fx)
	if _haste_fx != null:
		_haste_fx.emitting = p.stats.haste_time > 0.0
	var riposte_on: bool = p.stats.riposte_time > 0.0 and p.model != null and p.model.weapon_tip != null
	if riposte_on and _riposte_light == null:
		_riposte_light = OmniLight3D.new()
		_riposte_light.light_color = Color(1.0, 0.85, 0.35)
		_riposte_light.omni_range = 3.5
		_riposte_light.light_energy = 0.0
		p.model.weapon_tip.add_child(_riposte_light)
	if _riposte_light != null:
		var pulse: float = 1.6 + 0.8 * sin(Time.get_ticks_msec() * 0.012)
		_riposte_light.light_energy = pulse if riposte_on else 0.0

func _make_haste_fx() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0, 0.5, 0)
	p.position = Vector3(0, 0.5, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 0.25, 0.8))
	ramp.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	p.color_ramp = ramp
	return p

## Picks the next swing of the combo and returns it merged over the basic attack stats.
func _next_basic() -> Dictionary:
	var variants: Array = SkillDb.basic_combo()[combo_step]
	var skill: Dictionary = SkillDb.all()["basic"].duplicate()
	skill.merge(variants[randi() % variants.size()], true)
	combo_step = (combo_step + 1) % SkillDb.basic_combo().size()
	combo_timer = COMBO_WINDOW + float(skill["time"])
	return skill

func _tick_busy(delta: float) -> void:
	busy_t += delta
	var skill: Dictionary = busy_def
	if bool(skill.get("skewer", false)):
		p.skewer._tick_skewer(delta)
		return
	if bool(skill.get("leap", false)):
		p.leap._tick_leap(delta)
		return
	if bool(skill.get("charged", false)):
		_tick_charged(skill)
		return
	if busy_target != null and not busy_target.dead:
		busy_aim = busy_target.global_position
	var duration: float = busy_time
	var hit_at: float = duration * hit_fraction(skill)
	# Whoosh just before the blow so the sound leads the impact.
	if not _swing_sound_played and busy_t >= hit_at - 0.14:
		_swing_sound_played = true
		match String(skill["kind"]):
			"melee", "cleave":
				Sfx.play(p, "swing_heavy" if float(skill["weight"]) > 1.3 else "swing", -3.0)
			"projectile":
				Sfx.play(p, "fire_whoosh", -4.0)
	if not busy_hit_done and busy_t >= hit_at:
		busy_hit_done = true
		_apply_skill(skill)
		_lunge(float(skill["lunge"]))
		_strike_fx(skill)
	var u: float = busy_t / duration
	var hf: float = hit_fraction(skill)
	if busy_skill == "power" or busy_skill == "cleave":
		_blade_glow(u, hf)
	if p._trail != null:
		p._trail.active = String(skill["kind"]) in ["melee", "cleave"] and u > hf - 0.35 and u < hf + 0.22
	if String(skill["kind"]) in ["melee", "cleave"]:
		# Coil back while gathering the swing, then throw the weight forward through the strike.
		var heft: float = clampf(float(skill["weight"]), 0.8, 1.7)
		if u < hf:
			p.visual.rotation.x = -0.14 * heft * sin(clampf(u / hf, 0.0, 1.0) * PI * 0.5)
		else:
			p.visual.rotation.x = lerpf(0.2 * heft, 0.0, clampf((u - hf) / (1.0 - hf) * 1.5, 0.0, 1.0))
	p.model.scrub(CharacterModel.remap(busy_t / duration, hit_fraction(skill),
		float(skill["start"]), float(skill["strike"]), float(skill["end"])))
	if busy_t >= duration:
		busy = false
		if p._trail != null:
			p._trail.active = false

## Two-phase cast: arms rise and the orb swells (gather), then both hands drive forward and it is thrown.
func _tick_charged(skill: Dictionary) -> void:
	var scale_factor: float = busy_time / float(skill["time"])
	var t_gather: float = float(skill["gather"]) * scale_factor
	var t_throw: float = t_gather + float(skill["release_after"]) * scale_factor
	p.face(busy_aim, 0.2)
	if busy_t < t_gather:
		var u: float = clampf(busy_t / t_gather, 0.0, 1.0)
		# Slow at first (the weight of pulling fire out of the air), then the arms rush up.
		p.model.scrub(lerpf(float(skill["start"]), float(skill["strike"]), pow(u, 1.7)))
		p.visual.rotation.x = -0.14 * sin(u * PI * 0.5)
		Fx.shake(p, 0.008 + 0.02 * u)  # faint tremble that builds with the charge
	else:
		if not _release_started:
			_release_started = true
			p.model.once(String(skill["release_clip"]), float(skill["release_start"]),
				float(skill["release_speed"]) / scale_factor, 0.12)
			_lunge(float(skill["lunge"]))
			Fx.punch(p, 1.0)
		p.visual.rotation.x = 0.22 * (1.0 - clampf((busy_t - t_throw) / 0.3, 0.0, 1.0))
		if not busy_hit_done and busy_t >= t_throw:
			busy_hit_done = true
			_apply_skill(skill)
			Fx.shake(p, 0.12)
			Fx.punch(p, 2.4)
			Fx.ring(p, p.global_position, 2.2, Color(1.0, 0.6, 0.2))
	if busy_t >= busy_time:
		busy = false

## Weight of the blow itself, independent of whether it connects: camera punch, dust, ground shock.
func _strike_fx(skill: Dictionary) -> void:
	if not (String(skill["kind"]) in ["melee", "cleave"]):
		return
	if busy_skill == "power" or busy_skill == "cleave":
		return   # these have their own, much bigger impact effects (SkillFx)
	var weight: float = float(skill["weight"])
	var dir: Vector3 = busy_aim - p.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	Fx.shake(p, 0.03 + 0.05 * weight)
	Fx.punch(p, 0.6 + 1.2 * weight)
	Fx.burst(p, p.global_position + dir * 1.3 + Vector3(0, 0.05, 0), dir + Vector3.UP * 0.4, Color(0.5, 0.45, 0.38),
		int(5 + 6 * weight), 2.2 + weight, 0.04)
	if weight >= 1.5:
		Fx.ring(p, p.global_position + dir * 1.2, 1.7, Color(0.9, 0.85, 0.7))

## Steps toward the target, but never into it: the lunge only closes the gap that actually exists.
func _lunge(max_distance: float) -> void:
	if max_distance <= 0.0:
		return
	var to_aim: Vector3 = busy_aim - p.global_position
	to_aim.y = 0.0
	var target_radius: float = busy_target.body_radius if busy_target != null else 0.0
	var gap: float = to_aim.length() - target_radius - p.body_radius - 0.15
	var travel: float = clampf(gap, 0.0, max_distance)
	if travel <= 0.02:
		return
	# knock decays at 22 m/s^2, so an impulse of v covers v^2 / 44 metres.
	p.knock += to_aim.normalized() * sqrt(44.0 * travel)

static func hit_fraction(skill: Dictionary) -> float:
	return (float(skill["strike"]) - float(skill["start"])) / (float(skill["end"]) - float(skill["start"]))

## Power Strike lands: crater, rings, rocks and cracks at the point of impact, splash on neighbours, and a shove.
func _power_impact() -> void:
	var dir: Vector3 = busy_aim - p.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	var point: Vector3 = p.global_position + dir * 1.9
	if busy_target != null and is_instance_valid(busy_target):
		point = busy_target.global_position
	point.y = 0.0
	SkillFx.power_impact(p, point, dir, p.stats.has_affix("gravewarden"))
	Fx.hitstop(p, 0.08)
	if busy_target != null and is_instance_valid(busy_target) and not busy_target.dead:
		busy_target.interrupt(0.7)
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e == busy_target:
			continue
		var gap: Vector3 = e.global_position - point
		gap.y = 0.0
		if gap.length() > POWER_SPLASH_RADIUS + e.body_radius:
			continue
		var splash: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(float(SkillDb.all()["power"]["mult"]) * 0.5), Combat.DamageType.PHYSICAL, false, 1.5)
		splash["skill_id"] = "power"
		splash["secondary"] = true
		e.receive(splash, point)
		if is_instance_valid(e) and not e.dead:
			e.interrupt(0.5)
	ItemEffects.power_shockwave(p, dir)

const POWER_SPLASH_RADIUS := 2.0
func _apply_skill(skill: Dictionary) -> void:
	var mult: float = skill["mult"]
	match String(skill["kind"]):
		"melee":
			if busy_target != null and not busy_target.dead \
					and p.flat_distance_to(busy_target) - busy_target.body_radius <= float(skill["range"]) + 0.5:
				var guaranteed_crit: bool = p.stats.riposte_time > 0.0
				var damage: float = p.stats.weapon_damage(mult) * ItemEffects.outgoing_multiplier(p, busy_target)
				var result: Dictionary = Combat.resolve(p, busy_target, damage, Combat.DamageType.PHYSICAL,
					not guaranteed_crit, float(skill["weight"]), guaranteed_crit)
				result["skill_id"] = busy_skill
				result["finisher"] = skill.get("finisher", false)
				if guaranteed_crit:
					p.stats.riposte_time = 0.0
				busy_target.receive(result, p.global_position)
			if busy_skill == "power":
				_power_impact()
		"cleave":
			var cleave_hits: int = 0
			for node in p.get_tree().get_nodes_in_group("enemies"):
				var e := node as Actor
				if e != null and not e.dead and p.flat_distance_to(e) - e.body_radius <= float(skill["range"]):
					var swing: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(mult) * ItemEffects.outgoing_multiplier(p, e),
						Combat.DamageType.PHYSICAL, true, float(skill["weight"]))
					swing["skill_id"] = busy_skill
					e.receive(swing, p.global_position)
					cleave_hits += 1
					SkillFx.cleave_hit(p, e)
			SkillFx.cleave_burst(p, float(skill["range"]))
			if cleave_hits > 0:
				Fx.hitstop(p, 0.05)
				Fx.punch(p, 1.2 + 0.4 * minf(cleave_hits, 4))
		"projectile":
			var ball := Projectile.new()
			ball.owner_actor = p
			var dir: Vector3 = busy_aim - p.global_position
			dir.y = 0.0
			ball.direction = dir.normalized()
			ball.damage = 14.0 + p.stats.strength * 0.4
			ball.destination = busy_aim + Vector3(0, 0.8, 0)
			p.get_tree().current_scene.add_child(ball)
			var origin: Vector3 = p.global_position + Vector3(0, 1.2, 0) + ball.direction * 0.8
			if _fire_orb != null and is_instance_valid(_fire_orb):
				origin = _fire_orb.release()  # the gathered orb is the fireball that gets thrown
				_fire_orb = null
			ball.global_position = origin
			if p.stats.has_affix("twin_flame"):
				var twin := Projectile.new()
				twin.owner_actor = p
				twin.direction = ball.direction.rotated(Vector3.UP, 0.4)
				twin.damage = ball.damage * 0.6
				var offset: Vector3 = (busy_aim - p.global_position).rotated(Vector3.UP, 0.35)
				twin.destination = p.global_position + offset + Vector3(0, 0.8, 0)
				p.get_tree().current_scene.add_child(twin)
				twin.global_position = ball.global_position

## The sword stays red while it is bloody and slowly dries.
func _update_blade_blood(delta: float) -> void:
	if p.model == null or p.model.weapon == null:
		return
	blade_blood = maxf(blade_blood - delta * 0.04, 0.0)
	if blade_blood <= 0.02:
		if _blood_mat != null:
			p.model.set_weapon_overlay(null)
			_blood_mat = null
		return
	if _blood_mat == null:
		_blood_mat = p.model.make_blade_blood_material()
		p.model.set_weapon_overlay(_blood_mat)
	_blood_mat.set_shader_parameter("amount", clampf(blade_blood, 0.0, 1.0))
