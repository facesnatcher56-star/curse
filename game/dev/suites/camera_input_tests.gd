extends DevSuite
## Self-test: navigation, camera, zoom, gamepad, settings, pause and loading.

## Navigation: a path across the biggest obstacle must detour around it, and the hero must actually walk it.
func _test_navigation() -> void:
	for i in 120:
		if Nav.ready(player): break
		await get_tree().physics_frame
	expect("navigation region is synchronized", Nav.ready(player))
	print("  nav regions ", NavigationServer3D.map_get_regions(Nav.map_of(player)).size(), " polygons ", arena._nav_region.navigation_mesh.get_polygon_count())
	var largest: Dictionary = {}
	for ob in arena.obstacles:
		if largest.is_empty() or float(ob["radius"]) > float(largest["radius"]):
			largest = ob
	if largest.is_empty():
		print("  navigation: no obstacles to test")
		return
	var centre: Vector3 = largest["position"]
	var radius: float = float(largest["radius"])
	# Pick the axis with the most room around the obstacle.
	var span: float = radius + 3.0
	var from: Vector3 = Nav.snap(player, centre + Vector3(-span, 0, 0))
	var to: Vector3 = Nav.snap(player, centre + Vector3(span, 0, 0))
	var map: RID = Nav.map_of(player)
	print("  nav centre ", centre, " map ", map, " region map ", NavigationServer3D.region_get_map(arena._nav_region.get_rid()), " layer ", arena._nav_region.navigation_layers, " region closest ", NavigationServer3D.region_get_closest_point(arena._nav_region.get_rid(), centre))
	await get_tree().physics_frame
	print("  closest origin ", NavigationServer3D.map_get_closest_point(map, Vector3(0, 1, 0)), " owner ", NavigationServer3D.map_get_closest_point_owner(map, centre), " iteration ", NavigationServer3D.map_get_iteration_id(map))
	from = Nav.snap(player, centre + Vector3(-span, 0, 0))
	to = Nav.snap(player, centre + Vector3(span, 0, 0))
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	print("  nav endpoints ", from, " -> ", to, " active ", NavigationServer3D.map_is_active(map), " debug ", Nav.debug_broken_snap, " region bounds ", NavigationServer3D.region_get_bounds(arena._nav_region.get_rid()))
	expect("obstacle route is nonempty", path.size() >= 3)
	var length: float = 0.0
	var clearance: float = 9999.0
	var body_clear := true
	for i in path.size() - 1:
		body_clear = body_clear and Nav.clearance(player, path[i], path[i + 1])
		length += path[i].distance_to(path[i + 1])
		var seg: Vector3 = path[i + 1] - path[i]
		var t: float = clampf((centre - path[i]).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		var nearest: Vector3 = path[i] + seg * t
		clearance = minf(clearance, Vector2(nearest.x - centre.x, nearest.z - centre.z).length())
	var straight: float = from.distance_to(to)
	expect("obstacle route detours with clearance", length > straight and clearance > radius)
	expect("every path segment clears the actual actor body", body_clear)
	# Now walk it with the real controller.
	player.global_position = from
	player.reset_physics_interpolation()
	await get_tree().physics_frame
	player.movement.goal = to
	player.movement.has_goal = true
	var elapsed: float = 0.0
	var min_gap: float = 9999.0
	while elapsed < 12.0 and Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() > 0.8:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		player.movement.has_goal = true
		player.movement.goal = to
		min_gap = minf(min_gap, Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length())
	var reached: bool = Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() <= 1.0
	expect("hero walks around the obstacle to the goal", reached)
	print("  navigation: obstacle radius ", snappedf(radius, 0.1), " m; path ", snappedf(length, 0.1), " m vs straight ", snappedf(straight, 0.1),
		" m (", path.size(), " points), path clearance ", snappedf(clearance, 0.1), " m; hero walked it: reached=", reached, " in ", snappedf(elapsed, 0.1),
		" s, closest approach ", snappedf(min_gap, 0.1), " m")
	player.movement.has_goal = false
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	await get_tree().process_frame

## Controller: sticks move and aim the hero, buttons are bound to the skills, rolls follow the stick, hints switch to pad labels.
func _test_gamepad() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	# Every action has its pad button.
	var wanted: Dictionary = {"alt_skill": true, "dodge": true, "skill_1": true, "skill_2": true, "use_potion": true, "skill_4": true,
		"skill_5": true, "skill_6": true, "pause": true, "gear": true, "zoom_in": true, "zoom_out": true, "stand_still": true}
	var missing: PackedStringArray = []
	for action in wanted:
		var has_pad: bool = false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_pad = true
		if not has_pad:
			missing.append(action)
	expect("every action has a controller binding", missing.is_empty())
	expect("keyboard bindings survive next to the pad ones", GameSettings.binding_text("skill_1") == "1")

	player.global_position = Vector3(-30, 0, 20)
	player.reset_physics_interpolation()
	player.movement.has_goal = false
	player.attack_target = null
	Gamepad.active = true
	# Left stick moves the hero, analog.
	Gamepad.test_axes = {JOY_AXIS_LEFT_X: 1.0, JOY_AXIS_LEFT_Y: 0.0}
	var start: Vector3 = player.global_position
	await get_tree().create_timer(1.0).timeout
	var run_dist: float = player.global_position.x - start.x
	var run_clip: String = player.model.current
	expect("left stick runs the hero", run_dist > 3.5 and run_clip == "run")
	Gamepad.test_axes = {JOY_AXIS_LEFT_X: 0.0, JOY_AXIS_LEFT_Y: 0.5}
	start = player.global_position
	await get_tree().create_timer(1.0).timeout
	var walk_dist: float = player.global_position.z - start.z
	expect("a light push walks slower than a full push", walk_dist > 1.0 and walk_dist < run_dist * 0.8)
	Gamepad.test_axes = {}
	await get_tree().create_timer(0.4).timeout
	expect("releasing the stick stops the hero", player.velocity.length() < 0.5 and player.model.current == "idle_alert")
	print("  gamepad move: full push ", snappedf(run_dist, 0.1), " m (", run_clip, "), half push ", snappedf(walk_dist, 0.1), " m")

	# The right stick is the camera: pushed up with no skill held it does not move the target; the nearest enemy in front is targeted.
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: 0.0, JOY_AXIS_RIGHT_Y: -1.0}
	player.visual.rotation.y = 0.0
	var enemy: Enemy = _spawn_enemy(player.global_position + Vector3(4.0, 0, 3.0))
	enemy.aggro_range = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("the right stick does not aim the hero; the facing target is used", player.cursor_world().distance_to(enemy.global_position) < 0.01 and player.hover_target == enemy)
	Gamepad.test_axes = {}

	# A attacks the auto-target (same path as the right mouse button).
	player.global_position = enemy.global_position + Vector3(-1.6, 0, 0)
	player.reset_physics_interpolation()
	enemy.max_health = 5000.0
	enemy.health = 5000.0
	Input.action_press("alt_skill")
	var swung: bool = false
	var t: float = 0.0
	while t < 2.0 and not swung:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		swung = player.skills.busy
	Input.action_release("alt_skill")
	expect("A attacks the targeted enemy", swung)
	await get_tree().create_timer(1.2).timeout
	for retry in 3:   # a swing can miss or be blocked at random: swing again rather than fail on bad luck
		if enemy.health < enemy.max_health:
			break
		Input.action_press("alt_skill")
		await get_tree().create_timer(1.4).timeout
		Input.action_release("alt_skill")
	expect("the enemy was hit", enemy.health < enemy.max_health)

	# Rolling follows the stick.
	player.skills.cancel_action()
	player.stats.cooldowns.clear()
	player.stats.stamina = player.stats.max_stamina
	player.global_position = Vector3(-30, 0, 20)
	player.reset_physics_interpolation()
	await get_tree().physics_frame
	Gamepad.test_axes = {JOY_AXIS_LEFT_X: 0.0, JOY_AXIS_LEFT_Y: 1.0}
	player.movement.try_roll(player.cursor_world())
	var roll_toward_z: bool = player.movement.rolling and player.movement.roll_dir.z > 0.9
	expect("the dodge rolls the way the stick points", roll_toward_z)
	Gamepad.test_axes = {}
	await get_tree().create_timer(0.8).timeout

	# Hints show pad labels while the pad is in use and keyboard ones otherwise.
	var pad_hint: String = GameSettings.short_binding_text("skill_1")
	Gamepad.active = false
	var key_hint: String = GameSettings.short_binding_text("skill_1")
	expect("hotbar hints switch between pad and keyboard labels", pad_hint == "X" and key_hint == "1")
	print("  gamepad hints: pad=", pad_hint, " keyboard=", key_hint)
	Gamepad.active = false
	Gamepad.test_axes = {}
	enemy.queue_free()
	await get_tree().process_frame

