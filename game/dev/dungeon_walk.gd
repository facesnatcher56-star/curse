extends SceneTree
## Walks the hero through the dungeon test level once, start to end, with click-to-move goals (issue #25), and reports any stuck spot.
## The enemies' AI is frozen for this walk, so it tests the navigation and the props, not the fight. Run:
##   godot --headless --path . -s res://game/dev/dungeon_walk.gd -- --dungeon

## The route: each waypoint must be reached within TOLERANCE metres.
## The critical path, door to door: the entry, then each corridor and hall to the final hall (see TestDungeon).
var ROUTE: Array = [
	Vector3(0, 0, 100), Vector3(9, 0, 82), Vector3(-20, 0, 64), Vector3(-25, 0, 48), Vector3(0, 0, 30), Vector3(25, 0, 13),
	Vector3(0, 0, -4), Vector3(-29, 0, -28), Vector3(0, 0, -52), Vector3(21, 0, -76), Vector3(0, 0, -100),
]
const TOLERANCE := 1.4
const STUCK_SECONDS := 4.0
const LIMIT_SECONDS := 240.0   # the critical path is about 345 m

var _main: Node
var _frames := 0
var _leg := 0
var _elapsed := 0.0
var _still := 0.0
var _last := Vector3.ZERO
var _stuck_reports := 0
var _failures := 0
var _frozen := false


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--crypt01"):   # the Crypt: its main route, or `--loop` for the way through the ossuary
		var cells: Array[Vector2] = CryptLayout.LOOP_PATH if OS.get_cmdline_user_args().has("--loop") else CryptLayout.MAIN_PATH
		ROUTE = []
		for w in CryptLayout.route_world(cells):
			ROUTE.append(Vector3(w.x, 0.0, w.y))
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main


func _process(delta: float) -> bool:
	_frames += 1
	if _frames < 240 or _main.player == null or _main.location == null:
		return false
	if not _frozen:
		# The guards stand in the passages and would block the hero (they have to be fought through in play). For a clean geometry
		# walk they are removed; the props, walls and navigation are what is being tested.
		for e in get_nodes_in_group("enemies"):
			(e as Node).queue_free()
		_frozen = true
		_last = _main.player.global_position
		print("DUNGEON_WALK start %s, %d waypoints" % [_last, ROUTE.size()])
		_goto(0)
		return false
	var hero: Node3D = _main.player
	var here: Vector3 = hero.global_position
	_elapsed += delta
	if here.distance_to(_last) < 0.05:
		_still += delta
	else:
		_still = 0.0
	_last = here
	if _still > STUCK_SECONDS:
		_stuck_reports += 1
		print("DUNGEON_WALK STUCK on leg %d at %s (no progress for %.1f s)" % [_leg, here, _still])
		_diagnose(here, ROUTE[mini(_leg, ROUTE.size() - 1)])
		_failures += 1
		_still = 0.0
		_leg = ROUTE.size()   # stop the walk here
	if _leg < ROUTE.size() and here.distance_to(ROUTE[_leg]) < TOLERANCE:
		print("DUNGEON_WALK reached %d %s at t=%.1f s" % [_leg, ROUTE[_leg], _elapsed])
		_leg += 1
		if _leg < ROUTE.size():
			_goto(_leg)
	if _leg >= ROUTE.size() or _elapsed > LIMIT_SECONDS:
		var done: bool = _leg >= ROUTE.size()
		if not done:
			print("DUNGEON_WALK TIMEOUT on leg %d at %s" % [_leg, here])
			_failures += 1
		print("DUNGEON_WALK DONE legs=%d/%d elapsed=%.1f s stuck=%d failures=%d" % [mini(_leg, ROUTE.size()), ROUTE.size(), _elapsed,
			_stuck_reports, _failures])
		quit(1 if _failures > 0 else 0)
		return true
	return false


## Prints the navigation path from where the hero stopped to the waypoint, and the solid things close to the stop.
func _diagnose(here: Vector3, goal: Vector3) -> void:
	var map: RID = _main.get_world_3d().navigation_map
	var snapped: Vector3 = Nav.snap(_main.player, _main.location.at(goal.x, goal.z))
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, here, snapped, true)
	print("DUNGEON_WALK diag goal %s snapped %s path_points=%d end=%s" % [goal, snapped, path.size(),
		path[path.size() - 1] if path.size() > 0 else Vector3.ZERO])
	for node in _main.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body.global_position.distance_to(goal) < 3.5 or body.global_position.distance_to(here) < 3.5:
			for child in body.get_children():
				if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
					var shape: Shape3D = (child as CollisionShape3D).shape
					print("DUNGEON_WALK diag body %s shape %s at %s shape_size=%s" % [body.get_parent().name, shape.get_class(),
						(child as CollisionShape3D).global_position, shape.get_class()])
	var shape := CylinderShape3D.new()
	shape.radius = float(_main.player.get("body_radius")) + 0.05
	shape.height = maxf(float(_main.player.get("body_height")) - 0.2, 0.2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Actor.LAYER_WORLD
	query.transform = Transform3D(Basis.IDENTITY, Vector3(here.x, shape.height * 0.5 + 0.1, here.z))
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var hits: Array = space.intersect_shape(query, 8)
	print("DUNGEON_WALK diag clearance radius=%.2f height=%.2f start_hits=%d" % [shape.radius, shape.height, hits.size()])
	query.motion = Vector3(goal.x - here.x, 0, goal.z - here.z)
	var fractions: PackedFloat32Array = space.cast_motion(query)
	print("DUNGEON_WALK diag cast_motion fractions=%s motion=%s" % [fractions, query.motion])
	if fractions.size() == 2:
		query.transform = Transform3D(Basis.IDENTITY, Vector3(here.x, shape.height * 0.5 + 0.1, here.z) + query.motion * fractions[1])
		query.motion = Vector3.ZERO
		var blockers: Array = space.intersect_shape(query, 8)
		for hit in blockers:
			var collider: Object = hit["collider"]
			print("DUNGEON_WALK diag blocker %s parent=%s at %s" % [collider.name, collider.get_parent().name, (collider as Node3D).global_position])
	var params := PhysicsTestMotionParameters3D.new()
	params.from = _main.player.global_transform
	params.motion = Vector3(-0.5, 0, 0)
	var result := PhysicsTestMotionResult3D.new()
	var blocked: bool = PhysicsServer3D.body_test_motion(_main.player.get_rid(), params, result)
	print("DUNGEON_WALK diag body_test_motion blocked=%s collision=%s" % [blocked, result.get_collision_count()])
	if result.get_collision_count() > 0:
		var collider_id: int = result.get_collider_id(0)
		var collider_obj: Object = instance_from_id(collider_id)
		var who: Node3D = collider_obj as Node3D
		print("DUNGEON_WALK diag body collider %s at %s groups=%s companion=%s" % [who.name, who.global_position,
			who.get_groups(), who == _main.companion])
	var nav_here: Vector3 = NavigationServer3D.map_get_closest_point(map, here)
	var nav_goal: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(goal.x, 0.0, goal.z))
	print("DUNGEON_WALK diag nav closest to stop %s, to goal %s" % [nav_here, nav_goal])


func _goto(leg: int) -> void:
	var hero: Node3D = _main.player
	var goal: Vector3 = ROUTE[leg]
	hero.movement.goal = Nav.snap(hero, _main.location.at(goal.x, goal.z))
	hero.movement.has_goal = true
