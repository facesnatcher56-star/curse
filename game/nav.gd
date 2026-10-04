class_name Nav
extends RefCounted
## Thin wrapper over the navigation map so the hero and zombies walk around solid objects instead of
## sliding along them. Falls back to straight-line movement until the arena's navmesh exists.

static func map_of(node: Node3D) -> RID:
	return node.get_world_3d().navigation_map

static func ready(node: Node3D) -> bool:
	return NavigationServer3D.map_get_iteration_id(map_of(node)) > 0

## Nearest walkable point; clicking inside a pillar sends you to the closest reachable spot beside it.
static func snap(node: Node3D, point: Vector3) -> Vector3:
	if not ready(node):
		return point
	return NavigationServer3D.map_get_closest_point(map_of(node), point)

## The next point to steer toward on the way to `goal`. `state` is a per-actor Dictionary that caches the path.
static func next_point(node: Node3D, goal: Vector3, state: Dictionary, delta: float, refresh: float = 0.4) -> Vector3:
	if not ready(node):
		return goal
	state["timer"] = float(state.get("timer", 0.0)) - delta
	var path: PackedVector3Array = state.get("path", PackedVector3Array())
	var stale_goal: bool = (state.get("goal", Vector3(INF, INF, INF)) as Vector3).distance_to(goal) > 0.6
	if float(state["timer"]) <= 0.0 or path.size() < 2 or stale_goal:
		var map: RID = map_of(node)
		var from: Vector3 = NavigationServer3D.map_get_closest_point(map, node.global_position)
		var to: Vector3 = NavigationServer3D.map_get_closest_point(map, goal)
		path = NavigationServer3D.map_get_path(map, from, to, true)
		state["path"] = path
		state["index"] = 1
		state["goal"] = goal
		state["timer"] = refresh + randf() * 0.15
	if path.is_empty():
		return goal
	var index: int = int(state.get("index", 1))
	var here: Vector3 = node.global_position
	while index < path.size() - 1:
		var waypoint: Vector3 = path[index]
		if Vector2(waypoint.x - here.x, waypoint.z - here.z).length() < 0.55:
			index += 1
		else:
			break
	state["index"] = index
	return path[mini(index, path.size() - 1)]