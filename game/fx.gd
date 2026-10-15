class_name Fx
extends RefCounted
## Feedback helpers: floating text, hit-stop, camera shake.

const OUTCOME_STYLE := {
	Combat.Outcome.MISS: ["Dodge", Color(0.6, 0.95, 1.0), 32],   # the only way a blow misses here is a dodge (DS2 has no accuracy roll)
	Combat.Outcome.BLOCK: ["Block", Color(0.5, 0.85, 1.0), 34],
	Combat.Outcome.HIT: ["", Color(1, 1, 1), 36],
	Combat.Outcome.CRITICAL: ["Critical ", Color(1.0, 0.9, 0.2), 46],
}

static var _hitstop_id: int = 0

## Impacts reported recently, so two presentation hooks describing the same logical hit draw it once: key -> [msec, position].
static var _recent_impacts: Dictionary = {}
const IMPACT_DEDUP_MSEC := 120
const IMPACT_DEDUP_RADIUS := 1.2
const MAX_FLASH_LIGHTS := 3
const IMPACT_GROUP := "impact_fx"

const CHARACTER_LEVEL_SIGIL: Texture2D = preload("res://assets/fx/levelup/character_level_sigil_contrast.png")
const CHARACTER_LEVEL_BEAM: Shader = preload("res://game/level_up_beam.gdshader")
const CHARACTER_LEVEL_TRAIL: Shader = preload("res://game/level_up_trail.gdshader")
const CHARACTER_LEVEL_SIGIL_SHADER: Shader = preload("res://game/level_up_sigil.gdshader")

const LEVEL_UP_DURATION := 2.8
const LEVEL_UP_PEAK_TIME := 1.35
const LEVEL_UP_GOLD := Color(1.0, 0.68, 0.28)
const LEVEL_UP_IVORY := Color(1.0, 0.92, 0.68)
const LEVEL_UP_TEAL := Color(0.33, 0.86, 0.76)

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

## What a landed blow should feel like, from its outcome and weight. Pure (no scene needed), so it is checked directly.
## tier 0 light, 1 critical, 2 a heavy blow (weight Actor.HEAVY_BLOW_WEIGHT or more); every value is bounded so a crowd of heavy blows
## cannot pile up.
static func impact_profile(outcome: int, weight: float) -> Dictionary:
	var w: float = clampf(weight, 0.5, 3.0)
	if weight >= Actor.HEAVY_BLOW_WEIGHT:
		return {"tier": 2, "kick": minf(0.5 * w * 1.7, 1.4), "hitstop": 0.07}
	match outcome:
		Combat.Outcome.CRITICAL:
			return {"tier": 1, "kick": minf(0.5 * w * 1.3, 1.1), "hitstop": 0.045}
		_:
			return {"tier": 0, "kick": minf(0.5 * w, 0.8), "hitstop": 0.0}

## Compact, grounded melee impact: tier 0 light (a few sparks), 1 critical (sparks, a puff of dust, a short flash), 2 a heavy blow
## (the same pieces, a bigger dust cloud and a brighter flash). A repeat on the same target inside the dedup window is dropped.
static func melee_impact(from: Node, pos: Vector3, away: Vector3, tier: int, target_id: int = 0) -> bool:
	if not claim_impact("melee_%d_%d" % [tier, target_id], pos):
		return false
	var dir: Vector3 = away + Vector3.UP * 0.4
	if tier <= 0:
		burst(from, pos, dir, Color(0.85, 0.72, 0.5), 6, 4.5, 0.02, true)
		return true
	var crushing: bool = tier >= 2
	burst(from, pos, dir, Color(0.95, 0.75, 0.4), 12, 6.5, 0.026, true)
	burst(from, pos, dir, Color(0.3, 0.27, 0.23), 14 if crushing else 8, 4.2 if crushing else 3.5, 0.05 if crushing else 0.04)
	light_flash(from, pos, Color(1.0, 0.8, 0.5), 2.2 if crushing else 1.6, 0.08 if crushing else 0.07)
	if crushing and claim_impact("crush_ring", pos):   # the one extra cue critical lacks: a low shockwave of dust off the ground
		ring(from, Vector3(pos.x, 0.1, pos.z), 2.6, Color(0.6, 0.5, 0.38))
	return true

