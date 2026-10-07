class_name Fx
extends RefCounted
## Feedback helpers: floating text, hit-stop, camera shake.

const OUTCOME_STYLE := {
	Combat.Outcome.MISS: ["Miss", Color(0.7, 0.7, 0.7), 30],
	Combat.Outcome.BLOCK: ["Block", Color(0.5, 0.85, 1.0), 34],
	Combat.Outcome.HIT: ["", Color(1, 1, 1), 36],
	Combat.Outcome.CRITICAL: ["Critical ", Color(1.0, 0.9, 0.2), 46],
	Combat.Outcome.CRUSHING: ["Crushing ", Color(1.0, 0.55, 0.15), 54],
	Combat.Outcome.DEEP_WOUNDS: ["Wound ", Color(0.85, 0.15, 0.15), 42],
}

static var _hitstop_id: int = 0

## Impacts reported recently, so two presentation hooks describing the same logical hit draw it once: key -> [msec, position].
static var _recent_impacts: Dictionary = {}
const IMPACT_DEDUP_MSEC := 120
const IMPACT_DEDUP_RADIUS := 1.2
const MAX_FLASH_LIGHTS := 3
const IMPACT_GROUP := "impact_fx"

## True the first time a given kind of impact is claimed near `pos` inside the dedup window; false for a repeat (skip the visuals).
static func claim_impact(kind: String, pos: Vector3) -> bool:
	var now: int = Time.get_ticks_msec()
	for key in _recent_impacts.keys():
		if now - int(_recent_impacts[key][0]) > IMPACT_DEDUP_MSEC * 4:
			_recent_impacts.erase(key)
	var last: Array = _recent_impacts.get(kind, [])
	if not last.is_empty() and now - int(last[0]) <= IMPACT_DEDUP_MSEC and (last[1] as Vector3).distance_to(pos) <= IMPACT_DEDUP_RADIUS:
		return false
	_recent_impacts[kind] = [now, pos]
	return true

## Compact, grounded melee impact: tier 0 light (a few sparks), 1 heavy (sparks, a puff of dust, a short flash).
## A repeat on the same target inside the dedup window is dropped.
static func melee_impact(from: Node, pos: Vector3, away: Vector3, tier: int, target_id: int = 0) -> bool:
	if not claim_impact("melee_%d_%d" % [tier, target_id], pos):
		return false
	var dir: Vector3 = away + Vector3.UP * 0.4
	if tier <= 0:
		burst(from, pos, dir, Color(0.85, 0.72, 0.5), 6, 4.5, 0.02, true)
		return true
	burst(from, pos, dir, Color(0.95, 0.75, 0.4), 12, 6.5, 0.026, true)
	burst(from, pos, dir, Color(0.3, 0.27, 0.23), 8, 3.5, 0.04)
	light_flash(from, pos, Color(1.0, 0.8, 0.5), 1.6, 0.07)
	return true

static func popup(from: Node3D, outcome: int, damage: float, tint: Color = Color(0, 0, 0, 0)) -> void:
	if not GameSettings.show_damage_numbers:
		return
	var style: Array = OUTCOME_STYLE[outcome]
	var text: String = style[0]
	if outcome != Combat.Outcome.MISS and outcome != Combat.Outcome.BLOCK:
		text += str(int(round(damage)))
	var color: Color = style[1]
	if tint.a > 0.0 and outcome == Combat.Outcome.HIT:
		color = tint
	var top: float = from.body_height + 0.4 if from is Actor else 2.2
	text_at(from, from.global_position + Vector3(randf_range(-0.3, 0.3), top, 0), text, color, style[2])

static func text_at(from: Node3D, pos: Vector3, text: String, color: Color, size: int = 48) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = size
	label.outline_size = 12
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	from.get_tree().current_scene.add_child(label)
	label.global_position = pos
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", pos.y + 1.4, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.5)
	tween.chain().tween_callback(label.queue_free)

static var _slow_scale: float = 1.0
static var _slow_id: int = 0
static var _stopped: bool = false

## The clock is the slower of a hit-stop freeze and a slow-motion moment.
static func _apply_time() -> void:
	Engine.time_scale = 0.06 if _stopped else _slow_scale

