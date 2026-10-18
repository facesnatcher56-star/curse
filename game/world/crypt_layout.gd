class_name CryptLayout
extends RefCounted
## The plan of the Crypt (`game/world/dungeons/crypt_01.tscn`, reached with `-- --crypt01`): which grid cells are floor, which space each cell
## belongs to, and the way through. The scene is the SOURCE of the level once written; this is the plan the baker (`tools/build_crypt_01.gd`) wrote it
## from, and what the tests and the walk check read the route from. Keep it in step with the scene if you move a room.
##
## One grid cell is 4 m (the KayKit module). Column c, row r is the cell whose middle is world ((c + 0.5 - W/2) * 4, (r + 0.5 - H/2) * 4); north is
## row 0 (-z), the hero starts in the south-east vestibule (the highest rows) and fights north to the arena (row 0).

const CELL := 4.0
const W := 32
const H := 58

## Spaces: name -> {rects: [[c0, r0, c1, r1] inclusive, ...], kind, stage}. Cells of two different spaces that touch get a doorway between them;
## cells of one space have no wall between them. `stage` is the DungeonEnemyGroup `area` of the packs there (enemy level = what the hero is
## projected to be on reaching it, TestDungeon.project): it counts progress along the way in, not rooms.
const SPACES := {
	"vestibule": {"rects": [[24, 53, 30, 57]], "kind": "room", "stage": 0},
	"stair_hall": {"rects": [[27, 49, 27, 52]], "kind": "corridor", "stage": 0},
	"long_hall": {"rects": [[8, 45, 30, 48], [14, 44, 14, 44], [20, 44, 20, 44], [24, 44, 24, 44], [12, 49, 12, 49], [17, 49, 17, 49], [22, 49, 22, 49]], "kind": "hall", "stage": 1},
	"gallery_link": {"rects": [[9, 41, 10, 44]], "kind": "corridor", "stage": 1},
	"pillared_crypt": {"rects": [[4, 33, 14, 40], [6, 32, 6, 32], [10, 32, 10, 32], [6, 41, 6, 41], [13, 41, 13, 41]], "kind": "hall", "stage": 2},
	"bone_closet": {"rects": [[0, 34, 2, 38]], "kind": "side", "stage": 2},
	"bone_closet_door": {"rects": [[3, 36, 3, 36]], "kind": "corridor", "stage": 2},
	"ossuary_link": {"rects": [[15, 36, 17, 36]], "kind": "corridor", "stage": 3},
	"ossuary": {"rects": [[18, 33, 26, 39], [24, 32, 24, 32], [19, 40, 19, 40], [23, 40, 23, 40], [27, 35, 27, 35], [27, 37, 27, 37]], "kind": "hall", "stage": 3},
	"ossuary_stair": {"rects": [[20, 26, 21, 32]], "kind": "corridor", "stage": 3},
	"choke": {"rects": [[14, 28, 14, 32]], "kind": "corridor", "stage": 3},
	"rotunda": {"rects": [[13, 21, 19, 26], [14, 27, 18, 27]], "kind": "round", "stage": 4},
	"vault_link": {"rects": [[10, 24, 12, 24]], "kind": "corridor", "stage": 4},
	"vault": {"rects": [[4, 22, 9, 26]], "kind": "side", "stage": 4},
	"warden_walk": {"rects": [[16, 19, 16, 20]], "kind": "corridor", "stage": 4},
	"guard_hall": {"rects": [[11, 15, 21, 18], [12, 14, 12, 14], [20, 14, 20, 14], [12, 19, 12, 19], [20, 19, 20, 19]], "kind": "hall", "stage": 5},
	"shrine_link": {"rects": [[22, 16, 24, 16]], "kind": "corridor", "stage": 5},
	"shrine": {"rects": [[25, 14, 29, 18]], "kind": "side", "stage": 5},
	"nave_link": {"rects": [[16, 13, 16, 14]], "kind": "corridor", "stage": 5},
	"antechamber": {"rects": [[12, 10, 20, 12], [13, 9, 13, 9], [19, 9, 19, 9]], "kind": "hall", "stage": 6},
	"arena_link": {"rects": [[16, 8, 16, 9]], "kind": "corridor", "stage": 6},
	"arena": {"rects": [[8, 0, 24, 7]], "kind": "arena", "stage": 7},
}

