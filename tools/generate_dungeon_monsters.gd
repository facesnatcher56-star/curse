extends SceneTree
## Re-rolls the monsters of the dungeon level scene: replaces its EnemyGroups with a fresh set from the plan in DungeonMonsterGenerator,
## leaving floors, walls, props and chests as they are. Hand-placed groups in the scene ARE replaced (git is the backup), so to keep
## some, generate into a copy with --out= and move the markers you want across in the editor.
##   godot --headless --path . -s res://tools/generate_dungeon_monsters.gd -- [--seed=N] [--density=1.0] [--out=res://path.tscn]
## --density scales how many groups each area gets (0.5 is half as many, 2 is twice).

const LEVEL := "res://game/world/dungeon_level.tscn"

func _initialize() -> void:
	var rng_seed: int = 2525
	var density: float = 1.0
	var out: String = LEVEL
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			rng_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--density="):
			density = float(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
	var level: Node3D = (load(LEVEL) as PackedScene).instantiate() as Node3D
	var made: int = DungeonMonsterGenerator.generate(level, rng_seed, density)
	var groups: Array = TestDungeon.read_groups(level)
	var members: int = 0
	for group in groups:
		for pair in group["kinds"]:
			members += int(pair[1])
	var packed := PackedScene.new()
	var error: int = packed.pack(level)
	if error == OK:
		error = ResourceSaver.save(packed, out)
	print("DUNGEON_MONSTERS %s: %d groups, %d monsters (seed %d, density %.2f, error %d)" % [out, made, members, rng_seed, density, error])
	level.free()
	quit(0 if error == OK else 1)