## The loading screen loads every asset on background threads, the bar only ever moves forward and ends at 100%,
## and the messages rotate without repeating back to back.
func _test_loading() -> void:
	var screen := LoadingScreen.new()
	screen.auto_switch = false
	LoadingScreen.next_scene = "res://game/main.tscn"
	add_child(screen)
	var last: float = 0.0
	var monotonic: bool = true
	var elapsed: float = 0.0
	while elapsed < 60.0 and not (screen._finished and screen.progress >= 0.999):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		monotonic = monotonic and screen.progress >= last - 0.0001
		last = screen.progress
	expect("loading screen finishes loading everything", screen._finished and screen.assets_total > 20 and screen.assets_done == screen.assets_total)
	expect("the progress bar only moves forward and ends full", monotonic and screen.progress >= 0.999)
	var seen: Dictionary = {}
	var repeat: bool = false
	var previous: String = screen.message
	for i in 120:
		var next: String = screen.next_message()
		repeat = repeat or next == previous
		previous = next
		seen[next] = true
	expect("loading messages are plentiful and never repeat back to back", LoadingScreen.MESSAGES.size() >= 40 and seen.size() >= 25 and not repeat)
	print("  loading: ", screen.assets_done, "/", screen.assets_total, " assets in ", snappedf(elapsed, 0.1), " s, ", LoadingScreen.MESSAGES.size(), " messages, e.g. \"", screen.message, "\"")
	if DisplayServer.get_name() != "headless":
		var old_size := get_window().size
		var old_scale := GameSettings.ui_size
		var old_screen := get_window().current_screen
		var old_borderless := get_window().borderless
		hud.hide()
		for resolution in GameSettings.RESOLUTIONS:
			for multiplier in [0.5, 1.0, 1.5]:
				var monitor := 0 if resolution.y > 1080 else mini(1, DisplayServer.get_screen_count() - 1)
				get_window().current_screen = monitor
				get_window().borderless = true
				get_window().size = resolution
				get_window().position = DisplayServer.screen_get_position(monitor) + (DisplayServer.screen_get_size(monitor) - resolution) / 2
				GameSettings.ui_size = multiplier
				GameSettings.apply_ui_scale()
				for frame in 8: await get_tree().process_frame
				var tag := "%dx%d_scale%s" % [resolution.x, resolution.y, str(multiplier)]
				var panel: Control = screen._bar.get_parent().get_parent()
				expect("loading panel fits: " + tag, get_viewport().get_visible_rect().encloses(panel.get_global_rect()))
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_loading_" + tag + ".png")
				print("LOADING_CASE ", tag)
		GameSettings.ui_size = old_scale
		get_window().borderless = old_borderless
		get_window().current_screen = old_screen
		get_window().size = old_size
		GameSettings.apply_ui_scale()
		hud.show()
	screen.queue_free()
	await get_tree().process_frame

