class_name Player
extends Actor
## Click-to-move action RPG hero. Control scheme follows the Zombasite manual:
##  - Left click ground: move (hold to keep moving). Left click enemy: walk up and attack, hold to keep attacking.
##  - Number keys: use the hotbar skill on the enemy nearest the cursor. Hold to repeat.
##  - Right click: use the right-click skill (default basic attack) on the enemy nearest the cursor.
##  - Ctrl (hold): stand still, so clicks and skills never move the hero.
##  - Attacks and casts root the hero until the swing finishes (StandStillToCast).

const MODEL_DIR := "res://assets/models/knight2"
const HELD_SCALE := 0.85   # how much of a weapon's real length shows in the hand
const SWORD_PATH := "res://assets/models/sword/model.glb"
# Sword orientation in the hand bone: index into GRIPS (tuned by eye with --grip=N screenshots).
const GRIPS: Array[Basis] = [Basis(), Basis(Vector3(0, 0, 1), -PI / 2), Basis(Vector3(0, 0, 1), PI / 2),
	Basis(Vector3(1, 0, 0), PI / 2), Basis(Vector3(1, 0, 0), -PI / 2), Basis(Vector3(1, 0, 0), PI)]
# Middle of the right fist in the hand bone's space (rig units are cm; the bone origin is the wrist).
const HAND_GRIP_POINT := Vector3(-0.8, 15.0, 0.5)
const CLIPS: Array[String] = ["idle_alert", "walk", "run", "charge", "throw", "charge_run", "kick", "slash", "slash_l", "slash_r", "thrust", "combo_end", "power", "cast", "roll", "hit", "death", "leap", "stomp", "yank", "jump", "earthshatter", "atk_slash_r", "atk_slash_l", "atk_slash", "atk_thrust", "atk_finisher", "atk2_slash_r", "atk2_slash_l", "atk2_slash", "atk2_thrust", "atk2_finisher", "idle_rest", "wthrow", "wthrow_release", "wthrow_catch"]

# State the hero itself owns (everything else lives in a component).
var combat_timer: float = 0.0
var message: String = ""
var message_time: float = 0.0
var hurt_flash: float = 0.0
var attack_target: Actor
var pickup_target: LootDrop   # an item the hero was sent to take (click it, or its name): nothing is picked up by walking over it
var attack_prop: Destructible   # a barrel the hero was told to smash (only barrels can be attacked for now)
var hover_target: Actor  # enemy under the mouse cursor, for the health bar and highlight ring
var _ring: MeshInstance3D
var _cursor_on_enemy: bool = false
var click_mode: int = 0  # 0 move, 1 attack locked target, 2 stand-still attack
var _was_stunned: bool = false
var _trail: WeaponTrail
var _dormancy_timer: float = 0.0
var _pad_hold: Vector3 = Vector3.ZERO          # aim offset kept while an aimed skill button is held
var _pad_hold_valid: bool = false

# Components (see game/player/ and game/skills/). Each owns one slice of what the hero is and does.
var skewer: SkewerSkill
var leap: LeapSkill
var earthshatter: EarthshatterSkill
var movement: PlayerMovement
var stats: PlayerStats
var skills: SkillController
var weapon_throw: WeaponThrowSkill

func _init() -> void:
	skewer = SkewerSkill.new(self)
	leap = LeapSkill.new(self)
	earthshatter = EarthshatterSkill.new(self)
	movement = PlayerMovement.new(self)
	stats = PlayerStats.new(self)
	skills = SkillController.new(self)
	weapon_throw = WeaponThrowSkill.new(self)

var _grip_index: int = 3
var _held_path: String = SWORD_PATH

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
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--grip="):
				_grip_index = int(arg.substr(7))
		model.attach_weapon(SWORD_PATH, "RightHand", GRIPS[_grip_index], 1.25, 0.12, HAND_GRIP_POINT, 1.7)
		_trail = WeaponTrail.new()
		_trail.base_node = model.weapon_base
		_trail.tip_node = model.weapon_tip
		add_child(_trail)
	for item in Items.starting_gear():
		stats.equip(item, false)

