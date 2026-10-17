class_name BrutalCrimsonFx
extends Node3D
## Owner-approved blood-magic presentation, deliberately beyond the DS2 orange
## effect. All nodes are visual; combat timing and spend remain in SkillController.

const SHARD_PATH := "res://assets/fx/brutal_crimson_rupture.glb"
const GROUP := "brutal_crimson_impact"
const ENERGY_SHADER := preload("res://game/skills/brutal_crimson_energy.gdshader")
const FLOW_SHADER := preload("res://game/skills/brutal_weapon_flow.gdshader")
var body: Player
var _ribbons: Array[MeshInstance3D] = []
var _weapon_glow: MeshInstance3D
var _idle_materials: Array[ShaderMaterial] = []
var _flow_materials: Array[ShaderMaterial] = []
var _infusion_motes: Array[MeshInstance3D] = []
var _age := 0.0
static var _shard_mesh: ArrayMesh

func setup(owner_body: Player) -> void:
	body = owner_body
	name = "CrimsonGathering"
	process_priority = 110 # Follow the model's final animated weapon pose (priority 100).
	for strand in 3:
		var ribbon := MeshInstance3D.new()
		ribbon.name = "CrimsonVein%d" % strand
		ribbon.mesh = ImmediateMesh.new()
		ribbon.material_override = _blood_material(Color("f31643"))
		_idle_materials.append(ribbon.material_override as ShaderMaterial)
		var flow_material := ShaderMaterial.new()
		flow_material.shader = FLOW_SHADER
		_flow_materials.append(flow_material)
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ribbon)
		_ribbons.append(ribbon)
	_weapon_glow = MeshInstance3D.new()
	_weapon_glow.name = "CrimsonWeaponInfusion"
	_weapon_glow.mesh = ImmediateMesh.new()
	_weapon_glow.material_override = _energy(Color(1.0, 0.025, 0.10, 0.0), 1.5)
	(_weapon_glow.material_override as StandardMaterial3D).no_depth_test = true
	_weapon_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_weapon_glow)
	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.042
	mote_mesh.height = 0.084
	mote_mesh.radial_segments = 6
	mote_mesh.rings = 3
	# Bound HDR intensity so tonemapping keeps the particles crimson rather than orange.
	var mote_material := _energy(Color(0.75, 0.001, 0.08), 0.35)
	mote_material.no_depth_test = true
	for i in 30:
		var mote := MeshInstance3D.new()
		mote.name = "InfusionParticle%d" % i
		mote.mesh = mote_mesh
		mote.material_override = mote_material
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mote.visible = false
		add_child(mote)
		_infusion_motes.append(mote)

func infusion_duration() -> float:
	# Use the existing draw-back almost up to contact; never delay gameplay timing.
	return maxf(body.skills.busy_time * SkillController.hit_fraction(body.skills.busy_def) * 0.90, 0.001)

func infusion_fraction() -> float:
	if not is_instance_valid(body) or not body.skills.busy or not bool(body.skills.busy_def.get("brutal_animation", false)):
		return 0.0
	return clampf(body.skills.busy_t / infusion_duration(), 0.0, 1.0)

func mote_position(index: int, progress: float) -> Vector3:
	var angle := float(index) * 2.39996
	var source := Vector3(cos(angle) * 0.70, 0.25 + float(index % 7) * 0.23, sin(angle) * 0.70)
	var destination := to_local(body.model.weapon_base.global_position.lerp(body.model.weapon_tip.global_position, 0.35 + float(index % 6) * 0.12))
	var delay := float(index % 5) * 0.035
	var travel := pow(clampf((progress - delay) / (1.0 - delay), 0.0, 1.0), 1.4)
	return source.bezier_interpolate(source + Vector3.UP * 0.35, destination + Vector3.UP * 0.15, destination, travel)

