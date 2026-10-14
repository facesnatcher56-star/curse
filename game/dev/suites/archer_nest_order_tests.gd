extends DevSuite
## The companion archer's nest order on the real Crypt Road, through the input path: the test points the hero's mouse at a screen
## point (Player.test_mouse), the hero's own cursor_world and hover pick project it through the road camera, and the real
## companion-attack action is pressed. The order is then followed until the nest breaks.
## Cases: an unobstructed nest; a nest with a monster standing in its target area (the nest wins), with a monster outside it
## (ordinary enemy targeting) fighting while the order is held; and a distant nest the archer must walk to a firing spot for.
##
## The hero is made invulnerable for the whole test. He only points: the road's monsters killed him in some runs (a dead hero is
## not controlled, so the hotkey did nothing), which made this suite fail on whichever press came next.

## Physics frames on the nest (not counting frames fighting monsters) allowed for an ordered nest (140 hp) to break, walking included.
## The bow needs about 22-29 shots at about 100-115 frames each; the measured runs took 2100-3000 frames on the nest.
const ORDER_FRAME_BOUND := 3600
const PICK_MARGIN := 0.35   # the margin Player.order_companions_to_prop passes to Destructible.near

## The road's own camera (TownScene.rig): the one Player.cursor_world projects the mouse through while the town is up.
var cam: Camera3D
var lowest_archer_health: float = INF

## With --nestshots=<dir> (a windowed run), the rendered frame is saved there at the key moments, for a person to look at.
func _shot_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nestshots="):
			return arg.trim_prefix("--nestshots=")
	return ""

func _shot(label: String) -> void:
	if _shot_dir() == "":
		return
	await RenderingServer.frame_post_draw
	var path: String = _shot_dir().path_join(label + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("NEST SHOT: ", path)

## A capture run only: lets the scene play on so the shooting itself is on screen when the frame is taken.
func _shot_after(frames: int, label: String) -> void:
	if _shot_dir() == "":
		return
	for i in frames:
		await get_tree().physics_frame
	await _shot(label)

## The screen point where a world point is drawn.
func _screen_of(point: Vector3) -> Vector2:
	return cam.unproject_position(point)

## A walkable point `radius` from `centre` with a clear sight line to it (the way a firing position is judged).
func _clear_point(hero: Node3D, centre: Vector3, radius: float, ignore: Object) -> Vector3:
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0, 2.5, -2.5, 3.0, -3.0]:
		var candidate: Vector3 = Nav.snap(hero, centre + Vector3(sin(angle), 0.0, cos(angle)) * radius)
		var reach: float = Vector2(candidate.x - centre.x, candidate.z - centre.z).length()
		if reach >= radius - 1.5 and Nav.sight_clear(hero, candidate, centre + Vector3(0, 0.8, 0), ignore):
			return candidate
	return Vector3.INF

## The mouse on `screen` and the companion-attack hotkey pressed: Player's own physics frame projects the mouse, picks what is under
## it and acts on the press. Returns what the hero saw under the mouse on the press frame.
func _press_companion_attack(hero: Player, screen: Vector2) -> Dictionary:
	expect("precondition: the hero is alive and controlled before the press", not hero.dead and hero.is_controlled())
	hero.test_mouse = screen
	await get_tree().physics_frame
	Input.action_press("companion_attack")
	await get_tree().physics_frame
	var seen := {"hover": hero.hover_target, "ground": hero.cursor_world(),
		"prop": Destructible.near(get_tree(), hero.cursor_world(), PICK_MARGIN, Destructible.HERO)}
	Input.action_release("companion_attack")
	await get_tree().physics_frame
	hero.test_mouse = Vector2(-1.0, -1.0)
	return seen

## Lets the scene run until the nest breaks (or the frame bound), counting the archer's shots, frames fighting, and frames the order
## was not held.
func _run_order(archer: ArcherCompanion, nest: Destructible, bound: int) -> Dictionary:
	var shots0: int = archer.bow.shots
	var retreat0: float = archer.bow.retreat_seconds
	var frames := 0
	var enemy_frames := 0
	var unordered_frames := 0
	var hp0: float = nest.hp
	var hits := 0
	var last_hp: float = nest.hp
	# Frames on the nest (no enemy target), by what the archer is doing: drawing or recovering, walking, or standing.
	var on_nest := {"busy": 0, "moving": 0, "idle": 0}
	# The bound counts the frames spent on the nest: time fighting the road's own monsters is the order held, not lost (capped at 2x).
	while frames - enemy_frames < bound and frames < bound * 2 and not nest.broken:
		await get_tree().physics_frame
		frames += 1
		lowest_archer_health = minf(lowest_archer_health, archer.health)
		if nest.hp < last_hp:
			hits += 1
			last_hp = nest.hp
		if is_instance_valid(archer.attack_target):
			enemy_frames += 1
		elif archer.skills.busy:
			on_nest["busy"] += 1
		elif archer.movement.has_goal:
			on_nest["moving"] += 1
		else:
			on_nest["idle"] += 1
		if archer.attack_prop != nest: unordered_frames += 1
	return {"broke": nest.broken, "frames": frames, "shots": archer.bow.shots - shots0, "nest_hits": hits, "enemy_frames": enemy_frames,
		"unordered_frames": unordered_frames, "nest_hp_lost": snappedf(hp0 - nest.hp, 0.1), "on_nest": on_nest,
		"retreat_s": snappedf(archer.bow.retreat_seconds - retreat0, 0.1)}

