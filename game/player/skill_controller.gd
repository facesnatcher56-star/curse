class_name SkillController
extends RefCounted
## Skill use: hotkeys and the aim preview, starting and ticking a skill, the basic combo, strike effects and blade blood.

var p: Player

func _init(player: Player) -> void:
	p = player

const COMBO_WINDOW := 0.9
## The single-party hotbar: every controlled body reads this same layout.
var hotbar: Array[String]:
	get: return GameSettings.hotbar_slots
	set(value): GameSettings.hotbar_slots.assign(value)
var right_click_skill: String:
	get: return GameSettings.hotbar_alt
	set(value): GameSettings.hotbar_alt = value

func caster_id(slot: int) -> String:
	return GameSettings.hotbar_caster(slot)

## Puts a skill on a slot (0.. numbered, HotbarLayout.ALT for the right mouse button); if it was on another slot the two swap.
func assign_slot(slot: int, id: String) -> void:
	GameSettings.assign_hotbar(slot, id)
	clear_aim()

const TAKE_AIM_CURSOR := preload("res://assets/ui/cursors/take_aim_reticle.png")
const TAKE_AIM_HOTSPOT := Vector2(24, 24)
var take_aim_targeting: bool = false
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
var _brutal_aura: Node3D
var brutal_armed: bool = false
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
var _highlighted: Array[Actor] = []
## A basic swing can always be abandoned by clicking away; heavier melee skills only once the blow has landed.
func swing_cancellable_by_move() -> bool:
	# Ground movement always supersedes the actor-side action. A launched projectile
	# is scene-owned and remains committed, but wind-ups and recovery are abandoned.
	return busy

## Hotkeys are read every frame, whatever the hero is doing, and cancel the current animation:
##  - the potion drinks at once (even while stunned);
##  - any other usable skill interrupts a swing/cast/charge and then starts through the normal path;
##  - a skill that cannot be used (cooldown, no mana, nothing to hit) tells you why and does NOT cancel anything.
func handle_hotkeys(cursor: Vector3) -> void:
	if p.dead:
		return
	if Input.is_action_just_pressed("use_potion"):
		drink_potion()
	if Input.is_action_just_pressed("use_mana_potion"):
		drink_mana_potion()
	if not Input.is_action_pressed("alt_skill"):
		for body in PartyManager.current().bodies.values():
			if is_instance_valid(body): body.skills.swallow_alt = false
	for i in hotbar.size():
		_route_hotbar_action("skill_%d" % (i + 1), hotbar[i], i, cursor)
	_route_hotbar_action("alt_skill", right_click_skill, HotbarLayout.ALT, cursor)
	for body in PartyManager.current().bodies.values():
		if is_instance_valid(body) and (body.skills.take_aim_targeting or body.skills.aiming_id != ""):
			body.skills.check_cancel()
			body.skills.update_aim(cursor)

## A shared key always sends its command to the member assigned to that slot, independent of who is controlled.
func _route_hotbar_action(action: String, id: String, slot: int, cursor: Vector3) -> void:
	if id == "":
		return
	var caster_id := GameSettings.hotbar_caster(slot)
	var caster := PartyManager.current().bodies.get(caster_id) as Player
	if not is_instance_valid(caster) or caster.dead:
		if Input.is_action_just_pressed(action):
			p._say("%s is not available" % caster_id.capitalize())
		return
	var controller: SkillController = caster.skills
	if action == "alt_skill" and (p.skills.swallow_alt or controller.swallow_alt):
		return
	if Input.is_action_just_pressed(action) and controller.take_aim_targeting and id != "take_aim":
		controller.cancel_take_aim_targeting()
	if bool(SkillDb.all()[id].get("aimed", false)):
		controller.handle_aimed_key(action, id, cursor)
		return
	if not Input.is_action_pressed(action):
		return
	if id == "brutal_attack":
		if Input.is_action_just_pressed(action): controller.activate_brutal_attack()
	elif id == "take_aim":
		if Input.is_action_just_pressed(action): controller.activate_take_aim(p.pad_facing_target() as Enemy)
	elif PowerController.LIVE.has(id):
		if Input.is_action_just_pressed(action): caster.powers.activate(id, cursor)
	else:
		if Input.is_action_just_pressed(action) and id != "basic":
			controller.interrupt_for(id, cursor)
		controller.queue_skill(id, cursor)

