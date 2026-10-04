extends Node
## Keeps receiving input while the game is paused, and hands it to the main scene (which itself pauses with the rest of the world,
## so that pausing really does freeze the hero, enemies, projectiles and effects). Only forwards while paused: otherwise the
## main scene already gets the event directly.

signal unhandled(event: InputEvent)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		unhandled.emit(event)
