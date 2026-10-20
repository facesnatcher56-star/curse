class_name MapModeLayout
extends RefCounted
## The plan of the map-mode dungeon (`game/world/dungeons/map_mode_01.tscn`, reached with `-- --mapmode`): a GRAPH. Rooms are nodes, corridors are paths.
## Two jobs in one file, both pure static data:
##  1. the DATA CONTRACT the node-map UI reads: nodes(), links(), start_id(), boss_id() (world x, z in metres, on the navigation mesh);
##  2. the grid plan the baker (game/dev/map_mode_baker.gd) writes the scene from: the same constants CryptLayout has (CELL, W, H, SPACES, ROUNDS,
##     CUTS, PACKS, CHESTS, START_CELL, world(), space_at(), cell_of()), so the Crypt's baker works on this plan unchanged.
## Edit the plan here, then rebake (docs/MAP_MODE_DUNGEON.md). One grid cell is 4 m; north is row 0 (-z); the party starts in the far south.

const CELL := 4.0
const W := 64
const H := 100

## The nodes. kind: start | pack | swarm | champion | chest | shrine | boss. rect = inclusive cell rectangle [c0, r0, c1, r1], centre = where the
## party arrives (cell coordinates), stage = DungeonEnemyGroup `area` (how far along: decides the enemies' level), groups = [[kind, count]],
## champion = {"kind": enemy kind that carries it, "affix": Champion.AFFIXES key} or {}.
const NODES: Array = [
	{"id": 0, "kind": "start", "name": "The Landing", "rect": [28, 94, 34, 98], "centre": Vector2(31, 96), "stage": 0, "groups": []},
	{"id": 1, "kind": "pack", "name": "Fallen Guard", "rect": [28, 79, 34, 83], "centre": Vector2(31, 81), "stage": 0,
		"groups": [["zombie", 4], ["ghoul", 1]]},
	{"id": 2, "kind": "swarm", "name": "The Charnel Pit", "rect": [42, 70, 54, 82], "centre": Vector2(48, 76), "stage": 1,
		"groups": [["zombie", 20], ["ghoul", 6], ["rock_thrower", 2]]},
	{"id": 3, "kind": "pack", "name": "Weeping Cloister", "rect": [16, 64, 22, 70], "centre": Vector2(19, 67), "stage": 1,
		"groups": [["zombie", 3], ["ghoul", 2], ["rock_thrower", 2]]},
	{"id": 4, "kind": "champion", "name": "Iron Vestry", "rect": [30, 58, 40, 64], "centre": Vector2(35, 61), "stage": 2,
		"groups": [["ghoul", 3], ["zombie", 3], ["rock_thrower", 1]], "champion": {"kind": "ghoul", "affix": "fast"}},
	{"id": 5, "kind": "chest", "name": "Hidden Cache", "rect": [4, 65, 8, 69], "centre": Vector2(6, 67), "stage": 1, "groups": []},
	{"id": 6, "kind": "pack", "name": "Drowned Nave", "rect": [30, 40, 38, 46], "centre": Vector2(34, 43), "stage": 3,
		"groups": [["zombie", 4], ["ghoul", 2], ["rock_thrower", 2]]},
	{"id": 7, "kind": "shrine", "name": "Pale Shrine", "rect": [12, 54, 18, 60], "centre": Vector2(15, 57), "stage": 2, "groups": []},
	{"id": 8, "kind": "champion", "name": "The Reliquary", "rect": [10, 38, 18, 44], "centre": Vector2(14, 41), "stage": 4,
		"groups": [["brute", 1], ["ghoul", 3], ["zombie", 2]], "champion": {"kind": "brute", "affix": "shielded"}},
	{"id": 9, "kind": "pack", "name": "Ghoul Warren", "rect": [44, 36, 50, 42], "centre": Vector2(47, 39), "stage": 4,
		"groups": [["ghoul", 3], ["rock_thrower", 2], ["zombie", 2]]},
	{"id": 10, "kind": "pack", "name": "The Ossuary", "rect": [24, 24, 32, 30], "centre": Vector2(28, 27), "stage": 5,
		"groups": [["brute", 1], ["zombie", 4], ["ghoul", 2], ["rock_thrower", 1]]},
	{"id": 11, "kind": "boss", "name": "The Warden's Court", "rect": [23, 0, 33, 7], "centre": Vector2(28, 3.5), "stage": 7,
		"groups": [["warden", 1], ["zombie", 3], ["ghoul", 2], ["rock_thrower", 2]]},
	{"id": 12, "kind": "chest", "name": "Collapsed Vault", "rect": [57, 37, 61, 41], "centre": Vector2(59, 39), "stage": 4, "groups": []},
	{"id": 13, "kind": "shrine", "name": "Ember Shrine", "rect": [12, 13, 16, 17], "centre": Vector2(14, 15), "stage": 6, "groups": []},
	{"id": 14, "kind": "pack", "name": "Collapsed Stair", "rect": [24, 12, 32, 18], "centre": Vector2(28, 15), "stage": 6,
		"groups": [["ghoul", 3], ["zombie", 3], ["rock_thrower", 2]]},
]