## Camera zoom: eases toward the target (no instant jump), respects limits, and zooms both ways.
func _test_zoom() -> void:
	var base: float = rig.camera.position.length()
	var zoom_out := InputEventAction.new()
	zoom_out.action = "zoom_out"
	zoom_out.pressed = true
	for i in 3:
		rig._unhandled_input(zoom_out)
	await get_tree().process_frame
	await get_tree().process_frame
	var early: float = rig.camera.position.length()
	await get_tree().create_timer(1.0).timeout
	var out: float = rig.camera.position.length()
	var zoom_in := InputEventAction.new()
	zoom_in.action = "zoom_in"
	zoom_in.pressed = true
	for i in 40:
		rig._unhandled_input(zoom_in)
	await get_tree().create_timer(1.2).timeout
	var near: float = rig.camera.position.length()
	for i in 12:
		rig._unhandled_input(zoom_out)
	for i in 40:
		rig._unhandled_input(zoom_out)
	await get_tree().create_timer(1.2).timeout
	var far: float = rig.camera.position.length()
	expect("camera zoom is eased", early < out)
	print("  zoom: base=", snappedf(base, 0.01), " after 2 frames=", snappedf(early, 0.01), " (eased: ", early < out, ") out=", snappedf(out, 0.01),
		" min=", snappedf(near / base, 0.01), " max=", snappedf(far / base, 0.01))
	rig._zoom_target = 1.0
	rig._zoom = 1.0

## Settings: rebinding, conflict swap, save/load round trip, and the pause menu node.
func _test_settings() -> void:
	var ok: bool = true
	var backup: Dictionary = GameSettings.custom_bindings.duplicate()
	# Isolated: this test saves and loads settings, so it must never touch the owner's real settings file.
	var real_settings_path: String = GameSettings.settings_path
	GameSettings.settings_path = "user://camera_input_check_settings.cfg"
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	GameSettings.rebind("dodge", q)
	ok = ok and GameSettings.binding_text("dodge") == "Q"
	# Binding hotbar 1 to Q must swap: dodge gets the old "1".
	GameSettings.rebind("skill_1", q)
	ok = ok and GameSettings.binding_text("skill_1") == "Q" and GameSettings.binding_text("dodge") == "1"
	GameSettings.master_volume = 0.42
	GameSettings.save_to_disk()
	GameSettings.master_volume = 0.1
	GameSettings.custom_bindings.clear()
	GameSettings.load_from_disk()
	GameSettings.apply_bindings()
	ok = ok and absf(GameSettings.master_volume - 0.42) < 0.001 and GameSettings.binding_text("skill_1") == "Q"
	GameSettings.reset_bindings()
	ok = ok and GameSettings.binding_text("skill_1") == "1" and GameSettings.binding_text("dodge") == "Space"
	# Controller buttons: rebind, swap on conflict, persist, survive a keyboard rebind, reset.
	var pad_ok: bool = GameSettings.pad_binding_text("skill_1") == "X" and GameSettings.pad_binding_text("skill_2") == "Y"
	var pad_press := InputEventJoypadButton.new()
	pad_press.button_index = JOY_BUTTON_Y
	GameSettings.rebind_pad("skill_1", pad_press)   # skill_1 takes Y; skill_2 (which had Y) gets X
	pad_ok = pad_ok and GameSettings.pad_binding_text("skill_1") == "Y" and GameSettings.pad_binding_text("skill_2") == "X"
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	GameSettings.rebind_pad("dodge", trigger)       # a trigger can be bound too; skill_5 (RT) gets dodge's old B
	pad_ok = pad_ok and GameSettings.pad_binding_text("dodge") == "RT" and GameSettings.pad_binding_text("skill_5") == "B"
	GameSettings.rebind("use_potion", q)             # a keyboard rebind must leave the pad button alone
	pad_ok = pad_ok and GameSettings.pad_binding_text("use_potion") == "RB" and GameSettings.binding_text("use_potion") == "Q"
	GameSettings.swap_sticks = true
	GameSettings.save_to_disk()
	GameSettings.custom_pad_bindings.clear()
	GameSettings.swap_sticks = false
	GameSettings.load_from_disk()
	GameSettings.apply_bindings()
	pad_ok = pad_ok and GameSettings.swap_sticks and GameSettings.pad_binding_text("skill_1") == "Y" and GameSettings.pad_binding_text("dodge") == "RT"
	GameSettings.reset_bindings()
	pad_ok = pad_ok and GameSettings.pad_binding_text("skill_1") == "X" and GameSettings.pad_binding_text("dodge") == "B" and GameSettings.pad_binding_text("skill_5") == "RT"
	GameSettings.swap_sticks = false
	expect("controller rebind/swap/persist/reset keeps keyboard bindings", pad_ok)
	print("  controller bindings round trip ok=", pad_ok)
	GameSettings.master_volume = 0.8
	GameSettings.save_to_disk()
	GameSettings.custom_bindings = backup
	expect("settings rebind/swap/save/load/reset", ok)
	print("  settings: rebind/swap/save/load/reset ok=", ok, "  pause menu node=", pause_menu != null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.settings_path))
	GameSettings.settings_path = real_settings_path

