class_name BrutalAttackFx
extends Node3D
## Take Aim keeps the shared DS2 amber wisps. Brutal Attack's full crimson
## presentation is an explicit owner-approved departure (2026-10-16).
## The owner's special overhead swing and miss-preserves-power rules remain in SkillController.

const BODY_BONES := ["Hips", "Spine", "Spine01", "Spine02", "Neck", "Head", "LeftArm", "RightArm",
	"LeftForeArm", "RightForeArm", "LeftHand", "RightHand", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]
var skeleton: Skeleton3D
var emitters: Dictionary = {}
var crimson: bool = false

static func rank_color(rank: int) -> Color:
	# Approved crimson replacement for DS2's 9E5D33 / BC5900 / 8F2808 palette.
	return [Color("d61036"), Color("ef2546"), Color("ff5367")][clampi(rank, 1, 3) - 1]

static func rank_scale(rank: int) -> float:
	return 1.0 if rank <= 1 else clampi(rank, 2, 3) * 0.6

func setup(model: CharacterModel, gather: bool = true) -> void:
	crimson = gather # The separate Take Aim caller explicitly passes false.
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for bone_name in BODY_BONES:
		var bone: int = skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var wisp := CPUParticles3D.new()
		wisp.name = bone_name + "Wisp"
		wisp.amount = 6 if crimson else 4
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
		wisp.mesh = _soft_quad(Vector2(0.09, 0.28), Color(1.0, 0.08, 0.15, 0.8)) if crimson else _soft_quad(Vector2(0.06, 0.18), Color(0.82, 0.32, 0.05, 0.28))
		wisp.scale_amount_min = 0.65
		wisp.scale_amount_max = 1.15
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.04, 0.15, 0.0) if crimson else Color(0.74, 0.35, 0.07, 0.0))
		ramp.add_point(0.15, Color(1.0, 0.15, 0.24, 0.82) if crimson else Color(0.82, 0.42, 0.10, 0.24))
		ramp.set_color(1, Color(0.40, 0.0, 0.04, 0.0) if crimson else Color(0.30, 0.15, 0.06, 0.0))
		wisp.color_ramp = ramp
		add_child(wisp)
		wisp.top_level = true   # Rig units/scale must not enlarge the steam.
		emitters[bone] = wisp
	model.anim.mixer_applied.connect(update_pose)
	update_pose()
	if gather:
		_gather()
		var energy := BrutalCrimsonFx.new()
		add_child(energy)
		energy.setup(get_parent() as Player)

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
	gather.amount = 48
	gather.one_shot = true
	gather.explosiveness = 1.0
	gather.lifetime = 0.45
	gather.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	gather.emission_sphere_radius = 1.35
	gather.radial_accel_min = -20.0
	gather.radial_accel_max = -20.0
	gather.initial_velocity_min = 0.0
	gather.initial_velocity_max = 0.0
	gather.gravity = Vector3.ZERO
	gather.mesh = _soft_quad(Vector2(0.10, 0.24), Color(1.0, 0.04, 0.12, 0.8))
	gather.color = Color(1.0, 0.06, 0.20, 0.8)
	add_child(gather)
	gather.position.y = 1.0
	gather.finished.connect(gather.queue_free)

static func impact(from: Node, point: Vector3, direction: Vector3, rank: int) -> void:
	BrutalCrimsonFx.impact(from, point, direction, rank)
