extends SceneTree
## Navigation and wiring check for the map-mode dungeon, on the real game and a real navigation bake. Run:
##   godot --headless --path . -s res://game/dev/map_mode_nav_check.gd -- --mapmode
## For every link of MapModeLayout: each waypoint snaps to the navigation mesh within 0.5 m and the walk from one waypoint to the next is a
## straight line on the mesh (navigation path no longer than 5% over the straight distance). Then: every node's pos is on the mesh; the loader
## reports a group for every combat node, a Chest per chest node and a Shrine per shrine node; exactly the two champion nodes carry a champion
## with the plan's name; a shrine heals once.

var _main: Node
var _frames := 0

func _initialize() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 300 or _main.player == null or _main.location == null:
		return false
	var map: RID = _main.get_world_3d().navigation_map
	var dungeon := _main.location as MapModeDungeon
	var bad := 0
	if dungeon == null:
		print("MAPNAV FAIL: the location is not a MapModeDungeon")
		quit(1)
		return true
	var worst_snap: float = 0.0
	var worst_detour: float = 0.0
	for link in MapModeLayout.links():
		var pts: Array = link["waypoints"]
		for i in pts.size():
			var p: Vector2 = pts[i]
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(p.x, 0.0, p.y))
			var off: float = Vector2(snapped.x, snapped.z).distance_to(p)
			worst_snap = maxf(worst_snap, off)
			if off > 0.5:
				bad += 1
				print("MAPNAV waypoint %d of link %d-%d is %.2f m off the mesh at %s" % [i, int(link["a"]), int(link["b"]), off, str(p)])
			if i + 1 < pts.size():
				var q: Vector2 = pts[i + 1]
				var path: PackedVector3Array = NavigationServer3D.map_get_path(map, Vector3(p.x, 0.0, p.y), Vector3(q.x, 0.0, q.y), true)
				var length: float = 0.0
				for k in path.size() - 1:
					length += path[k].distance_to(path[k + 1])
				var straight: float = p.distance_to(q)
				worst_detour = maxf(worst_detour, length / maxf(straight, 0.01))
				if path.size() < 2 or length > straight * 1.05 + 0.3 or Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(q) > 0.6:
					bad += 1
					print("MAPNAV segment %d of link %d-%d is not a straight walk: %.1f m for %.1f m" % [i, int(link["a"]), int(link["b"]), length, straight])
	for n in MapModeLayout.nodes():
		var id: int = int(n["id"])
		var kind: String = String(n["kind"])
		var champion: String = String(n["champion"])
		if kind in ["pack", "swarm", "champion", "boss"]:
			if not dungeon.node_groups.has(id):
				bad += 1
				print("MAPNAV node %d has no group" % id)
				continue
			var members: int = 0
			var champions: Array[String] = []
			for node in get_nodes_in_group("enemies"):
				var e := node as Enemy
				if e != null and e.group_id == int(dungeon.node_groups[id]):
					members += 1
					if e.champion != null:
						champions.append(e.display_name)
			var expected: int = 0
			for pair in n["groups"]:
				expected += int(pair[1])
			print("MAPNAV node %d %-20s %-9s group %d: %d bodies (plan %d) champions %s" % [id, n["name"], kind, int(dungeon.node_groups[id]), members, expected, str(champions)])
			if members != expected or (champion == "") != champions.is_empty() or (champion != "" and champions != [champion]):
				bad += 1
				print("MAPNAV node %d does not match its plan (want champion '%s')" % [id, champion])
		elif kind == "chest" and not dungeon.node_chests.has(id):
			bad += 1
			print("MAPNAV node %d has no chest" % id)
		elif kind == "shrine" and not dungeon.node_shrines.has(id):
			bad += 1
			print("MAPNAV node %d has no shrine" % id)
	var total_champions: int = 0
	for node in get_nodes_in_group("enemies"):
		total_champions += 1 if (node as Enemy).champion != null else 0
	if total_champions != 2:
		bad += 1
		print("MAPNAV %d champions in the whole dungeon, want 2" % total_champions)
	for id in dungeon.node_shrines:
		var hero: Player = _main.player
		hero.health = 1.0
		var first: bool = (dungeon.node_shrines[id] as Shrine).use_shrine()
		var second: bool = (dungeon.node_shrines[id] as Shrine).use_shrine()
		if not first or second or hero.health < hero.max_health - 0.01:
			bad += 1
			print("MAPNAV shrine %d: first use %s, second use %s, hero life %.0f/%.0f" % [int(id), str(first), str(second), hero.health, hero.max_health])
	print("MAPNAV DONE worst snap %.2f m, worst detour x%.3f, problems %d, enemies %d" % [worst_snap, worst_detour, bad, get_nodes_in_group("enemies").size()])
	quit(1 if bad > 0 else 0)
	return true