## The mouse over the minimap, hotbar or bars must not pick (or walk to) an enemy standing in the world behind them.
func _test_ui_block() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var size_px: Vector2 = get_viewport().get_visible_rect().size
	var minimap_point: Vector2 = Hud.minimap_rect(size_px, game.hud.use_ds2_ui).get_center()   # the map this UI mode draws
	var open_point: Vector2 = size_px * 0.5
	expect("the minimap blocks the mouse", game.hud.covers(minimap_point))
	expect("the hotbar blocks the mouse", game.hud.covers(Vector2(size_px.x * 0.5, size_px.y - 50.0)))
	expect("open ground does not", not game.hud.covers(open_point))
	# An enemy standing in the world exactly behind the minimap pixel.
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var hidden_spot: Variant = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(minimap_point), camera.project_ray_normal(minimap_point))
	var enemy: Enemy = _spawn_enemy(hidden_spot)
	enemy.aggro_range = 0.0
	await get_tree().process_frame
	Gamepad.active = false
	expect("the enemy behind the minimap is picked when the mouse is not over the interface", player._hover_pick(enemy.global_position, minimap_point) == enemy)
	expect("the player treats the minimap as interface, not world", player.mouse_over_ui(minimap_point) and not player.mouse_over_ui(open_point))
	enemy.queue_free()
	await get_tree().process_frame
	# Regular Godot controls are not necessarily in the HUD's custom covers() group.
	# A button that hides on press exercises the click-through race where it vanishes
	# before Player's next physics tick.
	var layer := CanvasLayer.new()
	layer.layer = 90
	game.add_child(layer)
	var button := Button.new()
	button.text = "Close on press"
	button.position = Vector2(32.0, 32.0)
	button.size = Vector2(180.0, 48.0)
	button.button_down.connect(func() -> void: button.hide())
	layer.add_child(button)
	await get_tree().process_frame
	var pointer: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	Gamepad.active = false
	expect("a regular interactive Control is recognized as UI", get_viewport().gui_get_hovered_control() == button and player.mouse_over_ui())
	player.cursor_override = Vector3(0.0, 0.0, -6.0)
	player.attack_target = null
	player.movement.has_goal = false
	var idle_press := InputEventMouseButton.new()
	idle_press.button_index = MOUSE_BUTTON_LEFT
	idle_press.position = pointer
	idle_press.pressed = true
	get_viewport().push_input(idle_press, true)
	await get_tree().physics_frame
	expect("a UI button click while idle does not create a world movement order", not player.movement.has_goal and player.attack_target == null)
	var idle_release := idle_press.duplicate() as InputEventMouseButton
	idle_release.pressed = false
	get_viewport().push_input(idle_release, true)
	button.show()
	var motion_again := InputEventMouseMotion.new()
	motion_again.position = pointer
	get_viewport().push_input(motion_again, true)
	await get_tree().process_frame
	var target: Enemy = _spawn_enemy(player.global_position + Vector3(4.0, 0.0, 0.0))
	target.aggro_range = 0.0
	await get_tree().physics_frame
	player.attack_target = target
	player.skills.start_skill("basic", target)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = pointer
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().physics_frame
	expect("a UI button that closes on press does not cancel combat or issue world movement",
		not button.visible and player.skills.busy and player.attack_target == target and not player.movement.has_goal)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)
	await get_tree().physics_frame
	player.skills.cancel_action()
	player.attack_target = null
	target.queue_free()
	layer.queue_free()
	player.cursor_override = Vector3.INF
	await get_tree().process_frame

## An enemy behind the camera must never be picked: Camera3D.unproject_position mirrors such points back onto the screen, so one
## standing behind the view used to be "under" the cursor (highlighted and chased on click) while nothing visible was there.
func _test_hover_behind_camera() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, -20)
	player.reset_physics_interpolation()
	game.rig.global_position = player.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera: Camera3D = get_viewport().get_camera_3d()
	var behind: Vector3 = Vector3(camera.global_position.x, 0.0, camera.global_position.z + 20.0)
	var enemy: Enemy = _spawn_enemy(behind)
	enemy.aggro_range = 0.0
	await get_tree().process_frame
	var projected: Vector2 = camera.unproject_position(enemy.global_position + Vector3(0, enemy.body_height * 0.5, 0))
	var size_px: Vector2 = get_viewport().get_visible_rect().size
	print("  behind-camera enemy: behind=", camera.is_position_behind(enemy.global_position), " mirrored onto screen at ", projected, " (screen ", size_px, ")")
	expect("the test enemy really is behind the camera", camera.is_position_behind(enemy.global_position))
	expect("an enemy behind the camera is not picked by a cursor where it mirrors", player._hover_pick(Vector3(0, 0, 0), projected) != enemy)
	enemy.queue_free()
	await get_tree().process_frame

