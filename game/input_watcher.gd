extends Node
## Autoload: feeds every input event to Gamepad so the pad/mouse switch (hidden mouse, pad hints) works in the menus,
## the loading screen and the game alike, including while the game is paused.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	Gamepad.note_event(event)
