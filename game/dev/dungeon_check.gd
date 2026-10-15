extends SceneTree
## Headless check of the dungeon test level (issue #25, grown for issue #34): the level boots, the navigation mesh has a walkable path from
## the hero's start to every area and side space, the groups, props and chests are in place, and the enemy-level projection is printed
## for entry levels 1, 5 and 10. Run:
##   godot --headless --path . -s res://game/dev/dungeon_check.gd -- --dungeon --atmosphere

const TARGETS := {
	"entry": Vector3(0, 0, 100),
	"corridor_1": Vector3(9, 0, 82),
	"hall_1": Vector3(-20, 0, 64),
	"corridor_2": Vector3(-25, 0, 48),
	"hall_2": Vector3(0, 0, 30),
	"corridor_3": Vector3(25, 0, 13),
	"hall_3": Vector3(0, 0, -4),
	"corridor_4": Vector3(-29, 0, -28),
	"hall_4": Vector3(0, 0, -52),
	"corridor_5": Vector3(21, 0, -76),
	"hall_5": Vector3(0, 0, -100),
	"alcove_w0": Vector3(-15, 0, 98),
	"cave_a": Vector3(20, 0, 94),
	"alcove_k1w": Vector3(3, 0, 83),
	"treasure_h3e": Vector3(35, 0, -6),
	"chamber_h2e": Vector3(34, 0, 33),
	"cave_h3a": Vector3(-12, 0, 8),
	"treasure_vault": Vector3(13, 0, -116),
	"alcove_h5e": Vector3(37, 0, -96),
}
## The enemies the dungeon places (the groups in TestDungeon.GROUPS) and its chests (CHEST_SPOTS).
const EXPECT_ENEMIES := 85
const EXPECT_CHESTS := 5
const ENTRY_LEVELS := [1, 5, 10]

var _main: Node
var _frames := 0
var _failures := 0


func _initialize() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 240:
		return false
	if _main.location == null or not (_main.location is TestDungeon):
		print("DUNGEON_CHECK FAIL: the dungeon was not built (run with -- --dungeon)")
		quit(1)
		return true
	var map: RID = _main.get_world_3d().navigation_map
	var start: Vector3 = _main.location.start_position()
	print("DUNGEON_CHECK start %s" % start)
	for key in TARGETS:
		var goal: Vector3 = TARGETS[key]
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, goal, true)
		var reached: bool = path.size() > 0 and path[path.size() - 1].distance_to(goal) < 2.0
		if not reached:
			_failures += 1
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		print("DUNGEON_CHECK path %-14s %s  points=%d length=%.1f m" % [key, "OK" if reached else "NO PATH", path.size(), length])
	var enemies := get_nodes_in_group("enemies").size()
	var crates := 0
	var barrels := 0
	var urns := 0
	for node in _main.find_children("*", "Destructible", true, false):
		var prop: String = (node as Destructible).prop_name
		if prop == "crate":
			crates += 1
		elif prop == "barrel":
			barrels += 1
		elif prop == "urn":
			urns += 1
	var chests := get_nodes_in_group("chests").size()
	print("DUNGEON_CHECK enemies=%d chests=%d crates=%d barrels=%d urns=%d" % [enemies, chests, crates, barrels, urns])
	if enemies < EXPECT_ENEMIES:
		_failures += 1
	if chests != EXPECT_CHESTS:
		_failures += 1
	var levels: Dictionary = {}
	for node in get_nodes_in_group("enemies"):
		var level: int = (node as Enemy).level
		levels[level] = int(levels.get(level, 0)) + 1
	print("DUNGEON_CHECK enemy levels at load (hero XP %d, level %d): %s" % [TownState.hero_xp, TownState.hero_level, levels])
	for entry in ENTRY_LEVELS:
		_print_projection(entry)
	print("DUNGEON_CHECK DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)
	return true


## The projection for a hero who enters the dungeon at `entry` (XP at the very start of that level). Enemy level is the hero's level
## on arrival at each area; XP per area is what its kills pay the hero (Cutter in the party).
func _print_projection(entry: int) -> void:
	print("DUNGEON_PROJECTION entry level %d (xp %d)" % [entry, HeroProgression.xp_for_level(entry)])
	print("DUNGEON_PROJECTION   area          enemy_lvl  xp_in_area  xp_total  hero_lvl_after")
	for row in TestDungeon.project(HeroProgression.xp_for_level(entry)):
		print("DUNGEON_PROJECTION   %-13s %9d %11d %9d %15d" % [row["area"], row["level"], row["xp"], row["xp_total"], row["hero_level"]])