func _draw_motes(infusion: float) -> void:
	for i in _infusion_motes.size():
		var mote := _infusion_motes[i]
		mote.visible = infusion > 0.0 and infusion < 1.0
		if not mote.visible: continue
		mote.position = mote_position(i, infusion)
		# Stay vivid and distinct while moving; shrink into the weapon at arrival.
		mote.scale = Vector3.ONE * (0.65 + float(i % 4) * 0.15) * (1.0 - smoothstep(0.88, 1.0, infusion))

## The weapon markers are shared with weapon trails and refreshed on equipment changes.
## Resolve them each frame so swords, axes and replacement weapons all receive the flow.
func weapon_destination(strand: int) -> Vector3:
	return to_local(body.model.weapon_base.global_position.lerp(body.model.weapon_tip.global_position, 0.35 + 0.25 * strand))

func _flow_point(u: float, strand: int, destination: Vector3, infusion: float) -> Vector3:
	var angle := TAU * float(strand) / 3.0 + _age * 0.35
	var source := Vector3(cos(angle) * 0.60, 0.35 + float(strand) * 0.48, sin(angle) * 0.60)
	var control := (source + destination) * 0.5 + Vector3.UP * 0.45
	var pulled_u := lerpf(infusion * 0.97, 1.0, u)
	var pulled := source.bezier_interpolate(control, control, destination, pulled_u)
	var orbit_angle := u * TAU * 0.72 + TAU * float(strand) / 3.0 + _age * 1.15
	var radius := 0.40 + sin(u * PI) * 0.22
	var orbit := Vector3(cos(orbit_angle) * radius, 0.18 + u * 1.65, sin(orbit_angle) * radius)
	return orbit.lerp(pulled, minf(infusion * 4.0, 1.0))

func _draw_flow(ribbon: MeshInstance3D, strand: int, destination: Vector3, width_axis: Vector3, infusion: float) -> void:
	var mesh := ribbon.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in 24:
		var u0 := float(step) / 24.0
		var u1 := float(step + 1) / 24.0
		var a := _flow_point(u0, strand, destination, infusion)
		var b := _flow_point(u1, strand, destination, infusion)
		var ribbon_axis := Vector3.UP.lerp(width_axis, minf(infusion * 4.0, 1.0))
		var w0 := ribbon_axis * (infusion * 0.018 + sin(u0 * PI) * 0.075)
		var w1 := ribbon_axis * (infusion * 0.018 + sin(u1 * PI) * 0.075)
		var vertices := [a - w0, a + w0, b + w1, a - w0, b + w1, b - w1]
		var coords := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), Vector2(u0, 0), Vector2(u1, 1), Vector2(u1, 0)]
		for i in 6:
			mesh.surface_set_normal((b - a).cross(ribbon_axis).normalized())
			mesh.surface_set_uv(coords[i])
			mesh.surface_add_vertex(vertices[i])
	mesh.surface_end()

func _draw_weapon_glow(width_axis: Vector3, infusion: float) -> void:
	var mesh := _weapon_glow.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if infusion <= 0.0: return
	var a := to_local(body.model.weapon_base.global_position)
	var b := to_local(body.model.weapon_tip.global_position)
	var width := width_axis * 0.060
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [a - width, a + width, b + width * 0.15, a - width, b + width * 0.15, b - width * 0.15]:
		mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	(_weapon_glow.material_override as StandardMaterial3D).albedo_color.a = infusion * 0.75

func _process(delta: float) -> void:
	_age += delta
	var has_weapon := is_instance_valid(body) and is_instance_valid(body.model.weapon_base) and is_instance_valid(body.model.weapon_tip)
	visible = has_weapon
	if not has_weapon: return
	var infusion := infusion_fraction()
	var surge := 1.0 + infusion * 0.65 + 0.13 * sin(_age * 7.0)
	var camera := get_viewport().get_camera_3d()
	var width_axis := global_basis.inverse() * camera.global_basis.x if camera != null else Vector3.RIGHT
	for i in _ribbons.size():
		var ribbon := _ribbons[i]
		ribbon.visible = infusion > 0.0   # no idle ring around the hero while armed; the veins only appear as they flow into the weapon
		_draw_flow(ribbon, i, weapon_destination(i), width_axis, infusion)
		ribbon.material_override = _flow_materials[i] if infusion > 0.0 else _idle_materials[i]
		var material := ribbon.material_override as ShaderMaterial
		material.set_shader_parameter("surge", surge)
		material.set_shader_parameter("fade", 1.0 - smoothstep(0.75, 1.0, infusion))
		if infusion > 0.0: material.set_shader_parameter("flow_phase", infusion)
	_draw_weapon_glow(width_axis, infusion)
	_draw_motes(infusion)

