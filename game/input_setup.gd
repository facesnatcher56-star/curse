class_name InputSetup
extends RefCounted
## Registers input actions in code so the project does not depend on hand-edited project.godot input maps.

static func apply() -> void:
	_mouse("click", MOUSE_BUTTON_LEFT)
	_mouse("alt_skill", MOUSE_BUTTON_RIGHT)
	_mouse("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_mouse("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)
	_key("stand_still", KEY_CTRL)
	_key("restart", KEY_R)
	_key("dodge", KEY_SPACE)
	_key("gear", KEY_TAB)
	_key("pause", KEY_ESCAPE)
	for i in 6:
		_key("skill_%d" % (i + 1), KEY_1 + i)
	_apply_gamepad()

## Controller bindings (see Gamepad for the layout). Added next to the keyboard ones, never instead of them.
static func _apply_gamepad() -> void:
	_pad_button("alt_skill", JOY_BUTTON_A)
	_pad_button("restart", JOY_BUTTON_A)
	_pad_button("dodge", JOY_BUTTON_B)
	_pad_button("skill_1", JOY_BUTTON_X)
	_pad_button("skill_2", JOY_BUTTON_Y)
	_pad_button("skill_3", JOY_BUTTON_RIGHT_SHOULDER)
	_pad_button("skill_4", JOY_BUTTON_LEFT_SHOULDER)
	_pad_trigger("skill_5", JOY_AXIS_TRIGGER_RIGHT)
	_pad_trigger("skill_6", JOY_AXIS_TRIGGER_LEFT)
	_pad_button("stand_still", JOY_BUTTON_LEFT_STICK)
	_pad_button("gear", JOY_BUTTON_BACK)
	_pad_button("pause", JOY_BUTTON_START)
	_pad_button("zoom_in", JOY_BUTTON_DPAD_UP)
	_pad_button("zoom_out", JOY_BUTTON_DPAD_DOWN)

static func _pad_button(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		return
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton and (existing as InputEventJoypadButton).button_index == button:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button as JoyButton
	InputMap.action_add_event(action, event)

static func _pad_trigger(action: String, axis: int) -> void:
	if not InputMap.has_action(action):
		return
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadMotion and (existing as InputEventJoypadMotion).axis == axis:
			return
	var event := InputEventJoypadMotion.new()
	event.axis = axis as JoyAxis
	event.axis_value = 1.0
	InputMap.action_add_event(action, event)

static func _mouse(action: String, button: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button as MouseButton
	InputMap.action_add_event(action, event)

static func _key(action: String, keycode: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode as Key
	InputMap.action_add_event(action, event)
