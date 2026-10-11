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
const MOVE_SPEED := 4.5
const RANGE := 17.0
const MIN_COMBAT_RANGE := 8.0
const PREFERRED_COMBAT_RANGE := 12.0
const DRAW_TIME := 0.62
const SHOT_COOLDOWN := 1.05
## Take Aim's arrow multiplier (DS2: 1500 + 25 x Ranged %). CURSE CHOICE: Cutter buys no passives, so his Take Aim stays at rank 1, its
## damage growing with his own Ranged level.
static func take_aim_mult() -> float:
	return PowerDb.get_def("take_aim").value("damage_pct", 1, {"ranged": HeroAttributes.class_level(TownState.cutter_xp)}) / 100.0
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
var _bow_holder: Node3D
var _string_upper: MeshInstance3D
var _string_lower: MeshInstance3D
var _skeleton: Skeleton3D
var _pose_bones: Dictionary = {}
var _release: float = 0.0
var _bow_scale: float
var _arrow_rest: Transform3D
var _take_aim_aura: BrutalAttackFx

func setup(hero: Player) -> void:
	player = hero
	global_position = hero.global_position + Vector3(1.8, 0.0, 1.6)

func _ready() -> void:
	add_to_group("companions")
	display_name = "Cutter"
	refresh_level()   # a DS2 party member: his level, attributes, life and armour from his own XP (TownState.cutter_xp)
	health = max_health
	impalable = false
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	_build_model(MODEL_DIR, CLIPS, 1.8, 0.38)
	model.loop("idle")
	_attach_gear()
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for bone_name in ["Spine02", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
		_pose_bones[bone_name] = _skeleton.find_bone(bone_name)
	model.anim.mixer_applied.connect(_apply_draw_pose)

## Cutter levels with the hero's kills (his share, see RunDirector._pay_kill_xp), all of it Ranged: his character level is his combat
## level, his Ranged class level his attributes (HeroAttributes) and so his life; he wears a ranger's on-level armour (DS2: the armour
## budget `16 + 4L` x 0.8 over a full set). The share of life he has left stays.
func refresh_level() -> void:
	level = HeroProgression.level_for_xp(TownState.cutter_xp)
	var attr: Vector3 = HeroAttributes.attributes({"ranged": HeroAttributes.class_level(TownState.cutter_xp)})
	var share: float = health / maxf(max_health, 1.0)
	max_health = HeroAttributes.max_life(attr)
	health = max_health * clampf(share, 0.0, 1.0)
	armor = (16.0 + 4.0 * level) * 0.8
	_dexterity = attr.y

var _dexterity: float = 11.0

## One arrow: a DS2 bow of his level (`3.0 + 0.65 L` on average) plus 0.2 x DEX, 0.75 of that on the low roll and 1.25 on the high.
func arrow_damage() -> float:
	var damage := arrow_damage_range()
	return randf_range(damage.x, damage.y)

func arrow_damage_range() -> Vector2:
	var bow: float = 3.0 + 0.65 * level
	var bonus: float = 0.2 * maxf(_dexterity, 10.0)
	return Vector2(bow * 0.75 + 0.75 * bonus, bow * 1.25 + 1.25 * bonus)

func _attach_gear() -> void:
	# Blender Z exports as Godot Y, so the bow is already upright. Rotating it
	# another quarter-turn made Cutter carry and draw it like a staff.
	_bow_holder = _attach_prop(BOW_MODEL, "LeftHand", 1.58, Basis.IDENTITY, Vector3(0.0, 0.02, 0.02))
	# The imported quiver is already upright along +Y. Keep it aligned with the spine and add only a slight shoulder cant.
	var quiver_basis := Basis(Vector3.FORWARD, -0.16)
	_attach_prop(QUIVER_MODEL, "Spine02", 0.78, quiver_basis, Vector3(-0.14, -0.08, 0.08))
	_draw_arrow = _attach_prop(ARROW_MODEL, "RightHand", 0.92, Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.02, 0.02))
	_draw_arrow.visible = false
	_bow_scale = _bow_holder.global_basis.get_scale().x
	_arrow_rest = _draw_arrow.transform
	_string_upper = _make_bow_cord()
	_string_lower = _make_bow_cord()
	add_child(_string_upper)
	add_child(_string_lower)

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
	holder.set_meta("mesh_bounds", box)
	return holder