static func _blood_material(tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ENERGY_SHADER
	material.set_shader_parameter("blood_color", tint)
	return material

static func _energy(tint: Color, glow: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = glow
	return material

static func impact(from: Node, point: Vector3, direction: Vector3, rank: int) -> void:
	if not Fx.claim_impact("brutal_attack", point): return
	var dir := direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD
	var scale_factor := BrutalAttackFx.rank_scale(rank)
	var hue := BrutalAttackFx.rank_color(rank)
	var contact := point + Vector3.UP * 1.0
	var camera := from.get_viewport().get_camera_3d()
	var facing := camera.global_basis if camera != null else Basis.IDENTITY
	# No flying crescents and no contact tear: the spray, the mist and the gibs carry the blow.
	BrutalBloodWake.spawn(from, contact, dir, scale_factor)
	Fx.light_flash(from, contact, Color("ff284b"), 3.0, 0.14)
	Fx.burst(from, contact, dir + Vector3.UP * 0.25, Color("650a17"), 36, 8.0 * scale_factor, 0.035)
	Fx.burst(from, contact, -dir + Vector3.UP * 0.55, Color("8e1523"), 20, 5.0 * scale_factor, 0.022)
	Fx.burst(from, contact, dir + Vector3.UP * 0.6, Color("230d17"), 24, 4.0, 0.10)
	Fx.burst(from, point + Vector3.UP * 0.1, Vector3.UP, Color("4c2027"), 20, 3.8, 0.08)
	Fx.shake(from, 0.25)
	Fx.punch(from, 3.5)
	Fx.kick(from, dir, 0.8)

static func _impact_seam(from: Node, contact: Vector3, facing: Basis, size: float) -> void:
	var seam := MeshInstance3D.new()
	seam.name = "CrimsonContactSeam"
	seam.add_to_group(GROUP)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var a := Vector3(sin(float(i) * 2.4) * 0.045, float(i) / 12.0 * 1.5 - 0.75, 0.0)
		var b := Vector3(sin(float(i + 1) * 2.4) * 0.045, float(i + 1) / 12.0 * 1.5 - 0.75, 0.0)
		var width := Vector3(0.035 * sin(float(i + 1) / 13.0 * PI), 0, 0)
		for vertex in [a - width, a + width, b + width, a - width, b + width, b - width]: surface.add_vertex(vertex)
	seam.mesh = surface.commit()
	var material := _energy(Color("ff183b"), 1.2)
	seam.material_override = material
	seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(seam)
	seam.global_transform = Transform3D(facing, contact)
	seam.scale = Vector3.ONE * size
	var tween := seam.create_tween().set_parallel(true)
	tween.tween_property(seam, "scale:x", size * 2.4, 0.08)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.22).set_delay(0.04)
	tween.chain().tween_callback(seam.queue_free)

static func rupture_mesh() -> ArrayMesh:
	if _shard_mesh == null:
		var scene := (load(SHARD_PATH) as PackedScene).instantiate()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_append_meshes(scene, Transform3D.IDENTITY, surface)
		_shard_mesh = surface.commit()
		scene.free()
	return _shard_mesh

static func _append_meshes(node: Node, parent_transform: Transform3D, surface: SurfaceTool) -> void:
	var transform: Transform3D = parent_transform * (node.transform if node is Node3D else Transform3D.IDENTITY)
	if node is MeshInstance3D and node.mesh != null:
		for index in node.mesh.get_surface_count(): surface.append_from(node.mesh, index, transform)
	for child in node.get_children(): _append_meshes(child, transform, surface)