## Back to normal speed (a new run, or a test finishing).
static func reset_time() -> void:
	_stopped = false
	_slow_scale = 1.0
	_slow_id += 1
	_hitstop_id += 1
	_recent_impacts.clear()
	Engine.time_scale = 1.0

static func hitstop(node: Node, duration: float) -> void:
	_hitstop_id += 1
	var my_id: int = _hitstop_id
	_stopped = true
	_apply_time()
	await node.get_tree().create_timer(duration, true, false, true).timeout
	if my_id == _hitstop_id:
		_stopped = false
		_apply_time()

## A slow-motion beat: the world drops to `scale` speed for `hold` seconds, then eases back over `ease_back` seconds.
## Both are real time (they do not stretch with the slowdown). A later call replaces an earlier one.
static func slowmo(node: Node, scale: float, hold: float, ease_back: float = 0.4) -> void:
	if not GameSettings.slow_motion:
		return
	_slow_id += 1
	var my_id: int = _slow_id
	_slow_scale = clampf(scale, 0.05, 1.0)
	_apply_time()
	var tree: SceneTree = node.get_tree()
	await tree.create_timer(hold, true, false, true).timeout
	var started: int = Time.get_ticks_msec()
	while my_id == _slow_id:
		var u: float = clampf(float(Time.get_ticks_msec() - started) / 1000.0 / maxf(ease_back, 0.01), 0.0, 1.0)
		_slow_scale = lerpf(clampf(scale, 0.05, 1.0), 1.0, u * u)
		_apply_time()
		if u >= 1.0:
			break
		await tree.process_frame

static func shake(node: Node, amount: float) -> void:
	node.get_tree().call_group("camera_rig", "shake", amount * GameSettings.screen_shake)

## FOV punch-in on the camera, scaled by the shake setting.
static func punch(node: Node, amount: float) -> void:
	node.get_tree().call_group("camera_rig", "punch", amount * GameSettings.screen_shake)

## Short directional camera shove, used on heavy hits.
static func kick(node: Node, direction: Vector3, amount: float) -> void:
	node.get_tree().call_group("camera_rig", "kick", direction, amount)

## One-shot spray of droplets/sparks.
static var _spark_pool: Dictionary = {}    # particle count -> free emitters, kept for the next burst
static var _spark_looks: Dictionary = {}   # (colour, size, emissive) -> the one mesh and material every burst of that look shares
const SPARK_BUCKETS: Array[int] = [8, 14, 20, 28, 40, 56, 80]

## A puff of particles that fly out and fall. Emitters and their meshes are reused (a fight throws a few of these every frame, and
## building a particle node, mesh and material each time was the biggest hitch in a crowded fight), so what comes back out of the
## pool is simply restarted.
static func burst(from: Node, pos: Vector3, dir: Vector3, color: Color, amount: int, speed: float,
		size: float = 0.022, emissive: bool = false) -> void:
	var count: int = SPARK_BUCKETS[SPARK_BUCKETS.size() - 1]
	for bucket in SPARK_BUCKETS:
		if amount <= bucket:
			count = bucket
			break
	var free: Array = _spark_pool.get(count, [])
	var particles: CPUParticles3D = null
	while not free.is_empty() and particles == null:
		var candidate = free.pop_back()   # untyped: a scene change frees pooled emitters, and a freed object cannot be put in a typed variable
		if is_instance_valid(candidate) and candidate.is_inside_tree():
			particles = candidate
	var scene: Node = from.get_tree().current_scene
	if particles == null:
		particles = CPUParticles3D.new()
		particles.one_shot = true
		particles.amount = count
		particles.lifetime = 0.6
		particles.explosiveness = 1.0
		particles.spread = 38.0
		particles.gravity = Vector3(0, -16, 0)
		scene.add_child(particles)
	var look: String = "%s/%.3f/%s" % [color.to_html(), size, emissive]
	if not _spark_looks.has(look):
		var mesh := SphereMesh.new()
		mesh.radius = size
		mesh.height = size * 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		if emissive:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		_spark_looks[look] = mesh
	particles.mesh = _spark_looks[look]
	particles.direction = dir
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.global_position = pos
	particles.restart()
	particles.emitting = true
	from.get_tree().create_timer(0.8).timeout.connect(_recycle_sparks.bind(particles.get_instance_id(), count))

