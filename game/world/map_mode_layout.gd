class_name MapModeLayout
extends RefCounted
## The plan of the map-mode dungeon (`game/world/dungeons/map_mode_01.tscn`, reached with `-- --mapmode`): a GRAPH. Rooms are nodes, corridors are paths.
## Two jobs in one file, both pure static data:
##  1. the DATA CONTRACT the node-map UI reads: nodes(), links(), start_id(), boss_id() (world x, z in metres, on the navigation mesh);
##  2. the grid plan the baker (game/dev/map_mode_baker.gd) writes the scene from: the same constants CryptLayout has (CELL, W, H, SPACES, ROUNDS,
##     CUTS, PACKS, CHESTS, START_CELL, world(), space_at(), cell_of()), so the Crypt's baker works on this plan unchanged.
## Edit the plan here, then rebake (docs/MAP_MODE_DUNGEON.md). One grid cell is 4 m; north is row 0 (-z); the party starts in the south.

const CELL := 4.0
const W := 52
const H := 84

## The nodes. kind: start | pack | swarm | champion | chest | shrine | boss. rect = inclusive cell rectangle [c0, r0, c1, r1] (`extra` adds more
## rectangles to the same room), centre = where the party arrives (cell coordinates: world() of a whole number is a cell's middle, of x.5 the line
## between two cells), stage = DungeonEnemyGroup `area` (how far along: decides the enemies' level), groups = [[kind, count]],
## champion = {"kind": enemy kind that carries it, "affix": Champion.AFFIXES key} or {}, cover = cells where a pillar stands (the baker puts them;
## they keep clear of the centre and of every corridor line).
## Layout (owner-approved redesign, 2026-10-22): rooms that join sit side by side in bands with short corridors (8-24 m, two cells wide).
const NODES: Array = [
	{"id": 0, "kind": "start", "name": "The Landing", "rect": [23, 77, 28, 81], "centre": Vector2(25.5, 79), "stage": 0, "groups": []},
	{"id": 1, "kind": "pack", "name": "Fallen Guard", "rect": [21, 66, 30, 72], "centre": Vector2(25.5, 69), "stage": 0,
		"groups": [["zombie", 4], ["ghoul", 1]], "cover": [Vector2(22, 67), Vector2(29, 67), Vector2(22, 71), Vector2(29, 71)]},
	{"id": 2, "kind": "swarm", "name": "The Charnel Pit", "rect": [34, 55, 47, 72], "centre": Vector2(40.5, 63.5), "stage": 1,
		"groups": [["zombie", 20], ["ghoul", 6], ["rock_thrower", 2]],
		"cover": [Vector2(36, 61), Vector2(45, 61), Vector2(36, 66), Vector2(45, 66), Vector2(37, 70), Vector2(44, 57)]},
	{"id": 3, "kind": "pack", "name": "Weeping Cloister", "rect": [7, 56, 16, 72], "centre": Vector2(11.5, 64), "stage": 1,
		"groups": [["zombie", 3], ["ghoul", 2], ["rock_thrower", 2]],
		"cover": [Vector2(8, 61), Vector2(15, 61), Vector2(8, 66), Vector2(15, 66), Vector2(8, 71), Vector2(15, 71)]},
	{"id": 4, "kind": "champion", "name": "Iron Vestry", "rect": [21, 54, 30, 62], "centre": Vector2(25.5, 58), "stage": 2,
		"groups": [["ghoul", 3], ["zombie", 3], ["rock_thrower", 1]], "champion": {"kind": "ghoul", "affix": "fast"},
		"cover": [Vector2(24, 55), Vector2(28, 55), Vector2(24, 61), Vector2(28, 61)]},
	{"id": 5, "kind": "chest", "name": "Hidden Cache", "rect": [2, 62, 4, 66], "centre": Vector2(3, 64), "stage": 1, "groups": []},
	{"id": 6, "kind": "pack", "name": "Drowned Nave", "rect": [21, 40, 30, 47], "centre": Vector2(25.5, 43.5), "stage": 3,
		"groups": [["zombie", 4], ["ghoul", 2], ["rock_thrower", 2]], "cover": [Vector2(22, 41), Vector2(29, 41), Vector2(22, 46), Vector2(29, 46)]},
	{"id": 7, "kind": "shrine", "name": "Pale Shrine", "rect": [15, 50, 18, 53], "centre": Vector2(16.5, 51.5), "stage": 2, "groups": []},
	{"id": 8, "kind": "champion", "name": "The Reliquary", "rect": [9, 40, 18, 48], "centre": Vector2(13.5, 44), "stage": 4,
		"groups": [["brute", 1], ["ghoul", 3], ["zombie", 2]], "champion": {"kind": "brute", "affix": "shielded"},
		"cover": [Vector2(10, 41), Vector2(11, 41), Vector2(17, 41), Vector2(10, 47), Vector2(17, 47)]},
	{"id": 9, "kind": "pack", "name": "Ghoul Warren", "rect": [34, 40, 43, 48], "centre": Vector2(38.5, 44), "stage": 4,
		"groups": [["ghoul", 3], ["rock_thrower", 2], ["zombie", 2]],
		"cover": [Vector2(35, 41), Vector2(36, 41), Vector2(42, 41), Vector2(35, 47), Vector2(42, 47), Vector2(41, 47)]},
	{"id": 10, "kind": "pack", "name": "The Ossuary", "rect": [11, 31, 40, 36], "extra": [[21, 27, 30, 30]], "centre": Vector2(25.5, 33.5), "stage": 5,
		"groups": [["brute", 1], ["zombie", 4], ["ghoul", 2], ["rock_thrower", 1]],
		"cover": [Vector2(17, 35), Vector2(34, 35), Vector2(19, 31), Vector2(32, 31), Vector2(23, 28), Vector2(28, 28)]},
	{"id": 11, "kind": "boss", "name": "The Warden's Court", "rect": [17, 4, 34, 14], "centre": Vector2(25.5, 9), "stage": 7,
		"groups": [["warden", 1], ["zombie", 3], ["ghoul", 2], ["rock_thrower", 2]]},
	{"id": 12, "kind": "chest", "name": "Collapsed Vault", "rect": [47, 42, 50, 46], "centre": Vector2(48.5, 44), "stage": 4, "groups": []},
	{"id": 13, "kind": "shrine", "name": "Ember Shrine", "rect": [13, 20, 17, 23], "centre": Vector2(15, 21.5), "stage": 6, "groups": []},
	{"id": 14, "kind": "pack", "name": "Collapsed Stair", "rect": [21, 19, 30, 24], "centre": Vector2(25.5, 21.5), "stage": 6,
		"groups": [["ghoul", 3], ["zombie", 3], ["rock_thrower", 2]], "cover": [Vector2(28, 20), Vector2(28, 23), Vector2(22, 23)]},
]