## The hero holds the model of the weapon that is equipped (the same models the weapons lie on the ground as), at a size that
## follows the weapon; a base with no model keeps the old sword.
func refresh_weapon_model() -> void:
	if model == null or not ResourceLoader.exists(SWORD_PATH):
		return
	var worn: Variant = stats.equipment.get(Items.Slot.WEAPON)
	var path: String = SWORD_PATH
	if worn != null and ResourceLoader.exists(Items.model_path(worn as Dictionary)):
		path = Items.model_path(worn as Dictionary)
	if path == _held_path:
		return
	_held_path = path
	model.clear_weapon()
	if path == SWORD_PATH:
		model.attach_weapon(SWORD_PATH, "RightHand", GRIPS[_grip_index], 1.25, 0.12, HAND_GRIP_POINT, 1.7)
	else:
		# Built lying down with the pommel at -X and the point at +X: turn it upright. About 0.85 of its real length in the hand.
		var measured: Node3D = (load(path) as PackedScene).instantiate()
		var bounds: AABB = CharacterModel._bounds_of(measured)
		measured.free()   # only measured, never shown
		model.attach_weapon(path, "RightHand", GRIPS[_grip_index], bounds.size.x * HELD_SCALE, 0.11, HAND_GRIP_POINT, 1.8,
			Basis(Vector3(0, 0, 1), PI * 0.5), true)
	if _trail != null:
		_trail.base_node = model.weapon_base
		_trail.tip_node = model.weapon_tip

## Whether a Skewer charge is under way (wind-up, run or skid): nothing may stall or push the hero then.
func is_charging() -> bool:
	return skewer.skewer_phase >= 1 and skewer.skewer_phase <= 3

## The hero is never frozen by the blows he lands while charging: every enemy the blade takes would otherwise stop him for a beat.
func add_hitpause(duration: float) -> void:
	if is_charging():
		return
	super.add_hitpause(duration)

# --- Build (see BuildDefs, TownState): what the hero has bought; read straight from the one saved source, never cached here -----------------

func has_passive(id: String) -> bool:
	return TownState.has_passive(id)

func evolution_of(skill_id: String) -> String:
	return TownState.selected_evolution(skill_id)

## One blow is HEAVY at a tenth of max health or an enemy's heavy attack; anything else is light. (The one definition: Unbowed, Stubborn
## Advance, Iron Recovery and Retaliation all ask it.)
func is_heavy_hit(result: Dictionary) -> bool:
	return float(result.get("damage", 0.0)) >= max_health * BuildDefs.HEAVY_HIT_FRACTION or float(result.get("weight", 1.0)) >= BuildDefs.HEAVY_HIT_WEIGHT

const COMMITTED_SKILLS: Array[String] = ["power", "skewer", "leap", "throw"]

## Winding up or charging one of the heavy skills (aiming a held one, or between the start of a committed one and its strike).
func is_committed_windup() -> bool:
	return skills.aiming_id != "" or weapon_throw.charging() or (skills.busy and not skills.busy_hit_done and skills.busy_skill in COMMITTED_SKILLS)

## Pressing in on a target (clicked or locked on), not busy with a skill, not in town idling.
func is_advancing() -> bool:
	return attack_target != null and is_instance_valid(attack_target) and not attack_target.dead and not skills.busy and not movement.rolling

var retaliation_time: float = 0.0           # Retaliation: seconds left in which the next basic strike staggers hard
var unbowed_suppressed: int = 0             # how often Unbowed / Stubborn Advance have shrugged a light stagger off (tests, diagnostics)
var stubborn_suppressed: int = 0
var iron_shoves: int = 0
var retaliations_fired: int = 0
var last_stun_blocked: String = ""
var _unbowed_ready_ms: int = 0
var _recovery_shove_armed: bool = false
var _stun_prev: bool = false

## A stagger that would stop him. A LIGHT one is shrugged off while he winds up a heavy skill (Unbowed, then a short cooldown so chip
## damage cannot make him unstoppable) or presses in on a target (Stubborn Advance: he only flinches, slowed a moment). A HEAVY one always
## lands, and with Iron Recovery arms the shove he makes when he shakes it off. None of this is damage immunity.
func _gain_stun(duration: float, result: Dictionary = {}) -> void:
	var heavy: bool = is_heavy_hit(result)
	if not heavy:
		if has_passive("unbowed") and is_committed_windup() and Time.get_ticks_msec() >= _unbowed_ready_ms:
			_unbowed_ready_ms = Time.get_ticks_msec() + int(BuildDefs.UNBOWED_COOLDOWN * 1000.0)
			unbowed_suppressed += 1
			last_stun_blocked = "unbowed"
			return
		if has_passive("stubborn_advance") and is_advancing():
			apply_slow(BuildDefs.STUBBORN_SLOW, BuildDefs.STUBBORN_SLOW_TIME)
			stubborn_suppressed += 1
			last_stun_blocked = "stubborn_advance"
			return
	super._gain_stun(duration, result)
	if heavy and has_passive("iron_recovery"):
		_recovery_shove_armed = true