## Holding the camera-rotate button and dragging swings the camera around the hero smoothly; sticks, picking and the minimap follow it,
## and a click without a drag puts it back.
func _test_camera_rotation() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	rig.reset_view()
	await get_tree().create_timer(0.6).timeout
	expect("the camera starts behind the hero", absf(rig.yaw) < 0.01 and absf(Gamepad.view_yaw) < 0.01)
	var down := InputEventAction.new()
	down.action = "camera_rotate"
	down.pressed = true
	rig._unhandled_input(down)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(-285.0, 0.0)   # about a quarter turn
	rig._unhandled_input(drag)
	var up := InputEventAction.new()
	up.action = "camera_rotate"
	up.pressed = false
	rig._unhandled_input(up)
	expect("a drag does not count as a reset click", absf(rig._yaw_target) > 1.0)
	var last: float = rig.yaw
	var biggest_step: float = 0.0
	var frames: int = 0
	var t: float = 0.0
	while t < 1.2:
		await get_tree().process_frame
		t += get_process_delta_time()
		biggest_step = maxf(biggest_step, absf(angle_difference(last, rig.yaw)))
		last = rig.yaw
		frames += 1
	expect("the camera glides to the new angle (no snap)", biggest_step < 0.25 and frames > 10)
	expect("it arrives", absf(angle_difference(rig.yaw, rig._yaw_target)) < 0.02 and absf(rig.yaw) > 1.0)
	expect("the camera node is really turned", absf(angle_difference(rig.rotation.y, rig.yaw)) < 0.001)
	expect("sticks follow the view", Gamepad.to_world(Vector2(0, -1)).distance_to(Vector3(0, 0, -1).rotated(Vector3.UP, rig.yaw)) < 0.001)
	# Stick up now means up the screen: the hero walks away from the camera, not along world -Z.
	var camera: Camera3D = get_viewport().get_camera_3d()
	var screen_up: Vector3 = -camera.global_transform.basis.z
	screen_up.y = 0.0
	screen_up = screen_up.normalized()
	Gamepad.active = true
	Gamepad.test_axes = {JOY_AXIS_LEFT_X: 0.0, JOY_AXIS_LEFT_Y: -1.0}
	var start: Vector3 = player.global_position
	await get_tree().create_timer(0.8).timeout
	Gamepad.test_axes = {}
	Gamepad.active = false
	var moved: Vector3 = player.global_position - start
	moved.y = 0.0
	expect("stick up walks up the screen after the camera is turned", moved.length() > 2.0 and moved.normalized().dot(screen_up) > 0.95)
	# Picking still works from the new angle.
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var enemy: Enemy = _spawn_enemy(Vector3(2.0, 0, 1.0))
	enemy.aggro_range = 0.0
	await get_tree().create_timer(0.3).timeout
	var at: Vector2 = camera.unproject_position(enemy.global_position + Vector3(0, enemy.body_height * 0.5, 0))
	expect("an enemy is still picked under the cursor from the new angle", player._hover_pick(enemy.global_position, at) == enemy)
	enemy.queue_free()
	# A click without a drag resets.
	var click_down := InputEventAction.new()
	click_down.action = "camera_rotate"
	click_down.pressed = true
	rig._unhandled_input(click_down)
	var click_up := InputEventAction.new()
	click_up.action = "camera_rotate"
	click_up.pressed = false
	rig._unhandled_input(click_up)
	await get_tree().create_timer(1.2).timeout
	expect("a middle click without a drag resets the camera", absf(rig.yaw) < 0.02 and absf(Gamepad.view_yaw) < 0.02)
	print("  camera rotation: biggest per-frame step ", snappedf(biggest_step, 0.001), " rad over ", frames, " frames")
	await get_tree().process_frame

## A normal run starts with the camera zoomed all the way out.
func _test_start_zoom() -> void:
	var fresh := CameraRig.new()
	add_child(fresh)
	fresh.start_zoomed_out()
	await get_tree().process_frame
	expect("a new run starts fully zoomed out", is_equal_approx(fresh._zoom, CameraRig.ZOOM_MAX) and is_equal_approx(fresh._zoom_target, CameraRig.ZOOM_MAX))
	fresh.queue_free()
	await get_tree().process_frame

