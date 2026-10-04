class_name Player
extends Actor
## Click-to-move action RPG hero. Control scheme follows the Zombasite manual:
##  - Left click ground: move (hold to keep moving). Left click enemy: walk up and attack, hold to keep attacking.
##  - Number keys: use the hotbar skill on the enemy nearest the cursor. Hold to repeat.
##  - Right click: use the right-click skill (default basic attack) on the enemy nearest the cursor.
##  - Ctrl (hold): stand still, so clicks and skills never move the hero.
##  - Attacks and casts root the hero until the swing finishes (StandStillToCast).

const MODEL_DIR := "res://assets/models/knight2"
const SWORD_PATH := "res://assets/models/sword/model.glb"
# Sword orientation in the hand bone: index into GRIPS (tuned by eye with --grip=N screenshots).
const GRIPS: Array[Basis] = [Basis(), Basis(Vector3(0, 0, 1), -PI / 2), Basis(Vector3(0, 0, 1), PI / 2),
	Basis(Vector3(1, 0, 0), PI / 2), Basis(Vector3(1, 0, 0), -PI / 2), Basis(Vector3(1, 0, 0), PI)]
# Middle of the right fist in the hand bone's space (rig units are cm; the bone origin is the wrist).
const HAND_GRIP_POINT := Vector3(-0.8, 15.0, 0.5)
const CLIPS: Array[String] = ["idle_alert", "walk", "run", "charge", "throw", "charge_run", "kick", "slash", "slash_l", "slash_r", "thrust", "combo_end", "power", "cleave", "cast", "roll", "hit", "death", "leap", "stomp", "yank", "jump", "earthshatter"]

# State the hero itself owns (everything else lives in a component).
var combat_timer: float = 0.0
var message: String = ""
var message_time: float = 0.0
var hurt_flash: float = 0.0
var attack_target: Actor
var hover_target: Actor  # enemy under the mouse cursor, for the health bar and highlight ring
var _ring: MeshInstance3D
var _cursor_on_enemy: bool = false
var click_mode: int = 0  # 0 move, 1 attack locked target, 2 stand-still attack
var _was_stunned: bool = false
var _trail: WeaponTrail
var _pad_aim_dir: Vector3 = Vector3.FORWARD
var _pad_hold: Vector3 = Vector3.ZERO          # aim offset kept while an aimed skill button is held
var _pad_hold_valid: bool = false

# Components (see game/player/ and game/skills/). Each owns one slice of what the hero is and does.
var skewer: SkewerSkill
var leap: LeapSkill
var earthshatter: EarthshatterSkill
var movement: PlayerMovement
var stats: PlayerStats
var skills: SkillController

func _init() -> void:
	skewer = SkewerSkill.new(self)
	leap = LeapSkill.new(self)
	earthshatter = EarthshatterSkill.new(self)
	movement = PlayerMovement.new(self)
	stats = PlayerStats.new(self)
	skills = SkillController.new(self)

func _ready() -> void:
	add_to_group("player")
	display_name = "Knight"
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	max_health = 120.0
	health = max_health
	attack_rating = 40.0
	defense = 30.0
	armor = stats.base_armor
	block_chance = 0.1
	_build_model(MODEL_DIR, CLIPS, 1.8, 0.4)
	model.loop("idle_alert")
	if ResourceLoader.exists(SWORD_PATH):
		var grip: int = 3
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--grip="):
				grip = int(arg.substr(7))
		model.attach_weapon(SWORD_PATH, "RightHand", GRIPS[grip], 1.25, 0.12, HAND_GRIP_POINT, 1.7)
		_trail = WeaponTrail.new()
		_trail.base_node = model.weapon_base
		_trail.tip_node = model.weapon_tip
		add_child(_trail)
	for item in Items.starting_gear():
		stats.equip(item, false)