## Iron Recovery: shaking off a heavy stagger, he drives the lesser enemies round him back with his whole body (no damage; bosses and
## heavy bodies resist).
func _iron_recovery() -> void:
	iron_shoves += 1
	var centre: Vector3 = global_position
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.impaled or e.is_boss or e.knock_resist >= 0.5 or e.flat_distance_to(self) > BuildDefs.IRON_RADIUS + e.body_radius:
			continue
		var away: Vector3 = e.global_position - centre
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
		e.knock += away * BuildDefs.IRON_KNOCK * (1.0 - e.knock_resist)
		e.interrupt(BuildDefs.IRON_STAGGER)
	Fx.ring(self, centre + Vector3(0, 0.08, 0), BuildDefs.IRON_RADIUS * 0.8, Color(0.75, 0.62, 0.45))
	Fx.burst(self, centre + Vector3(0, 0.2, 0), Vector3.UP, Color(0.42, 0.36, 0.28), 14, 3.5, 0.05)
	Fx.shake(self, 0.1)
	Fx.punch(self, 1.4)

func _physics_process(delta: float) -> void:
	weapon_throw.tick(delta)
	_dormancy_timer -= delta
	if _dormancy_timer <= 0.0:
		_dormancy_timer = 0.5
		_manage_dormancy()
	if skewer.skewer_phase >= 1 and skewer.skewer_phase <= 3:
		knock = Vector3.ZERO   # nothing pushes the hero off a Skewer charge, not even a hit-pause frame
	if _actor_tick(delta):
		move_with(Vector3.ZERO)
		return
	if dead:
		return
	retaliation_time = maxf(retaliation_time - delta, 0.0)
	var stunned_now: bool = stun_time > 0.0
	if _stun_prev and not stunned_now and _recovery_shove_armed:
		_recovery_shove_armed = false
		_iron_recovery()
	_stun_prev = stunned_now
	hurt_flash = maxf(hurt_flash - delta * 2.5, 0.0)
	skills.update_blade_blood(delta)
	skills.update_buff_visuals()
	if model != null and model.weapon != null:
		model.weapon.visible = not weapon_throw.is_away() and not (skills.busy and bool(skills.busy_def.get("charged", false)))   # (not while it is out in the world)
	if not skills.busy and visual != null and absf(visual.rotation.x) > 0.001:
		visual.rotation.x = lerpf(visual.rotation.x, 0.0, 1.0 - exp(-14.0 * delta))
	message_time = maxf(message_time - delta, 0.0)
	combat_timer = maxf(combat_timer - delta, 0.0)
	for id in stats.cooldowns.keys():
		stats.cooldowns[id] = maxf(float(stats.cooldowns[id]) - delta, 0.0)
	stats.regen(delta)
	stats.haste_time = maxf(stats.haste_time - delta, 0.0)
	stats.vault_time = maxf(stats.vault_time - delta, 0.0)
	stats.chain_time = maxf(stats.chain_time - delta, 0.0)
	if stats.chain_time <= 0.0:
		stats.chain_stacks = 0
	stats.collect_orbs()
	skills.combo_timer = maxf(skills.combo_timer - delta, 0.0)
	if skills.combo_timer <= 0.0 and not skills.busy:
		skills.combo_step = 0

	_update_pad_aim(delta)
	var cursor: Vector3 = cursor_world()
	hover_target = _hover_pick(cursor)
	if skills.aiming_id != "" and (movement.rolling or stun_time > 0.0):
		skills.clear_aim()
	skills.check_cancel()
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
	if Gamepad.active and skills.aiming_id != "":
		face(cursor, 0.3)   # holding an aimed skill: the hero looks at the target area
	_read_input(cursor)
	_act(delta, cursor)
	movement.update_locomotion_anim()

# --- Input -------------------------------------------------------------------

## Where the hero is "pointing": the mouse position on the ground, or with a controller the right-stick aim point.
## The self-test points the cursor with this (there is no mouse); INF means use the real one.
var cursor_override: Vector3 = Vector3.INF

func cursor_world() -> Vector3:
	if cursor_override != Vector3.INF:
		return cursor_override
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

