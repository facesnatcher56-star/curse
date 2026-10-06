class_name SkillController
extends RefCounted
## Skill use: hotkeys and the aim preview, starting and ticking a skill, the basic combo, strike effects and blade blood.

var p: Player

func _init(player: Player) -> void:
	p = player

const COMBO_WINDOW := 0.9
var hotbar: Array[String] = ["power", "fireball", "potion", "skewer", "leap", "earthshatter"]
var right_click_skill: String = "basic"
var _glow_light: OmniLight3D
var _haste_fx: CPUParticles3D
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
var fire_orb: FireOrb
var _release_started: bool = false
var aiming_id: String = ""
var aim_blocked: String = ""      # an aim key that was cancelled and is still held down
var swallow_alt: bool = false      # the right-click that cancelled something must not also start an attack
var aiming_action: String = ""
var aim_point: Vector3 = Vector3.ZERO
var _aim_root: Node3D
var _aim_sphere_mat: StandardMaterial3D
var _aim_line: MeshInstance3D
var _lane: SkewerPreview   # the lane Skewer shows while its key is held
var _highlighted: Array[Actor] = []
## A basic swing can always be abandoned by clicking away; heavier melee skills only once the blow has landed.
func swing_cancellable_by_move() -> bool:
	var kind: String = String(busy_def.get("kind", ""))
	if kind != "melee":
		return false
	return busy_skill == "basic" or busy_hit_done

## Hotkeys are read every frame, whatever the hero is doing, and cancel the current animation:
##  - the potion drinks at once (even while stunned);
##  - any other usable skill interrupts a swing/cast/charge and then starts through the normal path;
##  - a skill that cannot be used (cooldown, no mana, nothing to hit) tells you why and does NOT cancel anything.
func handle_hotkeys(cursor: Vector3) -> void:
	if p.dead:
		return
	for i in hotbar.size():
		var action: String = "skill_%d" % (i + 1)
		if not Input.is_action_just_pressed(action):
			continue
		var id: String = hotbar[i]
		if id == "potion":
			if p.stats.use_potion() and busy and not p.movement.rolling:
				cancel_action()
		elif busy and not p.movement.rolling and p.stun_time <= 0.0:
			if not p.stats.can_use(id):
				if p.stats.mana < float(SkillDb.all()[id]["mana"]):
					p._say("Not enough mana")
				else:
					p._say("%s is on cooldown" % SkillDb.all()[id]["name"])
			elif _hotkey_would_start(id, cursor):
				cancel_action()

## Whether pressing this skill's key right now would actually start it (targeted skills need an enemy near the cursor).
func _hotkey_would_start(id: String, cursor: Vector3) -> bool:
	var skill: Dictionary = SkillDb.all()[id]
	if skill.get("directional", false) or skill.get("aimed", false):
		return true
	return p.enemy_near(cursor, 12.0) != null

## Aborts the current swing, cast or charge immediately.
func cancel_action() -> void:
	if not busy:
		return
	if bool(busy_def.get("skewer", false)):
		p.skewer.end_skewer()  # releases anyone on the blade and restores collision
	if bool(busy_def.get("leap", false)):
		p.leap.end_leap()
	if bool(busy_def.get("earthshatter", false)):
		p.earthshatter.end()
	if bool(busy_def.get("charged", false)):
		drop_orb()
	busy = false
	busy_hit_done = true
	queued_skill = ""
	if p._trail != null:
		p._trail.active = false
	if p.visual != null:
		p.visual.rotation.x = 0.0
	p.model.loop("idle_alert")

## Skills that launch in a direction (Skewer) trigger on press, toward the cursor.
func try_directional(id: String, cursor: Vector3) -> void:
	if not p.stats.can_use(id):
		if p.stats.ult_charge < p.stats.ult_cost(id):
			p._say("%s is %d%% charged" % [SkillDb.all()[id]["name"], int(p.stats.ult_fraction(id) * 100.0)])
		elif p.stats.mana < float(SkillDb.all()[id]["mana"]):
			p._say("Not enough mana")
		return
	if bool(SkillDb.all()[id].get("earthshatter", false)):
		p.earthshatter.start(cursor)
	elif bool(SkillDb.all()[id].get("leap", false)):
		p.leap.start_leap(cursor)
	else:
		p.skewer.start_skewer(cursor)