## A skill pressed mid-action cancels it (a skill never waits behind a basic swing); the same for a numbered key and for the skill on the right mouse button.
func interrupt_for(id: String, cursor: Vector3) -> void:
	if busy and not p.movement.rolling and p.stun_time <= 0.0:
		if not p.stats.can_use(id):
			if p.stats.mana < p.stats.mana_cost(id):
				p._say("Not enough mana")
			else:
				p._say("%s is on cooldown" % SkillDb.all()[id]["name"])
		elif _hotkey_would_start(id, cursor):
			cancel_action()

## Drinks a potion at once, even mid-swing or stunned (it cancels a swing that was in progress).
func drink_potion() -> void:
	if not p.dead and p.stats.use_potion() and not p.movement.rolling:
		cancel_action()

func drink_mana_potion() -> void:
	if not p.dead and p.stats.use_mana_potion() and not p.movement.rolling:
		cancel_action()

## Whether pressing this skill's key right now would actually start it (targeted skills need an enemy near the cursor).
func _hotkey_would_start(id: String, cursor: Vector3) -> bool:
	var skill: Dictionary = SkillDb.all()[id]
	if skill.get("directional", false) or skill.get("aimed", false):
		return true
	return p.enemy_near(cursor, 12.0) != null

## Aborts the current swing, cast or charge immediately.
func cancel_action() -> void:
	var was_busy: bool = busy
	cancel_take_aim_targeting()
	clear_queue()
	if not was_busy:
		return
	_refund_unreleased_cast()
	if bool(busy_def.get("charged", false)):
		drop_orb()
	if p.bow != null and String(busy_def.get("kind", "")) == "ranged":
		p.bow.cancel()
	busy = false
	busy_hit_done = false
	queued_skill = ""
	queued_target = null
	busy_skill = ""
	busy_def = {}
	busy_target = null
	busy_t = 0.0
	busy_time = 0.0
	busy_aim = Vector3.ZERO
	_release_started = false
	_mana_spent = 0.0
	if p._trail != null:
		p._trail.active = false
	if p.visual != null:
		p.visual.rotation.x = 0.0
	if p.model != null and p.stun_time <= 0.0 and not p.knockdown.active():
		p.model.loop("idle_alert")

## What the skill under way cost (Fireball's cost grows with INT, so the refund is what was taken, not the data's number).
var _mana_spent: float = 0.0

## The charged cast reserves its cost at start; every abort path settles the same reservation.
func _refund_unreleased_cast() -> void:
	if busy and bool(busy_def.get("charged", false)) and not busy_hit_done:
		p.stats.mana = minf(p.stats.mana + _mana_spent, p.stats.max_mana)
		p.stats.cooldowns[busy_skill] = 0.0

## Death/revive cleanup without changing the actor's animation or transition.
func reset() -> void:
	cancel_take_aim_targeting()
	_refund_unreleased_cast()
	clear_aim()
	if p.model != null:
		p.model.weapon_aim = null
		p.model.leg_raise = 0.0
	if p._trail != null:
		p._trail.active = false
	busy = false
	busy_skill = ""
	busy_def = {}
	busy_target = null
	busy_t = 0.0
	busy_hit_done = false
	_release_started = false
	queued_skill = ""
	queued_target = null
	aim_blocked = ""
	swallow_alt = false
	combo_step = 0
	combo_timer = 0.0
	brutal_armed = false
	_clear_brutal_visual()

func activate_brutal_attack() -> void:
	if brutal_armed:
		p._say("Brutal Attack is armed")
		return
	if PowerDb.hero_rank("brutal_attack", p.member_id) <= 0:   # DS2: a power opens with passive ranks (Critical Strike 1)
		p._say("Brutal Attack needs Critical Strike")
		return
	if not p.stats.can_use("brutal_attack"):
		p._say("Brutal Attack is %d%% charged" % int(p.stats.ult_fraction("brutal_attack") * 100.0))
		return
	# DS2 powers take priority over the ordinary attack job. Preserve the target
	# before cancelling so the powered blow begins now, never behind the queue.
	var immediate_target: Actor = busy_target if is_instance_valid(busy_target) else p.attack_target
	if not is_instance_valid(immediate_target):
		immediate_target = p.hover_target
	if busy:
		cancel_action()
	clear_queue()
	brutal_armed = true
	p.power_activated.emit(p.member_id, "brutal_attack")
	_ensure_brutal_visual()
	if is_instance_valid(immediate_target) and not immediate_target.dead:
		p.attack_target = immediate_target
		p.movement.has_goal = false
		start_skill("basic", immediate_target)

