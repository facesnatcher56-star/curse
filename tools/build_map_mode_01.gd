extends SceneTree
## Writes the map-mode scene (res://game/world/dungeons/map_mode_01.tscn) from the plan in MapModeLayout, by MapModeBaker. Run only to START OVER: the
## scene is the dungeon's source, and hand edits made to it in the editor are replaced by what this writes.
##   godot --headless --path . -s res://tools/build_map_mode_01.gd

func _initialize() -> void:
	var baker := MapModeBaker.new()
	var error: int = baker.build()
	quit(0 if error == OK else 1)
