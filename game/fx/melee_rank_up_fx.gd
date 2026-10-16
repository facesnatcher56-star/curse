extends Node3D
## Melee rank advancement: a Meshy crossed-swords insignia forges a new engraved rank notch.

const CREST_SCENE: PackedScene = preload("res://assets/fx/melee_crossed_swords_insignia.glb")
const DURATION := 4.50
const MARKS_PER_TIER := 3
const SLOT_X := [-0.17, 0.0, 0.17]
const BRONZE := Color("c18b4f")
const GOLD := Color("ffe0a0")
const MOLTEN := Color("ff7133")

var _elapsed := 0.0
var _actor: Player
var _insignia_root: Node3D
var _emblem: Node3D
var _rank_root: Node3D
var _previous_rank_root: Node3D
var _previous_marks: Array[MeshInstance3D] = []
var _previous_mark_materials: Array[StandardMaterial3D] = []
var _new_mark: MeshInstance3D
var _new_mark_material: StandardMaterial3D
var _crest_materials: Array[StandardMaterial3D] = []
var _tier_details: Array[MeshInstance3D] = []
var _tier_detail_materials: Array[StandardMaterial3D] = []
var _fade_materials: Array[StandardMaterial3D] = []
var _fade_bases: Array[float] = []
var _fade_emission_bases: Array[float] = []
var _flash: OmniLight3D
var _glint: OmniLight3D
var _glint_b: OmniLight3D
var _sparks: GPUParticles3D
var _embers: GPUParticles3D
var _rank_transition := false
var _latest := 0


func start(rank: int) -> void:
	_actor = get_parent() as Player
	if not is_instance_valid(_actor):
		queue_free()
		return
	set_as_top_level(true)
	global_position = _actor.global_position + Vector3.UP * (_actor.body_height + 0.45)
	_build(rank)
	_play(rank)


func _build(rank: int) -> void:
	var camera := get_viewport().get_camera_3d()
	_insignia_root = Node3D.new()
	_insignia_root.name = "MeleeRankInsigniaAndMarks"
	add_child(_insignia_root)
	_emblem = Node3D.new()
	_emblem.name = "MeleeCrossedSwordsInsignia"
	_emblem.position = Vector3.ZERO
	_emblem.scale = Vector3.ONE * 0.78
	_insignia_root.add_child(_emblem)
	if camera != null:
		_emblem.look_at(camera.global_position, camera.global_transform.basis.y)

	var crest := CREST_SCENE.instantiate() as Node3D
	crest.name = "MeshyCrossedSwordsInsignia"
	crest.scale = Vector3.ONE * 0.34
	crest.rotation.y = PI
	_emblem.add_child(crest)
	for node in crest.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			var material := source.duplicate() as StandardMaterial3D if source is StandardMaterial3D else StandardMaterial3D.new()
			material.albedo_color = material.albedo_color.darkened(0.38)
			material.metallic = 0.88
			material.roughness = 0.34
			material.emission_enabled = true
			material.emission = BRONZE
			material.emission_energy_multiplier = 0.0
			mesh.set_surface_override_material(surface, material)
			_crest_materials.append(material)
			_track_fade(material)
	# Construct the prior attained rank first. At ranks 4, 7, ... show its full three-mark
	# row, then turn that row into a permanent tier detail as the next row begins.
	var previous_rank := maxi(rank - 1, 0)
	var previous_tiers := maxi((previous_rank - 1) / MARKS_PER_TIER, 0) if previous_rank > 0 else 0
	var current_tiers := maxi((rank - 1) / MARKS_PER_TIER, 0)
	var previous_marks := previous_rank - previous_tiers * MARKS_PER_TIER
	var current_marks := rank - current_tiers * MARKS_PER_TIER
	_latest = maxi(rank - 1, 0) % MARKS_PER_TIER
	_rank_transition = current_tiers > previous_tiers
	_previous_rank_root = _make_rank_root("PreviousRankMarks", camera)
	_rank_root = _make_rank_root("CurrentRankMarks", camera)
	if _rank_transition:
		_create_rank_row(_previous_rank_root, previous_marks, false)
		_create_rank_row(_rank_root, current_marks, true)
		_rank_root.visible = false
	else:
		_create_rank_row(_rank_root, current_marks, true)
		_previous_rank_root.queue_free()
		_previous_rank_root = null

	# Completed tiers remain engraved above the active mark row; the next tier's detail
	# is forged during the rank-4/7/... transition rather than appearing at the start.
	for tier_index in range(current_tiers):
		var tier_mark := MeshInstance3D.new()
		tier_mark.name = "CompletedTierDetail%d" % (tier_index + 1)
		var tier_mesh := BoxMesh.new()
		var detail_size := 0.070 + 0.010 * minf(float(tier_index), 5.0)
		tier_mesh.size = Vector3(detail_size, detail_size, 0.022)
		tier_mark.mesh = tier_mesh
		tier_mark.position = Vector3(0.0, 0.30, 0.12 + tier_index * 0.004)
		tier_mark.rotation.z = deg_to_rad(45.0)
		tier_mark.material_override = _material(BRONZE.lightened(minf(0.05 * tier_index, 0.25)), 0.20)
		_emblem.add_child(tier_mark)
		var tier_material := tier_mark.material_override as StandardMaterial3D
		_track_fade(tier_material)
		_tier_details.append(tier_mark)
		_tier_detail_materials.append(tier_material)
		if _rank_transition and tier_index == current_tiers - 1:
			tier_mark.scale = Vector3.ONE * 0.06
			tier_material.emission_energy_multiplier = 0.0

	_flash = OmniLight3D.new()
	_flash.name = "RankNotchForgeFlash"
	_flash.position = Vector3(SLOT_X[_latest], 0.0, 0.11)
	_flash.light_color = GOLD
	_flash.light_energy = 0.0
	_flash.omni_range = 0.72
	_flash.shadow_enabled = false
	_rank_root.add_child(_flash)
	_glint = OmniLight3D.new()
	_glint.name = "CrossedSwordLockInGlint"
	_glint.position = Vector3(-0.20, 0.11, 0.20)
	_glint.light_color = Color("fff1c7")
	_glint.light_energy = 0.0
	_glint.omni_range = 0.30
	_glint.shadow_enabled = false
	_emblem.add_child(_glint)
	_glint_b = OmniLight3D.new()
	_glint_b.name = "CrossedSwordLockInGlintB"
	_glint_b.position = Vector3(0.20, 0.16, 0.20)
	_glint_b.light_color = Color("fff1c7")
	_glint_b.light_energy = 0.0
	_glint_b.omni_range = 0.24
	_glint_b.shadow_enabled = false
	_emblem.add_child(_glint_b)
	_sparks = _make_sparks()
	_sparks.position = _flash.position
	_rank_root.add_child(_sparks)
	_insignia_root.scale = Vector3.ONE * 0.001
	_insignia_root.position = Vector3.ZERO
	if camera != null:
		_insignia_root.global_basis = camera.global_basis
	if _rank_transition:
		_rank_root.position = Vector3(0.0, -0.53, 0.02)
		_previous_rank_root.position = Vector3(0.0, -0.34, 0.02)
	else:
		_rank_root.position = Vector3(0.0, -0.36, 0.02)
		_emblem.position.y = 0.0
		for root in [_rank_root, _previous_rank_root]:
			if is_instance_valid(root):
				root.position = Vector3(0.0, -0.34, 0.02)


