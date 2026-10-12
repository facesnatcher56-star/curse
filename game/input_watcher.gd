extends Node
var _switch_held: bool = false
## Autoload: feeds every input event to Gamepad so the pad/mouse switch (hidden mouse, pad hints) works in the menus,
## the loading screen and the game alike, including while the game is paused.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	Gamepad.note_event(event)
	for menu in get_tree().get_nodes_in_group("settings_menu"):
		if menu._listening_action != "": return
	if InputMap.has_action("party_switch") and event.is_action("party_switch"):
		if event.is_action_released("party_switch"):
			_switch_held = false
		elif event.is_action_pressed("party_switch") and not event.is_echo() and not _switch_held:
			_switch_held = true
			PartyManager.current().cycle()
		get_viewport().set_input_as_handled()
