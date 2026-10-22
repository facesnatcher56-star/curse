extends DevSuite
## The map-mode dungeon (game/world/dungeons/map_mode_01.tscn, `-- --mapmode`, plan in MapModeLayout): the contract the node-map UI reads, the graph's
## shape (forks, optional side branches, a boss exit), every corridor walkable, packs far enough apart that one fight never wakes a neighbour, and a
## run-time estimate. (The navigation mesh itself is checked on a real bake by game/dev/map_mode_nav_check.gd.)

## Run-time model (assumptions, all tunable here): the party runs at 4.5 m/s (PlayerStats.run_speed); a kill takes this many seconds of fighting per
## body (the hero plus Cutter together); a champion adds CHAMPION_EXTRA, every cleared group CLEAR_OVERHEAD (collect loot, walk to it), every
## reward POI (open a chest, use a shrine) POI_TIME.
const RUN_SPEED := 4.5
const KILL_SECONDS := {"zombie": 3.0, "ghoul": 5.0, "rock_thrower": 5.0, "brute": 14.0, "warden": 55.0}
const CHAMPION_EXTRA := 25.0
const CLEAR_OVERHEAD := 8.0
const POI_TIME := 12.0
## How close to a body of another group the fight (or the arrival spot) may be, beyond its reach, plus the bodies' own spread: extra safety.
const WAKE_MARGIN := 4.0
const ARRIVAL_OFFSET := 6.0   # MapMode.ARRIVE_DISTANCE: the party stands this far from the group it fights
const AGENT_RADIUS := 0.5


