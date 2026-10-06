class_name Nav
extends RefCounted
## Thin wrapper over the navigation map so the hero and zombies walk around solid objects instead of
## sliding along them. Falls back to straight-line movement until the arena's navmesh exists.

static func map_of(node: Node3D) -> RID:
	return node.get_world_3d().navigation_map

## Tests set this to simulate a navigation map that is not usable yet (every query answers with the origin).
static var debug_broken_snap: bool = false

static func ready(node: Node3D) -> bool:
	return debug_broken_snap or NavigationServer3D.map_get_iteration_id(map_of(node)) > 0

## Nearest walkable point; clicking inside a pillar sends you to the closest reachable spot beside it.
static func snap(node: Node3D, point: Vector3) -> Vector3:
	if debug_broken_snap:
		return Vector3.ZERO
	if not ready(node):
		return point
	return NavigationServer3D.map_get_closest_point(map_of(node), point)

## Path queries a physics tick may spend (a crowd chasing a moving hero used to ask for a new path every tick, each).
const QUERIES_PER_TICK := 4
static var _budget_tick: int = -1
static var _budget_used: int = 0

static func _may_query() -> bool:
	var tick: int = Engine.get_physics_frames()
	if tick != _budget_tick:
		_budget_tick = tick
		_budget_used = 0
	if _budget_used >= QUERIES_PER_TICK:
		return false
	_budget_used += 1
	return true

## The next point to steer toward on the way to `goal`. `state` is a per-actor Dictionary that caches the path. A new path is asked for
## only when the old one has run its time, the goal has really moved (a fraction of the way left, not a fixed 0.6 m: a hero running
## about is always moving), or the actor has stopped getting anywhere (stuck on a corner), and never more than a few a tick.
static func next_point(node: Node3D, goal: Vector3, state: Dictionary, delta: float, refresh: float = 0.4) -> Vector3:
	if not ready(node):
		return goal
	var here: Vector3 = node.global_position
	state["timer"] = float(state.get("timer", 0.0)) - delta
	var path: PackedVector3Array = state.get("path", PackedVector3Array())
	var remaining: float = Vector2(goal.x - here.x, goal.z - here.z).length()
	var moved_goal: float = (state.get("goal", Vector3(INF, INF, INF)) as Vector3).distance_to(goal)
	var stale_goal: bool = moved_goal > maxf(2.0, remaining * 0.25)
	# Stuck: a second of trying to get somewhere without covering half a metre.
	state["stuck_t"] = float(state.get("stuck_t", 0.0)) + delta
	var stuck: bool = false
	if float(state["stuck_t"]) >= 1.0:
		var last_pos: Vector3 = state.get("stuck_pos", Vector3(INF, INF, INF))
		stuck = Vector2(last_pos.x - here.x, last_pos.z - here.z).length() < 0.5 and remaining > 2.0
		state["stuck_t"] = 0.0
		state["stuck_pos"] = here
	if float(state["timer"]) <= 0.0 or path.size() < 2 or stale_goal or stuck:
		if _may_query() or path.size() < 2:
			var map: RID = map_of(node)
			var from: Vector3 = NavigationServer3D.map_get_closest_point(map, here)
			var to: Vector3 = NavigationServer3D.map_get_closest_point(map, goal)
			path = NavigationServer3D.map_get_path(map, from, to, true)
			state["path"] = path
			state["index"] = 1
			state["goal"] = goal
			state["timer"] = refresh + randf() * 0.25
			if stuck and path.size() > 2:
				state["index"] = 2   # skip the corner it was wedged on
	if path.is_empty():
		return goal
	var index: int = int(state.get("index", 1))
	while index < path.size() - 1:
		var waypoint: Vector3 = path[index]
		if Vector2(waypoint.x - here.x, waypoint.z - here.z).length() < 0.55:
			index += 1
		else:
			break
	state["index"] = index
	if index >= path.size() - 1:
		return goal   # on the last leg it heads for where the target is now, not where it was when the path was made
	return path[index]