func _physics_process(delta: float) -> void:
	if _actor_tick(delta):
		move_with(Vector3.ZERO)
		return
	if dead:
		return
	hurt_flash = maxf(hurt_flash - delta * 2.5, 0.0)
	skills.update_blade_blood(delta)
	skills.update_buff_visuals()
	if model != null and model.weapon != null:
		model.weapon.visible = not (skills.busy and bool(skills.busy_def.get("charged", false)))
	if not skills.busy and visual != null and absf(visual.rotation.x) > 0.001:
		visual.rotation.x = lerpf(visual.rotation.x, 0.0, 1.0 - exp(-14.0 * delta))
	message_time = maxf(message_time - delta, 0.0)
	combat_timer = maxf(combat_timer - delta, 0.0)
	for id in stats.cooldowns.keys():
		stats.cooldowns[id] = maxf(float(stats.cooldowns[id]) - delta, 0.0)
	stats.regen(delta)
	stats.haste_time = maxf(stats.haste_time - delta, 0.0)
	stats.riposte_time = maxf(stats.riposte_time - delta, 0.0)
	stats.ward_timer = maxf(stats.ward_timer - delta, 0.0)
	stats.collect_orbs()
	skills.combo_timer = maxf(skills.combo_timer - delta, 0.0)
	if skills.combo_timer <= 0.0 and not skills.busy:
		skills.combo_step = 0

	var cursor: Vector3 = cursor_world()
	hover_target = _hover_pick(cursor)
	if skills.aiming_id != "" and (movement.rolling or stun_time > 0.0):
		skills.clear_aim()
	skills.update_aim(cursor)
	skills.handle_hotkeys(cursor)
	if movement.rolling:
		movement.tick_roll(delta)
		return
	if Input.is_action_just_pressed("dodge") and stun_time <= 0.0:
		movement.try_roll(cursor)
		if movement.rolling:
			return
	if skills.busy:
		skills.tick_busy(delta)
		move_with(Vector3.ZERO)
		return
	if stun_time > 0.0:
		if not _was_stunned:
			_was_stunned = true
			model.once("hit", 0.0, 1.4)
		move_with(Vector3.ZERO)
		return
	_was_stunned = false
	var aiming_stick: Vector2 = Gamepad.aim_vector()
	if Gamepad.active and aiming_stick.length() > 0.0:
		face(global_position + Gamepad.to_world(aiming_stick), 0.3)   # twin-stick: the hero looks where it aims
	_read_input(cursor)
	_act(delta, cursor)
	movement.update_locomotion_anim()

# --- Input -------------------------------------------------------------------

## Where the hero is "pointing": the mouse position on the ground, or with a controller the right-stick aim point.
func cursor_world() -> Vector3:
	if Gamepad.active:
		return _pad_cursor()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return global_position
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse)
	var dir: Vector3 = camera.project_ray_normal(mouse)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		return global_position
	return hit

## Controller aim. The right stick places the cursor in front of the hero (further out the harder it is pushed) and it snaps
## to an enemy near that spot. With the stick released, the nearest enemy in range is targeted; with none, straight ahead.
func _pad_cursor() -> Vector3:
	var aim: Vector2 = Gamepad.aim_vector()
	var aiming_skill: bool = skills.aiming_id != ""
	if aim.length() > 0.0:
		_pad_aim_dir = Gamepad.to_world(aim).normalized()
		var point: Vector3 = global_position + _pad_aim_dir * (3.0 + 11.0 * aim.length())
		var assist: Actor = enemy_near(point, 2.2)
		if assist != null:
			point = assist.global_position
		if aiming_skill:
			_pad_hold = point - global_position
			_pad_hold_valid = true
		return point
	if aiming_skill:
		# Holding an aimed skill's button (Fireball): the target area stays where the stick left it. It starts on the nearest
		# enemy (or straight ahead), and the right stick then moves it about.
		if not _pad_hold_valid:
			_pad_hold = _pad_default_target() - global_position
			_pad_hold_valid = true
		return global_position + _pad_hold
	_pad_hold_valid = false
	return _pad_default_target()

## The nearest enemy in range, or a spot straight ahead when there is none.
func _pad_default_target() -> Vector3:
	var nearest: Actor = enemy_near(global_position, 12.0)
	if nearest != null:
		return nearest.global_position
	return global_position + Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y)) * 7.0

