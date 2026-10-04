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
const CLIPS: Array[String] = ["idle_alert", "walk", "run", "charge", "throw", "charge_run", "kick", "slash", "slash_l", "slash_r", "thrust", "combo_end", "power", "cleave", "cast", "roll", "hit", "death", "leap", "stomp", "yank", "jump"]

## `time` is the gameplay duration. The clip window (start/strike/end, in clip seconds, measured with
## tools/anim_timing.gd) is stretched to fit it, and the damage frame is derived from the strike time.
const SKILLS := {
	"basic": {"name": "Attack", "mana": 0.0, "time": 0.85, "range": 2.4, "mult": 1.0, "cd": 0.0, "kind": "melee",
		"clip": "slash", "start": 0.5, "strike": 1.07, "end": 1.45, "weight": 1.0, "lunge": 0.5},
	"power": {"name": "Power Strike", "mana": 8.0, "time": 1.3, "range": 2.4, "mult": 2.3, "cd": 2.0, "kind": "melee",
		"clip": "power", "start": 0.55, "strike": 1.23, "end": 1.75, "weight": 1.9, "lunge": 1.0},
	"cleave": {"name": "Cleave", "mana": 12.0, "time": 1.35, "range": 3.0, "mult": 1.1, "cd": 3.5, "kind": "cleave",
		"clip": "cleave", "start": 1.0, "strike": 1.73, "end": 3.0, "weight": 1.3, "lunge": 0.3},
	# Fireball is a two-phase cast: gather (arms rise, orb swells overhead), then throw. Times are at 1.0x speed:
	# `gather` seconds of gathering (charge clip start -> strike), then the throw clip plays and the fireball
	# leaves the hand `release_after` seconds into it.
	"fireball": {"name": "Fireball", "mana": 16.0, "time": 1.4, "range": 14.0, "mult": 1.0, "cd": 3.0, "kind": "projectile", "aimed": true,
		"charged": true, "clip": "charge", "start": 0.8, "strike": 2.05, "end": 2.3, "gather": 0.72,
		"release_clip": "throw", "release_start": 0.55, "release_speed": 1.5, "release_after": 0.3,
		"weight": 1.6, "lunge": 0.4},	# Skewer: charge, run up to three enemies onto the blade, skid to a halt, then kick them all off. `range` is the
	# longest charge in metres; `mult` scales the impale and the kick.
	"skewer": {"name": "Skewer", "mana": 18.0, "time": 1.8, "range": 9.0, "mult": 1.5, "cd": 9.0, "kind": "charge", "directional": true,
		"skewer": true, "weight": 2.2, "lunge": 0.0, "clip": "charge_run", "start": 0.0, "strike": 0.3, "end": 0.5},
	# Leap: spring up to `range` m at the cursor. On a downed enemy it is a slam (`LEAP_SLAM_MULT`, always crits);
	# otherwise a lighter overhead chop around the landing spot.
	"leap": {"name": "Leap", "mana": 12.0, "time": 1.8, "range": 10.0, "mult": 1.3, "cd": 7.0, "kind": "leap", "directional": true,
		"leap": true, "weight": 2.0, "lunge": 0.0, "clip": "leap", "start": 1.4, "strike": 2.5, "end": 3.9},
	"potion": {"name": "Potion", "mana": 0.0, "time": 0.0, "range": 0.0, "mult": 0.0, "cd": 1.0, "kind": "potion"},
	"dodge": {"name": "Dodge", "mana": 0.0, "time": 0.55, "range": 0.0, "mult": 0.0, "cd": 0.7, "kind": "dodge"},
}

## Tooltip text for the hotbar. Keep these in step with what the skills actually do.
const SKILL_DESCRIPTIONS := {
	"basic": "A three-hit sword combo. The first two hits vary between slashes and thrusts; the third is a heavy finisher. Pause for a moment and the combo resets.",
	"power": "Heave the blade overhead for a crushing blow. Hits much harder than a normal swing, and heavily staggers and knocks back what it hits.",
	"cleave": "Whirl your blade around you, striking every enemy within reach.",
	"fireball": "Hold the key to aim a ground target, release to cast. The fireball flies to that exact point and explodes, burning everything inside the highlighted sphere. Fire damage ignores armor and cannot miss.",
	"potion": "Drink a health potion to restore 60 health. Does nothing at full health.",
	"skewer": "Lower the blade and charge toward the cursor. The first enemy in your path is run through to the hilt and carried along; up to two more are skewered on the same blade. Then you plant yourself and drive a boot into the pile, kicking all of them off the sword and far away from you. Enemies in the way that do not fit on the blade are shoved aside. Bosses cannot be impaled and stop the charge.",
	"leap": "Spring through the air to the cursor. Land on a knocked-down enemy and drive the sword straight down through it into the earth for a guaranteed critical blow, then plant a boot on it, pinning it and stunning it while you wrench the blade free. Land anywhere else and the same plunging chop hits everything around the landing spot for lighter damage. You sail over enemies in the way.",
	"dodge": "Roll in the direction you are moving (or toward the cursor). You take no damage for the whole roll, and every non-boss enemy near you is shoved aside and has its current attack interrupted.",
}
## Gear effects that change a skill, shown in its tooltip while equipped: skill id -> affix ids.
const SKILL_AFFIXES := {
	"basic": ["cleaving", "momentum", "chain", "searing", "executioner", "frostbite", "riposte"],
	"power": ["gravewarden", "executioner", "frostbite", "searing", "chain"],
	"cleave": ["whirlpool", "executioner", "frostbite", "searing", "chain"],
	"fireball": ["twin_flame"],
	"dodge": ["shock_roll", "riposte"],
	"skewer": ["frostbite", "searing"],
}

## True when worn gear changes how this skill behaves (shown as a gold pip on its hotbar slot).
func skill_has_modifier(id: String) -> bool:
	for affix in SKILL_AFFIXES.get(id, []):
		if has_affix(affix):
			return true
	return false

## One-line damage summary for tooltips.
func skill_damage_text(id: String) -> String:
	var skill: Dictionary = SKILLS[id]
	match String(skill["kind"]):
		"melee", "cleave":
			var factor: float = (1.0 + strength * 0.02) * weapon_stat("damage", 1.0) * float(skill["mult"])
			if id == "basic":
				return "Damage %d-%d per hit" % [int(weapon_min * factor), int(weapon_max * factor)]
			return "Damage %d-%d" % [int(weapon_min * factor), int(weapon_max * factor)]
		"projectile":
			return "Fire damage ~%d" % int(14.0 + strength * 0.4)
		"charge":
			var base: float = (1.0 + strength * 0.02) * weapon_stat("damage", 1.0)
			return "Impale %d-%d, then %d-%d per kick" % [int(weapon_min * base * 1.5), int(weapon_max * base * 1.5),
				int(weapon_min * base * 1.8), int(weapon_max * base * 1.8)]
		"leap":
			var factor: float = (1.0 + strength * 0.02) * weapon_stat("damage", 1.0)
			return "Chop %d-%d, slam %d-%d (crit)" % [int(weapon_min * factor * LEAP_CHOP_MULT), int(weapon_max * factor * LEAP_CHOP_MULT),
				int(weapon_min * factor * LEAP_SLAM_MULT), int(weapon_max * factor * LEAP_SLAM_MULT)]
		"potion":
			return "Heals 60"
	return ""

## The basic attack is a 3-step combo; each step picks one of these variants at random.
## Strike timings come from tools/anim_timing.gd; `lunge` is the most distance (m) the swing may close.
const BASIC_COMBO: Array = [
	[
		{"clip": "slash_r", "start": 0.35, "strike": 0.73, "end": 1.1, "time": 0.78, "weight": 1.0, "lunge": 0.4},
		{"clip": "thrust", "start": 1.0, "strike": 1.57, "end": 2.1, "time": 0.9, "weight": 0.9, "lunge": 0.7, "range": 2.8},
	],
	[
		{"clip": "slash_l", "start": 0.7, "strike": 1.37, "end": 1.85, "time": 0.85, "weight": 1.0, "lunge": 0.4},
		{"clip": "slash", "start": 0.5, "strike": 1.07, "end": 1.45, "time": 0.85, "weight": 1.0, "lunge": 0.5},
	],
	[
		{"clip": "combo_end", "start": 0.6, "strike": 1.37, "end": 2.2, "time": 1.3, "weight": 1.7, "lunge": 0.9, "mult": 1.35, "finisher": true},
	],
]
const COMBO_WINDOW := 0.9
const ROLL_TIME := 0.55
const ROLL_SPEED := 10.0
const ROLL_STAMINA := 20.0
# The roll clip crouches for ~0.9 s before it tumbles (see tools/roll_profile.gd). Play only the dive and
# tumble so the visible roll starts the instant the body starts moving.
const ROLL_CLIP_START := 0.78
const ROLL_CLIP_END := 1.68

