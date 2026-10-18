extends DevSuite
## The Crypt (game/world/dungeons/crypt_01.tscn, `-- --crypt01`): the scene loads and holds what the game needs, the plan connects the start to the
## arena (also by the loop), packs follow the shared pack rules, the first pack is in sight, and the walls leave every doorway open. (The scene
## wired into a running game, its navigation and the walk are checked by game/dev/dungeon_walk.gd -- --crypt01.)

func _test_crypt_dungeon() -> void:
	var level: Node3D = (load(CryptDungeon.CRYPT_SCENE) as PackedScene).instantiate() as Node3D
	var parts_ok: bool = true
	for part in ["Floor", "Walls", "Pillars", "Props", "SetPieces", "Torches", "Scatter", "Chests", "EnemyGroups", "PlayerStart"]:
		parts_ok = parts_ok and level.has_node(part)
	expect("the Crypt scene holds floor, walls, props, set pieces, torches, scatter, chests, packs and a start", parts_ok)
	var floor_cells: int = (level.get_node("Floor/Floor") as GridMap).get_used_cells().size()
	var door_cells: int = 0
	for dir_name in ["N", "E", "S", "W"]:
		var walls := level.get_node("Walls/Walls" + dir_name) as GridMap
		for cell in walls.get_used_cells():
			door_cells += 1 if walls.mesh_library.get_item_name(walls.get_cell_item(cell)).begins_with("wall_doorway") else 0
	expect("it is a GridMap build of 12+ spaces with 22+ doorways (%d floor cells, %d doorways)" % [floor_cells, door_cells],
		CryptLayout.SPACES.size() >= 12 and floor_cells > 500 and door_cells >= 22)
	expect("every side room has its chest", level.get_node("Chests").get_child_count() == CryptLayout.CHESTS.size() and CryptLayout.CHESTS.size() >= 2)
	expect("props are dressed with ProtonScatter in every space (%d)" % level.get_node("Scatter").get_child_count(),
		level.get_node("Scatter").get_child_count() == CryptLayout.SPACES.size())
	# The refinement: curved rooms and chamfers (wall segments), and clutter several times the first pass's 672 scatter items.
	var scatter_items: int = 0
	for sc in level.get_node("Scatter").get_children():
		scatter_items += int((sc.get("modifier_stack").stack[0] as Object).get("amount"))
	expect("the rooms carry 3x+ the first pass's clutter (%d scatter items, was 672)" % scatter_items, scatter_items >= 672 * 3)
	expect("rotunda and arena are curved and corners chamfered (%d liner pieces)" % level.get_node("Liners").get_child_count(),
		level.get_node("Liners").get_child_count() >= 100 and CryptLayout.ROUNDS.has("rotunda") and CryptLayout.ROUNDS.has("arena"))
	# Lane S3: low flat floor detail with no collider, and the Crypt's own title.
	var detail: int = 0
	var blocking: int = 0
	var tall: float = 0.0
	for node in level.get_node("Decor").get_children():
		if node.has_meta("floor_detail"):
			detail += 1
			blocking += node.find_children("*", "CollisionObject3D", true, false).size()
			for mi in node.find_children("*", "MeshInstance3D", true, false):
				tall = maxf(tall, ((mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb()).end.y)
	expect("the room centres carry flat floor detail (%d marks, none higher than %.2f m)" % [detail, tall], detail >= 60 and tall <= 0.08)
	expect("floor detail has no collider, so it blocks nothing", blocking == 0)
	var title: String = CryptDungeon.new().banner_text({})
	expect("the Crypt's banner is its own title, not the Road's run text (%s)" % title.replace("
", " / "),
		title.begins_with("The Crypt") and not title.contains("Road") and not title.contains("Free run"))
	# The plan: the start reaches the arena, with and without the loop.
	var reach: Dictionary = _flood(CryptLayout.START_CELL, "")
	expect("the arena is reachable from the start through the plan", reach.has("arena"))
	expect("the plan has a loop: the arena is still reached with the choke point closed", _flood(CryptLayout.START_CELL, "choke").has("arena"))
	expect("the plan has a loop: the arena is still reached with the ossuary closed", _flood(CryptLayout.START_CELL, "ossuary").has("arena"))
	var all_reached: bool = true
	for space in CryptLayout.SPACES:
		all_reached = all_reached and reach.has(space)
	expect("every space of the plan is connected", all_reached)
	# Walls leave doorways open: a doorway has two jambs and nothing across its middle.
	var boxes: Array = CryptDungeon.wall_boxes("wall_doorway", 4.0)
	var open_gap: float = float((boxes[1]["centre"] as Vector3).x - (boxes[0]["centre"] as Vector3).x) - float((boxes[0]["size"] as Vector3).x)
	expect("a doorway's two jambs leave %.1f m open" % open_gap, boxes.size() == 2 and open_gap >= 2.0 and CryptDungeon.wall_boxes("wall", 4.0).size() == 1)
	# Packs: the shared pack rules.
	var packs: Array = TestDungeon.read_groups(level)
	var sizes_ok: bool = true
	var elite: int = 0
	var homes: Array = []
	var nearest_start: float = INF
	var start: Vector3 = (level.get_node("PlayerStart") as Node3D).position
	var warden_in_arena: bool = false
	for pack in packs:
		var n: int = 0
		var has_elite: bool = false
		for pair in pack["kinds"]:
			n += int(pair[1])
			has_elite = has_elite or pair[0] == "brute" or pair[0] == "warden"
			if pair[0] == "warden" and int(pack["area"]) == 7:
				warden_in_arena = true
		sizes_ok = sizes_ok and n >= DungeonMonsterGenerator.PACK_MIN and n <= DungeonMonsterGenerator.PACK_MAX
		elite += 1 if has_elite else 0
		homes.append(pack["home"])
		nearest_start = minf(nearest_start, (pack["home"] as Vector2).distance_to(Vector2(start.x, start.z)))
	expect("every Crypt pack holds %d to %d bodies (%d packs)" % [DungeonMonsterGenerator.PACK_MIN, DungeonMonsterGenerator.PACK_MAX, packs.size()], sizes_ok and packs.size() >= 15)
	expect("about one pack in five carries an elite (%d of %d)" % [elite, packs.size()], float(elite) / packs.size() >= 0.1 and float(elite) / packs.size() <= 0.3)
	expect("the final arena holds the warden pack", warden_in_arena)
	var gap: float = CryptDungeon.longest_pack_gap(homes)
	expect("no more than %.0f s of walking without a pack in view (longest %.0f m of %.0f m)" % [RoadEncounterRoster.MAX_WALK_SECONDS_BETWEEN_PACKS, gap, TestDungeon.MAX_WALK_GAP], gap <= TestDungeon.MAX_WALK_GAP)
	expect("the first pack is in sight of the start (%.1f m)" % nearest_start, nearest_start <= TestDungeon.PACK_VIEW_RANGE)
	var rows: Array = TestDungeon.project(HeroProgression.xp_for_level(1), packs)
	expect("enemy levels follow the hero: rising along the way, never above the projection", int(rows[7]["level"]) >= int(rows[0]["level"]))
	level.free()


## The spaces reachable from `from` (a cell) through touching cells, with `blocked` closed.
func _flood(from: Vector2, blocked: String) -> Dictionary:
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = [Vector2i(int(from.x), int(from.y))]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true
		var space: String = CryptLayout.space_at(cell.x, cell.y)
		if space == "" or space == blocked:
			continue
		seen[space] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			queue.append(cell + d)
	return seen
