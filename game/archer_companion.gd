class_name ArcherCompanion
extends Actor
## Cutter: a permanent ranged companion. He follows the hero, chooses among enemies actively hunting the hero, draws, looses a physical
## arrow, and repositions instead of becoming another melee obstruction. No command UI is required: he is part of every run by default.

const MODEL_DIR := "res://assets/models/npc_recruit"
const CLIPS: Array[String] = ["idle", "calm", "walk", "run"]
const BOW_MODEL := "res://assets/models/archer/bow/model.glb"
const QUIVER_MODEL := "res://assets/models/archer/quiver/model.glb"
const ARROW_MODEL := "res://assets/models/archer/arrow/model.glb"
const FOLLOW_DISTANCE := 2.7
const HARD_TETHER_DISTANCE := 16.0
const TELEPORT_TETHER_DISTANCE := 30.0
const MOVE_SPEED := 4.6
const RANGE := 17.0
const MIN_COMBAT_RANGE := 8.0
const PREFERRED_COMBAT_RANGE := 12.0
const DRAW_TIME := 0.62
const SHOT_COOLDOWN := 1.05
const DAMAGE := 17.0
const TAKE_AIM_MULT := 15.0
const TAKE_AIM_COMBAT_SECONDS := 21.0
const TAKE_AIM_DRAW_TIME := 0.92

var player: Player
var target: Enemy
var testing_disabled: bool = false
var shots_fired: int = 0
var last_hit_target: Enemy
var take_aim_armed: bool = false
var take_aim_reload_required: float = 0.0
var take_aim_reload_remaining: float = 0.0
var _nav: Dictionary = {}
var _scan_left: float = 0.0
var _cooldown: float = 0.25
var _draw: float = 0.0
var _draw_arrow: Node3D
var _skeleton: Skeleton3D
var _pose_bones: Dictionary = {}

func setup(hero: Player) -> void:
	player = hero
	global_position = hero.global_position + Vector3(1.8, 0.0, 1.6)

func _ready() -> void:
	add_to_group("companions")
	display_name = "Cutter"
	max_health = 180.0
	health = max_health
	attack_rating = 42.0
	defense = 28.0
	armor = 18.0
	crit_chance = 0.08
	crushing_chance = 0.0
	deep_wounds_chance = 0.10
	impalable = false
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	_build_model(MODEL_DIR, CLIPS, 1.8, 0.38)
	model.loop("idle")
	_attach_gear()
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for bone_name in ["Spine02", "LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "RightHand"]:
		_pose_bones[bone_name] = _skeleton.find_bone(bone_name)
	model.anim.mixer_applied.connect(_apply_draw_pose)

func _attach_gear() -> void:
	_attach_prop(BOW_MODEL, "LeftHand", 1.58, Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.02, 0.02))
	# The imported quiver is already upright along +Y. Keep it aligned with the spine and add only a slight shoulder cant.
	var quiver_basis := Basis(Vector3.FORWARD, -0.16)
	_attach_prop(QUIVER_MODEL, "Spine02", 0.78, quiver_basis, Vector3(-0.14, -0.08, 0.08))
	_draw_arrow = _attach_prop(ARROW_MODEL, "RightHand", 0.92, Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.02, 0.02))
	_draw_arrow.visible = false

func _attach_prop(path: String, bone: String, size: float, prop_basis: Basis, offset: Vector3) -> Node3D:
	var prop: Node3D = (load(path) as PackedScene).instantiate()
	LootDrop._use_vertex_colours(prop)
	var box: AABB = CharacterModel._bounds_of(prop)
	var extent: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var rig_scale: float = skeleton.global_transform.basis.get_scale().x
	var holder := Node3D.new()
	holder.position = offset
	holder.basis = prop_basis.scaled(Vector3.ONE * size / maxf(extent * rig_scale, 0.001))
	model._mount_for(bone).add_child(holder)
	holder.add_child(prop)
	prop.position = -box.get_center()
	return holder