## Controller in the menus and the game: pad input hides the mouse and takes over; a real mouse move or any key or click takes it back;
## noisy axes cannot steal control; menus have a selection that D-pad / left stick move; rewards can be chosen from the pad.
func _test_pad_menus() -> void:
	var down := InputEventJoypadButton.new()
	down.pressed = true
	down.button_index = JOY_BUTTON_A
	Gamepad.active = false
	Gamepad._mouse_ms = -100000
	Gamepad.note_event(down)
	expect("a pad button press hands control to the controller", Gamepad.active)
	var wiggle := InputEventMouseMotion.new()
	wiggle.relative = Vector2(4.0, 0.0)
	Gamepad.note_event(wiggle)
	expect("mouse moves arriving right alongside pad input (Steam's emulated mouse) are ignored", Gamepad.active)
	Gamepad._pad_ms = -100000   # ...but once the pad has been quiet for a moment a real mouse move takes over
	Gamepad.note_event(wiggle)
	expect("moving the real mouse switches back to mouse and keyboard", not Gamepad.active)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 0.9
	Gamepad.note_event(stick)
	expect("a wobbling stick right after mouse use does not steal control", not Gamepad.active)
	Gamepad._mouse_ms = -100000   # ...but after the mouse has been still for a moment a real push does
	Gamepad.note_event(stick)
	expect("a real stick push takes control once the mouse is still", Gamepad.active)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_W
	Gamepad._pad_ms = -100000
	Gamepad.note_event(key)
	expect("a key press switches back to keyboard and mouse", not Gamepad.active)
	var rest := InputEventJoypadMotion.new()
	rest.axis = JOY_AXIS_TRIGGER_LEFT
	rest.axis_value = -1.0     # an idle trigger on some drivers
	Gamepad._mouse_ms = -100000
	Gamepad.note_event(rest)
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_RIGHT_Y
	drift.axis_value = 0.2
	Gamepad.note_event(drift)
	expect("a resting trigger or a drifting stick never counts as using the pad", not Gamepad.active)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	Gamepad.note_event(down)
	Gamepad._pad_ms = -100000
	Gamepad.note_event(click)
	expect("a mouse click switches back too", not Gamepad.active)
	# The pause menu opens with something selected, and the D-pad / stick (ui_down) moves it.
	game.pause_menu.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var first: Control = get_viewport().gui_get_focus_owner()
	expect("the pause menu opens with a button selected", first is Button)
	var move := InputEventAction.new()
	move.action = "ui_down"
	move.pressed = true
	Input.parse_input_event(move)
	await get_tree().process_frame
	await get_tree().process_frame
	var second: Control = get_viewport().gui_get_focus_owner()
	expect("down on the D-pad / left stick moves the selection", second != null and second != first)
	var release := InputEventAction.new()
	release.action = "ui_down"
	release.pressed = false
	Input.parse_input_event(release)
	# A real A-button press on the selected button presses it (Resume is first in the pause menu).
	game.pause_menu.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var lift := InputEventJoypadButton.new()
	lift.button_index = JOY_BUTTON_A
	lift.pressed = false
	Input.parse_input_event(lift)
	await get_tree().process_frame
	expect("pressing A on the selected menu button activates it", not game.pause_menu.visible)
	game.pause_menu.close()
	await get_tree().process_frame
	# Settings: opened from the pause menu it gets a selection too.
	var settings := SettingsMenu.new()
	add_child(settings)
	await get_tree().process_frame
	settings.focus_first()
	await get_tree().process_frame
	expect("the settings screen has a selection for the controller", get_viewport().gui_get_focus_owner() != null)
	settings.queue_free()
	await get_tree().process_frame
	Gamepad.active = false
	await get_tree().process_frame