## A flying body striking scenery ("wall") or another enemy ("enemy"): dust, one recorded thud and a short camera shove, once per
## logical impact (two hooks describing the same strike draw it once). Presentation only: it never deals or resolves damage.
## Returns false for a repeat.
static func body_impact(from: Node, pos: Vector3, dir: Vector3, kind: String, speed: float) -> bool:
	if not claim_impact("body_" + kind, pos):
		return false
	var s: float = clampf(speed, 0.0, 14.0)
	var away: Vector3 = -dir.normalized() if dir.length() > 0.01 else Vector3.UP
	if kind == "wall":
		burst(from, pos, away + Vector3.UP * 0.3, Color(0.55, 0.5, 0.42), 10 + int(s), 3.0 + s * 0.15, 0.05)
		shake(from, clampf(0.04 + s * 0.008, 0.04, 0.14))
		kick(from, dir, clampf(s / 16.0, 0.15, 0.7))
	else:
		burst(from, pos, Vector3.UP, Color(0.5, 0.45, 0.38), 6, 2.5, 0.04)
	Sfx.body_impact(from, kind, s)
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

static func text_at(from: Node3D, pos: Vector3, text: String, color: Color, size: int = 48, duration: float = 0.9) -> void:
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
	tween.tween_property(label, "global_position:y", pos.y + 1.4, duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, duration * 0.45).set_delay(duration * 0.55)
	tween.chain().tween_callback(label.queue_free)

## An item pickup's name over the hero: fully readable for PICKUP_HOLD seconds (PICKUP_HOLD_IMPORTANT for a rare, unique or set item), then
## a PICKUP_FADE fade. Only this hero's own pickups stack: each new line starts just above the highest one still showing, so rapid
## pickups read as a column instead of writing over each other. Returns the label (for checks).
const PICKUP_HOLD := 3.0
const PICKUP_HOLD_IMPORTANT := 4.0
const PICKUP_FADE := 0.5
const PICKUP_STEP := 0.42   # world height between two pickup lines in the same column
const PICKUP_RISE := 1.4
static var _pickup_lines: Array[Label3D] = []

## How long a pickup line is fully visible and how long it then takes to fade: (hold seconds, fade seconds).
static func pickup_timing(important: bool) -> Vector2:
	return Vector2(PICKUP_HOLD_IMPORTANT if important else PICKUP_HOLD, PICKUP_FADE)

static func pickup_text(from: Node3D, pos: Vector3, text: String, color: Color, important: bool = false, size: int = 40) -> Label3D:
	var owner_id: int = from.get_instance_id()
	var live: Array[Label3D] = []   # typed: only lines still showing are kept (freed or queued ones are dropped)
	for line in _pickup_lines:
		if is_instance_valid(line) and not line.is_queued_for_deletion():
			live.append(line)
	_pickup_lines = live
	var top: float = pos.y
	for line in _pickup_lines:
		if int(line.get_meta("owner", 0)) == owner_id:
			top = maxf(top, line.global_position.y + PICKUP_STEP)
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = size
	label.outline_size = 12
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.set_meta("owner", owner_id)
	from.get_tree().current_scene.add_child(label)
	label.global_position = Vector3(pos.x, top, pos.z)
	_pickup_lines.append(label)
	var timing := pickup_timing(important)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", top + PICKUP_RISE, timing.x + timing.y).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, timing.y).set_delay(timing.x)
	tween.chain().tween_callback(label.queue_free)
	return label

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

## A flat sector of ground that opens outward and fades: a sweeping arc (`spin` turns it through that many radians while it fades) or a
## cone blast (`half_angle` in degrees, forward along `facing`). Powers use it for their own silhouette, not the shared ring.
static func sector(from: Node, pos: Vector3, facing: Vector3, half_angle: float, radius: float, color: Color, duration: float,
		spin: float = 0.0, inner: float = 0.35) -> void:
	const SEGMENTS := 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = deg_to_rad(half_angle)
	for i in SEGMENTS:
		var a0: float = lerpf(-half, half, float(i) / SEGMENTS)
		var a1: float = lerpf(-half, half, float(i + 1) / SEGMENTS)
		var o0 := Vector3(sin(a0), 0.0, cos(a0))
		var o1 := Vector3(sin(a1), 0.0, cos(a1))
		# Inner edge at `inner` of the radius: a band for a sweep, a short fan for a cone (inner 0 makes a full fan).
		var i0: Vector3 = o0 * inner
		var i1: Vector3 = o1 * inner
		st.add_vertex(i0); st.add_vertex(o0); st.add_vertex(o1)
		st.add_vertex(i0); st.add_vertex(o1); st.add_vertex(i1)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	from.get_tree().current_scene.add_child(mesh_instance)
	mesh_instance.global_position = Vector3(pos.x, 0.09, pos.z)
	var flat := Vector3(facing.x, 0.0, facing.z)
	mesh_instance.rotation.y = atan2(flat.x, flat.z) if flat.length() > 0.01 else 0.0
	mesh_instance.scale = Vector3(0.3 * radius, 1.0, 0.3 * radius)
	var tween := mesh_instance.create_tween().set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3(radius, 1.0, radius), duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	if spin != 0.0:
		tween.tween_property(mesh_instance, "rotation:y", mesh_instance.rotation.y + spin, duration).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(mesh_instance.queue_free)

