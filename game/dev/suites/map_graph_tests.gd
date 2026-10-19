extends DevSuite
## Map mode's node map: the graph rules (reachable / beyond / hidden, routes that never pass an uncleared node, dashing back), the overlay
## (icon-only nodes, tooltip only for the hovered or focused node, dim nodes not clickable, nothing overlapping at the supported interface
## scales) and a run through MapMode on a synthetic graph (only the chosen group wakes, the boss ends the run).

## 12 nodes. 0 start; 1 pack, 2 swarm; 3 champion, 4 chest; 5 shrine; 6, 7 packs; 8 boss; 9 pack, 10 champion; 11 swarm.
func _rows() -> Array:
	var spec: Array = [
		[0, "start", Vector2(0, 0)], [1, "pack", Vector2(22, -16)], [2, "swarm", Vector2(22, 16)],
		[3, "champion", Vector2(44, -16)], [4, "chest", Vector2(44, 16)], [5, "shrine", Vector2(66, 0)],
		[6, "pack", Vector2(88, -16)], [7, "pack", Vector2(88, 16)], [8, "boss", Vector2(110, 0)],
		[9, "pack", Vector2(66, -34)], [10, "champion", Vector2(66, 34)], [11, "swarm", Vector2(88, -40)]]
	var out: Array = []
	for s in spec:
		var groups: Array = [] if s[1] in ["start", "chest", "shrine"] else [["zombie", 3 if s[1] != "swarm" else 9]]
		out.append({"id": s[0], "kind": s[1], "name": "Node %d" % s[0], "pos": s[2], "groups": groups, "champion": "Grimfang" if s[1] == "champion" else ""})
	return out

func _links(rows: Array) -> Array:
	var pairs: Array = [[0, 1], [0, 2], [1, 3], [2, 4], [3, 5], [4, 5], [5, 6], [5, 7], [6, 8], [7, 8], [3, 9], [4, 10], [9, 11]]
	var pos: Dictionary = {}
	for r in rows:
		pos[r["id"]] = r["pos"]
	var out: Array = []
	for pr in pairs:
		var a: Vector2 = pos[pr[0]]
		var b: Vector2 = pos[pr[1]]
		out.append({"a": pr[0], "b": pr[1], "waypoints": [a, (a + b) * 0.5 + Vector2(0, 3), b]})
	return out

func _graph() -> MapGraph:
	var rows: Array = _rows()
	return MapGraph.from_rows(rows, _links(rows))

func _route_has(route: Array[Vector2], p: Vector2) -> bool:
	for q in route:
		if q.distance_to(p) < 0.01:
			return true
	return false

func _test_map_graph() -> void:
	_graph_rules()
	await _overlay_checks()
	await _run_checks()

# --- Graph rules ----------------------------------------------------------------------------------------------------------------------