var hotbar: Array[String] = ["power", "cleave", "fireball", "potion", "skewer", "leap"]
var right_click_skill: String = "basic"

var max_mana: float = 80.0
var mana: float = 80.0
var max_stamina: float = 100.0
var stamina: float = 100.0
const MAX_POTIONS := 6
var potions: int = 3
var _glow_light: OmniLight3D
var _haste_fx: CPUParticles3D
var _riposte_light: OmniLight3D
var run_speed: float = 5.0
var strength: float = 15.0
var weapon_min: float = 6.0
var weapon_max: float = 11.0
var cooldowns: Dictionary = {}
var combat_timer: float = 0.0
var message: String = ""
var message_time: float = 0.0
var hurt_flash: float = 0.0

var goal: Vector3 = Vector3.ZERO
var has_goal: bool = false
var attack_target: Actor
var hover_target: Actor  # enemy under the mouse cursor, for the health bar and highlight ring
var _ring: MeshInstance3D
var _cursor_on_enemy: bool = false
var click_mode: int = 0  # 0 move, 1 attack locked target, 2 stand-still attack
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

# Equipment (see items.gd / item_effects.gd)
var equipment: Dictionary = {}  # Items.Slot -> item Dictionary
var base_armor: float = 15.0
var haste_time: float = 0.0
var riposte_time: float = 0.0
var ward_timer: float = 0.0
var aegis_hits: int = 0
var busy_time: float = 0.8

# Aimed skills (Fireball): hold the key to aim, release to cast. The preview shows the blast sphere.
# Skewer state
var skewer_phase: int = 0  # 0 off, 1 wind-up, 2 charge, 3 skid, 4 kick, 5 recover
var skewer_t: float = 0.0
var skewer_dir: Vector3 = Vector3.FORWARD
var skewer_travel: float = 0.0
var skewer_full_at: float = -1.0
var skewer_kicked: bool = false
var skewer_impaled: Array[Actor] = []
var _skewer_tick_clock: float = 0.0
var _skewer_dust: float = 0.0
var _big_hit: Dictionary = {}   # enemies already staggered by this charge
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

var _nav_state: Dictionary = {}  # cached path for click-to-move (see Nav)
var _shoved: Dictionary = {}  # enemies already staggered by the current roll
var rolling: bool = false
var roll_t: float = 0.0
var roll_dir: Vector3 = Vector3.FORWARD

var _was_stunned: bool = false
var _trail: WeaponTrail
var _swing_sound_played: bool = false

func _ready() -> void:
	add_to_group("player")
	display_name = "Knight"
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	max_health = 120.0
	health = max_health
	attack_rating = 40.0
	defense = 30.0
	armor = base_armor
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
		equip(item, false)

func _physics_process(delta: float) -> void:
	if _actor_tick(delta):
		move_with(Vector3.ZERO)
		return
	if dead:
		return
	hurt_flash = maxf(hurt_flash - delta * 2.5, 0.0)
	_update_blade_blood(delta)
	_update_buff_visuals()
	if model != null and model.weapon != null:
		model.weapon.visible = not (busy and bool(busy_def.get("charged", false)))
	if not busy and visual != null and absf(visual.rotation.x) > 0.001:
		visual.rotation.x = lerpf(visual.rotation.x, 0.0, 1.0 - exp(-14.0 * delta))
	message_time = maxf(message_time - delta, 0.0)
	combat_timer = maxf(combat_timer - delta, 0.0)
	for id in cooldowns.keys():
		cooldowns[id] = maxf(float(cooldowns[id]) - delta, 0.0)
	_regen(delta)
	haste_time = maxf(haste_time - delta, 0.0)
	riposte_time = maxf(riposte_time - delta, 0.0)
	ward_timer = maxf(ward_timer - delta, 0.0)
	_collect_orbs()
	combo_timer = maxf(combo_timer - delta, 0.0)
	if combo_timer <= 0.0 and not busy:
		combo_step = 0

	var cursor: Vector3 = cursor_world()
	hover_target = _hover_pick(cursor)
	if aiming_id != "" and (rolling or stun_time > 0.0):
		_clear_aim()
	_update_aim(cursor)
	_handle_hotkeys(cursor)
	if rolling:
		_tick_roll(delta)
		return
	if Input.is_action_just_pressed("dodge") and stun_time <= 0.0:
		_try_roll(cursor)
		if rolling:
			return
	if busy:
		_tick_busy(delta)
		move_with(Vector3.ZERO)
		return
	if stun_time > 0.0:
		if not _was_stunned:
			_was_stunned = true
			model.once("hit", 0.0, 1.4)
		move_with(Vector3.ZERO)
		return
	_was_stunned = false
	_read_input(cursor)
	_act(delta, cursor)
	_update_locomotion_anim()

func _update_locomotion_anim() -> void:
	var moving_speed: float = (velocity - knock).length()
	# Only walk or run on purpose: being shoved by the crowd or a hit must not start the legs moving.
	if moving_speed > 0.5 and has_goal and not busy:
		if moving_speed > run_speed * 0.8:
			model.loop("run", 1.0)
		else:
			model.loop("walk", 1.0)
	elif not busy:
		model.loop("idle_alert")

# --- Input -------------------------------------------------------------------

func cursor_world() -> Vector3:
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

## Enemy under the mouse, picked in screen space: pointing at a head or chest counts, not just the feet.
func _hover_pick(cursor: Vector3, mouse_override: Vector2 = Vector2(-1.0, -1.0)) -> Actor:
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
		var feet: Vector2 = camera.unproject_position(origin)
		var head: Vector2 = camera.unproject_position(origin + Vector3(0, e.body_height, 0))
		var pixels_per_metre: float = maxf(feet.distance_to(head) / e.body_height, 1.0)
		var reach: float = e.body_radius * pixels_per_metre + 4.0
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
	if _fire_orb != null and is_instance_valid(_fire_orb):
		_fire_orb.global_position = _orb_home()
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
		var hover: Actor = _hover_pick(cursor)
		queued_skill = ""
		if ctrl:
			click_mode = 2
		elif hover:
			click_mode = 1
			attack_target = hover
			has_goal = false
		else:
			click_mode = 0
			attack_target = null
			Fx.click_marker(self, cursor)
			# Clicking the ground means "go there": drop a swing in progress instead of finishing it.
			if busy and not rolling and _swing_cancellable_by_move():
				_cancel_action()
	if Input.is_action_pressed("click"):
		match click_mode:
			0:
				goal = Nav.snap(self, cursor)  # clicking inside a pillar goes to the nearest reachable spot
				has_goal = true
			1:
				if attack_target == null or attack_target.dead:
					attack_target = enemy_near(cursor, 3.0)
					if attack_target == null:
						click_mode = 0
			2:
				attack_target = enemy_near(cursor, 10.0)

	for i in hotbar.size():
		var action: String = "skill_%d" % (i + 1)
		if SKILLS[hotbar[i]].get("directional", false):
			if Input.is_action_just_pressed(action):
				_try_directional(hotbar[i], cursor)
		elif SKILLS[hotbar[i]].get("aimed", false):
			_handle_aimed_key(action, hotbar[i], cursor)
		elif Input.is_action_just_pressed(action) or Input.is_action_pressed(action):
			if hotbar[i] != "potion":  # potions are handled every frame in _handle_hotkeys, even mid-animation
				_queue_skill(hotbar[i], cursor)
	if SKILLS[right_click_skill].get("aimed", false):
		_handle_aimed_key("alt_skill", right_click_skill, cursor)
	elif Input.is_action_pressed("alt_skill"):
		_queue_skill(right_click_skill, cursor)

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
	if dead:
		return
	for i in hotbar.size():
		var action: String = "skill_%d" % (i + 1)
		if not Input.is_action_just_pressed(action):
			continue
		var id: String = hotbar[i]
		if id == "potion":
			if _use_potion() and busy and not rolling:
				_cancel_action()
		elif busy and not rolling and stun_time <= 0.0:
			if not _can_use(id):
				if mana < float(SKILLS[id]["mana"]):
					_say("Not enough mana")
				else:
					_say("%s is on cooldown" % SKILLS[id]["name"])
			elif _hotkey_would_start(id, cursor):
				_cancel_action()

## Whether pressing this skill's key right now would actually start it (targeted skills need an enemy near the cursor).
func _hotkey_would_start(id: String, cursor: Vector3) -> bool:
	var skill: Dictionary = SKILLS[id]
	if skill.get("directional", false) or skill.get("aimed", false):
		return true
	return enemy_near(cursor, 12.0) != null

