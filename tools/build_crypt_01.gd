extends SceneTree
## Writes the Crypt scene (res://game/world/dungeons/crypt_01.tscn) from the plan in CryptLayout, by CryptBaker. Run only to START OVER: the scene is
## the dungeon's source, and hand edits made to it in the editor are replaced by what this writes.
##   godot --headless --path . -s res://tools/build_crypt_01.gd

func _initialize() -> void:
	var baker := CryptBaker.new()
	var error: int = baker.build()
	quit(0 if error == OK else 1)