func _physics_process(delta: float) -> void:
	if testing_disabled or player == null or not is_instance_valid(player) or player.dead:
		move_with(Vector3.ZERO)
		model.loop("idle")
		return
	var frozen: bool = _actor_tick(delta)
	if frozen or dead or stun_time > 0.0:
		move_with(Vector3.ZERO)
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_scan_left -= delta
	if not is_instance_valid(target):
		target = null
	if not _valid_target(target):
		target = null
	if _scan_left <= 0.0:
		_scan_left = 0.30
		if target == null or randf() < 0.28:
			target = _random_threat()
	var player_gap: float = flat_distance_to(player)
	# Combat spacing wins over formation following. Only a genuinely separated hero may pull Cutter away from his firing position.
	if player_gap > TELEPORT_TETHER_DISTANCE:
		global_position = Nav.snap(self, _formation_point())
		reset_physics_interpolation()
		_nav.clear()
		_cancel_draw()
		return
	if player_gap > HARD_TETHER_DISTANCE or target == null:
		_follow(delta)
		return
	var enemy_gap: float = flat_distance_to(target)
	if enemy_gap < MIN_COMBAT_RANGE:
		_reposition(delta, (global_position - target.global_position).normalized())
		return
	if enemy_gap > RANGE or not _line_to(target):
		# Close only until bow range, never until Cutter is standing on the target. With blocked sight, strafe instead of charging.
		var toward: Vector3 = (target.global_position - global_position).normalized()
		var move_dir: Vector3 = toward if enemy_gap > PREFERRED_COMBAT_RANGE else toward.cross(Vector3.UP)
		_reposition(delta, move_dir)
		return
	move_with(Vector3.ZERO)
	face(target.global_position, 0.28)
	model.loop("idle", 0.82)
	if _cooldown > 0.0:
		_cancel_draw()
		return
	if not take_aim_armed and take_aim_reload_remaining <= 0.0 and not _is_take_aim_assigned_to_bar():
		arm_take_aim()
	var draw_time: float = TAKE_AIM_DRAW_TIME if take_aim_armed else DRAW_TIME
	_draw = minf(_draw + delta / draw_time, 1.0)
	_draw_arrow.visible = true
	if _draw >= 1.0:
		_loose()

func _formation_point() -> Vector3:
	var offset := Vector3(1.55, 0.0, 1.85).rotated(Vector3.UP, player.visual.rotation.y)
	return player.global_position + offset

func _follow(delta: float) -> void:
	_cancel_draw()
	var goal: Vector3 = _formation_point()
	var gap: float = flat_distance_to_point(goal)
	if gap <= 0.8:
		move_with(Vector3.ZERO)
		model.loop("idle")
		return
	var next: Vector3 = Nav.next_point(self, goal, _nav, delta, 0.35)
	var dir: Vector3 = next - global_position
	dir.y = 0.0
	face(global_position + dir, 0.24)
	var speed: float = minf(MOVE_SPEED, maxf(2.2, gap * 1.5))
	move_with(dir.normalized() * speed)
	model.loop("run" if speed > 3.5 else "walk", clampf(speed / (4.4 if speed > 3.5 else 1.8), 0.8, 1.25))

func _reposition(_delta: float, dir: Vector3) -> void:
	_cancel_draw()
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	face(target.global_position, 0.28)
	move_with(dir.normalized() * MOVE_SPEED * 0.72)
	model.loop("walk", 1.12)

func _valid_target(enemy: Enemy) -> bool:
	return enemy != null and is_instance_valid(enemy) and not enemy.dead and enemy.is_aggro() and enemy.target == player \
		and flat_distance_to(enemy) <= RANGE * 1.25

func _random_threat() -> Enemy:
	var choices: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if _valid_target(enemy):
			choices.append(enemy)
	return choices.pick_random() if not choices.is_empty() else null