func _test_map_mode_dungeon() -> void:
	var nodes: Array[Dictionary] = MapModeLayout.nodes()
	var links: Array[Dictionary] = MapModeLayout.links()
	var by_id: Dictionary = {}
	for n in nodes:
		by_id[int(n["id"])] = n
	# --- the contract -------------------------------------------------------------------------------------------------------------------
	var kinds: Dictionary = {}
	for n in nodes:
		kinds[n["kind"]] = int(kinds.get(n["kind"], 0)) + 1
	var combat: int = int(kinds.get("pack", 0)) + int(kinds.get("swarm", 0)) + int(kinds.get("champion", 0))
	var poi: int = int(kinds.get("chest", 0)) + int(kinds.get("shrine", 0))
	expect("%d enemy nodes (8 to 10), %d points of interest (3 to 4), one boss, one start (%s)" % [combat, poi, str(kinds)],
		combat >= 8 and combat <= 10 and poi >= 3 and poi <= 4 and int(kinds.get("boss", 0)) == 1 and int(kinds.get("start", 0)) == 1)
	expect("ids are unique, the start is id 0 and the boss id is the boss node", by_id.size() == nodes.size() and MapModeLayout.start_id() == 0
		and by_id.has(0) and by_id[0]["kind"] == "start" and by_id[MapModeLayout.boss_id()]["kind"] == "boss")
	var swarm_bodies: int = 0
	var champions: Array[String] = []
	var rows_ok: bool = true
	for n in nodes:
		var bodies: int = 0
		for pair in n["groups"]:
			bodies += int(pair[1])
		if n["kind"] == "swarm":
			swarm_bodies = maxi(swarm_bodies, bodies)
		if n["kind"] == "champion":
			champions.append(String(n["champion"]))
		var combat_kind: bool = n["kind"] in ["pack", "swarm", "champion", "boss"]
		rows_ok = rows_ok and (n["pos"] is Vector2) and (n["groups"] as Array).is_empty() != combat_kind and (n["champion"] is String) \
			and ((String(n["champion"]) != "") == (n["kind"] == "champion"))
	expect("every row has pos / groups / champion in the contract's shape", rows_ok)
	expect("a swarm of 25+ bodies (%d)" % swarm_bodies, swarm_bodies >= 25)
	expect("two champion packs, each with a named champion (%s)" % str(champions), champions.size() == 2 and not champions.has(""))
	# --- the graph ----------------------------------------------------------------------------------------------------------------------
	var adj: Dictionary = {}
	for n in nodes:
		adj[int(n["id"])] = []
	var links_ok: bool = true
	for link in links:
		links_ok = links_ok and adj.has(int(link["a"])) and adj.has(int(link["b"])) and int(link["a"]) != int(link["b"]) and (link["waypoints"] as Array).size() >= 2
		if links_ok:
			(adj[int(link["a"])] as Array).append(int(link["b"]))
			(adj[int(link["b"])] as Array).append(int(link["a"]))
	expect("every link joins two known nodes and carries waypoints", links_ok)
	var reached: Dictionary = _reach(adj, 0)
	expect("every node is reachable from the start (%d of %d)" % [reached.size(), nodes.size()], reached.size() == nodes.size())
	expect("the boss is reachable from the start", reached.has(MapModeLayout.boss_id()))
	var forks: int = 0
	var side_branches: int = 0
	for id in adj:
		forks += 1 if (adj[id] as Array).size() >= 3 else 0
		if (adj[id] as Array).size() == 1 and by_id[id]["kind"] in ["chest", "shrine"]:
			side_branches += 1
	expect("at least two forks (%d) and an optional side branch ending in a reward (%d dead ends)" % [forks, side_branches], forks >= 2 and side_branches >= 1)
	var fastest: Dictionary = _fastest_route(nodes, links, adj, by_id)
	var on_route: int = 0
	for id in fastest["route"]:
		on_route += 1 if by_id[id]["kind"] in ["pack", "swarm", "champion"] else 0
	expect("the route to the boss is a choice: the fastest one skips enemy nodes (%d of %d on it)" % [on_route, combat], on_route < combat and on_route >= 5)
	# --- the scene ----------------------------------------------------------------------------------------------------------------------
	var level: Node3D = (load(MapModeDungeon.MAP_SCENE) as PackedScene).instantiate() as Node3D
	var parts_ok: bool = true
	for part in ["Floor", "Walls", "Pillars", "Props", "SetPieces", "Torches", "Scatter", "Liners", "Chests", "Shrines", "EnemyGroups", "PlayerStart"]:
		parts_ok = parts_ok and level.has_node(part)
	expect("the scene holds floor, walls, props, set pieces, torches, scatter, chests, shrines, packs and a start", parts_ok)
	var markers: Dictionary = {}   # node id -> DungeonEnemyGroup
	for m in level.get_node("EnemyGroups").get_children():
		markers[int(String(m.name).trim_prefix("Node"))] = m
	var marker_ok: bool = true
	for n in nodes:
		marker_ok = marker_ok and markers.has(int(n["id"])) == (not (n["groups"] as Array).is_empty())
	expect("each combat node has a DungeonEnemyGroup named Node<id> (%d markers)" % markers.size(), marker_ok and markers.size() == combat + 1)
	var kinds_match: bool = true
	var carriers: int = 0
	for id in markers:
		var counts: Array = (markers[id] as DungeonEnemyGroup).kinds
		kinds_match = kinds_match and JSON.stringify(counts) == JSON.stringify(by_id[id]["groups"])
		var plan: Dictionary = (markers[id] as Node).get_meta(MapModeLayout.CHAMPION_META, {}) as Dictionary
		carriers += 0 if plan.is_empty() else 1
		kinds_match = kinds_match and plan.is_empty() == (String(by_id[id]["champion"]) == "")
	expect("the markers hold the plan's groups, and exactly the two champion nodes carry the champion flag (%d)" % carriers, kinds_match and carriers == 2)
	var chest_nodes: Dictionary = {}
	for c in level.get_node("Chests").get_children():
		chest_nodes[int(String(c.name).trim_prefix("Node"))] = c
	var shrine_nodes: Dictionary = {}
	for s in level.get_node("Shrines").get_children():
		shrine_nodes[int(String(s.name).trim_prefix("Node"))] = s
	var poi_ok: bool = true
	for n in nodes:
		poi_ok = poi_ok and chest_nodes.has(int(n["id"])) == (n["kind"] == "chest") and shrine_nodes.has(int(n["id"])) == (n["kind"] == "shrine")
	expect("every chest is Node<id> under Chests, every shrine a Marker3D Node<id> under Shrines (%d, %d)" % [chest_nodes.size(), shrine_nodes.size()],
		poi_ok and chest_nodes.size() + shrine_nodes.size() == poi)
	expect("shrines are visible: an altar stands at each marker", _shrine_altars(level, shrine_nodes))
	var door_cells: int = 0
	for dir_name in ["N", "E", "S", "W"]:
		var walls := level.get_node("Walls/Walls" + dir_name) as GridMap
		for cell in walls.get_used_cells():
			door_cells += 1 if walls.mesh_library.get_item_name(walls.get_cell_item(cell)).begins_with("wall_doorway") else 0
	var openings: int = 0   # cell edges where two different spaces meet: each is an opening in the wall
	var walled_openings: int = 0
	for r in MapModeLayout.H:
		for c in MapModeLayout.W:
			var here_space: String = MapModeLayout.space_at(c, r)
			if here_space == "":
				continue
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var there: String = MapModeLayout.space_at(c + step.x, r + step.y)
				if there != "" and there != here_space:
					openings += 1
					var near_side := level.get_node("Walls/Walls" + ("E" if step.x == 1 else "S")) as GridMap   # either side may carry the piece
					var far_side := level.get_node("Walls/Walls" + ("W" if step.x == 1 else "N")) as GridMap
					if near_side.get_cell_item(Vector3i(c, 0, r)) != GridMap.INVALID_CELL_ITEM or far_side.get_cell_item(Vector3i(c + step.x, 0, r + step.y)) != GridMap.INVALID_CELL_ITEM:
						walled_openings += 1
	expect("the plan joins spaces only at the corridors' ends: %d openings, two per corridor end %d cells wide (%d links), so nothing is joined that the graph does not join" % [openings, MapModeLayout.CORRIDOR_WIDTH, links.size()],
		openings == 2 * MapModeLayout.CORRIDOR_WIDTH * links.size())
	expect("the corridor openings are open (8 m wide: no narrow door pieces, no wall across them; %d door pieces, %d walled openings)" % [door_cells, walled_openings],
		door_cells == 0 and walled_openings == 0)
	var gates: Array = level.get_node("SetPieces").get_children().filter(func(n: Node) -> bool: return n.get_script() == preload("res://game/world/gateway.gd"))
	var round_ends: int = 0
	for link in links:
		for end_id in [int(link["a"]), int(link["b"])]:
			round_ends += 1 if MapModeLayout.ROUNDS.has(MapModeLayout._space_name(by_id[end_id])) else 0
	var gates_ok: bool = gates.size() == 2 * links.size() - round_ends
	for g in gates:
		var into: Vector3 = -(g as Node3D).global_transform.basis.z if (g as Node3D).is_inside_tree() else -(g as Node3D).transform.basis.z
		var ahead: Vector2 = Vector2((g as Node3D).position.x, (g as Node3D).position.z) + Vector2(into.x, into.z) * 2.0
		var behind: Vector2 = Vector2((g as Node3D).position.x, (g as Node3D).position.z) - Vector2(into.x, into.z) * 2.0
		var ahead_cell: Vector2i = MapModeLayout.cell_of(ahead)
		var behind_cell: Vector2i = MapModeLayout.cell_of(behind)
		gates_ok = gates_ok and MapModeLayout.space_at(ahead_cell.x, ahead_cell.y).begins_with("c") and not MapModeLayout.space_at(behind_cell.x, behind_cell.y).begins_with("c")
		gates_ok = gates_ok and bool(g.get("low")) == (into.z > 0.5)
	expect("a gateway stands across every corridor end but the round court's (%d), facing into its corridor, low on a room's south wall" % gates.size(), gates_ok)
	expect("the player starts at node 0", (level.get_node("PlayerStart") as Node3D).position.is_equal_approx(_v3(by_id[0]["pos"])))
	# --- corridors are walkable ---------------------------------------------------------------------------------------------------------
	var obstacles: Array = []   # {p (Vector2), r}
	for group_name in ["SetPieces", "Props"]:
		for holder in level.get_node(group_name).get_children():
			if holder.has_meta("obstacle_radius") and holder is Node3D:
				obstacles.append({"p": Vector2((holder as Node3D).position.x, (holder as Node3D).position.z), "r": float(holder.get_meta("obstacle_radius"))})
	for c in level.get_node("Chests").get_children():
		obstacles.append({"p": Vector2((c as Node3D).position.x, (c as Node3D).position.z), "r": 0.9})
	var ends_ok: bool = true
	var floor_ok: bool = true
	var clear_ok: bool = true
	var worst_clear: float = INF
	var bad_note: String = ""
	for link in links:
		var pts: Array = link["waypoints"]
		ends_ok = ends_ok and (pts[0] as Vector2).is_equal_approx(by_id[int(link["a"])]["pos"]) and (pts[pts.size() - 1] as Vector2).is_equal_approx(by_id[int(link["b"])]["pos"])
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var length: float = a.distance_to(b)
			var steps: int = maxi(int(length / 0.5), 1)
			for k in steps + 1:
				var q: Vector2 = a.lerp(b, float(k) / float(steps))
				var cell: Vector2i = MapModeLayout.cell_of(q)
				if MapModeLayout.space_at(cell.x, cell.y) == "":
					floor_ok = false
					bad_note = "link %d-%d at %s is rock" % [int(link["a"]), int(link["b"]), str(q)]
			for o in obstacles:
				var clearance: float = _segment_distance(o["p"], a, b) - float(o["r"])
				worst_clear = minf(worst_clear, clearance)
				if clearance < AGENT_RADIUS:
					clear_ok = false
					bad_note = "link %d-%d passes %.2f m from a %.1f m obstacle at %s" % [int(link["a"]), int(link["b"]), clearance + float(o["r"]), float(o["r"]), str(o["p"])]
		for p in pts:
			var cell: Vector2i = MapModeLayout.cell_of(p)
			floor_ok = floor_ok and MapModeLayout.space_at(cell.x, cell.y) != ""
	expect("every link runs from its node's pos to the other's pos", ends_ok)
	expect("every waypoint and every 0.5 m along each corridor stands on floor (%s)" % bad_note, floor_ok)
	expect("no corridor segment passes within %.1f m of a prop, set piece or chest (worst clearance %.2f m) %s" % [AGENT_RADIUS, worst_clear, bad_note], clear_ok)
	# --- fights never wake a neighbour --------------------------------------------------------------------------------------------------
	var rows: Array = TestDungeon.read_groups(level)
	var homes: Dictionary = {}   # node id -> {home, spread, reach}
	var idx: int = 0
	for m in level.get_node("EnemyGroups").get_children():
		if not (m is DungeonEnemyGroup):
			continue
		var id: int = int(String(m.name).trim_prefix("Node"))
		var row: Dictionary = rows[idx]
		idx += 1
		var reach: float = 0.0
		for pair in row["kinds"]:
			var def: EnemyDef = EnemyDb.get_def(String(pair[0]))
			reach = maxf(reach, maxf(def.aggro_range, float(def.params.get("fire_range", 0.0))))
		homes[id] = {"home": row["home"], "spread": float(row["spread"]) * 1.415, "reach": reach, "roam": float(row["roam"]) if row["mode"] == "wander" else 0.0}
	var pos_ok: bool = true
	for id in homes:
		pos_ok = pos_ok and (homes[id]["home"] as Vector2).is_equal_approx(by_id[id]["pos"])
	expect("each group stands at its node's pos", pos_ok)
	var tightest: float = INF
	var tight_note: String = ""
	var isolated: bool = true
	var walled: bool = true
	var nearest: float = INF
	for a_id in homes:
		var a: Dictionary = homes[a_id]
		for n in nodes:
			var b_id: int = int(n["id"])
			if b_id == a_id:
				continue
			var spot: Vector2 = n["pos"]
			var extra: float = 0.0
			if homes.has(b_id):   # another group: its bodies stand round its home
				extra = float(homes[b_id]["spread"]) + float(homes[b_id]["roam"])
			else:
				extra = ARRIVAL_OFFSET   # start / chest / shrine: the party may stand a few metres off the room's middle
			var gap: float = (a["home"] as Vector2).distance_to(spot) - (float(a["reach"]) + float(a["spread"]) + float(a["roam"]) + extra)
			if homes.has(b_id):
				extra += ARRIVAL_OFFSET   # fighting group B means standing 6 m from it, toward whichever side the party came from
			var margin: float = (a["home"] as Vector2).distance_to(spot) - (float(a["reach"]) + float(a["spread"]) + float(a["roam"]) + extra)
			if margin < tightest:
				tightest = margin
				tight_note = "node %d vs node %d" % [a_id, b_id]
			isolated = isolated and gap > WAKE_MARGIN and margin > 0.0
			if homes.has(b_id):
				nearest = minf(nearest, (a["home"] as Vector2).distance_to(spot))
				var ca: Vector2i = MapModeLayout.cell_of(a["home"])
				var cb: Vector2i = MapModeLayout.cell_of(spot)
				walled = walled and MapModeLayout.space_at(ca.x, ca.y) != MapModeLayout.space_at(cb.x, cb.y)
	expect("no group can wake another, whoever stands where (tightest margin %.1f m, %s)" % [tightest, tight_note], isolated)
	expect("no two groups share a room, and the nearest two homes are %.0f m apart (40 m and more)" % nearest, walled and nearest >= 40.0)
	# --- the minimap (the walking game, #112): the plan's rooms and corridors are the floor, nothing else ----------------------------
	var plan := MapModeDungeon.new()
	var floor_rects: Array[Rect2] = plan.floor_rects()
	plan.free()
	var on_floor := func(p: Vector2) -> bool:
		return floor_rects.any(func(r: Rect2) -> bool: return r.grow(0.01).has_point(p))
	var covered: bool = not floor_rects.is_empty()
	for n in nodes:
		covered = covered and on_floor.call(n["pos"])
	for link in links:
		for w in link["waypoints"]:
			covered = covered and on_floor.call(w)
	expect("the minimap floor covers every room centre and corridor waypoint (%d cells)" % floor_rects.size(), covered)
	var probe_map := MinimapMap.new()
	probe_map.origin = Vector2(-MapModeLayout.half_x(), -MapModeLayout.half_z())
	probe_map.cols = ceili(MapModeLayout.half_x() * 2.0 / MinimapMap.CELL)
	probe_map.rows = ceili(MapModeLayout.half_z() * 2.0 / MinimapMap.CELL)
	probe_map.kinds.resize(probe_map.cols * probe_map.rows)
	probe_map.kinds.fill(MinimapMap.K_GROUND)
	var host := MapModeDungeon.new()
	probe_map._paint_floor(host)
	host.free()
	probe_map.terrain = Image.create(1, 1, false, Image.FORMAT_RGBA8)   # (kind_at only needs a built map)
	var start_pos: Vector2 = by_id[0]["pos"]
	var outside := Vector2(-MapModeLayout.half_x() + 2.0, -MapModeLayout.half_z() + 2.0)
	expect("the minimap paints the start room as floor and leaves the rock between rooms empty",
		probe_map.kind_at(Vector3(start_pos.x, 0, start_pos.y)) == MinimapMap.K_ROAD and probe_map.kind_at(Vector3(outside.x, 0, outside.y)) == MinimapMap.K_VOID)

	# --- walking pacing (#112): corridor packs keep every stretch under the walking-gap budget ------------------------------------
	var pace_homes: Array[Vector2] = []
	for n in nodes:
		if not (n["groups"] as Array).is_empty():
			pace_homes.append(n["pos"])
	var corridor: Array[Vector2] = []
	for row in MapModeDungeon.corridor_homes_with_links():
		corridor.append(row["home"])
	pace_homes.append_array(corridor)
	var worst_gap: float = 0.0
	var worst_link: String = ""
	for link in links:
		var points: Array[Vector2] = link["waypoints"]
		var run: float = 0.0
		for i in points.size() - 1:
			var leg: float = points[i].distance_to(points[i + 1])
			var s: float = 0.0
			while s < leg:
				var here: Vector2 = points[i].lerp(points[i + 1], s / leg)
				run = 0.0 if pace_homes.any(func(h: Vector2) -> bool: return here.distance_to(h) <= TestDungeon.PACK_VIEW_RANGE) else run + 1.0
				if run > worst_gap:
					worst_gap = run
					worst_link = "%d-%d" % [int(link["a"]), int(link["b"])]
				s += 1.0
	print("  corridor packs: %d, longest walk with nothing in view %.0f m (%s)" % [corridor.size(), worst_gap, worst_link])
	expect("walking the Sunken Way, no corridor stretch is longer than %.1f m with no pack in view (%d corridor packs, longest %.0f m on %s)" % [TestDungeon.MAX_WALK_GAP, corridor.size(), worst_gap, worst_link],
		worst_gap <= TestDungeon.MAX_WALK_GAP)
	expect("corridor packs stand in a corridor, or in a room at least two view ranges from every room's own group (never on a fight)", corridor.all(func(h: Vector2) -> bool:
		var cell: Vector2i = MapModeLayout.cell_of(h)
		var far: bool = nodes.all(func(n: Dictionary) -> bool: return (n["groups"] as Array).is_empty() or h.distance_to(n["pos"]) >= 2.0 * TestDungeon.PACK_VIEW_RANGE)
		return MapModeLayout.space_at(cell.x, cell.y).begins_with("c") or far))
	expect("map mode's dungeon has no corridor packs (off unless the walking game sets it)", not MapModeDungeon.new().corridor_packs)

	# --- run time -----------------------------------------------------------------------------------------------------------------------
	var fast_min: float = float(fastest["seconds"]) / 60.0
	var full_min: float = _full_clear_seconds(nodes, links, adj, by_id) / 60.0
	var typical: float = (fast_min + full_min) * 0.5
	print("  map-mode run estimate: fastest route to the boss %.1f min (%s), full clear %.1f min, typical %.1f min (run %.1f m/s)" % [fast_min, str(fastest["route"]), full_min, typical, RUN_SPEED])
	expect("a typical run takes 10 to 15 minutes (fastest %.1f, full clear %.1f, mean %.1f)" % [fast_min, full_min, typical], typical >= 10.0 and typical <= 15.0 and fast_min >= 7.0 and full_min <= 18.0)
	level.free()