## Right-click or dodge backs out of a Fireball. While aiming nothing has been spent; during the wind-up the mana and cooldown come
## back. Once the fireball has left the hand it is thrown, and nothing cancels it.
func check_cancel() -> void:
	var alt: bool = Input.is_action_just_pressed("alt_skill") and aiming_action != "alt_skill"
	var dodge: bool = Input.is_action_just_pressed("dodge")
	if not (alt or dodge):
		return
	if aiming_id != "":
		aim_blocked = aiming_action   # the aim key may still be held: letting go of it must not cast
		clear_aim()
		if alt:
			swallow_alt = true
		p._say("Cancelled")
	elif busy and bool(busy_def.get("charged", false)) and not busy_hit_done:
		p.stats.mana = minf(p.stats.mana + float(busy_def["mana"]), p.stats.max_mana)
		p.stats.cooldowns[busy_skill] = 0.0
		cancel_action()
		if alt:
			swallow_alt = true
		p._say("Cancelled")

## Holding the key aims; letting go casts at the point under the cursor.
func handle_aimed_key(action: String, id: String, cursor: Vector3) -> void:
	if Input.is_action_pressed(action):
		if aim_blocked == action:
			return   # cancelled while this key was held: nothing happens until it is released
		aiming_id = id
		aiming_action = action
		p.movement.has_goal = false
	elif aim_blocked == action:
		aim_blocked = ""
	elif aiming_id == id and aiming_action == action:
		_release_aim(cursor)

func _release_aim(cursor: Vector3) -> void:
	var id: String = aiming_id
	var point: Vector3 = aim_point_for(id, cursor)
	if not p.stats.can_use(id):
		clear_aim()
		if p.stats.mana < float(SkillDb.all()[id]["mana"]):
			p._say("Not enough mana")
		return
	clear_aim(true)
	if bool(SkillDb.all()[id].get("skewer", false)):
		p.skewer.start_skewer(point)   # (its own charge, not a timed skill)
		return
	start_skill(id, null, point)

func clear_aim(keep_orb: bool = false) -> void:
	if not keep_orb:
		drop_orb()
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
	if _lane != null:
		_lane.hide_lane()

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
func update_aim(cursor: Vector3) -> void:
	if aiming_id == "":
		return
	aim_point = aim_point_for(aiming_id, cursor)
	if bool(SkillDb.all()[aiming_id].get("skewer", false)):
		_update_lane(cursor)
		return
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

## Skewer's preview: the lane the charge will run and the fan the kick throws across, with the enemies the blade would take lit up.
func _update_lane(cursor: Vector3) -> void:
	if _lane == null:
		_lane = SkewerPreview.new(p)
	var dir: Vector3 = cursor - p.global_position
	dir.y = 0.0
	if dir.length() < 0.4:
		dir = Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	dir = dir.normalized()
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
	_lane.show_lane(p.get_world_3d(), p.global_position, dir, float(SkillDb.all()[aiming_id]["range"]), pulse)
	Actor.get_highlight_material().albedo_color.a = 0.3 + 0.2 * pulse
	# The first three that fit on the blade, nearest first, are the ones it would run through.
	var in_lane: Array[Actor] = []
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or not e.can_be_impaled():
			continue
		var rel: Vector3 = e.global_position - p.global_position
		rel.y = 0.0
		var ahead: float = rel.dot(dir)
		if ahead > 0.2 and ahead < _lane.length + 1.0 and absf(rel.cross(dir).y) <= SkewerPreview.LANE_HALF_WIDTH + e.body_radius * 0.3:
			in_lane.append(e)
	in_lane.sort_custom(func(a: Actor, b: Actor) -> bool: return a.global_position.distance_squared_to(p.global_position) < b.global_position.distance_squared_to(p.global_position))
	var now_hit: Array[Actor] = in_lane.slice(0, 3)
	for e in _highlighted:
		if is_instance_valid(e) and not (e in now_hit):
			e.set_highlighted(false)
	for e in now_hit:
		e.set_highlighted(true)
	_highlighted = now_hit

func _ensure_orb(size: float) -> void:
	if fire_orb == null or not is_instance_valid(fire_orb):
		fire_orb = FireOrb.new()
		p.add_child(fire_orb)
		fire_orb.global_position = orb_home()
		fire_orb.grow_to(size, 0.3)

func drop_orb() -> void:
	if fire_orb != null and is_instance_valid(fire_orb):
		fire_orb.fade_out()
	fire_orb = null

## Over the head, where the raised hands end up at the top of the gather.
func orb_home() -> Vector3:
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

