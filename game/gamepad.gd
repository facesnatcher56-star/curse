class_name Gamepad
extends RefCounted
## Controller support (Xbox 360/One/Series and anything Godot maps the same way, over USB or Bluetooth).
##
##   Left stick   move (analog: a light push walks, a full push runs)
##   Right stick  camera: left/right turns it, up/down zooms. While an aimed skill (Fireball) is held it slides the target area instead.
##                The target is always the enemy nearest to where the hero faces; holding A attacks it.
##   A            attack the target (hold to keep attacking)         B   dodge roll
##   X / Y        Power Strike / Fireball (hold to aim, release)     RB  potion
##   LB           Skewer                                             RT  Leap
##   R3 (press the right stick)  Earthshatter
##   D-pad up/down  camera zoom       L3  stand still (hold)         Back  gear (hold)           Start  pause
## The buttons are ordinary input actions (see InputSetup), so they also work in menus and on the reward screen.

## True once the pad was the last thing used; flips back to false the moment the mouse or keyboard is touched.
static var active: bool = false
## Tests inject stick positions here (axis -> value); when non-empty it replaces the real device.
static var test_axes: Dictionary = {}
## The camera's turn around the hero (set by CameraRig): "stick up" means up the screen, wherever the camera is looking.
static var view_yaw: float = 0.0

## A stick or screen-space vector (x right, y down the screen) as a world direction.
static func to_world(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y).rotated(Vector3.UP, view_yaw)

## The controller used last (the Deck's own pad and an Xbox pad can both be connected); note_event keeps it current.
static var _last_device: int = -1

static func device() -> int:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		return -1
	return _last_device if pads.has(_last_device) else pads[0]

static func connected() -> bool:
	return device() >= 0 or not test_axes.is_empty()

static func axis(which: int) -> float:
	if not test_axes.is_empty():
		return float(test_axes.get(which, 0.0))
	var d: int = device()
	return Input.get_joy_axis(d, which as JoyAxis) if d >= 0 else 0.0

## A stick as a vector with a radial dead zone, rescaled so the edge of the dead zone is 0 and a full push is 1.
static func _stick(ax: int, ay: int) -> Vector2:
	var v := Vector2(axis(ax), axis(ay))
	var length: float = v.length()
	var dead: float = GameSettings.stick_deadzone
	if length < dead:
		return Vector2.ZERO
	return v.normalized() * minf((length - dead) / (1.0 - dead), 1.0)

## Movement and aiming normally use the left and right sticks; "swap sticks" in the settings reverses that.
static func move_vector() -> Vector2:
	if GameSettings.swap_sticks:
		return _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	return _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)

static func aim_vector() -> Vector2:
	if GameSettings.swap_sticks:
		return _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	return _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)

static var _mouse_ms: int = -100000   # when the mouse or keyboard was last used
static var _pad_ms: int = -100000     # when the pad was last used deliberately
const MOUSE_PRIORITY_MS := 400
## Steam Input (the Steam Deck's default layout) turns sticks and buttons into mouse moves, clicks and keys. Those arrive
## right alongside the pad's own events, so while the pad is in use they must not hand control back to the mouse.
const PAD_PRIORITY_MS := 600

## Called for every input event (by the InputWatcher autoload): tracks whether the pad or the mouse/keyboard is the active
## device. A button press, or a stick pushed well off centre, hands control to the pad; a mouse move or any key or click takes
## it back. Trigger axes that rest at -1 (some drivers do) and stick drift never count, and for a moment after the mouse was
## used a wobbling pad cannot steal control from it.
static func note_event(event: InputEvent) -> void:
	var was: bool = active
	var now: int = Time.get_ticks_msec()
	if event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			active = true
			_pad_ms = now
			_last_device = event.device
	elif event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		var is_trigger: bool = motion.axis == JOY_AXIS_TRIGGER_LEFT or motion.axis == JOY_AXIS_TRIGGER_RIGHT
		var deliberate: bool = motion.axis_value > 0.6 if is_trigger else absf(motion.axis_value) > 0.55
		if deliberate:
			_pad_ms = now
			_last_device = motion.device
			if now - _mouse_ms > MOUSE_PRIORITY_MS:
				active = true
	elif event is InputEventKey or event is InputEventMouseButton:
		if not (active and now - _pad_ms < PAD_PRIORITY_MS):
			active = false
			_mouse_ms = now
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 1.5:
		if not (active and now - _pad_ms < PAD_PRIORITY_MS):
			active = false
			_mouse_ms = now
	if active != was and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if active else Input.MOUSE_MODE_VISIBLE

## Short force-feedback pulse (weak = high-frequency motor, strong = low-frequency).
static func rumble(weak: float, strong: float, seconds: float) -> void:
	var d: int = device()
	if d >= 0 and active and GameSettings.vibration:
		Input.start_joy_vibration(d, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)

## The pad button currently bound to an action ("" if none), so hints follow rebinding.
static func label_for(action: String) -> String:
	var text: String = GameSettings.pad_binding_text(action)
	return "" if text == "Unbound" or text == "-" else text

static func help_text() -> String:
	var move: String = "R-stick" if GameSettings.swap_sticks else "L-stick"
	var aim: String = "L-stick" if GameSettings.swap_sticks else "R-stick"
	return "%s move   %s camera (aim while holding Fireball)   %s attack   %s/%s/%s/%s/%s skills   %s ultimate   %s dodge   %s gear   %s pause" % [move, aim,
		label_for("alt_skill"), label_for("skill_1"), label_for("skill_2"), label_for("skill_3"), label_for("skill_4"),
		label_for("skill_5"), label_for("skill_6"), label_for("dodge"), label_for("gear"), label_for("pause")]
