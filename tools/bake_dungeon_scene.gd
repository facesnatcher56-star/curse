extends SceneTree
## Writes the dungeon level scene (res://game/world/dungeon_level.tscn) from the plan in DungeonBaker. Run only to START OVER: the scene is the
## level's source, and hand edits made to it in the editor are replaced by what this writes.
##   godot --headless --path . -s res://tools/bake_dungeon_scene.gd

const OUT := "res://game/world/dungeon_level.tscn"

func _initialize() -> void:
	var arena := TestDungeon.make_arena()
	root.add_child(arena)
	arena.build(false)
	var nav: NavigationRegion3D = arena.get("_nav_region")
	var before: Array = nav.get_children()   # the arena's own ground: not part of the level
	var baker := DungeonBaker.new()
	root.add_child(baker)
	baker.build(arena)
	var error: int = baker.pack_scene(OUT, before)
	quit(0 if error == OK else 1)
