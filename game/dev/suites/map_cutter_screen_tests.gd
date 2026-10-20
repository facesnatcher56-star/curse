extends DevSuite
## Map mode, issue #87 part 1: the Cutter stays on screen. Unit checks of the safe area and the clamp, then the real thing on the dedicated map
## (MapModeDungeon, "The Sunken Way"): the party dashes to a narrow room, a big pit, a champion room and the boss court through MapMode's own click
## path, the Cutter is projected through the real camera at arrival and every second of a simulated fight, and must stay inside the safe area.
## Run with `--only=mmcutterscreen`. (It replaces the arena with the dungeon, so it runs alone.)

const ROOMS := [1, 2, 4, 11]   # a narrow room off the landing, the big pit, a champion room, the boss court
const FIGHT_SECONDS := 10
const SETTLE_FRAMES := 70      # the camera eases after the warrior (follow speed 8): about a second

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _test_map_cutter_screen() -> void:
	# --- the world: the Sunken Way, as Main builds it for `-- --mapmode` ----------------------------------------------------------------
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	game.arena.queue_free()
	await get_tree().process_frame
	var cutter: Player = game.companion
	cutter.testing_disabled = false
	game.arena = MapModeDungeon.make_arena()
	game.add_child(game.arena)
	game.arena.build(false)
	game.location = MapModeDungeon.new()
	game.add_child(game.location)
	game.location.build(game.arena)
	hud.arena = game.arena
	rig.zoom_max = TestDungeon.ZOOM_MAX   # the dungeon's own view, as Main sets it up
	rig.set_zoom_now(TestDungeon.ZOOM_START)
	get_window().size = Vector2i(1920, 1080)   # 16:9 at 1080p, whatever the harness opened (headless gives a square)
	await _frames(2)
	await game.location.wait_for_navigation()
	game.director.start_location(game.location)
	var start: Vector3 = game.location.start_position()
	player.global_position = start
	cutter.global_position = Nav.snap(cutter, start + Vector3(2.0, 0.0, 0.0))
	player.invulnerable_time = 1.0e9
	cutter.invulnerable_time = 1.0e9
	var shake_was: float = GameSettings.screen_shake
	GameSettings.screen_shake = 0.0   # the camera's hit shake moves everything by tens of pixels; this checks the geometry
	var m := MapMode.new()
	m.setup(player, cutter, hud)
	game.add_child(m)
	await _frames(20)
	var camera: Camera3D = rig.camera
	camera.make_current()
	var size_px: Vector2 = get_viewport().get_visible_rect().size

	# --- the safe area ------------------------------------------------------------------------------------------------------------------
	var rect: Rect2 = MapModeScreen.safe_rect(size_px, hud)
	print("[mmcutterscreen] viewport %s safe area %s" % [size_px, rect])
	expect("the safe area is clear of the party portraits (left %.0f >= %.0f)" % [rect.position.x, MapModeScreen.PORTRAIT_STRIP], rect.position.x >= MapModeScreen.PORTRAIT_STRIP)
	expect("the safe area is clear of the target banner (top %.0f)" % rect.position.y, rect.position.y >= 72.0)
	expect("the safe area is clear of the hotbar (bottom %.0f, hotbar top %.0f)" % [rect.end.y, hud.hotbar_rect(size_px).position.y], rect.end.y <= hud.hotbar_rect(size_px).position.y)
	var minimap: Rect2 = Hud.minimap_rect(size_px, hud.use_ds2_ui)
	var blocked: Array[Rect2] = MapModeScreen.blocked_rects(size_px, hud)
	expect("the minimap is kept out (a blocked rectangle covers it)", blocked.size() >= 1 and blocked[0].encloses(minimap))
	expect("the safe area is inside the screen and holds its centre", Rect2(Vector2.ZERO, size_px).encloses(rect) and rect.has_point(size_px * 0.5))
	# --- unit asserts for the clamp, in the real camera ---------------------------------------------------------------------------------
	await _frames(SETTLE_FRAMES)
	var here: Vector3 = player.global_position
	expect("a point on the warrior is inside", MapModeScreen.inside_now(player, here))
	expect("a point far to the side projects outside", not MapModeScreen.inside_now(player, here + Vector3(-60.0, 0.0, 0.0)))
	expect("a point behind the camera is outside", not MapModeScreen.inside_now(player, here + Vector3(0.0, 0.0, 80.0)))
	expect("the clamp leaves an on-screen preferred spot alone", MapModeScreen.clamp_spot(cutter, here, here).is_equal_approx(here))
	# A navmesh spot that is off screen: the farthest navmesh point of a ring round the warrior that projects outside.
	var off: Vector3 = Vector3.INF
	for k in 24:
		var raw: Vector3 = here + Vector3.RIGHT.rotated(Vector3.UP, TAU * k / 24.0) * 22.0
		var spot: Vector3 = Nav.snap(player, raw)
		if not MapModeScreen.inside_now(player, spot) and Vector2(spot.x - here.x, spot.z - here.z).length() > MapModeScreen.MIN_GAP + 3.0:
			off = spot
			break
	if off.is_finite():
		var clamped: Vector3 = MapModeScreen.clamp_spot(cutter, off, here)
		print("[mmcutterscreen] clamp: %s (off screen) -> %s inside=%s" % [off, clamped, MapModeScreen.inside_now(player, clamped)])
		expect("the clamp moves an off-screen spot to one inside, on the navmesh", MapModeScreen.inside_now(player, clamped) and clamped.distance_to(Nav.snap(player, clamped)) < 0.3)
		expect("and that spot is nearer the warrior than the off-screen one", clamped.distance_to(here) < off.distance_to(here))
		cutter.global_position = off
		var goal: Vector3 = MapModeScreen.guard_goal(cutter, here)
		expect("the guard names an on-screen goal for a Cutter standing off screen", goal.is_finite() and MapModeScreen.inside_now(player, goal))
		cutter.global_position = Nav.snap(cutter, here + Vector3(2.0, 0.0, 0.0))
		expect("the guard is quiet for a Cutter on screen", not MapModeScreen.guard_goal(cutter, here).is_finite())
	else:
		print("[mmcutterscreen] (no off-screen navmesh spot round the start; the clamp unit checks were skipped there)")
	MapModeScreen.enabled = false
	expect("with the clamp off nothing moves", MapModeScreen.spot_visible(cutter, Vector3(1000.0, 0.0, 1000.0)) and not MapModeScreen.guard_goal(cutter, here).is_finite())
	MapModeScreen.enabled = true

	# --- the rooms ----------------------------------------------------------------------------------------------------------------------
	var graph: MapGraph = m.graph
	expect("map mode found the dungeon's graph", graph != null)
	if graph == null:
		return
	for room in ROOMS:
		await _room(m, graph, cutter, room)
	m.queue_free()
	await _frames(2)
	GameSettings.screen_shake = shake_was
	cutter.testing_disabled = true
	expect("map mode is off again afterwards", not MapMode.active)