func _line_to(enemy: Enemy) -> bool:
	var from: Vector3 = global_position + Vector3(0, 1.35, 0)
	var to: Vector3 = enemy.global_position + Vector3(0, enemy.body_height * 0.62, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _loose() -> void:
	var from: Vector3 = global_position + Vector3(0, 1.35, 0) - visual.global_basis.z * 0.32
	var aim: Vector3 = target.global_position + Vector3(0, target.body_height * 0.62, 0)
	# A small physical lead keeps the arrow honest against moving enemies without homing after release.
	aim += target.velocity * clampf(from.distance_to(aim) / CompanionArrow.SPEED, 0.0, 0.45)
	var arrow: CompanionArrow = CompanionArrow.fire(get_parent(), self, from, aim,
		DAMAGE * (TAKE_AIM_MULT if take_aim_armed else 1.0), take_aim_armed)
	arrow.tree_exiting.connect(func() -> void:
		if arrow.struck is Enemy:
			last_hit_target = arrow.struck as Enemy)
	shots_fired += 1
	_draw = 0.0
	_draw_arrow.visible = false
	_cooldown = SHOT_COOLDOWN + randf_range(0.0, 0.22)

func arm_take_aim() -> void:
	if take_aim_armed or dead or stun_time > 0.0:
		return
	take_aim_armed = true
	Fx.text_at(self, global_position + Vector3(0.0, 2.25, 0.0), "Take Aim", Color(1.0, 0.58, 0.18), 30)
	SkillFx.take_aim_ready(self, global_position + Vector3(0.0, 1.35, 0.0) - visual.global_basis.z * 0.38)

func _is_take_aim_assigned_to_bar() -> bool:
	if player == null or player.skills == null:
		return false
	return HotbarLayout.where(player.skills.hotbar, player.skills.right_click_skill, "take_aim") != HotbarLayout.NONE

func spend_take_aim() -> void:
	take_aim_armed = false
	take_aim_reload_required = player.stats.power_recharge_damage(TAKE_AIM_COMBAT_SECONDS)
	take_aim_reload_remaining = take_aim_reload_required

func gain_take_aim_charge(damage: float) -> void:
	take_aim_reload_remaining = maxf(take_aim_reload_remaining - maxf(damage, 0.0), 0.0)

func _cancel_draw() -> void:
	_draw = move_toward(_draw, 0.0, 0.18)
	if _draw <= 0.02 and _draw_arrow != null:
		_draw_arrow.visible = false

func _apply_draw_pose() -> void:
	if _skeleton == null or _draw <= 0.01:
		return
	var weight: float = smoothstep(0.0, 0.75, _draw)
	_pose("Spine02", Vector3(0.0, -0.12, 0.0), weight)
	var forward: Vector3 = -visual.global_basis.z.normalized()
	var side: Vector3 = visual.global_basis.x.normalized()
	var chest: Vector3 = global_position + Vector3.UP * 1.36
	# Bow arm straight toward the shot; string hand pulls back beside the jaw. Iterating each chain twice settles the elbow cleanly.
	_aim_chain(["LeftArm", "LeftForeArm"], "LeftHand", chest + forward * 0.58 - side * 0.12, weight)
	_aim_chain(["RightArm", "RightForeArm"], "RightHand", chest - forward * 0.02 + side * 0.34, weight)

func _aim_chain(chain: Array[String], hand_name: String, target_world: Vector3, weight: float) -> void:
	var hand: int = int(_pose_bones.get(hand_name, -1))
	if hand < 0:
		return
	var target_local: Vector3 = _skeleton.to_local(target_world)
	for iteration in 2:
		for name in chain:
			var bone: int = int(_pose_bones.get(name, -1))
			if bone < 0:
				continue
			var pivot: Vector3 = _skeleton.get_bone_global_pose(bone).origin
			var hand_pos: Vector3 = _skeleton.get_bone_global_pose(hand).origin
			var current: Vector3 = hand_pos - pivot
			var wanted: Vector3 = target_local - pivot
			if current.length_squared() < 0.0001 or wanted.length_squared() < 0.0001:
				continue
			var world_delta := Basis(Quaternion(current.normalized(), wanted.normalized()))
			var parent: int = _skeleton.get_bone_parent(bone)
			var parent_basis: Basis = _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
			var local_delta: Quaternion = Quaternion(parent_basis.inverse() * world_delta * parent_basis)
			var applied: Quaternion = Quaternion.IDENTITY.slerp(local_delta, weight * 0.72)
			_skeleton.set_bone_pose_rotation(bone, applied * _skeleton.get_bone_pose_rotation(bone))

func _pose(name: String, euler: Vector3, weight: float) -> void:
	var index: int = int(_pose_bones.get(name, -1))
	if index < 0:
		return
	var base: Quaternion = _skeleton.get_bone_pose_rotation(index)
	var layer := Quaternion.from_euler(euler)
	_skeleton.set_bone_pose_rotation(index, base * Quaternion.IDENTITY.slerp(layer, weight))