func queue_skill(id: String, cursor: Vector3) -> void:
	var target: Actor = p.enemy_near(cursor, 12.0)
	if target == null:
		return
	queued_skill = id
	queued_target = target
	p.movement.has_goal = false

func start_skill(id: String, target: Actor, aim: Variant = null) -> void:
	var skill: Dictionary = SkillDb.all()[id]
	if id == "basic":
		skill = _next_basic()
	busy_def = skill
	busy_time = float(skill["time"]) / p.stats.attack_speed()
	if id == "power" and p.stats.vault_time > 0.0:
		p.stats.vault_time = 0.0   # Vaultborn: this one is free
	else:
		p.stats.mana -= float(skill["mana"])
		p.stats.cooldowns[id] = float(skill["cd"])
	ItemEffects.on_skill_start(p, id)
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
	_release_started = false
	_style_trail(id)
	p.model.manual(skill["clip"])
	p.model.scrub(float(skill["start"]))
	if bool(skill.get("charged", false)):
		_ensure_orb(0.28)
		fire_orb.grow_to(0.55, float(skill["gather"]) * busy_time / float(skill["time"]))
		Fx.ring(p, p.global_position, 1.8, Color(1.0, 0.55, 0.15))
		Fx.light_flash(p, p.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 2.0, 0.3)

## Blade ribbon colour and length per skill: plain steel for the combo, hot orange for Power Strike.
func _style_trail(id: String) -> void:
	if p._trail == null:
		return
	match id:
		"power":
			p._trail.tint = Color(1.0, 0.62, 0.25)
			p._trail.max_age = 0.34
			p._trail.strength = 0.85
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

## Gear buffs you can see: a haste wake behind you.
func update_buff_visuals() -> void:
	if _glow_light != null and not (busy and busy_skill == "power"):
		_glow_light.light_energy = 0.0
	if _haste_fx == null and p.stats.haste_time > 0.0:
		_haste_fx = _make_haste_fx()
		p.add_child(_haste_fx)
	if _haste_fx != null:
		_haste_fx.emitting = p.stats.haste_time > 0.0

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
	if bool(skill.get("finisher", false)):   # a falchion's finisher is over sooner than a greatsword's
		skill["time"] = float(skill["time"]) * float(p.stats.weapon_profile("finisher_time", 1.0))
	combo_timer = COMBO_WINDOW + float(skill["time"])
	return skill

func tick_busy(delta: float) -> void:
	busy_t += delta
	var skill: Dictionary = busy_def
	if bool(skill.get("skewer", false)):
		p.skewer.tick_skewer(delta)
		return
	if bool(skill.get("leap", false)):
		p.leap.tick_leap(delta)
		return
	if bool(skill.get("earthshatter", false)):
		p.earthshatter.tick(delta)
		return
	if bool(skill.get("charged", false)):
		_tick_charged(skill)
		return
	if busy_target != null and not busy_target.dead:
		busy_aim = busy_target.global_position
	var duration: float = busy_time
	var hit_at: float = duration * hit_fraction(skill)
	if not busy_hit_done and busy_t >= hit_at:
		busy_hit_done = true
		_apply_skill(skill)
		_lunge(float(skill["lunge"]))
		_strike_fx(skill)
	if busy_hit_done and busy_skill == "basic":   # the weapon decides how quickly the blade comes back (a falchion fast, a greatsword slowly)
		busy_t += delta * (float(p.stats.weapon_profile("recovery", 1.0)) - 1.0)
	var u: float = busy_t / duration
	var hf: float = hit_fraction(skill)
	if busy_skill == "power":
		_blade_glow(u, hf)
	if p._trail != null:
		p._trail.active = String(skill["kind"]) == "melee" and u > hf - 0.35 and u < hf + 0.22
	if String(skill["kind"]) == "melee":
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
	if String(skill["kind"]) != "melee":
		return
	if busy_skill == "power":
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
	Destructible.blast(p.get_tree(), point, 2.4, 60.0, dir, 1.7, Destructible.HERO)
	Fx.hitstop(p, 0.08)
	if busy_target != null and is_instance_valid(busy_target) and not busy_target.dead:
		busy_target.knocked_by = p
		busy_target.knock += dir * POWER_KNOCK * (1.0 - busy_target.knock_resist)   # thrown back, hard: into a wall or another monster it pays for it
		busy_target.interrupt(POWER_STUN)
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
			var outward: Vector3 = (gap.normalized() * 0.6 + dir * 0.4).normalized() if gap.length() > 0.1 else dir
			e.knocked_by = p
			e.knock += outward * POWER_SPLASH_KNOCK * (1.0 - e.knock_resist)
			e.interrupt(POWER_SPLASH_STUN)
	ItemEffects.power_shockwave(p, dir)

