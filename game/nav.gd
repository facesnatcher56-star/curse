class_name Nav
extends RefCounted
## Shared, budgeted routing. Failed queries never authorize straight-line movement.
enum Status { FOLLOWING, ARRIVED, WAITING, UNREACHABLE }
const QUERIES_PER_TICK := 4
static var debug_broken_snap: bool = false
static var _budget_tick: int = -1
static var _budget_used: int = 0
static var _pending: Array[Dictionary] = []
static var queries_peak: int = 0
static var requests_total: int = 0   # every path query served, monotonic (per-agent state is cleared on rebake; this is not)
static var longest_wait_ticks: int = 0
static var _ready_iterations: Dictionary = {}

static func map_of(node: Node3D) -> RID:
	return node.get_world_3d().navigation_map

static func ready(node: Node3D) -> bool:
	var map := map_of(node)
	if debug_broken_snap or NavigationServer3D.map_get_iteration_id(map) == 0: return false
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	if int(_ready_iterations.get(map, -1)) == iteration: return true
	for rid in NavigationServer3D.map_get_regions(map):
		if NavigationServer3D.region_get_enabled(rid) and NavigationServer3D.region_get_iteration_id(rid) > 0:
			if NavigationServer3D.map_get_closest_point_owner(map, node.global_position).is_valid():
				_ready_iterations[map] = iteration
				return true
	return false

static func snap(node: Node3D, point: Vector3) -> Vector3:
	if debug_broken_snap: return Vector3.ZERO
	if not ready(node): return point
	return NavigationServer3D.map_get_closest_point(map_of(node), point)

static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## World-only body clearance; floor lies below the swept cylinder.
static func clearance(node: Node3D, from: Vector3, to: Vector3, include_actors: bool = false) -> bool:
	var shape := CylinderShape3D.new()
	shape.radius = float(node.get("body_radius")) + 0.05 if node is Actor else 0.45
	shape.height = maxf(float(node.get("body_height")) - 0.2, 0.2) if node is Actor else 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Actor.LAYER_WORLD
	if include_actors:
		query.collision_mask |= Actor.LAYER_PLAYER | Actor.LAYER_ENEMY
		if node is CollisionObject3D: query.exclude = [node.get_rid()]
	query.transform = Transform3D(Basis.IDENTITY, Vector3(from.x, shape.height * 0.5 + 0.1, from.z))
	query.motion = Vector3(to.x - from.x, 0, to.z - from.z)
	var space := node.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	if query.motion.length_squared() < 0.0001: return true
	var fractions := space.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.999

static func line_clear(node: Node3D, to: Vector3, ignore: Object = null) -> bool:
	return sight_clear(node, node.global_position, to, ignore)

## Waist-high sight line over the world geometry from `from` to `to`. When `ignore` is a prop being shot at, its own collider as the
## first thing hit is allowed (the sight line ends at its centre); anything else in the way blocks.
static func sight_clear(node: Node3D, from: Vector3, to: Vector3, ignore: Object = null) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.8, Vector3(to.x, 0.8, to.z), Actor.LAYER_WORLD)
	var hit: Dictionary = node.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return true
	return ignore != null and hit.collider is Node and (hit.collider as Node).get_parent() == ignore

static func reset(node: Node3D, state: Dictionary) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		if int(_pending[i].id) == node.get_instance_id(): _pending.remove_at(i)
	state.clear()

static func _request(node: Node3D, goal: Vector3, state: Dictionary) -> void:
	for entry in _pending:
		if int(entry.id) == node.get_instance_id():
			entry.goal = goal
			return
	_pending.append({"id": node.get_instance_id(), "node": weakref(node), "goal": goal,
		"state": state, "tick": Engine.get_physics_frames()})