func _room(m: MapMode, graph: MapGraph, cutter: Player, room: int) -> void:
	var route: Array = _path(graph, 0, room)
	var label: String = "%s (node %d)" % [graph.row(room).get("name", "?"), room]
	# Open the way and stand the party at the node before the room (the click path itself is MapMode's).
	for id in route:
		if int(id) != room:
			graph.mark_cleared(int(id))
	var before_id: int = int(route[route.size() - 2]) if route.size() >= 2 else 0
	var before: Vector2 = graph.pos_of(before_id)
	player.global_position = Nav.snap(player, Vector3(before.x, 0.0, before.y))
	cutter.global_position = Nav.snap(cutter, player.global_position + Vector3(1.5, 0.0, 0.0))
	player.velocity = Vector3.ZERO
	m.current_node = before_id
	m.state = MapMode.State.MAP
	await _frames(SETTLE_FRAMES)
	m.select_marker(room)
	var n: int = 0
	while m.state != MapMode.State.FIGHT and n < 400:
		await get_tree().physics_frame
		n += 1
	expect("%s: the dash ended in a fight (state %d, clickable %s)" % [label, m.state, graph.is_clickable(room)], m.state == MapMode.State.FIGHT)
	if m.state != MapMode.State.FIGHT:
		return
	for e in m.fight_enemies():
		e.max_health = 100000.0   # the fight lasts as long as the sampling does
		e.health = e.max_health
	var camera: Camera3D = get_viewport().get_camera_3d()
	var rect: Rect2 = MapModeScreen.safe_rect(get_viewport().get_visible_rect().size, hud)
	var landed: bool = MapModeScreen.inside_now(cutter, cutter.global_position, MapModeScreen.camera_shift(cutter, player.global_position))   # the landing spot, judged as the camera will frame it
	expect("%s: the Cutter lands inside the safe area (as the camera will frame the warrior)" % label, landed)
	await _frames(SETTLE_FRAMES)
	var worst: String = ""
	var bad: int = 0
	var samples: int = 0
	var first_ok: bool = false
	var lowest_gap: float = INF
	for second in FIGHT_SECONDS + 1:
		var feet: Vector2 = camera.unproject_position(cutter.global_position)
		var head: Vector2 = camera.unproject_position(cutter.global_position + Vector3.UP * MapModeScreen.BODY_HEIGHT)
		var ok: bool = MapModeScreen.inside_now(cutter, cutter.global_position)
		samples += 1
		if second == 0:
			first_ok = ok
		lowest_gap = minf(lowest_gap, player.flat_distance_to(cutter))
		if not ok:
			bad += 1
			worst = "t=%ds feet %s head %s" % [second, feet, head]
		if second == 0 or not ok:
			print("[mmcutterscreen] %s t=%d s: Cutter feet %s head %s, %.1f m behind the warrior (warrior feet %s, rig %s vs warrior %s), %s" % [label, second, feet, head, player.flat_distance_to(cutter), camera.unproject_position(player.global_position), rig.global_position, player.global_position, "inside" if ok else "OUTSIDE"])
		await _frames(60)
	print("[mmcutterscreen] %s: %d samples, %d outside, nearest %.1f m, guard pulled %d times" % [label, samples, bad, lowest_gap, m.guard_pulls])
	expect("%s: the Cutter was inside the safe area at arrival (the first sample)" % label, first_ok)
	expect("%s: and at every one-second sample of the fight (%d of %d outside; last %s)" % [label, bad, samples, worst], bad == 0)
	# End the fight.
	for e in m.fight_enemies():
		e.max_health = 10.0
		e.credit_hero()
		e._apply_damage(1000.0)
	var wait: int = 0
	while m.state != MapMode.State.MAP and wait < 900:
		await get_tree().physics_frame
		wait += 1
	if m.overlay != null and m.overlay.is_open():
		m.overlay.close()

## The shortest chain of node ids from `from_id` to `to_id` over the graph's links (breadth first), start and end included.
func _path(graph: MapGraph, from_id: int, to_id: int) -> Array:
	var came: Dictionary = {from_id: -1}
	var queue: Array = [from_id]
	while not queue.is_empty():
		var id: int = int(queue.pop_front())
		if id == to_id:
			break
		for n in graph.neighbours(id):
			if not came.has(int(n)):
				came[int(n)] = id
				queue.append(int(n))
	var out: Array = []
	var at: int = to_id
	while came.has(at) and at != -1:
		out.push_front(at)
		at = int(came[at])
	return out