## Aborts the current swing, cast or charge immediately.
func _cancel_action() -> void:
	if not busy:
		return
	if bool(busy_def.get("skewer", false)):
		_end_skewer()  # releases anyone on the blade and restores collision
	if bool(busy_def.get("leap", false)):
		_end_leap()
	if bool(busy_def.get("charged", false)):
		_drop_orb()
	busy = false
	busy_hit_done = true
	queued_skill = ""
	if _trail != null:
		_trail.active = false
	if visual != null:
		visual.rotation.x = 0.0
	model.loop("idle_alert")

## Skills that launch in a direction (Skewer) trigger on press, toward the cursor.
func _try_directional(id: String, cursor: Vector3) -> void:
	if not _can_use(id):
		if mana < float(SKILLS[id]["mana"]):
			_say("Not enough mana")
		return
	if bool(SKILLS[id].get("leap", false)):
		_start_leap(cursor)
	else:
		_start_skewer(cursor)

## Holding the key aims; letting go casts at the point under the cursor.
func _handle_aimed_key(action: String, id: String, cursor: Vector3) -> void:
	if Input.is_action_pressed(action):
		aiming_id = id
		aiming_action = action
		has_goal = false
	elif aiming_id == id and aiming_action == action:
		_release_aim(cursor)

func _release_aim(cursor: Vector3) -> void:
	var id: String = aiming_id
	var point: Vector3 = aim_point_for(id, cursor)
	if not _can_use(id):
		_clear_aim()
		if mana < float(SKILLS[id]["mana"]):
			_say("Not enough mana")
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
	var reach: float = float(SKILLS[id]["range"])
	var flat: Vector3 = cursor - global_position
	flat.y = 0.0
	if flat.length() > reach:
		flat = flat.normalized() * reach
	return global_position + flat

## Per-frame preview while aiming: sphere at the impact point, ring on the ground, a line from the hero,
## and every enemy inside the blast lit up.
func _update_aim(cursor: Vector3) -> void:
	if aiming_id == "":
		return
	aim_point = aim_point_for(aiming_id, cursor)
	if bool(SKILLS[aiming_id].get("charged", false)) and not busy:
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
	var from: Vector3 = global_position + Vector3(0, 1.1, 0)
	var length: float = from.distance_to(centre)
	_aim_line.visible = length > 0.2
	if _aim_line.visible:
		var up: Vector3 = (centre - from).normalized()
		var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
		(_aim_line.mesh as CylinderMesh).height = length
		_aim_line.global_transform = Transform3D(Basis(side.cross(up).normalized(), up, side), (from + centre) * 0.5)
	# Highlight everything the blast would hit.
	var now_hit: Array[Actor] = []
	for node in get_tree().get_nodes_in_group("enemies"):
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
		add_child(_fire_orb)
		_fire_orb.global_position = _orb_home()
		_fire_orb.grow_to(size, 0.3)

func _drop_orb() -> void:
	if _fire_orb != null and is_instance_valid(_fire_orb):
		_fire_orb.fade_out()
	_fire_orb = null

## Over the head, where the raised hands end up at the top of the gather.
func _orb_home() -> Vector3:
	return get_global_transform_interpolated().origin + Vector3(0, body_height + 0.8, 0)

func _on_death() -> void:
	_drop_orb()

func _ensure_aim_nodes() -> void:
	if _aim_root != null:
		return
	_aim_root = Node3D.new()
	_aim_root.top_level = true
	_aim_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_aim_root)
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
	add_child(_aim_line)

func _queue_skill(id: String, cursor: Vector3) -> void:
	var target: Actor = enemy_near(cursor, 12.0)
	if target == null:
		return
	queued_skill = id
	queued_target = target
	has_goal = false

# --- Acting ------------------------------------------------------------------

func _act(delta: float, cursor: Vector3) -> void:
	var ctrl: bool = Input.is_action_pressed("stand_still")
	var skill_id: String = ""
	var target: Actor = null
	if queued_skill != "" and queued_target != null and not queued_target.dead:
		skill_id = queued_skill
		target = queued_target
	elif attack_target != null and not attack_target.dead:
		skill_id = "basic"
		target = attack_target
	else:
		queued_skill = ""
		attack_target = null

	if skill_id != "" and target != null:
		var skill: Dictionary = SKILLS[skill_id]
		var dist: float = flat_distance_to(target) - target.body_radius
		if dist <= float(skill["range"]):
			if _can_use(skill_id):
				_start_skill(skill_id, target)
				return
			if mana < float(skill["mana"]):
				_say("Not enough mana")
			queued_skill = ""
			move_with(Vector3.ZERO)
			face(target.global_position, 0.4)
			return
		if ctrl:
			face(target.global_position, 0.4)
			move_with(Vector3.ZERO)
			return
		goal = target.global_position
		has_goal = true

	if ctrl:
		face(cursor, 0.4)
		move_with(Vector3.ZERO)
		return
	_move(delta)

func _move(delta: float) -> void:
	if not has_goal:
		move_with(Vector3.ZERO)
		return
	var to_goal: Vector3 = goal - global_position
	to_goal.y = 0.0
	if to_goal.length() < 0.2:
		has_goal = false
		move_with(Vector3.ZERO)
		return
	var speed: float = run_speed
	var in_combat: bool = combat_timer > 0.0
	if in_combat:
		if stamina <= 0.0:
			speed = run_speed * 0.6
		else:
			stamina = maxf(stamina - 16.0 * delta, 0.0)
	# Steer along the navmesh path so we walk around pillars, walls and ruins instead of grinding against them.
	var steer: Vector3 = Nav.next_point(self, goal, _nav_state, delta)
	var to_steer: Vector3 = steer - global_position
	to_steer.y = 0.0
	if to_steer.length() < 0.05:
		to_steer = to_goal
	face(global_position + to_steer, 0.35)
	move_with(to_steer.normalized() * speed)

func _can_use(id: String) -> bool:
	var skill: Dictionary = SKILLS[id]
	return float(cooldowns.get(id, 0.0)) <= 0.0 and mana >= float(skill["mana"])

func _use_potion() -> bool:
	if potions <= 0:
		_say("No potions left")
		return false
	if float(cooldowns.get("potion", 0.0)) > 0.0:
		_say("Potion not ready")
		return false
	if health >= max_health:
		_say("Already at full health")
		return false
	potions -= 1
	cooldowns["potion"] = float(SKILLS["potion"]["cd"])
	health = minf(health + 60.0, max_health)
	Sfx.play(self, "potion", -4.0)
	Fx.text_at(self, global_position + Vector3(0, 2.4, 0), "+60", Color(0.4, 1.0, 0.4), 56)
	return true

func _start_skill(id: String, target: Actor, aim: Variant = null) -> void:
	var skill: Dictionary = SKILLS[id]
	if id == "basic":
		skill = _next_basic()
	busy_def = skill
	busy_time = float(skill["time"]) / attack_speed()
	if String(skill["kind"]) == "cleave":
		ItemEffects.pull_for_cleave(self)
	mana -= float(skill["mana"])
	cooldowns[id] = float(skill["cd"])
	busy = true
	busy_skill = id
	busy_target = target
	busy_t = 0.0
	busy_hit_done = false
	busy_aim = aim if aim != null else target.global_position
	combat_timer = 5.0
	has_goal = false
	face(busy_aim)
	if id == queued_skill:
		queued_skill = ""
	# A click attacks once; the hero only keeps swinging while the attack button is held. Any other skill
	# replaces the attack order, so the hero never starts auto-attacking again once the skill ends.
	if id != "basic" or not (Input.is_action_pressed("click") or Input.is_action_pressed("alt_skill")):
		attack_target = null
	_swing_sound_played = false
	_release_started = false
	_style_trail(id)
	model.manual(skill["clip"])
	model.scrub(float(skill["start"]))
	if bool(skill.get("charged", false)):
		_ensure_orb(0.28)
		_fire_orb.grow_to(0.55, float(skill["gather"]) * busy_time / float(skill["time"]))
		Fx.ring(self, global_position, 1.8, Color(1.0, 0.55, 0.15))
		Fx.light_flash(self, global_position + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 2.0, 0.3)

## Blade ribbon colour and length per skill: plain steel for the combo, hot orange for Power Strike, icy white for Cleave.
func _style_trail(id: String) -> void:
	if _trail == null:
		return
	match id:
		"power":
			_trail.tint = Color(1.0, 0.62, 0.25)
			_trail.max_age = 0.34
			_trail.strength = 0.85
		"cleave":
			_trail.tint = Color(0.75, 0.92, 1.0)
			_trail.max_age = 0.4
			_trail.strength = 0.8
		_:
			_trail.tint = Color(1.0, 0.92, 0.75)
			_trail.max_age = WeaponTrail.DEFAULT_AGE
			_trail.strength = 0.4

