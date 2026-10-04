class_name Gamepad
extends RefCounted
## Controller support (Xbox 360/One/Series and anything Godot maps the same way, over USB or Bluetooth).
##
##   Left stick   move (analog: a light push walks, a full push runs)
##   Right stick  aim: the cursor sits in front of the hero (further out the harder you push) and snaps to a nearby enemy.
##                Released, the nearest enemy in range is targeted automatically.
##   A            attack the target (hold to keep attacking)         B   dodge roll
##   X / Y        skills 1 / 2 (Power Strike, Cleave)                RB  skill 3 (Fireball: hold to aim, release to cast)
##   LB           skill 4 (potion)                                   RT  skill 5 (Skewer)        LT  skill 6 (Leap)
##   R3 (press the right stick)  skill 7: the ultimate, Earthshatter
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

static func device() -> int:
	var pads: Array[int] = Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1

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

## Called for every input event: tracks whether the pad or the mouse/keyboard is the active device.
static func note_event(event: InputEvent) -> void:
	var was: bool = active
	if event is InputEventJoypadButton:
		active = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.4:
			active = true
	elif event is InputEventKey or event is InputEventMouseButton:
		active = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 3.0:
		active = false
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
	return "%s move   %s aim   %s attack   %s/%s/%s/%s/%s/%s skills   %s ultimate   %s dodge   %s gear   %s pause" % [move, aim,
		label_for("alt_skill"), label_for("skill_1"), label_for("skill_2"), label_for("skill_3"), label_for("skill_4"),
		label_for("skill_5"), label_for("skill_6"), label_for("skill_7"), label_for("dodge"), label_for("gear"), label_for("pause")]