func activate_take_aim(target_override: Enemy = null) -> void:
	if not p.stats.can_use("take_aim"):
		p._say("Take Aim requires Critical Shot, a bow, and full charge")
		return
	if p.bow.armed:
		p._say("Take Aim is armed")
		return
	if take_aim_targeting:
		cancel_take_aim_targeting()
		return
	if Gamepad.active:
		var target := target_override if is_instance_valid(target_override) else p.pad_facing_target() as Enemy
		if target != null: _arm_take_aim(target)
		else:
			p.bow.arm()
			p.power_activated.emit(p.member_id, "take_aim")
		return
	start_take_aim_targeting()
	p.power_activated.emit(p.member_id, "take_aim")

func _arm_take_aim(target: Enemy) -> void:
	if not p.stats.can_use("take_aim"): return
	cancel_action()
	p.bow.arm()
	p.power_activated.emit(p.member_id, "take_aim")
	p.attack_target = target
	p.movement.has_goal = false
	if p.flat_distance_to(target) <= 17.0: start_skill("basic", target)

func start_take_aim_targeting() -> void:
	take_aim_targeting = true
	Input.set_custom_mouse_cursor(TAKE_AIM_CURSOR, Input.CURSOR_ARROW, TAKE_AIM_HOTSPOT)
	Input.set_custom_mouse_cursor(TAKE_AIM_CURSOR, Input.CURSOR_CROSS, TAKE_AIM_HOTSPOT)

func cancel_take_aim_targeting() -> void:
	if not take_aim_targeting:
		return
	take_aim_targeting = false
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_CROSS)

func confirm_take_aim(target_enemy: Enemy) -> void:
	if not take_aim_targeting: return
	cancel_take_aim_targeting()
	_arm_take_aim(target_enemy)

func _ensure_brutal_visual() -> void:
	if p == null:
		return
	if _brutal_aura != null and is_instance_valid(_brutal_aura):
		return
	_brutal_aura = BrutalAttackFx.new()
	_brutal_aura.name = "BrutalAttackAura"
	p.add_child(_brutal_aura)
	(_brutal_aura as BrutalAttackFx).setup(p.model)

func _clear_brutal_visual() -> void:
	if _brutal_aura != null and is_instance_valid(_brutal_aura):
		_brutal_aura.queue_free()
	_brutal_aura = null

## Right-click or dodge backs out of a Fireball. While aiming nothing has been spent; during the wind-up the mana and cooldown come
## back. Once the fireball has left the hand it is thrown, and nothing cancels it.
func check_cancel() -> void:
	var alt: bool = Input.is_action_just_pressed("alt_skill") and aiming_action != "alt_skill"
	var dodge: bool = Input.is_action_just_pressed("dodge")
	var esc: bool = Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause")
	if not (alt or dodge or esc):
		return
	if take_aim_targeting:
		cancel_take_aim_targeting()
		if alt:
			swallow_alt = true
		p._say("Cancelled")
		return
	if aiming_id != "":
		aim_blocked = aiming_action   # the aim key may still be held: letting go of it must not cast
		clear_aim()
		if alt:
			swallow_alt = true
		p._say("Cancelled")
	elif busy and bool(busy_def.get("charged", false)) and not busy_hit_done:
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
		if p.stats.mana < p.stats.mana_cost(id):
			p._say("Not enough mana")
		return
	clear_aim(true)
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

func clear_queue() -> void:
	queued_skill = ""
	queued_target = null

func queue_skill(id: String, cursor: Vector3) -> void:
	if p.dead:
		return
	var target: Actor = p.enemy_near(cursor, 12.0)
	if target == null:
		return
	queued_skill = id
	queued_target = target
	p.movement.has_goal = false