## Controller aim. Normally the cursor is simply the enemy the hero is facing (see pad_facing_target); the right stick is the
## camera. Holding an aimed skill's button (Fireball) is the exception: the target area snaps to that enemy once, when the button
## goes down, and from then on the right stick slides it freely (no snapping back onto enemies) until the button is released.
const PAD_AIM_SPEED := 11.0     # metres per second at full stick
const PAD_AIM_REACH := 16.0

func _update_pad_aim(delta: float) -> void:
	if not Gamepad.active or skills.aiming_id == "":
		_pad_hold_valid = false
		return
	if not _pad_hold_valid:
		_pad_hold = _pad_default_target()   # the one and only snap
		_pad_hold_valid = true
	var stick: Vector2 = Gamepad.aim_vector()
	if stick.length() > 0.0:
		_pad_hold += Gamepad.to_world(stick) * (PAD_AIM_SPEED * stick.length() * delta)
		var offset: Vector3 = _pad_hold - global_position
		offset.y = 0.0
		_pad_hold = global_position + offset.limit_length(PAD_AIM_REACH)
	_pad_hold.y = 0.0

func _pad_cursor() -> Vector3:
	if skills.aiming_id != "":
		if not _pad_hold_valid:
			_pad_hold = _pad_default_target()
			_pad_hold_valid = true
		return _pad_hold
	_pad_hold_valid = false
	return _pad_default_target()

## With a controller the hero's target is the enemy nearest to where the model is facing (close counts, and so does being straight
## ahead; anything behind is a last resort). It sticks to its choice until another enemy is clearly better, so the highlight does
## not flicker between two enemies; holding A attacks it. With no enemy about, a spot straight ahead.
const PAD_TARGET_RANGE := 14.0
const PAD_TARGET_STICKY := 1.3
var _pad_target: Actor

func _pad_default_target() -> Vector3:
	var target: Actor = pad_facing_target()
	if target != null:
		return target.global_position
	return global_position + Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y)) * 7.0

func pad_facing_target() -> Actor:
	var forward := Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	var best: Actor = null
	var best_score: float = INF
	var kept_score: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead:
			continue
		var offset: Vector3 = e.global_position - global_position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist > PAD_TARGET_RANGE:
			continue
		var angle: float = forward.angle_to(offset) if dist > 0.05 else 0.0   # 0 straight ahead .. PI directly behind
		var score: float = dist * (1.0 + angle * 0.9) + (6.0 if angle > deg_to_rad(100.0) else 0.0)
		if score < best_score:
			best_score = score
			best = e
		if e == _pad_target:
			kept_score = score
	if _pad_target != null and is_instance_valid(_pad_target) and not _pad_target.dead and kept_score <= best_score * PAD_TARGET_STICKY:
		return _pad_target
	_pad_target = best
	return best

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
	if not is_instance_valid(focus):
		focus = null   # freed since last frame (a dead enemy removed from the scene)
	_update_focus_glow(focus)
	_ring.visible = focus != null and not focus.dead
	if _ring.visible:
		var radius: float = focus.body_radius * 1.5
		var origin: Vector3 = focus.get_global_transform_interpolated().origin
		_ring.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), Vector3(origin.x, 0.05, origin.z))

var _glowing: Actor