func _graph_rules() -> void:
	var g: MapGraph = _graph()
	expect("the start is cleared, its neighbours reachable, the next ring beyond, the rest hidden",
		g.state_of(0) == "cleared" and g.state_of(1) == "reachable" and g.state_of(2) == "reachable" and g.state_of(3) == "beyond" \
		and g.state_of(4) == "beyond" and g.state_of(5) == "hidden" and g.state_of(8) == "hidden")
	var clickable: Array = g.ids().filter(func(i: int) -> bool: return g.is_clickable(i))
	expect("only cleared and reachable nodes are clickable (%s)" % [clickable], clickable == [0, 1, 2])
	expect("a beyond node has no route, a hidden node has no route", g.route(0, 3).is_empty() and g.route(0, 8).is_empty())
	expect("the boss is hidden and not clickable at the start", g.state_of(8) == "hidden" and not g.is_clickable(8))
	var r1: Array[Vector2] = g.route(0, 1)
	expect("a reachable node routes along its corridor from the start to its icon", r1.size() == 3 and r1[0] == g.pos_of(0) and r1[r1.size() - 1] == g.pos_of(1))
	expect("an uncleared node cannot be the start of a route", g.route(1, 0).is_empty())
	g.mark_cleared(1)
	expect("clearing a node reveals the ones behind it (beyond -> reachable, hidden -> beyond)",
		g.state_of(3) == "reachable" and g.state_of(9) == "beyond" and g.state_of(5) == "beyond" and g.state_of(11) == "hidden" and g.state_of(1) == "cleared")
	expect("the other side stays as it was", g.state_of(2) == "reachable" and g.state_of(4) == "beyond")
	var r3: Array[Vector2] = g.route(0, 3)
	expect("a route to the new node goes through the cleared one and never the uncleared side",
		not r3.is_empty() and _route_has(r3, g.pos_of(1)) and not _route_has(r3, g.pos_of(2)) and g.route_nodes(0, 3) == [0, 1, 3])
	g.mark_cleared(3)
	var to5: Array = g.route_nodes(0, 5)
	expect("the shrine is reachable through the cleared chain only (%s)" % [to5], to5 == [0, 1, 3, 5])
	expect("a node whose only access is an uncleared node has no route (the swarm side: 2 and 4 are uncleared)", g.route_nodes(0, 10).is_empty() and g.state_of(10) == "hidden")
	g.mark_cleared(5)
	expect("the boss stays out of reach while its approaches are uncleared", g.route(0, 8).is_empty() and g.state_of(8) == "beyond" and g.state_of(6) == "reachable")
	g.mark_cleared(6)
	var to8: Array = g.route_nodes(0, 8)
	expect("the boss is reachable only through the graph: start-1-3-5-6-boss (%s)" % [to8], g.state_of(8) == "reachable" and to8 == [0, 1, 3, 5, 6, 8])
	expect("the route never visits an uncleared node before the boss", not to8.has(7) and not to8.has(2) and not to8.has(4))
	# Dashing back: any cleared node, from any cleared node.
	expect("dash back from the shrine to the start and to node 1", g.route_nodes(5, 0) == [5, 3, 1, 0] and g.route_nodes(5, 1) == [5, 3, 1])
	expect("dashing to the node you are at is a route of one point", g.route(3, 3).size() == 1)
	var back: Array[Vector2] = g.route(6, 0)
	expect("a route back runs from the first node to the last along the same corridors", back[0] == g.pos_of(6) and back[back.size() - 1] == g.pos_of(0))
	g.mark_cleared(99)
	expect("clearing an unknown node changes nothing", not g.cleared.has(99))
	# The diamond: the far side is only reachable via an uncleared node.
	var rows: Array = [
		{"id": 0, "kind": "start", "name": "S", "pos": Vector2(0, 0), "groups": [], "champion": ""},
		{"id": 1, "kind": "pack", "name": "A", "pos": Vector2(20, -10), "groups": [["zombie", 3]], "champion": ""},
		{"id": 2, "kind": "pack", "name": "B", "pos": Vector2(20, 10), "groups": [["zombie", 3]], "champion": ""},
		{"id": 3, "kind": "boss", "name": "T", "pos": Vector2(40, 0), "groups": [["zombie", 1]], "champion": ""}]
	var links: Array = [{"a": 0, "b": 1, "waypoints": []}, {"a": 0, "b": 2, "waypoints": []}, {"a": 1, "b": 3, "waypoints": []}, {"a": 2, "b": 3, "waypoints": []}]
	var d: MapGraph = MapGraph.from_rows(rows, links)
	expect("diamond: the far node is beyond and has no route while both sides are uncleared", d.state_of(3) == "beyond" and d.route(0, 3).is_empty())
	d.mark_cleared(3)   # it cannot happen in play; the rule must hold anyway
	expect("diamond: even a cleared far node cannot be dashed to past uncleared nodes", d.route(0, 3).is_empty())
	d.mark_cleared(2)
	expect("diamond: once one side is cleared the far node routes through that side only", d.route_nodes(0, 3) == [0, 2, 3])
	var line: MapGraph = MapGraph.from_rows(rows.slice(0, 2), [links[0]])
	expect("a lone neighbour: reachable, clickable", line.state_of(1) == "reachable" and line.is_clickable(1))

# --- Overlay --------------------------------------------------------------------------------------------------------------------------