func start_skill(id: String, target: Actor, aim: Variant = null) -> void:
	if busy or p.dead or not p.stats.can_use(id):
		return
	if aim == null and not is_instance_valid(target):
		return
	if id == "basic" and p.stats.is_ranged() and p.bow != null:
		clear_queue()
		p.bow.start(target)
		return
	# An Opening on this enemy: the basic attack becomes the weapon's execution (the mark is spent here).
	if id == "basic" and aim == null and p.openings.try_execute(target):
		clear_queue()
		return
	var skill: Dictionary = SkillDb.all()[id]
	clear_queue()   # an accepted immediate action replaces any pending order
	if id == "basic":
		skill = _next_basic()
	busy_def = skill
	busy_time = float(skill["time"]) / p.stats.skill_speed(id)
	_mana_spent = p.stats.mana_cost(id)
	p.stats.mana -= _mana_spent
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
	# Basic attacks retain the explicit engagement after button release. Replacement
	# skills still cancel that order; movement/dodge/loot cancellation lives with input.
	if id != "basic":
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

## A power's wind-up (PowerController.CASTS). It is the busy action, so every cancel path (a move, a dodge, a potion, a knockdown, another
## skill) reaches it. The power's damage, stun, cost and recharge happen at the strike frame (tick_busy -> PowerController.impact); a
## wind-up cut short before then does none of them and is not spent.
func start_power_cast(id: String, aim: Vector3, cast: Dictionary) -> void:
	clear_queue()
	busy_def = cast.duplicate()
	busy_def["kind"] = "power"
	busy_def["charged"] = false
	busy_time = float(cast["time"])
	busy = true
	busy_skill = id
	busy_target = null
	busy_t = 0.0
	busy_hit_done = false
	busy_aim = aim
	p.combat_timer = 5.0
	p.movement.has_goal = false
	p.attack_target = null
	if bool(cast.get("face", false)):
		p.face(aim)
	_release_started = false
	p.model.manual(String(cast["clip"]))
	p.model.scrub(float(cast["start"]))

## An Opening's execution (Openings.STYLES): one melee blow on the marked enemy, timed by the weapon's speed. It is never cancelled by
## the enemy moving (the mark is what the hero is committed to), and it grants the hero a short invulnerability.
func start_opening(target: Actor, style: Dictionary) -> void:
	if busy or p.dead or not is_instance_valid(target):
		return
	clear_queue()
	busy_def = style.duplicate()
	busy_def["kind"] = "melee"
	busy_def["charged"] = false
	busy_time = float(style["time"]) / maxf(p.stats.attack_speed(), 0.2)
	busy = true
	busy_skill = "opening"
	busy_target = target
	busy_t = 0.0
	busy_hit_done = false
	busy_aim = target.global_position
	p.combat_timer = 5.0
	p.movement.has_goal = false
	p.face(busy_aim)   # the basic-attack engagement stays: after the execution the hero carries on as before
	p.invulnerable_time = maxf(p.invulnerable_time, Openings.INVULNERABLE)
	_release_started = false
	_style_trail("opening")
	p.model.manual(String(style["clip"]))
	p.model.scrub(float(style["start"]))

## Blade ribbon colour and length: plain steel.
func _style_trail(_id: String) -> void:
	if p._trail == null:
		return
	var crimson := bool(busy_def.get("brutal_animation", false))
	p._trail.tint = Color("ff3456") if crimson else Color(1.0, 0.92, 0.75)
	p._trail.max_age = 0.32 if crimson else WeaponTrail.DEFAULT_AGE
	p._trail.strength = 0.7 if crimson else 0.4