## Enemy under the mouse, picked in screen space: pointing at a head or chest counts, not just the feet.
func _hover_pick(cursor: Vector3, mouse_override: Vector2 = Vector2(-1.0, -1.0)) -> Actor:
	if Gamepad.active and mouse_override.x < 0.0:
		return enemy_near(cursor, 2.5)
	if mouse_override.x < 0.0 and mouse_over_ui():
		return null   # an enemy hidden behind the minimap or hotbar is not under the cursor
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse: Vector2 = get_viewport().get_mouse_position() if mouse_override.x < 0.0 else mouse_override
	var best: Actor = null
	var best_score: float = 9999.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead:
			continue
		var origin: Vector3 = e.get_global_transform_interpolated().origin
		# unproject_position mirrors anything behind the camera back onto the screen: such an enemy would be "under" the
		# cursor (highlighted, and chased on click) with nothing visible there.
		if camera.is_position_behind(origin) or camera.is_position_behind(origin + Vector3(0, e.body_height, 0)):
			continue
		var feet: Vector2 = camera.unproject_position(origin)
		var head: Vector2 = camera.unproject_position(origin + Vector3(0, e.body_height, 0))
		var pixels_per_metre: float = maxf(feet.distance_to(head) / e.body_height, 1.0)
		var reach: float = minf(e.body_radius * pixels_per_metre + 4.0, 90.0)   # close to the camera the projection blows up
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(mouse, feet, head)
		var d: float = mouse.distance_to(closest)
		if d <= reach and d < best_score:
			best_score = d
			best = e
	# Fall back to the ground point so clicking right at an enemy's feet still selects it.
	if best == null:
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Actor
			if e == null or e.dead:
				continue
			var gap: Vector3 = e.global_position - cursor
			gap.y = 0.0
			if gap.length() <= e.body_radius + 0.15 and gap.length() < best_score:
				best_score = gap.length()
				best = e
	return best
func _process(_delta: float) -> void:
	if skills.fire_orb != null and is_instance_valid(skills.fire_orb):
		skills.fire_orb.global_position = skills.orb_home()
	# Crosshair cursor and a ring under whatever enemy the mouse is over (or that we are attacking).
	var on_enemy: bool = hover_target != null
	if on_enemy != _cursor_on_enemy:
		_cursor_on_enemy = on_enemy
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if on_enemy else Input.CURSOR_ARROW)
	if _ring == null:
		_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.93
		torus.outer_radius = 1.0
		_ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.25, 0.2, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring.material_override = mat
		_ring.top_level = true
		_ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	var focus: Actor = hover_target
	if focus == null and attack_target != null and not attack_target.dead:
		focus = attack_target
	_ring.visible = focus != null and not focus.dead
	if _ring.visible:
		var radius: float = focus.body_radius * 1.5
		var origin: Vector3 = focus.get_global_transform_interpolated().origin
		_ring.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), Vector3(origin.x, 0.05, origin.z))