func _physics_process(delta: float) -> void:
	if dead:
		_clear_take_aim_visual()
	if testing_disabled or player == null or not is_instance_valid(player) or player.dead:
		move_with(Vector3.ZERO)
		model.loop("idle")
		return
	var frozen: bool = _actor_tick(delta)
	if frozen or dead or stun_time > 0.0:
		move_with(Vector3.ZERO)
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_release = maxf(_release - delta, 0.0)
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
		if _draw > 0.0:
			_cancel_draw()
		return
	if not take_aim_armed and take_aim_reload_remaining <= 0.0 and not _is_take_aim_assigned_to_bar():
		arm_take_aim()
	var draw_time: float = TAKE_AIM_DRAW_TIME if take_aim_armed else DRAW_TIME
	if take_aim_armed and is_zero_approx(_draw):
		SkillFx.take_aim_charge(_bow_holder)
		Sfx.power(self, "take_aim_charge")
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
	# Evaluate the contact pose before spawning: physics may run before the mixer.
	_apply_draw_pose()
	var box: AABB = _draw_arrow.get_meta("mesh_bounds")
	var from: Vector3 = _draw_arrow.to_global(Vector3(0.0, box.size.y * 0.5, 0.0))
	var aim: Vector3 = target.global_position + Vector3(0, target.body_height * 0.62, 0)
	# A small physical lead keeps the arrow honest against moving enemies without homing after release.
	var flight_speed: float = CompanionArrow.SPEED * (2.0 if take_aim_armed else 1.0)
	aim += target.velocity * clampf(from.distance_to(aim) / flight_speed, 0.0, 0.45)
	var arrow: CompanionArrow = CompanionArrow.fire(get_parent(), self, from, aim,
		arrow_damage() * (take_aim_mult() if take_aim_armed else 1.0), take_aim_armed)
	if take_aim_armed:
		Sfx.power(self, "take_aim_fire")
		spend_take_aim()   # DS2 starts reloading at release, even if the arrow never hits.
	arrow.tree_exiting.connect(func() -> void:
		if arrow.struck is Enemy:
			last_hit_target = arrow.struck as Enemy)
	shots_fired += 1
	_draw = 0.0
	_release = 0.20
	_draw_arrow.visible = false
	_set_bow_string_visible(false)
	_cooldown = SHOT_COOLDOWN + randf_range(0.0, 0.22)

func arm_take_aim() -> void:
	if take_aim_armed or dead or stun_time > 0.0:
		return
	take_aim_armed = true
	Fx.text_at(self, global_position + Vector3(0.0, 2.25, 0.0), "Take Aim", Color(1.0, 0.58, 0.18), 30)
	# active_skills.gas uses the same body pre-launch FFX as Brutal Attack.
	_take_aim_aura = BrutalAttackFx.new()
	_take_aim_aura.name = "TakeAimAura"
	add_child(_take_aim_aura)
	_take_aim_aura.setup(model, false)

func _clear_take_aim_visual() -> void:
	if is_instance_valid(_take_aim_aura):
		_take_aim_aura.queue_free()
	_take_aim_aura = null

## A party power interrupts Cutter's ordinary shot job immediately. If he just
## fired, it also bypasses that ordinary-shot recovery; the power never queues.
func activate_take_aim_now() -> void:
	if dead or stun_time > 0.0 or take_aim_armed:
		return
	_cancel_draw(true)
	_cooldown = 0.0
	if not _valid_target(target):
		target = _random_threat()
	arm_take_aim()

func _is_take_aim_assigned_to_bar() -> bool:
	if player == null or player.skills == null:
		return false
	return HotbarLayout.where(player.skills.hotbar, player.skills.right_click_skill, "take_aim") != HotbarLayout.NONE