## Picks the next swing of the combo and returns it merged over the basic attack stats.
func _next_basic() -> Dictionary:
	# An armed Brutal Attack is its own compact overhead blow, not a tinted frame of the basic combo.
	# It still travels through the basic-hit path so a miss/block preserves the stored power.
	if brutal_armed:
		var brutal_skill: Dictionary = SkillDb.all()["basic"].duplicate(true)
		brutal_skill.merge(SkillDb.all()["brutal_attack"]["attack_animation"], true)
		combo_step = 0
		combo_timer = 0.0
		return brutal_skill
	# An armed Staggering Blow is its own overhead blow; its impact releases the power (see _apply_skill).
	if p.powers.staggering_armed:
		var stagger_skill: Dictionary = SkillDb.all()["basic"].duplicate(true)
		stagger_skill.merge(PowerController.STAGGER_SWING, true)
		combo_step = 0
		combo_timer = 0.0
		return stagger_skill
	var variants: Array = SkillDb.basic_combo()[combo_step]
	var skill: Dictionary = SkillDb.all()["basic"].duplicate()
	skill.merge(variants[randi() % variants.size()], true)
	var both_hands: Dictionary = p.stats.weapon_profile("two_hand_clips", {})   # a two-hander swings with both hands on the grip
	if both_hands.has(skill["clip"]):
		skill.merge(both_hands[skill["clip"]], true)
	combo_step = (combo_step + 1) % SkillDb.basic_combo().size()
	if bool(skill.get("finisher", false)):   # a falchion's finisher is over sooner than a greatsword's
		skill["time"] = float(skill["time"]) * float(p.stats.weapon_profile("finisher_time", 1.0))
	combo_timer = COMBO_WINDOW + float(skill["time"])
	return skill

func tick_busy(delta: float) -> void:
	if not busy or p.dead:
		return
	if String(busy_def.get("kind", "")) == "ranged" and p.bow != null:
		p.bow.tick(delta)
		return
	var skill: Dictionary = busy_def
	if String(skill.get("kind", "")) == "power":
		_tick_power_cast(skill, delta)
		return
	busy_t += delta
	if bool(skill.get("charged", false)):
		_tick_charged(skill)
		return
	if is_instance_valid(busy_target) and not busy_target.dead:
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
	if p._trail != null:
		var show_heavy_trail: bool = busy_skill != "basic" or bool(skill.get("brutal_animation", false))
		p._trail.active = String(skill["kind"]) == "melee" and show_heavy_trail and u > hf - 0.35 and u < hf + 0.22
	if String(skill["kind"]) == "melee":
		# Coil back while gathering the swing, then throw the weight forward through the strike.
		var heft: float = clampf(float(skill["weight"]), 0.8, 1.7)
		if bool(skill.get("brutal_animation", false)): heft = 2.25
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

## A power's wind-up: scrubbed through its clip, the impact at its strike frame, and the cast ends with its recovery.
func _tick_power_cast(skill: Dictionary, delta: float) -> void:
	busy_t += delta
	var duration: float = busy_time
	var hf: float = hit_fraction(skill)
	if not busy_hit_done and busy_t >= duration * hf:
		busy_hit_done = true
		p.powers.impact(busy_skill, busy_aim)
	p.model.scrub(CharacterModel.remap(clampf(busy_t / duration, 0.0, 1.0), hf,
		float(skill["start"]), float(skill["strike"]), float(skill["end"])))
	if busy_t >= duration:
		busy = false

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
	var weight: float = float(skill["weight"])
	var dir: Vector3 = busy_aim - p.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	Fx.shake(p, 0.04 + 0.06 * weight)
	Fx.punch(p, 0.9 + 1.5 * weight)
	# The body behind the blow: the front foot comes down hard and kicks up dust.
	Fx.burst(p, p.global_position + dir * 0.5 + Vector3(0, 0.05, 0), Vector3.UP * 0.6, Color(0.5, 0.45, 0.38), int(4 + 3 * weight), 1.4 + 0.5 * weight, 0.05)
	Fx.burst(p, p.global_position + dir * 1.3 + Vector3(0, 0.05, 0), dir + Vector3.UP * 0.4, Color(0.5, 0.45, 0.38),
		int(5 + 6 * weight), 2.2 + weight, 0.04)
	if weight >= 1.5 and not bool(skill.get("brutal_animation", false)):
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

