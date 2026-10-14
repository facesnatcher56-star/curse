extends DevSuite
## The companion archer's nest order on the real Crypt Road, through the input path: the mouse's screen point is projected to the
## ground the way Player.cursor_world does, the companion-attack hotkey is pressed, and the order is followed until the nest breaks.
## Scenes: a nest on the real road layout (with its real monster population), a nearby monster that appears during the order, and a
## distant nest that needs the archer to walk to a firing spot.

## Physics frames on the nest (not counting frames fighting monsters) allowed for an ordered nest (140 hp) to break, walking included.
## The bow needs about 22 shots, about 2300 frames; the run is seeded, so this leaves margin for the walk and close-range step-backs.
const ORDER_FRAME_BOUND := 3600
const PICK_MARGIN := 0.35   # the margin Player.order_companions_to_prop passes to Destructible.near

## The road's own camera (TownScene.rig): the one Player.cursor_world projects the mouse through while the town is up.
var cam: Camera3D

## Where the mouse ray meets the ground, exactly as Player.cursor_world computes it for a screen point.
func _ground_under(screen: Vector2) -> Vector3:
	var camera: Camera3D = cam
	var from: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return hit if hit != null else Vector3.INF

## The screen point where a point of the prop (at `height` metres above its base) is drawn.
func _screen_of(point: Vector3) -> Vector2:
	var camera: Camera3D = cam
	return camera.unproject_position(point)

## A walkable point `radius` from `centre` with a clear sight line to it (the way a firing position is judged).
func _clear_point(hero: Node3D, centre: Vector3, radius: float, ignore: Object) -> Vector3:
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0, 2.5, -2.5, 3.0, -3.0]:
		var candidate: Vector3 = Nav.snap(hero, centre + Vector3(sin(angle), 0.0, cos(angle)) * radius)
		var reach: float = Vector2(candidate.x - centre.x, candidate.z - centre.z).length()
		if reach >= radius - 1.5 and Nav.sight_clear(hero, candidate, centre + Vector3(0, 0.8, 0), ignore):
			return candidate
	return Vector3.INF

## Presses the companion-attack hotkey with the mouse on `ground`: the real action goes through Player._act and its cursor.
func _press_companion_attack(hero: Player, ground: Vector3) -> void:
	hero.cursor_override = ground
	Input.action_press("companion_attack")
	await get_tree().physics_frame
	Input.action_release("companion_attack")
	await get_tree().physics_frame
	hero.cursor_override = Vector3.INF

## Walks the scene on: waits until the nest breaks (or the frame bound), counting the archer's shots and the frames.
func _run_order(archer: ArcherCompanion, nest: Destructible, bound: int) -> Dictionary:
	var shots0: int = archer.bow.shots
	var holds0: int = archer.bow.holds
	var frames := 0
	var enemy_frames := 0
	var unordered_frames := 0
	var hp0: float = nest.hp
	# The bound counts the frames spent on the nest: time fighting the road's own monsters is the order held, not lost (capped at 2x).
	while frames - enemy_frames < bound and frames < bound * 2 and not nest.broken:
		await get_tree().physics_frame
		frames += 1
		if is_instance_valid(archer.attack_target): enemy_frames += 1
		if archer.attack_prop != nest: unordered_frames += 1
	return {"broke": nest.broken, "frames": frames, "shots": archer.bow.shots - shots0, "enemy_frames": enemy_frames,
		"unordered_frames": unordered_frames, "holds": archer.bow.holds - holds0, "nest_hp_lost": hp0 - nest.hp}