func spend_take_aim() -> void:
	take_aim_armed = false
	_clear_take_aim_visual()
	take_aim_reload_required = player.stats.power_recharge_damage(TAKE_AIM_COMBAT_SECONDS, "ranged", self)
	take_aim_reload_remaining = take_aim_reload_required

func gain_take_aim_charge(damage: float) -> void:
	take_aim_reload_remaining = maxf(take_aim_reload_remaining - maxf(damage, 0.0), 0.0)

func _cancel_draw(immediate: bool = false) -> void:
	_release = 0.0
	_draw = 0.0 if immediate else move_toward(_draw, 0.0, 0.18)
	if _draw <= 0.02 and _draw_arrow != null:
		_draw_arrow.visible = false
		_set_bow_string_visible(false)

func _make_bow_cord() -> MeshInstance3D:
	var cord := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.006
	mesh.bottom_radius = 0.006
	mesh.height = 1.0
	mesh.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.22, 0.16, 0.09)
	mesh.material = mat
	cord.mesh = mesh
	cord.top_level = true
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cord.visible = false
	return cord

func _set_cord(cord: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta: Vector3 = b - a
	var length: float = delta.length()
	if length <= 0.001:
		cord.visible = false
		return
	var y_axis: Vector3 = delta / length
	var x_axis: Vector3 = y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	cord.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis).scaled(Vector3(1.0, length, 1.0)), (a + b) * 0.5)
	cord.visible = true

func _update_bow_string() -> void:
	if _bow_holder == null or _draw_arrow == null:
		_set_bow_string_visible(false)
		return
	var upper: Vector3 = _bow_holder.to_global(Vector3(0.065, 0.78, 0.0))
	var lower: Vector3 = _bow_holder.to_global(Vector3(0.065, -0.78, 0.0))
	var box: AABB = _draw_arrow.get_meta("mesh_bounds")
	var nock: Vector3 = _draw_arrow.to_global(Vector3(0.0, -box.size.y * 0.5, 0.0)) if _draw > 0.01 else (upper + lower) * 0.5
	_set_cord(_string_upper, upper, nock)
	_set_cord(_string_lower, nock, lower)

func _set_bow_string_visible(on: bool) -> void:
	if _string_upper != null:
		_string_upper.visible = on
	if _string_lower != null:
		_string_lower.visible = on

func _apply_draw_pose() -> void:
	if _skeleton == null:
		return
	if _draw <= 0.01 and _release <= 0.0:
		_draw_arrow.top_level = false
		_draw_arrow.transform = _arrow_rest
		_draw_arrow.visible = false
		_apply_carry_pose()
		_update_bow_string()
		return
	var weight: float = smoothstep(0.0, 0.20, _draw) if _release <= 0.0 else smoothstep(0.0, 0.10, _release)
	_pose("Spine02", Vector3(0.0, -0.12, 0.0), weight)
	var forward: Vector3 = visual.global_basis.z.normalized()   # Actor.face uses +Z.
	var side: Vector3 = visual.global_basis.x.normalized()
	var chest: Vector3 = global_position + Vector3.UP * 1.36
	var pull: float = smoothstep(0.18, 0.92, _draw)
	var bow_hand: Vector3 = chest + Vector3.UP * 0.10 + forward * 0.56 + side * 0.16
	var string_hand: Vector3 = bow_hand.lerp(chest + Vector3.UP * 0.13 + side * 0.16 - forward * 0.06, pull)
	if _release > 0.0:
		string_hand = chest + Vector3.UP * 0.13 + side * 0.28 - forward * 0.14
	_aim_chain(["LeftArm", "LeftForeArm"], "LeftHand", bow_hand, weight)
	_aim_chain(["RightArm", "RightForeArm"], "RightHand", string_hand, weight)
	# Props follow the solved hands, not detached ideal coordinates.
	bow_hand = _skeleton.to_global(_skeleton.get_bone_global_pose(int(_pose_bones["LeftHand"])).origin)
	string_hand = _skeleton.to_global(_skeleton.get_bone_global_pose(int(_pose_bones["RightHand"])).origin)
	_present_draw_props(bow_hand, string_hand, forward)
	_update_bow_string()

