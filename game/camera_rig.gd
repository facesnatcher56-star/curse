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

## Impact response. Every hit, landing and blast reaches the camera through shake()/kick()/punch() (see Fx), so the limits live here:
## an impulse is short, decays fast and cannot pile up past a ceiling, however many things hit in the same moment.
const MAX_SHAKE := 0.35          # the largest sway of the view, whatever is asked for (the Screen shake setting can scale it up to 1.5x)
const SHAKE_DECAY := 10.0        # exponential decay per second: a heavy blow is gone in about a third of a second
const SHAKE_FLOOR := 0.3         # plus a steady fall so a faint tremble ends instead of lingering
const SHAKE_HZ := Vector2(11.0, 14.0)   # smooth sway on two unrelated rhythms; random jitter every frame was frame-rate noise, not a thud
const SHAKE_VERTICAL := 0.7      # up and down sways less than side to side
const MAX_KICK := 1.0            # the largest shove (the view moves about 0.6 of it, then eases back)
const MAX_PUNCH := 3.5           # the largest FOV punch-in, in degrees
const DEATH_SHAKE := 0.2         # the death itself may keep this much sway; everything else is dropped

var target: Node3D
var camera: Camera3D
var _shake: float = 0.0
var _shake_clock: float = 0.0
var _kick_frame: int = -1        # the process frame the shove below arrived in
var _kick_frame_vec: Vector3 = Vector3.ZERO
var _target_id: int = 0
var _target_dead: bool = false

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
## Jumps to a zoom level (ZOOM_MIN..ZOOM_MAX) without easing.
func set_zoom_now(value: float) -> void:
	_zoom_target = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_zoom = _zoom_target

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
	_fov_kick = minf(maxf(_fov_kick, amount), MAX_PUNCH)

## A sway of the view. Impulses do not add: the strongest one in play wins, so a blow that reports itself from several places at once
## (the swing, the ragdoll, the hit-pause) is still one blow.
func shake(amount: float) -> void:
	_shake = maxf(_shake, minf(amount, MAX_SHAKE))

## A shove along `direction` (flattened: the view never dips into the ground). Shoves from the same frame do not add up: a crowd
## landing blows together pushes the camera as hard as its strongest member, and the total is capped.
func kick(direction: Vector3, amount: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.001 or amount <= 0.0:
		return
	var shove: Vector3 = flat.normalized() * amount
	var frame: int = Engine.get_process_frames()
	if frame == _kick_frame:
		if shove.length() <= _kick_frame_vec.length():
			return
		_kick -= _kick_frame_vec
	_kick_frame = frame
	_kick_frame_vec = shove
	_kick = (_kick + shove).limit_length(MAX_KICK)

## Drops every transient effect (shove, sway, FOV punch) and puts the view back to its resting frame.
func reset_transients() -> void:
	_kick = Vector3.ZERO
	_kick_frame_vec = Vector3.ZERO
	_kick_frame = -1
	_shake = 0.0
	_fov_kick = 0.0
	if camera != null:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.fov = fov

## The hero falling or being dragged home ends the effects of the blows that got him there; getting up starts from a still view.
func _watch_target() -> void:
	var id: int = target.get_instance_id() if target != null else 0
	var dead_now: bool = target != null and target.get("dead") == true
	if id != _target_id:
		_target_id = id
		_target_dead = dead_now
		reset_transients()
	elif dead_now != _target_dead:
		_target_dead = dead_now
		if dead_now:
			_kick = Vector3.ZERO
			_fov_kick = 0.0
			_shake = minf(_shake, DEATH_SHAKE)
		else:
			reset_transients()

func _process(delta: float) -> void:
	_watch_target()
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
	_shake = move_toward(_shake * exp(-SHAKE_DECAY * delta), 0.0, SHAKE_FLOOR * delta)
	if _shake <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	else:
		_shake_clock += delta
		camera.h_offset = _shake * sin(_shake_clock * TAU * SHAKE_HZ.x)
		camera.v_offset = _shake * SHAKE_VERTICAL * sin(_shake_clock * TAU * SHAKE_HZ.y + 1.3)