func _all_markers(g: MapGraph, state: String = "reachable") -> Array:
	var out: Array = []
	for id in g.ids():
		var p: Vector2 = g.pos_of(int(id))
		out.append({"id": int(id), "pos": Vector3(p.x, 0, p.y), "kind": g.kind_of(int(id)), "state": state, "strength": 3 + int(id), "label": "Node %d\n3 zombie\nGuards: gold" % id})
	return out

func _make_overlay(screen: Vector2, g: MapGraph, markers: Array) -> MapModeOverlay:
	var ov := MapModeOverlay.new()
	ov.screen_override = screen
	add_child(ov)
	ov.set_links(g.link_rows())
	ov.set_frame(g.bounds())
	ov.open(markers, Vector3.ZERO, false)
	return ov

func _moved(ov: MapModeOverlay, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ov._input(ev)

func _overlay_checks() -> void:
	var g: MapGraph = _graph()
	# Every node shown, at the smallest and largest interface scales of 720p and 1080p (the virtual screen is the window over the content scale).
	var screens: Array = [Vector2(853, 480), Vector2(1280, 720), Vector2(1536, 864), Vector2(2560, 1440), Vector2(4608, 2592)]
	for screen in screens:
		var ov: MapModeOverlay = _make_overlay(screen, g, _all_markers(g))
		var panel: Rect2 = ov.panel_rect()
		var inside: bool = true
		var apart: bool = true
		var rects: Array[Rect2] = []
		for id in g.ids():
			var r: Rect2 = ov.icon_rect(int(id))
			inside = inside and panel.encloses(r) and panel.has_point(ov.marker_screen_pos(int(id)))
			for o in rects:
				apart = apart and not r.intersects(o)
			rects.append(r)
		expect("%s: all 12 icons lie inside the panel" % [screen], inside)
		expect("%s: no two icons overlap" % [screen], apart)
		var span := Rect2(ov.marker_screen_pos(0), Vector2.ZERO)
		for id in g.ids():
			span = span.expand(ov.marker_screen_pos(int(id)))
		expect("%s: the graph is fitted to the panel (uses most of one dimension: %s of %s)" % [screen, span.size, panel.size],
			span.size.x > ov.panel_inner_rect().size.x * 0.9 or span.size.y > ov.panel_inner_rect().size.y * 0.9)
		ov.queue_free()
	# Tooltips, dim nodes and clicking, on the real game state after the first node is cleared.
	var mm := MapMode.new()
	mm.use_graph(g, {})
	g.mark_cleared(1)
	var marks: Array = mm.markers()
	var ids: Array = marks.map(func(m: Dictionary) -> int: return int(m["id"]))
	expect("only cleared, reachable and beyond nodes are listed, hidden ones are not drawn (%s)" % [ids], ids == [0, 1, 2, 3, 4, 5, 9])
	var by_id: Dictionary = {}
	for m in marks:
		by_id[int(m["id"])] = m
	expect("a reachable node carries its full detail", String(by_id[2]["label"]).contains("Node 2") and String(by_id[2]["label"]).contains("9 zombie") \
		and String(by_id[3]["label"]).contains("Champion: Grimfang") and String(by_id[3]["label"]).contains("Guards:"))
	expect("a beyond node carries no label", String(by_id[5]["label"]) == "" and String(by_id[9]["label"]) == "" and by_id[5]["state"] == "beyond")
	expect("a cleared node says so", String(by_id[1]["label"]).contains("Cleared"))
	expect("strength grows with the group (swarm 9 > pack 3)", int(by_id[2]["strength"]) > int(by_id[3]["strength"]) or int(by_id[2]["strength"]) == 9)
	mm.free()
	var ov: MapModeOverlay = _make_overlay(Vector2(1920, 1080) / 1.2, g, marks)
	var picked: Array = []
	ov.selected.connect(func(id: int) -> void: picked.append(id))
	expect("with nothing hovered and no pad in use there is no tooltip", ov.tooltip_text() == "" and ov.focused_id() == -1)
	_moved(ov, ov.marker_screen_pos(2))
	expect("hovering a reachable node shows its tooltip", ov.focused_id() == 2 and ov.tooltip_text().contains("Node 2") and ov.tooltip_text().contains("9 zombie"))
	var tip: Rect2 = ov.tooltip_rect()
	expect("the tooltip stays on screen and clear of the node's icon", Rect2(Vector2.ZERO, ov.size).encloses(tip) and not tip.intersects(ov.icon_rect(2)))
	_moved(ov, ov.marker_screen_pos(5))
	expect("hovering a beyond node shows nothing and focuses nothing", ov.focused_id() == -1 and ov.tooltip_text() == "")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = ov.marker_screen_pos(5)
	ov._input(click)
	expect("clicking a beyond node does nothing", picked.is_empty())
	click.position = ov.marker_screen_pos(3)
	ov._input(click)
	expect("clicking a reachable node selects it", picked == [3])
	click.position = ov.marker_screen_pos(1)
	ov._input(click)
	expect("clicking a cleared node selects it (dash back)", picked == [3, 1])
	# The tooltip of a node at the screen edge stays inside the screen.
	var edge_ok: bool = true
	for id in [0, 1, 2, 3, 4]:
		_moved(ov, ov.marker_screen_pos(id))
		edge_ok = edge_ok and Rect2(Vector2.ZERO, ov.size).encloses(ov.tooltip_rect())
	expect("every tooltip stays on screen", edge_ok)
	# Controller: the stick moves between neighbouring clickable nodes by direction, never onto a beyond node.
	_moved(ov, Vector2(-50, -50))
	ov._focus = 0
	ov.move_focus(Vector2.RIGHT)
	expect("focus moves from the start to a node on its right and shows its tooltip", ov._focus in [1, 2] and ov.focused_id() == ov._focus and ov.tooltip_text() != "")
	var before: int = ov._focus
	ov.move_focus(Vector2.RIGHT)
	expect("focus never lands on a beyond node (%d -> %d)" % [before, ov._focus], ov._focus in [0, 1, 2, 3])
	ov._focus = 0
	ov.move_focus(Vector2.LEFT)
	expect("a push with nothing that way leaves the focus where it is", ov._focus == 0)
	picked.clear()
	ov._focus = 2
	ov.choose_focused()
	expect("A selects the focused node", picked == [2])
	var closed_count: Array = []
	ov.closed.connect(func() -> void: closed_count.append(1))
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	ov._input(cancel)
	expect("B does not close a map that may not be closed", closed_count.is_empty() and ov.is_open())
	ov.queue_free()

# --- A run on the arena ---------------------------------------------------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _wait_state(m: MapMode, wanted: MapMode.State, max_frames: int) -> void:
	var n: int = 0
	while m.state != wanted and n < max_frames:
		await get_tree().physics_frame
		n += 1

func _run_checks() -> void:
	var cutter: Player = game.companion
	var cutter_was_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = false
	var base: Vector3 = player.global_position
	var p0: Vector3 = Nav.snap(player, base)
	var p1: Vector3 = Nav.snap(player, base + Vector3(18.0, 0.0, 0.0))
	var p2: Vector3 = Nav.snap(player, base + Vector3(18.0, 0.0, -18.0))
	var rows: Array = [
		{"id": 0, "kind": "start", "name": "Start", "pos": Vector2(p0.x, p0.z), "groups": [], "champion": ""},
		{"id": 1, "kind": "pack", "name": "Pack", "pos": Vector2(p1.x, p1.z), "groups": [["zombie", 2]], "champion": ""},
		{"id": 2, "kind": "boss", "name": "Boss", "pos": Vector2(p2.x, p2.z), "groups": [["zombie", 1]], "champion": ""}]
	var links: Array = [{"a": 0, "b": 1, "waypoints": [Vector2(p0.x, p0.z), Vector2(p1.x, p1.z)]}, {"a": 1, "b": 2, "waypoints": [Vector2(p1.x, p1.z), Vector2(p2.x, p2.z)]}]
	var g: MapGraph = MapGraph.from_rows(rows, links)
	var pack: Array[Enemy] = []
	for i in 2:
		pack.append(_spawn_enemy(Nav.snap(player, p1 + Vector3(2.0 * i, 0.0, 0.0)), "zombie", 1.0))
	var boss: Enemy = _spawn_enemy(p2, "zombie", 1.0)
	var bystander: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-16.0, 0.0, 6.0)), "zombie", 1.0)
	for e in pack:
		e.group_id = 911
		e.aggro_range = 0.0
	boss.group_id = 912
	boss.aggro_range = 0.0
	bystander.group_id = 913
	bystander.aggro_range = 0.0
	var m := MapMode.new()
	m.use_graph(g, {1: 911, 2: 912})
	game.add_child(m)
	m.setup(player, cutter, hud)
	await _wait_state(m, MapMode.State.MAP, 120)
	expect("the node map opens by itself with the start as the party's node", m.state == MapMode.State.MAP and m.overlay.is_open() and m.current_node == 0)
	var listed: Array = m.markers().map(func(x: Dictionary) -> int: return int(x["id"]))
	expect("the map lists the start, the reachable pack and the boss as a dim step beyond (%s)" % [listed], listed == [0, 1, 2])
	m.overlay.selected.emit(2)
	expect("selecting the boss before the pack is cleared does nothing (not clickable, no route)", m.state == MapMode.State.MAP and m.overlay.is_open() and not pack[0].is_aggro())
	m.overlay.selected.emit(1)
	expect("selecting the reachable pack closes the map and starts the dash", m.state == MapMode.State.DASH and not m.overlay.is_open())
	await _wait_state(m, MapMode.State.FIGHT, 150)
	expect("the dash ends in a fight", m.state == MapMode.State.FIGHT)
	await _frames(3)
	var gap: float = Vector2(player.global_position.x - p1.x, player.global_position.z - p1.z).length()
	expect("the party stands short of the pack, on the side it came from (%.1f m)" % gap, gap < MapMode.ARRIVE_DISTANCE + 3.0 and player.global_position.x < p1.x + 0.5)
	expect("only the chosen group is awake: its members aggro, the boss and the bystander asleep", pack[0].is_aggro() and pack[1].is_aggro() and not boss.is_aggro() and not bystander.is_aggro())
	await _frames(20)
	expect("the other groups stay asleep through the fight", not boss.is_aggro() and not bystander.is_aggro())
	for e in pack:
		e.credit_hero()
		e._apply_damage(e.max_health + 10.0)
	await _wait_state(m, MapMode.State.COLLECT, 30)
	await _wait_state(m, MapMode.State.MAP, 150)
	expect("a cleared pack reopens the map with the node cleared and the party's node moved", m.state == MapMode.State.MAP and g.is_cleared(1) and m.current_node == 1)
	expect("the boss is now reachable and clickable", g.state_of(2) == "reachable" and g.is_clickable(2))
	# Dash back to the start (a cleared node): no fight.
	m.overlay.selected.emit(0)
	expect("dashing back to a cleared node starts a dash", m.state == MapMode.State.DASH)
	await _wait_state(m, MapMode.State.COLLECT, 100)
	await _wait_state(m, MapMode.State.MAP, 100)
	var back_gap: float = Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()
	expect("the party stands at the start again, no fight (%.1f m) and the map is back" % back_gap, back_gap < 2.5 and m.current_node == 0 and m.state == MapMode.State.MAP)
	expect("the boss's group is still asleep after the dash back", not boss.is_aggro() and not bystander.is_aggro())
	# On to the boss through the cleared pack.
	m.overlay.selected.emit(2)
	expect("the boss is dashed to through the cleared pack", m.state == MapMode.State.DASH and m.group_id == 912)
	await _wait_state(m, MapMode.State.FIGHT, 200)
	expect("the boss fight starts, only the boss group is awake", m.state == MapMode.State.FIGHT and boss.is_aggro() and not bystander.is_aggro())
	boss.credit_hero()
	boss._apply_damage(boss.max_health + 10.0)
	await _wait_state(m, MapMode.State.DONE, 200)
	expect("clearing the boss ends the run", m.state == MapMode.State.DONE and m.run_complete and g.boss_cleared())
	# Tidy.
	bystander.credit_hero()
	bystander._apply_damage(bystander.max_health + 10.0)
	m.overlay.queue_free()
	m.queue_free()
	await _frames(2)
	cutter.testing_disabled = cutter_was_disabled