## Keep the bow upright beside the hip, rather than rotating it with the generic
## unarmed walk/run palm. Legs, torso and the free arm retain their locomotion.
func _apply_carry_pose() -> void:
	var forward: Vector3 = visual.global_basis.z.normalized()
	var side: Vector3 = visual.global_basis.x.normalized()
	var carry_hand: Vector3 = global_position + Vector3.UP * 1.0 + side * 0.42 + forward * 0.12
	_aim_chain(["LeftArm", "LeftForeArm"], "LeftHand", carry_hand, 1.0)
	var hand: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(int(_pose_bones["LeftHand"])).origin)
	var bow_y: Vector3 = (Vector3.UP + forward * 0.22).normalized()
	var bow_x: Vector3 = side.cross(bow_y).normalized()
	var bow_z: Vector3 = bow_x.cross(bow_y).normalized()
	_bow_holder.top_level = true
	_bow_holder.global_transform = Transform3D(Basis(bow_x, bow_y, bow_z).scaled(Vector3.ONE * _bow_scale), hand + bow_x * 0.065 * _bow_scale)

## The recruit rig has no authored bow clip, and its idle hand transforms do not
## carry props in an archery pose. During the draw, place the equipment from the
## same three physical points an archer uses: bow hand, string hand, arrow tip.
func _present_draw_props(bow_hand: Vector3, nock: Vector3, forward: Vector3) -> void:
	if _bow_holder == null or _draw_arrow == null:
		return
	var bow_scale: float = maxf(_bow_holder.global_basis.get_scale().x, 0.001)
	var arrow_scale: float = maxf(_draw_arrow.global_basis.get_scale().x, 0.001)
	# BoneAttachment updates later in the skeleton pass. World-space presentation
	# must not inherit that second transform after already following solved hands.
	_bow_holder.top_level = true
	_draw_arrow.top_level = true
	var bow_centre: Vector3 = bow_hand + forward * 0.065 * bow_scale
	var arrow_dir: Vector3 = (bow_hand + forward * 0.38 - nock).normalized()
	# Bow bends in its X/Y plane; arrow was exported with its shaft along +Y.
	var bow_x: Vector3 = forward
	var bow_y: Vector3 = Vector3.UP
	var bow_z: Vector3 = bow_x.cross(bow_y).normalized()
	_bow_holder.global_transform = Transform3D(Basis(bow_x, bow_y, bow_z).scaled(Vector3.ONE * bow_scale), bow_centre)
	var arrow_x: Vector3 = arrow_dir.cross(Vector3.UP).normalized()
	var arrow_z: Vector3 = arrow_x.cross(arrow_dir).normalized()
	var box: AABB = _draw_arrow.get_meta("mesh_bounds")
	_draw_arrow.global_transform = Transform3D(Basis(arrow_x, arrow_dir, arrow_z).scaled(Vector3.ONE * arrow_scale), nock + arrow_dir * box.size.y * arrow_scale * 0.5)

func _aim_chain(chain: Array[String], hand_name: String, target_world: Vector3, weight: float) -> void:
	var hand: int = int(_pose_bones.get(hand_name, -1))
	if hand < 0:
		return
	var start: Vector3 = _skeleton.get_bone_global_pose(hand).origin
	var target_local: Vector3 = start.lerp(_skeleton.to_local(target_world), weight)
	for iteration in 8:
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
			_skeleton.set_bone_pose_rotation(bone, local_delta * _skeleton.get_bone_pose_rotation(bone))

func _pose(name: String, euler: Vector3, weight: float) -> void:
	var index: int = int(_pose_bones.get(name, -1))
	if index < 0:
		return
	var base: Quaternion = _skeleton.get_bone_pose_rotation(index)
	var layer := Quaternion.from_euler(euler)
	_skeleton.set_bone_pose_rotation(index, base * Quaternion.IDENTITY.slerp(layer, weight))
