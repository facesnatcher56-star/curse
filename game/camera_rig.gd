class_name CameraRig
extends Node3D
## Fixed-angle perspective camera that follows the hero, like the original's 3/4 view.

@export var offset: Vector3 = Vector3(0.0, 9.0, 6.5)
@export var pitch_degrees: float = -54.0
@export var fov: float = 38.0
@export var follow_speed: float = 8.0

## Scroll wheel zooms along the view direction; the angle stays fixed. Movement is eased, not stepped.
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.2
const ZOOM_EASE := 9.0

## Hold the "camera_rotate" button (middle mouse) and drag sideways to swing the camera around the hero. The angle eases toward
## where the drag asks for, so it glides instead of snapping. A middle click without a drag puts the camera back behind the hero.
const ROTATE_PER_PIXEL := 0.0055
const ROTATE_EASE := 11.0
const CLICK_PIXELS := 6.0
const PAD_ROTATE_SPEED := 2.2    # radians per second at full stick
const PAD_ZOOM_SPEED := 1.6      # zoom units per second at full stick

var yaw: float = 0.0            # what is drawn (eased)
var _yaw_target: float = 0.0
var _rotating: bool = false
var _drag_pixels: float = 0.0
var _saved_mouse: Vector2 = Vector2.ZERO
var fog_env: Environment      # fog thins out as the camera pulls back, so a wide view is not murky
var _base_fog: float = -1.0
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
	if event.is_action_pressed("camera_rotate"):
		_begin_rotate()
	elif event.is_action_released("camera_rotate"):
		_end_rotate()
	elif _rotating and event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		_drag_pixels += absf(motion.relative.x) + absf(motion.relative.y)
		rotate_view(-motion.relative.x * ROTATE_PER_PIXEL)
	if event.is_action_pressed("zoom_in"):
		_zoom_target = clampf(_zoom_target - GameSettings.zoom_step, ZOOM_MIN, ZOOM_MAX)
	elif event.is_action_pressed("zoom_out"):
		_zoom_target = clampf(_zoom_target + GameSettings.zoom_step, ZOOM_MIN, ZOOM_MAX)

## A new run starts fully zoomed out (the widest view).
func start_zoomed_out() -> void:
	_zoom_target = ZOOM_MAX
	_zoom = ZOOM_MAX

## Swings the camera by `radians` (eased). Positive turns the view counter-clockwise seen from above.
func rotate_view(radians: float) -> void:
	_yaw_target = wrapf(_yaw_target + radians, -PI, PI)

## Right stick: left/right orbits the camera, up/down zooms (up = closer). It is the target-area stick while Fireball is held.
func _pad_camera(delta: float) -> void:
	if not Gamepad.active:
		return
	var player := target as Player
	if player != null and player.skills.aiming_id != "":
		return
	var stick: Vector2 = Gamepad.aim_vector()
	if stick.length() <= 0.0:
		return
	rotate_view(-stick.x * PAD_ROTATE_SPEED * delta)
	_zoom_target = clampf(_zoom_target + stick.y * PAD_ZOOM_SPEED * delta, ZOOM_MIN, ZOOM_MAX)

## Back behind the hero (the default angle).
func reset_view() -> void:
	_yaw_target = 0.0

func _begin_rotate() -> void:
	_rotating = true
	_drag_pixels = 0.0
	if DisplayServer.get_name() != "headless":
		_saved_mouse = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # the pointer cannot hit a screen edge mid-drag

func _end_rotate() -> void:
	if not _rotating:
		return
	_rotating = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if Gamepad.active else Input.MOUSE_MODE_VISIBLE
		Input.warp_mouse(_saved_mouse)
	if _drag_pixels < CLICK_PIXELS:
		reset_view()

## Quick narrowing of the field of view; reads as the camera punching in on a heavy impact.
func punch(amount: float) -> void:
	_fov_kick = maxf(_fov_kick, amount)

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func kick(direction: Vector3, amount: float) -> void:
	_kick += direction.normalized() * amount

func _process(delta: float) -> void:
	_kick = _kick.lerp(Vector3.ZERO, clampf(10.0 * delta, 0.0, 1.0))
	_pad_camera(delta)
	yaw = lerp_angle(yaw, _yaw_target, 1.0 - exp(-ROTATE_EASE * delta))
	rotation.y = yaw
	Gamepad.view_yaw = yaw   # sticks and the minimap follow the view
	if target != null:
		# With physics interpolation on, the target is drawn between physics ticks; follow that, not the raw tick.
		var focus: Vector3 = target.get_global_transform_interpolated().origin
		global_position = global_position.lerp(focus, clampf(follow_speed * delta, 0.0, 1.0)) + _kick * delta * 6.0
	# Frame-rate independent easing toward the zoom target.
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-ZOOM_EASE * delta))
	camera.position = offset * _zoom
	if fog_env != null:
		if _base_fog < 0.0:
			_base_fog = fog_env.fog_density
		fog_env.fog_density = _base_fog / maxf(_zoom, 1.0)
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-14.0 * delta))
	camera.fov = fov - _fov_kick
	_shake = move_toward(_shake, 0.0, delta * 0.9)
	camera.h_offset = randf_range(-_shake, _shake)
	camera.v_offset = randf_range(-_shake, _shake)