## The corridors, two cells wide: each path is a polyline in cell coordinates from room a's centre to room b's centre, axis-aligned, running on the
## line between the corridor's two cells (x.5); the corridor's cells are the path's cells outside the rooms. These are also the waypoints links()
## hands out.
const CORRIDOR_WIDTH := 2
## The baker leaves doorways open (no door piece): a corridor this wide would get a pier in the middle of its opening (CryptBaker._walls).
const OPEN_DOORWAYS := true
const LINKS: Array = [
	{"a": 0, "b": 1, "path": [Vector2(25.5, 79), Vector2(25.5, 69)]},
	{"a": 1, "b": 2, "path": [Vector2(25.5, 69), Vector2(25.5, 68.5), Vector2(40.5, 68.5), Vector2(40.5, 63.5)]},
	{"a": 1, "b": 3, "path": [Vector2(25.5, 69), Vector2(25.5, 68.5), Vector2(11.5, 68.5), Vector2(11.5, 64)]},
	{"a": 2, "b": 4, "path": [Vector2(40.5, 63.5), Vector2(40.5, 58.5), Vector2(25.5, 58.5), Vector2(25.5, 58)]},
	{"a": 3, "b": 4, "path": [Vector2(11.5, 64), Vector2(11.5, 58.5), Vector2(25.5, 58.5), Vector2(25.5, 58)]},
	{"a": 3, "b": 5, "path": [Vector2(11.5, 64), Vector2(3, 64)]},
	{"a": 4, "b": 6, "path": [Vector2(25.5, 58), Vector2(25.5, 43.5)]},
	{"a": 4, "b": 7, "path": [Vector2(25.5, 58), Vector2(21.5, 58), Vector2(21.5, 51.5), Vector2(16.5, 51.5)]},
	{"a": 6, "b": 8, "path": [Vector2(25.5, 43.5), Vector2(13.5, 43.5), Vector2(13.5, 44)]},
	{"a": 6, "b": 9, "path": [Vector2(25.5, 43.5), Vector2(38.5, 43.5), Vector2(38.5, 44)]},
	{"a": 9, "b": 12, "path": [Vector2(38.5, 44), Vector2(48.5, 44)]},
	{"a": 8, "b": 10, "path": [Vector2(13.5, 44), Vector2(13.5, 33.5), Vector2(25.5, 33.5)]},
	{"a": 9, "b": 10, "path": [Vector2(38.5, 44), Vector2(38.5, 33.5), Vector2(25.5, 33.5)]},
	{"a": 10, "b": 14, "path": [Vector2(25.5, 33.5), Vector2(25.5, 21.5)]},
	{"a": 14, "b": 13, "path": [Vector2(25.5, 21.5), Vector2(15, 21.5)]},
	{"a": 14, "b": 11, "path": [Vector2(25.5, 21.5), Vector2(25.5, 9)]},
]

