class_name TakeAimTrail
extends Node3D
## The empowered arrow's wake: a thin, tapered cut through the air that is silver-green at the arrow and dark emerald at its tail,
## breaks into fragments toward the end and lives only a moment, so it shortens with the arrow's speed. Samples are world-space, so
## the strip stays where the arrow was while it moves on (and after it sticks, the remainder simply fades).

const LIFE := 0.17
const WIDTH := 0.012
const MAX_SAMPLES := 18

var arrow: Node3D
var _samples: Array[Dictionary] = []
var _mesh := ImmediateMesh.new()
var _shaft: MeshInstance3D
var _flash: MeshInstance3D
var _spent := false

static func attach(to_arrow: Node3D, shaft_length: float) -> TakeAimTrail:
	var trail := TakeAimTrail.new()
	trail.name = "TakeAimTrail"
	trail.arrow = to_arrow
	to_arrow.add_child(trail)
	trail.top_level = true
	trail.global_transform = Transform3D.IDENTITY
	trail._build(to_arrow, shaft_length)
	return trail

func _build(to_arrow: Node3D, shaft_length: float) -> void:
	var strip := MeshInstance3D.new()
	strip.mesh = _mesh
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	strip.material_override = mat
	add_child(strip)
	# A narrow emerald line along the shaft and a silver edge at the head, carried by the arrow itself.
	_shaft = MeshInstance3D.new()
	_shaft.name = "TakeAimShaft"
	var line := CylinderMesh.new()
	line.top_radius = 0.0045
	line.bottom_radius = 0.0045
	line.height = shaft_length
	line.radial_segments = 6
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	line_mat.albedo_color = Color(0.2, 0.9, 0.5, 0.55)
	line.material = line_mat
	_shaft.mesh = line
	_shaft.position.y = -shaft_length * 0.5
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	to_arrow.add_child(_shaft)
	_flash = MeshInstance3D.new()
	var head := QuadMesh.new()
	head.size = Vector2(0.10, 0.10)
	var head_mat := StandardMaterial3D.new()
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	head_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	head_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	head_mat.albedo_texture = Fx.soft_texture()
	head_mat.albedo_color = Color(0.82, 1.0, 0.9, 0.85)
	head.material = head_mat
	_flash.mesh = head
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	to_arrow.add_child(_flash)

## The arrow has stopped: stop sampling, drop the shaft and head glow; the strip fades on its own.
func settle() -> void:
	_spent = true
	if is_instance_valid(_shaft):
		_shaft.queue_free()
	if is_instance_valid(_flash):
		_flash.queue_free()

func _process(delta: float) -> void:
	for sample in _samples:
		sample["age"] = float(sample["age"]) + delta
	while not _samples.is_empty() and float(_samples[0]["age"]) > LIFE:
		_samples.pop_front()
	if not _spent and is_instance_valid(arrow):
		var at: Vector3 = arrow.global_position
		if _samples.is_empty() or (_samples[_samples.size() - 1]["pos"] as Vector3).distance_to(at) > 0.04:
			_samples.append({"pos": at, "age": 0.0})
			if _samples.size() > MAX_SAMPLES:
				_samples.pop_front()
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		if _spent:
			queue_free()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var view: Vector3 = cam.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n: int = _samples.size()
	for i in n:
		var pos: Vector3 = _samples[i]["pos"]
		var prev: Vector3 = (_samples[maxi(i - 1, 0)]["pos"] as Vector3)
		var next: Vector3 = (_samples[mini(i + 1, n - 1)]["pos"] as Vector3)
		var dir: Vector3 = (next - prev).normalized()
		var side: Vector3 = dir.cross((view - pos).normalized()).normalized()
		var life: float = clampf(float(_samples[i]["age"]) / LIFE, 0.0, 1.0)   # 0 at the arrow, 1 at the tail's end
		var col: Color = SILVER_GREEN.lerp(DARK_EMERALD, life)
		# Fragmented toward the end: the oldest third breaks into broken beads.
		var broken: float = 1.0
		if life > 0.55:
			broken = 1.0 if (i % 2 == 0) else 0.25
		col.a = (1.0 - life) * 0.85 * broken
		var w: float = WIDTH * (1.0 - life * 0.9)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(pos + side * w)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(pos - side * w)
	_mesh.surface_end()

const SILVER_GREEN := Color(0.78, 1.0, 0.88)
const DARK_EMERALD := Color(0.03, 0.34, 0.17)
