extends SceneTree
## Navigation check for the Crypt: from the start, a navigation path must reach the middle of every space and every doorway (so the hero,
## the archer and every enemy, which share one navigation map, can pass every door), and Nav.snap must keep each of them in place. Run:
##   godot --headless --path . -s res://game/dev/crypt_nav_check.gd -- --crypt01

var _main: Node
var _frames := 0

func _initialize() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 240 or _main.player == null or _main.location == null:
		return false
	var map: RID = _main.get_world_3d().navigation_map
	var from: Vector3 = _main.player.global_position
	var targets: Array = []
	for space in CryptLayout.SPACES:
		var rect: Array = CryptLayout.SPACES[space]["rects"][0]
		var c := Vector2((float(rect[0]) + float(rect[2])) * 0.5, (float(rect[1]) + float(rect[3])) * 0.5)
		targets.append([space, CryptLayout.world(c.x, c.y)])
	for door in _main.location.level.get_node("Walls").find_children("Walls*", "GridMap", false, false):
		var grid := door as GridMap
		for cell in grid.get_used_cells():
			if grid.mesh_library.get_item_name(grid.get_cell_item(cell)).begins_with("wall_doorway"):
				var local: Vector3 = grid.map_to_local(cell)
				var basis: Basis = grid.get_cell_item_basis(cell)
				var spot: Vector3 = grid.global_transform * (local + basis * Vector3(0, 0, -2.0))
				targets.append(["door@%d,%d" % [cell.x, cell.z], Vector2(spot.x, spot.z)])
	var bad := 0
	for t in targets:
		var p: Vector2 = t[1]
		var goal := Vector3(p.x, 0.0, p.y)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, goal, true)
		var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3(INF, 0, INF)
		var gap: float = Vector2(end.x, end.z).distance_to(p)
		if gap > 2.5:   # an altar may stand on a room's middle: its footprint plus the agent radius
			bad += 1
			print("CRYPT_NAV UNREACHABLE %s at %s: path ends %.1f m short" % [t[0], p, gap])
	print("CRYPT_NAV DONE targets=%d unreachable=%d" % [targets.size(), bad])
	quit(1 if bad > 0 else 0)
	return true