## The way in, in cell coordinates (column, row): the hero's route from the start to the arena, door to door, through the choke point (the
## ossuary is the loop that rejoins the rotunda).
const MAIN_PATH: Array[Vector2] = [Vector2(26, 56), Vector2(27, 53), Vector2(27, 47), Vector2(9, 47), Vector2(9, 41), Vector2(10, 37),
		Vector2(14, 35), Vector2(14, 28), Vector2(16, 25), Vector2(16, 19), Vector2(16, 14), Vector2(16, 9), Vector2(16, 4)]
## The other way round: from the pillared crypt through the ossuary into the rotunda.
const LOOP_PATH: Array[Vector2] = [Vector2(10, 37), Vector2(14, 36), Vector2(17, 36), Vector2(22, 36), Vector2(20, 32), Vector2(20, 27),
		Vector2(19, 25), Vector2(16, 25)]
## Side rooms: the chest stands at the far end. {space, chest (cell column, row), enter (door cell)}
const CHESTS: Array = [
	{"space": "bone_closet", "cell": Vector2(0.4, 36)},
	{"space": "vault", "cell": Vector2(4.3, 24)},
	{"space": "shrine", "cell": Vector2(29.2, 16)},
]

## Round spaces: the cells stay a block, but the room is walled as an ellipse (centre in plan cells, semi-axes in metres to the wall's middle,
## segments). Doorways keep their cell edge and get a short stub passage to the curve.
const ROUNDS := {
	"rotunda": {"centre": Vector2(16, 24), "rx": 13.0, "ry": 13.0, "segments": 24},
	"arena": {"centre": Vector2(16, 3.5), "rx": 31.0, "ry": 13.5, "segments": 44},
}

## Chamfered corners of the first rect of a space: [space, corner (NW NE SW SE), size in metres along each wall]. A diagonal wall cuts
## the corner off inside the room; the square walls behind it stay.
const CUTS: Array = [
	["vestibule", "NW", 4.0], ["vestibule", "NE", 4.0], ["vestibule", "SW", 4.0], ["vestibule", "SE", 4.0],
	["long_hall", "NW", 5.0], ["long_hall", "NE", 5.0], ["long_hall", "SW", 5.0], ["long_hall", "SE", 5.0],
	["pillared_crypt", "NW", 5.0], ["pillared_crypt", "SW", 5.0], ["pillared_crypt", "SE", 5.0],
	["ossuary", "NW", 5.0], ["ossuary", "NE", 5.0], ["ossuary", "SW", 5.0], ["ossuary", "SE", 5.0],
	["vault", "NW", 4.0], ["vault", "NE", 4.0], ["vault", "SW", 4.0], ["vault", "SE", 4.0],
	["guard_hall", "NW", 3.0], ["guard_hall", "NE", 3.0], ["guard_hall", "SW", 4.0], ["guard_hall", "SE", 4.0],
	["shrine", "NW", 4.0], ["shrine", "NE", 4.0], ["shrine", "SW", 4.0], ["shrine", "SE", 4.0],
	["antechamber", "NW", 4.0], ["antechamber", "NE", 4.0], ["antechamber", "SW", 4.0], ["antechamber", "SE", 4.0],
	["bone_closet", "NW", 4.0], ["bone_closet", "NE", 4.0], ["bone_closet", "SW", 4.0], ["bone_closet", "SE", 4.0],
]

const START_CELL := Vector2(26, 56)