## With the pad the targeted enemy also glows (the ring alone is easy to lose in a crowd).
func _update_focus_glow(focus: Variant) -> void:
	var want: Actor = focus as Actor if (Gamepad.active and is_instance_valid(focus) and not (focus as Actor).dead and skills.aiming_id == "") else null
	if _glowing != null and _glowing != want and is_instance_valid(_glowing):
		_glowing.set_highlighted(false)
	_glowing = want
	if _glowing != null:
		_glowing.set_highlighted(true)

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
	_pursue_pickup(ctrl)

	if Input.is_action_just_pressed("click"):
		_ui_click = mouse_over_ui()
	if not Input.is_action_pressed("click"):
		_ui_click = false
	if Input.is_action_just_pressed("click") and not _ui_click:
		var hover: Actor = _hover_pick(cursor)
		var loot: LootDrop = LootDrop.focused if is_instance_valid(LootDrop.focused) else null
		skills.clear_queue()
		pickup_target = null
		if loot != null and not ctrl:   # an item, or its name, under the pointer: go and take it
			click_mode = 4
			pickup_target = loot
			attack_target = null
			attack_prop = null
			movement.goal = Nav.snap(self, loot.global_position)
			movement.has_goal = true
		elif ctrl:
			click_mode = 2
		elif hover:
			click_mode = 1
			attack_target = hover
			attack_prop = null
			movement.has_goal = false
		elif Destructible.near(get_tree(), cursor, 0.35, Destructible.HERO) != null:
			click_mode = 3
			attack_target = null
			attack_prop = Destructible.near(get_tree(), cursor, 0.35, Destructible.HERO)
			movement.has_goal = false
		else:
			attack_prop = null
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
			3:
				if attack_prop == null or not is_instance_valid(attack_prop) or attack_prop.broken:
					attack_prop = null
					click_mode = 0

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
	# The right mouse button carries whichever skill is on it (the attack by default), and drives it the way a numbered slot would.
	var alt_id: String = skills.right_click_skill
	var alt_def: Dictionary = SkillDb.all()[alt_id]
	if bool(alt_def.get("directional", false)):
		if Input.is_action_just_pressed("alt_skill") and not skills.swallow_alt:
			skills.try_directional(alt_id, cursor)
	elif bool(alt_def.get("aimed", false)):
		skills.handle_aimed_key("alt_skill", alt_id, cursor)
	elif alt_id == "potion":
		if Input.is_action_just_pressed("alt_skill") and not skills.swallow_alt:
			skills.drink_potion()
	elif Input.is_action_pressed("alt_skill") and not skills.swallow_alt:
		skills.queue_skill(alt_id, cursor)
	if not Input.is_action_pressed("alt_skill"):
		skills.swallow_alt = false

## Walks to the item the hero was sent for and takes it as soon as it is in reach; the use key takes the nearest one in reach too, which
## is how a controller (or the keyboard) picks things up.
func _pursue_pickup(stand_still: bool) -> void:
	if dead:
		return
	if pickup_target != null:
		if not is_instance_valid(pickup_target):
			pickup_target = null
			click_mode = 0
		elif pickup_target.in_reach(self):
			pickup_target.pick_up(self)
			pickup_target = null
			click_mode = 0
			movement.has_goal = false
		elif not stand_still:
			movement.goal = Nav.snap(self, pickup_target.global_position)
			movement.has_goal = true
	if Input.is_action_just_pressed("interact"):
		var nearest: LootDrop = null
		var nearest_d: float = INF
		for node in get_tree().get_nodes_in_group("loot"):
			var drop := node as LootDrop
			if drop != null and drop.in_reach(self):
				var d: float = drop.global_position.distance_to(global_position)
				if d < nearest_d:
					nearest_d = d
					nearest = drop
		if nearest != null:
			nearest.pick_up(self)

## Monsters still asleep and far from the hero are switched off (not drawn, not run, not animated) until he comes back; see Enemy.SLEEP_RANGE.
func _manage_dormancy() -> void:
	var here: Vector2 = Vector2(global_position.x, global_position.z)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead or e.is_aggro():
			continue
		var d: float = here.distance_to(Vector2(e.global_position.x, e.global_position.z))
		e.set_dormant(d > (Enemy.WAKE_RANGE if e.dormant else Enemy.SLEEP_RANGE))

func _exit_tree() -> void:
	if weapon_throw != null:
		weapon_throw.reset()

func _on_death() -> void:
	weapon_throw.reset()   # a weapon out in the world comes back to his hand: it is never left lying where he fell
	skills.reset()

## Back on his feet at `pos` (the world has no run to end when the hero falls: he is dragged home): whole, standing, the death
## animation put away, and a moment of grace before anything can hurt him.
func revive_at(pos: Vector3) -> void:
	if not dead:
		return
	weapon_throw.reset()
	dead = false
	if ragdoll != null and ragdoll.is_active():
		ragdoll._finish()
	set_physics_process(true)
	for shape in find_children("*", "CollisionShape3D", false, false):
		(shape as CollisionShape3D).set_deferred("disabled", false)
	visual.visible = true
	visual.rotation = Vector3(0.0, PI, 0.0)
	health = max_health
	stats.mana = stats.max_mana
	stats.stamina = stats.max_stamina
	stun_time = 0.0
	hitpause = 0.0
	invulnerable_time = 2.5
	velocity = Vector3.ZERO
	attack_target = null
	attack_prop = null
	skills.reset()
	movement.has_goal = false
	global_position = pos
	reset_physics_interpolation()
	model.current = ""   # the death clip is over: the next loop() must really start the idle
	model.loop("idle_alert")

# --- Acting ------------------------------------------------------------------

