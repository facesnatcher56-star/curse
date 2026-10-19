class_name MapGraph
extends RefCounted
## The node map of map mode: the dungeon as a graph of nodes (enemy groups and points of interest) joined by paths. Pure rules, no scene access.
##
## A node is "cleared" (done, or the start), "reachable" (not cleared, joined by a path to a cleared node: shown in full detail and clickable),
## "beyond" (joined to a reachable node: a dim icon, not clickable) or "hidden" (fog). A dash route only ever travels along paths between
## CLEARED nodes, plus a final hop onto a reachable target: it never passes an uncleared node.

const MAP_LAYOUT := "res://game/world/map_mode_layout.gd"

var nodes: Dictionary = {}        # id -> row {"id","kind","name","pos": Vector2,"groups","champion"}
var start_id: int = 0
var boss_id: int = -1
var cleared: Dictionary = {}      # id -> true

var _adj: Dictionary = {}         # id -> Array[int]
var _links: Dictionary = {}       # "a:b" -> PackedVector2Array oriented from a to b
var _link_rows: Array = []

## The graph from rows: nodes {"id","kind","name","pos","groups","champion"}, links {"a","b","waypoints"}.
static func from_rows(node_rows: Array, link_rows: Array, start: int = 0, boss: int = -1) -> MapGraph:
	var g := MapGraph.new()
	for row in node_rows:
		var id: int = int(row["id"])
		g.nodes[id] = row
		g._adj[id] = []
		if String(row.get("kind", "")) == "boss" and boss < 0:
			boss = id
	g.start_id = start
	g.boss_id = boss
	for row in link_rows:
		g._add_link(int(row["a"]), int(row["b"]), row.get("waypoints", []))
	g.cleared[start] = true
	return g

## The level's own graph (MapModeLayout), or null while that file does not exist.
static func from_layout() -> MapGraph:
	if not ResourceLoader.exists(MAP_LAYOUT):
		return null
	var layout: Object = load(MAP_LAYOUT)
	if layout == null:
		return null
	return from_rows(layout.nodes(), layout.links(), int(layout.start_id()), int(layout.boss_id()))

func _key(a: int, b: int) -> String:
	return "%d:%d" % [a, b]

func _add_link(a: int, b: int, waypoints: Array) -> void:
	if not nodes.has(a) or not nodes.has(b) or a == b:
		return
	var fwd := PackedVector2Array()
	for p in waypoints:
		fwd.append(Vector2(p.x, p.y) if p is Vector2 else Vector2(p.x, p.z))
	if fwd.size() < 2:
		fwd = PackedVector2Array([nodes[a]["pos"], nodes[b]["pos"]])
	var back := PackedVector2Array()
	for i in range(fwd.size() - 1, -1, -1):
		back.append(fwd[i])
	_links[_key(a, b)] = fwd
	_links[_key(b, a)] = back
	if not (_adj[a] as Array).has(b):
		(_adj[a] as Array).append(b)
		(_adj[b] as Array).append(a)
		_link_rows.append({"a": a, "b": b, "pts": fwd})

func ids() -> Array:
	var out: Array = nodes.keys()
	out.sort()
	return out

func has_node(id: int) -> bool:
	return nodes.has(id)

func row(id: int) -> Dictionary:
	return nodes.get(id, {})

func pos_of(id: int) -> Vector2:
	return nodes[id]["pos"] if nodes.has(id) else Vector2.ZERO

func kind_of(id: int) -> String:
	return String(nodes[id].get("kind", "pack")) if nodes.has(id) else ""

## Link rows {"a","b","pts": PackedVector2Array world (x, z)} for the overlay, one per path.
func link_rows() -> Array:
	return _link_rows

func neighbours(id: int) -> Array:
	return (_adj.get(id, []) as Array).duplicate()

func is_cleared(id: int) -> bool:
	return cleared.has(id)

func mark_cleared(id: int) -> void:
	if nodes.has(id):
		cleared[id] = true

func state_of(id: int) -> String:
	if not nodes.has(id):
		return "hidden"
	if cleared.has(id):
		return "cleared"
	for n in _adj[id]:
		if cleared.has(n):
			return "reachable"
	for n in _adj[id]:
		if state_of_reachable(int(n)):
			return "beyond"
	return "hidden"

## True for an uncleared node that touches a cleared one.
func state_of_reachable(id: int) -> bool:
	if cleared.has(id):
		return false
	for n in _adj.get(id, []):
		if cleared.has(n):
			return true
	return false

func is_clickable(id: int) -> bool:
	var s: String = state_of(id)
	return s == "cleared" or s == "reachable"

func all_cleared() -> bool:
	for id in nodes:
		if not cleared.has(id):
			return false
	return true

func boss_cleared() -> bool:
	return boss_id >= 0 and cleared.has(boss_id)

## Node ids of the legal route from `from_id` to `to_id`, or [] when there is none. Every node but the last is cleared, so an uncleared node can
## only ever be the destination. Shortest by corridor length.
func route_nodes(from_id: int, to_id: int) -> Array:
	if not nodes.has(from_id) or not nodes.has(to_id) or not cleared.has(from_id) or not is_clickable(to_id):
		return []
	if from_id == to_id:
		return [from_id]
	var dist: Dictionary = {from_id: 0.0}
	var prev: Dictionary = {}
	var open: Array = [from_id]
	while not open.is_empty():
		var best: int = 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[best]]):
				best = i
		var cur: int = int(open.pop_at(best))
		if cur == to_id:
			break
		if cur != from_id and not cleared.has(cur):
			continue   # an uncleared node is a dead end: reached, never passed
		for n in _adj[cur]:
			var nb: int = int(n)
			if not cleared.has(nb) and nb != to_id:
				continue
			var d: float = float(dist[cur]) + _length(_links[_key(cur, nb)])
			if not dist.has(nb) or d < float(dist[nb]):
				dist[nb] = d
				prev[nb] = cur
				if not open.has(nb):
					open.append(nb)
	if not dist.has(to_id):
		return []
	var out: Array = [to_id]
	while out[0] != from_id:
		out.push_front(int(prev[out[0]]))
	return out

## The corridor waypoints (world x, z) of that route, from the first node's position to the target's, or [] without a legal route.
func route(from_id: int, to_id: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var path: Array = route_nodes(from_id, to_id)
	if path.is_empty():
		return out
	if path.size() == 1:
		out.append(pos_of(from_id))
		return out
	for i in range(path.size() - 1):
		var pts: PackedVector2Array = _links[_key(int(path[i]), int(path[i + 1]))]
		for k in pts.size():
			if i > 0 and k == 0:
				continue
			out.append(pts[k])
	return out

static func _length(pts: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total

## Bounding box of every node and corridor point that is not hidden, for fitting the overlay.
func visible_bounds() -> Rect2:
	var box := Rect2()
	var first: bool = true
	for id in nodes:
		if state_of(int(id)) == "hidden":
			continue
		var p: Vector2 = pos_of(int(id))
		box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
		first = false
	return box

## Bounding box of the whole dungeon (the overlay keeps one frame for the whole run so the map does not jump as it is revealed).
func bounds() -> Rect2:
	var box := Rect2()
	var first: bool = true
	for id in nodes:
		var p: Vector2 = pos_of(int(id))
		box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
		first = false
	for key in _links:
		for p in _links[key]:
			box = box.expand(p)
	return box