const POWER_SPLASH_RADIUS := 2.0
## Power Strike throws what it hits (m/s of knock-back added to the blow's own: about 4-5 m for the one struck, 3 for its neighbours, less for the heavy ones) and
## stuns them longer than a normal blow, so it clears the space round the hero. See Actor._knock_impact for what a wall or another monster costs.
const POWER_KNOCK := 9.0
const POWER_SPLASH_KNOCK := 6.5
const POWER_STUN := 1.5
const POWER_SPLASH_STUN := 1.1
func _apply_skill(skill: Dictionary) -> void:
	var mult: float = skill["mult"]
	match String(skill["kind"]):
		"melee":
			# The basic combo's stagger and knockback follow the weapon: light for a falchion, heavy for a greatsword.
			var weight: float = float(skill["weight"]) * (float(p.stats.weapon_profile("weight", 1.0)) if busy_skill == "basic" else 1.0)
			if busy_target != null and not busy_target.dead \
					and p.flat_distance_to(busy_target) - busy_target.body_radius <= float(skill["range"]) + 0.5:
				var guaranteed_crit: bool = ItemEffects.guaranteed_crit(p, busy_target)
				var damage: float = p.stats.weapon_damage(mult) * ItemEffects.outgoing_multiplier(p, busy_target)
				var result: Dictionary = Combat.resolve(p, busy_target, damage, Combat.DamageType.PHYSICAL,
					not guaranteed_crit, weight, guaranteed_crit)
				result["skill_id"] = busy_skill
				result["finisher"] = skill.get("finisher", false)
				busy_target.receive(result, p.global_position)
				if busy_skill == "basic" and bool(skill.get("finisher", false)) and result["outcome"] not in [Combat.Outcome.MISS, Combat.Outcome.BLOCK]:
					_stun_finisher_hit(busy_target)
			else:
				Sfx.sword_miss(p)   # the target died, moved away or was never in reach: the swing finds only air
			if busy_skill == "basic":
				_weapon_style_hits(skill, mult, weight)
			_smash_props(mult, 1.4 + (1.0 if busy_skill == "power" else 0.0), 1.0 + (0.5 if busy_skill == "power" else 0.0))
			if busy_skill == "power":
				_power_impact()
		"projectile":
			Sfx.sample(p, "fireball_cast", -1.0, 1.0)   # the cast burst lands exactly as the fireball leaves the hands
			var ball := Projectile.new()
			ball.owner_actor = p
			var dir: Vector3 = busy_aim - p.global_position
			dir.y = 0.0
			ball.direction = dir.normalized()
			ball.damage = (14.0 + p.stats.strength * 0.4) * ItemEffects.virtuoso_multiplier(p)
			ball.destination = busy_aim + Vector3(0, 0.8, 0)
			p.get_tree().current_scene.add_child(ball)
			var origin: Vector3 = p.global_position + Vector3(0, 1.2, 0) + ball.direction * 0.8
			if fire_orb != null and is_instance_valid(fire_orb):
				origin = fire_orb.release()  # the gathered orb is the fireball that gets thrown
				fire_orb = null
			ball.global_position = origin
			if p.stats.has_affix("twin_flame"):
				var twin := Projectile.new()
				twin.owner_actor = p
				twin.damage = ball.damage * 0.6
				var twin_point: Vector3 = twin_destination(busy_aim)
				var heading: Vector3 = twin_point - p.global_position
				heading.y = 0.0
				twin.direction = heading.normalized() if heading.length() > 0.05 else ball.direction
				twin.destination = twin_point + Vector3(0, 0.8, 0)
				p.get_tree().current_scene.add_child(twin)
				twin.global_position = ball.global_position