## The blade glows as a heavy skill is wound up (a light on the tip that peaks at the strike, then fades).
func _blade_glow(u: float, hit_frac: float) -> void:
	if model == null or model.weapon_tip == null:
		return
	if _glow_light == null:
		_glow_light = OmniLight3D.new()
		_glow_light.omni_range = 4.0
		model.weapon_tip.add_child(_glow_light)
	_glow_light.light_color = Color(1.0, 0.6, 0.25) if busy_skill == "power" else Color(0.7, 0.9, 1.0)
	if u < hit_frac:
		_glow_light.light_energy = 3.5 * pow(u / hit_frac, 2.0)
	else:
		_glow_light.light_energy = 3.5 * clampf(1.0 - (u - hit_frac) / 0.3, 0.0, 1.0)

## Gear buffs you can see: a haste wake behind you, and a gold glow on the blade while a riposte is ready.
func _update_buff_visuals() -> void:
	if _glow_light != null and not (busy and (busy_skill == "power" or busy_skill == "cleave")):
		_glow_light.light_energy = 0.0
	if _haste_fx == null and haste_time > 0.0:
		_haste_fx = _make_haste_fx()
		add_child(_haste_fx)
	if _haste_fx != null:
		_haste_fx.emitting = haste_time > 0.0
	var riposte_on: bool = riposte_time > 0.0 and model != null and model.weapon_tip != null
	if riposte_on and _riposte_light == null:
		_riposte_light = OmniLight3D.new()
		_riposte_light.light_color = Color(1.0, 0.85, 0.35)
		_riposte_light.omni_range = 3.5
		_riposte_light.light_energy = 0.0
		model.weapon_tip.add_child(_riposte_light)
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
	var variants: Array = BASIC_COMBO[combo_step]
	var skill: Dictionary = SKILLS["basic"].duplicate()
	skill.merge(variants[randi() % variants.size()], true)
	combo_step = (combo_step + 1) % BASIC_COMBO.size()
	combo_timer = COMBO_WINDOW + float(skill["time"])
	return skill

func _tick_busy(delta: float) -> void:
	busy_t += delta
	var skill: Dictionary = busy_def
	if bool(skill.get("skewer", false)):
		_tick_skewer(delta)
		return
	if bool(skill.get("leap", false)):
		_tick_leap(delta)
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
				Sfx.play(self, "swing_heavy" if float(skill["weight"]) > 1.3 else "swing", -3.0)
			"projectile":
				Sfx.play(self, "fire_whoosh", -4.0)
	if not busy_hit_done and busy_t >= hit_at:
		busy_hit_done = true
		_apply_skill(skill)
		_lunge(float(skill["lunge"]))
		_strike_fx(skill)
	var u: float = busy_t / duration
	var hf: float = hit_fraction(skill)
	if busy_skill == "power" or busy_skill == "cleave":
		_blade_glow(u, hf)
	if _trail != null:
		_trail.active = String(skill["kind"]) in ["melee", "cleave"] and u > hf - 0.35 and u < hf + 0.22
	if String(skill["kind"]) in ["melee", "cleave"]:
		# Coil back while gathering the swing, then throw the weight forward through the strike.
		var heft: float = clampf(float(skill["weight"]), 0.8, 1.7)
		if u < hf:
			visual.rotation.x = -0.14 * heft * sin(clampf(u / hf, 0.0, 1.0) * PI * 0.5)
		else:
			visual.rotation.x = lerpf(0.2 * heft, 0.0, clampf((u - hf) / (1.0 - hf) * 1.5, 0.0, 1.0))
	model.scrub(CharacterModel.remap(busy_t / duration, hit_fraction(skill),
		float(skill["start"]), float(skill["strike"]), float(skill["end"])))
	if busy_t >= duration:
		busy = false
		if _trail != null:
			_trail.active = false

## While rolling, every non-boss enemy close to the hero is shoved sideways out of the way and has its current
## action interrupted. Bosses ignore it (Actor.is_boss).
func _shove_enemies(delta: float) -> void:
	var side: Vector3 = roll_dir.cross(Vector3.UP).normalized()
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.is_boss or e.impaled or e.is_ragdolled():
			continue
		# During a Skewer charge, do not shove enemies the blade can still catch; they are the target.
		if skewer_phase == 2 and e.can_be_impaled() and skewer_impaled.size() < 3 and not _big_hit.has(e.get_instance_id()):
			continue
		var rel: Vector3 = e.global_position - global_position
		rel.y = 0.0
		if rel.length() > body_radius + e.body_radius + 0.7:
			continue
		var direction: float = 1.0 if rel.dot(side) >= 0.0 else -1.0
		# Direct displacement (not knockback), so heavy enemies that resist knockback still get moved.
		var shove: Vector3 = side * direction * 6.0 + roll_dir * 1.5
		e.move_and_collide(shove * delta)
		if not _shoved.has(e.get_instance_id()):
			_shoved[e.get_instance_id()] = true
			e.interrupt(0.55)
			Fx.burst(self, e.global_position + Vector3(0, 0.3, 0), side * direction + Vector3.UP * 0.4, Color(0.5, 0.45, 0.38), 10, 3.5, 0.04)

# --- Skewer ---------------------------------------------------------------------------

const SKEWER_SPEED := 15.0
const SKEWER_SLOTS: Array[float] = [1.0, 1.4, 1.8]  # distance ahead of the hero along the blade, hilt first
const SKEWER_BIG_BONUS := 45.0   # flat extra damage against enemies too big to impale
const SKEWER_BIG_STUN := 1.6     # they are staggered this long, so they cannot hit back
const SKEWER_WINDUP := 0.28
const SKEWER_SKID := 0.24
const SKEWER_KICK_TIME := 0.55
const KICK_START := 0.15
const KICK_STRIKE := 0.6
const KICK_END := 1.1

func _start_skewer(cursor: Vector3) -> void:
	var skill: Dictionary = SKILLS["skewer"]
	var dir: Vector3 = cursor - global_position
	dir.y = 0.0
	if dir.length() < 0.4:
		dir = Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	skewer_dir = dir.normalized()
	mana -= float(skill["mana"])
	cooldowns["skewer"] = float(skill["cd"])
	_clear_aim()
	busy = true
	busy_skill = "skewer"
	busy_def = skill
	busy_target = null
	busy_t = 0.0
	busy_hit_done = false
	combat_timer = 5.0
	has_goal = false
	queued_skill = ""
	attack_target = null
	click_mode = 0
	skewer_phase = 1
	skewer_t = 0.0
	skewer_travel = 0.0
	skewer_full_at = -1.0
	skewer_kicked = false
	skewer_impaled.clear()
	_shoved.clear()
	_big_hit.clear()
	roll_dir = skewer_dir  # lets the roll's shove logic push bystanders out of the lane
	collision_mask = LAYER_WORLD  # run through the crowd; only the blade catches anyone
	visual.rotation.y = atan2(skewer_dir.x, skewer_dir.z)
	model.loop("charge_run", 0.6)
	model.weapon_aim = skewer_dir          # the animation carries the blade diagonally; aim it down the charge instead
	model.weapon_length_mult = 1.45        # long enough to carry three
	if _trail != null:
		_trail.active = false  # at charge speed the blade ribbon becomes a huge sheet; the impaled enemies sell it instead
	Fx.ring(self, global_position, 1.6, Color(0.8, 0.85, 1.0))