# --- helpers ---------------------------------------------------------------------------------------------------------------------------

func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


func _reach(adj: Dictionary, from: int) -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var id: int = queue.pop_back()
		for other in adj[id]:
			if not seen.has(other):
				seen[other] = true
				queue.append(other)
	return seen


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _shrine_altars(level: Node3D, shrine_nodes: Dictionary) -> bool:
	for id in shrine_nodes:
		var at: Vector3 = (shrine_nodes[id] as Node3D).position
		var found: bool = false
		for holder in level.get_node("SetPieces").get_children():
			if String(holder.name).begins_with("ShrineAltar") and (holder as Node3D).position.distance_to(at) < 1.0:
				found = true
		if not found:
			return false
	return true


func _link_length(link: Dictionary) -> float:
	var pts: Array = link["waypoints"]
	var length: float = 0.0
	for i in pts.size() - 1:
		length += (pts[i] as Vector2).distance_to(pts[i + 1])
	return length


## Seconds to clear a node: the fight (per body, a champion extra, then the clean-up) or a reward's visit.
func _node_seconds(n: Dictionary) -> float:
	if n["kind"] in ["chest", "shrine"]:
		return POI_TIME
	if (n["groups"] as Array).is_empty():
		return 0.0
	var seconds: float = CLEAR_OVERHEAD
	for pair in n["groups"]:
		seconds += float(KILL_SECONDS[String(pair[0])]) * float(pair[1])
	if String(n["champion"]) != "":
		seconds += CHAMPION_EXTRA
	return seconds


