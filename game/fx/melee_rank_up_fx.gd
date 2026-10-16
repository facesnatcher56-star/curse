extends Node3D
## Compact forged martial promotion badge, anchored to the unit that earned it.

const DURATION := 1.9
const EMBER := Color("ff9b49")
const BRONZE := Color("c58b4d")
const STEEL := Color("c4c0b0")
const CREST_SCENE: PackedScene = preload("res://assets/fx/melee_rank_crest.glb")

var _elapsed := 0.0
var _rank_group: Node3D
var _crest: Node3D
var _rank_plate: Node3D
var _label: Label3D
var _fade_materials: Array[StandardMaterial3D] = []

func start(rank: int) -> void:
	var actor := get_parent() as Player
	if not is_instance_valid(actor):
		queue_free()
		return
	_build(actor, rank)

func _build(actor: Player, rank: int) -> void:
	var h: float = actor.body_height
	var camera := actor.get_viewport().get_camera_3d()
	# A single compact stack: rising forged marker, Meshy insignia, then rank confirmation.
	_rank_group = Node3D.new()
	_rank_group.name = "MeleePromotionBadge"
	_rank_group.position.y = h + 0.10
	add_child(_rank_group)
	if camera != null:
		_rank_group.look_at(camera.global_position, Vector3.UP)

	var arrow := Node3D.new()
	arrow.name = "AscendingForgedRankMark"
	_rank_group.add_child(arrow)
	var arrow_mat := _material(BRONZE, true)
	arrow_mat.albedo_color.a = 0.0
	arrow_mat.emission_energy_multiplier = 0.0
	# Narrow iron shaft and angular shoulders give a ceremonial, forged chevron silhouette.
	_add_bar(arrow, Vector3(0.032, 0.36, 0.045), Vector3(0.0, 0.10, 0.16), 0.0, arrow_mat)
	_add_bar(arrow, Vector3(0.034, 0.20, 0.045), Vector3(-0.078, 0.25, 0.16), -0.72, arrow_mat)
	_add_bar(arrow, Vector3(0.034, 0.20, 0.045), Vector3(0.078, 0.25, 0.16), 0.72, arrow_mat)
	arrow.position.y = 0.02
	arrow.scale = Vector3.ONE * 0.72
	_crest = Node3D.new()
	_crest.name = "MeshyMartialCrest"
	_crest.position.y = 0.62
	_rank_group.add_child(_crest)
	var crest_model := CREST_SCENE.instantiate() as Node3D
	crest_model.scale = Vector3.ONE * 0.34
	crest_model.rotation.y = PI
	_crest.add_child(crest_model)
	for part in crest_model.find_children("*", "MeshInstance3D", true, false):
		(part as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# A compact forged rank tab anchors the numeral to the emblem instead of reading like a toast.
	_rank_plate = Node3D.new()
	_rank_plate.name = "MeleeRankPlate"
	_rank_plate.position.y = 1.42
	_rank_group.add_child(_rank_plate)
	var rim := MeshInstance3D.new()
	rim.name = "ForgedRankRim"
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(0.92, 0.34, 0.07)
	rim.mesh = rim_mesh
	rim.material_override = _material(Color("805a35"), false)
	(rim.material_override as StandardMaterial3D).albedo_color.a = 0.0
	_fade_materials.append(rim.material_override as StandardMaterial3D)
	_rank_plate.add_child(rim)
	var face := MeshInstance3D.new()
	face.name = "ForgedRankFace"
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(0.86, 0.28, 0.08)
	face.position.z = -0.015
	face.mesh = face_mesh
	face.material_override = _material(Color("211a16"), false)
	(face.material_override as StandardMaterial3D).albedo_color.a = 0.0
	_fade_materials.append(face.material_override as StandardMaterial3D)
	_rank_plate.add_child(face)
	_label = Label3D.new()
	_label.name = "MeleeRankLabel"
	_label.text = "MELEE  •  %s" % _roman(rank)
	_label.font = UiTheme.heading_font()
	_label.font_size = 24
	_label.outline_size = 4
	_label.outline_modulate = Color(0.06, 0.025, 0.008, 1.0)
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.shaded = false
	_label.no_depth_test = true
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.modulate = Color(1.0, 0.80, 0.49, 1.0)
	_label.transparency = 1.0
	_label.position.z = -0.07
	_rank_plate.add_child(_label)
	for x in [-0.40, 0.40]:
		var pin := MeshInstance3D.new()
		pin.name = "RankTabPin"
		var pin_mesh := BoxMesh.new()
		pin_mesh.size = Vector3(0.028, 0.028, 0.024)
		pin.mesh = pin_mesh
		pin.position = Vector3(x, 0.0, -0.068)
		pin.rotation.z = PI * 0.25
		pin.material_override = _material(Color("c29151"), false)
		_fade_materials.append(pin.material_override as StandardMaterial3D)
		(pin.material_override as StandardMaterial3D).albedo_color.a = 0.0
		_rank_plate.add_child(pin)
	var sparks := _make_sparks()
	sparks.position.y = 0.38
	_rank_group.add_child(sparks)
	_crest.scale = Vector3.ONE * 0.72
	_rank_plate.scale = Vector3.ONE * 0.76
	# Timed reveal: ember glint, badge lock-in, upward mark through the crest, rank confirmation.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_crest, "scale", Vector3.ONE, 0.30).set_delay(0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(arrow, "position:y", 0.83, 0.48).set_delay(0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(arrow, "scale", Vector3.ONE, 0.32).set_delay(0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(arrow_mat, "albedo_color:a", 1.0, 0.14).set_delay(0.55)
	tween.tween_property(arrow_mat, "emission_energy_multiplier", 0.8, 0.14).set_delay(0.55)
	tween.tween_property(_rank_plate, "scale", Vector3.ONE, 0.20).set_delay(0.86).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for mat in _fade_materials:
		tween.tween_property(mat, "albedo_color:a", 1.0, 0.16).set_delay(0.86)
	tween.tween_property(_label, "transparency", 0.0, 0.16).set_delay(0.92)
	tween.tween_property(_crest, "rotation:y", TAU * 0.06, 0.60).set_delay(0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_rank_group, "position:y", h + 0.14, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_crest, "scale", Vector3.ONE * 0.82, 0.34).set_delay(1.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_label, "transparency", 1.0, 0.30).set_delay(1.50)
	tween.tween_property(arrow_mat, "albedo_color:a", 0.0, 0.28).set_delay(1.48)
	tween.tween_property(arrow_mat, "emission_energy_multiplier", 0.0, 0.28).set_delay(1.48)
	for mat in _fade_materials:
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.30).set_delay(1.50)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()

func _add_bar(parent: Node3D, size: Vector3, at: Vector3, angle: float, material: StandardMaterial3D) -> void:
	var bar := MeshInstance3D.new()
	bar.mesh = BoxMesh.new()
	(bar.mesh as BoxMesh).size = size
	bar.position = at
	bar.rotation.z = angle
	bar.material_override = material
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bar)

func _material(tint: Color, emissive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.8
	return mat

func _roman(rank: int) -> String:
	var numerals := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	if rank > 0 and rank <= numerals.size():
		return numerals[rank - 1]
	return str(rank)

func _make_sparks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "PromotionEmbers"
	particles.amount = 12
	particles.lifetime = 0.62
	particles.explosiveness = 0.72
	particles.one_shot = true
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 28.0
	process.initial_velocity_min = 0.55
	process.initial_velocity_max = 1.35
	process.gravity = Vector3(0.0, 0.65, 0.0)
	process.scale_min = 0.018
	process.scale_max = 0.036
	process.color = EMBER
	particles.process_material = process
	var dot := SphereMesh.new()
	dot.radius = 0.018
	dot.height = 0.036
	particles.draw_pass_1 = dot
	return particles