func _tick_skewer(delta: float) -> void:
	skewer_t += delta
	var skill: Dictionary = busy_def
	match skewer_phase:
		1:
			# Wind-up: sink low behind the blade, then drive off.
			var u: float = clampf(skewer_t / SKEWER_WINDUP, 0.0, 1.0)
			visual.rotation.x = lerpf(0.0, -0.12, u)
			move_with(Vector3.ZERO)
			if skewer_t >= SKEWER_WINDUP:
				skewer_phase = 2
				skewer_t = 0.0
				model.loop("charge_run", 1.5)
				Fx.punch(self, 1.8)
				Fx.shake(self, 0.1)
		2:
			var ramp: float = clampf(0.25 + skewer_t / 0.3, 0.25, 1.0)
			var speed: float = SKEWER_SPEED * ramp
			var before: Vector3 = global_position
			move_with(skewer_dir * speed)
			var moved: float = before.distance_to(global_position)
			skewer_travel += moved
			visual.rotation.y = atan2(skewer_dir.x, skewer_dir.z)
			visual.rotation.x = 0.24
			_skewer_dust += delta
			if _skewer_dust > 0.05:
				_skewer_dust = 0.0
				Fx.burst(self, global_position + Vector3(0, 0.1, 0), -skewer_dir + Vector3.UP * 0.5, Color(0.5, 0.45, 0.38), 3, 2.5, 0.04)
			Fx.shake(self, 0.02)
			if blade_blood > 0.3 and model.weapon_tip != null:
				Fx.burst(self, model.weapon_tip.global_position, Vector3.DOWN + skewer_dir * -0.5, Color(0.55, 0.04, 0.04), 2, 1.5, 0.025)
			_skewer_catch_enemies(skill)
			_shove_enemies(delta)
			_carry_impaled(delta)
			var blocked: bool = skewer_t > 0.2 and moved < speed * delta * 0.35
			if skewer_impaled.size() >= 3 and skewer_full_at < 0.0:
				skewer_full_at = skewer_t
			var full_run_done: bool = skewer_full_at >= 0.0 and skewer_t - skewer_full_at > 0.3
			if skewer_travel >= float(skill["range"]) or blocked or full_run_done:
				skewer_phase = 3
				skewer_t = 0.0
				model.loop("charge_run", 0.5)
		3:
			# Skid to a stop: plant the feet, carry the momentum.
			var u: float = clampf(skewer_t / SKEWER_SKID, 0.0, 1.0)
			move_with(skewer_dir * SKEWER_SPEED * 0.55 * pow(1.0 - u, 2.0))
			visual.rotation.x = lerpf(0.24, 0.05, u)
			_carry_impaled(delta)
			if u >= 1.0 or skewer_t >= SKEWER_SKID:
				skewer_t = 0.0
				if skewer_impaled.is_empty():
					skewer_phase = 5
					model.loop("idle_alert")
				else:
					skewer_phase = 4
					skewer_kicked = false
					model.manual("kick")
					model.scrub(KICK_START)
					Fx.ring(self, global_position, 2.2, Color(1.0, 0.9, 0.6))
		4:
			var u: float = clampf(skewer_t / SKEWER_KICK_TIME, 0.0, 1.0)
			var hit_frac: float = (KICK_STRIKE - KICK_START) / (KICK_END - KICK_START)
			model.scrub(CharacterModel.remap(u, hit_frac, KICK_START, KICK_STRIKE, KICK_END))
			move_with(Vector3.ZERO)
			visual.rotation.x = -0.12 * sin(clampf(u / hit_frac, 0.0, 1.0) * PI * 0.5) if u < hit_frac else 0.12 * (1.0 - u)
			if u < hit_frac:
				_carry_impaled(delta)
			if not skewer_kicked and u >= hit_frac:
				skewer_kicked = true
				model.weapon_aim = null  # blade relaxes once the pile is booted off
				_skewer_kick()
			if u >= 1.0:
				skewer_phase = 5
				skewer_t = 0.0
		5:
			move_with(Vector3.ZERO)
			visual.rotation.x = lerpf(visual.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
			if skewer_t >= 0.22:
				_end_skewer()

## Runs the nearest enemies in the lane onto the blade. Returns true if a boss stops the charge.
func _skewer_catch_enemies(skill: Dictionary) -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		# Knocked-down enemies (lying or getting up) are still fair game; only ones already on the blade are skipped.
		if e == null or e.dead or e.impaled or (e.is_ragdolled() and e.ragdoll.state == Ragdoll.State.FLIGHT):
			continue
		var rel: Vector3 = e.global_position - global_position
		rel.y = 0.0
		var ahead: float = rel.dot(skewer_dir)
		var across: float = absf(rel.cross(skewer_dir).y)
		if ahead < 0.2 or ahead > 1.6 or across > 0.75 + e.body_radius * 0.6:
			continue
		if not e.can_be_impaled():
			# Too big (or a boss): cannot be spitted. It takes a flat chunk of extra damage and is staggered
			# so it cannot hit back, and the charge carries on past it.
			if _big_hit.has(e.get_instance_id()):
				continue
			_big_hit[e.get_instance_id()] = true
			var damage: float = weapon_damage(float(skill["mult"])) * ItemEffects.outgoing_multiplier(self, e) + SKEWER_BIG_BONUS
			var slam: Dictionary = Combat.resolve(self, e, damage, Combat.DamageType.PHYSICAL, false, 3.0)
			slam["skill_id"] = "skewer"
			e.receive(slam, global_position)
			e.stun_time = maxf(e.stun_time, SKEWER_BIG_STUN)  # forced, even for bosses
			Fx.text_at(self, e.global_position + Vector3(0, e.body_height + 0.7, 0), "Staggered", Color(1.0, 0.9, 0.5), 46)
			Fx.ring(self, e.global_position, 2.4, Color(1.0, 0.85, 0.5))
			Fx.punch(self, 2.6)
			Fx.shake(self, 0.2)
			blade_blood = minf(blade_blood + 0.2, 1.0)
			continue
		if skewer_impaled.size() >= 3:
			continue
		e.set_impaled(true)
		e.ragdoll_hang(atan2(-skewer_dir.x, -skewer_dir.z))
		skewer_impaled.append(e)
		var stab: Dictionary = Combat.resolve(self, e, weapon_damage(float(skill["mult"])) * ItemEffects.outgoing_multiplier(self, e),
			Combat.DamageType.PHYSICAL, false, 2.0)
		stab["skill_id"] = "skewer"
		stab["damage"] = minf(float(stab["damage"]), maxf(e.health - 1.0, 0.0))  # leave them alive for the kick
		e.receive(stab, global_position)
		blade_blood = minf(blade_blood + 0.4, 1.0)
		Fx.text_at(self, e.global_position + Vector3(0, e.body_height + 0.7, 0), "Impaled", Color(1.0, 0.8, 0.55), 44)
		Fx.burst(self, e.global_position + Vector3(0, 1.1, 0), skewer_dir + Vector3.UP * 0.3, Color(0.6, 0.04, 0.04), 16, 5.0)
		Fx.punch(self, 2.0)
		Fx.shake(self, 0.12)
	return false

## Keeps skewered enemies pinned along the blade, hilt first, and bleeds them a little as they ride.
func _carry_impaled(delta: float) -> void:
	_skewer_tick_clock += delta
	var tick: bool = false
	if _skewer_tick_clock >= 0.25:
		_skewer_tick_clock = 0.0
		tick = true
	for i in range(skewer_impaled.size() - 1, -1, -1):
		if not is_instance_valid(skewer_impaled[i]):
			skewer_impaled.remove_at(i)  # a dead enemy stays on the blade and is still kicked off
	for i in skewer_impaled.size():
		var e: Actor = skewer_impaled[i]
		var pos: Vector3 = global_position + skewer_dir * SKEWER_SLOTS[i]
		e.global_position = Vector3(pos.x, 0.3, pos.z)
		e.reset_physics_interpolation()
		if e.ragdoll != null:
			e.ragdoll.yaw = atan2(-skewer_dir.x, -skewer_dir.z)  # facing the knight, blade through the chest
		if tick and not e.dead and e.health > 1.0:
			var ride: Dictionary = Combat.resolve(self, e, weapon_damage(0.25), Combat.DamageType.PHYSICAL, false, 0.4)
			ride["secondary"] = true
			ride["quiet"] = true  # damage only: no popup, flinch or sound for the bleed ticks
			# The bleed alone never finishes them; the kick does.
			ride["damage"] = minf(float(ride["damage"]), maxf(e.health - 1.0, 0.0))
			e.receive(ride, global_position)

## The finish: a boot to the pile throws every impaled enemy off the sword and away, in a fan.
func _skewer_kick() -> void:
	var count: int = skewer_impaled.size()
	var angles: Array[float] = [0.0]
	if count == 2:
		angles = [-0.3, 0.3]
	elif count >= 3:
		angles = [-0.5, 0.0, 0.5]
	var skill: Dictionary = busy_def
	for i in count:
		var e: Actor = skewer_impaled[i]
		if not is_instance_valid(e):
			continue
		e.set_impaled(false)
		var away: Vector3 = skewer_dir.rotated(Vector3.UP, angles[i])
		if not e.dead:
			var boot: Dictionary = Combat.resolve(self, e, weapon_damage(float(skill["mult"]) * 1.2), Combat.DamageType.PHYSICAL, false, 3.2)
			boot["skill_id"] = "skewer_kick"
			e.receive(boot, global_position)
		if is_instance_valid(e):
			# Thrown like a sack (alive or not): fast over the ground, lofted, end-over-end.
			var spin: Vector3 = away.cross(Vector3.UP) * randf_range(7.0, 11.0) + Vector3.UP * randf_range(-3.0, 3.0)
			e.ragdoll_launch(away * 12.0, 6.5, spin)
		Fx.burst(self, e.global_position + Vector3(0, 1.0, 0), away + Vector3.UP * 0.4, Color(0.6, 0.05, 0.04), 20, 7.0)
	blade_blood = minf(blade_blood + 0.3, 1.0)
	skewer_impaled.clear()
	Fx.ring(self, global_position + skewer_dir * 1.3, 3.0, Color(1.0, 0.85, 0.5))
	Fx.shake(self, 0.3)
	Fx.punch(self, 3.8)
	Fx.hitstop(self, 0.09)
func _end_skewer() -> void:
	for e in skewer_impaled:
		if is_instance_valid(e):
			e.set_impaled(false)
			e.ragdoll_launch(skewer_dir * 3.0, 2.0, skewer_dir.cross(Vector3.UP) * 4.0)
	skewer_impaled.clear()
	skewer_phase = 0
	busy = false
	model.weapon_aim = null
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	visual.rotation.x = 0.0
	if _trail != null:
		_trail.active = false
	model.loop("idle_alert")

# --- Leap ------------------------------------------------------------------------------
# Spring at the cursor. Onto a downed enemy: land with the blade driven straight down through it into the ground,
# plant a boot on it and wrench the sword free. Onto open ground (or standing enemies): a two-handed overhead chop.

const LEAP_WINDUP := 0.2
const LEAP_SLAM_HOLD := 0.5
const LEAP_PULL_TIME := 1.0
const LEAP_SLAM_MULT := 3.6
const LEAP_CHOP_MULT := 1.3
const LEAP_CHOP_RADIUS := 2.3
const LEAP_PIN_TIME := 1.7
const LEAP_SLAM_REACH := 0.5      # landing spot sits this far short of the victim: the blade comes down in front of the knight
const LEAP_CHOP_RECOVER := 0.6
# Key times in the "leap" clip (Meshy Basic_Jump): crouch, take-off, plunge landing, then the rise that pulls the blade up.
const LEAP_CLIP_CROUCH := 1.4
const LEAP_CLIP_TAKEOFF := 1.68
const LEAP_CLIP_LAND := 2.5
const LEAP_CLIP_PULL_START := 2.95
const LEAP_CLIP_END := 3.9

var leap_phase: int = 0  # 0 off, 1 crouch, 2 airborne, 3 slam hold / chop recovery, 4 boot + pull-out
var leap_t: float = 0.0
var leap_from: Vector3 = Vector3.ZERO
var leap_to: Vector3 = Vector3.ZERO
var leap_air_time: float = 0.5
var leap_victim: Actor = null
var leap_dir: Vector3 = Vector3.FORWARD
var leap_slam: bool = false
var _leap_pulled: bool = false

## A knocked-down enemy (lying or getting up) is the slam target.
static func is_downed(e: Actor) -> bool:
	if e == null or e.dead or e.impaled or not e.is_ragdolled():
		return false
	return e.ragdoll.state != Ragdoll.State.HANG   # thrown, lying or getting up: anything not fully on its feet

func _downed_near(point: Vector3, radius: float) -> Actor:
	var best: Actor = null
	var best_d: float = radius
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if not is_downed(e):
			continue
		var d: float = Vector2(e.global_position.x - point.x, e.global_position.z - point.z).length()
		if d < best_d:
			best_d = d
			best = e
	return best

func _start_leap(cursor: Vector3) -> void:
	var skill: Dictionary = SKILLS["leap"]
	var reach: Vector3 = aim_point_for("leap", cursor)
	leap_victim = _downed_near(cursor, 3.2)
	leap_slam = leap_victim != null
	var dest: Vector3 = reach
	if leap_victim != null:
		var away: Vector3 = global_position - leap_victim.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.BACK
		dest = leap_victim.global_position + away * LEAP_SLAM_REACH  # the blade comes down in front of the knight
		var offset: Vector3 = dest - global_position
		offset.y = 0.0
		if offset.length() > float(skill["range"]):
			dest = global_position + offset.normalized() * float(skill["range"])
			leap_victim = null   # too far to land on it; still a decent chop at the spot
			leap_slam = false
	dest = Nav.snap(self, Vector3(dest.x, 0.0, dest.z))
	dest.y = 0.0
	leap_from = global_position
	leap_to = dest
	var flat: Vector3 = dest - global_position
	flat.y = 0.0
	leap_dir = flat.normalized() if flat.length() > 0.2 else Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	leap_air_time = clampf(0.36 + flat.length() * 0.035, 0.4, 0.75)
	mana -= float(skill["mana"])
	cooldowns["leap"] = float(skill["cd"])
	_clear_aim()
	busy = true
	busy_skill = "leap"
	busy_def = skill
	busy_target = null
	busy_t = 0.0
	busy_hit_done = false
	combat_timer = 5.0
	has_goal = false
	queued_skill = ""
	attack_target = null
	click_mode = 0
	leap_phase = 1
	leap_t = 0.0
	_leap_pulled = false
	collision_mask = LAYER_WORLD   # sail over the crowd; the landing decides who is hit
	visual.rotation.y = atan2(leap_dir.x, leap_dir.z)
	model.manual("leap")
	model.scrub(LEAP_CLIP_CROUCH)
	if _trail != null:
		_trail.active = false
	Fx.ring(self, global_position, 1.4, Color(0.9, 0.85, 0.7))

func _tick_leap(delta: float) -> void:
	leap_t += delta
	# Committed at take-off: once the knight is committed to a slam, the victim getting up or dying does not change it.
	var slam: bool = leap_slam and leap_victim != null and is_instance_valid(leap_victim)
	match leap_phase:
		1:
			var u: float = clampf(leap_t / LEAP_WINDUP, 0.0, 1.0)
			model.scrub(lerpf(LEAP_CLIP_CROUCH, LEAP_CLIP_TAKEOFF, u))
			move_with(Vector3.ZERO)
			if leap_t >= LEAP_WINDUP:
				leap_phase = 2
				leap_t = 0.0
				Fx.burst(self, global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 12, 3.5, 0.04)
				Fx.punch(self, 1.6)
				Sfx.play(self, "swing", -4.0)
		2:
			var u: float = clampf(leap_t / leap_air_time, 0.0, 1.0)
			if slam:
				# Track the target while airborne (it may still be tumbling or scrambling up).
				var spot: Vector3 = leap_victim.global_position - leap_dir * LEAP_SLAM_REACH
				leap_to = Vector3(spot.x, 0.0, spot.z)
			var ground: Vector3 = leap_from.lerp(leap_to, u)
			global_position = Vector3(ground.x, 0.0, ground.z)
			# The clip carries the whole jump: blade raised overhead, then the plunge down in front.
			model.scrub(lerpf(LEAP_CLIP_TAKEOFF, LEAP_CLIP_LAND, u))
			if u >= 1.0:
				_leap_land(slam)
		3:
			move_with(Vector3.ZERO)
			if slam:
				var u: float = clampf(leap_t / LEAP_SLAM_HOLD, 0.0, 1.0)
				model.scrub(lerpf(LEAP_CLIP_LAND, LEAP_CLIP_PULL_START, u))   # crouched over the planted blade
				if leap_victim != null and is_instance_valid(leap_victim) and leap_victim.ragdoll != null:
					leap_victim.ragdoll.pin(0.3)
				if u >= 1.0:
					leap_phase = 4
					leap_t = 0.0
					_leap_pulled = false
			else:
				var u: float = clampf(leap_t / LEAP_CHOP_RECOVER, 0.0, 1.0)
				model.scrub(lerpf(LEAP_CLIP_LAND, LEAP_CLIP_END, u))
				if u >= 1.0:
					_end_leap()
		4:
			# Boot up onto the body, then rise and wrench the blade out of the ground (the clip's own rise).
			move_with(Vector3.ZERO)
			var u: float = clampf(leap_t / LEAP_PULL_TIME, 0.0, 1.0)
			model.scrub(lerpf(LEAP_CLIP_PULL_START, LEAP_CLIP_END, smoothstep(0.0, 1.0, u)))
			model.leg_raise = smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.8, 1.0, u))
			if leap_victim != null and is_instance_valid(leap_victim) and leap_victim.ragdoll != null:
				leap_victim.ragdoll.pin(0.3)   # held down under the boot
			if not _leap_pulled and u >= 0.5:
				_leap_pulled = true
				if model.weapon_tip != null:
					Fx.burst(self, model.weapon_tip.global_position, Vector3.UP + leap_dir * -0.3, Color(0.6, 0.04, 0.04), 18, 5.0, 0.03)
				Fx.burst(self, leap_to + leap_dir * LEAP_SLAM_REACH + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 8, 2.5, 0.04)
				Fx.shake(self, 0.1)
				Fx.punch(self, 1.2)
			if u >= 1.0:
				_end_leap()