## Packs: {cell (column, row, may be fractional), stage, kinds [[kind, count]], mode ("" guards, "wander" strolls)}. Sizes follow the shared
## pack rules (DungeonMonsterGenerator.PACK_MIN..PACK_MAX), about one pack in five carries an elite (brute or warden), none before stage 3,
## and the first pack stands in sight of the start.
const PACKS: Array = [
	{"cell": Vector2(27, 54), "stage": 0, "kinds": [["zombie", 4]], "mode": ""},
	{"cell": Vector2(27, 47), "stage": 1, "kinds": [["zombie", 3], ["ghoul", 1]], "mode": ""},
	{"cell": Vector2(20, 46.5), "stage": 1, "kinds": [["zombie", 3], ["ghoul", 2], ["rock_thrower", 1]], "mode": "wander"},
	{"cell": Vector2(13, 46.5), "stage": 1, "kinds": [["zombie", 4], ["rock_thrower", 2]], "mode": ""},
	{"cell": Vector2(9, 42), "stage": 1, "kinds": [["ghoul", 2], ["zombie", 2]], "mode": ""},
	{"cell": Vector2(7, 36), "stage": 2, "kinds": [["zombie", 3], ["ghoul", 2], ["rock_thrower", 1]], "mode": ""},
	{"cell": Vector2(12, 34.5), "stage": 2, "kinds": [["zombie", 3], ["rock_thrower", 2]], "mode": ""},
	{"cell": Vector2(1, 36), "stage": 2, "kinds": [["zombie", 3], ["ghoul", 1]], "mode": ""},
	{"cell": Vector2(14, 30), "stage": 3, "kinds": [["brute", 1], ["zombie", 3]], "mode": ""},
	{"cell": Vector2(22, 36), "stage": 3, "kinds": [["zombie", 4], ["ghoul", 2]], "mode": "wander"},
	{"cell": Vector2(20, 29.5), "stage": 3, "kinds": [["rock_thrower", 2], ["zombie", 2]], "mode": ""},
	{"cell": Vector2(16, 24), "stage": 4, "kinds": [["ghoul", 3], ["rock_thrower", 2], ["zombie", 1]], "mode": ""},
	{"cell": Vector2(6.5, 24), "stage": 4, "kinds": [["ghoul", 3], ["rock_thrower", 1], ["zombie", 1]], "mode": ""},
	{"cell": Vector2(16, 17), "stage": 5, "kinds": [["zombie", 3], ["ghoul", 2], ["rock_thrower", 2]], "mode": "wander"},
	{"cell": Vector2(27, 16), "stage": 5, "kinds": [["brute", 1], ["ghoul", 3], ["zombie", 1]], "mode": ""},
	{"cell": Vector2(16, 11), "stage": 6, "kinds": [["brute", 1], ["ghoul", 2], ["zombie", 3]], "mode": ""},
	{"cell": Vector2(16, 3), "stage": 7, "kinds": [["warden", 1], ["zombie", 3], ["ghoul", 1], ["rock_thrower", 1]], "mode": ""},
	{"cell": Vector2(11, 4.5), "stage": 7, "kinds": [["ghoul", 3], ["rock_thrower", 2]], "mode": "wander"},
	{"cell": Vector2(21, 4.5), "stage": 7, "kinds": [["ghoul", 3], ["rock_thrower", 2]], "mode": "wander"},
]

## The walls round the arena rectangle (the arena's own ground and invisible perimeter): half the grid, plus a little margin.
static func half_x() -> float:
	return float(W) * CELL * 0.5 + 8.0


static func half_z() -> float:
	return float(H) * CELL * 0.5 + 8.0


## The middle of cell (c, r) on the ground, as world (x, z).
static func world(c: float, r: float) -> Vector2:
	return Vector2((c + 0.5 - float(W) * 0.5) * CELL, (r + 0.5 - float(H) * 0.5) * CELL)


## The space that owns cell (c, r), or "" for rock.
static func space_at(c: int, r: int) -> String:
	for key in SPACES:
		for rect in SPACES[key]["rects"]:
			if c >= int(rect[0]) and c <= int(rect[2]) and r >= int(rect[1]) and r <= int(rect[3]):
				return String(key)
	return ""


## The cell (as Vector2i) that world point (x, z) is in.
static func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(int(floor(point.x / CELL + float(W) * 0.5)), int(floor(point.y / CELL + float(H) * 0.5)))


## A route in cell coordinates as world points (x, z).
static func route_world(path: Array[Vector2]) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for cell in path:
		points.append(world(cell.x, cell.y))
	return points