## The mouse is over a HUD panel (minimap, hotbar, bars).
func mouse_over_ui(at: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	if Gamepad.active:
		return false
	var mouse: Vector2 = get_viewport().get_mouse_position() if at.x < 0.0 else at
	for node in get_tree().get_nodes_in_group("hud"):
		if node.has_method("covers") and node.covers(mouse):
			return true
	return false

var _ui_click: bool = false   # the current mouse press started on the interface: it does not move or attack

func enemy_near(point: Vector3, max_dist: float) -> Actor:
	var best: Actor = null
	var best_d: float = max_dist
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead:
			continue
		var d: Vector3 = e.global_position - point
		d.y = 0.0
		if d.length() < best_d:
			best_d = d.length()
			best = e
	return best

func _read_input(cursor: Vector3) -> void:
	var ctrl: bool = Input.is_action_pressed("stand_still")

	if Input.is_action_just_pressed("click"):
		_ui_click = mouse_over_ui()
	if not Input.is_action_pressed("click"):
		_ui_click = false
	if Input.is_action_just_pressed("click") and not _ui_click:
		var hover: Actor = _hover_pick(cursor)
		skills.queued_skill = ""
		if ctrl:
			click_mode = 2
		elif hover:
			click_mode = 1
			attack_target = hover
			movement.has_goal = false
		else:
			click_mode = 0
			attack_target = null
			Fx.click_marker(self, cursor)
			# Clicking the ground means "go there": drop a swing in progress instead of finishing it.
			if skills.busy and not movement.rolling and skills.swing_cancellable_by_move():
				skills.cancel_action()
	if Input.is_action_pressed("click") and not _ui_click:
		match click_mode:
			0:
				movement.goal = Nav.snap(self, cursor)  # clicking inside a pillar goes to the nearest reachable spot
				movement.has_goal = true
			1:
				if attack_target == null or attack_target.dead:
					attack_target = enemy_near(cursor, 3.0)
					if attack_target == null:
						click_mode = 0
			2:
				attack_target = enemy_near(cursor, 10.0)

	for i in skills.hotbar.size():
		var action: String = "skill_%d" % (i + 1)
		if SkillDb.all()[skills.hotbar[i]].get("directional", false):
			if Input.is_action_just_pressed(action):
				skills.try_directional(skills.hotbar[i], cursor)
		elif SkillDb.all()[skills.hotbar[i]].get("aimed", false):
			skills.handle_aimed_key(action, skills.hotbar[i], cursor)
		elif Input.is_action_just_pressed(action) or Input.is_action_pressed(action):
			if skills.hotbar[i] != "potion":  # potions are handled every frame in _handle_hotkeys, even mid-animation
				skills.queue_skill(skills.hotbar[i], cursor)
	if SkillDb.all()[skills.right_click_skill].get("aimed", false):
		skills.handle_aimed_key("alt_skill", skills.right_click_skill, cursor)
	elif Input.is_action_pressed("alt_skill"):
		skills.queue_skill(skills.right_click_skill, cursor)

func _on_death() -> void:
	skills.drop_orb()

# --- Acting ------------------------------------------------------------------

func _act(delta: float, cursor: Vector3) -> void:
	var ctrl: bool = Input.is_action_pressed("stand_still")
	var skill_id: String = ""
	var target: Actor = null
	if skills.queued_skill != "" and skills.queued_target != null and not skills.queued_target.dead:
		skill_id = skills.queued_skill
		target = skills.queued_target
	elif attack_target != null and not attack_target.dead:
		skill_id = "basic"
		target = attack_target
	else:
		skills.queued_skill = ""
		attack_target = null

	if skill_id != "" and target != null:
		var skill: Dictionary = SkillDb.all()[skill_id]
		var dist: float = flat_distance_to(target) - target.body_radius
		if dist <= float(skill["range"]):
			if stats.can_use(skill_id):
				skills.start_skill(skill_id, target)
				return
			if stats.mana < float(skill["mana"]):
				_say("Not enough mana")
			skills.queued_skill = ""
			move_with(Vector3.ZERO)
			face(target.global_position, 0.4)
			return
		if ctrl:
			face(target.global_position, 0.4)
			move_with(Vector3.ZERO)
			return
		if Gamepad.move_vector().length() == 0.0:   # with the left stick in use the player steers; no auto-chase
			movement.goal = target.global_position
			movement.has_goal = true

	if ctrl:
		face(cursor, 0.4)
		move_with(Vector3.ZERO)
		return
	movement.move(delta)

func on_dealt_hit(target: Actor, result: Dictionary) -> void:
	var outcome: int = result.get("outcome", 0)
	if outcome == Combat.Outcome.CRITICAL or outcome == Combat.Outcome.CRUSHING:
		Gamepad.rumble(0.15, 0.55, 0.14)
	if not result.get("secondary", false):
		skills.blade_blood = minf(skills.blade_blood + 0.05, 1.0)
	if result.get("skill_id", "") != "earthshatter":
		stats.gain_ult_charge(float(result.get("damage", 0.0)))   # the ultimate does not charge itself
	ItemEffects.on_dealt_hit(self, target, result)

func on_enemy_killed(enemy: Actor) -> void:
	ItemEffects.on_kill(self, enemy)

func _filter_incoming(result: Dictionary) -> Dictionary:
	return ItemEffects.filter_incoming(self, result)

func is_acting() -> bool:
	return skills.busy

func _say(text: String) -> void:
	message = text
	message_time = 1.5

func _on_hurt(result: Dictionary, _source_pos: Vector3) -> void:
	var share: float = float(result.get("damage", 0.0)) / maxf(max_health, 1.0)
	Gamepad.rumble(0.3 + share * 2.0, 0.4 + share * 3.0, 0.18 + share)
	combat_timer = 5.0
	hurt_flash = 1.0
	Sfx.play(self, "hurt", -2.0)
	Fx.shake(self, 0.08)

func _on_avoided(_outcome: int) -> void:
	combat_timer = 5.0

func _popup_tint() -> Color:
	return Color(1.0, 0.35, 0.3)
