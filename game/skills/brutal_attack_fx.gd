class_name BrutalAttackFx
extends Node3D
## DS2's shared Brutal Attack / Take Aim pre-launch presentation: bone-following
## amber wisps. Brutal Attack also uses the inward charge and impact cones.
## The owner's special overhead swing and miss-preserves-power rules remain in SkillController.

const BODY_BONES := ["Hips", "Spine", "Spine01", "Spine02", "Neck", "Head", "LeftArm", "RightArm",
	"LeftForeArm", "RightForeArm", "LeftHand", "RightHand", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]
var skeleton: Skeleton3D
var emitters: Dictionary = {}

static func rank_color(rank: int) -> Color:
	# efct_brutal_attack.gas: 9E5D33 / BC5900 / 8F2808.
	return [Color("9e5d33"), Color("bc5900"), Color("8f2808")][clampi(rank, 1, 3) - 1]

static func rank_scale(rank: int) -> float:
	return 1.0 if rank <= 1 else clampi(rank, 2, 3) * 0.6

func setup(model: CharacterModel, gather: bool = true) -> void:
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for bone_name in BODY_BONES:
		var bone: int = skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var wisp := CPUParticles3D.new()
		wisp.name = bone_name + "Wisp"
		wisp.amount = 4
		wisp.lifetime = 0.65
		wisp.randomness = 0.65
		wisp.local_coords = false
		wisp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		wisp.emission_sphere_radius = 0.055
		wisp.direction = Vector3.UP
		wisp.spread = 14.0
		wisp.initial_velocity_min = 0.12
		wisp.initial_velocity_max = 0.28
		wisp.gravity = Vector3(0.0, 0.04, 0.0)
		wisp.mesh = _soft_quad(Vector2(0.06, 0.18), Color(0.82, 0.32, 0.05, 0.28))
		wisp.scale_amount_min = 0.65
		wisp.scale_amount_max = 1.15
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.74, 0.35, 0.07, 0.0))
		ramp.add_point(0.15, Color(0.82, 0.42, 0.10, 0.24))
		ramp.set_color(1, Color(0.30, 0.15, 0.06, 0.0))
		wisp.color_ramp = ramp
		add_child(wisp)
		wisp.top_level = true   # Rig units/scale must not enlarge the steam.
		emitters[bone] = wisp
	model.anim.mixer_applied.connect(update_pose)
	update_pose()
	if gather:
		_gather()

func _process(_delta: float) -> void:
	update_pose()   # Also follow actor movement when the animation is held/hit-stopped.

func update_pose() -> void:
	if not is_instance_valid(skeleton):
		return
	var centre: Vector3 = global_position + Vector3.UP * 1.0
	for bone in emitters:
		var at: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
		var outward: Vector3 = (at - centre).normalized()
		(emitters[bone] as CPUParticles3D).global_position = at + outward * 0.055

static func _soft_quad(size: Vector2, tint: Color = Color(0.95, 0.72, 0.36, 0.75)) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	# A warm translucent base also bounds the first particles before their ramp updates.
	mat.albedo_color = tint
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	return quad

func _gather() -> void:
	# DS2's short inward shell charge; presentation never delays activation.
	var gather := CPUParticles3D.new()
	gather.name = "ChargeGather"
	gather.amount = 18
	gather.one_shot = true
	gather.explosiveness = 1.0
	gather.lifetime = 0.35
	gather.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	gather.emission_sphere_radius = 0.85
	gather.radial_accel_min = -14.0
	gather.radial_accel_max = -14.0
	gather.initial_velocity_min = 0.0
	gather.initial_velocity_max = 0.0
	gather.gravity = Vector3.ZERO
	gather.mesh = _soft_quad(Vector2(0.06, 0.12))
	gather.color = Color(0.65, 0.28, 0.07, 0.3)
	add_child(gather)
	gather.position.y = 1.0
	gather.finished.connect(gather.queue_free)

static func impact(from: Node, point: Vector3, direction: Vector3, rank: int) -> void:
	if not Fx.claim_impact("brutal_attack", point):
		return
	var dir: Vector3 = direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD
	var colour: Color = rank_color(rank)
	var size: float = rank_scale(rank)
	var contact: Vector3 = point + Vector3.UP * 0.85
	Fx.light_flash(from, contact, colour, 2.5, 0.11)
	# DS2 sends rays both away from the victim and back toward the attacker.
	Fx.burst(from, contact, dir + Vector3.UP * 0.12, colour, 16, 9.0 * size, 0.023, true)
	Fx.burst(from, contact, -dir + Vector3.UP * 0.20, colour, 10, 4.0 * size, 0.020, true)
	Fx.burst(from, contact, dir + Vector3.UP * 0.3, Color(0.16, 0.10, 0.07), 12, 6.0, 0.04)
	for i in 3:
		_cone(from, contact, dir, colour, size, i)
	Fx.shake(from, 0.22)
	Fx.punch(from, 3.2)
	Fx.kick(from, dir, 0.7)

static func _cone(from: Node, contact: Vector3, dir: Vector3, colour: Color, size: float, index: int) -> void:
	# Open cone/ring perpendicular to the blow, never an area-damage ground circle.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius: float = 0.10 + index * 0.045
	for i in 24:
		var a: float = TAU * i / 24.0
		var b: float = TAU * (i + 1) / 24.0
		var inner_a := Vector3(cos(a), 0.0, sin(a)) * radius * 0.5
		var inner_b := Vector3(cos(b), 0.0, sin(b)) * radius * 0.5
		var outer_a := Vector3(cos(a) * radius, 0.12, sin(a) * radius)
		var outer_b := Vector3(cos(b) * radius, 0.12, sin(b) * radius)
		for vertex in [inner_a, outer_a, outer_b, inner_a, outer_b, inner_b]:
			surface.set_color(Color(colour, 0.0 if is_zero_approx(vertex.y) else 0.32))
			surface.add_vertex(vertex)
	var cone := MeshInstance3D.new()
	cone.name = "BrutalImpactCone"
	cone.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material_override = mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(cone)
	cone.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), contact - dir * 0.15)
	var tween := cone.create_tween().set_parallel(true)
	tween.tween_property(cone, "scale", Vector3.ONE * (3.0 + index) * size, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.40)
	tween.chain().tween_callback(cone.queue_free)