## Character XP level-up: the sigil reveals as power builds, peaks in one compact burst, then resolves by 2.8 s.
## The Meshy artwork remains the hero; arcs, sparks, light and timing are native Godot effects around it.
static func character_level_up(from: Node3D, new_level: int = 0) -> void:
	if not is_instance_valid(from) or not from.is_inside_tree():
		return
	var previous := from.get_node_or_null("CharacterLevelUpFx")
	if previous != null:
		previous.free() # A repeated ding on one member restarts its own effect; other members stay independent.
	var height: float = from.body_height if from is Actor else 1.8
	var radius: float = from.body_radius if from is Actor else 0.38
	var fx_root := Node3D.new()
	fx_root.name = "CharacterLevelUpFx"
	from.add_child(fx_root) # Follow movement and let character deletion/scene changes own cleanup.

	# IGNITE → SURGE: a small localized glow rises in three measured steps, then peaks briefly.
	var ground_light := OmniLight3D.new()
	ground_light.light_color = LEVEL_UP_GOLD
	ground_light.light_energy = 0.0
	ground_light.omni_range = 2.7
	ground_light.shadow_enabled = false
	fx_root.add_child(ground_light)
	ground_light.position.y = 0.82
	var ignite := ground_light.create_tween()
	ignite.tween_property(ground_light, "light_energy", 0.55, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ignite.tween_property(ground_light, "light_energy", 1.15, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ignite.tween_property(ground_light, "light_energy", 1.85, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	ignite.tween_property(ground_light, "light_energy", 3.2, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ignite.tween_property(ground_light, "light_energy", 1.25, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	ignite.tween_property(ground_light, "light_energy", 0.0, 1.17).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# SEAL: let the original Meshy rune work draw itself from the center outward.
	_level_up_ground_sigil(fx_root, 1.36, LEVEL_UP_DURATION)
	_level_up_ground_arc(fx_root, 1.10, 0.145, 0.018, 0.66, LEVEL_UP_GOLD, 1.0)
	_level_up_ground_arc(fx_root, 0.68, 0.155, 0.014, 0.58, LEVEL_UP_TEAL, -1.0)
	_level_up_sparks(fx_root, 7, radius + 0.12, 0.9, Vector3.UP, 15.0, 0.55, 1.0)

	# SURGE / ASCEND: two smooth filaments spiral in opposite directions and meet at one point overhead.
	var aura_radius: float = maxf(radius + 0.08, 0.48)
	var aura_height: float = height + 0.68
	var pillar := _level_up_beam(fx_root, height + 0.9, radius)
	if pillar != null:
		var pillar_material := pillar.material_override as ShaderMaterial
		var pillar_rise := pillar.create_tween().set_parallel(true)
		pillar_rise.tween_property(pillar, "scale:y", height + 0.9, LEVEL_UP_PEAK_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		pillar_rise.tween_property(pillar, "position:y", (height + 0.9) * 0.5, LEVEL_UP_PEAK_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var pillar_glow := pillar.create_tween()
		pillar_glow.tween_property(pillar_material, "shader_parameter/opacity", 0.10, 0.78)
		pillar_glow.tween_property(pillar_material, "shader_parameter/opacity", 0.22, 0.57)
		pillar_glow.tween_interval(0.08)
		pillar_glow.tween_property(pillar_material, "shader_parameter/opacity", 0.0, 0.95)
		pillar_glow.tween_callback(pillar.queue_free)
	for i in 2:
		var phase: float = TAU * float(i) / 2.0
		var direction: float = 1.0 if i == 0 else -1.0
		var trail := _level_up_aura_trail(fx_root, aura_height, aura_radius, phase, direction)
		if trail == null:
			continue
		var trail_material := trail.material_override as ShaderMaterial
		var trail_rise := trail.create_tween()
		trail_rise.tween_property(trail_material, "shader_parameter/rise_progress", 1.0, LEVEL_UP_PEAK_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var trail_glow := trail.create_tween()
		trail_glow.tween_property(trail_material, "shader_parameter/opacity", 0.30, 0.35)
		trail_glow.tween_property(trail_material, "shader_parameter/opacity", 0.42, 0.55)
		trail_glow.tween_property(trail_material, "shader_parameter/opacity", 0.50, 0.45)
		trail_glow.tween_interval(0.50)
		trail_glow.tween_property(trail_material, "shader_parameter/opacity", 0.0, 0.95).set_trans(Tween.TRANS_SINE)
		trail_glow.tween_callback(trail.queue_free)
		var trail_spin := trail.create_tween()
		trail_spin.tween_property(trail, "rotation:y", direction * TAU * 0.22, 0.9).set_trans(Tween.TRANS_SINE)
		trail_spin.tween_property(trail, "rotation:y", direction * TAU * 0.62, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		trail_spin.tween_property(trail, "rotation:y", direction * TAU * 0.82, 1.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# The bright particles are narrow moving streaks, not glowing orbs. Their counts are kept deliberately low.
	var peak_sparks := _level_up_sparks(fx_root, 12, aura_radius, 0.48, Vector3(0.0, 0.32, 0.0), 76.0, 3.2, 0.7, false)
	var peak := fx_root.create_tween()
	peak.tween_interval(LEVEL_UP_PEAK_TIME)
	peak.tween_callback(func() -> void:
		if is_instance_valid(peak_sparks):
			peak_sparks.restart()
			peak_sparks.emitting = true
	)
	_level_up_shockwave(fx_root, LEVEL_UP_PEAK_TIME, 1.48)
	_level_up_notification(fx_root, height, new_level)

	var cleanup := fx_root.create_tween()
	cleanup.tween_interval(LEVEL_UP_DURATION)
	cleanup.tween_callback(fx_root.queue_free)

## Soft tapered golden light column; the Meshy ground sigil is its own floor decal.
static func _level_up_beam(parent: Node3D, height: float, radius: float) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = maxf(radius * 0.78, 0.28)
	cylinder.bottom_radius = maxf(radius * 1.28, 0.48)
	cylinder.height = 1.0
	cylinder.radial_segments = 32
	cylinder.rings = 2
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	var material := ShaderMaterial.new()
	material.shader = CHARACTER_LEVEL_BEAM
	material.set_shader_parameter("opacity", 0.0)
	var beam := MeshInstance3D.new()
	beam.name = "LevelUpGoldenColumn"
	beam.mesh = cylinder
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.scale = Vector3(1.0, 0.01, 1.0)
	beam.position.y = 0.005
	parent.add_child(beam)
	return beam

## Build one tapered ribbon that rises in a spiral and narrows to a point above the hero.
static func _level_up_aura_trail(parent: Node3D, height: float, orbit_radius: float, phase: float, direction: float) -> MeshInstance3D:
	const SEGMENTS := 72
	const HALF_WIDTH := 0.015
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for segment in range(SEGMENTS + 1):
		var t: float = float(segment) / float(SEGMENTS)
		var radius: float = lerpf(orbit_radius, 0.025, smoothstep(0.74, 1.0, t))
		var angle: float = phase + direction * TAU * 1.55 * t
		var center := Vector3(cos(angle) * radius, lerpf(0.12, height, t), sin(angle) * radius)
		var tangent := Vector3(-sin(angle) * radius * TAU * 1.55 * direction, height, cos(angle) * radius * TAU * 1.55 * direction)
		var side := tangent.cross(Vector3.UP).normalized() * HALF_WIDTH
		vertices.append(center - side)
		vertices.append(center + side)
		uvs.append(Vector2(0.0, t))
		uvs.append(Vector2(1.0, t))
		if segment < SEGMENTS:
			var index: int = segment * 2
			indices.append_array(PackedInt32Array([index, index + 2, index + 1, index + 1, index + 2, index + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = CHARACTER_LEVEL_TRAIL
	material.set_shader_parameter("opacity", 0.0)
	material.set_shader_parameter("rise_progress", 0.0)
	var trail := MeshInstance3D.new()
	trail.name = "LevelUpGoldenAuraTrail"
	trail.mesh = mesh
	trail.material_override = material
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(trail)
	return trail

## The Meshy ground sigil opens beneath the hero. It ignores physics and input.
static func _level_up_ground_sigil(parent: Node3D, size: float, lifetime: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "LevelUpGroundSigil"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	ring.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = CHARACTER_LEVEL_SIGIL_SHADER
	material.set_shader_parameter("sigil_texture", CHARACTER_LEVEL_SIGIL)
	material.set_shader_parameter("opacity", 1.0)
	material.set_shader_parameter("reveal_progress", 0.02)
	material.set_shader_parameter("brightness", 0.45)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.position.y = 0.1
	ring.rotation.x = -PI * 0.5
	ring.scale = Vector3.ONE * size * 0.88
	var scale_tween := ring.create_tween()
	scale_tween.tween_property(ring, "scale", Vector3.ONE * size, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var reveal := ring.create_tween()
	reveal.tween_property(material, "shader_parameter/reveal_progress", 0.50, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	reveal.tween_property(material, "shader_parameter/reveal_progress", 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var glow := ring.create_tween()
	glow.tween_property(material, "shader_parameter/brightness", 0.8, 0.35)
	glow.tween_property(material, "shader_parameter/brightness", 1.1, 0.55)
	glow.tween_property(material, "shader_parameter/brightness", 1.7, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	glow.tween_property(material, "shader_parameter/brightness", 2.25, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	glow.tween_property(material, "shader_parameter/brightness", 1.15, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	glow.tween_property(material, "shader_parameter/brightness", 0.0, maxf(lifetime - 1.63, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var rotation := ring.create_tween()
	rotation.tween_property(ring, "rotation:z", 0.18, 0.35).set_trans(Tween.TRANS_SINE)
	rotation.tween_property(ring, "rotation:z", 0.58, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	rotation.tween_property(ring, "rotation:z", 1.20, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	rotation.tween_property(ring, "rotation:z", 1.42, maxf(lifetime - 1.35, 0.05)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var pulse := ring.create_tween()
	pulse.tween_property(ring, "scale", Vector3.ONE * size * 1.045, 0.12).set_delay(LEVEL_UP_PEAK_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pulse.tween_property(ring, "scale", Vector3.ONE * size, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return ring

## Two fine, broken rings add counter-rotation while leaving the Meshy sigil as the dominant ground shape.
static func _level_up_ground_arc(parent: Node3D, radius: float, y: float, width: float, arc_fraction: float, color: Color, direction: float) -> MeshInstance3D:
	const SEGMENTS := 64
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var half_width: float = width * 0.5
	var start: float = 0.0 if direction > 0.0 else TAU * 0.22
	for segment in range(SEGMENTS + 1):
		var t: float = float(segment) / float(SEGMENTS)
		var angle: float = start + TAU * arc_fraction * t
		var outer: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * (radius + half_width)
		var inner: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * (radius - half_width)
		vertices.append(Vector3(inner.x, 0.0, inner.z))
		vertices.append(Vector3(outer.x, 0.0, outer.z))
		if segment < SEGMENTS:
			var index: int = segment * 2
			indices.append_array(PackedInt32Array([index, index + 1, index + 2, index + 1, index + 3, index + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.15
	var arc := MeshInstance3D.new()
	arc.name = "LevelUpCounterArc"
	arc.mesh = mesh
	arc.material_override = material
	arc.position.y = y
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(arc)
	var reveal := arc.create_tween()
	reveal.tween_property(material, "albedo_color:a", 0.64, 0.35)
	reveal.tween_property(material, "albedo_color:a", 0.84, 0.55)
	reveal.tween_property(material, "albedo_color:a", 0.95, 0.45)
	reveal.tween_interval(0.50)
	reveal.tween_property(material, "albedo_color:a", 0.0, 0.95).set_trans(Tween.TRANS_SINE)
	var spin := arc.create_tween()
	spin.tween_property(arc, "rotation:y", direction * TAU * 0.22, 0.9).set_trans(Tween.TRANS_SINE)
	spin.tween_property(arc, "rotation:y", direction * TAU * 0.60, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	spin.tween_property(arc, "rotation:y", direction * TAU * 0.76, 1.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return arc

## Warm, narrow streaks rise from around the body; a short one-shot burst marks the level-up peak.
static func _level_up_sparks(parent: Node3D, count: int, spawn_radius: float, lifetime: float, direction: Vector3, spread: float,
		velocity: float, velocity_spread: float, emit_on_ready: bool = true) -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.name = "LevelUpGoldSparks"
	sparks.amount = count
	sparks.one_shot = true
	sparks.explosiveness = 0.82
	sparks.lifetime = lifetime
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = spawn_radius
	sparks.direction = direction
	sparks.spread = spread
	sparks.initial_velocity_min = maxf(velocity - velocity_spread, 0.1)
	sparks.initial_velocity_max = velocity + velocity_spread
	sparks.gravity = Vector3(0.0, -0.48, 0.0)
	sparks.emitting = emit_on_ready
	var streak := QuadMesh.new()
	streak.size = Vector2(0.024, 0.16)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = soft_texture()
	streak.material = material
	sparks.mesh = streak
	var ramp := Gradient.new()
	ramp.set_color(0, LEVEL_UP_IVORY)
	ramp.add_point(0.35, LEVEL_UP_GOLD)
	ramp.set_color(1, Color(0.82, 0.30, 0.08, 0.0))
	sparks.color_ramp = ramp
	parent.add_child(sparks)
	sparks.position.y = 0.82
	sparks.finished.connect(sparks.queue_free)
	return sparks

## A thin ground shockwave expands across the rune circle on the peak, then fades in under half a second.
static func _level_up_shockwave(parent: Node3D, delay: float, radius: float) -> MeshInstance3D:
	var wave := MeshInstance3D.new()
	wave.name = "LevelUpGroundShockwave"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.975
	torus.outer_radius = 1.0
	torus.ring_segments = 48
	torus.rings = 6
	wave.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(LEVEL_UP_IVORY.r, LEVEL_UP_IVORY.g, LEVEL_UP_IVORY.b, 0.92)
	material.emission_enabled = true
	material.emission = LEVEL_UP_GOLD
	material.emission_energy_multiplier = 2.1
	wave.material_override = material
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wave.position.y = 0.17
	wave.scale = Vector3.ONE * 0.025
	parent.add_child(wave)
	var expand := wave.create_tween().set_parallel(true)
	expand.tween_property(wave, "scale", Vector3(radius, 1.0, radius), 0.42).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	expand.tween_property(material, "albedo_color:a", 0.0, 0.42).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	expand.chain().tween_callback(wave.queue_free)
	return wave

## World-space title above the rising aura, appearing at the crest.
static func _level_up_notification(parent: Node3D, height: float, new_level: int) -> void:
	var notice := Node3D.new()
	notice.name = "LevelUpWorldNotification"
	notice.position = Vector3(0.0, height + 0.55, 0.0)
	notice.scale = Vector3.ONE * 0.72
	notice.visible = false
	parent.add_child(notice)

	var title := Label3D.new()
	title.name = "LevelUpWorldTitle"
	title.text = "LEVEL UP"
	title.font_size = 68
	title.pixel_size = 0.004
	title.outline_size = 12
	title.outline_modulate = Color(0.08, 0.035, 0.008, 1.0)
	title.modulate = Color(1.0, 0.88, 0.56, 1.0)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.shaded = false
	title.no_depth_test = true
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice.add_child(title)
	title.position = Vector3(0.0, 0.11, 0.0)

	if new_level > 0:
		var level_label := Label3D.new()
		level_label.name = "LevelUpWorldLevel"
		level_label.text = "LEVEL %d" % new_level
		level_label.font_size = 36
		level_label.pixel_size = 0.004
		level_label.outline_size = 8
		level_label.outline_modulate = Color(0.08, 0.035, 0.008, 1.0)
		level_label.modulate = Color(0.42, 1.0, 0.92, 1.0)
		level_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		level_label.shaded = false
		level_label.no_depth_test = true
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		notice.add_child(level_label)
		level_label.position = Vector3(0.0, -0.18, 0.0)

	var tween := notice.create_tween()
	tween.tween_interval(LEVEL_UP_PEAK_TIME)
	tween.tween_callback(func() -> void: notice.visible = true)
	tween.tween_property(notice, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.44)
	tween.set_parallel(true)
	tween.tween_property(title, "modulate:a", 0.0, 0.78).set_trans(Tween.TRANS_SINE)
	if new_level > 0:
		var level_label := notice.get_node("LevelUpWorldLevel") as Label3D
		tween.tween_property(level_label, "modulate:a", 0.0, 0.78).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(notice.queue_free)

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