## The corridors: each path is a polyline in cell coordinates from room a's centre to room b's centre, axis-aligned in the corridor part; the
## corridor's cells are the path's cells outside the rooms. These are also the waypoints links() hands out.
const LINKS: Array = [
	{"a": 0, "b": 1, "path": [Vector2(31, 96), Vector2(31, 81)]},
	{"a": 1, "b": 2, "path": [Vector2(31, 81), Vector2(31, 80), Vector2(48, 80), Vector2(48, 76)]},
	{"a": 1, "b": 3, "path": [Vector2(31, 81), Vector2(31, 80), Vector2(19, 80), Vector2(19, 67)]},
	{"a": 2, "b": 4, "path": [Vector2(48, 76), Vector2(48, 63), Vector2(35, 63), Vector2(35, 61)]},
	{"a": 3, "b": 4, "path": [Vector2(19, 67), Vector2(19, 64), Vector2(35, 64), Vector2(35, 61)]},
	{"a": 3, "b": 5, "path": [Vector2(19, 67), Vector2(6, 67)]},
	{"a": 4, "b": 6, "path": [Vector2(35, 61), Vector2(35, 43), Vector2(34, 43)]},
	{"a": 4, "b": 7, "path": [Vector2(35, 61), Vector2(35, 58), Vector2(15, 58), Vector2(15, 57)]},
	{"a": 6, "b": 8, "path": [Vector2(34, 43), Vector2(14, 43), Vector2(14, 41)]},
	{"a": 6, "b": 9, "path": [Vector2(34, 43), Vector2(34, 41), Vector2(47, 41), Vector2(47, 39)]},
	{"a": 9, "b": 12, "path": [Vector2(47, 39), Vector2(59, 39)]},
	{"a": 8, "b": 10, "path": [Vector2(14, 41), Vector2(14, 27), Vector2(28, 27)]},
	{"a": 9, "b": 10, "path": [Vector2(47, 39), Vector2(47, 27), Vector2(28, 27)]},
	{"a": 10, "b": 14, "path": [Vector2(28, 27), Vector2(28, 15)]},
	{"a": 14, "b": 13, "path": [Vector2(28, 15), Vector2(14, 15)]},
	{"a": 14, "b": 11, "path": [Vector2(28, 15), Vector2(28, 3.5)]},
]

## Spaces (name -> {rects, kind, stage}) for the baker: every room first (so a corridor cell inside a room belongs to the room), then the corridors.
static var SPACES: Dictionary = _build_spaces()

const ROUNDS := {
	"n11_boss": {"centre": Vector2(28, 3.5), "rx": 19.0, "ry": 13.0, "segments": 34},
}

## Chamfered corners (rooms whose doors are all mid-wall): [space, corner, metres].
const CUTS: Array = [
	["n0_start", "NW", 4.0], ["n0_start", "NE", 4.0], ["n0_start", "SW", 4.0], ["n0_start", "SE", 4.0],
	["n2_swarm", "NW", 5.0], ["n2_swarm", "NE", 5.0], ["n2_swarm", "SW", 5.0], ["n2_swarm", "SE", 5.0],
	["n10_pack", "NW", 4.0], ["n10_pack", "NE", 4.0], ["n10_pack", "SW", 4.0], ["n10_pack", "SE", 4.0],
	["n14_pack", "NW", 4.0], ["n14_pack", "NE", 4.0], ["n14_pack", "SW", 4.0], ["n14_pack", "SE", 4.0],
]

const START_CELL := Vector2(31, 96)

## Chests (baker): {space, cell (far end of the room), node}.
const CHESTS: Array = [
	{"space": "n5_chest", "cell": Vector2(4.4, 67), "node": 5},
	{"space": "n12_chest", "cell": Vector2(60.6, 39), "node": 12},
]
## Shrine altars (baker): {space, cell, node}. The party arrives at the room's middle, a few metres from the altar.
const SHRINES: Array = [
	{"space": "n7_shrine", "cell": Vector2(13.2, 57), "node": 7},
	{"space": "n13_shrine", "cell": Vector2(12.8, 15), "node": 13},
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
		spaces[_space_name(n)] = {"rects": [n["rect"]], "kind": _room_kind(n), "stage": int(n["stage"])}
	for link in LINKS:
		var rects: Array = []
		var path: Array = link["path"]
		for i in path.size() - 1:
			var p: Vector2 = path[i]
			var q: Vector2 = path[i + 1]
			if not is_equal_approx(p.x, q.x) and not is_equal_approx(p.y, q.y):
				continue   # a diagonal run lies inside a room
			rects.append([int(floorf(minf(p.x, q.x))), int(floorf(minf(p.y, q.y))), int(floorf(maxf(p.x, q.x))), int(floorf(maxf(p.y, q.y)))])
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