func _play(rank: int) -> void:
	var timeline := create_tween()
	# Short emblem reveal. The rank state remains visible while the player sees the prior rank.
	timeline.tween_property(_insignia_root, "scale", Vector3.ONE, 0.50).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	timeline.parallel().tween_property(_emblem, "scale", Vector3.ONE, 0.50).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	timeline.tween_interval(0.04)
	if _rank_transition:
		timeline.tween_callback(func() -> void: _rank_root.visible = true)
		for mark in _previous_marks:
			timeline.parallel().tween_property(mark, "scale", Vector3.ONE * 0.04, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		for material in _previous_mark_materials:
			timeline.parallel().tween_property(material, "albedo_color:a", 0.0, 0.38)
			timeline.parallel().tween_property(material, "emission_energy_multiplier", 0.0, 0.38)
		var tier_mark: MeshInstance3D = _tier_details.back()
		var tier_material: StandardMaterial3D = _tier_detail_materials.back()
		timeline.parallel().tween_property(tier_mark, "scale", Vector3.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		timeline.parallel().tween_property(tier_material, "emission_energy_multiplier", 1.35, 0.16)
	else:
		# The new notch is the focal point: scale up from a spark-sized seed and cool from molten orange.
		timeline.parallel().tween_property(_new_mark, "scale", Vector3.ONE, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		timeline.parallel().tween_property(_new_mark, "position:y", -0.34, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	timeline.parallel().tween_property(_new_mark_material, "albedo_color", MOLTEN, 0.12)
	timeline.parallel().tween_property(_new_mark_material, "emission", MOLTEN, 0.12)
	timeline.parallel().tween_property(_new_mark_material, "emission_energy_multiplier", 2.4, 0.12)
	timeline.parallel().tween_property(_flash, "light_energy", 2.2, 0.12)
	timeline.tween_callback(func() -> void:
		if is_instance_valid(_sparks): _sparks.restart()
	)
	timeline.parallel().tween_property(_new_mark_material, "albedo_color", GOLD, 0.32)
	timeline.parallel().tween_property(_new_mark_material, "emission", GOLD, 0.32)
	timeline.parallel().tween_property(_new_mark_material, "emission_energy_multiplier", 0.72, 0.32)
	timeline.parallel().tween_property(_glint, "light_energy", 2.5, 0.12)
	timeline.parallel().tween_property(_glint, "position:x", 0.20, 0.38)
	timeline.parallel().tween_property(_glint_b, "light_energy", 2.1, 0.12)
	timeline.parallel().tween_property(_glint_b, "position:x", -0.20, 0.38)
	for material in _crest_materials:
		timeline.parallel().tween_property(material, "emission_energy_multiplier", 0.34, 0.12)
	timeline.parallel().tween_property(_flash, "light_energy", 0.0, 0.20)
	timeline.parallel().tween_property(_glint, "light_energy", 0.0, 0.20)
	timeline.parallel().tween_property(_glint_b, "light_energy", 0.0, 0.20)
	for material in _crest_materials:
		timeline.parallel().tween_property(material, "emission_energy_multiplier", 0.0, 0.25)
	# Hold the assembled rank briefly, then dissolve the entire insignia as one unit.
	timeline.tween_interval(3.00)
	timeline.tween_callback(_capture_fade_emission)
	timeline.tween_method(_set_fade, 1.0, 0.0, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	timeline.parallel().tween_property(_insignia_root, "scale", Vector3.ONE * 0.001, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	timeline.tween_callback(_emit_faint_embers)
	timeline.tween_interval(0.05)


func _emit_faint_embers() -> void:
	_embers = _make_sparks()
	_embers.name = "FaintEmbersAfterInsignia"
	_embers.amount = 7
	_embers.lifetime = 0.35
	_embers.position = Vector3.ZERO
	add_child(_embers)
	(_embers.process_material as ParticleProcessMaterial).color = Color("b86b3e")
	_embers.restart()


func _make_rank_root(node_name: String, camera: Camera3D) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	_insignia_root.add_child(root)
	if camera != null:
		root.global_basis = camera.global_basis
	return root


func _create_rank_row(root: Node3D, marks_count: int, has_new_mark: bool) -> void:
	for index in MARKS_PER_TIER:
		var socket := MeshInstance3D.new()
		socket.name = "RankMarkSocket%d" % (index + 1)
		var socket_mesh := BoxMesh.new()
		socket_mesh.size = Vector3(0.135, 0.058, 0.025)
		socket.mesh = socket_mesh
		socket.position = Vector3(SLOT_X[index], 0.0, 0.04)
		socket.material_override = _material(Color("30281f"), 0.03)
		root.add_child(socket)
		_track_fade(socket.material_override as StandardMaterial3D)
		if index >= marks_count:
			continue
		var mark := MeshInstance3D.new()
		mark.name = "ForgedRankNotch%d" % (index + 1)
		var notch := BoxMesh.new()
		notch.size = Vector3(0.115, 0.034, 0.032)
		mark.mesh = notch
		mark.position = Vector3(SLOT_X[index], 0.0, 0.075)
		var material := _material(GOLD, 0.20)
		mark.material_override = material
		root.add_child(mark)
		_track_fade(material)
		if has_new_mark and index == marks_count - 1:
			_new_mark = mark
			_new_mark_material = material
			mark.scale = Vector3.ONE * 0.04
			mark.position.y = 0.07
			material.albedo_color = BRONZE.darkened(0.22)
			material.emission = MOLTEN
			material.emission_energy_multiplier = 0.0
		else:
			_previous_marks.append(mark)
			_previous_mark_materials.append(material)


func _set_fade(alpha: float) -> void:
	for index in _fade_materials.size():
		_fade_materials[index].albedo_color.a = _fade_bases[index] * alpha
		_fade_materials[index].emission_energy_multiplier = _fade_emission_bases[index] * alpha


func _capture_fade_emission() -> void:
	_fade_emission_bases.clear()
	for material in _fade_materials:
		_fade_emission_bases.append(material.emission_energy_multiplier)


func _track_fade(material: StandardMaterial3D) -> void:
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_materials.append(material)
	_fade_bases.append(material.albedo_color.a)


func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(_actor):
		# Follow actor translation only. Camera-facing orientation and emblem pose remain independent.
		global_position = _actor.global_position + Vector3.UP * (_actor.body_height + 0.45)
	if not is_instance_valid(_actor) or _elapsed >= DURATION:
		queue_free()


func _material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.72
	material.roughness = 0.48
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.no_depth_test = true
	return material


func _make_sparks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "ForgedBronzeRankSparks"
	particles.amount = 18
	particles.lifetime = 0.40
	particles.explosiveness = 1.0
	particles.one_shot = true
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 0.0, 1.0)
	process.spread = 115.0
	process.initial_velocity_min = 0.25
	process.initial_velocity_max = 0.72
	process.gravity = Vector3(0.0, -0.10, 0.0)
	process.scale_min = 0.50
	process.scale_max = 0.95
	process.color = MOLTEN
	particles.process_material = process
	var shard := BoxMesh.new()
	shard.size = Vector3(0.014, 0.038, 0.012)
	var spark_material := StandardMaterial3D.new()
	spark_material.albedo_color = MOLTEN
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.emission_enabled = true
	spark_material.emission = Color("ff9b52")
	spark_material.emission_energy_multiplier = 0.85
	shard.material = spark_material
	particles.draw_pass_1 = shard
	return particles