## Spaces (name -> {rects, kind, stage}) for the baker: every room first (so a corridor cell inside a room belongs to the room), then the corridors.
static var SPACES: Dictionary = _build_spaces()

const ROUNDS := {
	"n11_boss": {"centre": Vector2(25.5, 9), "rx": 33.0, "ry": 19.0, "segments": 44},
}

## Chamfered corners (rooms whose doors are all mid-wall): [space, corner, metres].
const CUTS: Array = [
	["n1_pack", "NW", 6.0], ["n1_pack", "NE", 6.0], ["n1_pack", "SW", 6.0], ["n1_pack", "SE", 6.0],
	["n2_swarm", "NW", 8.0], ["n2_swarm", "NE", 8.0], ["n2_swarm", "SW", 8.0], ["n2_swarm", "SE", 8.0],
	["n14_pack", "NW", 6.0], ["n14_pack", "NE", 6.0], ["n14_pack", "SW", 6.0], ["n14_pack", "SE", 6.0],
]

const START_CELL := Vector2(25.5, 79)

## Chests (baker): {space, cell (far end of the room), node}.
const CHESTS: Array = [
	{"space": "n5_chest", "cell": Vector2(2.4, 64), "node": 5},
	{"space": "n12_chest", "cell": Vector2(50.6, 44), "node": 12},
]
## Shrine altars (baker): {space, cell, node}. The party arrives at the room's middle, a few metres from the altar.
const SHRINES: Array = [
	{"space": "n7_shrine", "cell": Vector2(15.2, 51.5), "node": 7},
	{"space": "n13_shrine", "cell": Vector2(13.2, 21.5), "node": 13},
]
## Per room kind: the enemy kinds that may carry a deterministic champion are in NODES; this is the champion pack flag the baker writes.
const CHAMPION_META := "map_champion"

## Packs for the baker, one per combat node: {cell, stage, kinds, mode, node, champion}.
static func packs() -> Array:
	var out: Array = []
	for n in NODES:
		if (n["groups"] as Array).is_empty():
			continue
		out.append({"cell": n["centre"], "stage": int(n["stage"]), "kinds": n["groups"], "mode": "", "node": int(n["id"]),
			"champion": n.get("champion", {})})
	return out


static var PACKS: Array = packs()


static func _space_name(n: Dictionary) -> String:
	var kind: String = String(n["kind"])
	return "n%d_%s" % [int(n["id"]), "pack" if kind in ["champion", "pack"] else kind]