func _act(delta: float, cursor: Vector3) -> void:
	var ctrl: bool = Input.is_action_pressed("stand_still")
	if attack_prop != null:
		if not is_instance_valid(attack_prop) or attack_prop.broken:
			attack_prop = null
		elif attack_target == null and skills.queued_skill == "":
			var offset: Vector3 = attack_prop.global_position - global_position
			offset.y = 0.0
			if offset.length() - attack_prop.radius <= 1.6:
				face(attack_prop.global_position, 0.4)
				if stats.can_use("basic"):
					skills.start_skill("basic", null, attack_prop.global_position)
				else:
					move_with(Vector3.ZERO)
				return
			if not ctrl and Gamepad.move_vector().length() == 0.0:
				movement.goal = attack_prop.global_position
				movement.has_goal = true
	var skill_id: String = ""
	var target: Actor = null
	if skills.queued_skill != "" and is_instance_valid(skills.queued_target) and not skills.queued_target.dead:
		skill_id = skills.queued_skill
		target = skills.queued_target
	elif is_instance_valid(attack_target) and not attack_target.dead:
		skills.clear_queue()
		skill_id = "basic"
		target = attack_target
	else:
		skills.clear_queue()
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
			skills.clear_queue()
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
	if retaliation_time > 0.0 and String(result.get("skill_id", "")) == "basic" and not result.get("secondary", false):
		_retaliate(target)
	if outcome == Combat.Outcome.CRITICAL or outcome == Combat.Outcome.CRUSHING:
		Gamepad.rumble(0.15, 0.55, 0.14)
	if not result.get("secondary", false):
		skills.blade_blood = minf(skills.blade_blood + 0.05, 1.0)
	if result.get("skill_id", "") != "earthshatter":
		stats.gain_ult_charge(float(result.get("damage", 0.0)))   # the ultimate does not charge itself
	ItemEffects.on_dealt_hit(self, target, result)

func on_enemy_killed(enemy: Actor) -> void:
	ItemEffects.on_kill(self, enemy)
	if has_passive("bloody_recovery") and enemy.hero_credited() and String(enemy.last_result.get("skill_id", "")) in BuildDefs.PHYSICAL_FINISHERS:
		stats.stamina_free_time = BuildDefs.BLOODY_RECOVERY_SECONDS   # a physical finish: the normal wait for stamina is gone at once

## Retaliation: the basic strike that lands inside the window sends its target reeling (no extra damage), and uses the window up.
func _retaliate(target: Actor) -> void:
	retaliation_time = 0.0
	retaliations_fired += 1
	var away: Vector3 = target.global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	target.interrupt(BuildDefs.RETALIATION_STAGGER)
	target.knock += away * BuildDefs.RETALIATION_KNOCK * (1.0 - target.knock_resist)
	Fx.ring(self, target.global_position + Vector3(0, 0.08, 0), 1.6, Color(0.9, 0.55, 0.25))
	Fx.punch(self, 1.6)

func _filter_incoming(result: Dictionary) -> Dictionary:
	return ItemEffects.filter_incoming(self, result)

## The throw samples aim at release, after the short catch beat. Stick input wins
## while it is active; otherwise the controller uses current combat facing.
func throw_aim_direction() -> Vector3:
	var direction: Vector3 = Vector3.ZERO
	if Gamepad.active:
		var stick: Vector2 = Gamepad.aim_vector()
		if stick.length() > 0.1:
			direction = Gamepad.to_world(stick)
		else:
			direction = Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	else:
		direction = cursor_world() - global_position
		direction.y = 0.0
		if direction.length() < 0.2:
			direction = Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	return direction.normalized()

func is_acting() -> bool:
	return skills.busy

func _say(text: String) -> void:
	message = text
	message_time = 1.5

func _on_hurt(result: Dictionary, _source_pos: Vector3) -> void:
	ItemEffects.on_player_hurt(self)
	if has_passive("retaliation") and is_heavy_hit(result) and float(result.get("damage", 0.0)) > 0.0:
		retaliation_time = BuildDefs.RETALIATION_SECONDS   # a heavy hit taken: the next basic strike will send its target reeling
	var share: float = float(result.get("damage", 0.0)) / maxf(max_health, 1.0)
	Gamepad.rumble(0.3 + share * 2.0, 0.4 + share * 3.0, 0.18 + share)
	combat_timer = 5.0
	hurt_flash = 1.0
	Fx.shake(self, 0.08)

func _on_avoided(_outcome: int) -> void:
	combat_timer = 5.0

func _popup_tint() -> Color:
	return Color(1.0, 0.35, 0.3)
