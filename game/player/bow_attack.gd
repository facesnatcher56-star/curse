class_name BowAttack
extends RefCounted
## Shared bow attack and the existing procedural archery presentation, for either member.
const BOW_MODEL := "res://assets/models/archer/bow/model.glb"
const QUIVER_MODEL := "res://assets/models/archer/quiver/model.glb"
const ARROW_MODEL := "res://assets/models/archer/arrow/model.glb"
var p: Player
var _draw: float = 0.0
var _release: float = 0.0
var _recovery: float = 1.05
var armed: bool = false
var reload_required: float = 0.0
var reload_remaining: float = 0.0
var _draw_arrow: Node3D
var _bow_holder: Node3D
var _quiver: Node3D
var _string_upper: MeshInstance3D
var _string_lower: MeshInstance3D
var _skeleton: Skeleton3D
var _pose_bones: Dictionary = {}
var _bow_scale: float
var _arrow_rest: Transform3D
var aura: BrutalAttackFx

func _init(character: Player) -> void:
	p = character

func attach() -> void:
	_attach_gear()
	_skeleton = p.model.find_children("*", "Skeleton3D", true, false)[0]
	for bone_name in ["Spine02", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
		_pose_bones[bone_name] = _skeleton.find_bone(bone_name)
	p.model.anim.mixer_applied.connect(_apply_draw_pose)

func detach() -> void:
	cancel()
	if p.model.anim.mixer_applied.is_connected(_apply_draw_pose):
		p.model.anim.mixer_applied.disconnect(_apply_draw_pose)
	for node in [_bow_holder, _quiver, _draw_arrow, _string_upper, _string_lower, aura]:
		if is_instance_valid(node): node.queue_free()

func disarm() -> void:
	armed = false
	if is_instance_valid(aura): aura.queue_free()

func arm() -> void:
	if not p.stats.can_use("take_aim") or armed: return
	armed = true
	aura = BrutalAttackFx.new()
	p.add_child(aura)
	aura.setup(p.model, false)

func start(target: Actor) -> void:
	if not is_instance_valid(target) or target.dead or not p.stats.is_ranged() or not Nav.line_clear(p, target.global_position): return
	p.skills.busy = true
	p.skills.busy_skill = "basic"
	p.skills.busy_target = target
	p.skills.busy_def = {"kind": "ranged", "charged": false}
	p.skills.busy_t = 0.0
	p.skills.busy_hit_done = false
	p.skills.busy_time = (0.92 if armed else 0.62) / p.stats.attack_speed()
	_recovery = (1.05 + randf_range(0.0, 0.22)) / p.stats.attack_speed()
	p.movement.has_goal = false
	p.combat_timer = 5.0
	p.face(target.global_position)
	p.model.loop("idle_alert")
	_draw = 0.0
	if armed:
		SkillFx.take_aim_charge(_bow_holder)
		Sfx.power(p, "take_aim_charge")

func tick(delta: float) -> void:
	if not is_instance_valid(p.skills.busy_target) or p.skills.busy_target.dead:
		cancel()
		return
	p.skills.busy_t += delta
	if not p.skills.busy_hit_done:
		p.face(p.skills.busy_target.global_position, 0.28)
		_draw = clampf(p.skills.busy_t / p.skills.busy_time, 0.0, 1.0)
		_draw_arrow.visible = true
		if _draw >= 1.0: loose()
	elif p.skills.busy_t >= p.skills.busy_time + _recovery:
		p.skills.busy = false
	_release = maxf(_release - delta, 0.0)
	_apply_draw_pose()

func loose() -> void:
	_apply_draw_pose()
	var target := p.skills.busy_target
	var from := p.global_position + Vector3(0, 1.45, 0)
	var box: AABB = _draw_arrow.get_meta("mesh_bounds")
	from = _draw_arrow.to_global(Vector3(0, box.size.y * 0.5, 0))
	var aim := target.global_position + Vector3(0, target.body_height * 0.62, 0)
	aim += target.velocity * clampf(from.distance_to(aim) / (CompanionArrow.SPEED * (2.0 if armed else 1.0)), 0, 0.45)
	var damage := p.stats.ranged_range()
	var multiplier := PowerDb.hero_value("take_aim", "damage_pct", p.member_id) / 100.0 if armed else 1.0
	CompanionArrow.fire(p.get_parent(), p, from, aim, randf_range(damage.x, damage.y) * multiplier, armed)
	if armed:
		Sfx.power(p, "take_aim_fire")
		reload_required = p.stats.power_recharge_damage(PowerDb.get_def("take_aim").recharge, "ranged")
		reload_remaining = reload_required
		armed = false
		if is_instance_valid(aura): aura.queue_free()
	p.skills.busy_hit_done = true
	_draw = 0.0
	_release = 0.20
	_draw_arrow.visible = false
	_set_bow_string_visible(false)

func cancel() -> void:
	_draw = 0.0
	_release = 0.0
	p.skills.busy = false
	if is_instance_valid(_draw_arrow): _draw_arrow.visible = false
	_set_bow_string_visible(false)

func _attach_gear() -> void:
	# Blender Z exports as Godot Y, so the bow is already upright. Rotating it
	# another quarter-turn made Cutter carry and draw it like a staff.
	_bow_holder = _attach_prop(BOW_MODEL, "LeftHand", 1.58, Basis.IDENTITY, Vector3(0.0, 0.02, 0.02))
	# The imported quiver is already upright along +Y. Keep it aligned with the spine and add only a slight shoulder cant.
	var quiver_basis := Basis(Vector3.FORWARD, -0.16)
	_quiver = _attach_prop(QUIVER_MODEL, "Spine02", 0.78, quiver_basis, Vector3(-0.14, -0.08, 0.08))
	_draw_arrow = _attach_prop(ARROW_MODEL, "RightHand", 0.92, Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.02, 0.02))
	_draw_arrow.visible = false
	_bow_scale = _bow_holder.global_basis.get_scale().x
	_arrow_rest = _draw_arrow.transform
	_string_upper = _make_bow_cord()
	_string_lower = _make_bow_cord()
	p.add_child(_string_upper)
	p.add_child(_string_lower)

func _attach_prop(path: String, bone: String, size: float, prop_basis: Basis, offset: Vector3) -> Node3D:
	var prop: Node3D = (load(path) as PackedScene).instantiate()
	LootDrop._use_vertex_colours(prop)
	var box: AABB = CharacterModel._bounds_of(prop)
	var extent: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	var skeleton: Skeleton3D = p.model.find_children("*", "Skeleton3D", true, false)[0]
	var rig_scale: float = skeleton.global_transform.basis.get_scale().x
	var holder := Node3D.new()
	holder.position = offset
	holder.basis = prop_basis.scaled(Vector3.ONE * size / maxf(extent * rig_scale, 0.001))
	p.model._mount_for(bone).add_child(holder)
	holder.add_child(prop)
	prop.position = -box.get_center()
	holder.set_meta("mesh_bounds", box)
	return holder

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
	var forward: Vector3 = p.visual.global_basis.z.normalized()   # Actor.face uses +Z.
	var side: Vector3 = p.visual.global_basis.x.normalized()
	var chest: Vector3 = p.global_position + Vector3.UP * 1.36
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
	var forward: Vector3 = p.visual.global_basis.z.normalized()
	var side: Vector3 = p.visual.global_basis.x.normalized()
	var carry_hand: Vector3 = p.global_position + Vector3.UP * 1.0 + side * 0.42 + forward * 0.12
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