## FIFO service. New paths and retries share the same strict cap.
static func _service() -> void:
	var tick := Engine.get_physics_frames()
	if tick != _budget_tick:
		_budget_tick = tick
		_budget_used = 0
	while _budget_used < QUERIES_PER_TICK and not _pending.is_empty():
		var entry: Dictionary = _pending.pop_front()
		var node := entry.node.get_ref() as Node3D
		if not is_instance_valid(node) or not node.is_inside_tree(): continue
		var state: Dictionary = entry.state
		if not ready(node): continue
		_budget_used += 1
		requests_total += 1
		queries_peak = maxi(queries_peak, _budget_used)
		longest_wait_ticks = maxi(longest_wait_ticks, tick - int(entry.tick))
		var map := map_of(node)
		var from := NavigationServer3D.map_get_closest_point(map, node.global_position)
		var to := NavigationServer3D.map_get_closest_point(map, entry.goal)
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		state["path"] = path
		state["index"] = 1 if path.size() > 1 else 0
		state["goal"] = entry.goal
		state["endpoint"] = to
		state["iteration"] = NavigationServer3D.map_get_iteration_id(map)
		state["map"] = map
		state["timer"] = 1.0 if path.is_empty() or float(state.get("failed_time", 0.0)) >= 5.0 else 0.4
		state["retry_grace"] = 0.2
		state["queries"] = int(state.get("queries", 0)) + 1
		if float(state.get("failed_time", 0.0)) >= 1.0:
			state["failed_replans"] = int(state.get("failed_replans", 0)) + 1
		state["blocked"] = false

static func route(node: Node3D, goal: Vector3, state: Dictionary, delta: float) -> Dictionary:
	var here := node.global_position
	if not ready(node):
		state["path"] = PackedVector3Array()
		return {"status": Status.WAITING, "waypoint": here}
	var map := map_of(node)
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	if state.get("map", map) != map or int(state.get("iteration", iteration)) != iteration:
		reset(node, state)
	state["timer"] = float(state.get("timer", 0.0)) - delta
	state["retry_grace"] = maxf(float(state.get("retry_grace", 0.0)) - delta, 0.0)
	var anchor: Vector3 = state.get("progress_pos", here)
	if _flat_gap(anchor, here) >= 0.5:
		state["progress_pos"] = here
		state["failed_time"] = 0.0
		state["failed_replans"] = 0
	else:
		state["progress_pos"] = anchor
		state["failed_time"] = float(state.get("failed_time", 0.0)) + delta
	var path: PackedVector3Array = state.get("path", PackedVector3Array())
	var moved := _flat_gap(state.get("goal", Vector3(INF, 0, INF)), goal) > 0.5
	var stalled := float(state.get("failed_time", 0.0)) >= 1.0
	var exhausted := float(state.get("failed_time", 0.0)) >= 5.0 and int(state.get("failed_replans", 0)) >= 2
	if float(state["timer"]) <= 0.0 and (path.is_empty() or moved or stalled or bool(state.get("blocked", false))):
		_request(node, goal, state)
	_service()
	path = state.get("path", PackedVector3Array())
	if path.is_empty(): return {"status": Status.UNREACHABLE if state.has("queries") else Status.WAITING, "waypoint": here}
	var index := mini(int(state.get("index", 0)), path.size() - 1)
	while index < path.size() - 1 and _flat_gap(here, path[index]) <= 0.25:
		if not clearance(node, here, path[index + 1]): break
		index += 1
	state["index"] = index
	var endpoint := path[path.size() - 1]
	if index == path.size() - 1 and _flat_gap(here, endpoint) <= 0.2:
		if _flat_gap(state.get("goal", goal), goal) > 0.5:
			return {"status": Status.WAITING, "waypoint": here}
		return {"status": Status.ARRIVED if _flat_gap(endpoint, state.endpoint) <= 0.5 else Status.UNREACHABLE, "waypoint": here}
	if exhausted and float(state.get("retry_grace", 0.0)) <= 0.0: return {"status": Status.UNREACHABLE, "waypoint": here}
	if not clearance(node, here, path[index]):
		state["blocked"] = true
		return {"status": Status.WAITING, "waypoint": here}
	return {"status": Status.FOLLOWING, "waypoint": path[index]}

## Compatibility for developer callers; runtime consumers use the explicit result.
static func next_point(node: Node3D, goal: Vector3, state: Dictionary, delta: float, _refresh: float = 0.4) -> Vector3:
	return route(node, goal, state, delta).waypoint