## The enemy a directed Power Strike lands on: the nearest one to the point the blow lands on (a stride out toward the cursor), if any is
## in reach. Chosen when the blade comes down, not when the key is pressed.
func _apply_skill(skill: Dictionary) -> void:
	var mult: float = skill["mult"]
	match String(skill["kind"]):
		"melee":
			# The basic combo's stagger and knockback follow the weapon: light for a falchion, heavy for a greatsword.
			var weight: float = float(skill["weight"]) * (float(p.stats.weapon_profile("weight", 1.0)) if busy_skill == "basic" else 1.0)
			if busy_target != null and not busy_target.dead \
					and p.flat_distance_to(busy_target) - busy_target.body_radius <= float(skill["range"]) + 0.5 \
					and Nav.line_clear(p, busy_target.global_position):
				var brutal: bool = busy_skill == "basic" and brutal_armed
				var opening: bool = busy_skill == "opening"
				var damage: float = p.stats.weapon_damage(mult)
				# An Opening is a guaranteed critical (it cannot be dodged or blocked) with its own bonus damage on top.
				var multiplier: float = 1.0
				if brutal:
					multiplier = p.stats.brutal_mult() * p.stats.power_damage_mult()
				elif opening:
					multiplier = 1.0 + p.openings.damage_bonus() / 100.0
				var result: Dictionary = Combat.resolve(p, busy_target, damage, Combat.DamageType.PHYSICAL, not opening, weight, opening, not brutal, multiplier)
				result["skill_id"] = "brutal_attack" if brutal else busy_skill
				result["finisher"] = skill.get("finisher", false)
				if brutal and result["outcome"] not in [Combat.Outcome.MISS, Combat.Outcome.BLOCK]:
					var brutal_dir: Vector3 = busy_target.global_position - p.global_position
					brutal_dir.y = 0.0
					SkillFx.brutal_impact(p, busy_target.global_position, brutal_dir, PowerDb.hero_rank("brutal_attack", p.member_id))
				if brutal and result["outcome"] not in [Combat.Outcome.MISS, Combat.Outcome.BLOCK]:
					brutal_armed = false
					p.stats.spend_brutal_attack()
					_clear_brutal_visual()
				var target: Actor = busy_target
				target.receive(result, p.global_position)
				if opening:
					p.openings.on_executed(target, result, skill)
				elif brutal:
					if result["outcome"] in [Combat.Outcome.HIT, Combat.Outcome.CRITICAL]:
						p.openings.on_power_use()   # Brutal Attack is a power: one roll for its use, not a basic-hit roll
				elif result["outcome"] in [Combat.Outcome.HIT, Combat.Outcome.CRITICAL] and not p.powers.staggering_armed:
					# A plain basic blow may show an Opening. A blow that releases Staggering Blow rolls once, in release_staggering.
					p.openings.on_melee_hit(target)
				if p.powers.staggering_armed and result["outcome"] not in [Combat.Outcome.MISS, Combat.Outcome.BLOCK] \
						and is_instance_valid(busy_target):
					p.powers.release_staggering(busy_target)   # DS2's Staggering Blow rides the next blow that lands
			else:
				Sfx.sword_miss(p)   # the target died, moved away or was never in reach: the swing finds only air
			_smash_props(mult, 1.4, 1.0)
		"projectile":
			Sfx.sample(p, "fireball_cast", -1.0, 1.0)   # the cast burst lands exactly as the fireball leaves the hands
			var ball := Projectile.new()
			ball.owner_actor = p
			var dir: Vector3 = busy_aim - p.global_position
			dir.y = 0.0
			ball.direction = dir.normalized()
			ball.damage = p.stats.spell_damage()   # a DS2 spell: grows with INT
			ball.destination = busy_aim + Vector3(0, 0.8, 0)
			p.get_tree().current_scene.add_child(ball)
			var origin: Vector3 = p.global_position + Vector3(0, 1.2, 0) + ball.direction * 0.8
			if fire_orb != null and is_instance_valid(fire_orb):
				origin = fire_orb.release()  # the gathered orb is the fireball that gets thrown
				fire_orb = null
			ball.global_position = origin

## A swing also breaks a barrel in front of the hero (only barrels, for now), so one can be attacked like an enemy.
func _smash_props(mult: float, reach: float, force: float) -> void:
	var dir: Vector3 = busy_aim - p.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	Destructible.blast(p.get_tree(), p.global_position + dir * 1.2, reach, p.stats.weapon_damage(mult) * 1.5, dir, force, Destructible.HERO)

## The sword stays red while it is bloody and slowly dries.
func update_blade_blood(delta: float) -> void:
	if brutal_armed:
		blade_blood = maxf(blade_blood - delta * 0.04, 0.0)
		_ensure_brutal_visual()
		return
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