func _test_archer_nest_order() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.road_conditions_in_tests = false
	seed(4243)   # bow damage, recovery and the road's monsters draw on the global RNG: the same run every time
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena.queue_free()
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	var town := TownScene.new()
	game.add_child(town)
	var waited: int = 0
	while (town.director == null or get_tree().get_nodes_in_group("enemies").size() < 36) and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var crypt: CryptRoad = town.crypt
	var hero: Player = town.player
	var archer: ArcherCompanion = town.companion
	archer.testing_disabled = false   # the party AI runs: this is the order's own path, not a direct call into the bow
	cam = town.rig.camera
	cam.make_current()
	expect("road: the real Crypt Road with its monsters is loaded", crypt != null and crypt.nests.size() == 3
		and get_tree().get_nodes_in_group("enemies").size() >= 36)

	# Phase 1 (reproduction): which ground points pick the nest. The nest is drawn 1.9 m tall; the pick is a ground point with a 0.35 m margin.
	var nest: Destructible = crypt.nests[0]
	var spot: Vector3 = _clear_point(hero, nest.global_position, 9.0, nest)
	expect("road: a clear firing ground point exists 9 m from nest 1", spot != Vector3.INF)
	hero.global_position = spot
	hero.reset_physics_interpolation()
	archer.global_position = _clear_point(hero, hero.global_position, 3.0, null)
	archer.reset_physics_interpolation()
	# The rig eases after the hero: let the camera settle on him before any mouse point is projected.
	for i in 90:
		await get_tree().physics_frame
	var hits: Array[String] = []
	for fraction in [0.05, 0.25, 0.5, 0.75, 0.95]:
		var point: Vector3 = nest.global_position + Vector3(0, nest.height * fraction, 0)
		var ground: Vector3 = _ground_under(_screen_of(point))
		var picked: Destructible = Destructible.near(get_tree(), ground, PICK_MARGIN, Destructible.HERO)
		var ok: bool = picked == nest
		hits.append("%.2fh drawn at %s -> ground gap %.2f -> %s" % [fraction, str(_screen_of(point).round()), (ground - nest.global_position).length() - nest.radius, "PICK" if ok else "MISS"])
	for line in hits:
		print("PICK SAMPLE nest0: ", line)
	print("PICK nest0 footprint radius=", snappedf(nest.radius, 0.01), " height=", nest.height)

	# Phase 2 (the real hotkey): the mouse rests on the middle of the nest as drawn.
	var mid_ground: Vector3 = _ground_under(_screen_of(nest.global_position + Vector3(0, nest.height * 0.5, 0)))
	await _press_companion_attack(hero, mid_ground)
	expect("hotkey: the mouse on the drawn middle of nest 1 orders Cutter onto it", archer.attack_prop == nest)
	var told: Array = town.hud.log_lines.filter(func(line: Dictionary) -> bool: return String(line["text"]).contains("ordered onto the nest"))
	print("FEEDBACK accepted: road_log_lines=", told.size(), " text=", told[0]["text"] if not told.is_empty() else "")
	expect("feedback: the accepted order is told in the road's message log", not told.is_empty())
	var result: Dictionary = await _run_order(archer, nest, ORDER_FRAME_BOUND)
	print("ORDER nest0 (near, no monsters): ", result)
	expect("order: Cutter breaks the nest he was ordered onto (within %d frames on the nest)" % ORDER_FRAME_BOUND, result["broke"])
	await get_tree().process_frame
	# A second press on the broken nest picks nothing: no prop is ordered and the archer fires nothing more.
	await _press_companion_attack(hero, mid_ground)
	for i in 120:
		await get_tree().physics_frame
	expect("order: a broken nest is not ordered again (the press picks nothing)", not is_instance_valid(archer.attack_prop) or archer.attack_prop.broken)

	# Phase 3: a nearby monster appears while Cutter is ordered onto the second nest. The order must survive the fight.
	var nest1: Destructible = crypt.nests[1]
	hero.global_position = _clear_point(hero, nest1.global_position, 9.0, nest1)
	hero.reset_physics_interpolation()
	archer.global_position = _clear_point(hero, hero.global_position, 3.0, null)
	archer.reset_physics_interpolation()
	for i in 90:
		await get_tree().physics_frame
	await _press_companion_attack(hero, _ground_under(_screen_of(nest1.global_position + Vector3(0, nest1.height * 0.5, 0))))
	expect("monster: the order onto the second nest is taken", archer.attack_prop == nest1)
	var monster_spot: Vector3 = _clear_point(hero, hero.global_position, 5.0, null)
	var monster: Enemy = town.director.spawn_enemy(monster_spot, "zombie", 1.0)
	monster.max_health = 500.0
	monster.health = 500.0
	monster.wake()
	monster.set_physics_process(false)
	var order_kept: bool = true
	var monster_frames := 0
	while monster_frames < 240 and is_instance_valid(monster) and not monster.dead:
		await get_tree().physics_frame
		monster_frames += 1
		order_kept = order_kept and archer.attack_prop == nest1
	print("MONSTER phase: frames=", monster_frames, " order_kept=", order_kept, " archer target=", archer.attack_target,
		" attack_prop=", archer.attack_prop, " nest1 hp=", nest1.hp, " shots=", archer.bow.shots)
	expect("monster: the nest order is still held while a monster stands by the hero", order_kept)
	if is_instance_valid(monster):
		monster.queue_free()
	var mid_result: Dictionary = await _run_order(archer, nest1, ORDER_FRAME_BOUND)
	print("ORDER nest1 (monster interrupted): ", mid_result)
	var nest1_point: Vector3 = nest1.global_position + Vector3(0, nest1.height * 0.5, 0)
	print("NEST1 END: archer_to_nest=", snappedf(archer.flat_distance_to_point(nest1_point), 0.1), " hero_to_nest=",
		snappedf(hero.flat_distance_to(nest1), 0.1), " sight=", Nav.sight_clear(archer, archer.global_position, nest1_point, nest1),
		" busy=", archer.skills.busy, " has_goal=", archer.movement.has_goal, " has_spot=", archer.bow._has_spot)
	expect("monster: Cutter still breaks the ordered nest after the monster is gone (within %d frames on the nest)" % ORDER_FRAME_BOUND, mid_result["broke"])

	# Phase 4: a distant nest. The archer stands 17 m from the nest (beyond the 16 m engagement limit) and must walk to a firing spot.
	var nest2: Destructible = crypt.nests[2]
	hero.global_position = _clear_point(hero, nest2.global_position, 14.0, nest2)
	hero.reset_physics_interpolation()
	var away: Vector3 = (hero.global_position - nest2.global_position)
	away.y = 0.0
	away = away.normalized()
	archer.global_position = Nav.snap(archer, hero.global_position + away * 3.0)
	archer.reset_physics_interpolation()
	for i in 90:
		await get_tree().physics_frame
	var archer_start: Vector3 = archer.global_position
	print("DISTANT setup: archer to nest2 flat distance=", snappedf(archer.flat_distance_to(nest2), 0.1), " hero to nest2=",
		snappedf(hero.flat_distance_to(nest2), 0.1))
	await _press_companion_attack(hero, _ground_under(_screen_of(nest2.global_position + Vector3(0, nest2.height * 0.5, 0))))
	var far_ground: Vector3 = _ground_under(_screen_of(nest2.global_position + Vector3(0, nest2.height * 0.5, 0)))
	print("DISTANT press: hover_pick=", hero._hover_pick(far_ground), " archer attack_target=", archer.attack_target, " attack_prop==nest2=", archer.attack_prop == nest2,
		" pick=", Destructible.near(get_tree(), far_ground, PICK_MARGIN, Destructible.HERO) == nest2, " nest2 broken=", nest2.broken)
	expect("distant: the order onto the far nest is taken", archer.attack_prop == nest2)
	var far_result: Dictionary = await _run_order(archer, nest2, ORDER_FRAME_BOUND)
	print("ORDER nest2 (distant, walk needed): ", far_result, " archer moved=", snappedf(archer.global_position.distance_to(archer_start), 0.1))
	expect("distant: Cutter walks to a firing spot and breaks the far nest (within %d frames on the nest)" % ORDER_FRAME_BOUND, far_result["broke"])
	town.queue_free()
	await get_tree().process_frame
