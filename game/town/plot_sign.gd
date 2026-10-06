class_name PlotSign
extends Node3D
## A sign out on the road that a monster's plot is under way: a dread altar going up, a war banner and fire for a raid, a pile of bones and
## smoke for an uprising. It grows as the plot nears its end and goes when the plot does. Charred, crooked, built of what is lying about:
## stone, bone, rope and a low ember light, the same material language as everything else.

var plot_type: String = ""
var monster_uid: int = -1
var _body: Node3D
var _light: OmniLight3D
var _base_energy: float = 1.0
var _time: float = randf() * 10.0

static func spawn(parent: Node, at: Vector3, type: String, uid: int) -> PlotSign:
	var made := PlotSign.new()
	made.plot_type = type
	made.monster_uid = uid
	parent.add_child(made)
	made.global_position = at
	made.add_to_group("plot_signs")
	made._build()
	return made

func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _part(mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, emission: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color, emission)
	node.position = pos
	node.rotation = rot
	_body.add_child(node)
	return node

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 7
	return c

func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var stone := Color(0.17, 0.155, 0.15)
	var bone := Color(0.55, 0.52, 0.44)
	var rag := Color(0.28, 0.07, 0.06)
	var ember := Color(1.0, 0.4, 0.14)
	match plot_type:
		"altar":
			_part(_box(Vector3(2.8, 0.4, 1.8)), stone, Vector3(0, 0.2, 0))
			for corner in [Vector2(-1.2, -0.7), Vector2(1.2, -0.7), Vector2(-1.2, 0.7), Vector2(1.2, 0.7)]:
				var tall: float = 1.6 + 0.5 * absf(sin(corner.x * 3.0 + corner.y))
				_part(_cyl(0.18, 0.28, tall), stone, Vector3(corner.x, tall * 0.5 + 0.3, corner.y), Vector3(0.05 * corner.y, 0, 0.07 * corner.x))
			_part(_box(Vector3(1.3, 0.5, 0.8)), Color(0.1, 0.09, 0.09), Vector3(0, 0.65, 0))
			var core := SphereMesh.new()
			core.radius = 0.28
			core.height = 0.56
			_part(core, ember, Vector3(0, 1.4, 0), Vector3.ZERO, 3.0)
		"raid":
			_part(_cyl(0.07, 0.1, 4.2), Color(0.2, 0.15, 0.1), Vector3(0, 2.1, 0), Vector3(0, 0, 0.06))
			_part(_box(Vector3(1.3, 1.4, 0.05)), rag, Vector3(0.7, 3.3, 0), Vector3(0, 0, -0.08))
			for log in 3:
				_part(_cyl(0.12, 0.12, 1.6), Color(0.14, 0.1, 0.07), Vector3(2.0, 0.15, -0.5 + 0.5 * log), Vector3(0, 0.6 * log, PI / 2.0))
			_part(_box(Vector3(0.6, 0.35, 0.6)), ember, Vector3(2.0, 0.5, 0.0), Vector3.ZERO, 2.5)
			_smoke(Vector3(2.0, 0.8, 0.0), Color(0.12, 0.11, 0.11, 0.35))
		"uprising":
			for i in 14:
				var angle: float = i * 2.4
				_part(_box(Vector3(0.12, 0.12, 0.7 + 0.1 * (i % 3))), bone, Vector3(cos(angle) * (0.4 + 0.1 * i), 0.1 + 0.05 * (i % 4), sin(angle) * (0.4 + 0.1 * i)),
					Vector3(0.3 * i, angle, 0.2 * (i % 3)))
			var skull := SphereMesh.new()
			skull.radius = 0.28
			skull.height = 0.5
			_part(skull, bone, Vector3(0, 0.45, 0))
			_smoke(Vector3(0, 0.6, 0), Color(0.15, 0.14, 0.12, 0.3))
		_:
			_part(_cyl(0.05, 0.05, 2.2), Color(0.2, 0.15, 0.1), Vector3(0, 1.1, 0))
	_light = OmniLight3D.new()
	_light.light_color = ember
	_light.omni_range = 7.0
	_light.position = Vector3(0, 1.6, 0)
	add_child(_light)
	set_progress(0.0)

## A slow column of smoke, tall enough to be seen from far down the road.
func _smoke(pos: Vector3, color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 24
	particles.lifetime = 7.0
	particles.position = pos
	particles.visibility_aabb = AABB(Vector3(-12, -1, -12), Vector3(24, 40, 24))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 8.0
	process.initial_velocity_min = 2.2
	process.initial_velocity_max = 3.2
	process.gravity = Vector3(0.4, 0.0, 0.0)
	process.scale_min = 1.2
	process.scale_max = 2.6
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = color
	quad.material = mat
	particles.draw_pass_1 = quad
	_body.add_child(particles)

## 0..1: how far the plot has got. The sign is small and faint at first and full size at the end.
func set_progress(fraction: float) -> void:
	var f: float = clampf(fraction, 0.0, 1.0)
	_body.scale = Vector3.ONE * lerpf(0.55, 1.0, f)
	_base_energy = lerpf(0.8, 2.2, f)

func _process(delta: float) -> void:
	_time += delta
	if _light != null:
		_light.light_energy = _base_energy * (0.9 + 0.1 * sin(_time * 11.0))   # a slight flicker
