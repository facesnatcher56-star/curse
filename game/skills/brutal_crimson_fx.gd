class_name BrutalCrimsonFx
extends Node3D
## Owner-approved blood-magic presentation, deliberately beyond the DS2 orange
## effect. All nodes are visual; combat timing and spend remain in SkillController.

const SHARD_PATH := "res://assets/fx/brutal_crimson_rupture.glb"
const GROUP := "brutal_crimson_impact"
const ENERGY_SHADER := preload("res://game/skills/brutal_crimson_energy.gdshader")
var body: Player
var _ribbons: Array[MeshInstance3D] = []
var _age := 0.0
static var _shard_mesh: ArrayMesh

func setup(owner_body: Player) -> void:
	body = owner_body
	name = "CrimsonGathering"
	for strand in 3:
		var ribbon := MeshInstance3D.new()
		ribbon.name = "CrimsonVein%d" % strand
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for step in 32:
			var u0 := float(step) / 32.0
			var u1 := float(step + 1) / 32.0
			var a := _helix(u0, strand)
			var b := _helix(u1, strand)
			var w0 := Vector3.UP * sin(u0 * PI) * 0.075
			var w1 := Vector3.UP * sin(u1 * PI) * 0.075
			for vertex in [a - w0, a + w0, b + w1, a - w0, b + w1, b - w1]:
				surface.set_color(Color(1.0, 0.08, 0.17, 0.75))
				surface.add_vertex(vertex)
		surface.generate_normals()
		ribbon.mesh = surface.commit()
		ribbon.material_override = _blood_material(Color("f31643"))
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ribbon)
		_ribbons.append(ribbon)

static func _helix(u: float, strand: int) -> Vector3:
	var angle := u * TAU * 0.72 + TAU * float(strand) / 3.0
	var radius := 0.40 + sin(u * PI) * 0.22
	return Vector3(cos(angle) * radius, 0.18 + u * 1.65, sin(angle) * radius)

func _process(delta: float) -> void:
	_age += delta
	var winding := is_instance_valid(body) and body.skills.busy and bool(body.skills.busy_def.get("brutal_animation", false))
	var surge := 1.0 + (0.65 if winding else 0.0) + 0.13 * sin(_age * 7.0)
	for i in _ribbons.size():
		var ribbon := _ribbons[i]
		ribbon.rotation.y = _age * (2.7 if winding else 1.15)
		ribbon.scale = Vector3.ONE * (1.08 if winding else 1.0)
		(ribbon.material_override as ShaderMaterial).set_shader_parameter("surge", surge)

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
	var mesh := rupture_mesh()
	# Meshy's serrated crescents fracture outward from the actual contact point.
	for i in 5:
		var root := Node3D.new()
		root.name = "CrimsonRuptureShard"
		root.add_to_group(GROUP)
		from.get_tree().current_scene.add_child(root)
		root.global_position = contact
		root.basis = facing.rotated(facing.z, float(i) * 1.27 - 0.5)
		var shard := MeshInstance3D.new()
		shard.mesh = mesh
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := _blood_material(hue if i % 2 == 0 else hue.darkened(0.25))
		shard.material_override = material
		root.add_child(shard)
		var bounds := mesh.get_aabb()
		shard.position = -bounds.get_center()
		var norm := (0.70 + float(i % 3) * 0.25) * scale_factor / maxf(bounds.size.length(), 0.01)
		root.scale = Vector3.ONE * norm * 0.12
		var angle := float(i) * TAU / 5.0
		var outward := facing.x * cos(angle) + facing.y * sin(angle)
		var tween := root.create_tween().set_parallel(true)
		tween.tween_property(root, "scale", Vector3.ONE * norm, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(root, "global_position", contact + outward * 1.35 * scale_factor + dir * 0.30, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(root, "rotation:z", root.rotation.z + 0.5, 0.40)
		var fade := func(value: float) -> void: material.set_shader_parameter("fade", value)
		tween.tween_method(fade, 1.0, 0.0, 0.24).set_delay(0.14)
		tween.chain().tween_callback(root.queue_free)
	_impact_seam(from, contact, facing, scale_factor)
	Fx.light_flash(from, contact, Color("ff284b"), 3.0, 0.14)
	Fx.burst(from, contact, dir + Vector3.UP * 0.25, hue, 36, 8.0 * scale_factor, 0.045, true)
	Fx.burst(from, contact, -dir + Vector3.UP * 0.55, Color("ff6571"), 20, 5.0 * scale_factor, 0.027, true)
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
