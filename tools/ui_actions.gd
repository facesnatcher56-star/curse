extends SceneTree
## `godot --headless --path . --script tools/ui_actions.gd`: lists the events bound to the built-in menu actions.
func _init() -> void:
	for action in ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right"]:
		var parts: Array[String] = []
		for ev in InputMap.action_get_events(action):
			parts.append(ev.as_text())
		print(action, ": ", ", ".join(parts))
	quit()
