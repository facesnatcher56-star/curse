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
const CLIPS: Array[String] = ["idle_alert", "walk", "run", "charge", "throw", "charge_run", "kick", "slash", "slash_l", "slash_r", "thrust", "combo_end", "power", "cast", "roll", "hit", "block", "death", "leap", "stomp", "yank", "jump", "earthshatter", "atk_slash_r", "atk_slash_l", "atk_slash", "atk_thrust", "atk_finisher", "atk2_slash_r", "atk2_slash_l", "atk2_slash", "atk2_thrust", "atk2_finisher", "idle_rest", "wthrow", "wthrow_release", "wthrow_catch"]

# State the hero itself owns (everything else lives in a component).
var combat_timer: float = 0.0
var message: String = ""
var message_time: float = 0.0
var hurt_flash: float = 0.0
var _attack_engaged: bool = false
var attack_target: Actor:
	set(value):
		attack_target = value
		_attack_engaged = is_instance_valid(value)
var chest_target: Chest   # a treasure chest the hero was sent to open (click it): walks up and opens it once in reach
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
var movement: PlayerMovement
var stats: PlayerStats
var skills: SkillController
var powers: PowerController   # the DS2 powers that play (Whirling Strike, War Cry ...)
var knockdown: Knockdown
var hit_reaction: HitReaction
var openings: Openings   # the Opening passive: a mark on an enemy, and its execution (game/player/openings.gd)
var member_id: String = "hero"
var character: CharacterState:
	get: return PartyManager.current().member(member_id)
var ai: PartyCharacterAI
var bow: BowAttack
## Worn equipment shown as separate skinned pieces (see ModularAppearance); null on the default fused-mesh rigs.
var appearance: ModularAppearance
var input_locked: bool = false

func is_controlled() -> bool:
	return PartyManager.current().active_id == member_id

func combat_identity() -> Dictionary:
	return {"character_id": member_id, "owner_id": character.owner_id}

func release_control() -> void:
	skills.cancel_take_aim_targeting()
	skills.clear_aim()
	skills.clear_queue()
	click_mode = 0
	pickup_target = null
	chest_target = null
	attack_prop = null
	movement.has_goal = false
	hover_target = null
	set_highlighted(false)

func receive_control() -> void:
	input_locked = true
	attack_target = null
	skills.clear_queue()
	movement.has_goal = false

func capture_state() -> void:
	var saved_bow: Dictionary = character.power_state.get("bow", {})
	if bow != null:
		saved_bow = {"armed": bow.armed, "required": bow.reload_required, "remaining": bow.reload_remaining}
	character.health = health
	character.mana = stats.mana
	character.equipment = stats.equipment
	character.power_state = {"initialized": true, "brutal_armed": skills.brutal_armed,
		"brutal_required": stats.brutal_reload_required, "brutal_remaining": stats.brutal_reload_remaining,
		"required": powers.reload_required.duplicate(true), "remaining": powers.reload_remaining.duplicate(true),
		"staggering_armed": powers.staggering_armed, "forced_crits": forced_crits, "bow": saved_bow,
		"provoke_time": powers.provoke_time, "provoke_armor_pct": powers.provoke_armor_pct,
		"repulse_time": powers.repulse_time, "repulse_radius": powers._repulse_radius,
		"repulse_push": powers._repulse_push, "repulse_stun": powers._repulse_stun}

func _init() -> void:
	movement = PlayerMovement.new(self)
	stats = PlayerStats.new(self)
	skills = SkillController.new(self)
	powers = PowerController.new(self)
	knockdown = Knockdown.new(self)
	hit_reaction = HitReaction.new(self)
	openings = Openings.new(self)

var _grip_index: int = 3
var _held_path: String = SWORD_PATH