## What the wielded weapon adds to a basic swing. A wide weapon (the greatsword) also hits the other enemies inside its arc, for a
## share of the damage; a slam finisher drives the blade into the ground and throws a shockwave through everything in front.
func _weapon_style_hits(skill: Dictionary, mult: float, weight: float) -> void:
	var arc: float = float(p.stats.weapon_profile("arc", 0.0))
	var slam: bool = bool(skill.get("finisher", false)) and String(p.stats.weapon_profile("finisher", "")) == "slam"
	if arc <= 0.0 and not slam:
		return
	var dir: Vector3 = busy_aim - p.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	var reach: float = float(skill["range"]) + 0.3
	var share: float = float(p.stats.weapon_profile("arc_damage", 0.6))
	var swept: int = 0
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e == busy_target:
			continue
		var offset: Vector3 = e.global_position - p.global_position
		offset.y = 0.0
		var in_arc: bool = arc > 0.0 and offset.length() - e.body_radius <= reach and absf(dir.angle_to(offset)) <= deg_to_rad(arc * 0.5)
		var in_slam: bool = slam and offset.length() - e.body_radius <= SLAM_RADIUS and absf(dir.angle_to(offset)) <= deg_to_rad(100.0)
		if not (in_arc or in_slam):
			continue
		var frac: float = share if in_arc and not in_slam else 0.8
		var swing: Dictionary = Combat.resolve(p, e, p.stats.weapon_damage(mult) * frac * ItemEffects.outgoing_multiplier(p, e),
			Combat.DamageType.PHYSICAL, true, weight * (1.6 if in_slam else 1.0), false)
		swing["skill_id"] = busy_skill
		swing["secondary"] = true
		e.receive(swing, p.global_position)
		if bool(skill.get("finisher", false)) and swing["outcome"] not in [Combat.Outcome.MISS, Combat.Outcome.BLOCK]:
			_stun_finisher_hit(e)
		if in_slam and is_instance_valid(e) and not e.dead:
			e.interrupt(0.7)
		swept += 1
	if slam:
		var at: Vector3 = p.global_position + dir * 1.8
		Fx.ring(p, at + Vector3(0, 0.05, 0), 2.4, Color(0.55, 0.5, 0.42))
		Fx.burst(p, at + Vector3(0, 0.2, 0), Vector3.UP, Color(0.34, 0.31, 0.27), 16, 4.0, 0.045)
		Fx.shake(p, 0.1)
		Fx.hitstop(p, 0.06)
		Destructible.blast(p.get_tree(), at, SLAM_RADIUS - 0.6, p.stats.weapon_damage(mult) * 1.5, dir, 1.8, Destructible.HERO)
	elif swept > 0:
		Fx.punch(p, 0.8 + 0.2 * minf(swept, 3))

const SLAM_RADIUS := 3.2

func _stun_finisher_hit(enemy: Actor) -> void:
	if p.stats.has_affix("maelstrom") and is_instance_valid(enemy) and not enemy.dead:
		enemy.interrupt(1.0)

## A swing also breaks a barrel in front of the hero (only barrels, for now), so one can be attacked like an enemy.
func _smash_props(mult: float, reach: float, force: float) -> void:
	var dir: Vector3 = busy_aim - p.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	Destructible.blast(p.get_tree(), p.global_position + dir * 1.2, reach, p.stats.weapon_damage(mult) * 1.5, dir, force, Destructible.HERO)

## Where the second Twin Flame fireball goes: at a second enemy (the nearest one to the first fireball's target that is not the
## target itself, preferring one outside the first blast); with only one enemy about, right next to it.
func twin_destination(first_point: Vector3) -> Vector3:
	var enemies: Array[Actor] = []
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e != null and not e.dead and p.flat_distance_to(e) <= float(SkillDb.all()["fireball"]["range"]) + 2.0:
			enemies.append(e)
	var primary: Actor = null
	var primary_d: float = INF
	for e in enemies:
		var d: float = Vector2(e.global_position.x - first_point.x, e.global_position.z - first_point.z).length()
		if d < primary_d:
			primary_d = d
			primary = e
	var second: Actor = null
	var second_d: float = INF
	var outside: bool = false   # one beyond the first blast beats any inside it
	for e in enemies:
		if e == primary:
			continue
		var d: float = Vector2(e.global_position.x - first_point.x, e.global_position.z - first_point.z).length()
		var is_outside: bool = d > Projectile.BLAST_RADIUS * 0.9
		if (is_outside and not outside) or (is_outside == outside and d < second_d):
			second = e
			second_d = d
			outside = is_outside
	if second != null:
		return Vector3(second.global_position.x, 0.0, second.global_position.z)
	var anchor: Vector3 = primary.global_position if primary != null else first_point
	var side: Vector3 = (anchor - p.global_position)
	side.y = 0.0
	side = side.normalized().rotated(Vector3.UP, PI * 0.5) if side.length() > 0.05 else Vector3.RIGHT
	return Vector3(anchor.x, 0.0, anchor.z) + side * 0.8   # right beside the only target

## The sword stays red while it is bloody and slowly dries.
func update_blade_blood(delta: float) -> void:
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
