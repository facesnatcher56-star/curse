extends DevSuite
## The dungeon level scene (game/world/dungeon_level.tscn): it holds what the game needs (floors, walls, props, chests, rock, enemy groups, a
## start), its enemy groups read back with everything the editor lets you set, and the monster generator fills a level with groups that stand
## on its floor, clear of the start, props and chests. (The scene wired into a running game is checked by game/dev/dungeon_check.gd.)

func _test_dungeon_scene() -> void:
	var level: Node3D = (load(TestDungeon.LEVEL_SCENE) as PackedScene).instantiate() as Node3D
	var parts_ok: bool = true
	for part in ["Floor", "Walls", "Pillars", "Props", "Torches", "Rock", "Chests", "EnemyGroups", "PlayerStart"]:
		parts_ok = parts_ok and level.has_node(part)
	expect("the level scene holds floors, walls, pillars, props, torches, rock, chests, enemy groups and a start", parts_ok)
	expect("it holds a real level (2000+ floor tiles, 700+ wall pieces, 5 chests, 160 props)", level.get_node("Floor").get_child_count() > 2000
		and level.get_node("Walls").get_child_count() > 700 and level.get_node("Chests").get_child_count() == 5 and level.get_node("Props").get_child_count() >= 150)
	var groups: Array = TestDungeon.read_groups(level)
	var areas: Dictionary = {}
	for group in groups:
		areas[int(group["area"])] = true
	expect("its enemy groups cover every area of the critical path (%d groups)" % groups.size(), groups.size() >= 30 and areas.size() == TestDungeon.AREAS.size())
	var rows: Array = TestDungeon.project(HeroProgression.xp_for_level(1), groups)
	expect("the projection reads the scene's groups (a level for every area, rising)", rows.size() == TestDungeon.AREAS.size()
		and int(rows[rows.size() - 1]["level"]) > int(rows[0]["level"]))
	# What the editor lets you set on a group reads back: its level, behaviour, patrol loop, spawn points and feed point.
	var marker := DungeonEnemyGroup.new()
	marker.position = Vector3(10.0, 0.0, 20.0)
	marker.area = 3
	marker.level_offset = 2
	marker.fixed_level = 0
	marker.behaviour = DungeonEnemyGroup.Behaviour.WANDER
	marker.kinds = [["zombie", 2]]
	for name_and_spot in [["Patrol1", Vector3(12, 0, 20)], ["Patrol2", Vector3(12, 0, 24)], ["Spawn1", Vector3(9, 0, 19)], ["FeedPoint", Vector3(11, 0, 21)]]:
		var child := Marker3D.new()
		child.name = String(name_and_spot[0])
		child.position = (name_and_spot[1] as Vector3) - marker.position
		marker.add_child(child)
	level.get_node("EnemyGroups").add_child(marker)
	var read: Dictionary = TestDungeon.read_groups(level)[TestDungeon.read_groups(level).size() - 1]
	expect("a group's level offset, behaviour, patrol loop, spawn point and feed point read back",
		int(read["level_offset"]) == 2 and String(read["mode"]) == "wander" and (read["patrol"] as Array).size() == 2
		and (read["spawns"] as Array).size() == 1 and read["feed"] == Vector2(11, 21) and (read["patrol"] as Array)[1] == Vector2(12, 24))
	# The generator.
	var made: int = DungeonMonsterGenerator.generate(level, 11, 1.0)
	var generated: Array = TestDungeon.read_groups(level)
	var start: Vector3 = (level.get_node("PlayerStart") as Node3D).position
	var tiles: Array[Vector2] = []
	for tile in level.get_node("Floor").get_children():
		tiles.append(Vector2((tile as Node3D).position.x, (tile as Node3D).position.z))
	var all_on_floor: bool = true
	var all_clear_of_start: bool = true
	for group in generated:
		var home: Vector2 = group["home"]
		var nearest: float = INF
		for tile in tiles:
			nearest = minf(nearest, home.distance_to(tile))
		all_on_floor = all_on_floor and nearest < 2.5
		all_clear_of_start = all_clear_of_start and home.distance_to(Vector2(start.x, start.z)) >= DungeonMonsterGenerator.MIN_FROM_START
	expect("the generator makes groups in every area (%d)" % made, made >= 30 and generated.size() == made)
	expect("every generated group stands on the floor and well away from the start", all_on_floor and all_clear_of_start)
	expect("the final hall has its warden", generated.any(func(g: Dictionary) -> bool: return int(g["area"]) == 10 and (g["kinds"] as Array).any(func(k: Array) -> bool: return k[0] == "warden")))
	var again: int = DungeonMonsterGenerator.generate(level, 11, 1.0)
	expect("the same seed makes the same groups, and a lower density makes fewer", again == made and DungeonMonsterGenerator.generate(level, 11, 0.5) < made)
	level.free()