## The quickest way from the start to the boss (walk + fights on the way): {route: Array[int], seconds}.
func _fastest_route(nodes: Array[Dictionary], links: Array[Dictionary], adj: Dictionary, by_id: Dictionary) -> Dictionary:
	var cost: Dictionary = {}
	for link in links:
		cost["%d-%d" % [int(link["a"]), int(link["b"])]] = _link_length(link) / RUN_SPEED
		cost["%d-%d" % [int(link["b"]), int(link["a"])]] = _link_length(link) / RUN_SPEED
	var best: Dictionary = {0: _node_seconds(by_id[0])}
	var came: Dictionary = {}
	var open: Array[int] = [0]
	while not open.is_empty():
		open.sort_custom(func(x: int, y: int) -> bool: return float(best[x]) < float(best[y]))
		var id: int = open.pop_front()
		for other in adj[id]:
			var total: float = float(best[id]) + float(cost["%d-%d" % [id, other]]) + _node_seconds(by_id[other])
			if not best.has(other) or total < float(best[other]):
				best[other] = total
				came[other] = id
				open.append(other)
	var route: Array[int] = []
	var at: int = MapModeLayout.boss_id()
	while at != 0:
		route.push_front(at)
		at = int(came[at])
	route.push_front(0)
	return {"route": route, "seconds": float(best[MapModeLayout.boss_id()])}


## Every node cleared: all fights, every corridor walked once, and the dead ends (a reward at the end of a spur) walked back as well.
func _full_clear_seconds(nodes: Array[Dictionary], links: Array[Dictionary], adj: Dictionary, by_id: Dictionary) -> float:
	var seconds: float = 0.0
	for n in nodes:
		seconds += _node_seconds(n)
	for link in links:
		var walk: float = _link_length(link) / RUN_SPEED
		var dead_end: bool = (adj[int(link["a"])] as Array).size() == 1 or (adj[int(link["b"])] as Array).size() == 1
		seconds += walk * (2.0 if dead_end and int(link["a"]) != 0 and int(link["b"]) != 0 and int(link["a"]) != MapModeLayout.boss_id() and int(link["b"]) != MapModeLayout.boss_id() else 1.0)
	return seconds