static func _room_kind(n: Dictionary) -> String:
	match String(n["kind"]):
		"start": return "room"
		"chest", "shrine": return "side"
		"boss": return "arena"
		_: return "hall"


static func _build_spaces() -> Dictionary:
	var spaces: Dictionary = {}
	for n in NODES:
		var room_rects: Array = [n["rect"]]
		room_rects.append_array(n.get("extra", []))
		spaces[_space_name(n)] = {"rects": room_rects, "kind": _room_kind(n), "stage": int(n["stage"])}
	for link in LINKS:
		var rects: Array = []
		var path: Array = link["path"]
		for i in path.size() - 1:
			var p: Vector2 = path[i]
			var q: Vector2 = path[i + 1]
			if not is_equal_approx(p.x, q.x) and not is_equal_approx(p.y, q.y):
				continue   # a diagonal run lies inside a room
			var rect: Array = [int(floorf(minf(p.x, q.x))), int(floorf(minf(p.y, q.y))), int(floorf(maxf(p.x, q.x))), int(floorf(maxf(p.y, q.y)))]
			if is_equal_approx(p.x, q.x):
				rect[2] = int(rect[0]) + CORRIDOR_WIDTH - 1   # a north-south run: its cells and the ones east of them
			else:
				rect[3] = int(rect[1]) + CORRIDOR_WIDTH - 1   # an east-west run: its cells and the ones south of them
			rects.append(rect)
		spaces["c%d_%d" % [int(link["a"]), int(link["b"])]] = {"rects": rects, "kind": "corridor", "stage": 0}
	return spaces


# --- The contract ---------------------------------------------------------------------------------------------------------------------

static func start_id() -> int:
	return 0


static func boss_id() -> int:
	return 11


## One row per node: {id, kind, name, pos (world x, z), groups ([[kind, count]]), champion (the champion's display name, or "")}.
static func nodes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in NODES:
		var centre: Vector2 = n["centre"]
		out.append({"id": int(n["id"]), "kind": String(n["kind"]), "name": String(n["name"]), "pos": world(centre.x, centre.y),
			"groups": (n["groups"] as Array).duplicate(true), "champion": champion_name(n),
			"affixes": ([String((n["champion"] as Dictionary)["affix"])] if not (n.get("champion", {}) as Dictionary).is_empty() else [])})
	return out


## One row per corridor: {a, b, waypoints (world x, z from a's pos to b's pos)}. Undirected.
static func links() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for link in LINKS:
		var points: Array[Vector2] = []
		for cell in link["path"]:
			points.append(world((cell as Vector2).x, (cell as Vector2).y))
		out.append({"a": int(link["a"]), "b": int(link["b"]), "waypoints": points})
	return out


## The champion's display name as the game will show it ("Swift Ghoul"), or "" for a node without one.
static func champion_name(n: Dictionary) -> String:
	var c: Dictionary = n.get("champion", {})
	if c.is_empty():
		return ""
	return "%s %s" % [String(Champion.AFFIXES[String(c["affix"])]["title"]), EnemyDb.get_def(String(c["kind"])).display_name]


# --- Grid helpers (same as CryptLayout) -----------------------------------------------------------------------------------------------

static func half_x() -> float:
	return float(W) * CELL * 0.5 + 8.0


static func half_z() -> float:
	return float(H) * CELL * 0.5 + 8.0


static func world(c: float, r: float) -> Vector2:
	return Vector2((c + 0.5 - float(W) * 0.5) * CELL, (r + 0.5 - float(H) * 0.5) * CELL)


static func space_at(c: int, r: int) -> String:
	for key in SPACES:
		for rect in SPACES[key]["rects"]:
			if c >= int(rect[0]) and c <= int(rect[2]) and r >= int(rect[1]) and r <= int(rect[3]):
				return String(key)
	return ""


static func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(int(floor(point.x / CELL + float(W) * 0.5)), int(floor(point.y / CELL + float(H) * 0.5)))


static func route_world(path: Array[Vector2]) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for cell in path:
		points.append(world(cell.x, cell.y))
	return points
