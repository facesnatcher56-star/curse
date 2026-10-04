class_name CameraRig
extends Node3D
## Fixed-angle perspective camera that follows the hero, like the original's 3/4 view.

@export var offset: Vector3 = Vector3(0.0, 9.0, 6.5)
@export var pitch_degrees: float = -54.0
@export var fov: float = 38.0
@export var follow_speed: float = 8.0

## Scroll wheel zooms along the view direction; the angle stays fixed. Movement is eased, not stepped.
const ZOOM_MIN := 0.5
const ZOOM_MAX := 1.8
const ZOOM_EASE := 9.0

var _fov_kick: float = 0.0
var _zoom: float = 1.0
var _zoom_target: float = 1.0

var target: Node3D
var camera: Camera3D
var _shake: float = 0.0

func _ready() -> void:
	add_to_group("camera_rig")
	# This node is moved from _process (smooth follow), so it must not be physics-interpolated itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.fov = fov
	camera.current = true
	camera.position = offset
	camera.rotation_degrees = Vector3(pitch_degrees, 0.0, 0.0)
	add_child(camera)

var _kick: Vector3 = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		_zoom_target = clampf(_zoom_target - GameSettings.zoom_step, ZOOM_MIN, ZOOM_MAX)
	elif event.is_action_pressed("zoom_out"):
		_zoom_target = clampf(_zoom_target + GameSettings.zoom_step, ZOOM_MIN, ZOOM_MAX)

## Quick narrowing of the field of view; reads as the camera punching in on a heavy impact.
func punch(amount: float) -> void:
	_fov_kick = maxf(_fov_kick, amount)

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func kick(direction: Vector3, amount: float) -> void:
	_kick += direction.normalized() * amount

func _process(delta: float) -> void:
	_kick = _kick.lerp(Vector3.ZERO, clampf(10.0 * delta, 0.0, 1.0))
	if target != null:
		# With physics interpolation on, the target is drawn between physics ticks; follow that, not the raw tick.
		var focus: Vector3 = target.get_global_transform_interpolated().origin
		global_position = global_position.lerp(focus, clampf(follow_speed * delta, 0.0, 1.0)) + _kick * delta * 6.0
	# Frame-rate independent easing toward the zoom target.
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-ZOOM_EASE * delta))
	camera.position = offset * _zoom
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-14.0 * delta))
	camera.fov = fov - _fov_kick
	_shake = move_toward(_shake, 0.0, delta * 0.9)
	camera.h_offset = randf_range(-_shake, _shake)
	camera.v_offset = randf_range(-_shake, _shake)