func _ready() -> void:
	add_to_group("player")
	# The window sees every pointer event before it is routed to a popup or control, so a press that a dropdown consumes is still latched.
	get_tree().root.window_input.connect(_latch_ui_click)
	PartyManager.current().bodies[member_id] = self
	ai = PartyCharacterAI.new(self)
	display_name = "Hero" if member_id == "hero" else "Cutter"
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	stats.refresh()   # DS2: life and mana from his attributes, which come from his class skills; his level is his character level
	health = max_health
	stats.mana = stats.max_mana
	armor = stats.base_armor
	block_chance = 0.0   # DS2: blocking needs a shield
	var folder := CharacterPresentation.folder(member_id)
	var clips: Array[String] = []
	clips.assign(CLIPS if member_id == "hero" else ["idle", "calm", "walk", "run"])
	var modular: bool = ModularAppearance.enabled_for(member_id)
	_build_model(folder, clips, 1.8, 0.4, not modular)
	CharacterPresentation.share_combat_clips(model)
	if modular:
		appearance = ModularAppearance.new(model)
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
	stats.equipment = character.equipment
	if stats.equipment.is_empty() and not character.power_state.has("initialized"):
		var kit: Array = Items.starting_gear() if member_id == "hero" else [Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow")]
		for item in kit: stats.equip(item, false)
	stats.refresh()
	refresh_appearance()
	refresh_weapon_model()
	if character.health >= 0.0: health = clampf(character.health, 0.0, max_health)
	if character.mana >= 0.0: stats.mana = clampf(character.mana, 0.0, stats.max_mana)
	var saved := character.power_state
	stats.brutal_reload_required = float(saved.get("brutal_required", 0.0))
	stats.brutal_reload_remaining = float(saved.get("brutal_remaining", 0.0))
	powers.reload_required = saved.get("required", {}).duplicate(true)
	powers.reload_remaining = saved.get("remaining", {}).duplicate(true)
	powers.staggering_armed = bool(saved.get("staggering_armed", false))
	skills.brutal_armed = bool(saved.get("brutal_armed", false))
	if skills.brutal_armed: skills._ensure_brutal_visual()
	forced_crits = int(saved.get("forced_crits", 0))
	powers.provoke_time = float(saved.get("provoke_time", 0.0))
	powers.provoke_armor_pct = float(saved.get("provoke_armor_pct", 0.0))
	powers.repulse_time = float(saved.get("repulse_time", 0.0))
	powers._repulse_radius = float(saved.get("repulse_radius", 0.0))
	powers._repulse_push = float(saved.get("repulse_push", 0.0))
	powers._repulse_stun = float(saved.get("repulse_stun", 0.0))
	character.power_state["initialized"] = true
	if health <= 0.0: _die()

func refresh_appearance() -> void:
	if appearance != null:
		appearance.sync(stats.equipment)

## The hero holds the model of the weapon that is equipped (the same models the weapons lie on the ground as), at a size that
## follows the weapon; a base with no model keeps the old sword.
func refresh_weapon_model() -> void:
	if model == null or not ResourceLoader.exists(SWORD_PATH):
		return
	if stats.is_ranged():
		if bow == null:
			model.clear_weapon()
			bow = BowAttack.new(self)
			bow.attach()
			var saved_bow: Dictionary = character.power_state.get("bow", {})
			bow.reload_required = float(saved_bow.get("required", 0.0))
			bow.reload_remaining = float(saved_bow.get("remaining", 0.0))
			if bool(saved_bow.get("armed", false)): bow.arm()
		return
	if bow != null:
		capture_state()
		bow.detach()
		bow = null
		_held_path = ""
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

## A HEAVY blow is an enemy's heavy attack (its strike weight, Actor.HEAVY_BLOW_WEIGHT); it puts him on the ground (see Knockdown).
func is_heavy_hit(result: Dictionary) -> bool:
	return float(result.get("weight", 1.0)) >= HEAVY_BLOW_WEIGHT

## A stagger that would stop him. A HEAVY one always lands and puts him on the ground (see Knockdown); a light one is an ordinary flinch.
func _gain_stun(duration: float, result: Dictionary = {}) -> void:
	if knockdown.active():
		return   # already down: the lock is the fall's own, and a second blow neither restarts nor stretches it
	if is_heavy_hit(result) and knockdown.begin():
		return
	super._gain_stun(duration, result)

## The flinch of an ordinary stagger. A blow that lands in the middle of a swing is only felt once the swing is over (the swing is
## never cut short), so the reaction runs at the speed that ends it with the stun: it never plays on after control is back, and a
## stagger with only a breath left is not acted out at all.
func _play_flinch() -> void:
	if stun_time < 0.08:
		return
	var speed: float = 1.4
	if model.anim != null and model.anim.has_animation("game/hit"):
		speed = clampf(model.anim.get_animation("game/hit").length / stun_time, 1.0, 2.2)
	model.once("hit", 0.0, speed, 0.1)
	hit_reaction.begin(_last_hit_from, stun_time)

func _physics_process(delta: float) -> void:
	powers.tick(delta)   # (power timers and Repulse's field run through a hit-pause too)
	openings.tick(delta)
	_dormancy_timer -= delta
	if _dormancy_timer <= 0.0:
		_dormancy_timer = 0.5
		_manage_dormancy()
	# Busy actions, hit-pause and control locks must not swallow an explicit ground order.
	# Consume only eligible world movement clicks here; normal enemy, loot and UI clicks
	# continue through the existing input path.
	var move_click: bool = false
	if not dead and is_controlled() and not input_locked and not movement.rolling \
			and (skills.busy or stun_time > 0.0 or knockdown.active()):
		move_click = _read_interrupt_move_click(cursor_world())
	if _actor_tick(delta):
		move_with(Vector3.ZERO)
		return
	if dead:
		return
	knockdown.tick(delta)
	hit_reaction.tick(delta)
	hurt_flash = maxf(hurt_flash - delta * 2.5, 0.0)
	skills.update_blade_blood(delta)
	if model != null and model.weapon != null:
		model.weapon.visible = not (skills.busy and bool(skills.busy_def.get("charged", false)))   # (put away while casting)
	if not skills.busy and not knockdown.active() and visual != null and absf(visual.rotation.x) > 0.001:
		visual.rotation.x = lerpf(visual.rotation.x, 0.0, 1.0 - exp(-14.0 * delta))
	message_time = maxf(message_time - delta, 0.0)
	combat_timer = maxf(combat_timer - delta, 0.0)
	for id in stats.cooldowns.keys():
		stats.cooldowns[id] = maxf(float(stats.cooldowns[id]) - delta, 0.0)
	stats.regen(delta)
	stats.collect_orbs()
	skills.combo_timer = maxf(skills.combo_timer - delta, 0.0)
	if skills.combo_timer <= 0.0 and not skills.busy:
		skills.combo_step = 0

	if not is_controlled():
		ai.track_orders(delta)   # (a nest order's end is kept track of through shots, rolls and stuns)
		if movement.rolling: movement.tick_roll(delta)
		elif skills.busy:
			skills.tick_busy(delta)
			move_with(Vector3.ZERO)
		elif stun_time <= 0.0: ai.tick(delta)
		else: move_with(Vector3.ZERO)
		return
	if input_locked:
		input_locked = Input.is_action_pressed("click") or Input.is_action_pressed("alt_skill")
		for i in 6: input_locked = input_locked or Input.is_action_pressed("skill_%d" % (i + 1))
		if input_locked:
			if skills.busy: skills.tick_busy(delta)
			return
	if move_click:
		if stun_time > 0.0 or knockdown.active():
			move_with(Vector3.ZERO)
			return
		_act(delta, cursor_world())
		movement.update_locomotion_anim()
		return
	_update_pad_aim(delta)
	var cursor: Vector3 = cursor_world()
	hover_target = _hover_pick(cursor)
	if skills.aiming_id != "" and (movement.rolling or stun_time > 0.0):
		skills.clear_aim()
	skills.check_cancel()
	if skills.take_aim_targeting and bow == null: skills.cancel_take_aim_targeting()
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
			if not knockdown.active():   # (the fall plays its own clip)
				_play_flinch()
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
## The self-test's mouse: a screen point that stands in for the real mouse in cursor_world and the hover pick, so both are projected
## through the camera exactly as a real mouse is. Negative means use the real mouse.
var test_mouse: Vector2 = Vector2(-1.0, -1.0)

func cursor_world() -> Vector3:
	if cursor_override != Vector3.INF:
		return cursor_override
	if Gamepad.active and test_mouse.x < 0.0:
		return _pad_cursor()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return global_position
	var mouse: Vector2 = get_viewport().get_mouse_position() if test_mouse.x < 0.0 else test_mouse
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
	if mouse_override.x < 0.0 and test_mouse.x >= 0.0:
		mouse_override = test_mouse
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
	if bow != null and not skills.busy: bow._release = maxf(bow._release - _delta, 0.0)
	if skills.fire_orb != null and is_instance_valid(skills.fire_orb):
		skills.fire_orb.global_position = skills.orb_home()
	if not is_controlled():
		if _ring != null: _ring.hide()
		return
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

## DS2 outlines the creature under the pointer as well as the controller target;
## keep that silhouette cue for both input methods (the ground ring is secondary).
func _update_focus_glow(focus: Variant) -> void:
	var want: Actor = focus as Actor if (is_instance_valid(focus) and not (focus as Actor).dead and skills.aiming_id == "") else null
	if _glowing != null and _glowing != want and is_instance_valid(_glowing):
		_glowing.set_highlighted(false)
	_glowing = want
	if _glowing != null:
		_glowing.set_highlighted(true)

## Latch UI clicks before a button can close its popup before the next physics tick. Connected to the root window's `window_input`, not
## `_input`: an open dropdown (OptionButton, MenuButton) is an embedded sub-window that consumes the press and release that choose an entry or
## dismiss it, and polling `Input` for the click does not know that.
func _latch_ui_click(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.is_action("click"):
		return
	var click := event as InputEventMouseButton
	if click.pressed and not click.is_echo():
		_ui_click = _point_over_ui(click.position, true) or _popup_is_open()
	elif not click.pressed:
		_ui_click = false

## Whether any popup (a dropdown list, a menu) is showing: the press that picks from it or dismisses it is the interface's, wherever it lands.
func _popup_is_open() -> bool:
	for node in get_tree().root.find_children("*", "Popup", true, false):
		if (node as Popup).visible:
			return true
	return false

func _point_over_ui(mouse: Vector2, check_hovered_control: bool = false) -> bool:
	# Polling Input actions does not respect Control.accept_event(). The active GUI control
	# (including popups) must keep world commands out.
	if check_hovered_control and get_viewport().gui_get_hovered_control() != null:
		return true
	for node in get_tree().get_nodes_in_group("hud"):
		if node.has_method("covers") and node.covers(mouse):
			return true
	return false

## The mouse is over an interactive control or a custom-drawn HUD panel.
func mouse_over_ui(at: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	if Gamepad.active:
		return false
	if at.x < 0.0:
		return _point_over_ui(get_viewport().get_mouse_position(), true)
	return _point_over_ui(at)

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
		_ui_click = _ui_click or mouse_over_ui()
	if not Input.is_action_pressed("click"):
		_ui_click = false
	if Input.is_action_just_pressed("click") and not _ui_click:
		if skills.take_aim_targeting:
			var hit_enemy: Enemy = (hover_target as Enemy) if (hover_target is Enemy and not hover_target.dead) else (_hover_pick(cursor) as Enemy)
			if hit_enemy == null:
				hit_enemy = enemy_near(cursor, 3.5) as Enemy
			if hit_enemy != null and not hit_enemy.dead:
				skills.confirm_take_aim(hit_enemy)
			return
		var hover: Actor = _hover_pick(cursor)
		var loot: LootDrop = LootDrop.focused if is_instance_valid(LootDrop.focused) else null
		var chest: Chest = Chest.near(get_tree(), cursor, 0.35) if loot == null else null
		skills.clear_queue()
		pickup_target = null
		chest_target = null
		if loot != null and not ctrl:   # an item, or its name, under the pointer: go and take it
			click_mode = 4
			pickup_target = loot
			attack_target = null
			attack_prop = null
			movement.goal = Nav.snap(self, loot.global_position)
			movement.has_goal = true
		elif chest != null and not ctrl and hover == null:   # a closed chest under the pointer: go and open it
			click_mode = 4
			chest_target = chest
			attack_target = null
			attack_prop = null
			movement.goal = Nav.snap(self, chest.global_position)
			movement.has_goal = true
		elif ctrl:
			click_mode = 2
		elif hover:
			click_mode = 1
			attack_target = hover
			attack_prop = null
			movement.has_goal = false
			if (skills.brutal_armed or powers.staggering_armed) and skills.busy and skills.busy_skill == "basic":
				skills.cancel_action()
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
				if not is_instance_valid(attack_target) or attack_target.dead:
					attack_target = _nearest_attacker() if _attack_engaged else null
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
		var slot_id: String = skills.hotbar[i]
		if slot_id == "" or slot_id == "brutal_attack" or slot_id == "take_aim" or PowerController.LIVE.has(slot_id):
			continue   # (powers go off from SkillController.handle_hotkeys)
		if SkillDb.all()[skills.hotbar[i]].get("aimed", false):
			skills.handle_aimed_key(action, skills.hotbar[i], cursor)
		elif Input.is_action_just_pressed(action) or Input.is_action_pressed(action):
			skills.queue_skill(skills.hotbar[i], cursor)
	# The right mouse button carries whichever skill is on it (the attack by default), and drives it the way a numbered slot would.
	var alt_id: String = skills.right_click_skill
	var alt_def: Dictionary = SkillDb.all()[alt_id]
	if bool(alt_def.get("aimed", false)):
		skills.handle_aimed_key("alt_skill", alt_id, cursor)
	elif alt_id == "brutal_attack":
		if Input.is_action_just_pressed("alt_skill") and not skills.swallow_alt:
			skills.activate_brutal_attack()
	elif alt_id == "take_aim":
		if Input.is_action_just_pressed("alt_skill") and not skills.swallow_alt:
			skills.activate_take_aim()
	elif PowerController.LIVE.has(alt_id):
		if Input.is_action_just_pressed("alt_skill") and not skills.swallow_alt:
			powers.activate(alt_id, cursor)
	elif Input.is_action_pressed("alt_skill") and not skills.swallow_alt:
		if Input.is_action_just_pressed("alt_skill") and alt_id != "basic":
			skills.interrupt_for(alt_id, cursor)   # a skill on the right button cancels the swing in progress, like a numbered key
		skills.queue_skill(alt_id, cursor)
	if not Input.is_action_pressed("alt_skill"):
		skills.swallow_alt = false

## Walks to the item the hero was sent for and takes it as soon as it is in reach; the use key takes the nearest one in reach too, which
## is how a controller (or the keyboard) picks things up.
func _pursue_pickup(stand_still: bool) -> void:
	if dead:
		return
	if chest_target != null:
		if not is_instance_valid(chest_target) or chest_target.opened:
			chest_target = null
			click_mode = 0
		elif chest_target.in_reach(self):
			chest_target.open()
			chest_target = null
			click_mode = 0
			movement.has_goal = false
		elif not stand_still:
			movement.goal = Nav.snap(self, chest_target.global_position)
			movement.has_goal = true
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
		else:   # nothing on the ground in reach: the nearest closed chest
			var chest: Chest = Chest.near(get_tree(), global_position, Chest.REACH)
			if chest != null and chest.in_reach(self):
				chest.open()
	if Input.is_action_just_pressed("companion_attack"):
		# A nest under the cursor wins over an enemy overlapping its target area (owner decision); elsewhere enemies come first.
		var hover_nest: Destructible = Destructible.near(get_tree(), cursor_world(), 0.35, Destructible.HERO)
		if hover_nest != null and hover_nest.prop_name != "nest":
			hover_nest = null
		var hover_enemy: Enemy = (hover_target as Enemy) if (hover_target is Enemy and not hover_target.dead) else (_hover_pick(cursor_world()) as Enemy)
		if hover_nest != null and not skills.take_aim_targeting:
			order_companions_to_prop(cursor_world())
		elif hover_enemy != null and not hover_enemy.dead:
			if skills.take_aim_targeting:
				skills.confirm_take_aim(hover_enemy)
			else:
				for body in PartyManager.current().living():
					if body != self: body.attack_target = hover_enemy
		elif hover_enemy == null and not skills.take_aim_targeting:
			order_companions_to_prop(cursor_world())

## The companion-attack order for a breakable prop (a nest or barrel) at the cursor: the other members shoot or swing at it.
## Returns the prop ordered, or null when nothing breakable is there.
func order_companions_to_prop(cursor: Vector3) -> Destructible:
	var hover_prop: Destructible = Destructible.near(get_tree(), cursor, 0.35, Destructible.HERO)
	if hover_prop != null:
		var shooter: String = ""
		for body in PartyManager.current().living():
			if body == self: continue
			body.attack_prop = hover_prop
			if body.bow != null and body.stats.is_ranged(): shooter = body.display_name
		# Only an archer in the party carries a prop order out (see PartyCharacterAI), so only an archer is named.
		if shooter != "": say_banner("%s: ordered onto the %s" % [shooter, hover_prop.prop_name.replace("_", " ")])
	return hover_prop

## A short word to the player: the town's message log while the town or road is up, else the arena HUD banner; quiet with no HUD.
func say_banner(text: String) -> void:
	var hud_node: Node = get_tree().get_first_node_in_group("town_hud")
	if hud_node == null:
		hud_node = get_tree().get_first_node_in_group("hud")
	if hud_node != null and hud_node.has_method("show_banner"):
		hud_node.call("show_banner", text, 2.5)

## Monsters still asleep and far from the hero are switched off (not drawn, not run, not animated) until he comes back; see Enemy.SLEEP_RANGE.
func _manage_dormancy() -> void:
	if not is_controlled(): return
	var here: Vector2 = Vector2(global_position.x, global_position.z)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead or e.is_aggro():
			continue
		var d: float = here.distance_to(Vector2(e.global_position.x, e.global_position.z))
		e.set_dormant(d > (Enemy.WAKE_RANGE if e.dormant else Enemy.SLEEP_RANGE))

func _enter_tree() -> void:
	TownState.events.member_xp_changed.connect(_member_xp_changed)
	TownState.events.member_leveled.connect(_member_leveled)
	TownState.events.member_passives_changed.connect(_member_passives_changed)

func _member_xp_changed(id: String, old_xp: int, new_xp: int) -> void:
	if id == member_id: _on_xp_changed(old_xp, new_xp)

func _member_leveled(id: String, old_level: int, new_level: int, xp: int) -> void:
	if id == member_id: _on_leveled(old_level, new_level, xp)

func _member_passives_changed(id: String) -> void:
	if id == member_id: stats.refresh()

func _on_xp_changed(_old_xp: int, _new_xp: int) -> void:
	stats.refresh()

## DS2's level-up: full life and mana, and every power and skill ready again (Brutal Attack, Earthshatter, Cutter's Take Aim, cooldowns).
func _on_leveled(_old_level: int, _new_level: int, _new_xp: int) -> void:
	stats.refresh()
	if dead:
		return
	health = max_health
	stats.mana = stats.max_mana
	stats.cooldowns.clear()
	stats.brutal_reload_remaining = 0.0
	powers.reset()
	if bow != null: bow.reload_remaining = 0.0

func _exit_tree() -> void:
	if get_tree() != null and get_tree().root.window_input.is_connected(_latch_ui_click):
		get_tree().root.window_input.disconnect(_latch_ui_click)
	Nav.reset(self, movement._nav_state)
	capture_state()
	if PartyManager.current().bodies.get(member_id) == self:
		PartyManager.current().bodies.erase(member_id)
	TownState.events.member_xp_changed.disconnect(_member_xp_changed)
	TownState.events.member_leveled.disconnect(_member_leveled)
	TownState.events.member_passives_changed.disconnect(_member_passives_changed)
	if TownState.events.hero_xp_changed.is_connected(_on_xp_changed):
		TownState.events.hero_xp_changed.disconnect(_on_xp_changed)
	if TownState.events.hero_leveled.is_connected(_on_leveled):
		TownState.events.hero_leveled.disconnect(_on_leveled)
	if TownState.events.passives_changed.is_connected(stats.refresh):
		TownState.events.passives_changed.disconnect(stats.refresh)

func _on_death() -> void:
	hit_reaction.clear()
	knockdown.die()   # dying supersedes the fall (no get-up, no Iron Recovery) and the death clip carries on from his pose
	skills.reset()
	if bow != null:
		bow.cancel()
		bow.disarm()
	if is_controlled(): PartyManager.current().cycle()

## Back on his feet at `pos` (the world has no run to end when the hero falls: he is dragged home): whole, standing, the death
## animation put away, and a moment of grace before anything can hurt him.
func revive_at(pos: Vector3) -> void:
	if not dead:
		return
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
	knockdown.cancel()
	hit_reaction.clear()
	stun_time = 0.0
	hitpause = 0.0
	invulnerable_time = 2.5
	velocity = Vector3.ZERO
	attack_target = null
	attack_prop = null
	skills.reset()
	movement.has_goal = false
	global_position = pos
	Nav.reset(self, movement._nav_state)
	reset_physics_interpolation()
	model.current = ""   # the death clip is over: the next loop() must really start the idle
	model.loop("idle_alert")

## Consume an explicit ground order while an action or movement lock would otherwise hide input.
## UI, actors, loot, props and Ctrl clicks keep their existing semantics.
func _read_interrupt_move_click(cursor: Vector3) -> bool:
	if Input.is_action_just_pressed("click"):
		_ui_click = _ui_click or mouse_over_ui()
	elif not Input.is_action_pressed("click"):
		_ui_click = false
	if not Input.is_action_just_pressed("click") or _ui_click or Input.is_action_pressed("stand_still") \
			or skills.take_aim_targeting or skills.aiming_id != "":
		return false
	if _hover_pick(cursor) != null:
		return false
	var loot: LootDrop = LootDrop.focused if is_instance_valid(LootDrop.focused) else null
	if loot != null and not loot.is_queued_for_deletion():
		return false
	if Destructible.near(get_tree(), cursor, 0.35, Destructible.HERO) != null or Chest.near(get_tree(), cursor, 0.35) != null:
		return false
	click_mode = 0
	pickup_target = null
	chest_target = null
	attack_prop = null
	attack_target = null
	skills.clear_queue()
	movement.goal = Nav.snap(self, cursor)
	movement.has_goal = true
	Fx.click_marker(self, cursor)
	if skills.busy and skills.swing_cancellable_by_move():
		skills.cancel_action()
	return true

# --- Acting ------------------------------------------------------------------

func _act(delta: float, cursor: Vector3) -> void:
	if _attack_engaged and (not is_instance_valid(attack_target) or attack_target.dead):
		attack_target = _nearest_attacker()
		movement.has_goal = false
	var ctrl: bool = Input.is_action_pressed("stand_still")
	if attack_prop != null:
		if not is_instance_valid(attack_prop) or attack_prop.broken:
			attack_prop = null
		elif attack_target == null and skills.queued_skill == "":
			if stats.is_ranged() and bow != null:
				# An archer shoots the prop from a firing position, rather than walking up to it to swing.
				bow.engage(null, attack_prop, delta, ctrl)
				return
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

	# An archer's manual attack on an enemy takes the same firing-position decision as the companion's (sight, range, separation).
	if skill_id == "basic" and target != null and stats.is_ranged() and bow != null:
		bow.engage(target, null, delta, ctrl)
		return
	if skill_id != "" and target != null:
		var skill: Dictionary = SkillDb.all()[skill_id]
		var dist: float = flat_distance_to(target) - target.body_radius
		if dist <= (17.0 if skill_id == "basic" and stats.is_ranged() else float(skill["range"])) and Nav.line_clear(self, target.global_position):
			if (skills.brutal_armed or powers.staggering_armed) and skills.busy and skills.busy_skill == "basic":
				skills.cancel_action()
			if stats.can_use(skill_id):
				skills.start_skill(skill_id, target)
				return
			if stats.mana < stats.mana_cost(skill_id):
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

## Continue an explicit engagement only against enemies attacking this member.
## Target identity belongs to the body, never whichever member is selected globally.
func _nearest_attacker() -> Enemy:
	var nearest: Enemy = null
	var nearest_distance: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.dead or not enemy.is_aggro() or enemy.target != self:
			continue
		var distance: float = flat_distance_to(enemy)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest

func on_dealt_hit(target: Actor, result: Dictionary) -> void:
	var outcome: int = result.get("outcome", 0)
	if outcome == Combat.Outcome.CRITICAL or float(result.get("weight", 1.0)) >= HEAVY_BLOW_WEIGHT:
		Gamepad.rumble(0.15, 0.55, 0.14)
	if not result.get("secondary", false):
		skills.blade_blood = minf(skills.blade_blood + 0.05, 1.0)
	on_party_damage(float(result.get("damage", 0.0)), String(result.get("skill_id", "")))
	_steal_resources(result)
	_passive_on_hit(target, result)

## All party damage feeds every power except the power that produced it.
func on_party_damage(damage: float, skill_id: String = "") -> void:
	for body in PartyManager.current().living():
		if body != self or skill_id != "brutal_attack": body.stats.gain_brutal_charge(damage)
		body.powers.gain(damage, skill_id if body == self else "")
		if body.bow != null and (body != self or skill_id != "take_aim"):
			body.bow.reload_remaining = maxf(body.bow.reload_remaining - maxf(damage, 0.0), 0.0)

## DS2 rules.skrit 1730-1767: weapons and direct spells qualify; DoT/secondary events do not.
func _steal_resources(result: Dictionary) -> void:
	if dead or not Combat.restoration_eligible(result) or float(result.get("damage", 0.0)) <= 0.0 \
			or int(result.get("outcome", Combat.Outcome.HIT)) < Combat.Outcome.HIT:
		return
	var gain: float = stats.gear_stat("life_per_hit") + stats.gear_stat("life_steal") / 100.0 * float(result.get("damage", 0.0))
	if gain > 0.0:
		health = minf(health + gain, max_health)
	var mana_gain: float = stats.gear_stat("mana_per_hit") + stats.gear_stat("mana_steal") / 100.0 * float(result.get("damage", 0.0))
	if mana_gain > 0.0:
		stats.mana = minf(stats.mana + mana_gain, stats.max_mana)

## DS2's passives that ride a landed blow (docs/ds2-combat-and-loot.md 4): Smite stuns on a two-handed hit (5-50%, 1-2 s), Ignite sets a
## fire hit alight (DS2's rules.skrit: `increased_ignite_chance x damage / (1.2 + 0.6 INT)` against a 0-100 roll, the chance from its 5-30 table,
## 0.08-0.5 x INT a second for 3 s).
func _passive_on_hit(target: Actor, result: Dictionary) -> void:
	if target == null or target.dead or result.get("secondary", false):
		return
	var skill: String = String(result.get("skill_id", ""))
	var damage: float = float(result.get("damage", 0.0))
	var smite: int = TownState.effective_passive_rank("smite", member_id)
	if smite > 0 and skill in SWORD_SKILLS and PlayerStats._two_handed(stats.equipment.get(Items.Slot.WEAPON, {})) \
			and randf() < PassiveDb.get_def("smite").value(smite) / 100.0:
		target._gain_stun(PassiveDb.get_def("smite").extra_value("stun", smite))
	var ignite: int = TownState.effective_passive_rank("ignite", member_id)
	if ignite > 0 and int(result.get("type", 0)) == Combat.DamageType.FIRE \
			and randf() < PassiveDb.get_def("ignite").extra_value("chance", ignite) / 100.0 * damage / (1.2 + 0.6 * stats.intelligence):
		target.apply_burn(PassiveDb.get_def("ignite").value(ignite) * stats.intelligence, 3.0, true, self, skill)

## DS2 rules.skrit 1769-1818: melee/ranged weapon damage, no second armor roll or recursive effects.
func _on_received_hit(result: Dictionary) -> void:
	var source: Variant = result.get("source")
	var share: float = stats.gear_stat("reflect") / 100.0
	if share > 0.0 and is_instance_valid(source) and source is Actor and source != self and not source.dead \
			and Combat.weapon_hit_eligible(result) and float(result.get("damage", 0.0)) > 0.0:
		source.receive({"outcome": Combat.Outcome.HIT, "damage": float(result["damage"]) * share, "weight": 0.3,
			"source": self, "origin": combat_identity(), "type": Combat.DamageType.PHYSICAL,
			"calm": true, "secondary": true, "skill_id": "reflect"}, global_position)

func on_enemy_killed(enemy: Actor) -> void:
	pass # Loot belongs to the dead enemy's tier, not the active member's missing health.

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
	var share: float = float(result.get("damage", 0.0)) / maxf(max_health, 1.0)
	Gamepad.rumble(0.3 + share * 2.0, 0.4 + share * 3.0, 0.18 + share)
	combat_timer = 5.0
	hurt_flash = 1.0
	Fx.shake(self, 0.08)

func _on_avoided(outcome: int) -> void:
	combat_timer = 5.0
	if outcome == Combat.Outcome.BLOCK:
		_on_blocked()
	# DS2's Rebuke: a block hits back for 0.4-2.5 x Melee level and stuns for 1-2 s.
	var rebuke: int = TownState.effective_passive_rank("rebuke", member_id)
	if rebuke > 0 and outcome == Combat.Outcome.BLOCK and last_hit_by is Enemy and not last_hit_by.dead:
		var melee: int = int(HeroAttributes.levels_from_xp(character.class_xp).get("melee", 0))
		last_hit_by.receive({"outcome": Combat.Outcome.HIT, "damage": maxf(PassiveDb.get_def("rebuke").value(rebuke) * melee, 1.0), "weight": 1.0,
			"source": self, "type": Combat.DamageType.PHYSICAL, "secondary": true, "skill_id": "rebuke"}, global_position)
		last_hit_by._gain_stun(PassiveDb.get_def("rebuke").extra_value("stun", rebuke))

## A blow caught on the shield: the guard clip (only when the swing in progress is not using the body), the shield's ring, and the Shield
## Openings roll on the attacker. Blocks are not stunned, so the hero keeps his footing.
func _on_blocked() -> void:
	if not dead and not knockdown.active() and not skills.busy and model != null and model.anim != null and model.anim.has_animation("game/block"):
		model.once("block", 0.0, 1.0, 0.04)
	Sfx.sample(self, "sword_hit", -6.0, 1.45)   # the shield's ring: the blade's recording, higher and quieter (a dedicated shield recording is pending)
	openings.on_block(last_hit_by)

func _popup_tint() -> Color:
	return Color(1.0, 0.35, 0.3)
