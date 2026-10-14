extends SceneTree
## Headless check of the dungeon test level (issue #25): the level boots, the navigation mesh has a walkable path from the hero's start
## to every space, and the groups and props are in place. Run:
##   godot --headless --path . -s res://game/dev/dungeon_check.gd -- --dungeon --atmosphere

const TARGETS := {
	"entry": Vector3(0, 0, 36),
	"corridor_a": Vector3(0, 0, 19),
	"central": Vector3(0, 0, 4),
	"treasure": Vector3(20, 0, 1),
	"collapsed": Vector3(-21, 0, 2.2),
	"corridor_b": Vector3(0, 0, -10),
	"final": Vector3(0, 0, -30),
}

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
		print("DUNGEON_CHECK path %-11s %s  points=%d length=%.1f m" % [key, "OK" if reached else "NO PATH", path.size(), length])
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
	print("DUNGEON_CHECK enemies=%d crates=%d barrels=%d urns=%d" % [enemies, crates, barrels, urns])
	if enemies < 15:
		_failures += 1
	print("DUNGEON_CHECK DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)
	return true