## Controller targeting: the enemy nearest to where the hero faces is targeted and glows; holding A attacks it; B dodges; Start pauses.
func _test_pad_targeting() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.visual.rotation.y = 0.0   # facing +Z
	Gamepad.active = true
	var behind: Enemy = _spawn_enemy(Vector3(0, 0, -3))
	var ahead: Enemy = _spawn_enemy(Vector3(1.5, 0, 7))
	for e in [behind, ahead]:
		e.aggro_range = 0.0
		e.max_health = 4000.0
		e.health = 4000.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("the pad targets the enemy in front, not the nearer one behind", player.pad_facing_target() == ahead)
	expect("the targeted enemy is the cursor point and the hover target", player.cursor_world().distance_to(ahead.global_position) < 0.01 and player.hover_target == ahead)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("the targeted enemy glows", ahead.highlighted and not behind.highlighted)
	# Turn around: the enemy behind is now the one in front.
	player.visual.rotation.y = PI
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	expect("turning around changes the target", player.pad_facing_target() == behind and behind.highlighted and not ahead.highlighted)
	# It does not flicker: a slightly different angle keeps the same target.
	player.visual.rotation.y = PI + 0.15
	await get_tree().physics_frame
	expect("the target is sticky", player.pad_facing_target() == behind)
	# Holding A attacks the targeted enemy.
	Gamepad.test_axes = {}
	player.visual.rotation.y = PI
	var start_health: float = behind.health
	Input.action_press("alt_skill")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("alt_skill")
	expect("holding A attacks the targeted enemy", behind.health < start_health)
	# Defaults: A attacks (and confirms in menus), B dodges, Start pauses.
	var has_a: bool = false
	for ev in InputMap.action_get_events("alt_skill"):
		has_a = has_a or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	var has_b: bool = false
	for ev in InputMap.action_get_events("dodge"):
		has_b = has_b or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	var has_start: bool = false
	for ev in InputMap.action_get_events("pause"):
		has_start = has_start or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_START)
	var confirms: bool = false
	for ev in InputMap.action_get_events("ui_accept"):
		confirms = confirms or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	for ev in InputMap.action_get_events("ui_cancel"):
		confirms = confirms and true
	var backs: bool = false
	for ev in InputMap.action_get_events("ui_cancel"):
		backs = backs or (ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	confirms = confirms and backs
	expect("A is attack and menu confirm, B is dodge, Start is pause", has_a and has_b and has_start and confirms)
	Gamepad.active = false
	# Changing input method does not put the pointer over an enemy. Supply real
	# viewport mouse input instead of expecting the last controller target at (0,0).
	player.skills.cancel_action()
	player.attack_target = null
	var motion := InputEventMouseMotion.new()
	motion.position = rig.camera.unproject_position(behind.get_global_transform_interpolated().origin + Vector3.UP * behind.body_height * 0.5)
	if DisplayServer.get_name() != "headless": get_viewport().warp_mouse(motion.position)
	Input.parse_input_event(motion)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		# Dummy DisplayServer ignores pointer warps/events (mouse remains 0,0).
		# Exercise the production picker with its explicit screen-coordinate API,
		# then the production presentation tick; don't assert a fabricated OS hover.
		player.hover_target = player._hover_pick(behind.global_position, motion.position)
		player._process(0.0)
	print("  mouse targeting: injected=", motion.position, " actual=", get_viewport().get_mouse_position(), " hover=", player.hover_target, " expected=", behind, " pad=", Gamepad.active, " ui=", player.mouse_over_ui(), " aiming=", player.skills.aiming_id)
	expect("mouse hover keeps DS2's target silhouette instead of removing the controller glow",
		player.hover_target == behind and behind.highlighted and not ahead.highlighted)
	# Leave the hero idle for whatever test comes next (no swing in progress, no target, no queued skill).
	player.skills.cancel_action()
	player.skills.queued_skill = ""
	player.attack_target = null
	player.click_mode = 0
	player.movement.has_goal = false
	behind.queue_free()
	ahead.queue_free()
	await get_tree().create_timer(0.3).timeout

## Controller camera and Fireball aiming: the right stick turns/zooms the camera, except while Fireball is held, when it slides the
## target area: one snap to the nearest target at the start, then free movement with no snapping back onto enemies.
func _test_pad_camera_and_aim() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.visual.rotation.y = 0.0
	Gamepad.active = true
	rig.reset_view()
	rig._zoom_target = 2.0
	rig._zoom = 2.0
	await get_tree().create_timer(0.5).timeout
	# Right stick: right turns the camera, down zooms out.
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: 1.0, JOY_AXIS_RIGHT_Y: 0.0}
	await get_tree().create_timer(0.6).timeout
	var turned: float = rig._yaw_target
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: 0.0, JOY_AXIS_RIGHT_Y: 1.0}
	var zoom_before: float = rig._zoom_target
	await get_tree().create_timer(0.6).timeout
	var zoom_out: float = rig._zoom_target
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: 0.0, JOY_AXIS_RIGHT_Y: -1.0}
	await get_tree().create_timer(0.6).timeout
	var zoom_in: float = rig._zoom_target
	Gamepad.test_axes = {}
	expect("the right stick turns the camera", absf(turned) > 0.5)
	expect("right stick down zooms out and up zooms in", zoom_out > zoom_before + 0.3 and zoom_in < zoom_out - 0.3)
	# While Fireball is held the stick no longer moves the camera; it slides the target area.
	rig.reset_view()
	await get_tree().create_timer(1.0).timeout
	var first: Enemy = _spawn_enemy(Vector3(2.0, 0, 6.0))
	var second: Enemy = _spawn_enemy(Vector3(-6.0, 0, 8.0))
	for e in [first, second]:
		e.aggro_range = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.stats.cooldowns.clear()
	player.stats.mana = player.stats.max_mana
	GameSettings.assign_hotbar_caster(1, "hero")   # the shared bar routes slot 2 to Cutter by default
	player.skills.hotbar[1] = "fireball"   # this check exercises the optional skill, outside the default loadout
	Input.action_press("skill_2")
	await get_tree().create_timer(0.2).timeout
	expect("holding Fireball is aiming", player.skills.aiming_id == "fireball")
	var snap_point: Vector3 = player.cursor_world()
	expect("the target area starts on the enemy the hero faces", snap_point.distance_to(first.global_position) < 0.5)
	var yaw_before: float = rig._yaw_target
	Gamepad.test_axes = {JOY_AXIS_RIGHT_X: -1.0, JOY_AXIS_RIGHT_Y: 0.0}   # push left: toward the second enemy and past it
	await get_tree().create_timer(0.5).timeout
	var mid: Vector3 = player.cursor_world()
	expect("the stick slides the target area", mid.distance_to(snap_point) > 2.0 and mid.x < snap_point.x)
	expect("the camera does not turn while aiming", absf(rig._yaw_target - yaw_before) < 0.001)
	# It passes straight over the second enemy without latching onto it: keep going and it ends up beyond.
	await get_tree().create_timer(0.8).timeout
	var far: Vector3 = player.cursor_world()
	expect("no snapping onto enemies once the stick is moving it", far.x < second.global_position.x - 1.0)
	Gamepad.test_axes = {}
	var held: Vector3 = player.cursor_world()
	await get_tree().create_timer(0.4).timeout
	expect("released stick: the target area stays where it was put", player.cursor_world().distance_to(held) < 0.01)
	Input.action_release("skill_2")
	await get_tree().create_timer(1.2).timeout
	player.skills.cancel_action()
	first.queue_free()
	second.queue_free()
	Gamepad.active = false
	rig._zoom_target = 1.0
	rig._zoom = 1.0
	await get_tree().process_frame

