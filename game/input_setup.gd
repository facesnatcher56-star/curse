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