## Puts the hero `distance` from a nest with the archer beside him, both topped up, and lets the camera settle on the hero.
func _stage(hero: Player, archer: ArcherCompanion, nest: Destructible, distance: float) -> void:
	hero.global_position = _clear_point(hero, nest.global_position, distance, nest)
	hero.reset_physics_interpolation()
	archer.global_position = _clear_point(hero, hero.global_position, 3.0, null)
	archer.reset_physics_interpolation()
	archer.health = archer.max_health
	for i in 90:   # the rig eases after the hero
		await get_tree().physics_frame

func _test_archer_nest_order() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.road_conditions_in_tests = false
	seed(4243)
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
	hero.invulnerable_time = 1.0e9   # see the note at the top: the hero only points
	archer.testing_disabled = false   # the party AI runs: this is the order's own path, not a direct call into the bow
	cam = town.rig.camera
	cam.make_current()
	expect("road: the real Crypt Road with its monsters is loaded", crypt != null and crypt.nests.size() == 3
		and get_tree().get_nodes_in_group("enemies").size() >= 36)

	# Case 1: an unobstructed nest. Every height of the drawn nest projects to a ground point that picks it.
	var nest: Destructible = crypt.nests[0]
	await _stage(hero, archer, nest, 9.0)
	var misses := 0
	for fraction in [0.05, 0.25, 0.5, 0.75, 0.95]:
		hero.test_mouse = _screen_of(nest.global_position + Vector3(0, nest.height * fraction, 0))
		if Destructible.near(get_tree(), hero.cursor_world(), PICK_MARGIN, Destructible.HERO) != nest:
			misses += 1
	hero.test_mouse = Vector2(-1.0, -1.0)
	print("PICK nest0: drawn heights sampled=5 misses=", misses, " footprint radius=", snappedf(nest.radius, 0.01))
	expect("cursor: the mouse anywhere on the drawn nest projects to a ground point that picks it", misses == 0)
	var nest_mid: Vector2 = _screen_of(nest.global_position + Vector3(0, nest.height * 0.5, 0))
	await _shot("1_unobstructed_before_press")
	var seen: Dictionary = await _press_companion_attack(hero, nest_mid)
	await _shot("2_unobstructed_order_accepted")
	await _shot_after(400, "3_unobstructed_shooting")
	expect("unobstructed: the hotkey on the drawn nest orders Cutter onto it", archer.attack_prop == nest and seen["prop"] == nest)
	var told: Array = town.hud.log_lines.filter(func(line: Dictionary) -> bool: return String(line["text"]).contains("ordered onto the nest"))
	print("FEEDBACK accepted: road_log_lines=", told.size(), " text=", told[0]["text"] if not told.is_empty() else "")
	expect("feedback: the accepted order is told in the road's message log", not told.is_empty())
	var result: Dictionary = await _run_order(archer, nest, ORDER_FRAME_BOUND)
	print("ORDER nest0 (unobstructed): ", result)
	expect("unobstructed: Cutter breaks the nest (within %d frames on the nest)" % ORDER_FRAME_BOUND, result["broke"])
	expect("unobstructed: the order is held until the nest breaks", result["unordered_frames"] == 0)
	await _press_companion_attack(hero, nest_mid)
	for i in 120:
		await get_tree().physics_frame
	await _shot("4_unobstructed_broken")
	expect("unobstructed: a broken nest is not ordered again", not is_instance_valid(archer.attack_prop) or archer.attack_prop.broken)

	# Case 2: a monster stands in the second nest's target area, drawn over it. The hotkey on it orders the nest, not the monster.
	var nest1: Destructible = crypt.nests[1]
	await _stage(hero, archer, nest1, 9.0)
	var toward_hero: Vector3 = hero.global_position - nest1.global_position
	toward_hero.y = 0.0
	var overlap: Enemy = town.director.spawn_enemy(nest1.global_position + toward_hero.normalized() * nest1.radius * 0.5, "zombie", 1.0)
	overlap.set_physics_process(false)   # it stands where it was put, asleep: the AI never picks it for itself
	overlap.aggro_range = 0.0
	await get_tree().physics_frame
	var overlap_screen: Vector2 = _screen_of(overlap.global_position + Vector3(0, overlap.body_height * 0.6, 0))
	await _shot("5_overlap_monster_on_nest")
	seen = await _press_companion_attack(hero, overlap_screen)
	await _shot("6_overlap_after_press")
	print("OVERLAP press: hover=", seen["hover"] == overlap, " prop=", seen["prop"] == nest1, " attack_prop=", archer.attack_prop == nest1,
		" attack_target_is_overlap=", archer.attack_target == overlap)
	expect("overlap: precondition - the mouse is on a monster and on the nest's target area at once", seen["hover"] == overlap and seen["prop"] == nest1)
	expect("overlap: the nest wins - Cutter is ordered onto the nest, not the monster", archer.attack_prop == nest1 and archer.attack_target != overlap)
	overlap.queue_free()

	# Outside the nest's area, enemy targeting is ordinary: the hotkey on a monster sends Cutter at it, and the nest order is held.
	var outside: Enemy = town.director.spawn_enemy(_clear_point(hero, hero.global_position, 5.0, null), "zombie", 1.0)
	outside.max_health = 500.0
	outside.health = 500.0
	outside.set_physics_process(false)
	await get_tree().physics_frame
	seen = await _press_companion_attack(hero, _screen_of(outside.global_position + Vector3(0, outside.body_height * 0.6, 0)))
	expect("outside: the hotkey on a monster away from the nest sends Cutter at the monster", archer.attack_target == outside and seen["prop"] == null)
	expect("outside: the nest order is still held while he fights it", archer.attack_prop == nest1)
	outside.wake()
	var order_kept: bool = true
	for i in 240:
		await get_tree().physics_frame
		order_kept = order_kept and archer.attack_prop == nest1
	await _shot("7_fight_order_held")
	print("FIGHT phase: frames=240 order_kept=", order_kept, " archer_on_monster=", archer.attack_target == outside, " shots=", archer.bow.shots)
	expect("outside: the nest order is held through 240 frames of fighting", order_kept)
	if is_instance_valid(outside):
		outside.queue_free()
	var mid_result: Dictionary = await _run_order(archer, nest1, ORDER_FRAME_BOUND)
	print("ORDER nest1 (overlap, then a fight): ", mid_result)
	expect("overlap: Cutter breaks the second nest after the fight (within %d frames on the nest)" % ORDER_FRAME_BOUND, mid_result["broke"])
	expect("overlap: the order is held until the nest breaks", mid_result["unordered_frames"] == 0)

	# Case 3: a distant nest. The archer stands 17 m from it (beyond the 16 m engagement limit) and must walk to a firing spot.
	var nest2: Destructible = crypt.nests[2]
	await _stage(hero, archer, nest2, 14.0)
	var away: Vector3 = hero.global_position - nest2.global_position
	away.y = 0.0
	archer.global_position = Nav.snap(archer, hero.global_position + away.normalized() * 3.0)
	archer.reset_physics_interpolation()
	await get_tree().physics_frame
	var archer_start: Vector3 = archer.global_position
	var start_gap: float = archer.flat_distance_to(nest2)
	seen = await _press_companion_attack(hero, _screen_of(nest2.global_position + Vector3(0, nest2.height * 0.5, 0)))
	expect("distant: the order onto the far nest is taken", archer.attack_prop == nest2 and seen["prop"] == nest2)
	await _shot_after(300, "8_distant_repositioned")
	var far_result: Dictionary = await _run_order(archer, nest2, ORDER_FRAME_BOUND)
	print("ORDER nest2 (distant): ", far_result, " start_gap=", snappedf(start_gap, 0.1), " archer moved=",
		snappedf(archer.global_position.distance_to(archer_start), 0.1))
	expect("distant: Cutter walks to a firing spot and breaks the far nest (within %d frames on the nest)" % ORDER_FRAME_BOUND, far_result["broke"])
	expect("distant: the order is held until the nest breaks", far_result["unordered_frames"] == 0)
	print("NEST ORDER SUMMARY: hero_dead=", hero.dead, " archer_dead=", archer.dead, " lowest_archer_health=", snappedf(lowest_archer_health, 0.1),
		" of ", archer.max_health)
	town.queue_free()
	await get_tree().process_frame