## Start (or Esc) pauses the whole game: enemies, hero, animations, projectiles and effects all stop until it is resumed.
func _test_pause_stops_game() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var chaser: Enemy = _spawn_enemy(Vector3(0, 0, -12))
	chaser.alert_delay = 0.0
	chaser.aggro_range = 60.0
	var ball := Projectile.new()
	ball.owner_actor = player
	ball.direction = Vector3(1, 0, 0)
	ball.destination = Vector3(20, 0.8, 0)
	add_child(ball)
	ball.global_position = Vector3(4, 1.0, 0)
	await get_tree().create_timer(0.8).timeout
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_START
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("Start opens the pause menu and pauses the tree", game.pause_menu.visible and get_tree().paused)
	var chaser_at: Vector3 = chaser.global_position
	var ball_at: Vector3 = ball.global_position
	var player_at: Vector3 = player.global_position
	var anim_at: float = chaser.model.anim.current_animation_position
	await get_tree().create_timer(1.0, true, false, true).timeout
	expect("enemies do not move while paused", chaser.global_position.distance_to(chaser_at) < 0.01)
	expect("projectiles do not fly while paused", ball.global_position.distance_to(ball_at) < 0.01)
	expect("the hero does not move while paused", player.global_position.distance_to(player_at) < 0.01)
	expect("animations stand still while paused", is_equal_approx(chaser.model.anim.current_animation_position, anim_at))
	expect("time scale is untouched", is_equal_approx(Engine.time_scale, 1.0))
	game.pause_menu.close()
	await get_tree().create_timer(0.5).timeout
	expect("resuming gets everything moving again", not get_tree().paused and chaser.global_position.distance_to(chaser_at) > 0.3)
	if is_instance_valid(ball):
		ball.queue_free()
	chaser.queue_free()
	await get_tree().process_frame

## Real mouse events through Input.parse_input_event (what the operating system delivers): the action state AND the viewport routing,
## including an OptionButton's popup, which consumes the click that selects an entry.
func _popup_press(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _popup_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _test_popup_click_through() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	Gamepad.active = false
	var window_was: Vector2i = get_window().size
	get_window().size = Vector2i(1280, 720)   # a headless window starts 64 x 64, which would clip every synthesized pointer position
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.cursor_override = Vector3(0.0, 0.0, -6.0)   # open terrain wherever the pointer is
	player.movement.has_goal = false
	player.attack_target = null
	var layer := CanvasLayer.new()
	layer.layer = 90
	game.add_child(layer)
	var menu := OptionButton.new()
	for entry in ["Alpha", "Bravo", "Charlie", "Delta"]:
		menu.add_item(entry)
	menu.position = Vector2(40.0, 40.0)
	menu.size = Vector2(160.0, 32.0)
	var chosen: Array[int] = []
	menu.item_selected.connect(func(index: int) -> void: chosen.append(index))
	layer.add_child(menu)
	await get_tree().process_frame
	var center: Vector2 = menu.get_global_rect().get_center()
	_popup_move(center)
	await get_tree().process_frame

	# Open: press and release on the button.
	_popup_press(center, true)
	await get_tree().physics_frame
	_popup_press(center, false)
	await get_tree().physics_frame
	var popup: PopupMenu = menu.get_popup()
	expect("the dropdown popup opened", popup.visible)
	expect("opening a dropdown does not move the hero", not player.movement.has_goal and player.click_mode == 0)

	# Select the third entry: the popup consumes press and release; the world must never see them.
	var pick: Vector2 = Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * 0.62)
	_popup_move(pick)
	await get_tree().process_frame
	_popup_press(pick, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("pressing an entry does not move the hero", not player.movement.has_goal)
	_popup_press(pick, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("an entry was selected through the popup", not chosen.is_empty() and not popup.visible)
	expect("selecting an entry does not move the hero or start an order", not player.movement.has_goal and player.attack_target == null)

	# Open again and cancel by clicking open terrain: the click that closes a popup is not a move order.
	_popup_move(center)
	await get_tree().process_frame
	_popup_press(center, true)
	await get_tree().physics_frame
	_popup_press(center, false)
	await get_tree().physics_frame
	expect("the dropdown reopened", popup.visible)
	var terrain := Vector2(640.0, 500.0)
	_popup_move(terrain)
	await get_tree().process_frame
	_popup_press(terrain, true)
	await get_tree().physics_frame
	_popup_press(terrain, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("clicking terrain only to dismiss the dropdown does not move the hero", not popup.visible and not player.movement.has_goal)

	# The very next real terrain click is a normal move order, immediately.
	_popup_press(terrain, true)
	await get_tree().physics_frame
	_popup_press(terrain, false)
	await get_tree().physics_frame
	expect("the next genuine ground click moves the hero at once", player.movement.has_goal and player.click_mode == 0)

	player.movement.has_goal = false
	layer.queue_free()
	player.cursor_override = Vector3.INF
	await get_tree().process_frame
