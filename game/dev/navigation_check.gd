extends SceneTree
## Deterministic real-physics navigation checks. Developer state only, no production save access.
var failures := 0
var world: Node3D
var arena: Arena
var hero: Player
var cutter: Player
var pillar: StaticBody3D

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	print("%s: %s" % ["PASS" if passed else "FAIL", label])
	if not passed: failures += 1

func box(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at + Vector3.UP * dimensions.y * 0.5
	body.collision_layer = Actor.LAYER_WORLD
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collider.shape = shape
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = dimensions
	mesh.mesh = cube
	body.add_child(mesh)
	arena._nav_region.add_child(body)
	return body

func settle_map() -> void:
	for i in 120:
		await physics_frame
		if Nav.ready(hero): return

func travel(body: Player, start: Vector3, goal: Vector3, seconds: float = 14.0) -> bool:
	body.global_position = start
	body.reset_physics_interpolation()
	Nav.reset(body, body.movement._nav_state)
	body.movement.goal = goal
	body.movement.has_goal = true
	var path_seen := false
	for i in int(seconds * 60):
		await physics_frame
		body.movement.move(1.0 / 60.0)
		path_seen = path_seen or (body.movement._nav_state.get("path", PackedVector3Array()) as PackedVector3Array).size() >= 2
		if body.flat_distance_to_point(goal) < 0.5:
			return path_seen
	print("  travel stopped at ", body.global_position, " goal ", goal, " state ", body.movement._nav_state)
	return false

func run() -> void:
	TownState.persist = false
	TownState.reset()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	arena = Arena.new()
	arena.scatter = false
	arena.half = 60
	world.add_child(arena)
	arena.build(false)
	pillar = box(Vector3.ZERO, Vector3(4, 4, 4))
	box(Vector3(20, 0, 0), Vector3(0.5, 3, 6))
	box(Vector3(-20, 0, -2), Vector3(12, 3, 2))
	box(Vector3(-20, 0, 2), Vector3(12, 3, 2))
	box(Vector3(-4, 0, 25), Vector3(1, 3, 10))
	box(Vector3(4, 0, 25), Vector3(1, 3, 10))
	box(Vector3(0, 0, 20), Vector3(9, 3, 1))
	for at in [Vector3(26, 0, 25), Vector3(34, 0, 25)]: box(at, Vector3(1, 4, 9))
	for at in [Vector3(30, 0, 21), Vector3(30, 0, 29)]: box(at, Vector3(9, 4, 1))
	arena.bake_navigation()
	hero = Player.new()
	world.add_child(hero)
	hero.set_physics_process(false)
	cutter = Player.new()
	cutter.member_id = "cutter"
	world.add_child(cutter)
	cutter.set_physics_process(false)
	cutter.global_position = Vector3(50, 0, 50)
	await settle_map()
	check("synchronized map contains usable polygons", Nav.ready(hero) and arena._nav_region.navigation_mesh.get_polygon_count() > 0)
	check("body sweep rejects direct pillar shortcut", not Nav.clearance(hero, Vector3(-6, 0, 0), Vector3(6, 0, 0)))
	check("Hero walks a valid detour around pillar", await travel(hero, Vector3(-6, 0, 0), Vector3(6, 0, 0)))
	check("Cutter uses same movement around nearby wall", await travel(cutter, Vector3(19, 0, 0), Vector3(21, 0, 0)))
	check("narrow passage retains actor clearance", await travel(hero, Vector3(-28, 0, 0), Vector3(-12, 0, 0)))
	check("U-shaped obstacle routes out through its opening", await travel(cutter, Vector3(0, 0, 25), Vector3(0, 0, 17)))
	hero.global_position = Vector3(-15, 0, -15)
	Nav.reset(hero, hero.movement._nav_state)
	for i in 240:
		await physics_frame
		hero.movement.goal = Vector3(0 if i < 60 else 8, 0, -15)
		hero.movement.has_goal = true
		hero.movement.move(0.016)
	check("moving goal replaces cached endpoint without cutting corners", hero.global_position.x > 1.0 and hero.movement._nav_state.goal.x == 8)
	var enemy := Enemy.new()
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.target = hero
	enemy.global_position = Vector3(19, 0, 0)
	hero.global_position = Vector3(21, 0, 0)
	var hp := hero.health
	enemy.strike_target(1.0, 1.0)
	check("nearby enemy cannot melee through wall", hero.health == hp)
	cutter.global_position = Vector3(21, 0, 0)
	cutter.bow.start(enemy)
	check("common bow refuses a shot through solid wall", not cutter.skills.busy)
	cutter.global_position = Vector3(50, 0, 50)
	for i in 600:
		await physics_frame
		enemy.advance_on_target(0.016, enemy.flat_distance_to(hero))
		if enemy.flat_distance_to(hero) <= enemy.attack_range and Nav.line_clear(enemy, hero.global_position): break
	check("enemy chase routes around wall even within old bypass range", enemy.flat_distance_to(hero) <= enemy.attack_range and Nav.line_clear(enemy, hero.global_position))
	enemy.global_position = Vector3(10, 0, -10)
	hero.global_position = Vector3(9, 0, -10)
	for i in 120:
		await physics_frame
		enemy.back_away_from(hero.global_position)
	check("enemy retreat uses reachable routing", enemy.global_position.x > 10.5)
	enemy.global_position = Vector3(19, 0, 1)
	hero.global_position = Vector3(21, 0, 1)
	Nav.reset(enemy, enemy._nav_state)
	var circle_start := enemy.global_position
	for frame in 180:
		await physics_frame
		enemy.circle_target(enemy.flat_distance_to(hero))
	check("enemy circling uses shared paths and moves without entering wall", enemy._nav_state.has("queries") and enemy.global_position.distance_to(circle_start) > 0.5 and Nav.clearance(enemy, enemy.global_position, enemy.global_position))
	enemy.queue_free()
	# Companion follow and subgroup switching execute the same movement component.
	hero.global_position = Vector3(6, 0, 0)
	cutter.global_position = Vector3(-6, 0, 0)
	hero.attack_target = null
	cutter.attack_target = null
	Nav.reset(cutter, cutter.movement._nav_state)
	for i in 600:
		await physics_frame
		cutter.ai.tick(0.016)
		if i == 60:
			var in_flight_cache := cutter.movement._nav_state.duplicate(true)
			PartyManager.current().select("cutter")
			check("switch during traversal retains the body's own route", cutter.movement._nav_state == in_flight_cache)
			PartyManager.current().select("hero")
		if cutter.flat_distance_to(hero) <= 3.6: break
	check("inactive Cutter follows around obstacle without rescue", cutter.flat_distance_to(hero) <= 3.6)
	var hero_cache := hero.movement._nav_state.duplicate(true)
	PartyManager.current().select("cutter")
	check("switching does not transfer navigation caches", hero.movement._nav_state == hero_cache and hero.movement._nav_state != cutter.movement._nav_state)
	PartyManager.current().select("hero")
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16
	hero.global_position = Vector3(-35, 0, -35)
	camera.position = hero.global_position + Vector3(0, 20, 10)
	camera.look_at(hero.global_position)
	camera.make_current()
	cutter.global_position = Vector3(10, 0, -35)
	cutter.movement._nav_state = {"failed_time": 5.0, "failed_replans": 2}
	cutter.ai._trail = [Vector3(-35, 0, -18)]
	check("sustained distant off-camera failure permits rescue", cutter.ai.rescue_eligible(hero))
	var camera_pos := camera.position
	var camera_rotation := camera.rotation
	camera.position = cutter.global_position + Vector3(0, 20, 10)
	camera.look_at(cutter.global_position)
	check("visible distant departure prohibits rescue", not cutter.ai.try_rescue(hero))
	camera.position = camera_pos
	camera.rotation = camera_rotation
	camera.clear_current(false)
	check("unknown camera visibility prohibits rescue", not cutter.ai.try_rescue(hero))
	camera.make_current()
	cutter.skills.busy = true
	check("committed attack prohibits rescue", not cutter.ai.try_rescue(hero))
	cutter.skills.busy = false
	cutter.stun_time = 1.0
	check("incapacitation prohibits rescue", not cutter.ai.try_rescue(hero))
	cutter.stun_time = 0.0
	cutter.knockdown.phase = Knockdown.Phase.DOWNED
	check("knockdown prohibits rescue", not cutter.ai.try_rescue(hero))
	cutter.knockdown.phase = Knockdown.Phase.NONE
	var saved_ragdoll := cutter.ragdoll
	cutter.ragdoll = Ragdoll.new(cutter)
	cutter.ragdoll.state = Ragdoll.State.LYING
	check("ragdoll prohibits rescue", not cutter.ai.try_rescue(hero))
	cutter.ragdoll = saved_ragdoll
	cutter.movement.rolling = true
	check("dodge prohibits rescue", not cutter.ai.try_rescue(hero))
	cutter.movement.rolling = false
	cutter.dead = true
	check("dead member cannot rescue", not cutter.ai.try_rescue(hero))
	cutter.dead = false
	cutter.movement._nav_state.failed_replans = 1
	check("two failed replans are required", not cutter.ai.try_rescue(hero))
	cutter.movement._nav_state.failed_replans = 2
	cutter.ai._trail = [Vector3.ZERO]
	check("blocked breadcrumb cannot rescue", not cutter.ai.try_rescue(hero))
	cutter.ai._trail = []
	check("missing recorded route cannot rescue", not cutter.ai.try_rescue(hero))
	cutter.ai._trail = [hero.global_position]
	check("visible arrival prohibits rescue", not cutter.ai.try_rescue(hero))
	cutter.ai._trail = [Vector3(-35, 0, -18)]
	var occupied := Enemy.new()
	world.add_child(occupied)
	occupied.set_physics_process(false)
	occupied.global_position = cutter.ai._trail[0]
	await physics_frame
	check("occupied arrival cannot rescue", not cutter.ai.try_rescue(hero))
	occupied.queue_free()
	await physics_frame
	check("safe off-camera breadcrumb rescues and clears route", cutter.ai.try_rescue(hero) and cutter.movement._nav_state.is_empty())
	cutter.global_position = hero.global_position
	cutter.movement._nav_state = {"failed_time": 10.0, "failed_replans": 5}
	check("visible departure and short distance prohibit rescue", not cutter.ai.rescue_eligible(hero))
	cutter.global_position = Vector3(10, 0, -35)
	cutter.movement._nav_state = {"failed_time": 4.0, "failed_replans": 1}
	check("distance alone never triggers rescue", not cutter.ai.rescue_eligible(hero))
	hero.global_position = Vector3(30, 0, 25)
	Nav.reset(hero, hero.movement._nav_state)
	var result: Dictionary
	for i in 420:
		await physics_frame
		result = Nav.route(hero, Vector3(40, 0, 25), hero.movement._nav_state, 1.0 / 60.0)
		if result.status == Nav.Status.FOLLOWING:
			hero.move_with((result.waypoint - hero.global_position).normalized() * 4.5)
		else: hero.move_with(Vector3.ZERO)
	check("disconnected goal stops at reachable endpoint", result.status == Nav.Status.UNREACHABLE and hero.global_position.x < 34)
	var retries := int(hero.movement._nav_state.queries)
	var stopped_at := hero.global_position
	for frame in 120:
		await physics_frame
		Nav.route(hero, Vector3(40, 0, 25), hero.movement._nav_state, 1.0 / 60.0)
	check("failed route backs off to one-second retries without wall pushing", int(hero.movement._nav_state.queries) - retries <= 3 and hero.global_position.distance_to(stopped_at) < 0.01)
	Nav.debug_broken_snap = true
	result = Nav.route(hero, Vector3.ZERO, {}, 0.016)
	check("unusable map waits without direct steering", result.status == Nav.Status.WAITING and result.waypoint == hero.global_position)
	Nav.debug_broken_snap = false
	var iteration := NavigationServer3D.map_get_iteration_id(Nav.map_of(hero))
	pillar.queue_free()
	await process_frame
	arena.request_nav_refresh()
	for i in 240:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(Nav.map_of(hero)) != iteration: break
	check("destroyed prop performs a real synchronized rebake", NavigationServer3D.map_get_iteration_id(Nav.map_of(hero)) != iteration)
	check("destroyed pillar opens a body-clear direct route", Nav.clearance(hero, Vector3(-6, 0, 0), Vector3(6, 0, 0)))
	check("character follows newly opened route", await travel(hero, Vector3(-6, 0, 0), Vector3(6, 0, 0)))
	var before_overlap := NavigationServer3D.map_get_iteration_id(Nav.map_of(hero))
	arena._nav_region.bake_navigation_mesh(true)
	arena.request_nav_refresh()
	for frame in 240:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(Nav.map_of(hero)) >= before_overlap + 2: break
	check("refresh requested during a bake is not lost", NavigationServer3D.map_get_iteration_id(Nav.map_of(hero)) >= before_overlap + 2)
	# Six common characters plus twenty real enemies exercise the shared FIFO.
	var actors: Array[Actor] = [hero, cutter]
	for i in 4:
		var body := Player.new()
		body.member_id = "nav_guest_%d" % i
		world.add_child(body)
		body.set_physics_process(false)
		actors.append(body)
	for i in 20:
		var body := Enemy.new()
		world.add_child(body)
		body.set_physics_process(false)
		actors.append(body)
	var states: Array[Dictionary] = []
	for i in actors.size():
		actors[i].global_position = Vector3(-40 + i, 0, -30)
		states.append({})
	Nav.queries_peak = 0
	Nav.longest_wait_ticks = 0
	for frame in 240:
		await physics_frame
		for i in actors.size():
			var step := Nav.route(actors[i], Vector3(-40 + i, 0, -20), states[i], 0.016)
			if step.status == Nav.Status.FOLLOWING:
				var direction: Vector3 = step.waypoint - actors[i].global_position
				direction.y = 0
				actors[i].move_with(direction.normalized() * 3.0)
	var served := true
	for state in states: served = served and state.has("queries")
	check("all six characters and twenty crowd actors receive paths", served)
	check("strict four-query budget and bounded FIFO wait", Nav.queries_peak <= 4 and Nav.longest_wait_ticks <= 7)
	var progressed := true
	for body in actors: progressed = progressed and body.global_position.z > -25
	check("six-member party and enemy crowd make actual forward progress", progressed)
	print("NAVIGATION CHECK: %d failure(s); peak queries %d; longest wait %d ticks" % [failures, Nav.queries_peak, Nav.longest_wait_ticks])
	quit(1 if failures else 0)
