class_name DebrisChunk
extends Node3D
## One piece of a broken prop: a small solid thrown with a velocity and a spin, bouncing a couple of times on the ground, lying there
## for a few seconds, then shrinking away. Kept to a fixed number so a long fight does not pile up a thousand splinters.

const GRAVITY := 22.0
const LIFETIME := 7.0
const MAX_CHUNKS := 140

var velocity: Vector3 = Vector3.ZERO
var spin: Vector3 = Vector3.ZERO
var limit: Vector2 = Vector2(Arena.HALF, Arena.HALF) - Vector2(0.6, 0.6)   # how far from the middle they may land (the arena's walls)

var _age: float = 0.0
var _rest: float = 0.0
var _half_height: float = 0.03
var _mesh: MeshInstance3D

func setup(size: Vector3, color: Color, glow: bool) -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.08)
		mat.emission_energy_multiplier = 1.5
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_half_height = minf(minf(size.x, size.y), size.z) * 0.5

func _ready() -> void:
	add_to_group("debris")
	var all: Array[Node] = get_tree().get_nodes_in_group("debris")
	if all.size() > MAX_CHUNKS:
		all[0].queue_free()   # the oldest goes first

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	if _age > LIFETIME - 1.2:
		_mesh.scale = Vector3.ONE * clampf((LIFETIME - _age) / 1.2, 0.01, 1.0)
	if _rest > 0.0:
		return
	velocity.y -= GRAVITY * delta
	global_position += velocity * delta
	rotation += spin * delta
	if global_position.y <= _half_height:
		global_position.y = _half_height
		if velocity.y < -1.5:
			velocity.y *= -0.32
			velocity.x *= 0.62
			velocity.z *= 0.62
			spin *= 0.55
		else:
			velocity = Vector3.ZERO
			spin = Vector3.ZERO
			_rest = 1.0
	# They cannot leave the arena through the invisible walls.
	global_position.x = clampf(global_position.x, -limit.x, limit.x)
	global_position.z = clampf(global_position.z, -limit.y, limit.y)