## Back into the pool when the burst is spent. Goes by instance id: a scene change may have freed the emitter in the meantime.
static func _recycle_sparks(id: int, count: int) -> void:
	var particles := instance_from_id(id) as CPUParticles3D
	if particles == null:
		return
	particles.emitting = false
	if not _spark_pool.has(count):
		_spark_pool[count] = []
	(_spark_pool[count] as Array).append(particles)

static var _blood_texture: GradientTexture2D

static var _soft_texture: GradientTexture2D

## Soft round falloff for billboarded smoke and flame particles (otherwise they draw as hard squares).
static func soft_texture() -> GradientTexture2D:
	if _soft_texture == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		_soft_texture = GradientTexture2D.new()
		_soft_texture.gradient = g
		_soft_texture.fill = GradientTexture2D.FILL_RADIAL
		_soft_texture.fill_from = Vector2(0.5, 0.5)
		_soft_texture.fill_to = Vector2(1.0, 0.5)
		_soft_texture.width = 64
		_soft_texture.height = 64
	return _soft_texture

## Dark stain on the ground; old ones are recycled so the arena does not fill up.
static func blood_decal(from: Node, pos: Vector3, radius: float, color: Color = Color(0.25, 0.02, 0.02)) -> void:
	if _blood_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 0.85))
		gradient.set_color(1, Color(1, 1, 1, 0.0))
		_blood_texture = GradientTexture2D.new()
		_blood_texture.gradient = gradient
		_blood_texture.fill = GradientTexture2D.FILL_RADIAL
		_blood_texture.fill_from = Vector2(0.5, 0.5)
		_blood_texture.fill_to = Vector2(1.0, 0.5)
		_blood_texture.width = 64
		_blood_texture.height = 64
	var scene: Node = from.get_tree().current_scene
	var stains: Array[Node] = from.get_tree().get_nodes_in_group("stains")
	if stains.size() > 60:
		stains[0].queue_free()
	var quad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	quad.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _blood_texture
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material_override = mat
	quad.add_to_group("stains")
	scene.add_child(quad)
	quad.global_position = Vector3(pos.x, 0.02 + randf() * 0.01, pos.z)
	quad.rotation.y = randf() * TAU

## Small ring that pulses where a move-click landed.
static func click_marker(from: Node, pos: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.36
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.9, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(ring)
	ring.global_position = Vector3(pos.x, 0.05, pos.z)
	ring.scale = Vector3(1.6, 1.0, 1.6)
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(0.6, 1.0, 0.6), 0.35).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(ring.queue_free)

## Thin glowing line between two points (lightning arcs).
static func beam(from: Node, a: Vector3, b: Vector3, color: Color) -> void:
	var length: float = a.distance_to(b)
	if length < 0.05:
		return
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.035
	cylinder.bottom_radius = 0.035
	cylinder.height = length
	mesh_instance.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(mesh_instance)
	mesh_instance.global_position = (a + b) * 0.5
	var up: Vector3 = (b - a).normalized()
	var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
	mesh_instance.global_transform.basis = Basis(side.cross(up).normalized(), up, side)
	var tween := mesh_instance.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tween.tween_callback(mesh_instance.queue_free)

## Expanding ground ring for area effects (shockwaves, blasts).
static func ring(from: Node, pos: Vector3, radius: float, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	mesh_instance.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(mesh_instance)
	mesh_instance.global_position = Vector3(pos.x, 0.08, pos.z)
	mesh_instance.scale = Vector3(0.3, 1.0, 0.3)
	var tween := mesh_instance.create_tween().set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3(radius, 1.0, radius), 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(mesh_instance.queue_free)

## Brief point light for impact flashes.
static func light_flash(from: Node, pos: Vector3, color: Color, energy: float, duration: float) -> void:
	var tree: SceneTree = from.get_tree()
	if tree.get_nodes_in_group("flash_light").size() >= MAX_FLASH_LIGHTS:
		return   # a crowd's worth of flashes at once only washes the screen out
	var light := OmniLight3D.new()
	light.add_to_group("flash_light")
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 5.0
	from.get_tree().current_scene.add_child(light)
	light.global_position = pos
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration)
	tween.tween_callback(light.queue_free)