func _leap_land(slam: bool) -> void:
	if slam and leap_victim.dead:
		slam = false         # it died in mid-air; nothing left to pin, so this lands as a plain chop
		leap_slam = false
	global_position = Vector3(leap_to.x, 0.0, leap_to.z)
	reset_physics_interpolation()
	leap_phase = 3
	leap_t = 0.0
	if slam:
		model.scrub(LEAP_CLIP_LAND)
		var damage: float = weapon_damage(LEAP_SLAM_MULT) * ItemEffects.outgoing_multiplier(self, leap_victim)
		var result: Dictionary = Combat.resolve(self, leap_victim, damage, Combat.DamageType.PHYSICAL, false, 2.4, true)
		result["skill_id"] = "leap"
		leap_victim.receive(result, global_position)
		if is_instance_valid(leap_victim) and not leap_victim.dead:
			leap_victim.stun_time = maxf(leap_victim.stun_time, LEAP_PIN_TIME)
			if leap_victim.ragdoll != null:
				leap_victim.ragdoll.pin(LEAP_SLAM_HOLD + LEAP_PULL_TIME)
		var tip: Vector3 = leap_victim.global_position + Vector3(0, 0.2, 0) if is_instance_valid(leap_victim) else leap_to
		Fx.burst(self, tip, Vector3.UP, Color(0.6, 0.04, 0.04), 26, 6.0, 0.03)
		Fx.burst(self, leap_to + leap_dir * 0.5 + Vector3(0, 0.05, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 18, 4.0, 0.05)
		Fx.ring(self, leap_to, 2.4, Color(1.0, 0.85, 0.55))
		Fx.text_at(self, tip + Vector3(0, 1.3, 0), "Impaled!", Color(1.0, 0.8, 0.5), 52)
		blade_blood = minf(blade_blood + 0.5, 1.0)
		Fx.shake(self, 0.3)
		Fx.punch(self, 3.4)
		Fx.hitstop(self, 0.08)
		Sfx.play(self, "swing_heavy", 0.0)
	else:
		model.scrub(LEAP_CLIP_LAND)
		var hit_any: bool = false
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Actor
			if e == null or e.dead or e.impaled:
				continue
			if flat_distance_to(e) - e.body_radius > LEAP_CHOP_RADIUS:
				continue
			var chop: Dictionary = Combat.resolve(self, e, weapon_damage(LEAP_CHOP_MULT) * ItemEffects.outgoing_multiplier(self, e),
				Combat.DamageType.PHYSICAL, true, 1.8)
			chop["skill_id"] = "leap"
			e.receive(chop, global_position)
			hit_any = true
		Fx.burst(self, global_position + leap_dir * 1.0 + Vector3(0, 0.05, 0), Vector3.UP, Color(0.5, 0.45, 0.38), 20, 4.0, 0.05)
		Fx.ring(self, global_position + leap_dir * 0.8, 2.6, Color(0.9, 0.85, 0.7))
		Fx.shake(self, 0.22 if hit_any else 0.12)
		Fx.punch(self, 2.6)
		if hit_any:
			Fx.hitstop(self, 0.06)
		Sfx.play(self, "swing_heavy", -2.0)

func _end_leap() -> void:
	if leap_victim != null and is_instance_valid(leap_victim) and leap_victim.ragdoll != null:
		leap_victim.ragdoll.release_pin()
	leap_victim = null
	leap_phase = 0
	busy = false
	model.leg_raise = 0.0
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	visual.rotation.x = 0.0
	if _trail != null:
		_trail.active = false
	model.loop("idle_alert")

## Two-phase cast: arms rise and the orb swells (gather), then both hands drive forward and it is thrown.
func _tick_charged(skill: Dictionary) -> void:
	var scale_factor: float = busy_time / float(skill["time"])
	var t_gather: float = float(skill["gather"]) * scale_factor
	var t_throw: float = t_gather + float(skill["release_after"]) * scale_factor
	face(busy_aim, 0.2)
	if busy_t < t_gather:
		var u: float = clampf(busy_t / t_gather, 0.0, 1.0)
		# Slow at first (the weight of pulling fire out of the air), then the arms rush up.
		model.scrub(lerpf(float(skill["start"]), float(skill["strike"]), pow(u, 1.7)))
		visual.rotation.x = -0.14 * sin(u * PI * 0.5)
		Fx.shake(self, 0.008 + 0.02 * u)  # faint tremble that builds with the charge
	else:
		if not _release_started:
			_release_started = true
			model.once(String(skill["release_clip"]), float(skill["release_start"]),
				float(skill["release_speed"]) / scale_factor, 0.12)
			_lunge(float(skill["lunge"]))
			Fx.punch(self, 1.0)
		visual.rotation.x = 0.22 * (1.0 - clampf((busy_t - t_throw) / 0.3, 0.0, 1.0))
		if not busy_hit_done and busy_t >= t_throw:
			busy_hit_done = true
			_apply_skill(skill)
			Fx.shake(self, 0.12)
			Fx.punch(self, 2.4)
			Fx.ring(self, global_position, 2.2, Color(1.0, 0.6, 0.2))
	if busy_t >= busy_time:
		busy = false

## Weight of the blow itself, independent of whether it connects: camera punch, dust, ground shock.
func _strike_fx(skill: Dictionary) -> void:
	if not (String(skill["kind"]) in ["melee", "cleave"]):
		return
	if busy_skill == "power" or busy_skill == "cleave":
		return   # these have their own, much bigger impact effects (SkillFx)
	var weight: float = float(skill["weight"])
	var dir: Vector3 = busy_aim - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	Fx.shake(self, 0.03 + 0.05 * weight)
	Fx.punch(self, 0.6 + 1.2 * weight)
	Fx.burst(self, global_position + dir * 1.3 + Vector3(0, 0.05, 0), dir + Vector3.UP * 0.4, Color(0.5, 0.45, 0.38),
		int(5 + 6 * weight), 2.2 + weight, 0.04)
	if weight >= 1.5:
		Fx.ring(self, global_position + dir * 1.2, 1.7, Color(0.9, 0.85, 0.7))

## Steps toward the target, but never into it: the lunge only closes the gap that actually exists.
func _lunge(max_distance: float) -> void:
	if max_distance <= 0.0:
		return
	var to_aim: Vector3 = busy_aim - global_position
	to_aim.y = 0.0
	var target_radius: float = busy_target.body_radius if busy_target != null else 0.0
	var gap: float = to_aim.length() - target_radius - body_radius - 0.15
	var travel: float = clampf(gap, 0.0, max_distance)
	if travel <= 0.02:
		return
	# knock decays at 22 m/s^2, so an impulse of v covers v^2 / 44 metres.
	knock += to_aim.normalized() * sqrt(44.0 * travel)

func _try_roll(cursor: Vector3) -> void:
	if float(cooldowns.get("dodge", 0.0)) > 0.0:
		return
	if busy and not busy_hit_done:
		return  # committed to the wind-up; once the blow lands the recovery can be cancelled
	var roll_cost: float = ROLL_STAMINA * armor_stat("roll_cost", 1.0)
	if stamina < roll_cost:
		_say("Too tired to dodge")
		return
	var dir: Vector3 = Vector3.ZERO
	if has_goal and (goal - global_position).length() > 0.4:
		dir = goal - global_position
	else:
		dir = cursor - global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	roll_dir = dir.normalized()
	stamina -= roll_cost
	cooldowns["dodge"] = float(SKILLS["dodge"]["cd"])
	rolling = true
	roll_t = 0.0
	busy = false
	queued_skill = ""
	attack_target = null
	click_mode = 0
	has_goal = false
	if _trail != null:
		_trail.active = false
	invulnerable_time = ROLL_TIME + 0.12  # immune for the whole roll plus a short grace
	_shoved.clear()
	collision_mask = LAYER_WORLD  # slip through enemies while rolling
	visual.rotation.y = atan2(roll_dir.x, roll_dir.z)
	model.manual("roll")
	model.scrub(ROLL_CLIP_START)
	Sfx.play(self, "swing", -6.0, 0.7)
	ItemEffects.on_roll_start(self)

func _tick_roll(delta: float) -> void:
	_shove_enemies(delta)
	roll_t += delta
	var u: float = clampf(roll_t / ROLL_TIME, 0.0, 1.0)
	model.scrub(lerpf(ROLL_CLIP_START, ROLL_CLIP_END, u))
	move_with(roll_dir * ROLL_SPEED * armor_stat("roll_speed", 1.0) * (1.0 - 0.6 * u))
	if roll_t >= ROLL_TIME:
		rolling = false
		collision_mask = LAYER_WORLD | LAYER_ENEMY
		model.loop("idle_alert")
		ItemEffects.on_roll_end(self)

static func hit_fraction(skill: Dictionary) -> float:
	return (float(skill["strike"]) - float(skill["start"])) / (float(skill["end"]) - float(skill["start"]))

## Power Strike lands: crater, rings, rocks and cracks at the point of impact, splash on neighbours, and a shove.
func _power_impact() -> void:
	var dir: Vector3 = busy_aim - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
	var point: Vector3 = global_position + dir * 1.9
	if busy_target != null and is_instance_valid(busy_target):
		point = busy_target.global_position
	point.y = 0.0
	SkillFx.power_impact(self, point, dir, has_affix("gravewarden"))
	Fx.hitstop(self, 0.08)
	if busy_target != null and is_instance_valid(busy_target) and not busy_target.dead:
		busy_target.interrupt(0.7)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e == busy_target:
			continue
		var gap: Vector3 = e.global_position - point
		gap.y = 0.0
		if gap.length() > POWER_SPLASH_RADIUS + e.body_radius:
			continue
		var splash: Dictionary = Combat.resolve(self, e, weapon_damage(float(SKILLS["power"]["mult"]) * 0.5), Combat.DamageType.PHYSICAL, false, 1.5)
		splash["skill_id"] = "power"
		splash["secondary"] = true
		e.receive(splash, point)
		if is_instance_valid(e) and not e.dead:
			e.interrupt(0.5)
	ItemEffects.power_shockwave(self, dir)

const POWER_SPLASH_RADIUS := 2.0

func weapon_damage(mult: float) -> float:
	return randf_range(weapon_min, weapon_max) * (1.0 + strength * 0.02) * mult * weapon_stat("damage", 1.0)

func _apply_skill(skill: Dictionary) -> void:
	var mult: float = skill["mult"]
	match String(skill["kind"]):
		"melee":
			if busy_target != null and not busy_target.dead \
					and flat_distance_to(busy_target) - busy_target.body_radius <= float(skill["range"]) + 0.5:
				var guaranteed_crit: bool = riposte_time > 0.0
				var damage: float = weapon_damage(mult) * ItemEffects.outgoing_multiplier(self, busy_target)
				var result: Dictionary = Combat.resolve(self, busy_target, damage, Combat.DamageType.PHYSICAL,
					not guaranteed_crit, float(skill["weight"]), guaranteed_crit)
				result["skill_id"] = busy_skill
				result["finisher"] = skill.get("finisher", false)
				if guaranteed_crit:
					riposte_time = 0.0
				busy_target.receive(result, global_position)
			if busy_skill == "power":
				_power_impact()
		"cleave":
			var cleave_hits: int = 0
			for node in get_tree().get_nodes_in_group("enemies"):
				var e := node as Actor
				if e != null and not e.dead and flat_distance_to(e) - e.body_radius <= float(skill["range"]):
					var swing: Dictionary = Combat.resolve(self, e, weapon_damage(mult) * ItemEffects.outgoing_multiplier(self, e),
						Combat.DamageType.PHYSICAL, true, float(skill["weight"]))
					swing["skill_id"] = busy_skill
					e.receive(swing, global_position)
					cleave_hits += 1
					SkillFx.cleave_hit(self, e)
			SkillFx.cleave_burst(self, float(skill["range"]))
			if cleave_hits > 0:
				Fx.hitstop(self, 0.05)
				Fx.punch(self, 1.2 + 0.4 * minf(cleave_hits, 4))
		"projectile":
			var ball := Projectile.new()
			ball.owner_actor = self
			var dir: Vector3 = busy_aim - global_position
			dir.y = 0.0
			ball.direction = dir.normalized()
			ball.damage = 14.0 + strength * 0.4
			ball.destination = busy_aim + Vector3(0, 0.8, 0)
			get_tree().current_scene.add_child(ball)
			var origin: Vector3 = global_position + Vector3(0, 1.2, 0) + ball.direction * 0.8
			if _fire_orb != null and is_instance_valid(_fire_orb):
				origin = _fire_orb.release()  # the gathered orb is the fireball that gets thrown
				_fire_orb = null
			ball.global_position = origin
			if has_affix("twin_flame"):
				var twin := Projectile.new()
				twin.owner_actor = self
				twin.direction = ball.direction.rotated(Vector3.UP, 0.4)
				twin.damage = ball.damage * 0.6
				var offset: Vector3 = (busy_aim - global_position).rotated(Vector3.UP, 0.35)
				twin.destination = global_position + offset + Vector3(0, 0.8, 0)
				get_tree().current_scene.add_child(twin)
				twin.global_position = ball.global_position

## The sword stays red while it is bloody and slowly dries.
func _update_blade_blood(delta: float) -> void:
	if model == null or model.weapon == null:
		return
	blade_blood = maxf(blade_blood - delta * 0.04, 0.0)
	if blade_blood <= 0.02:
		if _blood_mat != null:
			model.set_weapon_overlay(null)
			_blood_mat = null
		return
	if _blood_mat == null:
		_blood_mat = model.make_blade_blood_material()
		model.set_weapon_overlay(_blood_mat)
	_blood_mat.set_shader_parameter("amount", clampf(blade_blood, 0.0, 1.0))

# --- Equipment -----------------------------------------------------------------

func has_affix(id: String) -> bool:
	for item in equipment.values():
		if item["affix"] == id:
			return true
	return false

func _stat(slot: int, key: String, fallback: float) -> float:
	var item: Variant = equipment.get(slot)
	if item == null:
		return fallback
	return float((item as Dictionary)["stats"].get(key, fallback))

func weapon_stat(key: String, fallback: float) -> float:
	return _stat(Items.Slot.WEAPON, key, fallback)

func armor_stat(key: String, fallback: float) -> float:
	return _stat(Items.Slot.ARMOR, key, fallback)

## Attack speed: weapon base times a temporary haste bonus.
func attack_speed() -> float:
	return weapon_stat("speed", 1.0) * (1.0 + (ItemEffects.HASTE_BONUS if haste_time > 0.0 else 0.0))

func equip(item: Dictionary, announce: bool = true) -> void:
	equipment[int(item["slot"])] = item
	armor = base_armor + armor_stat("armor", 0.0)
	if announce:
		_say("Equipped %s" % item["name"])

func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	Fx.text_at(self, global_position + Vector3(0, 2.4, 0), "+%d" % int(amount), Color(0.4, 1.0, 0.4), 40)

func _collect_orbs() -> void:
	for node in get_tree().get_nodes_in_group("orbs"):
		var orb := node as Node3D
		if orb != null and orb.global_position.distance_to(global_position + Vector3(0, 0.6, 0)) < 1.3:
			if bool(orb.get("is_potion")):
				potions = mini(potions + 1, MAX_POTIONS)
				Fx.text_at(self, global_position + Vector3(0, 2.4, 0), "+1 potion", Color(1.0, 0.45, 0.4), 40)
			else:
				heal(HealthOrb.HEAL)
			orb.queue_free()

func on_dealt_hit(target: Actor, result: Dictionary) -> void:
	if not result.get("secondary", false):
		blade_blood = minf(blade_blood + 0.05, 1.0)
	ItemEffects.on_dealt_hit(self, target, result)

func on_enemy_killed(enemy: Actor) -> void:
	ItemEffects.on_kill(self, enemy)

func _filter_incoming(result: Dictionary) -> Dictionary:
	return ItemEffects.filter_incoming(self, result)

func _regen(delta: float) -> void:
	var in_combat: bool = combat_timer > 0.0
	health = minf(health + 1.5 * (0.3 if in_combat else 1.0) * delta, max_health)
	mana = minf(mana + 3.0 * delta, max_mana)
	if not in_combat or velocity.length() < 0.5:
		stamina = minf(stamina + 14.0 * delta, max_stamina)

func _say(text: String) -> void:
	message = text
	message_time = 1.5

func cooldown_fraction(id: String) -> float:
	var total: float = float(SKILLS[id]["cd"])
	if total <= 0.0:
		return 0.0
	return clampf(float(cooldowns.get(id, 0.0)) / total, 0.0, 1.0)

func _on_hurt(_result: Dictionary, _source_pos: Vector3) -> void:
	combat_timer = 5.0
	hurt_flash = 1.0
	Sfx.play(self, "hurt", -2.0)
	Fx.shake(self, 0.08)

func _on_avoided(_outcome: int) -> void:
	combat_timer = 5.0

func _popup_tint() -> Color:
	return Color(1.0, 0.35, 0.3)
